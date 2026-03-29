import Foundation
import Combine
import Contacts

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var permissionStatus: CNAuthorizationStatus = .notDetermined
    @Published var loading: Bool = false
    @Published var registered: [RegisteredContact] = []
    @Published var invitable: [LocalContact] = []
    @Published var errorMessage: String?

    // Pull the signed-in user's phone from cached profile data (normalized to E.164).
    private var myOwnNumber: String? {
        let cached = UserDefaults.standard.string(forKey: "userPhone")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = cached.isEmpty ? "" : normalizeToE164ish(cached)
        return normalized.isEmpty ? nil : normalized
    }

    // Optional debug helpers (only when supplied via env var to avoid shipping test numbers).
    private var debugAlwaysIncludePhones: [String] {
#if DEBUG
        if let env = ProcessInfo.processInfo.environment["CRITIC_DEBUG_PHONES"] {
            return env
                .split(separator: ",")
                .map { normalizeToE164ish(String($0)) }
                .filter { !$0.isEmpty }
        }
#endif
        return []
    }

    // ✅ JWT-protected API Gateway route
    private let lookupURL = AppEndpoints.Gateway.contactsLookup

    private let store = CNContactStore()

    // MARK: Entry
    func bootstrap() async {
        await refreshPermission()
        switch permissionStatus {
        case .authorized:
            await safeLoad()
        case .notDetermined:
            errorMessage = nil
            registered = []
            invitable = []
        default:
            errorMessage = deniedMessage
        }
    }

    func refresh() async { await safeLoad() }

    func requestAccessAndLoad() async {
        await requestPermissionLegacy()
        switch permissionStatus {
        case .authorized:
            await safeLoad()
        case .notDetermined:
            errorMessage = nil
        default:
            errorMessage = deniedMessage
            registered = []
            invitable = []
        }
    }

    // MARK: Permission
    private var deniedMessage: String {
        "Contacts access denied. To show which of your friends are on Critic, enable Contacts in Settings."
    }

    private func refreshPermission() async {
        permissionStatus = CNContactStore.authorizationStatus(for: .contacts)
        print("[ContactsVM] permission=\(permissionStatus.rawValue)")
    }

    private func requestPermissionLegacy() async {
        await withCheckedContinuation { cont in
            store.requestAccess(for: .contacts) { _, err in
                DispatchQueue.main.async {
                    if let err { print("[ContactsVM] requestAccess error: \(err.localizedDescription)") }
                    self.permissionStatus = CNContactStore.authorizationStatus(for: .contacts)
                    cont.resume()
                }
            }
        }
    }

    // MARK: Load & Network
    private func safeLoad() async {
        do {
            try Task.checkCancellation()
            try await loadContactsAndLookup()
        } catch is CancellationError {
            return
        } catch {
            print("[ContactsVM] load error: \(error)")
            errorMessage = error.localizedDescription
            registered = []
            invitable = []
        }
    }

    private func loadContactsAndLookup() async throws {
        guard permissionStatus == .authorized else {
            print("[ContactsVM] load skipped: not authorized")
            return
        }

        loading = true
        errorMessage = nil
        defer { loading = false }

        try Task.checkCancellation()

        // 1) Fetch local contacts off the main actor.
        let (locals, deviceE164s) = try await fetchLocalContacts()
        try Task.checkCancellation()

        // 2) Merge with test numbers (dedupe)
        let phonesToLookup = Array(Set(deviceE164s + debugAlwaysIncludePhones)).sorted()
        print("[ContactsVM] locals=\(locals.count) lookupPhones=\(phonesToLookup.count)")

        if phonesToLookup.isEmpty {
            registered = []
            invitable = locals
            return
        }

        // 3) Build request with myPhone (for excluding me server-side)
        var payload: [String: Any] = [
            "phoneNumbers": phonesToLookup
        ]
        if let myPhone = myOwnNumber {
            payload["myPhone"] = myPhone
        }

        print("[ContactsVM] POST \(lookupURL.absoluteString) phones=\(phonesToLookup.count)")
        let request = APIRequestDescriptor(
            url: lookupURL,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(payload),
            authorization: .currentUser
        )
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        try Task.checkCancellation()

        print("[ContactsVM] HTTP \(response.statusCode)")
        print("[ContactsVM] BODY \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")

        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ContactsLookup", code: response.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Lookup failed: \(body)"])
        }

        // 4) Decode
        struct LookupResponse: Decodable {
            struct Item: Decodable { let userId: String; let name: String? }
            let registered: [Item]
            let unregistered: [String]
        }
        let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)

        // 5) Map server results
        let reg: [RegisteredContact] = decoded.registered.map {
            .init(id: $0.userId, name: $0.name, phoneE164: "")
        }

        let unregSet = Set(decoded.unregistered)
        let inv: [LocalContact] = locals.compactMap { c in
            let anyRegisteredHere = c.normalizedPhones.contains { !unregSet.contains($0) }
            let anyUnregisteredHere = c.normalizedPhones.contains { unregSet.contains($0) }
            return anyRegisteredHere ? nil : (anyUnregisteredHere ? c : nil)
        }

        registered = reg.sorted { ($0.name ?? $0.phoneE164) < ($1.name ?? $1.phoneE164) }
        invitable = inv.sorted { $0.displayName < $1.displayName }
        print("[ContactsVM] registered=\(reg.count) invitable=\(inv.count)")
    }

    // MARK: Contacts fetch
    private func fetchLocalContacts() async throws -> ([LocalContact], [String]) {
        try await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault

            var results: [LocalContact] = []
            var allE164: [String] = []

            do {
                try store.enumerateContacts(with: request) { c, stop in
                    if Task.isCancelled {
                        stop.pointee = true
                        return
                    }

                    let name = [c.givenName, c.familyName].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    let rawPhones = c.phoneNumbers.map { $0.value.stringValue }.filter { !$0.isEmpty }
                    let normalized = rawPhones.map { normalizeToE164ish($0) }
                    allE164.append(contentsOf: normalized)
                    if !rawPhones.isEmpty {
                        results.append(.init(
                            id: c.identifier,
                            displayName: name.isEmpty ? (rawPhones.first ?? "Contact") : name,
                            phones: rawPhones,
                            normalizedPhones: normalized
                        ))
                    }
                }
            } catch {
                print("⚠️ [ContactsVM] enumerateContacts failed: \(error.localizedDescription)")
                throw error
            }

            try Task.checkCancellation()
            let uniqueE164 = Array(Set(allE164))
            return (results, uniqueE164)
        }.value
    }
}
