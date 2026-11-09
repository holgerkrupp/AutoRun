import XCTest
import CryptoKit
@testable import AutoRun

final class AutoRunTests: XCTestCase {
    func testAuthenticatedCommandRoundTripsAndReplayIsRejected() throws {
        let signer = P256.Signing.PrivateKey()
        let recipient = P256.KeyAgreement.PrivateKey()
        let sourceID = UUID()
        let targetID = UUID()
        let operationID = UUID()
        let grant = DeviceGrant(
            id: sourceID,
            signingPublicKey: signer.publicKey.x963Representation,
            agreementPublicKey: Data(),
            capabilities: [.automationExecute]
        )
        let envelope = try RemoteCommandCryptography.seal(
            payload: ["approvedAutomation": operationID.uuidString],
            sourceDeviceID: sourceID,
            targetDeviceID: targetID,
            operationID: operationID,
            capability: .automationExecute,
            signer: signer,
            recipient: recipient.publicKey
        )
        var consumed = Set<UUID>()
        let decoded: [String: String] = try RemoteCommandCryptography.open(
            envelope,
            as: [String: String].self,
            signerPublicKey: signer.publicKey,
            recipient: recipient,
            expectedTargetDeviceID: targetID,
            grant: grant
        ) { commandID, _ in
            guard consumed.insert(commandID).inserted else { throw RemoteSecurityError.replay }
        }
        XCTAssertEqual(decoded["approvedAutomation"], operationID.uuidString)
        XCTAssertThrowsError(try RemoteCommandCryptography.open(
            envelope,
            as: [String: String].self,
            signerPublicKey: signer.publicKey,
            recipient: recipient,
            expectedTargetDeviceID: targetID,
            grant: grant
        ) { commandID, _ in
            guard consumed.insert(commandID).inserted else { throw RemoteSecurityError.replay }
        }) { XCTAssertEqual($0 as? RemoteSecurityError, .replay) }
    }

    func testCommandEnvelopeRejectsTamperingWrongTargetAndPermissionEscalation() throws {
        let signer = P256.Signing.PrivateKey()
        let recipient = P256.KeyAgreement.PrivateKey()
        let sourceID = UUID()
        let targetID = UUID()
        let operationID = UUID()
        let envelope = try RemoteCommandCryptography.seal(
            payload: "safe payload",
            sourceDeviceID: sourceID,
            targetDeviceID: targetID,
            operationID: operationID,
            capability: .automationExecute,
            signer: signer,
            recipient: recipient.publicKey
        )
        let grant = DeviceGrant(
            id: sourceID,
            signingPublicKey: signer.publicKey.x963Representation,
            agreementPublicKey: Data(),
            capabilities: [.automationExecute]
        )
        var tamperedBytes = envelope.sealedPayload
        tamperedBytes[tamperedBytes.index(before: tamperedBytes.endIndex)] ^= 0x01
        let tampered = AuthenticatedCommandEnvelope(
            header: envelope.header,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            sealedPayload: tamperedBytes,
            signature: envelope.signature
        )
        XCTAssertThrowsError(try RemoteCommandCryptography.open(
            tampered,
            as: String.self,
            signerPublicKey: signer.publicKey,
            recipient: recipient,
            expectedTargetDeviceID: targetID,
            grant: grant,
            consumeReplay: { _, _ in }
        )) { XCTAssertEqual($0 as? RemoteSecurityError, .invalidSignature) }
        XCTAssertThrowsError(try RemoteCommandCryptography.open(
            envelope,
            as: String.self,
            signerPublicKey: signer.publicKey,
            recipient: recipient,
            expectedTargetDeviceID: UUID(),
            grant: grant,
            consumeReplay: { _, _ in }
        )) { XCTAssertEqual($0 as? RemoteSecurityError, .wrongTarget) }
        let limitedGrant = DeviceGrant(
            id: sourceID,
            signingPublicKey: signer.publicKey.x963Representation,
            agreementPublicKey: Data(),
            capabilities: [.systemRead]
        )
        XCTAssertThrowsError(try RemoteCommandCryptography.open(
            envelope,
            as: String.self,
            signerPublicKey: signer.publicKey,
            recipient: recipient,
            expectedTargetDeviceID: targetID,
            grant: limitedGrant,
            consumeReplay: { _, _ in }
        )) { XCTAssertEqual($0 as? RemoteSecurityError, .unauthorized) }
    }

