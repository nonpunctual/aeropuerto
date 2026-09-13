import Cocoa
import CoreLocation
import CoreWLAN
import Foundation

final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    var latestStatus: CLAuthorizationStatus = .notDetermined

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        latestStatus = manager.authorizationStatus
    }
}

// CWInterface/CWNetwork properties silently redact when unauthorized, they don't
// themselves ask the user for authorization. Only CLLocationManager's authorization
// request actually triggers locationd's #AuthPrompt flow (the modal). This must run
// before any CoreWLAN access, or the prompt never fires (confirmed 2026-09-13: a
// no-args launch reached CWWiFiClient/airportd but never touched locationd at all).
func requestLocationAuthorizationIfNeeded() {
    let manager = CLLocationManager()
    let authorizer = LocationAuthorizer()
    manager.delegate = authorizer
    authorizer.latestStatus = manager.authorizationStatus

    guard authorizer.latestStatus == .notDetermined else {
        return
    }

    manager.requestWhenInUseAuthorization()

    let deadline = Date().addingTimeInterval(60)
    while authorizer.latestStatus == .notDetermined && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }
}

let usage = """
Usage: aeropuerto -s [-interface <interface>]
       aeropuerto -I [-interface <interface>]

  -s   Scan for nearby Wi-Fi networks, print a JSON array.
  -I   Print CoreWLAN attributes as a JSON array: one object per Wi-Fi
       interface present (on or off) by default, or just the named one
       with -interface.
  -interface <interface>
       Target a specific Wi-Fi interface (e.g. en0) with -s or -I,
       instead of -s's single default interface or -I's default of
       every interface present.
"""

func phyModeString(_ mode: CWPHYMode) -> String {
    switch mode {
    case .mode11a: return "802.11a"
    case .mode11b: return "802.11b"
    case .mode11g: return "802.11g"
    case .mode11n: return "802.11n"
    case .mode11ac: return "802.11ac"
    case .mode11ax: return "802.11ax"
    case .mode11be: return "802.11be"
    case .modeNone: return "none"
    @unknown default: return "unknown"
    }
}

func interfaceModeString(_ mode: CWInterfaceMode) -> String {
    switch mode {
    case .station: return "station"
    case .IBSS: return "IBSS"
    case .hostAP: return "hostAP"
    case .none: return "none"
    @unknown default: return "unknown"
    }
}

func securityString(_ security: CWSecurity) -> String {
    switch security {
    case .none: return "None"
    case .WEP: return "WEP"
    case .wpaPersonal: return "WPA Personal"
    case .wpaPersonalMixed: return "WPA Personal Mixed"
    case .wpa2Personal: return "WPA2 Personal"
    case .personal: return "Personal"
    case .dynamicWEP: return "Dynamic WEP"
    case .wpaEnterprise: return "WPA Enterprise"
    case .wpaEnterpriseMixed: return "WPA Enterprise Mixed"
    case .wpa2Enterprise: return "WPA2 Enterprise"
    case .enterprise: return "Enterprise"
    case .wpa3Personal: return "WPA3 Personal"
    case .wpa3Enterprise: return "WPA3 Enterprise"
    case .wpa3Transition: return "WPA2/WPA3 Personal"
    case .OWE: return "Enhanced Open"
    case .oweTransition: return "Open/Enhanced Open"
    case .unknown: return "Unknown"
    @unknown default: return "Unknown"
    }
}

func channelBandString(_ band: CWChannelBand) -> String {
    switch band {
    case .band2GHz: return "2.4GHz"
    case .band5GHz: return "5GHz"
    case .band6GHz: return "6GHz"
    case .bandUnknown: return "unknown"
    @unknown default: return "unknown"
    }
}

func channelWidthString(_ width: CWChannelWidth) -> String {
    switch width {
    case .width20MHz: return "20MHz"
    case .width40MHz: return "40MHz"
    case .width80MHz: return "80MHz"
    case .width160MHz: return "160MHz"
    case .widthUnknown: return "unknown"
    @unknown default: return "unknown"
    }
}

func jsonOptional(_ value: String?) -> Any {
    value ?? NSNull()
}

func channelJSON(_ channel: CWChannel?) -> [String: Any] {
    guard let channel = channel else {
        return [
            "channelNumber": NSNull(),
            "channelBand": NSNull(),
            "channelWidth": NSNull()
        ]
    }
    return [
        "channelNumber": channel.channelNumber,
        "channelBand": channelBandString(channel.channelBand),
        "channelWidth": channelWidthString(channel.channelWidth)
    ]
}

