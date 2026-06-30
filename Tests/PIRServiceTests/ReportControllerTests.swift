// Copyright 2025-2026 Apple Inc. and the Swift Homomorphic Encryption project authors
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
import HummingbirdTesting
@testable import PIRService
@testable import PIRServiceTesting
import SwiftProtobuf
import Testing
import Util

struct ReportControllerTests {
    @Test
    func reportWrittenWhenDirectoryConfigured() async throws {
        let reportStore = ReportStore()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        await reportStore.set(reportDirectory: tmpDir.path)
        let app = try await buildApplication(reportStore: reportStore)

        let report = URLFilterReport.with { $0.urls = ["https://example.com", "https://blocked.com"] }

        try await app.test(.live) { client in
            try await client.execute(uri: "/report", message: report) { response in
                #expect(response.status == .ok)
            }
        }

        let writtenFiles = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        #expect(writtenFiles.count == 1)
        #expect(await reportStore.savedReportCount == 1)
        let writtenFile = try tmpDir.appendingPathComponent(#require(writtenFiles.first))
        let data = try String(contentsOf: writtenFile, encoding: .utf8)
        let decoded = try URLFilterReportWithMetadata(textFormatString: data)
        #expect(decoded.report.urls == ["https://example.com", "https://blocked.com"])
        #expect(!decoded.userAgent.isEmpty)
        #expect(decoded.hasReceivedAt)
    }

    @Test
    func reportWrittenWhenDirectoryConfiguredJSON() async throws {
        let reportStore = ReportStore()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        await reportStore.set(reportDirectory: tmpDir.path)
        let app = try await buildApplication(reportStore: reportStore)

        let urls = ["https://example.com", "https://blocked.com"]
        let jsonData = try JSONEncoder().encode(urls)
        let body = ByteBuffer(data: jsonData)

        try await app.test(.live) { client in
            var headers = HTTPFields()
            headers[.userAgent] = Platform.iOS18.exampleUserAgent
            headers[.contentType] = "application/json"

            try await client.execute(
                uri: "/report",
                method: .post,
                headers: headers,
                body: body)
            { response in
                #expect(response.status == .ok)
            }
        }

        let writtenFiles = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        #expect(writtenFiles.count == 1)
        #expect(await reportStore.savedReportCount == 1)
        let writtenFile = try tmpDir.appendingPathComponent(#require(writtenFiles.first))
        let data = try String(contentsOf: writtenFile, encoding: .utf8)
        let decoded = try URLFilterReportWithMetadata(textFormatString: data)
        #expect(decoded.report.urls == urls)
        #expect(!decoded.userAgent.isEmpty)
        #expect(decoded.hasReceivedAt)
    }

    @Test
    func reportDroppedWhenNoDirectoryConfigured() async throws {
        let reportStore = ReportStore()
        // reportDirectory is nil — report should be dropped
        let app = try await buildApplication(reportStore: reportStore)
        let user = UserIdentifier()

        let report = URLFilterReport.with { $0.urls = ["https://example.com"] }

        try await app.test(.live) { client in
            try await client.execute(uri: "/report", userIdentifier: user, message: report) { response in
                #expect(response.status == .ok)
            }
        }

        #expect(await reportStore.savedReportCount == 0)
    }

    @Test
    func reportDroppedWhenNoDirectoryConfiguredJSON() async throws {
        let reportStore = ReportStore()
        // reportDirectory is nil — report should be dropped
        let app = try await buildApplication(reportStore: reportStore)
        let user = UserIdentifier()
        let userIdentifierName = try #require(HTTPField.Name("User-Identifier"))

        let urls = ["https://example.com"]
        let jsonData = try JSONEncoder().encode(urls)
        let body = ByteBuffer(data: jsonData)

        try await app.test(.live) { client in
            try await client.execute(
                uri: "/report",
                method: .post,
                headers: [userIdentifierName: user.identifier, .contentType: "application/json"],
                body: body)
            { response in
                #expect(response.status == .ok)
            }
        }

        #expect(await reportStore.savedReportCount == 0)
    }

    @Test
    func malformedBodyReturnsBadRequest() async throws {
        let app = try await buildApplication()
        let user = UserIdentifier()
        let userIdentifierName = try #require(HTTPField.Name("User-Identifier"))

        try await app.test(.live) { client in
            try await client.execute(
                uri: "/report",
                method: .post,
                headers: [userIdentifierName: user.identifier],
                body: ByteBuffer(bytes: [0xFF, 0xFE, 0x00]))
            { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test
    func malformedJSONBodyReturnsBadRequest() async throws {
        let app = try await buildApplication()
        let user = UserIdentifier()
        let userIdentifierName = try #require(HTTPField.Name("User-Identifier"))

        try await app.test(.live) { client in
            try await client.execute(
                uri: "/report",
                method: .post,
                headers: [userIdentifierName: user.identifier, .contentType: "application/json"],
                body: ByteBuffer(string: "{invalid json"))
            { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test
    func emptyJSONArrayWritesReport() async throws {
        let reportStore = ReportStore()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        await reportStore.set(reportDirectory: tmpDir.path)
        let app = try await buildApplication(reportStore: reportStore)
        let user = UserIdentifier()
        let userIdentifierName = try #require(HTTPField.Name("User-Identifier"))

        let urls: [String] = []
        let jsonData = try JSONEncoder().encode(urls)
        let body = ByteBuffer(data: jsonData)

        try await app.test(.live) { client in
            try await client.execute(
                uri: "/report",
                method: .post,
                headers: [userIdentifierName: user.identifier, .contentType: "application/json"],
                body: body)
            { response in
                #expect(response.status == .ok)
            }
        }

        let writtenFiles = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        #expect(writtenFiles.count == 1)
        #expect(await reportStore.savedReportCount == 1)
        let writtenFile = try tmpDir.appendingPathComponent(#require(writtenFiles.first))
        let data = try String(contentsOf: writtenFile, encoding: .utf8)
        let decoded = try URLFilterReportWithMetadata(textFormatString: data)
        #expect(decoded.report.urls.isEmpty)
        #expect(decoded.hasReceivedAt)
    }
}
