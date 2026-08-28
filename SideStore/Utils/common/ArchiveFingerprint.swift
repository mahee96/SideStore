//
//  ArchiveFingerprint.swift
//  SideStore
//
//  Created by Magesh K on 28/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CryptoKit

public enum ArchiveFingerprint {
    
    private static let minZipSize: UInt64 = 22
    private static let minEOCDSize: Int = 22
    private static let maxCommentLength: Int = 65536
    private static let fallbackChunkSize: Int = 65536
    
    private static let eocdSignatureBytes: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
    private static let zip64LocatorSignature: UInt32 = 0x07064b50
    private static let zip64EOCDSignature: UInt32 = 0x06064b50
    private static let zip32Limit: UInt32 = 0xFFFFFFFF
    
    private static let eocdCentralDirSizeOffset = 12
    private static let eocdCentralDirOffsetOffset = 16
    
    private static let zip64LocatorSize = 20
    private static let zip64LocatorEOCDOffsetOffset = 8
    
    private static let zip64EOCDHeaderSize = 56
    private static let zip64EOCDCentralDirSizeOffset = 40
    private static let zip64EOCDCentralDirOffsetOffset = 48
    
    public static func compute(for url: URL) -> String? {
        guard url.isFileURL, let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fileHandle.close() }
        
        guard let fileSize = try? fileHandle.seekToEnd(), fileSize >= minZipSize else {
            return nil
        }
        
        if let centralDirectoryData = readCentralDirectory(from: fileHandle, fileSize: fileSize) {
            return hashData(centralDirectoryData, fileSize: fileSize)
        }
        
        return computeFallbackHash(from: fileHandle, fileSize: fileSize)
    }
    
    private static func hashData(_ data: Data, fileSize: UInt64) -> String {
        var hasher = SHA256()
        var sizeLE = fileSize.littleEndian
        withUnsafeBytes(of: &sizeLE) { hasher.update(bufferPointer: $0) }
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    
    private static func computeFallbackHash(from fileHandle: FileHandle, fileSize: UInt64) -> String? {
        var hasher = SHA256()
        var sizeLE = fileSize.littleEndian
        withUnsafeBytes(of: &sizeLE) { hasher.update(bufferPointer: $0) }
        
        guard (try? fileHandle.seek(toOffset: 0)) != nil,
              let headChunk = try? fileHandle.read(upToCount: fallbackChunkSize) else {
            return nil
        }
        hasher.update(data: headChunk)
        
        let chunkSize64 = UInt64(fallbackChunkSize)
        if fileSize > chunkSize64 {
            let tailOffset = max(chunkSize64, fileSize - chunkSize64)
            guard (try? fileHandle.seek(toOffset: tailOffset)) != nil,
                  let tailChunk = try? fileHandle.read(upToCount: fallbackChunkSize) else {
                return nil
            }
            hasher.update(data: tailChunk)
        }
        
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    
    private static func readCentralDirectory(from fileHandle: FileHandle, fileSize: UInt64) -> Data? {
        let maxSearchSize = min(fileSize, UInt64(maxCommentLength + minEOCDSize))
        let searchOffset = fileSize - maxSearchSize
        guard (try? fileHandle.seek(toOffset: searchOffset)) != nil,
              let searchData = try? fileHandle.read(upToCount: Int(maxSearchSize)),
              let eocdIndex = findEOCDIndex(in: searchData) else {
            return nil
        }
        
        let cdSize = searchData.subdata(in: (eocdIndex + eocdCentralDirSizeOffset)..<(eocdIndex + eocdCentralDirSizeOffset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
        let cdOffset = searchData.subdata(in: (eocdIndex + eocdCentralDirOffsetOffset)..<(eocdIndex + eocdCentralDirOffsetOffset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
        
        var finalCDOffset = UInt64(cdOffset)
        var finalCDSize = UInt64(cdSize)
        
        if (cdOffset == zip32Limit || cdSize == zip32Limit),
           let zip64 = resolveZip64CentralDirectory(from: fileHandle, searchData: searchData, eocdIndex: eocdIndex) {
            finalCDOffset = zip64.offset
            finalCDSize = zip64.size
        }
        
        guard finalCDOffset + finalCDSize <= fileSize,
              (try? fileHandle.seek(toOffset: finalCDOffset)) != nil,
              let cdData = try? fileHandle.read(upToCount: Int(finalCDSize)) else {
            return nil
        }
        
        return cdData
    }
    
    private static func findEOCDIndex(in searchData: Data) -> Int? {
        let bytes = [UInt8](searchData)
        guard bytes.count >= minEOCDSize else { return nil }
        for i in stride(from: bytes.count - minEOCDSize, through: 0, by: -1) {
            if bytes[i] == eocdSignatureBytes[0] &&
               bytes[i + 1] == eocdSignatureBytes[1] &&
               bytes[i + 2] == eocdSignatureBytes[2] &&
               bytes[i + 3] == eocdSignatureBytes[3] {
                return i
            }
        }
        return nil
    }
    
    private static func resolveZip64CentralDirectory(
        from fileHandle: FileHandle,
        searchData: Data,
        eocdIndex: Int
    ) -> (offset: UInt64, size: UInt64)? {
        guard eocdIndex >= zip64LocatorSize else { return nil }
        let locatorStart = eocdIndex - zip64LocatorSize
        
        let locatorSig = searchData.subdata(in: locatorStart..<(locatorStart + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard locatorSig == zip64LocatorSignature else { return nil }
        
        let zip64EOCDOffset = searchData.subdata(in: (locatorStart + zip64LocatorEOCDOffsetOffset)..<(locatorStart + zip64LocatorEOCDOffsetOffset + 8)).withUnsafeBytes { $0.load(as: UInt64.self) }
        
        guard (try? fileHandle.seek(toOffset: zip64EOCDOffset)) != nil,
              let zip64EOCDData = try? fileHandle.read(upToCount: zip64EOCDHeaderSize),
              zip64EOCDData.count >= zip64EOCDHeaderSize else {
            return nil
        }
        
        let sig = zip64EOCDData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard sig == zip64EOCDSignature else { return nil }
        
        let cdSize = zip64EOCDData.subdata(in: zip64EOCDCentralDirSizeOffset..<(zip64EOCDCentralDirSizeOffset + 8)).withUnsafeBytes { $0.load(as: UInt64.self) }
        let cdOffset = zip64EOCDData.subdata(in: zip64EOCDCentralDirOffsetOffset..<(zip64EOCDCentralDirOffsetOffset + 8)).withUnsafeBytes { $0.load(as: UInt64.self) }
        
        return (cdOffset, cdSize)
    }
}
