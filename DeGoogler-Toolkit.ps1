#Requires -Version 5.1
<#
.SYNOPSIS
    DeGoogler Toolkit v0.0.2 - Google Data Migration & Processing Suite
.DESCRIPTION
    Turnkey PowerShell WPF application that handles:
    - Google Takeout archive extraction and organization
    - Google Photos metadata restoration (JSON sidecar to EXIF)
    - Chrome password CSV to Bitwarden/KeePass conversion
    - MBOX email processing and conversion to EML
    - Chrome bookmark conversion for Firefox/Brave
    - Google Contacts vCard processing
    Features:
    - Dry-Run mode on every tool (reports planned actions without writing)
    - Structured JSONL logging to %LOCALAPPDATA%\DeGoogler\logs\
.AUTHOR
    SysAdminDoc
.VERSION
    0.0.2
#>

param(
    [string]$DeepLink,
    [string]$PlanPath,
    [switch]$RegisterProtocol,
    [switch]$CheckForUpdate,
    [switch]$DownloadUpdate
)

$script:toolkitRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:corePath = Join-Path $script:toolkitRoot 'DeGoogler-Toolkit.Core.ps1'
if (-not (Test-Path -LiteralPath $script:corePath)) {
    Write-Error "Missing toolkit core: $script:corePath. Keep DeGoogler-Toolkit.Core.ps1 beside this script."
    exit 1
}
. $script:corePath
$script:toolkitVersion = '0.0.7'

function Register-DgProtocolHandler {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) { throw 'Protocol registration requires running the toolkit from a .ps1 file.' }
    $protocolRoot = 'HKCU:\Software\Classes\degoogler'
    $commandRoot = Join-Path $protocolRoot 'shell\open\command'
    New-Item -Path $commandRoot -Force | Out-Null
    Set-ItemProperty -Path $protocolRoot -Name '(Default)' -Value 'URL:DeGoogler Toolkit'
    New-ItemProperty -Path $protocolRoot -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    Set-ItemProperty -Path $commandRoot -Name '(Default)' -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -DeepLink "%1"')
}

if ($RegisterProtocol) {
    Register-DgProtocolHandler
    Write-Output 'Registered degoogler:// protocol handler for the current user.'
    exit 0
}

if ($CheckForUpdate -or $DownloadUpdate) {
    try {
        $update = Get-DgReleaseUpdate -CurrentVersion $script:toolkitVersion
        if (-not $update.UpdateAvailable) {
            Write-Output "DeGoogler Toolkit $($script:toolkitVersion) is current."
            exit 0
        }
        if (-not $update.VerifiedBundleAvailable) {
            Write-Error "DeGoogler $($update.LatestVersion) is available, but its release bundle/checksum assets are incomplete. No download was made."
            exit 2
        }
        Write-Output "Verified update available: DeGoogler $($update.LatestVersion) ($($update.BundleAssetName))."
        Write-Output "Release: $($update.ReleaseUrl)"
        if ($DownloadUpdate) {
            $destination = Join-Path $env:LOCALAPPDATA ("DeGoogler\updates\{0}" -f $update.BundleAssetName)
            $downloaded = Save-DgVerifiedReleaseBundle -Update $update -DestinationPath $destination
            Write-Output "Downloaded and SHA-256 verified: $($downloaded.Path)"
        }
        exit 0
    } catch {
        Write-Error "Update check failed: $($_.Exception.Message)"
        exit 1
    }
}

# ── Auto-elevate ──
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevatedArguments = @('-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
    if ($DeepLink) { $elevatedArguments += @('-DeepLink',('"' + $DeepLink + '"')) }
    if ($PlanPath) { $elevatedArguments += @('-PlanPath',('"' + $PlanPath + '"')) }
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($elevatedArguments -join ' ')
    exit
}

# ── Assemblies ──
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ── Hide console ──
Add-Type -Name Win -Namespace Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
[Native.Win]::ShowWindow([Native.Win]::GetConsoleWindow(), 0) | Out-Null

# ── Check/Install exiftool for Photos metadata ──
function Test-ExifToolLayout {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $filesDir = Join-Path (Split-Path -Parent $Path) 'exiftool_files'
    return (Test-Path -LiteralPath $filesDir)
}

function Install-ExifTool {
    $exifPath = Join-Path $env:LOCALAPPDATA "DeGoogler\exiftool.exe"
    if (Test-ExifToolLayout $exifPath) { return $exifPath }
    $bundledCandidates = @(
        (Join-Path $script:toolkitRoot "tools\exiftool.exe"),
        (Join-Path $script:toolkitRoot "exiftool.exe")
    )
    foreach ($candidate in $bundledCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $dir = Split-Path $exifPath
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $candidate -Destination $exifPath -Force
            $bundledFiles = Join-Path (Split-Path -Parent $candidate) 'exiftool_files'
            if (Test-Path -LiteralPath $bundledFiles) {
                $targetFiles = Join-Path $dir 'exiftool_files'
                if (Test-Path -LiteralPath $targetFiles) { Remove-Item -LiteralPath $targetFiles -Recurse -Force -ErrorAction SilentlyContinue }
                Copy-Item -LiteralPath $bundledFiles -Destination $targetFiles -Recurse -Force
            }
            if (Test-ExifToolLayout $exifPath) { return $exifPath }
        }
    }

    $dir = Split-Path $exifPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    try {
        $apiUrl = "https://api.github.com/repos/exiftool/exiftool/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' -and $_.name -match 'exiftool' } | Select-Object -First 1
        if ($zipAsset) {
            $zipPath = Join-Path $env:TEMP ("degoogler-exiftool-" + [guid]::NewGuid().ToString('N') + ".zip")
            Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing
            $extractDir = Join-Path $env:TEMP ("degoogler-exiftool-" + [guid]::NewGuid().ToString('N'))
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
            $exeFile = Get-ChildItem -Path $extractDir -Filter "exiftool(-k).exe" -Recurse | Select-Object -First 1
            if (-not $exeFile) { $exeFile = Get-ChildItem -Path $extractDir -Filter "exiftool*.exe" -Recurse | Select-Object -First 1 }
            if ($exeFile) {
                Copy-Item $exeFile.FullName $exifPath -Force
                $downloadedFiles = Join-Path $exeFile.Directory.FullName 'exiftool_files'
                if (Test-Path -LiteralPath $downloadedFiles) { Copy-Item -LiteralPath $downloadedFiles -Destination (Join-Path $dir 'exiftool_files') -Recurse -Force }
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-ExifToolLayout $exifPath) { return $exifPath }
            }
        }
    } catch {}
    return $null
}

# ── Structured JSONL Logging ──
$script:logDir = Join-Path $env:LOCALAPPDATA "DeGoogler\logs"
if (-not (Test-Path $script:logDir)) { New-Item -ItemType Directory -Path $script:logDir -Force | Out-Null }
$script:logFile = Join-Path $script:logDir ("toolkit_{0}.jsonl" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-JsonLog {
    param(
        [string]$Tool,
        [string]$Action,
        [string]$Message,
        [string]$Level = "INFO",
        [hashtable]$Data = @{}
    )
    $entry = @{
        ts      = (Get-Date -Format 'o')
        tool    = $Tool
        action  = $Action
        msg     = $Message
        level   = $Level
    }
    if ($Data.Count -gt 0) { $entry.data = $Data }
    try {
        $json = $entry | ConvertTo-Json -Compress -Depth 4
        [System.IO.File]::AppendAllText($script:logFile, "$json`n", [System.Text.Encoding]::UTF8)
    } catch {}
}

function Get-CheckpointPath {
    param([string]$Tool, [string]$InputPath)
    $safe = ($InputPath -replace '[\\/:*?"<>|]', '_')
    if ($safe.Length -gt 90) { $safe = $safe.Substring($safe.Length - 90) }
    return (Join-Path $script:logDir ("{0}_{1}.progress.json" -f $Tool, $safe))
}

function Read-Checkpoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
        $map = @{}
        foreach ($name in $json.PSObject.Properties.Name) {
            if ($name -eq 'done') {
                $doneMap = @{}
                foreach ($doneName in $json.done.PSObject.Properties.Name) { $doneMap[$doneName] = $json.done.$doneName }
                $map[$name] = $doneMap
            } else {
                $map[$name] = $json.$name
            }
        }
        return $map
    } catch {
        return @{}
    }
}

function Write-Checkpoint {
    param([string]$Path, [hashtable]$State)
    try {
        $dir = Split-Path $Path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temp, ($State | ConvertTo-Json -Depth 5), $utf8)
        Move-Item -LiteralPath $temp -Destination $Path -Force
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Set-CheckpointDone {
    param([hashtable]$State, [string]$Key)
    if (-not $State.ContainsKey('done')) { $State.done = @{} }
    $State.done[$Key] = (Get-Date -Format 'o')
}

function Test-CheckpointDone {
    param([hashtable]$State, [string]$Key)
    if (-not $State.ContainsKey('done')) { return $false }
    $done = $State['done']
    if ($done -is [hashtable]) { return $done.ContainsKey($Key) }
    return ($done.PSObject.Properties.Name -contains $Key)
}

$script:asyncCheckpointSource = @'
function Read-DgAsyncCheckpoint {
    param([string]$Path)
    $state = @{ version = 1; done = @{} }
    if (-not (Test-Path -LiteralPath $Path)) { return $state }
    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($property in $json.PSObject.Properties) {
            if ($property.Name -eq 'done') {
                $done = @{}
                foreach ($doneProperty in $property.Value.PSObject.Properties) { $done[$doneProperty.Name] = $doneProperty.Value }
                $state.done = $done
            } else { $state[$property.Name] = $property.Value }
        }
    } catch {}
    return $state
}
function Write-DgAsyncCheckpoint {
    param([string]$Path, [hashtable]$State)
    try {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temp, ($State | ConvertTo-Json -Depth 6), $utf8)
        Move-Item -LiteralPath $temp -Destination $Path -Force
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    } catch {}
}
function Set-DgAsyncCheckpointDone {
    param([hashtable]$State, [string]$Key)
    if (-not $State.ContainsKey('done') -or $null -eq $State.done) { $State.done = @{} }
    $State.done[$Key] = (Get-Date -Format 'o')
}
function Test-DgAsyncCheckpointDone {
    param([hashtable]$State, [string]$Key)
    if (-not $State.ContainsKey('done') -or $null -eq $State.done) { return $false }
    if ($State.done -is [hashtable]) { return $State.done.ContainsKey($Key) }
    return ($State.done.PSObject.Properties.Name -contains $Key)
}
'@

