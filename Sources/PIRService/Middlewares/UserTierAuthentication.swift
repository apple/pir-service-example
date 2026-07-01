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

import HTTPTypes
import Hummingbird

enum UserTier: String, Equatable, CaseIterable, Hashable, Codable {
    case tier1
    case tier2
    case tier3
}

protocol AuthenticatedRequestContext: RequestContext {
    var userTier: UserTier { get set }
}

struct AuthenticateUserTierMiddleware<
    Context: AuthenticatedRequestContext,
    Authenticator: UserTokenAuthenticator,
>: RouterMiddleware {
    let state: PrivacyPassState<Authenticator>

    init(_: Context.Type, state: PrivacyPassState<Authenticator>) {
        self.state = state
    }

    func handle(_ input: Request, context: Context,
                next: (Request, Context) async throws -> Response) async throws -> Response
    {
        context.logger.info("Authenticating request")
        var context = context
        guard let token = try input.headers.privateToken() else {
            throw HTTPError(.unauthorized, message: "No private token")
        }

        guard let truncatedKeyId = token.tokenKeyId.last,
              let tieredVerifier = await state.verifiers[truncatedKeyId]
        else {
            throw HTTPError(.unauthorized, message: "No token key found with key id: \(token.tokenKeyId)")
        }

        guard try await tieredVerifier.verifier.verify(token: token) else {
            throw HTTPError(.unauthorized, message: "Token did not pass verification")
        }

        context.userTier = tieredVerifier.tier
        return try await next(input, context)
    }
}
