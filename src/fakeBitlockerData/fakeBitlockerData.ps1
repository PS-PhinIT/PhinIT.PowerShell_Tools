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
      - Verify : Prüft die vom Skript erzeugten Fake-Daten und zeigt sie an (optional auch Legacy-Daten aus 0.0.1).
      - Clean  : Entfernt ausschließlich die vom Skript erzeugten (markierten) Fake-Daten, optional auch per
                 Fingerabdruck erkannte Legacy-Daten aus 0.0.1 (-IncludeLegacy) und Dummy-Computer
                 (-RemoveDummyComputers).

    Sicherheitsmechanismen:
      - Fake-BitLocker-Objekte werden über das Attribut adminDescription mit dem Marker 'PhinIT-FakeTestData'
        gekennzeichnet, Fake-LAPS-Passwörter beginnen mit dem Präfix 'FAKE-'. Verify und Clean berücksichtigen
        nur so markierte Daten – echte BitLocker-/LAPS-Daten werden weder angezeigt, exportiert noch gelöscht.
      - Vorhandene echte LAPS-Passwörter werden im Create-Modus nicht überschrieben.
      - Domänencontroller werden im Create-Modus nicht als Ziel verwendet.
      - Fake-Passwörter werden mit einem kryptografisch sicheren Zufallszahlengenerator erzeugt.
      - -WhatIf und -Confirm werden für alle schreibenden/löschenden AD-Operationen unterstützt.

    Legacy-Daten aus Version 0.0.1 (nur mit -IncludeLegacy):
      Version 0.0.1 hat keine Marker gesetzt. Ohne -IncludeLegacy werden solche Daten weiterhin ignoriert.
      Mit -IncludeLegacy erkennen Verify und Clean sie ausschließlich über die folgenden Fingerabdrücke, die
      nur 0.0.1 erzeugt hat und die echte Windows-/BitLocker-/LAPS-Komponenten nie erzeugen. Es müssen
      jeweils ALLE Kriterien eines Fingerabdrucks erfüllt sein:
        P  Passwortmuster 0.0.1 (allein NICHT ausreichend, nur Bestandteil von W1/L1/L2):
           genau 15 Zeichen, ausschließlich aus dem 0.0.1-Zeichensatz a-z A-Z 0-9 ! @ # $ % * _ { } [ ] , . ? /
           und alle 15 Zeichen paarweise verschieden (0.0.1 nutzte Get-Random -Count = Ziehen ohne Zurücklegen).
        W1 Windows LAPS: msLAPS-Password erfüllt P (also Klartext statt des JSON-Formats {"n":..,"t":..,"p":..},
           das Windows LAPS immer schreibt) UND msLAPS-PasswordExpirationTime liegt zwischen 946684800 und
           4102444800 (Unix-Sekunden 2000–2100). Als FILETIME wäre das ein Zeitpunkt wenige Minuten nach dem
           01.01.1601 – Windows LAPS schreibt immer FILETIME.
        L1 Legacy-LAPS auf 0.0.1-Dummy-Computer: ms-Mcs-AdmPwd erfüllt P UND der Computer erfüllt D1
           (ein deaktivierter, nie verwendeter Dummy-Computer hat keinen LAPS-Client).
        L2 Legacy-LAPS neben W1: ms-Mcs-AdmPwd erfüllt P UND derselbe Computer erfüllt W1 UND
           ms-Mcs-AdmPwdExpirationTime (FILETIME) liegt 0–600 Sekunden vor msLAPS-PasswordExpirationTime
           (0.0.1 schrieb bei DataType All beide Werte direkt nacheinander mit "jetzt + 30 Tage").
           Ein echtes Legacy-LAPS-Passwort ist von einem 0.0.1-Fake-Passwort sonst nicht unterscheidbar
           (gleiches FILETIME-Format, gleiche Länge/Zeichen möglich) – ohne L1/L2 wird es daher nie erkannt.
        D1 Dummy-Computer 0.0.1: Name FAKE-PC-<5 Ziffern> UND Beschreibung exakt 'Temporärer Dummy-PC für
           Testdaten' (bzw. die von Windows PowerShell 5.1 aus der BOM-losen 0.0.1-Datei erzeugte Variante
           'TemporÃ¤rer Dummy-PC fÃ¼r Testdaten') UND Konto deaktiviert.
        B1 BitLocker: msFVE-RecoveryInformation ohne adminDescription UND Objektname
           'CN=<yyyyMMddHHmmss>-{GUID}' (0.0.1 übergab das Präfix 'CN=' fälschlich als Teil des Namens; Windows
           verwendet '<yyyy-MM-ddTHH:mm:ss±hh:mm>{GUID}') UND msFVE-RecoveryPassword aus 8 Blöcken à 6 Ziffern
           mit mindestens einem Block, der nicht durch 11 teilbar oder >= 720896 ist (echte
           Wiederherstellungskennwörter sind immer gültig). Hinweis: 0.0.1 konnte BitLocker-Objekte praktisch
           nicht anlegen (falscher Attributname, fehlendes Pflichtattribut msFVE-RecoveryGuid) – B1 ist eine
           Absicherung, in der Regel wird nichts gefunden. Das Fehlen von msFVE-RecoveryGuid ist kein
           Kriterium, da das AD-Schema dieses Attribut erzwingt.
      Erkannte Legacy-Elemente erscheinen in Verify mit Status 'Legacy 0.0.1', dem erkannten Fingerabdruck und
      maskiertem Passwort. Clean entfernt sie nur nach einer zusätzlichen Sicherheitsabfrage bzw. mit
      -ForceLegacyClean (im Quiet-Modus Pflicht).

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

