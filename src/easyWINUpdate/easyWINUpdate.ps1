<#
.SYNOPSIS
    easyWINUpdate - Windows Update Verwaltungstool mit GUI
.DESCRIPTION
    Dieses Script ermöglicht die Verwaltung von Windows Updates auf Windows 11 und Windows Server 2019-2022.
    Es bietet eine moderne XAML-GUI zur Anzeige, Installation und Deinstallation von Updates sowie zur Verwaltung
    der Update-Quellen und WSUS-Einstellungen.
.NOTES
    Version:        0.2.4
    Author:         Andreas Hepp | PhinIT (www.phinit.de)
    Creation Date:  31.05.2025
    Voraussetzungen: Windows PowerShell 5.1 oder PowerShell 7 (Windows), Modul PSWindowsUpdate, Administratorrechte
    Logs:           Unterordner "Logs" im Skriptverzeichnis (Fallback: %LOCALAPPDATA%\easyWINUpdate\Logs)
#>

$script:AppVersion = '0.2.4'

#region Administratorrechte / STA sicherstellen
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
if ((-not $script:IsAdmin -or -not $isSta) -and $PSCommandPath) {
    try {
        # Gleichen PowerShell-Host (powershell.exe bzw. pwsh.exe) verwenden und Skriptpfad korrekt quoten
        $hostExe = (Get-Process -Id $PID).Path
        $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
        if ($script:IsAdmin) {
            Start-Process -FilePath $hostExe -ArgumentList $relaunchArgs -ErrorAction Stop | Out-Null
        } else {
            Start-Process -FilePath $hostExe -ArgumentList $relaunchArgs -Verb RunAs -ErrorAction Stop | Out-Null
        }
        exit
    } catch {
        if (-not $isSta) {
            Write-Host "Die GUI benötigt einen STA-Thread. Bitte mit 'powershell.exe -STA -File `"$PSCommandPath`"' starten." -ForegroundColor Red
            exit 1
        }
        Write-Host "Keine Administratorrechte erhalten - viele Funktionen (Dienste, Registry, DISM/SFC) stehen nicht zur Verfügung." -ForegroundColor Yellow
    }
}
#endregion

#region Logging
$script:LogDirectory = $null
foreach ($candidate in @(
        $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Logs' }),
        (Join-Path $env:LOCALAPPDATA 'easyWINUpdate\Logs'))) {
    if (-not $candidate) { continue }
    try {
        if (-not (Test-Path -LiteralPath $candidate)) {
            New-Item -Path $candidate -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $probeFile = Join-Path $candidate '.write_test'
        [System.IO.File]::WriteAllText($probeFile, '')
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
        $script:LogDirectory = $candidate
        break
    } catch {
        Write-Verbose "Log-Verzeichnis '$candidate' nicht beschreibbar: $($_.Exception.Message)"
    }
}
$script:LogFile = if ($script:LogDirectory) { Join-Path $script:LogDirectory ("easyWINUpdate_{0}.log" -f (Get-Date -Format 'yyyyMMdd')) } else { $null }

function Write-AppLog {
    param (
        [string]$Message,
        [string]$Level = 'INFO'
    )
    if (-not $script:LogFile) { return }
    try {
        $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        [System.IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Verbose "Log konnte nicht geschrieben werden: $($_.Exception.Message)"
    }
}
Write-AppLog -Message "easyWINUpdate v$($script:AppVersion) gestartet (Admin: $($script:IsAdmin), PowerShell $($PSVersionTable.PSVersion))"
#endregion

# Fehlercode-Mapping mit bekannten Loesungen
$errorCodes = @{
    "0x80072EE7" = @{
        "Description" = "WININET_E_CANNOT_RESOLVE_NAME / The server name or address could not be resolved (DNS issue)";
        "Solutions" = @(
            "Clear DNS cache (ipconfig /flushdns)",
            "Check proxy settings",
            "Check network connection",
            "Restart Windows Update services"
        )
    };
    "0x8024402C" = @{
        "Description" = "WU_E_PT_WINHTTP_NAME_NOT_RESOLVED / DNS resolution error";
        "Solutions" = @(
            "Clear DNS cache (ipconfig /flushdns)",
            "Check DNS server settings",
            "Configure alternate DNS servers",
            "Reset network adapter"
        )
    };
    "0x8024401B" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_PROXY_AUTH_REQ / Proxy authentication required";
        "Solutions" = @(
            "Check proxy settings and configure user authentication",
            "Reset WinHTTP proxy (netsh winhttp reset proxy)",
            "Check network connection",
            "Reset Windows Update components"
        )
    };
    "0x80244018" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_FORBIDDEN / Access denied (HTTP 403)";
        "Solutions" = @(
            "Check firewall/proxy rules",
            "Check access permissions",
            "Restart Windows Update services",
            "Delete temporary files"
        )
    };
    "0x80244019" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_NOT_FOUND / Update not found (HTTP 404)";
        "Solutions" = @(
            "Check WSUS/update source",
            "Import proxy settings (netsh winhttp import proxy source=ie)",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80244022" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_SERVICE_UNAVAIL / Update server unavailable (HTTP 503)";
        "Solutions" = @(
            "Try again later",
            "Check Microsoft Update server status",
            "Use alternate update source",
            "Check network connection"
        )
    };
    "0x80072EFD" = @{
        "Description" = "WININET_E_TIMEOUT / Timeout establishing connection";
        "Solutions" = @(
            "Check network connection",
            "Check firewall/proxy settings",
            "Restart Windows Update services",
            "Try again later"
        )
    };
    "0x80072EFE" = @{
        "Description" = "WININET_E_INVALID_URL / Invalid URL for update server";
        "Solutions" = @(
            "Check update server address",
            "Clear Windows Update cache",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80D02002" = @{
        "Description" = "BG_E_NETWORK_FAILURE / Network failure during update download";
        "Solutions" = @(
            "Check internet connection",
            "Check firewall/proxy settings",
            "Reset BITS (bitsadmin /reset)",
            "Reset Windows Update components"
        )
    };
    "0x80072EE2" = @{
        "Description" = "WININET_E_CONNECTION_TIMEOUT / Connection to update server could not be established";
        "Solutions" = @(
            "Check network connection",
            "Check date and time settings",
            "Enable TLS 1.2",
            "Restart Windows Update services"
        )
    };
    "0x80072F8F" = @{
        "Description" = "WININET_E_DECODING_FAILED / TLS/SSL error";
        "Solutions" = @(
            "Enable TLS 1.2",
            "Correct system date/time",
            "Update Windows Update Agent",
            "Restart Windows Update services"
        )
    };
    "0x80200053" = @{
        "Description" = "BG_E_VALIDATION_FAILED / File validation failed";
        "Solutions" = @(
            "Check web filter/firewall",
            "Temporarily disable antivirus software",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80244007" = @{
        "Description" = "WU_E_PT_SOAPCLIENT_SOAPFAULT / SOAP error during update scan (WSUS)";
        "Solutions" = @(
            "Check WSUS server settings",
            "Reset WSUS client (wuauclt /resetauthorization /detectnow)",
            "Restart Windows Update services",
            "Restart system"
        )
    };
    "0x8024D009" = @{
        "Description" = "WU_E_SETUP_SKIP_UPDATE / Windows Update Agent self-update skipped";
        "Solutions" = @(
            "Repair WSUS self-update",
            "Check permissions of virtual directory",
            "Restart Windows Update services",
            "Restart system"
        )
    };
    "0x8024402F" = @{
        "Description" = "WU_E_PT_ECP_SUCCEEDED_WITH_ERRORS / External CAB processing completed with errors";
        "Solutions" = @(
            "Configure web filter exceptions",
            "Reset Windows Update components",
            "Delete temporary files",
            "Restart system"
        )
    };
    "0x8024A10A" = @{
        "Description" = "USO_E_SERVICE_SHUTTING_DOWN / Windows Update service shutting down";
        "Solutions" = @(
            "Keep system active during updates",
            "Restart Windows Update services",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80070422" = @{
        "Description" = "ERROR_SERVICE_DISABLED / Windows Update service is disabled or not started";
        "Solutions" = @(
            "sc config wuauserv start= auto && sc start wuauserv",
            "Check registry settings for update services",
            "Review group policies",
            "Run system diagnostics"
        )
    };
    "0x80240020" = @{
        "Description" = "WU_E_NO_INTERACTIVE_USER / No interactive user logged on";
        "Solutions" = @(
            "Log on as a user and restart update",
            "Restart system",
            "Restart Windows Update services",
            "Reset Windows Update components"
        )
    };
    "0x80242014" = @{
        "Description" = "WU_E_UH_POSTREBOOTSTILLPENDING / Update is pending reboot";
        "Solutions" = @(
            "Restart system",
            "Restart Windows Update services",
            "Reset Windows Update components",
            "Run system diagnostics"
        )
    };
    "0x80070BC9" = @{
        "Description" = "ERROR_FAIL_REBOOT_REQUIRED / Pending restart required";
        "Solutions" = @(
            "Restart system",
            "Delete temporary update files",
            "Reset Windows Update components",
            "Run system diagnostics"
        )
    };
    "0x800706BE" = @{
        "Description" = "RPC_S_CALL_FAILED / RPC communication error";
        "Solutions" = @(
            "Check and restart RPC services",
            "Reset Windows Update components",
            "Restart system",
            "Repair system files (sfc /scannow)"
        )
    };
    "0x80246017" = @{
        "Description" = "WU_E_DM_UNAUTHORIZED_LOCAL_USER / Download denied (user rights)";
        "Solutions" = @(
            "Log on as administrator",
            "Check user rights",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x8007000D" = @{
        "Description" = "ERROR_INVALID_DATA / Invalid or corrupted update data";
        "Solutions" = @(
            "Re-download update",
            "Clear Windows Update cache",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80070490" = @{
        "Description" = "ERROR_NOT_FOUND / Update element not found";
        "Solutions" = @(
            "Check registry value",
            "Reset Windows Update components",
            "Restart Windows Update services",
            "Restart system"
        )
    };
    "0x80242006" = @{
        "Description" = "WU_E_UH_INVALIDMETADATA / Invalid metadata in update";
        "Solutions" = @(
            "Rename SoftwareDistribution\\DataStore",
            "Rename Catroot2",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x8024200D" = @{
        "Description" = "SUS_E_UH_NEEDANOTHERDOWNLOAD / Another download is needed";
        "Solutions" = @(
            "Redownload update",
            "Install latest servicing stack",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80246007" = @{
        "Description" = "WU_E_DM_NOTDOWNLOADED / Update not downloaded";
        "Solutions" = @(
            "Reset BITS (bitsadmin /reset)",
            "Reset Windows Update components",
            "Restart Windows Update services",
            "Restart system"
        )
    };
    "0x800705B4" = @{
        "Description" = "ERROR_TIMEOUT / Operation timed out";
        "Solutions" = @(
            "Try again later",
            "Run Windows Update Troubleshooter",
            "Restart Windows Update services",
            "Restart system"
        )
    };
    "0x8024000B" = @{
        "Description" = "WU_E_CALL_CANCELLED / Operation cancelled";
        "Solutions" = @(
            "Retry update without cancelling",
            "Restart Windows Update services",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80070643" = @{
        "Description" = "FATAL_ERROR_DURING_INSTALLATION / Fatal error during installation";
        "Solutions" = @(
            "sfc /scannow (repair system files)",
            "Reset Windows Update components",
            "Restart system",
            "Repair Windows system files"
        )
    };
    "0x800B0109" = @{
        "Description" = "TRUST_E_CERT_SIGNATURE / Certificate chain ends in untrusted root certificate";
        "Solutions" = @(
            "Repair system files (sfc /scannow)",
            "Install missing root certificate",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80070005" = @{
        "Description" = "E_ACCESSDENIED / Access denied (permission issue)";
        "Solutions" = @(
            "Adjust permissions of affected files/registry paths",
            "Run as administrator",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80070570" = @{
        "Description" = "ERROR_FILE_CORRUPT / File or directory corrupted (component store)";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80070003" = @{
        "Description" = "ERROR_PATH_NOT_FOUND / A required path was not found";
        "Solutions" = @(
            "Search logs in %windir%\\Logs\\CBS\\CBS.log for error",
            "Check and correct paths",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80070020" = @{
        "Description" = "ERROR_SHARING_VIOLATION / Sharing violation accessing a file";
        "Solutions" = @(
            "Perform clean boot",
            "Use Process Monitor to find blocking process",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80073701" = @{
        "Description" = "ERROR_SXS_ASSEMBLY_MISSING / Referenced assembly not found (component store inconsistent)";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x8007371B" = @{
        "Description" = "ERROR_SXS_TRANSACTION_CLOSURE_INCOMPLETE / Transaction not complete";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x80073712" = @{
        "Description" = "ERROR_SXS_COMPONENT_STORE_CORRUPT / Component store is corrupt";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "Consider in-place upgrade",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x800F081F" = @{
        "Description" = "CBS_E_SOURCE_MISSING / Source package/file not found (often .NET Framework issue)";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth /Source:<path>",
            "Repair component store",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x800F0831" = @{
        "Description" = "CBS_E_STORE_CORRUPTION / Component store corruption";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x800F0821" = @{
        "Description" = "CBS_E_ABORT / Operation aborted by client (timeout)";
        "Solutions" = @(
            "Provide more resources (increase CPU/RAM)",
            "Install patch KB4493473 or later",
            "Reset Windows Update components",
            "Restart system"
        )
    };
    "0x800F0825" = @{
        "Description" = "CBS_E_CANNOT_UNINSTALL / Package cannot be uninstalled";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Restart system",
            "Reset Windows Update components"
        )
    };
    "0x800F0920" = @{
        "Description" = "CBS_E_HANG_DETECTED / Hang detected during update processing";
        "Solutions" = @(
            "Increase VM resources",
            "Extend timeout",
            "Install patch KB4493473+",
            "Restart system"
        )
    };
    "0x800F0922" = @{
        "Description" = "CBS_E_INSTALLERS_FAILED / Installer routines failed";
        "Solutions" = @(
            "Adjust write permissions for C:\\Windows\\System32\\spp",
            "Reset Windows Update components",
            "Restart system",
            "Restart Windows Update services"
        )
    };
    "0xC1900101" = @{
        "Description" = "General installation failure during upgrade (rollback)";
        "Solutions" = @(
            "Update drivers",
            "Remove unnecessary hardware",
            "Ensure sufficient disk space",
            "Restart system"
        )
    };
    "0xC1900107" = @{
        "Description" = "Cleanup operation still pending / restart required";
        "Solutions" = @(
            "Restart system",
            "Clean temporary Windows Update files",
            "Run Disk Cleanup",
            "Restart Windows Update services"
        )
    };
    "0xC1900201" = @{
        "Description" = "System reserved partition could not be updated (insufficient space)";
        "Solutions" = @(
            "Increase space on reserved partition",
            "Remove unneeded language packs",
            "Extend partition",
            "Restart system"
        )
    };
    "0x80240034" = @{
        "Description" = "WU_E_PT_ECP_FAILURE_TO_DECOMPRESS_CAB_FILE / External CAB archive could not be decompressed";
        "Solutions" = @(
            "Reset Windows Update components",
            "Delete temporary update files",
            "Restart system",
            "Run DISM /Online /Cleanup-Image /RestoreHealth"
        )
    };
    "0x8024001F" = @{
        "Description" = "WU_E_NO_CONNECTION / No connection to update service";
        "Solutions" = @(
            "Check network connection",
            "Check firewall and proxy settings",
            "Restart network adapter",
            "Restart Windows Update services"
        )
    };
    "0x80240003" = @{
        "Description" = "WU_E_UNKNOWN_ID / An ID could not be found";
        "Solutions" = @(
            "Clear Windows Update cache",
            "Manually install update",
            "Reset Windows Update components",
            "Restart system"
        )
    };
}  

#region Requires
# Module PSWindowsUpdate wird benötigt
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    try {
        # PowerShellGet prüfen und ggf. installieren
        if (-not (Get-Module -ListAvailable -Name PowerShellGet | Where-Object Version -ge "2.0")) {
            Install-Module PowerShellGet -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        }
        
        # PSWindowsUpdate installieren (als Administrator für alle Benutzer, damit auch die geplante Aufgabe unter SYSTEM es laden kann)
        $moduleScope = if ($script:IsAdmin) { "AllUsers" } else { "CurrentUser" }
        Install-Module -Name PSWindowsUpdate -Force -Scope $moduleScope -ErrorAction Stop
        Write-AppLog -Message "PSWindowsUpdate installiert (Scope: $moduleScope)"
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-Host "PSWindowsUpdate-Modul wurde installed und importiert." -ForegroundColor Green
    } catch {
        Write-Host "Fehler beim Installieren des PSWindowsUpdate-Moduls: $_" -ForegroundColor Red
        Write-Host "Bitte führen Sie 'Install-Module -Name PSWindowsUpdate -Force' manuell mit administrativen Rechten aus." -ForegroundColor Yellow
        exit
    }
} else {
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
    } catch {
        Write-Host "Fehler beim Importieren des PSWindowsUpdate-Moduls: $_" -ForegroundColor Red
        exit
    }
}
#endregion

# WPF-Assemblies laden
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

#region XAML GUI Definition
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="easyWINUpdate v0.2.4 - Windows Update Management" Height="950" Width="1400" 
    WindowStartupLocation="CenterScreen" ResizeMode="CanResize" 
    Background="#F0F0F0">
    
    <Window.Resources>
        <Style x:Key="NavButtonStyle" TargetType="RadioButton">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="border" Background="Transparent" BorderThickness="4,0,0,0" BorderBrush="Transparent" Padding="{TemplateBinding Padding}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#F0F0F0"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#0078D7"/>
                                <Setter TargetName="border" Property="Background" Value="#F0F0F0"/>
                                <Setter Property="Foreground" Value="#0078D7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="60"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="40"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <Border Grid.Row="0" Background="#0078D7" Padding="15,0">
            <Grid>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="easyWINUpdate" Foreground="White" FontSize="24" FontWeight="Bold" VerticalAlignment="Center"/>
                    <TextBlock Text="v0.2.4" Foreground="#CCFFFFFF" FontSize="14" Margin="10,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock x:Name="computerNameLabel" Text="Computer: " Foreground="White" FontSize="14" VerticalAlignment="Center"/>
                    <TextBlock x:Name="computerName" Text="..." Foreground="White" FontSize="14" FontWeight="SemiBold" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>
        
        <!-- Content Area -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="250"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <!-- Navigation Panel -->
            <Border Background="#F9F9F9" BorderBrush="#DDDDDD" BorderThickness="0,0,1,0">
                <StackPanel Margin="0,20,0,0">
                    <RadioButton x:Name="navHome" Content="Home" GroupName="Navigation" 
                                IsChecked="True" Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>
                    
                    <RadioButton x:Name="navInstalledUpdates" Content="Installed Updates" GroupName="Navigation" 
                                Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>
                    
                    <RadioButton x:Name="navAvailableUpdates" Content="Available Updates" GroupName="Navigation" 
                                Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>
                    
                    <RadioButton x:Name="navWSUSSettings" Content="WSUS Settings" GroupName="Navigation" 
                                Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>
                    
                    <RadioButton x:Name="navTroubleshooting" Content="Troubleshooting" GroupName="Navigation" 
                                Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>
                </StackPanel>
            </Border>
            
            <!-- Content Pages -->
            <Grid Grid.Column="1" Margin="20">
                <!-- Home Page (Combined Welcome and Update Status) -->
                <Grid x:Name="homePage" Visibility="Visible">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel>
                            <TextBlock Text="Welcome to easyWINUpdate" FontSize="24" FontWeight="SemiBold" Margin="0,0,0,20"/>
                            
                            <!-- System Info Section -->
                            <Border Background="#F0F8FF" BorderBrush="#99CCE8" BorderThickness="1" Padding="20" CornerRadius="4" Margin="0,0,0,20">
                                <StackPanel>
                                    <TextBlock Text="System Information" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                    
                                    <Grid Margin="0,0,0,10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        
                                        <TextBlock Grid.Row="0" Grid.Column="0" Text="Windows Version:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="0" Grid.Column="1" x:Name="txtWindowsVersion" Text="Loading..." Margin="0,5,0,5"/>
                                        
                                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Update Source:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="1" Grid.Column="1" x:Name="txtUpdateSource" Text="Loading..." Margin="0,5,0,5"/>
                                        
                                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Last Update:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="2" Grid.Column="1" x:Name="txtLastUpdate" Text="Loading..." Margin="0,5,0,5"/>
                                        
                                        <TextBlock Grid.Row="3" Grid.Column="0" Text="Update Status:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="3" Grid.Column="1" x:Name="txtUpdateStatus" Text="Loading..." Margin="0,5,0,5"/>
                                        
                                        <TextBlock Grid.Row="4" Grid.Column="0" Text="Installed Updates:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="4" Grid.Column="1" x:Name="txtInstalledUpdatesCount" Text="Loading..." Margin="0,5,0,5"/>
                                    </Grid>
                                    
                                    <Button x:Name="btnCheckForUpdates" Content="Check for Updates" Padding="15,8" 
                                            Background="#0078D7" Foreground="White" BorderThickness="0"
                                            HorizontalAlignment="Left" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Border>
                            
                            <!-- Features Section -->
                            <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="20" CornerRadius="4" Margin="0,0,0,20">
                                <StackPanel>
                                    <TextBlock Text="Key Features" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                    
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        
                                        <StackPanel Grid.Column="0" Grid.Row="0" Margin="0,0,10,15">
                                            <TextBlock Text="Installed Updates" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="View and manage updates that have already been installed" />
                                        </StackPanel>
                                        
                                        <StackPanel Grid.Column="1" Grid.Row="0" Margin="10,0,0,15">
                                            <TextBlock Text="Available Updates" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="Search for and install pending updates" />
                                        </StackPanel>
                                        
                                        <StackPanel Grid.Column="0" Grid.Row="1" Margin="0,0,10,0">
                                            <TextBlock Text="WSUS Settings" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="Configure Windows Server Update Services integration" />
                                        </StackPanel>
                                        
                                        <StackPanel Grid.Column="1" Grid.Row="1" Margin="10,0,0,0">
                                            <TextBlock Text="Troubleshooting" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="Fix common Windows Update issues" />
                                        </StackPanel>
                                    </Grid>
                                </StackPanel>
                            </Border>
                            
                            <!-- Admin Note Section -->
                            <Border Background="#FFF8E8" BorderBrush="#FFDD99" BorderThickness="1" Padding="20" CornerRadius="4" Margin="0,0,0,20">
                                <StackPanel>
                                    <TextBlock Text="Note" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                    <TextBlock TextWrapping="Wrap">
                                        Some operations require administrator privileges. If you encounter permission issues, please restart the application with "Run as administrator".
                                    </TextBlock>
                                </StackPanel>
                            </Border>
                            
                            <!-- About Section -->
                            <Border Background="#E8F5E9" BorderBrush="#A5D6A7" BorderThickness="1" Padding="20" CornerRadius="4">
                                <StackPanel>
                                    <TextBlock Text="About easyWINUpdate" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                    <TextBlock TextWrapping="Wrap" Margin="0,0,0,10">
                                        easyWINUpdate is a powerful tool for managing Windows Updates on Windows 11 and Windows Server 2019-2022 systems.
                                    </TextBlock>
                                    <TextBlock TextWrapping="Wrap">
                                        Using this tool, you can check update status, install or uninstall updates, configure WSUS settings, and troubleshoot common issues.
                                    </TextBlock>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
                
                <!-- Installed Updates Page -->
                <Grid x:Name="installedUpdatesPage" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="Installed Windows Updates" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,20"/>
                        
                        <!-- Progress Bar -->
                        <ProgressBar x:Name="progressInstalledUpdates" IsIndeterminate="True" Height="10" Margin="0,0,0,10" Visibility="Collapsed"/>
                        
                        <Grid Margin="0,0,0,10">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            
                            <TextBox x:Name="txtSearchInstalled" Grid.Column="0" Padding="8" Margin="0,0,10,0" 
                                    BorderThickness="1" BorderBrush="#AAAAAA">
                                <TextBox.Style>
                                    <Style TargetType="TextBox">
                                        <Style.Resources>
                                            <VisualBrush x:Key="HintBrush" TileMode="None" Opacity="0.5" Stretch="None" AlignmentX="Left">
                                                <VisualBrush.Visual>
                                                    <TextBlock Text="Filter by KB number or title..." FontStyle="Italic" />
                                                </VisualBrush.Visual>
                                            </VisualBrush>
                                        </Style.Resources>
                                        <Style.Triggers>
                                            <Trigger Property="Text" Value="">
                                                <Setter Property="Background" Value="{StaticResource HintBrush}" />
                                            </Trigger>
                                            <Trigger Property="IsKeyboardFocused" Value="True">
                                                <Setter Property="Background" Value="White" />
                                            </Trigger>
                                        </Style.Triggers>
                                    </Style>
                                </TextBox.Style>
                            </TextBox>
                            <Button x:Name="btnSearchInstalled" Grid.Column="1" Content="Search" Padding="15,8" 
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                        </Grid>
                        
                        <DataGrid x:Name="dgInstalledUpdates" AutoGenerateColumns="False" HeadersVisibility="Column"
                                IsReadOnly="True" BorderThickness="1" BorderBrush="#DDDDDD"
                                Background="White" RowBackground="White" AlternatingRowBackground="#F8F8F8"
                                VerticalScrollBarVisibility="Auto" Height="400">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="KB Number" Binding="{Binding HotFixID}" Width="100"/>
                                <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="*"/>
                                <DataGridTextColumn Header="Installed On" Binding="{Binding InstalledOn}" Width="150"/>
                                <DataGridTemplateColumn Header="Actions" Width="100">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Button Content="Remove" Tag="{Binding HotFixID}" x:Name="btnRemoveUpdate"
                                                    Padding="10,5" Margin="5" Background="#E81123" Foreground="White" BorderThickness="0"/>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>
                            </DataGrid.Columns>
                        </DataGrid>
                        
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                            <Button x:Name="btnRefreshInstalled" Content="Refresh" Padding="15,8" Margin="0,0,10,0"
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                            <Button x:Name="btnExportInstalled" Content="Export List" Padding="15,8" 
                                    Background="#107C10" Foreground="White" BorderThickness="0"/>
                        </StackPanel>
                    </StackPanel>
                </Grid>
                
                <!-- Available Updates Page -->
                <Grid x:Name="availableUpdatesPage" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="Available Windows Updates" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,20"/>
                        
                        <!-- Progress Bar -->
                        <ProgressBar x:Name="progressAvailableUpdates" IsIndeterminate="True" Height="10" Margin="0,0,0,10" Visibility="Collapsed"/>
                        
                        <Grid Margin="0,0,0,10">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            
                            <StackPanel Grid.Column="0" Orientation="Horizontal">
                                <CheckBox x:Name="chkCriticalUpdates" Content="Critical Updates" IsChecked="True" Margin="0,0,15,0"/>
                                <CheckBox x:Name="chkSecurityUpdates" Content="Security Updates" IsChecked="True" Margin="0,0,15,0"/>
                                <CheckBox x:Name="chkDefinitionUpdates" Content="Definition Updates" IsChecked="True" Margin="0,0,15,0"/>
                                <CheckBox x:Name="chkFeatureUpdates" Content="Feature Updates" IsChecked="False"/>
                            </StackPanel>
                            
                            <Button x:Name="btnSearchAvailable" Grid.Column="1" Content="Search for Updates" Padding="15,8" Margin="10,0"
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                            <Button x:Name="btnInstallAll" Grid.Column="2" Content="Install All" Padding="15,8" 
                                    Background="#107C10" Foreground="White" BorderThickness="0"/>
                        </Grid>
                        
                        <ProgressBar x:Name="progressUpdates" Height="5" Margin="0,0,0,10" Visibility="Collapsed"/>
                        
                        <DataGrid x:Name="dgAvailableUpdates" AutoGenerateColumns="False" HeadersVisibility="Column"
                                IsReadOnly="False" BorderThickness="1" BorderBrush="#DDDDDD" 
                                Background="White" RowBackground="White" AlternatingRowBackground="#F8F8F8"
                                VerticalScrollBarVisibility="Auto" Height="400">
                            <DataGrid.Columns>
                                <DataGridCheckBoxColumn Header="Select" Binding="{Binding IsSelected}" Width="80"/>
                                <DataGridTextColumn Header="KB Number" Binding="{Binding KBArticleID}" Width="100"/>
                                <DataGridTextColumn Header="Title" Binding="{Binding Title}" Width="*"/>
                                <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="120"/>
                                <DataGridTextColumn Header="Size" Binding="{Binding Size}" Width="100"/>
                                <DataGridTemplateColumn Header="Actions" Width="120">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Button Content="Install" Tag="{Binding Identity}" x:Name="btnInstallUpdate"
                                                    Padding="10,5" Margin="5" Background="#107C10" Foreground="White" BorderThickness="0"/>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>
                            </DataGrid.Columns>
                        </DataGrid>
                        
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                            <Button x:Name="btnInstallSelected" Content="Install Selected" Padding="15,8" Margin="0,0,10,0"
                                    Background="#107C10" Foreground="White" BorderThickness="0"/>
                            <Button x:Name="btnDownloadSelected" Content="Download Selected" Padding="15,8" 
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                        </StackPanel>
                    </StackPanel>
                </Grid>
                
                <!-- WSUS Settings Page -->
                <Grid x:Name="wsusSettingsPage" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="WSUS Settings " FontSize="22" FontWeight="SemiBold" Margin="0,0,0,20"/>
                        
                        <!-- TabControl for advanced WSUS settings -->
                        <TabControl Background="Transparent" BorderThickness="0" Margin="0,0,0,0">
                            <!-- Tab 1: Status -->
                            <TabItem Header="Status">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Current WSUS Configuration" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                </Grid.RowDefinitions>
                                                
                                                <TextBlock Grid.Row="0" Grid.Column="0" Text="WSUS Server:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="0" Grid.Column="1" x:Name="txtWSUSServer" Text="Wird geladen..." Margin="0,5,0,5"/>
                                                
                                                <TextBlock Grid.Row="1" Grid.Column="0" Text="WSUS Status:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="1" Grid.Column="1" x:Name="txtWSUSStatus" Text="Wird geladen..." Margin="0,5,0,5"/>
                                                
                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Target Group:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="2" Grid.Column="1" x:Name="txtWSUSTargetGroup" Text="Wird geladen..." Margin="0,5,0,5"/>
                                                
                                                <TextBlock Grid.Row="3" Grid.Column="0" Text="Configuration Source:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="3" Grid.Column="1" x:Name="txtWSUSConfigSource" Text="Wird geladen..." Margin="0,5,0,5"/>
                                                
                                                <TextBlock Grid.Row="4" Grid.Column="0" Text="Last Check:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="4" Grid.Column="1" x:Name="txtWSUSLastCheck" Text="Wird geladen..." Margin="0,5,0,5"/>
                                            </Grid>
                                        </StackPanel>
                                    </Border>
                                    
                                    <Border Background="#F0F7FF" BorderBrush="#99CCF9" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Reset WSUS Settings" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Resetting the WSUS settings will cause the client to receive updates directly from Microsoft again.
                                                The existing WSUS configuration will be removed and the Windows Update services will be restarted.
                                            </TextBlock>
                                            <Button x:Name="btnResetWSUS" Content="Reset WSUS Settings" Padding="15,8" 
                                                    Background="#E81123" Foreground="White" BorderThickness="0" HorizontalAlignment="Left"/>
                                        </StackPanel>
                                    </Border>
                                    
                                    <Border Background="#F5FFF0" BorderBrush="#99F9CC" BorderThickness="1" Padding="15" CornerRadius="4">
                                        <StackPanel>
                                            <TextBlock Text="Check WSUS Connection" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Checks the connection to the configured WSUS server and synchronizes the client settings.
                                            </TextBlock>
                                            <StackPanel Orientation="Horizontal">
                                                <Button x:Name="btnCheckWSUSConn" Content="Check WSUS Connection" Padding="15,8" 
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnDetectNow" Content="Start Update Detection" Padding="15,8" 
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>
                            
                            <!-- Tab 2: Manuelle Konfiguration -->
                            <TabItem Header="Manual Configuration">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Manually configure WSUS Server" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Configure the connection to a WSUS server here. These settings temporarily override Group Policy settings.
                                            </TextBlock>
                                            
                                            <Grid Margin="0,0,0,15">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                </Grid.RowDefinitions>
                                                
                                                <TextBlock Grid.Row="0" Grid.Column="0" Text="WSUS-Server:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <TextBox Grid.Row="0" Grid.Column="1" x:Name="txtManualWSUSServer" Margin="0,5,0,5" Padding="5,3"/>
                                                
                                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Port:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <TextBox Grid.Row="1" Grid.Column="1" x:Name="txtManualWSUSPort" Margin="0,5,0,5" Padding="5,3" Text="8530"/>
                                                
                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Use SSL:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <CheckBox Grid.Row="2" Grid.Column="1" x:Name="chkManualWSUSUseSSL" Margin="0,5,0,5" Content="Use SSL/TLS for the connection"/>
                                                
                                                <TextBlock Grid.Row="3" Grid.Column="0" Text="Target Group:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="3" Grid.Column="1" x:Name="cmbManualWSUSTargetGroup" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Standard"/>
                                                </ComboBox>
                                            </Grid>
                                            
                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnLoadWSUSTargetGroups" Content="Load Target Groups" Padding="15,8" 
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnApplyManualWSUS" Content="Apply Configuration" Padding="15,8" 
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>
                            
                            <!-- Tab 3: Group Policy -->
                            <TabItem Header="Group Policy">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Windows Update Group Policy" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                These settings reflect the current Group Policy settings for Windows Update. Changes are stored at the user level and can override local settings.
                                            </TextBlock>
                                            
                                            <Grid Margin="0,0,0,15">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                </Grid.RowDefinitions>
                                                
                                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Automatische Updates:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="0" Grid.Column="1" x:Name="cmbAutoUpdateSetting" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Enabled"/>
                                                    <ComboBoxItem Content="Disabled"/>
                                                </ComboBox>
                                                
                                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Configuration Type:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="1" Grid.Column="1" x:Name="cmbUpdateConfigType" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Notify only"/>
                                                    <ComboBoxItem Content="Download and notify"/>
                                                    <ComboBoxItem Content="Download and install automatically"/>
                                                </ComboBox>
                                                
                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Install Time:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="2" Grid.Column="1" x:Name="cmbInstallTime" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="03:00"/>
                                                    <ComboBoxItem Content="04:00"/>
                                                    <ComboBoxItem Content="05:00"/>
                                                    <ComboBoxItem Content="10:00"/>
                                                    <ComboBoxItem Content="15:00"/>
                                                    <ComboBoxItem Content="22:00"/>
                                                </ComboBox>
                                                
                                                <TextBlock Grid.Row="3" Grid.Column="0" Text="Show notifications:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <CheckBox Grid.Row="3" Grid.Column="1" x:Name="chkShowNotifications" Margin="0,5,0,5" Content="Show notifications"/>
                                                
                                                <TextBlock Grid.Row="4" Grid.Column="0" Text="Reboot Behavior:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="4" Grid.Column="1" x:Name="cmbRebootBehavior" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Immediately reboot"/>
                                                    <ComboBoxItem Content="User notification"/>
                                                    <ComboBoxItem Content="Automatically after 15 minutes"/>
                                                    <ComboBoxItem Content="Scheduled reboot"/>
                                                </ComboBox>
                                            </Grid>
                                            
                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnRefreshGPOSettings" Content="Update settings" Padding="15,8" 
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnApplyGPOSettings" Content="Apply settings" Padding="15,8" 
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>
                            
                            <!-- Tab 4: Target Groups -->
                            <TabItem Header="Target Groups">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="WSUS Target Groups" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Typical WSUS target groups (client-side targeting). The selected group must exist on the WSUS server. You can change the target group for this computer.
                                            </TextBlock>
                                            
                                            <DataGrid x:Name="dgWSUSTargetGroups" AutoGenerateColumns="False" Margin="0,0,0,15" 
                                                      HeadersVisibility="Column" CanUserAddRows="False" Height="200">
                                                <DataGrid.Columns>
                                                    <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="2*" />
                                                    <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="3*" />
                                                    <DataGridTextColumn Header="Computer" Binding="{Binding ComputerCount}" Width="*" />
                                                </DataGrid.Columns>
                                            </DataGrid>
                                            
                                            <Grid Margin="0,10,0,15">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                
                                                <TextBlock Grid.Column="0" Text="Current Target Group:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                                <TextBlock Grid.Column="1" x:Name="txtCurrentTargetGroup" Text="Loading..." VerticalAlignment="Center"/>
                                            </Grid>
                                            
                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnRefreshTargetGroups" Content="Refresh Target Groups" Padding="15,8" 
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnSetTargetGroup" Content="Set Target Group" Padding="15,8" 
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>
                            
                            <!-- Tab 5: Synchronisierung -->
                            <TabItem Header="Synchronization">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="WSUS Synchronization Control" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Here you can control the synchronization with the WSUS server and view the history.
                                            </TextBlock>
                                            
                                            <Grid Margin="0,0,0,15">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                </Grid.RowDefinitions>
                                                
                                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Last Synchronization:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="0" Grid.Column="1" x:Name="txtLastSyncTime" Text="Loading..." VerticalAlignment="Center" Margin="0,5,0,5"/>
                                                
                                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Synchronization Interval:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="1" Grid.Column="1" x:Name="cmbSyncInterval" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Automatically (Windows-Standard)"/>
                                                    <ComboBoxItem Content="Daily"/>
                                                    <ComboBoxItem Content="Weekly"/>
                                                    <ComboBoxItem Content="Monthly"/>
                                                </ComboBox>
                                                
                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Automatic Synchronization:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <CheckBox Grid.Row="2" Grid.Column="1" x:Name="chkAutoSync" Margin="0,5,0,5" Content="Enable automatic synchronization" IsChecked="True"/>
                                            </Grid>
                                            
                                            <TextBlock Text="Synchronization History" FontWeight="SemiBold" Margin="0,10,0,10"/>
                                            
                                            <DataGrid x:Name="dgSyncHistory" AutoGenerateColumns="False" Margin="0,0,0,15" 
                                                      HeadersVisibility="Column" CanUserAddRows="False" Height="150">
                                                <DataGrid.Columns>
                                                    <DataGridTextColumn Header="Date" Binding="{Binding Date}" Width="*" />
                                                    <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="*" />
                                                    <DataGridTextColumn Header="Details" Binding="{Binding Details}" Width="2*" />
                                                </DataGrid.Columns>
                                            </DataGrid>
                                            
                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnSaveWSUSSyncSettings" Content="Save Settings" Padding="15,8" 
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnStartWSUSSync" Content="Start Synchronization" Padding="15,8" 
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>

                            <!-- Tab 6: Zeitplanung -->
                            <TabItem Header="Schedule">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Windows Update Schedule" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Configure here when Windows Updates should be automatically searched, downloaded and installed.
                                            </TextBlock>
                                            
                                            <!-- Enable/Disable automatic updates -->
                                            <CheckBox x:Name="chkEnableAutoUpdates" Content="Enable automatic updates" Margin="0,0,0,10"/>
                                            
                                            <!-- Konfiguration für automatische Updates -->
                                            <Grid Margin="0,10,0,0">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="180"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="Auto"/>
                                                </Grid.RowDefinitions>
                                                
                                                <!-- Zeile 1: Updatezeitpunkt -->
                                                <TextBlock Grid.Column="0" Grid.Row="0" Text="Update time:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="0" x:Name="cmbUpdateScheduleType" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Daily"/>
                                                    <ComboBoxItem Content="Weekly"/>
                                                    <ComboBoxItem Content="Monthly"/>
                                                </ComboBox>
                                                
                                                <!-- Zeile 2: Wochentag (only visible if weekly is selected) -->
                                                <TextBlock Grid.Column="0" Grid.Row="1" x:Name="lblWeekDay" Text="Weekday:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="1" x:Name="cmbWeekDay" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Monday"/>
                                                    <ComboBoxItem Content="Tuesday"/>
                                                    <ComboBoxItem Content="Wednesday"/>
                                                    <ComboBoxItem Content="Thursday"/>
                                                    <ComboBoxItem Content="Friday"/>
                                                    <ComboBoxItem Content="Saturday"/>
                                                    <ComboBoxItem Content="Sunday"/>
                                                </ComboBox>
                                                
                                                <!-- Zeile 3: Tag des Monats (only visible if monthly is selected) -->
                                                <TextBlock Grid.Column="0" Grid.Row="2" x:Name="lblMonthDay" Text="Month day:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="2" x:Name="cmbMonthDay" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <!-- Tage 1-31 werden dynamisch befüllt -->
                                                </ComboBox>
                                                
                                                <!-- Zeile 4: Time -->
                                                <TextBlock Grid.Column="0" Grid.Row="3" Text="Time:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <StackPanel Grid.Column="1" Grid.Row="3" Orientation="Horizontal" Margin="0,5,0,5">
                                                    <ComboBox x:Name="cmbHour" MinWidth="80" HorizontalAlignment="Left">
                                                        <!-- Stunden werden dynamisch befüllt -->
                                                    </ComboBox>
                                                    <TextBlock Text=":" VerticalAlignment="Center" Margin="5,0"/>
                                                    <ComboBox x:Name="cmbMinute" MinWidth="80" HorizontalAlignment="Left">
                                                        <!-- Minuten werden dynamisch befüllt -->
                                                    </ComboBox>
                                                </StackPanel>
                                                
                                                <!-- Zeile 5: Behavior -->
                                                <TextBlock Grid.Column="0" Grid.Row="4" Text="Behavior:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="4" x:Name="cmbUpdateBehavior" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Only search for updates"/>
                                                    <ComboBoxItem Content="Search and download"/>
                                                    <ComboBoxItem Content="Search, download and install automatically"/>
                                                </ComboBox>
                                                
                                                <!-- Zeile 6: Restart behavior -->
                                                <TextBlock Grid.Column="0" Grid.Row="5" Text="After installation:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="5" x:Name="cmbRestartBehavior" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Notify user"/>
                                                    <ComboBoxItem Content="Automatically restart"/>
                                                    <ComboBoxItem Content="Schedule restart for:"/>
                                                </ComboBox>
                                            </Grid>
                                            
                                            <!-- Restart time (only visible if "Schedule restart for" is selected) -->
                                            <StackPanel x:Name="pnlRestartTime" Orientation="Horizontal" Margin="180,10,0,10">
                                                <ComboBox x:Name="cmbRestartHour" MinWidth="80" HorizontalAlignment="Left">
                                                    <!-- Stunden werden dynamisch befüllt -->
                                                </ComboBox>
                                                <TextBlock Text=":" VerticalAlignment="Center" Margin="5,0"/>
                                                <ComboBox x:Name="cmbRestartMinute" MinWidth="80" HorizontalAlignment="Left">
                                                    <!-- Minuten werden dynamisch befüllt -->
                                                </ComboBox>
                                            </StackPanel>
                                            
                                            <!-- Action buttons -->
                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
                                                <Button x:Name="btnApplySchedule" Content="Apply schedule" Padding="15,8" 
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnViewCurrentSchedule" Content="View current schedule" Padding="15,8"
                                                        Background="#F0F0F0" BorderThickness="1" BorderBrush="#CCCCCC" Margin="0,0,0,0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                    
                                    <!-- Aktuelle Zeitplan-Einstellungen anzeigen -->
                                    <Border Background="#F0F8FF" BorderBrush="#99CCE8" BorderThickness="1" Padding="15" CornerRadius="4">
                                        <StackPanel>
                                            <TextBlock Text="Current Windows Update Schedule" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                            <TextBlock x:Name="txtCurrentSchedule" TextWrapping="Wrap" Margin="0,0,0,10">
                                                No schedule information available. Click on "View current schedule".
                                            </TextBlock>
                                            
                                            <TextBlock x:Name="txtLastRunResult" TextWrapping="Wrap" Margin="0,10,0,0" Visibility="Collapsed">
                                            </TextBlock>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>

                        </TabControl>
                    </StackPanel>
                </Grid>
                
                <!-- Troubleshooting Page -->
                <Grid x:Name="troubleshootingPage" Visibility="Collapsed">
                    <ScrollViewer MaxHeight="750" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel Margin="15,0">
                            <TextBlock Text="Windows Update Troubleshooting" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,10"/>
                            
                            <!-- Warning -->
                            <Border Background="#FFF4F4" BorderBrush="#FFCECE" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock TextWrapping="Wrap" Margin="0,0,0,5">
                                        <Bold>Warning:</Bold> The following actions can reset or repair Windows Update components. It is recommended to create a system restore point first.
                                    </TextBlock>
                                    <Button x:Name="btnCreateRestorePoint" Content="Create System Restore Point" Padding="10,5" 
                                            Background="#0078D7" Foreground="White" BorderThickness="0"
                                            HorizontalAlignment="Right" Margin="0,5,0,0"/>
                                </StackPanel>
                            </Border>
                            
                            <!-- Grid for standard functions -->
                            <TextBlock Text="Standard Troubleshooting" FontSize="16" FontWeight="SemiBold" Margin="0,5,0,10"/>
                            <Grid Margin="0,0,0,10">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                
                                <!-- Reset components -->
                                <Border Grid.Column="0" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Reset Components" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Resets Windows Update components and services to their default state.
                                        </TextBlock>
                                        <Button x:Name="btnResetComponents" Content="Reset" Padding="10,5" 
                                                Background="#E81123" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Check system files -->
                                <Border Grid.Column="1" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Check System Files" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Runs SFC and DISM tools to scan and repair corrupted system files that may affect updates.
                                        </TextBlock>
                                        <Button x:Name="btnCheckSystemFiles" Content="Check" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Clear update history -->
                                <Border Grid.Column="2" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Clear Update History" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Clears update history, caches, and temporary files to resolve update installation issues.
                                        </TextBlock>
                                        <Button x:Name="btnClearUpdateHistory" Content="Clear" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Re-register DLLs -->
                                <Border Grid.Column="3" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="Re-register DLLs" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Re-registers critical Windows Update DLL files to fix component registration issues.
                                        </TextBlock>
                                        <Button x:Name="btnRegisterDLLs" Content="Register" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Remove stuck updates -->
                                <Border Grid.Column="0" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Stuck Updates" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Removes stuck BITS jobs and pending updates that may be blocking the update process.
                                        </TextBlock>
                                        <Button x:Name="btnClearStuckUpdates" Content="Remove" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Additional box 1 -->
                                <Border Grid.Column="1" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Clean Temp Files" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Removes temporary files that might interfere with the update process.
                                        </TextBlock>
                                        <Button x:Name="btnCleanTemp" Content="Clean" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Additional box 2 -->
                                <Border Grid.Column="2" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Reset WinSock" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Resets network configuration to fix network-related update issues.
                                        </TextBlock>
                                        <Button x:Name="btnResetWinsock" Content="Reset" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Additional box 3 -->
                                <Border Grid.Column="3" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="Check Disk" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Checks disk for errors that might cause update installation failures.
                                        </TextBlock>
                                        <Button x:Name="btnCheckDisk" Content="Check" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                            </Grid>
                            
                            <!-- Grid for advanced functions -->
                            <TextBlock Text="Advanced Troubleshooting Options" FontSize="16" FontWeight="SemiBold" Margin="0,5,0,10"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                
                                <!-- Error diagnosis -->
                                <Border Grid.Column="0" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Error Diagnosis" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Analyzes Windows Update error codes and provides targeted solutions for specific issues.
                                        </TextBlock>
                                        <Button x:Name="btnDiagnoseError" Content="Diagnose" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Repair BITS -->
                                <Border Grid.Column="1" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Repair BITS Service" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Repairs the Background Intelligent Transfer Service which is essential for downloading updates.
                                        </TextBlock>
                                        <Button x:Name="btnRepairBITS" Content="Repair" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Check WaaSMedic -->
                                <Border Grid.Column="2" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Check WaaSMedic" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Checks and repairs Windows Update Medic Service which helps maintain update functionality.
                                        </TextBlock>
                                        <Button x:Name="btnWaaSMedic" Content="Check" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Analyze update logs -->
                                <Border Grid.Column="3" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="Analyze Logs" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Analyzes Windows Update logs to identify specific errors and troubleshooting information.
                                        </TextBlock>
                                        <Button x:Name="btnAnalyzeLogs" Content="Analyze" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Repair registry -->
                                <Border Grid.Column="0" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Repair Registry" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Repairs registry settings related to Windows Update to restore proper functionality.
                                        </TextBlock>
                                        <Button x:Name="btnRepairRegistry" Content="Repair" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Repair database -->
                                <Border Grid.Column="1" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Repair Database" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Repairs the Windows Update database to fix corruption issues that prevent updates.
                                        </TextBlock>
                                        <Button x:Name="btnRepairDatabase" Content="Repair" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Toggle debug mode -->
                                <Border Grid.Column="2" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Debug Mode" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Toggles enhanced logging and diagnostic features for advanced troubleshooting.
                                        </TextBlock>
                                        <Button x:Name="btnToggleDebug" Content="Toggle" Padding="10,5" 
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                                
                                <!-- Auto-Fix -->
                                <Border Grid.Column="3" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="Auto-Fix" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Runs comprehensive automatic troubleshooting to identify and fix common update issues.
                                        </TextBlock>
                                        <Button x:Name="btnAutoFix" Content="Start" Padding="10,5" 
                                                Background="#107C10" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Grid>
        </Grid>
        
        <!-- Footer -->
        <Border Grid.Row="2" Background="#F0F0F0" BorderBrush="#DDDDDD" BorderThickness="0,1,0,0">
            <Grid Margin="20,0">
                <TextBlock x:Name="statusText" Text="Ready" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock x:Name="versionText" Text="easyWINUpdate v0.2.4 - PhinIT" FontStyle="Italic" Foreground="#555555"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# XAML-Reader erstellen und GUI laden
try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    try {
        $window = [Windows.Markup.XamlReader]::Load($reader)
        # Erfolgreiche Meldung
        Write-Host "GUI wurde erfolgreich geladen." -ForegroundColor Green
    } catch {
        Write-Error "Fehler beim Laden des XAML: $($_.Exception.Message)"
        if ($_.Exception.Message -like '*PlaceholderText*') {
            Write-Host "The 'PlaceholderText' property is not supported in WPF." -ForegroundColor Yellow
            Write-Host "Please replace it with a WPF-compatible solution, such as a TextBox with VisualBrush." -ForegroundColor Yellow
        }
        exit
    }
} catch {
    Write-Error "Fehler beim Erstellen des XmlNodeReader: $($_.Exception.Message)"
    exit
}

# Hauptfunktionen des Scripts
#region Hilfsfunktionen

# Funktion zum Aktualisieren des Status-Textes
function Update-StatusText {
    param (
        [string]$Text,
        [string]$Color = "Black"
    )
    
    $statusText = $window.FindName("statusText")
    $statusText.Text = $Text
    $statusText.Foreground = $Color

    $logLevel = switch ($Color) { 'Red' { 'ERROR' } 'Yellow' { 'WARN' } default { 'INFO' } }
    Write-AppLog -Message $Text -Level $logLevel
}

#region Hintergrundverarbeitung (verhindert Einfrieren der GUI)
$script:BackgroundTasks = New-Object System.Collections.ArrayList
$script:BackgroundTimer = $null

# Startet einen Skriptblock in einem eigenen Runspace. Das Ergebnis wird per DispatcherTimer
# im GUI-Thread abgeholt und an -OnCompleted ($Output, $ErrorText) übergeben.
function Start-BackgroundTask {
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [scriptblock]$OnCompleted,
        [string]$Name = 'Hintergrundaufgabe'
    )

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($ScriptBlock.ToString())
    if ($Parameters.Count -gt 0) {
        [void]$ps.AddParameters($Parameters)
    }

    $task = [PSCustomObject]@{
        Name        = $Name
        PowerShell  = $ps
        Handle      = $ps.BeginInvoke()
        OnCompleted = $OnCompleted
    }
    [void]$script:BackgroundTasks.Add($task)
    Write-AppLog -Message "Hintergrundaufgabe gestartet: $Name"

    if (-not $script:BackgroundTimer) {
        $script:BackgroundTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:BackgroundTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:BackgroundTimer.Add_Tick({ Complete-BackgroundTasks })
    }
    $script:BackgroundTimer.Start()
}

function Complete-BackgroundTasks {
    foreach ($task in @($script:BackgroundTasks)) {
        if (-not $task.Handle.IsCompleted) { continue }
        [void]$script:BackgroundTasks.Remove($task)

        $output = @()
        $errorText = $null
        try {
            $output = @($task.PowerShell.EndInvoke($task.Handle))
            if ($task.PowerShell.Streams.Error.Count -gt 0) {
                $errorText = ($task.PowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
            }
        } catch {
            $errorText = $_.Exception.Message
        } finally {
            $task.PowerShell.Runspace.Dispose()
            $task.PowerShell.Dispose()
        }

        Write-AppLog -Message "Hintergrundaufgabe beendet: $($task.Name)$(if ($errorText) { " (Fehler: $errorText)" })" -Level $(if ($errorText) { 'WARN' } else { 'INFO' })
        if ($task.OnCompleted) {
            try {
                & $task.OnCompleted $output $errorText
            } catch {
                Update-StatusText -Text "Fehler bei der Verarbeitung von '$($task.Name)': $_" -Color "Red"
            }
        }
    }
    if ($script:BackgroundTasks.Count -eq 0 -and $script:BackgroundTimer) {
        $script:BackgroundTimer.Stop()
    }
}

# Führt eine im Skript definierte Funktion im Hintergrund aus (Update-StatusText wird dort ignoriert)
function Start-FunctionInBackground {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FunctionName,
        [hashtable]$FunctionParameters = @{},
        [string[]]$HelperFunctions = @(),
        [scriptblock]$OnCompleted
    )

    $helperText = foreach ($helper in $HelperFunctions) {
        "function $helper {`n$((Get-Command -Name $helper -CommandType Function).ScriptBlock.ToString())`n}`n"
    }
    $functionBody = (Get-Command -Name $FunctionName -CommandType Function).ScriptBlock.ToString()
    $scriptText = @"
param([hashtable]`$FunctionParameters)
function Update-StatusText { param([string]`$Text, [string]`$Color) }
$($helperText -join "`n")
function $FunctionName {
$functionBody
}
$FunctionName @FunctionParameters
"@
    Start-BackgroundTask -Name $FunctionName -ScriptBlock ([scriptblock]::Create($scriptText)) -Parameters @{ FunctionParameters = $FunctionParameters } -OnCompleted $OnCompleted
}

# Öffnet ein Konsolenfenster für lang laufende Kommandozeilen-Tools (DISM, SFC, CHKDSK),
# damit die GUI bedienbar bleibt und der Fortschritt sichtbar ist.
function Start-ConsoleTool {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CommandLine,
        [string]$Title = 'easyWINUpdate'
    )
    $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    Start-Process -FilePath $cmdExe -ArgumentList "/k title $Title & $CommandLine" -ErrorAction Stop | Out-Null
    Write-AppLog -Message "Konsolen-Tool gestartet: $CommandLine"
}
#endregion

# Startet die Update-Erkennung (Windows 10/11/Server 2016+: UsoClient, ältere Systeme: wuauclt)
function Start-UpdateDetection {
    param (
        [switch]$ResetAuthorization
    )
    $usoClient = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
    if ([Environment]::OSVersion.Version.Major -ge 10 -and (Test-Path -LiteralPath $usoClient)) {
        & $usoClient StartScan 2>&1 | Out-Null
    } else {
        $wuArgs = @()
        if ($ResetAuthorization) { $wuArgs += '/resetauthorization' }
        $wuArgs += '/detectnow'
        & (Join-Path $env:SystemRoot 'System32\wuauclt.exe') @wuArgs 2>&1 | Out-Null
    }
}

# Manuelle WSUS-Konfiguration anwenden
$btnApplyManualWSUS = $window.FindName("btnApplyManualWSUS")
$btnApplyManualWSUS.Add_Click({
    # Eingaben aus der GUI auslesen
    $txtManualWSUSServer = $window.FindName("txtManualWSUSServer")
    $txtManualWSUSPort = $window.FindName("txtManualWSUSPort")
    $chkManualWSUSUseSSL = $window.FindName("chkManualWSUSUseSSL")
    $cmbManualWSUSTargetGroup = $window.FindName("cmbManualWSUSTargetGroup")
    
    $wsusServer = $txtManualWSUSServer.Text.Trim()
    $wsusPort = 0
    $useSSL = [bool]$chkManualWSUSUseSSL.IsChecked
    $targetGroup = if ($cmbManualWSUSTargetGroup.SelectedItem) { $cmbManualWSUSTargetGroup.SelectedItem.Content } else { "Standard" }
    
    # Prüfen, ob ein Server angegeben wurde
    if ([string]::IsNullOrEmpty($wsusServer)) {
        [System.Windows.MessageBox]::Show(
            "Please specify a WSUS server.",
            "Missing Input",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }

    # Servername (Hostname/FQDN/IPv4) und Port validieren
    if ($wsusServer -notmatch '^[A-Za-z0-9]([A-Za-z0-9\-\.]{0,252})$' -or
        -not [int]::TryParse($txtManualWSUSPort.Text.Trim(), [ref]$wsusPort) -or $wsusPort -lt 1 -or $wsusPort -gt 65535) {
        [System.Windows.MessageBox]::Show(
            "Ungültiger WSUS-Servername oder Port. Bitte nur den Hostnamen/FQDN (ohne http://) und einen Port zwischen 1 und 65535 angeben.",
            "Ungültige Eingabe",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }
    
    # Bestätigung anfordern
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to apply the specified WSUS configuration? This change can override Group Policy settings and may require a restart of the Windows Update service.",
        "Apply WSUS Configuration",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        # WSUS-Konfiguration anwenden
        Update-StatusText -Text "Applying manual WSUS configuration..." -Color "Blue"
        
        $success = Set-ManualWSUSConfiguration -WSUSServer $wsusServer -WSUSPort $wsusPort -UseSSL $useSSL -TargetGroup $targetGroup
        
        if ($success) {
            Update-StatusText -Text "WSUS configuration applied successfully." -Color "Green"
            
            # WSUS-Seite neu laden
            Load-WSUSSettingsPage
        } else {
            Update-StatusText -Text "Failed to apply WSUS configuration." -Color "Red"
        }
    }
})

# WSUS-Zielgruppen laden
$btnLoadWSUSTargetGroups = $window.FindName("btnLoadWSUSTargetGroups")
$btnLoadWSUSTargetGroups.Add_Click({
    # WSUS-Server-Einstellungen auslesen
    $txtManualWSUSServer = $window.FindName("txtManualWSUSServer")
    $txtManualWSUSPort = $window.FindName("txtManualWSUSPort")
    $chkManualWSUSUseSSL = $window.FindName("chkManualWSUSUseSSL")
    $cmbManualWSUSTargetGroup = $window.FindName("cmbManualWSUSTargetGroup")
    
    $wsusServer = $txtManualWSUSServer.Text.Trim()
    $wsusPort = 8530
    if (-not [int]::TryParse($txtManualWSUSPort.Text.Trim(), [ref]$wsusPort)) { $wsusPort = 8530 }
    $useSSL = [bool]$chkManualWSUSUseSSL.IsChecked
    # Prüfen, ob ein Server angegeben wurde
    if ([string]::IsNullOrEmpty($wsusServer)) {
        [System.Windows.MessageBox]::Show(
            "Bitte geben Sie einen WSUS-Server an.",
            "Fehlende Eingabe",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }
    
    # Zielgruppen laden
    Update-StatusText -Text "Lade WSUS-Zielgruppen..." -Color "Blue"
    
    try {
        $targetGroups = Get-WSUSTargetGroups -WSUSServer $wsusServer -WSUSPort $wsusPort -UseSSL $useSSL
        
        if ($targetGroups -and $targetGroups.Count -gt 0) {
            # ComboBox leeren und neu befüllen
            $cmbManualWSUSTargetGroup.Items.Clear()
            
            foreach ($group in $targetGroups) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $group.Name
                $cmbManualWSUSTargetGroup.Items.Add($item)
            }
            
            # Ersten Eintrag auswählen
            $cmbManualWSUSTargetGroup.SelectedIndex = 0
            
            Update-StatusText -Text "$($targetGroups.Count) WSUS-Zielgruppen geladen." -Color "Green"
        } else {
            Update-StatusText -Text "No WSUS target groups found." -Color "Yellow"
            
            # Standard-Eintrag hinzufügen
            $cmbManualWSUSTargetGroup.Items.Clear()
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = "Standard"
            $cmbManualWSUSTargetGroup.Items.Add($item)
            $cmbManualWSUSTargetGroup.SelectedIndex = 0
        }
    } catch {
        Update-StatusText -Text "Failed to load WSUS target groups: $_" -Color "Red"
    }
})

# Initialize Status
$statusText = $window.FindName("statusText")
$statusText.Text = "Ready"

# Funktion zum Überprüfen der Update-Quelle
function Get-UpdateSource {
    $wsusSettings = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
    $wsusUrl = $wsusSettings.WUServer
    
    if ($wsusUrl) {
        return "WSUS ($wsusUrl)"
    }
    
    $intuneRegistered = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\*" -ErrorAction SilentlyContinue | 
                        Where-Object { $_.ProviderID -eq "MS DM Server" -and $_.EnrollmentState -eq 1 }
    
    if ($intuneRegistered) {
        return "Microsoft Intune"
    }
    
    return "Windows Update (Microsoft)"
}

# Funktion zum Abrufen des letzten Update-Datums
function Get-LastUpdateDate {
    $lastUpdate = Get-HotFix | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1 -ExpandProperty InstalledOn
    
    if ($lastUpdate) {
        return $lastUpdate.ToString("dd.MM.yyyy HH:mm")
    } else {
        return "No updates found"
    }
}
# Function to diagnose Windows Update error codes
function Diagnose-WindowsUpdateError {
    param (
        [string]$ErrorCode = ""
    )
    
    try {
        Update-StatusText -Text "Analysiere Windows Update-Fehler..." -Color "Blue"
        
        # Wenn kein Fehlercode uebergeben wurde, versuche den letzten Fehlercode aus dem Ereignisprotokoll zu holen
        if ([string]::IsNullOrEmpty($ErrorCode)) {
            $lastError = Get-WinEvent -LogName "Microsoft-Windows-WindowsUpdateClient/Operational" -MaxEvents 50 -ErrorAction SilentlyContinue | 
                Where-Object { $_.Level -eq 2 -or $_.Message -like "*0x8*" } | 
                Select-Object -First 1
                
            if ($lastError) {
                # Extrahiere den Fehlercode aus der Nachricht (Format 0x8xxxxxxx)
                $codeMatches = [regex]::Matches($lastError.Message, "0x8[0-9A-Fa-f]{7}")
                if ($codeMatches.Count -gt 0) {
                    $ErrorCode = $codeMatches[0].Value
                }
            }
        }
        
        # Verwende die globale Fehlercode-Tabelle
        # Wenn ein bekannter Fehlercode gefunden wurde
        if ($ErrorCode -and $errorCodes.ContainsKey($ErrorCode)) {
            $errorInfo = $errorCodes[$ErrorCode]
            
            # Erstelle die Ausgabe
            $output = "Windows Update error code: $ErrorCode`r`n"
            $output += "Description: $($errorInfo.Description)`r`n"
            $output += "Recommended Solutions:`r`n"
            
            foreach ($solution in $errorInfo.Solutions) {
                $output += "- $solution`r`n"
            }
            
            Update-StatusText -Text "Error code analysis completed." -Color "Green"
            return $output
        }
        elseif ([string]::IsNullOrEmpty($ErrorCode)) {
            Update-StatusText -Text "No Windows Update error code found." -Color "Yellow"
            return "No Windows Update error code found."
        }
        else {
            Update-StatusText -Text "Unknown error code: $ErrorCode" -Color "Yellow"
            return "Unknown Windows Update error code: $ErrorCode"
        }
    }
    catch {
        Update-StatusText -Text "Error analyzing Windows Update error: $_" -Color "Red"
        return "Error analyzing Windows Update error: $_"
    }
}

# Function to perform an extended BITS repair
function Repair-BITSService {
    try {
        Update-StatusText -Text "Performing extended BITS repair..." -Color "Blue"
        
        # BITS-Warteschlange löschen (muss vor dem Stoppen des Dienstes erfolgen)
        Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue
        
        # BITS-Dienst stoppen
        Stop-Service -Name BITS -Force
        
        # BITS-Verzeichnisse bereinigen
        $qmgrFiles = @(
            "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\qmgr*.dat",
            "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader\qmgr*.dat"
        )
        
        foreach ($file in $qmgrFiles) {
            if (Test-Path $file) {
                Remove-Item -Path $file -Force
            }
        }
        
        # Registry-Einträge für BITS zurücksetzen
        $bitsSvcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\BITS"
        
        # Dienststarttyp auf Automatisch setzen
        Set-ItemProperty -Path $bitsSvcKey -Name "Start" -Value 2
        
        # Sicherheitsbeschreibungen zurücksetzen (direkter Aufruf statt Invoke-Expression)
        $bitsSddl = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'
        $scOutput = & "$env:SystemRoot\System32\sc.exe" sdset bits $bitsSddl 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "sc.exe sdset bits fehlgeschlagen (ExitCode $LASTEXITCODE): $scOutput"
        }
        
        # BITS-Dienst neu starten
        Start-Service -Name BITS
        
        Update-StatusText -Text "BITS service repaired successfully." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Error repairing BITS service: $_" -Color "Red"
        return $false
    }
}

# Function to check and repair the WaaSMedic service
function Repair-WaaSMedicService {
    try {
        Update-StatusText -Text "Checking Windows Update Medic Service..." -Color "Blue"
        
        # Check if the service exists (only on newer Windows versions)
        $waasService = Get-Service -Name WaaSMedicSvc -ErrorAction SilentlyContinue
        
        if (-not $waasService) {
            Update-StatusText -Text "Windows Update Medic Service (WaaSMedicSvc) ist auf diesem System nicht verfügbar." -Color "Yellow"
            return $false
        }
        
        # Prüfen und korrigieren des Dienststarttyps
        if ($waasService.StartType -ne "Automatic") {
            Set-Service -Name WaaSMedicSvc -StartupType Automatic
            Update-StatusText -Text "WaaSMedicSvc-Starttyp auf Automatisch gesetzt." -Color "Blue"
        }
        
        # Dienst starten, falls er nicht läuft
        if ($waasService.Status -ne "Running") {
            Start-Service -Name WaaSMedicSvc
            Update-StatusText -Text "WaaSMedicSvc-Dienst gestartet." -Color "Blue"
        }
        
        # Überprüfen der Registry-Einstellungen
        $waasKey = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
        if (Test-Path $waasKey) {
            $startValue = (Get-ItemProperty -Path $waasKey -Name "Start").Start
            if ($startValue -ne 2) {
                Set-ItemProperty -Path $waasKey -Name "Start" -Value 2
                Update-StatusText -Text "WaaSMedicSvc registry settings corrected." -Color "Blue"
            }
        }
        
        Update-StatusText -Text "Windows Update Medic Service checked and repaired." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Error checking and repairing Windows Update Medic Service: $_" -Color "Red"
        return $false
    }
}
# Function to analyze Windows Update logs
function Analyze-WindowsUpdateLogs {
    param (
        [string]$OutputDirectory = $env:TEMP
    )
    try {
        Update-StatusText -Text "Analysiere Windows Update-Logs..." -Color "Blue"
        
        # Pfad zum Windows Update Log je nach Windows-Version
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $osVersion = [Version]$osInfo.Version
        
        if ($osVersion -ge [Version]"10.0") {
            # Windows 10/11: Logs konvertieren (ETL -> Text)
            if (-not $OutputDirectory -or -not (Test-Path -LiteralPath $OutputDirectory)) { $OutputDirectory = $env:TEMP }
            $logPath = Join-Path $OutputDirectory ("WindowsUpdate_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            Get-WindowsUpdateLog -LogPath $logPath | Out-Null
        } else {
            # Ältere Windows-Versionen
            $logPath = "$env:SystemRoot\WindowsUpdate.log"
        }
        
        if (-not (Test-Path $logPath)) {
            Update-StatusText -Text "Windows Update log not found." -Color "Yellow"
            return "Windows Update log not found."
        }
        
        # Log file size check
        $logFile = Get-Item $logPath
        if ($logFile.Length -gt 5MB) {
            Update-StatusText -Text "Windows Update-Log ist sehr groß ($(($logFile.Length / 1MB).ToString('0.00')) MB)." -Color "Yellow"
        }
        
        # Fehler im Log suchen
        $errorKeywords = @(
            "Fehler", "Error", "0x8", "FATAL", "WARNING", "Failed", "Fehlgeschlagen"
        )
        
        $logContent = Get-Content -Path $logPath -Tail 1000 -ErrorAction SilentlyContinue
        $logErrors = @($logContent | Where-Object { 
            $line = $_
            $foundKeyword = $false
            foreach ($keyword in $errorKeywords) {
                if ($line -match $keyword) {
                    $foundKeyword = $true
                    break
                }
            }
            $foundKeyword
        } | Select-Object -Last 20)
        
        if ($logErrors.Count -eq 0) {
            Update-StatusText -Text "No obvious errors found in Windows Update logs." -Color "Green"
            return "No distinct errors found in the last 1000 log entries.`r`nLog: $logPath"
        } else {
            Update-StatusText -Text "Errors found in Windows Update logs." -Color "Yellow"
            
            $output = "The last 20 error messages from the Windows Update logs ($logPath):`r`n"
            foreach ($logLine in $logErrors) {
                $output += "- $logLine`r`n"
            }
            
            return $output
        }
    } catch {
        Update-StatusText -Text "Error analyzing Windows Update logs: $_" -Color "Red"
        return "Error analyzing logs: $_"
    }
}
# Function to repair common registry issues with Windows Update
function Repair-WindowsUpdateRegistry {
    try {
        Update-StatusText -Text "Repairing Windows Update registry settings..." -Color "Blue"
        
        # Important Windows Update registry paths
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate",
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
        )
        
        # Problematische Registry-Werte prüfen und korrigieren
        foreach ($path in $registryPaths) {
            # Prüfen, ob der Pfad existiert
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
                Update-StatusText -Text "Registry-Pfad erstellt: $path" -Color "Blue"
            }
            
            # Überprüfung und Korrektur spezifischer Schlüsselwerte
            if ($path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update") {
                # AUOptions prüfen (falls auf deaktiviert) - AUOptions ist ein Registry-Wert, kein Schlüssel
                $auOptions = (Get-ItemProperty -Path $path -Name "AUOptions" -ErrorAction SilentlyContinue).AUOptions
                if ($null -ne $auOptions -and $auOptions -eq 1) {
                    Set-ItemProperty -Path $path -Name "AUOptions" -Value 3 # Auf "Herunterladen aber nicht installieren" setzen
                    Update-StatusText -Text "Automatische Updates were disabled - set to 'Download but do not install'." -Color "Blue"
                }
            }
        }
        
        # Windows Update-Dienste auf den richtigen Starttyp setzen
        $updateServices = @(
            @{Name = "wuauserv"; StartupType = "Automatic"; DisplayName = "Windows Update"},
            @{Name = "bits"; StartupType = "Manual"; DisplayName = "Background Intelligent Transfer Service"},
            @{Name = "cryptsvc"; StartupType = "Automatic"; DisplayName = "Cryptographic Services"},
            @{Name = "trustedinstaller"; StartupType = "Manual"; DisplayName = "Windows Modules Installer"}
        )
        
        foreach ($service in $updateServices) {
            $svc = Get-Service -Name $service.Name -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.StartType -ne $service.StartupType) {
                    Set-Service -Name $service.Name -StartupType $service.StartupType
                    Update-StatusText -Text "$($service.DisplayName)-Dienst auf $($service.StartupType) gesetzt." -Color "Blue"
                }
            }
        }
        
        # Debugging-Modus für Windows Update ausschalten (falls aktiviert)
        $wuTraceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Trace"
        if (Test-Path $wuTraceKey) {
            $flags = (Get-ItemProperty -Path $wuTraceKey -ErrorAction SilentlyContinue).Flags
            if ($flags -eq 1) {
                Set-ItemProperty -Path $wuTraceKey -Name "Flags" -Value 0
                Update-StatusText -Text "Windows Update-Debugging deaktiviert." -Color "Blue"
            }
        }
        
        Update-StatusText -Text "Windows Update registry settings have been repaired." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Error repairing registry settings: $_" -Color "Red"
        return $false
    }
}
# Function to repair the Windows Update database
function Repair-WindowsUpdateDatabase {
    try {
        Update-StatusText -Text "Repairing Windows Update database..." -Color "Blue"
        
        # Windows Update services stop
        $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver', 'appidsvc')
        foreach ($service in $services) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        }
        
        # SoftwareDistribution-Ordner umbenennen (nicht löschen)
        $sdFolder = "$env:SystemRoot\SoftwareDistribution"
        $sdBackup = "$env:SystemRoot\SoftwareDistribution.bak"
        $catroot2Folder = "$env:SystemRoot\System32\catroot2"
        $catroot2Backup = "$env:SystemRoot\System32\catroot2.bak"
        
        if (Test-Path $sdFolder) {
            # Altes Backup entfernen, falls vorhanden
            if (Test-Path $sdBackup) {
                Remove-Item -Path $sdBackup -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Umbenennen statt löschen
            Rename-Item -Path $sdFolder -NewName "SoftwareDistribution.bak" -Force -ErrorAction SilentlyContinue
            New-Item -Path $sdFolder -ItemType Directory -Force | Out-Null
        }
        
        if (Test-Path $catroot2Folder) {
            # Altes Backup entfernen, falls vorhanden
            if (Test-Path $catroot2Backup) {
                Remove-Item -Path $catroot2Backup -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Umbenennen statt löschen
            Rename-Item -Path $catroot2Folder -NewName "catroot2.bak" -Force -ErrorAction SilentlyContinue
            # catroot2 wird automatisch neu erstellt, daher kein New-Item notwendig
        }
        
        # Datenbankdateien zurücksetzen
        $dbFiles = @(
            "$env:SystemRoot\WindowsUpdate.log",
            "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader\qmgr*.dat",
            "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\qmgr*.dat"
        )
        
        foreach ($file in $dbFiles) {
            if (Test-Path $file) {
                Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
            }
        }
        
        # WSUS Client-Einstellungen zurücksetzen (wenn vorhanden)
        $wsusClientKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\WSUS\Client"
        if (Test-Path $wsusClientKey) {
            Remove-Item -Path $wsusClientKey -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Dienste wieder starten
        foreach ($service in $services) {
            Start-Service -Name $service -ErrorAction SilentlyContinue
        }
        
        # Update-Erkennung erzwingen
        Start-UpdateDetection -ResetAuthorization
        
        Update-StatusText -Text "Windows Update database has been repaired. The system should be restarted." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Error repairing the Windows Update database: $_" -Color "Red"
        return $false
    }
}
# Funktion zum Aktivieren/Deaktivieren des Fehlersuchmodus für Windows Update
function Toggle-WindowsUpdateDebugMode {
    param (
        [bool]$Enable = $true
    )
    
    try {
        if ($Enable) {
            Update-StatusText -Text "Activating Windows Update error search mode..." -Color "Blue"
            
            # Registry-Pfad für Windows Update-Trace erstellen oder aktualisieren
            $wuTraceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Trace"
            if (-not (Test-Path $wuTraceKey)) {
                New-Item -Path $wuTraceKey -Force | Out-Null
            }
            
            # Trace-Flag setzen
            New-ItemProperty -Path $wuTraceKey -Name "Flags" -Value 1 -PropertyType DWord -Force | Out-Null
            
            # Detaillierte Protokollierung aktivieren
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Setup"
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            New-ItemProperty -Path $regPath -Name "EnableVerboseLogging" -Value 1 -PropertyType DWord -Force | Out-Null
            
            Update-StatusText -Text "Windows Update error search mode has been activated. Try the update operation again and check the logs." -Color "Green"
            return $true
        } else {
            Update-StatusText -Text "Deactivating Windows Update error search mode..." -Color "Blue"
            
            # Registry-Pfad für Windows Update-Trace aktualisieren
            $wuTraceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Trace"
            if (Test-Path $wuTraceKey) {
                Set-ItemProperty -Path $wuTraceKey -Name "Flags" -Value 0 -Force | Out-Null
            }
            
            # Detaillierte Protokollierung deaktivieren
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Setup"
            if (Test-Path $regPath) {
                Set-ItemProperty -Path $regPath -Name "EnableVerboseLogging" -Value 0 -Force | Out-Null
            }
            
            Update-StatusText -Text "Windows Update error search mode has been disabled." -Color "Green"
            return $true
        }
    } catch {
        Update-StatusText -Text "Error changing Windows Update error search mode: $_" -Color "Red"
        return $false
    }
}


# Funktion zum Abrufen der WSUS-Einstellungen
function Get-WSUSSettings {
    $wsusSettings = @{
        Server = $null
        Status = "Not configured"
        TargetGroup = "None"
        ConfigSource = "Not configured"
        LastCheck = "Unknown"
    }
    
    $wuPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
    $wuSettings = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -ErrorAction SilentlyContinue
    
    if ($wuPolicies) {
        $wsusSettings.Server = $wuPolicies.WUServer
        $wsusSettings.Status = if ($wsusSettings.Server) { "Active" } else { "Not configured" }
        $wsusSettings.TargetGroup = if ($wuPolicies.TargetGroupEnabled -eq 1) { $wuPolicies.TargetGroup } else { "None" }
        
        if ($wsusSettings.Server) {
            if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate") {
                $wsusSettings.ConfigSource = "Group Policy"
            } elseif (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\WSUS") {
                $wsusSettings.ConfigSource = "Manuell konfiguriert"
            } else {
                $wsusSettings.ConfigSource = "Unbekannt"
            }
        }
    }
    
    if ($wuSettings -and $wuSettings.LastWUAutoupdate) {
        try {
            $lastCheckTime = [DateTime]::FromFileTime($wuSettings.LastWUAutoupdate)
            $wsusSettings.LastCheck = $lastCheckTime.ToString("dd.MM.yyyy HH:mm")
        } catch {
            $wsusSettings.LastCheck = "Error converting date"
        }
    }
    
    return $wsusSettings
}
# Funktion zur automatischen Analyse und Behebung von Windows Update-Problemen
function Auto-FixWindowsUpdateIssues {
    try {
        Update-StatusText -Text "Starte automatische Behebung von Windows Update-Problemen..." -Color "Blue"
        
        # Step 1: Windows Update Service check
        $wuauserv = Get-Service -Name wuauserv
        if ($wuauserv.Status -ne "Running" -or $wuauserv.StartType -ne "Automatic") {
            Update-StatusText -Text "Windows Update Service is not correctly configured. Fixing..." -Color "Yellow"
            Set-Service -Name wuauserv -StartupType Automatic
            Start-Service -Name wuauserv
        }
        
        # Step 2: Analyze existing errors
        $lastError = Get-WinEvent -LogName "Microsoft-Windows-WindowsUpdateClient/Operational" -MaxEvents 50 -ErrorAction SilentlyContinue | 
            Where-Object { $_.Level -eq 2 -or $_.Message -like "*0x8*" } | 
            Select-Object -First 1
        
        $errorCode = ""
        if ($lastError) {
            $codeMatches = [regex]::Matches($lastError.Message, "0x8[0-9A-Fa-f]{7}")
            if ($codeMatches.Count -gt 0) {
                $errorCode = $codeMatches[0].Value
                Update-StatusText -Text "Last Windows Update error code: $errorCode" -Color "Yellow"
            }
        }
        
        # Step 3: Specific error correction based on error code
        $specificFix = $false
        
        switch ($errorCode) {
            "0x80240034" { # Download error
                Update-StatusText -Text "Download error detected. Fixing network issues..." -Color "Yellow"
                Clear-WindowsUpdateHistory
                Repair-BITSService
                $specificFix = $true
            }
            "0x8024001F" { # No connection
                Update-StatusText -Text "Connection problem detected. Checking network settings..." -Color "Yellow"
                Repair-BITSService
                Reset-WindowsUpdateComponents
                $specificFix = $true
            }
            "0x80070020" { # File locked
                Update-StatusText -Text "File locked problem detected. Cleaning Windows Update database..." -Color "Yellow"
                Repair-WindowsUpdateDatabase
                $specificFix = $true
            }
            "0x80240022" { # All updates failed
                Update-StatusText -Text "Critical update problem detected. Performing full repair..." -Color "Yellow"
                Reset-WindowsUpdateComponents
                Repair-WindowsSystemFiles
                $specificFix = $true
            }
            "0x80070422" { # Service disabled
                Update-StatusText -Text "Windows Update service disabled. Activating services..." -Color "Yellow"
                Repair-WindowsUpdateRegistry
                $specificFix = $true
            }
            "0x8024402C" { # DNS resolution problem
                Update-StatusText -Text "DNS problem detected. Resetting network settings..." -Color "Yellow"
                # Netzwerkeinstellungen zurücksetzen
                ipconfig.exe /flushdns | Out-Null
                ipconfig.exe /registerdns | Out-Null
                $specificFix = $true
            }
        }
        
        # Step 4: General repair if no specific fix was applied
        if (-not $specificFix) {
            Update-StatusText -Text "Performing general repair actions..." -Color "Blue"
            
            # Windows Update components reset
            Reset-WindowsUpdateComponents
            
            # WaaSMedic service repair (on newer Windows versions)
            $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
            $osVersion = [Version]$osInfo.Version
            if ($osVersion -ge [Version]"10.0.17134") {
                Repair-WaaSMedicService
            }
            
            # Registry-Einstellungen reparieren
            Repair-WindowsUpdateRegistry
        }
        
        # Step 5: Update services restart
        Update-StatusText -Text "Restarting Windows Update services..." -Color "Blue"
        Restart-Service -Name wuauserv -Force
        Restart-Service -Name bits -Force
        
        # Step 6: Update detection forced
        Update-StatusText -Text "Forcing update detection..." -Color "Blue"
        Start-UpdateDetection -ResetAuthorization
        
        Update-StatusText -Text "Automatic error correction completed. It is recommended to restart the computer." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Error during automatic error correction: $_" -Color "Red"
        return $false
    }
}
# Funktion zum Zurücksetzen der WSUS-Einstellungen
function Reset-WSUSSettings {
    try {
        # Nur WSUS-relevante Werte entfernen (andere Windows Update-Richtlinien bleiben erhalten)
        $wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auRegPath = "$wuRegPath\AU"
        if (Test-Path $wuRegPath) {
            foreach ($valueName in @('WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate', 'TargetGroup', 'TargetGroupEnabled')) {
                Remove-ItemProperty -Path $wuRegPath -Name $valueName -ErrorAction SilentlyContinue
            }
        }
        if (Test-Path $auRegPath) {
            Remove-ItemProperty -Path $auRegPath -Name 'UseWUServer' -ErrorAction SilentlyContinue
        }
        
        # WindowsUpdate-Dienst-Client ID zurücksetzen
        Stop-Service -Name wuauserv -Force
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientId" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientIDValidation" -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv
        Restart-Service -Name bits -Force
        
        # Client-Aktualisierung erzwingen
        Start-UpdateDetection -ResetAuthorization
        
        return $true
    } catch {
        Write-Error "Fehler beim Zurücksetzen der WSUS-Einstellungen: $_"
        return $false
    }
}

# Funktion zum Abrufen installeder Updates
function Get-InstalledWindowsUpdates {
    try {
        $hotfixes = Get-HotFix | Select-Object @{Name="HotFixID"; Expression={$_.HotFixID}}, 
                                                @{Name="Description"; Expression={$_.Description}}, 
                                                @{Name="InstalledOn"; Expression={if($_.InstalledOn){$_.InstalledOn.ToString("dd.MM.yyyy")}else{"Unbekannt"}}}
        
        return $hotfixes
    } catch {
        Write-Error "Fehler beim Abrufen der installeden Updates: $_"
        return $null
    }
}

# Funktion zum Abrufen verfügbarer Updates (Windows Update Agent COM-API, Standard-Updatequelle inkl. WSUS)
function Get-AvailableWindowsUpdates {
    param (
        [bool]$IncludeCritical = $true,
        [bool]$IncludeSecurity = $true,
        [bool]$IncludeDefinition = $true,
        [bool]$IncludeFeature = $false
    )
    
    try {
        Write-Verbose "Suche nach Windows Updates..."
        
        # Kategorien basierend auf Parametern bestimmen ("Andere" wird immer angezeigt)
        $categoryFilter = @("Andere")
        if ($IncludeCritical) { $categoryFilter += "Critical Updates" }
        if ($IncludeSecurity) { $categoryFilter += "Security Updates" }
        if ($IncludeDefinition) { $categoryFilter += "Definition Updates" }
        if ($IncludeFeature) { $categoryFilter += "Feature Packs" }
        
        # Windows Update COM-Objekt erstellen
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        # Suchkriterien definieren (ausgeblendete Updates nicht anzeigen)
        $searchCriteria = "IsInstalled=0 and IsHidden=0"
        
        # Nach Updates suchen
        $searchResult = $updateSearcher.Search($searchCriteria)
        
        # Updates filtern und formatieren
        $updates = @()
        foreach ($update in $searchResult.Updates) {
            # Kategorie anhand der WU-Kategorien bzw. MSRC-Schweregrad bestimmen
            $categoryNames = @($update.Categories | ForEach-Object { $_.Name })
            $category = "Andere"
            if ($update.MsrcSeverity -eq "Critical" -or $categoryNames -contains "Critical Updates") { $category = "Critical Updates" }
            elseif ($categoryNames -contains "Security Updates" -or $update.MsrcSeverity) { $category = "Security Updates" }
            elseif ($categoryNames -contains "Definition Updates" -or $update.Title -match 'Definition|Security Intelligence') { $category = "Definition Updates" }
            elseif ($categoryNames -contains "Feature Packs" -or $categoryNames -contains "Upgrades" -or $update.Title -like "*Feature*") { $category = "Feature Packs" }
            
            # Prüfen, ob Update der ausgewählten Kategorie entspricht
            if ($categoryFilter -contains $category) {
                # KB-Nummer extrahieren
                $kbNumber = if ($update.KBArticleIDs.Count -gt 0) { "KB$($update.KBArticleIDs.Item(0))" } else {
                    $kbMatch = [regex]::Match($update.Title, 'KB\d+')
                    if ($kbMatch.Success) { $kbMatch.Value } else { "Unbekannt" }
                }
                
                $updates += [PSCustomObject]@{
                    IsSelected = $false
                    KBArticleID = $kbNumber
                    Title = $update.Title
                    Category = $category
                    Size = if ($update.MaxDownloadSize -gt 0) { "$([Math]::Round($update.MaxDownloadSize / 1MB, 2)) MB" } else { "Unbekannt" }
                    Identity = [string]$update.Identity.UpdateID
                }
            }
        }
        
        return $updates
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Error "Error fetching available updates: $errorMessage"
        return $null
    }
}

# Funktion zum Entfernen eines Windows Updates
function Remove-WindowsUpdateKB {
    param (
        [string]$KBNumber
    )
    
    try {
        $kbID = ($KBNumber.Trim() -replace '^(?i)KB', '')
        if ($kbID -notmatch '^\d{4,8}$') {
            throw "Ungültige KB-Nummer: '$KBNumber'"
        }
        $KBNumber = "KB$kbID"
        
        $wusaPath = Join-Path $env:SystemRoot 'System32\wusa.exe'
        $process = Start-Process -FilePath $wusaPath -ArgumentList "/uninstall", "/kb:$kbID", "/quiet", "/norestart" -Wait -PassThru -ErrorAction Stop
        
        # 0 = Erfolg, 3010 = Erfolg, Neustart erforderlich
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "wusa.exe beendet mit ExitCode $($process.ExitCode) (2359303 = Update nicht installiert / nicht deinstallierbar)"
        }
        
        return $true
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Error ("Error removing Windows Update " + $KBNumber + ": " + $errorMessage)
        return $false
    }
}

