<#
.SYNOPSIS
    easyExecutionPolicy - grafischer Manager für PowerShell Execution Policies.

.DESCRIPTION
    WinForms-GUI zum Anzeigen, Setzen, Sichern und Wiederherstellen der PowerShell
    Execution Policies je Scope (MachinePolicy, UserPolicy, Process, CurrentUser, LocalMachine).
    - MachinePolicy/UserPolicy werden per GPO gesteuert und nur angezeigt (nicht setzbar).
    - Process, CurrentUser und LocalMachine können geändert werden (mit Bestätigung).
    - Beim Start wird automatisch ein Backup erstellt (Arbeitsspeicher + Datei in
      %APPDATA%\easyExecutionPolicy\AutoBackups, die letzten 10 automatischen Backups bleiben erhalten).
    - Backups/Exporte (JSON) können manuell gespeichert, importiert und wiederhergestellt werden;
      importierte Dateien werden validiert (nur gültige Scopes und Policy-Werte).
    Das Skript benötigt Administratorrechte und startet sich bei Bedarf selbst erhöht neu
    (mit demselben PowerShell-Host: Windows PowerShell 5.1 oder PowerShell 7).

.NOTES
    Version: 0.0.4
    Autor:   Andreas Hepp | PhinIT
    Web:     www.phinit.de
    Voraussetzungen: Windows, Windows PowerShell 5.1 oder PowerShell 7.x, Administratorrechte.
#>

# Assembly-Loading für Windows Forms und Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Skriptinformationen (auf Skriptebene erfassen - innerhalb von Funktionen verweist $MyInvocation auf die Funktion)
$script:AppVersion = "0.0.4"
$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrEmpty($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.Path }

# Globale Variablen
$global:currentPolicies = @{}
$global:backupPolicies = @{}
$global:autoBackupPath = Join-Path $env:APPDATA "easyExecutionPolicy\AutoBackups"
$policyOptions = @("Restricted", "AllSigned", "RemoteSigned", "Unrestricted", "Bypass", "Undefined")
# Nur diese Scopes können per Set-ExecutionPolicy gesetzt werden (MachinePolicy/UserPolicy = GPO)
$script:SettableScopes = @("Process", "CurrentUser", "LocalMachine")
$script:MaxBackupFileSize = 1MB

# Hilfsfunktion zum Erstellen des Backup-Verzeichnisses
function Initialize-BackupDirectory {
    if (-not (Test-Path $global:autoBackupPath)) {
        try {
            New-Item -Path $global:autoBackupPath -ItemType Directory -Force | Out-Null
            Write-Host "Backup-Verzeichnis erstellt: $global:autoBackupPath"
        } catch {
            Write-Warning "Konnte Backup-Verzeichnis nicht erstellen: $($_.Exception.Message)"
            $global:autoBackupPath = $env:TEMP
        }
    }
}

# Funktion zur Überprüfung und Anforderung von Administratorrechten
function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $dialogResult = [System.Windows.Forms.MessageBox]::Show("Dieses Skript erfordert Administratorrechte. Möchten Sie es als Administrator neu starten?", "Administratorrechte erforderlich", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)

        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                if ([string]::IsNullOrEmpty($script:ScriptPath) -or -not (Test-Path -LiteralPath $script:ScriptPath)) {
                    throw "Der Skriptpfad konnte nicht ermittelt werden. Bitte das Skript als Datei (.ps1) starten."
                }
                # Denselben PowerShell-Host verwenden (pwsh.exe bei PowerShell 7, sonst powershell.exe)
                $exeName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
                $powershellPath = Join-Path $PSHOME $exeName
                if (-not (Test-Path -LiteralPath $powershellPath)) {
                    $powershellPath = (Get-Process -Id $PID).Path
                }
                # -ExecutionPolicy Bypass gilt nur für den neu gestarteten Prozess (Scope Process)
                $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$($script:ScriptPath)`""
                Start-Process -FilePath $powershellPath -Verb RunAs -ArgumentList $argumentList -ErrorAction Stop
                Write-Host "Die nicht-administrative Instanz wird beendet, da eine neue administrative Instanz gestartet wurde."
                exit
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Fehler beim Neustart des Skripts als Administrator:`n$($_.Exception.Message)", "Fehler beim Neustart", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                Write-Host "Fehler beim Neustart als Administrator. Das Skript wird beendet."
                exit
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Das Skript kann ohne Administratorrechte nicht fortfahren und wird nun beendet.", "Administratorrechte verweigert", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Write-Host "Benutzer hat den Neustart als Administrator abgelehnt. Das Skript wird beendet."
            exit
        }
    }
}

# Function to get current Execution Policies
function Get-CurrentExecutionPolicies {
    $scopes = @("MachinePolicy", "UserPolicy", "Process", "CurrentUser", "LocalMachine")
    foreach ($scope in $scopes) {
        try {
            $policy = Get-ExecutionPolicy -Scope $scope -ErrorAction SilentlyContinue 
            if ($null -eq $policy) {
                $global:currentPolicies[$scope] = "Undefined"
            } else {
                $global:currentPolicies[$scope] = $policy.ToString()
            }
        } catch {
            $global:currentPolicies[$scope] = "Error"
        }
    }
    try {
        $global:currentPolicies["Effective"] = (Get-ExecutionPolicy).ToString()
    } catch {
        $global:currentPolicies["Effective"] = "Error"
    }
}

