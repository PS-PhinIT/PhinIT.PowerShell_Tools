# easyExecutionPolicy v0.0.5 – Execution Policy Manager

Deutschsprachige WinForms-Oberfläche zum Anzeigen, Setzen, Sichern und Wiederherstellen der PowerShell-Ausführungsrichtlinien je Scope.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#easyexecutionpolicy-004--005)
- **Screenshots:** [assets/screenshots/easyExecutionPolicy](../../assets/screenshots/easyExecutionPolicy/)

## Funktionen

| Bereich | Funktionen |
|---------|------------|
| Anzeige | Alle Scopes (MachinePolicy, UserPolicy, Process, CurrentUser, LocalMachine) mit deutscher Kurzbeschreibung der effektiven Policy |
| Setzen | Process, CurrentUser, LocalMachine – mit Übersicht „alt → neu“ und Bestätigung; Warnung vor Unrestricted/Bypass. MachinePolicy/UserPolicy werden per GPO gesteuert und nur angezeigt |
| Backup | Automatisches Backup beim Start (Arbeitsspeicher + Datei), manuelles Backup, Export als JSON |
| Restore/Import | Wiederherstellen aus Arbeitsspeicher oder JSON-Datei; Dateien werden geprüft (max. 1 MB, nur gültige Scopes und Werte) |

## Voraussetzungen

- Windows, Windows PowerShell 5.1 oder PowerShell 7.x
- Administratorrechte – ohne Adminrechte bietet das Tool einen Neustart mit UAC an (gleicher PowerShell-Host)
- Keine zusätzlichen Module

## Start

```powershell
Unblock-File -Path .\src\easyExecutionPolicy\easyExecutionPolicy.ps1
powershell.exe -ExecutionPolicy Bypass -File .\src\easyExecutionPolicy\easyExecutionPolicy.ps1
```

Parameter: `-Verbose` (optional) – Diagnosemeldungen in der Konsole; wird beim Neustart als Administrator weitergegeben.

Bedienung: Menü „Datei“/„Extras“, Buttons „Aktualisieren“, „Backup“, „Wiederherstellen“, „Auswahl anwenden“.

> Hinweis: Beim Start mit `-ExecutionPolicy Bypass` steht der Scope `Process` für diese Sitzung auf `Bypass`.
> Das Tool weist darauf hin, wenn eine Einstellung dadurch (oder per GPO) überschrieben wird.

## Ablage

- Automatische Backups: `%APPDATA%\easyExecutionPolicy\AutoBackups\ExecutionPolicyBackup_*.json` (die letzten 10 bleiben erhalten)
- Manuelle Backups und Exporte: frei wählbarer Speicherort

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
