# Changelog

Alle relevanten Änderungen an den PhinIT PowerShell Tools werden in dieser Datei dokumentiert.
Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), die Tools verwenden [Semantic Versioning](https://semver.org/lang/de/).
Jeder Eintrag gehört zu einem veröffentlichten Stand mit Datum (`DD.MM.YYYY`) und – je Tool – zu einer konkreten Version.

> Da im Repository keine Pull Requests existieren, wurde der Verlauf bis 18.07.2025 aus der Git-Commit-Historie rekonstruiert.

## 14.10.2026

Audit-Release: easyWINUpdate 0.2.4 · easyPSInfo 0.0.4 · easyExecutionPolicy 0.0.4 · easyADDummyUserCreator 0.0.3 · fakeBitlockerData 0.0.2.
Vollständiger Bericht: [docs/AUDIT.md](docs/AUDIT.md).

### Repository
- Neue Ordnerstruktur: `src/<Tool>/<Tool>.ps1` (ein Skript pro Tool, ohne Versionsnummer im Dateinamen), `docs/`, `assets/screenshots/<Tool>/`.
- Ordner `Dummy Active Directoy` (Tippfehler, Leerzeichen) aufgelöst: `src/easyADDummyUserCreator/` und `src/fakeBitlockerData/`.
- Entfernt: alle Archivversionen (`# Versions`, `#VERSION`): easyADDummyUserCreator 0.0.1/0.0.2, easyExecutionPolicy 0.0.1/0.0.2, easyPSInfo 0.0.1/0.0.2, easyWINUpdate 0.0.11/0.1.5/0.2.3 (Duplikat).
- Entfernt: alle Screenshots (`Screeshot_V0.0.2.jpg`, `Screeshot_V0.0.3.jpg`, `easyPSInfo_EXAMPLE-V0.0.3.jpg`, `Screenshot_V0.1.4.jpg`).
- Entfernt: eingecheckte Logdatei `easyPSInfo/Logs/easySTARTUP_Setup.log` (enthielt einen internen UNC-Pfad mit IP-Adresse) und die leere `Dummy Active Directoy/Readme.md`.
- Hinzugefügt: `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `docs/AUDIT.md` sowie eine README je Tool; Haupt-README neu geschrieben.
- `.gitignore` überarbeitet (`Logs/`, `Exports/`, Archivordner, Backups; Beispiel-CSV ausgenommen).
- Alle Skripte als UTF-8 mit BOM gespeichert (Umlaute unter Windows PowerShell 5.1).
- Authenticode-Signaturen entfernt (durch die Codeänderungen ungültig) – Anleitung zum Neusignieren in der README.

### easyWINUpdate 0.2.4

#### Sicherheit
- Geplante Aufgabe (läuft als SYSTEM) führte ein Skript aus dem für Benutzer beschreibbaren `%TEMP%` aus (Rechteausweitung) – Skript liegt jetzt in `%ProgramData%\easyWINUpdate` mit Zugriff nur für SYSTEM und Administratoren.
- `Invoke-Expression` für `sc.exe sdset` und `schtasks` entfernt (direkter Aufruf mit Exit-Code-Prüfung bzw. Task-Scheduler-COM).
- Prüfung auf Administratorrechte beim Start mit automatischem Neustart (UAC, STA).
- WSUS-Server (Hostname) und -Port (1–65535) sowie KB-Nummern für `wusa.exe` werden validiert; `wusa.exe` mit vollem Pfad.
- „Reset WSUS“ löscht nur noch die WSUS-Werte statt des gesamten Richtlinienschlüssels `Policies\WindowsUpdate`.

#### Behoben
- Log-Analyse brach immer ab (`foreach ($error …)` überschrieb die automatische Variable).
- Laufzeitfehler durch `-Value (if …)` beim Setzen von GPO-Werten.
- Unterschiedliche Aufgabennamen beim Anlegen, Anzeigen und Löschen der geplanten Aufgabe; sprachabhängige Statusabfrage.
- Neustart-Option wurde über einen Text ausgewertet, der nicht zum XAML passte.
- Geplante Aufgabe wartete als SYSTEM auf eine Bestätigung (`-AcceptAll`, Transcript-Log); PSWindowsUpdate für SYSTEM nicht ladbar.
- Haken „Auto-Update aktiv“ war wegen eines Text-zu-bool-Fehlers immer gesetzt; Wochentage doppelt in der Auswahl.
- Buttons im DataGrid (Entfernen/Installieren) funktionierten nie (`FindName` in DataTemplate).
- Handler für nicht vorhandene Controls und Aufruf der nicht vorhandenen Funktion `SwitchPage`; 9 Buttons ohne Funktion (GPO-Einstellungen, Zielgruppen, Synchronisierung, Temp bereinigen, Winsock, CHKDSK) mit Handlern versehen.
- `DetectionFrequency`/`RebootRelaunchTimeout` mit falschen Wertebereichen bzw. fehlenden Aktivierungswerten; toter `AUOptions`-Code.
- Fehlererkennung hing an der deutschen Anzeige „Fehler“ (jetzt über den Level).
- WSUS-Verbindungstest per Ping ersetzt durch TCP-Test auf den WSUS-Port.
- Startseite wurde doppelt geladen; Hintergrundaufgaben wurden beim Schließen nicht aufgeräumt.
- PSScriptAnalyzer: `$null`-Vergleiche, Zuweisungen an automatische Variablen, Switch-Parameter mit Standardwert `$true`.

#### Geändert
- Updatesuche, Installation, Download, Deinstallation, installierte Updates, Wiederherstellungspunkt, Log-Analyse und „Hängende Updates entfernen“ laufen im Hintergrund (Runspace) – die GUI friert nicht mehr ein; DISM/SFC/CHKDSK in eigenem Konsolenfenster.
- Echte Updatesuche über die Windows-Update-API und echter WSUS-Synchronisierungsverlauf (Ereignisse 25/26); Installation über Update-IDs (konfigurierte WSUS-Quelle wird beachtet).
- `wuauclt /detectnow` durch `UsoClient StartScan` ersetzt (Fallback für ältere Systeme).
- Logdatei im Unterordner `Logs`; CSV-Export auf den echten Desktop-Pfad (auch OneDrive) in UTF-8.
- `Write-Log` in `Write-AppLog` umbenannt; Version 0.2.4 und Branding „Andreas Hepp | PhinIT“ überall einheitlich.

#### Entfernt
- Simulierte Update- und Synchronisierungsdaten, `schtasks`-Textauswertung, `Start-Sleep`-Wartezeiten.

### easyPSInfo 0.0.4

#### Sicherheit
- Pfade im Log werden maskiert (Skriptordner, Benutzerprofil, `\\Server\Freigabe`) – Ursache des Lecks im zuvor eingecheckten Log.
- PSGallery wird nicht mehr dauerhaft als „Trusted“ eingetragen; jede Modulinstallation muss bestätigt werden (`-Scope CurrentUser -Repository PSGallery`).
- Unrestricted/Bypass für dauerhafte Scopes nur nach Sicherheitsabfrage.
- Weblinks werden nur mit `http`/`https` geöffnet; das Tool bietet sich nicht mehr selbst im Script-Launcher an.

#### Behoben
- Button „Refresh Modules“ ohne Funktion (Handler suchte `btnRefresh`).
- Neustart als Administrator verlor den Skriptpfad (`$MyInvocation` in einer Funktion) und startete immer Windows PowerShell.
- Logpfad brach bei leerem `$PSScriptRoot` (z. B. ISE-Auswahl); Fallback-Ordner bei fehlenden Schreibrechten; Logfehler brechen das Tool nicht mehr ab.
- Gestartete Skripte überschrieben die GUI-Variablen (`$Global:window`, `$Global:txtLog`).
- Log-Fenster scrollte nicht mit; Policy-Buttons waren auch für GPO- und Effective-Zeilen aktiv.
- „Überschrieben durch spezifischeren Scope“ wurde als Fehler statt als Warnung gemeldet; Fehler gestarteter Skripte erscheinen jetzt auch in der GUI.
- PSScriptAnalyzer: Zuweisung an `$matches`, `$null`-Vergleich, leerer `catch`-Block.

#### Geändert
- Modulinstallation im Hintergrund-Runspace; parallele Installationen werden verhindert; TLS 1.2 unter PS 5.1; NuGet-Provider mit Mindestversion.
- Modulstatus mit einem einzigen `Get-Module -ListAvailable`; Skriptsuche mit generischen Listen.
- Einheitlicher Titel „PhinIT | easyPSInfo“, Version 0.0.4, Kommentar-Header; STA-Prüfung beim Start.
- Logdatei heißt `easyPSInfo.log` statt `easySTARTUP_Setup.log`.

#### Entfernt
- Ungenutzte Funktion `Test-ModuleInstalled` und spekulative Suchpfade (`Documents\...\Modules`).

### easyExecutionPolicy 0.0.4

#### Sicherheit
- Backup-/Importdateien werden geprüft (max. 1 MB, Struktur, nur erlaubte Scopes und Policy-Werte); Texte aus Dateien werden bereinigt.
- Vor jedem `Set-ExecutionPolicy -Force` Bestätigung mit Übersicht „alt → neu“; Warnung vor Unrestricted/Bypass beim Restore.

#### Behoben
- Neustart als Administrator verlor den Skriptpfad und nutzte immer Windows PowerShell (jetzt gleicher Host, `-NoProfile`).
- Restore aus dem Arbeitsspeicher stellte nie etwas wieder her (Hashtable-Schlüssel).
- Falsche Erfolgsmeldungen bei fehlgeschlagenem Restore/Backup (Rückgabewert von `MessageBox::Show`).
- Abbruch des Anwendens nach abgelehnter Sicherheitswarnung (`continue` in `ForEach-Object`).
- `Undefined` wurde beim Restore übersprungen bzw. unter PowerShell 7 falsch per Registry gesetzt.
- Durch GPO/Process überschriebene Einstellungen werden als Hinweis statt als Fehler gemeldet.
- Automatische Backups wurden nie nach `AutoBackups` geschrieben (jetzt beim Start, Rotation auf 10 Dateien).
- Statuszeile wurde abgeschnitten.

#### Geändert
- Kommentarbasierter Hilfe-Header (Version 0.0.4, Andreas Hepp | PhinIT), Version im Fenstertitel.
- Import nutzt die gemeinsame, geprüfte Restore-Logik; Pfade mit `Join-Path`/`-LiteralPath`.

### easyADDummyUserCreator 0.0.3

#### Sicherheit
- Hart codiertes Standardkennwort `P@sswOrd123!` sowie feste Kennwörter (`123`, `Test123!`, `P@ssw0rd123!`) entfernt; neues GUI-Feld „Initial-Passwort“, sonst eigenes kryptografisch sicheres Zufallskennwort je Benutzer.
- Kennwortumwandlung zentralisiert (kein `ConvertTo-SecureString -AsPlainText` mehr); Kennwörter werden nie protokolliert.
- OUs werden nur nach Prüfung des Inhalts rekursiv gelöscht, bei fremden Objekten mit gesonderter Rückfrage.
- Löschfunktionen entfernen nur tatsächlich gelöschte Objekte aus den Listen der erstellten Objekte.
- Werte in AD-`-Filter`-Ausdrücken werden maskiert (z. B. „O'Brien“).

#### Behoben
- Testdaten-Set scheiterte komplett (OU-Namen `USER`/`COMPUTER` vs. `USERS`/`COMPUTERS`).
- SPNs ohne Port (`"$host:80"`), nicht eindeutige SPNs, Namensmuster `svc-*` statt `svc_*`.
- BitLocker: Ausnahme bei `Substring(0,40)`, Setzen des Systemattributs `whenCreated`, GUIDs als Text statt Bytes, Fehler bei nur einem Computer, ungültiges Recovery-Passwort-Format.
- LAPS: Auswahl bei nur einem System und Kennwortlänge.
- Passwortrichtlinien setzten vom AD abgelehnte Attribute (`pwdLastSet`, `badPwdCount`, `lockoutTime`).
- Verschachtelte Gruppen: ungültige Bereichskombinationen, immer Verteilergruppen; `Quick-CreateGroups` erfasste Gruppen nicht.
- Chaos-Modus verlor trotz Fehler angelegte Benutzer; fehlende Zeilenumbrüche in Dialogen.
- Überlange sAMAccountNames (> 20) und Computernamen (> 15); undefinierte Variable im Ergebnistext.
- CSV-Import: Ländercodes (ISO 3166), führende Nullen bei Postleitzahlen, LDAP-Namen, mehrere proxyAddresses, HomeDrive, Manager-Auflösung.
- Zahleneingaben mit Buchstaben führten zu Ausnahmen; leerer `catch`-Block.

#### Geändert
- Pfade basieren auf dem Skriptordner (`AD_DummyUserList.csv`, `Logs\`, `Exports\`) statt auf dem aktuellen Arbeitsverzeichnis.
- Domäneninformationen und Benutzerauflösung werden zwischengespeichert, Gruppenmitglieder in einem Aufruf hinzugefügt, Ergebnislisten ohne `+=`.
- GUI aktualisiert sich während langer Vorgänge, ist dabei gesperrt (keine Doppelstarts) und fängt Fehler zentral ab.
- Version einheitlich 0.0.3 (Header nannte 0.1.0), Autor „Andreas Hepp | PhinIT“.

#### Entfernt
- `DefaultPassword` aus der Konfiguration; ungültige Attributzuweisungen (`whenCreated`, `badPwdCount`, `lockoutTime`, `ManagedBy = $null`).

### fakeBitlockerData 0.0.2

#### Sicherheit
- `Verify` zeigte und exportierte **echte** BitLocker-Schlüssel und LAPS-Kennwörter aller Computer – jetzt nur noch markierte Fake-Daten.
- `Clean` löschte **alle** BitLocker-Objekte und LAPS-Attribute – jetzt nur noch markierte Fake-Daten (Marker `adminDescription=PhinIT-FakeTestData` bzw. Präfix `FAKE-`).
- `Create` überschrieb echte LAPS-Kennwörter und beschrieb Domänencontroller – beides ausgeschlossen.
- Fake-Kennwörter mit kryptografisch sicherem Zufallsgenerator statt `Get-Random`.
- Dummy-Computer werden erst nach der Sicherheitsabfrage angelegt.

#### Behoben
- BitLocker-Objekte konnten nicht angelegt werden (LDAP-Namen, Pflichtattribut `msFVE-RecoveryGuid`, Objektname); Recovery-Passwort-Format.
- Windows LAPS: Ablaufzeit als FILETIME, Kennwort im JSON-Format.
- Doppelte Zeilen bei `Verify`/`Clean`; feste Spalten in Tabelle und CSV.
- Gleicher Hotkey für „Create“ und „Clean“ in der interaktiven Auswahl.
- `-WhatIf`/`-Confirm` wirken bei allen schreibenden und löschenden AD-Operationen.
- Fehler bei genau einem gefundenen Computer; Absturz bei sehr großen `Count`-Eingaben; Fehler bei fehlenden LAPS-Schemaattributen.

#### Geändert
- Kommentarbasierte Hilfe mit Testlab-Warnung, `#requires`, Version 0.0.2.
- `-Quiet` unterdrückt alle Abfragen; `-Mode` und `-DataType` sind dann Pflicht.
- Weniger AD-Abfragen (Attribute mit der ersten Abfrage, eine Subtree-Suche für BitLocker-Objekte), generische Listen.
- CSV standardmäßig unter `<Skriptordner>\Logs`; `Write-Log` in `Write-ScriptLog` umbenannt.

## 18.07.2025

### Repository
- Entfernt: `Other Scripts/SPOSiteURL.ps1` (vier Tage nach dem Hinzufügen wieder entfernt).

## 14.07.2025

### Repository
- Hinzugefügt: `Other Scripts/SPOSiteURL.ps1` – Umwandlung einer SharePoint-Site-URL in eine für Gruppenrichtlinien verwendbare URL.

## 12.07.2025

### fakeBitlockerData 0.0.1
- Hinzugefügt: Konsolenskript zum Erstellen (`Create`), Prüfen (`Verify`) und Entfernen (`Clean`) von Fake-BitLocker-Wiederherstellungsdaten sowie Legacy-LAPS- und Windows-LAPS-Attributen an AD-Computerobjekten für Testumgebungen, inkl. CSV-Export.

### easyWINUpdate 0.2.3
- Behoben: Das am 01.07.2025 versehentlich geleerte Skript `easyWINUpdate_V0.2.3.ps1` wurde wiederhergestellt.

### Repository
- Alle Skripte (easyADDummyUserCreator, easyExecutionPolicy, easyPSInfo, easyWINUpdate inkl. Archivversionen) mit Authenticode signiert.

## 03.07.2025

### Repository
- Entfernt: easyADReport (letzte Version 0.5.3) wurde in ein eigenes Repository ausgelagert – inkl. aller Archivversionen und Screenshots.

## 02.07.2025

### easyADDummyUserCreator 0.0.2
- Behoben: diverse Fehler der Version 0.0.1.
- Entfernt: versehentlich eingecheckte Logdatei `easyADDummyUserCreator.log`.

### easyADDummyUserCreator 0.0.1
- Geändert: Versionsnummer im Dateinamen eingeführt (`easyADDummyUserCreator_V0.0.1.ps1`).

### easyADReport 0.5.3
- Hinzugefügt: neue Reports (u. a. Compromise Indicators, OU-Hierarchie), neue Screenshots, README überarbeitet.

## 01.07.2025

### easyADReport 0.4.2 / 0.5.1-BETA
- Hinzugefügt: Quick Reports implementiert und getestet; Design und Menü angepasst; README hinzugefügt.

### easyWINUpdate 0.2.3
- Fehler: Das Skript `easyWINUpdate_V0.2.3.ps1` wurde versehentlich geleert (am 12.07.2025 wiederhergestellt).

## 29.06.2025

### easyADDummyUserCreator (erste Version, ohne Versionsnummer)
- Hinzugefügt: WPF-GUI zum Anlegen von AD-Dummy-Benutzern aus einer CSV-Datei inkl. Beispieldaten `AD_DummyUserList.csv`.
- Entfernt: Vorläuferskript `ADDummys/Create_DummyUsers.ps1`.

### easyWINUpdate 0.2.3
- Geändert: Überarbeitung und Fehlerbehebungen gegenüber 0.2.1.

### easyADReport 0.3.1 – 0.3.3
- Hinzugefügt: neue Versionen mit Fehlerbehebungen.

## 09.06.2025

### Repository
- Hinzugefügt: `ADDummys/Create_DummyUsers.ps1` (Vorläufer von easyADDummyUserCreator).

### easyADReport 0.2.2 – 0.2.4
- Hinzugefügt: neue Quick Reports; Fehlerbehebungen.

## 07.06.2025

### easyExecutionPolicy 0.0.3
- Geändert: GUI-Redesign.

### easyExecutionPolicy 0.0.2
- Geändert: GUI überarbeitet; Screenshots hinzugefügt.

### easyPSInfo 0.0.3
- Geändert: GUI-Redesign.

### easyADReport 0.1.2 – 0.2.1
- Hinzugefügt: neue Reports; Fehlerbehebungen.

## 02.06.2025

### easyPSInfo 0.0.3
- Behoben: diverse Fehler.
- Geändert: Versionen 0.0.1 und 0.0.2 in den Archivordner verschoben.

### Repository
- Hinzugefügt: `.gitignore`.

## 01.06.2025

### easyExecutionPolicy 0.0.1
- Hinzugefügt: Tooltips in der GUI.
- Behoben: diverse Fehler.
- Geändert: Versionsnummer im Dateinamen eingeführt (`easyExecutionPolicy_V0.0.1.ps1`).

## 31.05.2025

### easyWINUpdate 0.2.3
- Hinzugefügt: neue Version; 0.2.1 und Screenshot 0.1.4 ins Archiv verschoben.

### easyADReport 0.1.1
- Geändert: GUI-Anpassungen.

### Repository
- Entfernt: easyADFind, easyADPASSWORD, easyINIEditor, easySPO sowie die Screenshots von easyMS365License und easyWSMigrate.

## 29.05.2025

### easyADReport 0.0.13 – 0.1.1
- Hinzugefügt: Nachfolger von easyADAudit – Benutzer- und Gruppensuche mit Quick Reports und Custom Reports; Grundfunktionen im Versionszweig 0.0.x implementiert und getestet.

### Repository
- Entfernt: easyADAudit (in easyADReport aufgegangen).

## 27.05.2025

### easyWINUpdate 0.2.1
- Hinzugefügt: neue Version; 0.1.4 als 0.1.5 archiviert.

### easyWINUpdate 0.1.4
- Hinzugefügt: Troubleshooting-Bereich (Fehlercodes mit Lösungsvorschlägen); Screenshot.
- Behoben: diverse Fehler.

### easyWINUpdate 0.0.2
- Hinzugefügt: neue Projektversion; alte GUI-/Asset-Dateien entfernt.

### easyADAudit 0.0.2
- Hinzugefügt: erste lauffähige Version; GUI-Fehler behoben.

## 26.05.2025

### Repository
- Geändert: easyWS in easyWSMigrate umbenannt und um Funktionen erweitert; anschließend in ein eigenes Repository ausgelagert.
- Hinzugefügt: Screenshots von easyMS365License 0.0.94 und easyWSMigrate 0.0.51.

## 24.05.2025

### Repository
- Entfernt: easyWSAudit (Version 0.2.3, alle Funktionen getestet) in ein eigenes Repository ausgelagert.
- Entfernt: Ordner `Logs/` und `easyWSAudit/audit_log.txt`.

## 23.05.2025

### Repository
- Hinzugefügt: Initial Commit mit `LICENSE` (MIT) und `README.md`.
- Hinzugefügt: erste Tool-Sammlung „PowerShell GUI Tools for Windows & M365 Admins“: easyADFind, easyExecutionPolicy, easyINIEditor 0.5.1, easyPowerShell (easyStartUp 0.0.1 – 0.0.3), easySPO, easyWINServer, easyWusaWSUS (easyWINUpdate 0.0.1), easyADPASSWORD 0.0.1, easyWSAudit 0.0.1 – 0.0.3.
- Geändert: Ordner umbenannt – easyPowerShell → easyPSInfo, easyWusaWSUS → easyWINUpdate, easyADFind → easyADAudit, easyWINServer → easyWS.
- Entfernt: eingecheckte Logdateien.

### easyPSInfo 0.0.1 – 0.0.3
- Hinzugefügt: PowerShell-Modul- und Policy-Manager mit Script-Launcher (zunächst als easyStartUp).

### easyWINUpdate 0.0.1
- Hinzugefügt: erste Version der Windows-Update-Verwaltung mit GUI.

### easyExecutionPolicy (erste Version)
- Hinzugefügt: GUI zum Anzeigen und Ändern der PowerShell-Ausführungsrichtlinien.
