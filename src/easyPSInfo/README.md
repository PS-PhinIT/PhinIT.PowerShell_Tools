# easyPSInfo v0.0.5 – PowerShell Module & Policy Manager mit Script-Launcher

Deutschsprachige WPF-Oberfläche, die den Status wichtiger Microsoft-365-/Azure-PowerShell-Module anzeigt, diese installiert bzw. aktualisiert,
Ausführungsrichtlinien verwaltet und PowerShell-Skripte startet.

- **Changelog:** [CHANGELOG.md](../../CHANGELOG.md)
- **Audit-Bericht:** [docs/AUDIT.md](../../docs/AUDIT.md#easypsinfo-003--004) · [Nacharbeiten](../../docs/AUDIT.md#nacharbeiten--zweite-runde)
- **Screenshots:** [assets/screenshots/easyPSInfo](../../assets/screenshots/easyPSInfo/)

## Funktionen

| Bereich | Funktionen |
|---------|------------|
| Module | Status von ExchangeOnlineManagement, Microsoft.Graph(.Beta), Microsoft.Entra(.Beta), PnP.PowerShell, Microsoft.Online.SharePoint.PowerShell, AzureAD, MSOnline, PowerShellGet mit Spalte „Status“ (OK/Veraltet/Fehlt/Abgekündigt); Installation/Update aus der PSGallery (`-Scope CurrentUser`) im Hintergrund nach Bestätigung. AzureAD und MSOnline sind als „(abgekündigt)“ markiert (Tooltip mit Nachfolger) |
| Ausführungsrichtlinien | Anzeige aller Scopes; Setzen für Process/CurrentUser/LocalMachine (Unrestricted/Bypass nur nach Sicherheitsabfrage). MachinePolicy/UserPolicy (GPO) und „Effective“ sind schreibgeschützt |
| Script-Launcher | Listet `.ps1`-Dateien im Basisordner und dessen Unterordnern (max. 5 Ebenen) und startet sie nach Bestätigung. Standard-Basisordner: `src` mit allen Tools des Repositorys, wenn das Tool unter `src\easyPSInfo\` liegt – sonst der eigene Skriptordner. „Ordner wählen…“ setzt einen anderen Basisordner, „Standard“ setzt ihn zurück. Übersprungen werden `Logs`, `Exports`, `Backups`, Ordner mit „old“ im Namen, Junctions/Links und nicht zugreifbare Ordner; das Tool selbst wird nicht angeboten |

## Voraussetzungen

- Windows, Windows PowerShell 5.1 oder PowerShell 7.x (STA-Modus, Standard)
- Internetzugang zur PowerShell Gallery (TLS 1.2 wird unter PS 5.1 automatisch aktiviert)
- Administratorrechte nur für den Scope `LocalMachine` (das Tool bietet einen Neustart mit UAC an)

## Start

```powershell
Unblock-File -Path .\src\easyPSInfo\easyPSInfo.ps1
powershell.exe -File .\src\easyPSInfo\easyPSInfo.ps1
```

Parameter: keine. Der gewählte Basisordner des Launchers wird in `%APPDATA%\PhinIT\easyPSInfo\settings.json` gespeichert
(beim Laden geprüft; ungültige Einstellungen → Standard-Basisordner).

## Logs

- `src/easyPSInfo/Logs/easyPSInfo.log` – Pfade werden maskiert (`<ScriptRoot>`, `<ScriptBase>`, `%USERPROFILE%`, `\\<server>\<share>`)
- Fallback, wenn der Ordner nicht beschreibbar ist: `%LOCALAPPDATA%\PhinIT\easyPSInfo\Logs`

## Bekannte Einschränkungen

- AzureAD und MSOnline sind von Microsoft abgekündigt/eingestellt. Sie werden als „abgekündigt“ markiert, die Installation bleibt für Altskripte möglich (mit Hinweis).

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
