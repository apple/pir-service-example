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
import HomomorphicEncryptionProtobuf
import Hummingbird
import HummingbirdTesting
@testable import PIRService
import PrivateInformationRetrieval
import Testing
import Util

@Suite
struct PIRServiceControllerTests {
    // Error message returned by Hummingbird
    struct ErrorMessage: Codable {
        // swiftlint:disable:next nesting
        struct Details: Codable {
            let message: String
        }

        let error: Details
    }

    @Test
    func noUserIdentifier() async throws {
        let app = try await buildApplication()
        try await app.test(.live) { client in
            try await client.execute(uri: "/key", method: .post) { response in
                let errorMessage = try JSONDecoder().decode(ErrorMessage.self, from: response.body)
                #expect(errorMessage.error.message == "Missing 'User-Identifier' header")
            }
        }
    }

    @Test
    func keyUpload() async throws {
        let evaluationKeyStore = MemoryPersistDriver()
        let app = try await buildApplication(evaluationKeyStore: evaluationKeyStore)
        let user = UserIdentifier()

        let evalKeyMetadata = Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKeyMetadata.with { metadata in
            metadata.timestamp = UInt64(Date.now.timeIntervalSince1970)
            metadata.identifier = Data("test".utf8)
        }
        let evalKey = Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey.with { evalKey in
            evalKey.metadata = evalKeyMetadata
            evalKey.evaluationKey = Apple_SwiftHomomorphicEncryption_V1_SerializedEvaluationKey()
        }
        let evaluationKeys = Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKeys.with { evalKeys in
            evalKeys.keys = [evalKey]
        }
        try await app.test(.live) { client in
            try await client.execute(uri: "/key", userIdentifier: user, message: evaluationKeys) { response in
                #expect(response.status == .ok)
            }

            // make sure the evaluation key was persisted
            let persistKey = PIRServiceController.persistKey(user: user, configHash: evalKeyMetadata.identifier)
            let storedKey = try await evaluationKeyStore.get(
                key: persistKey,
                as: Protobuf<Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey>.self)
            #expect(storedKey?.message == evalKey)
        }
    }

    @Test
    func configFetch() async throws {
        let usecaseStore = UsecaseStore()
        let exampleUsecase = ExampleUsecase.hundred
        try await usecaseStore.set(name: "test", usecase: exampleUsecase)
        let app = try await buildApplication(usecaseStore: usecaseStore)
        let user = UserIdentifier()

        let configRequest = Apple_SwiftHomomorphicEncryption_Api_V1_ConfigRequest.with { configReq in
            configReq.usecases = ["test"]
        }
        try await app.test(.live) { client in
            try await client.execute(uri: "/config", userIdentifier: user, message: configRequest) { response in
                #expect(response.status == .ok)
                let configResponse = try response
                    .message(as: Apple_SwiftHomomorphicEncryption_Api_V1_ConfigResponse.self)
                #expect(try configResponse.configs["test"] == exampleUsecase.config())
                #expect(try configResponse.keyInfo[0].keyConfig == exampleUsecase.evaluationKeyConfig())
            }
        }
    }