.PARAMETER IncludeLegacy
    Verify/Clean: bezieht zusätzlich nicht markierte Fake-Daten aus Version 0.0.1 ein, die über die oben
    beschriebenen Fingerabdrücke (W1, L1, L2, B1, D1) zuverlässig erkannt werden. Ohne diesen Schalter bleibt
    das Verhalten unverändert (nur markierte Daten). Im Modus Create ohne Wirkung.

.PARAMETER ForceLegacyClean
    Clean: entfernt erkannte Legacy-Elemente (0.0.1) ohne die zusätzliche Sicherheitsabfrage. Im Quiet-Modus
    ist dieser Schalter zusammen mit -IncludeLegacy Pflicht (ausdrückliche Zustimmung für unbeaufsichtigtes
    Löschen). -WhatIf und -Confirm werden weiterhin berücksichtigt. Ohne -IncludeLegacy ohne Wirkung.

.PARAMETER RemoveDummyComputers
    Clean: entfernt zusätzlich die von Create angelegten Dummy-Computer. Gelöscht wird nur ein Computer, dessen
    Name FAKE-PC-<5 Ziffern> lautet UND dessen Beschreibung auf '[PhinIT-FakeTestData]' endet UND der
    deaktiviert ist UND sich nie angemeldet hat (lastLogonTimestamp leer) UND der höchstens vom Skript erzeugte
    BitLocker-Unterobjekte enthält (diese werden vorher einzeln gelöscht, kein rekursives Löschen).
    Zusammen mit -IncludeLegacy werden auch Dummy-Computer aus 0.0.1 (Fingerabdruck D1, gleiche
    Zusatzbedingungen) entfernt – nur nach der Legacy-Sicherheitsabfrage bzw. mit -ForceLegacyClean.

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

.EXAMPLE
    .\fakeBitlockerData.ps1 -Mode Verify -DataType All -IncludeLegacy
    Zeigt markierte Fake-Daten und zusätzlich per Fingerabdruck erkannte Fake-Daten aus Version 0.0.1
    (Status 'Legacy 0.0.1', Passwörter maskiert) sowie Dummy-Computer aus 0.0.1 an.

.EXAMPLE
    .\fakeBitlockerData.ps1 -Mode Clean -DataType All -IncludeLegacy -RemoveDummyComputers -WhatIf
    Zeigt an, welche markierten Fake-Daten, Legacy-Daten aus 0.0.1 und Dummy-Computer entfernt würden.

.EXAMPLE
    .\fakeBitlockerData.ps1 -Mode Clean -DataType All -RemoveDummyComputers
    Entfernt markierte Fake-Daten und anschließend die markierten Dummy-Computer FAKE-PC-*.

.EXAMPLE
    .\fakeBitlockerData.ps1 -Mode Clean -DataType All -IncludeLegacy -ForceLegacyClean -RemoveDummyComputers -Quiet
    Unbeaufsichtigtes Entfernen aller markierten und per Fingerabdruck erkannten Legacy-Fake-Daten inklusive
    Dummy-Computer. Ohne -ForceLegacyClean bricht der Quiet-Modus mit -IncludeLegacy im Modus Clean ab.

.NOTES
    Version : 0.0.3
    Autor   : Andreas Hepp | PhinIT (www.phinit.de)
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
    [switch]$Quiet,

    [Parameter(HelpMessage = "Verify/Clean: bezieht per Fingerabdruck erkannte, nicht markierte Fake-Daten aus Version 0.0.1 ein.")]
    [switch]$IncludeLegacy,

    [Parameter(HelpMessage = "Clean: entfernt erkannte Legacy-Daten (0.0.1) ohne zusätzliche Sicherheitsabfrage (im Quiet-Modus Pflicht).")]
    [switch]$ForceLegacyClean,

    [Parameter(HelpMessage = "Clean: entfernt zusätzlich die vom Skript angelegten Dummy-Computer (FAKE-PC-*).")]
    [switch]$RemoveDummyComputers
)

