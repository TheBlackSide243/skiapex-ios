import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Signing in with Google, without Google's library: the page of Google opens in the browser
/// sheet of iOS, and what comes back is exchanged for a token that says who signed in. The
/// token goes to the Ski Apex server, which checks it. Only the name is asked for: no email.
///
/// It needs the app's client ID from the Google Cloud console (an OAuth client of type iOS), in
/// the build setting GOOGLE_CLIENT_ID. Until there is one, the button is not shown.
@MainActor final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: Error { case canceled, failed }

    /// The client ID of the app at Google: "<numbers>-<letters>.apps.googleusercontent.com".
    static var clientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return id
    }

    /// The scheme Google sends the answer back to: the client ID with its parts in reverse.
    nonisolated static func scheme(for clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    /// The proof that who asks for the token is who opened the page (PKCE): the SHA-256 of a
    /// secret, in base64 for addresses.
    nonisolated static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The page to open, for a client ID, a secret and a word to recognize the answer by.
    nonisolated static func page(clientID: String, verifier: String, state: String) -> URL? {
        var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        parts?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: scheme(for: clientID) + ":/oauth2redirect"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid profile"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return parts?.url
    }

    private var session: ASWebAuthenticationSession?

    private static func random(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64url(Data(bytes))
    }

    /// Opens Google's page and gives the token that says who signed in.
    func token() async throws -> String {
        guard let clientID = Self.clientID else { throw Failure.failed }
        let verifier = Self.random(48), state = Self.random(16)
        guard let page = Self.page(clientID: clientID, verifier: verifier, state: state) else { throw Failure.failed }
        let scheme = Self.scheme(for: clientID)
        let back: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: page, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: Failure.canceled)
                } else {
                    continuation.resume(throwing: Failure.failed)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(throwing: Failure.failed) }
        }
        session = nil
        let items = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw Failure.failed }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: scheme + ":/oauth2redirect"),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = answer["id_token"] as? String else { throw Failure.failed }
        return token
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.compactMap(\.keyWindow).first ?? ASPresentationAnchor()
    }
}
