// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

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

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
]

let package = Package(
    name: "pir-service-example",
    products: [
        .executable(name: "PIRService", targets: ["PIRService"]),
        .executable(name: "ConstructDatabase", targets: ["ConstructDatabase"]),
        .library(name: "PrivacyPass", targets: ["PrivacyPass"]),
        .library(name: "PIRServiceTesting", targets: ["PIRServiceTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.10.0"),
        .package(url: "https://github.com/apple/swift-homomorphic-encryption", branch: "release/1.1"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-compression", from: "2.0.0-rc.2"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "PIRService",
            dependencies: [
                "PrivacyPass", "Util",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "HomomorphicEncryptionProtobuf", package: "swift-homomorphic-encryption"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdCompression", package: "hummingbird-compression"),
                .product(name: "PrivateInformationRetrievalProtobuf", package: "swift-homomorphic-encryption"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "UnixSignals", package: "swift-service-lifecycle"),
            ],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "PIRServiceTests",
            dependencies: [
                "PIRService",
                "PIRServiceTesting",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            swiftSettings: swiftSettings),
        .executableTarget(
            name: "ConstructDatabase",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PrivateInformationRetrievalProtobuf", package: "swift-homomorphic-encryption"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            exclude: ["protobuf"],
            swiftSettings: swiftSettings),
        .target(
            name: "PrivacyPass",
            dependencies: [
                "Util",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            swiftSettings: swiftSettings),
        .target(name: "Util", swiftSettings: swiftSettings),
        .testTarget(
            name: "PrivacyPassTests",
            dependencies: [
                "PrivacyPass",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            exclude: [
                "TestVectors/PrivacyPassPublicTokens.json",
                "TestVectors/PrivacyPassChallengeAndRedemptionStructure.json",
            ],
            swiftSettings: swiftSettings),
        .target(
            name: "PIRServiceTesting",
            dependencies: [
                "PrivacyPass", "Util",
                .product(name: "HomomorphicEncryptionProtobuf", package: "swift-homomorphic-encryption"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "PrivateInformationRetrievalProtobuf", package: "swift-homomorphic-encryption"),
            ],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "UtilTests",
            dependencies: ["Util"],
            swiftSettings: swiftSettings),
    ])

#if canImport(Darwin)
// Set the minimum macOS version for the package
package.platforms = [
    .macOS(.v15), // Constrained by swift-homomorphic-encryption
]
#endif