    func testExpiredPairingChallengeIsRejected() {
        let created = Date(timeIntervalSince1970: 1_000)
        let macSigner = P256.Signing.PrivateKey()
        let macAgreement = P256.KeyAgreement.PrivateKey()
        let challenge = try! PairingChallenge(
            macDeviceID: UUID(),
            signer: macSigner,
            agreementPublicKey: macAgreement.publicKey.x963Representation,
            now: created
        )
        XCTAssertNoThrow(try challenge.validate(now: created.addingTimeInterval(10)))
        XCTAssertThrowsError(try challenge.validate(now: created.addingTimeInterval(181))) {
            XCTAssertEqual($0 as? RemoteSecurityError, .challengeExpired)
        }
    }

    func testPairingProofBindsDeviceIdentityAndPublicKeys() throws {
        let macSigningKey = P256.Signing.PrivateKey()
        let macAgreementKey = P256.KeyAgreement.PrivateKey()
        let companionSigningKey = P256.Signing.PrivateKey()
        let companionAgreementKey = P256.KeyAgreement.PrivateKey()
        let challenge = try PairingChallenge(
            macDeviceID: UUID(),
            signer: macSigningKey,
            agreementPublicKey: macAgreementKey.publicKey.x963Representation
        )
        let proof = try PairingCryptography.makeProof(
            challenge: challenge,
            companionDeviceID: UUID(),
            signer: companionSigningKey,
            agreementPublicKey: companionAgreementKey.publicKey.x963Representation
        )
        let grant = try PairingCryptography.verify(proof, for: challenge)
        XCTAssertEqual(grant.id, proof.companionDeviceID)
        XCTAssertTrue(grant.capabilities.isEmpty)

        let changedProof = PairingProof(
            challengeID: proof.challengeID,
            macDeviceID: proof.macDeviceID,
            companionDeviceID: UUID(),
            signingPublicKey: proof.signingPublicKey,
            agreementPublicKey: proof.agreementPublicKey,
            signature: proof.signature
        )
        XCTAssertThrowsError(try PairingCryptography.verify(changedProof, for: challenge)) {
            XCTAssertEqual($0 as? RemoteSecurityError, .invalidSignature)
        }
    }

    func testPairingChallengeIsSingleUseAcrossLedgerRecreation() throws {
        let suiteName = "AutoRunTests.Pairing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let signer = P256.Signing.PrivateKey()
        let agreement = P256.KeyAgreement.PrivateKey()
        let challenge = try PairingChallenge(
            macDeviceID: UUID(),
            signer: signer,
            agreementPublicKey: agreement.publicKey.x963Representation
        )
        try PairingChallengeLedger(defaults: defaults).register(challenge)
        try PairingChallengeLedger(defaults: defaults).consume(challengeID: challenge.id)
        XCTAssertThrowsError(try PairingChallengeLedger(defaults: defaults).consume(challengeID: challenge.id)) {
            XCTAssertEqual($0 as? RemoteSecurityError, .replay)
        }
    }

    func testMacGrantApprovalPermissionsAndRevocationAreIndependent() throws {
        let defaultsName = "AutoRunTests.Grant.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let persistence = TestDeviceGrantPersistence()
        let registry = DeviceGrantRegistry(persistence: persistence)
        let ledger = PairingChallengeLedger(defaults: defaults)
        let macSigningKey = P256.Signing.PrivateKey()
        let macAgreementKey = P256.KeyAgreement.PrivateKey()
        let companionSigningKey = P256.Signing.PrivateKey()
        let companionAgreementKey = P256.KeyAgreement.PrivateKey()
        let challenge = try PairingChallenge(
            macDeviceID: UUID(),
            signer: macSigningKey,
            agreementPublicKey: macAgreementKey.publicKey.x963Representation
        )
        try ledger.register(challenge)
        let proof = try PairingCryptography.makeProof(
            challenge: challenge,
            companionDeviceID: UUID(),
            signer: companionSigningKey,
            agreementPublicKey: companionAgreementKey.publicKey.x963Representation
        )
        let approved = try registry.approve(
            proof: proof,
            challenge: challenge,
            capabilities: [.automationExecute],
            challengeLedger: ledger
        )
        XCTAssertTrue(approved.capabilities.contains(.automationExecute))
        XCTAssertFalse(approved.capabilities.contains(.filesRead))

        try registry.setCapabilities([.systemRead], for: approved.id)
        let reduced = try XCTUnwrap(registry.grant(for: approved.id))
        XCTAssertEqual(reduced.capabilities, [.systemRead])
        try registry.revoke(approved.id)
        XCTAssertNil(try registry.grant(for: approved.id))
        XCTAssertTrue(try XCTUnwrap(registry.all().first).isRevoked)
    }

