# easyPSInfo v0.0.4 – PowerShell Module & Policy Manager mit Script-Launcher

WPF-Oberfläche, die den Status wichtiger Microsoft-365-/Azure-PowerShell-Module anzeigt, diese installiert bzw. aktualisiert,
Ausführungsrichtlinien verwaltet und PowerShell-Skripte startet.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#easypsinfo-003--004)
- **Screenshots:** [assets/screenshots/easyPSInfo](../../assets/screenshots/easyPSInfo/)

## Funktionen

| Bereich | Funktionen |
|---------|------------|
| Module | Status von ExchangeOnlineManagement, Microsoft.Graph(.Beta), Microsoft.Entra(.Beta), PnP.PowerShell, Microsoft.Online.SharePoint.PowerShell, AzureAD, MSOnline, PowerShellGet; Installation/Update aus der PSGallery (`-Scope CurrentUser`) im Hintergrund nach Bestätigung |
| Ausführungsrichtlinien | Anzeige aller Scopes; Setzen für Process/CurrentUser/LocalMachine (Unrestricted/Bypass nur nach Sicherheitsabfrage). MachinePolicy/UserPolicy (GPO) und „Effective“ sind schreibgeschützt |
| Script-Launcher | Listet `.ps1`-Dateien im Skriptordner und dessen Unterordnern (Ordner mit „old“ im Namen werden übersprungen, das Tool selbst wird nicht angeboten) und startet sie nach Bestätigung |

## Voraussetzungen

- Windows, Windows PowerShell 5.1 oder PowerShell 7.x (STA-Modus, Standard)
- Internetzugang zur PowerShell Gallery (TLS 1.2 wird unter PS 5.1 automatisch aktiviert)
- Administratorrechte nur für den Scope `LocalMachine` (das Tool bietet einen Neustart mit UAC an)

## Start

```powershell
Unblock-File -Path .\src\easyPSInfo\easyPSInfo.ps1
powershell.exe -File .\src\easyPSInfo\easyPSInfo.ps1
```

Parameter: keine. Eigene Skripte für den Launcher in `src/easyPSInfo/` oder einen Unterordner davon ablegen
(oder das Tool in den gewünschten Skriptordner kopieren).

## Logs

- `src/easyPSInfo/Logs/easyPSInfo.log` – Pfade werden maskiert (`<ScriptRoot>`, `%USERPROFILE%`, `\\<server>\<share>`)
- Fallback, wenn der Ordner nicht beschreibbar ist: `%LOCALAPPDATA%\PhinIT\easyPSInfo\Logs`

## Bekannte Einschränkungen

- AzureAD und MSOnline sind von Microsoft abgekündigt/eingestellt und werden nur noch zur Statusanzeige geführt.

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
