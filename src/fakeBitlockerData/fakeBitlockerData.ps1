#requires -Version 5.1
#requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Erstellt, prüft und entfernt Fake-BitLocker- und Fake-LAPS-Daten im Active Directory (NUR für Test-/Laborumgebungen).

.DESCRIPTION
    !!! WARNUNG: NUR FÜR TEST- UND LABORUMGEBUNGEN !!!
    Dieses Skript schreibt künstliche Daten in das Active Directory. Niemals in einer Produktionsumgebung ausführen!

    Funktionen:
      - Create : Erstellt Fake-BitLocker-Wiederherstellungsobjekte (msFVE-RecoveryInformation) unterhalb von
                 Computerobjekten und/oder setzt Fake-Passwörter für Legacy-LAPS (ms-Mcs-AdmPwd) bzw.
                 Windows LAPS (msLAPS-Password, Klartext-JSON). Reichen die vorhandenen Computer nicht aus,
                 werden deaktivierte Dummy-Computer (FAKE-PC-xxxxx) angelegt.
      - Verify : Prüft die vom Skript erzeugten Fake-Daten und zeigt sie an.
      - Clean  : Entfernt ausschließlich die vom Skript erzeugten (markierten) Fake-Daten.

    Sicherheitsmechanismen:
      - Fake-BitLocker-Objekte werden über das Attribut adminDescription mit dem Marker 'PhinIT-FakeTestData'
        gekennzeichnet, Fake-LAPS-Passwörter beginnen mit dem Präfix 'FAKE-'. Verify und Clean berücksichtigen
        nur so markierte Daten – echte BitLocker-/LAPS-Daten werden weder angezeigt, exportiert noch gelöscht.
      - Vorhandene echte LAPS-Passwörter werden im Create-Modus nicht überschrieben.
      - Domänencontroller werden im Create-Modus nicht als Ziel verwendet.
      - Fake-Passwörter werden mit einem kryptografisch sicheren Zufallszahlengenerator erzeugt.
      - -WhatIf und -Confirm werden für alle schreibenden/löschenden AD-Operationen unterstützt.

    Hinweis: Mit älteren Versionen erzeugte, nicht markierte Daten werden von Verify/Clean nicht erkannt.

.PARAMETER Mode
    Aktionsmodus: Create, Verify oder Clean. Im Quiet-Modus Pflicht, sonst interaktive Abfrage.

.PARAMETER DataType
    Datentyp: All, Bitlocker, LAPS (Legacy-LAPS) oder WindowsLAPS. Im Quiet-Modus Pflicht, sonst interaktive Abfrage.

.PARAMETER Count
    Anzahl der zu bearbeitenden Computer im Create-Modus (Standard: 10).

.PARAMETER Volumes
    Laufwerke, für die im Create-Modus BitLocker-Wiederherstellungsdaten erzeugt werden (Standard: C:, D:).

.PARAMETER SearchBase
    DistinguishedName der OU, in der nach Computern gesucht wird. Ohne Angabe wird die gesamte Domäne
    durchsucht; Dummy-Computer werden dann im Standard-Computercontainer angelegt.

.PARAMETER OutputFile
    Pfad der CSV-Exportdatei. Standard: <Skriptordner>\Logs\FakeADData_<Modus>_<Zeitstempel>.csv

.PARAMETER Quiet
    Unterdrückt Konsolenausgaben und alle interaktiven Abfragen (inkl. Sicherheitsabfrage).
    Mode und DataType müssen dann als Parameter angegeben werden.

.EXAMPLE
    .\fakeBitlockerData.ps1
    Interaktiver Start mit Auswahl von Modus, Datentyp und Anzahl.

.EXAMPLE
    .\fakeBitlockerData.ps1 -Mode Create -DataType All -Count 20 -SearchBase 'OU=Testclients,DC=lab,DC=local'
    Erstellt Fake-BitLocker- und Fake-LAPS-Daten für 20 Computer der angegebenen OU.

