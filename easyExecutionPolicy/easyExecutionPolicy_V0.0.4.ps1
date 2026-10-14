# Assembly-Loading für Windows Forms und Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Globale Variablen
$global:currentPolicies = @{}
$global:backupPolicies = @{}
$global:autoBackupPath = "$env:APPDATA\easyExecutionPolicy\AutoBackups"
$policyOptions = @("Restricted", "AllSigned", "RemoteSigned", "Unrestricted", "Bypass", "Undefined")

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
                $powershellPath = (Get-Command PowerShell).Source
                $argumentList = "-File `"$($MyInvocation.MyCommand.Path)`""
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
                "$global:autoBackupPath\ExecutionPolicyBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            }
            
            $backupData | ConvertTo-Json -Depth 3 | Out-File -FilePath $filePath -Encoding UTF8
            Write-Host "Backup gespeichert unter: $filePath"
            
            if (-not $CustomPath) {
                $autoBackups = Get-ChildItem -Path $global:autoBackupPath -Filter "ExecutionPolicyBackup_*.json" | 
                              Sort-Object CreationTime -Descending
                if ($autoBackups.Count -gt 10) {
                    $autoBackups | Select-Object -Skip 10 | Remove-Item -Force
                    Write-Host "Alte Backups bereinigt. Behalten: 10"
                }
            }
            
            return $filePath
        } catch {
            Write-Warning "Fehler beim Speichern des Backups: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Backup konnte nicht gespeichert werden:`n$($_.Exception.Message)", "Backup Warnung", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
    
    return $null
}

# Funktion zum Wiederherstellen der Backup-Policies
function Restore-BackupPolicies {
    param(
        [switch]$FromFile,
        [string]$BackupFilePath
    )
    
    if ($FromFile -or $BackupFilePath) {
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "JSON Backup files (*.json)|*.json|All files (*.*)|*.*"
        $openFileDialog.Title = "Backup-Datei zum Wiederherstellen auswählen"
        $openFileDialog.InitialDirectory = $global:autoBackupPath
        
        $filePath = if ($BackupFilePath) {
            $BackupFilePath
        } else {
            if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $openFileDialog.FileName
            } else {
                return $false
            }
        }
        
        try {
            $backupContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json
            $policiesToRestore = $backupContent.Policies
            
            $confirmText = "Backup-Details:`n"
            $confirmText += "Datum: $($backupContent.BackupDate)`n"
            $confirmText += "Computer: $($backupContent.ComputerName)`n"
            $confirmText += "Typ: $($backupContent.BackupType)`n`n"
            $confirmText += "Möchten Sie diese Policies wiederherstellen?"
            
            $dialogResult = [System.Windows.Forms.MessageBox]::Show($confirmText, "Backup wiederherstellen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Lesen der Backup-Datei:`n$($_.Exception.Message)", "Restore Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return $false
        }
    } else {
        if ($global:backupPolicies.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Kein Backup im Arbeitsspeicher verfügbar!`n`nVerwenden Sie 'Aus Datei wiederherstellen' um ein gespeichertes Backup zu laden.", "Restore Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return $false
        }
        
        $policiesToRestore = $global:backupPolicies
        $dialogResult = [System.Windows.Forms.MessageBox]::Show("Möchten Sie wirklich alle Execution Policies auf den Backup-Stand (Arbeitsspeicher) zurücksetzen?", "Restore bestätigen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    }
    
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            $settableScopes = @("Process", "CurrentUser", "LocalMachine")
            foreach ($scope in $settableScopes) {
                if ($policiesToRestore.PSObject.Properties.Name -contains $scope) {
                    $backupPolicy = $policiesToRestore.$scope
                    if ($backupPolicy -and $backupPolicy -ne "Undefined" -and $backupPolicy -ne "Error") {
                        Set-ExecutionPolicy -ExecutionPolicy $backupPolicy -Scope $scope -Force -ErrorAction Stop
                    }
                    Write-Host "Wiederhergestellt: $scope = $backupPolicy"
                }
            }
            Update-PolicyDisplay
            return $true
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Wiederherstellen: $($_.Exception.Message)", "Restore Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return $false
        }
    }
    return $false
}