#region ── Konstanten ────────────────────────────────────────────────────────────
$script:ScriptVersion      = '0.0.3'
# Kennzeichnung der vom Skript erzeugten Daten – Verify/Clean berücksichtigen nur markierte Daten
$script:FakeMarker         = 'PhinIT-FakeTestData'
$script:FakePasswordPrefix = 'FAKE-'
$script:ResultColumns      = @('Computer', 'Type', 'Volume', 'Status', 'Success', 'Password', 'Expiry', 'Removed', 'Info', 'Error')
$script:Rng                = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$script:MarkedStatus       = 'Markiert'
$script:LegacyStatus       = 'Legacy 0.0.1'
$script:DummyNamePattern   = '^FAKE-PC-[0-9]{5}$'
# Fingerabdrücke der Version 0.0.1 (siehe Hilfe: P, W1, L1, L2, D1, B1)
$script:LegacyPasswordCharset    = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%*_{}[],.?/'
$script:LegacyPasswordLength     = 15
$script:LegacyDummyDescriptions  = @(
    'Temporärer Dummy-PC für Testdaten',
    # Variante aus Windows PowerShell 5.1 (0.0.1 war UTF-8 ohne BOM und wurde als ANSI/1252 gelesen)
    ('Tempor{0}{1}rer Dummy-PC f{0}{2}r Testdaten' -f [char]0x00C3, [char]0x00A4, [char]0x00BC)
)
$script:LegacyBitLockerNamePattern = '^CN=[0-9]{14}-\{[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}$'
$script:UnixSecondsMin           = [int64]946684800     # 01.01.2000 UTC
$script:UnixSecondsMax           = [int64]4102444800    # 01.01.2100 UTC
$script:FileTimeUnixEpoch        = [int64]116444736000000000
$script:LegacyLapsMaxDelaySeconds = [int64]600
$script:LegacyRemovalApproved    = $false
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

# Plausibilität der Legacy-/Dummy-Schalter (erst nach der interaktiven Abfrage ist der Modus bekannt)
if ($IncludeLegacy -and $Mode -eq 'Create') {
    Write-Warning "-IncludeLegacy hat im Modus 'Create' keine Wirkung."
}
if ($ForceLegacyClean -and ($Mode -ne 'Clean' -or -not $IncludeLegacy)) {
    Write-Warning "-ForceLegacyClean wirkt nur im Modus 'Clean' zusammen mit -IncludeLegacy."
}
if ($RemoveDummyComputers -and $Mode -ne 'Clean') {
    Write-Warning "-RemoveDummyComputers wirkt nur im Modus 'Clean'."
}
if ($Quiet -and $Mode -eq 'Clean' -and $IncludeLegacy -and -not $ForceLegacyClean -and -not $WhatIfPreference) {
    throw "Im Quiet-Modus ist für das Entfernen von Legacy-Daten (0.0.1) die ausdrückliche Zustimmung per -ForceLegacyClean erforderlich."
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

function Get-RandomFakePassword([int]$Length = 15) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%*_{}[],.?/'.ToCharArray()
    $randomPart = -join (1..$Length | ForEach-Object { $chars[(Get-SecureRandomNumber $chars.Length)] })
    return $script:FakePasswordPrefix + $randomPart
}

function Get-RandomRecoveryPassword {
    # Echtes Format: 8 Blöcke à 6 Ziffern, jeder Block ist ein Vielfaches von 11 (< 720896)
    (1..8 | ForEach-Object { '{0:D6}' -f ((Get-SecureRandomNumber 65536) * 11) }) -join '-'
}

function Write-ScriptLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Farbige Konsolenausgabe ist die Benutzeroberfläche dieses Konsolenskripts; mit -Quiet abschaltbar, Ergebnisse gehen zusätzlich in die CSV.')]
    param(
        [string]$Message,
        [System.ConsoleColor]$Color = 'Gray'
    )
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

#region ── Fingerabdrücke für Legacy-Daten aus Version 0.0.1 (siehe Hilfe) ─────
function Test-LegacyFakePassword {
    # P: 15 Zeichen, nur 0.0.1-Zeichensatz, alle Zeichen verschieden (Get-Random -Count zieht ohne Zurücklegen)
    [OutputType([bool])]
    param([AllowNull()][object]$Value)
    $text = [string]$Value
    if ($text.Length -ne $script:LegacyPasswordLength) { return $false }
    $seen = New-Object 'System.Collections.Generic.HashSet[char]'
    foreach ($ch in $text.ToCharArray()) {
        if ($script:LegacyPasswordCharset.IndexOf($ch) -lt 0) { return $false }
        if (-not $seen.Add($ch)) { return $false }
    }
    return $true
}

function Test-InvalidRecoveryPassword {
    # 8 Blöcke à 6 Ziffern, aber mindestens ein Block ist kein gültiger BitLocker-Block (Vielfaches von 11, < 720896)
    [OutputType([bool])]
    param([AllowNull()][object]$Value)
    $text = [string]$Value
    if ($text -cnotmatch '^[0-9]{6}(-[0-9]{6}){7}$') { return $false }
    foreach ($block in $text.Split('-')) {
        $number = [int]$block
        if (($number % 11) -ne 0 -or $number -ge 720896) { return $true }
    }
    return $false
}

function Test-LegacyBitLockerFingerprint {
    # B1: kein Marker + Name 'CN=<yyyyMMddHHmmss>-{GUID}' + ungültiges Wiederherstellungskennwort
    [OutputType([bool])]
    param(
        [AllowNull()][string]$Name,
        [AllowNull()][object]$RecoveryValue,
        [AllowNull()][object]$AdminDescription
    )
    if (-not [string]::IsNullOrEmpty([string]$AdminDescription)) { return $false }
    if ([string]::IsNullOrEmpty($Name) -or $Name -cnotmatch $script:LegacyBitLockerNamePattern) { return $false }
    $timestamp = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Name.Substring(3, 14), 'yyyyMMddHHmmss', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$timestamp)) {
        return $false
    }
    return (Test-InvalidRecoveryPassword $RecoveryValue)
}

