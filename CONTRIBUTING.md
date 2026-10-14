# Contributing / Mitwirken

Danke, dass du die PhinIT PowerShell Tools verbessern möchtest!

## Ablauf

1. Repository forken und einen Feature-Branch anlegen.
2. Das jeweilige Skript unter `src/<Tool>/<Tool>.ps1` ändern. Pro Tool gibt es **genau ein** Skript –
   keine versionierten Kopien (`<Tool>_Vx.y.z.ps1`) und keine Archivordner (`# Versions`, `#VERSION`) anlegen.
   Ältere Stände sind über die Git-Historie verfügbar.
3. Die Prüfungen unten ausführen.
4. Einen Eintrag in [CHANGELOG.md](CHANGELOG.md) unter einer **konkreten Version mit Datum** anlegen
   (`## DD.MM.YYYY` → `### <Tool> x.y.z`). Einen Abschnitt „Unreleased“ gibt es nicht.
5. Die Version im Skript (Kommentar-Header und ggf. Konfiguration/Fenstertitel) sowie in der README des Tools
   und in der Tool-Tabelle der Haupt-[README](README.md) anpassen.
6. Pull Request mit aussagekräftiger Beschreibung erstellen.

## Prüfungen

```powershell
# Syntaxprüfung aller Skripte
Get-ChildItem -Path ./src -Filter *.ps1 -Recurse | ForEach-Object {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
    '{0}: {1} Fehler' -f $_.Name, $errors.Count
}

# Statische Analyse
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

Erwartetes Ergebnis: 0 Parser-Fehler und 0 PSScriptAnalyzer-Befunde (alle Schweregrade). Unterdrückungen
(`SuppressMessageAttribute`) nur mit konkreter `Justification`, wenn eine echte Korrektur nicht möglich ist.

Funktionstests benötigen Windows (WPF/WinForms) und – je nach Tool – Active Directory bzw. Administratorrechte.
AD-Tools ausschließlich in Test-/Laborumgebungen testen.

## Regeln für den Code

- Encoding: **UTF-8 mit BOM** (erforderlich für Windows PowerShell 5.1, sonst werden Umlaute falsch dargestellt).
- Pfade immer relativ zu `$PSScriptRoot` bilden, nie relativ zum aktuellen Arbeitsverzeichnis.
- Laufzeitdaten (`Logs/`, Exporte, Backups) gehören nicht ins Repository (siehe `.gitignore`).
- Keine Kennwörter, Tokens, internen Hostnamen/IP-Adressen oder echte Benutzerdaten committen.
- Keine `Invoke-Expression`-Aufrufe mit Benutzereingaben; externe Programme mit sauber gequoteten Argumenten starten.
- Benutzereingaben validieren, bevor sie an AD-/System-Cmdlets übergeben werden.
- Schreibende AD-/Systemoperationen nur nach Bestätigung bzw. mit `-WhatIf`/`-Confirm`-Unterstützung.
- Generische Listen statt `+=` auf Arrays in Schleifen verwenden.
- Den UI-Thread nicht mit `Start-Sleep` oder lang laufenden Operationen blockieren.
- Oberflächentexte auf Deutsch; technische Werte (Cmdlet-, Policy-, Scope-, AD-Attributnamen, Fehlercodes) bleiben unverändert.
- Funktionen mit genehmigten Verben (`Get-Verb`) und Nomen im Singular benennen; `$script:` statt `$Global:`.
- Screenshots gehören nach `assets/screenshots/<Tool>/` (Dateiname: `<Tool>_<Version>_<Ansicht>.png`).

## Code-Signing

Geänderte Skripte verlieren ihre Authenticode-Signatur. Signiert wird ausschließlich durch den Maintainer
(siehe [README](README.md#code-signing)). Bitte keine Signaturblöcke in Pull Requests einchecken.
