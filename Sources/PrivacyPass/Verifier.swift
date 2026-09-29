// Copyright 2024 Apple Inc. and the Swift Homomorphic Encryption project authors
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
import Foundation

/// Token verifier.
public struct Verifier<NonceStore: NonceStoring>: Sendable {
    /// Public key used to verify tokens.
    public let publicKey: PublicKey

    /// Nonce store to use to avoid double spending of tokens.
    public let nonceStore: NonceStore

    /// Challenge digest to use for verification.
    public let challengeDigest: [UInt8]?

    /// Initialize a verifier.
    /// - Parameters:
    ///   - publicKey: Public key to use for verification.
    ///   - nonceStore: Nonce store to use for storing nonces of redeemed tokens.
    ///   - challengeDigest: Optional challenge digest.
    public init(publicKey: PublicKey, nonceStore: NonceStore, challengeDigest: [UInt8]? = nil) {
        self.publicKey = publicKey
        self.nonceStore = nonceStore
        self.challengeDigest = challengeDigest
    }

    /// Verify that the token is valid.
    ///
    /// This function verifies that the given token has:
    ///  - correct token type,
    ///  - correct challenge digest (if present in the verifier),
    ///  - valid signature.
    /// - Parameter token: The token whose validity is being verified.
    /// - Returns: If the token is valid.
    /// - seealso: [RFC 9578: Token Verification](https://www.rfc-editor.org/rfc/rfc9578#name-token-verification-2)
    public func verify(token: Token) async throws -> Bool {
        // fast return, when token type or token key id are invalid
        guard token.tokenType == TokenTypeBlindRSA,
              token.tokenKeyId == publicKey.tokenKeyId
        else {
            return false
        }

        // verify the challenge digest, if available
        if let challengeDigest {
            guard token.challengeDigest == challengeDigest else {
                return false
            }
        }

        // skip the signature check for a nonce that is known to be redeemed already
        guard try await !nonceStore.definitelyContains(nonce: token.nonce) else {
            return false
        }

        /*
         token_authenticator_input =
           concat(Token.token_type,
                  Token.nonce,
                  Token.challenge_digest,
                  Token.token_key_id)
         valid = RSASSA-PSS-VERIFY(pkI,
                                   token_authenticator_input,
                                   Token.authenticator)
         */
        let tokenAuthenticatorInputSize = MemoryLayout.size(ofValue: token.tokenType) + MemoryLayout
            .size(ofValue: token.nonce) + MemoryLayout.size(ofValue: token.challengeDigest) + MemoryLayout
            .size(ofValue: token.tokenKeyId)
        var inputMessage = Data(capacity: tokenAuthenticatorInputSize)
        inputMessage.append(contentsOf: token.tokenType.bigEndianBytes)
        inputMessage.append(contentsOf: token.nonce)
        inputMessage.append(contentsOf: token.challengeDigest)
        inputMessage.append(contentsOf: token.tokenKeyId)
        let preparedMessage = publicKey.backing.prepare(inputMessage)
        let blindSignature = _RSA.Signing.RSASignature(rawRepresentation: token.authenticator)
        guard publicKey.backing.isValidSignature(blindSignature, for: preparedMessage) else {
            return false
        }
        // the atomic insert is the double spend check: of concurrent redemptions of one token, only one inserts
        return try await nonceStore.insert(nonce: token.nonce)
    }
}
