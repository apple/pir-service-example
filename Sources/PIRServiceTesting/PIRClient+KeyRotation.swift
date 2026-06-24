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

import ApplicationProtobuf
import Foundation
import HomomorphicEncryption
import PrivateInformationRetrieval
import SwiftProtobuf

extension PIRClient {
    mutating func fetchKeyStatus(for usecase: String) async throws
        -> Apple_SwiftHomomorphicEncryption_Api_Shared_V1_KeyStatus
    {
        let configRequest = Apple_SwiftHomomorphicEncryption_Api_V1_ConfigRequest.with { configRequest in
            configRequest.usecases = [usecase]
            configRequest.existingConfigIds = [configCache[usecase]?.configurationId ?? Data()]
        }

        let configResponse: Apple_SwiftHomomorphicEncryption_Api_V1_ConfigResponse = try await post(
            path: "/config",
            body: configRequest)
        guard let config = configResponse.configs[usecase] else {
            throw PIRClientError.missingConfiguration
        }
        configCache[usecase] = Configuration(config: config.pirConfig, configurationId: config.configID)

        guard let keyStatus = configResponse.keyInfo.first else {
            throw PIRClientError.missingKeyStatus
        }
        return keyStatus
    }

    mutating func rotateKey(for usecase: String) async throws {
        let keyStatus = try await fetchKeyStatus(for: usecase)
        guard let config = configCache[usecase]?.config else {
            throw PIRClientError.missingConfiguration
        }

        if let storedSecretKey = secretKeys[config.evaluationKeyConfigHash],
           storedSecretKey.timestamp == keyStatus.timestamp
        {
            // we do not need to rotate
            return
        }

        let context = try Context<PIRClient.Scheme>(encryptionParameters: config.encryptionParameters.native())
        let secretKey = try context.generateSecretKey()
        let storedSecretKey = StoredSecretKey(secretKey: secretKey.serialize())
        let evaluationKey = try context.generateEvaluationKey(config: keyStatus.keyConfig.native(), using: secretKey)
        secretKeys[config.evaluationKeyConfigHash] = storedSecretKey

        let evaluationKeyWithMetadata = Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey.with { evalKey in
            evalKey.metadata = .with { metadata in
                metadata.timestamp = storedSecretKey.timestamp
                metadata.identifier = config.evaluationKeyConfigHash
            }
            evalKey.evaluationKey = evaluationKey.serialize().proto()
        }

        try await uploadKey(evaluationKeyWithMetadata)
    }

    mutating func uploadKey(_ key: Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey) async throws {
        let keys = Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKeys.with { keyRequest in
            keyRequest.keys = [key]
        }

        let _: EmptyProtobufMessage = try await post(path: "/key", body: keys)
    }
}

/// Empty message
private struct EmptyProtobufMessage: Message {
    static let protoMessageName = "Empty"

    var unknownFields = SwiftProtobuf.UnknownStorage()

    static func == (lhs: EmptyProtobufMessage, rhs: EmptyProtobufMessage) -> Bool {
        if lhs.unknownFields != rhs.unknownFields {
            return false
        }
        return true
    }

    mutating func decodeMessage(decoder: inout some SwiftProtobuf.Decoder) throws {
        // Load everything into unknown fields
        while try decoder.nextFieldNumber() != nil {}
    }

    func traverse(visitor: inout some SwiftProtobuf.Visitor) throws {
        try unknownFields.traverse(visitor: &visitor)
    }

    func isEqualTo(message: any SwiftProtobuf.Message) -> Bool {
        guard let other = message as? EmptyProtobufMessage else {
            return false
        }
        return self == other
    }
}
