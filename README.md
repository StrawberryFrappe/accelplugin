# HW Accel Toggler

A browser extension for **Opera GX, Google Chrome, Brave and Firefox** on Windows.

When you open Netflix, Crunchyroll or another site on your list, it asks whether to turn **hardware acceleration off**. The prompt shows the setting itself and a **Restart browser** button.

When you're done watching, it turns hardware acceleration back **on** and restarts the browser by itself. That happens once all of these are true:

- hardware acceleration is off,
- no window's active tab is one of your sites,
- 15 minutes have passed since one was (you can change this).

Your tabs come back after every restart.

## Why there's a helper

Browser extensions can't change hardware acceleration or restart the browser; no browser offers an API for either. The setting lives in a file that can only be changed while the browser is closed:

| Browser | Setting | File |
|---|---|---|
| Opera GX, Chrome, Brave | `hardware_acceleration_mode` | `Local State` in the browser's user data folder |
| Firefox | `layers.acceleration.disabled` | `prefs.js` in your default profile |

The `native-host` folder holds a small PowerShell helper that the extension talks to through the browser's native messaging. When asked, the helper:

1. closes that browser the normal way, as if you clicked X,
2. backs up the settings file, then changes only the hardware acceleration entries,
3. starts the browser again and restores your tabs.

It uses only Windows' built-in PowerShell and needs no admin rights. It only works with the browsers you select when installing it. It also checks which browser is calling it, so it never restarts a browser you didn't pick (for example regular Opera, or Chrome when you only selected Opera GX).

## Install

1. **Put this folder somewhere permanent**, for example `C:\Tools\accelplugin`. The helper is registered by its path.
2. **Load the extension** in each browser you want to use it with:
   - **Opera GX / Chrome / Brave:**
     1. Open `opera://extensions`, `chrome://extensions` or `brave://extensions`, and switch on **Developer mode**.
     2. Click **Load unpacked** and choose the `extension` folder.
     3. Check that the extension ID is `lbheolnljihmphgebojmlbifcfmchhnk`. It's fixed by the `key` in `manifest.json`.
   - **Firefox:** see [Firefox](#firefox) below.
3. **Install the helper:** double-click `native-host\install.bat`.
   - It lists the four browsers, shows which ones it found, and asks which to set up. Type the numbers, e.g. `1` or `1,4`.
   - It works best with those browsers open, because it finds them from their running processes.
   - If it can't find a browser or its settings file, it asks you for the path and tells you where to look.
   - Run it again any time to change the selection. Browsers you leave out stop using the helper.
4. **Restart each selected browser** once, so it picks up the helper.
5. In each browser, open the extension's **Settings** (right-click its icon → Options) and click **Test helper**. It should say *Installed* and show your current state. The test changes nothing.

### Firefox

Firefox only keeps extensions installed permanently when Mozilla has signed them. An add-on loaded from `about:debugging` disappears when Firefox restarts, and restarting Firefox is exactly what this extension does. Pick one of these:

- **Sign it for yourself (free, private):**
  1. Create API keys at <https://addons.mozilla.org/developers/addon/api/key/>.
  2. Run:
     ```
     npx web-ext sign --source-dir extension --channel unlisted --api-key <key> --api-secret <secret>
     ```
     You need Node.js for this. Unlisted add-ons aren't published, only signed.
  3. Open the `.xpi` it creates in `web-ext-artifacts\` with Firefox.
- **Firefox Developer Edition, Nightly or ESR:** set `xpinstall.signatures.required` to `false` in `about:config`, then install the zipped `extension` folder from `about:addons` → gear icon → *Install Add-on From File*.

After installing:
- If the options page shows **Allow access** next to a site, click it. Firefox may not grant site access at install time.
- Firefox notifications can't have buttons. When the automatic restart is announced, click the notification itself to postpone it.
- **Open setting** can't open Firefox's settings page, because extensions aren't allowed to. Instead it tells you where the setting is: `about:preferences` → General → Performance.

## Use

- **Open a listed site.** A banner appears in the top-right corner with:
  - the *Use hardware acceleration when available* switch,
  - **Turn off & restart**,
  - **Not now**, which stops asking until the browser restarts,
  - **Open setting**, which opens the browser's own settings page.
- **The toolbar popup** shows the current state and the time left before the automatic re-enable. You can switch the setting either way from there at any time.
- **Automatic re-enable.** When the countdown runs out, a notification warns you 60 seconds before the restart and offers **Restart now** and **Postpone**.

## Settings

| Setting | Default |
|---|---|
| Sites (subdomains included) | `netflix.com`, `crunchyroll.com` |
| Turn hardware acceleration back on automatically | on |
| Re-enable after no listed site has been the active tab for | 15 min |
| Warn before restarting (0 = no warning) | 60 s |

When you add a site, the browser asks for permission to show the banner there.

## Troubleshooting

- **"Helper not installed" or "isn't set up for …":**
  1. Run `native-host\install.bat` again and select that browser.
  2. Restart the browser.

  Also run the installer again if you moved the folder.
- **Your extension ID is different** from the one above: run `install.ps1 -ExtensionId <your id>`.
- **Log:** `%LOCALAPPDATA%\accelplugin\apply.log` records every restart, step by step.
- **Backup:** before each change, the previous settings file is saved next to it as `Local State.accelplugin.bak` or `prefs.js.accelplugin.bak`.
- **Check the result:**
  - Chromium browsers: `opera://gpu`, `chrome://gpu` or `brave://gpu`.
  - Firefox: `about:support` → *Graphics*.
- **Firefox profile with a `user.js` that sets `layers.acceleration.disabled`:** that file wins on every start, so the helper's change won't stick. The extension warns you when this is the case.
- **Slow closing:**
  - If a browser takes more than 30 s to close (for example, it's waiting on a "close N tabs?" dialog), the helper force-closes it.
  - If it closes its windows but keeps running in the background (Chrome's *Continue running background apps*), the helper force-closes it after 8 s.

  Your tabs are still restored either way.

## Uninstall

1. Double-click `native-host\uninstall.bat`. This unregisters the helper from all browsers.
2. Remove the extension from each browser.
3. Delete the folder.

## Development

```
npm test                                          # extension logic (Node 18+)
pwsh -NoProfile -File tests/native-host.tests.ps1 # settings-file patching, browser table, helper protocol
npx web-ext lint --source-dir extension           # Firefox compatibility
```

Layout:

- `extension/`: one MV3 extension for all four browsers.
  - `manifest.json`: has both `background.service_worker` (Chromium) and `background.scripts` (Firefox), plus `browser_specific_settings` for Firefox.
  - `background.js`: the prompt and timer logic.
  - `content/banner.js`: the in-page prompt.
  - `popup/`, `options/`: the toolbar popup and the settings page.
  - `lib/`: pure logic, unit-tested.
    - `lib/ext.js`: picks `browser.*` (Firefox) or `chrome.*`.
    - `lib/browser.js`: detects the browser.
- `native-host/`:
  - `common.ps1`: the browser table (`Get-BrowserDefs`) and the `Local State` / `prefs.js` editing.
  - `host.ps1`: the native messaging host; works out which browser is calling.
  - `apply.ps1`: closes the browser, patches its settings, relaunches.
  - `install.ps1` and `uninstall.ps1`.
