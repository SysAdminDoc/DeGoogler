#Requires -Version 5.1
<#
.SYNOPSIS
    DeGoogler Toolkit v0.0.1 - Google Data Migration & Processing Suite
.DESCRIPTION
    Turnkey PowerShell WPF application that handles:
    - Google Takeout archive extraction and organization
    - Google Photos metadata restoration (JSON sidecar to EXIF)
    - Chrome password CSV to Bitwarden/KeePass conversion
    - MBOX email processing and conversion to EML
    - Chrome bookmark conversion for Firefox/Brave
    - Google Contacts vCard processing
.AUTHOR
    SysAdminDoc
.VERSION
    0.0.1
#>

# ── Auto-elevate ──
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
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
function Install-ExifTool {
    $exifPath = Join-Path $env:LOCALAPPDATA "DeGoogler\exiftool.exe"
    if (Test-Path $exifPath) { return $exifPath }

    $dir = Split-Path $exifPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    try {
        $apiUrl = "https://api.github.com/repos/exiftool/exiftool/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' -and $_.name -match 'exiftool' } | Select-Object -First 1
        if ($zipAsset) {
            $zipPath = Join-Path $env:TEMP "exiftool.zip"
            Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $dir -Force
            $exeFile = Get-ChildItem -Path $dir -Filter "exiftool(-k).exe" -Recurse | Select-Object -First 1
            if (-not $exeFile) { $exeFile = Get-ChildItem -Path $dir -Filter "exiftool*.exe" -Recurse | Select-Object -First 1 }
            if ($exeFile) {
                Copy-Item $exeFile.FullName $exifPath -Force
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                return $exifPath
            }
        }
    } catch {}
    return $null
}

