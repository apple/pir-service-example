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

import Crypto
import Foundation
import HomomorphicEncryptionProtobuf
import Hummingbird
import SwiftProtobuf

/// Wrapper class for protobuf messages
struct Protobuf<Msg: Message>: ResponseGenerator {
    let message: Msg

    init(_ message: Msg) {
        self.message = message
    }

    func response(from _: HummingbirdCore.Request,
                  context _: some RequestContext) throws -> Response
    {
        let serialized = try message.serializedData()
        let buffer = ByteBuffer(bytes: serialized)
        return Response(status: .ok, body: ResponseBody(byteBuffer: buffer))
    }
}

extension Protobuf: Codable {
    init(from decoder: any Swift.Decoder) throws {
        let serialized = try decoder.singleValueContainer().decode(Data.self)
        self.message = try Msg(serializedBytes: serialized)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(message.serializedData())
    }
}

extension Message {
    func sha256() throws -> Data {
        let serialized = try serializedData()
        let digest = SHA256.hash(data: serialized)
        return Data(digest)
    }
}
