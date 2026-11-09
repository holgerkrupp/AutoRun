import CryptoKit
import Foundation
import Security

/// Stable operation grants shared by macOS, iOS, and iPadOS. A permission is
/// deliberately not inferred from another permission or from CloudKit access.
enum RemoteCapability: String, Codable, CaseIterable, Sendable {
    case automationExecute = "automation.execute"
    case systemRead = "system.read"
    case filesRead = "files.read"
    case filesWrite = "files.write"
    case terminalExecute = "terminal.execute"
    case terminalInteractive = "terminal.interactive"
    case screenControl = "screen.control"
}

enum DeviceKeychainError: Error {
    case keychainStatus(OSStatus)
    case invalidKeyMaterial
}

/// Device identity and software-backed P-256 keys stored as device-only
/// Keychain items. Secure Enclave support is a follow-up: CryptoKit's generic
/// key representation cannot claim enclave protection, so this implementation
/// does not imply that the private key is enclave-backed.
enum DeviceKeychain {
    private static let service = "de.holgerkrupp.AutoRun.device-identity.v1"

    static func deviceID() throws -> UUID {
        let data = try value(for: "device-id") { Data(UUID().uuidString.utf8) }
        guard let string = String(data: data, encoding: .utf8), let id = UUID(uuidString: string) else {
            throw DeviceKeychainError.invalidKeyMaterial
        }
        return id
    }

    static func storeDeviceID(_ id: UUID) throws {
        _ = try value(for: "device-id") { Data(id.uuidString.utf8) }
    }

    static func signingPrivateKey() throws -> P256.Signing.PrivateKey {
        let data = try value(for: "signing-private-key") { P256.Signing.PrivateKey().rawRepresentation }
        do { return try P256.Signing.PrivateKey(rawRepresentation: data) }
        catch { throw DeviceKeychainError.invalidKeyMaterial }
    }

    static func agreementPrivateKey() throws -> P256.KeyAgreement.PrivateKey {
        let data = try value(for: "agreement-private-key") { P256.KeyAgreement.PrivateKey().rawRepresentation }
        do { return try P256.KeyAgreement.PrivateKey(rawRepresentation: data) }
        catch { throw DeviceKeychainError.invalidKeyMaterial }
    }

    static func loadTrustedGrants() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "trusted-device-grants",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DeviceKeychainError.keychainStatus(status)
        }
        return data
    }

    static func saveTrustedGrants(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "trusted-device-grants"
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw DeviceKeychainError.keychainStatus(updateStatus) }
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw DeviceKeychainError.keychainStatus(addStatus) }
    }

    private static func value(for account: String, create: () -> Data) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var existing: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &existing)
        if status == errSecSuccess, let data = existing as? Data { return data }
        guard status == errSecItemNotFound else { throw DeviceKeychainError.keychainStatus(status) }

        let generated = create()
        var insertion = query
        insertion.removeValue(forKey: kSecReturnData as String)
        insertion.removeValue(forKey: kSecMatchLimit as String)
        insertion[kSecValueData as String] = generated
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            var racedValue: CFTypeRef?
            let racedStatus = SecItemCopyMatching(query as CFDictionary, &racedValue)
            guard racedStatus == errSecSuccess, let data = racedValue as? Data else {
                throw DeviceKeychainError.keychainStatus(racedStatus)
            }
            return data
        }
        guard addStatus == errSecSuccess else { throw DeviceKeychainError.keychainStatus(addStatus) }
        return generated
    }
}

enum RemoteSecurityError: Error, Equatable {
    case unsupportedVersion
    case expired
    case invalidLifetime
    case wrongTarget
    case unauthorized
    case invalidSignature
    case invalidCiphertext
    case replay
    case invalidChallenge
    case challengeExpired
    case replayLedgerUnavailable
}

