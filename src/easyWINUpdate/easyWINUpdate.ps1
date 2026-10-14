<#
.SYNOPSIS
    easyWINUpdate - Windows Update Verwaltungstool mit GUI
.DESCRIPTION
    Dieses Script ermöglicht die Verwaltung von Windows Updates auf Windows 11 und Windows Server 2019-2022.
    Es bietet eine moderne XAML-GUI zur Anzeige, Installation und Deinstallation von Updates sowie zur Verwaltung
    der Update-Quellen und WSUS-Einstellungen.
.NOTES
    Version:        0.2.5
    Author:         Andreas Hepp | PhinIT (www.phinit.de)
    Creation Date:  31.05.2025
    Voraussetzungen: Windows PowerShell 5.1 oder PowerShell 7 (Windows), Modul PSWindowsUpdate, Administratorrechte
    Logs:           Unterordner "Logs" im Skriptverzeichnis (Fallback: %LOCALAPPDATA%\easyWINUpdate\Logs)
#>

$script:AppVersion = '0.2.5'

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
            Write-Error "Die GUI benötigt einen STA-Thread. Bitte mit 'powershell.exe -STA -File `"$PSCommandPath`"' starten."
            exit 1
        }
        Write-Warning "Keine Administratorrechte erhalten - viele Funktionen (Dienste, Registry, DISM/SFC) stehen nicht zur Verfügung."
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

# Fehlercode-Mapping mit bekannten Lösungen
$errorCodes = @{
    "0x80072EE7" = @{
        "Description" = "WININET_E_CANNOT_RESOLVE_NAME / Servername oder -adresse konnte nicht aufgelöst werden (DNS-Problem)";
        "Solutions" = @(
            "DNS-Cache leeren (ipconfig /flushdns)",
            "Proxy-Einstellungen prüfen",
            "Netzwerkverbindung prüfen",
            "Windows Update-Dienste neu starten"
        )
    };
    "0x8024402C" = @{
        "Description" = "WU_E_PT_WINHTTP_NAME_NOT_RESOLVED / Fehler bei der DNS-Auflösung";
        "Solutions" = @(
            "DNS-Cache leeren (ipconfig /flushdns)",
            "DNS-Servereinstellungen prüfen",
            "Alternative DNS-Server konfigurieren",
            "Netzwerkadapter zurücksetzen"
        )
    };
    "0x8024401B" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_PROXY_AUTH_REQ / Proxy-Authentifizierung erforderlich";
        "Solutions" = @(
            "Proxy-Einstellungen prüfen und Benutzerauthentifizierung konfigurieren",
            "WinHTTP-Proxy zurücksetzen (netsh winhttp reset proxy)",
            "Netzwerkverbindung prüfen",
            "Windows Update-Komponenten zurücksetzen"
        )
    };
    "0x80244018" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_FORBIDDEN / Zugriff verweigert (HTTP 403)";
        "Solutions" = @(
            "Firewall-/Proxy-Regeln prüfen",
            "Zugriffsberechtigungen prüfen",
            "Windows Update-Dienste neu starten",
            "Temporäre Dateien löschen"
        )
    };
    "0x80244019" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_NOT_FOUND / Update nicht gefunden (HTTP 404)";
        "Solutions" = @(
            "WSUS-/Update-Quelle prüfen",
            "Proxy-Einstellungen importieren (netsh winhttp import proxy source=ie)",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80244022" = @{
        "Description" = "WU_E_PT_HTTP_STATUS_SERVICE_UNAVAIL / Update-Server nicht verfügbar (HTTP 503)";
        "Solutions" = @(
            "Später erneut versuchen",
            "Status der Microsoft Update-Server prüfen",
            "Alternative Update-Quelle verwenden",
            "Netzwerkverbindung prüfen"
        )
    };
    "0x80072EFD" = @{
        "Description" = "WININET_E_TIMEOUT / Zeitüberschreitung beim Verbindungsaufbau";
        "Solutions" = @(
            "Netzwerkverbindung prüfen",
            "Firewall-/Proxy-Einstellungen prüfen",
            "Windows Update-Dienste neu starten",
            "Später erneut versuchen"
        )
    };
    "0x80072EFE" = @{
        "Description" = "WININET_E_INVALID_URL / Ungültige URL des Update-Servers";
        "Solutions" = @(
            "Adresse des Update-Servers prüfen",
            "Windows Update-Cache leeren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80D02002" = @{
        "Description" = "BG_E_NETWORK_FAILURE / Netzwerkfehler beim Update-Download";
        "Solutions" = @(
            "Internetverbindung prüfen",
            "Firewall-/Proxy-Einstellungen prüfen",
            "BITS zurücksetzen (bitsadmin /reset)",
            "Windows Update-Komponenten zurücksetzen"
        )
    };
    "0x80072EE2" = @{
        "Description" = "WININET_E_CONNECTION_TIMEOUT / Verbindung zum Update-Server konnte nicht hergestellt werden";
        "Solutions" = @(
            "Netzwerkverbindung prüfen",
            "Datums- und Uhrzeiteinstellungen prüfen",
            "TLS 1.2 aktivieren",
            "Windows Update-Dienste neu starten"
        )
    };
    "0x80072F8F" = @{
        "Description" = "WININET_E_DECODING_FAILED / TLS-/SSL-Fehler";
        "Solutions" = @(
            "TLS 1.2 aktivieren",
            "Systemdatum/-uhrzeit korrigieren",
            "Windows Update-Agent aktualisieren",
            "Windows Update-Dienste neu starten"
        )
    };
    "0x80200053" = @{
        "Description" = "BG_E_VALIDATION_FAILED / Dateiprüfung fehlgeschlagen";
        "Solutions" = @(
            "Webfilter/Firewall prüfen",
            "Antivirensoftware vorübergehend deaktivieren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80244007" = @{
        "Description" = "WU_E_PT_SOAPCLIENT_SOAPFAULT / SOAP-Fehler bei der Update-Suche (WSUS)";
        "Solutions" = @(
            "WSUS-Servereinstellungen prüfen",
            "WSUS-Client zurücksetzen (wuauclt /resetauthorization /detectnow)",
            "Windows Update-Dienste neu starten",
            "System neu starten"
        )
    };
    "0x8024D009" = @{
        "Description" = "WU_E_SETUP_SKIP_UPDATE / Selbstaktualisierung des Windows Update-Agents übersprungen";
        "Solutions" = @(
            "WSUS-Selbstaktualisierung reparieren",
            "Berechtigungen des virtuellen Verzeichnisses prüfen",
            "Windows Update-Dienste neu starten",
            "System neu starten"
        )
    };
    "0x8024402F" = @{
        "Description" = "WU_E_PT_ECP_SUCCEEDED_WITH_ERRORS / Verarbeitung der externen CAB-Datei mit Fehlern abgeschlossen";
        "Solutions" = @(
            "Ausnahmen im Webfilter konfigurieren",
            "Windows Update-Komponenten zurücksetzen",
            "Temporäre Dateien löschen",
            "System neu starten"
        )
    };
    "0x8024A10A" = @{
        "Description" = "USO_E_SERVICE_SHUTTING_DOWN / Windows Update-Dienst wird beendet";
        "Solutions" = @(
            "System während der Updates aktiv halten",
            "Windows Update-Dienste neu starten",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80070422" = @{
        "Description" = "ERROR_SERVICE_DISABLED / Windows Update-Dienst ist deaktiviert oder nicht gestartet";
        "Solutions" = @(
            "sc config wuauserv start= auto && sc start wuauserv",
            "Registry-Einstellungen der Update-Dienste prüfen",
            "Gruppenrichtlinien überprüfen",
            "Systemdiagnose ausführen"
        )
    };
    "0x80240020" = @{
        "Description" = "WU_E_NO_INTERACTIVE_USER / Kein interaktiver Benutzer angemeldet";
        "Solutions" = @(
            "Als Benutzer anmelden und Update erneut starten",
            "System neu starten",
            "Windows Update-Dienste neu starten",
            "Windows Update-Komponenten zurücksetzen"
        )
    };
    "0x80242014" = @{
        "Description" = "WU_E_UH_POSTREBOOTSTILLPENDING / Update wartet auf Neustart";
        "Solutions" = @(
            "System neu starten",
            "Windows Update-Dienste neu starten",
            "Windows Update-Komponenten zurücksetzen",
            "Systemdiagnose ausführen"
        )
    };
    "0x80070BC9" = @{
        "Description" = "ERROR_FAIL_REBOOT_REQUIRED / Ausstehender Neustart erforderlich";
        "Solutions" = @(
            "System neu starten",
            "Temporäre Update-Dateien löschen",
            "Windows Update-Komponenten zurücksetzen",
            "Systemdiagnose ausführen"
        )
    };
    "0x800706BE" = @{
        "Description" = "RPC_S_CALL_FAILED / RPC-Kommunikationsfehler";
        "Solutions" = @(
            "RPC-Dienste prüfen und neu starten",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten",
            "Systemdateien reparieren (sfc /scannow)"
        )
    };
    "0x80246017" = @{
        "Description" = "WU_E_DM_UNAUTHORIZED_LOCAL_USER / Download verweigert (Benutzerrechte)";
        "Solutions" = @(
            "Als Administrator anmelden",
            "Benutzerrechte prüfen",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x8007000D" = @{
        "Description" = "ERROR_INVALID_DATA / Ungültige oder beschädigte Update-Daten";
        "Solutions" = @(
            "Update erneut herunterladen",
            "Windows Update-Cache leeren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80070490" = @{
        "Description" = "ERROR_NOT_FOUND / Update-Element nicht gefunden";
        "Solutions" = @(
            "Registry-Wert prüfen",
            "Windows Update-Komponenten zurücksetzen",
            "Windows Update-Dienste neu starten",
            "System neu starten"
        )
    };
    "0x80242006" = @{
        "Description" = "WU_E_UH_INVALIDMETADATA / Ungültige Metadaten im Update";
        "Solutions" = @(
            "SoftwareDistribution\\DataStore umbenennen",
            "Catroot2 umbenennen",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x8024200D" = @{
        "Description" = "SUS_E_UH_NEEDANOTHERDOWNLOAD / Ein weiterer Download ist erforderlich";
        "Solutions" = @(
            "Update erneut herunterladen",
            "Aktuellen Servicing Stack installieren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80246007" = @{
        "Description" = "WU_E_DM_NOTDOWNLOADED / Update nicht heruntergeladen";
        "Solutions" = @(
            "BITS zurücksetzen (bitsadmin /reset)",
            "Windows Update-Komponenten zurücksetzen",
            "Windows Update-Dienste neu starten",
            "System neu starten"
        )
    };
    "0x800705B4" = @{
        "Description" = "ERROR_TIMEOUT / Zeitüberschreitung des Vorgangs";
        "Solutions" = @(
            "Später erneut versuchen",
            "Windows Update-Problembehandlung ausführen",
            "Windows Update-Dienste neu starten",
            "System neu starten"
        )
    };
    "0x8024000B" = @{
        "Description" = "WU_E_CALL_CANCELLED / Vorgang abgebrochen";
        "Solutions" = @(
            "Update erneut ohne Abbruch ausführen",
            "Windows Update-Dienste neu starten",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80070643" = @{
        "Description" = "FATAL_ERROR_DURING_INSTALLATION / Schwerwiegender Fehler während der Installation";
        "Solutions" = @(
            "sfc /scannow (Systemdateien reparieren)",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten",
            "Windows-Systemdateien reparieren"
        )
    };
    "0x800B0109" = @{
        "Description" = "TRUST_E_CERT_SIGNATURE / Zertifikatkette endet in einem nicht vertrauenswürdigen Stammzertifikat";
        "Solutions" = @(
            "Systemdateien reparieren (sfc /scannow)",
            "Fehlendes Stammzertifikat installieren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80070005" = @{
        "Description" = "E_ACCESSDENIED / Zugriff verweigert (Berechtigungsproblem)";
        "Solutions" = @(
            "Berechtigungen der betroffenen Dateien/Registry-Pfade anpassen",
            "Als Administrator ausführen",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80070570" = @{
        "Description" = "ERROR_FILE_CORRUPT / Datei oder Verzeichnis beschädigt (Komponentenspeicher)";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80070003" = @{
        "Description" = "ERROR_PATH_NOT_FOUND / Ein benötigter Pfad wurde nicht gefunden";
        "Solutions" = @(
            "Fehler in %windir%\\Logs\\CBS\\CBS.log suchen",
            "Pfade prüfen und korrigieren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80070020" = @{
        "Description" = "ERROR_SHARING_VIOLATION / Freigabeverletzung beim Dateizugriff";
        "Solutions" = @(
            "Sauberen Systemstart durchführen",
            "Blockierenden Prozess mit Process Monitor ermitteln",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80073701" = @{
        "Description" = "ERROR_SXS_ASSEMBLY_MISSING / Referenzierte Assembly nicht gefunden (Komponentenspeicher inkonsistent)";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x8007371B" = @{
        "Description" = "ERROR_SXS_TRANSACTION_CLOSURE_INCOMPLETE / Transaktion nicht abgeschlossen";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x80073712" = @{
        "Description" = "ERROR_SXS_COMPONENT_STORE_CORRUPT / Komponentenspeicher ist beschädigt";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "Inplace-Upgrade in Betracht ziehen",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x800F081F" = @{
        "Description" = "CBS_E_SOURCE_MISSING / Quellpaket/-datei nicht gefunden (häufig .NET Framework-Problem)";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth /Source:<Pfad>",
            "Komponentenspeicher reparieren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x800F0831" = @{
        "Description" = "CBS_E_STORE_CORRUPTION / Beschädigung des Komponentenspeichers";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x800F0821" = @{
        "Description" = "CBS_E_ABORT / Vorgang vom Client abgebrochen (Zeitüberschreitung)";
        "Solutions" = @(
            "Mehr Ressourcen bereitstellen (CPU/RAM erhöhen)",
            "Patch KB4493473 oder neuer installieren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
        )
    };
    "0x800F0825" = @{
        "Description" = "CBS_E_CANNOT_UNINSTALL / Paket kann nicht deinstalliert werden";
        "Solutions" = @(
            "DISM /Online /Cleanup-Image /RestoreHealth",
            "sfc /scannow",
            "System neu starten",
            "Windows Update-Komponenten zurücksetzen"
        )
    };
    "0x800F0920" = @{
        "Description" = "CBS_E_HANG_DETECTED / Hänger bei der Update-Verarbeitung erkannt";
        "Solutions" = @(
            "VM-Ressourcen erhöhen",
            "Zeitlimit erhöhen",
            "Patch KB4493473 oder neuer installieren",
            "System neu starten"
        )
    };
    "0x800F0922" = @{
        "Description" = "CBS_E_INSTALLERS_FAILED / Installationsroutinen fehlgeschlagen";
        "Solutions" = @(
            "Schreibrechte für C:\\Windows\\System32\\spp anpassen",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten",
            "Windows Update-Dienste neu starten"
        )
    };
    "0xC1900101" = @{
        "Description" = "Allgemeiner Installationsfehler beim Upgrade (Rollback)";
        "Solutions" = @(
            "Treiber aktualisieren",
            "Nicht benötigte Hardware entfernen",
            "Ausreichend Speicherplatz sicherstellen",
            "System neu starten"
        )
    };
    "0xC1900107" = @{
        "Description" = "Bereinigungsvorgang noch ausstehend / Neustart erforderlich";
        "Solutions" = @(
            "System neu starten",
            "Temporäre Windows Update-Dateien bereinigen",
            "Datenträgerbereinigung ausführen",
            "Windows Update-Dienste neu starten"
        )
    };
    "0xC1900201" = @{
        "Description" = "Systemreservierte Partition konnte nicht aktualisiert werden (zu wenig Speicherplatz)";
        "Solutions" = @(
            "Speicherplatz auf der reservierten Partition vergrößern",
            "Nicht benötigte Sprachpakete entfernen",
            "Partition vergrößern",
            "System neu starten"
        )
    };
    "0x80240034" = @{
        "Description" = "WU_E_PT_ECP_FAILURE_TO_DECOMPRESS_CAB_FILE / Externes CAB-Archiv konnte nicht entpackt werden";
        "Solutions" = @(
            "Windows Update-Komponenten zurücksetzen",
            "Temporäre Update-Dateien löschen",
            "System neu starten",
            "DISM /Online /Cleanup-Image /RestoreHealth ausführen"
        )
    };
    "0x8024001F" = @{
        "Description" = "WU_E_NO_CONNECTION / Keine Verbindung zum Update-Dienst";
        "Solutions" = @(
            "Netzwerkverbindung prüfen",
            "Firewall- und Proxy-Einstellungen prüfen",
            "Netzwerkadapter neu starten",
            "Windows Update-Dienste neu starten"
        )
    };
    "0x80240003" = @{
        "Description" = "WU_E_UNKNOWN_ID / Eine ID wurde nicht gefunden";
        "Solutions" = @(
            "Windows Update-Cache leeren",
            "Update manuell installieren",
            "Windows Update-Komponenten zurücksetzen",
            "System neu starten"
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
        Write-Verbose "PSWindowsUpdate-Modul wurde installiert und importiert."
    } catch {
        Write-AppLog -Message "Fehler beim Installieren des PSWindowsUpdate-Moduls: $_" -Level 'ERROR'
        Write-Error "Fehler beim Installieren des PSWindowsUpdate-Moduls: $_"
        Write-Warning "Bitte führen Sie 'Install-Module -Name PSWindowsUpdate -Force' manuell mit administrativen Rechten aus."
        exit
    }
} else {
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
    } catch {
        Write-AppLog -Message "Fehler beim Importieren des PSWindowsUpdate-Moduls: $_" -Level 'ERROR'
        Write-Error "Fehler beim Importieren des PSWindowsUpdate-Moduls: $_"
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
    Title="easyWINUpdate v$($script:AppVersion) - Windows Update-Verwaltung" Height="950" Width="1400"
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
                    <TextBlock Text="v$($script:AppVersion)" Foreground="#CCFFFFFF" FontSize="14" Margin="10,0,0,0" VerticalAlignment="Center"/>
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
                    <RadioButton x:Name="navHome" Content="Startseite" GroupName="Navigation"
                                IsChecked="True" Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>

                    <RadioButton x:Name="navInstalledUpdates" Content="Installierte Updates" GroupName="Navigation"
                                Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>

                    <RadioButton x:Name="navAvailableUpdates" Content="Verfügbare Updates" GroupName="Navigation"
                                Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>

                    <RadioButton x:Name="navWSUSSettings" Content="WSUS-Einstellungen" GroupName="Navigation"
                                Height="50" FontSize="14" Padding="15,0,0,0"
                                Foreground="#333333" Style="{StaticResource NavButtonStyle}"/>

                    <RadioButton x:Name="navTroubleshooting" Content="Fehlerbehebung" GroupName="Navigation"
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
                            <TextBlock Text="Willkommen bei easyWINUpdate" FontSize="24" FontWeight="SemiBold" Margin="0,0,0,20"/>

                            <!-- System Info Section -->
                            <Border Background="#F0F8FF" BorderBrush="#99CCE8" BorderThickness="1" Padding="20" CornerRadius="4" Margin="0,0,0,20">
                                <StackPanel>
                                    <TextBlock Text="Systeminformationen" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>

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

                                        <TextBlock Grid.Row="0" Grid.Column="0" Text="Windows-Version:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="0" Grid.Column="1" x:Name="txtWindowsVersion" Text="Wird geladen..." Margin="0,5,0,5"/>

                                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Update-Quelle:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="1" Grid.Column="1" x:Name="txtUpdateSource" Text="Wird geladen..." Margin="0,5,0,5"/>

                                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Letztes Update:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="2" Grid.Column="1" x:Name="txtLastUpdate" Text="Wird geladen..." Margin="0,5,0,5"/>

                                        <TextBlock Grid.Row="3" Grid.Column="0" Text="Update-Status:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="3" Grid.Column="1" x:Name="txtUpdateStatus" Text="Wird geladen..." Margin="0,5,0,5"/>

                                        <TextBlock Grid.Row="4" Grid.Column="0" Text="Installierte Updates:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                        <TextBlock Grid.Row="4" Grid.Column="1" x:Name="txtInstalledUpdatesCount" Text="Wird geladen..." Margin="0,5,0,5"/>
                                    </Grid>

                                    <Button x:Name="btnCheckForUpdates" Content="Nach Updates suchen" Padding="15,8"
                                            Background="#0078D7" Foreground="White" BorderThickness="0"
                                            HorizontalAlignment="Left" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Border>

                            <!-- Features Section -->
                            <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="20" CornerRadius="4" Margin="0,0,0,20">
                                <StackPanel>
                                    <TextBlock Text="Hauptfunktionen" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>

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
                                            <TextBlock Text="Installierte Updates" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="Bereits installierte Updates anzeigen und verwalten" />
                                        </StackPanel>

                                        <StackPanel Grid.Column="1" Grid.Row="0" Margin="10,0,0,15">
                                            <TextBlock Text="Verfügbare Updates" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="Ausstehende Updates suchen und installieren" />
                                        </StackPanel>

                                        <StackPanel Grid.Column="0" Grid.Row="1" Margin="0,0,10,0">
                                            <TextBlock Text="WSUS-Einstellungen" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="Anbindung an Windows Server Update Services (WSUS) konfigurieren" />
                                        </StackPanel>

                                        <StackPanel Grid.Column="1" Grid.Row="1" Margin="10,0,0,0">
                                            <TextBlock Text="Fehlerbehebung" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                            <TextBlock TextWrapping="Wrap" Text="Häufige Windows Update-Probleme beheben" />
                                        </StackPanel>
                                    </Grid>
                                </StackPanel>
                            </Border>

                            <!-- Admin Note Section -->
                            <Border Background="#FFF8E8" BorderBrush="#FFDD99" BorderThickness="1" Padding="20" CornerRadius="4" Margin="0,0,0,20">
                                <StackPanel>
                                    <TextBlock Text="Hinweis" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                    <TextBlock TextWrapping="Wrap">
                                        Einige Aktionen erfordern Administratorrechte. Bei Berechtigungsproblemen die Anwendung bitte über &quot;Als Administrator ausführen&quot; neu starten.
                                    </TextBlock>
                                </StackPanel>
                            </Border>

                            <!-- About Section -->
                            <Border Background="#E8F5E9" BorderBrush="#A5D6A7" BorderThickness="1" Padding="20" CornerRadius="4">
                                <StackPanel>
                                    <TextBlock Text="Über easyWINUpdate" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                    <TextBlock TextWrapping="Wrap" Margin="0,0,0,10">
                                        easyWINUpdate ist ein Werkzeug zur Verwaltung von Windows Updates auf Windows 11 und Windows Server 2019-2022.
                                    </TextBlock>
                                    <TextBlock TextWrapping="Wrap">
                                        Damit können Sie den Update-Status prüfen, Updates installieren oder deinstallieren, WSUS-Einstellungen konfigurieren und häufige Probleme beheben.
                                    </TextBlock>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>

                <!-- Installed Updates Page -->
                <Grid x:Name="installedUpdatesPage" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="Installierte Windows Updates" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,20"/>

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
                                                    <TextBlock Text="Nach KB-Nummer oder Titel filtern..." FontStyle="Italic" />
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
                            <Button x:Name="btnSearchInstalled" Grid.Column="1" Content="Suchen" Padding="15,8"
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                        </Grid>

                        <DataGrid x:Name="dgInstalledUpdates" AutoGenerateColumns="False" HeadersVisibility="Column"
                                IsReadOnly="True" BorderThickness="1" BorderBrush="#DDDDDD"
                                Background="White" RowBackground="White" AlternatingRowBackground="#F8F8F8"
                                VerticalScrollBarVisibility="Auto" Height="400">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="KB-Nummer" Binding="{Binding HotFixID}" Width="100"/>
                                <DataGridTextColumn Header="Beschreibung" Binding="{Binding Description}" Width="*"/>
                                <DataGridTextColumn Header="Installiert am" Binding="{Binding InstalledOn}" Width="150"/>
                                <DataGridTemplateColumn Header="Aktionen" Width="100">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Button Content="Entfernen" Tag="{Binding HotFixID}" x:Name="btnRemoveUpdate"
                                                    Padding="10,5" Margin="5" Background="#E81123" Foreground="White" BorderThickness="0"/>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>
                            </DataGrid.Columns>
                        </DataGrid>

                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                            <Button x:Name="btnRefreshInstalled" Content="Aktualisieren" Padding="15,8" Margin="0,0,10,0"
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                            <Button x:Name="btnExportInstalled" Content="Liste exportieren" Padding="15,8"
                                    Background="#107C10" Foreground="White" BorderThickness="0"/>
                        </StackPanel>
                    </StackPanel>
                </Grid>

                <!-- Available Updates Page -->
                <Grid x:Name="availableUpdatesPage" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="Verfügbare Windows Updates" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,20"/>

                        <!-- Progress Bar -->
                        <ProgressBar x:Name="progressAvailableUpdates" IsIndeterminate="True" Height="10" Margin="0,0,0,10" Visibility="Collapsed"/>

                        <Grid Margin="0,0,0,10">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Orientation="Horizontal">
                                <CheckBox x:Name="chkCriticalUpdates" Content="Kritische Updates" IsChecked="True" Margin="0,0,15,0"/>
                                <CheckBox x:Name="chkSecurityUpdates" Content="Sicherheitsupdates" IsChecked="True" Margin="0,0,15,0"/>
                                <CheckBox x:Name="chkDefinitionUpdates" Content="Definitionsupdates" IsChecked="True" Margin="0,0,15,0"/>
                                <CheckBox x:Name="chkFeatureUpdates" Content="Funktionsupdates" IsChecked="False"/>
                            </StackPanel>

                            <Button x:Name="btnSearchAvailable" Grid.Column="1" Content="Nach Updates suchen" Padding="15,8" Margin="10,0"
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                            <Button x:Name="btnInstallAll" Grid.Column="2" Content="Alle installieren" Padding="15,8"
                                    Background="#107C10" Foreground="White" BorderThickness="0"/>
                        </Grid>

                        <ProgressBar x:Name="progressUpdates" Height="5" Margin="0,0,0,10" Visibility="Collapsed"/>

                        <DataGrid x:Name="dgAvailableUpdates" AutoGenerateColumns="False" HeadersVisibility="Column"
                                IsReadOnly="False" BorderThickness="1" BorderBrush="#DDDDDD"
                                Background="White" RowBackground="White" AlternatingRowBackground="#F8F8F8"
                                VerticalScrollBarVisibility="Auto" Height="400">
                            <DataGrid.Columns>
                                <DataGridCheckBoxColumn Header="Auswahl" Binding="{Binding IsSelected}" Width="80"/>
                                <DataGridTextColumn Header="KB-Nummer" Binding="{Binding KBArticleID}" Width="100"/>
                                <DataGridTextColumn Header="Titel" Binding="{Binding Title}" Width="*"/>
                                <DataGridTextColumn Header="Kategorie" Binding="{Binding Category}" Width="120"/>
                                <DataGridTextColumn Header="Größe" Binding="{Binding Size}" Width="100"/>
                                <DataGridTemplateColumn Header="Aktionen" Width="120">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Button Content="Installieren" Tag="{Binding Identity}" x:Name="btnInstallUpdate"
                                                    Padding="10,5" Margin="5" Background="#107C10" Foreground="White" BorderThickness="0"/>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>
                            </DataGrid.Columns>
                        </DataGrid>

                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                            <Button x:Name="btnInstallSelected" Content="Auswahl installieren" Padding="15,8" Margin="0,0,10,0"
                                    Background="#107C10" Foreground="White" BorderThickness="0"/>
                            <Button x:Name="btnDownloadSelected" Content="Auswahl herunterladen" Padding="15,8"
                                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
                        </StackPanel>
                    </StackPanel>
                </Grid>

                <!-- WSUS Settings Page -->
                <Grid x:Name="wsusSettingsPage" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="WSUS-Einstellungen" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,20"/>

                        <!-- TabControl for advanced WSUS settings -->
                        <TabControl Background="Transparent" BorderThickness="0" Margin="0,0,0,0">
                            <!-- Tab 1: Status -->
                            <TabItem Header="Status">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Aktuelle WSUS-Konfiguration" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
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

                                                <TextBlock Grid.Row="0" Grid.Column="0" Text="WSUS-Server:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="0" Grid.Column="1" x:Name="txtWSUSServer" Text="Wird geladen..." Margin="0,5,0,5"/>

                                                <TextBlock Grid.Row="1" Grid.Column="0" Text="WSUS-Status:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="1" Grid.Column="1" x:Name="txtWSUSStatus" Text="Wird geladen..." Margin="0,5,0,5"/>

                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Zielgruppe:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="2" Grid.Column="1" x:Name="txtWSUSTargetGroup" Text="Wird geladen..." Margin="0,5,0,5"/>

                                                <TextBlock Grid.Row="3" Grid.Column="0" Text="Konfigurationsquelle:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="3" Grid.Column="1" x:Name="txtWSUSConfigSource" Text="Wird geladen..." Margin="0,5,0,5"/>

                                                <TextBlock Grid.Row="4" Grid.Column="0" Text="Letzte Prüfung:" FontWeight="SemiBold" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="4" Grid.Column="1" x:Name="txtWSUSLastCheck" Text="Wird geladen..." Margin="0,5,0,5"/>
                                            </Grid>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#F0F7FF" BorderBrush="#99CCF9" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="WSUS-Einstellungen zurücksetzen" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Nach dem Zurücksetzen der WSUS-Einstellungen bezieht der Client Updates wieder direkt von Microsoft.
                                                Die vorhandene WSUS-Konfiguration wird entfernt und die Windows Update-Dienste werden neu gestartet.
                                            </TextBlock>
                                            <Button x:Name="btnResetWSUS" Content="WSUS-Einstellungen zurücksetzen" Padding="15,8"
                                                    Background="#E81123" Foreground="White" BorderThickness="0" HorizontalAlignment="Left"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#F5FFF0" BorderBrush="#99F9CC" BorderThickness="1" Padding="15" CornerRadius="4">
                                        <StackPanel>
                                            <TextBlock Text="WSUS-Verbindung prüfen" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Prüft die Verbindung zum konfigurierten WSUS-Server und gleicht die Client-Einstellungen ab.
                                            </TextBlock>
                                            <StackPanel Orientation="Horizontal">
                                                <Button x:Name="btnCheckWSUSConn" Content="WSUS-Verbindung prüfen" Padding="15,8"
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnDetectNow" Content="Update-Erkennung starten" Padding="15,8"
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>

                            <!-- Tab 2: Manuelle Konfiguration -->
                            <TabItem Header="Manuelle Konfiguration">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="WSUS-Server manuell konfigurieren" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Hier wird die Verbindung zu einem WSUS-Server konfiguriert. Diese Einstellungen überschreiben vorübergehend die Gruppenrichtlinieneinstellungen.
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

                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="SSL verwenden:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <CheckBox Grid.Row="2" Grid.Column="1" x:Name="chkManualWSUSUseSSL" Margin="0,5,0,5" Content="SSL/TLS für die Verbindung verwenden"/>

                                                <TextBlock Grid.Row="3" Grid.Column="0" Text="Zielgruppe:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="3" Grid.Column="1" x:Name="cmbManualWSUSTargetGroup" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Standard"/>
                                                </ComboBox>
                                            </Grid>

                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnLoadWSUSTargetGroups" Content="Zielgruppen laden" Padding="15,8"
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnApplyManualWSUS" Content="Konfiguration übernehmen" Padding="15,8"
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>

                            <!-- Tab 3: Group Policy -->
                            <TabItem Header="Gruppenrichtlinie">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Windows Update-Gruppenrichtlinien" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Diese Einstellungen spiegeln die aktuellen Gruppenrichtlinieneinstellungen für Windows Update wider. Änderungen werden in der lokalen Registry gespeichert und können lokale Einstellungen überschreiben.
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
                                                    <ComboBoxItem Content="Aktiviert"/>
                                                    <ComboBoxItem Content="Deaktiviert"/>
                                                </ComboBox>

                                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Konfigurationstyp:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="1" Grid.Column="1" x:Name="cmbUpdateConfigType" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Nur benachrichtigen"/>
                                                    <ComboBoxItem Content="Herunterladen und benachrichtigen"/>
                                                    <ComboBoxItem Content="Automatisch herunterladen und installieren"/>
                                                </ComboBox>

                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Installationszeit:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="2" Grid.Column="1" x:Name="cmbInstallTime" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="03:00"/>
                                                    <ComboBoxItem Content="04:00"/>
                                                    <ComboBoxItem Content="05:00"/>
                                                    <ComboBoxItem Content="10:00"/>
                                                    <ComboBoxItem Content="15:00"/>
                                                    <ComboBoxItem Content="22:00"/>
                                                </ComboBox>

                                                <TextBlock Grid.Row="3" Grid.Column="0" Text="Benachrichtigungen anzeigen:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <CheckBox Grid.Row="3" Grid.Column="1" x:Name="chkShowNotifications" Margin="0,5,0,5" Content="Benachrichtigungen anzeigen"/>

                                                <TextBlock Grid.Row="4" Grid.Column="0" Text="Neustartverhalten:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="4" Grid.Column="1" x:Name="cmbRebootBehavior" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Sofort neu starten"/>
                                                    <ComboBoxItem Content="Benutzer benachrichtigen"/>
                                                    <ComboBoxItem Content="Automatisch nach 15 Minuten"/>
                                                    <ComboBoxItem Content="Geplanter Neustart"/>
                                                </ComboBox>
                                            </Grid>

                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnRefreshGPOSettings" Content="Einstellungen aktualisieren" Padding="15,8"
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnApplyGPOSettings" Content="Einstellungen übernehmen" Padding="15,8"
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>

                            <!-- Tab 4: Target Groups -->
                            <TabItem Header="Zielgruppen">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="WSUS-Zielgruppen" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Typische WSUS-Zielgruppen (clientseitige Zielgruppenadressierung). Die gewählte Gruppe muss auf dem WSUS-Server existieren. Hier kann die Zielgruppe dieses Computers geändert werden.
                                            </TextBlock>

                                            <DataGrid x:Name="dgWSUSTargetGroups" AutoGenerateColumns="False" Margin="0,0,0,15"
                                                      HeadersVisibility="Column" CanUserAddRows="False" Height="200">
                                                <DataGrid.Columns>
                                                    <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="2*" />
                                                    <DataGridTextColumn Header="Beschreibung" Binding="{Binding Description}" Width="3*" />
                                                    <DataGridTextColumn Header="Computer" Binding="{Binding ComputerCount}" Width="*" />
                                                </DataGrid.Columns>
                                            </DataGrid>

                                            <Grid Margin="0,10,0,15">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>

                                                <TextBlock Grid.Column="0" Text="Aktuelle Zielgruppe:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                                <TextBlock Grid.Column="1" x:Name="txtCurrentTargetGroup" Text="Wird geladen..." VerticalAlignment="Center"/>
                                            </Grid>

                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnRefreshTargetGroups" Content="Zielgruppen aktualisieren" Padding="15,8"
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnSetTargetGroup" Content="Zielgruppe festlegen" Padding="15,8"
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>

                            <!-- Tab 5: Synchronisierung -->
                            <TabItem Header="Synchronisierung">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="WSUS-Synchronisierung steuern" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Hier steuern Sie die Synchronisierung mit dem WSUS-Server und sehen den Verlauf ein.
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

                                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Letzte Synchronisierung:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <TextBlock Grid.Row="0" Grid.Column="1" x:Name="txtLastSyncTime" Text="Wird geladen..." VerticalAlignment="Center" Margin="0,5,0,5"/>

                                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Synchronisierungsintervall:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Row="1" Grid.Column="1" x:Name="cmbSyncInterval" Margin="0,5,0,5" Padding="5,3">
                                                    <ComboBoxItem Content="Automatisch (Windows-Standard)"/>
                                                    <ComboBoxItem Content="Täglich"/>
                                                    <ComboBoxItem Content="Wöchentlich"/>
                                                    <ComboBoxItem Content="Monatlich"/>
                                                </ComboBox>

                                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Automatische Synchronisierung:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <CheckBox Grid.Row="2" Grid.Column="1" x:Name="chkAutoSync" Margin="0,5,0,5" Content="Automatische Synchronisierung aktivieren" IsChecked="True"/>
                                            </Grid>

                                            <TextBlock Text="Synchronisierungsverlauf" FontWeight="SemiBold" Margin="0,10,0,10"/>

                                            <DataGrid x:Name="dgSyncHistory" AutoGenerateColumns="False" Margin="0,0,0,15"
                                                      HeadersVisibility="Column" CanUserAddRows="False" Height="150">
                                                <DataGrid.Columns>
                                                    <DataGridTextColumn Header="Datum" Binding="{Binding Date}" Width="*" />
                                                    <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="*" />
                                                    <DataGridTextColumn Header="Details" Binding="{Binding Details}" Width="2*" />
                                                </DataGrid.Columns>
                                            </DataGrid>

                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <Button x:Name="btnSaveWSUSSyncSettings" Content="Einstellungen speichern" Padding="15,8"
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnStartWSUSSync" Content="Synchronisierung starten" Padding="15,8"
                                                        Background="#107C10" Foreground="White" BorderThickness="0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </TabItem>

                            <!-- Tab 6: Zeitplanung -->
                            <TabItem Header="Zeitplan">
                                <StackPanel Margin="0,15,0,0">
                                    <Border Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="15" CornerRadius="4" Margin="0,0,0,20">
                                        <StackPanel>
                                            <TextBlock Text="Windows Update-Zeitplan" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/>
                                            <TextBlock TextWrapping="Wrap" Margin="0,0,0,15">
                                                Legen Sie hier fest, wann Windows Updates automatisch gesucht, heruntergeladen und installiert werden sollen.
                                            </TextBlock>

                                            <!-- Enable/Disable automatic updates -->
                                            <CheckBox x:Name="chkEnableAutoUpdates" Content="Automatische Updates aktivieren" Margin="0,0,0,10"/>

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
                                                <TextBlock Grid.Column="0" Grid.Row="0" Text="Update-Zeitpunkt:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="0" x:Name="cmbUpdateScheduleType" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Täglich"/>
                                                    <ComboBoxItem Content="Wöchentlich"/>
                                                    <ComboBoxItem Content="Monatlich"/>
                                                </ComboBox>

                                                <!-- Zeile 2: Wochentag (only visible if weekly is selected) -->
                                                <TextBlock Grid.Column="0" Grid.Row="1" x:Name="lblWeekDay" Text="Wochentag:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="1" x:Name="cmbWeekDay" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Montag"/>
                                                    <ComboBoxItem Content="Dienstag"/>
                                                    <ComboBoxItem Content="Mittwoch"/>
                                                    <ComboBoxItem Content="Donnerstag"/>
                                                    <ComboBoxItem Content="Freitag"/>
                                                    <ComboBoxItem Content="Samstag"/>
                                                    <ComboBoxItem Content="Sonntag"/>
                                                </ComboBox>

                                                <!-- Zeile 3: Tag des Monats (only visible if monthly is selected) -->
                                                <TextBlock Grid.Column="0" Grid.Row="2" x:Name="lblMonthDay" Text="Tag des Monats:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="2" x:Name="cmbMonthDay" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <!-- Tage 1-31 werden dynamisch befüllt -->
                                                </ComboBox>

                                                <!-- Zeile 4: Time -->
                                                <TextBlock Grid.Column="0" Grid.Row="3" Text="Uhrzeit:" VerticalAlignment="Center" Margin="0,5,10,5"/>
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
                                                <TextBlock Grid.Column="0" Grid.Row="4" Text="Verhalten:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="4" x:Name="cmbUpdateBehavior" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Nur nach Updates suchen"/>
                                                    <ComboBoxItem Content="Suchen und herunterladen"/>
                                                    <ComboBoxItem Content="Suchen, herunterladen und automatisch installieren"/>
                                                </ComboBox>

                                                <!-- Zeile 6: Restart behavior -->
                                                <TextBlock Grid.Column="0" Grid.Row="5" Text="Nach der Installation:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                                                <ComboBox Grid.Column="1" Grid.Row="5" x:Name="cmbRestartBehavior" Margin="0,5,0,5" MinWidth="200" HorizontalAlignment="Left">
                                                    <ComboBoxItem Content="Benutzer benachrichtigen"/>
                                                    <ComboBoxItem Content="Automatisch neu starten"/>
                                                    <ComboBoxItem Content="Neustart planen für:"/>
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
                                                <Button x:Name="btnApplySchedule" Content="Zeitplan anwenden" Padding="15,8"
                                                        Background="#0078D7" Foreground="White" BorderThickness="0" Margin="0,0,10,0"/>
                                                <Button x:Name="btnViewCurrentSchedule" Content="Aktuellen Zeitplan anzeigen" Padding="15,8"
                                                        Background="#F0F0F0" BorderThickness="1" BorderBrush="#CCCCCC" Margin="0,0,0,0"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Aktuelle Zeitplan-Einstellungen anzeigen -->
                                    <Border Background="#F0F8FF" BorderBrush="#99CCE8" BorderThickness="1" Padding="15" CornerRadius="4">
                                        <StackPanel>
                                            <TextBlock Text="Aktueller Windows Update-Zeitplan" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                            <TextBlock x:Name="txtCurrentSchedule" TextWrapping="Wrap" Margin="0,0,0,10">
                                                Keine Zeitplan-Informationen verfügbar. Bitte auf &quot;Aktuellen Zeitplan anzeigen&quot; klicken.
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
                            <TextBlock Text="Windows Update-Fehlerbehebung" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,10"/>

                            <!-- Warning -->
                            <Border Background="#FFF4F4" BorderBrush="#FFCECE" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock TextWrapping="Wrap" Margin="0,0,0,5">
                                        <Bold>Warnung:</Bold> Die folgenden Aktionen können Windows Update-Komponenten zurücksetzen oder reparieren. Es wird empfohlen, vorher einen Systemwiederherstellungspunkt zu erstellen. Reparaturen laufen im Hintergrund; währenddessen sind die Reparatur-Schaltflächen gesperrt.
                                    </TextBlock>
                                    <Button x:Name="btnCreateRestorePoint" Content="Systemwiederherstellungspunkt erstellen" Padding="10,5"
                                            Background="#0078D7" Foreground="White" BorderThickness="0"
                                            HorizontalAlignment="Right" Margin="0,5,0,0"/>
                                </StackPanel>
                            </Border>

                            <!-- Fortschritt laufender Reparaturen (wird im Hintergrundbetrieb eingeblendet) -->
                            <Border x:Name="pnlRepairProgress" Background="#E8F1FB" BorderBrush="#9CC3EA" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,0,10" Visibility="Collapsed">
                                <StackPanel>
                                    <TextBlock x:Name="txtRepairProgress" Text="" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                    <ProgressBar x:Name="progressRepair" IsIndeterminate="True" Height="8"/>
                                </StackPanel>
                            </Border>

                            <!-- Grid for standard functions -->
                            <TextBlock Text="Standard-Fehlerbehebung" FontSize="16" FontWeight="SemiBold" Margin="0,5,0,10"/>
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
                                        <TextBlock Text="Komponenten zurücksetzen" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Setzt die Windows Update-Komponenten und -Dienste auf den Standardzustand zurück.
                                        </TextBlock>
                                        <Button x:Name="btnResetComponents" Content="Zurücksetzen" Padding="10,5"
                                                Background="#E81123" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Check system files -->
                                <Border Grid.Column="1" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Systemdateien prüfen" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Führt DISM und SFC aus, um beschädigte Systemdateien zu finden und zu reparieren, die Updates beeinträchtigen können.
                                        </TextBlock>
                                        <Button x:Name="btnCheckSystemFiles" Content="Prüfen" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Clear update history -->
                                <Border Grid.Column="2" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Update-Verlauf löschen" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Löscht Update-Verlauf, Caches und temporäre Update-Dateien, um Installationsprobleme zu beheben.
                                        </TextBlock>
                                        <Button x:Name="btnClearUpdateHistory" Content="Löschen" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Re-register DLLs -->
                                <Border Grid.Column="3" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="DLLs neu registrieren" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Registriert wichtige Windows Update-DLLs neu, um Registrierungsprobleme der Komponenten zu beheben.
                                        </TextBlock>
                                        <Button x:Name="btnRegisterDLLs" Content="Registrieren" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Remove stuck updates -->
                                <Border Grid.Column="0" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Hängende Updates" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Entfernt hängende BITS-Jobs und ausstehende Updates, die den Update-Vorgang blockieren können.
                                        </TextBlock>
                                        <Button x:Name="btnClearStuckUpdates" Content="Entfernen" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Additional box 1 -->
                                <Border Grid.Column="1" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Temporäre Dateien bereinigen" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Entfernt temporäre Dateien, die den Update-Vorgang stören können.
                                        </TextBlock>
                                        <Button x:Name="btnCleanTemp" Content="Bereinigen" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Additional box 2 -->
                                <Border Grid.Column="2" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Winsock zurücksetzen" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Setzt den Winsock-Katalog zurück, um netzwerkbedingte Update-Probleme zu beheben.
                                        </TextBlock>
                                        <Button x:Name="btnResetWinsock" Content="Zurücksetzen" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Additional box 3 -->
                                <Border Grid.Column="3" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="Datenträger prüfen" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Prüft den Systemdatenträger auf Fehler, die Update-Installationen scheitern lassen können.
                                        </TextBlock>
                                        <Button x:Name="btnCheckDisk" Content="Prüfen" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>
                            </Grid>

                            <!-- Grid for advanced functions -->
                            <TextBlock Text="Erweiterte Fehlerbehebung" FontSize="16" FontWeight="SemiBold" Margin="0,5,0,10"/>
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
                                        <TextBlock Text="Fehlerdiagnose" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Analysiert Windows Update-Fehlercodes und liefert gezielte Lösungsvorschläge.
                                        </TextBlock>
                                        <Button x:Name="btnDiagnoseError" Content="Diagnose starten" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Repair BITS -->
                                <Border Grid.Column="1" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="BITS-Dienst reparieren" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Repariert den Intelligenten Hintergrundübertragungsdienst (BITS), der für Update-Downloads benötigt wird.
                                        </TextBlock>
                                        <Button x:Name="btnRepairBITS" Content="Reparieren" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Check WaaSMedic -->
                                <Border Grid.Column="2" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="WaaSMedic prüfen" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Prüft und repariert den Windows Update Medic Service, der die Update-Funktion aufrechterhält.
                                        </TextBlock>
                                        <Button x:Name="btnWaaSMedic" Content="Prüfen" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Analyze update logs -->
                                <Border Grid.Column="3" Grid.Row="0" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="Logs analysieren" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Analysiert die Windows Update-Logs auf Fehler und Hinweise zur Fehlerbehebung.
                                        </TextBlock>
                                        <Button x:Name="btnAnalyzeLogs" Content="Analysieren" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Repair registry -->
                                <Border Grid.Column="0" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="0,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Registry reparieren" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Repariert Windows Update-bezogene Registry-Einstellungen.
                                        </TextBlock>
                                        <Button x:Name="btnRepairRegistry" Content="Reparieren" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Repair database -->
                                <Border Grid.Column="1" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Datenbank reparieren" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Repariert die Windows Update-Datenbank (SoftwareDistribution, catroot2) bei Beschädigungen.
                                        </TextBlock>
                                        <Button x:Name="btnRepairDatabase" Content="Reparieren" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Toggle debug mode -->
                                <Border Grid.Column="2" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,5,10">
                                    <StackPanel>
                                        <TextBlock Text="Fehlersuchmodus" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Schaltet die erweiterte Protokollierung für die Fehlersuche ein bzw. aus.
                                        </TextBlock>
                                        <Button x:Name="btnToggleDebug" Content="Umschalten" Padding="10,5"
                                                Background="#0078D7" Foreground="White" BorderThickness="0"
                                                HorizontalAlignment="Right"/>
                                    </StackPanel>
                                </Border>

                                <!-- Auto-Fix -->
                                <Border Grid.Column="3" Grid.Row="1" Background="#F5F5F5" BorderBrush="#DDDDDD" BorderThickness="1" Padding="10" CornerRadius="4" Margin="5,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="Auto-Fix" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,5"/>
                                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,5" Height="50">
                                            Führt eine umfassende automatische Fehlerbehebung für häufige Update-Probleme durch.
                                        </TextBlock>
                                        <Button x:Name="btnAutoFix" Content="Starten" Padding="10,5"
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
                <TextBlock x:Name="statusText" Text="Bereit" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <ProgressBar x:Name="progressBackground" Width="120" Height="10" IsIndeterminate="True" Margin="0,0,15,0" Visibility="Collapsed"/>
                    <TextBlock x:Name="versionText" Text="easyWINUpdate v$($script:AppVersion) - PhinIT" FontStyle="Italic" Foreground="#555555"/>
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
        Write-Verbose "GUI wurde erfolgreich geladen."
    } catch {
        Write-Error "Fehler beim Laden des XAML: $($_.Exception.Message)"
        if ($_.Exception.Message -like '*PlaceholderText*') {
            Write-Warning "Die Eigenschaft 'PlaceholderText' wird von WPF nicht unterstützt. Bitte durch eine WPF-kompatible Lösung ersetzen (z. B. TextBox mit VisualBrush)."
        }
        exit
    }
} catch {
    Write-Error "Fehler beim Erstellen des XmlNodeReader: $($_.Exception.Message)"
    exit
}

# Hauptfunktionen des Scripts
#region Hilfsfunktionen

# Aktualisiert die Statuszeile und schreibt die Meldung ins Log (nur im GUI-Thread aufrufen).
# In Hintergrund-Runspaces ersetzt Start-FunctionInBackground diese Funktion durch eine Variante,
# die die Meldung über $BackgroundMessages an den GUI-Thread übergibt.
function Write-StatusText {
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
# Der Runspace erhält die Warteschlange $BackgroundMessages: dort abgelegte Status- und Logmeldungen
# werden im GUI-Thread angezeigt bzw. protokolliert (der Runspace greift nie selbst auf WPF-Steuerelemente zu).
function Start-BackgroundTask {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [scriptblock]$OnCompleted,
        [string]$Name = 'Hintergrundaufgabe',
        [switch]$ShowRepairProgress
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Im Hintergrund ausführen')) {
        # OnCompleted trotzdem aufrufen, damit Sperren (z. B. einer laufenden Reparatur) wieder freigegeben werden
        if ($OnCompleted) { & $OnCompleted @() 'Ausführung übersprungen.' }
        return
    }

    $messageQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('BackgroundMessages', $messageQueue)

    $ps = [PowerShell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($ScriptBlock.ToString())
    if ($Parameters.Count -gt 0) {
        [void]$ps.AddParameters($Parameters)
    }

    $task = [PSCustomObject]@{
        Name               = $Name
        PowerShell         = $ps
        Handle             = $ps.BeginInvoke()
        OnCompleted        = $OnCompleted
        Messages           = $messageQueue
        ShowRepairProgress = [bool]$ShowRepairProgress
    }
    [void]$script:BackgroundTasks.Add($task)
    Write-AppLog -Message "Hintergrundaufgabe gestartet: $Name"

    if (-not $script:BackgroundTimer) {
        $script:BackgroundTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:BackgroundTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:BackgroundTimer.Add_Tick({ Complete-BackgroundTask })
    }
    $script:BackgroundTimer.Start()
}

# Übernimmt die Meldungen eines Hintergrund-Runspaces in Statuszeile, Fortschrittsanzeige und Logdatei (GUI-Thread)
function Receive-BackgroundMessage {
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$Task
    )
    $message = $null
    while ($Task.Messages.TryDequeue([ref]$message)) {
        if ($message.Kind -eq 'Log') {
            Write-AppLog -Message $message.Text -Level $message.Level
            continue
        }
        Write-StatusText -Text $message.Text -Color $message.Color
        if ($Task.ShowRepairProgress) {
            $txtRepairProgress = $window.FindName("txtRepairProgress")
            if ($txtRepairProgress) { $txtRepairProgress.Text = "$($Task.Name): $($message.Text)" }
        }
    }
}

# Wird vom DispatcherTimer im GUI-Thread aufgerufen: Meldungen übernehmen, fertige Aufgaben abschließen
function Complete-BackgroundTask {
    foreach ($task in @($script:BackgroundTasks)) {
        # Status vor dem Abholen der Meldungen merken, damit bei fertigen Aufgaben keine Meldung verloren geht
        $isCompleted = $task.Handle.IsCompleted
        Receive-BackgroundMessage -Task $task
        if (-not $isCompleted) { continue }
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
                Write-StatusText -Text "Fehler bei der Verarbeitung von '$($task.Name)': $_" -Color "Red"
            }
        }
    }
    if ($script:BackgroundTasks.Count -eq 0 -and $script:BackgroundTimer) {
        $script:BackgroundTimer.Stop()
    }
}

# Führt eine im Skript definierte Funktion (inkl. der benötigten Hilfsfunktionen) im Hintergrund aus.
# Runspaces kennen die Skriptfunktionen nicht – deshalb werden die Funktionsdefinitionen mitgegeben.
# Write-StatusText und Write-AppLog werden dort durch Varianten ersetzt, die ihre Meldungen über
# $BackgroundMessages an den GUI-Thread übergeben.
function Start-FunctionInBackground {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FunctionName,
        [hashtable]$FunctionParameters = @{},
        [string[]]$HelperFunctions = @(),
        [scriptblock]$OnCompleted,
        [string]$Name = $FunctionName,
        [switch]$ShowRepairProgress
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Im Hintergrund ausführen')) {
        if ($OnCompleted) { & $OnCompleted @() 'Ausführung übersprungen.' }
        return
    }

    $helperText = foreach ($helper in $HelperFunctions) {
        "function $helper {`n$((Get-Command -Name $helper -CommandType Function -ErrorAction Stop).ScriptBlock.ToString())`n}`n"
    }
    $functionBody = (Get-Command -Name $FunctionName -CommandType Function -ErrorAction Stop).ScriptBlock.ToString()
    $scriptText = @"