# Function to get service status
function Get-ServiceStatusInfo {
    param (
        [string]$ServiceName
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        
        return @{
            Status = $service.Status
            DisplayName = $service.DisplayName
            StatusText = if ($service.Status -eq "Running") { "Aktiv" } else { "Gestoppt" }
            StatusColor = if ($service.Status -eq "Running") { "Green" } else { "Red" }
        }
    } catch {
        return @{
            Status = "Unknown"
            DisplayName = "Service not found"
            StatusText = "Error"
            StatusColor = "Red"
        }
    }
}

# Funktion zum Testen der WSUS-Verbindung (TCP-Verbindung zum WSUS-Port statt ICMP-Ping)
function Test-WSUSConnection {
    param (
        [string]$WSUSServer,
        [int]$TimeoutMilliseconds = 3000
    )
    
    try {
        if (-not $WSUSServer -or $WSUSServer -eq "Not configured") {
            return $false
        }
        
        # Server-URL zerlegen (Standardports: 8530 HTTP, 8531 HTTPS)
        $serverName = $WSUSServer
        $port = 8530
        if ($WSUSServer -match "^(https?)://([^/:]+)(?::([0-9]+))?") {
            $serverName = $Matches[2]
            if ($Matches[3]) {
                $port = [int]$Matches[3]
            } elseif ($Matches[1] -eq 'https') {
                $port = 8531
            }
        }
        
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        try {
            $connectTask = $tcpClient.ConnectAsync($serverName, $port)
            $connected = $connectTask.Wait($TimeoutMilliseconds) -and $tcpClient.Connected
        } finally {
            $tcpClient.Dispose()
        }
        return [bool]$connected
    } catch {
        return $false
    }
}