/// Durable replay protection for accepted envelopes. The lock makes the
/// check-and-record atomic across concurrent callers in this process; the
/// persisted marker survives app restarts. Full storage fails closed.
final class CommandReplayLedger: @unchecked Sendable {
    static let shared = CommandReplayLedger()
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let storageKey = "AutoRun.remoteCommandReplay.v1"
    private let maximumEntries = 50_000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func consume(commandID: UUID, nonce: Data, now: Date = .now) throws {
        lock.lock()
        defer { lock.unlock() }

        var entries = try readEntries()
        entries = entries.filter { now.timeIntervalSince($0.value) <= RemoteCommandCryptography.maximumLifetime + 60 }
        let key = "\(commandID.uuidString):\(nonce.base64EncodedString())"
        guard entries[key] == nil else { throw RemoteSecurityError.replay }
        guard entries.count < maximumEntries else { throw RemoteSecurityError.replayLedgerUnavailable }
        entries[key] = now
        do { defaults.set(try JSONEncoder().encode(entries), forKey: storageKey) }
        catch { throw RemoteSecurityError.replayLedgerUnavailable }
    }

    private func readEntries() throws -> [String: Date] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        do { return try JSONDecoder().decode([String: Date].self, from: data) }
        catch { throw RemoteSecurityError.replayLedgerUnavailable }
    }
}

/// Short-lived pairing data suitable for a QR payload. It contains only public
/// keys and a random, single-use challenge; never private or reusable secrets.
struct PairingChallenge: Codable, Hashable, Sendable {
    static let protocolVersion = 1
    static let lifetime: TimeInterval = 180

    let protocolVersion: Int
    let id: UUID
    let macDeviceID: UUID
    let createdAt: Date
    let expiresAt: Date
    let nonce: Data
    let signingPublicKey: Data
    let agreementPublicKey: Data
    let signature: Data

    init(
        macDeviceID: UUID,
        signer: P256.Signing.PrivateKey,
        agreementPublicKey: Data,
        now: Date = .now
    ) throws {
        self.protocolVersion = Self.protocolVersion
        self.id = UUID()
        self.macDeviceID = macDeviceID
        self.createdAt = now
        self.expiresAt = now.addingTimeInterval(Self.lifetime)
        self.nonce = Self.randomNonce()
        self.signingPublicKey = signer.publicKey.x963Representation
        self.agreementPublicKey = agreementPublicKey
        self.signature = try signer.signature(for: Self.signedBytes(
            protocolVersion: self.protocolVersion,
            id: self.id,
            macDeviceID: self.macDeviceID,
            createdAt: self.createdAt,
            expiresAt: self.expiresAt,
            nonce: self.nonce,
            signingPublicKey: self.signingPublicKey,
            agreementPublicKey: self.agreementPublicKey
        )).derRepresentation
    }

    func validate(now: Date = .now) throws {
        guard protocolVersion == Self.protocolVersion else { throw RemoteSecurityError.unsupportedVersion }
        guard expiresAt > createdAt, expiresAt.timeIntervalSince(createdAt) <= Self.lifetime else {
            throw RemoteSecurityError.invalidLifetime
        }
        guard now < expiresAt else { throw RemoteSecurityError.challengeExpired }
        let publicKey: P256.Signing.PublicKey
        let signature: P256.Signing.ECDSASignature
        do {
            publicKey = try P256.Signing.PublicKey(x963Representation: signingPublicKey)
            signature = try P256.Signing.ECDSASignature(derRepresentation: self.signature)
        } catch { throw RemoteSecurityError.invalidSignature }
        guard publicKey.isValidSignature(signature, for: Self.signedBytes(
            protocolVersion: protocolVersion,
            id: id,
            macDeviceID: macDeviceID,
            createdAt: createdAt,
            expiresAt: expiresAt,
            nonce: nonce,
            signingPublicKey: signingPublicKey,
            agreementPublicKey: agreementPublicKey
        )) else { throw RemoteSecurityError.invalidSignature }
    }