param([hashtable]`$FunctionParameters)
function Write-StatusText { param([string]`$Text, [string]`$Color = 'Black') `$BackgroundMessages.Enqueue([pscustomobject]@{ Kind = 'Status'; Text = `$Text; Color = `$Color }) }
function Write-AppLog { param([string]`$Message, [string]`$Level = 'INFO') `$BackgroundMessages.Enqueue([pscustomobject]@{ Kind = 'Log'; Text = `$Message; Level = `$Level }) }
$($helperText -join "`n")
function $FunctionName {
$functionBody
}
$FunctionName @FunctionParameters
"@
    Start-BackgroundTask -Name $Name -ScriptBlock ([scriptblock]::Create($scriptText)) -Parameters @{ FunctionParameters = $FunctionParameters } -OnCompleted $OnCompleted -ShowRepairProgress:$ShowRepairProgress
}

# Öffnet ein Konsolenfenster für lang laufende Kommandozeilen-Tools (DISM, SFC, CHKDSK),
# damit die GUI bedienbar bleibt und der Fortschritt sichtbar ist.
function Start-ConsoleTool {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CommandLine,
        [string]$Title = 'easyWINUpdate'
    )
    if (-not $PSCmdlet.ShouldProcess($CommandLine, 'In eigenem Konsolenfenster starten')) { return }
    $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    Start-Process -FilePath $cmdExe -ArgumentList "/k title $Title & $CommandLine" -ErrorAction Stop | Out-Null
    Write-AppLog -Message "Konsolen-Tool gestartet: $CommandLine"
}
#endregion