# ── XAML UI ──
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DeGoogler Toolkit v0.0.2" Width="920" Height="720"
        WindowStartupLocation="CenterScreen" Background="#1a1a2e"
        FontFamily="Segoe UI" ResizeMode="CanResizeWithGrip">
    <Window.Resources>
        <!-- ComboBox Toggle Button Template -->
        <ControlTemplate x:Key="ComboBoxToggleButton" TargetType="ToggleButton">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition/><ColumnDefinition Width="20"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="Border" Grid.ColumnSpan="2" Background="#333" BorderBrush="#444" BorderThickness="1" CornerRadius="3"/>
                <Border Grid.Column="0" Background="#333" BorderBrush="Transparent" BorderThickness="0" CornerRadius="3,0,0,3" Margin="1"/>
                <Path x:Name="Arrow" Grid.Column="1" Fill="#CCCCCC" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M0,0 L4,4 L8,0 Z"/>
            </Grid>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="Background" Value="#3a3a3a"/></Trigger>
                <Trigger Property="IsChecked" Value="True"><Setter TargetName="Border" Property="Background" Value="#404040"/></Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>
        <ControlTemplate x:Key="ComboBoxTemplate" TargetType="ComboBox">
            <Grid>
                <ToggleButton Name="ToggleButton" Template="{StaticResource ComboBoxToggleButton}" Focusable="False" ClickMode="Press"
                              IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
                <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}"
                                  ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" Margin="8,3,25,3" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                    <Grid Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                        <Border x:Name="DropDownBorder" Background="#2a2a2a" BorderThickness="1" BorderBrush="#444" CornerRadius="3">
                            <Border.Effect><DropShadowEffect Color="Black" BlurRadius="10" ShadowDepth="2" Opacity="0.5"/></Border.Effect>
                        </Border>
                        <ScrollViewer Margin="4,6,4,6" SnapsToDevicePixels="True"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
                    </Grid>
                </Popup>
            </Grid>
        </ControlTemplate>
        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="#e0e0e0"/><Setter Property="Background" Value="#333"/>
            <Setter Property="BorderBrush" Value="#444"/><Setter Property="Height" Value="32"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/><Setter Property="Template" Value="{StaticResource ComboBoxTemplate}"/>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#e0e0e0"/><Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="8,6"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
                <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="3" Margin="0,1">
                    <ContentPresenter/></Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="#3a3a3a"/></Trigger>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#3a3a3a"/></Trigger>
                    <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#0078D4"/></Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate></Setter.Value></Setter>
        </Style>
        <!-- Base styles -->
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#e0e0e0"/></Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#252536"/><Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="BorderBrush" Value="#333"/><Setter Property="CaretBrush" Value="#fff"/>
            <Setter Property="Padding" Value="8,6"/><Setter Property="SelectionBrush" Value="#0078D4"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0078D4"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="16,8"/>
            <Setter Property="Cursor" Value="Hand"/><Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#1a8ae8"/></Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#e0e0e0"/></Style>
        <Style TargetType="Label"><Setter Property="Foreground" Value="#e0e0e0"/></Style>
        <Style TargetType="ToolTip">
            <Setter Property="Background" Value="#2a2a2a"/><Setter Property="Foreground" Value="#e0e0e0"/><Setter Property="BorderBrush" Value="#444"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#16213e" Padding="20,14" BorderBrush="#333" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#0078D4" CornerRadius="8" Width="36" Height="36" Margin="0,0,12,0">
                        <TextBlock Text="DG" FontWeight="ExtraBold" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="White"/>
                    </Border>
                    <TextBlock Text="DeGoogler Toolkit" FontSize="18" FontWeight="Bold" VerticalAlignment="Center"/>
                    <Border Background="#252536" CornerRadius="4" Padding="6,2" Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="v0.0.2" FontSize="10" Foreground="#888"/>
                    </Border>
                </StackPanel>
                <StackPanel Grid.Column="2" HorizontalAlignment="Right">
                    <TextBlock Text="Your data stays on your machine" FontSize="11" Foreground="#666" HorizontalAlignment="Right"/>
                    <Button x:Name="btnCheckForUpdate" Content="Check for updates" FontSize="10" Padding="8,3" Margin="0,5,0,0" Background="#333" HorizontalAlignment="Right"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Tab navigation -->
        <Grid Grid.Row="1" Margin="16,12,16,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Tab buttons -->
            <WrapPanel Grid.Row="0" Margin="0,0,0,12">
                <Button x:Name="btnTabTakeout" Content="Takeout Extractor" Margin="0,0,6,6" Tag="tabTakeout"/>
                <Button x:Name="btnTabPhotos" Content="Photos Metadata Fix" Margin="0,0,6,6" Tag="tabPhotos"/>
                <Button x:Name="btnTabPasswords" Content="Password Converter" Margin="0,0,6,6" Tag="tabPasswords"/>
                <Button x:Name="btnTabEmail" Content="Email (MBOX) Processor" Margin="0,0,6,6" Tag="tabEmail"/>
                <Button x:Name="btnTabBookmarks" Content="Bookmark Converter" Margin="0,0,6,6" Tag="tabBookmarks"/>
                <Button x:Name="btnTabContacts" Content="Contacts Processor" Margin="0,0,6,6" Tag="tabContacts"/>
                <Button x:Name="btnTabConverters" Content="Export Converters" Margin="0,0,6,6" Tag="tabConverters"/>
            </WrapPanel>

            <!-- Tab: Takeout Extractor -->
            <Border x:Name="tabTakeout" Grid.Row="1" Background="#16213e" CornerRadius="8" Padding="20" BorderBrush="#333" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="Google Takeout Archive Extractor" FontSize="16" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Text="Extracts and organizes Google Takeout ZIP archives into labeled folders per service." Foreground="#999" FontSize="12" Margin="0,0,0,16" TextWrapping="Wrap"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtTakeoutInput" IsReadOnly="True" Text="Select Takeout archive(s)..." Foreground="#666"/>
                        <Button x:Name="btnTakeoutBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtTakeoutOutput" IsReadOnly="True" Text="Select output folder..." Foreground="#666"/>
                        <Button x:Name="btnTakeoutOutputBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <CheckBox x:Name="chkTakeoutDeleteZips" Content="Delete original ZIP files after extraction" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkTakeoutDryRun" Content="Dry Run — preview actions without writing" Margin="0,0,0,12" Foreground="#f59e0b"/>
                    <Button x:Name="btnTakeoutRun" Content="Extract and Organize" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <!-- Tab: Photos Metadata Fix -->
            <Border x:Name="tabPhotos" Grid.Row="1" Background="#16213e" CornerRadius="8" Padding="20" BorderBrush="#333" BorderThickness="1" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Google Photos Metadata Restorer" FontSize="16" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Text="Google Takeout strips EXIF data from photos and puts timestamps in sidecar JSON files. This tool merges them back so your photos retain original dates, GPS, and descriptions in any app." Foreground="#999" FontSize="12" Margin="0,0,0,16" TextWrapping="Wrap"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtPhotosInput" IsReadOnly="True" Text="Select Google Photos Takeout folder..." Foreground="#666"/>
                        <Button x:Name="btnPhotosBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <CheckBox x:Name="chkPhotosDeleteJson" Content="Delete JSON sidecar files after merging" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkPhotosFixDates" Content="Set file system dates to match photo dates" IsChecked="True" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkPhotosRecursive" Content="Process subfolders recursively" IsChecked="True" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkPhotosDryRun" Content="Dry Run — preview actions without writing" Margin="0,0,0,12" Foreground="#f59e0b"/>
                    <TextBlock x:Name="lblPhotosExiftool" Text="ExifTool: Checking..." Foreground="#f59e0b" FontSize="11" Margin="0,0,0,12"/>
                    <Button x:Name="btnPhotosRun" Content="Restore Photo Metadata" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <!-- Tab: Password Converter -->
            <Border x:Name="tabPasswords" Grid.Row="1" Background="#16213e" CornerRadius="8" Padding="20" BorderBrush="#333" BorderThickness="1" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Chrome Password Converter" FontSize="16" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Foreground="#999" FontSize="12" Margin="0,0,0,16" TextWrapping="Wrap">
                        <Run Text="Converts Chrome's exported password CSV to Bitwarden or KeePass import format. "/><LineBreak/>
                        <Run Text="Export from Chrome: Settings > Passwords > Export passwords (or chrome://password-manager/settings)" Foreground="#0078D4"/>
                    </TextBlock>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtPasswordsInput" IsReadOnly="True" Text="Select Chrome passwords CSV..." Foreground="#666"/>
                        <Button x:Name="btnPasswordsBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                        <TextBlock Text="Target format:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <ComboBox x:Name="cmbPasswordsFormat" Width="220">
                            <ComboBoxItem Content="Bitwarden (CSV)" IsSelected="True"/>
                            <ComboBoxItem Content="KeePass (CSV)"/>
                            <ComboBoxItem Content="1Password (CSV)"/>
                            <ComboBoxItem Content="Proton Pass (CSV)"/>
                        </ComboBox>
                    </StackPanel>
                    <CheckBox x:Name="chkPasswordsSecureDelete" Content="Securely overwrite source CSV after conversion" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkPasswordsDryRun" Content="Dry Run — preview actions without writing" Margin="0,0,0,12" Foreground="#f59e0b"/>
                    <Button x:Name="btnPasswordsRun" Content="Convert Passwords" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <!-- Tab: Email MBOX Processor -->
            <Border x:Name="tabEmail" Grid.Row="1" Background="#16213e" CornerRadius="8" Padding="20" BorderBrush="#333" BorderThickness="1" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Gmail MBOX Processor" FontSize="16" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Text="Splits Google Takeout MBOX files into individual EML files for import into Thunderbird, Proton Mail Bridge, or any standard email client." Foreground="#999" FontSize="12" Margin="0,0,0,16" TextWrapping="Wrap"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtEmailInput" IsReadOnly="True" Text="Select MBOX file..." Foreground="#666"/>
                        <Button x:Name="btnEmailBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtEmailOutput" IsReadOnly="True" Text="Select output folder for EML files..." Foreground="#666"/>
                        <Button x:Name="btnEmailOutputBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <CheckBox x:Name="chkEmailPreserveLabels" Content="Create subfolders from Gmail labels" IsChecked="True" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkEmailDryRun" Content="Dry Run — preview actions without writing" Margin="0,0,0,12" Foreground="#f59e0b"/>
                    <Button x:Name="btnEmailRun" Content="Process MBOX" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <!-- Tab: Bookmark Converter -->
            <Border x:Name="tabBookmarks" Grid.Row="1" Background="#16213e" CornerRadius="8" Padding="20" BorderBrush="#333" BorderThickness="1" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Chrome Bookmark Converter" FontSize="16" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Foreground="#999" FontSize="12" Margin="0,0,0,16" TextWrapping="Wrap">
                        <Run Text="Converts Chrome bookmarks (JSON or HTML) to standard Netscape HTML format for import into Firefox, Brave, LibreWolf, or Vivaldi."/><LineBreak/>
                        <Run Text="Auto-detects Chrome bookmark file if installed." Foreground="#0078D4"/>
                    </TextBlock>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtBookmarksInput" IsReadOnly="True" Text="Select bookmarks file or auto-detect..." Foreground="#666"/>
                        <Button x:Name="btnBookmarksBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                        <Button x:Name="btnBookmarksDetect" Grid.Column="2" Content="Auto-Detect" Margin="8,0,0,0" Background="#333"/>
                    </Grid>
                    <CheckBox x:Name="chkBookmarksDryRun" Content="Dry Run — preview actions without writing" Margin="0,0,0,12" Foreground="#f59e0b"/>
                    <Button x:Name="btnBookmarksRun" Content="Convert Bookmarks" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <!-- Tab: Contacts Processor -->
            <Border x:Name="tabContacts" Grid.Row="1" Background="#16213e" CornerRadius="8" Padding="20" BorderBrush="#333" BorderThickness="1" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Google Contacts Processor" FontSize="16" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Text="Processes Google Contacts vCard exports. Cleans duplicates, merges entries, and exports in standard vCard 3.0 format compatible with any contacts app." Foreground="#999" FontSize="12" Margin="0,0,0,16" TextWrapping="Wrap"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtContactsInput" IsReadOnly="True" Text="Select contacts.vcf or Takeout Contacts folder..." Foreground="#666"/>
                        <Button x:Name="btnContactsBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <CheckBox x:Name="chkContactsDedup" Content="Remove duplicate contacts" IsChecked="True" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkContactsClean" Content="Clean formatting (standardize phone numbers, fix encoding)" IsChecked="True" Margin="0,0,0,8"/>
                    <CheckBox x:Name="chkContactsDryRun" Content="Dry Run — preview actions without writing" Margin="0,0,0,12" Foreground="#f59e0b"/>
                    <Button x:Name="btnContactsRun" Content="Process Contacts" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <!-- Tab: Export Converters -->
            <Border x:Name="tabConverters" Grid.Row="1" Background="#16213e" CornerRadius="8" Padding="20" BorderBrush="#333" BorderThickness="1" Visibility="Collapsed">
                <StackPanel>
                    <TextBlock Text="Takeout Export Converters" FontSize="16" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Text="Converts Google Keep, Fit, Maps saved places, and Chat/Hangouts exports into portable formats." Foreground="#999" FontSize="12" Margin="0,0,0,16" TextWrapping="Wrap"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                        <TextBlock Text="Converter:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <ComboBox x:Name="cmbConvertersType" Width="280">
                            <ComboBoxItem Content="Keep to Markdown" IsSelected="True"/>
                            <ComboBoxItem Content="Fit to Apple Health XML / TCX"/>
                            <ComboBoxItem Content="Maps saved places to GeoJSON / GPX / KML"/>
                            <ComboBoxItem Content="Chat or Hangouts MBOX to JSON"/>
                        </ComboBox>
                    </StackPanel>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtConvertersInput" IsReadOnly="True" Text="Select export file or folder..." Foreground="#666"/>
                        <Button x:Name="btnConvertersBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtConvertersOutput" IsReadOnly="True" Text="Select output folder..." Foreground="#666"/>
                        <Button x:Name="btnConvertersOutputBrowse" Grid.Column="1" Content="Browse" Margin="8,0,0,0"/>
                    </Grid>
                    <CheckBox x:Name="chkConvertersDryRun" Content="Dry Run - preview actions without writing" Margin="0,0,0,12" Foreground="#f59e0b"/>
                    <Button x:Name="btnConvertersRun" Content="Convert Export" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>
        </Grid>

        <!-- Progress bar -->
        <Grid Grid.Row="2" Margin="16,8,16,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <ProgressBar x:Name="progressBar" Height="6" Background="#252536" Foreground="#0078D4" BorderThickness="0" Value="0"/>
            <TextBlock x:Name="lblProgress" Grid.Column="1" Text="" Foreground="#888" FontSize="11" Margin="10,0,0,0" VerticalAlignment="Center"/>
        </Grid>

        <!-- Log panel -->
        <Border Grid.Row="3" Background="#0d1117" BorderBrush="#333" BorderThickness="0,1,0,0" Margin="0,8,0,0" MaxHeight="180">
            <TextBox x:Name="txtLog" IsReadOnly="True" Background="Transparent" Foreground="#4ade80" FontFamily="Consolas" FontSize="11"
                     TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" BorderThickness="0" Padding="12,8"
                     Text="[DeGoogler Toolkit] Ready. Select a tool tab above to begin.&#x0A;"/>
        </Border>
    </Grid>
