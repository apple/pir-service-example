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

import HomomorphicEncryption
import PrivateInformationRetrieval

actor UsecaseStore {
    typealias ConfigId = [UInt8]

    struct VersionedUsecases {
        /// Mapping from Configuration ID to usecase.
        var usecases: [ConfigId: Usecase]
        /// Configuration IDs, in order from oldest to newest.
        var configIds: [ConfigId]
        /// How many versions to store.
        var versionCount: Int

        /// Newest configuration ID.
        var latestConfigId: ConfigId? {
            configIds.last
        }

        var usecase: Usecase? {
            if let latestConfigId {
                return usecases[latestConfigId]
            }
            return nil
        }

        init(versionCount: Int) {
            self.usecases = [:]
            self.configIds = []
            self.versionCount = versionCount
        }

        mutating func add(usecase: Usecase, versionCount: Int? = nil) throws {
            let configId = try Array(usecase.config().configID)
            // make sure there are no double entries with the same configID.
            if let existingLocation = configIds.firstIndex(of: configId) {
                configIds.remove(at: existingLocation)
            }
            configIds.append(configId)
            usecases[configId] = usecase

            if let versionCount {
                self.versionCount = versionCount
            }
            trim()
        }

        /// Remove old usecases
        mutating func trim() {
            precondition(versionCount >= 0)
            while configIds.count > versionCount {
                let removedConfigID = configIds.removeFirst()
                usecases[removedConfigID] = nil
            }
        }
    }

    var store: [String: VersionedUsecases]

    var allUsecaseNames: [String] {
        .init(store.keys)
    }

    init() {
        self.store = [:]
    }

    func set(name: String, usecase: Usecase?, versionCount: Int = 2) throws {
        if let usecase {
            try store[name, default: .init(versionCount: versionCount)].add(
                usecase: usecase,
                versionCount: versionCount)
        } else {
            store[name] = nil
        }
    }

    func get(name: String, configId: ConfigId) -> Usecase? {
        store[name]?.usecases[configId]
    }

    func get(name: String) -> Usecase? {
        store[name]?.usecase
    }

    func get(names: [String]) -> [String: Usecase] {
        .init(uniqueKeysWithValues: names.compactMap { name in
            guard let usecase = store[name]?.usecase else {
                return nil
            }
            return (name, usecase)
        })
    }

    func getAll() -> [String: Usecase] {
        store.compactMapValues { versionedUsecases in
            versionedUsecases.usecase
        }
    }
}
