# aeropuerto

## requirements

### CLI tool

- `aeropuerto -s` scans nearby Wi-Fi networks (SSID/BSSID/signal strength, JSON to stdout)
- `aeropuerto -I` reports current Wi-Fi interface(s) association info (JSON to stdout)
- `-interface <name>` targets one interface with either mode
- `-v`/`--version` prints `CFBundleShortVersionString` from the `Info.plist` embedded in the binary's `__info_plist` section, exit 0 (confirmed via testing: app bundle, symlink, bare `.build/debug` binary)
- `-interface <name>` naming a nonexistent/non-Wi-Fi interface, the two modes behave differently: for `-I`, empty JSON array, exit 0, not an error (confirmed via testing). For `-s`, `"no Wi-Fi interface found"` to stderr, exit 1 (confirmed by reading `main.swift`, not by testing).
- invalid/conflicting flags (unrecognized flag, both -s and -I, -interface with no value): usage to stderr, exit 1 (confirmed via testing)
- Will ship as a signed, notarized .app bundle
  - required: bare Mach-O binaries don't register with Location Services
- Installation via signed/notarized .pkg
  - see: /Users/Shared/scripty-legacy/build.pkg.sh for package building
- Hardware / software: macOS 12+, a Mac with Wi-Fi hardware

### Data

