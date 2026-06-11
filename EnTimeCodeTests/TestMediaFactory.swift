import Foundation
import AVFoundation
import CoreMedia
@testable import EnTimeCode

/// Builds a short `.mov` fixture with a video track and a stereo LPCM audio track where channel 0
/// carries LTC and channel 1 carries a scratch tone. LPCM keeps the LTC bit-exact for decoding.
enum TestMediaFactory {
    static func makeStereoLTCMovie(start: Timecode,
                                   fps: Int = 30,
                                   seconds: Int = 2,
                                   sampleRate: Int = 48000) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Video input.
        let width = 160, height = 90
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])
        writer.add(videoInput)

        // Stereo LPCM audio input.
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)

        guard writer.startWriting() else {
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: writer.error?.localizedDescription ?? "startWriting"])
        }
        writer.startSession(atSourceTime: .zero)

        // Audio: channel 0 = LTC, channel 1 = sine scratch.
        let frameCount = sampleRate * seconds
        let ltc = LTCSignalGenerator.render(start: start, frameCount: fps * seconds,
                                            sampleRate: sampleRate, fps: fps)
        var interleaved = [Float](repeating: 0, count: frameCount * 2)
        for i in 0..<frameCount {
            interleaved[i * 2] = i < ltc.count ? ltc[i] : 0
            interleaved[i * 2 + 1] = 0.3 * sinf(2 * .pi * 1000 * Float(i) / Float(sampleRate))
        }
        let audioBuffer = try makeStereoSampleBuffer(interleaved: interleaved,
                                                     frameCount: frameCount,
                                                     asbd: &asbd,
                                                     sampleRate: sampleRate)
        while !audioInput.isReadyForMoreMediaData { usleep(1000) }
        audioInput.append(audioBuffer)
        audioInput.markAsFinished()

        // Video: solid frames.
        let totalFrames = fps * seconds
        for f in 0..<totalFrames {
            while !videoInput.isReadyForMoreMediaData { usleep(1000) }
            let pts = CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps))
            if let pb = makePixelBuffer(adaptor: adaptor, width: width, height: height, frame: f) {
                adaptor.append(pb, withPresentationTime: pts)
            }
        }
        videoInput.markAsFinished()

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw NSError(domain: "fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: writer.error?.localizedDescription ?? "finish"])
        }
        return url
    }

    private static func makeStereoSampleBuffer(interleaved: [Float],
                                               frameCount: Int,
                                               asbd: inout AudioStreamBasicDescription,
                                               sampleRate: Int) throws -> CMSampleBuffer {
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                                       layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let byteCount = interleaved.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                           blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
                                           customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        _ = interleaved.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block!,
                                          offsetIntoDestination: 0, dataLength: byteCount)
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleSize = MemoryLayout<Float>.size * 2
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block!,
                                  formatDescription: format!, sampleCount: frameCount,
                                  sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                  sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
                                  sampleBufferOut: &sb)
        return sb!
    }

    private static func makePixelBuffer(adaptor: AVAssetWriterInputPixelBufferAdaptor,
                                        width: Int, height: Int, frame: Int) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bytes = CVPixelBufferGetBytesPerRow(pb) * height
            memset(base, Int32((frame * 4) % 255), bytes)
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    /// Read the starting frame number stored in the output's `tmcd` timecode track.
    static func readTimecodeFrameNumber(url: URL) async throws -> Int? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .timecode).first else {
            throw NSError(domain: "tmcd", code: 10, userInfo: [NSLocalizedDescriptionKey: "no timecode track"])
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else {
            throw NSError(domain: "tmcd", code: 11, userInfo: [NSLocalizedDescriptionKey: "cannot add tmcd output"])
        }
        reader.add(output)
        guard reader.startReading() else {
            throw NSError(domain: "tmcd", code: 12, userInfo: [NSLocalizedDescriptionKey: "startReading: \(reader.error?.localizedDescription ?? "?")"])
        }
        var sampleCount = 0
        while let sb = output.copyNextSampleBuffer() {
            sampleCount += 1
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0
            var dataPtr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                        totalLengthOut: &length, dataPointerOut: &dataPtr)
            guard let dataPtr, length >= 4 else { continue }
            var value: Int32 = 0
            memcpy(&value, dataPtr, 4)
            return Int(Int32(bigEndian: value))
        }
        throw NSError(domain: "tmcd", code: 13, userInfo: [NSLocalizedDescriptionKey: "no usable tmcd sample (sampleCount \(sampleCount), status \(reader.status.rawValue), \(reader.error?.localizedDescription ?? "?"))"])
    }
}