# Funktion zum Erstellen eines Backups der aktuellen Policies
function Backup-CurrentPolicies {
    param(
        [switch]$SaveToFile,
        [string]$CustomPath
    )
    
    Get-CurrentExecutionPolicies
    $global:backupPolicies = $global:currentPolicies.Clone()
    Write-Host "Backup der aktuellen Execution Policies erstellt (Arbeitsspeicher)."
    
    if ($SaveToFile -or $CustomPath) {
        try {
            Initialize-BackupDirectory
            
            $backupData = @{
                BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ComputerName = $env:COMPUTERNAME
                Username = $env:USERNAME
                BackupType = if ($CustomPath) { "Manual" } else { "Automatic" }
                Policies = $global:currentPolicies
            }
            
            $filePath = if ($CustomPath) { 
                $CustomPath 
            } else { 
                Join-Path $global:autoBackupPath "ExecutionPolicyBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            }
            
            $backupData | ConvertTo-Json -Depth 3 | Out-File -LiteralPath $filePath -Encoding UTF8 -ErrorAction Stop
            Write-Host "Backup gespeichert unter: $filePath"
            
            if (-not $CustomPath) {
                $autoBackups = @(Get-ChildItem -LiteralPath $global:autoBackupPath -Filter "ExecutionPolicyBackup_*.json" -File -ErrorAction SilentlyContinue |
                              Sort-Object LastWriteTime -Descending)
                if ($autoBackups.Count -gt 10) {
                    $autoBackups | Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
                    Write-Host "Alte Backups bereinigt. Behalten: 10"
                }
            }
            
            return $filePath
        } catch {
            Write-Warning "Fehler beim Speichern des Backups: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Backup konnte nicht gespeichert werden:`n$($_.Exception.Message)", "Backup Warnung", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }
    
    return $null
}

# Hilfsfunktion: Text aus nicht vertrauenswürdigen Dateien für die Anzeige entschärfen (Steuerzeichen, Länge)
function Format-SafeText {
    param($Text, [int]$MaxLength = 80)
    if ($null -eq $Text) { return "-" }
    $s = ([string]$Text) -replace '[\x00-\x1F\x7F]', ' '
    if ($s.Length -gt $MaxLength) { $s = $s.Substring(0, $MaxLength) + "..." }
    return $s
}

# Backup-/Exportdatei einlesen und Grundstruktur prüfen (Datei ist nicht vertrauenswürdig)
function Read-PolicyBackupFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) { throw "Der angegebene Pfad ist ein Verzeichnis." }
    if ($item.Length -gt $script:MaxBackupFileSize) { throw "Die Datei ist zu groß ($([math]::Round($item.Length / 1KB)) KB). Maximal erlaubt: $($script:MaxBackupFileSize / 1KB) KB." }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Die Datei ist leer." }
    $content = $raw | ConvertFrom-Json -ErrorAction Stop

    if ($null -eq $content -or $content -is [array] -or -not ($content.PSObject.Properties.Name -contains 'Policies') -or $null -eq $content.Policies) {
        throw "Keine gültige Backup-/Exportdatei: Eigenschaft 'Policies' fehlt."
    }
    return $content
}

# Policies (Hashtable aus dem Arbeitsspeicher oder PSCustomObject aus JSON) validieren.
# Liefert nur gültige, setzbare Scopes mit erlaubten Policy-Werten zurück.
function Get-ValidatedPolicySet {
    param($Policies)

    $valid = [ordered]@{}
    $invalid = New-Object System.Collections.Generic.List[string]
    $entries = @{}

    if ($Policies -is [System.Collections.IDictionary]) {
        foreach ($key in $Policies.Keys) { $entries[[string]$key] = $Policies[$key] }
    } elseif ($null -ne $Policies) {
        foreach ($prop in $Policies.PSObject.Properties) { $entries[$prop.Name] = $prop.Value }
    }

    foreach ($key in $entries.Keys) {
        # Nur informative Einträge (GPO-Scopes, effektive Policy) werden stillschweigend übersprungen
        if (@("MachinePolicy", "UserPolicy", "Effective") -contains $key) { continue }
        if ($script:SettableScopes -notcontains $key) {
            $invalid.Add("Unbekannter Scope '$(Format-SafeText $key 40)' ignoriert.")
        }
    }

    foreach ($scope in $script:SettableScopes) {
        if (-not $entries.ContainsKey($scope)) { continue }
        $value = $entries[$scope]
        if ($null -eq $value -or $value -is [array] -or $value -is [System.Management.Automation.PSCustomObject]) {
            $invalid.Add("Ungültiger Wert für Scope '$scope' ignoriert.")
            continue
        }
        $value = ([string]$value).Trim()
        if ($value -eq "Error" -or $value -eq "") { continue }
        $match = $policyOptions | Where-Object { $_ -eq $value } | Select-Object -First 1
        if (-not $match) {
            $invalid.Add("Ungültige Policy '$(Format-SafeText $value 40)' für Scope '$scope' ignoriert.")
            continue
        }
        $valid[$scope] = $match
    }

    return [pscustomobject]@{ Valid = $valid; Invalid = $invalid }
}

