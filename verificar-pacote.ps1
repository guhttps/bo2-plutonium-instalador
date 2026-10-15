param([string]$PackagePath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $PackagePath) { $PackagePath = Join-Path $PSScriptRoot 'BO2-Plutonium' }
foreach ($script in (Get-ChildItem -LiteralPath $packagePath -Filter '*.ps1')) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
}
. (Join-Path $packagePath 'Funcoes.ps1')
Add-Type -Path (Join-Path $packagePath 'TorrentVerifier.cs')
$original = [Bo2Torrent]::Load((Join-Path $packagePath 'pluto_t6_full_game.torrent'))
if ($original.InfoHash -ne '228d582decc9415565f1413cd1b755cad3d8a490' -or
    $original.Files.Count -ne 525 -or $original.TotalLength -ne 14540713332) { throw 'Torrent original incorreto.' }
Write-Host 'OK: sintaxe dos scripts, infohash e manifesto original de 525 arquivos.'

$testPath = Join-Path $PSScriptRoot ('.verificacao-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testPath | Out-Null
$fixturePath = Join-Path $testPath 'fixture'
New-Item -ItemType Directory -Path $fixturePath | Out-Null
try {
    $prefix = 'd4:infod5:filesld6:lengthi3e4:pathl5:a.txteed6:lengthi7e4:pathl5:b.txteee4:name7:fixture12:piece lengthi4e6:pieces60:'
    $stream = New-Object IO.MemoryStream
    $prefixBytes = [Text.Encoding]::ASCII.GetBytes($prefix)
    $stream.Write($prefixBytes, 0, $prefixBytes.Length)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    foreach ($piece in @('abcd', 'efgh', 'ij')) {
        $hash = $sha1.ComputeHash([Text.Encoding]::ASCII.GetBytes($piece))
        $stream.Write($hash, 0, $hash.Length)
    }
    $sha1.Dispose()
    $stream.WriteByte([byte][char]'e'); $stream.WriteByte([byte][char]'e')
    $fixtureTorrent = Join-Path $testPath 'fixture.torrent'
    [IO.File]::WriteAllBytes($fixtureTorrent, $stream.ToArray())
    $stream.Dispose()
    [IO.File]::WriteAllText((Join-Path $fixturePath 'a.txt'), 'abc')
    [IO.File]::WriteAllText((Join-Path $fixturePath 'b.txt'), 'defghij')
    $fixture = [Bo2Torrent]::Load($fixtureTorrent)
    $fixture.Verify($testPath, $null)
    [IO.File]::WriteAllText((Join-Path $fixturePath 'b.txt'), 'xefghij')
    $rejected = $false
    try { $fixture.Verify($testPath, $null) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Corrupcao entre arquivos nao foi detectada.' }
    [IO.File]::WriteAllText((Join-Path $fixturePath 'b.txt'), 'x')
    $rejected = $false
    try { $fixture.Verify($testPath, $null) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Arquivo incompleto nao foi detectado.' }
    $raw = [IO.File]::ReadAllBytes($fixtureTorrent)
    $unsafePrefix = [Text.Encoding]::ASCII.GetBytes($prefix.Replace('5:b.txt', '2:..'))
    $unsafe = New-Object byte[] ($unsafePrefix.Length + 62)
    [Array]::Copy($unsafePrefix, 0, $unsafe, 0, $unsafePrefix.Length)
    [Array]::Copy($raw, $prefixBytes.Length, $unsafe, $unsafePrefix.Length, 62)
    $unsafeTorrent = Join-Path $testPath 'unsafe.torrent'
    [IO.File]::WriteAllBytes($unsafeTorrent, $unsafe)
    $rejected = $false
    try { [void][Bo2Torrent]::Load($unsafeTorrent) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Caminho com .. nao foi rejeitado.' }
    Write-Host 'OK: blocos cruzando arquivos, ultimo bloco parcial, corrupcao, truncamento e caminhos inseguros.'

    $configPath = Join-Path $testPath 'config.json'
    [IO.File]::WriteAllText($configPath, '{"t6Path":"antigo","t5Path":"manter","nested":{"number":7}}')
    Set-GamePath -ConfigPath $configPath -GamePath 'D:\Jogos com espaco\BO2'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($config.t6Path -ne 'D:\Jogos com espaco\BO2' -or $config.t5Path -ne 'manter' -or $config.nested.number -ne 7) { throw 'Configuracao nao preservada.' }
    if (@(Get-ChildItem -LiteralPath $testPath -Filter 'config.json.backup-*').Count -ne 1) { throw 'Backup da configuracao ausente.' }
    $before = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($configPath, 'JSON quebrado')
    $invalidBefore = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    $rejected = $false
    try { Set-GamePath -ConfigPath $configPath -GamePath 'D:\BO2' } catch { $rejected = $true }
    if (-not $rejected -or (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne $invalidBefore) { throw 'Configuracao invalida nao preservada.' }
    Write-Host 'OK: caminhos com espacos, preservacao das outras configuracoes, backup e JSON invalido.'

    if (-not (Test-Executable -Path (Join-Path $PSHOME 'powershell.exe'))) { throw 'Executavel valido rejeitado.' }
    $invalidPath = Join-Path $testPath 'html.exe'
    [IO.File]::WriteAllText($invalidPath, '<html>Erro</html>')
    if (Test-Executable -Path $invalidPath) { throw 'HTML aceito como executavel.' }
    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
        [IO.File]::WriteAllText($OutFile, '<html>Falha simulada</html>')
    }
    $destination = Join-Path $testPath 'download.exe'
    [IO.File]::WriteAllText($destination, 'arquivo anterior')
    $previousHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    $rejected = $false
    try { Get-OfficialLauncher -Destination $destination } catch { $rejected = $true }
    if (-not $rejected -or (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $previousHash) { throw 'Download invalido sobrescreveu arquivo anterior.' }
    $rejected = $false
    try { Get-WebFile -Url 'https://exemplo.invalid' -Destination $destination -Sha256 ('0' * 64) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Download com hash incorreto aceito.' }
    if (@(Get-ChildItem -LiteralPath $testPath -Filter '*.download').Count -gt 0) { throw 'Download temporario nao removido.' }
    Write-Host 'OK: executavel valido, resposta HTML, hash incorreto e preservacao apos falha.'
} finally {
    # Limpa somente arquivos e pastas desta verificacao, sem exclusao recursiva.
    Get-ChildItem -LiteralPath $fixturePath -File | Remove-Item -Force
    Remove-Item -LiteralPath $fixturePath
    Get-ChildItem -LiteralPath $testPath -File | Remove-Item -Force
    Remove-Item -LiteralPath $testPath
}
