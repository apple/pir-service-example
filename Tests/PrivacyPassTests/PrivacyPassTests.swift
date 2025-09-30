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
import _CryptoExtras
import Crypto
import Foundation
@testable import PrivacyPass
import Testing

@Suite
struct PrivacyPassTests {
    private enum InvalidHexString: Error {
        case invalidHexString
    }

    private func unhex(_ hexString: String) throws -> [UInt8] {
        guard let array = Array(hexEncoded: hexString) else {
            throw InvalidHexString.invalidHexString
        }
        return array
    }

    @Test
    func convertAndLoadPublicKey() throws {
        let privateKey = try PrivacyPass.PrivateKey()
        let spki = try privateKey.publicKey.spki()
        _ = try PrivacyPass.PublicKey(fromSPKI: spki)
    }

    @Test
    func issuance() async throws {
        let privateKey = try PrivacyPass.PrivateKey()
        let publicKey = privateKey.publicKey
        let preparedRequest = try publicKey.request(challenge: [1, 2, 3])
        let issuer = try PrivacyPass.Issuer(privateKey: privateKey)
        let response = try issuer.issue(request: preparedRequest.tokenRequest)
        let token = try preparedRequest.finalize(response: response)
        let verifier = PrivacyPass.Verifier(publicKey: publicKey, nonceStore: InMemoryNonceStore())
        #expect(try await verifier.verify(token: token))
    }

    @Test
    func noDoubleSpend() async throws {
        let privateKey = try PrivacyPass.PrivateKey()
        let publicKey = privateKey.publicKey
        let preparedRequest = try publicKey.request(challenge: [1, 2, 3])
        let issuer = try PrivacyPass.Issuer(privateKey: privateKey)
        let response = try issuer.issue(request: preparedRequest.tokenRequest)
        let token = try preparedRequest.finalize(response: response)
        let verifier = PrivacyPass.Verifier(publicKey: publicKey, nonceStore: InMemoryNonceStore())
        #expect(try await verifier.verify(token: token))
        #expect(try await !verifier.verify(token: token))
    }

