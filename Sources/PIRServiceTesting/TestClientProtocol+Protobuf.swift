// Copyright 2024-2026 Apple Inc. and the Swift Homomorphic Encryption project authors
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
import HTTPTypes
import HummingbirdTesting
import SwiftProtobuf

extension TestClientProtocol {
    func post(path: String, body: [UInt8], headers: HTTPFields) async throws -> TestResponse {
        try await executeRequest(uri: path, method: .post, headers: headers, body: .init(bytes: body))
    }

    func get(path: String, body: [UInt8], headers: HTTPFields) async throws -> TestResponse {
        try await executeRequest(uri: path, method: .get, headers: headers, body: .init(bytes: body))
    }

    func post<Response: Message>(path: String, body: some Message, headers: HTTPFields) async throws -> Response {
        let response = try await executeRequest(
            uri: path,
            method: .post,
            headers: headers,
            body: .init(data: body.serializedBytes()))
        guard response.status == .ok else {
            throw PIRClientError.serverError(
                status: response.status,
                message: String(data: Data(buffer: response.body), encoding: .utf8) ??
                    "<\(response.body.readableBytes) bytes of binary response>")
        }
        return try Response(serializedBytes: Array(buffer: response.body))
    }
}

extension HTTPField.Name {
    static var userIdentifier: Self {
        // swiftlint:disable:next force_unwrapping
        Self("User-Identifier")!
    }
}
