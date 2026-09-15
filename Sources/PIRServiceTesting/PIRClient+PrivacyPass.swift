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
#if !canImport(Darwin)
import NIOFoundationCompat
#endif

extension PIRClient {
    func fetchTokenDirectory() async throws -> TokenIssuerDirectory {
        let response = try await connection.get(
            path: "/.well-known/private-token-issuer-directory",
            body: [],
            headers: [:])

        let body = Data(buffer: response.body)
        guard response.status == .ok else {
            throw PIRClientError.failedToFetchTokenIssuerDirectory(
                status: response.status,
                message: String(data: body, encoding: .utf8) ?? "<\(body.count) bytes of binary response>")
        }
        return try JSONDecoder().decode(TokenIssuerDirectory.self, from: body)
    }

    func fetchPublicKeyForUserToken(authenticationToken: String) async throws -> PublicKey {
        let response = try await connection.get(
            path: "/token-key-for-user-token",
            body: [],
            headers: [.authorization: "Bearer \(authenticationToken)"])
        let body = Array(buffer: response.body)
        guard response.status == .ok else {
            throw PIRClientError.failedToFetchTokenPublicKey(
                status: response.status,
                message: String(data: Data(body), encoding: .utf8) ?? "<\(body.count) bytes of binary response>")
        }
        return try PublicKey(fromSPKI: body)
    }

    mutating func fetchTokens(count: Int) async throws {
        guard let userToken else {
            throw PIRClientError.missingAuthenticationToken
        }

        let tokenIssuerDirectory = try await fetchTokenDirectory()
        let publicKey: PublicKey
        if platform.requiresTokenKeyForUserToken {
            publicKey = try await fetchPublicKeyForUserToken(authenticationToken: userToken)
            let spki = try publicKey.spki()
            guard tokenIssuerDirectory.isValid(tokenKey: spki) else {
                throw PIRClientError.invalidTokenIssuerPublicKey
            }
        } else {
            guard let rawPublicKey = tokenIssuerDirectory.firstValidTokenKey(),
                  let publicKeySPKI = rawPublicKey.tokenKey
            else {
                throw PIRClientError.invalidTokenIssuerPublicKey
            }
            publicKey = try PublicKey(fromSPKI: publicKeySPKI)
        }

        let connection = connection
        let challenge = try TokenChallenge(tokenType: TokenTypeBlindRSA, issuer: "test")

        try await withThrowingTaskGroup(of: Token.self) { group in
            for _ in 0..<count {
                group.addTask {
                    let preparedRequest = try publicKey.request(challenge: challenge.bytes())
                    let response = try await connection.post(
                        path: "/issue",
                        body: preparedRequest.tokenRequest.bytes(),
                        headers: [.authorization: "Bearer \(userToken)"])
                    let body = Array(buffer: response.body)
                    guard response.status == .ok else {
                        throw PIRClientError.failedToFetchToken(
                            status: response.status,
                            message: String(data: Data(body), encoding: .utf8) ??
                                "<\(body.count) bytes of binary response>")
                    }
                    let tokenResponse = try TokenResponse(from: body)
                    return try preparedRequest.finalize(response: tokenResponse)
                }
            }

            for try await token in group {
                tokens.append(token)
            }
        }
    }
}
