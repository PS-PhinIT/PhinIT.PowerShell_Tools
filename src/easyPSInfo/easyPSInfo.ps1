<#
.SYNOPSIS
    easyPSInfo - PowerShell Module & Policy Manager mit Script Launcher (WPF-GUI).
.DESCRIPTION
    Zeigt den Status wichtiger Microsoft-365-/Azure-PowerShell-Module, installiert/aktualisiert diese
    (PSGallery, Scope CurrentUser), zeigt und setzt ExecutionPolicies und startet PowerShell-Skripte.
    Der Script-Launcher durchsucht standardmäßig den Repository-Ordner "src" (alle Tools), wenn das Tool
    unter src\<Tool>\<Tool>.ps1 liegt, sonst den eigenen Skriptordner; ein anderer Basisordner kann in der
    GUI gewählt werden (gespeichert in %APPDATA%\PhinIT\easyPSInfo\settings.json).
.NOTES
    Tool:    easyPSInfo
    Version: 0.0.5
    Autor:   Andreas Hepp | PhinIT (www.phinit.de)
    Web:     www.phinit.de
#>

#############################################
# Teil 1: Konfiguration, Logging und Utility-Funktionen
#############################################

# Benötigte Assemblies laden (für WPF und Windows Forms)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$script:AppName    = "easyPSInfo"
$script:AppVersion = "0.0.5"
$script:WindowTitle = "PhinIT | easyPSInfo - PowerShell-Modul- & Richtlinien-Manager mit Script-Launcher"

# GUI-Elemente (werden in Import-XamlGui im Skript-Scope gesetzt)
$script:window              = $null
$script:txtLog              = $null
$script:lvModules           = $null
$script:lvExecutionPolicies = $null
$script:guiElementNames     = @()

# Script-Launcher: Basisordner, Suchtiefe, Ausschlüsse, Einstellungen
$script:ScriptSearchBase         = $null
$script:ScriptSearchBaseIsCustom = $false
$script:MaxScriptSearchDepth     = 5
$script:MaxScriptSearchFolders   = 2000
$script:ExcludedFolderNames      = @("Logs", "Exports", "Backups")
$script:ExcludedFolderPatterns   = @("*old*", "*#old*", "*# old*")
$script:SettingsFolder = if ($env:APPDATA) { Join-Path -Path $env:APPDATA -ChildPath "PhinIT\easyPSInfo" } else { $null }
$script:SettingsFile   = if ($script:SettingsFolder) { Join-Path -Path $script:SettingsFolder -ChildPath "settings.json" } else { $null }

# Skriptpfad/-ordner robust ermitteln (auch bei leerem $PSScriptRoot, z.B. Ausführung einer Auswahl in der ISE)
$script:ScriptPath = $null
if (-not [string]::IsNullOrEmpty($PSCommandPath)) {
    $script:ScriptPath = $PSCommandPath
}
elseif (-not [string]::IsNullOrEmpty($MyInvocation.MyCommand.Path)) {
    $script:ScriptPath = $MyInvocation.MyCommand.Path
}
elseif ($psISE -and $psISE.CurrentFile -and -not $psISE.CurrentFile.IsUntitled) {
    $script:ScriptPath = $psISE.CurrentFile.FullPath
}

if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    $script:ScriptRoot = $PSScriptRoot
}
elseif ($script:ScriptPath) {
    $script:ScriptRoot = Split-Path -Parent $script:ScriptPath
}
else {
    $script:ScriptRoot = (Get-Location -PSProvider FileSystem).ProviderPath
}