function Test-LegacyWindowsLapsFingerprint {
    # W1: msLAPS-Password im Muster P (kein JSON) + msLAPS-PasswordExpirationTime in Unix-Sekunden statt FILETIME
    [OutputType([bool])]
    param(
        [AllowNull()][object]$Value,
        [AllowNull()][object]$Expiration
    )
    if (-not (Test-LegacyFakePassword $Value)) { return $false }
    $expirationValue = [int64]0
    if (-not [int64]::TryParse([string]$Expiration, [ref]$expirationValue)) { return $false }
    return ($expirationValue -ge $script:UnixSecondsMin -and $expirationValue -le $script:UnixSecondsMax)
}

function Test-LegacyDummyComputerFingerprint {
    # D1: Name FAKE-PC-<5 Ziffern> + exakte 0.0.1-Beschreibung (ohne Marker) + deaktiviert
    [OutputType([bool])]
    param(
        [AllowNull()][string]$Name,
        [AllowNull()][object]$Description,
        [AllowNull()][object]$Enabled
    )
    if ([string]::IsNullOrEmpty($Name) -or $Name -cnotmatch $script:DummyNamePattern) { return $false }
    if ($script:LegacyDummyDescriptions -cnotcontains [string]$Description) { return $false }
    return ($Enabled -is [bool] -and -not $Enabled)
}

function Test-MarkedDummyComputer {
    # Ab 0.0.2: Name FAKE-PC-<5 Ziffern> + Beschreibung endet auf '[PhinIT-FakeTestData]' + deaktiviert
    [OutputType([bool])]
    param(
        [AllowNull()][string]$Name,
        [AllowNull()][object]$Description,
        [AllowNull()][object]$Enabled
    )
    if ([string]::IsNullOrEmpty($Name) -or $Name -cnotmatch $script:DummyNamePattern) { return $false }
    if (-not ([string]$Description).EndsWith("[$($script:FakeMarker)]", [System.StringComparison]::Ordinal)) { return $false }
    return ($Enabled -is [bool] -and -not $Enabled)
}

function Test-LegacyLapsFingerprint {
    # L1: Muster P + 0.0.1-Dummy-Computer (D1)
    # L2: Muster P + W1 auf demselben Computer + Ablaufzeiten passen zum 0.0.1-Ablauf (0..600 s Abstand)
    [OutputType([string])]
    param(
        [AllowNull()][object]$Value,
        [AllowNull()][object]$Expiration,
        [bool]$IsLegacyDummy,
        [AllowNull()][object]$WindowsLapsValue,
        [AllowNull()][object]$WindowsLapsExpiration
    )
    if (-not (Test-LegacyFakePassword $Value)) { return '' }
    if ($IsLegacyDummy) { return 'L1' }
    if (-not (Test-LegacyWindowsLapsFingerprint -Value $WindowsLapsValue -Expiration $WindowsLapsExpiration)) { return '' }
    $fileTime = [int64]0
    if (-not [int64]::TryParse([string]$Expiration, [ref]$fileTime) -or $fileTime -lt $script:FileTimeUnixEpoch) { return '' }
    $legacyUnixSeconds = [int64][math]::Floor(($fileTime - $script:FileTimeUnixEpoch) / 10000000)
    $delay = [int64]$WindowsLapsExpiration - $legacyUnixSeconds
    if ($delay -ge -1 -and $delay -le $script:LegacyLapsMaxDelaySeconds) { return 'L2' }
    return ''
}