</Window>
'@

# ── Parse XAML and get controls ──
$window = [System.Windows.Markup.XamlReader]::Parse($xaml)

# Find all named controls
$controls = @{}
$controlNames = @(
    'btnTabTakeout','btnTabPhotos','btnTabPasswords','btnTabEmail','btnTabBookmarks','btnTabContacts','btnTabConverters',
    'tabTakeout','tabPhotos','tabPasswords','tabEmail','tabBookmarks','tabContacts','tabConverters',
    'txtTakeoutInput','btnTakeoutBrowse','txtTakeoutOutput','btnTakeoutOutputBrowse','chkTakeoutDeleteZips','chkTakeoutDryRun','btnTakeoutRun',
    'txtPhotosInput','btnPhotosBrowse','chkPhotosDeleteJson','chkPhotosFixDates','chkPhotosRecursive','chkPhotosDryRun','lblPhotosExiftool','btnPhotosRun',
    'txtPasswordsInput','btnPasswordsBrowse','cmbPasswordsFormat','chkPasswordsSecureDelete','chkPasswordsDryRun','btnPasswordsRun',
    'txtEmailInput','btnEmailBrowse','txtEmailOutput','btnEmailOutputBrowse','chkEmailPreserveLabels','chkEmailDryRun','btnEmailRun',
    'txtBookmarksInput','btnBookmarksBrowse','btnBookmarksDetect','chkBookmarksDryRun','btnBookmarksRun',
    'txtContactsInput','btnContactsBrowse','chkContactsDedup','chkContactsClean','chkContactsDryRun','btnContactsRun',
    'cmbConvertersType','txtConvertersInput','btnConvertersBrowse','txtConvertersOutput','btnConvertersOutputBrowse','chkConvertersDryRun','btnConvertersRun',
    'progressBar','lblProgress','txtLog','btnCheckForUpdate'
)
foreach ($name in $controlNames) {
    $controls[$name] = $window.FindName($name)
}

# ── Logging ──
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $prefix = switch ($Level) {
        "ERROR" { "[!]" }
        "WARN"  { "[~]" }
        "OK"    { "[+]" }
        default { "[*]" }
    }
    $controls['txtLog'].Dispatcher.Invoke([Action]{
        $controls['txtLog'].AppendText("[$timestamp] $prefix $Message`r`n")
        $controls['txtLog'].ScrollToEnd()
    })
}

function Set-Progress {
    param([int]$Value, [string]$Text = "")
    $controls['progressBar'].Dispatcher.Invoke([Action]{
        $controls['progressBar'].Value = $Value
        $controls['lblProgress'].Text = $Text
    })
}

# ── Tab switching ──
$tabNames = @('tabTakeout','tabPhotos','tabPasswords','tabEmail','tabBookmarks','tabContacts','tabConverters')
$tabBtnNames = @('btnTabTakeout','btnTabPhotos','btnTabPasswords','btnTabEmail','btnTabBookmarks','btnTabContacts','btnTabConverters')

