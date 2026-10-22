# Tunemarchy

What Spotify is playing, in the Omarchy bar. Click it for a dropdown with seek,
play/pause, skip, shuffle, repeat and volume. Optionally, sign in to Spotify to
save songs to Liked Songs, see what's up next, and move playback between your
Spotify Connect devices.

It is deliberately small and dependable:

- **Works with no setup.** Playback, seek, shuffle, repeat and volume use
  Spotify's own MPRIS interface: no account link, no API calls.
- **Nothing extra running.** No daemon, no systemd service, no sudo, no
  second Quickshell. The only helper is a short-lived Python script (standard
  library only) that runs while you sign in or when an access token needs
  refreshing, roughly once an hour while you use the extras.
- **Few Spotify API calls.** One request when the track changes (is it liked?)
  and a couple when you open the dropdown (queue, devices). Nothing polls in the
  background.

Requires Omarchy 4 and the Spotify desktop app (Omarchy installs it; also works
with spotifyd and other players that expose `org.mpris.MediaPlayer2.spotify*`).

## Install

```bash
omarchy plugin add https://github.com/atlastimed/tunemarchy.git --enable
```

The widget appears on the right of the bar. Move it with
`omarchy bar move atlastimed.tunemarchy --before omarchy.bluetooth` (or any
other placement).

## Likes, queue and devices (optional)

Spotify only lets each person use these through their own developer app, and
the app's owner needs Spotify Premium. Setting it up takes two minutes:

1. Open <https://developer.spotify.com/dashboard> and click **Create app**.
2. Fill in:
   - **App name:** anything that doesn't start with "Spot", for example
     `Tunemarchy`
   - **App description:** anything, for example `My Omarchy bar widget`
   - **Redirect URI:** `http://127.0.0.1:43117/callback` (then click **Add**)
   - **Which API/SDKs:** tick **Web API**
3. Accept the terms and click **Save**, then copy the **Client ID** from the
   app's page. You do not need the client secret.
4. Give the Client ID to the widget:

   ```bash
   omarchy bar set atlastimed.tunemarchy clientId YOUR_CLIENT_ID
   ```

5. Open the dropdown, click **Sign in to Spotify**, and approve access in the
   browser tab that opens.

Spotify ends a sign-in after 180 days; the dropdown then offers to sign in
again. All Development Mode apps on one developer account share a single API
quota. If it runs out, the extras pause until it resets and playback controls
keep working.

## Controls

| In the bar | Action |
| --- | --- |
| Left click | Open the dropdown (opens Spotify if it isn't running) |
| Middle click | Play / pause |
| Right click | Show Spotify |
| Scroll | Volume (or skip, or nothing; see settings) |

| In the dropdown | Action |
| --- | --- |
| `Space` / `Enter` | Play / pause |
| `←` `→` (or `h` `l`) | Seek 10 seconds |
| `↑` `↓` (or `k` `j`) | Volume |
| `n` / `p` | Next / previous |
| `s` / `r` | Shuffle / cycle repeat |
| `f` | Save to or remove from Liked Songs |
| `1`–`9` | Move playback to that device |
| `o` | Show Spotify |
| `Esc` | Close |

### Keyboard shortcuts

The widget answers shell IPC, so you can bind anything in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + M", "Tunemarchy", "omarchy-shell shell toggle atlastimed.tunemarchy '{}'")
o.bind("SUPER + ALT + L", "Like current song", "omarchy-shell tunemarchy like")
```

Then run `hyprctl reload` and check `hyprctl configerrors`. Other calls:
`omarchy-shell tunemarchy playPause | next | previous | seek 10 | seek -10 | status`,
and `players` to list every MPRIS player the shell sees (handy when the widget
cannot find Spotify).

## Settings

Change them in the bar's widget settings or with
`omarchy bar set atlastimed.tunemarchy <key> <value>`:

| Key | Default | Meaning |
| --- | --- | --- |
| `showArtist` | `true` | Show the artist after the title |
| `maxWidth` | `240` | Longest label in pixels; `0` shows only the icon |
| `whenClosed` | `icon` | `icon` keeps a dimmed icon that opens Spotify; `hide` removes the widget until Spotify starts |
| `scrollAction` | `volume` | `volume`, `skip` or `off` |
| `clientId` | empty | Your Spotify app's Client ID, for the optional extras |

## Privacy and security

- **Refresh token:** in your desktop keyring (GNOME Keyring), as
  "Tunemarchy: Spotify sign-in". It passes to and from `secret-tool` over stdin,
  never on a command line.
- **Access token:** kept in memory by the shell only, never written to disk.
- **Client ID:** in `~/.config/omarchy/shell.json`. It isn't a secret: sign-in
  uses PKCE, so there is no client secret anywhere.
- **Network:** `accounts.spotify.com` and `api.spotify.com` for the extras, and
  Spotify's image CDN for cover art (the URL Spotify itself reports).
- **Sign-in listener:** opens only while you sign in, on `127.0.0.1:43117`, and
  accepts only the redirect carrying that sign-in's random `state`.

**Sign out** in the dropdown's footer to delete the stored sign-in. To remove
the plugin entirely, run `omarchy plugin remove atlastimed.tunemarchy`, and
remove the app on Spotify's dashboard if you like.

## Development

```bash
scripts/check-plugin.sh          # manifest contract, settings, QML syntax
node --test tests/               # Model.js
python3 -m pytest -q             # sign-in helper (or: python3 -I -m unittest discover -s tests)
ruff check . && ruff format --check .
```

To work on a checkout, link it into the plugin folder:
`ln -s "$PWD" ~/.config/omarchy/plugins/atlastimed.tunemarchy`, then
`omarchy-shell shell rescanPlugins`. The shell's file watcher does not follow
symlinks, so load your edits with `omarchy restart shell`; a rescan alone can
leave the previous `Service.qml` running.

## License

MIT
