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

/// A protocol for storing nonces to prevent double spending of tokens.
public protocol NonceStoring: Sendable {
    /// Check if a nonce is known to be used.
    ///
    /// This is only an optimization that lets the verifier skip the signature check for a token that was already
    /// redeemed. It may return false for a used nonce, but it must never return true for an unused one, because that
    /// would reject a valid token. ``insert(nonce:)`` makes the final decision.
    ///
    /// A store behind a network call should usually keep the default implementation: valid tokens are the common
    /// case, and for each of them the lookup would be a wasted round trip, while a replayed token only costs a
    /// signature check before ``insert(nonce:)`` rejects it.
    /// - Parameter nonce: The nonce to check.
    /// - Returns: True, if the nonce is known to be used.
    func definitelyContains(nonce: [UInt8]) async throws -> Bool

    /// Atomically insert a nonce, unless it is already in the store.
    ///
    /// Only one call returns true for a given nonce, even when several calls with that nonce run concurrently.
    /// - Parameter nonce: The nonce of the token being redeemed.
    /// - Returns: True, if this call inserted the nonce; false, if it was already in the store.
    func insert(nonce: [UInt8]) async throws -> Bool
}

public extension NonceStoring {
    /// Never reports a nonce as used, so every token gets a signature check before ``insert(nonce:)``.
    func definitelyContains(nonce _: [UInt8]) async throws -> Bool {
        false
    }
}

/// In memory nonce store that just adds used nonces to a set.
///
/// - Warning: The in memory set of used nonces will keep growing, because there is no garbage collection of old nonces.
public actor InMemoryNonceStore: NonceStoring {
    private var nonces: Set<[UInt8]>

    public init() {
        self.nonces = []
    }

    public func definitelyContains(nonce: [UInt8]) async throws -> Bool {
        nonces.contains(nonce)
    }

    public func insert(nonce: [UInt8]) async throws -> Bool {
        nonces.insert(nonce).inserted
    }
}
