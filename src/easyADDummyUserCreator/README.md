# easyADDummyUserCreator v0.0.4 – AD Dummy Object Creator

Deutschsprachige WPF-Oberfläche zum Anlegen und Bereinigen von Testobjekten in Active Directory.

> ⚠️ **Nur für Test-/Laborumgebungen.** Niemals in einer Produktivdomäne verwenden.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#easyaddummyusercreator-003--004)
- **Screenshots:** [assets/screenshots/easyADDummyUserCreator](../../assets/screenshots/easyADDummyUserCreator/)

## Funktionen

- Benutzer aus CSV (`AD_DummyUserList.csv`) mit wählbarer Attributzuordnung, zufällig erzeugt oder **aus einer Vorlage**
  (Attribute und Gruppen eines vorhandenen Benutzers; privilegierte Gruppen mit `adminCount=1` werden nicht übernommen)
- Erstellte Benutzer anpassen: zufällige Attribute, **Profilbilder** (`thumbnailPhoto`, generiert oder aus einem Ordner),
  **Anmeldezeiten** (`logonHours`, Mo–Fr 08–17 Uhr), temporäres Konto/zufälliges Ablaufdatum
- Gruppen (Sicherheits- oder Verteilergruppen, verschachtelt, vollständige Hierarchie), Computer, Dienstkonten (mit eindeutigen SPNs),
  **Drucker** (`printQueue`), **OU-Struktur nach Firmengröße** (klein, mittel, groß, Konzern)
- BitLocker- und LAPS-Testdaten, Passwortrichtlinien-Testfälle, RBAC-Rollen, Chaos- und Testdatensätze
- **Performance-Test** (Bericht als TXT, Messwerte als CSV im Ordner `Exports\`)
- Bereinigung: entfernt nur die vom Tool angelegten Objekte; OUs mit fremden Objekten nur nach gesonderter Rückfrage.
  „Alles löschen“ entfernt Gruppen, Computer, Dienstkonten, Drucker und Test-OUs; Benutzer werden unter „Erstellte Benutzer verwalten“
  über „🗑️ Löschen“ entfernt, OUs aus der OU-Struktur über „🗑️ OUs“

## Voraussetzungen

- Windows mit Windows PowerShell 5.1 oder PowerShell 7.x (WPF)
- RSAT-Modul `ActiveDirectory`
- Rechte zum Anlegen/Löschen von Objekten in der Ziel-OU (für BitLocker-/LAPS-Attribute ggf. erweiterte Rechte)

## Start

```powershell
Unblock-File -Path .\src\easyADDummyUserCreator\easyADDummyUserCreator.ps1
powershell.exe -ExecutionPolicy Bypass -File .\src\easyADDummyUserCreator\easyADDummyUserCreator.ps1
```

Parameter: keine. Protokollmeldungen erscheinen zusätzlich in der Konsole, wenn vor dem Start `$VerbosePreference = 'Continue'` gesetzt ist.

## Kennwörter

- Im Feld **„Initial-Passwort“** kann ein Kennwort für alle neuen Benutzer vorgegeben werden (CSV, Zufall, Vorlage, Testdaten-Set, Komplett-Set, Performance-Test).
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

- „Attribute befüllen“ verwendet die Benutzer des letzten Laufs von „Benutzer aus CSV erstellen“ (Hinweis im Tooltip und in der Rückfrage).
- Die Test-Umgebung wird im Domänenstamm angelegt (`OU=TestCompany`).
- Computernamen ohne Zufallsoption (`WS-0001` …) und Gruppen `GRP_<Abteilung>` kollidieren bei wiederholten Läufen mit vorhandenen Objekten.
- RBAC-Rollennamen und OU-Namen der Strukturvorlagen sind bewusst englisch (AD-Konvention).

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
