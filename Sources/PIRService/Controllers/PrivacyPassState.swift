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
import PrivacyPass

actor PrivacyPassState {
    var allowList: Set<String>
    let issuer: PrivacyPass.Issuer
    /// map from truncated key id to verifier
    var verifiers: [UInt8: PrivacyPass.Verifier<InMemoryNonceStore>]

    init() throws {
        let issuer = try PrivacyPass.Issuer(privateKey: .init())
        self.allowList = []
        self.issuer = issuer
        self.verifiers = [
            issuer.truncatedTokenKeyId: PrivacyPass.Verifier(
                publicKey: issuer.publicKey,
                nonceStore: InMemoryNonceStore()),
        ]
    }

    func authenticate(userToken: String) -> Bool {
        allowList.contains(userToken)
    }

    func add(token: String) {
        allowList.insert(token)
    }

    func update(allowList: Set<String>) {
        self.allowList = allowList
    }
}
