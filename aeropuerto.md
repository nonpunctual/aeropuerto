# aeropuerto

## history

 Two independent sources agree on the same field list and order for the deprecated airport -I:
  
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

see: https://ss64.com/mac/airport.html

## requirements

### CLI tool

  - aeropuerto -s scans nearby Wi-Fi networks (SSID/BSSID/signal strength, JSON to stdout)
  - aeropuerto -I reports current Wi-Fi interface(s) association info (JSON to stdout)
  - -interface <name> targets one interface with either mode.
  - Will ship as a signed, notarized .app bundle
  - required — bare Mach-O binaries don't register with Location Services.
  - Installation via signed/notarized .pkg.
    - see: /Users/Shared/scripty-legacy/build.pkg.sh for package building
  - Hardware / software: macOS 12+, a Mac with Wi-Fi hardware.

### data

  - SSID and BSSID are redacted unless the calling process holds Location Services authorization
  - confirmed on this Mac via `system_profiler SPAirPortDataType` and `ipconfig getsummary en0`
  - both showed `<redacted>` for these fields without authorization
  - `ipconfig getsummary en0` also redacted a `NetworkID` field
  - `CWInterface.h` documents ssid/ssidData/bssid/countryCode as the gated set
  - actual observed behavior on this system only confirms ssid and bssid using known CLI tools
  - `sudo aeropuerto -I` additionally includes mcsIndex/guardInterval/spatialStreams/channelClearAssessment/scanCacheCount from `wdutil` (requires root). 
  - Unprivileged runs omit those five fields.

>"Redacted" = when the calling process lacks Location Services authorization, CoreWLAN's underlying property for that field returns a placeholder rather than the real value. Directly observed the display convention two system tools use for that placeholder, the literal string <redacted>, for ssid/bssid/networkID.

#### CoreWLAN

CoreWLAN read/report surface, from CWInterface.h and CWWiFiClient.h in the SDK:

A. Per-interface identity & state (no Location Services needed, per header docs)
- interfaceName — BSD name (en0)
- hardwareAddress — MAC
- powerOn — radio on/off
- serviceActive — network service up/down
- interfaceMode — station / IBSS / hostAP / none
- activePHYMode — 802.11 PHY (a/b/g/n/ac/ax...)
- transmitRate — Mbps
- transmitPower — mW
- rssiValue — dBm
- noiseMeasurement — dBm
- wlanChannel — current channel (number/band/width)
- supportedWLANChannels — full channel list for current country code
- security — current association's security type
- configuration — saved/preferred network config (not live association)

B. Gated behind Location Services
- ssid / ssidData
- bssid
- countryCode

C. Enumeration (backs interface discovery for -s and -I)
- CWWiFiClient.interfaces() → [CWInterface]
- CWWiFiClient.interfaceNames() → [String] (deprecated class variant also exists)

#### wdutil

>`aeropuerto` uses [CoreWLAN](https://developer.apple.com/documentation/corewlan); `mcsIndex`, `guardInterval`, `spatialStreams`, `channelClearAssessment`, and `scanCacheCount` come from `wdutil`, which requires root. A plain, unprivileged `aeropuerto -I` never attempts this and these five fields are simply omitted; run with `sudo` to include them.

### behavior

  - After install, the app auto-launches so the Location Services system prompt fires immediately, without the user having to find and run it themselves.
  - This must work reliably: the tool is deployed via MDM/Fleet to end-user Macs the admin doesn't have hands-on access to.
  - The end user is the only one who can grant Location Services consent (Apple requires a human in the loop).
  - Once granted, the app should not need to be opened again
  - It can be used purely as a CLI via /usr/local/bin/aeropuerto (symlinked to the bundle's binary by the installer).

>The prompt itself is rendered by `locationd` (not TCC; Location Services has its own daemon and authorization store, separate from `tccd`). `locationd` fills in the app name from `CFBundleName`/`CFBundleDisplayName` and the body text verbatim from `NSLocationUsageDescription`/`NSLocationWhenInUseUsageDescription` in the bundle's `Info.plist`. Those two keys are the only lever the project has over the prompt's wording.

#### Location Services / location modal for granting permission

- Authorization should be granted to the console user's app bundle via a Location Service modal / popup.
- Authorization can be granted by manually toggling the Location Services entry for `aeropuerto` on, but, this diminishes the utility of this tool.
- If `aeropuerto` is created on a device wihtout proper signing, Location Services will not remove references to it if they exist.
- If a user has granted Location Services permission to `aeropuerto` one time, the modal may not reappear during testing. 

>Verification gate: this has already failed under controlled conditions (ad-hoc and properly signed, this Mac, fresh VMs, a fresh physical Mac) after ruling out signing and `locationd` cache state as the cause. A build is not "done" until the modal is actually observed firing in the session doing the work, evidence (a screenshot, same standard as `Resources/aeropuerto.png`), not code that looks correct.

Claude thread 2026-09-12T19:16:00

❯ acknowledge the .png file in /Resources

Acknowledged: /Users/Shared/aeropuerto/Resources/aeropuerto.png, the macOS Location Services authorization prompt screenshot ("'aeropuerto' would like to use your current location..."), referenced from README.md.

✻ Brewed for 4s

❯ Assuming I am not a liar (which you accused me of, ie, of potentially fabricating this image...) acknowledge that the only LEGITIMATE way I could have this screen shot is if this workflow created a modal for approving Location Services permission.

Acknowledged, and fair. That screenshot is only explainable if a signed aeropuerto.app bundle with that exact NSLocationUsageDescription string was built, launched, and successfully triggered locationd's authorization request at least once. There's no other legitimate way to produce that exact system-rendered modal with that exact app name and that exact body text.
