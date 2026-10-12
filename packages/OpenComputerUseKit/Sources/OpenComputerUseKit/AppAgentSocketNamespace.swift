import CryptoKit
import Foundation

public let openComputerUseAppAgentSocketNamespaceEnvironmentKey = "OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE"

// The fork's own socket name, so its CLI never talks to an upstream app agent
// that happens to be running for the same user.
let openComputerUseAppAgentSocketPrefix = "tinhthanh-open-computer-use-agent"

public func openComputerUseAppAgentSocketFileName(namespace: String?) -> String {
    guard let namespace = namespace?.trimmingCharacters(in: .whitespacesAndNewlines), !namespace.isEmpty else {
        return "\(openComputerUseAppAgentSocketPrefix).sock"
    }

    let digest = SHA256.hash(data: Data(namespace.utf8))
    let identifier = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    return "\(openComputerUseAppAgentSocketPrefix)-\(identifier).sock"
}
