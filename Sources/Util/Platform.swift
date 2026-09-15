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

/// Description of a computing environment.
public struct Platform: Equatable, Hashable, Sendable {
    /// iOS 18.
    public static let iOS18 = Platform(osType: .iOS, osVersion: .init(major: 18))
    /// iOS 18.2.
    public static let iOS18_2 = Platform(osType: .iOS, osVersion: .init(major: 18, minor: 2))

    /// macOS 15.
    public static let macOS15 = Platform(osType: .macOS, osVersion: .init(major: 15))
    /// macOS 15.2.
    public static let macOS15_2 = Platform(osType: .macOS, osVersion: .init(major: 15, minor: 2))

    /// iOS 27.3.
    public static let iOS27_3 = Platform(osType: .iOS, osVersion: .init(major: 27, minor: 3))
    /// macOS 27.3.
    public static let macOS27_3 = Platform(osType: .macOS, osVersion: .init(major: 27, minor: 3))

    /// Operating system type.
    public let osType: OsType
    /// Operating system version.
    public let osVersion: OsVersion

    /// Initializes a `Platform`.
    /// - Parameters:
    ///   - osType: Operating system type.
    ///   - osVersion: Operating system version.
    public init(osType: OsType, osVersion: OsVersion) {
        self.osVersion = osVersion
        self.osType = osType
    }

    /// Initializes a platform from a `User-Agent` HTTP header.
    /// - Parameter userAgent: `User-Agent` HTTP header.
    public init?(userAgent: String) {
        let iOSRegex: Regex = #/^.*iOS/(\d+)\.(\d+)\.?(\d)?.*/# // matches ... iOS/18.0 ...
        let macOSRegex: Regex = #/^.*Macintosh; OS X (\d+)\.(\d+)\.?(\d)?.*/# // matches ... Macintosh; OS X 15.0.1 ...

        // swiftlint:disable:next large_tuple
        func parseOsVersion(from match: Regex<(Substring, Substring, Substring, Substring?)>.Match) -> OsVersion? {
            guard let major = Int(match.output.1) else {
                return nil
            }
            guard let minor = Int(match.output.2) else {
                return nil
            }
            guard let patch = Int(match.output.3 ?? "0") else {
                return nil
            }
            return OsVersion(major: major, minor: minor, patch: patch)
        }

        for (osType, regexExpression): (OsType, Regex) in [(.iOS, iOSRegex), (.macOS, macOSRegex)] {
            // `wholeMatch` only throws on failable transformaton closures.
            // swiftlint:disable:next force_try
            if let match = try! regexExpression.wholeMatch(in: userAgent) {
                if let osVersion = parseOsVersion(from: match) {
                    self = .init(osType: osType, osVersion: osVersion)
                    return
                }
                return nil
            }
        }
        return nil
    }
}

public extension Platform {
    /// An example 'User-Agent' for a device with this platform.
    var exampleUserAgent: String {
        switch osType {
        case .iOS:
            "com.apple.ciphermld/1.0 iOS/\(osVersion.major).\(osVersion.minor) ..."
        case .macOS:
            "com.apple.ciphermld/1.2 (Macintosh; OS X \(osVersion.major).\(osVersion.minor); XXXXX) ..."
        default:
            fatalError("Unsupported OS type: \(osType)")
        }
    }

    /// Whether the platform requires fetching the Privacy Pass public key via `/token-key-for-user-token`.
    ///
    /// Newer platforms fetch the public key directly from the token issuer directory instead.
    var requiresTokenKeyForUserToken: Bool {
        switch osType {
        case .iOS:
            osVersion < Self.iOS27_3.osVersion
        case .macOS:
            osVersion < Self.macOS27_3.osVersion
        default:
            fatalError("Unsupported OS type: \(osType)")
        }
    }
}
