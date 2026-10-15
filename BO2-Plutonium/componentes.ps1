[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GamePath,
    [Parameter(Mandatory)][string]$CachePath,
    [switch]$Elevado,
    [switch]$SomenteVerificar
)

. (Join-Path $PSScriptRoot 'Funcoes.ps1')

function Get-RequiredComponents {
    $systemPath = Join-Path $env:WINDIR 'SysWOW64'
    $sxsPath = Join-Path $env:WINDIR 'WinSxS'
    foreach ($version in @('80', '90')) {
        $dll = 'msvcp' + $version + '.dll'
        $present = Test-Path -LiteralPath (Join-Path $systemPath $dll)
        if (-not $present) {
            foreach ($directory in (Get-ChildItem -LiteralPath $sxsPath -Directory -Filter ('x86_microsoft.vc' + $version + '.crt_*'))) {
                if (Test-Path -LiteralPath (Join-Path $directory.FullName $dll)) { $present = $true; break }
            }
        }
        if (-not $present) {
            if ($version -eq '80') {
                [pscustomobject]@{Name='Visual C++ 2005 x86'; Path=(Join-Path $CachePath 'vc2005-x86.exe'); Url='https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.EXE'; Args='/q'}
            } else {
                [pscustomobject]@{Name='Visual C++ 2008 x86'; Path=(Join-Path $CachePath 'vc2008-x86.exe'); Url='https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe'; Args='/qn'}
            }
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $systemPath 'msvcp100.dll'))) {
        [pscustomobject]@{Name='Visual C++ 2010 x86'; Path=(Join-Path $CachePath 'vc2010-x86.exe'); Url='https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe'; Args='/quiet /install /norestart'}
    }
    if (-not (Test-Path -LiteralPath (Join-Path $systemPath 'msvcp140.dll'))) {
        [pscustomobject]@{Name='Visual C++ v14 x86'; Path=(Join-Path $CachePath 'vc14-x86.exe'); Url='https://aka.ms/vc14/vc_redist.x86.exe'; Args='/quiet /install /norestart'}
    }
    $directXMissing = $false
    foreach ($dll in @('d3dx9_43.dll', 'd3d11.dll', 'xinput1_3.dll', 'XAudio2_7.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $systemPath $dll))) { $directXMissing = $true }
    }
    if ($directXMissing) {
        [pscustomobject]@{Name='DirectX June 2010'; Path=(Join-Path $GamePath 'redist\DirectX\DXSETUP.exe'); Url=$null; Args='/silent'}
    }
}

try {
    $required = @(Get-RequiredComponents)
    if ($SomenteVerificar) { $required | Select-Object Name,Path | ConvertTo-Json -Compress; exit 0 }
    if ($required.Count -eq 0) { Write-Host 'Componentes Microsoft ja presentes.'; exit 0 }
    foreach ($component in $required) {
        if ($component.Url -and -not (Test-Path -LiteralPath $component.Path -PathType Leaf)) {
            Write-Host ('Baixando ' + $component.Name + ' da Microsoft...')
            Get-WebFile -Url $component.Url -Destination $component.Path
        }
        Assert-MicrosoftSignature -Path $component.Path
    }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ($Elevado) { throw 'O Windows nao concedeu permissao para instalar os componentes.' }
        Write-Host 'Confirme a janela do Windows para instalar os componentes Microsoft ausentes.'
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -GamePath "' + $GamePath + '" -CachePath "' + $CachePath + '" -Elevado'
        $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Componentes nao concluidos (codigo $($process.ExitCode))." }
        exit 0
    }
    foreach ($component in $required) {
        Assert-MicrosoftSignature -Path $component.Path
        Write-Host ('Instalando ' + $component.Name + '...')
        $process = Start-Process -FilePath $component.Path -ArgumentList $component.Args -Wait -PassThru
        if ($process.ExitCode -eq 3010) { Write-Host 'Um componente solicitou reinicializacao. Reinicie antes de jogar.' }
        elseif ($process.ExitCode -notin @(0, 1638)) { throw "$($component.Name): codigo de erro $($process.ExitCode)." }
    }
    if (@(Get-RequiredComponents).Count -gt 0) { throw 'Ainda ha componentes ausentes. Reinicie o PC e execute INSTALAR.cmd novamente.' }
    exit 0
} catch {
    Write-Host ('Componentes pendentes: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
