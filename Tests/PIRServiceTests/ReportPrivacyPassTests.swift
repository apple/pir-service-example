// Copyright 2025-2026 Apple Inc. and the Swift Homomorphic Encryption project authors
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
import HTTPTypes
import Hummingbird
import HummingbirdTesting
@testable import PIRService
@testable import PIRServiceTesting
import PrivateInformationRetrieval
import SwiftProtobuf
import Testing
import Util

struct ReportPrivacyPassTests {
    @Test
    func reportRejectedWithoutPrivacyPassToken() async throws {
        let userAuthenticator = UserAuthenticator()
        await userAuthenticator.add(token: "ABCD", tier: .tier1)
        let privacyPassState = try PrivacyPassState(userAuthenticator: userAuthenticator)
        let app = try await buildApplication(privacyPassState: privacyPassState)

        try await app.test(.live) { client in
            let user = UserIdentifier()
            let report = URLFilterReport.with { $0.urls = ["https://example.com"] }
            let platform = Platform(osType: .iOS, osVersion: .init(major: 18, minor: 0))
            var headers = HTTPFields()
            try headers[#require(HTTPField.Name("User-Identifier"))] = user.identifier
            headers[.userAgent] = platform.exampleUserAgent

            try await client.execute(uri: "/report", method: .post, headers: headers,
                                     body: ByteBuffer(data: report.serializedData()))
            { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test
    func reportAcceptedWithToken() async throws {
        let userAuthenticator = UserAuthenticator()
        await userAuthenticator.add(token: "ABCD", tier: .tier1)
        let privacyPassState = try PrivacyPassState(userAuthenticator: userAuthenticator)
        let app = try await buildApplication(privacyPassState: privacyPassState)

        try await app.test(.live) { client in
            var pirClient = PIRClient<MulPirClient<Bfv<UInt32>>>(
                connection: client,
                userToken: "ABCD")
            // Fetch a Privacy Pass token via the standard token exchange.
            try await pirClient.fetchTokens(count: 1)
            let token = pirClient.tokens.removeFirst()

            let report = URLFilterReport.with { $0.urls = ["https://example.com"] }
            var headers = HTTPFields()
            try headers[#require(HTTPField.Name("User-Identifier"))] = pirClient.userID.uuidString
            headers[.userAgent] = pirClient.platform.exampleUserAgent
            headers[.authorization] = "PrivateToken token=\(token.bytes().base64URLEncodedString())"
            try await client.execute(uri: "/report", method: .post, headers: headers,
                                     body: ByteBuffer(data: report.serializedData()))
            { response in
                #expect(response.status == .ok)
            }
        }
    }
}
