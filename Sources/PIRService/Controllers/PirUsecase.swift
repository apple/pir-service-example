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
import HomomorphicEncryptionProtobuf
import Hummingbird
import PrivateInformationRetrieval
import PrivateInformationRetrievalProtobuf
import Util

enum LoadingError: Error {
    case invalidParameters(shard: String, got: String, expected: String)
}

extension LoadingError {
    static func invalidParameters<Scheme: HeScheme>(
        shard: String,
        got: EncryptionParameters<Scheme>,
        expected: EncryptionParameters<Scheme>) -> Self
    {
        .invalidParameters(shard: shard, got: got.description, expected: expected.description)
    }
}

enum SymmetricPirError: Error, Codable, Hashable {
    case symmetricPirNotConfigured
}

extension SymmetricPirError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .symmetricPirNotConfigured:
            "SymmetricPIR not configured."
        }
    }
}

struct PirUsecase<PirScheme: IndexPirServer>: Usecase {
    typealias Scheme = PirScheme.Scheme
    let context: Context<Scheme>
    let keywordParams: KeywordPirParameter
    let shards: [KeywordPirServer<PirScheme>]
    let symmetricPirConfig: SymmetricPirConfig?

    init(
        context: Context<Scheme>,
        keywordParams: KeywordPirParameter,
        shards: [KeywordPirServer<PirScheme>],
        symmetricPirConfig: SymmetricPirConfig? = nil)
    {
        self.context = context
        self.keywordParams = keywordParams
        self.shards = shards
        self.symmetricPirConfig = symmetricPirConfig
    }

    init(usecase: ServerConfiguration.Usecase) throws {
        let parameterPath = "\(usecase.fileStem)-0.params.txtpb"
        let params = try Apple_SwiftHomomorphicEncryption_Pir_V1_PirParameters(from: parameterPath)
        let encryptionParams: EncryptionParameters<Scheme> = try params.encryptionParameters.native()
        let context: Context<Scheme> = try Context(encryptionParameters: encryptionParams)
        self.context = context
        self.keywordParams = try params.keywordPirParams.nativeWithSymmetricPirClientConfig()
        self.symmetricPirConfig = try usecase.symmetricPirArguments?.resolve()
        self.shards = try (0..<usecase.shardCount).map { shardIndex in
            let parameterPath = "\(usecase.fileStem)-\(shardIndex).params.txtpb"
            let databasePath = "\(usecase.fileStem)-\(shardIndex).bin"
            let pirParams = try Apple_SwiftHomomorphicEncryption_Pir_V1_PirParameters(from: parameterPath)
            let encryptionParams: EncryptionParameters<Scheme> = try pirParams.encryptionParameters.native()
            guard encryptionParams == context.encryptionParameters else {
                throw LoadingError.invalidParameters(
                    shard: parameterPath,
                    got: encryptionParams,
                    expected: context.encryptionParameters)
            }

            let database = try ProcessedDatabase(from: databasePath, context: context)
            let processed = try ProcessedDatabaseWithParameters(
                database: database,
                algorithm: pirParams.algorithm.native(),
                evaluationKeyConfig: pirParams.evaluationKeyConfig.native(),
                pirParameter: pirParams.native(),
                keywordPirParameter: pirParams.keywordPirParams.nativeWithSymmetricPirClientConfig())
            return try KeywordPirServer(context: context, processed: processed)
        }
    }

    @_specialize(where PirScheme == MulPirServer<Bfv<UInt32>>)
    @_specialize(where PirScheme == MulPirServer<Bfv<UInt64>>)
    func process(
        request: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Request,
        evaluationKey: Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey) async throws
        -> Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Response
    {
        let pirRequest = request.pirRequest
        guard !pirRequest.hasShardID else {
            throw HTTPError(.notImplemented, message: "overloading shard index with ShardID is not supported")
        }
        let shard = shards[Int(pirRequest.shardIndex)]
        let query: KeywordPirServer<PirScheme>.Query = try pirRequest.query.native(context: context)
        let evaluationKey: EvaluationKey<Scheme> = try evaluationKey.evaluationKey.native(context: context)
        let response = try shard.computeResponse(to: query, using: evaluationKey)
        return try Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Response.with { apiResponse in
            apiResponse.pirResponse = try response.proto()
        }
    }

    func config() throws -> Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Config {
        var pirConfig = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig()
        pirConfig.encryptionParameters = try context.encryptionParameters.proto()
        guard let firstShard = shards.first else {
            throw HTTPError(.internalServerError, message: "Empty shards")
        }

        pirConfig.keywordPirParams = keywordParams.proto()
        pirConfig.algorithm = .mulPir
        pirConfig.batchSize = UInt64(firstShard.indexPirParameter.batchSize)
        pirConfig.evaluationKeyConfigHash = try evaluationKeyConfig().sha256()
        pirConfig.shardConfigs = shards.map { shard in
            shard.indexPirParameter.proto()
        }
        let allShardsSame = shards.count > 1 && shards.dropFirst().allSatisfy { shard in
            shard.indexPirParameter == firstShard.indexPirParameter
        }
        if allShardsSame {
            pirConfig.pirShardConfigs = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRShardConfigs
                .with { shardConfigs in
                    shardConfigs.repeatedShardConfig = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRFixedShardConfig
                        .with { fixedShardConfig in
                            fixedShardConfig.shardCount = UInt32(shards.count)
                            fixedShardConfig.shardConfig = firstShard.indexPirParameter.proto()
                        }
                }
            pirConfig.shardConfigs = []
        }

        return try Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Config.with { config in
            config.pirConfig = pirConfig
            config.configID = try pirConfig.sha256()
        }
    }

    func evaluationKeyConfig() throws -> Apple_SwiftHomomorphicEncryption_V1_EvaluationKeyConfig {
        try shards.map(\.evaluationKeyConfig).union().proto(encryptionParameters: context.encryptionParameters)
    }

    @_specialize(where PirScheme == MulPirServer<Bfv<UInt32>>)
    @_specialize(where PirScheme == MulPirServer<Bfv<UInt64>>)
    func processOprf(request: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_OPRFRequest) async throws ->
        Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Response
    {
        guard let symmetricPirConfig else {
            throw SymmetricPirError.symmetricPirNotConfigured
        }
        let oprfResponse = try OprfServer(symmetricPirConfig: symmetricPirConfig).computeResponse(
            query: request.native())
        return Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Response.with { apiResponse in
            apiResponse.oprfResponse = oprfResponse.proto()
        }
    }
}