#region Reparatur- und Fehlerbehebungsaktionen (Hintergrund, gegenseitig gesperrt)
# Schaltflächen, die während einer laufenden Reparatur gesperrt werden: alle Aktionen, die Dienste,
# Registry-Werte oder Update-Ordner verändern, dürfen nicht gleichzeitig laufen.
$script:RepairButtonNames = @(
    'btnCreateRestorePoint', 'btnResetComponents', 'btnCheckSystemFiles', 'btnClearUpdateHistory',
    'btnRegisterDLLs', 'btnClearStuckUpdates', 'btnCleanTemp', 'btnResetWinsock', 'btnCheckDisk',
    'btnDiagnoseError', 'btnRepairBITS', 'btnWaaSMedic', 'btnAnalyzeLogs', 'btnRepairRegistry',
    'btnRepairDatabase', 'btnToggleDebug', 'btnAutoFix',
    'btnResetWSUS', 'btnApplyManualWSUS', 'btnApplyGPOSettings', 'btnSaveWSUSSyncSettings'
)
$script:ActiveRepair = $null
$script:UpdateBeingRemoved = $null
$script:RepairCompletedHandler = $null
$script:RepairContext = $null

# Sperrt die Reparatur-Schaltflächen und blendet die Fortschrittsanzeige ein
function Lock-RepairControl {
    param (
        [string]$Text
    )
    foreach ($buttonName in $script:RepairButtonNames) {
        $button = $window.FindName($buttonName)
        if ($button) { $button.IsEnabled = $false }
    }
    $pnlRepairProgress = $window.FindName("pnlRepairProgress")
    if ($pnlRepairProgress) { $pnlRepairProgress.Visibility = "Visible" }
    $txtRepairProgress = $window.FindName("txtRepairProgress")
    if ($txtRepairProgress) { $txtRepairProgress.Text = $Text }
    $progressBackground = $window.FindName("progressBackground")
    if ($progressBackground) { $progressBackground.Visibility = "Visible" }
}