# Logging initialisieren ($ScriptRoot\Logs, Fallback: %LOCALAPPDATA%\PhinIT\easyPSInfo\Logs)
$script:logFolder = Join-Path -Path $script:ScriptRoot -ChildPath "Logs"
try {
    if (-not (Test-Path -LiteralPath $script:logFolder)) {
        New-Item -Path $script:logFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}
catch {
    $fallbackBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [System.IO.Path]::GetTempPath() }
    $script:logFolder = Join-Path -Path $fallbackBase -ChildPath "PhinIT\easyPSInfo\Logs"
    if (-not (Test-Path -LiteralPath $script:logFolder)) {
        New-Item -Path $script:logFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
}
$script:logFile = Join-Path -Path $script:logFolder -ChildPath "easyPSInfo.log"

# Entfernt interne Pfade (UNC-Server/Freigaben, Skriptordner, Suchbasis, Benutzerprofil) aus Log-Einträgen
function ConvertTo-SafeLogText {
    [OutputType([string])]
    param ([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $safeText = $Text

    # Längere Pfade zuerst maskieren (Suchbasis kann über- oder untergeordnet zum Skriptordner sein)
    $masks = New-Object System.Collections.Generic.List[object]
    if ($script:ScriptRoot) {
        $masks.Add([PSCustomObject]@{ Path = $script:ScriptRoot.TrimEnd('\', '/'); Token = '<ScriptRoot>' })
    }
    if ($script:ScriptSearchBase) {
        $masks.Add([PSCustomObject]@{ Path = $script:ScriptSearchBase.TrimEnd('\', '/'); Token = '<ScriptBase>' })
    }
    foreach ($mask in ($masks | Sort-Object -Property { $_.Path.Length } -Descending)) {
        if ($mask.Path -and $mask.Path.Length -gt 3) {
            $safeText = [regex]::Replace($safeText, [regex]::Escape($mask.Path), $mask.Token, 'IgnoreCase')
        }
    }
    if ($env:USERPROFILE) {
        $safeText = [regex]::Replace($safeText, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', 'IgnoreCase')
    }
    $safeText = [regex]::Replace($safeText, '\\\\[^\\\s"'']+\\[^\\\s"'']+', '\\<server>\<share>')
    return $safeText
}

# Zentrale Logging-Funktion (Datei + Verbose/Warning-Stream; die GUI-Anzeige übernimmt Write-GuiLog)
function Write-AppLog {
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Type = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $(ConvertTo-SafeLogText -Text $Message)"
    try {
        Add-Content -LiteralPath $script:logFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Verbose "Log-Datei konnte nicht geschrieben werden: $($_.Exception.Message)"
    }

    if ($Type -in @("Warning", "Error")) {
        Write-Warning $logEntry
    }
    else {
        Write-Verbose $logEntry
    }
}

# Konsolidierte Funktion zur Ausgabe in der Log-Anzeige der GUI (und in der Log-Datei)
function Write-GuiLog {
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Type = "Info"
    )
    Write-AppLog -Message $Message -Type $Type

    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] "
    switch ($Type) {
        "Info"    { $logEntry += "[INFO] " }
        "Warning" { $logEntry += "[WARNUNG] " }
        "Error"   { $logEntry += "[FEHLER] " }
        "Success" { $logEntry += "[OK] " }
    }
    $logEntry += $Message

    if ($script:txtLog) {
        $script:txtLog.AppendText("$logEntry`n")
        $script:txtLog.ScrollToEnd()
    }
}

# Definition der Module
$requiredModules = @(
    @{
        Name         = "ExchangeOnlineManagement"
        MinVersion   = "3.8.0"
        Description  = "Exchange-Online-Verwaltung"
        Webseite     = "https://www.powershellgallery.com/packages/ExchangeOnlineManagement/"
        Install      = "Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Graph"
        MinVersion   = "2.28.0"
        Description  = "Microsoft Graph API"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Graph/"
        Install      = "Install-Module -Name Microsoft.Graph -Scope CurrentUser"
    },
    @{
        Name         = "PowerShellGet"
        MinVersion   = "2.2.5"
        Description  = "PowerShell-Modulverwaltung"
        Webseite     = "https://www.powershellgallery.com/packages/PowerShellGet/"
        Install      = "Install-Module -Name PowerShellGet -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Graph.Beta"
        MinVersion   = "2.28.0"
        Description  = "Microsoft Graph Beta"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Graph.Beta/"
        Install      = "Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Entra"
        MinVersion   = "1.0.7"
        Description  = "Entra ID PowerShell"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Entra/"
        Install      = "Install-Module -Name Microsoft.Entra -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Entra.Beta"
        MinVersion   = "1.0.7"
        Description  = "Entra ID PowerShell (Beta)"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Entra.Beta/"
        Install      = "Install-Module -Name Microsoft.Entra.Beta -Scope CurrentUser"
    },
    @{
        Name         = "PnP.PowerShell"
        MinVersion   = "3.1.0"
        Description  = "SharePoint PnP"
        Webseite     = "https://www.powershellgallery.com/packages/PnP.PowerShell/"
        Install      = "Install-Module -Name PnP.PowerShell -Scope CurrentUser"
    },
    @{
        Name         = "AzureAD"
        MinVersion   = "2.0.2.182"
        Description  = "Azure AD (Legacy) - von Microsoft abgekündigt, Nachfolger: Microsoft.Graph / Microsoft.Entra"
        Webseite     = "https://www.powershellgallery.com/packages/AzureAD/"
        Install      = "Install-Module -Name AzureAD -Scope CurrentUser"
        Deprecated   = $true
    },
    @{
        Name         = "MSOnline"
        MinVersion   = "1.1.183.81"
        Description  = "Azure AD V1 (Legacy) - von Microsoft abgekündigt, Nachfolger: Microsoft.Graph / Microsoft.Entra"
        Webseite     = "https://www.powershellgallery.com/packages/MSOnline/"
        Install      = "Install-Module -Name MSOnline -Scope CurrentUser"
        Deprecated   = $true
    },
    @{
        Name         = "Microsoft.Online.SharePoint.PowerShell"
        MinVersion   = "16.0.26017.12000"
        Description  = "SharePoint Online"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Online.SharePoint.PowerShell/"
        Install      = "Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser"
    }
)

# Installationslogik (läuft in einem eigenen Runspace, damit die GUI nicht blockiert).
# Gibt Objekte mit Type/Message zurück; das letzte Objekt hat Type "Result" und Success.
# PSGallery wird NICHT dauerhaft als vertrauenswürdig eingetragen; die Bestätigung erfolgt in der GUI.
# Hinweis: Der Scriptblock wird als Text in einen eigenen Runspace übergeben - dort gibt es weder
# $script:-Variablen noch Funktionen dieses Skripts; alle Daten kommen über Parameter.
$script:InstallModuleScript = {
    param (
        [string]$ModuleName,
        [string]$MinVersion
    )
    try {
        # PSGallery erfordert TLS 1.2 (Windows PowerShell 5.1 nutzt sonst ggf. TLS 1.0)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
        catch {
            [PSCustomObject]@{ Type = "Warning"; Message = "TLS 1.2 konnte nicht aktiviert werden: $($_.Exception.Message)" }
        }
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            [PSCustomObject]@{ Type = "Info"; Message = "NuGet-Provider wird installiert..." }
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }
        $installParams = @{
            Name         = $ModuleName
            Force        = $true
            AllowClobber = $true
            Scope        = "CurrentUser"
            Repository   = "PSGallery"
            ErrorAction  = "Stop"
        }
        if (-not [string]::IsNullOrEmpty($MinVersion)) {
            $installParams.MinimumVersion = $MinVersion
            [PSCustomObject]@{ Type = "Info"; Message = "$ModuleName (Mindestversion $MinVersion) wird aus der PSGallery installiert..." }
        }
        else {
            [PSCustomObject]@{ Type = "Info"; Message = "$ModuleName wird aus der PSGallery installiert..." }
        }
        Install-Module @installParams
        [PSCustomObject]@{ Type = "Result"; Success = $true; Message = "Modul $ModuleName erfolgreich installiert." }
    }
    catch {
        [PSCustomObject]@{ Type = "Result"; Success = $false; Message = "Fehler bei der Installation von $ModuleName - $($_.Exception.Message)" }
    }
}

# Funktion zur Ermittlung von Moduldaten (ein einziger Get-Module -ListAvailable-Aufruf für alle Module)
function Get-ModuleData {
    $moduleData = New-Object System.Collections.Generic.List[object]
    $moduleNames = @($requiredModules | ForEach-Object { $_.Name })
    $availableModules = @(Get-Module -ListAvailable -Name $moduleNames -ErrorAction SilentlyContinue)

    foreach ($module in $requiredModules) {
        $moduleName    = $module.Name
        $minVersion    = $module.MinVersion
        $deprecated    = [bool]$module.Deprecated

        $installedModule = $availableModules | Where-Object { $_.Name -eq $moduleName } | Sort-Object Version -Descending | Select-Object -First 1
        $installedVersion = if ($installedModule) { $installedModule.Version.ToString() } else { "Nicht installiert" }
        $installed = [bool]$installedModule
        if ($installed -and $minVersion) {
            $installed = ($installedModule.Version -ge [version]$minVersion)
        }

        $status = if (-not $installedModule) { "Fehlt" } elseif ($installed) { "OK" } else { "Veraltet" }
        $toolTip = $module.Description
        if ($deprecated) {
            $status  = "Abgekündigt"
            $toolTip = "$($module.Description). Nur noch für Altskripte verwenden."
        }

        $moduleData.Add([PSCustomObject]@{
            Name             = $moduleName
            DisplayName      = if ($deprecated) { "$moduleName (abgekündigt)" } else { $moduleName }
            Description      = $module.Description
            ToolTip          = $toolTip
            Deprecated       = $deprecated
            Status           = $status
            MinVersion       = $minVersion
            InstalledVersion = $installedVersion
            InstallEnabled   = -not $installed
            Webseite         = $module.Webseite
            InstallCmd       = $module.Install
        })
    }
    return $moduleData.ToArray()
}

# Funktion zur Anzeige des Modulstatus in der ListView
function Show-ModuleStatus {
    Write-GuiLog -Message "Module werden geprüft..." -Type "Info"
    $moduleData = @(Get-ModuleData)
    if ($script:lvModules) {
        $script:lvModules.ItemsSource = $moduleData
        Write-GuiLog -Message "Modulliste aktualisiert." -Type "Info"
        $installedDeprecated = @($moduleData | Where-Object { $_.Deprecated -and $_.InstalledVersion -ne "Nicht installiert" } | ForEach-Object { $_.Name })
        if ($installedDeprecated.Count -gt 0) {
            Write-GuiLog -Message "Hinweis: $($installedDeprecated -join ', ') von Microsoft abgekündigt - bitte auf Microsoft.Graph bzw. Microsoft.Entra umstellen." -Type "Warning"
        }
    }
    else {
        Write-GuiLog -Message "ListView-Element für Module nicht gefunden!" -Type "Error"
    }
}

# ExecutionPolicy-Funktionen
function Get-CurrentExecutionPolicy {
    $policies = Get-ExecutionPolicy -List | Select-Object Scope, ExecutionPolicy
    $policyData = @()

    $scopeDescriptions = @{
        "MachinePolicy" = "MachinePolicy (GPO - alle Benutzer dieses Computers)"
        "UserPolicy"    = "UserPolicy (GPO - aktueller Benutzer)"
        "Process"       = "Process (nur aktuelle PowerShell-Sitzung)"
        "CurrentUser"   = "CurrentUser (Einstellung des aktuellen Benutzers)"
        "LocalMachine"  = "LocalMachine (Standard für alle Benutzer dieses Computers)"
    }

    foreach ($policy in $policies) {
        $scopeName = $policy.Scope.ToString()
        $canModify = $scopeName -notin @("MachinePolicy", "UserPolicy")

        $policyData += [PSCustomObject]@{
            Scope = $scopeName
            Description = $scopeDescriptions[$scopeName]
            CurrentPolicy = $policy.ExecutionPolicy.ToString()
            CanModify = $canModify
            PolicyOptions = @("Restricted", "AllSigned", "RemoteSigned", "Unrestricted", "Bypass", "Undefined")
        }
    }

    # Effektive Richtlinie ergänzen
    try {
        $effectivePolicy = Get-ExecutionPolicy
        $policyData += [PSCustomObject]@{
            Scope = "Effective"
            Description = "Effektive Richtlinie (aktuelle Sitzung)"
            CurrentPolicy = $effectivePolicy.ToString()
            CanModify = $false
            PolicyOptions = @()
        }
    }
    catch {
        Write-GuiLog -Message "Fehler beim Ermitteln der effektiven Richtlinie: $($_.Exception.Message)" -Type "Warning"
    }

    return $policyData
}

function Show-ExecutionPolicy {
    $policyData = Get-CurrentExecutionPolicy
    if ($script:lvExecutionPolicies) {
        $script:lvExecutionPolicies.ItemsSource = $policyData
        Write-GuiLog -Message "Ausführungsrichtlinien aktualisiert." -Type "Info"
    }
}

function Set-ExecutionPolicyHandler {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Scope,
        [string]$Policy
    )

    # Bei Bedarf Administratorrechte prüfen
    if ($Scope -eq "LocalMachine") {
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $result = [System.Windows.MessageBox]::Show(
                "Zum Ändern des Scopes LocalMachine sind Administratorrechte erforderlich. Als Administrator neu starten?",
                "Administratorrechte erforderlich",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                if ([string]::IsNullOrEmpty($script:ScriptPath) -or -not (Test-Path -LiteralPath $script:ScriptPath)) {
                    Write-GuiLog -Message "Neustart als Administrator nicht möglich: Skriptpfad unbekannt (Skript wurde nicht aus einer Datei gestartet)." -Type "Error"
                    return
                }
                try {
                    # Gleiche PowerShell-Edition neu starten (powershell.exe bzw. pwsh.exe, nie powershell_ise.exe)
                    $hostExe = if ($PSVersionTable.PSEdition -eq "Core") { Join-Path -Path $PSHOME -ChildPath "pwsh.exe" } else { Join-Path -Path $PSHOME -ChildPath "powershell.exe" }
                    $argumentLine = "-NoProfile -ExecutionPolicy Bypass -File `"$($script:ScriptPath)`""
                    if ($PSCmdlet.ShouldProcess($script:AppName, "Als Administrator neu starten")) {
                        Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $argumentLine -ErrorAction Stop
                        $script:window.Close()
                    }
                }
                catch {
                    Write-GuiLog -Message "Fehler beim Neustart als Administrator: $($_.Exception.Message)" -Type "Error"
                }
            }
            return
        }
    }

    # Sicherheitsabfrage bei dauerhaft wirkenden, unsicheren Richtlinien
    if ($Scope -in @("CurrentUser", "LocalMachine") -and $Policy -in @("Unrestricted", "Bypass")) {
        $confirm = [System.Windows.MessageBox]::Show(
            "Die ExecutionPolicy '$Policy' für den Scope '$Scope' wirkt dauerhaft und verringert die Skriptsicherheit.`n`nFortfahren?",
            "ExecutionPolicy bestätigen",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-GuiLog -Message "Änderung der ExecutionPolicy für den Scope '$Scope' auf '$Policy' vom Benutzer abgebrochen." -Type "Info"
            return
        }
    }

    try {
        if ($PSCmdlet.ShouldProcess("Scope $Scope", "ExecutionPolicy auf '$Policy' setzen")) {
            Write-GuiLog -Message "ExecutionPolicy für den Scope '$Scope' wird auf '$Policy' gesetzt..." -Type "Info"
            Set-ExecutionPolicy -ExecutionPolicy $Policy -Scope $Scope -Force -ErrorAction Stop
            Write-GuiLog -Message "ExecutionPolicy für den Scope '$Scope' erfolgreich gesetzt." -Type "Success"
        }
    }
    catch [System.Security.SecurityException] {
        # Wird geworfen, wenn die Einstellung gespeichert wurde, aber durch einen spezifischeren Scope überschrieben wird
        Write-GuiLog -Message "ExecutionPolicy für den Scope '$Scope' wurde gesetzt, wird aber durch einen spezifischeren Scope überschrieben: $($_.Exception.Message)" -Type "Warning"
    }
    catch {
        Write-GuiLog -Message "Fehler beim Setzen der ExecutionPolicy für den Scope '$Scope': $($_.Exception.Message)" -Type "Error"
    }
    Show-ExecutionPolicy
}

# Funktion zum Öffnen von Weblinks (nur http/https)
function Open-WebLink {
    param($url)
    try {
        if (-not [string]::IsNullOrEmpty($url) -and $url -match '^https?://') {
            Start-Process -FilePath $url
            Write-GuiLog -Message "Weblink wird geöffnet: $url" -Type "Info"
        } else {
            Write-GuiLog -Message "Für dieses Modul ist kein gültiger Weblink hinterlegt." -Type "Warning"
        }
    }
    catch {
        Write-GuiLog -Message "Fehler beim Öffnen des Weblinks: $($_.Exception.Message)" -Type "Error"
    }
}

$script:installJob   = $null
$script:installTimer = $null

# Wird vom DispatcherTimer aufgerufen und wertet eine laufende Hintergrund-Installation aus
function Complete-ModuleInstall {
    $job = $script:installJob
    if (-not $job -or -not $job.Handle.IsCompleted) { return }

    if ($script:installTimer) { $script:installTimer.Stop() }
    $script:installJob = $null
    try {
        $output = $job.PowerShell.EndInvoke($job.Handle)
        $success = $false
        foreach ($entry in $output) {
            if ($entry.Type -eq "Result") {
                $success = [bool]$entry.Success
                Write-GuiLog -Message $entry.Message -Type $(if ($success) { "Success" } else { "Error" })
            }
            elseif ($entry.Type -in @("Info", "Warning", "Error", "Success")) {
                Write-GuiLog -Message $entry.Message -Type $entry.Type
            }
        }
        foreach ($err in $job.PowerShell.Streams.Error) {
            Write-GuiLog -Message "$($job.ModuleName): $($err.Exception.Message)" -Type "Warning"
        }
        if (-not $success) {
            Write-GuiLog -Message "Fehler bei der Installation des Moduls $($job.ModuleName)." -Type "Error"
        }
    }
    catch {
        Write-GuiLog -Message "Fehler bei der Installation des Moduls $($job.ModuleName): $($_.Exception.Message)" -Type "Error"
    }
    finally {
        $job.PowerShell.Dispose()
        if ($script:window) { $script:window.Cursor = $null }
        Show-ModuleStatus
    }
}

function Install-ModuleHandler {
    param($buttonSender)
    $button = [System.Windows.Controls.Button]$buttonSender
    $moduleName = $button.Tag.ToString()

    $moduleInfo = $requiredModules | Where-Object { $_.Name -eq $moduleName } | Select-Object -First 1

    if ($moduleInfo) {
        if ($script:installJob) {
            Write-GuiLog -Message "Eine andere Modulinstallation ($($script:installJob.ModuleName)) läuft noch. Bitte warten." -Type "Warning"
            return
        }

        $confirmText = "Modul '$moduleName' (Mindestversion $($moduleInfo.MinVersion)) aus der PowerShell Gallery für den aktuellen Benutzer installieren/aktualisieren?"
        if ($moduleInfo.Deprecated) {
            $confirmText = "Hinweis: '$moduleName' ist von Microsoft abgekündigt (Nachfolger: Microsoft.Graph / Microsoft.Entra) und sollte nur noch für Altskripte verwendet werden.`n`n$confirmText"
        }
        $confirm = [System.Windows.MessageBox]::Show(
            $confirmText,
            "Modul installieren",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-GuiLog -Message "Installation von $moduleName vom Benutzer abgebrochen." -Type "Info"
            return
        }

        Write-GuiLog -Message "Installation von $moduleName wird gestartet (läuft im Hintergrund)..." -Type "Info"
        $button.IsEnabled = $false
        $button.Content = "Installiere..."
        if ($script:window) { $script:window.Cursor = [System.Windows.Input.Cursors]::AppStarting }

        try {
            $ps = [System.Management.Automation.PowerShell]::Create()
            [void]$ps.AddScript($script:InstallModuleScript.ToString()).AddArgument($moduleName).AddArgument([string]$moduleInfo.MinVersion)
            $script:installJob = @{
                PowerShell = $ps
                Handle     = $ps.BeginInvoke()
                ModuleName = $moduleName
            }

            if (-not $script:installTimer) {
                $script:installTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:installTimer.Interval = [TimeSpan]::FromMilliseconds(500)
                $script:installTimer.Add_Tick({ Complete-ModuleInstall })
            }
            $script:installTimer.Start()
        }
        catch {
            $script:installJob = $null
            if ($script:window) { $script:window.Cursor = $null }
            Write-GuiLog -Message "Fehler beim Starten der Installation von ${moduleName}: $($_.Exception.Message)" -Type "Error"
            Show-ModuleStatus
        }
    }
}

# XAML für die GUI (ohne Connect-Funktionen, mit ExecutionPolicy)
$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="PhinIT | easyPSInfo - PowerShell-Modul- &amp; Richtlinien-Manager mit Script-Launcher"
    Height="1000"
    Width="1450"
    WindowStartupLocation="CenterScreen"
    Background="#FFFFFF"
    FontFamily="Segoe UI"
    FontSize="12">
    <Window.Resources>
        <!-- Modern Button Style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#0078D4" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Padding" Value="12,6" />
            <Setter Property="Margin" Value="4" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="MinWidth" Value="80" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#106EBE" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#005A9E" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SmallModernButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="FontSize" Value="10"/>
            <Setter Property="MinWidth" Value="60"/>
        </Style>

        <Style x:Key="ExitButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#D32F2F"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#E57373" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#C62828" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="LinkButton" TargetType="Button" BasedOn="{StaticResource SmallModernButton}">
            <Setter Property="Background" Value="#E8F4FD"/>
            <Setter Property="Foreground" Value="#0078D4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#D0E0F0" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#B0C0D0" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Card Style for GroupBox -->
        <Style x:Key="CardGroupBox" TargetType="GroupBox">
            <Setter Property="BorderBrush" Value="#E0E0E0" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Padding" Value="12,8,12,12" />
            <Setter Property="Margin" Value="0,0,0,10" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GroupBox">
                        <Border Background="White"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <Border Background="#F7F7F7" CornerRadius="8,8,0,0" Padding="10,6" BorderThickness="0,0,0,1" BorderBrush="#E0E0E0">
                                    <ContentPresenter ContentSource="Header"/>
                                </Border>
                                <ContentPresenter Grid.Row="1" Margin="{TemplateBinding Padding}"/>
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Script Button Style -->
        <Style x:Key="ScriptButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#F9F9F9" />
            <Setter Property="Foreground" Value="#333333" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="BorderBrush" Value="#E0E0E0"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="Margin" Value="0,3"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#E3F2FD" />
                                <Setter TargetName="border" Property="BorderBrush" Value="#0078D4"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#BBDEFB" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.6" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScriptListHeaderBorderStyle" TargetType="Border">
            <Setter Property="Background" Value="#E3F2FD"/>
            <Setter Property="Margin" Value="0,10,0,5"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="CornerRadius" Value="3"/>
        </Style>

    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <!-- Header -->
        <Border Grid.Row="0" Background="#FF1C323C" Padding="20,15">
            <StackPanel>
                <TextBlock Text="PhinIT | easyPSInfo - PowerShell-Modul- &amp; Richtlinien-Manager mit Script-Launcher" FontSize="20" FontWeight="SemiBold" Foreground="#e2e2e2"/>
                <TextBlock Text="PowerShell-Module und Ausführungsrichtlinien verwalten | Skripte aus dem gewählten Basisordner starten" FontSize="12" Foreground="#d0e8ff" Margin="0,5,0,0"/>
            </StackPanel>
        </Border>
        <!-- Content with Split Layout -->
        <Grid Grid.Row="1" Margin="15">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2.2*"/>
                <!-- Status area: slightly larger -->
                <ColumnDefinition Width="1*"/>
                <!-- Script selection: 1/3 -->
            </Grid.ColumnDefinitions>
            <!-- Left side - Status area -->
            <Grid Grid.Column="0" Margin="0,0,10,0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <!-- Module Check Section -->
                <GroupBox Grid.Row="0" Header="PowerShell-Module" Style="{StaticResource CardGroupBox}">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <ListView Grid.Row="0" x:Name="lvModules" Margin="0,5,0,10" BorderThickness="1" BorderBrush="#E0E0E0" Height="260">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Modul" Width="320">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <TextBlock Text="{Binding DisplayName}" ToolTip="{Binding ToolTip}" VerticalAlignment="Center">
                                                    <TextBlock.Style>
                                                        <Style TargetType="TextBlock">
                                                            <Style.Triggers>
                                                                <DataTrigger Binding="{Binding Deprecated}" Value="True">
                                                                    <Setter Property="Foreground" Value="#B71C1C"/>
                                                                    <Setter Property="FontStyle" Value="Italic"/>
                                                                </DataTrigger>
                                                            </Style.Triggers>
                                                        </Style>
                                                    </TextBlock.Style>
                                                </TextBlock>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Status" Width="90">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <TextBlock Text="{Binding Status}" ToolTip="{Binding ToolTip}" VerticalAlignment="Center"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Benötigt" DisplayMemberBinding="{Binding MinVersion}" Width="100"/>
                                    <GridViewColumn Header="Installiert" DisplayMemberBinding="{Binding InstalledVersion}" Width="110"/>
                                    <GridViewColumn Header="Aktion" Width="120">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <Button Content="Installieren"
                                                        Style="{StaticResource SmallModernButton}"
                                                        IsEnabled="{Binding InstallEnabled}"
                                                        Tag="{Binding Name}"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Link" Width="90">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <Button Content="Webseite"
                                                        Style="{StaticResource LinkButton}"
                                                        Tag="{Binding Webseite}"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <Button Grid.Row="1" x:Name="btnRefreshModules" Content="Module aktualisieren" Style="{StaticResource ModernButton}" HorizontalAlignment="Left" Width="180" Height="25" Margin="0,5,0,0"/>
                    </Grid>
                </GroupBox>
                <!-- ExecutionPolicy Section -->
                <GroupBox Grid.Row="1" Header="PowerShell-Ausführungsrichtlinien (ExecutionPolicy)" Style="{StaticResource CardGroupBox}">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <ListView Grid.Row="0" x:Name="lvExecutionPolicies" Margin="0,0,0,10" BorderThickness="1" BorderBrush="#E0E0E0" Height="165">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Scope" DisplayMemberBinding="{Binding Description}" Width="330"/>
                                    <GridViewColumn Header="Aktuelle Richtlinie" DisplayMemberBinding="{Binding CurrentPolicy}" Width="150"/>
                                    <GridViewColumn Header="Ändern" Width="400">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <StackPanel Orientation="Horizontal" IsEnabled="{Binding CanModify}">
                                                    <Button Content="Restricted" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="65"/>
                                                    <Button Content="AllSigned" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="65"/>
                                                    <Button Content="RemoteSigned" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="90"/>
                                                    <Button Content="Unrestricted" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="80"/>
                                                    <Button Content="Bypass" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="55"/>
                                                </StackPanel>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <Button Grid.Row="1" x:Name="btnRefreshPolicies" Content="Richtlinien aktualisieren" Style="{StaticResource ModernButton}" HorizontalAlignment="Left" Width="200" Height="25"/>
                    </Grid>
                </GroupBox>
                <!-- Status Log -->
                <GroupBox Grid.Row="2" Header="Status und Protokoll" Style="{StaticResource CardGroupBox}" Margin="0,10,0,0">
                    <TextBox x:Name="txtLog" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                             FontFamily="Consolas" FontSize="11" Background="#1E1E1E" Foreground="#A0D2A0" BorderThickness="0" Padding="5"/>
                </GroupBox>
            </Grid>
            <!-- Right side - Script selection -->
            <GroupBox Grid.Column="1" Header="Verfügbare PowerShell-Skripte" Style="{StaticResource CardGroupBox}" Margin="10,0,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <!-- Basisordner der Skriptsuche -->
                    <StackPanel Grid.Row="0" Orientation="Vertical" Margin="0,0,0,8">
                        <TextBlock Text="Basisordner der Skriptsuche:" FontWeight="SemiBold" Margin="0,0,0,3"/>
                        <TextBox x:Name="txtScriptBase" IsReadOnly="True" Background="#F7F7F7" BorderBrush="#E0E0E0" Padding="4,3"
                                 ToolTip="Aktueller Basisordner; durchsucht werden dieser Ordner und seine Unterordner (max. 5 Ebenen, ohne Logs/Exports/Backups und 'old'-Ordner)."/>
                        <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                            <Button x:Name="btnSelectScriptBase" Content="Ordner wählen…" Style="{StaticResource SmallModernButton}"
                                    ToolTip="Anderen Basisordner für die Skriptsuche auswählen"/>
                            <Button x:Name="btnResetScriptBase" Content="Standard" Style="{StaticResource SmallModernButton}"
                                    ToolTip="Standard-Basisordner wiederherstellen (Repository-Ordner 'src' bzw. Skriptordner)"/>
                        </StackPanel>
                    </StackPanel>
                    <!-- Skriptliste -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,0,0,10">
                        <StackPanel x:Name="spScriptList" Orientation="Vertical" Margin="0,3,0,3">
                            <!-- Script buttons will be added dynamically -->
                        </StackPanel>
                    </ScrollViewer>
                    <!-- Refresh button -->
                    <Button Grid.Row="2" x:Name="btnRefreshScripts"
                            Content="Skriptliste aktualisieren" Style="{StaticResource ModernButton}"
                            Height="32"/>
                </Grid>
            </GroupBox>
        </Grid>
        <!-- Footer with Buttons and Info -->
        <Border Grid.Row="2" Background="#FF1C323C" Padding="20,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Vertical" HorizontalAlignment="Left" VerticalAlignment="Center">
                    <TextBlock Text="www.phinit.de | Andreas Hepp | easyPSInfo  -  Version: 0.0.5  -  Update: 14.10.2026" FontSize="10" Foreground="#d0e8ff"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="btnExit" Content="Beenden" Style="{StaticResource ExitButton}" Width="120" Height="32"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

#############################################
# Teil 2: GUI-Funktionen, Event-Handler und Main Block
#############################################

# Funktion zum Laden der XAML-GUI (benannte Elemente werden als $script:-Variablen bereitgestellt)
function Import-XamlGui {
    try {
        if ([string]::IsNullOrEmpty($xaml)) {
            throw "XAML-Inhalt ist leer."
        }

        $xmlReaderSettings = New-Object System.Xml.XmlReaderSettings
        $xmlReaderSettings.IgnoreWhitespace = $true
        $xmlReaderSettings.IgnoreComments = $true
        $xmlReaderSettings.IgnoreProcessingInstructions = $true

        $reader = $null
        $stringReader = $null

        try {
            $stringReader = New-Object System.IO.StringReader($xaml)
            $reader = [System.Xml.XmlReader]::Create($stringReader, $xmlReaderSettings)

            $window = [System.Windows.Markup.XamlReader]::Load($reader)

            $regex = New-Object System.Text.RegularExpressions.Regex('x:Name="([^"]*)"')
            $nameMatches = $regex.Matches($xaml)

            foreach ($match in $nameMatches) {
                if ($match.Groups.Count -gt 1) {
                    $name = $match.Groups[1].Value
                    $element = $window.FindName($name)

                    if ($null -ne $element) {
                        Set-Variable -Name $name -Value $element -Scope Script
                        if ($script:guiElementNames -notcontains $name) { $script:guiElementNames += $name }
                    }
                }
            }

            return $window
        }
        finally {
            if ($null -ne $reader) { $reader.Close() }
            if ($null -ne $stringReader) { $stringReader.Close() }
        }
    }
    catch {
        Write-AppLog "Fehler beim Laden der XAML-Oberfläche: $($_.Exception.Message)" -Type "Error"
        throw
    }
}

# Prüft, ob ein Ordnername von der Skriptsuche ausgeschlossen ist (Laufzeitordner und "old"-Muster, case-insensitive)
function Test-ScriptFolderExcluded {
    [OutputType([bool])]
    param ([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $false }
    if ($script:ExcludedFolderNames -contains $Name) { return $true }
    foreach ($pattern in $script:ExcludedFolderPatterns) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

# Liefert den Pfad relativ zum Basisordner ('' = Basisordner selbst, $null = liegt außerhalb)
function Get-RelativeFolderPath {
    [OutputType([string])]
    param (
        [string]$BasePath,
        [string]$Path
    )
    if ([string]::IsNullOrEmpty($BasePath) -or [string]::IsNullOrEmpty($Path)) { return $null }
    $separators = [char[]]@('\', '/')
    $normalizedBase = $BasePath.TrimEnd($separators)
    $normalizedPath = $Path.TrimEnd($separators)
    if ([string]::Equals($normalizedBase, $normalizedPath, [System.StringComparison]::OrdinalIgnoreCase)) { return '' }
    if ($normalizedPath.Length -gt $normalizedBase.Length -and
        $normalizedPath.StartsWith($normalizedBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        $normalizedPath[$normalizedBase.Length] -in $separators) {
        return $normalizedPath.Substring($normalizedBase.Length).TrimStart($separators)
    }
    return $null
}

# Prüft, ob ein Ordner ein Tool-Sammelordner ist (Repository-Ordner "src" oder enthält weitere
# Tool-Ordner nach dem Muster <Ordner>\<Ordner>.ps1). Laufwerkswurzeln werden nie verwendet.
function Test-ToolSourceFolder {
    [OutputType([bool])]
    param (
        [string]$Path,
        [string]$ExcludeChildFolder
    )
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    try {
        $dirInfo = New-Object System.IO.DirectoryInfo($Path)
        if (-not $dirInfo.Exists -or $null -eq $dirInfo.Parent) { return $false }
        if ($dirInfo.Name -ieq 'src') { return $true }
        foreach ($child in $dirInfo.GetDirectories()) {
            if ($ExcludeChildFolder -and ((Get-RelativeFolderPath -BasePath $ExcludeChildFolder -Path $child.FullName) -eq '')) { continue }
            if ([System.IO.File]::Exists([System.IO.Path]::Combine($child.FullName, "$($child.Name).ps1"))) { return $true }
        }
    }
    catch {
        Write-Verbose "Ordner '$Path' konnte nicht geprüft werden: $($_.Exception.Message)"
    }
    return $false
}

# Standard-Basisordner der Skriptsuche: liegt das Tool unter <src>\easyPSInfo\easyPSInfo.ps1 und ist <src> ein
# Tool-Sammelordner, wird <src> durchsucht (alle Tools des Repositorys), sonst der eigene Skriptordner.
function Get-DefaultScriptSearchBase {
    [OutputType([string])]
    param ()
    $root = $script:ScriptRoot
    if ([string]::IsNullOrEmpty($root) -or [string]::IsNullOrEmpty($script:ScriptPath)) { return $root }
    try {
        $rootInfo = New-Object System.IO.DirectoryInfo($root)
        $toolName = [System.IO.Path]::GetFileNameWithoutExtension($script:ScriptPath)
        if ($rootInfo.Name -ine $toolName -or $null -eq $rootInfo.Parent) { return $root }
        if (Test-ToolSourceFolder -Path $rootInfo.Parent.FullName -ExcludeChildFolder $rootInfo.FullName) {
            return $rootInfo.Parent.FullName
        }
    }
    catch {
        Write-Verbose "Standard-Basisordner konnte nicht ermittelt werden: $($_.Exception.Message)"
    }
    return $root
}

# Liest einen gespeicherten Basisordner aus %APPDATA%\PhinIT\easyPSInfo\settings.json und validiert ihn
function Get-SavedScriptSearchBase {
    [OutputType([string])]
    param ()
    if (-not $script:SettingsFile -or -not (Test-Path -LiteralPath $script:SettingsFile -PathType Leaf)) { return $null }
    try {
        $settingsInfo = Get-Item -LiteralPath $script:SettingsFile -ErrorAction Stop
        if ($settingsInfo.Length -gt 64KB) { throw "Einstellungsdatei ist unplausibel groß." }
        $settings = Get-Content -LiteralPath $script:SettingsFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $settings -or $settings -is [array] -or -not ($settings.PSObject.Properties.Name -contains 'ScriptSearchBase')) { return $null }
        $savedPath = $settings.ScriptSearchBase
        if ($null -eq $savedPath -or ($savedPath -is [string] -and [string]::IsNullOrWhiteSpace($savedPath))) { return $null }
        if ($savedPath -isnot [string] -or $savedPath.Length -gt 1024 -or
            $savedPath.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0 -or
            -not [System.IO.Path]::IsPathRooted($savedPath)) {
            throw "Gespeicherter Basisordner ist kein gültiger absoluter Pfad."
        }
        if (-not (Test-Path -LiteralPath $savedPath -PathType Container)) {
            Write-AppLog -Message "Gespeicherter Basisordner der Skriptsuche ist nicht mehr erreichbar - Standard wird verwendet." -Type "Warning"
            return $null
        }
        return [System.IO.Path]::GetFullPath($savedPath)
    }
    catch {
        Write-AppLog -Message "Einstellungen konnten nicht gelesen werden ($($_.Exception.Message)) - Standard wird verwendet." -Type "Warning"
        return $null
    }
}

# Speichert den gewählten Basisordner ($null = Standard) in %APPDATA%\PhinIT\easyPSInfo\settings.json
function Save-ScriptSearchBaseSetting {
    param ([string]$Path)
    if (-not $script:SettingsFile) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:SettingsFolder -PathType Container)) {
            New-Item -Path $script:SettingsFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $value = if ([string]::IsNullOrEmpty($Path)) { $null } else { $Path }
        $json = [PSCustomObject]@{ ScriptSearchBase = $value } | ConvertTo-Json
        [System.IO.File]::WriteAllText($script:SettingsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        Write-GuiLog -Message "Einstellung für den Basisordner konnte nicht gespeichert werden: $($_.Exception.Message)" -Type "Warning"
    }
}

# Legt den Basisordner der Skriptsuche fest (-UseDefault = Standard), aktualisiert Anzeige, Einstellung und Liste
function Set-ScriptSearchBase {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$Path,
        [switch]$UseDefault,
        [switch]$NoSave,
        [switch]$NoRefresh
    )
    if ($UseDefault -or [string]::IsNullOrEmpty($Path)) {
        $newBase  = Get-DefaultScriptSearchBase
        $isCustom = $false
    }
    else {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            Write-GuiLog -Message "Der Ordner '$Path' existiert nicht oder ist nicht erreichbar." -Type "Error"
            return
        }
        $newBase  = [System.IO.Path]::GetFullPath($Path)
        $isCustom = $true
    }
    if ([string]::IsNullOrEmpty($newBase)) {
        Write-GuiLog -Message "Kein gültiger Basisordner für die Skriptsuche gefunden." -Type "Error"
        return
    }
    if (-not $PSCmdlet.ShouldProcess($newBase, "Basisordner der Skriptsuche festlegen")) { return }

    $script:ScriptSearchBase         = $newBase
    $script:ScriptSearchBaseIsCustom = $isCustom
    if ($script:txtScriptBase) {
        $script:txtScriptBase.Text = $newBase
        $script:txtScriptBase.ToolTip = if ($isCustom) { "Benutzerdefinierter Basisordner: $newBase" } else { "Standard-Basisordner: $newBase" }
    }
    if (-not $NoSave) {
        Save-ScriptSearchBaseSetting -Path $(if ($isCustom) { $newBase } else { $null })
    }
    Write-GuiLog -Message "Basisordner der Skriptsuche ($(if ($isCustom) { 'benutzerdefiniert' } else { 'Standard' })): $newBase" -Type "Info"
    if (-not $NoRefresh) { Show-ScriptList }
}

# Öffnet einen Ordnerauswahldialog für den Basisordner der Skriptsuche
function Select-ScriptSearchBase {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = "Basisordner für die Skriptsuche auswählen (Unterordner werden bis zu $($script:MaxScriptSearchDepth) Ebenen tief durchsucht)"
        $dialog.ShowNewFolderButton = $false
        if ($script:ScriptSearchBase -and (Test-Path -LiteralPath $script:ScriptSearchBase -PathType Container)) {
            $dialog.SelectedPath = $script:ScriptSearchBase
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrEmpty($dialog.SelectedPath)) {
            Set-ScriptSearchBase -Path $dialog.SelectedPath
        }
        else {
            Write-GuiLog -Message "Ordnerauswahl abgebrochen." -Type "Info"
        }
    }
    catch {
        Write-GuiLog -Message "Fehler bei der Ordnerauswahl: $($_.Exception.Message)" -Type "Error"
    }
    finally {
        $dialog.Dispose()
    }
}

# Ermittelt die zu durchsuchenden Ordner: Basisordner + Unterordner bis $MaxDepth Ebenen (Breitensuche).
# Ausgeschlossene Ordner (inkl. Unterbaum), Junctions/symbolische Links und nicht zugreifbare Ordner werden übersprungen.
function Get-ScriptSearchFolder {
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [string]$BasePath,
        [int]$MaxDepth = 5,
        [int]$MaxFolders = 2000
    )
    $folders = New-Object System.Collections.Generic.List[string]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $inaccessible = 0
    $limitReached = $false

    $baseInfo = New-Object System.IO.DirectoryInfo($BasePath)
    $baseExcluded = Test-ScriptFolderExcluded -Name $baseInfo.Name
    if (-not $baseExcluded) { $folders.Add($baseInfo.FullName) }
    $queue.Enqueue([PSCustomObject]@{ Directory = $baseInfo; Depth = 0 })

    while ($queue.Count -gt 0 -and -not $limitReached) {
        $current = $queue.Dequeue()
        if ($current.Depth -ge $MaxDepth) { continue }
        try {
            $children = $current.Directory.GetDirectories()
        }
        catch {
            $inaccessible++
            continue
        }
        foreach ($child in ($children | Sort-Object -Property Name)) {
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if (Test-ScriptFolderExcluded -Name $child.Name) { continue }
            if ($folders.Count -ge $MaxFolders) {
                $limitReached = $true
                break
            }
            $folders.Add($child.FullName)
            $queue.Enqueue([PSCustomObject]@{ Directory = $child; Depth = $current.Depth + 1 })
        }
    }

    return [PSCustomObject]@{
        Folders      = $folders
        BaseExcluded = $baseExcluded
        Inaccessible = $inaccessible
        LimitReached = $limitReached
    }
}

# Funktion zur Anzeige der Skriptliste (hierarchisch relativ zum Basisordner)
function Show-ScriptList {
    try {
        Write-GuiLog -Message "Verfügbare PowerShell-Skripte werden geladen..." -Type "Info"

        $spScriptList = $script:window.FindName("spScriptList")
        if ($null -eq $spScriptList) {
            Write-GuiLog -Message "Element für die Skriptliste nicht gefunden!" -Type "Error"
            return
        }

        $spScriptList.Children.Clear()

        if ([string]::IsNullOrEmpty($script:ScriptSearchBase)) {
            $script:ScriptSearchBase = Get-DefaultScriptSearchBase
        }
        $searchBase = $script:ScriptSearchBase
        if ([string]::IsNullOrEmpty($script:ScriptPath)) {
            Write-GuiLog -Message "Skriptpfad nicht verfügbar (z.B. Auswahl in der ISE) - '$searchBase' wird als Basis für die Skriptsuche verwendet." -Type "Warning"
        }
        if ([string]::IsNullOrEmpty($searchBase)) {
            Write-GuiLog -Message "Kein gültiger Basisordner für die Skriptsuche gefunden." -Type "Error"
            return
        }
        if (-not (Test-Path -LiteralPath $searchBase -PathType Container -ErrorAction SilentlyContinue)) {
            Write-GuiLog -Message "Basisordner '$searchBase' existiert nicht oder ist nicht erreichbar." -Type "Error"
            return
        }

        $searchResult = Get-ScriptSearchFolder -BasePath $searchBase -MaxDepth $script:MaxScriptSearchDepth -MaxFolders $script:MaxScriptSearchFolders
        if ($searchResult.BaseExcluded) {
            Write-GuiLog -Message "Der Basisordner selbst wird nicht direkt durchsucht, da sein Name einem Ausschlussmuster entspricht." -Type "Warning"
        }
        if ($searchResult.Inaccessible -gt 0) {
            Write-GuiLog -Message "$($searchResult.Inaccessible) Ordner waren nicht zugreifbar und wurden übersprungen." -Type "Warning"
        }
        if ($searchResult.LimitReached) {
            Write-GuiLog -Message "Suche auf $($script:MaxScriptSearchFolders) Ordner begrenzt - bitte einen spezifischeren Basisordner wählen." -Type "Warning"
        }
        Write-GuiLog -Message "Skriptsuche in $($searchResult.Folders.Count) Ordnern (max. $($script:MaxScriptSearchDepth) Ebenen, ohne $($script:ExcludedFolderNames -join '/') und 'old'-Ordner)." -Type "Info"

        $scripts = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        # Das eigene Skript nicht in der Liste anbieten (würde die GUI verschachtelt erneut starten)
        $currentScriptFullName = $script:ScriptPath
        foreach ($folder in $searchResult.Folders) {
            try {
                $folderInfo = New-Object System.IO.DirectoryInfo($folder)
                foreach ($file in $folderInfo.GetFiles("*.ps1")) {
                    # .NET-Platzhalter "*.ps1" trifft unter Windows ggf. auch "*.ps1xml" - Erweiterung exakt prüfen
                    if ($file.Extension -ine ".ps1") { continue }
                    if ($currentScriptFullName -and [string]::Equals($file.FullName, $currentScriptFullName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    $scripts.Add($file)
                }
            }
            catch {
                Write-GuiLog -Message "Fehler bei der Skriptsuche in '$folder': $($_.Exception.Message)" -Type "Warning"
            }
        }

        if ($scripts.Count -eq 0) {
            Write-GuiLog -Message "Keine PowerShell-Skripte gefunden (nach Anwendung der Ausschlüsse)." -Type "Warning"
            $textBlock = New-Object System.Windows.Controls.TextBlock
            $textBlock.Text = "Keine Skripte gefunden."
            $textBlock.Margin = "9"
            $textBlock.Foreground = "Gray"
            $textBlock.FontStyle = "Italic"
            [void]$spScriptList.Children.Add($textBlock)
            return
        }

        # Hierarchische Sortierung: Basisordner zuerst, danach Baumreihenfolge (Ordner direkt gefolgt von seinen Unterordnern)
        $sortedDirectoryGroups = $scripts | Group-Object -Property DirectoryName | Sort-Object -Property {
            $relativePath = Get-RelativeFolderPath -BasePath $searchBase -Path $_.Name
            if ($null -eq $relativePath) { $relativePath = $_.Name }
            (($relativePath -split '[\\/]' | Where-Object { $_ -ne '' }) -join [char]1).ToLowerInvariant()
        }

        foreach ($directoryGroup in $sortedDirectoryGroups) {
            $currentDirectoryPath = $directoryGroup.Name
            $scriptsInDirectory = $directoryGroup.Group | Sort-Object -Property Name
            $buttonLeftMarginValue = 10

            $relativePath = Get-RelativeFolderPath -BasePath $searchBase -Path $currentDirectoryPath
            if ($relativePath -eq '') {
                $headerTextString = "Basisordner ($([System.IO.Path]::GetFileName($searchBase.TrimEnd('\', '/'))))"
            }
            elseif ($null -ne $relativePath) {
                $pathSegments = @($relativePath -split '[\\/]' | Where-Object { $_ -ne '' })
                $currentDepth = $pathSegments.Count
                $headerTextString = ("  " * $currentDepth) + ($pathSegments -join ' -> ')
                $buttonLeftMarginValue = 10 + ($currentDepth * 15)
            }
            else {
                # Fallback für Pfade außerhalb der Basis
                $headerTextString = [System.IO.Path]::GetFileName($currentDirectoryPath)
            }

            $headerBorder = New-Object System.Windows.Controls.Border
            $headerBorder.Background = "#E3F2FD"
            $headerBorder.Margin = "0,10,0,5"
            $headerBorder.Padding = "8,4"
            $headerBorder.CornerRadius = "3"
            $headerBorder.ToolTip = $currentDirectoryPath

            $headerTextElement = New-Object System.Windows.Controls.TextBlock
            $headerTextElement.Text = $headerTextString
            $headerTextElement.FontWeight = "Bold"
            $headerTextElement.FontSize = "10"
            $headerBorder.Child = $headerTextElement
            [void]$spScriptList.Children.Add($headerBorder)

            foreach ($scriptFile in $scriptsInDirectory) {
                $button = New-Object System.Windows.Controls.Button
                $button.Style = $script:window.FindResource("ScriptButtonStyle")
                $button.Tag = $scriptFile.FullName
                $button.Margin = "$($buttonLeftMarginValue),2,5,2"
                $button.ToolTip = $scriptFile.FullName

                $buttonContent = New-Object System.Windows.Controls.StackPanel
                $buttonContent.Orientation = "Vertical"

                $nameText = New-Object System.Windows.Controls.TextBlock
                $nameText.Text = $scriptFile.Name
                $nameText.FontWeight = "SemiBold"
                [void]$buttonContent.Children.Add($nameText)

                try {
                    $scriptFileContent = @(Get-Content -LiteralPath $scriptFile.FullName -TotalCount 20 -ErrorAction SilentlyContinue)
                    $synopsisDirectiveIndex = -1
                    for ($i = 0; $i -lt $scriptFileContent.Count; $i++) {
                        if ($scriptFileContent[$i] -match "\.SYNOPSIS") {
                            $synopsisDirectiveIndex = $i
                            break
                        }
                    }

                    if ($synopsisDirectiveIndex -ne -1) {
                        for ($i = $synopsisDirectiveIndex + 1; $i -lt $scriptFileContent.Count; $i++) {
                            $potentialDescription = $scriptFileContent[$i].Trim()
                            if (-not [string]::IsNullOrWhiteSpace($potentialDescription) -and -not $potentialDescription.StartsWith("#")) {
                                $descText = New-Object System.Windows.Controls.TextBlock
                                $descText.Text = $potentialDescription
                                $descText.TextTrimming = "CharacterEllipsis"
                                $descText.Opacity = 0.7
                                $descText.FontSize = "10"
                                [void]$buttonContent.Children.Add($descText)
                                break
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "SYNOPSIS von '$($scriptFile.Name)' konnte nicht gelesen werden: $($_.Exception.Message)"
                }

                $button.Content = $buttonContent

                $button.Add_Click({
                    param($buttonSender)
                    $scriptPathToExecute = [string]$buttonSender.Tag
                    $scriptFileName = [System.IO.Path]::GetFileName($scriptPathToExecute)
                    $result = [System.Windows.MessageBox]::Show(
                        "Soll das Skript '$scriptFileName' in der aktuellen Sitzung ausgeführt werden?",
                        "Skript ausführen",
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Question)
                    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                        try {
                            Write-GuiLog -Message "Skript wird ausgeführt: $scriptPathToExecute" -Type "Info"
                            [void](Start-MainScript -ScriptPath $scriptPathToExecute -KeepSetupWindowOpen)
                        }
                        catch {
                            Write-GuiLog -Message "Fehler beim Ausführen des Skripts '$scriptFileName': $($_.Exception.Message)" -Type "Error"
                            [void][System.Windows.MessageBox]::Show(
                                "Fehler beim Ausführen des Skripts '$scriptFileName': $($_.Exception.Message)",
                                "Fehler bei der Skriptausführung",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Error)
                        }
                    }
                })
                [void]$spScriptList.Children.Add($button)
            }
        }
        Write-GuiLog -Message "Skriptliste geladen - $($scripts.Count) Skripte gefunden und hierarchisch angezeigt." -Type "Success"
    }
    catch {
        Write-GuiLog -Message "Kritischer Fehler beim Aktualisieren der Skriptliste: $($_.Exception.Message)" -Type "Error"
    }
}

# Startet ein Skript in der aktuellen Sitzung (Hauptfenster bleibt minimiert geöffnet)
function Start-MainScript {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param (
        [string]$ScriptPath,
        [switch]$KeepSetupWindowOpen
    )
    # Gestartete Skripte laufen in einem eigenen Skript-Scope und überschreiben die $script:-Variablen dieses
    # Tools daher nicht. Wurde easyPSInfo jedoch per Dot-Sourcing gestartet, ist sein Skript-Scope der globale
    # Scope - dann könnten $Global:-Zuweisungen des gestarteten Skripts die GUI-Variablen überschreiben.
    # Deshalb werden die GUI-Variablen weiterhin gesichert und anschließend wiederhergestellt.
    $savedGuiVariables = @{}
    foreach ($guiVariableName in (@("window") + $script:guiElementNames)) {
        $existingVar = Get-Variable -Name $guiVariableName -Scope Script -ErrorAction SilentlyContinue
        if ($existingVar) { $savedGuiVariables[$guiVariableName] = $existingVar.Value }
    }
    $mainWindow = $script:window
    $scriptTimer = $null
    try {
        if ([string]::IsNullOrEmpty($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            Write-GuiLog -Message "Skript nicht gefunden: $ScriptPath" -Type "Error"
            return $false
        }
        if (-not $PSCmdlet.ShouldProcess($ScriptPath, "Skript ausführen")) { return $false }
        if ($KeepSetupWindowOpen -and $mainWindow) {
            Write-GuiLog -Message "Hauptfenster bleibt geöffnet (minimiert), damit bestehende Sitzungen erhalten bleiben." -Type "Info"
            $mainWindow.WindowState = [System.Windows.WindowState]::Minimized
            $mainWindow.Title = "$($script:WindowTitle) (Skript läuft...)"
        }

        $scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()
        & $ScriptPath

        return $true
    }
    catch {
        Write-GuiLog -Message "Fehler beim Ausführen des Skripts: $($_.Exception.Message)" -Type "Error"
        return $false
    }
    finally {
        foreach ($guiVariableName in $savedGuiVariables.Keys) {
            Set-Variable -Name $guiVariableName -Value $savedGuiVariables[$guiVariableName] -Scope Script
        }

        if ($scriptTimer) {
            $scriptTimer.Stop()
            Write-GuiLog -Message "Ausführungsdauer des Skripts: $($scriptTimer.Elapsed.ToString())" -Type "Info"
        }

        if ($KeepSetupWindowOpen -and $mainWindow) {
            $mainWindow.WindowState = [System.Windows.WindowState]::Normal
            $mainWindow.Title = $script:WindowTitle
        }
    }
}

# Funktion zum Registrieren der Event-Handler der GUI
function Register-EventHandler {
    try {
        Write-GuiLog -Message "GUI-Ereignishandler werden registriert..." -Type "Info"

        # Button-Ereignisse
        $btnRefreshScripts = $script:window.FindName("btnRefreshScripts")
        if ($btnRefreshScripts) {
            $btnRefreshScripts.Add_Click({ Show-ScriptList })
            Write-GuiLog -Message "Ereignis für 'Skriptliste aktualisieren' registriert." -Type "Info"
        }

        $btnSelectScriptBase = $script:window.FindName("btnSelectScriptBase")
        if ($btnSelectScriptBase) {
            $btnSelectScriptBase.Add_Click({ Select-ScriptSearchBase })
            Write-GuiLog -Message "Ereignis für 'Ordner wählen…' registriert." -Type "Info"
        }

        $btnResetScriptBase = $script:window.FindName("btnResetScriptBase")
        if ($btnResetScriptBase) {
            $btnResetScriptBase.Add_Click({ Set-ScriptSearchBase -UseDefault })
            Write-GuiLog -Message "Ereignis für 'Standard' (Basisordner) registriert." -Type "Info"
        }

        $btnRefreshModules = $script:window.FindName("btnRefreshModules")
        if ($btnRefreshModules) {
            $btnRefreshModules.Add_Click({ Show-ModuleStatus })
            Write-GuiLog -Message "Ereignis für 'Module aktualisieren' registriert." -Type "Info"
        }

        $btnRefreshPolicies = $script:window.FindName("btnRefreshPolicies")
        if ($btnRefreshPolicies) {
            $btnRefreshPolicies.Add_Click({ Show-ExecutionPolicy })
            Write-GuiLog -Message "Ereignis für 'Richtlinien aktualisieren' registriert." -Type "Info"
        }

        $btnExit = $script:window.FindName("btnExit")
        if ($btnExit) {
            $btnExit.Add_Click({ $script:window.Close() })
            Write-GuiLog -Message "Ereignis für 'Beenden' registriert." -Type "Info"
        }

        # Ereignisse der Modul-ListView
        $lvModules = $script:window.FindName("lvModules")
        if ($lvModules) {
            $lvModules.AddHandler(
                [System.Windows.Controls.Button]::ClickEvent,
                [System.Windows.RoutedEventHandler]{
                    $button = $_.OriginalSource -as [System.Windows.Controls.Button]
                    if ($button) {
                        if ($button.Content -eq "Installieren") {
                            Install-ModuleHandler -buttonSender $button
                        }
                        elseif ($button.Content -eq "Webseite") {
                            $webUrl = $button.Tag.ToString()
                            Open-WebLink -url $webUrl
                        }
                    }
                }
            )
            Write-GuiLog -Message "Button-Ereignisse der Modulliste registriert." -Type "Info"
        }

        # Ereignisse der ExecutionPolicy-ListView
        $lvExecutionPolicies = $script:window.FindName("lvExecutionPolicies")
        if ($lvExecutionPolicies) {
            $lvExecutionPolicies.AddHandler(
                [System.Windows.Controls.Button]::ClickEvent,
                [System.Windows.RoutedEventHandler]{
                    $button = $_.OriginalSource -as [System.Windows.Controls.Button]
                    if ($button) {
                        $scope = $button.Tag.ToString()
                        $policy = $button.Content.ToString()

                        # Änderungen nur für bestimmte Scopes zulassen
                        if ($scope -in @("Process", "CurrentUser", "LocalMachine")) {
                            Set-ExecutionPolicyHandler -Scope $scope -Policy $policy
                        }
                        else {
                            Write-GuiLog -Message "$scope kann nicht geändert werden - wird per Gruppenrichtlinie gesteuert bzw. ist schreibgeschützt." -Type "Warning"
                        }
                    }
                }
            )
            Write-GuiLog -Message "Button-Ereignisse der Richtlinienliste registriert." -Type "Info"
        }

        # Hintergrund-Installation beim Schließen sauber beenden
        $script:window.Add_Closed({
            if ($script:installTimer) { $script:installTimer.Stop() }
            if ($script:installJob) {
                try { $script:installJob.PowerShell.Stop(); $script:installJob.PowerShell.Dispose() } catch { Write-Verbose $_.Exception.Message }
                $script:installJob = $null
            }
        })

        Write-GuiLog -Message "Alle Ereignishandler erfolgreich registriert." -Type "Success"
        return $true
    }
    catch {
        Write-GuiLog -Message "Fehler beim Registrieren der Ereignishandler: $($_.Exception.Message)" -Type "Error"
        return $false
    }
}

# Hauptblock zur Initialisierung und Anzeige der GUI
# WPF benötigt einen STA-Thread (Standard in powershell.exe/pwsh.exe, nicht bei -MTA)
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    Write-AppLog "WPF erfordert den STA-Modus. Bitte starten mit: powershell.exe -STA -File `"$($script:ScriptPath)`"" -Type "Error"
    return
}

try {
    Write-AppLog "$($script:AppName) v$($script:AppVersion) wird gestartet (PowerShell $($PSVersionTable.PSVersion))..." -Type "Info"

    # GUI laden
    $script:window = Import-XamlGui
    if (-not $script:window) { throw "GUI konnte nicht geladen werden." }
    $script:WindowTitle = $script:window.Title

    # Module prüfen
    Show-ModuleStatus

    # ExecutionPolicy anzeigen
    Show-ExecutionPolicy

    # Basisordner der Skriptsuche festlegen (gespeicherte Auswahl oder Standard) und Skriptliste laden
    $savedScriptBase = Get-SavedScriptSearchBase
    if ($savedScriptBase) {
        Set-ScriptSearchBase -Path $savedScriptBase -NoSave -NoRefresh
    }
    else {
        Set-ScriptSearchBase -UseDefault -NoSave -NoRefresh
    }
    Show-ScriptList

    # Event-Handler registrieren
    [void](Register-EventHandler)

    Write-AppLog "GUI erfolgreich initialisiert und Event-Handler registriert." -Type "Success"

    # GUI anzeigen
    [void]$script:window.ShowDialog()
}
catch {
    $exception = $_
    $errorMessage = $exception.Exception.Message
    $fullStackTrace = $exception.ToString() # Für detaillierte Protokollierung

    # Allgemeine Fehlerbehandlung
    $lineNumber = $exception.InvocationInfo.ScriptLineNumber
    Write-AppLog -Message "Fehler bei der Ausführung von $($script:AppName) (Zeile $lineNumber): $errorMessage. Details: $fullStackTrace" -Type "Error"
    [void][System.Windows.MessageBox]::Show("Ein unerwarteter Fehler ist aufgetreten: $errorMessage`nDetails finden Sie in den Protokollen ($($script:logFile)).", "$($script:AppName) - Fehler", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
}

