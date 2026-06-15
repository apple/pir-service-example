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
import HTTPTypes
import HummingbirdTesting
import PrivacyPass
import PrivateInformationRetrieval
import SwiftProtobuf
import Util

/// PIRClient useful for testing `PIRService`.
public struct PIRClient<PIRClient: IndexPirClient> {
    public typealias EvaluationKeyConfigHash = Data

    /// Configuration that will cached by the client.
    public struct Configuration: Hashable, Sendable {
        /// PIR configuration.
        public let config: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig
        /// Configuration identifier, typically a hash of the PIR configuration.
        public let configurationId: Data

        /// Iniitialize a new configuration.
        /// - Parameters:
        ///   - config: PIR configuration.
        ///   - configurationId: Configuration identifier, typically a hash of the PIR configuration.
        public init(config: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig, configurationId: Data) {
            self.config = config
            self.configurationId = configurationId
        }
    }

    /// Secret key that will be stored on the client.
    public struct StoredSecretKey {
        /// Secret key.
        public let secretKey: SerializedSecretKey
        /// Key generation timestamp, seconds from UNIX epoch.
        public let timestamp: UInt64

        /// Initialize a new stored secret key.
        /// - Parameters:
        ///   - secretKey: Secret key.
        ///   - timestamp: Key generation timestamp, seconds from UNIX epoch.
        public init(secretKey: SerializedSecretKey, timestamp: Date = Date.now) {
            self.secretKey = secretKey
            self.timestamp = UInt64(timestamp.timeIntervalSince1970)
        }
    }

    let connection: TestClientProtocol

    /// User identifier.
    public var userID = UUID()
    /// Platform the device is using.
    public var platform: Platform
    /// Configuration cache.
    public var configCache: [String: Configuration]
    /// Stored secret keys.
    public var secretKeys: [EvaluationKeyConfigHash: StoredSecretKey]
    /// Privacy pass tokens.
    public var tokens: [Token]
    /// User token for requesting privacy pass tokens.
    public var userToken: String?

    /// Initialize a new testing client.
    /// - Parameters:
    ///   - connection: Connection to the service under test.
    ///   - userID: User identifier.
    ///   - platform: Platform the device is using.
    ///   - configCache: Configuration cache.
    ///   - secretKeys: Stored secret keys.
    ///   - tokens: Privacy pass tokens.
    ///   - userToken: User token for requesting privacy pass tokens.
    public init(
        connection: TestClientProtocol,
        userID: UUID = UUID(),
        platform: Platform = .iOS18,
        configCache: [String: Configuration] = [:],
        secretKeys: [EvaluationKeyConfigHash: StoredSecretKey] = [:],
        tokens: [Token] = [],
        userToken: String? = nil)
    {
        self.connection = connection
        self.userID = userID
        self.platform = platform
        self.configCache = configCache
        self.secretKeys = secretKeys
        self.tokens = tokens
        self.userToken = userToken
    }

    /// Request a value from the service.
    ///
    /// When `allowKeyRotation` is `true`, this will also:
    /// - Fetch the configuration if there’s none.
    /// - Generate a new secret key and evaluation key and upload the evaluation key to the server if there’s none.
    /// - Parameters:
    ///   - keywords: Keywords to request values for.
    ///   - usecase: Name of the use case to query.
    ///   - allowKeyRotation: Allow fetching missing configuration and uploading a new evaluation key when needed.
    /// - Returns: An array with the same length as `keywords`, where each element is either the corresponding value or
    /// `nil` to indicate the absence of a value.
    public mutating func request(
        keywords: [KeywordValuePair.Keyword],
        usecase: String,
        allowKeyRotation: Bool = true) async throws -> [KeywordValuePair.Value?]
    {
        guard let configuration = configCache[usecase] else {
            if allowKeyRotation {
                try await rotateKey(for: usecase)
                return try await request(keywords: keywords, usecase: usecase, allowKeyRotation: false)
            }
            throw PIRClientError.missingConfiguration
        }

        let config = configuration.config
        guard let storedSecretKey = secretKeys[config.evaluationKeyConfigHash] else {
            if allowKeyRotation {
                try await rotateKey(for: usecase)
                return try await request(keywords: keywords, usecase: usecase, allowKeyRotation: false)
            }
            throw PIRClientError.missingSecretKey(evaluationKeyConfigHash: Array(config.evaluationKeyConfigHash))
        }

        let context = try Context<PIRClient.Scheme>(encryptionParameters: config.encryptionParameters.native())
        let secretKey = try SecretKey(deserialize: storedSecretKey.secretKey, context: context)

        let pirRequests: [Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRRequest] = try keywords.map { keyword in
            let client = try keywordPIRClient(for: keyword, config: config, context: context)
            let query = try client.generateQuery(at: keyword, using: secretKey)
            return try Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRRequest.with { pirRequest in
                pirRequest.shardIndex = try UInt32(config.shardIndex(for: keyword))
                pirRequest.query = try query.proto()
                pirRequest.evaluationKeyMetadata = .with { evaluationKeyMetadata in
                    evaluationKeyMetadata.timestamp = storedSecretKey.timestamp
                    evaluationKeyMetadata.identifier = config.evaluationKeyConfigHash
                }
                pirRequest.configurationHash = configuration.configurationId
            }
        }

        let requests = Apple_SwiftHomomorphicEncryption_Api_V1_Requests.with { requests in
            requests.requests = pirRequests.map { pirRequest in
                Apple_SwiftHomomorphicEncryption_Api_V1_Request.with { request in
                    request.usecase = usecase
                    request.pirRequest = pirRequest
                }
            }
        }

        let responses: Apple_SwiftHomomorphicEncryption_Api_V1_Responses = try await post(
            path: "/queries",
            body: requests)

        return try zip(keywords, responses.responses).map { keyword, response in
            let client = try keywordPIRClient(for: keyword, config: config, context: context)
            return try client.decrypt(
                response: response.pirResponse.native(context: context),
                at: keyword,
                using: secretKey)
        }
    }

