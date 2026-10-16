import Foundation

/// Key codes understood by the Samsung Tizen remote-control WebSocket API.
enum TVKey: String {
    case power = "KEY_POWER"
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case enter = "KEY_ENTER"
    case back = "KEY_RETURN"
    case home = "KEY_HOME"
    case menu = "KEY_MENU"
    case source = "KEY_SOURCE"
    case info = "KEY_INFO"
    case guide = "KEY_GUIDE"
    case exit = "KEY_EXIT"
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
    case channelUp = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case play = "KEY_PLAY"
    case pause = "KEY_PAUSE"
    case rewind = "KEY_REWIND"
    case fastForward = "KEY_FF"
    case num0 = "KEY_0", num1 = "KEY_1", num2 = "KEY_2", num3 = "KEY_3", num4 = "KEY_4"
    case num5 = "KEY_5", num6 = "KEY_6", num7 = "KEY_7", num8 = "KEY_8", num9 = "KEY_9"

    static func digit(_ n: Int) -> TVKey {
        TVKey(rawValue: "KEY_\(n)") ?? .num0
    }
}

/// Apps that can be launched directly on Tizen TVs.
struct TVApp: Identifiable, Hashable {
    let name: String
    /// Letter and color for the app's pixel tile.
    let initial: String
    let tileColor: UInt32
    /// Samsung app IDs to try in order; they differ between TV generations and regions.
    let ids: [String]

    var id: String { name }

    static let shortcuts: [TVApp] = [
        TVApp(name: "Netflix", initial: "N", tileColor: 0x8E2C24, ids: ["3201907018807", "11101200001"]),
        TVApp(name: "YouTube", initial: "Y", tileColor: 0x9C3B27, ids: ["111299001912"]),
        TVApp(name: "Prime", initial: "P", tileColor: 0x2D5B82, ids: ["3201910019365", "3201512006785"]),
        TVApp(name: "Disney+", initial: "D", tileColor: 0x2C3B6E, ids: ["3201901017640"]),
    ]
}

/// A TV the app has paired with, persisted between launches.
struct SavedTV: Codable, Equatable {
    var host: String
    var name: String
    var model: String?
    /// Wi-Fi MAC reported by the TV itself; refreshed on every connection.
    var mac: String?
    /// MAC typed in by the user, e.g. the Ethernet MAC of a wired TV. Takes precedence.
    var manualMAC: String?
    var isWired: Bool?
    var token: String?
    /// The TV's device in SmartThings, used to switch it on through the cloud.
    var smartThingsDeviceID: String?
    var smartThingsDeviceName: String?

    /// The MAC address to send Wake-on-LAN packets to.
    var wakeMAC: String? {
        if let manualMAC, !manualMAC.isEmpty { return manualMAC }
        // A wired TV only reports its Wi-Fi MAC, which can't wake it.
        return isWired == true ? nil : mac
    }

    static func isValidMAC(_ text: String) -> Bool {
        text.split(whereSeparator: { $0 == ":" || $0 == "-" })
            .filter { $0.count == 2 && UInt8($0, radix: 16) != nil }
            .count == 6
    }
}
