# PhinIT PowerShell Tools

Sammlung von PowerShell-Skripten und Hilfswerkzeugen für die Administration von Windows, Windows Server,
Active Directory und Microsoft 365 – experimentell, in Entwicklung oder noch nicht reif für ein eigenes Repository.

- **Changelog:** [CHANGELOG.md](CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](docs/AUDIT.md)
- **Sicherheit:** [SECURITY.md](SECURITY.md)
- **Mitwirken:** [CONTRIBUTING.md](CONTRIBUTING.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

---

## Tools

| Tool | Version | Stand | Beschreibung |
|------|---------|-------|--------------|
| [easyWINUpdate](src/easyWINUpdate/README.md) | 0.2.5 | 14.10.2026 | Windows-Update- und WSUS-Verwaltung mit Troubleshooting (WPF) |
| [easyPSInfo](src/easyPSInfo/README.md) | 0.0.5 | 14.10.2026 | PowerShell-Modul- und Policy-Manager mit Script-Launcher (WPF) |
| [easyExecutionPolicy](src/easyExecutionPolicy/README.md) | 0.0.5 | 14.10.2026 | Ausführungsrichtlinien anzeigen, setzen, sichern, wiederherstellen (WinForms) |
| [easyADDummyUserCreator](src/easyADDummyUserCreator/README.md) | 0.0.4 | 14.10.2026 | AD-Testobjekte (Benutzer, Gruppen, Computer, OUs, Dienstkonten, Drucker) anlegen und bereinigen (WPF) – **nur Testumgebungen** |
| [fakeBitlockerData](src/fakeBitlockerData/README.md) | 0.0.3 | 14.10.2026 | Fake-BitLocker-/LAPS-Testdaten an AD-Computern erzeugen, prüfen, entfernen (Konsole) – **nur Testumgebungen** |

## Ordnerstruktur

```
.
├── src/
│   ├── easyADDummyUserCreator/
│   │   ├── easyADDummyUserCreator.ps1
│   │   ├── AD_DummyUserList.csv      # fiktive Beispieldaten
│   │   └── README.md
│   ├── easyExecutionPolicy/
│   │   ├── easyExecutionPolicy.ps1
│   │   └── README.md
│   ├── easyPSInfo/
│   │   ├── easyPSInfo.ps1
│   │   └── README.md
│   ├── easyWINUpdate/
│   │   ├── easyWINUpdate.ps1
│   │   └── README.md
│   └── fakeBitlockerData/
│       ├── fakeBitlockerData.ps1
│       └── README.md
├── docs/
│   └── AUDIT.md                      # Audit-Bericht 14.10.2026
├── assets/
│   └── screenshots/<Tool>/           # Ablage für aktuelle Screenshots
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
└── SECURITY.md
```

Pro Tool gibt es genau ein Skript ohne Versionsnummer im Dateinamen; die Version steht im Skript-Header, in der
README des Tools und im [CHANGELOG](CHANGELOG.md). Ältere Versionen sind nur noch über die Git-Historie verfügbar.
Zur Laufzeit legen die Tools Ordner wie `Logs/` und `Exports/` neben dem Skript an – diese sind per `.gitignore` ausgeschlossen.

## Ausführen der Skripte

Heruntergeladene Dateien sind als „aus dem Internet“ markiert und sollten zuerst freigegeben werden:

```powershell
Get-ChildItem -Path .\src -Recurse -Filter *.ps1 | Unblock-File
```

### Ausführungsrichtlinien in PowerShell

| Richtlinie | Beschreibung |
|------------|--------------|
| `Restricted` | Keine Skriptausführung erlaubt (Standard auf Windows-Clients) |
| `AllSigned` | Nur signierte Skripte erlaubt |
| `RemoteSigned` | Lokale Skripte erlaubt, Remote-Skripte müssen signiert sein (Standard auf Windows Server) |
| `Unrestricted` | Alle Skripte können ausgeführt werden (mit Warnung) |
| `Bypass` | Keine Einschränkungen, keine Warnungen |

```powershell
# Aktuelle Richtlinien anzeigen
Get-ExecutionPolicy -List

# Empfohlen: nur für den aktuellen Prozess lockern
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Oder direkt beim Start
powershell.exe -ExecutionPolicy Bypass -File .\src\easyWINUpdate\easyWINUpdate.ps1

# Dauerhaft für den aktuellen Benutzer
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Code-Signing

Seit dem Audit vom 14.10.2026 sind die Skripte **nicht signiert** – die bisherigen Authenticode-Signaturen wurden
durch die Codeänderungen ungültig und deshalb entfernt. Bei `AllSigned` die Skripte vor dem Einsatz selbst signieren:

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
Get-ChildItem -Path .\src -Recurse -Filter *.ps1 | ForEach-Object {
    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert -TimestampServer 'http://timestamp.digicert.com'
}
```

## Voraussetzungen (allgemein)

- Windows 10/11 oder Windows Server 2016 – 2025
- Windows PowerShell 5.1 oder PowerShell 7.x (Windows, STA-Modus für die GUI-Tools)
- Tool-spezifische Module und Rechte: siehe README des jeweiligen Tools

## Hinweis zur Sicherheit

Verwende diese Skripte nur in kontrollierten Umgebungen und prüfe den Quellcode vor der Ausführung.
Die AD-Testdaten-Tools sind ausschließlich für Test-/Laborumgebungen gedacht. Details: [SECURITY.md](SECURITY.md).

## Ausgelagerte Tools

Folgende Tools waren früher Teil dieses Repositorys und wurden in eigene Repositories ausgelagert bzw. entfernt
(Details im [CHANGELOG](CHANGELOG.md)): easyWSAudit, easyWSMigrate, easyADReport (vormals easyADAudit/easyADFind),
easyADPASSWORD, easyINIEditor, easySPO.

## Lizenz

[MIT License](LICENSE) – Nutzung auf eigene Verantwortung.

## Autor

- **Autor:** Andreas Hepp – PhinIT (www.phinit.de)
- **Repository:** <https://github.com/PS-PhinIT/PhinIT.PowerShell_Tools>
