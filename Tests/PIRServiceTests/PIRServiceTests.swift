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
import HomomorphicEncryption
import Hummingbird
@testable import PIRService
@testable import PIRServiceTesting
import PrivateInformationRetrieval
import Testing
import Util

@Suite
struct PIRServiceTests {
    @Test
    func testRequest() async throws {
        let usecaseStore = UsecaseStore()
        try await usecaseStore.set(name: "test", usecase: ExampleUsecase.hundred)
        let app = try await buildApplication(usecaseStore: usecaseStore)
        try await app.test(.live) { client in
            var pirClient = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: client)
            let result = try await pirClient.request(keyword: "23")
            #expect(result == "23")
        }
    }

    @Test
    func testSymmetricPirRequest() async throws {
        let usecaseStore = UsecaseStore()
        try await usecaseStore.set(name: "test", usecase: ExampleUsecase.symmetric)
        let app = try await buildApplication(usecaseStore: usecaseStore)
        try await app.test(.live) { client in
            var pirClient = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: client)
            let keywords: [KeywordValuePair.Keyword] = [.init("23".utf8), .init("27".utf8)]
            let result = try await pirClient.symmetricPirRequest(keywords: keywords, usecase: "test")
            // Values are same as keywords in this usecase.
            #expect(result == keywords)
        }
    }

    @Test
    func requestWithPrivacyPass() async throws {
        let usecaseStore = UsecaseStore()
        try await usecaseStore.set(name: "test", usecase: ExampleUsecase.hundred)
        let userAuthenticator = UserAuthenticator()
        await userAuthenticator.add(token: "ABCD", tier: .tier1)
        let privacyPassState = try PrivacyPassState(userAuthenticator: userAuthenticator)
        let app = try await buildApplication(usecaseStore: usecaseStore, privacyPassState: privacyPassState)
        try await app.test(.live) { client in
            var pirClient = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: client, userToken: "ABCD")
            let result = try await pirClient.request(keyword: "23")
            #expect(result == "23")
        }
    }

    @Test
    func routingToDifferentVersion() async throws {
        let usecaseStore = UsecaseStore()
        // make sure that the configs for these two are different
        #expect(try ExampleUsecase.ten.config() != (ExampleUsecase.hundred.config()))
        try await usecaseStore.set(name: "test", usecase: ExampleUsecase.hundred)
        let app = try await buildApplication(usecaseStore: usecaseStore)
        try await app.test(.live) { client in
            // make a request
            var clientWithOldConfig = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: client)
            var result = try await clientWithOldConfig.request(keyword: "23")
            #expect(result == "23")

            // update the usecase to only have 10 keywords
            try await usecaseStore.set(name: "test", usecase: ExampleUsecase.ten)

            // new client will not get a result for keyword "23"
            var newClient = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: client)
            result = try await newClient.request(keyword: "23")
            #expect(result == nil)

            // Request with the old configuration is correctly routed to the previous version.
            result = try await clientWithOldConfig.request(keyword: "23")
            #expect(result == "23")

            // update the usecase again, this time dropping the previous version.
            try await usecaseStore.set(name: "test", usecase: ExampleUsecase.ten, versionCount: 1)

            // request with the old configuration now throws an error
            await #expect { try await clientWithOldConfig.request(keyword: "1") }
                throws: { error in
                    if let error = error as? PIRClientError,
                       case let .serverError(status, _) = error
                    {
                        return status == .gone
                    }
                    return false
                }
        }
    }

    @Test
    func addingAndRemovingUserTokens() async throws {
        let usecaseStore = UsecaseStore()
        try await usecaseStore.set(name: "test", usecase: ExampleUsecase.hundred)
        let userAuthenticator = UserAuthenticator()
        let privacyPassState = try PrivacyPassState(userAuthenticator: userAuthenticator)
        let app = try await buildApplication(usecaseStore: usecaseStore, privacyPassState: privacyPassState)
        try await app.test(.live) { client in
            var pirClient = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: client, userToken: "ABCD")
            await #expect { try await pirClient.request(keyword: "23") }
                throws: { error in
                    if let error = error as? PIRClientError,
                       case let .failedToFetchTokenPublicKey(status, message) = error
                    {
                        return status == .unauthorized && message.contains("User token is unauthorized")
                    }
                    return false
                }

            // after adding the user token, the request should succeed
            await userAuthenticator.add(token: "ABCD", tier: .tier1)

            _ = try await pirClient.request(keyword: "42")

            // remove the user token
            await userAuthenticator.update(allowList: [:])

            // at least one more request should succeed because of cached tokens
            _ = try await pirClient.request(keyword: "42")

            await #expect {
                for _ in 0..<10 {
                    _ = try await pirClient.request(keyword: "this should eventually fail when tokens run out")
                }
            } throws: { error in
                if let error = error as? PIRClientError,
                   case let .failedToFetchTokenPublicKey(status, message) = error
                {
                    return status == .unauthorized && message.contains("User token is unauthorized")
                }
                return false
            }
        }
    }

    @Test
    func repeatedShardConfigs() async throws {
        let usecaseStore = UsecaseStore()
        try await usecaseStore.set(name: "test", usecase: ExampleUsecase.repeatedShardConfig)
        let app = try await buildApplication(usecaseStore: usecaseStore)
        for platform: Platform in [.macOS15, .macOS15_2, .iOS18, .iOS18_2] {
            try await app.test(.live) { client in
                var pirClient = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: client, platform: platform)
                var queriedShards: Set<Int> = []
                for index in [0, 1] {
                    let keyword = String(index)
                    let result = try await pirClient.request(keyword: keyword)
                    #expect(result == keyword)
                    let shardIndex = try #require(try pirClient.configCache["test"]?.config
                        .shardIndex(for: Array(keyword.utf8)))
                    queriedShards.insert(shardIndex)
                }
                #expect(queriedShards.count > 1)
            }
        }
    }

    @Test
    func pirConfigExtensions() throws {
        var config = try ExampleUsecase.repeatedShardConfig.config()
        #expect(config.pirConfig.shardConfigs.isEmpty)
        #expect(config.pirConfig.pirShardConfigs.repeatedShardConfig.shardCount == 5)
        let shard0Config = config.pirConfig.shardConfig(shardIndex: 0)
        #expect(config.pirConfig.shardCount == 5)

        try config.makeCompatible(with: .iOS18)
        #expect(config.pirConfig.shardConfigs.count == 5)
        #expect(config.pirConfig.shardConfigs == Array(repeating: shard0Config, count: 5))
        for shardIndex in 0..<5 {
            #expect(config.pirConfig.shardConfig(shardIndex: shardIndex) == shard0Config)
        }
        #expect(config.pirConfig.shardCount == 5)

        config.pirConfig.keywordPirParams.shardingFunction.function = .doubleMod(.with { doubleMod in
            doubleMod.otherShardCount = 5
        })

        #expect { try config.makeCompatible(with: .iOS18) } throws: { error in
            guard let error = error as? HTTPError else {
                return false
            }
            return error.status == .internalServerError && error.description
                .contains("does not support sharding functions other than SHA256")
        }

        #expect(throws: Never.self) { try config.makeCompatible(with: .iOS18_2) }
    }
}

extension PIRClient {
    mutating func request(keyword: String) async throws -> String? {
        let response = try await request(keywords: [.init(keyword.utf8)], usecase: "test")
        #expect(response.count == 1)
        return response[0].map { value in
            String(data: Data(value), encoding: .utf8) ?? "<\(value.count) bytes of binary response>"
        }
    }
}