# Funktion zum Abrufen von verfügbaren WSUS-Zielgruppen
function Get-WSUSTargetGroups {
    param (
        [string]$WSUSServer,
        [int]$WSUSPort = 8530,
        [bool]$UseSSL = $false
    )
    
    try {
        # Dummy-Funktion, da echte WSUS-API erfordert WSUS-Admin-Console auf dem Client
        # In einer Produktionsumgebung würde hier die echte WSUS-API verwendet werden
        $targetGroups = @(
            [PSCustomObject]@{
                Name = "Unassigned Computers"
                Description = "Computers not assigned to any group"
                ComputerCount = "N/A"
            },
            [PSCustomObject]@{
                Name = "Standard"
                Description = "Standard group for all computers"
                ComputerCount = "N/A"
            },
            [PSCustomObject]@{
                Name = "Testgroup"
                Description = "Testgroup for preview updates"
                ComputerCount = "N/A"
            },
            [PSCustomObject]@{
                Name = "Workstations"
                Description = "All workstations"
                ComputerCount = "N/A"
            },
            [PSCustomObject]@{
                Name = "Server"
                Description = "All servers"
                ComputerCount = "N/A"
            }
        )
        return $targetGroups
    } catch {
        Write-Error "Error retrieving WSUS target groups: $_"
        return @()
    }
}

