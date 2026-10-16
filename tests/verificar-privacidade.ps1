Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$checker = Join-Path $repoRoot 'verificar-privacidade.ps1'
. $checker

$sampleIp = '26.'+(@('11','22','33') -join '.')
$samples = @(
    $sampleIp,
    ('C:'+'/Users/'+'PessoaExemplo'+'/arquivo.txt'),
    ('/home/'+'pessoa-exemplo'+'/arquivo.txt'),
    ('pessoa-exemplo'+'@'+'mail.test'),
    ('gh'+'p_'+('A'*36)),
    ('-----BEGIN '+'PRIVATE KEY-----'),
    ('pass'+'word = "'+('segredo-simulado')+'"'),
    ('{"pass'+'word":"'+('segredo-simulado')+'"}'),
    ('2001'+':4860::8888')
)
foreach ($sample in $samples) {
    if (@(Get-PrivacyContentIssues $sample).Count -eq 0) { throw 'Um padrao sensivel simulado nao foi bloqueado. Valor omitido.' }
}
foreach ($safe in @('127.0.0.1','0.0.0.0','192.0.2.10','198.51.100.20','203.0.113.30','::1','2001:db8::1','robot@users.noreply.github.com','teste@example.invalid')) {
    if (@(Get-PrivacyContentIssues $safe).Count -gt 0) { throw 'Um exemplo permitido foi bloqueado.' }
}
$rpcSource = [IO.File]::ReadAllText((Join-Path $repoRoot 'BO2-Plutonium\Progresso.ps1'))
if (@(Get-PrivacyContentIssues $rpcSource).Count -gt 0) { throw 'O codigo que gera uma credencial temporaria foi confundido com uma credencial publicada.' }
$fakeBytes = [Text.Encoding]::UTF8.GetBytes('fixture')
foreach ($name in @('.env','config.json','captura.png','dados.pcap','chave.pem')) {
    if (@(Get-PrivacyFileIssues -RelativePath $name -Bytes $fakeBytes).Count -eq 0) { throw 'Arquivo local ou binario novo nao foi bloqueado.' }
}
if (@(Get-PrivacyFileIssues -RelativePath 'docs/interface.png' -Bytes $fakeBytes).Count -eq 0) { throw 'Uma imagem alterada passou sem revisao.' }
$image = [IO.File]::ReadAllBytes((Join-Path $repoRoot 'docs\interface.png'))
if (@(Get-PrivacyFileIssues -RelativePath 'docs/interface.png' -Bytes $image).Count -gt 0) { throw 'A imagem revisada foi rejeitada.' }
Write-Host 'OK: dados simulados bloqueados, exemplos permitidos, credenciais geradas e imagens com hash revisado.'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('bo2-privacidade-'+[guid]::NewGuid().ToString('N'))
$resolvedFixture = [IO.Path]::GetFullPath($fixture)
if (-not $resolvedFixture.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $resolvedFixture) -notmatch '^bo2-privacidade-[a-f0-9]{32}$') { throw 'Pasta de teste invalida.' }
New-Item -ItemType Directory -Path $fixture | Out-Null
function Invoke-PrivacyFixture {
    param([string]$Mode)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = (Get-Process -Id $PID).Path
    $process.StartInfo.WorkingDirectory = $fixture
    $process.StartInfo.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$checker+'" '+$Mode
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        [void]$process.Start()
        if (-not $process.WaitForExit(15000)) { $process.Kill(); $process.WaitForExit(); throw 'Tempo limite no teste de privacidade.' }
        $output = $process.StandardOutput.ReadToEnd()+$process.StandardError.ReadToEnd()
        if ($output.Contains($sampleIp)) { throw 'O relatorio revelou o valor que deveria ocultar.' }
        if ($output -match '(?i)[A-Z]:[\\/]+Users[\\/]') { throw 'O relatorio revelou um caminho de perfil local.' }
        return $process.ExitCode
    } finally { $process.Dispose() }
}
try {
    git -C $fixture -c init.defaultBranch=main init --quiet
    git -C $fixture config user.name 'Fixture'
    git -C $fixture config user.email 'fixture@example.invalid'
    git -C $fixture config core.hooksPath '.hooks-disabled'
    $data = Join-Path $fixture 'dados.txt'
    [IO.File]::WriteAllText($data,$sampleIp)
    git -C $fixture add dados.txt
    [IO.File]::WriteAllText($data,'documento sem dados pessoais')
    if ((Invoke-PrivacyFixture '-Staged') -eq 0) { throw 'O indice sensivel passou porque a copia de trabalho estava limpa.' }
    git -C $fixture commit --quiet -m 'Fixture de historico'
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar historico simulado.' }
    git -C $fixture add dados.txt
    git -C $fixture commit --quiet -m 'Fixture atual limpa'
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar historico atual.' }
    if ((Invoke-PrivacyFixture '-Staged') -ne 0) { throw 'O indice atual limpo foi rejeitado.' }
    if ((Invoke-PrivacyFixture '-History') -eq 0) { throw 'Um dado removido da versao atual continuou no historico sem ser detectado.' }
    Write-Host 'OK: indice real, dados antigos no historico e relatorios sem revelar os valores detectados.'
} finally {
    # A pasta foi criada e validada acima; limpa somente seus arquivos, sem exclusao recursiva.
    Get-ChildItem -LiteralPath $resolvedFixture -Recurse -File -Force | ForEach-Object {
        [IO.File]::SetAttributes($_.FullName,[IO.FileAttributes]::Normal)
        [IO.File]::Delete($_.FullName)
    }
    Get-ChildItem -LiteralPath $resolvedFixture -Recurse -Directory -Force | Sort-Object {$_.FullName.Length} -Descending | ForEach-Object {[IO.Directory]::Delete($_.FullName)}
    [IO.Directory]::Delete($resolvedFixture)
}
