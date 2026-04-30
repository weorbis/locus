import Foundation
import Compression

/// Errors thrown by `GzipEncoder.encode`.
public enum GzipEncoderError: Error, Equatable {
    /// `compression_stream` rejected the input or could not allocate state.
    case compressionFailed(status: Int32)
    /// The input exceeded the gzip ISIZE field (uint32; 4 GiB). Real Locus
    /// payloads are tens of KB so this is a defensive bound, not a real limit.
    case inputTooLarge
}

/// Produces RFC 1952 (gzip) compressed bytes suitable for use as an HTTP
/// request body with the `Content-Encoding: gzip` header.
///
/// Wire layout:
///   `[10-byte gzip header][raw deflate stream][CRC32 of input, LE][input size mod 2^32, LE]`
///
/// Apple's `Compression` framework only offers `COMPRESSION_ZLIB`, which emits
/// a *raw* deflate stream (no RFC 1950 zlib header/trailer). We wrap that with
/// the gzip framing manually; CRC32 is computed in pure Swift via the standard
/// IEEE 802.3 polynomial so we don't need to link `libz`.
public enum GzipEncoder {

    /// Standard gzip header: ID1=0x1f, ID2=0x8b, CM=0x08 (deflate), FLG=0,
    /// MTIME=0 (no timestamp), XFL=0, OS=0xff (unknown).
    private static let header: [UInt8] = [
        0x1f, 0x8b, 0x08, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0xff,
    ]

    /// Encodes `data` as a gzip stream.
    ///
    /// - Throws: `GzipEncoderError.compressionFailed` when `compression_stream`
    ///   fails (e.g. transient OS-level memory pressure). Callers should fall
    ///   back to sending the uncompressed body.
    public static func encode(_ data: Data) throws -> Data {
        if data.isEmpty {
            // Empty payload: still emit a valid gzip stream (header + empty
            // deflate block + CRC32(0) + ISIZE(0)). compression_encode_buffer
            // returns 0 on empty input which is ambiguous with failure, so we
            // short-circuit.
            var out = Data()
            out.append(contentsOf: header)
            // Empty stored deflate block: 0x03, 0x00 (BFINAL=1, BTYPE=00,
            // LEN=0, NLEN=0xffff packed). compression_stream actually emits a
            // 2-byte empty deflate block; reproduce that constant here.
            out.append(contentsOf: [0x03, 0x00])
            out.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // CRC32(empty)
            out.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // ISIZE(empty)
            return out
        }

        guard data.count <= UInt32.max else {
            throw GzipEncoderError.inputTooLarge
        }

        let deflated = try deflateRaw(data)

        var out = Data(capacity: header.count + deflated.count + 8)
        out.append(contentsOf: header)
        out.append(deflated)

        let crc = crc32(of: data)
        out.append(UInt8(truncatingIfNeeded: crc))
        out.append(UInt8(truncatingIfNeeded: crc >> 8))
        out.append(UInt8(truncatingIfNeeded: crc >> 16))
        out.append(UInt8(truncatingIfNeeded: crc >> 24))

        let isize = UInt32(truncatingIfNeeded: data.count)
        out.append(UInt8(truncatingIfNeeded: isize))
        out.append(UInt8(truncatingIfNeeded: isize >> 8))
        out.append(UInt8(truncatingIfNeeded: isize >> 16))
        out.append(UInt8(truncatingIfNeeded: isize >> 24))

        return out
    }

    // MARK: - Raw deflate via compression_stream

    /// Streams `input` through `compression_stream` with `COMPRESSION_ZLIB`,
    /// which emits a raw deflate bitstream (no zlib framing). The streaming
    /// API is used (vs `compression_encode_buffer`) because the destination
    /// size for highly-redundant inputs is hard to predict ahead of time —
    /// streaming lets us grow the output buffer as needed.
    private static func deflateRaw(_ input: Data) throws -> Data {
        let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPointer.deallocate() }

        var status = compression_stream_init(streamPointer, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else {
            throw GzipEncoderError.compressionFailed(status: status.rawValue)
        }
        defer { compression_stream_destroy(streamPointer) }

        // 64 KiB destination chunks — the OkHttp/iOS stack handles arbitrary
        // request body sizes so the chunk size only affects how many loop
        // iterations we run, not correctness.
        let destCapacity = 64 * 1024
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destCapacity)
        defer { destBuffer.deallocate() }

        var output = Data()

        try input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) in
            let inputBase = inputBytes.bindMemory(to: UInt8.self).baseAddress!
            streamPointer.pointee.src_ptr = inputBase
            streamPointer.pointee.src_size = input.count
            streamPointer.pointee.dst_ptr = destBuffer
            streamPointer.pointee.dst_size = destCapacity

            while true {
                status = compression_stream_process(streamPointer, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK:
                    // Destination full — drain and continue.
                    let written = destCapacity - streamPointer.pointee.dst_size
                    if written > 0 {
                        output.append(destBuffer, count: written)
                    }
                    streamPointer.pointee.dst_ptr = destBuffer
                    streamPointer.pointee.dst_size = destCapacity
                case COMPRESSION_STATUS_END:
                    let written = destCapacity - streamPointer.pointee.dst_size
                    if written > 0 {
                        output.append(destBuffer, count: written)
                    }
                    return
                default:
                    throw GzipEncoderError.compressionFailed(status: status.rawValue)
                }
            }
        }

        return output
    }

    // MARK: - CRC32 (IEEE 802.3 polynomial 0xEDB88320)

    /// Lazily-built lookup table for the standard CRC32 polynomial used by gzip.
    /// The compiler doesn't fold this at compile time, but it's only built once
    /// per process and amortizes across every batch.
    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1
            }
            table[i] = c
        }
        return table
    }()

    /// Computes the CRC32 of `data` using the IEEE 802.3 polynomial. Matches
    /// `zlib.crc32` byte-for-byte; verified against the reference vector
    /// `crc32(b"123456789") == 0xCBF43926`.
    public static func crc32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        let table = crcTable
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<data.count {
                let byte = base[i]
                let idx = Int((crc ^ UInt32(byte)) & 0xff)
                crc = table[idx] ^ (crc >> 8)
            }
        }
        return crc ^ 0xffff_ffff
    }
}
