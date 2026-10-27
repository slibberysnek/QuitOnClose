# QuitOnClose

A small, free macOS menu-bar app that quits applications after you close their last window using the red close button.

**Two windows open? Closing one leaves the other alone. Close the last window, and QuitOnClose requests a normal quit.** Apps retain their usual save and cancel prompts.

## Download and install

Requires **macOS 13 or later**. The universal download supports Apple Silicon and Intel Macs.

1. Download `QuitOnClose-macOS-universal.zip` from [Releases](https://github.com/slibberysnek/QuitOnClose/releases/latest).
2. Unzip it and move **QuitOnClose.app** to Applications.
3. Open the app. The first launch may be blocked because the community build is **ad-hoc signed, not Apple-notarized**. If you choose to run it, follow macOS's **Privacy & Security → Open Anyway** flow.
4. Click **Open Settings** and enable **QuitOnClose** in **Device Control and Data Access** (called **Accessibility** on older macOS versions).

Once permission is available, QuitOnClose runs in the background. No Terminal window, paid software, or third-party packages are needed.

## Use

Click red window close buttons normally. QuitOnClose observes the click, lets the application close its window, and checks that no windows remain before requesting Quit.

Use the **circled-X menu-bar icon** to:

- **Pause / Resume** automatic quitting.
- Enable or disable **Start at Login**. This is optional and off by default.
- Open permission settings.
- **Quit QuitOnClose**.

Finder and system-interface applications are excluded. Keyboard shortcuts such as Command-W keep their existing behavior.

To uninstall, disable **Start at Login**, quit QuitOnClose, and move the app to Trash. Its permission entry can also be removed in System Settings.

## Permissions and privacy

Accessibility permission is required to identify close buttons and inspect application windows. QuitOnClose does not make network requests, collect analytics, inspect message contents, or record keystrokes. Its event tap listens only for left-button down, drag, and up events; it does not consume or replace mouse events.

The app sends a normal quit request, never a force-quit. It checks both Accessibility and Window Server state twice and waits briefly for close animations. Failed or uncertain checks leave the application running.

### After an update

Locally/ad-hoc signed builds can need fresh permission after rebuilding or updating. If the switch is on but the app still waits for approval:

1. Quit QuitOnClose.
2. Remove its old entry from the permission list using the **minus** button.
3. Add the current **QuitOnClose.app** using the **plus** button and enable it.
4. Reopen the app.

Keep the app in a stable location and approve the app itself, rather than Terminal.

## Build from source

Install Apple's free Command Line Tools (`xcode-select --install`) and Python 3. Full Xcode is not required.

```sh
git clone https://github.com/slibberysnek/QuitOnClose.git
cd QuitOnClose
python3 scripts/test.py
python3 scripts/build.py
open build/QuitOnClose.app
```

The default build is universal. To build a single architecture:

```sh
python3 scripts/build.py --arch arm64
python3 scripts/build.py --arch x86_64
```

Outputs go in `build/`: the app, a release ZIP, and `SHA256SUMS`. Builds are signed ad hoc by default. Maintainers can pass `--sign "Developer ID Application: …"` to use their own signing identity; notarization is a separate distribution step.

## Limitations

- Custom close controls that do not expose a standard macOS Accessibility close button may not be recognized.
- Some applications retain auxiliary windows or use unusual window behavior. QuitOnClose may leave those apps running.
- Distinguishing closed backing objects from real windows on other desktops uses the **private, read-only** `SLSWindowIsOrderedIn` macOS API. It is dynamically resolved. If it is unavailable or fails, automatic quit is skipped. Future macOS updates may affect compatibility.
- Automated tests use simulated events and snapshots and do not click or quit your applications. Development checks also exercised real disposable windows on Apple Silicon; Intel builds are cross-compiled and have not been runtime-tested here. App-specific behavior still benefits from testing on your own Mac.

## License

[MIT](LICENSE).
