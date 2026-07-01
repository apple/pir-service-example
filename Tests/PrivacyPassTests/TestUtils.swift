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

import Testing

public extension [UInt8] {
    init?(hexEncoded hexString: String) {
        // Ensure the string has an even number of characters
        guard hexString.count.isMultiple(of: 2) else {
            return nil
        }

        var data = Array()
        data.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex

        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil // Invalid hex string
            }
            index = nextIndex
        }

        self = data
    }

    func hexEncodedString() -> String {
        reduce(into: "") { $0 += String(format: "%02x", $1) }
    }
}

struct TestUtilTests {
    @Test
    func testHexString() {
        #expect(Array(base64Encoded: "AAAA") == Array(hexEncoded: "000000"))
        #expect(Array(base64Encoded: "AAAB") == Array(hexEncoded: "000001"))
        let data = (0..<71).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        let hexString = data.hexEncodedString()
        #expect(Array(hexEncoded: hexString) == data)
    }
}
