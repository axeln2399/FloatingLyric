import XCTest
import CryptoKit
@testable import FloatingLyricCore

final class PKCETests: XCTestCase {
    func test_verifierLengthIsWithinSpecRange() {
        let pair = PKCE.generate()
        XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
        XCTAssertLessThanOrEqual(pair.verifier.count, 128)
    }

    func test_verifierUsesOnlyUnreservedCharacters() {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pair = PKCE.generate()
        XCTAssertTrue(pair.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func test_challengeIsBase64URLEncodedSHA256OfVerifier() {
        let pair = PKCE.generate()
        let digest = SHA256.hash(data: Data(pair.verifier.utf8))
        let expected = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(pair.challenge, expected)
    }

    func test_challengeHasNoPaddingOrURLUnsafeCharacters() {
        let challenge = PKCE.generate().challenge
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func test_eachGenerationIsUnique() {
        XCTAssertNotEqual(PKCE.generate().verifier, PKCE.generate().verifier)
        XCTAssertNotEqual(PKCE.randomState(), PKCE.randomState())
    }

    func test_inMemoryTokenStoreRoundTrips() {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.readRefreshToken())
        store.writeRefreshToken("abc")
        XCTAssertEqual(store.readRefreshToken(), "abc")
        store.deleteRefreshToken()
        XCTAssertNil(store.readRefreshToken())
    }
}