# Function to retrieve Windows Update Group Policy settings
function Get-WindowsUpdateGPOSettings {
    try {
        # Registry-Pfade für Windows Update Einstellungen
        $wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auRegPath = "$wuRegPath\AU"
        
        # Standardwerte setzen
        $settings = @{
            AutoUpdateEnabled = $true
            ConfigType = 3 # Automatisch herunterladen und installieren
            InstallTime = 3 # 3:00 AM
            ShowNotifications = $true
            RebootBehavior = 0 # Benutzer benachrichtigen
        }
        
        # Prüfen, ob Gruppenrichtlinien für Windows Update vorhanden sind
        if (Test-Path $auRegPath) {
            # Automatische Updates aktiviert/deaktiviert
            $noAutoUpdate = Get-ItemProperty -Path $auRegPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
            if ($null -ne $noAutoUpdate) {
                $settings.AutoUpdateEnabled = ($noAutoUpdate.NoAutoUpdate -eq 0)
            }
            
            # Konfigurationstyp
            $auOptions = Get-ItemProperty -Path $auRegPath -Name "AUOptions" -ErrorAction SilentlyContinue
            if ($null -ne $auOptions) {
                $settings.ConfigType = $auOptions.AUOptions
            }
            
            # Installationszeit
            $scheduledInstallTime = Get-ItemProperty -Path $auRegPath -Name "ScheduledInstallTime" -ErrorAction SilentlyContinue
            if ($null -ne $scheduledInstallTime) {
                $settings.InstallTime = $scheduledInstallTime.ScheduledInstallTime
            }
            
            # Benachrichtigungen
            $noAutoUpdateNotification = Get-ItemProperty -Path $auRegPath -Name "NoAutoUpdateNotification" -ErrorAction SilentlyContinue
            if ($null -ne $noAutoUpdateNotification) {
                $settings.ShowNotifications = ($noAutoUpdateNotification.NoAutoUpdateNotification -eq 0)
            }
            
            # Neustart-Verhalten
            $rebootRelaunchTimeout = Get-ItemProperty -Path $auRegPath -Name "RebootRelaunchTimeout" -ErrorAction SilentlyContinue
            if ($null -ne $rebootRelaunchTimeout) {
                $settings.RebootBehavior = if ($rebootRelaunchTimeout.RebootRelaunchTimeout -gt 0) { 1 } else { 0 }
            }
        }
        
        return $settings
    } catch {
        Write-Error "Error fetching Windows Update Group Policy settings: $_"
        return $null
    }
}

