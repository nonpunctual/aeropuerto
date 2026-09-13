import CoreWLAN
import Foundation

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

func interfaceJSON(_ interface: CWInterface, includeWdutil: Bool) -> [String: Any] {
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

    if includeWdutil {
        for (k, v) in wdutilFields() { json[k] = v }
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

var mode: String? = nil
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
        if mode != nil { argError = true }
        mode = arg
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

guard let mode = mode else {
    print(usage)
    exit(0)
}

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
    let result = interfaces.map { interfaceJSON($0, includeWdutil: isRoot) }
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
