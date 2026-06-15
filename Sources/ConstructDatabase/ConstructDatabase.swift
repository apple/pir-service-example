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
import ArgumentParser
import Foundation
import SwiftProtobuf

let discussion =
    """
    This utility allows one to manually write a few phone numbers in human-readable config format
    and then transform that to two datasets that can be processed with the `PIRProcessDatabase` utility.

    Additionally one can supply icons by storing them into a folder with setting the file name equal to
    the phone number and the file extension as ".heic".
    """

@main
struct ConstructDatabase: ParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "ConstructDatabase",
        abstract: "Transforms some input data into two datasets",
        discussion: discussion)
    static var exampleIdentities: String {
        var identities: [String: InputCallIdentity] = [:]

        identities["+123"] = InputCallIdentity.with { id in
            id.name = "Adam"
            id.cacheExpiryMinutes = 8
            id.block = true
            id.category = .person
        }

        identities["+1234"] = InputCallIdentity.with { id in
            id.name = "Bob"
            id.cacheExpiryMinutes = 7
            id.block = false
        }

        identities["+12345"] = InputCallIdentity.with { id in
            id.name = "Grocery Store"
            id.cacheExpiryMinutes = 18
            id.block = true
            id.category = .business
        }

        let example = InputIdentities.with { input in
            input.identities = identities
        }
        return example.textFormatString()
    }

    @Argument(help: "File containing the input data. Example:\n\(exampleIdentities)")
    var inputFile: String

    @Option(help: """
        Folder to search for icons.
        The folder should contains files like '<phonenumber>.heic'.
        For example:
        +123.heic
        +1234.heic
        +12345.heic
        """)
    var iconDirectory: String?

    @Argument(help: "Where to save the blocking dataset.")
    var blockFile: String

    @Argument(help: "Where to save the identity dataset.")
    var identityFile: String

    mutating func run() throws {
        let fm = FileManager.default

        let input = try String(contentsOfFile: inputFile, encoding: .utf8)
        let inputIdentities = try InputIdentities(textFormatString: input)

        print("Loaded \(inputIdentities.identities.count) identities")

        var blockRows = [Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabaseRow]()
        var identityRows = [Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabaseRow]()

        for (number, inputIdentity) in inputIdentities.identities {
            var icon: Icon? = .none

            if let iconDirectory {
                let directoryURL = URL(fileURLWithPath: iconDirectory)
                let fileURL = directoryURL.appendingPathComponent(number).appendingPathExtension(
                    "heic")

                if fm.fileExists(atPath: fileURL.path) {
                    icon = try Icon.with { icon in
                        icon.format = .heic
                        icon.image = try Data(contentsOf: fileURL)
                    }
                }
            }

            let identity = CallIdentity.with { id in
                id.name = inputIdentity.name
                id.cacheExpiryMinutes = inputIdentity.cacheExpiryMinutes
                if let icon {
                    id.icon = icon
                }
                id.category = inputIdentity.category
            }

            let blockRow = Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabaseRow.with { row in
                row.keyword = Data(number.utf8)
                var blockingData = Data(count: 1)
                blockingData[0] = inputIdentity.block ? 1 : 0
                row.value = blockingData
            }
            blockRows.append(blockRow)
            if identity != CallIdentity() {
                let encodedIdentity = try identity.serializedData()
                let identityRow = Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabaseRow.with { row in
                    row.keyword = Data(number.utf8)
                    row.value = encodedIdentity
                }
                identityRows.append(identityRow)
            }
        }

        let blockDB = Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabase.with { db in
            db.rows = blockRows
        }

        let identityDB = Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabase.with { db in
            db.rows = identityRows
        }

        let blockSerializedDB = try blockDB.serializedData()
        try blockSerializedDB.write(to: URL(fileURLWithPath: blockFile))
        print("Saved \(blockDB.rows.count) numbers to \(blockFile)")

        let identitySerializedDB = try identityDB.serializedData()
        try identitySerializedDB.write(to: URL(fileURLWithPath: identityFile))
        print("Saved \(identityDB.rows.count) numbers to \(identityFile)")
    }
}
