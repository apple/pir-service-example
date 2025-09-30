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

/// Token issuer directory hold the list of all public keys supported by the issuer.
///
/// - seealso: [RFC 9578: Configuration](https://www.rfc-editor.org/rfc/rfc9578#name-configuration)
public struct TokenIssuerDirectory: Codable, Sendable {
    /// Public key.
    public struct TokenKey: Codable, Sendable {
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case tokenType = "token-type"
            case tokenKeyBase64Url = "token-key"
            case notBefore = "not-before"
        }

        /// Token type.
        public let tokenType: UInt16
        /// Base64url encoded public key.
        public let tokenKeyBase64Url: String
        /// The time in seconds since the epoch (UNIX timestamp) when the token is valid.
        public let notBefore: UInt64?

        /// Binary representation of the public key.
        public var tokenKey: [UInt8]? {
            Array(base64URLEncoded: tokenKeyBase64Url)
        }

        /// Initialize a new TokenKey.
        /// - Parameters:
        ///   - tokenType: Token type.
        ///   - tokenKeyBase64Url: Base64url encoded public key.
        ///   - notBefore: UNIX timestamp after which the public key is considered usable.
        public init(tokenType: UInt16, tokenKeyBase64Url: String, notBefore: UInt64?) {
            self.tokenType = tokenType
            self.tokenKeyBase64Url = tokenKeyBase64Url
            self.notBefore = notBefore
        }
    }

    enum CodingKeys: String, CodingKey {
        case issuerRequestUri = "issuer-request-uri"
        case tokenKeys = "token-keys"
    }

    /// Issuer request URL value.
    ///
    /// This is the URL where token requests should be sent to.
    public let issuerRequestUri: URL
    /// List of issuer public keys
    public let tokenKeys: [TokenKey]

    /// Initialize a token issuer directory.
    /// - Parameters:
    ///   - issuerRequestUri: URL that accepts token requests.
    ///   - tokenKeys: Public keys available on the issuer.
    public init(issuerRequestUri: URL, tokenKeys: [TokenKey]) {
        self.issuerRequestUri = issuerRequestUri
        self.tokenKeys = tokenKeys
    }

    /// Check if a specific public key is valid for the token issuer directory.
    ///
    /// This makes sure that the given public key is
    /// * present in the directory and,
    /// * valid accourding to the current time obtained from `currentTime()` closure.
    /// - Parameters:
    ///   - tokenKey: The token key whose validity is being checked.
    ///   - currentTime: Closure that returns the current time.
    /// - Returns: Validity of the token key.
    public func isValid(tokenKey: [UInt8], currentTime: () -> Date = Date.init) -> Bool {
        for key in tokenKeys where key.tokenType == PrivacyPass.TokenTypeBlindRSA {
            if tokenKey == key.tokenKey {
                if let notBefore = key.notBefore {
                    let now = Int(currentTime().timeIntervalSince1970)
                    guard now >= notBefore else {
                        return false
                    }
                }
                return true
            }
        }
        return false
    }
}
