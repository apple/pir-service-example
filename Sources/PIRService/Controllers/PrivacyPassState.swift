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

protocol UserTokenAuthenticator: Sendable {
    func authenticate(userToken: String) async throws -> UserTier?
}

actor PrivacyPassState<UserAuthenticator: UserTokenAuthenticator> {
    struct TieredVerifier {
        let verifier: PrivacyPass.Verifier<InMemoryNonceStore>
        let tier: UserTier
    }

    let userAuthenticator: UserAuthenticator
    /// map from tier to issuer
    var issuers: [UserTier: PrivacyPass.Issuer]
    /// map from truncate key id to verifier & tier
    var verifiers: [UInt8: TieredVerifier]

    init(userAuthenticator: UserAuthenticator) throws {
        var issuers: [UserTier: PrivacyPass.Issuer] = [:]
        var verifiers: [UInt8: TieredVerifier] = [:]
        // generate issuers for each user tier and avoid truncated key id collisions
        for tier in UserTier.allCases {
            var issuer: PrivacyPass.Issuer
            repeat {
                issuer = try PrivacyPass.Issuer(privateKey: .init())
            } while verifiers[issuer.truncatedTokenKeyId] != nil
            issuers[tier] = issuer
            verifiers[issuer.truncatedTokenKeyId] = TieredVerifier(
                verifier: PrivacyPass.Verifier(publicKey: issuer.publicKey, nonceStore: InMemoryNonceStore()),
                tier: tier)
        }

        self.userAuthenticator = userAuthenticator
        self.issuers = issuers
        self.verifiers = verifiers
    }
}
