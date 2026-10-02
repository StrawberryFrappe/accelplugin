# HW Accel Toggler for Opera GX

An Opera GX extension (Windows). When you open Netflix, Crunchyroll or another site on your list, it asks whether to turn **hardware acceleration off**. The prompt shows the setting itself and a **Restart browser** button.

When you're done watching, it turns hardware acceleration back **on** and restarts Opera GX by itself. That happens once all of these are true:

- hardware acceleration is off,
- no window's active tab is one of your sites,
- 15 minutes have passed since one was (you can change this).

Your tabs come back after every restart.

## Why there's a helper

Browser extensions can't change hardware acceleration or restart the browser, because Opera and Chrome don't offer an API for either. The setting lives in Opera's `Local State` file, and that file can only be changed while Opera is closed.

The `native-host` folder holds a small PowerShell helper that the extension talks to through Opera's native messaging. When asked, the helper:

1. closes Opera GX the normal way, as if you clicked X,
2. backs up `Local State`, then changes only the hardware acceleration entries,
3. starts Opera GX again and restores your tabs.

It uses only Windows' built-in PowerShell, needs no admin rights, and never touches regular Opera.

## Install

1. Put this folder somewhere permanent, for example `C:\Tools\accelplugin`. The helper is registered by its path.
2. **Load the extension:**
   1. In Opera GX, open `opera://extensions` and switch on **Developer mode** (top right).
   2. Click **Load unpacked** and choose the `extension` folder.
   3. Check that the extension ID is `lbheolnljihmphgebojmlbifcfmchhnk`. It's fixed by the `key` in `manifest.json`.
3. **Install the helper:** with Opera GX open, double-click `native-host\install.bat`. It finds Opera GX and its `Local State`, and asks you if it can't.
4. **Restart Opera GX** once, so it picks up the helper.
5. Open the extension's **Settings** (right-click its icon → Options) and click **Test helper**. It should say *Installed* and show your current state. The test changes nothing.

## Use

- **Open a listed site.** A banner appears in the top-right corner with:
  - the *Use hardware acceleration when available* switch,
  - **Turn off & restart**,
  - **Not now**, which stops asking until Opera GX restarts,
  - **Open setting**, which opens Opera's own settings page.
- **The toolbar popup** shows the current state and the time left before the automatic re-enable. You can switch the setting either way from there at any time.
- **Automatic re-enable.** When the countdown runs out, a notification warns you 60 seconds before the restart and offers **Restart now** and **Postpone**.

## Settings

| Setting | Default |
|---|---|
| Sites (subdomains included) | `netflix.com`, `crunchyroll.com` |
| Turn hardware acceleration back on automatically | on |
| Re-enable after no listed site has been the active tab for | 15 min |
| Warn before restarting (0 = no warning) | 60 s |

When you add a site, Opera asks for permission to show the banner there.

## Troubleshooting

- **"Helper not installed"**:
  - Run `native-host\install.bat` again, then restart Opera GX.
  - If you moved the folder, run the installer again.
  - If the extension ID differs from the one above, run `install.ps1 -ExtensionId <your id>`.
- **Log:** `%LOCALAPPDATA%\accelplugin\apply.log` records every restart, step by step.
- **Backup:** before each change, the previous `Local State` is saved next to it as `Local State.accelplugin.bak`, in `%APPDATA%\Opera Software\Opera GX Stable\`.
- **Check the result:** `opera://gpu` shows whether hardware acceleration is on.
- **If Opera GX takes more than 30 s to close** (for example, it's waiting on a "close N tabs?" dialog), the helper force-closes it. Your tabs are still restored.

## Uninstall

1. Double-click `native-host\uninstall.bat`.
2. Remove the extension in `opera://extensions`.
3. Delete the folder.

## Development

```
npm test                                         # extension logic (Node 18+)
pwsh -NoProfile -File tests/native-host.tests.ps1 # Local State patching + helper protocol
```

Layout:

- `extension/`: the MV3 extension.
  - `background.js`: the service worker with the prompt and timer logic.
  - `content/banner.js`: the in-page prompt.
  - `popup/`, `options/`: the toolbar popup and the settings page.
  - `lib/`: pure logic, unit-tested.
- `native-host/`:
  - `host.ps1`: the native messaging host.
  - `apply.ps1`: closes Opera, patches `Local State`, relaunches.
  - `common.ps1`: shared functions.
  - `install.ps1` and `uninstall.ps1`.
