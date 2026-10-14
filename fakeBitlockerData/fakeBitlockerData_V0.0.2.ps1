[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(HelpMessage = "Modus: Create, Verify oder Clean.")]
    [ValidateSet('Create', 'Verify', 'Clean')]
    [string]$Mode,

    [Parameter(HelpMessage = "Datentyp: All, Bitlocker, LAPS oder WindowsLAPS.")]
    [ValidateSet('All', 'Bitlocker', 'LAPS', 'WindowsLAPS')]
    [string]$DataType,

    [Parameter(HelpMessage = "Anzahl der zu bearbeitenden Computer im Create-Modus.")]
    [int]$Count = 10,

    [Parameter(HelpMessage = "Die BitLocker-Laufwerke, für die Daten erstellt werden sollen.")]
    [string[]]$Volumes = @('C:', 'D:'),

    [Parameter(HelpMessage = "Die OU, in der nach Computern gesucht werden soll (DistinguishedName).")]
    [string]$SearchBase,

    [Parameter(HelpMessage = "Pfad für die CSV-Exportdatei.")]
    [string]$OutputFile,

    [Parameter(HelpMessage = "Unterdrückt die Ausgabe in der Konsole.")]
    [switch]$Quiet
)

#region ── Interaktive Parameterabfrage ─────────────────────────────────────────
if (-not $Quiet) {
    if (-not $PSBoundParameters.ContainsKey('Mode')) {
        $title = 'Aktionsmodus auswählen'
        $msg = 'Welche Aktion soll ausgeführt werden?'
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            '&Create (Fake-Daten erstellen)',
            '&Verify (Erstellte Daten prüfen)',
            '&Clean (Fake-Daten entfernen)'
        )
        $choiceId = $Host.UI.PromptForChoice($title, $msg, $choices, 0)
        $Mode = ($choices[$choiceId].Label -split ' ')[0].Replace('&','')
    }

    if (-not $PSBoundParameters.ContainsKey('DataType')) {
        $title = 'Datentyp auswählen'
        $msg = 'Welche Art von Daten soll verarbeitet werden?'
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            '&All',
            '&Bitlocker',
            '&LAPS',
            '&WindowsLAPS'
        )
        $choiceId = $Host.UI.PromptForChoice($title, $msg, $choices, 0)
        $DataType = $choices[$choiceId].Label.Replace('&','')
    }

    if ($Mode -eq 'Create' -and -not $PSBoundParameters.ContainsKey('Count')) {
        do {
            $countInput = Read-Host "Wie viele Computer sollen bearbeitet werden? (Standard: $Count)"
            if ([string]::IsNullOrWhiteSpace($countInput)) { $countInput = $Count; $valid = $true }
            else { $valid = $countInput -match '^\d+$' -and [int]$countInput -gt 0 }
            if (-not $valid) { Write-Warning "Bitte eine positive Zahl eingeben." }
        } until ($valid)
        $Count = [int]$countInput
    }
}
#endregion

#region ── Hilfsfunktionen ───────────────────────────────────────────────────────
function New-RandomPassword([int]$Length = 15) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%*_{}[],.?/'.ToCharArray()
    -join (Get-Random -Count $Length -InputObject $chars)
}

function New-BitLockerPassword {
    (1..8 | ForEach-Object { Get-Random -Minimum 100000 -Maximum 999999 }) -join '-'
}

