# QuitOnClose

A small, free macOS background process that quits applications after you close their last window with the red close button. **Install it, approve permission, and forget about it.**

No menu-bar icon, Dock icon, Terminal window, or daily interface. It starts automatically when you log in.

**Two windows open? Closing one leaves the other alone. Close the last window, and QuitOnClose requests a normal quit.** Apps retain their usual save and cancel prompts.

## Install

Requires **macOS 13 or later**. The universal download supports Apple Silicon and Intel Macs.

1. Download `QuitOnClose-macOS-universal.zip` from [Releases](https://github.com/slibberysnek/QuitOnClose/releases/latest) and unzip it.
2. Double-click **QuitOnClose.app**. It installs itself into your own `~/Applications` folder and enables automatic login startup. No administrator password is needed.
3. Approve **QuitOnClose** in macOS's Accessibility permission list (**Device Control and Data Access** on newer macOS versions). The one-time setup opens the relevant settings. If macOS requests login-item approval, allow that too.

Setup disappears when ready. After that, the process runs silently, including at login. Reopening it does not display anything. macOS may show its own login-item notification during installation.

The free download is **ad-hoc signed, not Apple-notarized**. macOS may initially block it; use **System Settings → Privacy & Security → Open Anyway** if you choose to run it. These macOS approvals cannot be bypassed by the installer.

## Behavior

Click red window close buttons normally. QuitOnClose observes the click, lets the application close its window, and checks that no windows remain before requesting Quit. Other windows stay open. Canceling a close gesture or an unsaved-document prompt leaves the application running.

Finder and system-interface applications are excluded. Keyboard shortcuts such as Command-W keep their existing behavior.

If access is unavailable, QuitOnClose waits quietly and leaves applications alone. It never opens recurring permission dialogs or setup windows at login.

## Stop or uninstall

1. Remove **QuitOnClose** from **System Settings → General → Login Items → Open at Login**.
2. In **Activity Monitor**, select **QuitOnClose**, click Stop, and choose **Quit**.
3. Move `~/Applications/QuitOnClose.app` to Trash. You can also remove its permission entry in System Settings.

There are no separate launch agents, daemons, background updaters, or third-party packages to remove.

## Permissions and privacy

Accessibility permission is required to identify close buttons and inspect application windows. QuitOnClose does not make network requests, collect analytics, inspect message contents, or record keystrokes. Its event tap listens only for left-button down, drag, and up events; it does not consume or replace mouse events.

The process sends a normal quit request, never a force-quit. It checks both Accessibility and Window Server state twice and waits briefly for close animations. Failed or uncertain checks leave the application running.

### Updating or restoring access

Download and open the newer version; it replaces the installed copy and opens setup only if approval is needed. Ad-hoc signed updates can invalidate macOS permission even when its switch remains on. If close-to-quit stops working:

1. Quit QuitOnClose in Activity Monitor.
2. Remove its old permission entry with the **minus** button.
3. Add `~/Applications/QuitOnClose.app` with the **plus** button and enable it.
4. Open the installed app again.

For an explicit setup or diagnostic run, optional commands are available:

```sh
~/Applications/QuitOnClose.app/Contents/MacOS/QuitOnClose --setup
~/Applications/QuitOnClose.app/Contents/MacOS/QuitOnClose --check
~/Applications/QuitOnClose.app/Contents/MacOS/QuitOnClose --login-status
```

Quit an existing instance before using `--setup`. Normal use requires no Terminal commands.

## Build from source

Install Apple's free Command Line Tools (`xcode-select --install`) and Python 3. Full Xcode is not required.

```sh
git clone https://github.com/slibberysnek/QuitOnClose.git
cd QuitOnClose
python3 scripts/test.py
python3 scripts/build.py
open build/QuitOnClose.app
```

Opening the built app installs it just like the download. The default build is universal; `--arch arm64` and `--arch x86_64` build a single architecture.

Outputs go in `build/`: the app, a release ZIP, and `SHA256SUMS`. Builds are signed ad hoc by default. Maintainers can pass `--sign "Developer ID Application: …"` to use their own signing identity; notarization is a separate distribution step.

## Limitations

- Custom close controls that do not expose a standard macOS Accessibility close button may not be recognized.
- Some applications retain auxiliary windows or use unusual window behavior. QuitOnClose may leave those apps running.
- Distinguishing closed backing objects from real windows on another desktop uses the **private, read-only** `SLSWindowIsOrderedIn` macOS API. It is dynamically resolved. If unavailable or unsuccessful, automatic quit is skipped. Future macOS updates may affect compatibility.
- Automated tests use simulated events and snapshots and do not click or quit your applications. Development checks also exercised real disposable windows on Apple Silicon; Intel builds are cross-compiled and have not been runtime-tested here.

## License

[MIT](LICENSE).