.EXAMPLE
    .\fakeBitlockerData.ps1 -Mode Clean -DataType All -WhatIf
    Zeigt an, welche Fake-Daten entfernt würden, ohne etwas zu ändern.

.EXAMPLE
    .\fakeBitlockerData.ps1 -Mode Verify -DataType LAPS -Quiet -OutputFile 'C:\Temp\laps.csv'
    Prüft die Fake-LAPS-Daten ohne Konsolenausgabe und exportiert das Ergebnis.

.NOTES
    Version : 0.0.2
    Autor   : Andreas Hepp | PhinIT
    Web     : www.phinit.de
    Voraussetzungen: Windows PowerShell 5.1 oder PowerShell 7, RSAT-Modul ActiveDirectory,
                     Schreibrechte auf die Ziel-Computerobjekte (z. B. Domänen-Admin im Testlab).
    NUR FÜR TEST-/LABORUMGEBUNGEN!
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(HelpMessage = "Modus: Create, Verify oder Clean.")]
    [ValidateSet('Create', 'Verify', 'Clean')]
    [string]$Mode,

    [Parameter(HelpMessage = "Datentyp: All, Bitlocker, LAPS oder WindowsLAPS.")]
    [ValidateSet('All', 'Bitlocker', 'LAPS', 'WindowsLAPS')]
    [string]$DataType,

    [Parameter(HelpMessage = "Anzahl der zu bearbeitenden Computer im Create-Modus.")]
    [ValidateRange(1, 100000)]
    [int]$Count = 10,

    [Parameter(HelpMessage = "Die BitLocker-Laufwerke, für die Daten erstellt werden sollen.")]
    [ValidatePattern('^\s*[A-Za-z]:?\s*$')]
    [string[]]$Volumes = @('C:', 'D:'),

    [Parameter(HelpMessage = "Die OU, in der nach Computern gesucht werden soll (DistinguishedName).")]
    [string]$SearchBase,

    [Parameter(HelpMessage = "Pfad für die CSV-Exportdatei.")]
    [string]$OutputFile,

    [Parameter(HelpMessage = "Unterdrückt die Ausgabe in der Konsole und alle interaktiven Abfragen.")]
    [switch]$Quiet
)

#region ── Konstanten ────────────────────────────────────────────────────────────
$script:ScriptVersion      = '0.0.2'
# Kennzeichnung der vom Skript erzeugten Daten – Verify/Clean berücksichtigen nur markierte Daten
$script:FakeMarker         = 'PhinIT-FakeTestData'
$script:FakePasswordPrefix = 'FAKE-'
$script:ResultColumns      = @('Computer', 'Type', 'Volume', 'Success', 'Password', 'Expiry', 'Removed', 'Info', 'Error')
$script:Rng                = [System.Security.Cryptography.RandomNumberGenerator]::Create()
#endregion

#region ── Interaktive Parameterabfrage ─────────────────────────────────────────
if ($Quiet) {
    $missingParams = @()
    if ([string]::IsNullOrEmpty($Mode))     { $missingParams += '-Mode' }
    if ([string]::IsNullOrEmpty($DataType)) { $missingParams += '-DataType' }
    if ($missingParams) {
        throw "Im Quiet-Modus sind keine interaktiven Abfragen möglich. Bitte folgende Parameter angeben: $($missingParams -join ', ')"
    }
} else {
    if ([string]::IsNullOrEmpty($Mode)) {
        $title = 'Aktionsmodus auswählen'
        $msg = 'Welche Aktion soll ausgeführt werden?'
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            '&Create (Fake-Daten erstellen)',
            '&Verify (Erstellte Daten prüfen)',
            'C&lean (Fake-Daten entfernen)'
        )
        $choiceId = $Host.UI.PromptForChoice($title, $msg, $choices, 0)
        $Mode = ($choices[$choiceId].Label -split ' ')[0].Replace('&','')
    }

    if ([string]::IsNullOrEmpty($DataType)) {
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
            $parsedCount = 0
            if ([string]::IsNullOrWhiteSpace($countInput)) { $parsedCount = $Count; $valid = $true }
            else { $valid = [int]::TryParse($countInput.Trim(), [ref]$parsedCount) -and $parsedCount -gt 0 }
            if (-not $valid) { Write-Warning "Bitte eine positive Zahl eingeben." }
        } until ($valid)
        $Count = $parsedCount
    }
}
#endregion

