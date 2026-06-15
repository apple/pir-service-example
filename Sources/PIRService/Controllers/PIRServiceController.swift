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
import HomomorphicEncryptionProtobuf
import Hummingbird
import HummingbirdCompression
import Util

struct PIRServiceController {
    let usecases: UsecaseStore
    let evaluationKeyStore: PersistDriver

    static func persistKey(user: UserIdentifier, configHash: Data) -> String {
        "\(user.identifier)/\(configHash.base64EncodedString())"
    }

    func addRoutes(to group: RouterGroup<AppContext>) {
        group.add(middleware: ExtractUserIdentifierMiddleware())
            .add(middleware: ExtractPlatformMiddleware())
            .post("/key", use: key)
            .post("/queries", use: queries)
            // only `config` uses response compression, since the key and queries are not compressible.
            .add(middleware: ResponseCompressionMiddleware())
            .post("/config", use: config)
    }

    @Sendable
    func key(_ request: Request, context: AppContext) async throws -> Response {
        let evaluationKeys = try await request.decodeProto(
            as: Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKeys.self,
            context: context)
        for evaluationKey in evaluationKeys.keys {
            guard evaluationKey.hasMetadata, evaluationKey.hasEvaluationKey else {
                throw HTTPError(.badRequest, message: "Evaluation key has unset fields")
            }

            let key = Self.persistKey(user: context.userIdentifier, configHash: evaluationKey.metadata.identifier)
            try await evaluationKeyStore.set(key: key, value: Protobuf(evaluationKey))
        }
        return .init(status: .ok)
    }

    @Sendable
    func config(_ request: Request, context: AppContext) async throws -> some ResponseGenerator {
        context.logger.info("Tier = \(context.userTier)")
        let configRequest = try await request.decodeProto(
            as: Apple_SwiftHomomorphicEncryption_Api_V1_ConfigRequest.self,
            context: context)
        let requestedUsecases = if configRequest.usecases.isEmpty {
            await usecases.getAll()
        } else {
            await usecases.get(names: configRequest.usecases)
        }

        guard configRequest.existingConfigIds.isEmpty ||
            configRequest.existingConfigIds.count == configRequest.usecases.count
        else {
            throw HTTPError(.badRequest, message: """
                Invalid existingConfigIds count \(configRequest.existingConfigIds.count). \
                Expected 0 or \(configRequest.usecases.count).
                """)
        }

        guard configRequest.usecases.isEmpty ||
            configRequest.usecases.count == requestedUsecases.count
        else {
            throw await HTTPError(.notFound, message: """
                One or more usecases not found. Requested usecases: \(configRequest.usecases).
                Usecases available on the server: \(usecases.getAll().keys).
                """)
        }

        let existingConfigIds = configRequest.existingConfigIds.isEmpty ? Array(
            repeating: Data(),
            count: requestedUsecases.count) : configRequest.existingConfigIds
        var configs = [String: Apple_SwiftHomomorphicEncryption_Api_V1_Config]()
        for (usecaseName, configId) in zip(requestedUsecases.keys, existingConfigIds) {
            if let usecase = requestedUsecases[usecaseName] {
                var config = try usecase.config(existingConfigId: Array(configId))
                if let platform = context.platform {
                    try config.makeCompatible(with: platform)
                }
                configs[usecaseName] = config
            }
        }

        let keyConfigs = try requestedUsecases.values.map { try $0.evaluationKeyConfig() }
        let keyStatusesSequence = keyConfigs.async.map { keyConfig in
            let keyConfigHash = try keyConfig.sha256()
            let key = Self.persistKey(user: context.userIdentifier, configHash: keyConfigHash)
            let storedEvaluationKey = try await evaluationKeyStore.get(
                key: key,
                as: Protobuf<Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey>.self)
            return Apple_SwiftHomomorphicEncryption_Api_Shared_V1_KeyStatus.with { keyStatus in
                // A timestamp of 0 indicates the evaluation key does not exist on the server
                keyStatus.timestamp = storedEvaluationKey?.message.metadata.timestamp ?? 0
                keyStatus.keyConfig = keyConfig
            }
        }

        let keyStatuses: [Apple_SwiftHomomorphicEncryption_Api_Shared_V1_KeyStatus] =
            try await .init(keyStatusesSequence)
        return Protobuf(Apple_SwiftHomomorphicEncryption_Api_V1_ConfigResponse.with { configResponse in
            configResponse.configs = configs
            configResponse.keyInfo = keyStatuses
        })
    }

    @Sendable
    func queries(_ request: Request, context: AppContext) async throws -> some ResponseGenerator {
        let startTime = Date.now
        let requests = try await request.decodeProto(
            as: Apple_SwiftHomomorphicEncryption_Api_V1_Requests.self,
            context: context)

        defer {
            let duration = Date.now.timeIntervalSince(startTime)
            context.logger.info("usecase=\(requests.requests.map(\.usecase)), duration=\(duration * 1000)ms")
        }

        let responsesSequence = requests.requests.async.map { request in
            switch request.request {
            case let .oprfRequest(oprfRequest):
                guard let usecase = await usecases.get(name: request.usecase) else {
                    throw HTTPError(.badRequest, message: "Unknown usecase: \(request.usecase)")
                }
                return try await usecase.processOprf(request: oprfRequest)
            case .pirRequest:
                var evaluationKey: Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey?
                if request.pirRequest.hasEvaluationKey {
                    evaluationKey = request.pirRequest.evaluationKey
                } else {
                    let evaluationKeyConfigHash = request.pirRequest.evaluationKeyMetadata.identifier
                    let evaluationKeyStoreKey = Self.persistKey(
                        user: context.userIdentifier,
                        configHash: evaluationKeyConfigHash)
                    evaluationKey = try await evaluationKeyStore.get(
                        key: evaluationKeyStoreKey,
                        as: Protobuf<Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey>.self)?.message
                }
                guard let evaluationKey else {
                    throw HTTPError(.badRequest, message: "Evaluation key not found")
                }
                let configId = Array(request.pirRequest.configurationHash)
                guard let usecase = await usecases.get(
                    name: request.usecase,
                    configId: configId)
                else {
                    if await (usecases.get(name: request.usecase)) != nil {
                        throw HTTPError(
                            .gone,
                            message: "Configuration id: \(configId) is not available for usecase \(request.usecase).")
                    }
                    throw HTTPError(.badRequest, message: "Unknown usecase: \(request.usecase)")
                }
                return try await usecase.process(request: request, evaluationKey: evaluationKey)
            case .some(.pnnsRequest):
                throw HTTPError(.badRequest, message: "Unknown request type.")
            case .none:
                throw HTTPError(.badRequest, message: "Unknown request type.")
            }
        }
        let responses: [Apple_SwiftHomomorphicEncryption_Api_V1_Response] = try await .init(responsesSequence)
        return Protobuf(Apple_SwiftHomomorphicEncryption_Api_V1_Responses.with { apiResponses in
            apiResponses.responses = responses
        })
    }
}