    func testUnsignedCommandFailsClosed() {
        let target = AutoRunDevice(displayName: "Mac", platform: .macOS, capabilities: [], appVersion: "1")
        let automation = AutomationDefinition(
            id: UUID(), targetDeviceID: target.id, name: "Timer", kind: .script,
            iconSystemName: "terminal", enabled: true, allowsRemoteExecution: true,
            watchEligible: false, schemaVersion: AutoRunSchema.currentVersion,
            parameters: [], updatedAt: .now
        )
        let source = AutoRunDevice(
            displayName: "iPhone", platform: .iOS,
            capabilities: [.sendRemoteCommands], appVersion: "1"
        )
        let command = RemoteCommand(
            automationID: automation.id,
            sourceDeviceID: source.id,
            targetDeviceID: target.id
        )
        XCTAssertEqual(
            command.validationError(definition: automation, targetDevice: target, sourceDevice: source),
            "Command is not cryptographically authenticated."
        )
    }

    func testReplayLedgerSurvivesRecreationAndSerializesConcurrentClaims() throws {
        let suiteName = "AutoRunTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let commandID = UUID()
        let nonce = Data([4, 5, 6])
        try CommandReplayLedger(defaults: defaults).consume(commandID: commandID, nonce: nonce)
        XCTAssertThrowsError(try CommandReplayLedger(defaults: defaults).consume(commandID: commandID, nonce: nonce)) {
            XCTAssertEqual($0 as? RemoteSecurityError, .replay)
        }

        let concurrentID = UUID()
        let ledger = CommandReplayLedger(defaults: defaults)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "AutoRunTests.replay", attributes: .concurrent)
        let resultLock = NSLock()
        var successCount = 0
        for _ in 0..<12 {
            group.enter()
            queue.async {
                if (try? ledger.consume(commandID: concurrentID, nonce: nonce)) != nil {
                    resultLock.lock()
                    successCount += 1
                    resultLock.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(successCount, 1)
    }

    func testCorruptReplayLedgerFailsClosed() throws {
        let suiteName = "AutoRunTests.CorruptReplay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("corrupt".utf8), forKey: "AutoRun.remoteCommandReplay.v1")
        XCTAssertThrowsError(try CommandReplayLedger(defaults: defaults).consume(commandID: UUID(), nonce: Data([1]))) {
            XCTAssertEqual($0 as? RemoteSecurityError, .replayLedgerUnavailable)
        }
    }

    func testRemoteCommandsRejectUnknownParametersAndDisabledAutomations() {
        let device = AutoRunDevice(displayName: "Mac", platform: .macOS, capabilities: [.executeScripts], appVersion: "1")
        let automation = AutomationDefinition(
            id: UUID(),
            targetDeviceID: device.id,
            name: "Backup",
            kind: .script,
            iconSystemName: "terminal",
            enabled: true,
            allowsRemoteExecution: false,
            watchEligible: false,
            schemaVersion: AutoRunSchema.currentVersion,
            parameters: [],
            updatedAt: .now
        )
        let command = RemoteCommand(automationID: automation.id, sourceDeviceID: UUID(), targetDeviceID: device.id, parameters: ["unexpected": .string("x")])
        XCTAssertEqual(command.validationError(definition: automation, targetDevice: device), "Remote execution is disabled.")
    }

    func testRemoteCommandsFailClosedForForgedTarget() {
        let target = AutoRunDevice(displayName: "Mac", platform: .macOS, capabilities: [.executeScripts], appVersion: "1")
        let automation = AutomationDefinition(
            id: UUID(), targetDeviceID: target.id, name: "Backup", kind: .script,
            iconSystemName: "terminal", enabled: true, allowsRemoteExecution: true,
            watchEligible: false, schemaVersion: AutoRunSchema.currentVersion, parameters: [], updatedAt: .now
        )

        let forgedTarget = RemoteCommand(
            automationID: automation.id, sourceDeviceID: UUID(), targetDeviceID: UUID()
        )
        XCTAssertEqual(
            forgedTarget.validationError(definition: automation, targetDevice: target),
            "Target device is unavailable."
        )

        let valid = RemoteCommand(
            automationID: automation.id, sourceDeviceID: UUID(), targetDeviceID: target.id
        )
        var json = try! JSONSerialization.jsonObject(with: AutoRunJSON.encoder.encode(valid)) as! [String: Any]
        json["schemaVersion"] = 99
        let incompatible = try! AutoRunJSON.decoder.decode(
            RemoteCommand.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(
            incompatible.validationError(definition: automation, targetDevice: target),
            "Unsupported command version."
        )

        let source = AutoRunDevice(
            id: UUID(), displayName: "iPhone", platform: .iOS,
            capabilities: [.sendRemoteCommands], appVersion: "1"
        )
        let sourcedCommand = RemoteCommand(
            automationID: automation.id, sourceDeviceID: source.id, targetDeviceID: target.id
        )
        XCTAssertEqual(
            sourcedCommand.validationError(definition: automation, targetDevice: target, sourceDevice: source),
            "Command is not cryptographically authenticated."
        )
        var retiredSource = source
        retiredSource.isRetired = true
        XCTAssertEqual(
            sourcedCommand.validationError(definition: automation, targetDevice: target, sourceDevice: retiredSource),
            "Source device is unavailable."
        )
    }

    func testRequiredParameterAndChoiceValidation() {
        let definition = AutomationDefinition(
            id: UUID(), targetDeviceID: UUID(), name: "Deploy", kind: .script,
            iconSystemName: "terminal", enabled: true, allowsRemoteExecution: true,
            watchEligible: false, schemaVersion: 1,
            parameters: [AutomationParameterDefinition(
                id: "environment", title: "Environment", helpText: nil,
                type: .singleChoice, required: true, defaultValue: nil,
                choices: [AutomationChoice(id: "prod", label: "Production")],
                persistedOnCompanion: false, minimum: nil, maximum: nil, maxLength: nil
            )], updatedAt: .now
        )
        XCTAssertEqual(definition.validate(parameters: [:]), ["Missing parameter: Environment"])
        XCTAssertEqual(definition.validate(parameters: ["environment": .string("staging")]), ["Invalid choice for Environment."])
        XCTAssertTrue(definition.validate(parameters: ["environment": .string("prod")]).isEmpty)
    }

    func testCommandExpiryAndSessionEventOutputAreBounded() {
        let now = Date(timeIntervalSince1970: 100)
        let command = RemoteCommand(automationID: UUID(), sourceDeviceID: UUID(), targetDeviceID: UUID(), createdAt: now, expiresAt: now.addingTimeInterval(1))
        XCTAssertEqual(command.validationError(now: now.addingTimeInterval(2), definition: nil, targetDevice: nil), "Command expired.")

        let event = SessionEvent(sessionID: UUID(), sequence: 1, kind: .stdout, text: String(repeating: "x", count: AutoRunSchema.maximumSessionEventText + 10))
        XCTAssertEqual(event.text?.count, AutoRunSchema.maximumSessionEventText)
    }

    func testCodableRoundTripPreservesRemoteCommand() throws {
        let command = RemoteCommand(automationID: UUID(), sourceDeviceID: UUID(), targetDeviceID: UUID(), parameters: ["enabled": .boolean(true)])
        let data = try AutoRunJSON.encoder.encode(command)
        let decoded = try AutoRunJSON.decoder.decode(RemoteCommand.self, from: data)
        XCTAssertEqual(decoded.id, command.id)
        XCTAssertEqual(decoded.automationID, command.automationID)
        XCTAssertEqual(decoded.sourceDeviceID, command.sourceDeviceID)
        XCTAssertEqual(decoded.targetDeviceID, command.targetDeviceID)
        XCTAssertEqual(decoded.parameters, command.parameters)
        XCTAssertEqual(decoded.state, command.state)
        XCTAssertEqual(decoded.claimedAt, command.claimedAt)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, command.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970, command.expiresAt.timeIntervalSince1970, accuracy: 0.001)
    }

    #if os(macOS)
    func testExistingTimerDataDefaultsNewRemotePermissionsToOff() throws {
        let oldRecord: [String: Any] = [
            "creationDate": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 10)),
            "name": "Existing timer",
            "active": true,
            "launchItem": "file:///Applications/Calculator.app",
            "launchType": 0,
            "interval": 30,
            "doesRepeat": true,
            "order": 4
        ]
        let data = try JSONSerialization.data(withJSONObject: oldRecord)
        let timer = try AutoRunJSON.decoder.decode(TimerItem.self, from: data)
        XCTAssertTrue(timer.isEnabled)
        XCTAssertEqual(timer.name, "Existing timer")
        XCTAssertEqual(timer.interval, 30)
        XCTAssertTrue(timer.doesRepeat)
        XCTAssertFalse(timer.allowsRemoteExecution)
        XCTAssertFalse(timer.watchEligible)
        let restored = try AutoRunJSON.decoder.decode(TimerItem.self, from: AutoRunJSON.encoder.encode(timer))
        XCTAssertEqual(restored.remoteID, timer.remoteID)
    }

    func testScriptProtocolIgnoresOrdinaryOutputAndParsesStrictEnvelope() {
        XCTAssertNil(ScriptProtocolParser.parse(line: "AUTORUN:1 not-json"))
        XCTAssertNil(ScriptProtocolParser.parse(line: "ordinary output"))
        let line = "AUTORUN:1 {\"kind\":\"progress\",\"payload\":{\"value\":0.5}}"
        XCTAssertEqual(ScriptProtocolParser.parse(line: line)?.kind, .progress)
    }
    #endif
}

private final class TestDeviceGrantPersistence: DeviceGrantPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func load() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func save(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        self.data = data
    }
}
