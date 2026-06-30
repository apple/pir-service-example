// Copyright 2026 Apple Inc. and the Swift Homomorphic Encryption project authors
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
import SwiftProtobuf

struct ReportController {
    let reportStore: ReportStore

    func addRoutes(to group: RouterGroup<AppContext>) {
        group.post("/report", use: report)
    }

    @Sendable
    func report(_ request: Request, context: AppContext) async throws -> Response {
        let timestamp = Google_Protobuf_Timestamp(date: .now)

        let receivedReport: URLFilterReport
        do {
            if request.headers[.contentType] == "application/json" {
                let urls = try await request.decodeJSON(as: [String].self, context: context)
                receivedReport = .with { report in
                    report.urls = urls
                }
            } else {
                receivedReport = try await request.decodeProto(as: URLFilterReport.self, context: context)
            }
        } catch {
            context.logger.warning("Received malformed input: \(error)")
            return .init(status: .badRequest)
        }

        let urlCount = receivedReport.urls.count

        var report = URLFilterReportWithMetadata()
        report.userAgent = request.headers[.userAgent] ?? ""
        report.receivedAt = timestamp
        report.report = receivedReport

        if let filePath = try await reportStore.save(report) {
            context.logger.info("Report written to \(filePath) with \(urlCount) blocked URLs")
        } else {
            context.logger
                .info(
                    "Report received with \(urlCount) blocked URLs but no reportDirectory configured; dropping report.")
        }

        return .init(status: .ok)
    }
}
