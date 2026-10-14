# easyADDummyUserCreator v0.0.3 – AD Dummy Object Creator

WPF-Oberfläche zum Anlegen und Bereinigen von Testobjekten in Active Directory.

> ⚠️ **Nur für Test-/Laborumgebungen.** Niemals in einer Produktivdomäne verwenden.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#easyaddummyusercreator-002--003)
- **Screenshots:** [assets/screenshots/easyADDummyUserCreator](../../assets/screenshots/easyADDummyUserCreator/)

## Funktionen

- Benutzer aus CSV (`AD_DummyUserList.csv`) mit wählbarer Attributzuordnung oder zufällig erzeugt
- Gruppen (inkl. verschachtelter Gruppen), Computer, OUs, Service-Accounts (mit eindeutigen SPNs)
- BitLocker- und LAPS-Testdaten, Passwortrichtlinien-Testfälle, Chaos- und Testdatensätze
- Bereinigung: entfernt nur die vom Tool angelegten Objekte; OUs mit fremden Objekten nur nach gesonderter Rückfrage

## Voraussetzungen

- Windows mit Windows PowerShell 5.1 oder PowerShell 7.x (WPF)
- RSAT-Modul `ActiveDirectory`
- Rechte zum Anlegen/Löschen von Objekten in der Ziel-OU (für BitLocker-/LAPS-Attribute ggf. erweiterte Rechte)

## Start

```powershell
Unblock-File -Path .\src\easyADDummyUserCreator\easyADDummyUserCreator.ps1
powershell.exe -ExecutionPolicy Bypass -File .\src\easyADDummyUserCreator\easyADDummyUserCreator.ps1
```

Parameter: keine.

## Kennwörter

- Im Feld **„Initial-Passwort“** kann ein Kennwort für alle neuen Benutzer vorgegeben werden.
- Bleibt das Feld leer, erhält jeder Benutzer ein eigenes, kryptografisch sicher erzeugtes Zufallskennwort.
  Dieses wird **nicht** angezeigt oder protokolliert – zum Anmelden das Kennwort anschließend per AD zurücksetzen.
- Es gibt kein fest im Code hinterlegtes Standardkennwort mehr.

## Dateien

| Datei | Ort |
|-------|-----|
| CSV (Standard) | `src/easyADDummyUserCreator/AD_DummyUserList.csv` (fiktive Daten; andere Datei über die GUI wählbar) |
| Log | `src/easyADDummyUserCreator/Logs/easyADDummyUserCreator.log` |
| Exporte | `src/easyADDummyUserCreator/Exports/` – LAPS-/BitLocker-Exporte enthalten Klartext und müssen sicher verwahrt werden |

## Bekannte Einschränkungen

- Mehrere vorbereitete Funktionen (z. B. Migrations- und Kerberos-Simulation) sind noch nicht über die GUI erreichbar.
- „Attribute befüllen“ verwendet die Liste der zuletzt per CSV angelegten Benutzer.

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
