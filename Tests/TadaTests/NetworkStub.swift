import Foundation
@testable import Tada

/// URLProtocol that intercepts requests made through `URLSession.shared` (which the
/// production API clients use) and returns a scripted response. Verified to intercept
/// the shared session on macOS.
final class StubURLProtocol: URLProtocol {
    /// Set by the active test. Returns (statusCode, body) for a given request.
    /// `nonisolated(unsafe)` because tests that use it run in a `.serialized` suite.
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { handler != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, body) = handler(request)
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Response builders

func jsonData(_ obj: Any) -> Data { try! JSONSerialization.data(withJSONObject: obj) }

/// Anthropic-style messages response carrying a single `tool_use` block with `input`.
func toolUseBody(_ input: [String: Any], name: String = "tool") -> Data {
    jsonData(["content": [["type": "tool_use", "id": "tool_1", "name": name, "input": input]]])
}

/// Anthropic-style messages response carrying a single `text` block.
func textBody(_ text: String) -> Data {
    jsonData(["content": [["type": "text", "text": text]]])
}

/// Anthropic-style error body.
func apiErrorBody(_ message: String) -> Data {
    jsonData(["type": "error", "error": ["type": "invalid_request_error", "message": message]])
}

/// Runs `body` with the stub installed for the lifetime of the call.
func withStub(
    _ handler: @escaping (URLRequest) -> (Int, Data),
    perform body: () async throws -> Void
) async rethrows {
    StubURLProtocol.handler = handler
    URLProtocol.registerClass(StubURLProtocol.self)
    defer {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.handler = nil
    }
    try await body()
}
