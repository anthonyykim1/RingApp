import Foundation

/// Constructs framed BLE packets for the AIZO RING protocol.
///
/// Packet format: [Length 2B] [Header 2B] [SN 2B] [Payload NB] [CRC16 2B]
/// - Length: byte count of payload + CRC (big-endian)
/// - Header: 0x9240 (fixed for app→ring single packets)
/// - SN: incrementing sequence number (big-endian)
/// - CRC16: computed over payload bytes only
final class PacketFramer {
    private var sequenceNumber: UInt16 = 0
    private let header: UInt16 = 0x9240

    func frame(payload: [UInt8]) -> [UInt8] {
        let crc = Self.crc16(payload)
        let crcHi = UInt8(crc >> 8)
        let crcLo = UInt8(crc & 0xFF)
        let length = UInt16(payload.count + 2)

        var packet: [UInt8] = []
        packet.append(UInt8(length >> 8))
        packet.append(UInt8(length & 0xFF))
        packet.append(UInt8(header >> 8))
        packet.append(UInt8(header & 0xFF))
        packet.append(UInt8(sequenceNumber >> 8))
        packet.append(UInt8(sequenceNumber & 0xFF))
        packet.append(contentsOf: payload)
        packet.append(crcHi)
        packet.append(crcLo)

        sequenceNumber &+= 1
        return packet
    }

    func resetSequence() {
        sequenceNumber = 0
    }

    static func crc16(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc = ((crc << 8) | (crc >> 8)) & 0xFFFF
            crc ^= UInt16(byte)
            crc ^= (crc & 0xFF) >> 4
            crc ^= (crc << 12) & 0xFFFF
            crc ^= ((crc & 0xFF) << 5) & 0xFFFF
        }
        return crc
    }
}
