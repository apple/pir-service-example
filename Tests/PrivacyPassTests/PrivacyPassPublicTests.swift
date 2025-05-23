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

import PrivacyPass
import Testing

@Suite
struct PrivacyPassPublicTests {
    @Test
    func testIssuance() async throws {
        let privateKey = try PrivacyPass.PrivateKey()
        let publicKey = privateKey.publicKey
        let preparedRequest = try publicKey.request(challenge: [1, 2, 3])
        let issuer = try PrivacyPass.Issuer(privateKey: privateKey)
        let response = try issuer.issue(request: preparedRequest.tokenRequest)
        let token = try preparedRequest.finalize(response: response)
        let verifier = PrivacyPass.Verifier(publicKey: publicKey, nonceStore: InMemoryNonceStore())
        #expect(try await verifier.verify(token: token))
    }
}
