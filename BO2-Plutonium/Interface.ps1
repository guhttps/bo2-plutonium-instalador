[CmdletBinding()]
param([switch]$Torrent, [string]$PreviewPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
$script:GuiPackagePath = $PSScriptRoot

function Assert-InstallerPackage {
    param([string]$Path)
    $required = @('Interface.ps1','instalar.ps1','Funcoes.ps1','Progresso.ps1',
        'componentes.ps1','TorrentVerifier.cs','arquivos-http.json','pluto_t6_full_game.torrent')
    $missing = @($required | Where-Object { -not [IO.File]::Exists((Join-Path $Path $_)) })
    if ($missing.Count -gt 0) {
        throw ("O pacote está incompleto. Feche esta janela e clique com o botão direito em BO2-Plutonium.zip > Extrair Tudo… Depois, abra INSTALAR.cmd dentro da pasta extraída, fora do ZIP.`n`nArquivos ausentes: "+($missing -join ', ')+".`nSe já extraiu tudo, baixe novamente o ZIP completo e extraia em uma nova pasta.")
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Assert-InstallerPackage -Path $script:GuiPackagePath }
    catch {
        [void][Windows.MessageBox]::Show($_.Exception.Message,'Extraia todos os arquivos','OK','Warning')
        exit 1
    }
}
. (Join-Path $PSScriptRoot 'Progresso.ps1')

function Format-DownloadSize {
    param([long]$Bytes)
    $culture = [Globalization.CultureInfo]::GetCultureInfo('pt-BR')
    if ($Bytes -ge 1000000000) { return ($Bytes/1000000000).ToString('N2',$culture)+' GB' }
    if ($Bytes -ge 1000000) { return ($Bytes/1000000).ToString('N1',$culture)+' MB' }
    if ($Bytes -ge 1000) { return ($Bytes/1000).ToString('N0',$culture)+' KB' }
    return $Bytes.ToString()+' B'
}

function Read-InstallerSnapshot {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $null }
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
        try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Set-InstallerSnapshot {
    param($Snapshot)
    $script:GuiSnapshot = $Snapshot
    $script:GuiControls.Status.Text = $Snapshot.Message
    if ($script:GuiCancelRequested -and $Snapshot.State -eq 'running') {
        $script:GuiControls.Status.Text = 'Interrompendo e salvando o download para retomar depois...'
    }
    $script:GuiControls.Phase.Text = switch ($Snapshot.Stage) {
        'download' { 'DOWNLOAD GERAL' }
        'verifying' { 'VERIFICAÇÃO DOS ARQUIVOS' }
        'components' { 'COMPONENTES DO WINDOWS' }
        'client' { 'PLUTONIUM' }
        'configuring' { 'CONFIGURAÇÃO FINAL' }
        'complete' { 'TUDO PRONTO' }
        'cancelled' { 'INSTALAÇÃO INTERROMPIDA' }
        'error' { 'PRECISA DE ATENÇÃO' }
        default { 'PREPARANDO' }
    }
    $hasPercent = $null -ne $Snapshot.Percent
    $script:GuiControls.Progress.IsIndeterminate = -not $hasPercent -and $Snapshot.State -eq 'running'
    $script:GuiControls.Progress.Value = if ($hasPercent) { [double]$Snapshot.Percent } else { 0 }
    $script:GuiControls.Percent.Text = if ($hasPercent) { ([double]$Snapshot.Percent).ToString('N0')+'%' } else { '—' }
    $script:GuiControls.Speed.Text = '—'
    $script:GuiControls.Eta.Text = '—'
    $script:GuiControls.Amount.Text = if ($Snapshot.TotalBytes -gt 0) {
        (Format-DownloadSize $Snapshot.CompletedBytes)+' de '+(Format-DownloadSize $Snapshot.TotalBytes)
    } else { '14,54 GB · Multiplayer, Zombies e DLCs' }
    $script:GuiControls.FileCount.Text = if ($Snapshot.TotalFiles -gt 0) { "$($Snapshot.CompletedFiles) de $($Snapshot.TotalFiles) arquivos" } else { '' }
    if ($Snapshot.Stage -eq 'download') {
        $script:GuiControls.Speed.Text = (Format-DownloadSize $Snapshot.Speed)+'/s'
        if ($Snapshot.Speed -gt 0) {
            $seconds = [Math]::Max(0,($Snapshot.TotalBytes-$Snapshot.CompletedBytes)/$Snapshot.Speed)
            $remaining = [TimeSpan]::FromSeconds($seconds)
            $script:GuiControls.Eta.Text = if ($seconds -ge 3600) { '{0}h {1:00}min' -f [int][Math]::Floor($remaining.TotalHours),$remaining.Minutes } elseif ($seconds -ge 60) { '{0}min {1:00}s' -f [int][Math]::Floor($remaining.TotalMinutes),$remaining.Seconds } else { '{0}s' -f [int]$seconds }
        } else { $script:GuiControls.Eta.Text = 'Aguardando rede' }
    }
    $script:GuiControls.Status.Foreground = if ($Snapshot.State -eq 'error') { '#FFA7A7' } else { '#DCE5EF' }
    if ($script:GuiBusy) { $script:GuiControls.Secondary.IsEnabled = [bool]$Snapshot.Cancellable -and -not $script:GuiCancelRequested }
}

function Save-InstallerPreview {
    param([string]$Path)
    $script:GuiWindow.UpdateLayout()
    $visual = $script:GuiWindow.Content
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$visual.ActualWidth,[int]$visual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

function Start-InstallerWorker {
    Assert-InstallerPackage -Path $script:GuiPackagePath
    $selectedPath = $script:GuiControls.Path.Text.Trim()
    if (-not $selectedPath -or $selectedPath -match '[\r\n\t"]' -or -not [IO.Path]::IsPathRooted($selectedPath)) {
        throw 'Escolha uma pasta com caminho completo, como D:\Jogos\BO2-Plutonium.'
    }
    $selectedPath = [IO.Path]::GetFullPath($selectedPath)
    if ((Split-Path -Leaf $selectedPath.TrimEnd('\')) -eq 'pluto_t6_full_game') { $selectedPath = Split-Path -Parent $selectedPath }
    $script:GuiControls.Path.Text = $selectedPath
    $sessionPath = Join-Path $env:LOCALAPPDATA ('BO2-Plutonium-Assistente\sessoes\'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
    $script:GuiStatusPath = Join-Path $sessionPath 'status.json'
    $script:GuiCancelPath = Join-Path $sessionPath 'cancelar'
    $script:GuiOutputPath = Join-Path $sessionPath 'instalacao.log'
    $script:GuiErrorPath = Join-Path $sessionPath 'erros.log'
    $workerArguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $script:GuiPackagePath 'instalar.ps1'),'-PastaJogos',$selectedPath,'-StatusPath',$script:GuiStatusPath,'-CancelPath',$script:GuiCancelPath,'-OwnerProcessId',$PID.ToString(),'-SemAbrir')
    if ($Torrent) { $workerArguments += '-Torrent' }
    $arguments = ($workerArguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $script:GuiWorker = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $script:GuiOutputPath -RedirectStandardError $script:GuiErrorPath
    $null = $script:GuiWorker.Handle
    $script:GuiBusy = $true
    $script:GuiCancelRequested = $false
    $script:GuiSnapshot = $null
    $script:GuiControls.Primary.IsEnabled = $false
    $script:GuiControls.Primary.Content = 'Instalando...'
    $script:GuiControls.Path.IsEnabled = $false
    $script:GuiControls.Browse.IsEnabled = $false
    $script:GuiControls.Secondary.Content = 'Interromper'
    $script:GuiControls.Secondary.IsEnabled = $true
    $script:GuiControls.Status.Text = 'Iniciando a instalação...'
    $script:GuiControls.Phase.Text = 'PREPARANDO'
    $script:GuiControls.Progress.IsIndeterminate = $true
}

function Complete-InstallerWorker {
    $script:GuiWorker.WaitForExit()
    $code = $script:GuiWorker.ExitCode
    if ($null -eq $script:GuiSnapshot -or $script:GuiSnapshot.State -eq 'running') {
        $fallback = [pscustomobject]@{State='error';Stage='error';Message='A instalação não concluiu. Abra os detalhes e tente novamente.';Percent=$null;CompletedBytes=0L;TotalBytes=0L;Speed=0L;CompletedFiles=0;TotalFiles=0;Cancellable=$false}
        Set-InstallerSnapshot $fallback
    }
    $script:GuiBusy = $false
    $script:GuiWorker.Dispose()
    $script:GuiWorker = $null
    $script:GuiControls.Progress.IsIndeterminate = $false
    $success = $code -eq 0 -and $script:GuiSnapshot.State -eq 'complete'
    $script:GuiControls.Primary.Content = if ($success) { 'Abrir Plutonium' } elseif ($script:GuiSnapshot.State -eq 'cancelled') { 'Continuar instalação' } else { 'Tentar novamente' }
    $script:GuiControls.Primary.IsEnabled = $true
    $script:GuiControls.Path.IsEnabled = -not $success
    $script:GuiControls.Browse.IsEnabled = -not $success
    $script:GuiControls.Secondary.Content = 'Fechar'
    $script:GuiControls.Secondary.IsEnabled = $true
}

function Update-InstallerDetails {
    if (-not $script:GuiControls.Details.IsExpanded) { return }
    $lines = @()
    foreach ($path in @($script:GuiOutputPath,$script:GuiErrorPath)) {
        if ($path -and [IO.File]::Exists($path)) { $lines += @(Get-Content -LiteralPath $path -Tail 50 -ErrorAction SilentlyContinue) }
    }
    $script:GuiControls.DetailsBox.Text = $lines -join [Environment]::NewLine
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="BO2 + Plutonium | Instalação" Width="840" Height="700" MinWidth="740" MinHeight="660" WindowStartupLocation="CenterScreen" Background="#10171F" Foreground="#F4F7FB" FontFamily="Segoe UI">
 <Window.Resources>
  <Style TargetType="Button">
   <Setter Property="Background" Value="#263544"/><Setter Property="Foreground" Value="#E6EDF5"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="20,11"/><Setter Property="FontSize" Value="14"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Surface" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.8"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Surface" Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>
 <ScrollViewer Background="#10171F" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
 <Grid Margin="32,28,32,24">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Grid.Row="0" Margin="0,0,0,24">
   <TextBlock Text="ASSISTENTE DE INSTALAÇÃO" Foreground="#63DCC2" FontSize="11" FontWeight="SemiBold"/>
   <TextBlock Text="Black Ops II + Plutonium" FontSize="32" FontWeight="SemiBold" Margin="0,6,0,8"/>
   <TextBlock Text="Multiplayer, Zombies e DLCs. Escolha a pasta e acompanhe tudo por aqui." Foreground="#A7B7C8" FontSize="14" TextWrapping="Wrap"/>
  </StackPanel>
  <Border Grid.Row="1" Background="#19232E" BorderBrush="#2B3B4C" BorderThickness="1" CornerRadius="12" Padding="20" Margin="0,0,0,16">
   <StackPanel>
    <TextBlock Text="Onde você quer instalar?" FontWeight="SemiBold" FontSize="16" Margin="0,0,0,12"/>
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBox x:Name="PathInput" Grid.Column="0" Background="#101923" Foreground="#EDF3FA" CaretBrush="#63DCC2" BorderBrush="#3C5064" FontSize="14" Padding="12,10" VerticalContentAlignment="Center" Margin="0,0,10,0"/>
     <Button x:Name="BrowseButton" Grid.Column="1" Content="Escolher pasta"/>
    </Grid>
    <TextBlock x:Name="DestinationPreview" Foreground="#A7B7C8" FontSize="11" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
    <TextBlock Text="Reserve 18 GB livres no disco do jogo e 1 GB para o cliente do Plutonium." Foreground="#A7B7C8" FontSize="12" Margin="0,7,0,0" TextWrapping="Wrap"/>
   </StackPanel>
  </Border>
  <Border Grid.Row="2" Background="#19232E" BorderBrush="#2B3B4C" BorderThickness="1" CornerRadius="12" Padding="20" Margin="0,0,0,16">
   <StackPanel>
    <TextBlock x:Name="PhaseLabel" Text="PRONTO PARA COMEÇAR" Foreground="#63DCC2" FontSize="11" FontWeight="SemiBold"/>
    <TextBlock x:Name="StatusLabel" Text="Tudo pronto para preparar seu jogo." FontSize="16" Foreground="#DCE5EF" Margin="0,8,0,18" TextWrapping="Wrap"/>
    <ProgressBar x:Name="OverallProgress" Height="12" Minimum="0" Maximum="100" Value="0" Foreground="#63DCC2" Background="#2A3A4B" BorderThickness="0"/>
    <Grid Margin="0,18,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
     <StackPanel Grid.Column="0"><TextBlock Text="PROGRESSO" Foreground="#93A7BB" FontSize="10"/><TextBlock x:Name="PercentLabel" Text="0%" FontSize="23" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel>
     <StackPanel Grid.Column="1"><TextBlock Text="VELOCIDADE" Foreground="#93A7BB" FontSize="10"/><TextBlock x:Name="SpeedLabel" Text="—" FontSize="23" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel>
     <StackPanel Grid.Column="2"><TextBlock Text="TEMPO RESTANTE" Foreground="#93A7BB" FontSize="10"/><TextBlock x:Name="EtaLabel" Text="—" FontSize="20" FontWeight="SemiBold" Margin="0,6,0,0"/></StackPanel>
    </Grid>
    <Grid Margin="0,14,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="AmountLabel" Text="14,54 GB · 525 arquivos" Foreground="#A7B7C8" FontSize="12"/><TextBlock x:Name="FileCountLabel" Grid.Column="1" Foreground="#A7B7C8" FontSize="12"/></Grid>
   </StackPanel>
  </Border>
  <Expander x:Name="DetailsExpander" Grid.Row="3" Header="Detalhes da instalação" Foreground="#A7B7C8" Margin="0,0,0,18" FontSize="12">
   <TextBox x:Name="DetailsBox" IsReadOnly="True" Height="120" Margin="0,10,0,0" Background="#0C1219" Foreground="#9FB1C4" BorderThickness="0" FontFamily="Consolas" FontSize="11" Padding="10" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
  </Expander>
  <Grid Grid.Row="4"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <TextBlock x:Name="FooterLabel" Text="Windows 10/11 · 64 bits&#xA;Cadastro e login no launcher oficial." Foreground="#93A7BB" FontSize="11" VerticalAlignment="Center"/>
   <Button x:Name="SecondaryButton" Grid.Column="1" Content="Fechar" Margin="12,0,10,0"/>
   <Button x:Name="PrimaryButton" Grid.Column="2" Content="Instalar agora" Background="#63DCC2" Foreground="#0E2727" FontWeight="SemiBold" MinWidth="170"/>
  </Grid>
 </Grid>
 </ScrollViewer>
</Window>
'@
$script:GuiWindow = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$script:GuiControls = @{}
@{Path='PathInput';Browse='BrowseButton';Destination='DestinationPreview';Phase='PhaseLabel';Status='StatusLabel';Progress='OverallProgress';Percent='PercentLabel';Speed='SpeedLabel';Eta='EtaLabel';Amount='AmountLabel';FileCount='FileCountLabel';Details='DetailsExpander';DetailsBox='DetailsBox';Primary='PrimaryButton';Secondary='SecondaryButton';Footer='FooterLabel'}.GetEnumerator() | ForEach-Object { $script:GuiControls[$_.Key] = $script:GuiWindow.FindName($_.Value) }
$script:GuiBusy = $false
$script:GuiWorker = $null
$script:GuiSnapshot = $null
$script:GuiCancelRequested = $false
$script:GuiStatusPath = ''
$script:GuiCancelPath = ''
$script:GuiOutputPath = ''
$script:GuiErrorPath = ''
$script:GuiControls.Path.Text = Join-Path $env:USERPROFILE 'Games\BO2-Plutonium'
$updateDestination = {
    $path = $script:GuiControls.Path.Text.TrimEnd('\')+'\pluto_t6_full_game'
    $script:GuiControls.Destination.Text = 'Pasta do jogo: '+$path
    $script:GuiControls.Destination.ToolTip = $path
}
$script:GuiControls.Path.Add_TextChanged($updateDestination)
& $updateDestination
if ($Torrent) { $script:GuiControls.Footer.Text = "Fonte alternativa: BitTorrent`nCadastro e login no launcher oficial." }
$script:GuiControls.Browse.Add_Click({
    $dialog = [Windows.Forms.FolderBrowserDialog]::new()
    try {
        $dialog.Description = 'Escolha a pasta em que quer guardar o jogo.'
        $dialog.ShowNewFolderButton = $true
        if ([IO.Directory]::Exists($script:GuiControls.Path.Text)) { $dialog.SelectedPath = $script:GuiControls.Path.Text }
        if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $script:GuiControls.Path.Text = $dialog.SelectedPath }
    } finally { $dialog.Dispose() }
})
$script:GuiControls.Primary.Add_Click({
    try {
        if ($null -ne $script:GuiSnapshot -and $script:GuiSnapshot.State -eq 'complete') {
            $launcher = Join-Path $env:LOCALAPPDATA 'BO2-Plutonium-Assistente\plutonium.exe'
            Start-Process -FilePath $launcher -WorkingDirectory (Split-Path -Parent $launcher) | Out-Null
        } else { Start-InstallerWorker }
    } catch { [void][Windows.MessageBox]::Show($script:GuiWindow,$_.Exception.Message,'Não foi possível iniciar','OK','Warning') }
})
$script:GuiControls.Secondary.Add_Click({
    if ($script:GuiBusy) {
        [IO.File]::WriteAllText($script:GuiCancelPath,'cancelar')
        $script:GuiCancelRequested = $true
        $script:GuiControls.Secondary.IsEnabled = $false
        $script:GuiControls.Status.Text = 'Interrompendo e salvando o download para retomar depois...'
    } else { $script:GuiWindow.Close() }
})
$script:GuiControls.Details.Add_Expanded({Update-InstallerDetails})
$script:GuiWindow.Add_Closing({
    param($sender,$eventArgs)
    if ($script:GuiBusy) {
        $eventArgs.Cancel = $true
        [void][Windows.MessageBox]::Show($script:GuiWindow,'A instalação ainda está em andamento. Use Interromper para salvar o download ou aguarde a etapa atual terminar.','Instalação em andamento','OK','Information')
    }
})
$script:GuiTimer = [Windows.Threading.DispatcherTimer]::new()
$script:GuiTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:GuiTimer.Add_Tick({
    try {
        Update-InstallerDetails
        if ($null -eq $script:GuiWorker) { return }
        $snapshot = Read-InstallerSnapshot $script:GuiStatusPath
        if ($null -ne $snapshot) { Set-InstallerSnapshot $snapshot }
        if ($script:GuiWorker.HasExited) { Complete-InstallerWorker }
    } catch { }
})
$script:GuiWindow.Add_Closed({ $script:GuiTimer.Stop() })
if ($PreviewPath) { $script:GuiWindow.Add_ContentRendered({ Save-InstallerPreview $PreviewPath; $script:GuiWindow.Close() }) }
if ($MyInvocation.InvocationName -ne '.') {
    $script:GuiTimer.Start()
    [void]$script:GuiWindow.ShowDialog()
}
