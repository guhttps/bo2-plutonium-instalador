[CmdletBinding()]
param([switch]$Staged, [switch]$History, [string]$PackagePath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-PrivacyGitBlob {
    param([string]$ObjectId)
    if ($ObjectId -notmatch '^[a-f0-9]{40,64}$') { throw 'Objeto Git invalido.' }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = 'git'
    $process.StartInfo.WorkingDirectory = (Get-Location).ProviderPath
    $process.StartInfo.Arguments = 'cat-file blob '+$ObjectId
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $memory = [IO.MemoryStream]::new()
    try {
        [void]$process.Start()
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw 'Nao foi possivel examinar um objeto Git.' }
        return ,$memory.ToArray()
    } finally { $memory.Dispose(); $process.Dispose() }
}

function Get-PrivacyContentIssues {
    param([string]$Content)
    $issues = @()
    foreach ($match in [regex]::Matches($Content, '(?<![\w.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![\w.])')) {
        $address = $null
        if (-not [Net.IPAddress]::TryParse($match.Value, [ref]$address)) { continue }
        $octets = $address.GetAddressBytes()
        $safe = $match.Value -eq '0.0.0.0' -or $octets[0] -eq 127 -or
            ($octets[0] -eq 192 -and $octets[1] -eq 0 -and $octets[2] -eq 2) -or
            ($octets[0] -eq 198 -and $octets[1] -eq 51 -and $octets[2] -eq 100) -or
            ($octets[0] -eq 203 -and $octets[1] -eq 0 -and $octets[2] -eq 113)
        if (-not $safe) { $issues += 'IPv4 fora dos exemplos e testes locais permitidos'; break }
    }
    foreach ($match in [regex]::Matches($Content, '(?i)(?<![\w:])[a-f0-9:]*:[a-f0-9:]+(?:%[0-9]+)?(?![\w:])')) {
        $address = $null
        if ([Net.IPAddress]::TryParse($match.Value, [ref]$address) -and $address.AddressFamily -eq 'InterNetworkV6') {
            $value = $address.ToString()
            if ($value -notin @('::','::1') -and -not $value.StartsWith('2001:db8:')) {
                $issues += 'IPv6 fora dos exemplos e testes locais permitidos'; break
            }
        }
    }
    if ($Content -match '(?i)\b[A-Z]:[\\/]+Users[\\/]+(?!Public(?:[\\/]|\b)|Default(?:[\\/]|\b))[^\\/\s"''<>]+' -or
        $Content -match '(?<![\w:])/(?:home|Users)/[^/\s"''<>]+') { $issues += 'Caminho de perfil pessoal' }
    foreach ($match in [regex]::Matches($Content, '(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}')) {
        if ($match.Value -notmatch '(?i)@users\.noreply\.github\.com$|@(?:[a-z0-9-]+\.)?example\.(?:com|org|net|invalid)$|\.invalid$') {
            $issues += 'Email pessoal'; break
        }
    }
    if ($Content -match 'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----' -or
        $Content -match '(?im)^\s*\$?(?:password|passwd|api[_-]?key|secret|token)\s*[:=]\s*["''][^"''\r\n]{8,}["'']' -or
        $Content -match '(?i)["''](?:password|passwd|api[_-]?key|secret|token)["'']\s*:\s*["''][^"''\r\n]{8,}["'']') {
        $issues += 'Possivel credencial ou chave privada'
    }
    return $issues | Select-Object -Unique
}

function Get-PrivacyFileIssues {
    param([string]$RelativePath, [byte[]]$Bytes)
    $path = $RelativePath.Replace('\','/')
    $issues = @(Get-PrivacyContentIssues $path)
    if ($path -match '(?i)(^|/)(?:\.env(?:\..*)?|config\.json|[^/]*\.(?:log|key|pem|pfx|p12|pcap|pcapng|dmp|etl)|id_rsa[^/]*|id_ed25519[^/]*)$|(^|/)(?:\.cache[^/]*|sessoes|\.verificacao[^/]*)(?:/|$)') {
        $issues += 'Arquivo local ou de credenciais'
    }
    # Binarios somente com hash revisado. Novas capturas precisam de revisao visual.
    $approved = @{
        'docs/interface.png' = 'EA1555BE5C4D21E5B2735D5836E50575CA4F6359252D0304A2747369101A8FC8'
        'BO2-Plutonium/pluto_t6_full_game.torrent' = '96A4BEECEF0CC0BA8CDD0D59F54ECC7721E837A44A9ECD78AE5834D18D2A2D89'
    }
    if ($approved.ContainsKey($path)) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
        if ($hash -ne $approved[$path]) { $issues += 'Binario alterado sem revisao de privacidade' }
    } elseif ([IO.Path]::GetExtension($path) -notin @('.md','.txt','.ps1','.cmd','.cs','.json','.yml','.yaml','.sh') -and
        $path -notin @('.gitignore','.gitattributes','.githooks/pre-commit','.githooks/pre-push','LICENSE','NOTICE')) {
        $issues += 'Tipo de arquivo sem revisao de privacidade'
    } else {
        $issues += @(Get-PrivacyContentIssues ([Text.Encoding]::UTF8.GetString($Bytes)))
    }
    return $issues | Select-Object -Unique
}