# Funktion für manuelles Backup mit Dateiauswahl
function Create-ManualBackup {
    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveFileDialog.Filter = "JSON Backup files (*.json)|*.json|All files (*.*)|*.*"
    $saveFileDialog.Title = "Backup speichern unter..."
    $saveFileDialog.FileName = "ExecutionPolicyBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $saveFileDialog.InitialDirectory = $global:autoBackupPath
    
    if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $savedPath = Backup-CurrentPolicies -SaveToFile -CustomPath $saveFileDialog.FileName
        if ($savedPath) {
            [System.Windows.Forms.MessageBox]::Show("Backup erfolgreich gespeichert unter:`n$savedPath", "Backup erstellt", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
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
$mainForm.Text = "Execution Policy Manager v0.0.3"
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
            $exportData = @{
                ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ComputerName = $env:COMPUTERNAME
                Username = $env:USERNAME
                Policies = $global:currentPolicies
            }
            $exportData | ConvertTo-Json -Depth 3 | Out-File -FilePath $saveFileDialog.FileName -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("Konfiguration erfolgreich exportiert nach:`n$($saveFileDialog.FileName)", "Export erfolgreich", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Export: $($_.Exception.Message)", "Export Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
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
            $importContent = Get-Content -Path $openFileDialog.FileName -Raw | ConvertFrom-Json
            $result = [System.Windows.Forms.MessageBox]::Show("Import von '$($importContent.ComputerName)' ($($importContent.ExportDate))?`n`nNur änderbare Scopes werden importiert.", "Import bestätigen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                $settableScopes = @("Process", "CurrentUser", "LocalMachine")
                foreach ($scope in $settableScopes) {
                    if ($importContent.Policies.PSObject.Properties.Name -contains $scope) {
                        $policyValue = $importContent.Policies.$scope
                        if ($policyValue -and $policyValue -ne "Undefined" -and $policyValue -ne "Error") {
                            Set-ExecutionPolicy -ExecutionPolicy $policyValue -Scope $scope -Force
                        }
                    }
                }
                Update-PolicyDisplay
                [System.Windows.Forms.MessageBox]::Show("Konfiguration erfolgreich importiert!", "Import erfolgreich", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Import: $($_.Exception.Message)", "Import Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
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
$statusLabel.Location = New-Object System.Drawing.Point($leftMargin, 5)
$statusLabel.Size = New-Object System.Drawing.Size(($footerPanel.Width - 2 * $leftMargin), 15)
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
$toolTip.SetToolTip($backupButton, "Erstellt ein Backup der aktuellen Execution Policies.")
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
    Backup-CurrentPolicies
    $statusLabel.Text = "Backup der aktuellen Policies erstellt."
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

    $changesMade = $false
    $errorOccurred = $false

    $scopesToManage | Where-Object {$_.Settable} | ForEach-Object {
        $scopeName = $_.Name
        $comboBox = $contentPanel.Controls.Find("cb$scopeName", $true)[0]
        if ($comboBox -and $comboBox.SelectedItem) {
            $selectedPolicy = $comboBox.SelectedItem.ToString()
            $currentPolicy = $global:currentPolicies[$scopeName] 

            if ($selectedPolicy -ne $currentPolicy) {
                if (-not (Validate-PolicyChange -Scope $scopeName -NewPolicy $selectedPolicy -CurrentPolicy $currentPolicy)) {
                    continue
                }
                
                try {
                    Write-Host "Setting ExecutionPolicy for Scope '$scopeName' to '$selectedPolicy'..."
                    if ($selectedPolicy -eq "Undefined") {
                        if ($scopeName -eq "Process") {
                            Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope $scopeName -Force -ErrorAction Stop
                        } else {
                            $registryPath = switch ($scopeName) {
                                "CurrentUser" { "HKCU:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" }
                                "LocalMachine" { "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" }
                                default { "" }
                            }
                            
                            if ($registryPath -and (Test-Path $registryPath)) {
                                if (Get-ItemProperty -Path $registryPath -Name "ExecutionPolicy" -ErrorAction SilentlyContinue) {
                                    Remove-ItemProperty -Path $registryPath -Name "ExecutionPolicy" -Force -ErrorAction Stop
                                    Write-Host "Removed ExecutionPolicy registry value for Scope '$scopeName'."
                                }
                            }
                        }
                    } else {
                        Set-ExecutionPolicy -ExecutionPolicy $selectedPolicy -Scope $scopeName -Force -ErrorAction Stop
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
        }
    }

    Update-PolicyDisplay

    if ($errorOccurred) {
        # Status bereits gesetzt im Catch-Block
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
        Backup-CurrentPolicies
        $restoreButton.Enabled = $true
        $statusLabel.Text = "Ready. Initial backup created."
        $statusLabel.ForeColor = $colorSuccess
    })
})

# Show GUI
$mainForm.ShowDialog() | Out-Null

# Clean up
$mainForm.Dispose()
