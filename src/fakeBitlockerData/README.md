# fakeBitlockerData v0.0.2 – Fake BitLocker/LAPS-Testdaten für Active Directory

Konsolenskript zum Erstellen, Prüfen und Entfernen von Fake-BitLocker-Wiederherstellungsdaten sowie
Fake-Kennwörtern für Legacy-LAPS und Windows LAPS an AD-Computerobjekten.

> ⚠️ **Nur für Test-/Laborumgebungen.** Niemals in einer Produktivdomäne verwenden.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#fakebitlockerdata-001--002)

## Funktionsweise

| Modus | Beschreibung |
|-------|--------------|
| `Create` | Erzeugt Fake-Daten und markiert sie (`adminDescription=PhinIT-FakeTestData;Volume=X` bzw. Kennwort-Präfix `FAKE-`). Vorhandene echte LAPS-Kennwörter werden nicht überschrieben, Domänencontroller ausgeschlossen. Bei zu wenigen Computern werden deaktivierte, markierte Dummy-Computer (`FAKE-PC-*`) angelegt |
| `Verify` | Zeigt nur markierte Fake-Daten; echte Kennwörter/Schlüssel werden nie angezeigt oder exportiert |
| `Clean` | Entfernt nur markierte Fake-Daten (Dummy-Computer `FAKE-PC-*` bleiben bestehen und müssen manuell gelöscht werden) |

## Voraussetzungen

- Windows PowerShell 5.1 oder PowerShell 7.x
- RSAT-Modul `ActiveDirectory`
- Schreibrechte auf die Computerobjekte; für LAPS muss das Schema um die jeweiligen Attribute erweitert sein

## Parameter

| Parameter | Werte / Standard |
|-----------|------------------|
| `-Mode` | `Create`, `Verify`, `Clean` |
| `-DataType` | `All`, `Bitlocker`, `LAPS`, `WindowsLAPS` |
| `-Count` | Anzahl Computer im Create-Modus (Standard `10`) |
| `-Volumes` | BitLocker-Laufwerke (Standard `C:`, `D:`) |
| `-SearchBase` | OU (DistinguishedName) für die Computersuche |
| `-OutputFile` | Pfad der CSV-Ausgabe |
| `-Quiet` | Keine Abfragen/Ausgaben – `-Mode` und `-DataType` sind dann Pflicht |
| `-WhatIf`, `-Confirm` | Werden bei allen schreibenden/löschenden AD-Operationen unterstützt |

## Beispiele

```powershell
.\src\fakeBitlockerData\fakeBitlockerData.ps1
.\src\fakeBitlockerData\fakeBitlockerData.ps1 -Mode Create -DataType All -Count 20 -SearchBase 'OU=Testclients,DC=lab,DC=local'
.\src\fakeBitlockerData\fakeBitlockerData.ps1 -Mode Clean -DataType All -WhatIf
Get-Help .\src\fakeBitlockerData\fakeBitlockerData.ps1 -Full
```

## Ausgabe

CSV unter `src/fakeBitlockerData/Logs/FakeADData_<Modus>_<Zeitstempel>.csv` oder unter `-OutputFile`. Bei `-WhatIf` wird nichts exportiert.

## Bekannte Einschränkungen

- Fake-Daten aus Version 0.0.1 tragen keinen Marker und werden von `Verify`/`Clean` bewusst nicht erkannt (Schutz echter Daten).

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
