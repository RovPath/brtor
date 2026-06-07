# brtor

> Multi-account browser session manager with VPN and Tor routing.  
> Compatible with **Linux** and **macOS**.

---

## Features

- **Isolated profiles** — each account runs in a completely separate browser directory
- **VPN proxy** — routes traffic through a local SOCKS5 proxy (e.g. Xray, Shadowsocks, sing-box)
- **Tor integration** — one-key toggle; automatically starts/stops the `tor` service
- **Per-profile settings** — name, start URL, proxy on/off
- **Backup manager** — export/import single profiles or full environment as `.tar.gz`
- **Session logs** — per-profile `session.log` for quick debugging
- **First-run wizard** — auto-detects installed browsers and configures defaults

## Supported Browsers

| Browser | Proxy isolation | Fingerprint flags |
|---------|----------------|-------------------|
| qutebrowser | ✅ | via `-s content.proxy` |
| Chromium / Brave / Chrome | ✅ | `--user-data-dir`, WebRTC disabled |
| Firefox | ✅ | `user.js` with SOCKS5 + `resistFingerprinting` |
| Other | ⚠️ partial | launched without isolation flags |

## Requirements

**Linux:** `bash`, `ss`, `systemctl`, `tar`, `sudo`  
**macOS:** `bash`, `lsof`, `tar`  
**Optional:** `tor` (for Tor mode), a SOCKS5 VPN client (for VPN mode)

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/brtor.git
cd brtor
chmod +x brtor.sh
./brtor.sh
```

## Configuration

Config is stored at `~/.config/brtor/config.conf`:

```bash
DEFAULT_BROWSER="qutebrowser"
VPN_PORT="10808"
TOR_PORT="9050"
TOR_ENABLED="false"
```

Profile list is stored at `~/.config/brtor/profiles.list` (pipe-separated):

```
acc_1234567890_0042|Work|true|https://example.com
acc_1234567890_1337|Personal|false|https://claude.ai
```

## Usage

```
  1)  Work                             [VPN]
  2)  Personal                         [DIRECT]

  t)  Toggle Tor mode
  a)  Add profile
  e)  Edit profile
  c)  Clear cache
  d)  Delete profile
  l)  View session logs
  i)  Backup manager
  s)  Settings
  q)  Quit
```

Enter a number to launch that profile's browser session.

## Backup & Restore

- **Single profile export** → `~/brtor_backups/<id>_backup_<timestamp>.tar.gz`
- **Full export** → `~/brtor_backups/brtor_FULL_GROUP_BACKUP_<date>.tar.gz`
- Restore via the **Backup Manager** menu (option `i`)

## License

MIT
