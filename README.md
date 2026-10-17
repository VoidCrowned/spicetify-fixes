# Spicetify Fixes

> [!WARNING]
> This is my personal fix collection for my own setup: Windows, Spotify 1.3.4, Spicetify 2.45.3.
> There's no support and no guarantee. It may break things. Use it at your own risk.
> It is not a Marketplace extension.
> Each fix switches itself off on Spicetify versions it wasn't tested on.

To remove it again: double-click `uninstall.cmd`. Details: [Uninstall](#uninstall).

## Contents

- [What it fixes](#what-it-fixes)
  - [Profile menu won't open](#profile-menu-wont-open-menuitem-v2)
  - [Top-bar buttons never appear](#top-bar-buttons-never-appear-topbar-history-class)
- [Install on Windows, the easy way](#install-on-windows-the-easy-way)
- [Install manually (any OS)](#install-manually-any-os)
  - [Windows (PowerShell)](#windows-powershell)
  - [macOS and Linux](#macos-and-linux)
- [Updating](#updating)
- [After Spotify updates itself](#after-spotify-updates-itself)
- [Uninstall](#uninstall)
  - [Uninstall manually (any OS)](#uninstall-manually-any-os)
  - [Want Spotify without Spicetify entirely?](#want-spotify-without-spicetify-entirely)
- [Something went wrong?](#something-went-wrong)
- [Licence](#licence)

## What it fixes

It applies known fixes for Spicetify bugs until Spicetify ships them in a release.
Each fix checks whether its bug is really there before it changes anything.

### Profile menu won't open (`menuitem-v2`)

**What you notice:** clicking your profile picture does nothing. The console shows `cannot be rendered outside a collection`. It happens as soon as any Spicetify or extension entry sits in the profile menu.

**Cause:** on Spotify 1.3.4, Spicetify picks Spotify's newer menu item, which only works inside Spotify's newer menus. Spicetify draws its profile-menu entries inside the older menu, so the whole menu crashes. The fix swaps in Spotify's menu item that works in both.

**Affected:** Spicetify 2.45.3 on Spotify 1.3.4 (verified on 1.3.4.258, 16 Oct 2026).

**Upstream:**

- [spicetify/cli#4012](https://github.com/spicetify/cli/pull/4012): describes exactly this and proposes the same fix (closed, not merged).
- [spicetify/cli#3965](https://github.com/spicetify/cli/issues/3965): the same wrong lookup on Spotify 1.3.1 (closed as fixed in 2.45.1).
- [spicetify/marketplace#1248](https://github.com/spicetify/marketplace/issues/1248): possibly related, the profile menu opens only once.

**Stops applying:** when Spicetify picks the right menu item by itself (`not-needed`), or on any Spicetify version other than 2.45.3 (`untested-version`).

### Top-bar buttons never appear (`topbar-history-class`)

**What you notice:** buttons that extensions and themes add to the top bar never show up, e.g. Hazy's pencil.

**Cause:** Spicetify waits for a class on Spotify's back/forward buttons before it adds top-bar buttons. Spicetify 2.45.3 doesn't know that class's new name in Spotify 1.3.4, so it waits forever. The fix adds the class.

**Affected:** Spicetify 2.45.3 on Spotify 1.3.4 (verified on 1.3.4.258).

**Upstream:**

- [spicetify/cli@1684023](https://github.com/spicetify/cli/commit/1684023): fixed on main on 11 Oct 2026, not released as of v2.45.3.
- No upstream issue: spicetify/cli currently only lets collaborators open issues.

**Stops applying:** when Spotify's buttons already have the class, e.g. after the next Spicetify release (`not-needed`), or on any Spicetify version other than 2.45.3 (`untested-version`).

## Install on Windows, the easy way

**You need:**

- [Spicetify CLI](https://spicetify.app/docs/getting-started) v2, installed and working.
- [Git](https://git-scm.com).
- Optional: Windows Developer Mode (Settings → System → For developers). Then the symlink needs no admin prompt.

**Steps:**

1. Open a terminal in the folder where you want the fixes to live.

2. Copy and run:

   ```
   git clone https://github.com/VoidCrowned/spicetify-fixes
   ```

   You should see: `Cloning into 'spicetify-fixes'...` and a new `spicetify-fixes` folder.

3. Open the `spicetify-fixes` folder in Explorer.

4. Double-click `install.cmd`.

   You should see: a window with steps `[1/4]` to `[4/4]`, each with a green `OK`.

5. If it asks `Create the link with an admin prompt? [Y/n]`, press Enter and click **Yes** in the Windows prompt.

   You should see: `OK    Linked ...`.

6. Wait for Spotify to restart.

   You should see: `Done. To check it works:` in the window. Press any key to close it.

**Check it worked:**

1. Copy and run:

   ```
   spicetify enable-devtools
   ```

   You should see: Spotify restart.

2. In Spotify, press `Ctrl+Shift+I` and open the **Console** tab.

3. Type this and press Enter:

   ```js
   __fixes.status()
   ```

   You should see something like:

   ```
   [spicetify-fixes] Spicetify 2.45.3, Spotify 1.3.4.258.g...
   ┌─────────┬────────────────────────┬───────────┬──────────────────────────────┬───────┐
   │ (index) │ id                     │ state     │ detail                       │ error │
   ├─────────┼────────────────────────┼───────────┼──────────────────────────────┼───────┤
   │ 0       │ 'menuitem-v2'          │ 'applied' │ 'Spicetify.ReactComponent... │ null  │
   │ 1       │ 'topbar-history-class' │ 'applied' │ 'added .main-globalNav-hi... │ null  │
   └─────────┴────────────────────────┴───────────┴──────────────────────────────┴───────┘
   ```

`not-needed` is fine too: it means the bug isn't there on your setup.

> [!NOTE]
> Downloading the repo as a ZIP works too, but Windows may block the scripts.
> Fix: right-click each `.cmd` file → Properties → tick **Unblock** → OK.
> Cloning avoids that and makes updating easy.

## Install manually (any OS)

Why a symlink and not a copy: then a `git pull` updates the fixes, and `spicetify apply` picks them up.

### Windows (PowerShell)

1. Clone the repo and go into it:

   ```powershell
   git clone https://github.com/VoidCrowned/spicetify-fixes
   cd spicetify-fixes
   ```

2. Find Spicetify's folder:

   ```powershell
   spicetify path userdata
   ```

   You should see: a folder, e.g. `C:\Users\<you>\AppData\Roaming\spicetify`. That's `<userdata>` below.

3. Create the symlink. Replace `<userdata>` and `<repo>` (the full path of the `spicetify-fixes` folder):

   ```powershell
   New-Item -ItemType SymbolicLink -Path "<userdata>\Extensions\spicetifyFixes.js" -Target "<repo>\spicetifyFixes.js"
   ```

   This needs an admin PowerShell. Windows PowerShell 5.1 ignores Developer Mode here.
   With Developer Mode on, this works without admin rights instead:

   ```powershell
   cmd /c mklink "<userdata>\Extensions\spicetifyFixes.js" "<repo>\spicetifyFixes.js"
   ```

   You should see: the new link listed, or `symbolic link created for ...`.

4. Add the extension:

   ```powershell
   spicetify config extensions spicetifyFixes.js
   ```

5. Apply:

   ```powershell
   spicetify apply
   ```

   You should see: green `success` lines (e.g. `Refreshed extensions`) and Spotify restart.

### macOS and Linux

1. Clone the repo and go into it:

   ```sh
   git clone https://github.com/VoidCrowned/spicetify-fixes
   cd spicetify-fixes
   ```

2. Create the symlink:

   ```sh
   ln -s "$PWD/spicetifyFixes.js" "$(spicetify path userdata)/Extensions/spicetifyFixes.js"
   ```

   You should see: no output. That means it worked.

3. Add the extension:

   ```sh
   spicetify config extensions spicetifyFixes.js
   ```

4. Apply:

   ```sh
   spicetify apply
   ```

   You should see: green `success` lines (e.g. `Refreshed extensions`) and Spotify restart.

## Updating

Double-click `update.cmd`.

You should see: steps `[1/3]` to `[3/3]` with green `OK`s, then Spotify restart.

By hand:

```sh
git pull
spicetify apply
```

## After Spotify updates itself

Spotify's update removes Spicetify's changes. Run:

```sh
spicetify backup apply
```

You should see: Spotify restart with Spicetify back. The fixes come back with it.

## Uninstall

`uninstall.cmd` removes everything this repo added to Spicetify.
It never touches Spicetify itself, other extensions, themes, or this folder's files.

**Steps:**

1. Open the `spicetify-fixes` folder in Explorer.

2. Double-click `uninstall.cmd`.

   You should see: a short list of what will happen, then `Remove spicetify-fixes from Spicetify? [Y/n]`.

3. Press Enter (Enter means yes).

   You should see: steps `[1/5]` to `[5/5]`. Spotify restarts during step 4.

4. Read step 5, the summary.

   You should see: `OK    spicetifyFixes.js is no longer in Spicetify's list.` and `OK    The file is gone from ...`, then what that means: the bugs come back. With extension entries in the profile menu, the menu won't open, and top-bar buttons disappear.

5. Answer `Open this folder in Explorer so you can delete it? [y/N]`.
   - Want to delete the folder too: type `y` and press Enter.

     You should see: Explorer with the `spicetify-fixes` folder selected. Close the uninstall window, then delete the folder.
   - Want to keep it: press Enter.

   If the folder has local changes that aren't on GitHub, you see a warning first.

**What's left afterwards:** nothing in Spicetify. Only the `spicetify-fixes` folder, if you keep it.

If you answer `n` to the first question, it stops and nothing changes.

### Uninstall manually (any OS)

1. Take it off Spicetify's list:

   ```sh
   spicetify config extensions spicetifyFixes.js-
   ```

2. Check the list:

   ```sh
   spicetify config extensions
   ```

   You should see: the other extensions, but not `spicetifyFixes.js`.

3. Find Spicetify's folder:

   ```sh
   spicetify path userdata
   ```

   You should see: a folder. `Extensions` is inside it.

4. Delete `spicetifyFixes.js` from that `Extensions` folder. It's a link or a copy; deleting it doesn't touch the repo.

   Windows (PowerShell):

   ```powershell
   Remove-Item "$(spicetify path userdata)\Extensions\spicetifyFixes.js"
   ```

   macOS and Linux:

   ```sh
   rm "$(spicetify path userdata)/Extensions/spicetifyFixes.js"
   ```

5. Apply:

   ```sh
   spicetify apply
   ```

   You should see: green `success` lines and Spotify restart.

6. Optional: delete the `spicetify-fixes` folder.

### Want Spotify without Spicetify entirely?

That's not this repo's job.

- `spicetify restore` returns Spotify to normal and keeps Spicetify's settings.
- To remove Spicetify itself: https://spicetify.app/docs/advanced-usage/uninstallation

## Something went wrong?

| What you see | What to do |
|---|---|
| `Spicetify was not found.` | Install Spicetify: https://spicetify.app/docs/getting-started. Then open a **new** window and try again. |
| `should NOT be run with administrator` or `Don't run this as administrator` | Close the window. Double-click the `.cmd` file normally, not with "Run as administrator". |
| `Copied instead of linked.` | The symlink failed. It still works, but run `update.cmd` after every `git pull`. Or turn on Developer Mode and run `install.cmd` again. |
| `__fixes.status()` shows `untested-version` | The bug is still there, but this Spicetify version wasn't tested. The fix stays off. Wait for an update of this repo. |
| `__fixes.status()` shows `skipped` | Spotify didn't finish loading within 30 s. Restart Spotify and check again. |
| `__fixes` is not defined | The extension isn't loaded. Run `install.cmd` again and check that step 3 says `OK`. |
| Uninstall: `Spicetify was not found. Skipping its list and spicetify apply` | Fine if you removed Spicetify already. Only the file was removed. |
| Uninstall: `Not ours (folder)` | A folder named `spicetifyFixes.js` is in the Extensions folder. It wasn't made by this repo, so it's left. Delete it by hand if you don't need it. |
| Uninstall: `ERROR ... is still in ...` | Close Spotify, then double-click `uninstall.cmd` again. Or delete the file by hand (see [Uninstall manually](#uninstall-manually-any-os)). |
| Uninstall: `Not finished.` | Read the `ERROR` lines above it. Each one has a next step. Then run `uninstall.cmd` again. |
| Uninstall: `local changes that aren't on GitHub` | Files in the folder differ from GitHub. Deleting the folder loses them. Keep them if you need them. |

## Licence

Copyright © 2026 VoidCrowned. This program is free software. It comes without any warranty, to the extent permitted by applicable law. You can redistribute it and/or modify it under the terms of the Do What The Fuck You Want To Public License, Version 2, as published by Sam Hocevar. See [LICENSE](LICENSE) or http://www.wtfpl.net/ for more details.
