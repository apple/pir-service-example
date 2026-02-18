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

import ApplicationProtobuf
import Hummingbird
import Util

extension Platform {
    var supportsPirFixedShardConfig: Bool {
        switch osType {
        case .iOS:
            osVersion >= .init(major: 18, minor: 2)
        case .macOS:
            osVersion >= .init(major: 15, minor: 2)
        default:
            fatalError("Unsupported platform \(self)")
        }
    }

    var supportsShardingFunctionDoubleMod: Bool {
        switch osType {
        case .iOS:
            osVersion >= .init(major: 18, minor: 2)
        case .macOS:
            osVersion >= .init(major: 15, minor: 2)
        default:
            fatalError("Unsupported platform \(self)")
        }
    }
}

public extension Apple_SwiftHomomorphicEncryption_Api_V1_Config {
    /// Makes the configuration compatible with the given platform.
    /// - Parameter platform: Device platform.
    mutating func makeCompatible(with platform: Platform) throws {
        if !platform.supportsPirFixedShardConfig {
            // Check for PIRFixedShardConfig, introduced in iOS 18.2
            switch pirConfig.pirShardConfigs.shardConfigs {
            case let .repeatedShardConfig(repeatedConfig):
                pirConfig.shardConfigs = Array(
                    repeating: repeatedConfig.shardConfig,
                    count: Int(repeatedConfig.shardCount))
                pirConfig.clearPirShardConfigs()
            case .none:
                break
            }
        }

        if !platform.supportsShardingFunctionDoubleMod {
            if pirConfig.keywordPirParams.shardingFunction.native() != .sha256 {
                throw HTTPError(.internalServerError,
                                message: "Platform \(platform) does not support sharding functions other than SHA256.")
            }
        }
    }
}