    @Test
    func vectors() async throws {
        struct TestVector: Codable {
            let skS: String
            let pkS: String
            let token_challenge: String
            let nonce: String
            let blind: String
            let salt: String
            let token_request: String
            let token_response: String
            let token: String

            static func load(from path: URL) throws -> [Self] {
                let json = try Data(contentsOf: path)
                let decoder = JSONDecoder()
                return try decoder.decode([Self].self, from: json)
            }
        }

        let testVectors = try TestVector.load(from: URL(
            fileURLWithPath: "TestVectors/PrivacyPassPublicTokens.json",
            relativeTo: URL(fileURLWithPath: #filePath)))
        for testVector in testVectors {
            // load private key
            let skS = try unhex(testVector.skS)
            let privateKeyPEM = try #require(String(data: Data(skS), encoding: .ascii))
            let privateKey = try PrivacyPass.PrivateKey(pemRepresentation: privateKeyPEM)
            // verify public key is correctly encoded
            let pkS = try unhex(testVector.pkS)
            let spki = try privateKey.publicKey.spki()
            #expect(spki == pkS)
            // verify we can load the public key directly from SPKI
            let publicKey = try PrivacyPass.PublicKey(fromSPKI: pkS)
            // construct token request
            let tokenChallenge = try unhex(testVector.token_challenge)
            // because we cannot feed in random bytes to blinding step, we will ignore the generated tokenRequest
            _ = try publicKey.request(challenge: tokenChallenge)
            // load token request
            let tokenRequestBytes = try unhex(testVector.token_request)
            let tokenRequest = try PrivacyPass.TokenRequest(from: tokenRequestBytes)
            #expect(tokenRequest.bytes() == tokenRequestBytes)
            // verify token response
            let tokenResponseBytes = try unhex(testVector.token_response)
            let tokenResponse = try PrivacyPass.TokenResponse(from: tokenResponseBytes)
            let issuer = try PrivacyPass.Issuer(privateKey: privateKey)
            let issuedResponse = try issuer.issue(request: tokenRequest)
            #expect(issuedResponse == tokenResponse)
            #expect(issuedResponse.bytes() == tokenResponseBytes)
            // load token
            let tokenBytes = try unhex(testVector.token)
            let token = try PrivacyPass.Token(from: tokenBytes)
            #expect(token.bytes() == tokenBytes)
            // verify token validity
            let verifier = PrivacyPass.Verifier(publicKey: privateKey.publicKey, nonceStore: InMemoryNonceStore())
            #expect(try await verifier.verify(token: token))
        }
    }

    @Test
    func testTokenChallenge() throws {
        // token challenge with issuer = "test"
        let referenceBytes: [UInt8] = [0, 2, 0, 4, 116, 101, 115, 116, 0, 0, 0]
        let tokenChallenge = try TokenChallenge(tokenType: TokenTypeBlindRSA, issuer: "test")
        let challengeBytes = try tokenChallenge.bytes()
        #expect(challengeBytes == referenceBytes)
        let decodedChallenge = try TokenChallenge(from: challengeBytes)
        #expect(decodedChallenge == tokenChallenge)
    }

    @Test
    func challengeVectors() throws {
        struct TestVector: Codable {
            // Note: we use implicitly unwrapped optionals, becuase test vector 6 from
            // https://www.rfc-editor.org/rfc/rfc9577#name-challenge-and-redemption-st
            // does not have all the fields. In the actual test, we skip over test vector 6, and therefore we will not
            // use a missing field.

            // swiftlint:disable implicitly_unwrapped_optional
            let test_vector: Int
            let token_type: String
            let issuer_name_text: String!
            let issuer_name: String!
            let origin_info_text: [String]!
            let origin_info: String!
            let redemption_context: String!
            let nonce: String!
            let token_key_id: String!
            let token_authenticator_input: String
            // swiftlint:enable implicitly_unwrapped_optional

            static func load(from path: URL) throws -> [Self] {
                let json = try Data(contentsOf: path)
                let decoder = JSONDecoder()
                return try decoder.decode([Self].self, from: json)
            }
        }

        let testVectors = try TestVector.load(from: URL(
            fileURLWithPath: "TestVectors/PrivacyPassChallengeAndRedemptionStructure.json",
            relativeTo: URL(fileURLWithPath: #filePath)))
        #expect(testVectors.count == 6)
        for testVector in testVectors {
            let tokenType = try UInt16(bigEndianBytes: unhex(testVector.token_type))
            guard tokenType == TokenTypeBlindRSA else {
                // skip test vector 6 which has missing fields.
                continue
            }
            let redemptionContext = try unhex(testVector.redemption_context)
            let tokenChallenge = try TokenChallenge(
                tokenType: tokenType,
                issuer: testVector.issuer_name_text,
                redemptionContext: redemptionContext,
                originInfo: testVector.origin_info_text)

            let nonce = try unhex(testVector.nonce)
            let tokenKeyId = try unhex(testVector.token_key_id)
            let tokenAuthenticatorInput = try unhex(testVector.token_authenticator_input)

            let challengeBytes = try tokenChallenge.bytes()
            let challengeDigest = SHA256.hash(data: challengeBytes)
            var tokenInput: [UInt8] = []
            tokenInput.append(contentsOf: tokenType.bigEndianBytes)
            tokenInput.append(contentsOf: nonce)
            tokenInput.append(contentsOf: challengeDigest)
            tokenInput.append(contentsOf: tokenKeyId)

            #expect(tokenInput == tokenAuthenticatorInput)

            // test parsing challenge bytes
            let parsed = try TokenChallenge(from: challengeBytes)
            #expect(parsed == tokenChallenge)

            // construct challenge bytes from fields
            let issuerName = try unhex(testVector.issuer_name)
            let originInfo = try unhex(testVector.origin_info)

            var constructedChallengeBytes: [UInt8] = []
            constructedChallengeBytes.append(contentsOf: tokenType.bigEndianBytes)
            constructedChallengeBytes.append(contentsOf: UInt16(issuerName.count).bigEndianBytes)
            constructedChallengeBytes.append(contentsOf: issuerName)
            constructedChallengeBytes.append(UInt8(redemptionContext.count))
            constructedChallengeBytes.append(contentsOf: redemptionContext)
            constructedChallengeBytes.append(contentsOf: UInt16(originInfo.count).bigEndianBytes)
            constructedChallengeBytes.append(contentsOf: originInfo)

            let constructedChallenge = try TokenChallenge(from: constructedChallengeBytes)
            #expect(constructedChallenge == tokenChallenge)
        }
    }
}