func wdutilFields() -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/wdutil")
    process.arguments = ["info"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    var fields: [String: Any] = [:]
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return fields }

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]

            switch key {
            case "MCS Index":
                if let n = Int(value) { fields["mcsIndex"] = n }
            case "Guard Interval":
                if let n = Int(value) { fields["guardInterval"] = n }
            case "NSS":
                if let n = Int(value) { fields["spatialStreams"] = n }
            case "CCA":
                if let n = Int(value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                    fields["channelClearAssessment"] = n
                }
            case "Scan Cache Count":
                if let n = Int(value) { fields["scanCacheCount"] = n }
            default:
                break
            }
        }
    } catch {
        return fields
    }
    return fields
}

func interfaceJSON(_ interface: CWInterface, wdutil: [String: Any]?) -> [String: Any] {
    var json: [String: Any] = [:]

    json["interfaceName"] = jsonOptional(interface.interfaceName)
    json["powerOn"] = interface.powerOn()
    json["serviceActive"] = interface.serviceActive()
    json["ssid"] = jsonOptional(interface.ssid())
    if let ssidData = interface.ssidData() {
        json["ssidData"] = ssidData.map { String(format: "%02x", $0) }.joined()
    } else {
        json["ssidData"] = NSNull()
    }
    json["bssid"] = jsonOptional(interface.bssid())
    json["rssi"] = interface.rssiValue()
    json["noise"] = interface.noiseMeasurement()
    for (k, v) in channelJSON(interface.wlanChannel()) { json[k] = v }
    json["security"] = securityString(interface.security())
    json["hardwareAddress"] = jsonOptional(interface.hardwareAddress())
    json["activePHYMode"] = phyModeString(interface.activePHYMode())
    json["transmitRate"] = interface.transmitRate()
    json["countryCode"] = jsonOptional(interface.countryCode())
    json["interfaceMode"] = interfaceModeString(interface.interfaceMode())

    if let supported = interface.supportedWLANChannels() {
        json["supportedWLANChannels"] = supported.compactMap { channelJSON($0) }
    } else {
        json["supportedWLANChannels"] = []
    }

    if let configuration = interface.configuration() {
        var profiles: [[String: Any]] = []
        if let networkProfiles = configuration.networkProfiles.array as? [CWNetworkProfile] {
            for profile in networkProfiles {
                profiles.append([
                    "ssid": profile.ssid as Any,
                    "security": securityString(profile.security)
                ])
            }
        }
        json["configuration"] = ["networkProfiles": profiles]
    } else {
        json["configuration"] = NSNull()
    }

    if let wdutil = wdutil {
        for (k, v) in wdutil { json[k] = v }
    }

    return json
}

func networkJSON(_ network: CWNetwork) -> [String: Any] {
    var json: [String: Any] = [:]
    json["ssid"] = jsonOptional(network.ssid)
    if let ssidData = network.ssidData {
        json["ssidData"] = ssidData.map { String(format: "%02x", $0) }.joined()
    } else {
        json["ssidData"] = NSNull()
    }
    json["bssid"] = jsonOptional(network.bssid)
    json["rssi"] = network.rssiValue
    json["noise"] = network.noiseMeasurement
    for (k, v) in channelJSON(network.wlanChannel) { json[k] = v }
    json["countryCode"] = jsonOptional(network.countryCode)
    return json
}

