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
    let samsungIDs: [String]
    /// The app's ID on LG webOS.
    let lgID: String

    var id: String { name }

    static let shortcuts: [TVApp] = [
        TVApp(name: "Netflix", initial: "N", tileColor: 0x8E2C24,
              samsungIDs: ["3201907018807", "11101200001"], lgID: "netflix"),
        TVApp(name: "YouTube", initial: "Y", tileColor: 0x9C3B27,
              samsungIDs: ["111299001912"], lgID: "youtube.leanback.v4"),
        TVApp(name: "Prime", initial: "P", tileColor: 0x2D5B82,
              samsungIDs: ["3201910019365", "3201512006785"], lgID: "amazon"),
        TVApp(name: "Disney+", initial: "D", tileColor: 0x2C3B6E,
              samsungIDs: ["3201901017640"], lgID: "com.disney.disneyplus-prod"),
    ]
}

/// The TV brands Controlinho can control.
enum TVBrand: String, Codable {
    case samsung
    case lg

    var displayName: String {
        switch self {
        case .samsung: "Samsung"
        case .lg: "LG"
        }
    }

    /// The setting that keeps the TV's network alive in standby, so it can be woken.
    var wakeSettingHint: String {
        switch self {
        case .samsung:
            "Power On with Mobile on the TV (Settings › General › Network › Expert Settings, or Settings › Connection › Network › Expert Settings on newer models)"
        case .lg:
            "Turn on via Wi-Fi on the TV (under Mobile TV On or TV On With Mobile, in the TV's General or Connection settings, depending on the model)"
        }
    }
}

/// A TV the app has paired with, persisted between launches.
struct SavedTV: Codable, Equatable {
    /// Missing on TVs saved before LG support, which were all Samsung.
    var brand: TVBrand?
    var host: String
    var name: String
    var model: String?
    /// Wi-Fi MAC reported by the TV itself; refreshed on every connection.
    var mac: String?
    /// MAC typed in by the user, e.g. the Ethernet MAC of a wired TV. Takes precedence.
    var manualMAC: String?
    var isWired: Bool?
    /// True when `mac` belongs to the interface the TV is connected with. Samsung TVs only
    /// report their Wi-Fi MAC, which can't wake a TV on a cable.
    var macMatchesConnection: Bool?
    /// Samsung's pairing token, or LG's client key.
    var token: String?
    /// True for older TVs that only accept the plain, unencrypted socket port.
    var usesLegacyPort: Bool?

    var kind: TVBrand { brand ?? .samsung }

    /// The MAC address to send Wake-on-LAN packets to.
    var wakeMAC: String? {
        if let manualMAC, !manualMAC.isEmpty { return manualMAC }
        // A Samsung TV on a cable only reports its Wi-Fi MAC, which can't wake it.
        return isWired == true && macMatchesConnection != true ? nil : mac
    }

    static func isValidMAC(_ text: String) -> Bool {
        text.split(whereSeparator: { $0 == ":" || $0 == "-" })
            .filter { $0.count == 2 && UInt8($0, radix: 16) != nil }
            .count == 6
    }
}
