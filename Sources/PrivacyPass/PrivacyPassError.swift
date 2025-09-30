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

/// Privacy Pass error.
public struct PrivacyPassError: Error, Equatable, Sendable {
    /// A high-level error code to provide a broad classification.
    public var code: Code

    /// The location from which this error was thrown.
    public var location: SourceLocation

    /// Creates a new ``PrivacyPassError``.
    /// - Parameters:
    ///   - code: Error code.
    ///   - location: Source location where the error occured.
    @inlinable
    public init(code: Code, location: SourceLocation) {
        self.code = code
        self.location = location
    }

    /// Creates a new ``PrivacyPassError``.
    /// - Parameters:
    ///   - code: Error code.
    ///   - function: The function in which the error was thrown.
    ///   - file: The file in which the error was thrown.
    ///   - line: The line on which the error was thrown.
    @inlinable
    public init(
        code: Code,
        function: String = #function,
        file: String = #fileID,
        line: Int = #line)
    {
        self.code = code
        self.location = SourceLocation(function: function, file: file, line: line)
    }
}

extension PrivacyPassError: CustomStringConvertible {
    public var description: String {
        "\(code)"
    }
}

extension PrivacyPassError: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(code): \(location.description)"
    }
}

public extension PrivacyPassError {
    /// A high level indication of the kind of error being thrown.
    struct Code: Hashable, Sendable, CustomStringConvertible {
        // Adding cases to an enum is source-breaking (since adopters might switch on an enum value without a default).
        // So we keep the enum private.
        private enum InternalCode: Hashable, Sendable, CustomStringConvertible { // swiftlint:disable:this nesting
            case invalidIssuer
            case invalidKeySize
            case invalidOriginInfo
            case invalidRedemptionContext
            case invalidSPKIFormat
            case invalidTokenChallenge
            case invalidTokenChallengeSize
            case invalidTokenKeyId
            case invalidTokenRequestBlindedMessageSize
            case invalidTokenRequestSize
            case invalidTokenResponseSize
            case invalidTokenSize
            case invalidTokenType

            var description: String {
                switch self {
                case .invalidIssuer:
                    "Invalid issuer"
                case .invalidKeySize:
                    "Invalid key size"
                case .invalidOriginInfo:
                    "Invalid origin info"
                case .invalidRedemptionContext:
                    "Invalid redemption context"
                case .invalidSPKIFormat:
                    "Invalid SPKI Format"
                case .invalidTokenChallenge:
                    "Invalid token challenge"
                case .invalidTokenChallengeSize:
                    "Invalid token challenge size"
                case .invalidTokenKeyId:
                    "Invalid token Id"
                case .invalidTokenRequestBlindedMessageSize:
                    "Invalid token request blinded message size"
                case .invalidTokenRequestSize:
                    "Invalid token request size"
                case .invalidTokenResponseSize:
                    "Invalid token response size"
                case .invalidTokenSize:
                    "Invalid token size"
                case .invalidTokenType:
                    "Invalid token type"
                }
            }
        }

        /// Invalid issuer.
        public static var invalidIssuer: Self {
            Self(.invalidIssuer)
        }

        /// Invalid key size.
        public static var invalidKeySize: Self {
            Self(.invalidKeySize)
        }

        /// Invalid origin info.
        public static var invalidOriginInfo: Self {
            Self(.invalidOriginInfo)
        }

        /// Invalid redemption context.
        public static var invalidRedemptionContext: Self {
            Self(.invalidRedemptionContext)
        }

        /// Invalid SPKI format.
        public static var invalidSPKIFormat: Self {
            Self(.invalidSPKIFormat)
        }

        /// Invalid token challenge.
        public static var invalidTokenChallenge: Self {
            Self(.invalidTokenChallenge)
        }

        /// Invalid token challenge size.
        public static var invalidTokenChallengeSize: Self {
            Self(.invalidTokenChallengeSize)
        }

        /// Invalid token identifier.
        public static var invalidTokenKeyId: Self {
            Self(.invalidTokenKeyId)
        }

        /// Invalid blinded message size in the token request.
        public static var invalidTokenRequestBlindedMessageSize: Self {
            Self(.invalidTokenRequestBlindedMessageSize)
        }

        /// Invalid token request size.
        public static var invalidTokenRequestSize: Self {
            Self(.invalidTokenRequestSize)
        }

        /// Invalid token response size.
        public static var invalidTokenResponseSize: Self {
            Self(.invalidTokenResponseSize)
        }

        /// Invalid token size.
        public static var invalidTokenSize: Self {
            Self(.invalidTokenSize)
        }

        /// Invalid token type.
        public static var invalidTokenType: Self {
            Self(.invalidTokenType)
        }

        public var description: String {
            String(describing: code)
        }

        private var code: InternalCode

        private init(_ code: InternalCode) {
            self.code = code
        }
    }

    /// A location within source code.
    struct SourceLocation: Sendable, Hashable, CustomStringConvertible {
        /// The function in which the error was thrown.
        public let function: String

        /// The file in which the error was thrown.
        public let file: String

        /// The line on which the error was thrown.
        public let line: Int

        public var description: String {
            "in \(function) at \(file):\(line)"
        }

        /// Creates a new ``SourceLocation``
        /// - Parameters:
        ///   - function: The function in which the error was thrown.
        ///   - file: The file in which the error was thrown.
        ///   - line: The line on which the error was thrown.
        public init(function: String, file: String, line: Int) {
            self.function = function
            self.file = file
            self.line = line
        }

        /// A ``SourceLocation`` which is the current location.
        /// - Parameters:
        ///   - function: The function in which the error was thrown.
        ///   - file: The file in which the error was thrown.
        ///   - line: The line on which the error was thrown.
        public static func here(function: String = #function, file: String = #fileID, line: Int = #line) -> Self {
            SourceLocation(function: function, file: file, line: line)
        }
    }
}
