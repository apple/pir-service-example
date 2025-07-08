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

import _CryptoExtras
import Crypto
import HomomorphicEncryption
@testable import PIRService
import PrivateInformationRetrieval

enum ExampleUsecase {
    /// Usecase where there are keys in the range `0..<10` and the values are equal to keys.
    static let ten: Usecase = // swiftlint:disable:next force_try
        try! buildExampleUsecase(count: 10)

    /// Usecase where there are keys in the range `0..<100` and the values are equal to keys.
    static let hundred: Usecase = // swiftlint:disable:next force_try
        try! buildExampleUsecase(count: 100)

    /// Usecase where there are keys in the range `0..<100` and the values are equal to keys.
    /// Each shard configuration is the same
    static let repeatedShardConfig: Usecase = // swiftlint:disable:next force_try
        try! buildRepeatedShardConfigsUsecase(count: 100)

    /// Symmetric PIR Usecase where there are keys in the range `0..<100` and the values are equal to keys.
    static let symmetric: Usecase = // swiftlint:disable:next force_try
        try! buildExampleUsecase(count: 100, forSymmetricPir: true)

    private static func buildExampleUsecase(count: Int, forSymmetricPir: Bool = false) throws -> Usecase {
        typealias ServerType = KeywordPirServer<MulPirServer<Bfv<UInt32>>>
        var databaseRows = (0..<count)
            .map { KeywordValuePair(keyword: [UInt8](String($0).utf8), value: [UInt8](String($0).utf8)) }
        let context: Context<ServerType.Scheme> =
            try .init(encryptionParameters: .init(from: .n_4096_logq_27_28_28_logt_4))
        var symmetricPirConfig: SymmetricPirConfig?
        if forSymmetricPir {
            let secretKey = [UInt8](P384._VOPRF.PrivateKey().rawRepresentation)
            symmetricPirConfig = try SymmetricPirConfig(
                oprfSecretKey: Secret(value: secretKey), configType: .OPRF_P384_AES_GCM_192_NONCE_96_TAG_128)
            // swiftlint:disable:next force_unwrapping
            databaseRows = try KeywordDatabase.symmetricPIRProcess(database: databaseRows, config: symmetricPirConfig!)
        }
        let config = try KeywordPirConfig(
            dimensionCount: 2,
            cuckooTableConfig: .defaultKeywordPir(maxSerializedBucketSize: context.bytesPerPlaintext),
            unevenDimensions: false, keyCompression: .noCompression,
            symmetricPirClientConfig: symmetricPirConfig?.clientConfig())
        let processed = try ServerType.process(
            database: databaseRows,
            config: config,
            with: context,
            symmetricPirConfig: symmetricPirConfig)
        let shard = try ServerType(context: context, processed: processed)
        return PirUsecase(
            context: context,
            keywordParams: config.parameter,
            shards: [shard],
            symmetricPirConfig: symmetricPirConfig)
    }

    private static func buildRepeatedShardConfigsUsecase(count: Int) throws -> Usecase {
        typealias ServerType = KeywordPirServer<MulPirServer<Bfv<UInt32>>>

        let context: Context<ServerType.Scheme> =
            try .init(encryptionParameters: .init(from: .n_4096_logq_27_28_28_logt_4))
        let cuckooTableConfig = try CuckooTableConfig(
            hashFunctionCount: 2,
            maxEvictionCount: 100,
            maxSerializedBucketSize: context.bytesPerPlaintext,
            bucketCount: .fixedSize(bucketCount: 10))
        let config = try KeywordPirConfig(
            dimensionCount: 2,
            cuckooTableConfig: cuckooTableConfig,
            unevenDimensions: false, keyCompression: .noCompression)

        let databaseRows = (0..<count)
            .map { KeywordValuePair(keyword: [UInt8](String($0).utf8), value: [UInt8](String($0).utf8)) }
        let database = try KeywordDatabase(rows: databaseRows, sharding: .shardCount(5))
        let shards = try database.shards.values.map { _ in
            let processed = try ServerType.process(
                database: databaseRows,
                config: config,
                with: context)
            return try ServerType(context: context, processed: processed)
        }
        let indexPirParameter = shards[0].indexPirParameter
        precondition(shards.allSatisfy { $0.indexPirParameter == indexPirParameter })

        return PirUsecase(context: context, keywordParams: config.parameter, shards: shards)
    }
}