#region ── Hilfsfunktionen ───────────────────────────────────────────────────────
function Get-SecureRandomNumber([int]$MaxExclusive) {
    # Kryptografisch sicherer Zufallswert 0..MaxExclusive-1 (Rejection Sampling gegen Modulo-Bias)
    $range = [long]4294967296
    $limit = $range - ($range % $MaxExclusive)
    $bytes = New-Object byte[] 4
    do {
        $script:Rng.GetBytes($bytes)
        $value = [long][BitConverter]::ToUInt32($bytes, 0)
    } while ($value -ge $limit)
    return [int]($value % $MaxExclusive)
}

function New-RandomPassword([int]$Length = 15) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%*_{}[],.?/'.ToCharArray()
    $randomPart = -join (1..$Length | ForEach-Object { $chars[(Get-SecureRandomNumber $chars.Length)] })
    return $script:FakePasswordPrefix + $randomPart
}

function New-BitLockerPassword {
    # Echtes Format: 8 Blöcke à 6 Ziffern, jeder Block ist ein Vielfaches von 11 (< 720896)
    (1..8 | ForEach-Object { '{0:D6}' -f ((Get-SecureRandomNumber 65536) * 11) }) -join '-'
}

function Write-ScriptLog($Message, $Color = 'Gray') {
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Test-ADSchemaAttribute([string]$Name) {
    try {
        return [bool](Get-ADObject -SearchBase $script:SchemaNC -LDAPFilter "(lDAPDisplayName=$Name)" -ErrorAction Stop)
    } catch {
        Write-Warning "Schemaprüfung für '$Name' fehlgeschlagen: $($_.Exception.Message)"
        return $false
    }
}

function Test-FakeLapsValue($Value) {
    # Erkennt vom Skript erzeugte LAPS-Werte (Klartext oder Windows-LAPS-JSON mit Präfix im Feld "p")
    if ([string]::IsNullOrEmpty([string]$Value)) { return $false }
    return (Get-FakeLapsPassword $Value).StartsWith($script:FakePasswordPrefix, [System.StringComparison]::Ordinal)
}

function Get-FakeLapsPassword($Value) {
    $text = [string]$Value
    if ($text.TrimStart().StartsWith('{')) {
        try {
            $json = $text | ConvertFrom-Json -ErrorAction Stop
            return [string]$json.p
        } catch {
            return $text
        }
    }
    return $text
}

function Get-TargetComputers {
    param(
        [int]$Number,
        [string]$SB,
        [string[]]$LapsAttributes
    )
    $pSB = @{ Filter = '*'; Properties = @('PrimaryGroupID') + @($LapsAttributes); ErrorAction = 'Stop' }
    if ($SB) { $pSB.SearchBase = $SB }

    try {
        $allComputers = @(Get-ADComputer @pSB)
    } catch {
        Write-Warning "Fehler beim Abrufen von Computern: $_"
        return @()
    }

    if ($Mode -in 'Verify', 'Clean') {
        return $allComputers
    }

    # Domänencontroller (516 = DC, 521 = RODC) werden nie mit Fake-Daten beschrieben
    $allComputers = @($allComputers | Where-Object { $_.PrimaryGroupID -notin 516, 521 })
    if ($allComputers.Count -ge $Number) {
        return @($allComputers | Get-Random -Count $Number)
    }
    return $allComputers
}

function New-DummyComputer {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [int]$Needed,
        [string]$SB
    )
    $newComputers = @()
    $targetOU = if ($SB) { $SB } else { (Get-ADDomain).ComputersContainer }

    for ($i = 1; $i -le $Needed; $i++) {
        $newName = "FAKE-PC-{0:d5}" -f (Get-Random -Minimum 1 -Maximum 100000)
        $params = @{ Name = $newName; SamAccountName = $newName; Path = $targetOU; Enabled = $false; Description = "Temporärer Dummy-PC für Testdaten [$($script:FakeMarker)]" }

        if ($PSCmdlet.ShouldProcess($newName, "Erstelle Dummy-Computer in OU '$targetOU'")) {
            try {
                $newComputers += New-ADComputer @params -PassThru -Confirm:$false -ErrorAction Stop
            } catch {
                Write-Error "Fehler beim Erstellen von Dummy-Computer '$newName': $_"
            }
        }
    }
    return $newComputers
}
#endregion

