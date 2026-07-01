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
import HTTPTypes
import Hummingbird

struct UserIdentifier: Equatable, Hashable {
    let identifier: String

    init() {
        self.identifier = UUID().uuidString
    }

    init(identifier: String) {
        self.identifier = identifier
    }
}

protocol IdentifiedRequestContext: RequestContext {
    var userIdentifier: UserIdentifier { get set }
}

/// Middleware that makes sure that the 'User-Identifier' header is set
struct ExtractUserIdentifierMiddleware<Context: IdentifiedRequestContext>: RouterMiddleware {
    func handle(
        _ input: Request,
        context: Context,
        next: (Request, Context) async throws -> Response) async throws -> Response
    {
        var context = context
        guard let userIdentifier = input.headers[.userIdentifier] else {
            throw HTTPError(.badRequest, message: "Missing 'User-Identifier' header")
        }
        context.userIdentifier = UserIdentifier(identifier: userIdentifier)
        return try await next(input, context)
    }
}

extension HTTPField.Name {
    static var userIdentifier: Self {
        // swiftlint:disable:next force_unwrapping
        Self("User-Identifier")!
    }
}