# Funktion zum Setzen der Windows Update Gruppenrichtlinieneinstellungen
function Set-WindowsUpdateGPOSettings {
    param (
        [bool]$AutoUpdateEnabled,
        [int]$ConfigType,
        [int]$InstallTime,
        [bool]$ShowNotifications,
        [int]$RebootBehavior
    )
    
    try {
        # Registry-Pfade für Windows Update Einstellungen
        $wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auRegPath = "$wuRegPath\AU"
        
        # Sicherstellen, dass die Registry-Pfade existieren
        if (-not (Test-Path $wuRegPath)) {
            New-Item -Path $wuRegPath -Force | Out-Null
        }
        if (-not (Test-Path $auRegPath)) {
            New-Item -Path $auRegPath -Force | Out-Null
        }
        
        # Automatische Updates aktivieren/deaktivieren
        Set-ItemProperty -Path $auRegPath -Name "NoAutoUpdate" -Value ([int](-not $AutoUpdateEnabled)) -Type DWord
        
        # Konfigurationstyp
        Set-ItemProperty -Path $auRegPath -Name "AUOptions" -Value $ConfigType -Type DWord
        
        # Installationszeit
        Set-ItemProperty -Path $auRegPath -Name "ScheduledInstallTime" -Value $InstallTime -Type DWord
        
        # Benachrichtigungen
        Set-ItemProperty -Path $auRegPath -Name "NoAutoUpdateNotification" -Value ([int](-not $ShowNotifications)) -Type DWord
        
        # Neustart-Verhalten (RebootRelaunchTimeout ist nur mit RebootRelaunchTimeoutEnabled wirksam, gültig 1-1440 Minuten)
        if ($RebootBehavior -eq 0) {
            Remove-ItemProperty -Path $auRegPath -Name "RebootRelaunchTimeout" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $auRegPath -Name "RebootRelaunchTimeoutEnabled" -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty -Path $auRegPath -Name "RebootRelaunchTimeoutEnabled" -Value 1 -Type DWord
            Set-ItemProperty -Path $auRegPath -Name "RebootRelaunchTimeout" -Value 15 -Type DWord
        }
        
        # Windows Update-Dienste neu starten
        Restart-Service -Name wuauserv -Force
        
        return $true
    } catch {
        Write-Error "Error setting Windows Update Group Policy settings: $_"
        return $false
    }
}

