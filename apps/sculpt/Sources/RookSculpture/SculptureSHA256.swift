import Foundation

/// SHA256 used by the compact container checksum and linked-file digests.
/// One implementation on every host, so a file written on macOS still checks on Linux.
internal enum SculptureSHA256 {
    internal static let byteCount = 32

    internal static func hash(_ data: Data) -> Data {
        PortableSHA256.digest(data)
    }

    internal static func hex(_ data: Data) -> String {
        hash(data).map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
    }
}

private enum PortableSHA256 {
    static func digest(_ data: Data) -> Data {
        var state = State()
        data.withUnsafeBytes { raw in
            state.update(raw.bindMemory(to: UInt8.self))
        }
        return state.finalize()
    }

    private struct State {
        private var hash: [UInt32] = [
            0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A,
            0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19,
        ]
        private var block = [UInt8](repeating: 0, count: 64)
        private var blockCount = 0
        private var bitLength: UInt64 = 0

        mutating func update(_ bytes: UnsafeBufferPointer<UInt8>) {
            var index = 0
            while index < bytes.count {
                let copied = min(64 - blockCount, bytes.count - index)
                for offset in 0..<copied {
                    block[blockCount + offset] = bytes[index + offset]
                }
                blockCount += copied
                index += copied
                bitLength &+= UInt64(copied) &* 8
                if blockCount == 64 {
                    compress(block)
                    blockCount = 0
                }
            }
        }

        mutating func finalize() -> Data {
            block[blockCount] = 0x80
            blockCount += 1
            if blockCount > 56 {
                while blockCount < 64 {
                    block[blockCount] = 0
                    blockCount += 1
                }
                compress(block)
                blockCount = 0
            }
            while blockCount < 56 {
                block[blockCount] = 0
                blockCount += 1
            }
            var length = bitLength.bigEndian
            withUnsafeBytes(of: &length) { raw in
                for byte in raw {
                    block[blockCount] = byte
                    blockCount += 1
                }
            }
            compress(block)
            var output = Data(count: 32)
            for index in 0..<8 {
                var word = hash[index].bigEndian
                let start = index * 4
                withUnsafeBytes(of: &word) { raw in
                    output.replaceSubrange(start..<(start + 4), with: raw)
                }
            }
            return output
        }

        private mutating func compress(_ block: [UInt8]) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = index * 4
                words[index] =
                    UInt32(block[offset]) << 24 | UInt32(block[offset + 1]) << 16 | UInt32(block[offset + 2]) << 8
                    | UInt32(block[offset + 3])
            }
            for index in 16..<64 {
                let earlier = words[index - 15]
                let recent = words[index - 2]
                let small = rotate(earlier, 7) ^ rotate(earlier, 18) ^ (earlier >> 3)
                let large = rotate(recent, 17) ^ rotate(recent, 19) ^ (recent >> 10)
                words[index] = words[index - 16] &+ small &+ words[index - 7] &+ large
            }
            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]
            for index in 0..<64 {
                let sum1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ sum1 &+ choice &+ roundConstants[index] &+ words[index]
                let sum0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }

        private func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
            (value >> count) | (value << (32 - count))
        }
    }

    private static let roundConstants: [UInt32] = [
        0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
        0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3, 0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
        0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
        0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
        0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13, 0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
        0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
        0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
        0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208, 0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
    ]
}
