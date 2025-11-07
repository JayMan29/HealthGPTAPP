//
//  MyChartClient.swift
//  HealthGPT
//
//  Created by Augustine Manadan on 8/15/25.
//

// MyChartClient.swift
import Foundation

final class MyChartClient {
    /// Set this to Epic’s FHIR base URL (R4). Example sandbox:
    /// https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4
    private let fhirBaseURL: URL
    private let tokenProvider: (@escaping (String?) -> Void) -> Void

    init(fhirBaseURL: URL,
         tokenProvider: @escaping (@escaping (String?) -> Void) -> Void) {
        self.fhirBaseURL = fhirBaseURL
        self.tokenProvider = tokenProvider
    }

    /// Builds a single EHRContext by calling a few FHIR resources.
    func buildEHRContext(patientID: String) async -> EHRContext {
        var ctx = EHRContext()

        // Each call is optional; if it fails we just skip that section.
        async let patient = fetchPatient(patientID: patientID)
        async let problems = fetchConditions(patientID: patientID)                  // Problem list
        async let meds = fetchMedications(patientID: patientID)                     // MedicationStatement/Request
        async let allergies = fetchAllergies(patientID: patientID)                  // AllergyIntolerance
        async let vitals = fetchVitals(patientID: patientID)                        // Observation?category=vital-signs
        async let labs = fetchLabs(patientID: patientID)                            // Observation?category=laboratory
        async let notes = fetchRecentNotes(patientID: patientID)                    // DocumentReference or Composition

        if let p = await patient {
            ctx.patientName = p.name
            ctx.ageYears = p.ageYears
            ctx.sex = p.sex
        }
        ctx.problems = await problems ?? []
        ctx.medications = await meds ?? []
        ctx.allergies = await allergies ?? []
        ctx.vitals = await vitals ?? []
        ctx.labs = await labs ?? []
        ctx.recentNotes = await notes ?? []

        return ctx
    }

    // MARK: - Simple fetch helpers