#region ── Aktionsfunktionen (Create, Verify, Clean) ───────────────────────────

function Invoke-BitLockerAction {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $Computer,
        [hashtable]$FakeIndex
    )
    $CN = $Computer.Name
    $DN = $Computer.DistinguishedName
    $results = New-Object System.Collections.Generic.List[object]

    switch ($Mode) {
        'Create' {
            foreach ($vol in $Volumes) {
                $cleanVol = $vol.Trim(' :').ToUpper()
                $details = [ordered]@{ Computer = $CN; Volume = $cleanVol; Type = 'Bitlocker' }
                $fakePassword = New-BitLockerPassword
                $details.Password = $fakePassword
                if ($PSCmdlet.ShouldProcess($DN, "Schreibe Fake-BitLocker-Daten für Volume $cleanVol")) {
                    try {
                        $recoveryGuid = [guid]::NewGuid()
                        # Name im Originalformat: <Zeitstempel mit Offset>{<RecoveryGuid>} – UTC, da ein '+' im RDN escaped werden müsste
                        $recoveryObjectName = '{0}-00:00{{{1}}}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'), $recoveryGuid.ToString().ToUpper()
                        $otherAttributes = @{
                            'msFVE-RecoveryPassword' = $fakePassword
                            'msFVE-RecoveryGuid'     = $recoveryGuid.ToByteArray()
                            'msFVE-VolumeGuid'       = [guid]::NewGuid().ToByteArray()
                            'adminDescription'       = "$($script:FakeMarker);Volume=$cleanVol"
                        }
                        New-ADObject -Name $recoveryObjectName -Type 'msFVE-RecoveryInformation' -Path $DN -OtherAttributes $otherAttributes -Confirm:$false -ErrorAction Stop
                        $details.Success = $true
                    } catch {
                        $details.Success = $false
                        $details.Error = "FEHLER: Konnte BitLocker-Objekt nicht erstellen: $_"
                    }
                }
                $results.Add([pscustomobject]$details)
            }
        }
        'Verify' {
            $objects = $FakeIndex[$DN]
            if ($null -ne $objects -and $objects.Count -gt 0) {
                foreach ($obj in $objects) {
                    $volume = if ([string]$obj.adminDescription -match 'Volume=([^;]+)') { $Matches[1] } else { '' }
                    $results.Add([pscustomobject][ordered]@{ Computer = $CN; Volume = $volume; Type = 'Bitlocker'; Success = $true; Password = $obj.'msFVE-RecoveryPassword' })
                }
            } else {
                $results.Add([pscustomobject][ordered]@{ Computer = $CN; Type = 'Bitlocker'; Success = $false; Error = 'Keine Fake-BitLocker-Wiederherstellungsschlüssel gefunden.' })
            }
        }
        'Clean' {
            $objects = $FakeIndex[$DN]
            if ($null -ne $objects -and $objects.Count -gt 0) {
                foreach ($obj in $objects) {
                    $volume = if ([string]$obj.adminDescription -match 'Volume=([^;]+)') { $Matches[1] } else { '' }
                    $details = [ordered]@{ Computer = $CN; Volume = $volume; Type = 'Bitlocker' }
                    if ($PSCmdlet.ShouldProcess($obj.DistinguishedName, 'Entferne Fake-BitLocker-Objekt')) {
                        try {
                            Remove-ADObject -Identity $obj.DistinguishedName -Confirm:$false -ErrorAction Stop
                            $details.Success = $true
                            $details.Removed = 1
                        } catch {
                            $details.Success = $false
                            $details.Error = $_.Exception.Message
                        }
                    }
                    $results.Add([pscustomobject]$details)
                }
            } else {
                $results.Add([pscustomobject][ordered]@{ Computer = $CN; Type = 'Bitlocker'; Success = $true; Removed = 0; Info = 'Keine Fake-BitLocker-Daten vorhanden.' })
            }
        }
    }
    return $results.ToArray()
}

