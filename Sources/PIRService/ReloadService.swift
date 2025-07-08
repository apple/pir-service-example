// Copyright 2024-2025 Apple Inc. and the Swift Homomorphic Encryption project authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Logging
import PrivateInformationRetrieval
import ServiceLifecycle
import UnixSignals

struct SymmetricPirArguments: Codable, Hashable {
    /// Error encountered on resolving SymmetricPirArguments.
    struct ValidationError: Error {
        let message: String
    }

    /// File path for key with which database will be encrypted.
    ///
    /// This is required, but is an Optional to allow for clearer error message.
    let databaseEncryptionKeyFilePath: String?
    /// Config for Symmetric PIR.
    let configType: SymmetricPirConfigType?

    func resolve() throws -> SymmetricPirConfig {
        guard let databaseEncryptionKeyFilePath else {
            throw ValidationError(message: "'databaseEncryptionKeyFilePath' is missing in symmetric PIR configuration.")
        }
        let secretKeyString = try String(contentsOfFile: databaseEncryptionKeyFilePath, encoding: .utf8)
        guard let secretKey = Array(hexEncoded: secretKeyString) else {
            throw ValidationError(message: "Invalid OPRF key.")
        }
        let configType = configType ?? .OPRF_P384_AES_GCM_192_NONCE_96_TAG_128
        return try SymmetricPirConfig(oprfSecretKey: Secret(value: secretKey), configType: configType)
    }
}

struct ServerConfiguration: Codable {
    struct Usecase: Codable {
        let name: String
        let fileStem: String
        let shardCount: Int
        let versionCount: Int?
        let symmetricPirArguments: SymmetricPirArguments?
    }

    struct UserGroup: Codable {
        let tier: UserTier
        let tokens: [String]
    }

    let issuerRequestUri: String?
    let users: [UserGroup]
    let usecases: [Usecase]
}

actor ReloadService: Service {
    let configFile: URL
    let usecaseStore: UsecaseStore
    let privacyPassState: PrivacyPassState<UserAuthenticator>
    let logger: Logger

    init(
        configFile: URL,
        usecaseStore: UsecaseStore,
        privacyPassState: PrivacyPassState<UserAuthenticator>,
        logger: Logger)
    {
        self.configFile = configFile
        self.usecaseStore = usecaseStore
        self.privacyPassState = privacyPassState
        self.logger = logger
    }

    func run() async throws {
        let signalSequence = await UnixSignalsSequence(trapping: .sighup)
        for await signal in signalSequence {
            guard signal == .sighup else {
                continue
            }

            logger.info("Reloading configuration...")
            do {
                try await reloadConfiguration()
                logger.info("Reloading configuration completed.")
            } catch {
                logger.error("Failed to reload configuration: \(error.localizedDescription).")
                logger.error("Service state might have been partially updated.")
            }
        }
    }

    func reloadConfiguration() async throws {
        let configData = try Data(contentsOf: configFile)
        let config = try JSONDecoder().decode(ServerConfiguration.self, from: configData)

        var allowedUsers: [String: UserTier] = [:]
        for userGroup in config.users {
            let tier = userGroup.tier
            for token in userGroup.tokens {
                if let existingTier = allowedUsers[token],
                   existingTier != tier
                {
                    logger.warning("""
                        User token '\(token)' is assigned to multiple tiers '\(existingTier)' \
                        and '\(tier)', using the latter.
                        """)
                }
                allowedUsers[token] = tier
            }
        }
        await privacyPassState.userAuthenticator.update(allowList: allowedUsers)

        for usecase in config.usecases {
            // default to two versions
            let versionCount = usecase.versionCount ?? 2
            if versionCount == 0 {
                // special case, remove all versions
                try await usecaseStore.set(name: usecase.name, usecase: nil, versionCount: versionCount)
                return
            }
            let loaded = try loadUsecase(usecase: usecase)
            try await usecaseStore.set(name: usecase.name, usecase: loaded, versionCount: versionCount)
        }
    }
}