# Gibt die Reparatur-Schaltflächen wieder frei und blendet die Fortschrittsanzeige aus
function Unlock-RepairControl {
    foreach ($buttonName in $script:RepairButtonNames) {
        $button = $window.FindName($buttonName)
        if ($button) { $button.IsEnabled = $true }
    }
    $pnlRepairProgress = $window.FindName("pnlRepairProgress")
    if ($pnlRepairProgress) { $pnlRepairProgress.Visibility = "Collapsed" }
    $progressBackground = $window.FindName("progressBackground")
    if ($progressBackground) { $progressBackground.Visibility = "Collapsed" }
}

# Führt eine Reparatur-/Fehlerbehebungsfunktion im Hintergrund aus. Es läuft immer nur eine solche Aktion;
# während der Ausführung sind die Reparatur-Schaltflächen gesperrt. -OnCompleted erhält ($Output, $ErrorText, $Context)
# im GUI-Thread. Ohne -OnCompleted wird bei einem Fehler ($ErrorText) eine Fehlermeldung angezeigt.
function Invoke-RepairAction {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$FunctionName,
        [hashtable]$FunctionParameters = @{},
        [string[]]$HelperFunctions = @(),
        [scriptblock]$OnCompleted,
        [object]$Context
    )

    if ($script:ActiveRepair) {
        Write-StatusText -Text "Bitte warten: '$($script:ActiveRepair)' läuft noch." -Color "Yellow"
        return
    }
    if ($script:UpdateInstallationRunning -or $script:AvailableUpdatesSearchRunning -or $script:UpdateBeingRemoved) {
        Write-StatusText -Text "Bitte warten, bis die laufende Update-Suche, -Installation bzw. -Deinstallation abgeschlossen ist." -Color "Yellow"
        return
    }

    $script:ActiveRepair = $Name
    $script:RepairCompletedHandler = $OnCompleted
    $script:RepairContext = $Context
    Lock-RepairControl -Text "$Name wird ausgeführt..."
    Write-StatusText -Text "$Name wird ausgeführt..." -Color "Blue"

    try {
        Start-FunctionInBackground -Name $Name -FunctionName $FunctionName -FunctionParameters $FunctionParameters `
            -HelperFunctions $HelperFunctions -ShowRepairProgress -OnCompleted {
            param($Output, $ErrorText)
            Complete-RepairAction -Output $Output -ErrorText $ErrorText
        }
    } catch {
        Complete-RepairAction -Output @() -ErrorText $_.Exception.Message
    }
}

# Abschluss einer Reparatur im GUI-Thread: Sperre aufheben, Ergebnis auswerten
function Complete-RepairAction {
    param (
        [object[]]$Output = @(),
        [string]$ErrorText
    )
    $name = $script:ActiveRepair
    $handler = $script:RepairCompletedHandler
    $context = $script:RepairContext
    $script:ActiveRepair = $null
    $script:RepairCompletedHandler = $null
    $script:RepairContext = $null
    Unlock-RepairControl

    if ($handler) {
        & $handler $Output $ErrorText $context
    } elseif (-not [bool](@($Output) | Select-Object -Last 1) -and $ErrorText) {
        Write-StatusText -Text "'$name' ist fehlgeschlagen: $ErrorText" -Color "Red"
    }
}
#endregion

# Startet die Update-Erkennung (Windows 10/11/Server 2016+: UsoClient, ältere Systeme: wuauclt)
function Start-UpdateDetection {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [switch]$ResetAuthorization
    )
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Update-Erkennung starten')) { return }
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
            "Bitte geben Sie einen WSUS-Server an.",
            "Fehlende Eingabe",
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
        "Möchten Sie die angegebene WSUS-Konfiguration übernehmen? Die Änderung kann Gruppenrichtlinieneinstellungen überschreiben; der Windows Update-Dienst wird neu gestartet.",
        "WSUS-Konfiguration übernehmen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        # WSUS-Konfiguration im Hintergrund anwenden (Neustart des Windows Update-Dienstes kann dauern)
        Invoke-RepairAction -Name 'WSUS-Konfiguration übernehmen' -FunctionName 'Set-ManualWSUSConfiguration' -FunctionParameters @{
            WSUSServer  = $wsusServer
            WSUSPort    = $wsusPort
            UseSSL      = $useSSL
            TargetGroup = $targetGroup
        } -OnCompleted {
            param($Output, $ErrorText)
            if ([bool](@($Output) | Select-Object -Last 1)) {
                Write-StatusText -Text "WSUS-Konfiguration wurde erfolgreich übernommen." -Color "Green"
                Show-WSUSSettingsPage
            } else {
                Write-StatusText -Text "WSUS-Konfiguration konnte nicht übernommen werden. $ErrorText" -Color "Red"
            }
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
    Write-StatusText -Text "Lade WSUS-Zielgruppen..." -Color "Blue"

    try {
        $targetGroups = Get-WSUSTargetGroup -WSUSServer $wsusServer -WSUSPort $wsusPort -UseSSL $useSSL

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

            Write-StatusText -Text "$($targetGroups.Count) WSUS-Zielgruppen geladen." -Color "Green"
        } else {
            Write-StatusText -Text "Keine WSUS-Zielgruppen gefunden." -Color "Yellow"

            # Standard-Eintrag hinzufügen
            $cmbManualWSUSTargetGroup.Items.Clear()
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = "Standard"
            $cmbManualWSUSTargetGroup.Items.Add($item)
            $cmbManualWSUSTargetGroup.SelectedIndex = 0
        }
    } catch {
        Write-StatusText -Text "WSUS-Zielgruppen konnten nicht geladen werden: $_" -Color "Red"
    }
})

# Status initialisieren
$statusText = $window.FindName("statusText")
$statusText.Text = "Bereit"

# Funktion zur Diagnose von Windows Update-Fehlercodes (läuft im Hintergrund; die Fehlercode-Tabelle
# wird als Parameter übergeben, da der Runspace die Skriptvariablen nicht kennt)
function Get-WindowsUpdateErrorDiagnosis {
    param (
        [string]$ErrorCode = "",
        [hashtable]$ErrorCodeTable = @{}
    )

    try {
        Write-StatusText -Text "Analysiere Windows Update-Fehler..." -Color "Blue"

        # Wenn kein Fehlercode übergeben wurde, versuche den letzten Fehlercode aus dem Ereignisprotokoll zu holen
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

        # Übergebene Fehlercode-Tabelle verwenden
        # Wenn ein bekannter Fehlercode gefunden wurde
        if ($ErrorCode -and $ErrorCodeTable.ContainsKey($ErrorCode)) {
            $errorInfo = $ErrorCodeTable[$ErrorCode]

            # Erstelle die Ausgabe
            $output = "Windows Update-Fehlercode: $ErrorCode`r`n"
            $output += "Beschreibung: $($errorInfo.Description)`r`n"
            $output += "Empfohlene Lösungen:`r`n"

            foreach ($solution in $errorInfo.Solutions) {
                $output += "- $solution`r`n"
            }

            Write-StatusText -Text "Fehlercode-Analyse abgeschlossen." -Color "Green"
            return $output
        }
        elseif ([string]::IsNullOrEmpty($ErrorCode)) {
            Write-StatusText -Text "Kein Windows Update-Fehlercode gefunden." -Color "Yellow"
            return "Kein Windows Update-Fehlercode gefunden."
        }
        else {
            Write-StatusText -Text "Unbekannter Fehlercode: $ErrorCode" -Color "Yellow"
            return "Unbekannter Windows Update-Fehlercode: $ErrorCode"
        }
    }
    catch {
        Write-StatusText -Text "Fehler bei der Analyse des Windows Update-Fehlers: $_" -Color "Red"
        return "Fehler bei der Analyse des Windows Update-Fehlers: $_"
    }
}

# Funktion für eine erweiterte BITS-Reparatur
function Repair-BITSService {
    try {
        Write-StatusText -Text "Führe erweiterte BITS-Reparatur durch..." -Color "Blue"

        # BITS-Warteschlange löschen (muss vor dem Stoppen des Dienstes erfolgen)
        Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue

        # BITS-Dienst stoppen
        Write-StatusText -Text "Stoppe BITS-Dienst und bereinige die BITS-Warteschlange..." -Color "Blue"
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
        Write-StatusText -Text "Starte BITS-Dienst..." -Color "Blue"
        Start-Service -Name BITS

        Write-StatusText -Text "BITS-Dienst wurde erfolgreich repariert." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler bei der Reparatur des BITS-Dienstes: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Prüfen und Reparieren des WaaSMedic-Dienstes
function Repair-WaaSMedicService {
    try {
        Write-StatusText -Text "Prüfe Windows Update Medic Service..." -Color "Blue"

        # Prüfen, ob der Dienst existiert (nur auf neueren Windows-Versionen)
        $waasService = Get-Service -Name WaaSMedicSvc -ErrorAction SilentlyContinue

        if (-not $waasService) {
            Write-StatusText -Text "Windows Update Medic Service (WaaSMedicSvc) ist auf diesem System nicht verfügbar." -Color "Yellow"
            return $false
        }

        # Prüfen und korrigieren des Dienststarttyps
        if ($waasService.StartType -ne "Automatic") {
            Set-Service -Name WaaSMedicSvc -StartupType Automatic
            Write-StatusText -Text "WaaSMedicSvc-Starttyp auf Automatisch gesetzt." -Color "Blue"
        }

        # Dienst starten, falls er nicht läuft
        if ($waasService.Status -ne "Running") {
            Start-Service -Name WaaSMedicSvc
            Write-StatusText -Text "WaaSMedicSvc-Dienst gestartet." -Color "Blue"
        }

        # Überprüfen der Registry-Einstellungen
        $waasKey = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
        if (Test-Path $waasKey) {
            $startValue = (Get-ItemProperty -Path $waasKey -Name "Start").Start
            if ($startValue -ne 2) {
                Set-ItemProperty -Path $waasKey -Name "Start" -Value 2
                Write-StatusText -Text "Registry-Einstellungen von WaaSMedicSvc korrigiert." -Color "Blue"
            }
        }

        Write-StatusText -Text "Windows Update Medic Service wurde geprüft und repariert." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler beim Prüfen und Reparieren des Windows Update Medic Service: $_" -Color "Red"
        return $false
    }
}
# Funktion zur Analyse der Windows Update-Logs
function Get-WindowsUpdateLogAnalysis {
    param (
        [string]$OutputDirectory = $env:TEMP
    )
    try {
        Write-StatusText -Text "Analysiere Windows Update-Logs..." -Color "Blue"

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
            Write-StatusText -Text "Windows Update-Log nicht gefunden." -Color "Yellow"
            return "Windows Update-Log nicht gefunden."
        }

        # Größe der Logdatei prüfen
        $logFile = Get-Item $logPath
        if ($logFile.Length -gt 5MB) {
            Write-StatusText -Text "Windows Update-Log ist sehr groß ($(($logFile.Length / 1MB).ToString('0.00')) MB)." -Color "Yellow"
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
            Write-StatusText -Text "Keine offensichtlichen Fehler in den Windows Update-Logs gefunden." -Color "Green"
            return "In den letzten 1000 Logeinträgen wurden keine eindeutigen Fehler gefunden.`r`nLog: $logPath"
        } else {
            Write-StatusText -Text "In den Windows Update-Logs wurden Fehler gefunden." -Color "Yellow"

            $output = "Die letzten 20 Fehlermeldungen aus den Windows Update-Logs ($logPath):`r`n"
            foreach ($logLine in $logErrors) {
                $output += "- $logLine`r`n"
            }

            return $output
        }
    } catch {
        Write-StatusText -Text "Fehler bei der Analyse der Windows Update-Logs: $_" -Color "Red"
        return "Fehler bei der Log-Analyse: $_"
    }
}
# Funktion zur Reparatur häufiger Registry-Probleme von Windows Update
function Repair-WindowsUpdateRegistry {
    try {
        Write-StatusText -Text "Repariere Windows Update-Registry-Einstellungen..." -Color "Blue"

        # Wichtige Windows Update-Registry-Pfade
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
                Write-StatusText -Text "Registry-Pfad erstellt: $path" -Color "Blue"
            }

            # Überprüfung und Korrektur spezifischer Schlüsselwerte
            if ($path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update") {
                # AUOptions prüfen (falls auf deaktiviert) - AUOptions ist ein Registry-Wert, kein Schlüssel
                $auOptions = (Get-ItemProperty -Path $path -Name "AUOptions" -ErrorAction SilentlyContinue).AUOptions
                if ($null -ne $auOptions -and $auOptions -eq 1) {
                    Set-ItemProperty -Path $path -Name "AUOptions" -Value 3 # Auf "Herunterladen aber nicht installieren" setzen
                    Write-StatusText -Text "Automatische Updates waren deaktiviert - auf 'Herunterladen, aber nicht installieren' gesetzt." -Color "Blue"
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
                    Write-StatusText -Text "$($service.DisplayName)-Dienst auf $($service.StartupType) gesetzt." -Color "Blue"
                }
            }
        }

        # Debugging-Modus für Windows Update ausschalten (falls aktiviert)
        $wuTraceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Trace"
        if (Test-Path $wuTraceKey) {
            $flags = (Get-ItemProperty -Path $wuTraceKey -ErrorAction SilentlyContinue).Flags
            if ($flags -eq 1) {
                Set-ItemProperty -Path $wuTraceKey -Name "Flags" -Value 0
                Write-StatusText -Text "Windows Update-Debugging deaktiviert." -Color "Blue"
            }
        }

        Write-StatusText -Text "Windows Update-Registry-Einstellungen wurden repariert." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler bei der Reparatur der Registry-Einstellungen: $_" -Color "Red"
        return $false
    }
}
# Funktion zur Reparatur der Windows Update-Datenbank
function Repair-WindowsUpdateDatabase {
    try {
        Write-StatusText -Text "Repariere Windows Update-Datenbank..." -Color "Blue"

        # Windows Update-Dienste stoppen
        $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver', 'appidsvc')
        Write-StatusText -Text "Stoppe Windows Update-Dienste..." -Color "Blue"
        foreach ($service in $services) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        }

        # SoftwareDistribution-Ordner umbenennen (nicht löschen)
        Write-StatusText -Text "Sichere SoftwareDistribution und catroot2 (.bak)..." -Color "Blue"
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
        Write-StatusText -Text "Starte Windows Update-Dienste..." -Color "Blue"
        foreach ($service in $services) {
            Start-Service -Name $service -ErrorAction SilentlyContinue
        }

        # Update-Erkennung erzwingen
        Start-UpdateDetection -ResetAuthorization

        Write-StatusText -Text "Windows Update-Datenbank wurde repariert. Das System sollte neu gestartet werden." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler bei der Reparatur der Windows Update-Datenbank: $_" -Color "Red"
        return $false
    }
}
# Funktion zum Aktivieren/Deaktivieren des Fehlersuchmodus für Windows Update
function Set-WindowsUpdateDebugMode {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [bool]$Enable = $true
    )

    if (-not $PSCmdlet.ShouldProcess('Windows Update-Fehlersuchmodus', $(if ($Enable) { 'Aktivieren' } else { 'Deaktivieren' }))) {
        return $false
    }
    try {
        if ($Enable) {
            Write-StatusText -Text "Aktiviere den Windows Update-Fehlersuchmodus..." -Color "Blue"

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

            Write-StatusText -Text "Der Windows Update-Fehlersuchmodus wurde aktiviert. Wiederholen Sie den Update-Vorgang und prüfen Sie die Logs." -Color "Green"
            return $true
        } else {
            Write-StatusText -Text "Deaktiviere den Windows Update-Fehlersuchmodus..." -Color "Blue"

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

            Write-StatusText -Text "Der Windows Update-Fehlersuchmodus wurde deaktiviert." -Color "Green"
            return $true
        }
    } catch {
        Write-StatusText -Text "Fehler beim Umschalten des Windows Update-Fehlersuchmodus: $_" -Color "Red"
        return $false
    }
}


# Funktion zum Abrufen der WSUS-Einstellungen
function Get-WSUSSetting {
    $wsusSettings = @{
        Server = $null
        Status = "Nicht konfiguriert"
        TargetGroup = "Keine"
        ConfigSource = "Nicht konfiguriert"
        LastCheck = "Unbekannt"
    }

    $wuPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
    $wuSettings = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -ErrorAction SilentlyContinue

    if ($wuPolicies) {
        $wsusSettings.Server = $wuPolicies.WUServer
        $wsusSettings.Status = if ($wsusSettings.Server) { "Aktiv" } else { "Nicht konfiguriert" }
        $wsusSettings.TargetGroup = if ($wuPolicies.TargetGroupEnabled -eq 1) { $wuPolicies.TargetGroup } else { "Keine" }

        if ($wsusSettings.Server) {
            if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate") {
                $wsusSettings.ConfigSource = "Gruppenrichtlinie"
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
            $wsusSettings.LastCheck = "Fehler beim Umwandeln des Datums"
        }
    }

    return $wsusSettings
}
# Funktion zur automatischen Analyse und Behebung von Windows Update-Problemen (Auto-Fix).
# Läuft im Hintergrund; alle aufgerufenen Reparaturfunktionen werden als Hilfsfunktionen mitgegeben.
function Repair-WindowsUpdateIssue {
    try {
        Write-StatusText -Text "Starte automatische Behebung von Windows Update-Problemen..." -Color "Blue"

        # Schritt 1: Windows Update-Dienst prüfen
        Write-StatusText -Text "Schritt 1/6: Prüfe den Windows Update-Dienst..." -Color "Blue"
        $wuauserv = Get-Service -Name wuauserv
        if ($wuauserv.Status -ne "Running" -or $wuauserv.StartType -ne "Automatic") {
            Write-StatusText -Text "Der Windows Update-Dienst ist nicht korrekt konfiguriert. Wird korrigiert..." -Color "Yellow"
            Set-Service -Name wuauserv -StartupType Automatic
            Start-Service -Name wuauserv
        }

        # Schritt 2: Vorhandene Fehler analysieren
        Write-StatusText -Text "Schritt 2/6: Analysiere die letzten Windows Update-Fehler..." -Color "Blue"
        $lastError = Get-WinEvent -LogName "Microsoft-Windows-WindowsUpdateClient/Operational" -MaxEvents 50 -ErrorAction SilentlyContinue |
            Where-Object { $_.Level -eq 2 -or $_.Message -like "*0x8*" } |
            Select-Object -First 1

        $errorCode = ""
        if ($lastError) {
            $codeMatches = [regex]::Matches($lastError.Message, "0x8[0-9A-Fa-f]{7}")
            if ($codeMatches.Count -gt 0) {
                $errorCode = $codeMatches[0].Value
                Write-StatusText -Text "Letzter Windows Update-Fehlercode: $errorCode" -Color "Yellow"
            }
        }

        # Schritt 3: Gezielte Fehlerbehebung anhand des Fehlercodes
        Write-StatusText -Text "Schritt 3/6: Gezielte Fehlerbehebung..." -Color "Blue"
        $specificFix = $false

        switch ($errorCode) {
            "0x80240034" { # Downloadfehler
                Write-StatusText -Text "Downloadfehler erkannt. Behebe Netzwerk- und Cacheprobleme..." -Color "Yellow"
                Clear-WindowsUpdateHistory
                Repair-BITSService
                $specificFix = $true
            }
            "0x8024001F" { # Keine Verbindung
                Write-StatusText -Text "Verbindungsproblem erkannt. Prüfe Netzwerkeinstellungen..." -Color "Yellow"
                Repair-BITSService
                Reset-WindowsUpdateComponent
                $specificFix = $true
            }
            "0x80070020" { # Datei gesperrt
                Write-StatusText -Text "Gesperrte Datei erkannt. Bereinige die Windows Update-Datenbank..." -Color "Yellow"
                Repair-WindowsUpdateDatabase
                $specificFix = $true
            }
            "0x80240022" { # Alle Updates fehlgeschlagen
                Write-StatusText -Text "Kritisches Update-Problem erkannt. Führe vollständige Reparatur durch..." -Color "Yellow"
                Reset-WindowsUpdateComponent
                Repair-WindowsSystemFile
                $specificFix = $true
            }
            "0x80070422" { # Dienst deaktiviert
                Write-StatusText -Text "Windows Update-Dienst deaktiviert. Aktiviere die Dienste..." -Color "Yellow"
                Repair-WindowsUpdateRegistry
                $specificFix = $true
            }
            "0x8024402C" { # DNS-Auflösungsproblem
                Write-StatusText -Text "DNS-Problem erkannt. Setze Netzwerkeinstellungen zurück..." -Color "Yellow"
                # Netzwerkeinstellungen zurücksetzen
                ipconfig.exe /flushdns | Out-Null
                ipconfig.exe /registerdns | Out-Null
                $specificFix = $true
            }
        }

        # Schritt 4: Allgemeine Reparatur, falls keine gezielte Behebung erfolgt ist
        if (-not $specificFix) {
            Write-StatusText -Text "Schritt 4/6: Führe allgemeine Reparaturmaßnahmen durch..." -Color "Blue"

            # Windows Update-Komponenten zurücksetzen
            Reset-WindowsUpdateComponent

            # WaaSMedic-Dienst reparieren (auf neueren Windows-Versionen)
            $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
            $osVersion = [Version]$osInfo.Version
            if ($osVersion -ge [Version]"10.0.17134") {
                Repair-WaaSMedicService
            }

            # Registry-Einstellungen reparieren
            Repair-WindowsUpdateRegistry
        }

        # Schritt 5: Update-Dienste neu starten
        Write-StatusText -Text "Schritt 5/6: Starte die Windows Update-Dienste neu..." -Color "Blue"
        Restart-Service -Name wuauserv -Force
        Restart-Service -Name bits -Force

        # Schritt 6: Update-Erkennung erzwingen
        Write-StatusText -Text "Schritt 6/6: Erzwinge die Update-Erkennung..." -Color "Blue"
        Start-UpdateDetection -ResetAuthorization

        Write-StatusText -Text "Automatische Fehlerbehebung abgeschlossen. Ein Neustart des Computers wird empfohlen." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler bei der automatischen Fehlerbehebung: $_" -Color "Red"
        return $false
    }
}
# Funktion zum Zurücksetzen der WSUS-Einstellungen
function Reset-WSUSSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param ()
    if (-not $PSCmdlet.ShouldProcess('WSUS-Einstellungen', 'Zurücksetzen')) { return $false }
    try {
        Write-StatusText -Text "Entferne WSUS-Richtlinienwerte..." -Color "Blue"
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
        Write-StatusText -Text "Setze die WSUS-Client-ID zurück und starte die Dienste neu..." -Color "Blue"
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

# Funktion zum Abrufen installierter Updates
function Get-InstalledWindowsUpdate {
    try {
        $hotfixes = Get-HotFix | Select-Object @{Name="HotFixID"; Expression={$_.HotFixID}},
                                                @{Name="Description"; Expression={$_.Description}},
                                                @{Name="InstalledOn"; Expression={if($_.InstalledOn){$_.InstalledOn.ToString("dd.MM.yyyy")}else{"Unbekannt"}}}

        return $hotfixes
    } catch {
        Write-Error "Fehler beim Abrufen der installierten Updates: $_"
        return $null
    }
}

# Funktion zum Abrufen verfügbarer Updates (Windows Update Agent COM-API, Standard-Updatequelle inkl. WSUS)
function Get-AvailableWindowsUpdate {
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
        # Anzeigenamen der (englischen) Windows Update-Kategorien
        $categoryDisplayNames = @{
            "Andere"             = "Andere"
            "Critical Updates"   = "Kritische Updates"
            "Security Updates"   = "Sicherheitsupdates"
            "Definition Updates" = "Definitionsupdates"
            "Feature Packs"      = "Funktionsupdates"
        }

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
                    Category = $categoryDisplayNames[$category]
                    Size = if ($update.MaxDownloadSize -gt 0) { "$([Math]::Round($update.MaxDownloadSize / 1MB, 2)) MB" } else { "Unbekannt" }
                    Identity = [string]$update.Identity.UpdateID
                }
            }
        }

        return $updates
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Error "Fehler beim Abrufen der verfügbaren Updates: $errorMessage"
        return $null
    }
}

# Funktion zum Entfernen eines Windows Updates
function Remove-WindowsUpdateKB {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$KBNumber
    )

    try {
        $kbID = ($KBNumber.Trim() -replace '^(?i)KB', '')
        if ($kbID -notmatch '^\d{4,8}$') {
            throw "Ungültige KB-Nummer: '$KBNumber'"
        }
        $KBNumber = "KB$kbID"
        if (-not $PSCmdlet.ShouldProcess($KBNumber, 'Update deinstallieren')) { return $false }

        $wusaPath = Join-Path $env:SystemRoot 'System32\wusa.exe'
        $process = Start-Process -FilePath $wusaPath -ArgumentList "/uninstall", "/kb:$kbID", "/quiet", "/norestart" -Wait -PassThru -ErrorAction Stop

        # 0 = Erfolg, 3010 = Erfolg, Neustart erforderlich
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "wusa.exe beendet mit ExitCode $($process.ExitCode) (2359303 = Update nicht installiert / nicht deinstallierbar)"
        }

        return $true
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Error ("Fehler beim Entfernen des Windows Updates " + $KBNumber + ": " + $errorMessage)
        return $false
    }
}

# Funktion zum Testen der WSUS-Verbindung (TCP-Verbindung zum WSUS-Port statt ICMP-Ping)
function Test-WSUSConnection {
    param (
        [string]$WSUSServer,
        [int]$TimeoutMilliseconds = 3000
    )

    try {
        if (-not $WSUSServer -or $WSUSServer -eq "Nicht konfiguriert") {
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
function Get-WSUSTargetGroup {
    param (
        [string]$WSUSServer,
        [int]$WSUSPort = 8530,
        [bool]$UseSSL = $false
    )

    try {
        # Die echte WSUS-API erfordert die WSUS-Verwaltungskonsole auf dem Client. Daher wird eine Liste
        # typischer Zielgruppen geliefert (Gruppennamen = WSUS-Bezeichner, müssen auf dem Server existieren).
        if ($WSUSServer) {
            $protocol = if ($UseSSL) { "https" } else { "http" }
            Write-Verbose "Typische Zielgruppen für ${protocol}://${WSUSServer}:${WSUSPort} (keine Abfrage der WSUS-API)"
        }
        $targetGroups = @(
            [PSCustomObject]@{
                Name = "Unassigned Computers"
                Description = "Computer ohne Gruppenzuordnung"
                ComputerCount = "k. A."
            },
            [PSCustomObject]@{
                Name = "Standard"
                Description = "Standardgruppe für alle Computer"
                ComputerCount = "k. A."
            },
            [PSCustomObject]@{
                Name = "Testgroup"
                Description = "Testgruppe für Vorabversionen von Updates"
                ComputerCount = "k. A."
            },
            [PSCustomObject]@{
                Name = "Workstations"
                Description = "Alle Arbeitsstationen"
                ComputerCount = "k. A."
            },
            [PSCustomObject]@{
                Name = "Server"
                Description = "Alle Server"
                ComputerCount = "k. A."
            }
        )
        return $targetGroups
    } catch {
        Write-Error "Fehler beim Abrufen der WSUS-Zielgruppen: $_"
        return @()
    }
}

# Funktion zum Abrufen der Windows Update-Gruppenrichtlinieneinstellungen
function Get-WindowsUpdateGPOSetting {
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
        Write-Error "Fehler beim Abrufen der Windows Update-Gruppenrichtlinieneinstellungen: $_"
        return $null
    }
}

# Funktion zum Setzen der Windows Update Gruppenrichtlinieneinstellungen
function Set-WindowsUpdateGPOSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [bool]$AutoUpdateEnabled,
        [int]$ConfigType,
        [int]$InstallTime,
        [bool]$ShowNotifications,
        [int]$RebootBehavior
    )

    if (-not $PSCmdlet.ShouldProcess('Windows Update-Richtlinien (HKLM)', 'Einstellungen schreiben')) { return $false }
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
        Write-StatusText -Text "Starte den Windows Update-Dienst neu..." -Color "Blue"
        Restart-Service -Name wuauserv -Force

        return $true
    } catch {
        Write-Error "Fehler beim Setzen der Windows Update-Gruppenrichtlinieneinstellungen: $_"
        return $false
    }
}

# Funktion zum Setzen der manuellen WSUS-Konfiguration
function Set-ManualWSUSConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$WSUSServer,
        [int]$WSUSPort,
        [bool]$UseSSL,
        [string]$TargetGroup
    )

    if (-not $PSCmdlet.ShouldProcess($WSUSServer, 'WSUS-Server konfigurieren')) { return $false }
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
        Write-StatusText -Text "Starte den Windows Update-Dienst neu..." -Color "Blue"
        Restart-Service -Name wuauserv -Force

        return $true
    } catch {
        Write-Error "Fehler beim Setzen der manuellen WSUS-Konfiguration: $_"
        return $false
    }
}

# Funktion zum Verwalten der WSUS-Synchronisierung
function Start-WSUSSynchronization {
    [CmdletBinding(SupportsShouldProcess)]
    param ()
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'WSUS-Synchronisierung starten')) { return $false }
    try {
        # WSUS-Synchronisierung starten (Client-seitig: Update-Erkennung gegen die konfigurierte Quelle)
        Write-StatusText -Text "Starte WSUS-Synchronisierung..." -Color "Blue"
        Start-UpdateDetection
        Write-StatusText -Text "WSUS-Synchronisierung (Update-Erkennung) wurde gestartet." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler beim Starten der WSUS-Synchronisierung: $_" -Color "Red"
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
                Status  = if ($wuEvent.Id -eq 26) { "Erfolgreich" } else { "Fehler" }
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
        Write-Error "Fehler beim Abrufen des WSUS-Synchronisierungsverlaufs: $_"
        return @()
    }
}

# Funktion zum Setzen der WSUS-Synchronisierungseinstellungen
function Set-WSUSSyncSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$SyncInterval,
        [bool]$AutoSync
    )

    if (-not $PSCmdlet.ShouldProcess('Windows Update-Richtlinien (HKLM)', 'Synchronisierungseinstellungen schreiben')) { return $false }
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
        Write-StatusText -Text "Starte den Windows Update-Dienst neu..." -Color "Blue"
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
    [CmdletBinding(SupportsShouldProcess)]
    param ()
    if (-not $PSCmdlet.ShouldProcess($env:SystemDrive, 'Systemwiederherstellungspunkt erstellen')) { return $false }
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
function Reset-WindowsUpdateComponent {
    [CmdletBinding(SupportsShouldProcess)]
    param ()
    if (-not $PSCmdlet.ShouldProcess('Windows Update-Komponenten', 'Zurücksetzen')) { return $false }
    try {
        Write-StatusText -Text "Setze Windows Update-Komponenten zurück..." -Color "Blue"

        # Dienste stoppen
        $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver', 'appidsvc', 'trustedinstaller')

        # Alle BITS-Jobs löschen (solange der BITS-Dienst noch läuft)
        Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue

        Write-StatusText -Text "Stoppe Windows Update-Dienste..." -Color "Blue"
        foreach ($service in $services) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        }

        # Windows Update-Datenbank und Cache-Ordner löschen
        Write-StatusText -Text "Lösche SoftwareDistribution und catroot2..." -Color "Blue"
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
        Write-StatusText -Text "Starte Windows Update-Dienste..." -Color "Blue"
        foreach ($service in $services) {
            Start-Service -Name $service -ErrorAction SilentlyContinue
        }

        # Update-Erkennung erzwingen
        Start-UpdateDetection -ResetAuthorization

        Write-StatusText -Text "Windows Update-Komponenten wurden zurückgesetzt. System sollte neu gestartet werden." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler beim Zurücksetzen der Windows Update-Komponenten: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Überprüfen und Reparieren von Windows-Systemdateien
function Repair-WindowsSystemFile {
    try {
        Write-StatusText -Text "Überprüfe Windows-Systemdateien..." -Color "Blue"

        # DISM und SFC in einem eigenen Konsolenfenster ausführen (kann 30+ Minuten dauern, GUI bleibt bedienbar)
        Start-ConsoleTool -Title 'easyWINUpdate - DISM und SFC' -CommandLine 'DISM.exe /Online /Cleanup-Image /RestoreHealth & sfc.exe /scannow'

        Write-StatusText -Text "DISM /RestoreHealth und SFC /scannow wurden in einem separaten Konsolenfenster gestartet." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler bei der Überprüfung der Windows-Systemdateien: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Löschen des Windows Update-Verlaufs
function Clear-WindowsUpdateHistory {
    try {
        Write-StatusText -Text "Lösche Windows Update-Verlauf..." -Color "Blue"

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

        Write-StatusText -Text "Windows Update-Verlauf wurde gelöscht." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler beim Löschen des Windows Update-Verlaufs: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Neuregistrieren der Windows Update-DLLs
function Register-WindowsUpdateDLL {
    try {
        Write-StatusText -Text "Registriere Windows Update-DLLs neu..." -Color "Blue"

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

        $dllIndex = 0
        foreach ($dll in $dllFiles) {
            $dllIndex++
            $dllPath = Join-Path $env:SystemRoot "System32\$dll"
            if (Test-Path $dllPath) {
                Write-StatusText -Text "Registriere $dll ($dllIndex/$($dllFiles.Count))..." -Color "Blue"
                Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s", $dllPath -Wait
            }
        }

        # Windows Update-Dienst neu starten
        Start-Service -Name wuauserv

        Write-StatusText -Text "Windows Update-DLLs wurden neu registriert." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler beim Neuregistrieren der Windows Update-DLLs: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Entfernen von hängenden Updates und BITS-Jobs
function Clear-StuckUpdateAndBITSJob {
    try {
        Write-StatusText -Text "Entferne hängende Updates und BITS-Jobs..." -Color "Blue"

        # Alle BITS-Jobs löschen
        Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue

        # Gestagte Windows Update-Pakete entfernen
        Write-StatusText -Text "Suche bereitgestellte (Staged) Update-Pakete..." -Color "Blue"
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

        Write-StatusText -Text "Hängende Updates und BITS-Jobs wurden entfernt." -Color "Green"
        return $true
    } catch {
        Write-StatusText -Text "Fehler beim Entfernen von hängenden Updates: $_" -Color "Red"
        return $false
    }
}

# Funktion zum Bereinigen der temporären Dateien (Benutzer-TEMP und %SystemRoot%\Temp); liefert die Anzahl entfernter Einträge
function Clear-TemporaryFile {
    [OutputType([int])]
    param ()
    $tempFolders = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    $removedCount = 0
    foreach ($tempFolder in $tempFolders) {
        Write-StatusText -Text "Bereinige $tempFolder..." -Color "Blue"
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
    return $removedCount
}

# Funktion zum Zurücksetzen des Winsock-Katalogs (netsh winsock reset); liefert Erfolg und Ausgabe
function Reset-WinsockCatalog {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param ()
    if (-not $PSCmdlet.ShouldProcess('Winsock-Katalog', 'Zurücksetzen')) {
        return [pscustomobject]@{ Success = $false; Output = 'Übersprungen.' }
    }
    $netshOutput = & (Join-Path $env:SystemRoot 'System32\netsh.exe') winsock reset 2>&1
    $success = ($LASTEXITCODE -eq 0)
    if ($success) {
        Write-AppLog -Message "Winsock zurückgesetzt"
    }
    return [pscustomobject]@{ Success = $success; Output = ($netshOutput -join ' ') }
}
#endregion

#region Event-Handler und GUI-Logik

# Hauptfunktion zum Laden der Update-Status-Seite
function Show-UpdateStatusPage {
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
                Write-AppLog -Message "Fehler beim Ermitteln der Windows-Version: $_" -Level 'WARN'
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
                Write-AppLog -Message "Fehler beim Ermitteln der Update-Quelle: $_" -Level 'WARN'
            }
        }

        # Installierte Updates nur einmal abfragen (Get-HotFix/WMI ist langsam)
        $installedHotfixes = @()
        $hotfixError = $null
        try {
            $installedHotfixes = @(Get-HotFix -ErrorAction Stop)
        } catch {
            $hotfixError = $_
            Write-AppLog -Message "Fehler beim Abrufen der installierten Updates: $_" -Level 'WARN'
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
                    $txtUpdateStatus.Text = "Bereit"
                }
            } catch {
                $txtUpdateStatus.Text = "Unbekannt"
                Write-AppLog -Message "Fehler beim Ermitteln des Update-Status: $_" -Level 'WARN'
            }
        }

        # Anzahl installierter Updates ermitteln
        $txtInstalledUpdatesCount = $window.FindName("txtInstalledUpdatesCount")
        if ($txtInstalledUpdatesCount) {
            if ($hotfixError) {
                $txtInstalledUpdatesCount.Text = "Fehler beim Abrufen der Update-Informationen"
            } else {
                $txtInstalledUpdatesCount.Text = "$($installedHotfixes.Count) Updates installiert"
            }
        }

        # Status-Anzeige aktualisieren
        Write-StatusText -Text "System bereit" -Color "Green"

    } catch {
        Write-AppLog -Message "Fehler beim Laden der Update-Status-Seite: $_" -Level 'ERROR'
        Write-StatusText -Text "Fehler beim Laden der Statusinformationen" -Color "Red"
    }
}

# Funktion zum Laden der Seite "Installierte Updates"
function Show-InstalledUpdatesPage {
    $dgInstalledUpdates = $window.FindName("dgInstalledUpdates")
    $progressUpdates = $window.FindName("progressInstalledUpdates")
    $progressUpdates.Visibility = "Visible"
    $dgInstalledUpdates.ItemsSource = $null

    # Temporäre Anzeige während des Ladens
    Write-StatusText -Text "Lade installierte Updates..." -Color "Blue"

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
            Write-StatusText -Text "$($hotfixes.Count) installierte Updates geladen." -Color "Green"
        } elseif ($ErrorText) {
            Write-StatusText -Text "Fehler beim Laden der installierten Updates: $ErrorText" -Color "Red"
        } else {
            Write-StatusText -Text "Keine installierten Updates gefunden." -Color "Blue"
        }
    }
}

# Funktion zum Laden der verfügbaren Updates-Seite (echte Suche über die Windows Update Agent API)
function Show-AvailableUpdatesPage {
    if ($script:AvailableUpdatesSearchRunning) {
        Write-StatusText -Text "Eine Update-Suche läuft bereits..." -Color "Yellow"
        return
    }
    if ($script:ActiveRepair) {
        # Reparaturen stoppen Dienste bzw. löschen den Update-Cache -> keine parallele Suche
        Write-StatusText -Text "Update-Suche nicht möglich, solange '$($script:ActiveRepair)' läuft. Bitte danach erneut suchen." -Color "Yellow"
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
    Write-StatusText -Text "Suche nach verfügbaren Updates (kann mehrere Minuten dauern)..." -Color "Blue"
    $script:AvailableUpdatesSearchRunning = $true

    $searchParameters = @{
        IncludeCritical   = [bool]$chkCriticalUpdates.IsChecked
        IncludeSecurity   = [bool]$chkSecurityUpdates.IsChecked
        IncludeDefinition = [bool]$chkDefinitionUpdates.IsChecked
        IncludeFeature    = [bool]$chkFeatureUpdates.IsChecked
    }

    Start-FunctionInBackground -FunctionName 'Get-AvailableWindowsUpdate' -FunctionParameters $searchParameters -OnCompleted {
        param($Output, $ErrorText)
        $script:AvailableUpdatesSearchRunning = $false
        $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
        $progressUpdates = $window.FindName("progressAvailableUpdates")
        $progressUpdates.Visibility = "Collapsed"

        $updates = @($Output | Where-Object { $_ -and $_.PSObject.Properties['Identity'] })
        $dgAvailableUpdates.ItemsSource = $updates
        if ($updates.Count -gt 0) {
            Write-StatusText -Text "$($updates.Count) verfügbare Updates gefunden." -Color "Green"
        } elseif ($ErrorText) {
            Write-StatusText -Text "Fehler bei der Update-Suche: $ErrorText" -Color "Red"
        } else {
            Write-StatusText -Text "Keine verfügbaren Updates gefunden." -Color "Blue"
        }
    }
}

# Installiert bzw. lädt Updates (PSWindowsUpdate) im Hintergrund
function Start-UpdateInstallation {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string[]]$UpdateIds = @(),
        [switch]$DownloadOnly,
        [string]$Description = "Updates"
    )

    if ($script:UpdateInstallationRunning) {
        Write-StatusText -Text "Es läuft bereits eine Installation bzw. ein Download." -Color "Yellow"
        return
    }
    if ($script:ActiveRepair) {
        Write-StatusText -Text "Installation bzw. Download nicht möglich, solange '$($script:ActiveRepair)' läuft." -Color "Yellow"
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Description, $(if ($DownloadOnly) { 'Herunterladen' } else { 'Installieren' }))) { return }
    $script:UpdateInstallationRunning = $true

    $progressUpdates = $window.FindName("progressUpdates")
    $progressUpdates.IsIndeterminate = $true
    $progressUpdates.Visibility = "Visible"
    $action = if ($DownloadOnly) { "Lade" } else { "Installiere" }
    Write-StatusText -Text "$action $Description..." -Color "Blue"

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
            Write-StatusText -Text "Fehler bei der Update-Verarbeitung: $ErrorText" -Color "Red"
        } else {
            $processed = @($Output | Where-Object { $_ })
            Write-StatusText -Text "Update-Verarbeitung abgeschlossen ($($processed.Count) Einträge). Ein Neustart kann erforderlich sein." -Color "Green"
            foreach ($entry in $processed) { Write-AppLog -Message "Update: $($entry.KB) - $($entry.Result) - $($entry.Title)" }
        }
        Show-AvailableUpdatesPage
    }
}

# Funktion zum Laden der WSUS-Einstellungen-Seite
function Show-WSUSSettingsPage {
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
            $txtWSUSServer.Text = "Nicht konfiguriert"
        }
    } catch {
        $txtWSUSServer.Text = "Fehler beim Abrufen der WSUS-Konfiguration"
    }

    # WSUS-Status ermitteln
    try {
        $useWUServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -ErrorAction SilentlyContinue
        if ($useWUServer -and $useWUServer.UseWUServer -eq 1) {
            if ($txtWSUSServer.Text -ne "Nicht konfiguriert") {
                $wsusConnection = Test-WSUSConnection -WSUSServer $txtWSUSServer.Text
                if ($wsusConnection) {
                    $txtWSUSStatus.Text = "Verbunden"
                } else {
                    $txtWSUSStatus.Text = "Nicht verbunden"
                }
            } else {
                $txtWSUSStatus.Text = "Nicht konfiguriert"
            }
        } else {
            $txtWSUSStatus.Text = "Deaktiviert"
        }
    } catch {
        $txtWSUSStatus.Text = "Fehler beim Prüfen des WSUS-Status"
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
        $txtWSUSTargetGroup.Text = "Unbekannt"
        if ($txtCurrentTargetGroup) {
            $txtCurrentTargetGroup.Text = "Unbekannt"
        }
    }

    # WSUS-Konfigurationsquelle ermitteln
    try {
        $configSource = "Lokale Einstellungen"
        $policySource = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "*" -ErrorAction SilentlyContinue

        if ($policySource) {
            $configSource = "Gruppenrichtlinie"
        }

        $txtWSUSConfigSource.Text = $configSource
    } catch {
        $txtWSUSConfigSource.Text = "Unbekannt"
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
            $txtWSUSLastCheck.Text = "Nicht verfügbar"
            if ($txtLastSyncTime) {
                $txtLastSyncTime.Text = "Nicht verfügbar"
            }
        }
    } catch {
        $txtWSUSLastCheck.Text = "Fehler beim Abrufen der letzten Prüfung"
        if ($txtLastSyncTime) {
            $txtLastSyncTime.Text = "Fehler beim Abrufen der letzten Prüfung"
        }
    }

    # Gruppenrichtlinieneinstellungen laden
    try {
        $gpoSettings = Get-WindowsUpdateGPOSetting

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
                # DetectionFrequency (Stunden, 1-22) entspricht hier dem Intervall "Täglich"
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
        Write-Error "Fehler beim Laden der Synchronisierungseinstellungen: $_"
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
                    $targetGroups = Get-WSUSTargetGroup -WSUSServer $serverName -WSUSPort $port -UseSSL $useSSL
                    $dgWSUSTargetGroups.ItemsSource = $targetGroups
                }
            }
        } catch {
            Write-Error "Fehler beim Laden der WSUS-Zielgruppen: $_"
        }
    }

    # Synchronisierungsverlauf laden
    $dgSyncHistory = $window.FindName("dgSyncHistory")
    if ($dgSyncHistory) {
        try {
            $syncHistory = Get-WSUSSyncHistory
            $dgSyncHistory.ItemsSource = $syncHistory
        } catch {
            Write-Error "Fehler beim Laden des Synchronisierungsverlaufs: $_"
        }
    }



    Write-StatusText -Text "WSUS-Einstellungen wurden geladen." -Color "Green"
}

# Funktion zum Initialisieren der Update-Zeitplan-Steuerelemente
function Initialize-UpdateScheduleControl {
    try {
        # ComboBox für Wochentage befüllen
        $cmbWeekDay = $window.FindName("cmbWeekDay")
        if ($cmbWeekDay -and $cmbWeekDay.Items.Count -eq 0) {
            $weekdays = @("Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag")
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
            # Get-AutoUpdateStatus liefert Text; nur "Deaktiviert" bedeutet deaktiviert
            $autoUpdateStatus = Get-AutoUpdateStatus
            $chkEnableAutoUpdates.IsChecked = ($autoUpdateStatus -ne "Deaktiviert")

            # Event-Handler für die CheckBox
            $chkEnableAutoUpdates.Add_Checked({
                Enable-WindowsAutoUpdate
            })

            $chkEnableAutoUpdates.Add_Unchecked({
                Disable-WindowsAutoUpdate
            })
        }

    } catch {
        Write-StatusText -Text "Fehler beim Initialisieren der Zeitplan-Steuerelemente: $_" -Color "Red"
    }
}

# Name der geplanten Aufgabe (einheitlich für Anlegen, Anzeigen und Löschen)
$script:ScheduledTaskName = "easyWINUpdate_Task"
$script:LegacyScheduledTaskNames = @("EasyWINUpdate_Scheduled_Task")
# Unter %ProgramFiles% koennen Standardbenutzer keine Ordner anlegen (anders als unter %ProgramData%)
$script:ScheduledTaskDirectory = Join-Path $env:ProgramFiles 'PhinIT\easyWINUpdate'

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
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param ()
    $removed = $false
    if (-not $PSCmdlet.ShouldProcess($script:ScheduledTaskName, 'Geplante Aufgabe entfernen')) {
        return $removed
    }
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
    $trustedSids = @('S-1-5-18', 'S-1-5-32-544')
    if (Test-Path -LiteralPath $Path) {
        # Vorhandenen Ordner nur weiterverwenden, wenn er SYSTEM oder den Administratoren gehört
        $ownerSid = $null
        try {
            $ownerSid = (Get-Acl -LiteralPath $Path).GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        } catch {
            $ownerSid = $null
        }
        if ($trustedSids -notcontains $ownerSid) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    $acl.SetAccessRuleProtection($true, $false)
    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in $trustedSids) {
        $identity = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', $inheritance, [System.Security.AccessControl.PropagationFlags]::None, 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Funktion zum Setzen des Windows Update Zeitplans
function Set-WindowsUpdateSchedule {
    [CmdletBinding(SupportsShouldProcess)]
    param ()
    try {
        if (-not $script:IsAdmin) {
            Write-StatusText -Text "Zum Anlegen des Zeitplans sind Administratorrechte erforderlich." -Color "Red"
            return
        }

        # Werte aus der GUI auslesen
        $chkEnableAutoUpdates = $window.FindName("chkEnableAutoUpdates")
        if (-not $chkEnableAutoUpdates -or -not $chkEnableAutoUpdates.IsChecked) {
            Write-StatusText -Text "Automatische Updates sind deaktiviert. Bitte zuerst aktivieren." -Color "Yellow"
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
            Write-StatusText -Text "Bitte alle erforderlichen Zeitplan-Optionen auswählen." -Color "Yellow"
            return
        }

        # Werte extrahieren (Auswertung über den Index, unabhängig vom angezeigten Text)
        $scheduleIndex = $cmbUpdateScheduleType.SelectedIndex          # 0 = täglich, 1 = wöchentlich, 2 = monatlich
        $scheduleType = [string]$cmbUpdateScheduleType.SelectedItem.Content
        $weekDayIndex = if ($cmbWeekDay -and $cmbWeekDay.SelectedIndex -ge 0) { $cmbWeekDay.SelectedIndex } else { 0 }
        $weekDay = if ($cmbWeekDay -and $null -ne $cmbWeekDay.SelectedItem) { [string]$cmbWeekDay.SelectedItem.Content } else { "Montag" }
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
                Write-StatusText -Text "Zeitplan nicht angelegt: PSWindowsUpdate ist nicht für alle Benutzer installiert." -Color "Yellow"
                return
            }
            Write-StatusText -Text "Installiere PSWindowsUpdate für alle Benutzer..." -Color "Blue"
            Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force -ErrorAction Stop
        }

        if (-not $PSCmdlet.ShouldProcess($script:ScheduledTaskName, 'Windows Update-Zeitplan anlegen')) {
            return
        }

        # Aufgabenplanung konfigurieren
        Write-StatusText -Text "Konfiguriere Windows Update-Zeitplan..." -Color "Blue"

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
        # Vorhandene Datei löschen, damit sie neu angelegt wird und die geschützten Rechte des Ordners erbt
        if (Test-Path -LiteralPath $scriptPath) {
            Remove-Item -LiteralPath $scriptPath -Force -ErrorAction Stop
        }
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

        Write-StatusText -Text "Windows Update-Zeitplan erfolgreich konfiguriert" -Color "Green"

        # Aktuellen Zeitplan anzeigen
        Get-WindowsUpdateSchedule

    } catch {
        Write-StatusText -Text "Fehler beim Anlegen des Windows Update-Zeitplans: $_" -Color "Red"
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

                # Zeitplan-Informationen aufbereiten (englische Werte aus Version <= 0.2.4 werden weiterhin erkannt)
                $scheduleInfo = "Zeitplan-Typ: $scheduleType`r`n"

                if ($scheduleType -in @("Wöchentlich", "Weekly")) {
                    $scheduleInfo += "Wochentag: $($scheduleConfig.WeekDay)`r`n"
                } elseif ($scheduleType -in @("Monatlich", "Monthly")) {
                    $scheduleInfo += "Tag des Monats: $($scheduleConfig.MonthDay)`r`n"
                }

                $scheduleInfo += "Uhrzeit: $($scheduleConfig.Hour):$($scheduleConfig.Minute)`r`n"
                $scheduleInfo += "Verhalten: $($scheduleConfig.UpdateBehavior)`r`n"
                $scheduleInfo += "Nach der Installation: $($scheduleConfig.RestartBehavior)`r`n"

                if ($scheduleConfig.RestartBehavior -like "Neustart planen*" -or $scheduleConfig.RestartBehavior -like "Schedule restart*") {
                    $scheduleInfo += "Geplanter Neustart: $($scheduleConfig.RestartHour):$($scheduleConfig.RestartMinute)`r`n"
                }
            }

            # Status anzeigen
            $scheduleText = "Windows Update-Zeitplan ist aktiv`r`n`r`n"
            $scheduleText += $scheduleInfo
            $scheduleText += "`r`nNächste Ausführung: $nextRunTime`r`n"
            $scheduleText += "Letzte Ausführung: $lastRunTime"

            $txtCurrentSchedule.Text = $scheduleText

            # Letztes Ergebnis anzeigen (0 = Erfolg, 0x41303 = noch nicht ausgeführt)
            if ($lastResult -ne 0 -and $lastResult -ne 0x41303) {
                $txtLastRunResult.Text = "Letztes Ergebnis: 0x{0:X8} (Fehlercode)" -f $lastResult
                $txtLastRunResult.Visibility = "Visible"
            } else {
                $txtLastRunResult.Visibility = "Collapsed"
            }
        } else {
            $txtCurrentSchedule.Text = "Kein Windows Update-Zeitplan konfiguriert."
            $txtLastRunResult.Visibility = "Collapsed"
        }

        Write-StatusText -Text "Zeitplan-Informationen aktualisiert" -Color "Green"

    } catch {
        Write-StatusText -Text "Fehler beim Abrufen der Zeitplan-Informationen: $_" -Color "Red"
    }
}

# Funktion zum Aktivieren der automatischen Windows Updates
function Enable-WindowsAutoUpdate {
    try {
        Write-StatusText -Text "Aktiviere automatische Windows Updates..." -Color "Blue"

        # Registry-Einstellungen für automatische Updates
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

        # Prüfen, ob der Pfad existiert, ansonsten erstellen
        if (!(Test-Path $auPath)) {
            New-Item -Path $auPath -Force | Out-Null
        }

        # AUOptions-Wert setzen (4 = automatische Installation)
        Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 4 -Type DWord -Force

        Write-StatusText -Text "Automatische Windows Updates aktiviert" -Color "Green"
    } catch {
        Write-StatusText -Text "Fehler beim Aktivieren der automatischen Windows Updates: $_" -Color "Red"
    }
}

# Funktion zum Deaktivieren der automatischen Windows Updates
function Disable-WindowsAutoUpdate {
    try {
        Write-StatusText -Text "Deaktiviere automatische Windows Updates..." -Color "Blue"

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
            Write-StatusText -Text "Geplante Update-Aufgabe entfernt" -Color "Blue"
        }

        Write-StatusText -Text "Automatische Windows Updates deaktiviert" -Color "Green"
    } catch {
        Write-StatusText -Text "Fehler beim Deaktivieren der automatischen Windows Updates: $_" -Color "Red"
    }
}

# Funktion zum Abrufen des aktuellen Status der automatischen Updates
function Get-AutoUpdateStatus {
    try {
        # Registry-Pfad für Windows Update Einstellungen
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

        if (Test-Path $auPath) {
            $noAutoUpdate = (Get-ItemProperty -Path $auPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
            $auOptions = (Get-ItemProperty -Path $auPath -Name "AUOptions" -ErrorAction SilentlyContinue).AUOptions

            # Status bestimmen
            if ($null -eq $noAutoUpdate) {
                return "Unbekannt"
            }
            elseif ($noAutoUpdate -eq 1) {
                return "Deaktiviert"
            }
            else {
                # Konfigurationstyp anzeigen
                switch ($auOptions) {
                    1 { return "Nur benachrichtigen" }
                    2 { return "Vor dem Download benachrichtigen" }
                    3 { return "Vor der Installation benachrichtigen" }
                    4 { return "Automatische Installation" }
                    default { return "Aktiviert (benutzerdefiniert)" }
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

# Funktion zum Wechseln zwischen den Seiten
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
            Write-StatusText -Text "Willkommen bei easyWINUpdate" -Color "Green"
            # Lade die Update-Status-Informationen auf der Home-Seite
            Show-UpdateStatusPage
        }
        "InstalledUpdates" {
            $installedUpdatesPage.Visibility = "Visible"
            Show-InstalledUpdatesPage
        }
        "AvailableUpdates" {
            $availableUpdatesPage.Visibility = "Visible"
            Show-AvailableUpdatesPage
        }
        "WSUSSettings" {
            $wsusSettingsPage.Visibility = "Visible"
            Show-WSUSSettingsPage
        }
        "Troubleshooting" {
            $troubleshootingPage.Visibility = "Visible"
            Write-StatusText -Text "Werkzeuge zur Fehlerbehebung bereit." -Color "Blue"
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
        Write-StatusText -Text "Suche nach Updates..." -Color "Blue"
        try {
            Start-UpdateDetection
            Write-StatusText -Text "Update-Erkennung gestartet. Ergebnisse erscheinen nach Abschluss der Suche." -Color "Green"
        } catch {
            Write-StatusText -Text "Fehler beim Starten der Update-Erkennung: $_" -Color "Red"
        }
        Show-UpdateStatusPage
    })
}

# Event-Handler für installierte Updates-Seite
$btnSearchInstalled = $window.FindName("btnSearchInstalled")
$btnSearchInstalled.Add_Click({
    $txtSearchInstalled = $window.FindName("txtSearchInstalled")
    $searchText = ([string]$txtSearchInstalled.Text).Trim()

    if (-not [string]::IsNullOrEmpty($searchText)) {
        # Bereits geladene Liste filtern (kein erneuter Get-HotFix-Aufruf), Platzhalter im Suchtext maskieren
        $hotfixes = if ($script:InstalledUpdatesCache) { $script:InstalledUpdatesCache } else { Get-InstalledWindowsUpdate }
        $pattern = "*$([System.Management.Automation.WildcardPattern]::Escape($searchText))*"
        $filteredHotfixes = @($hotfixes | Where-Object {
            "$($_.HotFixID)" -like $pattern -or "$($_.Description)" -like $pattern
        })

        $dgInstalledUpdates = $window.FindName("dgInstalledUpdates")
        $dgInstalledUpdates.ItemsSource = $filteredHotfixes

        Write-StatusText -Text "$($filteredHotfixes.Count) Updates mit '$searchText' gefunden" -Color "Green"
    } else {
        Show-InstalledUpdatesPage
    }
})

$btnRefreshInstalled = $window.FindName("btnRefreshInstalled")
$btnRefreshInstalled.Add_Click({
    Show-InstalledUpdatesPage
})

$btnExportInstalled = $window.FindName("btnExportInstalled")
$btnExportInstalled.Add_Click({
    # Desktop-Pfad über die Shell ermitteln (funktioniert auch bei umgeleitetem/OneDrive-Desktop)
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrEmpty($desktopPath) -or -not (Test-Path -LiteralPath $desktopPath)) {
        $desktopPath = $script:LogDirectory
    }
    $savePath = Join-Path $desktopPath "Installierte_Updates_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $hotfixes = Get-InstalledWindowsUpdate

    if ($hotfixes) {
        try {
            $hotfixes | Export-Csv -Path $savePath -NoTypeInformation -Delimiter ";" -Encoding UTF8 -ErrorAction Stop
            Write-StatusText -Text "Updates wurden nach '$savePath' exportiert." -Color "Green"
        } catch {
            Write-StatusText -Text "Fehler beim Exportieren der Updates: $_" -Color "Red"
        }
    } else {
        Write-StatusText -Text "Keine Updates zum Exportieren vorhanden." -Color "Red"
    }
})

# Event-Handler für verfügbare Updates-Seite
$btnSearchAvailable = $window.FindName("btnSearchAvailable")
$btnSearchAvailable.Add_Click({
    Show-AvailableUpdatesPage
})

$btnInstallAll = $window.FindName("btnInstallAll")
$btnInstallAll.Add_Click({
    $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
    $updates = @($dgAvailableUpdates.ItemsSource | Where-Object { $_ -and $_.Identity })

    if ($updates.Count -gt 0) {
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie alle $($updates.Count) Updates installieren? Anschließend kann ein Neustart erforderlich sein.",
            "Updates installieren",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            # Nur die angezeigten (gefilterten) Updates installieren, Quelle wie konfiguriert (Windows Update oder WSUS)
            Start-UpdateInstallation -UpdateIds @($updates | ForEach-Object { [string]$_.Identity }) -Description "$($updates.Count) Updates"
        }
    } else {
        Write-StatusText -Text "Keine Updates zur Installation verfügbar." -Color "Red"
    }
})

# Liefert die in der Liste angehakten Updates (offene Bearbeitung der CheckBox-Spalte vorher übernehmen)
function Get-SelectedAvailableUpdate {
    $dgAvailableUpdates = $window.FindName("dgAvailableUpdates")
    [void]$dgAvailableUpdates.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
    return @($dgAvailableUpdates.ItemsSource | Where-Object { $_ -and $_.IsSelected -and $_.Identity })
}

$btnInstallSelected = $window.FindName("btnInstallSelected")
$btnInstallSelected.Add_Click({
    $updates = Get-SelectedAvailableUpdate

    if ($updates.Count -gt 0) {
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie die ausgewählten $($updates.Count) Updates installieren? Anschließend kann ein Neustart erforderlich sein.",
            "Updates installieren",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            Start-UpdateInstallation -UpdateIds @($updates | ForEach-Object { [string]$_.Identity }) -Description "$($updates.Count) ausgewählte Updates"
        }
    } else {
        Write-StatusText -Text "Keine Updates ausgewählt." -Color "Red"
    }
})

$btnDownloadSelected = $window.FindName("btnDownloadSelected")
$btnDownloadSelected.Add_Click({
    $updates = Get-SelectedAvailableUpdate

    if ($updates.Count -gt 0) {
        Start-UpdateInstallation -UpdateIds @($updates | ForEach-Object { [string]$_.Identity }) -DownloadOnly -Description "$($updates.Count) ausgewählte Updates"
    } else {
        Write-StatusText -Text "Keine Updates ausgewählt." -Color "Red"
    }
})

# Event-Handler für die WSUS-Einstellungsseite
$btnResetWSUS = $window.FindName("btnResetWSUS")
$btnResetWSUS.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie die WSUS-Einstellungen wirklich zurücksetzen? Der Computer lädt Updates danach direkt von Microsoft herunter.",
        "WSUS-Einstellungen zurücksetzen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        # Dienstneustart und Update-Erkennung im Hintergrund
        Invoke-RepairAction -Name 'WSUS-Einstellungen zurücksetzen' -FunctionName 'Reset-WSUSSetting' -HelperFunctions 'Start-UpdateDetection' -OnCompleted {
            param($Output, $ErrorText)
            if ([bool](@($Output) | Select-Object -Last 1)) {
                Write-StatusText -Text "WSUS-Einstellungen wurden erfolgreich zurückgesetzt." -Color "Green"
                Show-WSUSSettingsPage
            } else {
                Write-StatusText -Text "Fehler beim Zurücksetzen der WSUS-Einstellungen. $ErrorText" -Color "Red"
            }
        }
    }
})

$btnCheckWSUSConn = $window.FindName("btnCheckWSUSConn")
$btnCheckWSUSConn.Add_Click({
    $wsusSettings = Get-WSUSSetting

    if ($wsusSettings.Server) {
        Write-StatusText -Text "Prüfe die Verbindung zum WSUS-Server..." -Color "Blue"
        # TCP-Verbindungstest (bis zu 3 Sekunden) im Hintergrund, Schaltfläche bis zum Ergebnis sperren
        $btnCheckWSUSConn = $window.FindName("btnCheckWSUSConn")
        $btnCheckWSUSConn.IsEnabled = $false
        try {
            Start-FunctionInBackground -Name 'WSUS-Verbindungstest' -FunctionName 'Test-WSUSConnection' -FunctionParameters @{ WSUSServer = [string]$wsusSettings.Server } -OnCompleted {
                param($Output, $ErrorText)
                $window.FindName("btnCheckWSUSConn").IsEnabled = $true
                if ([bool](@($Output) | Select-Object -Last 1)) {
                    Write-StatusText -Text "Verbindung zum WSUS-Server erfolgreich hergestellt." -Color "Green"
                } else {
                    Write-StatusText -Text "Verbindung zum WSUS-Server fehlgeschlagen. $ErrorText" -Color "Red"
                }
            }
        } catch {
            $btnCheckWSUSConn.IsEnabled = $true
            Write-StatusText -Text "Fehler beim Starten des Verbindungstests: $_" -Color "Red"
        }
    } else {
        Write-StatusText -Text "Kein WSUS-Server konfiguriert." -Color "Red"
    }
})

$btnDetectNow = $window.FindName("btnDetectNow")
$btnDetectNow.Add_Click({
    Write-StatusText -Text "Starte Update-Erkennung..." -Color "Blue"

    try {
        # Update-Erkennung erzwingen
        Start-UpdateDetection
        Write-StatusText -Text "Update-Erkennung gestartet." -Color "Green"
    } catch {
        Write-StatusText -Text "Fehler beim Starten der Update-Erkennung: $_" -Color "Red"
    }
})

# Gruppenrichtlinien-Einstellungen
$btnRefreshGPOSettings = $window.FindName("btnRefreshGPOSettings")
if ($btnRefreshGPOSettings) {
    $btnRefreshGPOSettings.Add_Click({
        Show-WSUSSettingsPage
        Write-StatusText -Text "Einstellungen neu geladen." -Color "Green"
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
            Write-StatusText -Text "Bitte zuerst alle Einstellungen auswählen." -Color "Yellow"
            return
        }

        $installHour = 3
        if ([string]$cmbInstallTime.SelectedItem.Content -match '^(\d{1,2}):') {
            $installHour = [int]$Matches[1]
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie diese Windows Update-Richtlinieneinstellungen in die lokale Registry schreiben? Der Windows Update-Dienst wird neu gestartet.",
            "Einstellungen übernehmen",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

        # AUOptions: 2 = nur benachrichtigen, 3 = herunterladen und benachrichtigen, 4 = automatisch installieren
        # Registry schreiben und Dienst neu starten im Hintergrund
        Invoke-RepairAction -Name 'Richtlinieneinstellungen übernehmen' -FunctionName 'Set-WindowsUpdateGPOSetting' -FunctionParameters @{
            AutoUpdateEnabled = ($cmbAutoUpdateSetting.SelectedIndex -eq 0)
            ConfigType        = ($cmbUpdateConfigType.SelectedIndex + 2)
            InstallTime       = $installHour
            ShowNotifications = [bool]$chkShowNotifications.IsChecked
            RebootBehavior    = $cmbRebootBehavior.SelectedIndex
        } -OnCompleted {
            param($Output, $ErrorText)
            if ([bool](@($Output) | Select-Object -Last 1)) {
                Write-StatusText -Text "Windows Update-Richtlinieneinstellungen übernommen." -Color "Green"
                Show-WSUSSettingsPage
            } else {
                Write-StatusText -Text "Fehler beim Übernehmen der Windows Update-Richtlinieneinstellungen. $ErrorText" -Color "Red"
            }
        }
    })
}

# WSUS-Zielgruppen (clientseitige Zielgruppenadressierung)
$btnRefreshTargetGroups = $window.FindName("btnRefreshTargetGroups")
if ($btnRefreshTargetGroups) {
    $btnRefreshTargetGroups.Add_Click({
        $dgWSUSTargetGroups = $window.FindName("dgWSUSTargetGroups")
        $dgWSUSTargetGroups.ItemsSource = @(Get-WSUSTargetGroup)
        Show-WSUSSettingsPage
        Write-StatusText -Text "Zielgruppen aktualisiert." -Color "Green"
    })
}

$btnSetTargetGroup = $window.FindName("btnSetTargetGroup")
if ($btnSetTargetGroup) {
    $btnSetTargetGroup.Add_Click({
        $dgWSUSTargetGroups = $window.FindName("dgWSUSTargetGroups")
        $selectedGroup = $dgWSUSTargetGroups.SelectedItem
        if ($null -eq $selectedGroup -or [string]::IsNullOrWhiteSpace([string]$selectedGroup.Name)) {
            Write-StatusText -Text "Bitte zuerst eine Zielgruppe auswählen." -Color "Yellow"
            return
        }

        $wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $wuServer = (Get-ItemProperty -Path $wuRegPath -Name "WUServer" -ErrorAction SilentlyContinue).WUServer
        if ([string]::IsNullOrEmpty($wuServer)) {
            Write-StatusText -Text "Kein WSUS-Server konfiguriert. Zielgruppen werden nur mit WSUS verwendet." -Color "Yellow"
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
            Write-StatusText -Text "Zielgruppe '$groupName' gesetzt. Die Zuordnung wird mit dem nächsten WSUS-Bericht wirksam." -Color "Green"
            Show-WSUSSettingsPage
        } catch {
            Write-StatusText -Text "Fehler beim Setzen der Zielgruppe: $_" -Color "Red"
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
            Write-StatusText -Text "Bitte ein Synchronisierungsintervall auswählen." -Color "Yellow"
            return
        }
        $syncInterval = [string]$cmbSyncInterval.SelectedItem.Content

        Invoke-RepairAction -Name 'Synchronisierungseinstellungen speichern' -FunctionName 'Set-WSUSSyncSetting' -FunctionParameters @{
            SyncInterval = $syncInterval
            AutoSync     = [bool]$chkAutoSync.IsChecked
        } -Context $syncInterval -OnCompleted {
            param($Output, $ErrorText, $Context)
            if ([bool](@($Output) | Select-Object -Last 1)) {
                # Hinweis: Die Richtlinie DetectionFrequency erlaubt maximal 22 Stunden
                Write-StatusText -Text "Synchronisierungseinstellungen gespeichert ($Context; Erkennungsintervall laut Richtlinie max. 22 Stunden)." -Color "Green"
                Show-WSUSSettingsPage
            } else {
                Write-StatusText -Text "Fehler beim Speichern der Synchronisierungseinstellungen. $ErrorText" -Color "Red"
            }
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
        if ($script:ActiveRepair -or $script:UpdateBeingRemoved -or $script:UpdateInstallationRunning) {
            Write-StatusText -Text "Bitte warten, bis die laufende Aktion abgeschlossen ist." -Color "Yellow"
            return
        }
        Write-StatusText -Text "Entferne Update $kbNumber..." -Color "Blue"
        $script:UpdateBeingRemoved = $kbNumber

        # wusa.exe kann mehrere Minuten benötigen -> im Hintergrund ausführen
        Start-FunctionInBackground -FunctionName 'Remove-WindowsUpdateKB' -FunctionParameters @{ KBNumber = $kbNumber } -OnCompleted {
            param($Output, $ErrorText)
            $removedKB = $script:UpdateBeingRemoved
            $script:UpdateBeingRemoved = $null
            if ([bool]($Output | Select-Object -Last 1)) {
                Write-StatusText -Text "Update $removedKB wurde entfernt. Möglicherweise ist ein Neustart erforderlich." -Color "Green"
                Show-InstalledUpdatesPage
            } else {
                Write-StatusText -Text "Fehler beim Entfernen von Update $removedKB. $ErrorText" -Color "Red"
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
        "Möchten Sie Update $kbNumber installieren?",
        "Update installieren",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-UpdateInstallation -UpdateIds @($identity) -Description "Update $kbNumber"
    }
})

# Event-Handler für die Seite "Fehlerbehebung"
# Alle Reparaturen laufen über Invoke-RepairAction im Hintergrund (GUI bleibt bedienbar, Schaltflächen gesperrt,
# immer nur eine Reparatur gleichzeitig). Statusmeldungen der Funktionen werden im GUI-Thread angezeigt.
$btnCreateRestorePoint = $window.FindName("btnCreateRestorePoint")
$btnCreateRestorePoint.Add_Click({
    Invoke-RepairAction -Name 'Wiederherstellungspunkt erstellen' -FunctionName 'New-SystemRestorePoint' -OnCompleted {
        param($Output, $ErrorText)
        if ([bool](@($Output) | Select-Object -Last 1)) {
            Write-StatusText -Text "Der Systemwiederherstellungspunkt wurde erfolgreich erstellt." -Color "Green"
        } else {
            Write-StatusText -Text "Fehler beim Erstellen des Systemwiederherstellungspunkts. $ErrorText" -Color "Red"
        }
    }
})

$btnResetComponents = $window.FindName("btnResetComponents")
$btnResetComponents.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie die Windows Update-Komponenten wirklich zurücksetzen? Dabei werden die Update-Dienste beendet und alle Update-Caches gelöscht.",
        "Windows Update-Komponenten zurücksetzen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'Komponenten-Reset' -FunctionName 'Reset-WindowsUpdateComponent' -HelperFunctions 'Start-UpdateDetection'
    }
})

$btnCheckSystemFiles = $window.FindName("btnCheckSystemFiles")
$btnCheckSystemFiles.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie die Windows-Systemdateien prüfen und reparieren? DISM und SFC laufen in einem eigenen Konsolenfenster und können einige Zeit dauern.",
        "Systemdateien prüfen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        # Startet nur das Konsolenfenster und kehrt sofort zurück
        Repair-WindowsSystemFile | Out-Null
    }
})

$btnClearUpdateHistory = $window.FindName("btnClearUpdateHistory")
$btnClearUpdateHistory.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie den Windows Update-Verlauf und alle Caches löschen? Dabei gehen alle Informationen über frühere Update-Versuche verloren.",
        "Update-Verlauf löschen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'Update-Verlauf löschen' -FunctionName 'Clear-WindowsUpdateHistory'
    }
})

$btnRegisterDLLs = $window.FindName("btnRegisterDLLs")
$btnRegisterDLLs.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie alle Windows Update-DLLs neu registrieren? Das kann bei Problemen mit den Update-Komponenten helfen.",
        "Update-DLLs registrieren",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'DLL-Registrierung' -FunctionName 'Register-WindowsUpdateDLL'
    }
})

$btnClearStuckUpdates = $window.FindName("btnClearStuckUpdates")
$btnClearStuckUpdates.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie hängende Updates und BITS-Jobs entfernen? Das kann bei hängenden Downloads helfen.",
        "Hängende Updates entfernen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        # Get-WindowsPackage kann lange dauern -> im Hintergrund ausführen
        Invoke-RepairAction -Name 'Hängende Updates entfernen' -FunctionName 'Clear-StuckUpdateAndBITSJob' -HelperFunctions 'Start-UpdateDetection' -OnCompleted {
            param($Output, $ErrorText)
            if ([bool](@($Output) | Select-Object -Last 1)) {
                Write-StatusText -Text "Hängende Updates und BITS-Jobs wurden entfernt." -Color "Green"
            } else {
                Write-StatusText -Text "Fehler beim Entfernen von hängenden Updates. $ErrorText" -Color "Red"
            }
        }
    }
})

# Fehlerdiagnose (Ereignisprotokoll auswerten; Fehlercode-Tabelle wird an den Hintergrund-Runspace übergeben)
$btnDiagnoseError = $window.FindName("btnDiagnoseError")
$btnDiagnoseError.Add_Click({
    Invoke-RepairAction -Name 'Fehlerdiagnose' -FunctionName 'Get-WindowsUpdateErrorDiagnosis' -FunctionParameters @{ ErrorCodeTable = $errorCodes } -OnCompleted {
        param($Output, $ErrorText)
        $diagnosisText = [string](@($Output) | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        if ([string]::IsNullOrEmpty($diagnosisText)) {
            $diagnosisText = "Die Fehlerdiagnose lieferte kein Ergebnis. $ErrorText"
        }
        Write-StatusText -Text "Fehlerdiagnose abgeschlossen." -Color "Green"
        [System.Windows.MessageBox]::Show($diagnosisText, "Windows Update-Fehlerdiagnose", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
})

$btnRepairBITS = $window.FindName("btnRepairBITS")
$btnRepairBITS.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie eine erweiterte Reparatur des BITS-Dienstes durchführen?",
        "BITS-Dienst reparieren",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'BITS-Reparatur' -FunctionName 'Repair-BITSService'
    }
})

# WaaSMedic-Dienst
$btnWaaSMedic = $window.FindName("btnWaaSMedic")
$btnWaaSMedic.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie den Windows Update Medic Service (WaaSMedicSvc) prüfen und reparieren? Das kann bei Problemen im Update-Prozess helfen.",
        "WaaSMedic-Dienst reparieren",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'WaaSMedic-Reparatur' -FunctionName 'Repair-WaaSMedicService'
    }
})

# Windows Update-Log-Analyse (Get-WindowsUpdateLog dauert lange -> Hintergrund)
$btnAnalyzeLogs = $window.FindName("btnAnalyzeLogs")
$btnAnalyzeLogs.Add_Click({
    Invoke-RepairAction -Name 'Log-Analyse' -FunctionName 'Get-WindowsUpdateLogAnalysis' -FunctionParameters @{ OutputDirectory = $script:LogDirectory } -OnCompleted {
        param($Output, $ErrorText)
        $analysisText = [string](@($Output) | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        if ([string]::IsNullOrEmpty($analysisText)) {
            $analysisText = "Die Log-Analyse lieferte kein Ergebnis. $ErrorText"
        }
        Write-StatusText -Text "Log-Analyse abgeschlossen." -Color "Green"
        [System.Windows.MessageBox]::Show($analysisText, "Windows Update-Log-Analyse", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
})

# Registry-Reparatur
$btnRepairRegistry = $window.FindName("btnRepairRegistry")
$btnRepairRegistry.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie die Windows Update-Registry-Einstellungen reparieren? Das kann bei fehlerhaften Konfigurationseinstellungen helfen.",
        "Registry-Einstellungen reparieren",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'Registry-Reparatur' -FunctionName 'Repair-WindowsUpdateRegistry'
    }
})

# Datenbank-Reparatur
$btnRepairDatabase = $window.FindName("btnRepairDatabase")
$btnRepairDatabase.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie die Windows Update-Datenbank reparieren? Dabei werden die aktuellen Update-Datenbanken (SoftwareDistribution, catroot2) gesichert und zurückgesetzt.",
        "Update-Datenbank reparieren",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'Datenbank-Reparatur' -FunctionName 'Repair-WindowsUpdateDatabase' -HelperFunctions 'Start-UpdateDetection'
    }
})

# Debug-Modus umschalten
$btnToggleDebug = $window.FindName("btnToggleDebug")
$btnToggleDebug.Add_Click({
    # Prüfen, ob der Debug-Modus aktiv ist (schneller Registry-Zugriff im GUI-Thread)
    $wuTraceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Trace"
    $debugActive = $false

    if (Test-Path $wuTraceKey) {
        $flags = (Get-ItemProperty -Path $wuTraceKey -ErrorAction SilentlyContinue).Flags
        if ($flags -eq 1) {
            $debugActive = $true
        }
    }

    $message = if ($debugActive) {
        "Der Windows Update-Fehlersuchmodus ist derzeit aktiv. Möchten Sie ihn deaktivieren?"
    } else {
        "Möchten Sie den Windows Update-Fehlersuchmodus aktivieren? Er hilft bei der Diagnose schwerwiegender Update-Probleme."
    }

    $result = [System.Windows.MessageBox]::Show(
        $message,
        "Fehlersuchmodus umschalten",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'Fehlersuchmodus umschalten' -FunctionName 'Set-WindowsUpdateDebugMode' -FunctionParameters @{ Enable = (-not $debugActive) }
    }
})

# Auto-Fix (ruft mehrere Reparaturfunktionen nacheinander auf -> alle als Hilfsfunktionen in den Runspace übernehmen)
$btnAutoFix = $window.FindName("btnAutoFix")
$btnAutoFix.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie eine automatische Fehlerbehebung für Windows Update durchführen? Das System versucht, Fehler selbstständig zu erkennen und zu beheben.",
        "Automatische Fehlerbehebung",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-RepairAction -Name 'Auto-Fix' -FunctionName 'Repair-WindowsUpdateIssue' -HelperFunctions @(
            'Start-UpdateDetection', 'Start-ConsoleTool', 'Clear-WindowsUpdateHistory', 'Repair-BITSService',
            'Reset-WindowsUpdateComponent', 'Repair-WindowsUpdateDatabase', 'Repair-WindowsSystemFile',
            'Repair-WindowsUpdateRegistry', 'Repair-WaaSMedicService'
        )
    }
})

# Weitere Werkzeuge
$btnCleanTemp = $window.FindName("btnCleanTemp")
if ($btnCleanTemp) {
    $btnCleanTemp.Add_Click({
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie die temporären Dateien des aktuellen Benutzers und von Windows ($env:SystemRoot\Temp) löschen? Verwendete Dateien werden übersprungen.",
            "Temporäre Dateien bereinigen",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Invoke-RepairAction -Name 'Temp-Bereinigung' -FunctionName 'Clear-TemporaryFile' -OnCompleted {
            param($Output, $ErrorText)
            $removedCount = @($Output) | Where-Object { $_ -is [int] } | Select-Object -Last 1
            if ($null -ne $removedCount) {
                Write-StatusText -Text "$removedCount temporäre Einträge entfernt (verwendete Dateien wurden übersprungen)." -Color "Green"
            } else {
                Write-StatusText -Text "Fehler beim Bereinigen der temporären Dateien. $ErrorText" -Color "Red"
            }
        }
    })
}

$btnResetWinsock = $window.FindName("btnResetWinsock")
if ($btnResetWinsock) {
    $btnResetWinsock.Add_Click({
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie den Winsock-Katalog zurücksetzen? Anschließend ist ein Neustart erforderlich.",
            "Winsock zurücksetzen",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Invoke-RepairAction -Name 'Winsock-Reset' -FunctionName 'Reset-WinsockCatalog' -OnCompleted {
            param($Output, $ErrorText)
            $winsockResult = @($Output) | Where-Object { $null -ne $_ -and $_.PSObject.Properties['Success'] } | Select-Object -Last 1
            if ($winsockResult -and $winsockResult.Success) {
                Write-StatusText -Text "Winsock-Katalog zurückgesetzt. Bitte den Computer neu starten." -Color "Green"
            } else {
                Write-StatusText -Text "Fehler beim Zurücksetzen von Winsock: $(if ($winsockResult) { $winsockResult.Output }) $ErrorText" -Color "Red"
            }
        }
    })
}

$btnCheckDisk = $window.FindName("btnCheckDisk")
if ($btnCheckDisk) {
    $btnCheckDisk.Add_Click({
        try {
            # Online-Prüfung (nur lesend) des Systemlaufwerks in eigenem Konsolenfenster
            Start-ConsoleTool -CommandLine "chkdsk.exe $env:SystemDrive /scan" -Title "easyWINUpdate - CHKDSK"
            Write-StatusText -Text "CHKDSK wurde in einem eigenen Fenster gestartet." -Color "Green"
        } catch {
            Write-StatusText -Text "Fehler beim Starten von CHKDSK: $_" -Color "Red"
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
    Initialize-UpdateScheduleControl

    # WSUS-Seite initialisieren
    Show-WSUSSettingsPage
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
        $closingArgs = $args[1]
        if ($script:ActiveRepair) {
            # Ein Abbruch mitten in einer Reparatur kann Dienste gestoppt bzw. Ordner umbenannt zurücklassen
            $closeAnswer = [System.Windows.MessageBox]::Show(
                "Die Aktion '$($script:ActiveRepair)' läuft noch. Beim Schließen wird sie abgebrochen; Windows Update-Dienste können dann gestoppt bleiben.`r`n`r`nTrotzdem beenden?",
                "Reparatur läuft",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($closeAnswer -ne [System.Windows.MessageBoxResult]::Yes) {
                $closingArgs.Cancel = $true
                return
            }
            Write-AppLog -Message "Anwendung während '$($script:ActiveRepair)' beendet - Aktion abgebrochen" -Level 'WARN'
        }
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
    Write-Error "Fehler beim Ausführen des Skripts: $_"
}
#endregion
