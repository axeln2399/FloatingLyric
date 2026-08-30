import Foundation
import CryptoKit

public struct PKCEPair: Sendable {
    public let verifier: String
    public let challenge: String
}

public enum PKCE {
    private static let unreserved = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func generate() -> PKCEPair {
        let verifier = randomString(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCEPair(verifier: verifier, challenge: base64URL(Data(digest)))
    }

    public static func randomState() -> String {
        randomString(length: 32)
    }

    private static func randomString(length: Int) -> String {
        String((0..<length).map { _ in unreserved.randomElement()! })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