# Funktion zum Setzen der manuellen WSUS-Konfiguration
function Set-ManualWSUSConfiguration {
    param (
        [string]$WSUSServer,
        [int]$WSUSPort,
        [bool]$UseSSL,
        [string]$TargetGroup
    )
    
    try {
        # Registry-Pfade für Windows Update Einstellungen
        $wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        
        # Sicherstellen, dass die Registry-Pfade existieren
        if (-not (Test-Path $wuRegPath)) {
            New-Item -Path $wuRegPath -Force | Out-Null
        }
        
        # WSUS-Server-URL erstellen
        $protocol = if ($UseSSL) { "https" } else { "http" }
        $wsusUrl = "${protocol}://${WSUSServer}:${WSUSPort}"
        
        # WSUS-Einstellungen setzen
        Set-ItemProperty -Path $wuRegPath -Name "WUServer" -Value $wsusUrl -Type String
        Set-ItemProperty -Path $wuRegPath -Name "WUStatusServer" -Value $wsusUrl -Type String
        
        # UseWUServer aktivieren
        $auRegPath = "$wuRegPath\AU"
        if (-not (Test-Path $auRegPath)) {
            New-Item -Path $auRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $auRegPath -Name "UseWUServer" -Value 1 -Type DWord
        
        # Zielgruppe setzen, falls angegeben
        if (-not [string]::IsNullOrEmpty($TargetGroup) -and $TargetGroup -ne "Standard") {
            Set-ItemProperty -Path $wuRegPath -Name "TargetGroup" -Value $TargetGroup -Type String
            Set-ItemProperty -Path $wuRegPath -Name "TargetGroupEnabled" -Value 1 -Type DWord
        } else {
            # Zielgruppe deaktivieren
            Remove-ItemProperty -Path $wuRegPath -Name "TargetGroup" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuRegPath -Name "TargetGroupEnabled" -Value 0 -Type DWord
        }
        
        # Windows Update-Dienste neu starten
        Restart-Service -Name wuauserv -Force
        
        return $true
    } catch {
        Write-Error "Error setting manual WSUS configuration: $_"
        return $false
    }
}

# Funktion zum Verwalten der WSUS-Synchronisierung
function Start-WSUSSynchronization {
    try {
        # WSUS-Synchronisierung starten (Client-seitig: Update-Erkennung gegen die konfigurierte Quelle)
        Update-StatusText -Text "Starte WSUS-Synchronisierung..." -Color "Blue"
        Start-UpdateDetection
        Update-StatusText -Text "WSUS-Synchronisierung (Update-Erkennung) wurde gestartet." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Error starting WSUS synchronization: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Abrufen des Synchronisierungsverlaufs (Update-Suchen) aus dem Ereignisprotokoll
function Get-WSUSSyncHistory {
    param (
        [int]$MaxEntries = 20
    )
    try {
        # Ereignis-ID 26 = Suche erfolgreich, 25 = Suche fehlgeschlagen (Microsoft-Windows-WindowsUpdateClient)
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'
            Id      = 25, 26
        } -MaxEvents $MaxEntries -ErrorAction SilentlyContinue
        
        $syncHistory = foreach ($wuEvent in $events) {
            [PSCustomObject]@{
                Date    = $wuEvent.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                Status  = if ($wuEvent.Id -eq 26) { "Success" } else { "Error" }
                Details = ($wuEvent.Message -split "`r?`n")[0]
            }
        }
        
        if (-not $syncHistory) {
            return @([PSCustomObject]@{
                Date    = "-"
                Status  = "-"
                Details = "Keine Einträge im Ereignisprotokoll gefunden"
            })
        }
        return @($syncHistory)
    } catch {
        Write-Error "Error fetching WSUS sync history: $_"
        return @()
    }
}

# Funktion zum Setzen der WSUS-Synchronisierungseinstellungen
function Set-WSUSSyncSettings {
    param (
        [string]$SyncInterval,
        [bool]$AutoSync
    )
    
    try {
        # Registry-Pfade für Windows Update Einstellungen
        $wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auRegPath = "$wuRegPath\AU"
        
        # Sicherstellen, dass die Registry-Pfade existieren
        if (-not (Test-Path $wuRegPath)) {
            New-Item -Path $wuRegPath -Force | Out-Null
        }
        if (-not (Test-Path $auRegPath)) {
            New-Item -Path $auRegPath -Force | Out-Null
        }
        
        # Automatische Synchronisierung aktivieren/deaktivieren
        if ($AutoSync) {
            # Automatische Updates aktivieren
            Set-ItemProperty -Path $auRegPath -Name "NoAutoUpdate" -Value 0 -Type DWord
            
            # Erkennungsintervall setzen. Die Richtlinie "DetectionFrequency" erwartet STUNDEN (1-22)
            # und wirkt nur zusammen mit DetectionFrequencyEnabled = 1. Längere Intervalle sind nicht möglich.
            if ($SyncInterval -match '^(Daily|Täglich|Weekly|Wöchentlich|Monthly|Monatlich)') {
                Set-ItemProperty -Path $auRegPath -Name "DetectionFrequencyEnabled" -Value 1 -Type DWord
                Set-ItemProperty -Path $auRegPath -Name "DetectionFrequency" -Value 22 -Type DWord
            } else {
                # Standard Windows-Einstellung (automatisch)
                Remove-ItemProperty -Path $auRegPath -Name "DetectionFrequency" -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $auRegPath -Name "DetectionFrequencyEnabled" -ErrorAction SilentlyContinue
            }
        } else {
            # Automatische Updates deaktivieren
            Set-ItemProperty -Path $auRegPath -Name "NoAutoUpdate" -Value 1 -Type DWord
        }
        
        # Windows Update-Dienste neu starten
        Restart-Service -Name wuauserv -Force
        
        return $true
    } catch {
        Write-Error "Fehler beim Setzen der WSUS-Synchronisierungseinstellungen: $_"
        return $false
    }
}

# Funktion zum Abrufen der Windows-Version
function Get-WindowsVersionInfo {
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $versionCaption = $osInfo.Caption
        $versionBuild = $osInfo.BuildNumber
        $versionInfo = "$versionCaption (Build $versionBuild)"
        
        return $versionInfo
    } catch {
        Write-Error "Fehler beim Abrufen der Windows-Version: $_"
        return "Unbekannt"
    }
}

# Funktion zum Erstellen eines Systemwiederherstellungspunkts
function New-SystemRestorePoint {
    try {
        # Systemwiederherstellungspunkt erstellen
        $description = "Vor Windows Update Troubleshooting"
        Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        return $true
    } catch {
        Write-Error "Fehler beim Erstellen des Systemwiederherstellungspunkts: $_"
        return $false
    }
}

# Funktion zum Zurücksetzen der Windows Update-Komponenten
function Reset-WindowsUpdateComponents {
    try {
        Update-StatusText -Text "Setze Windows Update-Komponenten zurück..." -Color "Blue"
        
        # Dienste stoppen
        $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver', 'appidsvc', 'trustedinstaller')
        
        # Alle BITS-Jobs löschen (solange der BITS-Dienst noch läuft)
        Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue
        
        foreach ($service in $services) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        }
        
        # Windows Update-Datenbank und Cache-Ordner löschen
        $folders = @("$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2")
        foreach ($folder in $folders) {
            if (Test-Path $folder) {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        # QMGR-Dateien entfernen
        Remove-Item -Path "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\qmgr*.dat" -Force -ErrorAction SilentlyContinue
        
        # Sicherstellen, dass Windows Update-Ordner wieder erstellt werden
        New-Item -Path "$env:SystemRoot\SoftwareDistribution" -ItemType Directory -Force | Out-Null
        
        # Dienste wieder starten
        foreach ($service in $services) {
            Start-Service -Name $service -ErrorAction SilentlyContinue
        }
        
        # Update-Erkennung erzwingen
        Start-UpdateDetection -ResetAuthorization
        
        Update-StatusText -Text "Windows Update-Komponenten wurden zurückgesetzt. System sollte neu gestartet werden." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Fehler beim Zurücksetzen der Windows Update-Komponenten: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Überprüfen und Reparieren von Windows-Systemdateien
function Repair-WindowsSystemFiles {
    try {
        Update-StatusText -Text "Überprüfe Windows-Systemdateien..." -Color "Blue"
        
        # DISM und SFC in einem eigenen Konsolenfenster ausführen (kann 30+ Minuten dauern, GUI bleibt bedienbar)
        Start-ConsoleTool -Title 'easyWINUpdate - DISM und SFC' -CommandLine 'DISM.exe /Online /Cleanup-Image /RestoreHealth & sfc.exe /scannow'
        
        Update-StatusText -Text "DISM /RestoreHealth und SFC /scannow wurden in einem separaten Konsolenfenster gestartet." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Fehler bei der Überprüfung der Windows-Systemdateien: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Löschen des Windows Update-Verlaufs
function Clear-WindowsUpdateHistory {
    try {
        Update-StatusText -Text "Lösche Windows Update-Verlauf..." -Color "Blue"
        
        # Dienste stoppen
        Stop-Service -Name wuauserv -Force
        
        # SoftwareDistribution-Ordner löschen
        if (Test-Path "$env:SystemRoot\SoftwareDistribution") {
            Remove-Item -Path "$env:SystemRoot\SoftwareDistribution" -Recurse -Force
        }
        
        # Windows Update-Log löschen
        if (Test-Path "$env:SystemRoot\WindowsUpdate.log") {
            Remove-Item -Path "$env:SystemRoot\WindowsUpdate.log" -Force
        }
        
        # SoftwareDistribution-Ordner neu erstellen
        New-Item -Path "$env:SystemRoot\SoftwareDistribution" -ItemType Directory -Force | Out-Null
        
        # Dienst wieder starten
        Start-Service -Name wuauserv
        
        Update-StatusText -Text "Windows Update-Verlauf wurde gelöscht." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Fehler beim Löschen des Windows Update-Verlaufs: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Neuregistrieren der Windows Update-DLLs
function Register-WindowsUpdateDLLs {
    try {
        Update-StatusText -Text "Registriere Windows Update-DLLs neu..." -Color "Blue"
        
        # Stoppen der Windows Update-Dienste
        Stop-Service -Name wuauserv -Force
        
        # Wichtige Windows Update-DLLs registrieren
        $dllFiles = @(
            "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll", "jscript.dll", 
            "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll", "msxml6.dll", "actxprxy.dll", 
            "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", 
            "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll", "shell32.dll", "wuapi.dll", 
            "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll", "wuweb.dll", 
            "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll"
        )
        
        foreach ($dll in $dllFiles) {
            $dllPath = Join-Path $env:SystemRoot "System32\$dll"
            if (Test-Path $dllPath) {
                Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s", $dllPath -Wait
            }
        }
        
        # Windows Update-Dienst neu starten
        Start-Service -Name wuauserv
        
        Update-StatusText -Text "Windows Update-DLLs wurden neu registriert." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Fehler beim Neuregistrieren der Windows Update-DLLs: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Entfernen von hängenden Updates und BITS-Jobs
function Clear-StuckUpdatesAndBITSJobs {
    try {
        Update-StatusText -Text "Entferne hängende Updates und BITS-Jobs..." -Color "Blue"
        
        # Alle BITS-Jobs löschen
        Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue
        
        # Gestagte Windows Update-Pakete entfernen
        $stagedUpdates = Get-WindowsPackage -Online | Where-Object { $_.PackageState -eq 'Staged' }
        if ($stagedUpdates) {
            foreach ($update in $stagedUpdates) {
                Remove-WindowsPackage -PackageName $update.PackageName -Online -NoRestart | Out-Null
            }
        }
        
        # Windows Update und BITS-Dienste neu starten
        Restart-Service -Name wuauserv -Force
        Restart-Service -Name bits -Force
        
        # Update-Erkennung erzwingen
        Start-UpdateDetection
        
        Update-StatusText -Text "Hängende Updates und BITS-Jobs wurden entfernt." -Color "Green"
        return $true
    } catch {
        Update-StatusText -Text "Fehler beim Entfernen von hängenden Updates: $_" -Color "Red"
        return $false
    }
}
#endregion

#region Event-Handler und GUI-Logik

# Hauptfunktion zum Laden der Update-Status-Seite
function Load-UpdateStatusPage {
    try {
        # Zuerst sicherstellen, dass die Home-Seite sichtbar ist
        $homePage = $window.FindName("homePage")
        if ($homePage) {
            $homePage.Visibility = "Visible"
            # Andere Seiten ausblenden
            $installedUpdatesPage = $window.FindName("installedUpdatesPage")
            if ($installedUpdatesPage) { $installedUpdatesPage.Visibility = "Collapsed" }
            $availableUpdatesPage = $window.FindName("availableUpdatesPage")
            if ($availableUpdatesPage) { $availableUpdatesPage.Visibility = "Collapsed" }
            $wsusSettingsPage = $window.FindName("wsusSettingsPage")
            if ($wsusSettingsPage) { $wsusSettingsPage.Visibility = "Collapsed" }
            $troubleshootingPage = $window.FindName("troubleshootingPage")
            if ($troubleshootingPage) { $troubleshootingPage.Visibility = "Collapsed" }
            
            # RadioButton auf Home setzen
            $navHome = $window.FindName("navHome")
            if ($navHome) { $navHome.IsChecked = $true }
        }
        
        # Windows-Version anzeigen
        $txtWindowsVersion = $window.FindName("txtWindowsVersion")
        if ($txtWindowsVersion) { 
            try {
                $txtWindowsVersion.Text = Get-WindowsVersionInfo
            } catch {
                $txtWindowsVersion.Text = "Unbekannt"
                Write-Host "Fehler beim Ermitteln der Windows-Version: $_" -ForegroundColor Yellow
            }
        }
        
        # Update-Quelle ermitteln
        $txtUpdateSource = $window.FindName("txtUpdateSource")
        if ($txtUpdateSource) {
            try {
                $useWUServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -ErrorAction SilentlyContinue
                if ($useWUServer -and $useWUServer.UseWUServer -eq 1) {
                    $wuServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -ErrorAction SilentlyContinue
                    if ($wuServer) {
                        $txtUpdateSource.Text = "WSUS: $($wuServer.WUServer)"
                    } else {
                        $txtUpdateSource.Text = "WSUS (Server nicht definiert)"
                    }
                } else {
                    $txtUpdateSource.Text = "Microsoft Windows Update"
                }
            } catch {
                $txtUpdateSource.Text = "Unbekannt"
                Write-Host "Fehler beim Ermitteln der Update-Quelle: $_" -ForegroundColor Yellow
            }
        }
        
        # Installierte Updates nur einmal abfragen (Get-HotFix/WMI ist langsam)
        $installedHotfixes = @()
        $hotfixError = $null
        try {
            $installedHotfixes = @(Get-HotFix -ErrorAction Stop)
        } catch {
            $hotfixError = $_
            Write-Host "Fehler beim Abrufen der installierten Updates: $_" -ForegroundColor Yellow
        }
        
        # Letztes Update ermitteln
        $txtLastUpdate = $window.FindName("txtLastUpdate")
        if ($txtLastUpdate) {
            if ($hotfixError) {
                $txtLastUpdate.Text = "Fehler beim Abrufen der Update-Historie"
            } else {
                $lastUpdate = $installedHotfixes | Where-Object { $_.InstalledOn } | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1 -ExpandProperty InstalledOn
                if ($lastUpdate) {
                    $txtLastUpdate.Text = $lastUpdate.ToString("dd.MM.yyyy")
                } else {
                    $txtLastUpdate.Text = "Keine Updates gefunden"
                }
            }
        }
        
        # Update-Status ermitteln
        $txtUpdateStatus = $window.FindName("txtUpdateStatus")
        if ($txtUpdateStatus) {
            try {
                $pendingRebootKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
                if (Test-Path $pendingRebootKey) {
                    $txtUpdateStatus.Text = "Neustart erforderlich"
                } else {
                    $txtUpdateStatus.Text = "Ready"
                }
            } catch {
                $txtUpdateStatus.Text = "Unbekannt"
                Write-Host "Fehler beim Ermitteln des Update-Status: $_" -ForegroundColor Yellow
            }
        }
        
        # Anzahl installeder Updates ermitteln
        $txtInstalledUpdatesCount = $window.FindName("txtInstalledUpdatesCount")
        if ($txtInstalledUpdatesCount) {
            if ($hotfixError) {
                $txtInstalledUpdatesCount.Text = "Fehler beim Abrufen der Update-Informationen"
            } else {
                $txtInstalledUpdatesCount.Text = "$($installedHotfixes.Count) Updates installed"
            }
        }
        
        # Status-Anzeige aktualisieren
        Update-StatusText -Text "System ready" -Color "Green"
        
    } catch {
        Write-Host "Fehler beim Laden der Update-Status-Seite: $_" -ForegroundColor Red
        Update-StatusText -Text "Fehler beim Laden der Statusinformationen" -Color "Red"
    }
}

# Funktion zum Laden der installeden Updates-Seite
function Load-InstalledUpdatesPage {
    $dgInstalledUpdates = $window.FindName("dgInstalledUpdates")
    $progressUpdates = $window.FindName("progressInstalledUpdates")
    $progressUpdates.Visibility = "Visible"
    $dgInstalledUpdates.ItemsSource = $null
    
    # Temporäre Anzeige während des Ladens
    Update-StatusText -Text "Loading installed updates..." -Color "Blue"
    
    # Get-HotFix im Hintergrund ausführen, damit die GUI nicht blockiert
    Start-BackgroundTask -Name 'Installierte Updates laden' -ScriptBlock {
        Get-HotFix | Select-Object HotFixID, Description, InstalledOn, InstalledBy
    } -OnCompleted {
        param($Output, $ErrorText)
        $dgInstalledUpdates = $window.FindName("dgInstalledUpdates")
        $progressUpdates = $window.FindName("progressInstalledUpdates")
        $progressUpdates.Visibility = "Collapsed"
        
        $hotfixes = @($Output | Where-Object { $_ })
        $script:InstalledUpdatesCache = $hotfixes
        if ($hotfixes.Count -gt 0) {
            $dgInstalledUpdates.ItemsSource = $hotfixes
            Update-StatusText -Text "$($hotfixes.Count) installed updates loaded." -Color "Green"
        } elseif ($ErrorText) {
            Update-StatusText -Text "Fehler beim Laden der installierten Updates: $ErrorText" -Color "Red"
        } else {
            Update-StatusText -Text "No installed updates found." -Color "Blue"
        }
    }
}

# Funktion zum Laden der verfügbaren Updates-Seite (echte Suche über die Windows Update Agent API)
function Load-AvailableUpdatesPage {
    if ($script:AvailableUpdatesSearchRunning) {
        Update-StatusText -Text "Eine Update-Suche läuft bereits..." -Color "Yellow"
        return
    }

    $chkCriticalUpdates = $window.FindName("chkCriticalUpdates")
    $chkSecurityUpdates = $window.FindName("chkSecurityUpdates")
    $chkDefinitionUpdates = $window.FindName("chkDefinitionUpdates")
    $chkFeatureUpdates = $window.FindName("chkFeatureUpdates")
    
    $progressUpdates = $window.FindName("progressAvailableUpdates")
    $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
    
    # UI vorbereiten
    $progressUpdates.Visibility = "Visible"
    $dgAvailableUpdates.ItemsSource = $null
    Update-StatusText -Text "Searching for available updates (this can take several minutes)..." -Color "Blue"
    $script:AvailableUpdatesSearchRunning = $true
    
    $searchParameters = @{
        IncludeCritical   = [bool]$chkCriticalUpdates.IsChecked
        IncludeSecurity   = [bool]$chkSecurityUpdates.IsChecked
        IncludeDefinition = [bool]$chkDefinitionUpdates.IsChecked
        IncludeFeature    = [bool]$chkFeatureUpdates.IsChecked
    }
    
    Start-FunctionInBackground -FunctionName 'Get-AvailableWindowsUpdates' -FunctionParameters $searchParameters -OnCompleted {
        param($Output, $ErrorText)
        $script:AvailableUpdatesSearchRunning = $false
        $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
        $progressUpdates = $window.FindName("progressAvailableUpdates")
        $progressUpdates.Visibility = "Collapsed"
        
        $updates = @($Output | Where-Object { $_ -and $_.PSObject.Properties['Identity'] })
        $dgAvailableUpdates.ItemsSource = $updates
        if ($updates.Count -gt 0) {
            Update-StatusText -Text "$($updates.Count) available updates found." -Color "Green"
        } elseif ($ErrorText) {
            Update-StatusText -Text "Fehler bei der Update-Suche: $ErrorText" -Color "Red"
        } else {
            Update-StatusText -Text "No available updates found." -Color "Blue"
        }
    }
}

# Installiert bzw. lädt Updates (PSWindowsUpdate) im Hintergrund
function Start-UpdateInstallation {
    param (
        [string[]]$UpdateIds = @(),
        [switch]$DownloadOnly,
        [string]$Description = "Updates"
    )

    if ($script:UpdateInstallationRunning) {
        Update-StatusText -Text "Es läuft bereits eine Installation bzw. ein Download." -Color "Yellow"
        return
    }
    $script:UpdateInstallationRunning = $true

    $progressUpdates = $window.FindName("progressUpdates")
    $progressUpdates.IsIndeterminate = $true
    $progressUpdates.Visibility = "Visible"
    $action = if ($DownloadOnly) { "Lade" } else { "Installiere" }
    Update-StatusText -Text "$action $Description..." -Color "Blue"

    Start-BackgroundTask -Name "$action $Description" -Parameters @{ UpdateIds = $UpdateIds; DownloadOnly = [bool]$DownloadOnly } -ScriptBlock {
        param([string[]]$UpdateIds, [bool]$DownloadOnly)
        Import-Module PSWindowsUpdate -ErrorAction Stop
        $wuParams = @{ AcceptAll = $true; Confirm = $false; ErrorAction = 'Stop' }
        if ($UpdateIds -and $UpdateIds.Count -gt 0) { $wuParams.UpdateID = $UpdateIds }
        if ($DownloadOnly) { $wuParams.Download = $true } else { $wuParams.Install = $true; $wuParams.IgnoreReboot = $true }
        Get-WindowsUpdate @wuParams | Select-Object -Property KB, Result, Title
    } -OnCompleted {
        param($Output, $ErrorText)
        $script:UpdateInstallationRunning = $false
        $progressUpdates = $window.FindName("progressUpdates")
        $progressUpdates.Visibility = "Collapsed"
        if ($ErrorText) {
            Update-StatusText -Text "Fehler bei der Update-Verarbeitung: $ErrorText" -Color "Red"
        } else {
            $processed = @($Output | Where-Object { $_ })
            Update-StatusText -Text "Update-Verarbeitung abgeschlossen ($($processed.Count) Einträge). Ein Neustart kann erforderlich sein." -Color "Green"
            foreach ($entry in $processed) { Write-AppLog -Message "Update: $($entry.KB) - $($entry.Result) - $($entry.Title)" }
        }
        Load-AvailableUpdatesPage
    }
}

# Funktion zum Laden der WSUS-Einstellungen-Seite
function Load-WSUSSettingsPage {
    # Aktuelle WSUS-Konfiguration laden
    $txtWSUSServer = $window.FindName("txtWSUSServer")
    $txtWSUSStatus = $window.FindName("txtWSUSStatus")
    $txtWSUSTargetGroup = $window.FindName("txtWSUSTargetGroup")
    $txtWSUSConfigSource = $window.FindName("txtWSUSConfigSource")
    $txtWSUSLastCheck = $window.FindName("txtWSUSLastCheck")
    $txtCurrentTargetGroup = $window.FindName("txtCurrentTargetGroup")
    $txtLastSyncTime = $window.FindName("txtLastSyncTime")
    
    # WSUS-Server ermitteln
    try {
        $wuServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -ErrorAction SilentlyContinue
        if ($wuServer) {
            $txtWSUSServer.Text = $wuServer.WUServer
            
            # Server in das manuelle Konfigurationsfeld übernehmen
            $txtManualWSUSServer = $window.FindName("txtManualWSUSServer")
            if ($txtManualWSUSServer) {
                # Server-URL und Port extrahieren
                if ($wuServer.WUServer -match "http[s]?://([^/:]+)(?::([0-9]+))?/?") {
                    $serverName = $matches[1]
                    $txtManualWSUSServer.Text = $serverName
                    
                    # Port extrahieren, wenn vorhanden
                    $txtManualWSUSPort = $window.FindName("txtManualWSUSPort")
                    if ($matches.Count -gt 2 -and $matches[2]) {
                        $txtManualWSUSPort.Text = $matches[2]
                    }
                    
                    # SSL-Status ermitteln
                    $chkManualWSUSUseSSL = $window.FindName("chkManualWSUSUseSSL")
                    $chkManualWSUSUseSSL.IsChecked = $wuServer.WUServer -like "https://*"
                }
            }
        } else {
            $txtWSUSServer.Text = "Not configured"
        }
    } catch {
        $txtWSUSServer.Text = "Error retrieving WSUS configuration"
    }
    
    # WSUS-Status ermitteln
    try {
        $useWUServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -ErrorAction SilentlyContinue
        if ($useWUServer -and $useWUServer.UseWUServer -eq 1) {
            if ($txtWSUSServer.Text -ne "Not configured") {
                $wsusConnection = Test-WSUSConnection -WSUSServer $txtWSUSServer.Text
                if ($wsusConnection) {
                    $txtWSUSStatus.Text = "Connected"
                } else {
                    $txtWSUSStatus.Text = "Not connected"
                }
            } else {
                $txtWSUSStatus.Text = "Not configured"
            }
        } else {
            $txtWSUSStatus.Text = "Deactivated"
        }
    } catch {
        $txtWSUSStatus.Text = "Error checking WSUS status"
    }
    
    # WSUS-Zielgruppe ermitteln
    try {
        $targetGroup = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetGroup" -ErrorAction SilentlyContinue
        $targetGroupEnabled = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetGroupEnabled" -ErrorAction SilentlyContinue
        
        if ($targetGroupEnabled -and $targetGroupEnabled.TargetGroupEnabled -eq 1 -and $targetGroup) {
            $txtWSUSTargetGroup.Text = $targetGroup.TargetGroup
            if ($txtCurrentTargetGroup) {
                $txtCurrentTargetGroup.Text = $targetGroup.TargetGroup
            }
        } else {
            $txtWSUSTargetGroup.Text = "Standard"
            if ($txtCurrentTargetGroup) {
                $txtCurrentTargetGroup.Text = "Standard"
            }
        }
    } catch {
        $txtWSUSTargetGroup.Text = "Unknown"
        if ($txtCurrentTargetGroup) {
            $txtCurrentTargetGroup.Text = "Unknown"
        }
    }
    
    # WSUS-Konfigurationsquelle ermitteln
    try {
        $configSource = "Local Settings"
        $policySource = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "*" -ErrorAction SilentlyContinue
        
        if ($policySource) {
            $configSource = "Group Policy"
        }
        
        $txtWSUSConfigSource.Text = $configSource
    } catch {
        $txtWSUSConfigSource.Text = "Unknown"
    }
    
    # Letzte WSUS-Prüfung ermitteln
    try {
        # Versuch, die letzte Aktualisierungszeit aus dem WindowsUpdate-Protokoll zu lesen
        $lastDetectionTime = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect" -Name "LastSuccessTime" -ErrorAction SilentlyContinue
        $lastCheckText = $null
        if ($lastDetectionTime) {
            $lastCheckText = [string]$lastDetectionTime.LastSuccessTime
        } else {
            # Windows 10/11: Registry-Wert existiert nicht mehr -> Windows Update Agent COM-API verwenden
            try {
                $lastSearch = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results.LastSearchSuccessDate
                if ($lastSearch -and $lastSearch -gt [datetime]'2000-01-01') {
                    $lastCheckText = ([datetime]$lastSearch).ToLocalTime().ToString("dd.MM.yyyy HH:mm")
                }
            } catch {
                Write-Verbose "LastSearchSuccessDate nicht verfügbar: $($_.Exception.Message)"
            }
        }
        
        if ($lastCheckText) {
            $txtWSUSLastCheck.Text = $lastCheckText
            if ($txtLastSyncTime) {
                $txtLastSyncTime.Text = $lastCheckText
            }
        } else {
            $txtWSUSLastCheck.Text = "Not available"
            if ($txtLastSyncTime) {
                $txtLastSyncTime.Text = "Not available"
            }
        }
    } catch {
        $txtWSUSLastCheck.Text = "Error retrieving last check time"
        if ($txtLastSyncTime) {
            $txtLastSyncTime.Text = "Error retrieving last check time"
        }
    }
    
    # Gruppenrichtlinieneinstellungen laden
    try {
        $gpoSettings = Get-WindowsUpdateGPOSettings
        
        if ($gpoSettings) {
            $cmbAutoUpdateSetting = $window.FindName("cmbAutoUpdateSetting")
            if ($cmbAutoUpdateSetting) {
                $cmbAutoUpdateSetting.SelectedIndex = if ($gpoSettings.AutoUpdateEnabled) { 0 } else { 1 }
            }
            
            $cmbUpdateConfigType = $window.FindName("cmbUpdateConfigType")
            if ($cmbUpdateConfigType) {
                # Index basierend auf AUOptions-Wert (2-4) setzen
                $cmbUpdateConfigType.SelectedIndex = [Math]::Max(0, [Math]::Min($gpoSettings.ConfigType - 2, 2))
            }
            
            $cmbInstallTime = $window.FindName("cmbInstallTime")
            if ($cmbInstallTime) {
                # Installationszeit (Stunde 0-23) dem passenden ComboBox-Eintrag zuordnen
                $timeIndex = 0
                for ($i = 0; $i -lt $cmbInstallTime.Items.Count; $i++) {
                    if ([string]$cmbInstallTime.Items[$i].Content -eq ('{0:D2}:00' -f [int]$gpoSettings.InstallTime)) {
                        $timeIndex = $i
                        break
                    }
                }
                $cmbInstallTime.SelectedIndex = $timeIndex
            }
            
            $chkShowNotifications = $window.FindName("chkShowNotifications")
            if ($chkShowNotifications) {
                $chkShowNotifications.IsChecked = $gpoSettings.ShowNotifications
            }
            
            $cmbRebootBehavior = $window.FindName("cmbRebootBehavior")
            if ($cmbRebootBehavior) {
                $cmbRebootBehavior.SelectedIndex = $gpoSettings.RebootBehavior
            }
        }
    } catch {
        Write-Error "Fehler beim Laden der Gruppenrichtlinieneinstellungen: $_"
    }
    
    # Synchronisierungseinstellungen laden
    try {
        $syncInterval = $window.FindName("cmbSyncInterval")
        if ($syncInterval) {
            $detectionFrequency = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "DetectionFrequency" -ErrorAction SilentlyContinue
            
            if ($detectionFrequency) {
                # DetectionFrequency (Stunden, 1-22) entspricht hier dem Intervall "Daily"
                $syncInterval.SelectedIndex = 1
            } else {
                $syncInterval.SelectedIndex = 0 # Automatisch
            }
        }
        
        $chkAutoSync = $window.FindName("chkAutoSync")
        if ($chkAutoSync) {
            $noAutoUpdate = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
            
            if ($noAutoUpdate) {
                $chkAutoSync.IsChecked = ($noAutoUpdate.NoAutoUpdate -eq 0)
            } else {
                $chkAutoSync.IsChecked = $true # Standardmäßig aktiviert
            }
        }
    } catch {
        Write-Error "Error loading sync settings: $_"
    }
    
    # WSUS-Zielgruppen laden
    $dgWSUSTargetGroups = $window.FindName("dgWSUSTargetGroups")
    if ($dgWSUSTargetGroups) {
        try {
            # WSUS-Server aus der Registry ermitteln
            $wuServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -ErrorAction SilentlyContinue
            
            if ($wuServer) {
                # Server-URL und Port extrahieren
                if ($wuServer.WUServer -match "http[s]?://([^/:]+)(?::([0-9]+))?/?") {
                    $serverName = $matches[1]
                    $port = if ($matches.Count -gt 2 -and $matches[2]) { $matches[2] } else { 8530 }
                    $useSSL = $wuServer.WUServer -like "https://*"
                    
                    # Zielgruppen abrufen
                    $targetGroups = Get-WSUSTargetGroups -WSUSServer $serverName -WSUSPort $port -UseSSL $useSSL
                    $dgWSUSTargetGroups.ItemsSource = $targetGroups
                }
            }
        } catch {
            Write-Error "Error loading WSUS target groups: $_"
        }
    }
    
    # Synchronisierungsverlauf laden
    $dgSyncHistory = $window.FindName("dgSyncHistory")
    if ($dgSyncHistory) {
        try {
            $syncHistory = Get-WSUSSyncHistory
            $dgSyncHistory.ItemsSource = $syncHistory
        } catch {
            Write-Error "Error loading sync history: $_"
        }
    }


    
    Update-StatusText -Text "WSUS settings have been loaded." -Color "Green"
}

# Funktion zum Initialisieren der Update-Zeitplan-Steuerelemente
function Initialize-UpdateScheduleControls {
    try {
        # ComboBox für Wochentage befüllen
        $cmbWeekDay = $window.FindName("cmbWeekDay")
        if ($cmbWeekDay -and $cmbWeekDay.Items.Count -eq 0) {
            $weekdays = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
            foreach ($day in $weekdays) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $day
                [void]$cmbWeekDay.Items.Add($item)
            }
        }
        
        # ComboBox für Tage des Monats befüllen
        $cmbMonthDay = $window.FindName("cmbMonthDay")
        if ($cmbMonthDay -and $cmbMonthDay.Items.Count -eq 0) {
            for ($i = 1; $i -le 31; $i++) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = "$i"
                [void]$cmbMonthDay.Items.Add($item)
            }
        }
        
        # ComboBox für Stunden befüllen
        $cmbHour = $window.FindName("cmbHour")
        $cmbRestartHour = $window.FindName("cmbRestartHour")
        if ($cmbHour -and $cmbRestartHour -and $cmbHour.Items.Count -eq 0) {
            for ($i = 0; $i -le 23; $i++) {
                $hourStr = $i.ToString("00")
                
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $hourStr
                [void]$cmbHour.Items.Add($item)
                
                $itemRestart = New-Object System.Windows.Controls.ComboBoxItem
                $itemRestart.Content = $hourStr
                [void]$cmbRestartHour.Items.Add($itemRestart)
            }
        }
        
        # ComboBox für Minuten befüllen
        $cmbMinute = $window.FindName("cmbMinute")
        $cmbRestartMinute = $window.FindName("cmbRestartMinute")
        if ($cmbMinute -and $cmbRestartMinute -and $cmbMinute.Items.Count -eq 0) {
            for ($i = 0; $i -le 59; $i += 5) { # 5-Minuten-Intervalle
                $minuteStr = $i.ToString("00")
                
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $minuteStr
                [void]$cmbMinute.Items.Add($item)
                
                $itemRestart = New-Object System.Windows.Controls.ComboBoxItem
                $itemRestart.Content = $minuteStr
                [void]$cmbRestartMinute.Items.Add($itemRestart)
            }
        }
        
        # Standardwerte setzen
        $cmbUpdateScheduleType = $window.FindName("cmbUpdateScheduleType")
        if ($cmbUpdateScheduleType) {
            $cmbUpdateScheduleType.SelectedIndex = 0
        }
        
        if ($cmbWeekDay) {
            $cmbWeekDay.SelectedIndex = 0
        }
        
        if ($cmbMonthDay) {
            $cmbMonthDay.SelectedIndex = 0
        }
        
        if ($cmbHour) {
            $cmbHour.SelectedIndex = 3 # 03:00 Uhr als Standard
        }
        
        if ($cmbMinute) {
            $cmbMinute.SelectedIndex = 0
        }
        
        $cmbUpdateBehavior = $window.FindName("cmbUpdateBehavior")
        if ($cmbUpdateBehavior) {
            $cmbUpdateBehavior.SelectedIndex = 2
        }
        
        $cmbRestartBehavior = $window.FindName("cmbRestartBehavior")
        if ($cmbRestartBehavior) {
            $cmbRestartBehavior.SelectedIndex = 0
        }
        
        if ($cmbRestartHour) {
            $cmbRestartHour.SelectedIndex = 3 # 03:00 Uhr als Standard
        }
        
        if ($cmbRestartMinute) {
            $cmbRestartMinute.SelectedIndex = 0
        }
        
        # Sichtbarkeit der Bedingten Elemente steuern
        $pnlRestartTime = $window.FindName("pnlRestartTime")
        if ($pnlRestartTime) {
            $pnlRestartTime.Visibility = [System.Windows.Visibility]::Collapsed
        }
        
        $lblWeekDay = $window.FindName("lblWeekDay")
        if ($lblWeekDay) {
            $lblWeekDay.Visibility = [System.Windows.Visibility]::Collapsed
        }
        
        if ($cmbWeekDay) {
            $cmbWeekDay.Visibility = [System.Windows.Visibility]::Collapsed
        }
        
        $lblMonthDay = $window.FindName("lblMonthDay")
        if ($lblMonthDay) {
            $lblMonthDay.Visibility = [System.Windows.Visibility]::Collapsed
        }
        
        if ($cmbMonthDay) {
            $cmbMonthDay.Visibility = [System.Windows.Visibility]::Collapsed
        }
        
        # Event-Handler für bedingte Anzeige
        if ($cmbUpdateScheduleType) {
            $cmbUpdateScheduleType.Add_SelectionChanged({
                # Lokale Variablen der Init-Funktion existieren zur Laufzeit des Events nicht mehr -> neu suchen
                $cmbUpdateScheduleType = $window.FindName("cmbUpdateScheduleType")
                $lblWeekDay = $window.FindName("lblWeekDay")
                $cmbWeekDay = $window.FindName("cmbWeekDay")
                $lblMonthDay = $window.FindName("lblMonthDay")
                $cmbMonthDay = $window.FindName("cmbMonthDay")
                if ($cmbUpdateScheduleType.SelectedIndex -eq 1) { # Wöchentlich
                    if ($lblWeekDay) { $lblWeekDay.Visibility = [System.Windows.Visibility]::Visible }
                    if ($cmbWeekDay) { $cmbWeekDay.Visibility = [System.Windows.Visibility]::Visible }
                    if ($lblMonthDay) { $lblMonthDay.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($cmbMonthDay) { $cmbMonthDay.Visibility = [System.Windows.Visibility]::Collapsed }
                }
                elseif ($cmbUpdateScheduleType.SelectedIndex -eq 2) { # Monatlich
                    if ($lblWeekDay) { $lblWeekDay.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($cmbWeekDay) { $cmbWeekDay.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($lblMonthDay) { $lblMonthDay.Visibility = [System.Windows.Visibility]::Visible }
                    if ($cmbMonthDay) { $cmbMonthDay.Visibility = [System.Windows.Visibility]::Visible }
                }
                else { # Täglich
                    if ($lblWeekDay) { $lblWeekDay.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($cmbWeekDay) { $cmbWeekDay.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($lblMonthDay) { $lblMonthDay.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($cmbMonthDay) { $cmbMonthDay.Visibility = [System.Windows.Visibility]::Collapsed }
                }
            })
        }
        
        if ($cmbRestartBehavior) {
            $cmbRestartBehavior.Add_SelectionChanged({
                $cmbRestartBehavior = $window.FindName("cmbRestartBehavior")
                $pnlRestartTime = $window.FindName("pnlRestartTime")
                if ($cmbRestartBehavior.SelectedIndex -eq 2 -and $pnlRestartTime) { # Neustart planen für
                    $pnlRestartTime.Visibility = [System.Windows.Visibility]::Visible
                }
                elseif ($pnlRestartTime) {
                    $pnlRestartTime.Visibility = [System.Windows.Visibility]::Collapsed
                }
            })
        }

        # Event-Handler für den Button "Zeitplan anwenden"
        $btnApplySchedule = $window.FindName("btnApplySchedule")
        if ($btnApplySchedule) {
            $btnApplySchedule.Add_Click({
                Set-WindowsUpdateSchedule
            })
        }
        
        # Event-Handler für den Button "Aktuellen Zeitplan anzeigen"
        $btnViewCurrentSchedule = $window.FindName("btnViewCurrentSchedule")
        if ($btnViewCurrentSchedule) {
            $btnViewCurrentSchedule.Add_Click({
                Get-WindowsUpdateSchedule
            })
        }
        
        # CheckBox für automatische Updates
        $chkEnableAutoUpdates = $window.FindName("chkEnableAutoUpdates")
        if ($chkEnableAutoUpdates) {
            # Aktuellen Status der automatischen Updates abfragen und CheckBox entsprechend setzen
            # Get-AutoUpdateStatus liefert Text; nur "Deactivated" bedeutet deaktiviert
            $autoUpdateStatus = Get-AutoUpdateStatus
            $chkEnableAutoUpdates.IsChecked = ($autoUpdateStatus -ne "Deactivated")
            
            # Event-Handler für die CheckBox
            $chkEnableAutoUpdates.Add_Checked({
                Enable-WindowsAutoUpdate
            })
            
            $chkEnableAutoUpdates.Add_Unchecked({
                Disable-WindowsAutoUpdate
            })
        }
        
    } catch {
        Update-StatusText -Text "Error initializing schedule controls: $_" -Color "Red"
    }
}

# Name der geplanten Aufgabe (einheitlich für Anlegen, Anzeigen und Löschen)
$script:ScheduledTaskName = "easyWINUpdate_Task"
$script:LegacyScheduledTaskNames = @("EasyWINUpdate_Scheduled_Task")
$script:ScheduledTaskDirectory = Join-Path $env:ProgramData 'easyWINUpdate'

# Liefert die geplante Aufgabe (Task Scheduler COM-API, sprachunabhängig) oder $null
function Get-EasyWUScheduledTask {
    try {
        $taskService = New-Object -ComObject Schedule.Service
        $taskService.Connect()
        return $taskService.GetFolder('\').GetTask($script:ScheduledTaskName)
    } catch {
        return $null
    }
}

# Entfernt die geplante Aufgabe (inkl. Altnamen früherer Versionen)
function Remove-EasyWUScheduledTask {
    $removed = $false
    try {
        $taskService = New-Object -ComObject Schedule.Service
        $taskService.Connect()
        $rootFolder = $taskService.GetFolder('\')
        foreach ($name in @($script:ScheduledTaskName) + $script:LegacyScheduledTaskNames) {
            try {
                $rootFolder.DeleteTask($name, 0)
                $removed = $true
            } catch {
                Write-Verbose "Geplante Aufgabe '$name' nicht vorhanden."
            }
        }
    } catch {
        Write-AppLog -Message "Aufgabenplanung nicht erreichbar: $($_.Exception.Message)" -Level 'WARN'
    }
    return $removed
}

# Verzeichnis für das als SYSTEM ausgeführte Skript anlegen und auf SYSTEM/Administratoren beschränken
# (verhindert, dass normale Benutzer das Skript manipulieren und so Code als SYSTEM ausführen)
function Initialize-ProtectedTaskDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $identity = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', $inheritance, [System.Security.AccessControl.PropagationFlags]::None, 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Funktion zum Setzen des Windows Update Zeitplans
function Set-WindowsUpdateSchedule {
    try {
        if (-not $script:IsAdmin) {
            Update-StatusText -Text "Zum Anlegen des Zeitplans sind Administratorrechte erforderlich." -Color "Red"
            return
        }

        # Werte aus der GUI auslesen
        $chkEnableAutoUpdates = $window.FindName("chkEnableAutoUpdates")
        if (-not $chkEnableAutoUpdates -or -not $chkEnableAutoUpdates.IsChecked) {
            Update-StatusText -Text "Automatische Updates are disabled. Please enable them first." -Color "Yellow"
            return
        }
        
        # UI-Elemente finden und Werte auslesen
        $cmbUpdateScheduleType = $window.FindName("cmbUpdateScheduleType")
        $cmbWeekDay = $window.FindName("cmbWeekDay")
        $cmbMonthDay = $window.FindName("cmbMonthDay")
        $cmbHour = $window.FindName("cmbHour")
        $cmbMinute = $window.FindName("cmbMinute")
        $cmbUpdateBehavior = $window.FindName("cmbUpdateBehavior")
        $cmbRestartBehavior = $window.FindName("cmbRestartBehavior")
        $cmbRestartHour = $window.FindName("cmbRestartHour")
        $cmbRestartMinute = $window.FindName("cmbRestartMinute")
        
        # Prüfen ob alle benötigten Elemente vorhanden und ausgewählt sind
        if (-not $cmbUpdateScheduleType -or $null -eq $cmbUpdateScheduleType.SelectedItem -or
            -not $cmbHour -or $null -eq $cmbHour.SelectedItem -or
            -not $cmbMinute -or $null -eq $cmbMinute.SelectedItem -or
            -not $cmbUpdateBehavior -or $null -eq $cmbUpdateBehavior.SelectedItem -or
            -not $cmbRestartBehavior -or $null -eq $cmbRestartBehavior.SelectedItem) {
            Update-StatusText -Text "Please select all required schedule options." -Color "Yellow"
            return
        }
        
        # Werte extrahieren (Auswertung über den Index, unabhängig vom angezeigten Text)
        $scheduleIndex = $cmbUpdateScheduleType.SelectedIndex          # 0 = Daily, 1 = Weekly, 2 = Monthly
        $scheduleType = [string]$cmbUpdateScheduleType.SelectedItem.Content
        $weekDayIndex = if ($cmbWeekDay -and $cmbWeekDay.SelectedIndex -ge 0) { $cmbWeekDay.SelectedIndex } else { 0 }
        $weekDay = if ($cmbWeekDay -and $null -ne $cmbWeekDay.SelectedItem) { [string]$cmbWeekDay.SelectedItem.Content } else { "Monday" }
        $monthDay = if ($cmbMonthDay -and $null -ne $cmbMonthDay.SelectedItem) { [int]$cmbMonthDay.SelectedItem.Content } else { 1 }
        $hour = [int]$cmbHour.SelectedItem.Content
        $minute = [int]$cmbMinute.SelectedItem.Content
        $updateBehaviorIndex = $cmbUpdateBehavior.SelectedIndex        # 0 = suchen, 1 = herunterladen, 2 = installieren
        $updateBehavior = [string]$cmbUpdateBehavior.SelectedItem.Content
        $restartBehaviorIndex = $cmbRestartBehavior.SelectedIndex      # 0 = benachrichtigen, 1 = automatisch, 2 = geplant
        $restartBehavior = [string]$cmbRestartBehavior.SelectedItem.Content
        $restartHour = if ($cmbRestartHour -and $null -ne $cmbRestartHour.SelectedItem) { [int]$cmbRestartHour.SelectedItem.Content } else { 3 }
        $restartMinute = if ($cmbRestartMinute -and $null -ne $cmbRestartMinute.SelectedItem) { [int]$cmbRestartMinute.SelectedItem.Content } else { 0 }
        
        # PSWindowsUpdate muss für SYSTEM erreichbar sein (AllUsers-Installation)
        $wuModule = Get-Module -ListAvailable -Name PSWindowsUpdate | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $wuModule -or -not ($wuModule.ModuleBase.StartsWith($env:ProgramFiles, [StringComparison]::OrdinalIgnoreCase) -or
                                     $wuModule.ModuleBase.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase))) {
            $installAnswer = [System.Windows.MessageBox]::Show(
                "Das Modul PSWindowsUpdate ist nur für den aktuellen Benutzer installiert. Die geplante Aufgabe läuft als SYSTEM und kann es so nicht laden.`r`n`r`nSoll PSWindowsUpdate jetzt für alle Benutzer installiert werden?",
                "PSWindowsUpdate",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )
            if ($installAnswer -ne [System.Windows.MessageBoxResult]::Yes) {
                Update-StatusText -Text "Zeitplan nicht angelegt: PSWindowsUpdate ist nicht für alle Benutzer installiert." -Color "Yellow"
                return
            }
            Update-StatusText -Text "Installiere PSWindowsUpdate für alle Benutzer..." -Color "Blue"
            Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force -ErrorAction Stop
        }
        
        # Aufgabenplanung konfigurieren
        Update-StatusText -Text "Configuring Windows Update schedule..." -Color "Blue"
        
        # PowerShell-Skript in geschütztem Verzeichnis erstellen (nicht im beschreibbaren %TEMP% des Benutzers)
        Initialize-ProtectedTaskDirectory -Path $script:ScheduledTaskDirectory
        $scriptPath = Join-Path $script:ScheduledTaskDirectory 'RunWindowsUpdate.ps1'
        $taskLogDirectory = (Join-Path $script:ScheduledTaskDirectory 'Logs') -replace "'", "''"
        
        # Je nach gewähltem Verhalten unterschiedliche Befehle (-AcceptAll verhindert Rückfragen im nicht-interaktiven Lauf)
        $wuCommand = switch ($updateBehaviorIndex) {
            0 { 'Get-WindowsUpdate' }
            1 { 'Get-WindowsUpdate -Download -AcceptAll' }
            default {
                switch ($restartBehaviorIndex) {
                    1 { 'Get-WindowsUpdate -Install -AcceptAll -AutoReboot' }
                    2 { 'Get-WindowsUpdate -Install -AcceptAll -ScheduleReboot $rebootTime' }
                    default { 'Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot' }
                }
            }
        }
        
        $scriptContent = @"
# Automatisch erstellt von easyWINUpdate v$($script:AppVersion) (PhinIT) am $(Get-Date -Format 'yyyy-MM-dd HH:mm')
`$logDirectory = '$taskLogDirectory'
if (-not (Test-Path -LiteralPath `$logDirectory)) { New-Item -Path `$logDirectory -ItemType Directory -Force | Out-Null }
Start-Transcript -Path (Join-Path `$logDirectory ("ScheduledUpdate_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) | Out-Null
try {
    Import-Module PSWindowsUpdate -ErrorAction Stop
    `$rebootTime = [datetime]::Today.AddHours($restartHour).AddMinutes($restartMinute)
    if (`$rebootTime -le (Get-Date)) { `$rebootTime = `$rebootTime.AddDays(1) }
    $wuCommand
} catch {
    Write-Error `$_
} finally {
    Stop-Transcript | Out-Null
}
"@
        
        # Skript speichern (UTF-8 mit BOM für Windows PowerShell 5.1)
        [System.IO.File]::WriteAllText($scriptPath, $scriptContent, (New-Object System.Text.UTF8Encoding($true)))
        
        # Geplante Aufgabe über die Task Scheduler COM-API anlegen (kein Invoke-Expression, keine Quoting-Probleme)
        Remove-EasyWUScheduledTask | Out-Null
        $taskService = New-Object -ComObject Schedule.Service
        $taskService.Connect()
        $rootFolder = $taskService.GetFolder('\')
        $taskDefinition = $taskService.NewTask(0)
        $taskDefinition.RegistrationInfo.Description = "Windows Update-Zeitplan (easyWINUpdate v$($script:AppVersion))"
        $taskDefinition.RegistrationInfo.Author = "easyWINUpdate - PhinIT"
        $taskDefinition.Settings.Enabled = $true
        $taskDefinition.Settings.StartWhenAvailable = $true
        $taskDefinition.Settings.ExecutionTimeLimit = "PT4H"
        $taskDefinition.Principal.RunLevel = 1 # Höchste Rechte
        
        switch ($scheduleIndex) {
            1 {
                # Wöchentlich: Bitmaske Sonntag=1, Montag=2 ... Samstag=64 (ComboBox beginnt mit Montag)
                $trigger = $taskDefinition.Triggers.Create(3)
                $trigger.WeeksInterval = 1
                $trigger.DaysOfWeek = @(2, 4, 8, 16, 32, 64, 1)[$weekDayIndex]
            }
            2 {
                # Monatlich am gewählten Tag (alle Monate)
                $trigger = $taskDefinition.Triggers.Create(4)
                $trigger.DaysOfMonth = [int](1 -shl ($monthDay - 1))
                $trigger.MonthsOfYear = 4095
            }
            default {
                $trigger = $taskDefinition.Triggers.Create(2)
                $trigger.DaysInterval = 1
            }
        }
        $trigger.StartBoundary = [datetime]::Today.AddHours($hour).AddMinutes($minute).ToString("yyyy-MM-dd'T'HH:mm:ss")
        $trigger.Enabled = $true
        
        $execAction = $taskDefinition.Actions.Create(0)
        $execAction.Path = (Get-Process -Id $PID).Path
        $execAction.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
        
        # 6 = TASK_CREATE_OR_UPDATE, 5 = TASK_LOGON_SERVICE_ACCOUNT
        [void]$rootFolder.RegisterTaskDefinition($script:ScheduledTaskName, $taskDefinition, 6, "SYSTEM", $null, 5)
        Write-AppLog -Message "Geplante Aufgabe '$($script:ScheduledTaskName)' angelegt: $scheduleType $('{0:D2}:{1:D2}' -f $hour, $minute), $updateBehavior, $restartBehavior"
        
        # Konfiguration in Registry speichern für die Anzeige
        $regPath = "HKCU:\SOFTWARE\easyWINUpdate"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # Konfiguration speichern
        New-ItemProperty -Path $regPath -Name "ScheduleEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "ScheduleType" -Value $scheduleType -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "WeekDay" -Value $weekDay -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "MonthDay" -Value ([string]$monthDay) -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "Hour" -Value ('{0:D2}' -f $hour) -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "Minute" -Value ('{0:D2}' -f $minute) -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "UpdateBehavior" -Value $updateBehavior -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "RestartBehavior" -Value $restartBehavior -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "RestartHour" -Value ('{0:D2}' -f $restartHour) -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "RestartMinute" -Value ('{0:D2}' -f $restartMinute) -PropertyType String -Force | Out-Null
        
        Update-StatusText -Text "Windows Update schedule successfully configured" -Color "Green"
        
        # Aktuellen Zeitplan anzeigen
        Get-WindowsUpdateSchedule
        
    } catch {
        Update-StatusText -Text "Error creating Windows Update schedule: $_" -Color "Red"
    }
}

# Funktion zum Abrufen des aktuellen Windows Update Zeitplans
function Get-WindowsUpdateSchedule {
    try {
        $txtCurrentSchedule = $window.FindName("txtCurrentSchedule")
        $txtLastRunResult = $window.FindName("txtLastRunResult")
        
        # Geplante Aufgabe abfragen (COM-API statt sprachabhängiger schtasks-Ausgabe)
        $task = Get-EasyWUScheduledTask
        if ($task) {
            $nextRunTime = if ($task.NextRunTime -and ([datetime]$task.NextRunTime) -gt [datetime]'2000-01-01') { ([datetime]$task.NextRunTime).ToString("dd.MM.yyyy HH:mm") } else { "Nicht geplant" }
            $lastRunTime = if ($task.LastRunTime -and ([datetime]$task.LastRunTime) -gt [datetime]'2000-01-01') { ([datetime]$task.LastRunTime).ToString("dd.MM.yyyy HH:mm") } else { "Noch nicht ausgeführt" }
            $lastResult = [int64]$task.LastTaskResult
            
            # Status aus Registry holen (detaillierte Konfiguration)
            $regPath = "HKCU:\SOFTWARE\easyWINUpdate"
            $scheduleInfo = ""
            
            if (Test-Path $regPath) {
                $scheduleConfig = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                $scheduleType = $scheduleConfig.ScheduleType
                
                # Format the schedule information
                $scheduleInfo = "Schedule type: $scheduleType`r`n"
                
                if ($scheduleType -eq "Weekly") {
                    $scheduleInfo += "Weekday: $($scheduleConfig.WeekDay)`r`n"
                } elseif ($scheduleType -eq "Monthly") {
                    $scheduleInfo += "Day of month: $($scheduleConfig.MonthDay)`r`n"
                }
                
                $scheduleInfo += "Time: $($scheduleConfig.Hour):$($scheduleConfig.Minute)`r`n"
                $scheduleInfo += "Behavior: $($scheduleConfig.UpdateBehavior)`r`n"
                $scheduleInfo += "After installation: $($scheduleConfig.RestartBehavior)`r`n"
                
                if ($scheduleConfig.RestartBehavior -like "Schedule restart*") {
                    $scheduleInfo += "Scheduled restart: $($scheduleConfig.RestartHour):$($scheduleConfig.RestartMinute)`r`n"
                }
            }
            
            # Status anzeigen
            $scheduleText = "Windows Update schedule is active`r`n`r`n"
            $scheduleText += $scheduleInfo
            $scheduleText += "`r`nNext execution: $nextRunTime`r`n"
            $scheduleText += "Last execution: $lastRunTime"
            
            $txtCurrentSchedule.Text = $scheduleText
            
            # Letztes Ergebnis anzeigen (0 = Erfolg, 0x41303 = noch nicht ausgeführt)
            if ($lastResult -ne 0 -and $lastResult -ne 0x41303) {
                $txtLastRunResult.Text = "Last result: 0x{0:X8} (Error code)" -f $lastResult
                $txtLastRunResult.Visibility = "Visible"
            } else {
                $txtLastRunResult.Visibility = "Collapsed"
            }
        } else {
            $txtCurrentSchedule.Text = "No Windows Update schedule configured."
            $txtLastRunResult.Visibility = "Collapsed"
        }
        
        Update-StatusText -Text "Update schedule information updated" -Color "Green"
        
    } catch {
        Update-StatusText -Text "Error fetching Windows Update schedule information: $_" -Color "Red"
    }
}

# Funktion zum Aktivieren der automatischen Windows Updates
function Enable-WindowsAutoUpdate {
    try {
        Update-StatusText -Text "Activating automatic Windows Updates..." -Color "Blue"
        
        # Registry-Einstellungen für automatische Updates
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        
        # Prüfen, ob der Pfad existiert, ansonsten erstellen
        if (!(Test-Path $auPath)) {
            New-Item -Path $auPath -Force | Out-Null
        }
        
        # AUOptions-Wert setzen (4 = automatische Installation)
        Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 4 -Type DWord -Force
        
        Update-StatusText -Text "Automatic Windows Updates activated" -Color "Green"
    } catch {
        Update-StatusText -Text "Error activating automatic Windows Updates: $_" -Color "Red"
    }
}

# Funktion zum Deaktivieren der automatischen Windows Updates
function Disable-WindowsAutoUpdate {
    try {
        Update-StatusText -Text "Deactivating automatic Windows Updates..." -Color "Blue"
        
        # Registry-Einstellungen für automatische Updates
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        
        # Prüfen, ob der Pfad existiert, ansonsten erstellen
        if (!(Test-Path $auPath)) {
            New-Item -Path $auPath -Force | Out-Null
        }
        
        # NoAutoUpdate-Wert setzen (1 = deaktiviert)
        Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 1 -Type DWord -Force
        
        # Geplante Aufgabe löschen
        if (Remove-EasyWUScheduledTask) {
            Update-StatusText -Text "Scheduled update task removed" -Color "Blue"
        }
        
        Update-StatusText -Text "Automatic Windows Updates deactivated" -Color "Green"
    } catch {
        Update-StatusText -Text "Error deactivating automatic Windows Updates: $_" -Color "Red"
    }
}

# Function to retrieve the current status of automatic updates
function Get-AutoUpdateStatus {
    try {
        # Registry-Pfad für Windows Update Einstellungen
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        
        if (Test-Path $auPath) {
            $noAutoUpdate = (Get-ItemProperty -Path $auPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
            $auOptions = (Get-ItemProperty -Path $auPath -Name "AUOptions" -ErrorAction SilentlyContinue).AUOptions
            
            # Status bestimmen
            if ($null -eq $noAutoUpdate) {
                return "Unknown"
            }
            elseif ($noAutoUpdate -eq 1) {
                return "Deactivated"
            }
            else {
                # Konfigurationstyp anzeigen
                switch ($auOptions) {
                    1 { return "Notify only" }
                    2 { return "Notify before download" }
                    3 { return "Notify before installation" }
                    4 { return "Automatic installation" }
                    default { return "Activated (User defined)" }
                }
            }
        }
        else {
            return "Nicht konfiguriert"
        }
    }
    catch {
        return "Fehler: $_"
    }
}

# Function to switch between pages
function Switch-Page {
    param (
        [string]$PageName
    )
    
    $homePage = $window.FindName("homePage")
    $installedUpdatesPage = $window.FindName("installedUpdatesPage")
    $availableUpdatesPage = $window.FindName("availableUpdatesPage")
    $wsusSettingsPage = $window.FindName("wsusSettingsPage")
    $troubleshootingPage = $window.FindName("troubleshootingPage")
    
    $homePage.Visibility = "Collapsed"
    $installedUpdatesPage.Visibility = "Collapsed"
    $availableUpdatesPage.Visibility = "Collapsed"
    $wsusSettingsPage.Visibility = "Collapsed"
    $troubleshootingPage.Visibility = "Collapsed"
    
    switch ($PageName) {
        "Home" {
            $homePage.Visibility = "Visible"
            Update-StatusText -Text "Welcome to easyWINUpdate" -Color "Green"
            # Lade die Update-Status-Informationen auf der Home-Seite
            Load-UpdateStatusPage
        }
        "InstalledUpdates" {
            $installedUpdatesPage.Visibility = "Visible"
            Load-InstalledUpdatesPage
        }
        "AvailableUpdates" {
            $availableUpdatesPage.Visibility = "Visible"
            Load-AvailableUpdatesPage
        }
        "WSUSSettings" {
            $wsusSettingsPage.Visibility = "Visible"
            Load-WSUSSettingsPage
        }
        "Troubleshooting" {
            $troubleshootingPage.Visibility = "Visible"
            Update-StatusText -Text "Troubleshooting tools ready." -Color "Blue"
        }
    }
}

# Event-Handler für Seitennavigation
$navHome = $window.FindName("navHome")
if ($navHome) {
    $navHome.Add_Checked({
        Switch-Page -PageName "Home"
    })
}

$navInstalledUpdates = $window.FindName("navInstalledUpdates")
if ($navInstalledUpdates) {
    $navInstalledUpdates.Add_Checked({
        Switch-Page -PageName "InstalledUpdates"
    })
}

$navAvailableUpdates = $window.FindName("navAvailableUpdates")
if ($navAvailableUpdates) {
    $navAvailableUpdates.Add_Checked({
        Switch-Page -PageName "AvailableUpdates"
    })
}

$navWSUSSettings = $window.FindName("navWSUSSettings")
if ($navWSUSSettings) {
    $navWSUSSettings.Add_Checked({
        Switch-Page -PageName "WSUSSettings"
    })
}

$navTroubleshooting = $window.FindName("navTroubleshooting")
if ($navTroubleshooting) {
    $navTroubleshooting.Add_Checked({
        Switch-Page -PageName "Troubleshooting"
    })
}

# Event-Handler für Update-Status-Seite
$btnCheckForUpdates = $window.FindName("btnCheckForUpdates")
if ($btnCheckForUpdates) {
    $btnCheckForUpdates.Add_Click({
        Update-StatusText -Text "Checking for updates..." -Color "Blue"
        try {
            Start-UpdateDetection
            Update-StatusText -Text "Update detection started. Results appear after the scan has finished." -Color "Green"
        } catch {
            Update-StatusText -Text "Error starting update detection: $_" -Color "Red"
        }
        Load-UpdateStatusPage
    })
}

# Event-Handler für installierte Updates-Seite
$btnSearchInstalled = $window.FindName("btnSearchInstalled")
$btnSearchInstalled.Add_Click({
    $txtSearchInstalled = $window.FindName("txtSearchInstalled")
    $searchText = ([string]$txtSearchInstalled.Text).Trim()
    
    if (-not [string]::IsNullOrEmpty($searchText)) {
        # Bereits geladene Liste filtern (kein erneuter Get-HotFix-Aufruf), Platzhalter im Suchtext maskieren
        $hotfixes = if ($script:InstalledUpdatesCache) { $script:InstalledUpdatesCache } else { Get-InstalledWindowsUpdates }
        $pattern = "*$([System.Management.Automation.WildcardPattern]::Escape($searchText))*"
        $filteredHotfixes = @($hotfixes | Where-Object {
            "$($_.HotFixID)" -like $pattern -or "$($_.Description)" -like $pattern
        })
        
        $dgInstalledUpdates = $window.FindName("dgInstalledUpdates")
        $dgInstalledUpdates.ItemsSource = $filteredHotfixes
        
        Update-StatusText -Text "$($filteredHotfixes.Count) Updates found containing '$searchText'" -Color "Green"
    } else {
        Load-InstalledUpdatesPage
    }
})

$btnRefreshInstalled = $window.FindName("btnRefreshInstalled")
$btnRefreshInstalled.Add_Click({
    Load-InstalledUpdatesPage
})

$btnExportInstalled = $window.FindName("btnExportInstalled")
$btnExportInstalled.Add_Click({
    # Desktop-Pfad über die Shell ermitteln (funktioniert auch bei umgeleitetem/OneDrive-Desktop)
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrEmpty($desktopPath) -or -not (Test-Path -LiteralPath $desktopPath)) {
        $desktopPath = $script:LogDirectory
    }
    $savePath = Join-Path $desktopPath "Installierte_Updates_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $hotfixes = Get-InstalledWindowsUpdates
    
    if ($hotfixes) {
        try {
            $hotfixes | Export-Csv -Path $savePath -NoTypeInformation -Delimiter ";" -Encoding UTF8 -ErrorAction Stop
            Update-StatusText -Text "Updates have been exported to '$savePath'." -Color "Green"
        } catch {
            Update-StatusText -Text "Error exporting updates: $_" -Color "Red"
        }
    } else {
        Update-StatusText -Text "No updates to export." -Color "Red"
    }
})

# Event-Handler für verfügbare Updates-Seite
$btnSearchAvailable = $window.FindName("btnSearchAvailable")
$btnSearchAvailable.Add_Click({
    Load-AvailableUpdatesPage
})

$btnInstallAll = $window.FindName("btnInstallAll")
$btnInstallAll.Add_Click({
    $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
    $updates = @($dgAvailableUpdates.ItemsSource | Where-Object { $_ -and $_.Identity })
    
    if ($updates.Count -gt 0) {
        $result = [System.Windows.MessageBox]::Show(
            "Do you want to install all $($updates.Count) updates? A restart may be required afterwards.",
            "Install updates",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        
        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            # Nur die angezeigten (gefilterten) Updates installieren, Quelle wie konfiguriert (Windows Update oder WSUS)
            Start-UpdateInstallation -UpdateIds @($updates | ForEach-Object { [string]$_.Identity }) -Description "$($updates.Count) Updates"
        }
    } else {
        Update-StatusText -Text "No updates available for installation." -Color "Red"
    }
})

# Liefert die in der Liste angehakten Updates (offene Bearbeitung der CheckBox-Spalte vorher übernehmen)
function Get-SelectedAvailableUpdates {
    $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
    [void]$dgAvailableUpdates.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
    return @($dgAvailableUpdates.ItemsSource | Where-Object { $_ -and $_.IsSelected -and $_.Identity })
}

$btnInstallSelected = $window.FindName("btnInstallSelected")
$btnInstallSelected.Add_Click({
    $updates = Get-SelectedAvailableUpdates
    
    if ($updates.Count -gt 0) {
        $result = [System.Windows.MessageBox]::Show(
            "Do you want to install the selected $($updates.Count) updates? A restart may be required afterwards.",
            "Install updates",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        
        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            Start-UpdateInstallation -UpdateIds @($updates | ForEach-Object { [string]$_.Identity }) -Description "$($updates.Count) ausgewählte Updates"
        }
    } else {
        Update-StatusText -Text "No updates selected." -Color "Red"
    }
})

$btnDownloadSelected = $window.FindName("btnDownloadSelected")
$btnDownloadSelected.Add_Click({
    $updates = Get-SelectedAvailableUpdates
    
    if ($updates.Count -gt 0) {
        Start-UpdateInstallation -UpdateIds @($updates | ForEach-Object { [string]$_.Identity }) -DownloadOnly -Description "$($updates.Count) ausgewählte Updates"
    } else {
        Update-StatusText -Text "No updates selected." -Color "Red"
    }
})

# Event-Handler for WSUS settings page
$btnResetWSUS = $window.FindName("btnResetWSUS")
$btnResetWSUS.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you really want to reset the WSUS settings? The computer will then download updates directly from Microsoft.",
        "Reset WSUS settings",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Update-StatusText -Text "Resetting WSUS settings..." -Color "Blue"
        
        if (Reset-WSUSSettings) {
            Update-StatusText -Text "WSUS settings have been successfully reset." -Color "Green"
            Load-WSUSSettingsPage
        } else {
            Update-StatusText -Text "Error resetting WSUS settings." -Color "Red"
        }
    }
})

$btnCheckWSUSConn = $window.FindName("btnCheckWSUSConn")
$btnCheckWSUSConn.Add_Click({
    $wsusSettings = Get-WSUSSettings
    
    if ($wsusSettings.Server) {
        Update-StatusText -Text "Checking connection to WSUS server..." -Color "Blue"
        
        if (Test-WSUSConnection -WSUSServer $wsusSettings.Server) {
            Update-StatusText -Text "Connection to WSUS server established successfully." -Color "Green"
        } else {
            Update-StatusText -Text "Connection to WSUS server failed." -Color "Red"
        }
    } else {
        Update-StatusText -Text "No WSUS server configured." -Color "Red"
    }
})

$btnDetectNow = $window.FindName("btnDetectNow")
$btnDetectNow.Add_Click({
    Update-StatusText -Text "Starting update detection..." -Color "Blue"
    
    try {
        # Update-Erkennung erzwingen
        Start-UpdateDetection
        Update-StatusText -Text "Update detection started." -Color "Green"
    } catch {
        Update-StatusText -Text "Error starting update detection: $_" -Color "Red"
    }
})

# Gruppenrichtlinien-Einstellungen
$btnRefreshGPOSettings = $window.FindName("btnRefreshGPOSettings")
if ($btnRefreshGPOSettings) {
    $btnRefreshGPOSettings.Add_Click({
        Load-WSUSSettingsPage
        Update-StatusText -Text "Settings reloaded." -Color "Green"
    })
}

$btnApplyGPOSettings = $window.FindName("btnApplyGPOSettings")
if ($btnApplyGPOSettings) {
    $btnApplyGPOSettings.Add_Click({
        $cmbAutoUpdateSetting = $window.FindName("cmbAutoUpdateSetting")
        $cmbUpdateConfigType = $window.FindName("cmbUpdateConfigType")
        $cmbInstallTime = $window.FindName("cmbInstallTime")
        $chkShowNotifications = $window.FindName("chkShowNotifications")
        $cmbRebootBehavior = $window.FindName("cmbRebootBehavior")
        
        if ($cmbAutoUpdateSetting.SelectedIndex -lt 0 -or $cmbUpdateConfigType.SelectedIndex -lt 0 -or
            $cmbInstallTime.SelectedIndex -lt 0 -or $cmbRebootBehavior.SelectedIndex -lt 0) {
            Update-StatusText -Text "Please select all settings first." -Color "Yellow"
            return
        }
        
        $installHour = 3
        if ([string]$cmbInstallTime.SelectedItem.Content -match '^(\d{1,2}):') {
            $installHour = [int]$Matches[1]
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Do you want to write these Windows Update policy settings to the local registry? The Windows Update service will be restarted.",
            "Apply settings",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        
        # AUOptions: 2 = nur benachrichtigen, 3 = herunterladen und benachrichtigen, 4 = automatisch installieren
        $applied = Set-WindowsUpdateGPOSettings -AutoUpdateEnabled ($cmbAutoUpdateSetting.SelectedIndex -eq 0) `
            -ConfigType ($cmbUpdateConfigType.SelectedIndex + 2) `
            -InstallTime $installHour `
            -ShowNotifications ([bool]$chkShowNotifications.IsChecked) `
            -RebootBehavior $cmbRebootBehavior.SelectedIndex
        
        if ($applied) {
            Update-StatusText -Text "Windows Update policy settings applied." -Color "Green"
            Load-WSUSSettingsPage
        } else {
            Update-StatusText -Text "Error applying Windows Update policy settings." -Color "Red"
        }
    })
}

# WSUS-Zielgruppen (clientseitige Zielgruppenadressierung)
$btnRefreshTargetGroups = $window.FindName("btnRefreshTargetGroups")
if ($btnRefreshTargetGroups) {
    $btnRefreshTargetGroups.Add_Click({
        $dgWSUSTargetGroups = $window.FindName("dgWSUSTargetGroups")
        $dgWSUSTargetGroups.ItemsSource = @(Get-WSUSTargetGroups)
        Load-WSUSSettingsPage
        Update-StatusText -Text "Target groups refreshed." -Color "Green"
    })
}

$btnSetTargetGroup = $window.FindName("btnSetTargetGroup")
if ($btnSetTargetGroup) {
    $btnSetTargetGroup.Add_Click({
        $dgWSUSTargetGroups = $window.FindName("dgWSUSTargetGroups")
        $selectedGroup = $dgWSUSTargetGroups.SelectedItem
        if ($null -eq $selectedGroup -or [string]::IsNullOrWhiteSpace([string]$selectedGroup.Name)) {
            Update-StatusText -Text "Please select a target group first." -Color "Yellow"
            return
        }
        
        $wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $wuServer = (Get-ItemProperty -Path $wuRegPath -Name "WUServer" -ErrorAction SilentlyContinue).WUServer
        if ([string]::IsNullOrEmpty($wuServer)) {
            Update-StatusText -Text "No WSUS server configured. Target groups are only used with WSUS." -Color "Yellow"
            return
        }
        
        $groupName = [string]$selectedGroup.Name
        try {
            if ($groupName -eq "Unassigned Computers") {
                # Keine Zielgruppe: clientseitige Zuordnung entfernen
                Remove-ItemProperty -Path $wuRegPath -Name "TargetGroup" -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $wuRegPath -Name "TargetGroupEnabled" -Value 0 -Type DWord
            } else {
                Set-ItemProperty -Path $wuRegPath -Name "TargetGroup" -Value $groupName -Type String
                Set-ItemProperty -Path $wuRegPath -Name "TargetGroupEnabled" -Value 1 -Type DWord
            }
            Write-AppLog -Message "WSUS-Zielgruppe gesetzt: $groupName"
            Start-UpdateDetection
            Update-StatusText -Text "Target group '$groupName' set. The assignment takes effect with the next WSUS report." -Color "Green"
            Load-WSUSSettingsPage
        } catch {
            Update-StatusText -Text "Error setting target group: $_" -Color "Red"
        }
    })
}

# WSUS-Synchronisierung
$btnSaveWSUSSyncSettings = $window.FindName("btnSaveWSUSSyncSettings")
if ($btnSaveWSUSSyncSettings) {
    $btnSaveWSUSSyncSettings.Add_Click({
        $cmbSyncInterval = $window.FindName("cmbSyncInterval")
        $chkAutoSync = $window.FindName("chkAutoSync")
        if ($null -eq $cmbSyncInterval.SelectedItem) {
            Update-StatusText -Text "Please select a synchronization interval." -Color "Yellow"
            return
        }
        $syncInterval = [string]$cmbSyncInterval.SelectedItem.Content
        
        if (Set-WSUSSyncSettings -SyncInterval $syncInterval -AutoSync ([bool]$chkAutoSync.IsChecked)) {
            # Hinweis: Die Richtlinie DetectionFrequency erlaubt maximal 22 Stunden
            Update-StatusText -Text "Synchronization settings saved ($syncInterval; detection interval max. 22 hours by policy)." -Color "Green"
            Load-WSUSSettingsPage
        } else {
            Update-StatusText -Text "Error saving synchronization settings." -Color "Red"
        }
    })
}

$btnStartWSUSSync = $window.FindName("btnStartWSUSSync")
if ($btnStartWSUSSync) {
    $btnStartWSUSSync.Add_Click({
        Start-WSUSSynchronization | Out-Null
    })
}

# Event-Handler für die Schaltflächen in den DataGrid-Zeilen
# Die Buttons stammen aus einem DataTemplate (eigener Namensbereich) und sind per FindName nicht erreichbar.
# Daher wird das geroutete Click-Ereignis zentral am DataGrid abgefangen.
$dgInstalledUpdates = $window.FindName("dgInstalledUpdates")
$dgInstalledUpdates.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    $routedArgs = $args[1]
    
    $clickedButton = $routedArgs.OriginalSource
    if (-not ($clickedButton -is [System.Windows.Controls.Button]) -or $clickedButton.Name -ne "btnRemoveUpdate") { return }
    $kbNumber = [string]$clickedButton.Tag
    
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie das Update $kbNumber wirklich entfernen?",
        "Update entfernen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Update-StatusText -Text "Removing Update $kbNumber..." -Color "Blue"
        $script:UpdateBeingRemoved = $kbNumber
        
        # wusa.exe kann mehrere Minuten benötigen -> im Hintergrund ausführen
        Start-FunctionInBackground -FunctionName 'Remove-WindowsUpdateKB' -FunctionParameters @{ KBNumber = $kbNumber } -OnCompleted {
            param($Output, $ErrorText)
            $removedKB = $script:UpdateBeingRemoved
            if ([bool]($Output | Select-Object -Last 1)) {
                Update-StatusText -Text "Update $removedKB has been removed. The computer may need to be restarted." -Color "Green"
                Load-InstalledUpdatesPage
            } else {
                Update-StatusText -Text "Error removing Update $removedKB. $ErrorText" -Color "Red"
            }
        }
    }
})

$dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
$dgAvailableUpdates.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    $routedArgs = $args[1]
    
    $clickedButton = $routedArgs.OriginalSource
    if (-not ($clickedButton -is [System.Windows.Controls.Button]) -or $clickedButton.Name -ne "btnInstallUpdate") { return }
    $identity = [string]$clickedButton.Tag
    if ([string]::IsNullOrEmpty($identity)) { return }
    
    $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
    $updateEntry = @($dgAvailableUpdates.ItemsSource | Where-Object { [string]$_.Identity -eq $identity }) | Select-Object -First 1
    $kbNumber = if ($updateEntry) { $updateEntry.KBArticleID } else { $identity }
    
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to install Update $kbNumber?",
        "Install Update",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-UpdateInstallation -UpdateIds @($identity) -Description "Update $kbNumber"
    }
})

# Event-Handler for Troubleshooting page
$btnCreateRestorePoint = $window.FindName("btnCreateRestorePoint")
$btnCreateRestorePoint.Add_Click({
    Update-StatusText -Text "Creating System Restore Point..." -Color "Blue"
    
    Start-FunctionInBackground -FunctionName 'New-SystemRestorePoint' -OnCompleted {
        param($Output, $ErrorText)
        if ([bool]($Output | Select-Object -Last 1)) {
            Update-StatusText -Text "System Restore Point has been successfully created." -Color "Green"
        } else {
            Update-StatusText -Text "Error creating System Restore Point. $ErrorText" -Color "Red"
        }
    }
})

$btnResetComponents = $window.FindName("btnResetComponents")
$btnResetComponents.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you really want to reset the Windows Update components? This will stop the update services and delete all update caches.",
        "Reset Windows Update Components",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Reset-WindowsUpdateComponents
    }
})

$btnCheckSystemFiles = $window.FindName("btnCheckSystemFiles")
$btnCheckSystemFiles.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to check and repair the Windows system files? This process may take some time.",
        "Check System Files",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Repair-WindowsSystemFiles
    }
})

$btnClearUpdateHistory = $window.FindName("btnClearUpdateHistory")
$btnClearUpdateHistory.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to clear the Windows Update history and all caches? This removes all information about previous update attempts.",
        "Clear Update History",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Clear-WindowsUpdateHistory
    }
})

$btnRegisterDLLs = $window.FindName("btnRegisterDLLs")
$btnRegisterDLLs.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to register all Windows Update DLLs? This can help with problems with update components.",
        "Register Update DLLs",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Register-WindowsUpdateDLLs
    }
})

$btnClearStuckUpdates = $window.FindName("btnClearStuckUpdates")
$btnClearStuckUpdates.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to remove stuck updates and BITS jobs? This can help with problems with stuck downloads.",
        "Remove Stuck Updates",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Update-StatusText -Text "Entferne hängende Updates und BITS-Jobs..." -Color "Blue"
        # Get-WindowsPackage kann lange dauern -> im Hintergrund ausführen
        Start-FunctionInBackground -FunctionName 'Clear-StuckUpdatesAndBITSJobs' -HelperFunctions 'Start-UpdateDetection' -OnCompleted {
            param($Output, $ErrorText)
            if ([bool]($Output | Select-Object -Last 1)) {
                Update-StatusText -Text "Hängende Updates und BITS-Jobs wurden entfernt." -Color "Green"
            } else {
                Update-StatusText -Text "Fehler beim Entfernen von hängenden Updates. $ErrorText" -Color "Red"
            }
        }
    }
})
# Event-Handler für die neuen Troubleshooting-Funktionen
$btnDiagnoseError = $window.FindName("btnDiagnoseError")
$btnDiagnoseError.Add_Click({
    $result = Diagnose-WindowsUpdateError
    [System.Windows.MessageBox]::Show($result, "Windows Update-Fehlerdiagnose", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
})

$btnRepairBITS = $window.FindName("btnRepairBITS")
$btnRepairBITS.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to perform an advanced repair of the BITS service?",
        "Repair BITS Service",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Repair-BITSService
    }
})
# WaaSMedic-Dienst
$btnWaaSMedic = $window.FindName("btnWaaSMedic")
$btnWaaSMedic.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to check and repair the Windows Update Medic Service? This can help with problems with the update process.",
        "Repair WaaSMedic Service",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Repair-WaaSMedicService
    }
})

# Windows Update-Log-Analyse (Get-WindowsUpdateLog dauert lange -> Hintergrund)
$btnAnalyzeLogs = $window.FindName("btnAnalyzeLogs")
$btnAnalyzeLogs.Add_Click({
    Update-StatusText -Text "Analysiere Windows Update-Logs (kann einige Minuten dauern)..." -Color "Blue"
    Start-FunctionInBackground -FunctionName 'Analyze-WindowsUpdateLogs' -FunctionParameters @{ OutputDirectory = $script:LogDirectory } -OnCompleted {
        param($Output, $ErrorText)
        $analysisText = [string]($Output | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        if ([string]::IsNullOrEmpty($analysisText)) {
            $analysisText = "Die Log-Analyse lieferte kein Ergebnis. $ErrorText"
        }
        Update-StatusText -Text "Log-Analyse abgeschlossen." -Color "Green"
        [System.Windows.MessageBox]::Show($analysisText, "Windows Update-Log-Analyse", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
})

# Registry-Reparatur
$btnRepairRegistry = $window.FindName("btnRepairRegistry")
$btnRepairRegistry.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to repair the Windows Update registry settings? This can help with problems with configuration settings.",
        "Repair Registry Settings",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Repair-WindowsUpdateRegistry
    }
})

# Datenbank-Reparatur
$btnRepairDatabase = $window.FindName("btnRepairDatabase")
$btnRepairDatabase.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to repair the Windows Update database? This creates backups of the current update database and resets them.",
        "Repair Update Database",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Repair-WindowsUpdateDatabase
    }
})

# Debug-Modus umschalten
$btnToggleDebug = $window.FindName("btnToggleDebug")
$btnToggleDebug.Add_Click({
    # Prüfen, ob der Debug-Modus aktiv ist
    $wuTraceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Trace"
    $debugActive = $false
    
    if (Test-Path $wuTraceKey) {
        $flags = (Get-ItemProperty -Path $wuTraceKey -ErrorAction SilentlyContinue).Flags
        if ($flags -eq 1) {
            $debugActive = $true
        }
    }
    
    $message = if ($debugActive) {
        "The Windows Update error search mode is currently active. Do you want to disable it?"
    } else {
        "Do you want to enable the Windows Update error search mode? This helps diagnose serious update problems."
    }
    
    $result = [System.Windows.MessageBox]::Show(
        $message,
        "Toggle Error Search Mode",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Toggle-WindowsUpdateDebugMode -Enable (-not $debugActive)
    }
})

# Auto-Fix
$btnAutoFix = $window.FindName("btnAutoFix")
$btnAutoFix.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Do you want to perform an automatic fix for Windows Update issues? The system will try to automatically detect and fix errors.",
        "Automatic Fix",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Auto-FixWindowsUpdateIssues
    }
})

# Weitere Werkzeuge
$btnCleanTemp = $window.FindName("btnCleanTemp")
if ($btnCleanTemp) {
    $btnCleanTemp.Add_Click({
        $result = [System.Windows.MessageBox]::Show(
            "Do you want to delete the temporary files of the current user and of Windows ($env:SystemRoot\Temp)? Files in use are skipped.",
            "Clean temporary files",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        
        Update-StatusText -Text "Cleaning temporary files..." -Color "Blue"
        $tempFolders = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
        $removedCount = 0
        foreach ($tempFolder in $tempFolders) {
            foreach ($item in @(Get-ChildItem -LiteralPath $tempFolder -Force -ErrorAction SilentlyContinue)) {
                try {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                    $removedCount++
                } catch {
                    Write-Verbose "Übersprungen (in Verwendung): $($item.FullName)"
                }
            }
        }
        Write-AppLog -Message "Temporäre Dateien bereinigt: $removedCount Einträge entfernt"
        Update-StatusText -Text "$removedCount temporary items removed (items in use were skipped)." -Color "Green"
    })
}

$btnResetWinsock = $window.FindName("btnResetWinsock")
if ($btnResetWinsock) {
    $btnResetWinsock.Add_Click({
        $result = [System.Windows.MessageBox]::Show(
            "Do you want to reset the Winsock catalog? A restart is required afterwards.",
            "Reset Winsock",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        
        $netshOutput = & (Join-Path $env:SystemRoot 'System32\netsh.exe') winsock reset 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-AppLog -Message "Winsock zurückgesetzt"
            Update-StatusText -Text "Winsock catalog reset. Please restart the computer." -Color "Green"
        } else {
            Update-StatusText -Text "Error resetting Winsock: $($netshOutput -join ' ')" -Color "Red"
        }
    })
}

$btnCheckDisk = $window.FindName("btnCheckDisk")
if ($btnCheckDisk) {
    $btnCheckDisk.Add_Click({
        try {
            # Online-Prüfung (nur lesend) des Systemlaufwerks in eigenem Konsolenfenster
            Start-ConsoleTool -CommandLine "chkdsk.exe $env:SystemDrive /scan" -Title "easyWINUpdate - CHKDSK"
            Update-StatusText -Text "CHKDSK has been started in a separate window." -Color "Green"
        } catch {
            Update-StatusText -Text "Error starting CHKDSK: $_" -Color "Red"
        }
    })
}

$window.Add_Loaded({
    # Initial Page anzeigen
    Switch-Page "Home"
    
    # ComputerName anzeigen
    $computerName = $window.FindName("computerName")
    $computerName.Text = $env:COMPUTERNAME
    
    # Zeitplan-Steuerelemente initialisieren
    Initialize-UpdateScheduleControls

    # WSUS-Seite initialisieren
    Load-WSUSSettingsPage
})

#region Hauptausführung

# Computername anzeigen
$computerName = $window.FindName("computerName")
$computerName.Text = $env:COMPUTERNAME

# Versionsnummer anzeigen
$versionText = $window.FindName("versionText")
$versionText.Text = "easyWINUpdate v$($script:AppVersion) - PhinIT"

# Initialisierung
try {
    # Event-Handler für Schließen des Fensters: laufende Hintergrundaufgaben beenden
    $window.Add_Closing({
        if ($script:BackgroundTimer) {
            $script:BackgroundTimer.Stop()
        }
        foreach ($task in @($script:BackgroundTasks)) {
            try {
                $task.PowerShell.Stop()
                $task.PowerShell.Runspace.Dispose()
                $task.PowerShell.Dispose()
            } catch {
                Write-Verbose "Hintergrundaufgabe konnte nicht beendet werden: $_"
            }
        }
        $script:BackgroundTasks.Clear()
        Write-AppLog -Message "easyWINUpdate beendet"
    })
    
    # GUI anzeigen (die Startseite wird im Loaded-Ereignis geladen)
    $window.ShowDialog() | Out-Null
} catch {
    Write-Error "Error executing the script: $_"
}
#endregion