func printJSON(_ object: Any) {
    guard JSONSerialization.isValidJSONObject(object) else {
        FileHandle.standardError.write("aeropuerto: internal error building JSON\n".data(using: .utf8)!)
        exit(1)
    }
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "[]")
    } catch {
        FileHandle.standardError.write("aeropuerto: failed to serialize JSON: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let arguments = CommandLine.arguments
let isRoot = geteuid() == 0

// wdutil is the only thing that actually needs root. CoreWLAN/Location Services
// authorization is tied to the console user who was granted it, not to root,
// confirmed 2026-09-13: `sudo aeropuerto -I` returned real wdutil fields but null
// ssid/bssid/countryCode, even with an active grant for the console user. So:
// capture wdutil now, while still root, then drop back to the original invoking
// user (via SUDO_UID, set by sudo) before touching anything CoreWLAN/CoreLocation.
let wdutilData: [String: Any]? = isRoot ? wdutilFields() : nil

if isRoot, let sudoUidString = ProcessInfo.processInfo.environment["SUDO_UID"],
   let sudoUid = uid_t(sudoUidString) {
    if seteuid(sudoUid) != 0 {
        FileHandle.standardError.write("aeropuerto: failed to drop root privileges (seteuid), Location Services fields will likely be redacted\n".data(using: .utf8)!)
    }
}

var parsedMode: String? = nil
var interfaceName: String? = nil
var index = 1
var argError = false

while index < arguments.count {
    let arg = arguments[index]
    switch arg {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "-s", "-I":
        if parsedMode != nil { argError = true }
        parsedMode = arg
    case "-interface":
        index += 1
        if index < arguments.count {
            interfaceName = arguments[index]
        } else {
            argError = true
        }
    default:
        argError = true
    }
    index += 1
}

if argError {
    FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
    exit(1)
}

// A GUI-style launch (Finder double-click, `open -a`, postinstall's auto-launch)
// passes no arguments and has no controlling terminal. Per README.md: "The first
// launch checks the current Wi-Fi interface." That CWWiFiClient call is what
// actually triggers the Location Services authorization prompt, so a no-args
// launch must reach it, not just print usage and exit, or the prompt never fires.
// An interactive terminal invocation with no args still gets the usage text.
let mode: String
let isGUILaunch: Bool
if let explicitMode = parsedMode {
    mode = explicitMode
    isGUILaunch = false
} else if isatty(STDOUT_FILENO) != 0 {
    print(usage)
    exit(0)
} else {
    mode = "-I"
    isGUILaunch = true
}

func performCoreWLANWork() {
    let client = CWWiFiClient.shared()

    switch mode {
    case "-I":
        var interfaces: [CWInterface] = []
        if let interfaceName = interfaceName {
            if let interface = client.interface(withName: interfaceName) {
                interfaces = [interface]
            }
        } else {
            interfaces = client.interfaces() ?? []
        }
        let result = interfaces.map { interfaceJSON($0, wdutil: wdutilData) }
        printJSON(result)

    case "-s":
        let targetInterface: CWInterface?
        if let interfaceName = interfaceName {
            targetInterface = client.interface(withName: interfaceName)
        } else {
            targetInterface = client.interface()
        }

        guard let interface = targetInterface else {
            FileHandle.standardError.write("aeropuerto: no Wi-Fi interface found\n".data(using: .utf8)!)
            exit(1)
        }

        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            let result = networks.map { networkJSON($0) }
            printJSON(result)
        } catch {
            FileHandle.standardError.write("aeropuerto: scan failed: \(error.localizedDescription)\n".data(using: .utf8)!)
            exit(1)
        }

    default:
        print(usage)
        exit(0)
    }
}

// This is a bare executable with no NSApplication/Cocoa event loop by default.
// A Finder double-click sends a standard "Open Application" Apple Event and
// waits for a reply; nothing answers it without a real run loop processing
// events, and Finder's own watchdog can then show "not responding", even
// though the process is alive and correctly waiting on the auth prompt underneath
// (confirmed 2026-09-13 on a fresh VM). NSApp.run() on the main thread answers
// Apple Events properly; NSApp.terminate(nil) ends the process once done.
//
// Everything here must stay on the main thread. requestLocationAuthorizationIfNeeded()'s
// polling loop calls RunLoop.main.run(), which only does anything when called from
// the main thread itself; calling it from a background thread (an earlier version of
// this fix used DispatchQueue.global().async) is a silent no-op that just busy-spins
// for the full timeout at 100% CPU, confirmed 2026-09-13 (measured ~60.19s against a
// 60s deadline). The CLLocationManager delegate callback below is what NSApp's own
// already-running main-thread loop delivers correctly, no manual polling needed here.
final class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.delegate = self
        if locationManager.authorizationStatus != .notDetermined {
            finish()
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined {
            finish()
        }
    }

    func finish() {
        performCoreWLANWork()
        NSApp.terminate(nil)
    }
}

// Only the no-args GUI-style launch needs NSApplication (to answer Finder's
// "Open Application" Apple Event and avoid "not responding"). Explicit -s/-I
// CLI invocations never had that problem, and wrapping them in NSApplication
// too was confirmed 2026-09-13 to add real latency for no benefit, unacceptable
// for a CLI tool, so they keep the original direct, fast, main-thread path.
if isGUILaunch {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
} else {
    requestLocationAuthorizationIfNeeded()
    performCoreWLANWork()
    exit(0)
}
