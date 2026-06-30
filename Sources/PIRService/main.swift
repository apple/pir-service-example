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

import ArgumentParser
import Foundation
import Hummingbird
import ServiceLifecycle

/// This executable is used in tests, which breaks `swift test -c release` when used with `@main`.
/// So we avoid using `@main` here.
struct ServerCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "PIRService")

    @Option var hostname: String = "127.0.0.1"
    @Option var port: Int = 8080
    @Argument var configFile: String

    func run() async throws {
        let usecaseStore = UsecaseStore()
        let privacyPassState = try PrivacyPassState(userAuthenticator: UserAuthenticator())
        let reportStore = ReportStore()

        let app = try await buildApplication(
            configuration: .init(address: .hostname(hostname, port: port)),
            usecaseStore: usecaseStore,
            privacyPassState: privacyPassState,
            reportStore: reportStore)

        let reloadService = ReloadService(
            configFile: URL(fileURLWithPath: configFile),
            usecaseStore: usecaseStore,
            privacyPassState: privacyPassState,
            reportStore: reportStore,
            logger: app.logger)

        try await reloadService.reloadConfiguration()

        let serviceGroup = ServiceGroup(configuration: .init(services: [app, reloadService], logger: app.logger))
        try await serviceGroup.run()
    }
}

/// workaround to call the async main, but without using a top-level `await` to not break `swift test -c release`.
let group = DispatchGroup()
group.enter()
let task = Task.detached(priority: .userInitiated) {
    defer { group.leave() }
    await ServerCommand.main()
}

group.wait()