    @Test
    func cachedConfigFetch() async throws {
        let usecaseStore = UsecaseStore()
        let exampleUsecase = ExampleUsecase.repeatedShardConfig
        try await usecaseStore.set(name: "test", usecase: exampleUsecase)
        let app = try await buildApplication(usecaseStore: usecaseStore)
        let user = UserIdentifier()

        try await app.test(.live) { client in // swiftlint:disable:this closure_body_length
            for platform: Platform in [.macOS15, .macOS15_2, .iOS18, .iOS18_2] {
                // No or wrong existing configId
                for existingConfigId in [Data(), Data([UInt8(1), 2])] {
                    let configRequest = Apple_SwiftHomomorphicEncryption_Api_V1_ConfigRequest.with { configReq in
                        configReq.usecases = ["test"]
                        configReq.existingConfigIds = [existingConfigId]
                    }
                    try await client.execute(
                        uri: "/config",
                        userIdentifier: user,
                        message: configRequest,
                        platform: platform)
                    { response in
                        #expect(response.status == .ok)
                        var expectedConfig = try exampleUsecase.config()
                        try expectedConfig.makeCompatible(with: platform)
                        let configResponse = try response
                            .message(as: Apple_SwiftHomomorphicEncryption_Api_V1_ConfigResponse.self)
                        #expect(configResponse.configs["test"] == expectedConfig)
                        #expect(try configResponse.keyInfo[0].keyConfig == exampleUsecase.evaluationKeyConfig())
                    }
                }
                // Existing configId
                let configRequestWithConfigId = try Apple_SwiftHomomorphicEncryption_Api_V1_ConfigRequest
                    .with { configReq in
                        configReq.usecases = ["test"]
                        configReq.existingConfigIds = try [exampleUsecase.config().configID]
                    }
                try await client.execute(
                    uri: "/config",
                    userIdentifier: user,
                    message: configRequestWithConfigId,
                    platform: platform)
                { response in
                    #expect(response.status == .ok)
                    let configResponse = try response
                        .message(as: Apple_SwiftHomomorphicEncryption_Api_V1_ConfigResponse.self)
                    #expect(configResponse.configs["test"]?.reuseExistingConfig == true)
                    #expect(configResponse.configs["test"]?.pirConfig ==
                        Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig())
                    #expect(try configResponse.keyInfo[0].keyConfig == exampleUsecase.evaluationKeyConfig())
                }
            }
        }
    }

    @Test
    func compressedConfigFetch() async throws {
        // Mock usecase that has a large config with 10K randomized shardConfigs.
        struct TestUseCaseWithLargeConfig: Usecase {
            let randomConfig: Apple_SwiftHomomorphicEncryption_Api_V1_Config

            init() throws {
                let shardConfigs = (0..<10000).map { _ in
                    Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRShardConfig.with { shardConfig in
                        shardConfig.numEntries = UInt64.random(in: 0..<1000)
                        shardConfig.entrySize = UInt64.random(in: 0..<1000)
                        shardConfig.dimensions = [UInt64.random(in: 0..<100), UInt64.random(in: 0..<100)]
                    }
                }

                let pirConfg = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig.with { pirConfig in
                    pirConfig.shardConfigs = shardConfigs
                }
                self.randomConfig = try Apple_SwiftHomomorphicEncryption_Api_V1_Config.with { config in
                    config.pirConfig = pirConfg
                    config.configID = try pirConfg.sha256()
                }
            }

            func config() throws -> Apple_SwiftHomomorphicEncryption_Api_V1_Config {
                randomConfig
            }

            func evaluationKeyConfig() throws -> Apple_SwiftHomomorphicEncryption_V1_EvaluationKeyConfig {
                Apple_SwiftHomomorphicEncryption_V1_EvaluationKeyConfig()
            }

            func process(
                request _: Apple_SwiftHomomorphicEncryption_Api_V1_Request,
                evaluationKey _: Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey) async throws
                -> Apple_SwiftHomomorphicEncryption_Api_V1_Response
            {
                Apple_SwiftHomomorphicEncryption_Api_V1_Response()
            }

            func processOprf(request _: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_OPRFRequest) async throws
                -> Apple_SwiftHomomorphicEncryption_Api_V1_Response
            {
                Apple_SwiftHomomorphicEncryption_Api_V1_Response()
            }
        }

        let usecaseStore = UsecaseStore()
        let exampleUsecase = try TestUseCaseWithLargeConfig()
        try await usecaseStore.set(name: "test", usecase: exampleUsecase)

        let app = try await buildApplication(usecaseStore: usecaseStore)
        let user = UserIdentifier()

        let configRequest = Apple_SwiftHomomorphicEncryption_Api_V1_ConfigRequest.with { configReq in
            configReq.usecases = ["test"]
        }

        let uncompressedConfigSize = try exampleUsecase.randomConfig.serializedData().count
        try await app.test(.live) { client in
            try await client.execute(
                uri: "/config",
                userIdentifier: user,
                message: configRequest,
                acceptCompression: true)
            { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentEncoding] == "gzip")
                #expect(response.headers[.transferEncoding] == "chunked")
                var compressedBody = response.body
                #expect(compressedBody.readableBytes < uncompressedConfigSize)
                let uncompressed = try compressedBody.decompress(with: .gzip())
                let configResponse = try Apple_SwiftHomomorphicEncryption_Api_V1_ConfigResponse(
                    serializedBytes: Array(buffer: uncompressed))
                #expect(try configResponse.configs["test"] == exampleUsecase.config())
            }
        }
    }

    @Test
    func configFetchWithUnknownUsecase() async throws {
        let usecaseStore = UsecaseStore()
        let exampleUsecase = ExampleUsecase.hundred
        try await usecaseStore.set(name: "test", usecase: exampleUsecase)
        let app = try await buildApplication(usecaseStore: usecaseStore)
        let user = UserIdentifier()

        let configRequest = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_ConfigRequest.with { configReq in
            configReq.usecases = ["other"]
        }
        try await app.test(.live) { client in
            try await client.execute(uri: "/config", userIdentifier: user, message: configRequest) { response in
                #expect(response.status == .notFound)
                let errorMessage = try JSONDecoder().decode(ErrorMessage.self, from: response.body)
                #expect(errorMessage.error.message == """
                    One or more usecases not found. Requested usecases: ["other"].
                    Usecases available on the server: ["test"].
                    """)
            }
        }
    }
}
