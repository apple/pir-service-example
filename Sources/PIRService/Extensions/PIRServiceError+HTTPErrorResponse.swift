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
import Hummingbird
import PrivateInformationRetrievalProtobuf

/// Errors reported to the client using the `Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Error` protobuf message.
enum PIRServiceError: Error {
    /// Client's configuration is stale or unknown. `configResponse`, if present, is the configuration the client
    /// should use for subsequent requests.
    case configVersionNotFound(configResponse: Apple_SwiftHomomorphicEncryption_Api_Pir_V1_ConfigResponse?)
    /// Client's evaluation key was not found on the server.
    case evaluationKeyNotFound
    /// Request could not be processed. `message` is for server-side logging only; it is not sent to the client.
    case invalidRequest(message: String)
}

extension PIRServiceError: Hummingbird.HTTPResponseError {
    public var status: HTTPResponse.Status {
        switch self {
        case .configVersionNotFound: .gone
        case .evaluationKeyNotFound: .badRequest
        case .invalidRequest: .badRequest
        }
    }

    public func response(from _: Request, context _: some RequestContext) throws -> Response {
        let error = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Error.with { error in
            switch self {
            case let .configVersionNotFound(configResponse):
                error.configVersionNotFound = .with { configVersionNotFound in
                    if let configResponse {
                        configVersionNotFound.configResponse = configResponse
                    }
                }
            case .evaluationKeyNotFound:
                error.evaluationKeyNotFound = .init()
            case .invalidRequest:
                error.invalidRequest = .init()
            }
        }
        let serialized = try error.serializedData()
        return Response(status: status, body: ResponseBody(byteBuffer: ByteBuffer(bytes: serialized)))
    }
}

extension PIRServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .configVersionNotFound: "Configuration id is not available"
        case .evaluationKeyNotFound: "Evaluation key not found"
        case let .invalidRequest(message): message
        }
    }
}