function Get-LegacyLapsMatch {
    # Liefert die Kennung des passenden Fingerabdrucks (W1, L1, L2) oder '' – nie für markierte Daten
    [OutputType([string])]
    param(
        $Computer,
        [bool]$IsWindowsLaps
    )
    if ($IsWindowsLaps) {
        if (Test-LegacyWindowsLapsFingerprint -Value $Computer.'msLAPS-Password' -Expiration $Computer.'msLAPS-PasswordExpirationTime') { return 'W1' }
        return ''
    }
    $winLapsValue = $null
    $winLapsExpiration = $null
    if ($script:HasWindowsLapsSchema) {
        $winLapsValue = $Computer.'msLAPS-Password'
        $winLapsExpiration = $Computer.'msLAPS-PasswordExpirationTime'
    }
    $isLegacyDummy = Test-LegacyDummyComputerFingerprint -Name $Computer.Name -Description $Computer.Description -Enabled $Computer.Enabled
    return (Test-LegacyLapsFingerprint -Value $Computer.'ms-Mcs-AdmPwd' -Expiration $Computer.'ms-Mcs-AdmPwdExpirationTime' `
        -IsLegacyDummy $isLegacyDummy -WindowsLapsValue $winLapsValue -WindowsLapsExpiration $winLapsExpiration)
}

function Get-MaskedSecret {
    # Legacy-Passwörter werden grundsätzlich maskiert angezeigt/exportiert
    [OutputType([string])]
    param([AllowNull()][object]$Value)
    $text = [string]$Value
    if ($text.Length -le 4) { return '****' }
    return $text.Substring(0, 2) + ('*' * ($text.Length - 2))
}
#endregion

function Get-TargetComputer {
    param(
        [int]$Number,
        [string]$SB,
        [string[]]$ExtraProperties
    )
    $pSB = @{ Filter = '*'; Properties = @('PrimaryGroupID') + @($ExtraProperties | Where-Object { $_ }); ErrorAction = 'Stop' }
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

function Test-RemovableFakeChild {
    # Unterobjekte eines Dummy-Computers dürfen nur markierte bzw. (freigegebene) Legacy-Fake-BitLocker-Objekte sein
    [OutputType([bool])]
    param($Object)
    if ([string]$Object.ObjectClass -ne 'msFVE-RecoveryInformation') { return $false }
    if (([string]$Object.adminDescription).StartsWith($script:FakeMarker, [System.StringComparison]::Ordinal)) { return $true }
    return ($IncludeLegacy -and $script:LegacyRemovalApproved -and
        (Test-LegacyBitLockerFingerprint -Name $Object.Name -RecoveryValue $Object.'msFVE-RecoveryPassword' -AdminDescription $Object.adminDescription))
}

function Remove-FakeDummyComputer {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        $Computer,
        [bool]$IsLegacy
    )
    $DN = $Computer.DistinguishedName
    $status = if ($IsLegacy) { $script:LegacyStatus } else { $script:MarkedStatus }
    $details = [ordered]@{ Computer = $Computer.Name; Type = 'DummyComputer'; Status = $status; Removed = 0 }

    if ($IsLegacy -and -not $script:LegacyRemovalApproved) {
        $details.Success = $false
        $details.Info = 'Legacy-Dummy-Computer (Fingerabdruck D1) nicht entfernt: Entfernen von Legacy-Daten wurde nicht bestätigt.'
        return [pscustomobject]$details
    }
    if ($Computer.lastLogonTimestamp) {
        $details.Success = $false
        $details.Info = 'Übersprungen: Der Computer hat sich bereits an der Domäne angemeldet (lastLogonTimestamp gesetzt).'
        return [pscustomobject]$details
    }
    try {
        $children = @(Get-ADObject -Filter * -SearchBase $DN -SearchScope OneLevel -Properties 'adminDescription', 'msFVE-RecoveryPassword' -ErrorAction Stop)
    } catch {
        $details.Success = $false
        $details.Error = "Unterobjekte konnten nicht geprüft werden: $($_.Exception.Message)"
        return [pscustomobject]$details
    }
    $foreignChildren = @($children | Where-Object { -not (Test-RemovableFakeChild $_) })
    if ($foreignChildren.Count -gt 0) {
        $details.Success = $false
        $details.Info = "Übersprungen: Der Computer enthält $($foreignChildren.Count) nicht vom Skript erzeugte Unterobjekte."
        return [pscustomobject]$details
    }

    $action = if ($IsLegacy) { 'Entferne Legacy-Dummy-Computer aus Version 0.0.1 (Fingerabdruck D1)' } else { 'Entferne markierten Fake-Dummy-Computer' }
    if ($PSCmdlet.ShouldProcess($DN, $action)) {
        try {
            # Kein rekursives Löschen: erst die geprüften Fake-Unterobjekte einzeln, dann das (leere) Computerobjekt
            foreach ($child in $children) {
                Remove-ADObject -Identity $child.DistinguishedName -Confirm:$false -ErrorAction Stop
            }
            Remove-ADObject -Identity $DN -Confirm:$false -ErrorAction Stop
            $details.Success = $true
            $details.Removed = 1
        } catch {
            $details.Success = $false
            $details.Error = $_.Exception.Message
        }
    }
    return [pscustomobject]$details
}
#endregion

#region ── Aktionsfunktionen (Create, Verify, Clean) ───────────────────────────

function Invoke-BitLockerAction {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $Computer,
        [hashtable]$FakeIndex,
        [hashtable]$LegacyIndex = @{}
    )
    $CN = $Computer.Name
    $DN = $Computer.DistinguishedName
    $results = New-Object System.Collections.Generic.List[object]

    switch ($Mode) {
        'Create' {
            foreach ($vol in $Volumes) {
                $cleanVol = $vol.Trim(' :').ToUpper()
                $details = [ordered]@{ Computer = $CN; Volume = $cleanVol; Type = 'Bitlocker' }
                $fakePassword = Get-RandomRecoveryPassword
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
            $objects = @($FakeIndex[$DN] | Where-Object { $null -ne $_ })
            $legacyObjects = @($LegacyIndex[$DN] | Where-Object { $null -ne $_ })
            foreach ($obj in $objects) {
                $volume = if ([string]$obj.adminDescription -match 'Volume=([^;]+)') { $Matches[1] } else { '' }
                $results.Add([pscustomobject][ordered]@{ Computer = $CN; Volume = $volume; Type = 'Bitlocker'; Status = $script:MarkedStatus; Success = $true; Password = $obj.'msFVE-RecoveryPassword' })
            }
            foreach ($obj in $legacyObjects) {
                $results.Add([pscustomobject][ordered]@{
                    Computer = $CN; Type = 'Bitlocker'; Status = $script:LegacyStatus; Success = $true
                    Password = Get-MaskedSecret $obj.'msFVE-RecoveryPassword'
                    Info     = "Nicht markiert, erkannt über Fingerabdruck B1 (Objekt '$($obj.Name)', Kennwort maskiert)."
                })
            }
            if ($objects.Count -eq 0 -and $legacyObjects.Count -eq 0) {
                $results.Add([pscustomobject][ordered]@{ Computer = $CN; Type = 'Bitlocker'; Success = $false; Error = 'Keine Fake-BitLocker-Wiederherstellungsschlüssel gefunden.' })
            }
        }
        'Clean' {
            $objects = @($FakeIndex[$DN] | Where-Object { $null -ne $_ })
            $legacyObjects = @($LegacyIndex[$DN] | Where-Object { $null -ne $_ })
            foreach ($obj in $objects) {
                $volume = if ([string]$obj.adminDescription -match 'Volume=([^;]+)') { $Matches[1] } else { '' }
                $details = [ordered]@{ Computer = $CN; Volume = $volume; Type = 'Bitlocker'; Status = $script:MarkedStatus }
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
            foreach ($obj in $legacyObjects) {
                $details = [ordered]@{ Computer = $CN; Type = 'Bitlocker'; Status = $script:LegacyStatus; Info = "Fingerabdruck B1 (Objekt '$($obj.Name)')." }
                if (-not $script:LegacyRemovalApproved) {
                    $details.Success = $false
                    $details.Removed = 0
                    $details.Info = 'Legacy-Daten (Fingerabdruck B1) nicht entfernt: Entfernen wurde nicht bestätigt.'
                } elseif ($PSCmdlet.ShouldProcess($obj.DistinguishedName, 'Entferne Legacy-Fake-BitLocker-Objekt aus Version 0.0.1 (Fingerabdruck B1)')) {
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
            if ($objects.Count -eq 0 -and $legacyObjects.Count -eq 0) {
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
    # Legacy-Erkennung (0.0.1) nur auf ausdrücklichen Wunsch und nie für markierte Daten
    $legacyMatch = ''
    if ($IncludeLegacy -and $Mode -ne 'Create' -and -not $isFake) {
        $legacyMatch = Get-LegacyLapsMatch -Computer $Computer -IsWindowsLaps $IsWindowsLaps
    }

    switch ($Mode) {
        'Create' {
            if (-not [string]::IsNullOrEmpty([string]$currentValue) -and -not $isFake) {
                $details.Success = $false
                $details.Info = "Übersprungen: vorhandenes echtes $lapsType-Passwort wird nicht überschrieben."
                break
            }
            $fakePassword = Get-RandomFakePassword
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
                $details.Status = $script:MarkedStatus
                $details.Success = $true
                $details.Password = Get-FakeLapsPassword $currentValue
                $expiryValue = $Computer.$expiryAttr
                if ($expiryValue) {
                    try { $details.Expiry = [datetime]::FromFileTimeUtc([int64]$expiryValue) }
                    catch { $details.Info = "Ungültige Ablaufzeit: $expiryValue" }
                }
            } elseif ($legacyMatch) {
                $details.Status = $script:LegacyStatus
                $details.Success = $true
                $details.Password = Get-MaskedSecret $currentValue
                $details.Info = "Nicht markiert, erkannt über Fingerabdruck $legacyMatch (Passwort maskiert)."
                $expiryValue = $Computer.$expiryAttr
                if ($expiryValue) {
                    # 0.0.1 schrieb Windows LAPS in Unix-Sekunden, Legacy-LAPS als FILETIME
                    try {
                        $details.Expiry = if ($IsWindowsLaps) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$expiryValue).UtcDateTime } else { [datetime]::FromFileTimeUtc([int64]$expiryValue) }
                    } catch {
                        $details.Info += " Ungültige Ablaufzeit: $expiryValue"
                    }
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
            if (-not $isFake -and -not $legacyMatch) {
                $details.Success = $true
                $details.Removed = 0
                $details.Info = "Keine Fake-$lapsType-Daten vorhanden (echte Daten bleiben unangetastet)."
                break
            }
            $action = "Entferne Fake-$lapsType-Daten"
            if ($legacyMatch) {
                $details.Status = $script:LegacyStatus
                $details.Info = "Fingerabdruck $legacyMatch."
                if (-not $script:LegacyRemovalApproved) {
                    $details.Success = $false
                    $details.Removed = 0
                    $details.Info = "Legacy-Daten (Fingerabdruck $legacyMatch) nicht entfernt: Entfernen wurde nicht bestätigt."
                    break
                }
                $action = "Entferne Legacy-Fake-$lapsType-Daten aus Version 0.0.1 (Fingerabdruck $legacyMatch)"
            } else {
                $details.Status = $script:MarkedStatus
            }
            if ($PSCmdlet.ShouldProcess($CN, $action)) {
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
$useLegacy   = $IncludeLegacy -and $Mode -in 'Verify', 'Clean'
# Dummy-Computer: Clean mit -RemoveDummyComputers entfernt sie, Verify mit -IncludeLegacy listet 0.0.1-Dummys auf
$doDummies   = ($Mode -eq 'Clean' -and $RemoveDummyComputers) -or ($Mode -eq 'Verify' -and $IncludeLegacy)

if ($doLaps -and -not (Test-ADSchemaAttribute 'ms-Mcs-AdmPwd')) {
    Write-Warning "Das AD-Schema enthält keine Legacy-LAPS-Attribute (ms-Mcs-AdmPwd). Legacy-LAPS wird übersprungen."
    $doLaps = $false
}
if ($doWinLaps -and -not (Test-ADSchemaAttribute 'msLAPS-Password')) {
    Write-Warning "Das AD-Schema enthält keine Windows-LAPS-Attribute (msLAPS-Password). Windows LAPS wird übersprungen."
    $doWinLaps = $false
}
# Für Fingerabdruck L2 werden die Windows-LAPS-Attribute auch bei DataType LAPS benötigt
$script:HasWindowsLapsSchema = $doWinLaps -or ($useLegacy -and $doLaps -and (Test-ADSchemaAttribute 'msLAPS-Password'))
if (-not ($doBitLocker -or $doLaps -or $doWinLaps -or $doDummies)) {
    Write-Warning "Für den Datentyp '$DataType' ist nichts zu tun. Breche ab."
    return
}

$extraProperties = @()
if ($doLaps) { $extraProperties += 'ms-Mcs-AdmPwd', 'ms-Mcs-AdmPwdExpirationTime' }
if ($doWinLaps -or ($useLegacy -and $script:HasWindowsLapsSchema)) { $extraProperties += 'msLAPS-Password', 'msLAPS-PasswordExpirationTime' }
if ($useLegacy -or $doDummies) { $extraProperties += 'Description', 'lastLogonTimestamp' }

$targets = @(Get-TargetComputer -Number $Count -SB $SearchBase -ExtraProperties ($extraProperties | Select-Object -Unique))
$allComputers = $targets

# Vom Skript erzeugte BitLocker-Objekte einmalig (statt je Computer) über den Marker ermitteln
$fakeBitLockerIndex = @{}
$legacyBitLockerIndex = @{}
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
        if ($useLegacy) {
            # Fingerabdruck B1: Vorauswahl per LDAP (Name beginnt mit 'CN=', kein adminDescription), Prüfung clientseitig
            $legacyCandidates = Get-ADObject -LDAPFilter '(&(objectClass=msFVE-RecoveryInformation)(name=CN\3d*)(!(adminDescription=*)))' `
                -SearchBase $bitLockerBase -SearchScope Subtree -Properties 'adminDescription', 'msFVE-RecoveryPassword' -ErrorAction Stop
            foreach ($obj in $legacyCandidates) {
                if (-not (Test-LegacyBitLockerFingerprint -Name $obj.Name -RecoveryValue $obj.'msFVE-RecoveryPassword' -AdminDescription $obj.adminDescription)) { continue }
                $parentDN = $obj.DistinguishedName.Substring($obj.DistinguishedName.IndexOf(',') + 1)
                if (-not $legacyBitLockerIndex.ContainsKey($parentDN)) { $legacyBitLockerIndex[$parentDN] = New-Object System.Collections.Generic.List[object] }
                $legacyBitLockerIndex[$parentDN].Add($obj)
            }
        }
    } catch {
        Write-Warning "Fehler beim Suchen der Fake-BitLocker-Objekte: $($_.Exception.Message)"
    }
}

