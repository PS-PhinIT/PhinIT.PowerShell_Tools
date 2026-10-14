# fakeBitlockerData v0.0.3 – Fake BitLocker/LAPS-Testdaten für Active Directory

Konsolenskript zum Erstellen, Prüfen und Entfernen von Fake-BitLocker-Wiederherstellungsdaten sowie
Fake-Kennwörtern für Legacy-LAPS und Windows LAPS an AD-Computerobjekten.

> ⚠️ **Nur für Test-/Laborumgebungen.** Niemals in einer Produktivdomäne verwenden.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#fakebitlockerdata-001--002) · [Nacharbeiten](../../docs/AUDIT.md#nacharbeiten--zweite-runde)

## Funktionsweise

| Modus | Beschreibung |
|-------|--------------|
| `Create` | Erzeugt Fake-Daten und markiert sie (`adminDescription=PhinIT-FakeTestData;Volume=X` bzw. Kennwort-Präfix `FAKE-`). Vorhandene echte LAPS-Kennwörter werden nicht überschrieben, Domänencontroller ausgeschlossen. Bei zu wenigen Computern werden deaktivierte, markierte Dummy-Computer (`FAKE-PC-*`) angelegt |
| `Verify` | Zeigt nur markierte Fake-Daten; mit `-IncludeLegacy` zusätzlich per Fingerabdruck erkannte Fake-Daten aus 0.0.1 (Spalte `Status`: `Markiert` / `Legacy 0.0.1`, Legacy-Kennwörter immer maskiert). Echte Kennwörter/Schlüssel werden nie angezeigt oder exportiert |
| `Clean` | Entfernt nur markierte Fake-Daten; mit `-IncludeLegacy` nach zusätzlicher Rückfrage auch erkannte 0.0.1-Daten; mit `-RemoveDummyComputers` auch die Dummy-Computer `FAKE-PC-*` (nur markierte bzw. per Fingerabdruck erkannte, deaktivierte Konten ohne Anmeldung, die nur Fake-Unterobjekte enthalten – nie rekursiv) |

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
| `-IncludeLegacy` | Verify/Clean berücksichtigen zusätzlich nicht markierte Fake-Daten aus Version 0.0.1 (Erkennung per Fingerabdruck, siehe `Get-Help -Full`) |
| `-ForceLegacyClean` | Zustimmung zum Löschen von Legacy-Daten ohne zusätzliche Rückfrage – bei `-Quiet -Mode Clean -IncludeLegacy` Pflicht (sonst Abbruch) |
| `-RemoveDummyComputers` | Clean entfernt zusätzlich die Dummy-Computer `FAKE-PC-*` (mit `-IncludeLegacy` auch die aus 0.0.1) |
| `-WhatIf`, `-Confirm` | Werden bei allen schreibenden/löschenden AD-Operationen unterstützt |

## Beispiele

```powershell
.\src\fakeBitlockerData\fakeBitlockerData.ps1
.\src\fakeBitlockerData\fakeBitlockerData.ps1 -Mode Create -DataType All -Count 20 -SearchBase 'OU=Testclients,DC=lab,DC=local'
.\src\fakeBitlockerData\fakeBitlockerData.ps1 -Mode Clean -DataType All -WhatIf
.\src\fakeBitlockerData\fakeBitlockerData.ps1 -Mode Verify -DataType All -IncludeLegacy
.\src\fakeBitlockerData\fakeBitlockerData.ps1 -Mode Clean -DataType All -IncludeLegacy -RemoveDummyComputers -WhatIf
Get-Help .\src\fakeBitlockerData\fakeBitlockerData.ps1 -Full
```

## Ausgabe

CSV unter `src/fakeBitlockerData/Logs/FakeADData_<Modus>_<Zeitstempel>.csv` oder unter `-OutputFile`. Bei `-WhatIf` wird nichts exportiert.

## Bekannte Einschränkungen

- Fake-Daten aus Version 0.0.1 tragen keinen Marker. Mit `-IncludeLegacy` werden sie nur erkannt, wenn ein eindeutiger Fingerabdruck zutrifft
  (z. B. Windows-LAPS-Ablaufzeit in Unix-Sekunden statt FILETIME, 0.0.1-Dummy-Computer). Ein einzelnes Legacy-LAPS-Kennwort aus 0.0.1
  an einem echten Computer ist von einem echten Kennwort nicht sicher unterscheidbar und wird deshalb nicht erkannt.
- 0.0.1 konnte keine BitLocker-Objekte anlegen; der BitLocker-Fingerabdruck greift daher nur bei manuell nachgebauten Objekten.

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