# ── XAML UI ──
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DeGoogler Toolkit v0.0.1" Width="920" Height="720"
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
                        <TextBlock Text="v0.0.1" FontSize="10" Foreground="#888"/>
                    </Border>
                </StackPanel>
                <TextBlock Grid.Column="2" Text="Your data stays on your machine" FontSize="11" Foreground="#666" VerticalAlignment="Center"/>
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
                    <CheckBox x:Name="chkTakeoutDeleteZips" Content="Delete original ZIP files after extraction" Margin="0,0,0,12"/>
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
                    <CheckBox x:Name="chkPhotosRecursive" Content="Process subfolders recursively" IsChecked="True" Margin="0,0,0,12"/>
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
                    <CheckBox x:Name="chkPasswordsSecureDelete" Content="Securely overwrite source CSV after conversion" Margin="0,0,0,12"/>
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
                    <CheckBox x:Name="chkEmailPreserveLabels" Content="Create subfolders from Gmail labels" IsChecked="True" Margin="0,0,0,12"/>
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
                    <CheckBox x:Name="chkContactsClean" Content="Clean formatting (standardize phone numbers, fix encoding)" IsChecked="True" Margin="0,0,0,12"/>
                    <Button x:Name="btnContactsRun" Content="Process Contacts" HorizontalAlignment="Left"/>
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
    'btnTabTakeout','btnTabPhotos','btnTabPasswords','btnTabEmail','btnTabBookmarks','btnTabContacts',
    'tabTakeout','tabPhotos','tabPasswords','tabEmail','tabBookmarks','tabContacts',
    'txtTakeoutInput','btnTakeoutBrowse','txtTakeoutOutput','btnTakeoutOutputBrowse','chkTakeoutDeleteZips','btnTakeoutRun',
    'txtPhotosInput','btnPhotosBrowse','chkPhotosDeleteJson','chkPhotosFixDates','chkPhotosRecursive','lblPhotosExiftool','btnPhotosRun',
    'txtPasswordsInput','btnPasswordsBrowse','cmbPasswordsFormat','chkPasswordsSecureDelete','btnPasswordsRun',
    'txtEmailInput','btnEmailBrowse','txtEmailOutput','btnEmailOutputBrowse','chkEmailPreserveLabels','btnEmailRun',
    'txtBookmarksInput','btnBookmarksBrowse','btnBookmarksDetect','btnBookmarksRun',
    'txtContactsInput','btnContactsBrowse','chkContactsDedup','chkContactsClean','btnContactsRun',
    'progressBar','lblProgress','txtLog'
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
$tabNames = @('tabTakeout','tabPhotos','tabPasswords','tabEmail','tabBookmarks','tabContacts')
$tabBtnNames = @('btnTabTakeout','btnTabPhotos','btnTabPasswords','btnTabEmail','btnTabBookmarks','btnTabContacts')

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
    $files = $script:takeoutFiles
    $logAction = ${function:Write-Log}
    $progressAction = ${function:Set-Progress}

    Write-Log "Starting extraction of $($files.Count) archive(s)..."
    Set-Progress 0 "Extracting..."

    $controls['btnTakeoutRun'].IsEnabled = $false

    Start-AsyncTask -ScriptBlock {
        param($files, $outputDir, $deleteZips)
        if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
        $results = @()
        for ($i = 0; $i -lt $files.Count; $i++) {
            $file = $files[$i]
            $tempDir = Join-Path $env:TEMP "degoogler_extract_$i"
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
            } catch {
                $results += "ERROR: $($_.Exception.Message)"
            }
        }
        return $results
    } -Arguments @(,$files), $outputDir, $deleteZips -OnComplete {
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

    Write-Log "Starting photo metadata restoration..."
    Set-Progress 0 "Processing photos..."
    $controls['btnPhotosRun'].IsEnabled = $false

    Start-AsyncTask -ScriptBlock {
        param($photosDir, $deleteJson, $fixDates, $recursive)
        $exifPath = Join-Path $env:LOCALAPPDATA "DeGoogler\exiftool.exe"
        $useExif = Test-Path $exifPath

        $searchOpt = if ($recursive) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
        $extensions = @('.jpg','.jpeg','.png','.gif','.mp4','.mov','.heic','.webp','.tiff','.bmp')
        $allFiles = [System.IO.Directory]::GetFiles($photosDir, "*.*", $searchOpt) |
            Where-Object { $extensions -contains [System.IO.Path]::GetExtension($_).ToLower() }

        $processed = 0; $fixed = 0; $failed = 0; $total = $allFiles.Count

        foreach ($mediaFile in $allFiles) {
            $processed++
            $baseName = [System.IO.Path]::GetFileName($mediaFile)
            # Google Takeout JSON sidecar naming patterns
            $jsonCandidates = @(
                "$mediaFile.json",
                [System.IO.Path]::ChangeExtension($mediaFile, '') + ".json",
                "$($mediaFile -replace '\.[^.]+$', '.json')"
            )
            # Also handle edited versions: photo.jpg -> photo.jpg(1).json
            $dir = [System.IO.Path]::GetDirectoryName($mediaFile)
            $jsonFiles = Get-ChildItem -Path $dir -Filter "*.json" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match [regex]::Escape($baseName) }
            foreach ($jf in $jsonFiles) {
                if ($jf.FullName -notin $jsonCandidates) { $jsonCandidates += $jf.FullName }
            }

            $jsonFile = $jsonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $jsonFile) { continue }

            try {
                $json = Get-Content $jsonFile -Raw | ConvertFrom-Json
                $photoTaken = $null
                $geoLat = $null; $geoLon = $null; $desc = $null

                # Extract timestamp
                if ($json.photoTakenTime.timestamp) {
                    $epoch = [long]$json.photoTakenTime.timestamp
                    $photoTaken = [DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime
                } elseif ($json.creationTime.timestamp) {
                    $epoch = [long]$json.creationTime.timestamp
                    $photoTaken = [DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime
                }

                # Extract GPS
                if ($json.geoData.latitude -and $json.geoData.latitude -ne 0) {
                    $geoLat = $json.geoData.latitude
                    $geoLon = $json.geoData.longitude
                } elseif ($json.geoDataExif.latitude -and $json.geoDataExif.latitude -ne 0) {
                    $geoLat = $json.geoDataExif.latitude
                    $geoLon = $json.geoDataExif.longitude
                }

                # Extract description
                if ($json.description) { $desc = $json.description }

                if ($useExif -and $photoTaken) {
                    $dateStr = $photoTaken.ToString('yyyy:MM:dd HH:mm:ss')
                    $args = @("-overwrite_original", "-DateTimeOriginal=`"$dateStr`"", "-CreateDate=`"$dateStr`"", "-ModifyDate=`"$dateStr`"")
                    if ($geoLat -and $geoLat -ne 0) {
                        $latRef = if ($geoLat -ge 0) { "N" } else { "S" }
                        $lonRef = if ($geoLon -ge 0) { "E" } else { "W" }
                        $args += "-GPSLatitude=$([Math]::Abs($geoLat))", "-GPSLatitudeRef=$latRef"
                        $args += "-GPSLongitude=$([Math]::Abs($geoLon))", "-GPSLongitudeRef=$lonRef"
                    }
                    if ($desc) { $args += "-ImageDescription=`"$desc`"" }
                    $args += "`"$mediaFile`""
                    & $exifPath @args 2>$null | Out-Null
                    $fixed++
                } elseif ($photoTaken -and $fixDates) {
                    # Fallback: at least fix file system dates
                    [System.IO.File]::SetCreationTime($mediaFile, $photoTaken)
                    [System.IO.File]::SetLastWriteTime($mediaFile, $photoTaken)
                    $fixed++
                }

                if ($deleteJson -and $jsonFile) {
                    Remove-Item $jsonFile -Force -ErrorAction SilentlyContinue
                }
            } catch {
                $failed++
            }
        }
        return @{ Total = $total; Fixed = $fixed; Failed = $failed }
    } -Arguments $photosDir, $deleteJson, $fixDates, $recursive -OnComplete {
        param($result, $errors)
        $controls['btnPhotosRun'].IsEnabled = $true
        Set-Progress 100 "Done"
        if ($errors) { foreach ($e in $errors) { Write-Log "Error: $e" "ERROR" } }
        if ($result -and $result.Count -gt 0) {
            $r = $result[0]
            Write-Log "Photo metadata restoration complete: $($r.Fixed) fixed / $($r.Total) total / $($r.Failed) failed" "OK"
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

    $formatName = switch ($formatIdx) { 0 { "Bitwarden" } 1 { "KeePass" } 2 { "1Password" } 3 { "ProtonPass" } default { "Bitwarden" } }
    $savePath = Get-SaveDialog -Filter "CSV Files (*.csv)|*.csv" -Title "Save $formatName CSV" -DefaultName "${formatName}_import.csv"
    if (-not $savePath) { return }

    Write-Log "Converting to $formatName format..."
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

        if ($secureDelete) {
            $bytes = [System.IO.File]::ReadAllBytes($inputFile)
            $random = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
            $random.GetBytes($bytes)
            [System.IO.File]::WriteAllBytes($inputFile, $bytes)
            $random.GetBytes($bytes)
            [System.IO.File]::WriteAllBytes($inputFile, $bytes)
            Remove-Item $inputFile -Force
            Write-Log "Source CSV securely overwritten and deleted" "OK"
        }

        Set-Progress 100 "Done"
    } catch {
        Write-Log "Error converting passwords: $_" "ERROR"
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
    Write-Log "Processing MBOX file..."
    Set-Progress 0 "Processing..."
    $controls['btnEmailRun'].IsEnabled = $false

    Start-AsyncTask -ScriptBlock {
        param($inputFile, $outputDir, $preserveLabels)
        $reader = [System.IO.StreamReader]::new($inputFile, [System.Text.Encoding]::UTF8)
        $emailCount = 0
        $currentEmail = New-Object System.Text.StringBuilder
        $currentLabel = "Inbox"
        $inEmail = $false

        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -match '^From ') {
                # Save previous email
                if ($inEmail -and $currentEmail.Length -gt 0) {
                    $emailCount++
                    $targetDir = $outputDir
                    if ($preserveLabels -and $currentLabel) {
                        $safeLabel = $currentLabel -replace '[\\/:*?"<>|]', '_'
                        $targetDir = Join-Path $outputDir $safeLabel
                    }
                    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                    $emlPath = Join-Path $targetDir "email_$($emailCount.ToString('D6')).eml"
                    [System.IO.File]::WriteAllText($emlPath, $currentEmail.ToString(), [System.Text.Encoding]::UTF8)
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
            $targetDir = $outputDir
            if ($preserveLabels -and $currentLabel) {
                $safeLabel = $currentLabel -replace '[\\/:*?"<>|]', '_'
                $targetDir = Join-Path $outputDir $safeLabel
            }
            if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
            $emlPath = Join-Path $targetDir "email_$($emailCount.ToString('D6')).eml"
            [System.IO.File]::WriteAllText($emlPath, $currentEmail.ToString(), [System.Text.Encoding]::UTF8)
        }
        $reader.Close()
        $reader.Dispose()
        return @{ Count = $emailCount }
    } -Arguments $inputFile, $outputDir, $preserveLabels -OnComplete {
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

    $savePath = Get-SaveDialog -Filter "HTML Bookmark File (*.html)|*.html" -Title "Save Bookmarks HTML" -DefaultName "bookmarks_export.html"
    if (-not $savePath) { return }

    Write-Log "Converting bookmarks..."

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

    $savePath = Get-SaveDialog -Filter "vCard Files (*.vcf)|*.vcf" -Title "Save Processed Contacts" -DefaultName "contacts_cleaned.vcf"
    if (-not $savePath) { return }

    Write-Log "Processing contacts..."
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

# ── Initialize ──
Switch-Tab 'tabTakeout'

# ── Show window ──
$window.ShowDialog() | Out-Null
