# Security Policy / Sicherheitsrichtlinie

## Unterstützte Versionen

Es wird jeweils nur die aktuelle Version eines Tools unterstützt. Ältere Versionen wurden aus dem Repository entfernt
(sie sind nur noch über die Git-Historie verfügbar und erhalten keine Sicherheitskorrekturen).

| Tool | Unterstützt | Nicht unterstützt |
|------|-------------|-------------------|
| easyADDummyUserCreator | 0.0.3 | < 0.0.3 |
| easyExecutionPolicy | 0.0.4 | < 0.0.4 |
| easyPSInfo | 0.0.4 | < 0.0.4 |
| easyWINUpdate | 0.2.4 | < 0.2.4 |
| fakeBitlockerData | 0.0.2 | < 0.0.2 |

## Schwachstelle melden

Bitte **kein** öffentliches Issue erstellen. Nutze die private Meldefunktion von GitHub
(*Security* → *Report a vulnerability*) in diesem Repository und gib an:

- betroffenes Tool, Version und Datei
- Schritte zur Reproduktion
- Auswirkung

Du erhältst so schnell wie möglich eine Rückmeldung; Korrekturen werden in [CHANGELOG.md](CHANGELOG.md) dokumentiert.

## Hinweise für Betreiber

- Die Tools ändern System- bzw. Active-Directory-Konfigurationen und benötigen teilweise Administratorrechte.
  Nur auf vertrauenswürdigen Admin-Arbeitsstationen ausführen und den Quellcode vor der Ausführung prüfen.
- **easyADDummyUserCreator** und **fakeBitlockerData** erzeugen Testdaten in Active Directory.
  Ausschließlich in Test-/Laborumgebungen verwenden – niemals in einer Produktivdomäne.
- Es gibt keine fest im Code hinterlegten Standardkennwörter. Generierte Testkennwörter werden nicht in Logdateien geschrieben.
- Logdateien (`src/<Tool>/Logs/`) und Exporte können Rechner-, Benutzer-, Pfad- und Domänennamen enthalten.
  Diese Ordner sind per `.gitignore` ausgeschlossen und müssen entsprechend geschützt werden.
- Die Skripte sind seit dem Audit vom 14.10.2026 **nicht signiert** (die bisherigen Signaturen wurden durch die
  Codeänderungen ungültig). Bei `AllSigned` die Skripte vor dem Einsatz selbst signieren (siehe [README](README.md#code-signing)).
- Die Ausführungsrichtlinie nur für den aktuellen Prozess lockern (`-ExecutionPolicy Bypass` beim Start bzw.
  `Set-ExecutionPolicy -Scope Process`), nicht dauerhaft systemweit.