# Setzt die Execution Policy für einen Scope. Gibt einen Hinweistext zurück, wenn die Einstellung
# zwar gespeichert, aber durch einen spezifischeren Scope (GPO oder Process) überschrieben wird.
function Set-ScopeExecutionPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Policy
    )

    if ($script:SettableScopes -notcontains $Scope) { throw "Der Scope '$Scope' kann nicht per Set-ExecutionPolicy gesetzt werden (GPO)." }
    if ($policyOptions -notcontains $Policy) { throw "Ungültige Execution Policy '$Policy'." }

    try {
        # -Force unterdrückt nur die Konsolen-Rückfrage; die Bestätigung erfolgt vorher in der GUI
        Set-ExecutionPolicy -ExecutionPolicy $Policy -Scope $Scope -Force -ErrorAction Stop
        return $null
    } catch {
        if ($_.FullyQualifiedErrorId -like "ExecutionPolicyOverride*") {
            return "Scope '$Scope' wurde auf '$Policy' gesetzt, wird aber durch einen spezifischeren Scope (GPO oder Process) überschrieben."
        }
        throw
    }
}

# Wendet einen validierten Policy-Satz an (jeder Scope einzeln, Fehler brechen nicht den Rest ab)
function Invoke-PolicySet {
    param([System.Collections.IDictionary]$PolicySet)

    Get-CurrentExecutionPolicies
    $errors = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]
    $changed = 0

    foreach ($scope in $script:SettableScopes) {
        if (-not $PolicySet.Contains($scope)) { continue }
        $target = $PolicySet[$scope]
        if ($global:currentPolicies[$scope] -eq $target) { continue }
        try {
            $note = Set-ScopeExecutionPolicy -Scope $scope -Policy $target
            if ($note) { $notes.Add($note); Write-Warning $note }
            $changed++
            Write-Host "Wiederhergestellt: $scope = $target"
        } catch {
            $errors.Add("${scope}: $($_.Exception.Message)")
            Write-Warning "Fehler beim Setzen von '$scope' auf '$target': $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{ Changed = $changed; Errors = $errors; Notes = $notes }
}

# Funktion zum Wiederherstellen der Backup-Policies (Arbeitsspeicher oder Datei)
function Restore-BackupPolicies {
    param(
        [switch]$FromFile,
        [string]$BackupFilePath,
        [string]$DialogTitle = "Backup-Datei zum Wiederherstellen auswählen"
    )

    if ($FromFile -or $BackupFilePath) {
        $filePath = $BackupFilePath
        if (-not $filePath) {
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            try {
                $openFileDialog.Filter = "JSON Backup files (*.json)|*.json|All files (*.*)|*.*"
                $openFileDialog.Title = $DialogTitle
                if (Test-Path -LiteralPath $global:autoBackupPath) { $openFileDialog.InitialDirectory = $global:autoBackupPath }
                if ($openFileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $false }
                $filePath = $openFileDialog.FileName
            } finally {
                $openFileDialog.Dispose()
            }
        }

        try {
            $backupContent = Read-PolicyBackupFile -Path $filePath
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Lesen der Backup-Datei:`n$($_.Exception.Message)", "Restore Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return $false
        }

        $backupDate = if ($backupContent.BackupDate) { $backupContent.BackupDate } else { $backupContent.ExportDate }
        $headerText = "Backup-Details:`n"
        $headerText += "Datei: $(Format-SafeText ([IO.Path]::GetFileName($filePath)) 80)`n"
        $headerText += "Datum: $(Format-SafeText $backupDate 40)`n"
        $headerText += "Computer: $(Format-SafeText $backupContent.ComputerName 40)`n"
        $headerText += "Typ: $(Format-SafeText $backupContent.BackupType 20)`n`n"
        $policiesSource = $backupContent.Policies
    } else {
        if ($global:backupPolicies.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Kein Backup im Arbeitsspeicher verfügbar!`n`nVerwenden Sie 'Aus Datei wiederherstellen' um ein gespeichertes Backup zu laden.", "Restore Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return $false
        }
        $headerText = "Quelle: Backup im Arbeitsspeicher`n`n"
        $policiesSource = $global:backupPolicies
    }

    $validated = Get-ValidatedPolicySet -Policies $policiesSource
    if ($validated.Valid.Count -eq 0) {
        $msg = "Das Backup enthält keine gültigen, setzbaren Execution Policies."
        if ($validated.Invalid.Count -gt 0) { $msg += "`n`n" + (($validated.Invalid | Select-Object -First 10) -join "`n") }
        [System.Windows.Forms.MessageBox]::Show($msg, "Restore Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }

    $confirmText = $headerText + "Folgende Policies werden gesetzt (MachinePolicy/UserPolicy sind GPO-gesteuert und werden nicht verändert):`n"
    foreach ($scope in $validated.Valid.Keys) { $confirmText += "  $scope = $($validated.Valid[$scope])`n" }
    if ($validated.Invalid.Count -gt 0) {
        $confirmText += "`nIgnorierte Einträge:`n  " + (($validated.Invalid | Select-Object -First 10) -join "`n  ") + "`n"
    }
    if (@($validated.Valid.Values | Where-Object { $_ -eq "Unrestricted" -or $_ -eq "Bypass" }).Count -gt 0) {
        $confirmText += "`nWARNUNG: 'Unrestricted' bzw. 'Bypass' kann Sicherheitsrisiken darstellen.`n"
    }
    $confirmText += "`nMöchten Sie diese Policies wiederherstellen?"

    $dialogResult = [System.Windows.Forms.MessageBox]::Show($confirmText, "Backup wiederherstellen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    $result = Invoke-PolicySet -PolicySet $validated.Valid
    Update-PolicyDisplay

    if ($result.Errors.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show("Fehler beim Wiederherstellen:`n" + ($result.Errors -join "`n"), "Restore Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    }
    if ($result.Notes.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show("Hinweis:`n" + ($result.Notes -join "`n"), "Restore", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    return $true
}

# Funktion für manuelles Backup mit Dateiauswahl
function Create-ManualBackup {
    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveFileDialog.Filter = "JSON Backup files (*.json)|*.json|All files (*.*)|*.*"
    $saveFileDialog.Title = "Backup speichern unter..."
    $saveFileDialog.FileName = "ExecutionPolicyBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    Initialize-BackupDirectory
    $saveFileDialog.InitialDirectory = $global:autoBackupPath
    
    $dialogOk = ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
    $chosenPath = $saveFileDialog.FileName
    $saveFileDialog.Dispose()
    if ($dialogOk) {
        $savedPath = Backup-CurrentPolicies -SaveToFile -CustomPath $chosenPath
        if ($savedPath) {
            [System.Windows.Forms.MessageBox]::Show("Backup erfolgreich gespeichert unter:`n$savedPath", "Backup erstellt", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return $true
        }
    }
    return $false
}

# Validierungsfunktion für Policy-Änderungen
function Validate-PolicyChange {
    param($Scope, $NewPolicy, $CurrentPolicy)
    
    if ($NewPolicy -eq "Unrestricted" -or $NewPolicy -eq "Bypass") {
        $result = [System.Windows.Forms.MessageBox]::Show("WARNUNG: Die Policy '$NewPolicy' für Scope '$Scope' kann Sicherheitsrisiken darstellen.`n`nMöchten Sie trotzdem fortfahren?", "Sicherheitswarnung", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    
    return $true
}

Ensure-Admin

# GUI Creation
$mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = "easyExecutionPolicy - Execution Policy Manager v$($script:AppVersion) | PhinIT"
$mainForm.Size = New-Object System.Drawing.Size(820, 450)
$mainForm.StartPosition = "CenterScreen"
$mainForm.FormBorderStyle = 'FixedDialog'
$mainForm.MaximizeBox = $false
$mainForm.MinimizeBox = $false
$mainForm.BackColor = [System.Drawing.Color]::White

# Define Fonts and Colors
$uiFontFamily = "Segoe UI"
$uiFontSizeNormal = 12
$uiFontSizeLarge = 20

$fontNormal = New-Object System.Drawing.Font($uiFontFamily, $uiFontSizeNormal)
$fontBold = New-Object System.Drawing.Font($uiFontFamily, $uiFontSizeNormal, [System.Drawing.FontStyle]::Bold)
$fontHeader = New-Object System.Drawing.Font($uiFontFamily, $uiFontSizeLarge, [System.Drawing.FontStyle]::Bold)

$colorDarkText = [System.Drawing.Color]::FromArgb(28, 28, 28)
$colorAccent = [System.Drawing.Color]::FromArgb(0, 120, 212)
$colorSuccess = [System.Drawing.Color]::FromArgb(16, 124, 16)
$colorWarning = [System.Drawing.Color]::FromArgb(255, 140, 0)
$colorGray = [System.Drawing.Color]::FromArgb(108, 117, 125)

# Menü hinzufügen
$menuStrip = New-Object System.Windows.Forms.MenuStrip
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$fileMenu.Text = "Datei"

$exportMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exportMenuItem.Text = "Konfiguration exportieren..."
$exportMenuItem.Add_Click({ 
    # Export function inline für bessere Referenz
    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveFileDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $saveFileDialog.Title = "Export Execution Policy Konfiguration"
    $saveFileDialog.FileName = "ExecutionPolicy_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    
    if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Get-CurrentExecutionPolicies
            $exportData = @{
                ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ComputerName = $env:COMPUTERNAME
                Username = $env:USERNAME
                Policies = $global:currentPolicies
            }
            $exportData | ConvertTo-Json -Depth 3 | Out-File -LiteralPath $saveFileDialog.FileName -Encoding UTF8 -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show("Konfiguration erfolgreich exportiert nach:`n$($saveFileDialog.FileName)", "Export erfolgreich", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Export: $($_.Exception.Message)", "Export Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }
    $saveFileDialog.Dispose()
})

$importMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$importMenuItem.Text = "Konfiguration importieren..."
$importMenuItem.Add_Click({ 
    # Import function inline
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $openFileDialog.Title = "Import Execution Policy Konfiguration"
    
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            # Gemeinsame, validierte Restore-Logik verwenden (nur gültige Scopes/Policies, Bestätigung)
            if (Restore-BackupPolicies -BackupFilePath $openFileDialog.FileName) {
                $statusLabel.Text = "Konfiguration erfolgreich importiert."
                $statusLabel.ForeColor = $colorSuccess
                [System.Windows.Forms.MessageBox]::Show("Konfiguration erfolgreich importiert!", "Import erfolgreich", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Import: $($_.Exception.Message)", "Import Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }
    $openFileDialog.Dispose()
})

$separatorMenuItem = New-Object System.Windows.Forms.ToolStripSeparator
$exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitMenuItem.Text = "Beenden"
$exitMenuItem.Add_Click({ $mainForm.Close() })

$fileMenu.DropDownItems.AddRange(@($exportMenuItem, $importMenuItem, $separatorMenuItem, $exitMenuItem))

$toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$toolsMenu.Text = "Tools"

$backupMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$backupMenuItem.Text = "Backup erstellen (Datei)"
$backupMenuItem.Add_Click({ 
    if (Create-ManualBackup) {
        $statusLabel.Text = "Manuelles Backup erfolgreich erstellt."
        $statusLabel.ForeColor = $colorSuccess
    }
})

$restoreMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$restoreMenuItem.Text = "Backup wiederherstellen"
$restoreMenuItem.Add_Click({ 
    if (Restore-BackupPolicies) {
        $statusLabel.Text = "Backup erfolgreich wiederhergestellt."
        $statusLabel.ForeColor = $colorSuccess
    }
})

$restoreFromFileMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$restoreFromFileMenuItem.Text = "Aus Datei wiederherstellen..."
$restoreFromFileMenuItem.Add_Click({ 
    if (Restore-BackupPolicies -FromFile) {
        $statusLabel.Text = "Backup aus Datei erfolgreich wiederhergestellt."
        $statusLabel.ForeColor = $colorSuccess
    }
})

$toolsMenu.DropDownItems.AddRange(@($backupMenuItem, $restoreMenuItem, $restoreFromFileMenuItem))
$menuStrip.Items.AddRange(@($fileMenu, $toolsMenu))
$mainForm.MainMenuStrip = $menuStrip
$mainForm.Controls.Add($menuStrip)

# Header Panel
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Size = New-Object System.Drawing.Size($mainForm.ClientSize.Width, 60)
$headerPanel.Location = New-Object System.Drawing.Point(0, $menuStrip.Height)
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(28, 50, 60)
$headerPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$mainForm.Controls.Add($headerPanel)

$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Text = "Execution Policy Manager"
$headerLabel.Font = $fontHeader
$headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(226, 226, 226)
$headerLabel.AutoSize = $true
$headerLabel.Location = New-Object System.Drawing.Point(20, 17)
$headerPanel.Controls.Add($headerLabel)

# Content Panel
$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Location = New-Object System.Drawing.Point(0, ($headerPanel.Location.Y + $headerPanel.Height))
$contentPanel.Size = New-Object System.Drawing.Size($mainForm.ClientSize.Width, ($mainForm.ClientSize.Height - $headerPanel.Height - $menuStrip.Height - 60))
$contentPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$contentPanel.AutoScroll = $true
$mainForm.Controls.Add($contentPanel)

# Footer Panel
$footerPanel = New-Object System.Windows.Forms.Panel
$footerPanel.Size = New-Object System.Drawing.Size($mainForm.ClientSize.Width, 60)
$footerPanel.Location = New-Object System.Drawing.Point(0, ($mainForm.ClientSize.Height - $footerPanel.Height))
$footerPanel.BackColor = [System.Drawing.Color]::White
$footerPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$mainForm.Controls.Add($footerPanel)

# ToolTip Object
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 10000
$toolTip.InitialDelay = 500

# Define Tooltip Texts
$scopeTooltips = @{
    "MachinePolicy" = "Richtlinie für alle Benutzer dieses Computers, typischerweise per GPO gesetzt."
    "UserPolicy"    = "Richtlinie für den aktuellen Benutzer, typischerweise per GPO gesetzt."
    "Process"       = "Richtlinie nur für die aktuelle PowerShell-Sitzung. Geht beim Schließen verloren."
    "CurrentUser"   = "Richtlinie für den aktuellen Benutzer, in der Registry gespeichert (HKCU)."
    "LocalMachine"  = "Standardrichtlinie für alle Benutzer dieses Computers, wenn keine spezifischere Richtlinie greift (HKLM)."
}
$policyExplanationTooltips = @{
    "Restricted"    = "Keine Skripte dürfen ausgeführt werden. PowerShell kann nur im interaktiven Modus verwendet werden."
    "AllSigned"     = "Nur Skripte, die von einem vertrauenswürdigen Herausgeber signiert wurden, können ausgeführt werden."
    "RemoteSigned"  = "Lokal erstellte Skripte können ausgeführt werden. Aus dem Internet heruntergeladene Skripte müssen von einem vertrauenswürdigen Herausgeber signiert sein."
    "Unrestricted"  = "Alle Skripte können ausgeführt werden. Vorsicht: Dies kann unsicher sein."
    "Bypass"        = "Nichts wird blockiert und es gibt keine Warnungen oder Eingabeaufforderungen."
    "Undefined"     = "Es ist keine Ausführungsrichtlinie in diesem Bereich festgelegt. Die Richtlinie eines übergeordneten Bereichs oder die Standardrichtlinie greift."
    "loading..."    = "Die aktuelle Richtlinie wird geladen..."
}

# Create GUI elements - Labels und ComboBoxes
$yPos = 25
$leftMargin = 20
$column1Width = 350
$column2Width = 180
$column3Width = 200
$spacing = 25

$column2XPos = $leftMargin + $column1Width + $spacing
$column3XPos = $column2XPos + $column2Width + $spacing

$scopesToManage = @(
    @{Name="MachinePolicy"; Display="MachinePolicy (GPO - All users)"; Settable=$false},
    @{Name="UserPolicy"; Display="UserPolicy (GPO - Current user)"; Settable=$false},
    @{Name="Process"; Display="Process (Current session only)"; Settable=$true},
    @{Name="CurrentUser"; Display="CurrentUser (Registry HKCU)"; Settable=$true},
    @{Name="LocalMachine"; Display="LocalMachine (Registry HKLM)"; Settable=$true}
)

foreach ($scopeInfo in $scopesToManage) {
    $scopeName = $scopeInfo.Name
    $scopeDisplay = $scopeInfo.Display
    $isSettable = $scopeInfo.Settable

    # Label for Scope name
    $labelScope = New-Object System.Windows.Forms.Label
    $labelScope.Text = "${scopeDisplay}:"
    $labelScope.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $labelScope.Size = New-Object System.Drawing.Size($column1Width, 20)
    $labelScope.Font = $fontNormal
    $labelScope.ForeColor = $colorDarkText
    $labelScope.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $contentPanel.Controls.Add($labelScope)
    if ($scopeTooltips.ContainsKey($scopeName)) {
        $toolTip.SetToolTip($labelScope, $scopeTooltips[$scopeName])
    }

    # Label for current Policy
    $lblCurrentPolicy = New-Object System.Windows.Forms.Label
    $lblCurrentPolicy.Name = "lblCurrent$scopeName"
    $lblCurrentPolicy.Text = "loading..."
    $lblCurrentPolicy.Location = New-Object System.Drawing.Point($column2XPos, $yPos)
    $lblCurrentPolicy.Size = New-Object System.Drawing.Size($column2Width, 20)
    $lblCurrentPolicy.Font = $fontBold
    $lblCurrentPolicy.ForeColor = $colorDarkText
    $lblCurrentPolicy.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $contentPanel.Controls.Add($lblCurrentPolicy)

    # ComboBox or placeholder
    if ($isSettable) {
        $cbPolicy = New-Object System.Windows.Forms.ComboBox
        $cbPolicy.Name = "cb$scopeName"
        $cbPolicy.Location = New-Object System.Drawing.Point($column3XPos, ($yPos - 3))
        $cbPolicy.Size = New-Object System.Drawing.Size($column3Width, 26)
        $cbPolicy.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cbPolicy.Font = $fontNormal
        $policyOptions | ForEach-Object { $cbPolicy.Items.Add($_) } | Out-Null
        $contentPanel.Controls.Add($cbPolicy)
        $toolTip.SetToolTip($cbPolicy, "Wählen Sie hier die neue Richtlinie für '$scopeDisplay'.")
    } else {
        $lblNotSettable = New-Object System.Windows.Forms.Label
        $lblNotSettable.Text = "(Controlled by GPO)"
        $lblNotSettable.Location = New-Object System.Drawing.Point($column3XPos, $yPos)
        $lblNotSettable.Size = New-Object System.Drawing.Size($column3Width, 20)
        $lblNotSettable.Font = $fontNormal
        $lblNotSettable.ForeColor = $colorGray
        $lblNotSettable.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $contentPanel.Controls.Add($lblNotSettable)
        $toolTip.SetToolTip($lblNotSettable, "Diese Richtlinie wird durch GPO verwaltet.")
    }
    $yPos += 31
}

# Separator Line
$yPos += 10
$separatorLine = New-Object System.Windows.Forms.Label
$separatorLine.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
$separatorLine.Size = New-Object System.Drawing.Size(($column1Width + $column2Width + $column3Width + 2 * $spacing), 1)
$separatorLine.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$contentPanel.Controls.Add($separatorLine)
$yPos += 10

# Label for effective Execution Policy
$lblEffectivePolicy = New-Object System.Windows.Forms.Label
$lblEffectivePolicy.Text = "Effective Policy (currently active):"
$lblEffectivePolicy.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
$lblEffectivePolicy.Size = New-Object System.Drawing.Size($column1Width, 20)
$lblEffectivePolicy.Font = $fontNormal
$lblEffectivePolicy.ForeColor = $colorDarkText
$lblEffectivePolicy.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$contentPanel.Controls.Add($lblEffectivePolicy)
$toolTip.SetToolTip($lblEffectivePolicy, "Die effektive Ausführungsrichtlinie für die aktuelle PowerShell-Sitzung.")

$lblEffectivePolicyValue = New-Object System.Windows.Forms.Label
$lblEffectivePolicyValue.Name = "lblEffectivePolicyValue"
$lblEffectivePolicyValue.Text = "loading..."
$lblEffectivePolicyValue.Location = New-Object System.Drawing.Point($column2XPos, $yPos)
$lblEffectivePolicyValue.Size = New-Object System.Drawing.Size(($column2Width + $spacing + $column3Width), 20)
$lblEffectivePolicyValue.Font = $fontBold
$lblEffectivePolicyValue.ForeColor = $colorAccent
$lblEffectivePolicyValue.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$contentPanel.Controls.Add($lblEffectivePolicyValue)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Name = "statusLabel"
$statusLabel.Text = "Ready."
$statusLabel.Location = New-Object System.Drawing.Point($leftMargin, 2)
$statusLabel.Size = New-Object System.Drawing.Size(($footerPanel.Width - 2 * $leftMargin), 22)
$statusLabel.AutoEllipsis = $true
$statusLabel.Font = $fontNormal
$statusLabel.ForeColor = $colorSuccess
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$footerPanel.Controls.Add($statusLabel)

# Buttons
$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "APPLY Selected Policies"
$applyButton.Location = New-Object System.Drawing.Point(($footerPanel.Width - 250 - $leftMargin), 25)
$applyButton.Size = New-Object System.Drawing.Size(250, 28)
$applyButton.Font = $fontBold
$applyButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$applyButton.FlatAppearance.BorderSize = 0
$applyButton.BackColor = $colorAccent
$applyButton.ForeColor = [System.Drawing.Color]::White
$applyButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$footerPanel.Controls.Add($applyButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Location = New-Object System.Drawing.Point($leftMargin, 25)
$refreshButton.Size = New-Object System.Drawing.Size(80, 28)
$refreshButton.Font = $fontNormal
$refreshButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$refreshButton.FlatAppearance.BorderSize = 0
$refreshButton.BackColor = $colorGray
$refreshButton.ForeColor = [System.Drawing.Color]::White
$refreshButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$footerPanel.Controls.Add($refreshButton)

$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = "Backup"
$backupButton.Location = New-Object System.Drawing.Point(($leftMargin + 90), 25)
$backupButton.Size = New-Object System.Drawing.Size(80, 28)
$backupButton.Font = $fontNormal
$backupButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$backupButton.FlatAppearance.BorderSize = 0
$backupButton.BackColor = $colorGray
$backupButton.ForeColor = [System.Drawing.Color]::White
$backupButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$footerPanel.Controls.Add($backupButton)

$restoreButton = New-Object System.Windows.Forms.Button
$restoreButton.Text = "Restore"
$restoreButton.Location = New-Object System.Drawing.Point(($leftMargin + 180), 25)
$restoreButton.Size = New-Object System.Drawing.Size(80, 28)
$restoreButton.Font = $fontNormal
$restoreButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$restoreButton.FlatAppearance.BorderSize = 0
$restoreButton.BackColor = $colorWarning
$restoreButton.ForeColor = [System.Drawing.Color]::White
$restoreButton.Enabled = $false
$restoreButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$footerPanel.Controls.Add($restoreButton)

# ToolTips für Buttons
$toolTip.SetToolTip($applyButton, "Wenden Sie die ausgewählten Richtlinienänderungen an.")
$toolTip.SetToolTip($refreshButton, "Aktualisieren Sie die angezeigten Richtlinienwerte.")
$toolTip.SetToolTip($backupButton, "Erstellt ein Backup der aktuellen Execution Policies (Arbeitsspeicher + Datei in AutoBackups).")
$toolTip.SetToolTip($restoreButton, "Stellt das letzte Backup wieder her.")

# Function to update GUI display
function Update-PolicyDisplay {
    Get-CurrentExecutionPolicies
    $scopes = @("MachinePolicy", "UserPolicy", "Process", "CurrentUser", "LocalMachine")
    for ($i = 0; $i -lt $scopes.Length; $i++) {
        $scopeName = $scopes[$i]
        $label = $contentPanel.Controls.Find("lblCurrent$scopeName", $true)[0]
        $comboBox = $contentPanel.Controls.Find("cb$scopeName", $true)[0]

        if ($label) {
            $currentPolicyValue = $global:currentPolicies[$scopeName]
            $label.Text = $currentPolicyValue
            $label.ForeColor = $colorDarkText
            if ($policyExplanationTooltips.ContainsKey($currentPolicyValue)) {
                $toolTip.SetToolTip($label, $policyExplanationTooltips[$currentPolicyValue])
            }
        }
        if ($comboBox) {
            $policyValueToSelect = $global:currentPolicies[$scopeName]
            $selectedIndex = $policyOptions.IndexOf($policyValueToSelect)
            if ($selectedIndex -eq -1) {
                $selectedIndex = $policyOptions.IndexOf("Undefined")
            }
            $comboBox.SelectedIndex = $selectedIndex
        }
    }
    try {
        $effectivePolicy = Get-ExecutionPolicy
        $lblEffectivePolicyValue = $contentPanel.Controls.Find("lblEffectivePolicyValue", $true)[0]
        if ($lblEffectivePolicyValue) {
            $lblEffectivePolicyValue.Text = $effectivePolicy.ToString()
            $lblEffectivePolicyValue.ForeColor = $colorAccent
            if ($policyExplanationTooltips.ContainsKey($effectivePolicy.ToString())) {
                $toolTip.SetToolTip($lblEffectivePolicyValue, $policyExplanationTooltips[$effectivePolicy.ToString()])
            }
        }
    } catch {
        $lblEffectivePolicyValue = $contentPanel.Controls.Find("lblEffectivePolicyValue", $true)[0]
        if ($lblEffectivePolicyValue) {
            $lblEffectivePolicyValue.Text = "Error retrieving"
            $lblEffectivePolicyValue.ForeColor = [System.Drawing.Color]::Red
        }
    }
}

# Event Handlers
$refreshButton.Add_Click({
    $statusLabel.Text = "Refreshing policies..."
    $statusLabel.ForeColor = $colorWarning
    Update-PolicyDisplay
    $statusLabel.Text = "Policies refreshed."
    $statusLabel.ForeColor = $colorSuccess
})

$backupButton.Add_Click({
    $savedPath = Backup-CurrentPolicies -SaveToFile
    $statusLabel.Text = if ($savedPath) { "Backup erstellt (Arbeitsspeicher + $([IO.Path]::GetFileName($savedPath)))." } else { "Backup der aktuellen Policies erstellt (Arbeitsspeicher)." }
    $statusLabel.ForeColor = $colorSuccess
    $restoreButton.Enabled = $true
})

$restoreButton.Add_Click({
    if (Restore-BackupPolicies) {
        $statusLabel.Text = "Backup erfolgreich wiederhergestellt."
        $statusLabel.ForeColor = $colorSuccess
    }
})

$applyButton.Add_Click({
    $statusLabel.Text = "Validating and applying selected policies..."
    $statusLabel.ForeColor = $colorWarning

    # Geplante Änderungen sammeln (foreach statt ForEach-Object, damit 'continue' korrekt funktioniert)
    $pendingChanges = New-Object System.Collections.Generic.List[object]
    foreach ($scopeInfo in ($scopesToManage | Where-Object { $_.Settable })) {
        $scopeName = $scopeInfo.Name
        $comboBox = $contentPanel.Controls.Find("cb$scopeName", $true)[0]
        if ($comboBox -and $comboBox.SelectedItem) {
            $selectedPolicy = $comboBox.SelectedItem.ToString()
            $currentPolicy = $global:currentPolicies[$scopeName]
            if ($selectedPolicy -ne $currentPolicy) {
                $pendingChanges.Add([pscustomobject]@{ Scope = $scopeName; Current = $currentPolicy; New = $selectedPolicy })
            }
        }
    }

    if ($pendingChanges.Count -eq 0) {
        $statusLabel.Text = "No changes were made to execution policies."
        $statusLabel.ForeColor = $colorAccent
        return
    }

    # Set-ExecutionPolicy wird mit -Force aufgerufen, daher hier eine explizite Bestätigung in der GUI
    $summary = ($pendingChanges | ForEach-Object { "  $($_.Scope): $($_.Current) -> $($_.New)" }) -join "`n"
    $confirm = [System.Windows.Forms.MessageBox]::Show("Folgende Änderungen werden angewendet:`n`n$summary`n`nFortfahren?", "Änderungen bestätigen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Update-PolicyDisplay
        $statusLabel.Text = "Änderungen abgebrochen."
        $statusLabel.ForeColor = $colorAccent
        return
    }

    $changesMade = $false
    $errorOccurred = $false
    $overrideNotes = New-Object System.Collections.Generic.List[string]

    foreach ($change in $pendingChanges) {
        $scopeName = $change.Scope
        $selectedPolicy = $change.New
        if (-not (Validate-PolicyChange -Scope $scopeName -NewPolicy $selectedPolicy -CurrentPolicy $change.Current)) {
            continue
        }

        try {
            Write-Host "Setting ExecutionPolicy for Scope '$scopeName' to '$selectedPolicy'..."
            # Auch 'Undefined' über Set-ExecutionPolicy setzen: funktioniert für Windows PowerShell (Registry)
            # und PowerShell 7 (powershell.config.json) gleichermaßen
            $note = Set-ScopeExecutionPolicy -Scope $scopeName -Policy $selectedPolicy
            if ($note) {
                $overrideNotes.Add($note)
                Write-Warning $note
            }
            $changesMade = $true
            Write-Host "Successfully processed Scope '$scopeName' for policy '$selectedPolicy'."
        } catch {
            $errorMessage = "Error for Scope ${scopeName}: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
            $statusLabel.Text = $errorMessage
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            $errorOccurred = $true
            Write-Warning "Error setting ExecutionPolicy for Scope '$scopeName' to '$selectedPolicy': $($_.Exception.Message)"
        }
    }

    Update-PolicyDisplay

    if ($errorOccurred) {
        # Status bereits gesetzt im Catch-Block
    } elseif ($overrideNotes.Count -gt 0) {
        $statusLabel.Text = "Policies gesetzt, aber teilweise durch einen spezifischeren Scope überschrieben."
        $statusLabel.ForeColor = $colorWarning
        [System.Windows.Forms.MessageBox]::Show("Hinweis:`n" + ($overrideNotes -join "`n"), "Execution Policy", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } elseif ($changesMade) {
        $statusLabel.Text = "Execution policies successfully applied."
        $statusLabel.ForeColor = $colorSuccess
    } else {
        $statusLabel.Text = "No changes were made to execution policies."
        $statusLabel.ForeColor = $colorAccent
    }
})

# On Form Load
$mainForm.Add_Load({
    $mainForm.BeginInvoke([Action]{ 
        Update-PolicyDisplay
        # Automatisches Start-Backup (Arbeitsspeicher + Datei in AutoBackups, Rotation: 10 Dateien)
        Backup-CurrentPolicies -SaveToFile | Out-Null
        $restoreButton.Enabled = $true
        $statusLabel.Text = "Ready. Initial backup created."
        $statusLabel.ForeColor = $colorSuccess
    })
})

# Show GUI
$mainForm.ShowDialog() | Out-Null

# Clean up
$mainForm.Dispose()
