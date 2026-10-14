# easyWINUpdate v0.2.5 – Windows Update Management Tool

Deutschsprachige WPF-Oberfläche zur Verwaltung von Windows Updates, WSUS-Einstellungen und zur Fehlersuche.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#easywinupdate-024--025)
- **Screenshots:** [assets/screenshots/easyWINUpdate](../../assets/screenshots/easyWINUpdate/)

## Funktionen

| Bereich | Funktionen |
|---------|------------|
| Dashboard | Systemübersicht und Update-Status |
| Updates | Installierte Updates anzeigen/exportieren/deinstallieren, verfügbare Updates suchen (Windows-Update-API), installieren und herunterladen |
| WSUS | Manuelle Konfiguration (Server/Port geprüft), GPO-Werte, Zielgruppe, Synchronisierung inkl. Verlauf (Ereignisse 25/26), Verbindungstest (TCP), Reset (nur WSUS-Werte) |
| Zeitplan | Geplante Aufgabe über die Task-Scheduler-COM-Schnittstelle (Skript in `%ProgramFiles%\PhinIT\easyWINUpdate`, nur SYSTEM/Administratoren) |
| Fehlerbehebung | Fehlercode-Datenbank mit Lösungen, BITS/WaaSMedic, Registry-/Datenbank-Reparatur, DLL-Registrierung, DISM/SFC/CHKDSK (eigenes Konsolenfenster), Log-Analyse, Debug-Modus, Auto-Fix, Temp bereinigen, Winsock-Reset |

Lang laufende Aktionen laufen im Hintergrund – die Oberfläche bleibt bedienbar:

- Suche, Installation, Download und Deinstallation von Updates
- alle Reparaturen und Fehlerbehebungen: Auto-Fix, Komponenten-Reset, Registry-/Datenbank-Reparatur, BITS/WaaSMedic, DLL-Registrierung,
  hängende Updates, Update-Verlauf löschen, Temp bereinigen, Winsock-Reset, Fehlerdiagnose, Log-Analyse, Debug-Modus, Wiederherstellungspunkt
- WSUS-Reset, manuelle WSUS-Konfiguration, Richtlinien/Sync-Einstellungen übernehmen, WSUS-Verbindungstest

Während einer Reparatur zeigt die Fehlerbehebungsseite den aktuellen Schritt und einen Fortschrittsbalken an; die Reparatur-Buttons
sind gesperrt. Es läuft immer nur eine Aktion gleichzeitig (keine Update-Suche/-Installation während einer Reparatur und umgekehrt).
Beim Schließen des Fensters während einer Reparatur erscheint eine Warnung. DISM/SFC/CHKDSK öffnen ein eigenes Konsolenfenster.

## Voraussetzungen

- Windows 10/11 oder Windows Server 2016 – 2025
- Windows PowerShell 5.1 oder PowerShell 7.x (Windows)
- Administratorrechte – das Tool startet sich bei Bedarf selbst erhöht (UAC) und im STA-Modus neu
- Modul `PSWindowsUpdate` (wird bei Bedarf aus der PowerShell Gallery installiert)

## Start

```powershell
Unblock-File -Path .\src\easyWINUpdate\easyWINUpdate.ps1
powershell.exe -ExecutionPolicy Bypass -File .\src\easyWINUpdate\easyWINUpdate.ps1
```

Parameter: keine.

## Logs und Exporte

| Datei | Ort |
|-------|-----|
| App-Log | `src/easyWINUpdate/Logs/easyWINUpdate_yyyyMMdd.log` (Fallback `%LOCALAPPDATA%\easyWINUpdate\Logs`) |
| Log-Analyse | `src/easyWINUpdate/Logs/WindowsUpdate_<Zeitstempel>.log` |
| Geplante Aufgabe | `%ProgramFiles%\PhinIT\easyWINUpdate\RunWindowsUpdate.ps1`, Protokolle in `%ProgramFiles%\PhinIT\easyWINUpdate\Logs\` |
| CSV-Export | `Desktop\Installierte_Updates_<Zeitstempel>.csv` (auch bei OneDrive-Umleitung) |

## Fehlerbehebung

| Problem | Lösung |
|---------|--------|
| Befehle/Reparaturen schlagen fehl | UAC-Abfrage bestätigen; das Tool benötigt Administratorrechte |
| Skript startet nicht | `Unblock-File`, Ausführungsrichtlinie prüfen (siehe Haupt-README) |
| Umlaute falsch dargestellt | Datei muss als UTF-8 **mit** BOM gespeichert sein |

## Bekannte Einschränkungen

- Kurz synchron: `Get-HotFix` auf der Startseite, das Laden der WSUS-Seite (Verbindungstest bis 3 s) und die Installation von `PSWindowsUpdate`
  für alle Benutzer beim Anlegen des Zeitplans.
- WSUS-Zielgruppen sind eine feste Auswahlliste (echte Gruppen erfordern die WSUS-Admin-Konsole).
- Intervalle „Wöchentlich/Monatlich“ werden auf das Richtlinien-Maximum von 22 Stunden (`DetectionFrequency`) abgebildet.
- `PSWindowsUpdate` wird bei Bedarf automatisch aus der PowerShell Gallery installiert.

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