    private static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static func signedBytes(
        protocolVersion: Int,
        id: UUID,
        macDeviceID: UUID,
        createdAt: Date,
        expiresAt: Date,
        nonce: Data,
        signingPublicKey: Data,
        agreementPublicKey: Data
    ) -> Data {
        struct Transcript: Codable {
            let protocolVersion: Int
            let id: UUID
            let macDeviceID: UUID
            let createdAt: Date
            let expiresAt: Date
            let nonce: Data
            let signingPublicKey: Data
            let agreementPublicKey: Data
        }
        return (try? JSONEncoder.canonical.encode(Transcript(
            protocolVersion: protocolVersion,
            id: id,
            macDeviceID: macDeviceID,
            createdAt: createdAt,
            expiresAt: expiresAt,
            nonce: nonce,
            signingPublicKey: signingPublicKey,
            agreementPublicKey: agreementPublicKey
        ))) ?? Data()
    }
}

/// Mac-local one-time challenge registry. In production this ledger is created
/// and consumed only by the pairing coordinator after user approval.
final class PairingChallengeLedger: @unchecked Sendable {
    private struct Entry: Codable { var expiresAt: Date; var consumed: Bool }
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let storageKey = "AutoRun.pairingChallenges.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func register(_ challenge: PairingChallenge, now: Date = .now) throws {
        try challenge.validate(now: now)
        lock.lock()
        defer { lock.unlock() }
        var entries = try readEntries()
        entries = entries.filter { now < $0.value.expiresAt && !$0.value.consumed }
        guard entries[challenge.id.uuidString] == nil else { throw RemoteSecurityError.replay }
        entries[challenge.id.uuidString] = Entry(expiresAt: challenge.expiresAt, consumed: false)
        do { defaults.set(try JSONEncoder().encode(entries), forKey: storageKey) }
        catch { throw RemoteSecurityError.replayLedgerUnavailable }
    }

    func consume(challengeID: UUID, now: Date = .now) throws {
        lock.lock()
        defer { lock.unlock() }
        var entries = try readEntries()
        guard var entry = entries[challengeID.uuidString] else { throw RemoteSecurityError.invalidChallenge }
        guard now < entry.expiresAt else { throw RemoteSecurityError.challengeExpired }
        guard !entry.consumed else { throw RemoteSecurityError.replay }
        entry.consumed = true
        entries[challengeID.uuidString] = entry
        do { defaults.set(try JSONEncoder().encode(entries), forKey: storageKey) }
        catch { throw RemoteSecurityError.replayLedgerUnavailable }
    }

    private func readEntries() throws -> [String: Entry] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        do { return try JSONDecoder().decode([String: Entry].self, from: data) }
        catch { throw RemoteSecurityError.replayLedgerUnavailable }
    }
}

struct PairingProof: Codable, Hashable, Sendable {
    let challengeID: UUID
    let macDeviceID: UUID
    let companionDeviceID: UUID
    let signingPublicKey: Data
    let agreementPublicKey: Data
    let signature: Data
}

enum PairingCryptography {
    static func makeProof(
        challenge: PairingChallenge,
        companionDeviceID: UUID,
        signer: P256.Signing.PrivateKey,
        agreementPublicKey: Data
    ) throws -> PairingProof {
        let unsigned = PairingProof(
            challengeID: challenge.id,
            macDeviceID: challenge.macDeviceID,
            companionDeviceID: companionDeviceID,
            signingPublicKey: signer.publicKey.x963Representation,
            agreementPublicKey: agreementPublicKey,
            signature: Data()
        )
        let signature = try signer.signature(for: try proofBytes(challenge: challenge, proof: unsigned)).derRepresentation
        return PairingProof(
            challengeID: unsigned.challengeID,
            macDeviceID: unsigned.macDeviceID,
            companionDeviceID: unsigned.companionDeviceID,
            signingPublicKey: unsigned.signingPublicKey,
            agreementPublicKey: unsigned.agreementPublicKey,
            signature: signature
        )
    }