function Write-Log($Message, $Color = 'Gray') {
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Get-TargetComputers {
    param(
        [int]$Number,
        [string]$SB,
        [psobject]$Cmdlet
    )
    $pSB = @{}
    if ($SB) { $pSB.SearchBase = $SB }

    try {
        $allComputers = Get-ADComputer -Filter * @pSB -ErrorAction Stop
    } catch {
        Write-Warning "Fehler beim Abrufen von Computern: $_"
        return @()
    }

    if ($Mode -in 'Verify', 'Clean') {
        Write-Log "Modus '$Mode': Bearbeite alle $($allComputers.Count) gefundenen Computer."
        return $allComputers
    }

    if ($allComputers.Count -ge $Number) {
        return $allComputers | Get-Random -Count $Number
    }

    $needed = $Number - $allComputers.Count
    Write-Warning "Nicht genügend Computer gefunden ($($allComputers.Count)/$Number). Erstelle $needed zusätzliche Dummy-Computer..."
    $newComputers = @()
    $targetOU = if ($SB) { $SB } else { (Get-ADDomain).ComputersContainer }

    for ($i = 1; $i -le $needed; $i++) {
        $newName = "FAKE-PC-{0:d5}" -f (Get-Random -Min 1 -Max 99999)
        $params = @{ Name = $newName; SamAccountName = $newName; Path = $targetOU; Enabled = $false; Description = 'Temporärer Dummy-PC für Testdaten' }

        if ($Cmdlet.ShouldProcess($newName, "Erstelle Dummy-Computer in OU '$targetOU'")) {
            try {
                $newComputers += New-ADComputer @params -PassThru -ErrorAction Stop
            } catch {
                Write-Error "Fehler beim Erstellen von Dummy-Computer '$newName': $_"
            }
        }
    }
    return $allComputers + $newComputers
}
#endregion

#region ── Aktionsfunktionen (Create, Verify, Clean) ───────────────────────────

function Invoke-BitLockerAction {
    param(
        $Computer,
        $Cmdlet
    )
    $CN = $Computer.Name
    $results = @()

    foreach ($vol in $Volumes) {
        $cleanVol = $vol.Trim(' :')
        $details = [ordered]@{ Computer = $CN; Volume = $cleanVol; Type = 'Bitlocker' }

        switch ($Mode) {
            'Create' {
                $pwd = New-BitLockerPassword
                $details.Password = $pwd
                if ($Cmdlet.ShouldProcess($Computer.DistinguishedName, "Schreibe BitLocker-Daten für Volume $cleanVol")) {
                    try {
                        $recoveryObjectName = "CN=$(Get-Date -f yyyyMMddHHmmss)-{$(New-Guid)}"
                        New-ADObject -Name $recoveryObjectName -Type 'msFVE-RecoveryInformation' -Path $Computer.DistinguishedName -OtherAttributes @{ 'ms-FVE-RecoveryPassword' = $pwd } -ErrorAction Stop
                        $details.Success = $true
                    } catch {
                        $details.Success = $false
                        $details.Error = "FEHLER: Konnte BitLocker-Objekt nicht erstellen: $_"
                    }
                }
            }
            'Verify' {
                try {
                    $recoveryObjects = Get-ADObject -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -SearchBase $Computer.DistinguishedName -SearchScope OneLevel -Properties 'ms-FVE-RecoveryPassword'
                    if ($recoveryObjects) {
                        $details.Success = $true
                        $details.Found = $recoveryObjects.Count
                        if ($recoveryObjects.'ms-FVE-RecoveryPassword') {
                            $details.Password = $recoveryObjects[0].'ms-FVE-RecoveryPassword'
                        }
                    } else {
                        $details.Success = $false
                        $details.Error = "Keine BitLocker-Wiederherstellungsschlüssel gefunden."
                    }
                } catch {
                    $details.Success = $false
                    $details.Error = $_.Exception.Message
                }
            }
            'Clean' {
                 if ($Cmdlet.ShouldProcess($Computer.DistinguishedName, "Entferne BitLocker-Daten")) {
                    try {
                        $objects = Get-ADObject -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -SearchBase $Computer.DistinguishedName -SearchScope OneLevel
                        if ($objects) {
                            $objects | Remove-ADObject -Confirm:$false -ErrorAction Stop
                            $details.Success = $true
                            $details.Removed = $objects.Count
                        } else {
                            $details.Success = $true
                            $details.Removed = 0
                        }
                    } catch {
                        $details.Success = $false
                        $details.Error = $_.Exception.Message
                    }
                 }
            }
        }
        $results += [pscustomobject]$details
    }
    return $results
}

function Invoke-LapsAction {
    param(
        $Computer,
        $Cmdlet,
        [bool]$IsWindowsLaps
    )
    $CN = $Computer.Name
    $lapsType = if ($IsWindowsLaps) { 'WindowsLAPS' } else { 'LAPS' }
    $details = [ordered]@{ Computer = $CN; Type = $lapsType }

    $pwdAttr = if ($IsWindowsLaps) { 'msLAPS-Password' } else { 'ms-Mcs-AdmPwd' }
    $expiryAttr = if ($IsWindowsLaps) { 'msLAPS-PasswordExpirationTime' } else { 'ms-Mcs-AdmPwdExpirationTime' }
    $officialAttrs = @($pwdAttr, $expiryAttr)

    switch ($Mode) {
        'Create' {
            $pwd = New-RandomPassword
            $details.Password = $pwd
            if ($Cmdlet.ShouldProcess($CN, "Schreibe $lapsType-Daten")) {
                try {
                    $props = if ($IsWindowsLaps) {
                        @{ $pwdAttr = $pwd; $expiryAttr = [int64](([datetimeoffset](Get-Date).AddDays(30)).ToUnixTimeSeconds()) }
                    } else {
                        @{ $pwdAttr = $pwd; $expiryAttr = (Get-Date).AddDays(30).ToFileTimeUtc() }
                    }
                    
                    # Schreibe Attribute
                    Set-ADComputer $Computer -Replace $props -ErrorAction Stop
                    
                    # Überprüfe, ob die Attribute erfolgreich geschrieben wurden
                    $verifyComputer = Get-ADComputer $Computer -Properties $officialAttrs -ErrorAction Stop
                    if ($verifyComputer.$pwdAttr -and $verifyComputer.$expiryAttr) {
                        $details.Success = $true
                    } else {
                        $details.Success = $false
                        $details.Error = "FEHLER: $lapsType-Attribute wurden nicht korrekt gesetzt."
                    }
                } catch {
                    $details.Success = $false
                    $details.Error = "FEHLER: Konnte $lapsType-Attribute nicht schreiben: $_"
                }
            }
        }
        'Verify' {
            try {
                $properties = @('Name') + $officialAttrs
                $adComputer = Get-ADComputer $Computer -Properties $properties
                if ($adComputer.$pwdAttr) {
                    $details.Success = $true
                    $details.Password = $adComputer.$pwdAttr
                    if ($adComputer.$expiryAttr) {
                        if ($IsWindowsLaps) {
                            $unixTime = $adComputer.$expiryAttr
                            $details.Expiry = [DateTimeOffset]::FromUnixTimeSeconds($unixTime).DateTime
                        } else {
                            $fileTime = $adComputer.$expiryAttr
                            $details.Expiry = [datetime]::FromFileTimeUtc($fileTime)
                        }
                    }
                } else {
                    $details.Success = $false
                    $details.Error = "Kein $lapsType-Passwort gefunden."
                }
            } catch {
                $details.Success = $false
                $details.Error = $_.Exception.Message
            }
        }
        'Clean' {
            if ($Cmdlet.ShouldProcess($CN, "Entferne $lapsType-Daten")) {
                try {
                    Set-ADComputer $Computer -Clear $officialAttrs -ErrorAction Stop
                    
                    # Überprüfe, ob die Attribute erfolgreich entfernt wurden
                    $verifyComputer = Get-ADComputer $Computer -Properties $officialAttrs -ErrorAction Stop
                    if (-not $verifyComputer.$pwdAttr -and -not $verifyComputer.$expiryAttr) {
                        $details.Success = $true
                    } else {
                        $details.Success = $false
                        $details.Error = "FEHLER: $lapsType-Attribute wurden nicht vollständig entfernt."
                    }
                } catch {
                    $details.Success = $false
                    $details.Error = $_.Exception.Message
                }
            }
        }
    }
    return [pscustomobject]$details
}

#endregion

#region ── Hauptlogik ───────────────────────────────────────────────────────────
$targets = Get-TargetComputers -Number $Count -SB $SearchBase -Cmdlet $PSCmdlet
$results = @()

$targetCount = if ($targets) { $targets.Count } else { 0 }
if ($targetCount -eq 0) {
    Write-Warning "Keine Zielcomputer gefunden oder erstellt. Breche ab."
    return
}

$confirmationPrompt = "`nZusammenfassung:`n  - Aktion: $Mode`n  - Datentyp: $DataType`n  - Zielcomputer: $targetCount"
if ($Mode -eq 'Create' -and $DataType -in 'Bitlocker', 'All') {
    $confirmationPrompt += "`n  - BitLocker-Laufwerke: $($Volumes -join ', ')"
}

if (-not $Quiet -and -not $PSCmdlet.ShouldContinue($confirmationPrompt, "Soll die Aktion ausgeführt werden?")) {
    Write-Warning "Aktion vom Benutzer abgebrochen."
    return
}

Write-Log "Starte Modus '$Mode' für '$DataType' auf $($targets.Count) Computern..." 'Cyan'

foreach ($c in $targets) {
    if ($DataType -in 'Bitlocker', 'All')   { $results += Invoke-BitLockerAction -Computer $c -Cmdlet $PSCmdlet }
    if ($DataType -in 'LAPS', 'All')        { $results += Invoke-LapsAction -Computer $c -Cmdlet $PSCmdlet -IsWindowsLaps $false }
    if ($DataType -in 'WindowsLAPS', 'All') { $results += Invoke-LapsAction -Computer $c -Cmdlet $PSCmdlet -IsWindowsLaps $true }
}

if ($results) {
    $results | Format-Table -AutoSize
}
#endregion

#region ── CSV-Export ────────────────────────────────────────────────────────────
if ($results -and -not $WhatIfPreference) {
    if (-not $OutputFile) {
        $logDir = Join-Path (Split-Path $PSCommandPath -Parent) 'Logs'
        if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory | Out-Null }
        $OutputFile = Join-Path $logDir ("FakeADData_{0}_{1}.csv" -f $Mode, (Get-Date -f yyyyMMdd_HHmmss))
    }
    try {
        $results | Export-Csv -Path $OutputFile -Encoding UTF8 -NoTypeInformation
        Write-Log "Ergebnis-CSV gespeichert unter: $OutputFile" 'Green'
    } catch {
        Write-Warning "CSV-Export fehlgeschlagen: $_"
    }
}
#endregion
