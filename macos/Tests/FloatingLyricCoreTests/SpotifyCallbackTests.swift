import XCTest
@testable import FloatingLyricCore

final class SpotifyCallbackTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    func test_theSchemeAndURIAgree() {
        XCTAssertTrue(SpotifyCallback.uri.hasPrefix(SpotifyCallback.scheme + "://"),
                      "ASWebAuthenticationSession matches the callback by scheme")
    }

    func test_readsTheCodeWhenTheStateMatches() {
        let result = SpotifyCallback.code(
            from: url("floatinglyric://callback?code=ABC123&state=ST"), expectedState: "ST")
        XCTAssertEqual(try? result.get(), "ABC123")
    }

    func test_rejectsAStateFromSomewhereElse() {
        let result = SpotifyCallback.code(
            from: url("floatinglyric://callback?code=ABC123&state=OTHER"), expectedState: "ST")
        XCTAssertEqual(result, .failure(.authStateMismatch))
    }

    func test_rejectsAResponseCarryingNoStateAtAll() {
        let result = SpotifyCallback.code(
            from: url("floatinglyric://callback?code=ABC123"), expectedState: "ST")
        XCTAssertEqual(result, .failure(.authStateMismatch))
    }

    func test_userRefusalIsReportedAsCancelled() {
        let result = SpotifyCallback.code(
            from: url("floatinglyric://callback?error=access_denied&state=ST"),
            expectedState: "ST")
        XCTAssertEqual(result, .failure(.authCancelled))
    }

    /// An error takes priority: Spotify sends no code with it, and reading the
    /// state first would report the wrong reason.
    func test_anErrorWinsOverAMismatchedState() {
        let result = SpotifyCallback.code(
            from: url("floatinglyric://callback?error=access_denied&state=OTHER"),
            expectedState: "ST")
        XCTAssertEqual(result, .failure(.authCancelled))
    }

    func test_aCallbackWithNothingUsefulIsCancelled() {
        XCTAssertEqual(SpotifyCallback.code(from: url("floatinglyric://callback"),
                                            expectedState: "ST"),
                       .failure(.authStateMismatch))
        XCTAssertEqual(SpotifyCallback.code(from: url("floatinglyric://callback?state=ST"),
                                            expectedState: "ST"),
                       .failure(.authCancelled))
    }

    func test_anEmptyCodeIsNotACode() {
        XCTAssertEqual(SpotifyCallback.code(from: url("floatinglyric://callback?code=&state=ST"),
                                            expectedState: "ST"),
                       .failure(.authCancelled))
    }

    func test_percentEncodedValuesAreDecoded() {
        let result = SpotifyCallback.code(
            from: url("floatinglyric://callback?code=A%2FB%2BC&state=ST"), expectedState: "ST")
        XCTAssertEqual(try? result.get(), "A/B+C")
    }
}