    static func verify(_ proof: PairingProof, for challenge: PairingChallenge, now: Date = .now) throws -> DeviceGrant {
        try challenge.validate(now: now)
        guard proof.challengeID == challenge.id, proof.macDeviceID == challenge.macDeviceID else {
            throw RemoteSecurityError.invalidChallenge
        }
        let signer: P256.Signing.PublicKey
        do { signer = try P256.Signing.PublicKey(x963Representation: proof.signingPublicKey) }
        catch { throw RemoteSecurityError.invalidSignature }
        let signature: P256.Signing.ECDSASignature
        do { signature = try P256.Signing.ECDSASignature(derRepresentation: proof.signature) }
        catch { throw RemoteSecurityError.invalidSignature }
        guard signer.isValidSignature(signature, for: try proofBytes(challenge: challenge, proof: proof)) else {
            throw RemoteSecurityError.invalidSignature
        }
        do { _ = try P256.KeyAgreement.PublicKey(x963Representation: proof.agreementPublicKey) }
        catch { throw RemoteSecurityError.invalidChallenge }
        return DeviceGrant(
            id: proof.companionDeviceID,
            signingPublicKey: proof.signingPublicKey,
            agreementPublicKey: proof.agreementPublicKey,
            capabilities: []
        )
    }

    private static func proofBytes(challenge: PairingChallenge, proof: PairingProof) throws -> Data {
        struct Transcript: Codable {
            let protocolVersion: Int
            let challengeID: UUID
            let macDeviceID: UUID
            let challengeNonce: Data
            let challengeExpiresAt: Date
            let macSigningPublicKey: Data
            let macAgreementPublicKey: Data
            let companionDeviceID: UUID
            let signingPublicKey: Data
            let agreementPublicKey: Data
        }
        let transcript = Transcript(
            protocolVersion: challenge.protocolVersion,
            challengeID: challenge.id,
            macDeviceID: challenge.macDeviceID,
            challengeNonce: challenge.nonce,
            challengeExpiresAt: challenge.expiresAt,
            macSigningPublicKey: challenge.signingPublicKey,
            macAgreementPublicKey: challenge.agreementPublicKey,
            companionDeviceID: proof.companionDeviceID,
            signingPublicKey: proof.signingPublicKey,
            agreementPublicKey: proof.agreementPublicKey
        )
        return try JSONEncoder.canonical.encode(transcript)
    }
}

struct DeviceGrant: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let signingPublicKey: Data
    let agreementPublicKey: Data
    var capabilities: Set<RemoteCapability>
    var revokedAt: Date?

    var isRevoked: Bool { revokedAt != nil }
}

protocol DeviceGrantPersistence: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct KeychainDeviceGrantPersistence: DeviceGrantPersistence {
    func load() throws -> Data? { try DeviceKeychain.loadTrustedGrants() }
    func save(_ data: Data) throws { try DeviceKeychain.saveTrustedGrants(data) }
}

/// Mac-authoritative local grants. Call `approve` only in response to an
/// explicit Mac-side user approval; CloudKit records cannot mutate this store.
final class DeviceGrantRegistry: @unchecked Sendable {
    static let shared = DeviceGrantRegistry(persistence: KeychainDeviceGrantPersistence())
    private let persistence: DeviceGrantPersistence
    private let lock = NSLock()

    init(persistence: DeviceGrantPersistence) { self.persistence = persistence }

    func all() throws -> [DeviceGrant] {
        lock.lock()
        defer { lock.unlock() }
        return try readGrants()
    }

    func grant(for deviceID: UUID) throws -> DeviceGrant? {
        try all().first { $0.id == deviceID && !$0.isRevoked }
    }