    /// Request a value from the service for a Symmetric PIR usecase.
    ///
    /// When `allowKeyRotation` is `true`, this will also:
    /// - Fetch the configuration if there’s none.
    /// - Generate a new secret key and evaluation key and upload the evaluation key to the server if there’s none.
    /// - Parameters:
    ///   - keywords: Keywords to request values for.
    ///   - usecase: Name of the use case to query.
    ///   - allowKeyRotation: Allow fetching missing configuration and uploading a new evaluation key when needed.
    /// - Returns: An array with the same length as `keywords`, where each element is either the corresponding value or
    /// `nil` to indicate the absence of a value.
    public mutating func symmetricPirRequest(
        keywords: [KeywordValuePair.Keyword],
        usecase: String,
        allowKeyRotation: Bool = true) async throws -> [KeywordValuePair.Value?]
    {
        guard let configuration = configCache[usecase] else {
            if allowKeyRotation {
                try await rotateKey(for: usecase)
                return try await symmetricPirRequest(keywords: keywords, usecase: usecase, allowKeyRotation: false)
            }
            throw PIRClientError.missingConfiguration
        }
        let config = configuration.config
        let symmetricPirClientConfig = try config.keywordPirParams.symmetricPirClientConfig.native()
        let oprfClient = try OprfClient(symmetricPirClientConfig: symmetricPirClientConfig)
        let oprfQueryContexts: [OprfQueryContext] = try keywords.map { keyword in
            try oprfClient.queryContext(at: keyword)
        }
        let requests = Apple_SwiftHomomorphicEncryption_Api_V1_Requests.with { requests in
            requests.requests = oprfQueryContexts.map { queryContext in
                Apple_SwiftHomomorphicEncryption_Api_V1_Request.with { request in
                    request.usecase = usecase
                    request.oprfRequest = queryContext.query.proto()
                }
            }
        }
        let responses: Apple_SwiftHomomorphicEncryption_Api_V1_Responses = try await post(
            path: "/queries",
            body: requests)
        let parsedOprfResponses: [OprfClient.ParsedOprfOutput] = try zip(responses.responses, oprfQueryContexts)
            .map { response, queryContext in
                let oprfResponse = try response.oprfResponse.native()
                return try oprfClient.parse(oprfResponse: oprfResponse, with: queryContext)
            }
        let keywordPirResponses = try await request(
            keywords: parsedOprfResponses.map(\.obliviousKeyword),
            usecase: usecase,
            allowKeyRotation: allowKeyRotation)
        return try zip(keywordPirResponses, parsedOprfResponses).map { keywordPirResponse, oprfResponse in
            try keywordPirResponse.map { entry in
                try oprfClient.decrypt(encryptedEntry: entry, with: oprfResponse)
            }
        }
    }

    private func keywordPIRClient(
        for keyword: KeywordValuePair.Keyword,
        config: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig,
        context: Context<PIRClient.Scheme>) throws -> KeywordPirClient<PIRClient>
    {
        let shardIndex = try config.shardIndex(for: keyword)
        let shardConfig = config.shardConfig(shardIndex: shardIndex)
        let evaluationKeyConfig = EvaluationKeyConfig()
        return try KeywordPirClient<PIRClient>(
            keywordParameter: config.keywordPirParams.native(),
            pirParameter: shardConfig.native(
                batchSize: Int(config.batchSize),
                evaluationKeyConfig: evaluationKeyConfig),
            context: context)
    }

    mutating func post<Response: Message>(path: String, body: some Message) async throws -> Response {
        var headers: HTTPFields = [
            .userIdentifier: userID.uuidString,
            .userAgent: platform.exampleUserAgent,
        ]
        if userToken != nil {
            if tokens.isEmpty {
                // Note: actual device behaviour is more complex than just fetching 4 tokens.
                // Device implementation is subject to change, but as of iOS 18.0 the implementation is like this:
                // If there are no tokens, fetch 1 token plus 3 extra tokens.
                // If after using a token, there are fewer than 5 tokens left, schedule a background task to fetch
                // enough tokens to have 10 tokens cached. The backgound task should run in `5 + random(in: 0…60)`
                // seconds.
                // Tokens cached for more than 24 hours are considered expired and removed from the cache.
                try await fetchTokens(count: 4)
            }

            let token = tokens.removeFirst()
            headers[.authorization] = "PrivateToken token=\(token.bytes().base64URLEncodedString())"
        }
        return try await connection.post(path: path, body: body, headers: headers)
    }
}
