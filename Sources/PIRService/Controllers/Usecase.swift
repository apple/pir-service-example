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
import HomomorphicEncryptionProtobuf
import Util

protocol Usecase: Sendable {
    /// Returns the configuration.
    ///
    /// Note: may use features that are not compatible with older platforms.
    /// ``ApplicationProtobuf/Apple_SwiftHomomorphicEncryption_Api_V1_Config/makeCompatible(with:)``
    /// can be used to make the configuration compatible with older platforms.
    func config() throws -> Apple_SwiftHomomorphicEncryption_Api_V1_Config
    func evaluationKeyConfig() throws -> Apple_SwiftHomomorphicEncryption_V1_EvaluationKeyConfig
    func process(
        request: Apple_SwiftHomomorphicEncryption_Api_V1_Request,
        evaluationKey: Apple_SwiftHomomorphicEncryption_Api_Shared_V1_EvaluationKey) async throws
        -> Apple_SwiftHomomorphicEncryption_Api_V1_Response
    func processOprf(request: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_OPRFRequest) async throws
        -> Apple_SwiftHomomorphicEncryption_Api_V1_Response
}

extension Usecase {
    func config(existingConfigId: [UInt8]) throws -> Apple_SwiftHomomorphicEncryption_Api_V1_Config {
        let config = try config()
        if Array(config.configID) == existingConfigId {
            return Apple_SwiftHomomorphicEncryption_Api_V1_Config.with { apiConfig in
                apiConfig.reuseExistingConfig = true
            }
        }
        return config
    }
}
