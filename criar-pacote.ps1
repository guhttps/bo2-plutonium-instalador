[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $SourcePath) { $SourcePath = Join-Path $PSScriptRoot 'BO2-Plutonium' }
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'dist' }
$SourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($OutputPath.TrimEnd('\') -eq $SourcePath.TrimEnd('\') -or
    $OutputPath.StartsWith($SourcePath.TrimEnd('\')+'\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'A pasta de saida deve ficar fora da pasta do instalador.'
}

# Lista explicita: dados instalados, registros e contas nunca entram no ZIP.
$required = @(
    'ALTERNATIVA-TORRENT.cmd', 'arquivos-http.json', 'componentes.ps1', 'FONTES.txt',
    'Funcoes.ps1', 'INSTALAR.cmd', 'instalar.ps1', 'Interface.ps1', 'LEIA-ME.txt',
    'pluto_t6_full_game.torrent', 'Progresso.ps1', 'TorrentVerifier.cs', 'VALIDACAO.txt'
) | Sort-Object
$actual = @(Get-ChildItem -LiteralPath $SourcePath -Force | ForEach-Object {
    if ($_.PSIsContainer) { throw ('Pasta inesperada no pacote: '+$_.Name) }
    $_.Name
}) | Sort-Object
if (@(Compare-Object $required $actual).Count -ne 0) { throw 'Arquivos ausentes ou inesperados na pasta do instalador.' }
$pins = @{
    'arquivos-http.json' = 'E7A96F8DC7D7F04B4E19E684001FDD6290CF9F8FE6921788361D82BBA89CCBCF'
    'pluto_t6_full_game.torrent' = '96A4BEECEF0CC0BA8CDD0D59F54ECC7721E837A44A9ECD78AE5834D18D2A2D89'
}
foreach ($name in $pins.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $SourcePath $name) -Algorithm SHA256).Hash -ne $pins[$name]) {
        throw ('Metadados originais alterados: '+$name)
    }
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$verificationPath = Join-Path $OutputPath ('.verificacao-zip-'+[guid]::NewGuid().ToString('N'))
$candidate = Join-Path $OutputPath ([guid]::NewGuid().ToString('N')+'.tmp')
$zipPath = Join-Path $OutputPath 'BO2-Plutonium.zip'
$checksumPath = $zipPath+'.sha256'
try {
    $archive = [IO.Compression.ZipFile]::Open($candidate, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $required) {
            $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
            # Mesmos arquivos produzem o mesmo ZIP, independentemente do checkout.
            $entry.LastWriteTime = [DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
            $inputFile = [IO.File]::OpenRead((Join-Path $SourcePath $name))
            try {
                $outputEntry = $entry.Open()
                try { $inputFile.CopyTo($outputEntry) } finally { $outputEntry.Dispose() }
            } finally { $inputFile.Dispose() }
        }
    } finally { $archive.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($candidate, $verificationPath)
    $extracted = @(Get-ChildItem -LiteralPath $verificationPath -Force)
    if ($extracted.Count -ne $required.Count) { throw 'Quantidade incorreta de arquivos no ZIP.' }
    foreach ($name in $required) {
        $sourceHash = (Get-FileHash -LiteralPath (Join-Path $SourcePath $name) -Algorithm SHA256).Hash
        $extractedHash = (Get-FileHash -LiteralPath (Join-Path $verificationPath $name) -Algorithm SHA256).Hash
        if ($sourceHash -ne $extractedHash) { throw ('Arquivo alterado ao compactar: '+$name) }
    }
    Write-Host ('OK: ZIP extraido; os '+$required.Count+' arquivos conferem byte a byte com a origem.')

    # Os testes executam o pacote extraido, em processos novos do PowerShell 5.1.
    $powershell = Join-Path $PSHOME 'powershell.exe'
    & $powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verificar-pacote.ps1') -PackagePath $verificationPath
    if ($LASTEXITCODE -ne 0) { throw 'A verificacao do pacote extraido falhou.' }
    & $powershell -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verificar-interface.ps1') -PackagePath $verificationPath -Download
    if ($LASTEXITCODE -ne 0) { throw 'A verificacao da interface e da retomada falhou.' }

    # Publica a saida local apenas depois de todos os testes passarem.
    Move-Item -LiteralPath $candidate -Destination $zipPath -Force
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($checksumPath, $hash+'  BO2-Plutonium.zip'+"`n", [Text.UTF8Encoding]::new($false))
    Write-Host ('OK: '+$zipPath+' | SHA-256 '+$hash)
} finally {
    if ([IO.File]::Exists($candidate)) { [IO.File]::Delete($candidate) }
    if ([IO.Directory]::Exists($verificationPath)) {
        # O ZIP foi construido somente com arquivos de nomes conhecidos, sem subpastas.
        foreach ($name in $required) { [IO.File]::Delete((Join-Path $verificationPath $name)) }
        [IO.Directory]::Delete($verificationPath)
    }
}
