//
//  FHIRClient.swift
//  HealthGPT
//
//  Created by Augustine Manadan on 8/15/25.
//

// FHIRClient.swift
import Foundation

struct FHIRClient {
    /// Your Epic tenant's FHIR base (R4). Example (MyChart Playground):
    /// https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4
    let baseURL: URL

    /// Call any FHIR endpoint with the bearer token from OAuth.
    func get(path: String, accessToken: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "FHIR", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "FHIR call failed"
            ])
        }
        return data
    }

    /// Quick sanity call: read Patient resource for the current user (patient context).
    /// Many Epic sandboxes expose `Patient/$patient` to resolve the current patient.
    func fetchCurrentPatientJSON(accessToken: String) async throws -> String {
        // Try an endpoint that works in Epic sandbox; if your Epic gives you a specific patient id, do "Patient/{id}"
        let data = try await get(path: "Patient/$patient", accessToken: accessToken)
        return String(data: data, encoding: .utf8) ?? "<non-utf8>"
    }

    /// Example labs call (LOINC-coded Observations) — optional.
    func fetchRecentLabsJSON(accessToken: String, max: Int = 10) async throws -> String {
        let data = try await get(path: "Observation?category=laboratory&_count=\(max)", accessToken: accessToken)
        return String(data: data, encoding: .utf8) ?? "<non-utf8>"
    }
}