    func approve(
        proof: PairingProof,
        challenge: PairingChallenge,
        capabilities: Set<RemoteCapability>,
        challengeLedger: PairingChallengeLedger,
        now: Date = .now
    ) throws -> DeviceGrant {
        let proposed = try PairingCryptography.verify(proof, for: challenge, now: now)
        try challengeLedger.consume(challengeID: challenge.id, now: now)
        lock.lock()
        defer { lock.unlock() }
        var grants = try readGrants()
        let approved = DeviceGrant(
            id: proposed.id,
            signingPublicKey: proposed.signingPublicKey,
            agreementPublicKey: proposed.agreementPublicKey,
            capabilities: capabilities,
            revokedAt: nil
        )
        grants.removeAll { $0.id == approved.id }
        grants.append(approved)
        try write(grants)
        return approved
    }

    func setCapabilities(_ capabilities: Set<RemoteCapability>, for deviceID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var grants = try readGrants()
        guard let index = grants.firstIndex(where: { $0.id == deviceID && !$0.isRevoked }) else {
            throw RemoteSecurityError.unauthorized
        }
        grants[index].capabilities = capabilities
        try write(grants)
    }

    func revoke(_ deviceID: UUID, at date: Date = .now) throws {
        lock.lock()
        defer { lock.unlock() }
        var grants = try readGrants()
        guard let index = grants.firstIndex(where: { $0.id == deviceID }) else { return }
        grants[index].capabilities = []
        grants[index].revokedAt = date
        try write(grants)
    }

    private func readGrants() throws -> [DeviceGrant] {
        guard let data = try persistence.load() else { return [] }
        return try JSONDecoder().decode([DeviceGrant].self, from: data)
    }

    private func write(_ grants: [DeviceGrant]) throws {
        try persistence.save(JSONEncoder.canonical.encode(grants))
    }
}

struct AuthenticatedCommandHeader: Codable, Hashable, Sendable {
    let protocolVersion: Int
    let commandID: UUID
    let sourceDeviceID: UUID
    let targetDeviceID: UUID
    let operationID: UUID
    let capability: RemoteCapability
    let createdAt: Date
    let expiresAt: Date
    let nonce: Data
}

struct AuthenticatedCommandEnvelope: Codable, Hashable, Sendable {
    let header: AuthenticatedCommandHeader
    let ephemeralPublicKey: Data
    /// AES.GCM combined representation (nonce, ciphertext, authentication tag).
    let sealedPayload: Data
    let signature: Data
}

/// Creates and validates versioned, signed, encrypted command envelopes. The
/// caller supplies locally approved grants; a public CloudKit device record is
/// never an authorization source.
enum RemoteCommandCryptography {
    static let maximumLifetime: TimeInterval = 15 * 60

    static func seal<Payload: Encodable>(
        payload: Payload,
        commandID: UUID = UUID(),
        sourceDeviceID: UUID,
        targetDeviceID: UUID,
        operationID: UUID,
        capability: RemoteCapability,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        signer: P256.Signing.PrivateKey,
        recipient: P256.KeyAgreement.PublicKey
    ) throws -> AuthenticatedCommandEnvelope {
        let expiry = expiresAt ?? createdAt.addingTimeInterval(maximumLifetime)
        let header = AuthenticatedCommandHeader(
            protocolVersion: PairingChallenge.protocolVersion,
            commandID: commandID,
            sourceDeviceID: sourceDeviceID,
            targetDeviceID: targetDeviceID,
            operationID: operationID,
            capability: capability,
            createdAt: createdAt,
            expiresAt: expiry,
            nonce: SecureNonce.generate()
        )
        try validateTime(header, now: createdAt)

        let ephemeral = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = deriveKey(sharedSecret: sharedSecret, header: header)
        let aad = try canonicalHeader(header)
        let payloadData = try JSONEncoder.canonical.encode(payload)
        let sealed = try AES.GCM.seal(payloadData, using: key, authenticating: aad)
        guard let combined = sealed.combined else { throw RemoteSecurityError.invalidCiphertext }
        let ephemeralPublicKey = ephemeral.publicKey.x963Representation
        let signedBytes = aad + ephemeralPublicKey + combined
        let signature = try signer.signature(for: signedBytes).derRepresentation
        return AuthenticatedCommandEnvelope(
            header: header,
            ephemeralPublicKey: ephemeralPublicKey,
            sealedPayload: combined,
            signature: signature
        )
    }