$neededDummies = 0
$legacyCount = 0
$dummyCandidates = New-Object System.Collections.Generic.List[object]
if ($Mode -eq 'Create') {
    if ($targets.Count -lt $Count) {
        $neededDummies = $Count - $targets.Count
        Write-Warning "Nicht genügend Computer gefunden ($($targets.Count)/$Count). Es werden $neededDummies zusätzliche Dummy-Computer erstellt."
    }
} else {
    Write-ScriptLog "Modus '$Mode': $($targets.Count) Computer gefunden, prüfe auf vom Skript erzeugte Fake-Daten..."
    # Nur Computer mit markierten (bzw. mit -IncludeLegacy per Fingerabdruck erkannten) Fake-Daten bearbeiten – echte Daten werden ignoriert
    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($comp in $targets) {
        $hasData = $false
        if ($doBitLocker) {
            if ($fakeBitLockerIndex.ContainsKey($comp.DistinguishedName)) { $hasData = $true }
            if ($legacyBitLockerIndex.ContainsKey($comp.DistinguishedName)) { $hasData = $true; $legacyCount += $legacyBitLockerIndex[$comp.DistinguishedName].Count }
        }
        if ($doLaps) {
            if (Test-FakeLapsValue $comp.'ms-Mcs-AdmPwd') { $hasData = $true }
            elseif ($useLegacy -and (Get-LegacyLapsMatch -Computer $comp -IsWindowsLaps $false)) { $hasData = $true; $legacyCount++ }
        }
        if ($doWinLaps) {
            if (Test-FakeLapsValue $comp.'msLAPS-Password') { $hasData = $true }
            elseif ($useLegacy -and (Get-LegacyLapsMatch -Computer $comp -IsWindowsLaps $true)) { $hasData = $true; $legacyCount++ }
        }
        if ($hasData) { $selected.Add($comp) }
    }
    $targets = @($selected.ToArray())

    if ($doDummies) {
        foreach ($comp in $allComputers) {
            if ($Mode -eq 'Clean' -and (Test-MarkedDummyComputer -Name $comp.Name -Description $comp.Description -Enabled $comp.Enabled)) {
                $dummyCandidates.Add([pscustomobject]@{ Computer = $comp; IsLegacy = $false })
            } elseif ($useLegacy -and (Test-LegacyDummyComputerFingerprint -Name $comp.Name -Description $comp.Description -Enabled $comp.Enabled)) {
                $dummyCandidates.Add([pscustomobject]@{ Computer = $comp; IsLegacy = $true })
                $legacyCount++
            }
        }
    }
}