    private func authedRequest(path: String, query: [URLQueryItem]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            tokenProvider { token in
                guard let token else {
                    return cont.resume(throwing: URLError(.userAuthenticationRequired))
                }
                var url = self.fhirBaseURL.appendingPathComponent(path)
                var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                comps.queryItems = query
                url = comps.url!
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
                URLSession.shared.dataTask(with: req) { data, _, err in
                    if let err { cont.resume(throwing: err); return }
                    cont.resume(returning: data ?? Data())
                }.resume()
            }
        }
    }

    // Patient (R4: /Patient/{id})
    private func fetchPatient(patientID: String) async -> (name: String?, ageYears: Int?, sex: String?)? {
        do {
            let data = try await authedRequest(path: "Patient/\(patientID)", query: [])
            let p = try JSONDecoder().decode(FHIRPatient.self, from: data)
            let name = p.name?.first.flatMap { [$0.given?.joined(separator: " "), $0.family].compactMap { $0 }.joined(separator: " ") }
            let sex = p.gender
            let age = p.birthDate.flatMap { ageFromBirthdate($0) }
            return (name, age, sex)
        } catch { return nil }
    }

    // Conditions (Problem list)  GET /Condition?patient={id}&category=problem-list-item
    private func fetchConditions(patientID: String) async -> [String]? {
        do {
            let data = try await authedRequest(path: "Condition",
                                               query: [URLQueryItem(name: "patient", value: patientID),
                                                       URLQueryItem(name: "category", value: "problem-list-item"),
                                                       URLQueryItem(name: "_count", value: "50")])
            let bundle = try JSONDecoder().decode(FHIRBundle<FHIRCondition>.self, from: data)
            return bundle.entry?.compactMap { $0.resource?.code?.text } ?? []
        } catch { return nil }
    }

    // Meds (MedicationStatement preferred; MedicationRequest is fine) /MedicationStatement?patient={id}
    private func fetchMedications(patientID: String) async -> [String]? {
        do {
            let data = try await authedRequest(path: "MedicationStatement",
                                               query: [URLQueryItem(name: "patient", value: patientID),
                                                       URLQueryItem(name: "_count", value: "50")])
            let bundle = try JSONDecoder().decode(FHIRBundle<FHIRMedicationStatement>.self, from: data)
            return bundle.entry?.compactMap { $0.resource?.medicationCodeableConcept?.text } ?? []
        } catch { return nil }
    }

    // Allergies /AllergyIntolerance?patient={id}
    private func fetchAllergies(patientID: String) async -> [String]? {
        do {
            let data = try await authedRequest(path: "AllergyIntolerance",
                                               query: [URLQueryItem(name: "patient", value: patientID),
                                                       URLQueryItem(name: "_count", value: "50")])
            let bundle = try JSONDecoder().decode(FHIRBundle<FHIRAllergyIntolerance>.self, from: data)
            return bundle.entry?.compactMap { $0.resource?.code?.text } ?? []
        } catch { return nil }
    }

    // Vitals /Observation?patient={id}&category=vital-signs
    private func fetchVitals(patientID: String) async -> [String]? {
        do {
            let data = try await authedRequest(path: "Observation",
                                               query: [URLQueryItem(name: "patient", value: patientID),
                                                       URLQueryItem(name: "category", value: "vital-signs"),
                                                       URLQueryItem(name: "_count", value: "50")])
            let bundle = try JSONDecoder().decode(FHIRBundle<FHIRObservation>.self, from: data)
            return bundle.entry?.compactMap { obs in
                guard let o = obs.resource else { return nil }
                let code = o.code?.text ?? "Vital"
                let when = o.effectiveDateTime ?? o.issued
                let val = o.valueQuantity.flatMap { formatQuantity($0) }
                return [code, val, dateString(when)].compactMap{ $0 }.joined(separator: " ")
            } ?? []
        } catch { return nil }
    }

    // Labs /Observation?patient={id}&category=laboratory
    private func fetchLabs(patientID: String) async -> [String]? {
        do {
            let data = try await authedRequest(path: "Observation",
                                               query: [URLQueryItem(name: "patient", value: patientID),
                                                       URLQueryItem(name: "category", value: "laboratory"),
                                                       URLQueryItem(name: "_count", value: "50")])
            let bundle = try JSONDecoder().decode(FHIRBundle<FHIRObservation>.self, from: data)
            return bundle.entry?.compactMap { obs in
                guard let o = obs.resource else { return nil }
                let name = o.code?.text ?? "Lab"
                let when = o.effectiveDateTime ?? o.issued
                let val = o.valueQuantity.flatMap { formatQuantity($0) }
                return [name, val, dateString(when)].compactMap{ $0 }.joined(separator: " ")
            } ?? []
        } catch { return nil }
    }

    // Notes — simplest path is DocumentReference (titles) /DocumentReference?patient={id}
    private func fetchRecentNotes(patientID: String) async -> [String]? {
        do {
            let data = try await authedRequest(path: "DocumentReference",
                                               query: [URLQueryItem(name: "patient", value: patientID),
                                                       URLQueryItem(name: "_count", value: "20")])
            let bundle = try JSONDecoder().decode(FHIRBundle<FHIRDocumentReference>.self, from: data)
            return bundle.entry?.compactMap { $0.resource?.description } ?? []
        } catch { return nil }
    }
}

// MARK: - Minimal FHIR models (R4-ish), only fields we use

private struct FHIRBundle<R: Decodable>: Decodable {
    struct Entry: Decodable { let resource: R? }
    let entry: [Entry]?
}

private struct FHIRPatient: Decodable {
    struct HumanName: Decodable {
        let family: String?
        let given: [String]?
    }
    let name: [HumanName]?
    let gender: String?
    let birthDate: String?
}

private struct FHIRCondition: Decodable {
    struct Code: Decodable { let text: String? }
    let code: Code?
}

private struct FHIRMedicationStatement: Decodable {
    struct Codeable: Decodable { let text: String? }
    let medicationCodeableConcept: Codeable?
}

private struct FHIRAllergyIntolerance: Decodable {
    struct Code: Decodable { let text: String? }
    let code: Code?
}

private struct FHIRObservation: Decodable {
    struct Code: Decodable { let text: String? }
    struct Quantity: Decodable { let value: Double?; let unit: String? }
    let code: Code?
    let valueQuantity: Quantity?
    let effectiveDateTime: String?
    let issued: String?
}

private struct FHIRDocumentReference: Decodable {
    let description: String?
}

// MARK: - Small format helpers

private func ageFromBirthdate(_ birthDateISO: String) -> Int? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    guard let d = f.date(from: birthDateISO) else { return nil }
    return Calendar.current.dateComponents([.year], from: d, to: Date()).year
}

private func formatQuantity(_ q: FHIRObservation.Quantity) -> String? {
    guard let v = q.value else { return nil }
    if let unit = q.unit, !unit.isEmpty { return "\(v) \(unit)" }
    return "\(v)"
}

private func dateString(_ iso: String?) -> String? {
    guard let iso else { return nil }
    // show just YYYY-MM-DD
    return String(iso.prefix(10))
}
