import Foundation

struct DiscoveredTV: Identifiable, Hashable {
    var id: String { host }
    let host: String
    let name: String
    let model: String?
    let mac: String?
    let isWired: Bool

    var savedTV: SavedTV {
        SavedTV(host: host, name: name, model: model, mac: mac, isWired: isWired)
    }
}

/// Finds Samsung TVs by probing the `/api/v2/` info endpoint on every host of the local /24.
enum TVDiscovery {
    private struct InfoResponse: Decodable {
        struct Device: Decodable {
            let name: String?
            let modelName: String?
            let wifiMac: String?
            let type: String?
            let networkType: String?
        }
        let name: String?
        let device: Device?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func fetchInfo(host: String) async throws -> DiscoveredTV {
        let url = URL(string: "http://\(host):8001/api/v2/")!
        let (data, _) = try await session.data(from: url)
        let info = try JSONDecoder().decode(InfoResponse.self, from: data)
        if let type = info.device?.type, !type.localizedCaseInsensitiveContains("samsung") {
            throw URLError(.badServerResponse)
        }
        let name = (info.device?.name ?? info.name ?? "Samsung TV")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return DiscoveredTV(
            host: host,
            name: name,
            model: info.device?.modelName,
            mac: info.device?.wifiMac,
            isWired: info.device?.networkType?.lowercased() == "wired"
        )
    }

    static func scan() async -> [DiscoveredTV] {
        guard let ip = LocalNetwork.currentIPv4() else { return [] }
        let prefix = ip.split(separator: ".").prefix(3).joined(separator: ".")
        return await withTaskGroup(of: DiscoveredTV?.self) { group in
            for last in 1...254 {
                let host = "\(prefix).\(last)"
                guard host != ip else { continue }
                group.addTask { try? await fetchInfo(host: host) }
            }
            var found: [DiscoveredTV] = []
            for await tv in group {
                if let tv { found.append(tv) }
            }
            return found.sorted { $0.name < $1.name }
        }
    }
}
