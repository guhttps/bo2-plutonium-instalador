Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Executable {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = $null
    $reader = $null
    try {
        $stream = [IO.File]::OpenRead($Path)
        $reader = New-Object IO.BinaryReader($stream)
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Position = 60
        $offset = $reader.ReadUInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 4)) { return $false }
        $stream.Position = $offset
        return ($reader.ReadUInt32() -eq 0x4550)
    } catch { return $false }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-WebFile {
    param([string]$Url, [string]$Destination, [string]$Sha256)
    if ($Sha256 -and (Test-Path -LiteralPath $Destination -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $Sha256) { return }
    $downloadPath = $Destination + '.' + [guid]::NewGuid().ToString('N') + '.download'
    $previousProgress = $ProgressPreference
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $downloadPath -UseBasicParsing -TimeoutSec 180
        if ($Sha256 -and (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $Sha256) {
            throw "O download nao corresponde ao SHA256 esperado: $Url"
        }
        Move-Item -LiteralPath $downloadPath -Destination $Destination -Force
    } finally {
        $ProgressPreference = $previousProgress
        if (Test-Path -LiteralPath $downloadPath) { Remove-Item -LiteralPath $downloadPath -Force }
    }
}

function Get-OfficialLauncher {
    param([Parameter(Mandatory)][string]$Destination)
    $temporary = $Destination + '.' + [guid]::NewGuid().ToString('N') + '.exe'
    try {
        Get-WebFile -Url 'https://cdn.plutonium.pw/updater/plutonium.exe' -Destination $temporary
        if (-not (Test-Executable -Path $temporary)) { throw 'O servidor nao entregou um executavel valido.' }
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Get-Aria2 {
    param([string]$CachePath)
    $binary = Join-Path $CachePath 'aria2\aria2-1.37.0-win-64bit-build1\aria2c.exe'
    $binaryHash = 'BE2099C214F63A3CB4954B09A0BECD6E2E34660B886D4C898D260FEBFE9D70C2'
    if ((Test-Path -LiteralPath $binary -PathType Leaf) -and
        (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -eq $binaryHash) { return $binary }
    $archive = Join-Path $CachePath 'aria2.zip'
    Get-WebFile -Url 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip' -Destination $archive -Sha256 '67D015301EEF0B612191212D564C5BB0A14B5B9C4796B76454276A4D28D9B288'
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $CachePath 'aria2') -Force
    if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -ne $binaryHash) { throw 'aria2 extraido invalido.' }
    return $binary
}

function Set-GamePath {
    param([string]$ConfigPath, [string]$GamePath)
    $config = [pscustomobject]@{}
    $previous = $null
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        $previous = [IO.File]::ReadAllText($ConfigPath)
        $config = $previous | ConvertFrom-Json
        if ($null -eq $config -or $config -isnot [pscustomobject]) { throw 'Config.json existente possui um formato desconhecido.' }
    }
    if ($config.PSObject.Properties['t6Path']) { $config.t6Path = $GamePath }
    else { $config | Add-Member -NotePropertyName t6Path -NotePropertyValue $GamePath }
    $json = $config | ConvertTo-Json -Depth 100
    if ($previous) {
        $backup = $ConfigPath + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText($backup, $previous, (New-Object Text.UTF8Encoding($false)))
    }
    $temporary = $ConfigPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $ConfigPath -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Assert-MicrosoftSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "Assinatura Microsoft nao validada: $Path"
    }
}

function Wait-PlutoniumUpdate {
    param([Diagnostics.Process]$Process)
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.WaitForExit(1000)) {
        if ($timer.Elapsed.TotalMinutes -ge 10) {
            throw 'O atualizador ainda esta aberto. Conclua as etapas nele, feche-o e execute INSTALAR.cmd novamente.'
        }
        $completed = $false
        try {
            $Process.Refresh()
            if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
                $window = [Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
                $condition = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, 'Game is up to date!')
                $status = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
                if ($null -ne $status) {
                    $bounds = $status.Current.BoundingRectangle
                    $completed = -not $status.Current.IsOffscreen -and $bounds.Width -gt 0 -and $bounds.Height -gt 0
                }
            }
        } catch { $completed = $false }
        if ($completed) {
            [void]$Process.CloseMainWindow()
            if (-not $Process.WaitForExit(10000)) { throw 'A atualizacao terminou, mas a janela do atualizador nao fechou. Feche-a e execute novamente.' }
        }
    }
    if ($Process.ExitCode -ne 0) { throw "O atualizador retornou codigo $($Process.ExitCode)." }
}