if ($MyInvocation.InvocationName -eq '.') { return }
try {
if (@($Staged,$History,[bool]$PackagePath | Where-Object { $_ }).Count -gt 1) { throw 'Escolha apenas um modo de verificacao.' }
$entries = @()
if ($PackagePath) {
    foreach ($file in (Get-ChildItem -LiteralPath $PackagePath -File -Force)) {
        $entries += [pscustomobject]@{Path=('BO2-Plutonium/'+$file.Name);File=$file.FullName;ObjectId='';Mode='100644'}
    }
} elseif ($Staged) {
    $lines = @(git -c core.quotepath=false ls-files --stage)
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao ler os arquivos preparados para commit.' }
    foreach ($line in $lines) {
        if ($line -notmatch '^(\d+) ([a-f0-9]{40,64}) 0\t(.+)$') { throw 'Indice Git com conflito ou nome de arquivo nao suportado.' }
        $entries += [pscustomobject]@{Path=$Matches[3];ObjectId=$Matches[2];Mode=$Matches[1];File=''}
    }
} elseif ($History) {
    $commits = @(git rev-list --all)
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar o historico Git.' }
    $seen = @{}
    foreach ($commit in $commits) {
        $lines = @(git -c core.quotepath=false ls-tree -r $commit)
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar uma arvore Git.' }
        foreach ($line in $lines) {
            if ($line -notmatch '^(\d+) blob ([a-f0-9]{40,64})\t(.+)$') { throw 'Historico com entrada nao suportada para revisao.' }
            $key = $Matches[2]+'|'+$Matches[3]
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $entries += [pscustomobject]@{Path=$Matches[3];ObjectId=$Matches[2];Mode=$Matches[1];File=''}
        }
    }
    $metadata = @(git log --all --format='%B%n%ae%n%ce') -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar metadados de commits.' }
    if (@(Get-PrivacyContentIssues $metadata).Count -gt 0) { throw 'Possivel dado pessoal em mensagens ou metadados de commits. Valores omitidos.' }
} else {
    $paths = @(git -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar os arquivos publicaveis.' }
    foreach ($path in $paths) { $entries += [pscustomobject]@{Path=$path;File=(Join-Path $PSScriptRoot $path);ObjectId='';Mode='100644'} }
}
$blocked = 0
foreach ($entry in $entries) {
    if ($entry.Mode -eq '120000' -or ($entry.File -and (Get-Item -LiteralPath $entry.File -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Link de sistema de arquivos nao permitido na publicacao.'
    }
    $bytes = if ($entry.ObjectId) { Read-PrivacyGitBlob $entry.ObjectId } else { [IO.File]::ReadAllBytes($entry.File) }
    $issues = @(Get-PrivacyFileIssues -RelativePath $entry.Path -Bytes $bytes)
    if ($issues.Count -gt 0) {
        $blocked++
        $label = if (@(Get-PrivacyContentIssues $entry.Path).Count -eq 0) { $entry.Path } else { '[nome omitido]' }
        Write-Host ('BLOQUEADO: '+$label+' | '+($issues -join '; '))
    }
}
if ($blocked -gt 0) { throw 'Verificacao de privacidade reprovada. Os valores detectados foram omitidos.' }
Write-Host ('OK: privacidade de '+$entries.Count+' arquivos/versoes; nenhum padrao proibido encontrado.')
exit 0
} catch {
    [Console]::Error.WriteLine('Verificacao de privacidade reprovada ou interrompida. Valores e caminhos locais foram omitidos; consulte as categorias acima.')
    exit 1
}