function Invoke-LapsAction {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $Computer,
        [bool]$IsWindowsLaps
    )
    $CN = $Computer.Name
    $lapsType = if ($IsWindowsLaps) { 'WindowsLAPS' } else { 'LAPS' }
    $details = [ordered]@{ Computer = $CN; Type = $lapsType }

    $pwdAttr = if ($IsWindowsLaps) { 'msLAPS-Password' } else { 'ms-Mcs-AdmPwd' }
    $expiryAttr = if ($IsWindowsLaps) { 'msLAPS-PasswordExpirationTime' } else { 'ms-Mcs-AdmPwdExpirationTime' }
    $officialAttrs = @($pwdAttr, $expiryAttr)
    # Die Attribute wurden bereits mit Get-ADComputer geladen (keine Einzelabfrage je Computer nötig)
    $currentValue = $Computer.$pwdAttr
    $isFake = Test-FakeLapsValue $currentValue

    switch ($Mode) {
        'Create' {
            if (-not [string]::IsNullOrEmpty([string]$currentValue) -and -not $isFake) {
                $details.Success = $false
                $details.Info = "Übersprungen: vorhandenes echtes $lapsType-Passwort wird nicht überschrieben."
                break
            }
            $fakePassword = New-RandomPassword
            $details.Password = $fakePassword
            if ($PSCmdlet.ShouldProcess($CN, "Schreibe Fake-$lapsType-Daten")) {
                try {
                    $now = Get-Date
                    $expiry = $now.AddDays(30).ToFileTimeUtc()
                    $props = if ($IsWindowsLaps) {
                        # Windows LAPS speichert Klartext-Passwörter als JSON, Ablaufzeit als FILETIME
                        $json = [ordered]@{ n = 'Administrator'; t = ('{0:x}' -f $now.ToFileTimeUtc()); p = $fakePassword } | ConvertTo-Json -Compress
                        @{ $pwdAttr = $json; $expiryAttr = $expiry }
                    } else {
                        @{ $pwdAttr = $fakePassword; $expiryAttr = $expiry }
                    }

                    # Schreibe Attribute
                    Set-ADComputer -Identity $Computer.DistinguishedName -Replace $props -Confirm:$false -ErrorAction Stop

                    # Überprüfe, ob die Attribute erfolgreich geschrieben wurden
                    $verifyComputer = Get-ADComputer -Identity $Computer.DistinguishedName -Properties $officialAttrs -ErrorAction Stop
                    if ($verifyComputer.$pwdAttr -and $verifyComputer.$expiryAttr) {
                        $details.Success = $true
                        $details.Expiry = [datetime]::FromFileTimeUtc($expiry)
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
            if ($isFake) {
                $details.Success = $true
                $details.Password = Get-FakeLapsPassword $currentValue
                $expiryValue = $Computer.$expiryAttr
                if ($expiryValue) {
                    try { $details.Expiry = [datetime]::FromFileTimeUtc([int64]$expiryValue) }
                    catch { $details.Info = "Ungültige Ablaufzeit: $expiryValue" }
                }
            } else {
                $details.Success = $false
                $details.Error = "Kein Fake-$lapsType-Passwort gefunden."
                if (-not [string]::IsNullOrEmpty([string]$currentValue)) {
                    $details.Info = 'Echtes Passwort vorhanden (wird nicht angezeigt).'
                }
            }
        }
        'Clean' {
            if (-not $isFake) {
                $details.Success = $true
                $details.Removed = 0
                $details.Info = "Keine Fake-$lapsType-Daten vorhanden (echte Daten bleiben unangetastet)."
                break
            }
            if ($PSCmdlet.ShouldProcess($CN, "Entferne Fake-$lapsType-Daten")) {
                try {
                    Set-ADComputer -Identity $Computer.DistinguishedName -Clear $officialAttrs -Confirm:$false -ErrorAction Stop

                    # Überprüfe, ob die Attribute erfolgreich entfernt wurden
                    $verifyComputer = Get-ADComputer -Identity $Computer.DistinguishedName -Properties $officialAttrs -ErrorAction Stop
                    if (-not $verifyComputer.$pwdAttr -and -not $verifyComputer.$expiryAttr) {
                        $details.Success = $true
                        $details.Removed = 1
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
Write-ScriptLog "Fake BitLocker/LAPS Data v$($script:ScriptVersion) – NUR FÜR TEST-/LABORUMGEBUNGEN!" 'Yellow'

try {
    $script:SchemaNC = (Get-ADRootDSE -ErrorAction Stop).schemaNamingContext
} catch {
    throw "Active Directory ist nicht erreichbar: $($_.Exception.Message)"
}

$doBitLocker = $DataType -in 'Bitlocker', 'All'
$doLaps      = $DataType -in 'LAPS', 'All'
$doWinLaps   = $DataType -in 'WindowsLAPS', 'All'

if ($doLaps -and -not (Test-ADSchemaAttribute 'ms-Mcs-AdmPwd')) {
    Write-Warning "Das AD-Schema enthält keine Legacy-LAPS-Attribute (ms-Mcs-AdmPwd). Legacy-LAPS wird übersprungen."
    $doLaps = $false
}
if ($doWinLaps -and -not (Test-ADSchemaAttribute 'msLAPS-Password')) {
    Write-Warning "Das AD-Schema enthält keine Windows-LAPS-Attribute (msLAPS-Password). Windows LAPS wird übersprungen."
    $doWinLaps = $false
}
if (-not ($doBitLocker -or $doLaps -or $doWinLaps)) {
    Write-Warning "Für den Datentyp '$DataType' ist nichts zu tun. Breche ab."
    return
}

$lapsAttributes = @()
if ($doLaps)    { $lapsAttributes += 'ms-Mcs-AdmPwd', 'ms-Mcs-AdmPwdExpirationTime' }
if ($doWinLaps) { $lapsAttributes += 'msLAPS-Password', 'msLAPS-PasswordExpirationTime' }

$targets = @(Get-TargetComputers -Number $Count -SB $SearchBase -LapsAttributes $lapsAttributes)

# Vom Skript erzeugte BitLocker-Objekte einmalig (statt je Computer) über den Marker ermitteln
$fakeBitLockerIndex = @{}
if ($Mode -in 'Verify', 'Clean' -and $doBitLocker) {
    try {
        $bitLockerBase = if ($SearchBase) { $SearchBase } else { (Get-ADDomain -ErrorAction Stop).DistinguishedName }
        $fakeObjects = Get-ADObject -LDAPFilter "(&(objectClass=msFVE-RecoveryInformation)(adminDescription=$($script:FakeMarker)*))" `
            -SearchBase $bitLockerBase -SearchScope Subtree -Properties 'adminDescription', 'msFVE-RecoveryPassword' -ErrorAction Stop
        foreach ($obj in $fakeObjects) {
            $parentDN = $obj.DistinguishedName.Substring($obj.DistinguishedName.IndexOf(',') + 1)
            if (-not $fakeBitLockerIndex.ContainsKey($parentDN)) { $fakeBitLockerIndex[$parentDN] = New-Object System.Collections.Generic.List[object] }
            $fakeBitLockerIndex[$parentDN].Add($obj)
        }
    } catch {
        Write-Warning "Fehler beim Suchen der Fake-BitLocker-Objekte: $($_.Exception.Message)"
    }
}

$neededDummies = 0
if ($Mode -eq 'Create') {
    if ($targets.Count -lt $Count) {
        $neededDummies = $Count - $targets.Count
        Write-Warning "Nicht genügend Computer gefunden ($($targets.Count)/$Count). Es werden $neededDummies zusätzliche Dummy-Computer erstellt."
    }
} else {
    Write-ScriptLog "Modus '$Mode': $($targets.Count) Computer gefunden, prüfe auf vom Skript erzeugte Fake-Daten..."
    # Nur Computer mit markierten Fake-Daten bearbeiten – echte Daten werden ignoriert
    $targets = @($targets | Where-Object {
        ($doBitLocker -and $fakeBitLockerIndex.ContainsKey($_.DistinguishedName)) -or
        ($doLaps -and (Test-FakeLapsValue $_.'ms-Mcs-AdmPwd')) -or
        ($doWinLaps -and (Test-FakeLapsValue $_.'msLAPS-Password'))
    })
}

$targetCount = $targets.Count + $neededDummies
if ($targetCount -eq 0) {
    Write-Warning "Keine Zielcomputer (bzw. keine vom Skript erzeugten Fake-Daten) gefunden. Breche ab."
    return
}

$confirmationPrompt = "`nZusammenfassung:`n  - Aktion: $Mode`n  - Datentyp: $DataType`n  - Zielcomputer: $targetCount"
if ($neededDummies -gt 0) {
    $confirmationPrompt += " (davon $neededDummies neue Dummy-Computer)"
}
if ($Mode -eq 'Create' -and $doBitLocker) {
    $confirmationPrompt += "`n  - BitLocker-Laufwerke: $($Volumes -join ', ')"
}
if ($Mode -eq 'Clean') {
    $confirmationPrompt += "`n  - Es werden ausschließlich vom Skript markierte Fake-Daten entfernt (Marker '$($script:FakeMarker)' / Präfix '$($script:FakePasswordPrefix)')."
}
$confirmationPrompt += "`n  - WARNUNG: Nur in Test-/Laborumgebungen verwenden!"

if (-not $Quiet -and -not $WhatIfPreference -and -not $PSCmdlet.ShouldContinue($confirmationPrompt, "Soll die Aktion ausgeführt werden?")) {
    Write-Warning "Aktion vom Benutzer abgebrochen."
    return
}

if ($neededDummies -gt 0) {
    $targets += @(New-DummyComputer -Needed $neededDummies -SB $SearchBase)
}

Write-ScriptLog "Starte Modus '$Mode' für '$DataType' auf $($targets.Count) Computern..." 'Cyan'

$results = New-Object System.Collections.Generic.List[object]
foreach ($c in $targets) {
    if ($doBitLocker) { foreach ($r in @(Invoke-BitLockerAction -Computer $c -FakeIndex $fakeBitLockerIndex)) { $results.Add($r) } }
    if ($doLaps)      { $results.Add((Invoke-LapsAction -Computer $c -IsWindowsLaps $false)) }
    if ($doWinLaps)   { $results.Add((Invoke-LapsAction -Computer $c -IsWindowsLaps $true)) }
}

# Einheitliche Spalten, damit Tabelle und CSV alle Felder (z. B. Error) enthalten
$results = @($results | Select-Object -Property $script:ResultColumns)

if ($results -and -not $Quiet) {
    $results | Format-Table -AutoSize | Out-Host
}
#endregion

#region ── CSV-Export ────────────────────────────────────────────────────────────
if ($results -and -not $WhatIfPreference) {
    if (-not $OutputFile) {
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $logDir = Join-Path $scriptDir 'Logs'
        $OutputFile = Join-Path $logDir ("FakeADData_{0}_{1}.csv" -f $Mode, (Get-Date -f yyyyMMdd_HHmmss))
    }
    try {
        $outputDir = Split-Path -Path $OutputFile -Parent
        if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
        }
        $results | Export-Csv -LiteralPath $OutputFile -Encoding UTF8 -NoTypeInformation -Confirm:$false -ErrorAction Stop
        Write-ScriptLog "Ergebnis-CSV gespeichert unter: $OutputFile" 'Green'
    } catch {
        Write-Warning "CSV-Export fehlgeschlagen: $_"
    }
}
#endregion
