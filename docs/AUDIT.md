# Audit PhinIT PowerShell Tools – 14.10.2026

**Umfang:** alle Tools des Repositorys – Sicherheit, Performance, Funktionen, Verweise, GUI, Befehle, Repository-Struktur und Dokumentation.
**Methode:** Code-Review aller Funktionen und Event-Handler, PowerShell-Parser, PSScriptAnalyzer 1.25, XAML-Wohlgeformtheit,
Abgleich XAML-Controls ↔ Verwendung im Code, Tests einzelner Hilfsfunktionen unter PowerShell 7.

Status: ✅ behoben · ⚠️ dokumentiertes Restrisiko / offen

| Tool | Version vorher → nachher | Datei |
|------|--------------------------|-------|
| easyWINUpdate | 0.2.3 → 0.2.4 | `src/easyWINUpdate/easyWINUpdate.ps1` |
| easyPSInfo | 0.0.3 → 0.0.4 | `src/easyPSInfo/easyPSInfo.ps1` |
| easyExecutionPolicy | 0.0.3 → 0.0.4 | `src/easyExecutionPolicy/easyExecutionPolicy.ps1` |
| easyADDummyUserCreator | 0.0.2 → 0.0.3 | `src/easyADDummyUserCreator/easyADDummyUserCreator.ps1` |
| fakeBitlockerData | 0.0.1 → 0.0.2 | `src/fakeBitlockerData/fakeBitlockerData.ps1` |

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
| W1 | Sicherheit | Geplante Aufgabe als SYSTEM startete ein Skript aus `%TEMP%` (benutzerschreibbar → Rechteausweitung) | ✅ `%ProgramData%\easyWINUpdate`, ACL nur SYSTEM/Administratoren |
| W2 | Sicherheit | 2× `Invoke-Expression` (`sc.exe sdset`, `schtasks`) | ✅ direkter Aufruf / Task-Scheduler-COM |
| W3 | Sicherheit | Keine Prüfung auf Administratorrechte | ✅ Neustart mit UAC und STA |
| W4 | Sicherheit | WSUS-Server/-Port und KB-Nummern ungeprüft | ✅ Validierung, `wusa.exe` mit vollem Pfad |
| W5 | Sicherheit | „Reset WSUS“ löschte den gesamten Schlüssel `Policies\WindowsUpdate` | ✅ nur WSUS-Werte |
| W6 | Sicherheit | PSWindowsUpdate wird bei Bedarf automatisch aus der PSGallery installiert | ⚠️ Verhalten beibehalten |
| W7 | Performance | Suche/Installation/Download/Deinstallation/Log-Analyse blockierten die GUI | ✅ Runspace + DispatcherTimer |
| W8 | Performance | DISM/SFC/CHKDSK blockierten die GUI | ✅ eigenes Konsolenfenster |
| W9 | Performance | Auto-Fix, Komponenten-Reset, Registry-/Datenbank-Reparatur synchron | ⚠️ offen (zu viele GUI-Abhängigkeiten) |
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
| P11 | Funktionen | AzureAD/MSOnline abgekündigt, aber gelistet | ⚠️ Entscheidung des Autors |
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
| E11 | GUI | Sprachmix Deutsch/Englisch | ⚠️ kosmetisch, offen |

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
| A11 | Funktionen | Tote Funktionen ohne Button (z. B. `Simulate-Migration`, `Create-KerberosTests`), 16 auskommentierte Handler | ⚠️ unverändert |
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
| F6 | Sicherheit | Fake-Daten aus 0.0.1 ohne Marker werden nicht erkannt | ⚠️ bewusst (Schutz echter Daten) |
| F7 | Funktionen | BitLocker-Objekte nicht anlegbar (LDAP-Namen, `msFVE-RecoveryGuid`, Objektname), falsches Passwortformat | ✅ |
| F8 | Funktionen | Windows-LAPS-Ablaufzeit in Unix-Sekunden statt FILETIME | ✅ |
| F9 | Funktionen | Doppelte Zeilen, fehlende CSV-Spalten, Hotkey-Konflikt, `-Quiet` inkonsequent | ✅ |
| F10 | Funktionen | Dummy-Computer `FAKE-PC-*` werden von `Clean` nicht gelöscht | ⚠️ markiert, manuell löschen |
| F11 | Performance | Zusätzliche AD-Abfragen pro Computer, `+=` | ✅ |
| F12 | Verweise | Kein Header, keine Version, Export ins Arbeitsverzeichnis | ✅ |
| F13 | Befehle | `SupportsShouldProcess` ohne `ShouldProcess`-Aufrufe (3), Zuweisung an `$pwd`, `Write-Log`-Konflikt | ✅ |

## Prüfergebnisse

| Skript | Parser-Fehler | PSScriptAnalyzer Error | Encoding |
|--------|---------------|------------------------|----------|
| easyWINUpdate.ps1 | 0 | 0 | UTF-8 BOM |
| easyPSInfo.ps1 | 0 | 0 | UTF-8 BOM |
| easyExecutionPolicy.ps1 | 0 | 0 | UTF-8 BOM |
| easyADDummyUserCreator.ps1 | 0 | 0 (vorher 11) | UTF-8 BOM |
| fakeBitlockerData.ps1 | 0 | 0 | UTF-8 BOM |

- Die Regeln `PSAvoidUsingInvokeExpression`, `PSAvoidAssignmentToAutomaticVariable`, `PSPossibleIncorrectComparisonWithNull`,
  `PSAvoidUsingEmptyCatchBlock`, `PSUseBOMForUnicodeEncodedFile`, `PSAvoidUsingConvertToSecureStringWithPlainText` und `PSShouldProcess` haben 0 Treffer.
- Verbleibende Warnungen sind Stilregeln (globale Variablen, nicht genehmigte Verben, Plural-Nomen, `Write-Host`, ShouldProcess bei GUI-Hilfsfunktionen) –
  bewusst kein Massen-Refactoring, um das Verhalten nicht zu gefährden.
- XAML aller WPF-Tools wohlgeformt; alle im Code referenzierten Controls vorhanden.
- **Nicht durchgeführt:** Funktionstests unter Windows (GUI, Active Directory, Windows Update, UAC) – die Prüfumgebung war Linux.
  Vor dem produktiven Einsatz in einer Testumgebung prüfen und die Skripte neu signieren.
