# Tunemarchy

A compact bar player for the [OmaSpotify fork](https://github.com/atlastimed/omaspotify),
for **Omarchy 4.5**. Album art, seek, playback, shuffle, repeat and volume stay
close at hand. Queue and Spotify Connect devices expand when you need them.
OmaSpotify owns playback, your library and the account connection.

## Install

Install both plugins, then hide OmaSpotify's own bar entry:

```bash
omarchy plugin add https://github.com/atlastimed/omaspotify.git --enable
omarchy plugin add https://github.com/atlastimed/tunemarchy.git --enable
omarchy bar set io.github.atlastimed.omaspotify showBarWidget false --json
```

Click Tunemarchy and choose **Open** to set up OmaSpotify. A personal Spotify
Premium account is required. OmaSpotify guides you through its account and
local playback authorizations; Tunemarchy has no additional sign-in.

## Controls

| Action | Result |
| --- | --- |
| Left click the bar | Open / close the compact player |
| Middle click | Play / pause |
| Right click | Open the full OmaSpotify player |
| Scroll the bar | Volume (configurable) |
| Arrows or h/j/k/l | Move the panel cursor |
| Left / right on seek or volume | Adjust that slider |
| Enter / Space | Activate the selected control |
| n / p, s / r, f | Next / previous, shuffle / repeat, like |
| q / d, o | Expand queue / devices, open full player |
| Tab / Shift+Tab | Adjacent Omarchy panel |
| Escape | Close |

The panel follows the active Omarchy theme, scale and language, with English
fallback strings. Track names are always displayed as plain text.

## Settings

Use `omarchy bar set atlastimed.tunemarchy <key> <value>`:

| Key | Default | Meaning |
| --- | --- | --- |
| `showArtist` | `true` | Include the artist in the bar |
| `maxWidth` | `240` | Label width at the base UI scale; `0` for icon only |
| `whenClosed` | `icon` | Keep an icon or `hide` when no player is available |
| `scrollAction` | `volume` | `volume`, `skip`, or `off` |

Existing IPC shortcuts remain available: `omarchy-shell tunemarchy playPause`,
`next`, `previous`, `like`, `seek 10`, and `status`. To toggle the panel:
`omarchy-shell shell toggle atlastimed.tunemarchy '{}'`.

## Updating from 0.1

This version replaces the standalone Spotify desktop integration with the
OmaSpotify companion. The official desktop client can remain installed.
Tunemarchy's old `clientId` setting is ignored. Its previous keyring entry is
left intact so rolling back does not require another sign-in. When you no
longer need it, remove only that legacy entry with:

```bash
secret-tool clear service tunemarchy
```

Your existing bar placement and other settings carry over.

## Runtime and privacy

Tunemarchy starts no helper processes and makes no Spotify API requests. One
persistent Unix socket in your private `XDG_RUNTIME_DIR` carries a versioned,
bounded public playback snapshot and a fixed list of playback commands.
Tokens stay inside OmaSpotify. The socket is scoped to your Wayland display;
other local processes running as your user can control it, just like MPRIS.

Snapshots are pushed on changes. Progress updates run only while a player
panel is visible. Queue and devices are fetched when expanded, and the queue
refreshes on track changes while expanded. Multiple monitors share one
connection. Artwork loads only while the compact player is open and only
from Spotify image hosts. Disconnection clears stale state and reconnects
automatically. OmaSpotify's own API policies still apply.

## Development

```bash
scripts/check-plugin.sh
node --test tests/model.test.mjs
# From the OmaSpotify checkout, test the real socket pair:
TUNEMARCHY_SOURCE=/path/to/tunemarchy scripts/test-companion.sh
```

Install a Git checkout as a real directory under `~/.config/omarchy/plugins/`.
A symlink is not watched reliably. Validate with `omarchy plugin validate`,
then use `omarchy-shell shell rescanPlugins` to reload without restarting the
shell. Never edit Omarchy's packaged components.

MIT — see [LICENSE](LICENSE).
