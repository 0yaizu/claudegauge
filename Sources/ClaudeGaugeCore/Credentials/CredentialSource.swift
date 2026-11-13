public protocol CredentialSource: Sendable {
    func load() async throws -> OAuthCredential
}
