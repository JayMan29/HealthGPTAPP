//
//  OAuthManager.swift
//  HealthGPT
//

import Foundation
import AppAuth
import AuthenticationServices
import UIKit

final class OAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    // MARK: Epic sandbox config (fill with your Non-Production client ID)
    // ⬇️ Use your actual client ID string (no angle brackets)
    private let clientID = "fec8a9ac-8cfe-4001-9c2e-80d6f224bc0b"

    private let authorizeEndpoint = URL(string: "https://fhir.epic.com/interconnect-fhir-oauth/oauth2/authorize")!
    private let tokenEndpoint     = URL(string: "https://fhir.epic.com/interconnect-fhir-oauth/oauth2/token")!
    private let fhirAudience      = "https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4"

    // IMPORTANT: must match Epic portal + Info.plist exactly
    // Use your lowercase bundle id as the scheme
    // OAuthManager.swift
    private let redirectURI = URL(string: "com.augustinemanadan.healthgpt://oauth2redirect")!


    // Lean patient-level scopes to start (expand as needed)
    private let scopes: [String] = [
        "openid", "fhirUser", "offline_access", "launch/patient",
        "patient/Condition.read", "patient/Observation.read", "patient/MedicationRequest.read"
    ]

    // MARK: AppAuth state
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private(set) var authState: OIDAuthState? { didSet { saveAuthState() } }
    private let authStateKey = "OAuthManager.authState"

    private override init() {
        super.init()
        loadAuthState()
    }

    var isLoggedIn: Bool { authState?.isAuthorized == true }

    // MARK: Login
    func startLogin(completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔵 OAuth starting. redirect=\(redirectURI.absoluteString) aud=\(fhirAudience)")

        let config = OIDServiceConfiguration(
            authorizationEndpoint: authorizeEndpoint,
            tokenEndpoint: tokenEndpoint
        )

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: clientID,
            clientSecret: nil,
            scopes: scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["aud": fhirAudience] // REQUIRED by Epic
        )

        guard let presenter = Self.topViewController() else {
            return completion(.failure(NSError(
                domain: "OAuth",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No presenter available"]
            )))
        }

        // Uses ASWebAuthenticationSession under the hood
        currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: presenter) { [weak self] state, error in
            guard let self else { return }
            if let state {
                print("🟢 OAuth success. Tokens received.")
                self.setAuthState(state)
                completion(.success(()))
            } else {
                print("🔴 OAuth failed:", error?.localizedDescription ?? "unknown")
                completion(.failure(error ?? NSError(
                    domain: "OAuth",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Authorization failed"]
                )))
            }
            self.currentAuthorizationFlow = nil
        }
    }

    /// MUST be called from App entry to finish OAuth. If this never runs, the web sheet won't close.
    @discardableResult
    func resumeExternalUserAgentFlow(with url: URL) -> Bool {
        print("🟣 resumeExternalUserAgentFlow URL:", url.absoluteString)
        if currentAuthorizationFlow?.resumeExternalUserAgentFlow(with: url) == true {
            currentAuthorizationFlow = nil
            return true
        }
        return false
    }

    // MARK: Tokens
    func withFreshAccessToken(_ block: @escaping (String?) -> Void) {
        guard let authState else { return block(nil) }
        authState.performAction { access, _, error in
            if let access { block(access) }
            else {
                print("🔴 Token error:", error?.localizedDescription ?? "unknown")
                block(nil)
            }
        }
    }

    func logout() { setAuthState(nil) }

    // MARK: Helpers (optional)
    func currentIDToken() -> String? { authState?.lastTokenResponse?.idToken }

    func currentFHIRUser() -> String? {
        currentIDTokenPayload()?["fhirUser"] as? String
    }

    func currentPatientID() -> String? {
        let payload = currentIDTokenPayload()
        if let p = payload?["patient"] as? String, !p.isEmpty { return p }
        if let fu = payload?["fhirUser"] as? String, let id = fu.split(separator: "/").last { return String(id) }
        return nil
    }

    private func currentIDTokenPayload() -> [String: Any]? {
        guard let id = currentIDToken() else { return nil }
        let parts = id.split(separator: "."); guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    // MARK: Persist auth state
    private func setAuthState(_ s: OIDAuthState?) {
        authState = s
        if let s {
            s.stateChangeDelegate = self
            s.errorDelegate = self
        }
    }

    private func saveAuthState() {
        guard let s = authState else {
            UserDefaults.standard.removeObject(forKey: authStateKey)
            return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: s, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: authStateKey)
        } catch { print("🔴 Persist OIDAuthState failed:", error.localizedDescription) }
    }

    private func loadAuthState() {
        guard let data = UserDefaults.standard.data(forKey: authStateKey) else { return }
        do {
            if let s = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) {
                setAuthState(s)
            }
        } catch { print("🔴 Restore OIDAuthState failed:", error.localizedDescription) }
    }

    // MARK: ASWebAuthenticationSession anchor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }

    // Find a presenter for AppAuth
    private static func topViewController(from base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        if let nav = root as? UINavigationController { return topViewController(from: nav.visibleViewController) }
        if let tab = root as? UITabBarController { return topViewController(from: tab.selectedViewController) }
        if let presented = root?.presentedViewController { return topViewController(from: presented) }
        return root
    }
}

// MARK: - OIDAuthStateChangeDelegate / OIDAuthStateErrorDelegate

extension OAuthManager: OIDAuthStateChangeDelegate, OIDAuthStateErrorDelegate {
    func didChange(_ state: OIDAuthState) { saveAuthState() }
    func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        print("🔴 Auth state error:", error.localizedDescription)
    }
}

// MARK: - Convenience factory for MyChartClient
// Keep this in the same file so it can access `private fhirAudience`.
extension OAuthManager {
    /// Builds a MyChartClient that uses OAuthManager for tokens.
    func makeMyChartClient() -> MyChartClient {
        let base = URL(string: self.fhirAudience)! // uses your R4 base
        return MyChartClient(
            fhirBaseURL: base,
            tokenProvider: { completion in
                self.withFreshAccessToken { token in completion(token) }
            }
        )
    }
}