$targetCount = $targets.Count + $neededDummies
if ($targetCount -eq 0 -and $dummyCandidates.Count -eq 0) {
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
    if ($RemoveDummyComputers) {
        $markedDummyCount = @($dummyCandidates | Where-Object { -not $_.IsLegacy }).Count
        $confirmationPrompt += "`n  - Markierte Dummy-Computer (FAKE-PC-*) zum Entfernen: $markedDummyCount"
    }
}
if ($useLegacy) {
    $confirmationPrompt += "`n  - Per Fingerabdruck erkannte Legacy-Elemente (0.0.1, ohne Marker): $legacyCount"
    if ($Mode -eq 'Clean' -and $legacyCount -gt 0) {
        $confirmationPrompt += " – Entfernen erfordert eine zusätzliche Bestätigung"
    }
}
$confirmationPrompt += "`n  - WARNUNG: Nur in Test-/Laborumgebungen verwenden!"

if (-not $Quiet -and -not $WhatIfPreference -and -not $PSCmdlet.ShouldContinue($confirmationPrompt, "Soll die Aktion ausgeführt werden?")) {
    Write-Warning "Aktion vom Benutzer abgebrochen."
    return
}

# Zusätzliche, ausdrückliche Zustimmung für das Entfernen nicht markierter Legacy-Daten
if ($Mode -eq 'Clean' -and $useLegacy -and $legacyCount -gt 0) {
    if ($WhatIfPreference -or $ForceLegacyClean) {
        # -WhatIf löscht nichts (ShouldProcess liefert $false), -ForceLegacyClean ist die ausdrückliche Zustimmung
        $script:LegacyRemovalApproved = $true
    } elseif (-not $Quiet) {
        $legacyPrompt = "`n$legacyCount nicht markierte Elemente wurden über Fingerabdrücke der Version 0.0.1 als Fake-Daten erkannt " +
            "(Details: Get-Help .\fakeBitlockerData.ps1 -Full).`nDiese Elemente tragen KEINEN Marker. Prüfen Sie sie vorher mit " +
            "'-Mode Verify -IncludeLegacy'.`nNicht bestätigte Legacy-Elemente bleiben unverändert, markierte Fake-Daten werden trotzdem entfernt."
        $script:LegacyRemovalApproved = $PSCmdlet.ShouldContinue($legacyPrompt, 'Sollen die erkannten Legacy-Daten (0.0.1) ebenfalls entfernt werden?')
        if (-not $script:LegacyRemovalApproved) {
            Write-Warning "Legacy-Daten (0.0.1) werden nicht entfernt."
        }
    }
}

