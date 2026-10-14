# Audit PhinIT PowerShell Tools – 14.10.2026

**Umfang:** alle Tools des Repositorys – Sicherheit, Performance, Funktionen, Verweise, GUI, Befehle, Repository-Struktur und Dokumentation.
**Methode:** Code-Review aller Funktionen und Event-Handler, PowerShell-Parser, PSScriptAnalyzer 1.25, XAML-Wohlgeformtheit,
Abgleich XAML-Controls ↔ Verwendung im Code, Tests einzelner Hilfsfunktionen unter PowerShell 7.

Status: ✅ behoben · ⚠️ dokumentiertes Restrisiko / offen

Die zunächst offenen Punkte wurden am selben Tag in einer zweiten Runde abgearbeitet (siehe [Nacharbeiten](#nacharbeiten--zweite-runde)).

| Tool | Version vorher → Audit → Nacharbeiten | Datei |
|------|---------------------------------------|-------|
| easyWINUpdate | 0.2.3 → 0.2.4 → 0.2.5 | `src/easyWINUpdate/easyWINUpdate.ps1` |
| easyPSInfo | 0.0.3 → 0.0.4 → 0.0.5 | `src/easyPSInfo/easyPSInfo.ps1` |
| easyExecutionPolicy | 0.0.3 → 0.0.4 → 0.0.5 | `src/easyExecutionPolicy/easyExecutionPolicy.ps1` |
| easyADDummyUserCreator | 0.0.2 → 0.0.3 → 0.0.4 | `src/easyADDummyUserCreator/easyADDummyUserCreator.ps1` |
| fakeBitlockerData | 0.0.1 → 0.0.2 → 0.0.3 | `src/fakeBitlockerData/fakeBitlockerData.ps1` |

## Repository

| # | Befund | Status |
|---|--------|--------|
| R1 | Archivversionen (`# Versions`, `#VERSION`) und ein exaktes Duplikat (`easyWINUpdate_V0.2.3.ps1`) neben den aktuellen Skripten | ✅ entfernt (Git-Historie) |
| R2 | Veraltete Screenshots, Tippfehler im Dateinamen (`Screeshot_…`) | ✅ entfernt, Ablage `assets/screenshots/<Tool>/` |
| R3 | Eingecheckte Logdatei mit internem UNC-Pfad und IP-Adresse (`easySTARTUP_Setup.log`) trotz `.gitignore` | ✅ entfernt, `.gitignore` überarbeitet, Log-Maskierung in easyPSInfo |
| R4 | Ordner `Dummy Active Directoy` (Tippfehler, Leerzeichen) mit zwei unabhängigen Tools und leerer `Readme.md` | ✅ `src/easyADDummyUserCreator/`, `src/fakeBitlockerData/` |
| R5 | Kein CHANGELOG, keine SECURITY/CONTRIBUTING/CODE_OF_CONDUCT, README nur für easyWINUpdate | ✅ angelegt (CHANGELOG aus der Git-Historie, da keine Pull Requests existieren) |
| R6 | README von easyWINUpdate verwies auf nicht existierende `easyWINUpdate.ps1` und „interne Lizenz“ (Widerspruch zu MIT) | ✅ |
| R7 | Dateien UTF-8 ohne BOM – Umlaute in Windows PowerShell 5.1 fehlerhaft | ✅ UTF-8 mit BOM |
| R8 | Authenticode-Signaturen durch Codeänderungen ungültig | ✅ entfernt, Anleitung zum Neusignieren in README · ⚠️ Neusignierung durch den Maintainer erforderlich |
| R9 | `*.csv` in `.gitignore` schloss die benötigte Beispiel-CSV aus | ✅ Ausnahme ergänzt |

## easyWINUpdate 0.2.3 → 0.2.4

| # | Kategorie | Befund | Status |
|---|-----------|--------|--------|
| W1 | Sicherheit | Geplante Aufgabe als SYSTEM startete ein Skript aus `%TEMP%` des Benutzers (auch von nicht erhöhten Prozessen beschreibbar → Rechteausweitung) | ✅ `%ProgramFiles%\PhinIT\easyWINUpdate`, Besitzer Administratoren, ACL nur SYSTEM/Administratoren, fremde Ordner/Dateien werden ersetzt |
| W2 | Sicherheit | 2× `Invoke-Expression` (`sc.exe sdset`, `schtasks`) | ✅ direkter Aufruf / Task-Scheduler-COM |
| W3 | Sicherheit | Keine Prüfung auf Administratorrechte | ✅ Neustart mit UAC und STA |
| W4 | Sicherheit | WSUS-Server/-Port und KB-Nummern ungeprüft | ✅ Validierung, `wusa.exe` mit vollem Pfad |
| W5 | Sicherheit | „Reset WSUS“ löschte den gesamten Schlüssel `Policies\WindowsUpdate` | ✅ nur WSUS-Werte |
| W6 | Sicherheit | PSWindowsUpdate wird bei Bedarf automatisch aus der PSGallery installiert | ⚠️ Verhalten beibehalten |
| W7 | Performance | Suche/Installation/Download/Deinstallation/Log-Analyse blockierten die GUI | ✅ Runspace + DispatcherTimer |
| W8 | Performance | DISM/SFC/CHKDSK blockierten die GUI | ✅ eigenes Konsolenfenster |
| W9 | Performance | Auto-Fix, Komponenten-Reset, Registry-/Datenbank-Reparatur synchron | ✅ in 0.2.5 (N1) |
| W10 | Funktionen | Log-Analyse brach immer ab (`foreach ($error …)`) | ✅ |
| W11 | Funktionen | „Verfügbare Updates“ und WSUS-Synchronisierungsverlauf waren simulierte Daten | ✅ Windows-Update-API, Ereignisse 25/26 |
| W12 | Funktionen | `-Value (if …)` Laufzeitfehler; Text-zu-bool-Fehler beim Auto-Update-Haken | ✅ |
| W13 | Funktionen | Aufgabenname uneinheitlich, Statusabfrage sprachabhängig, SYSTEM-Aufgabe wartete auf Bestätigung | ✅ |
| W14 | Funktionen | `wuauclt /detectnow` ab Windows 10 wirkungslos | ✅ `UsoClient StartScan` mit Fallback |
| W15 | Funktionen | `DetectionFrequency`/`RebootRelaunchTimeout` falsche Wertebereiche; toter `AUOptions`-Code | ✅ |
| W16 | Funktionen | WSUS-Zielgruppen feste Liste; Weekly/Monthly auf 22 h begrenzt | ⚠️ Grenze von WSUS-Konsole bzw. Richtlinie |
| W17 | Verweise | Handler für nicht vorhandene Controls, Aufruf der fehlenden Funktion `SwitchPage` | ✅ entfernt |
| W18 | Verweise | 9 Buttons ohne Handler | ✅ ergänzt |
| W19 | GUI | DataGrid-Buttons funktionierten nie (`FindName` in DataTemplate) | ✅ zentrales Click-Routing |
| W20 | GUI | Versionsanzeige v0.2.1/v0.2.3, doppelte Wochentage, Startseite doppelt geladen | ✅ |
| W21 | Befehle | 9× `$null`-Vergleich rechts, 5× Zuweisung an automatische Variablen, 3× Switch-Default `$true`, `Write-Log`-Namenskonflikt | ✅ |
| W22 | Befehle | Export auf `$env:USERPROFILE\Desktop` (falsch bei OneDrive-Umleitung) | ✅ `[Environment]::GetFolderPath('Desktop')`, UTF-8 |

## easyPSInfo 0.0.3 → 0.0.4

| # | Kategorie | Befund | Status |
|---|-----------|--------|--------|
| P1 | Sicherheit | Log enthielt vollständige Pfade (UNC-Server/IP, Benutzerprofil) | ✅ `ConvertTo-SafeLogText` |
| P2 | Sicherheit | PSGallery dauerhaft als „Trusted“ registriert | ✅ entfällt, Bestätigung je Installation |
| P3 | Sicherheit | Unrestricted/Bypass für dauerhafte Scopes ohne Rückfrage | ✅ Sicherheitsabfrage |
| P4 | Sicherheit | Weblinks ohne Schema-Prüfung; Tool konnte sich selbst verschachtelt starten | ✅ |
| P5 | Sicherheit | Script-Launcher | ✅ geprüft: kein `Invoke-Expression`, Start nach Bestätigung |
| P6 | Performance | Modulinstallation im UI-Thread (minutenlanges Einfrieren) | ✅ Runspace, keine Parallelinstallationen |
| P7 | Performance | `Get-Module -ListAvailable` 20× statt 1×; `+=` in der Skriptsuche | ✅ |
| P8 | Funktionen | „Refresh Modules“ ohne Handler | ✅ |
| P9 | Funktionen | Admin-Neustart verlor Skriptpfad, startete immer Windows PowerShell | ✅ |
| P10 | Funktionen | Gestartete Skripte überschrieben globale GUI-Variablen | ✅ sichern/wiederherstellen |
| P11 | Funktionen | AzureAD/MSOnline abgekündigt, aber gelistet | ✅ in 0.0.5 als „abgekündigt“ markiert (N7) · Entfernen bleibt Entscheidung des Autors |
| P12 | Verweise | Logpfad brach bei leerem `$PSScriptRoot`; Logname `easySTARTUP_Setup.log`; spekulative Suchpfade | ✅ |
| P13 | GUI | Uneinheitliche Titel („easyIT Setup“ …), Footer mit alter Version | ✅ „PhinIT \| easyPSInfo“, 0.0.4 |
| P14 | GUI | Log scrollte nicht (`ScrollToEnd` im ScrollViewer); Policy-Buttons für GPO-Zeilen aktiv | ✅ |
| P15 | Befehle | `$matches` überschrieben, `$null`-Vergleich, leerer `catch`, TLS 1.2 fehlte, keine STA-Prüfung | ✅ |

## easyExecutionPolicy 0.0.3 → 0.0.4

| # | Kategorie | Befund | Status |
|---|-----------|--------|--------|
| E1 | Sicherheit | Restore-/Importdateien ungeprüft an `Set-ExecutionPolicy` übergeben | ✅ Größe, Struktur, Scopes, Werte geprüft |
| E2 | Sicherheit | `Set-ExecutionPolicy -Force` ohne Rückfrage | ✅ Bestätigung „alt → neu“ |
| E3 | Sicherheit | Process-Scope nach Admin-Neustart auf `Bypass` | ⚠️ gewollt, nur dieser Prozess; Hinweis bei Überschreibung |
| E4 | Funktionen | Restore aus dem Arbeitsspeicher wirkungslos (Hashtable-Schlüssel) | ✅ |
| E5 | Funktionen | Falsche Erfolgsmeldungen durch Rückgabewert von `MessageBox::Show` | ✅ |
| E6 | Funktionen | `continue` in `ForEach-Object` brach den Handler ab | ✅ |
| E7 | Funktionen | `Undefined` übersprungen bzw. unter PS 7 falsch per Registry gesetzt | ✅ |
| E8 | Funktionen | Automatische Backups wurden nie geschrieben | ✅ inkl. Rotation |
| E9 | Verweise | `$MyInvocation.MyCommand.Path` in Funktion → Skriptpfad beim Neustart verloren; immer `powershell.exe` | ✅ `$PSCommandPath`, gleicher Host |
| E10 | GUI | Statuszeile abgeschnitten; kein Header/keine Version | ✅ |
| E11 | GUI | Sprachmix Deutsch/Englisch | ✅ in 0.0.5 (N4) |

## easyADDummyUserCreator 0.0.2 → 0.0.3

| # | Kategorie | Befund | Status |
|---|-----------|--------|--------|
| A1 | Sicherheit | Hart codiertes Standardkennwort `P@sswOrd123!` und weitere feste Kennwörter | ✅ GUI-Feld oder CSPRNG-Zufallskennwort je Benutzer |
| A2 | Sicherheit | 11× `ConvertTo-SecureString -AsPlainText` verstreut | ✅ zentrale Funktion, nie geloggt |
| A3 | Sicherheit | Rekursives OU-Löschen ohne Inhaltsprüfung | ✅ Prüfung + gesonderte Rückfrage |
| A4 | Sicherheit | Unmaskierte Werte in `-Filter` | ✅ |
| A5 | Sicherheit | LAPS-/BitLocker-Exporte enthalten Klartext | ⚠️ gewollt, Ablage `Exports\`, in `.gitignore` |
| A6 | Performance | Wiederholte `Get-ADDomain`/domänenweite `Get-ADUser`-Suchen in Schleifen, `+=`, `-Properties *` | ✅ Cache, Sammelaufrufe, Listen |
| A7 | Performance | GUI reagierte während langer Vorgänge nicht | ✅ Dispatcher-Refresh, Sperre gegen Doppelstart |
| A8 | Funktionen | Testdaten-Set scheiterte (OU-Namen), SPN-Port fehlte (`"$host:80"`), `svc-*`/`svc_*` | ✅ |
| A9 | Funktionen | BitLocker/LAPS/Passwortrichtlinien/verschachtelte Gruppen fehlerhaft (siehe CHANGELOG) | ✅ |
| A10 | Funktionen | CSV-Import: Ländercodes, PLZ, LDAP-Namen, proxyAddresses, HomeDrive | ✅ |
| A11 | Funktionen | Tote Funktionen ohne Button (z. B. `Simulate-Migration`, `Create-KerberosTests`), 16 auskommentierte Handler | ✅ in 0.0.4 (N2) |
| A12 | Verweise | CSV-/Log-/Exportpfade relativ zum Arbeitsverzeichnis | ✅ `$PSScriptRoot` |
| A13 | Verweise | Version 0.1.0 (Header) vs. 0.0.2 (Konfiguration) | ✅ 0.0.3 |
| A14 | Befehle | Leerer `catch`, ungültige Attributzuweisungen (`whenCreated`, `badPwdCount`, `lockoutTime`) | ✅ |

## fakeBitlockerData 0.0.1 → 0.0.2

| # | Kategorie | Befund | Status |
|---|-----------|--------|--------|
| F1 | Sicherheit | `Verify` zeigte/exportierte **echte** BitLocker-Schlüssel und LAPS-Kennwörter | ✅ nur markierte Fake-Daten |
| F2 | Sicherheit | `Clean` löschte **alle** BitLocker-Objekte/LAPS-Attribute der Domäne | ✅ nur markierte Fake-Daten |
| F3 | Sicherheit | `Create` überschrieb echte LAPS-Kennwörter, auch auf Domänencontrollern | ✅ ausgeschlossen |
| F4 | Sicherheit | Kennwörter aus `Get-Random` | ✅ `RandomNumberGenerator` |
| F5 | Sicherheit | Dummy-Computer vor der Sicherheitsabfrage angelegt | ✅ |
| F6 | Sicherheit | Fake-Daten aus 0.0.1 ohne Marker werden nicht erkannt | ✅ in 0.0.3 per Opt-in `-IncludeLegacy` (N3) |
| F7 | Funktionen | BitLocker-Objekte nicht anlegbar (LDAP-Namen, `msFVE-RecoveryGuid`, Objektname), falsches Passwortformat | ✅ |
| F8 | Funktionen | Windows-LAPS-Ablaufzeit in Unix-Sekunden statt FILETIME | ✅ |
| F9 | Funktionen | Doppelte Zeilen, fehlende CSV-Spalten, Hotkey-Konflikt, `-Quiet` inkonsequent | ✅ |
| F10 | Funktionen | Dummy-Computer `FAKE-PC-*` werden von `Clean` nicht gelöscht | ✅ in 0.0.3 per Opt-in `-RemoveDummyComputers` (N3) |
| F11 | Performance | Zusätzliche AD-Abfragen pro Computer, `+=` | ✅ |
| F12 | Verweise | Kein Header, keine Version, Export ins Arbeitsverzeichnis | ✅ |
| F13 | Befehle | `SupportsShouldProcess` ohne `ShouldProcess`-Aufrufe (3), Zuweisung an `$pwd`, `Write-Log`-Konflikt | ✅ |

## Nacharbeiten – zweite Runde

| # | Tool | Offener Punkt | Umsetzung | Status |
|---|------|---------------|-----------|--------|
| N1 | easyWINUpdate 0.2.5 | Auto-Fix und Reparaturfunktionen blockierten die Oberfläche (W9) | Alle Reparaturen und Fehlerbehebungen laufen über `Invoke-RepairAction` → `Start-FunctionInBackground` (Runspace + DispatcherTimer); benötigte Funktionen werden als Text übergeben, Status/Log über eine Warteschlange an den GUI-Thread (WPF wird im Runspace nie berührt); Buttons gesperrt, Fortschrittsanzeige, gegenseitiger Ausschluss mit Update-Aktionen, Warnung beim Schließen | ✅ |
| N2 | easyADDummyUserCreator 0.0.4 | Funktionen ohne Button, 16 auskommentierte Handler (A11) | Erreichbarkeitsanalyse ab `Show-MainWindow`: sinnvolle Funktionen an neue Buttons angebunden (Vorlage, Anmeldezeiten, Avatare, OU-Struktur, Drucker, Performance-Test), 13 doppelte/defekte/gefährliche Funktionen entfernt, alle auskommentierten Handler entfernt; 0 unerreichbare Funktionen, jeder Button hat einen Handler, jede Control-Referenz existiert im XAML | ✅ |
| N3 | fakeBitlockerData 0.0.3 | 0.0.1-Daten ohne Marker nicht erkannt (F6), Dummy-Computer nicht entfernt (F10) | Opt-in `-IncludeLegacy` mit Fingerabdrücken, bei denen alle Kriterien zutreffen müssen (W1: Windows-LAPS-Kennwort kein JSON + Ablaufzeit in Unix-Sekunden; L1/L2: Legacy-LAPS-Kennwort im 0.0.1-Format an 0.0.1-Dummy bzw. zusammen mit W1; D1: Dummy-Computer mit 0.0.1-Beschreibung, deaktiviert; B1: BitLocker-Objekt ohne Marker mit ungültigem Wiederherstellungskennwort); Löschen nur nach Zusatzrückfrage bzw. `-ForceLegacyClean`; `-RemoveDummyComputers` löscht nur deaktivierte Konten ohne Anmeldung, die nur Fake-Unterobjekte enthalten, nie rekursiv | ✅ · ⚠️ ein einzelnes 0.0.1-Legacy-LAPS-Kennwort an einem echten Computer ist nicht sicher von echten Daten unterscheidbar und wird bewusst nicht erkannt |
| N4 | alle | Sprachmix Deutsch/Englisch in den Oberflächen (E11) | Alle sichtbaren Texte deutsch; technische Werte (Policy-/Scope-Namen, AD-Attribute, CSV-Spalten, Fehlercodes, KB-Nummern) unverändert; Vergleiche auf Index bzw. angepasste Literale umgestellt, alte gespeicherte Werte werden weiter erkannt | ✅ · RBAC-Rollen- und OU-Vorlagennamen in easyADDummyUserCreator bewusst englisch (AD-Konvention) |
| N5 | alle | Reine Stilwarnungen (globale Variablen, Verbnamen, Plural, `Write-Host`, ShouldProcess, Leerzeichen) | Echte Korrekturen statt Unterdrückung: `$Global:` → `$script:` (Runspaces erhalten Daten als Parameter), Funktionen auf genehmigte Verben/Singular umbenannt inkl. aller Aufrufstellen, `ShouldProcess` mit echter Prüfung (ohne neue Rückfragen), `Write-Host` → `Write-Verbose`/Logger | ✅ 0 Befunde · einzige Unterdrückung: `PSAvoidUsingWriteHost` in fakeBitlockerData (farbige Konsolenausgabe ist die Oberfläche, mit `-Quiet` abschaltbar) |
| N6 | easyPSInfo 0.0.5 | Script-Launcher fand nur Skripte im eigenen Ordner `src/easyPSInfo/` | Liegt das Tool unter `src/<Tool>/<Tool>.ps1`, ist der Standard-Basisordner `src/` (alle Tools); Basisordner per „Ordner wählen…“ änderbar, „Standard“ setzt zurück, Speicherung geprüft in `%APPDATA%\PhinIT\easyPSInfo\settings.json`; Suche max. 5 Ebenen/2000 Ordner, ohne `Logs`/`Exports`/`Backups`/„old“/Links | ✅ |
| N7 | easyPSInfo 0.0.5 | AzureAD/MSOnline abgekündigt (P11) | Status „Abgekündigt“, Tooltip mit Nachfolger, Hinweis bei Installation | ✅ |
| N8 | easyWINUpdate 0.2.5 | Ungenutzte Hilfsfunktionen | `Get-UpdateSource`, `Get-LastUpdateDate`, `Get-ServiceStatusInfo` entfernt | ✅ |

Verbleibend (⚠️, bewusst bzw. kurz):

- easyWINUpdate: `Get-HotFix` auf der Startseite, das Laden der WSUS-Seite (Verbindungstest bis 3 s) und die Installation von `PSWindowsUpdate`
  für alle Benutzer beim Anlegen des Zeitplans laufen kurz synchron; beim Schließen wartet das Beenden des Runspaces ggf. auf ein laufendes externes Programm.
- easyADDummyUserCreator: Test-Umgebung im Domänenstamm (`OU=TestCompany`); Computernamen ohne Zufallsoption und `GRP_<Abteilung>` kollidieren bei
  wiederholten Läufen; LAPS-Export enthält simulierte Kennwörter im Klartext (A5).

### Umbenannte Funktionen (Auszug)

| Tool | Alt → Neu |
|------|-----------|
| easyWINUpdate | `Auto-FixWindowsUpdateIssues` → `Repair-WindowsUpdateIssue`, `Reset-WindowsUpdateComponents` → `Reset-WindowsUpdateComponent`, `Register-WindowsUpdateDLLs` → `Register-WindowsUpdateDLL`, `Load-*Page` → `Show-*Page`, `Update-StatusText` → `Write-StatusText` (insgesamt 24) |
| easyPSInfo | `Write-Log` → `Write-AppLog`, `Check-AllModules` → `Show-ModuleStatus`, `Update-ScriptList` → `Show-ScriptList` (insgesamt 7) |
| easyExecutionPolicy | `Ensure-Admin` → `Assert-AdminPrivilege`, `Create-ManualBackup` → `Save-ManualBackup`, `Restore-BackupPolicies` → `Restore-PolicyBackup` (insgesamt 7) |
| easyADDummyUserCreator | `Create-*` → `New-*`, `Quick-CleanupAll` → `Clear-CreatedTestData`, `Write-Log` → `Write-AppLog`, `Start-Application` → `Show-MainWindow` (insgesamt 50) |
| fakeBitlockerData | `Get-TargetComputers` → `Get-TargetComputer`, `New-RandomPassword` → `Get-RandomFakePassword`, `New-BitLockerPassword` → `Get-RandomRecoveryPassword` |

## Prüfergebnisse

| Skript | Parser-Fehler | PSScriptAnalyzer (alle Schweregrade) Audit → Nacharbeiten | Encoding |
|--------|---------------|-----------------------------------------------------------|----------|
| easyWINUpdate.ps1 | 0 | 571 → 0 | UTF-8 BOM |
| easyPSInfo.ps1 | 0 | 121 → 0 | UTF-8 BOM |
| easyExecutionPolicy.ps1 | 0 | 65 → 0 | UTF-8 BOM |
| easyADDummyUserCreator.ps1 | 0 | 1681 → 0 | UTF-8 BOM |
| fakeBitlockerData.ps1 | 0 | 4 → 0 | UTF-8 BOM |

- PSScriptAnalyzer 1.25 mit Standardregelsatz; einzige Unterdrückung: `PSAvoidUsingWriteHost` in fakeBitlockerData (begründet, siehe N5).
- XAML aller WPF-Tools wohlgeformt; alle im Code referenzierten Controls vorhanden, keine doppelten Namen, keine Buttons ohne Handler.
- Keine definierte, aber nicht aufgerufene Funktion; keine Aufrufe nicht definierter Funktionen.
- **Nicht durchgeführt:** Funktionstests unter Windows (GUI, Active Directory, Windows Update, UAC) – die Prüfumgebung war Linux.
  Vor dem produktiven Einsatz in einer Testumgebung prüfen und die Skripte neu signieren.