- SSID and BSSID are redacted unless the calling process holds Location Services authorization
- confirmed on this Mac via `system_profiler SPAirPortDataType` and `ipconfig getsummary en0`
- both showed `<redacted>` for these fields without authorization
- `ipconfig getsummary en0` also redacted a `NetworkID` field
- actual observed behavior on this system only confirms ssid and bssid using known CLI tools (see CoreWLAN's gated-field list below for the full documented set)
- `sudo aeropuerto -I` additionally includes mcsIndex/guardInterval/spatialStreams/channelClearAssessment/scanCacheCount from `wdutil` (requires root). 
- Unprivileged runs omit those five fields.
- `-s` hidden networks: CoreWLAN returns nil `ssid`/`ssidData` with a real `bssid`. aeropuerto emits `"ssid": "hiddenNetwork"` (`ssidData` stays `null`). Without authorization `bssid` is nil too, so redacted results stay `null`, not mislabeled hidden. BSSIDs matched WiFi Explorer Pro's "Hidden Network" rows (confirmed 2026-11-03).

"Redacted" = when the calling process lacks Location Services authorization, CoreWLAN's underlying property for that field returns a placeholder rather than the real value. Directly observed the display convention two system tools use for that placeholder, the literal string <redacted>, for ssid/bssid/networkID.

Code paths only, confirmed by reading `main.swift`, not tested against a real Wi-Fi-less machine. Which of these two CoreWLAN behaviors actually occurs on such a machine is unconfirmed.

- `-I`: if `CWWiFiClient.interfaces()` returns zero interfaces, prints `[]`, exit 0. If it instead returns an interface object with no working radio, prints one JSON object full of `null`/`0`/`"none"` values, exit 0.
- `-s`: if `CWWiFiClient.interface()`/`interface(withName:)` returns nil, prints `"no Wi-Fi interface found"` to stderr, exit 1, no JSON. If it returns a non-working interface object instead, `scanForNetworks` is attempted and will most likely fail with a CoreWLAN error, also stderr + exit 1, no JSON.

#### CoreWLAN

CoreWLAN read/report surface, from CWInterface.h and CWWiFiClient.h in the SDK:

A. Per-interface identity & state (no Location Services needed, per header docs)

- interfaceName: BSD name (en0)
- hardwareAddress: MAC
- powerOn: radio on/off
- serviceActive: network service up/down
- interfaceMode: station / IBSS / hostAP / none
- activePHYMode: 802.11 PHY (a/b/g/n/ac/ax...)
- transmitRate: Mbps
- transmitPower: mW
- rssiValue: dBm
- noiseMeasurement: dBm
- wlanChannel: current channel (number/band/width)
- supportedWLANChannels: full channel list for current country code
- security: current association's security type
- configuration: saved/preferred network config (not live association)

B. Gated behind Location Services

- ssid / ssidData
- bssid
- countryCode

C. Enumeration (backs interface discovery for -s and -I)

- CWWiFiClient.interfaces() -> [CWInterface]
- CWWiFiClient.interfaceNames() -> [String] (deprecated class variant also exists)

#### wdutil

>`aeropuerto` uses [CoreWLAN](https://developer.apple.com/documentation/corewlan); `mcsIndex`, `guardInterval`, `spatialStreams`, `channelClearAssessment`, and `scanCacheCount` come from `wdutil`, which requires root. A plain, unprivileged `aeropuerto -I` never attempts this and these five fields are simply omitted; run with `sudo` to include them.

### Launch behavior

- After install, the app should auto-launch to pop up the Location Services system prompt
- This must work reliably: the tool is deployed via MDM/Fleet to end-user Macs admins do not have access to
- Authorization can be granted by manually toggling the Location Services entry for `aeropuerto`
  - Manual toggle diminishes the utility of this tool
- An end user must grant Location Services consent, it can't be granted programmatically
- Once granted, the app should not need to be opened again
- The symlink @ /usr/local/bin/aeropuerto can be used purely as a CLI tool.

### Location Services

- The Location Services prompt is rendered by `locationd`.
  - Location Services has its own daemon and authorization store, separate from `tccd`.
  - `locationd` fills in the app name from `CFBundleName`/`CFBundleDisplayName` and the body text verbatim from `NSLocationUsageDescription`/`NSLocationWhenInUseUsageDescription` in the bundle's `Info.plist`.
- A Hardened-Runtime-signed binary that calls `requestWhenInUseAuthorization()` **must** also carry the `com.apple.security.personal-information.location` entitlement
  - Without it, `locationd` silently refuses to forward the request to `CoreLocationAgent` and the prompt never appears, no crash, no visible error.
  - This is a Hardened Runtime requirement specifically, not App Sandbox
  - This app is Developer ID distributed, not sandboxed.
- `build.sh` signs with Hardened Runtime (required for notarization).
  - `build.sh` MUST write this entitlement, and packaging of the app bundle must carry it forward (i.e., keep it & not overwrite it.)

### Testing

- Never test unsigned or ad-hoc-signed builds against privacy-gated frameworks (Location Services/CoreLocation, or any other TCC-style consent).
- Never delete an app bundle or build directory that still has a live, unresolved Location Services/TCC reference.
- Only exercise Location/Camera/Microphone/etc. permission flows against a properly signed build with a real Team ID and one stable identifier, registered via `lsregister` on every build
  - `build.sh` already does this correctly, don't add anything on top of it to force re-prompting.
- A properly signed app with a real Team ID and one stable, consistently `lsregister`ed identifier is expected to get pruned by macOS from locationd's `clients.plist` once it's actually gone, but this is not immediate (see the 2026-09-13 `locationtest` entry below).
  - Unsigned/ad-hoc-signed test builds and haphazard deletes are worse: their references go orphaned indefinitely instead of eventually resolving.
  - Disabling SIP to hand-edit `clients.plist` is a one-off manual cleanup, not something to script or repeat routinely.

## Build log

### `airport -I` precedent

Field list/order for the deprecated `airport -I`, two independent sources agree:

       agrCtlRSSI: -40
       agrExtRSSI: 0
      agrCtlNoise: -88
      agrExtNoise: 0
            state: running
          op mode: station
       lastTxRate: 450
          maxRate: 450
  lastAssocStatus: 0
      802.11 auth: open
        link auth: wpa2-psk
            BSSID: 5c:96:9d:79:4c:25
             SSID: AIRPORT
              MCS: 23 
          channel: 36,1

see: `https://ss64.com/mac/airport.html`

### 2026-09-12

#### Redaction testing 

`system_profiler SPAirPortDataType` / `ipconfig getsummary en0`, unauthorized: both show literal `<redacted>` for SSID/BSSID; `ipconfig` also redacts `NetworkID`. Country code NOT redacted in these tests, despite `CWInterface.h` listing it as gated.

Known issues at the time: an improperly-signed build leaves an orphaned `clients.plist` reference on delete; once granted, the modal won't reappear on retest.

#### Entitlement root cause

Prompt had failed under controlled conditions (ad-hoc + properly signed, this Mac, VMs, a fresh physical Mac), signing and `locationd` cache state ruled out. Root cause: missing `com.apple.security.personal-information.location` entitlement. Confirmed via `locationd`'s own log: "Client has supported the hardened runtime but doesn't have the entitlement, not sending #AuthPrompt message to #CoreLocationAgent". App-side logging never showed this, only daemon-side (`process == "locationd"`) logs did.

Reproduced with throwaway `com.nonpunctual.locationtest`, fixed via `entitlements.plist` + `codesign --entitlements`. Confirmed: prompt fires, "Allow" persists (toggle turns on in Settings; first attempt's toggle didn't visibly flip, likely a UI-refresh timing quirk, a second identical attempt worked cleanly).

### 2026-09-13

#### `locationtest` clients.plist cleanup pending

Deleted from disk, but its `clients.plist` entry (`Authorized => true`, `Registered => true`) persisted (confirmed via `sudo plutil -p /private/var/db/locationd/clients.plist`), pruning isn't immediate. Needs manual SIP-disabled removal, same as the earlier 5 orphaned entries, which traced to past ad-hoc test builds across two projects (`aeropuerto`, and a separate `TSP`-scoped `WifiScanTest`/`wifi-scanner` prototype) using inconsistent one-off identifiers. Resolved via a later SIP-disabled cleanup pass (see the `PlistBuddy` command at the end of this file).

#### aeropuerto CLI built and tested

`main.swift` written, compiled clean. Tested against real CoreWLAN/wdutil:

| Test | Result |
|---|---|
| no args / `-h` | usage printed, exit 0 |
| `-I` | real data; `ssid`/`bssid`/`countryCode` omitted (not yet authorized); `configuration.networkProfiles` unredacted |
| `-s` | 37 real nearby networks, exit 0; same omissions as `-I` |
| `sudo -I` (wdutil) | real values: `mcsIndex:0, guardInterval:0, spatialStreams:0, channelClearAssessment:18, scanCacheCount:70` |
| `-I`/`-s -interface en0` | correctly scoped to that interface |
| `-I -interface bogus0` | empty array `[]`, exit 0 |
| invalid/conflicting flags | usage to stderr, exit 1 |

Fixed: redacted/absent scalar fields now consistently emit JSON `null` (some had been silently omitted, others explicit `null`, an accidental inconsistency). `com.nonpunctual.aeropuerto` itself not yet granted at this point.

#### v2.8, no-args launch never reaches CoreWLAN

Installed pkg: no prompt (auto-launch or double-click), no `clients.plist` entry at all. Root cause: no-args path printed usage and exited before touching `CWWiFiClient`, contradicting README's documented "first launch checks the current Wi-Fi interface." Fix: `isatty(STDOUT_FILENO)` distinguishes an interactive terminal (usage) from a GUI-style launch (behave like `-I`).

After that fix, `log show` showed the process reaching `airportd` but zero `locationd` activity. Second root cause: `main.swift` never called `CLLocationManager` at all, only `CWWiFiClient`, which checks/enforces existing authorization but never requests it. Fix: added a `CLLocationManager` + delegate, requests authorization before any CoreWLAN access.

Confirmed end-to-end for the real app: modal fires, "Allow" persists (`clients.plist`: `Authorized => true`), `aeropuerto -I` returns real `ssid`/`bssid`/`countryCode`.

#### v3.0 upgrade-install confirmed

unredacted data confirmed from `-I`/`-s` after a `.pkg` upgrade-install (not a fresh machine).

#### sudo losing the grant (previously solved, lost in an earlier rewrite)

`sudo aeropuerto -I`: real `wdutil` fields, but `null` `ssid`/`bssid`/`countryCode`. Root cause: authorization is tied to the console user, not root. Fix: capture `wdutil` fields while still root, then `seteuid(SUDO_UID)` before touching CoreWLAN/CoreLocation. Confirmed: both real data and `wdutil` fields returned together.

#### GUI-launch "not responding"

Added `NSApplication` so Finder's "Open Application" Apple Event gets answered (a bare executable with no Cocoa loop can leave Finder thinking it's "not responding" on a fresh install). First attempt dispatched the work to a background thread while `NSApp.run()` owned the main thread; `RunLoop.main.run()` called from a background thread is a silent no-op, so it busy-spun at 100% CPU for the full 60s timeout. Fixed by keeping everything on the main thread, driven by the `CLLocationManager` delegate callback. Verified: CLI still fast, GUI launch ~0.2s, no hang. Released as v3.2.

Installed v3.2 on a separate real (non-VM) Mac with `clients.plist` manually cleared: no modal, same "doesn't have the entitlement" error as the original bug. Root cause: `/Users/Shared/scripty-legacy/build.pkg.sh` (external shared script) re-signs every `.app` during packaging, unconditionally, without `--entitlements`, silently stripping it. v3.0-v3.2 all shipped broken this way; every "re-verify entitlement" checkpoint had only ever checked the pre-packaging `aeropuerto.app`, never the actual shipped `payload/.../*.app`.

Fix: `build.pkg.sh` takes an optional entitlements-plist argument (backward compatible for other projects using it). Verified by expanding the actual notarized `.pkg` and confirming the entitlement on the app it contains. Released as v3.3.

**Lesson:** verify the final packaged artifact, not the pre-packaging build output.

#### v3.3 first fully clean end-to-end `.pkg` install

Installed `aeropuerto-3.3.pkg` fresh. Location Services prompt fired immediately at the end of the installer (no manual launch needed). Clicked Allow. `clients.plist` shows a single `com.nonpunctual.aeropuerto` entry, `Authorized => true`, `Registered => true`, no orphans. `aeropuerto -I` returned unredacted `ssid`/`bssid`/`countryCode`. `sudo aeropuerto -I` also returned unredacted data alongside the root-only `wdutil` fields, confirming the `seteuid(SUDO_UID)` fix still holds.

First release where every documented requirement (auto-launch prompt, entitlement survives packaging, symlink, unprivileged and `sudo` data all unredacted) has been confirmed together from a plain `.pkg` install, not pieced together across separate partial tests.

```sh
sudo /usr/libexec/PlistBuddy \
-c 'delete :A20DFBAE-1CEA-47AD-87E2-D9C5512CA617\:icom.nonpunctual.aeropuerto\:' \
-c 'delete :A20DFBAE-1CEA-47AD-87E2-D9C5512CA617\:icom.nonpunctual.locationtest\:' \
/private/var/db/locationd/clients.plist

sudo launchctl kickstart -k system/com.apple.locationd
```