if ($neededDummies -gt 0) {
    $targets += @(New-DummyComputer -Needed $neededDummies -SB $SearchBase)
}

Write-ScriptLog "Starte Modus '$Mode' für '$DataType' auf $($targets.Count) Computern..." 'Cyan'

$results = New-Object System.Collections.Generic.List[object]
foreach ($c in $targets) {
    if ($doBitLocker) { foreach ($r in @(Invoke-BitLockerAction -Computer $c -FakeIndex $fakeBitLockerIndex -LegacyIndex $legacyBitLockerIndex)) { $results.Add($r) } }
    if ($doLaps)      { $results.Add((Invoke-LapsAction -Computer $c -IsWindowsLaps $false)) }
    if ($doWinLaps)   { $results.Add((Invoke-LapsAction -Computer $c -IsWindowsLaps $true)) }
}

# Dummy-Computer erst nach den Daten bearbeiten (deren Fake-Unterobjekte sind dann bereits entfernt)
foreach ($candidate in $dummyCandidates) {
    if ($Mode -eq 'Clean') {
        $results.Add((Remove-FakeDummyComputer -Computer $candidate.Computer -IsLegacy $candidate.IsLegacy))
    } else {
        $results.Add([pscustomobject][ordered]@{
            Computer = $candidate.Computer.Name; Type = 'DummyComputer'; Status = $script:LegacyStatus; Success = $true
            Info     = 'Dummy-Computer aus Version 0.0.1 (Fingerabdruck D1, deaktiviert). Entfernen mit -Mode Clean -IncludeLegacy -RemoveDummyComputers.'
        })
    }
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