function Switch-Tab {
    param([string]$TargetTab)
    foreach ($tab in $tabNames) {
        $controls[$tab].Visibility = if ($tab -eq $TargetTab) { 'Visible' } else { 'Collapsed' }
    }
    foreach ($btn in $tabBtnNames) {
        $idx = $tabBtnNames.IndexOf($btn)
        $isActive = ($tabNames[$idx] -eq $TargetTab)
        $controls[$btn].Background = if ($isActive) { [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0078D4') } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString('#333') }
    }
}

foreach ($btnName in $tabBtnNames) {
    $idx = $tabBtnNames.IndexOf($btnName)
    $targetTab = $tabNames[$idx]
    $controls[$btnName].Add_Click([scriptblock]::Create("Switch-Tab '$targetTab'"))
}

# ── File/Folder dialogs ──
function Get-FileDialog {
    param([string]$Filter = "All Files (*.*)|*.*", [string]$Title = "Select File", [switch]$Multi)
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = $Filter
    $dlg.Title = $Title
    $dlg.Multiselect = $Multi.IsPresent
    if ($dlg.ShowDialog()) {
        if ($Multi) { return $dlg.FileNames } else { return $dlg.FileName }
    }
    return $null
}

function Get-FolderDialog {
    param([string]$Description = "Select Folder")
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    return $null
}

function Get-SaveDialog {
    param([string]$Filter = "All Files (*.*)|*.*", [string]$Title = "Save As", [string]$DefaultName = "")
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = $Filter
    $dlg.Title = $Title
    $dlg.FileName = $DefaultName
    if ($dlg.ShowDialog()) { return $dlg.FileName }
    return $null
}

# ── Async runner ──
function Start-AsyncTask {
    param([scriptblock]$ScriptBlock, [object[]]$Arguments = @(), [scriptblock]$OnComplete)

    $ps = [PowerShell]::Create()
    $ps.AddScript($script:asyncCheckpointSource) | Out-Null
    if (Test-Path -LiteralPath $script:corePath) {
        $coreSource = [System.IO.File]::ReadAllText($script:corePath)
        $ps.AddScript($coreSource) | Out-Null
    }
    $ps.AddScript($ScriptBlock) | Out-Null
    foreach ($arg in $Arguments) { $ps.AddArgument($arg) | Out-Null }
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Tag = @{ PS = $ps; Handle = $handle; OnComplete = $OnComplete }
    $timer.Add_Tick({
        $ctx = $this.Tag
        if ($ctx.Handle.IsCompleted) {
            $this.Stop()
            try {
                $result = $ctx.PS.EndInvoke($ctx.Handle)
                $errors = $ctx.PS.Streams.Error
                $ctx.PS.Dispose()
                if ($ctx.OnComplete) { & $ctx.OnComplete $result $errors }
            } catch {
                $ctx.PS.Dispose()
                if ($ctx.OnComplete) { & $ctx.OnComplete $null $_.Exception.Message }
            }
        }
    })
    $timer.Start()
}

$controls['btnCheckForUpdate'].Add_Click({
    $controls['btnCheckForUpdate'].IsEnabled = $false
    Write-Log 'Checking GitHub Releases for a verified toolkit update...'
    Start-AsyncTask -ScriptBlock {
        param($currentVersion)
        Get-DgReleaseUpdate -CurrentVersion $currentVersion
    } -Arguments @($script:toolkitVersion) -OnComplete {
        param($update, $errors)
        $controls['btnCheckForUpdate'].IsEnabled = $true
        if ($errors -and @($errors).Count -gt 0) { Write-Log "Update check failed: $($errors[0])" 'WARN'; return }
        if (-not $update -or -not $update.UpdateAvailable) { Write-Log "Toolkit $script:toolkitVersion is up to date." 'OK'; return }
        if (-not $update.VerifiedBundleAvailable) { Write-Log "DeGoogler $($update.LatestVersion) is available, but no verified release bundle was published." 'WARN'; return }
        $answer = [System.Windows.MessageBox]::Show(
            "DeGoogler $($update.LatestVersion) is available with a SHA-256 manifest. Download the verified release bundle now?",
            'DeGoogler Toolkit Update',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Information)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { Write-Log 'Update download cancelled.'; return }
        $destination = Join-Path $env:LOCALAPPDATA ("DeGoogler\updates\{0}" -f $update.BundleAssetName)
        Write-Log "Downloading $($update.BundleAssetName) and verifying SHA-256..."
        Start-AsyncTask -ScriptBlock {
            param($releaseUpdate, $targetPath)
            Save-DgVerifiedReleaseBundle -Update $releaseUpdate -DestinationPath $targetPath
        } -Arguments @($update, $destination) -OnComplete {
            param($downloaded, $downloadErrors)
            if ($downloadErrors -and @($downloadErrors).Count -gt 0) { Write-Log "Verified update download failed: $($downloadErrors[0])" 'ERROR'; return }
            if ($downloaded) { Write-Log "Verified update saved to $($downloaded.Path). Extract it to install the new toolkit." 'OK' }
        }
    }
})

# ═══════════════════════════════════════════════════
# TOOL 1: Takeout Archive Extractor
# ═══════════════════════════════════════════════════

$script:takeoutFiles = @()

$controls['btnTakeoutBrowse'].Add_Click({
    $files = Get-FileDialog -Filter "ZIP Archives (*.zip;*.tgz)|*.zip;*.tgz|All Files (*.*)|*.*" -Title "Select Takeout Archives" -Multi
    if ($files) {
        $script:takeoutFiles = $files
        $controls['txtTakeoutInput'].Text = "$($files.Count) archive(s) selected"
        $controls['txtTakeoutInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        Write-Log "Selected $($files.Count) Takeout archive(s)"
    }
})

$controls['btnTakeoutOutputBrowse'].Add_Click({
    $folder = Get-FolderDialog -Description "Select output folder for extracted data"
    if ($folder) {
        $controls['txtTakeoutOutput'].Text = $folder
        $controls['txtTakeoutOutput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
    }
})

$controls['btnTakeoutRun'].Add_Click({
    if ($script:takeoutFiles.Count -eq 0) { Write-Log "No archives selected" "WARN"; return }
    $outputDir = $controls['txtTakeoutOutput'].Text
    if ($outputDir -match 'Select output') {
        $outputDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "DeGoogler_Takeout"
        $controls['txtTakeoutOutput'].Text = $outputDir
    }

    $deleteZips = $controls['chkTakeoutDeleteZips'].IsChecked
    $dryRun = $controls['chkTakeoutDryRun'].IsChecked
    $files = $script:takeoutFiles
    $checkpointPath = Get-CheckpointPath -Tool 'TakeoutExtractor' -InputPath (($files -join '|') + '|' + $outputDir)

    if ($dryRun) {
        Write-Log "[DRY RUN] Takeout Extractor - no files will be written" "WARN"
        Write-JsonLog -Tool "TakeoutExtractor" -Action "DryRun" -Message "Dry run started" -Level "INFO" -Data @{ archiveCount = $files.Count; outputDir = $outputDir }
        Write-Log "[DRY RUN] Would extract $($files.Count) archive(s) to: $outputDir"
        foreach ($file in $files) {
            $size = [math]::Round((Get-Item $file).Length / 1MB, 1)
            Write-Log "[DRY RUN]   Archive: $([System.IO.Path]::GetFileName($file)) (${size} MB)"
        }
        if ($deleteZips) { Write-Log "[DRY RUN] Would DELETE original ZIP files after extraction" "WARN" }
        Write-Log "[DRY RUN] Dry run complete. No files were modified." "OK"
        Set-Progress 100 "Dry Run Complete"
        return
    }

    Write-Log "Starting extraction of $($files.Count) archive(s)..."
    Write-JsonLog -Tool "TakeoutExtractor" -Action "Start" -Message "Extraction started" -Level "INFO" -Data @{ archiveCount = $files.Count; outputDir = $outputDir }
    Set-Progress 0 "Extracting..."

    $controls['btnTakeoutRun'].IsEnabled = $false

    Start-AsyncTask -ScriptBlock {
        param($files, $outputDir, $deleteZips, $checkpointPath)
        if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
        $checkpoint = Read-DgAsyncCheckpoint $checkpointPath
        $results = @()
        for ($i = 0; $i -lt $files.Count; $i++) {
            $file = $files[$i]
            $fileKey = [System.IO.Path]::GetFullPath($file)
            if (Test-DgAsyncCheckpointDone $checkpoint $fileKey) {
                $results += "SKIP: $([System.IO.Path]::GetFileName($file)) (checkpoint)"
                continue
            }
            $tempDir = Join-Path $env:TEMP ("degoogler_extract_" + [guid]::NewGuid().ToString('N'))
            try {
                Expand-Archive -Path $file -DestinationPath $tempDir -Force
                # Organize by subfolder names (Takeout/service_name/...)
                $takeoutRoot = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -eq 'Takeout' } | Select-Object -First 1
                if (-not $takeoutRoot) { $takeoutRoot = Get-Item $tempDir }
                $serviceDirs = Get-ChildItem -Path $takeoutRoot.FullName -Directory
                foreach ($svcDir in $serviceDirs) {
                    $destDir = Join-Path $outputDir $svcDir.Name
                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    Get-ChildItem -Path $svcDir.FullName -Recurse | ForEach-Object {
                        $relPath = $_.FullName.Substring($svcDir.FullName.Length)
                        $destPath = Join-Path $destDir $relPath
                        if ($_.PSIsContainer) {
                            New-Item -ItemType Directory -Path $destPath -Force -ErrorAction SilentlyContinue | Out-Null
                        } else {
                            $parentDir = Split-Path $destPath
                            if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
                            Copy-Item $_.FullName $destPath -Force
                        }
                    }
                    $results += $svcDir.Name
                }
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                if ($deleteZips) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
                Set-DgAsyncCheckpointDone $checkpoint $fileKey
                Write-DgAsyncCheckpoint $checkpointPath $checkpoint
            } catch {
                $results += "ERROR: $($_.Exception.Message)"
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        return $results
    } -Arguments @(,$files), $outputDir, $deleteZips, $checkpointPath -OnComplete {
        param($result, $errors)
        $controls['btnTakeoutRun'].IsEnabled = $true
        Set-Progress 100 "Done"
        if ($errors) {
            foreach ($e in $errors) { Write-Log "Error: $e" "ERROR" }
        }
        if ($result) {
            $services = $result | Where-Object { $_ -notmatch '^ERROR' } | Select-Object -Unique
            Write-Log "Extraction complete. Found services: $($services -join ', ')" "OK"
            Write-Log "Output folder: $($controls['txtTakeoutOutput'].Text)" "OK"
            Write-JsonLog -Tool "TakeoutExtractor" -Action "Complete" -Message "Extraction finished" -Level "OK" -Data @{ services = ($services -join ',') }
        }
        # Open output folder
        $outPath = $controls['txtTakeoutOutput'].Text
        if (Test-Path $outPath) { Start-Process explorer.exe $outPath }
    }
})

# ═══════════════════════════════════════════════════
# TOOL 2: Google Photos Metadata Restorer
# ═══════════════════════════════════════════════════

$controls['btnPhotosBrowse'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Google Photos Takeout folder"
    if ($folder) {
        $controls['txtPhotosInput'].Text = $folder
        $controls['txtPhotosInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        $photoCount = (Get-ChildItem -Path $folder -Recurse -Include *.jpg,*.jpeg,*.png,*.gif,*.mp4,*.mov,*.heic -ErrorAction SilentlyContinue).Count
        $jsonCount = (Get-ChildItem -Path $folder -Recurse -Filter "*.json" -ErrorAction SilentlyContinue).Count
        Write-Log "Found $photoCount media files and $jsonCount JSON sidecar files"
    }
})

# Check exiftool availability
$window.Add_Loaded({
    $exifPath = Install-ExifTool
    if ($exifPath -and (Test-Path $exifPath)) {
        $controls['lblPhotosExiftool'].Text = "ExifTool: Installed ($exifPath)"
        $controls['lblPhotosExiftool'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4ade80')
    } else {
        $controls['lblPhotosExiftool'].Text = "ExifTool: Will attempt auto-download, or install manually from exiftool.org"
        $controls['lblPhotosExiftool'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#f59e0b')
    }
})

$controls['btnPhotosRun'].Add_Click({
    $photosDir = $controls['txtPhotosInput'].Text
    if ($photosDir -match 'Select Google Photos' -or -not (Test-Path $photosDir)) {
        Write-Log "No photos folder selected" "WARN"; return
    }

    $deleteJson = $controls['chkPhotosDeleteJson'].IsChecked
    $fixDates = $controls['chkPhotosFixDates'].IsChecked
    $recursive = $controls['chkPhotosRecursive'].IsChecked
    $dryRun = $controls['chkPhotosDryRun'].IsChecked
    $checkpointPath = Get-CheckpointPath -Tool 'PhotosMetadata' -InputPath $photosDir

    if ($dryRun) {
        Write-Log "[DRY RUN] Photos Metadata Restorer - no files will be modified" "WARN"
        $searchOpt = if ($recursive) { 'AllDirectories' } else { 'TopDirectoryOnly' }
        $extensions = @('*.jpg','*.jpeg','*.png','*.gif','*.mp4','*.mov','*.heic','*.webp','*.tiff','*.bmp')
        $mediaCount = (Get-ChildItem -Path $photosDir -Recurse:$recursive -Include $extensions -ErrorAction SilentlyContinue).Count
        $jsonCount = (Get-ChildItem -Path $photosDir -Recurse:$recursive -Filter "*.json" -ErrorAction SilentlyContinue).Count
        Write-Log "[DRY RUN] Would process $mediaCount media files with $jsonCount JSON sidecars"
        Write-Log "[DRY RUN] Source folder: $photosDir"
        Write-Log "[DRY RUN] Fix dates: $fixDates | Delete JSON: $deleteJson | Recursive: $recursive"
        $exifPath = Join-Path $env:LOCALAPPDATA "DeGoogler\exiftool.exe"
        if (Test-ExifToolLayout $exifPath) {
            Write-Log "[DRY RUN] ExifTool found - would write EXIF metadata directly"
        } else {
            Write-Log "[DRY RUN] ExifTool not found - would write XMP sidecars and fix file system dates"
        }
        if ($deleteJson) { Write-Log "[DRY RUN] Would DELETE $jsonCount JSON sidecar files after merging" "WARN" }
        Write-Log "[DRY RUN] Dry run complete. No files were modified." "OK"
        Write-JsonLog -Tool "PhotosMetadata" -Action "DryRun" -Message "Dry run" -Level "INFO" -Data @{ mediaCount = $mediaCount; jsonCount = $jsonCount }
        Set-Progress 100 "Dry Run Complete"
        return
    }

    Write-Log "Starting photo metadata restoration..."
    Write-JsonLog -Tool "PhotosMetadata" -Action "Start" -Message "Processing started" -Level "INFO" -Data @{ photosDir = $photosDir }
    Set-Progress 0 "Processing photos..."
    $controls['btnPhotosRun'].IsEnabled = $false

    Start-AsyncTask -ScriptBlock {
        param($photosDir, $deleteJson, $fixDates, $recursive, $checkpointPath)
        $exifPath = Join-Path $env:LOCALAPPDATA "DeGoogler\exiftool.exe"
        $useExif = (Test-Path -LiteralPath $exifPath) -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $exifPath) 'exiftool_files'))
        $checkpoint = Read-DgAsyncCheckpoint $checkpointPath

        $searchOpt = if ($recursive) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
        $extensions = @('.jpg','.jpeg','.png','.gif','.mp4','.mov','.heic','.webp','.tiff','.bmp')
        $allFiles = @([System.IO.Directory]::GetFiles($photosDir, "*.*", $searchOpt) |
            Where-Object { $extensions -contains [System.IO.Path]::GetExtension($_).ToLower() })
        $allJsonFiles = @(Get-ChildItem -Path $photosDir -Recurse:$recursive -Filter '*.json' -File -ErrorAction SilentlyContinue)

        $processed = 0; $fixed = 0; $failed = 0; $xmpCount = 0; $total = $allFiles.Count
        $dateSources = @{ EXIF = 0; JSON = 0; Picasa = 0; Filename = 0; MTime = 0 }
        $burstCandidates = New-Object System.Collections.Generic.List[object]

        function Get-DgExifDate {
            param([string]$Path)
            if (-not $useExif) { return $null }
            try {
                $values = @(& $exifPath '-s3' '-DateTimeOriginal' '-CreateDate' '-ModifyDate' $Path 2>$null)
                foreach ($value in $values) {
                    $parsed = ConvertTo-DgDateTimeOffset ([string]$value)
                    if ($parsed) { return $parsed }
                }
            } catch {}
            return $null
        }

        foreach ($mediaFile in $allFiles) {
            $fileKey = [System.IO.Path]::GetFullPath($mediaFile)
            if (Test-DgAsyncCheckpointDone $checkpoint $fileKey) { continue }
            $processed++

            try {
                $jsonFile = Find-DgPhotoMetadataFile -MediaPath $mediaFile -JsonFiles $allJsonFiles
                $json = $null
                if ($jsonFile) {
                    try { $json = Get-Content -LiteralPath $jsonFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }
                }

                $exifDate = Get-DgExifDate $mediaFile
                $jsonDate = $null
                $picasa = Get-DgPicasaMetadata $mediaFile
                $filenameDate = Get-DgFilenameDate $mediaFile
                $mtimeDate = [DateTimeOffset]::new([System.IO.File]::GetLastWriteTimeUtc($mediaFile))
                if ($json) {
                    $jsonTime = Get-DgProperty (Get-DgProperty $json 'photoTakenTime') 'timestamp'
                    if (-not $jsonTime) { $jsonTime = Get-DgProperty (Get-DgProperty $json 'creationTime') 'timestamp' }
                    $jsonDate = ConvertTo-DgDateTimeOffset $jsonTime
                }
                $photoTaken = $exifDate
                $dateSource = 'EXIF'
                if (-not $photoTaken) { $photoTaken = $jsonDate; $dateSource = 'JSON' }
                if (-not $photoTaken -and $picasa) { $photoTaken = $picasa.Date; $dateSource = 'Picasa' }
                if (-not $photoTaken) { $photoTaken = $filenameDate; $dateSource = 'Filename' }
                if (-not $photoTaken) { $photoTaken = $mtimeDate; $dateSource = 'MTime' }
                $dateSources[$dateSource]++
                $burstKey = Get-DgBurstKey -MediaPath $mediaFile -Date $photoTaken
                if ($burstKey) { $burstCandidates.Add([pscustomobject]@{ Key = $burstKey; Path = $mediaFile }) }

                $geoLat = $null; $geoLon = $null; $desc = $null
                if ($json) {
                    $geo = Get-DgProperty $json 'geoData'
                    if (-not $geo) { $geo = Get-DgProperty $json 'geoDataExif' }
                    if ($geo -and (Get-DgProperty $geo 'latitude') -ne $null -and (Get-DgProperty $geo 'latitude') -ne 0) {
                        $geoLat = ConvertTo-DgDouble (Get-DgProperty $geo 'latitude')
                        $geoLon = ConvertTo-DgDouble (Get-DgProperty $geo 'longitude')
                    }
                    $desc = [string](Get-DgProperty $json 'description')
                }
                if ($null -eq $geoLat -and $picasa) { $geoLat = $picasa.Latitude; $geoLon = $picasa.Longitude }
                if ([string]::IsNullOrWhiteSpace($desc) -and $picasa) { $desc = $picasa.Caption }

                $metadataApplied = $false
                $exifApplied = $false
                $extension = [System.IO.Path]::GetExtension($mediaFile).ToLowerInvariant()
                if ($useExif -and ($photoTaken -or $geoLat -ne $null -or $desc)) {
                    $exifArgs = @('-overwrite_original')
                    if ($photoTaken) {
                        $dateStr = $photoTaken.ToString('yyyy:MM:dd HH:mm:ss')
                        $exifArgs += "-DateTimeOriginal=`"$dateStr`"", "-CreateDate=`"$dateStr`"", "-ModifyDate=`"$dateStr`""
                    }
                    if ($geoLat -ne $null -and $geoLon -ne $null) {
                        $latRef = if ($geoLat -ge 0) { "N" } else { "S" }
                        $lonRef = if ($geoLon -ge 0) { "E" } else { "W" }
                        $exifArgs += "-GPSLatitude=$([Math]::Abs($geoLat))", "-GPSLatitudeRef=$latRef"
                        $exifArgs += "-GPSLongitude=$([Math]::Abs($geoLon))", "-GPSLongitudeRef=$lonRef"
                    }
                    if ($desc) { $exifArgs += "-ImageDescription=`"$desc`"" }
                    $exifArgs += "`"$mediaFile`""
                    & $exifPath @exifArgs 2>$null | Out-Null
                    $exifApplied = ($LASTEXITCODE -eq 0)
                    $metadataApplied = $exifApplied
                }
                if ($fixDates -and $photoTaken) {
                    [System.IO.File]::SetCreationTime($mediaFile, $photoTaken)
                    [System.IO.File]::SetLastWriteTime($mediaFile, $photoTaken)
                    $metadataApplied = $true
                }
                $xmpPreferred = $extension -in @('.png','.heic','.webp')
                if ((-not $exifApplied -or $xmpPreferred) -and ($photoTaken -or $geoLat -ne $null -or $desc)) {
                    $xmpPath = Write-DgXmpSidecar -MediaPath $mediaFile -Date $photoTaken -Latitude $geoLat -Longitude $geoLon -Description $desc
                    if ($xmpPath) { $xmpCount++; $metadataApplied = $true }
                }
                if ($metadataApplied) { $fixed++ }

                if ($deleteJson -and $jsonFile) {
                    Remove-Item -LiteralPath $jsonFile -Force -ErrorAction SilentlyContinue
                }
                Set-DgAsyncCheckpointDone $checkpoint $fileKey
                Write-DgAsyncCheckpoint $checkpointPath $checkpoint
            } catch {
                $failed++
            }
        }
        $burstGroups = @($burstCandidates | Group-Object Key | Where-Object { $_.Count -gt 1 })
        return @{ Total = $total; Fixed = $fixed; Failed = $failed; Xmp = $xmpCount; BurstGroups = $burstGroups.Count; DateSources = $dateSources }
    } -Arguments $photosDir, $deleteJson, $fixDates, $recursive, $checkpointPath -OnComplete {
        param($result, $errors)
        $controls['btnPhotosRun'].IsEnabled = $true
        Set-Progress 100 "Done"
        if ($errors) { foreach ($e in $errors) { Write-Log "Error: $e" "ERROR" } }
        if ($result -and $result.Count -gt 0) {
            $r = $result[0]
            Write-Log "Photo metadata restoration complete: $($r.Fixed) fixed / $($r.Total) total / $($r.Failed) failed" "OK"
            Write-Log "Wrote $($r.Xmp) XMP fallback sidecar(s); detected $($r.BurstGroups) burst group(s)." "INFO"
            Write-JsonLog -Tool "PhotosMetadata" -Action "Complete" -Message "Processing finished" -Level "OK" -Data @{ total = $r.Total; fixed = $r.Fixed; failed = $r.Failed; xmp = $r.Xmp; burstGroups = $r.BurstGroups; dateSources = $r.DateSources }
        }
    }
})

# ═══════════════════════════════════════════════════
# TOOL 3: Chrome Password Converter
# ═══════════════════════════════════════════════════

$controls['btnPasswordsBrowse'].Add_Click({
    $file = Get-FileDialog -Filter "CSV Files (*.csv)|*.csv" -Title "Select Chrome Passwords CSV"
    if ($file) {
        $controls['txtPasswordsInput'].Text = $file
        $controls['txtPasswordsInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        $lineCount = (Get-Content $file | Measure-Object -Line).Lines - 1
        Write-Log "Loaded password CSV with ~$lineCount entries"
    }
})

$controls['btnPasswordsRun'].Add_Click({
    $inputFile = $controls['txtPasswordsInput'].Text
    if ($inputFile -match 'Select Chrome' -or -not (Test-Path $inputFile)) {
        Write-Log "No password CSV selected" "WARN"; return
    }

    $formatIdx = $controls['cmbPasswordsFormat'].SelectedIndex
    $secureDelete = $controls['chkPasswordsSecureDelete'].IsChecked
    $dryRun = $controls['chkPasswordsDryRun'].IsChecked

    $formatName = switch ($formatIdx) { 0 { "Bitwarden" } 1 { "KeePass" } 2 { "1Password" } 3 { "ProtonPass" } default { "Bitwarden" } }

    if ($dryRun) {
        Write-Log "[DRY RUN] Password Converter - no files will be written" "WARN"
        $rows = Import-Csv $inputFile
        Write-Log "[DRY RUN] Source: $([System.IO.Path]::GetFileName($inputFile)) ($($rows.Count) entries)"
        Write-Log "[DRY RUN] Target format: $formatName"
        Write-Log "[DRY RUN] Would convert $($rows.Count) passwords to $formatName CSV"
        if ($secureDelete) { Write-Log "[DRY RUN] Would SECURELY DELETE source CSV after conversion" "WARN" }
        Write-Log "[DRY RUN] Dry run complete. No files were modified." "OK"
        Write-JsonLog -Tool "PasswordConverter" -Action "DryRun" -Message "Dry run" -Level "INFO" -Data @{ entryCount = $rows.Count; format = $formatName }
        Set-Progress 100 "Dry Run Complete"
        return
    }

    $savePath = Get-SaveDialog -Filter "CSV Files (*.csv)|*.csv" -Title "Save $formatName CSV" -DefaultName "${formatName}_import.csv"
    if (-not $savePath) { return }

    Write-Log "Converting to $formatName format..."
    Write-JsonLog -Tool "PasswordConverter" -Action "Start" -Message "Conversion started" -Level "INFO" -Data @{ format = $formatName }
    Set-Progress 0 "Converting..."

    try {
        $rows = Import-Csv $inputFile
        $output = @()

        foreach ($row in $rows) {
            # Chrome CSV columns: name, url, username, password, note (varies by version)
            $name = if ($row.name) { $row.name } elseif ($row.origin_url) { $row.origin_url } else { "" }
            $url = if ($row.url) { $row.url } elseif ($row.origin_url) { $row.origin_url } else { "" }
            $user = if ($row.username) { $row.username } else { "" }
            $pass = if ($row.password) { $row.password } else { "" }
            $note = if ($row.note) { $row.note } else { "" }

            switch ($formatIdx) {
                0 { # Bitwarden
                    $output += [PSCustomObject]@{
                        folder = ""; favorite = ""; type = "login"; name = $name; notes = $note
                        fields = ""; reprompt = ""; login_uri = $url; login_username = $user; login_password = $pass; login_totp = ""
                    }
                }
                1 { # KeePass
                    $output += [PSCustomObject]@{
                        Group = "Chrome Import"; Title = $name; Username = $user; Password = $pass; URL = $url; Notes = $note
                    }
                }
                2 { # 1Password
                    $output += [PSCustomObject]@{
                        Title = $name; Website = $url; Username = $user; Password = $pass; Notes = $note; Type = "Login"
                    }
                }
                3 { # Proton Pass
                    $output += [PSCustomObject]@{
                        name = $name; url = $url; username = $user; password = $pass; note = $note; totp = ""
                    }
                }
            }
        }

        $output | Export-Csv -Path $savePath -NoTypeInformation -Encoding UTF8
        Write-Log "Converted $($rows.Count) passwords to $formatName format" "OK"
        Write-Log "Saved to: $savePath" "OK"
        Write-JsonLog -Tool "PasswordConverter" -Action "Complete" -Message "Conversion finished" -Level "OK" -Data @{ count = $rows.Count; format = $formatName }

        if ($secureDelete) {
            $bytes = [System.IO.File]::ReadAllBytes($inputFile)
            $random = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
            $random.GetBytes($bytes)
            [System.IO.File]::WriteAllBytes($inputFile, $bytes)
            $random.GetBytes($bytes)
            [System.IO.File]::WriteAllBytes($inputFile, $bytes)
            Remove-Item $inputFile -Force
            Write-Log "Source CSV securely overwritten and deleted" "OK"
            Write-JsonLog -Tool "PasswordConverter" -Action "SecureDelete" -Message "Source CSV deleted" -Level "OK"
        }

        Set-Progress 100 "Done"
    } catch {
        Write-Log "Error converting passwords: $_" "ERROR"
        Write-JsonLog -Tool "PasswordConverter" -Action "Error" -Message "$_" -Level "ERROR"
        Set-Progress 0 ""
    }
})

# ═══════════════════════════════════════════════════
# TOOL 4: Gmail MBOX Processor
# ═══════════════════════════════════════════════════

$controls['btnEmailBrowse'].Add_Click({
    $file = Get-FileDialog -Filter "MBOX Files (*.mbox)|*.mbox|All Files (*.*)|*.*" -Title "Select Gmail MBOX File"
    if ($file) {
        $controls['txtEmailInput'].Text = $file
        $controls['txtEmailInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        $size = [math]::Round((Get-Item $file).Length / 1MB, 1)
        Write-Log "Selected MBOX file: ${size}MB"
    }
})

$controls['btnEmailOutputBrowse'].Add_Click({
    $folder = Get-FolderDialog -Description "Select output folder for EML files"
    if ($folder) {
        $controls['txtEmailOutput'].Text = $folder
        $controls['txtEmailOutput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
    }
})

$controls['btnEmailRun'].Add_Click({
    $inputFile = $controls['txtEmailInput'].Text
    if ($inputFile -match 'Select MBOX' -or -not (Test-Path $inputFile)) {
        Write-Log "No MBOX file selected" "WARN"; return
    }

    $outputDir = $controls['txtEmailOutput'].Text
    if ($outputDir -match 'Select output') {
        $outputDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "DeGoogler_Emails"
        $controls['txtEmailOutput'].Text = $outputDir
    }
    if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

    $preserveLabels = $controls['chkEmailPreserveLabels'].IsChecked
    $dryRun = $controls['chkEmailDryRun'].IsChecked
    $checkpointPath = Get-CheckpointPath -Tool 'MboxProcessor' -InputPath ($inputFile + '|' + $outputDir)

    if ($dryRun) {
        Write-Log "[DRY RUN] Email MBOX Processor - no files will be written" "WARN"
        $size = [math]::Round((Get-Item $inputFile).Length / 1MB, 1)
        Write-Log "[DRY RUN] Source: $([System.IO.Path]::GetFileName($inputFile)) (${size} MB)"
        Write-Log "[DRY RUN] Output folder: $outputDir"
        Write-Log "[DRY RUN] Preserve labels as subfolders: $preserveLabels"
        # Quick scan to count emails
        $fromCount = (Select-String -Path $inputFile -Pattern '^From ' -SimpleMatch | Measure-Object).Count
        Write-Log "[DRY RUN] Would extract ~$fromCount emails to individual EML files"
        Write-Log "[DRY RUN] Dry run complete. No files were modified." "OK"
        Write-JsonLog -Tool "MboxProcessor" -Action "DryRun" -Message "Dry run" -Level "INFO" -Data @{ emailCount = $fromCount; sizeMB = $size }
        Set-Progress 100 "Dry Run Complete"
        return
    }

    Write-Log "Processing MBOX file..."
    Write-JsonLog -Tool "MboxProcessor" -Action "Start" -Message "Processing started" -Level "INFO" -Data @{ inputFile = $inputFile }
    Set-Progress 0 "Processing..."
    $controls['btnEmailRun'].IsEnabled = $false

    Start-AsyncTask -ScriptBlock {
        param($inputFile, $outputDir, $preserveLabels, $checkpointPath)
        $checkpoint = Read-DgAsyncCheckpoint $checkpointPath
        $reader = [System.IO.StreamReader]::new($inputFile, [System.Text.Encoding]::UTF8)
        $emailCount = 0
        $currentEmail = New-Object System.Text.StringBuilder
        $currentLabel = "Inbox"
        $inEmail = $false

        function Save-DgMboxMessage {
            param([string]$RawMessage, [string]$Label, [int]$Number)
            $key = "message:$Number"
            $safeLabel = if ($preserveLabels -and $Label) { $Label -replace '[\\/:*?"<>|]', '_' } else { '' }
            $targetDir = if ($safeLabel) { Join-Path $outputDir $safeLabel } else { $outputDir }
            if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
            $emlPath = Join-Path $targetDir "email_$($Number.ToString('D6')).eml"
            if (-not (Test-DgAsyncCheckpointDone $checkpoint $key) -and -not (Test-Path -LiteralPath $emlPath)) {
                [System.IO.File]::WriteAllText($emlPath, $RawMessage, [System.Text.Encoding]::UTF8)
            }
            Set-DgAsyncCheckpointDone $checkpoint $key
            Write-DgAsyncCheckpoint $checkpointPath $checkpoint
        }

        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -match '^From ') {
                # Save previous email
                if ($inEmail -and $currentEmail.Length -gt 0) {
                    $emailCount++
                    Save-DgMboxMessage -RawMessage $currentEmail.ToString() -Label $currentLabel -Number $emailCount
                }
                $currentEmail = New-Object System.Text.StringBuilder
                $currentLabel = "Inbox"
                $inEmail = $true
            } else {
                if ($inEmail) {
                    # Extract Gmail label from X-Gmail-Labels header
                    if ($line -match '^X-Gmail-Labels:\s*(.+)') {
                        $labels = $Matches[1] -split ','
                        $currentLabel = ($labels | Select-Object -First 1).Trim()
                    }
                    $currentEmail.AppendLine($line) | Out-Null
                }
            }
        }
        # Save last email
        if ($inEmail -and $currentEmail.Length -gt 0) {
            $emailCount++
            Save-DgMboxMessage -RawMessage $currentEmail.ToString() -Label $currentLabel -Number $emailCount
        }
        $reader.Close()
        $reader.Dispose()
        return @{ Count = $emailCount }
    } -Arguments $inputFile, $outputDir, $preserveLabels, $checkpointPath -OnComplete {
        param($result, $errors)
        $controls['btnEmailRun'].IsEnabled = $true
        Set-Progress 100 "Done"
        if ($errors) { foreach ($e in $errors) { Write-Log "Error: $e" "ERROR" } }
        if ($result -and $result.Count -gt 0) {
            Write-Log "MBOX processing complete: $($result[0].Count) emails extracted" "OK"
            Write-Log "Output: $($controls['txtEmailOutput'].Text)" "OK"
            $outPath = $controls['txtEmailOutput'].Text
            if (Test-Path $outPath) { Start-Process explorer.exe $outPath }
        }
    }
})

# ═══════════════════════════════════════════════════
# TOOL 5: Chrome Bookmark Converter
# ═══════════════════════════════════════════════════

$controls['btnBookmarksBrowse'].Add_Click({
    $file = Get-FileDialog -Filter "Bookmark Files (*.json;*.html)|*.json;*.html|All Files (*.*)|*.*" -Title "Select Chrome Bookmarks File"
    if ($file) {
        $controls['txtBookmarksInput'].Text = $file
        $controls['txtBookmarksInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        Write-Log "Selected bookmarks file: $([System.IO.Path]::GetFileName($file))"
    }
})

$controls['btnBookmarksDetect'].Add_Click({
    $chromePath = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Bookmarks"
    if (Test-Path $chromePath) {
        $controls['txtBookmarksInput'].Text = $chromePath
        $controls['txtBookmarksInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        Write-Log "Auto-detected Chrome bookmarks file" "OK"
    } else {
        # Try other Chromium browsers
        $paths = @(
            (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Profile 1\Bookmarks"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Bookmarks"),
            (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\Default\Bookmarks")
        )
        $found = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) {
            $controls['txtBookmarksInput'].Text = $found
            $controls['txtBookmarksInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
            Write-Log "Auto-detected browser bookmarks: $([System.IO.Path]::GetFileName((Split-Path $found -Parent)))" "OK"
        } else {
            Write-Log "Could not auto-detect bookmarks file" "WARN"
        }
    }
})

$controls['btnBookmarksRun'].Add_Click({
    $inputFile = $controls['txtBookmarksInput'].Text
    if ($inputFile -match 'Select bookmarks' -or -not (Test-Path $inputFile)) {
        Write-Log "No bookmarks file selected" "WARN"; return
    }

    $dryRun = $controls['chkBookmarksDryRun'].IsChecked

    if ($dryRun) {
        Write-Log "[DRY RUN] Bookmark Converter - no files will be written" "WARN"
        $content = Get-Content $inputFile -Raw
        $isJson = $content.TrimStart().StartsWith('{')
        Write-Log "[DRY RUN] Source: $([System.IO.Path]::GetFileName($inputFile))"
        Write-Log "[DRY RUN] Format detected: $(if ($isJson) { 'Chrome JSON' } else { 'HTML (already Netscape format)' })"
        if ($isJson) {
            $json = $content | ConvertFrom-Json
            $bookmarkCount = 0
            function Count-BookmarkNodes($node) {
                if ($node.type -eq 'url') { $script:bmCount++ }
                if ($node.children) { foreach ($c in $node.children) { Count-BookmarkNodes $c } }
            }
            $script:bmCount = 0
            @($json.roots.bookmark_bar, $json.roots.other, $json.roots.synced) | Where-Object { $_ -and $_.children } | ForEach-Object { Count-BookmarkNodes $_ }
            Write-Log "[DRY RUN] Would convert $($script:bmCount) bookmarks to Netscape HTML format"
        } else {
            Write-Log "[DRY RUN] File is already HTML - would copy as-is"
        }
        Write-Log "[DRY RUN] Dry run complete. No files were modified." "OK"
        Write-JsonLog -Tool "BookmarkConverter" -Action "DryRun" -Message "Dry run" -Level "INFO"
        Set-Progress 100 "Dry Run Complete"
        return
    }

    $savePath = Get-SaveDialog -Filter "HTML Bookmark File (*.html)|*.html" -Title "Save Bookmarks HTML" -DefaultName "bookmarks_export.html"
    if (-not $savePath) { return }

    Write-Log "Converting bookmarks..."
    Write-JsonLog -Tool "BookmarkConverter" -Action "Start" -Message "Conversion started" -Level "INFO"

    try {
        $content = Get-Content $inputFile -Raw

        if ($content.TrimStart().StartsWith('{')) {
            # Chrome JSON format
            $json = $content | ConvertFrom-Json
            $sb = New-Object System.Text.StringBuilder
            $sb.AppendLine('<!DOCTYPE NETSCAPE-Bookmark-file-1>') | Out-Null
            $sb.AppendLine('<!-- DeGoogler Toolkit - Bookmark Export -->') | Out-Null
            $sb.AppendLine('<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">') | Out-Null
            $sb.AppendLine('<TITLE>Bookmarks</TITLE>') | Out-Null
            $sb.AppendLine('<H1>Bookmarks</H1>') | Out-Null
            $sb.AppendLine('<DL><p>') | Out-Null

            function Convert-BookmarkNode {
                param($node, [System.Text.StringBuilder]$sb, [int]$depth = 1)
                $indent = "    " * $depth
                if ($node.type -eq 'folder') {
                    $sb.AppendLine("$indent<DT><H3>$($node.name)</H3>") | Out-Null
                    $sb.AppendLine("$indent<DL><p>") | Out-Null
                    if ($node.children) {
                        foreach ($child in $node.children) {
                            Convert-BookmarkNode -node $child -sb $sb -depth ($depth + 1)
                        }
                    }
                    $sb.AppendLine("$indent</DL><p>") | Out-Null
                } elseif ($node.type -eq 'url') {
                    $addDate = ""
                    if ($node.date_added) {
                        try {
                            $epoch = [long]$node.date_added / 1000000 - 11644473600
                            $addDate = " ADD_DATE=`"$epoch`""
                        } catch {}
                    }
                    $url = [System.Web.HttpUtility]::HtmlEncode($node.url)
                    $name = [System.Web.HttpUtility]::HtmlEncode($node.name)
                    $sb.AppendLine("$indent<DT><A HREF=`"$url`"$addDate>$name</A>") | Out-Null
                }
            }

            $roots = @($json.roots.bookmark_bar, $json.roots.other, $json.roots.synced)
            foreach ($root in $roots) {
                if ($root -and $root.children) {
                    Convert-BookmarkNode -node $root -sb $sb -depth 1
                }
            }
            $sb.AppendLine('</DL><p>') | Out-Null

            [System.IO.File]::WriteAllText($savePath, $sb.ToString(), [System.Text.Encoding]::UTF8)
            $bookmarkCount = ($sb.ToString() | Select-String -Pattern '<DT><A HREF' -AllMatches).Matches.Count
            Write-Log "Converted $bookmarkCount bookmarks to Netscape HTML format" "OK"
        } else {
            # Already HTML - just copy
            Copy-Item $inputFile $savePath -Force
            Write-Log "Bookmarks file was already in HTML format - copied as-is" "OK"
        }
        Write-Log "Saved to: $savePath" "OK"
        Set-Progress 100 "Done"
    } catch {
        Write-Log "Error converting bookmarks: $_" "ERROR"
    }
})

# ═══════════════════════════════════════════════════
# TOOL 6: Google Contacts Processor
# ═══════════════════════════════════════════════════

$controls['btnContactsBrowse'].Add_Click({
    $file = Get-FileDialog -Filter "vCard Files (*.vcf)|*.vcf|All Files (*.*)|*.*" -Title "Select Google Contacts VCF"
    if ($file) {
        $controls['txtContactsInput'].Text = $file
        $controls['txtContactsInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        $vcardCount = (Get-Content $file | Select-String -Pattern '^BEGIN:VCARD' -AllMatches).Count
        Write-Log "Loaded contacts file with $vcardCount entries"
    }
})

$controls['btnContactsRun'].Add_Click({
    $inputFile = $controls['txtContactsInput'].Text
    if ($inputFile -match 'Select contacts' -or -not (Test-Path $inputFile)) {
        Write-Log "No contacts file selected" "WARN"; return
    }

    $dedup = $controls['chkContactsDedup'].IsChecked
    $clean = $controls['chkContactsClean'].IsChecked
    $dryRun = $controls['chkContactsDryRun'].IsChecked

    if ($dryRun) {
        Write-Log "[DRY RUN] Contacts Processor - no files will be written" "WARN"
        $vcardCount = (Get-Content $inputFile | Select-String -Pattern '^BEGIN:VCARD' -AllMatches).Count
        Write-Log "[DRY RUN] Source: $([System.IO.Path]::GetFileName($inputFile)) ($vcardCount contacts)"
        Write-Log "[DRY RUN] Deduplication: $dedup | Clean formatting: $clean"
        Write-Log "[DRY RUN] Would process $vcardCount contacts"
        Write-Log "[DRY RUN] Dry run complete. No files were modified." "OK"
        Write-JsonLog -Tool "ContactsProcessor" -Action "DryRun" -Message "Dry run" -Level "INFO" -Data @{ contactCount = $vcardCount }
        Set-Progress 100 "Dry Run Complete"
        return
    }

    $savePath = Get-SaveDialog -Filter "vCard Files (*.vcf)|*.vcf" -Title "Save Processed Contacts" -DefaultName "contacts_cleaned.vcf"
    if (-not $savePath) { return }

    Write-Log "Processing contacts..."
    Write-JsonLog -Tool "ContactsProcessor" -Action "Start" -Message "Processing started" -Level "INFO"
    Set-Progress 0 "Processing..."

    try {
        $content = Get-Content $inputFile -Raw -Encoding UTF8
        $vcards = @()
        $current = New-Object System.Text.StringBuilder
        $inCard = $false

        foreach ($line in ($content -split "`r?`n")) {
            if ($line -match '^BEGIN:VCARD') {
                $current = New-Object System.Text.StringBuilder
                $current.AppendLine($line) | Out-Null
                $inCard = $true
            } elseif ($line -match '^END:VCARD' -and $inCard) {
                $current.AppendLine($line) | Out-Null
                $vcards += $current.ToString()
                $inCard = $false
            } elseif ($inCard) {
                $processedLine = $line
                if ($clean) {
                    # Standardize phone numbers - remove extra spaces/dashes
                    if ($processedLine -match '^TEL') {
                        $processedLine = $processedLine -replace '\s{2,}', ' '
                        $processedLine = $processedLine -replace '(\d)\s+(\d)', '$1$2' -replace '\.', '-'
                    }
                    # Fix encoded characters
                    $processedLine = $processedLine -replace '=0D=0A', ''
                }
                $current.AppendLine($processedLine) | Out-Null
            }
        }

        $originalCount = $vcards.Count

        if ($dedup) {
            # Deduplicate by FN (full name) + first email
            $seen = @{}
            $unique = @()
            foreach ($vcard in $vcards) {
                $fn = ""; $email = ""
                foreach ($l in ($vcard -split "`r?`n")) {
                    if ($l -match '^FN[;:](.+)') { $fn = $Matches[1].Trim().ToLower() }
                    if ($l -match '^EMAIL[;:](.+)' -and -not $email) { $email = $Matches[1].Trim().ToLower() }
                }
                $key = "$fn|$email"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $unique += $vcard
                }
            }
            $vcards = $unique
        }

        $output = $vcards -join ""
        [System.IO.File]::WriteAllText($savePath, $output, [System.Text.Encoding]::UTF8)

        $dupsRemoved = $originalCount - $vcards.Count
        Write-Log "Contacts processed: $($vcards.Count) contacts saved" "OK"
        if ($dedup -and $dupsRemoved -gt 0) {
            Write-Log "Removed $dupsRemoved duplicate entries" "OK"
        }
        Write-Log "Saved to: $savePath" "OK"
        Set-Progress 100 "Done"
    } catch {
        Write-Log "Error processing contacts: $_" "ERROR"
    }
})

# ═══════════════════════════════════════════════════
# TOOL 7: Takeout Export Converters
# ═══════════════════════════════════════════════════

function Get-ConverterDefinition {
    param([int]$Index)
    switch ($Index) {
        0 { return @{ Name = 'Convert-DgKeepTakeout'; Label = 'Keep to Markdown'; Extensions = @('.json') } }
        1 { return @{ Name = 'Convert-DgFitTakeout'; Label = 'Fit to Apple Health XML / TCX'; Extensions = @('.json') } }
        2 { return @{ Name = 'Convert-DgMapsSavedPlaces'; Label = 'Maps saved places to GeoJSON / GPX / KML'; Extensions = @('.json','.csv') } }
        3 { return @{ Name = 'Convert-DgChatMbox'; Label = 'Chat or Hangouts MBOX to JSON'; Extensions = @('.mbox','.mbx','.txt') } }
        default { return @{ Name = 'Convert-DgKeepTakeout'; Label = 'Keep to Markdown'; Extensions = @('.json') } }
    }
}

$controls['btnConvertersBrowse'].Add_Click({
    $definition = Get-ConverterDefinition $controls['cmbConvertersType'].SelectedIndex
    $selection = $null
    if ($controls['cmbConvertersType'].SelectedIndex -eq 0 -or $controls['cmbConvertersType'].SelectedIndex -eq 2) {
        $selection = Get-FolderDialog -Description ("Select input folder for " + $definition.Label)
    } else {
        $filter = switch ($controls['cmbConvertersType'].SelectedIndex) {
            1 { 'Fit exports (*.json)|*.json|All Files (*.*)|*.*' }
            3 { 'MBOX exports (*.mbox;*.mbx;*.txt)|*.mbox;*.mbx;*.txt|All Files (*.*)|*.*' }
            default { 'All Files (*.*)|*.*' }
        }
        $selection = Get-FileDialog -Filter $filter -Title ("Select input for " + $definition.Label)
    }
    if ($selection) {
        $controls['txtConvertersInput'].Text = $selection
        $controls['txtConvertersInput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
        try {
            $count = @(Get-DgInputFiles -InputPath $selection -Extensions $definition.Extensions).Count
            Write-Log "Selected converter input with $count matching file(s)"
        } catch { Write-Log "Selected input could not be scanned: $_" "WARN" }
    }
})

$controls['btnConvertersOutputBrowse'].Add_Click({
    $folder = Get-FolderDialog -Description 'Select output folder for converted data'
    if ($folder) {
        $controls['txtConvertersOutput'].Text = $folder
        $controls['txtConvertersOutput'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
    }
})

$controls['btnConvertersRun'].Add_Click({
    $definition = Get-ConverterDefinition $controls['cmbConvertersType'].SelectedIndex
    $inputPath = $controls['txtConvertersInput'].Text
    if ($inputPath -match 'Select input' -or -not (Test-Path -LiteralPath $inputPath)) {
        Write-Log 'No converter input selected' 'WARN'; return
    }
    $outputPath = $controls['txtConvertersOutput'].Text
    if ($outputPath -match 'Select output') {
        $outputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeGoogler_Converted'
        $controls['txtConvertersOutput'].Text = $outputPath
    }
    $dryRun = $controls['chkConvertersDryRun'].IsChecked
    try { $matchingFiles = @(Get-DgInputFiles -InputPath $inputPath -Extensions $definition.Extensions) } catch { Write-Log "Cannot read converter input: $_" 'ERROR'; return }
    if ($matchingFiles.Count -eq 0) { Write-Log "No matching input files found for $($definition.Label)" 'WARN'; return }

    if ($dryRun) {
        Write-Log "[DRY RUN] $($definition.Label) - no files will be written" 'WARN'
        Write-Log "[DRY RUN] Input files: $($matchingFiles.Count) | Output folder: $outputPath"
        Write-Log '[DRY RUN] Dry run complete. No files were modified.' 'OK'
        Write-JsonLog -Tool 'ExportConverter' -Action 'DryRun' -Message 'Converter dry run' -Level 'INFO' -Data @{ converter = $definition.Label; inputFiles = $matchingFiles.Count; output = $outputPath }
        Set-Progress 100 'Dry Run Complete'
        return
    }

    Write-Log "Starting $($definition.Label)..."
    Write-JsonLog -Tool 'ExportConverter' -Action 'Start' -Message 'Converter started' -Level 'INFO' -Data @{ converter = $definition.Label; inputFiles = $matchingFiles.Count; output = $outputPath }
    Set-Progress 0 'Converting...'
    $controls['btnConvertersRun'].IsEnabled = $false
    Start-AsyncTask -ScriptBlock {
        param($functionName, $source, $target)
        & $functionName -InputPath $source -OutputPath $target
    } -Arguments $definition.Name, $inputPath, $outputPath -OnComplete {
        param($result, $errors)
        $controls['btnConvertersRun'].IsEnabled = $true
        if ($errors) { foreach ($e in $errors) { Write-Log "Error: $e" 'ERROR' } }
        $summary = @($result | Where-Object { $_ -and $_.PSObject.Properties['Converter'] } | Select-Object -Last 1)
        if ($summary.Count -gt 0) {
            $item = $summary[0]
            $count = if ($item.Written) { $item.Written } elseif ($item.Records -ne $null) { $item.Records } else { 0 }
            Write-Log "$($definition.Label) complete ($count output unit(s))" 'OK'
            Write-JsonLog -Tool 'ExportConverter' -Action 'Complete' -Message 'Converter finished' -Level 'OK' -Data @{ converter = $definition.Label; outputUnits = $count; output = $item.Output }
            Set-Progress 100 'Done'
        } elseif (-not $errors) {
            Write-Log "$($definition.Label) produced no summary" 'WARN'
            Set-Progress 0 ''
        }
    }
})

function Apply-DgStartupInputs {
    if ($DeepLink) {
        try {
            $link = ConvertFrom-DgDeepLink -Uri $DeepLink
            $targetTab = switch ($link.Tool) {
                'takeout' { 'tabTakeout' }
                'photos' { 'tabPhotos' }
                'passwords' { 'tabPasswords' }
                'email' { 'tabEmail' }
                'bookmarks' { 'tabBookmarks' }
                'contacts' { 'tabContacts' }
                default { 'tabConverters' }
            }
            Switch-Tab $targetTab
            if ($link.Tool -eq 'takeout' -and $link.Path -and (Test-Path -LiteralPath $link.Path)) {
                $script:takeoutFiles = @(Get-ChildItem -LiteralPath $link.Path -File | Where-Object { $_.Extension -in @('.zip','.tgz') } | ForEach-Object { $_.FullName })
                $controls['txtTakeoutInput'].Text = "$($script:takeoutFiles.Count) archive(s) selected"
            } elseif ($link.Path) {
                $controlName = switch ($link.Tool) {
                    'photos' { 'txtPhotosInput' }
                    'passwords' { 'txtPasswordsInput' }
                    'email' { 'txtEmailInput' }
                    'bookmarks' { 'txtBookmarksInput' }
                    'contacts' { 'txtContactsInput' }
                    default { 'txtConvertersInput' }
                }
                if (Test-Path -LiteralPath $link.Path) {
                    $controls[$controlName].Text = $link.Path
                    $controls[$controlName].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#e0e0e0')
                } else { Write-Log "Deep-link path does not exist: $($link.Path)" 'WARN' }
            }
            if ($link.Plan) { $PlanPath = $link.Plan }
            Write-Log "Opened from degoogler:// deep link ($($link.Tool))" 'OK'
        } catch { Write-Log "Invalid DeGoogler deep link: $_" 'ERROR' }
    }
    if ($PlanPath) {
        try {
            $plan = Import-DgMigrationPlan -Path $PlanPath
            $pending = @($plan.actions | Where-Object { -not $_.done }).Count
            Write-Log "Loaded migration plan for profile '$($plan.profile)': $pending pending action(s)." 'OK'
            Write-JsonLog -Tool 'PlanSync' -Action 'Import' -Message 'Migration plan loaded' -Level 'OK' -Data @{ profile = $plan.profile; pendingActions = $pending; source = $PlanPath }
        } catch { Write-Log "Could not load migration plan: $_" 'ERROR' }
    }
}

# ── Initialize ──
Switch-Tab 'tabTakeout'
Apply-DgStartupInputs

# ── Show window ──
$window.ShowDialog() | Out-Null