    static func open<Payload: Decodable>(
        _ envelope: AuthenticatedCommandEnvelope,
        as type: Payload.Type,
        signerPublicKey: P256.Signing.PublicKey,
        recipient: P256.KeyAgreement.PrivateKey,
        expectedTargetDeviceID: UUID,
        grant: DeviceGrant,
        now: Date = .now,
        consumeReplay: (UUID, Data) throws -> Void = {
            try CommandReplayLedger.shared.consume(commandID: $0, nonce: $1)
        }
    ) throws -> Payload {
        let header = envelope.header
        guard header.protocolVersion == PairingChallenge.protocolVersion else { throw RemoteSecurityError.unsupportedVersion }
        try validateTime(header, now: now)
        guard header.targetDeviceID == expectedTargetDeviceID else { throw RemoteSecurityError.wrongTarget }
        guard grant.id == header.sourceDeviceID,
              !grant.isRevoked,
              grant.capabilities.contains(header.capability),
              grant.signingPublicKey == signerPublicKey.x963Representation else {
            throw RemoteSecurityError.unauthorized
        }

        let aad = try canonicalHeader(header)
        let signedBytes = aad + envelope.ephemeralPublicKey + envelope.sealedPayload
        guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: envelope.signature),
              signerPublicKey.isValidSignature(signature, for: signedBytes) else {
            throw RemoteSecurityError.invalidSignature
        }

        let ephemeral: P256.KeyAgreement.PublicKey
        do { ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: envelope.ephemeralPublicKey) }
        catch { throw RemoteSecurityError.invalidCiphertext }
        let sharedSecret: SharedSecret
        do { sharedSecret = try recipient.sharedSecretFromKeyAgreement(with: ephemeral) }
        catch { throw RemoteSecurityError.invalidCiphertext }
        let key = deriveKey(sharedSecret: sharedSecret, header: header)
        let box: AES.GCM.SealedBox
        do { box = try AES.GCM.SealedBox(combined: envelope.sealedPayload) }
        catch { throw RemoteSecurityError.invalidCiphertext }
        let plaintext: Data
        do { plaintext = try AES.GCM.open(box, using: key, authenticating: aad) }
        catch { throw RemoteSecurityError.invalidCiphertext }

        try consumeReplay(header.commandID, header.nonce)
        do { return try JSONDecoder.canonical.decode(type, from: plaintext) }
        catch { throw RemoteSecurityError.invalidCiphertext }
    }

    private static func validateTime(_ header: AuthenticatedCommandHeader, now: Date) throws {
        guard header.protocolVersion == PairingChallenge.protocolVersion else { throw RemoteSecurityError.unsupportedVersion }
        guard header.expiresAt > header.createdAt,
              header.expiresAt.timeIntervalSince(header.createdAt) <= maximumLifetime else {
            throw RemoteSecurityError.invalidLifetime
        }
        guard now >= header.createdAt.addingTimeInterval(-60), now < header.expiresAt else {
            throw RemoteSecurityError.expired
        }
    }

    private static func canonicalHeader(_ header: AuthenticatedCommandHeader) throws -> Data {
        try JSONEncoder.canonical.encode(header)
    }

    private static func deriveKey(sharedSecret: SharedSecret, header: AuthenticatedCommandHeader) -> SymmetricKey {
        let salt = Data(header.commandID.uuidString.utf8) + header.nonce
        let info = Data("AutoRun.command.v\(header.protocolVersion)".utf8)
        return sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
    }
}

private enum SecureNonce {
    static func generate() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

private extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var canonical: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
