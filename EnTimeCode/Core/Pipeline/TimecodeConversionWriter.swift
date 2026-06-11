import Foundation
import AVFoundation
import CoreMedia

enum ConversionWriterError: Error, LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case writerSetup(String)
    case readerSetup(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The file has no video track."
        case .noAudioTrack: return "The file has no audio track."
        case .writerSetup(let m): return "Writer setup failed: \(m)"
        case .readerSetup(let m): return "Reader setup failed: \(m)"
        case .failed(let m): return "Conversion failed: \(m)"
        }
    }
}

/// Writes an output `.mov` that passes the source video through unchanged, carries the scratch
/// audio channel, and adds a QuickTime `tmcd` timecode track starting at `startTimecode`.
struct TimecodeConversionWriter {
    let sourceURL: URL
    let outputURL: URL
    let startTimecode: Timecode
    let rate: FrameRate
    /// Channel index that carries LTC; the *other* channel is treated as scratch audio.
    let ltcChannel: Int

    /// Runs the conversion synchronously. Call from a background task.
    /// `progress` reports 0...1 based on video time processed.
    func run(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionWriterError.noVideoTrack
        }
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionWriterError.noAudioTrack
        }

        let duration = try await asset.load(.duration)
        let videoFormats = try await videoTrack.load(.formatDescriptions)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioFormats = try await audioTrack.load(.formatDescriptions)
        let audioASBD = audioFormats.first.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        let sampleRate = audioASBD?.mSampleRate ?? 48000
        let channelCount = Int(audioASBD?.mChannelsPerFrame ?? 1)
        let scratchChannel = channelCount > 1 ? (1 - min(ltcChannel, 1)) : 0

        try? FileManager.default.removeItem(at: outputURL)

        // MARK: Reader
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil) // passthrough
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw ConversionWriterError.readerSetup("cannot add video output")
        }
        reader.add(videoOutput)

        let audioPCMSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioPCMSettings)
        audioOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(audioOutput) else {
            throw ConversionWriterError.readerSetup("cannot add audio output")
        }
        reader.add(audioOutput)

        // MARK: Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoInput = AVAssetWriterInput(mediaType: .video,
                                            outputSettings: nil,
                                            sourceFormatHint: videoFormats.first)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = preferredTransform
        guard writer.canAdd(videoInput) else {
            throw ConversionWriterError.writerSetup("cannot add video input")
        }
        writer.add(videoInput)

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: 128_000
        ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else {
            throw ConversionWriterError.writerSetup("cannot add audio input")
        }
        writer.add(audioInput)

        let tmcdFormat = try Self.makeTimecodeFormatDescription(rate: rate)
        let timecodeInput = AVAssetWriterInput(mediaType: .timecode,
                                               outputSettings: nil,
                                               sourceFormatHint: tmcdFormat)
        timecodeInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(timecodeInput) else {
            throw ConversionWriterError.writerSetup("cannot add timecode input")
        }
        writer.add(timecodeInput)

        // The video track references the timecode track.
        if videoInput.canAddTrackAssociation(withTrackOf: timecodeInput, type: AVAssetTrack.AssociationType.timecode.rawValue) {
            videoInput.addTrackAssociation(withTrackOf: timecodeInput, type: AVAssetTrack.AssociationType.timecode.rawValue)
        }

        guard reader.startReading() else {
            throw ConversionWriterError.readerSetup(reader.error?.localizedDescription ?? "startReading failed")
        }
        guard writer.startWriting() else {
            throw ConversionWriterError.writerSetup(writer.error?.localizedDescription ?? "startWriting failed")
        }
        try catchingObjCException { writer.startSession(atSourceTime: .zero) }

        // Write the single timecode sample spanning the whole track.
        let tmcdSample = try Self.makeTimecodeSampleBuffer(frameNumber: startTimecode.frameNumber,
                                                           duration: duration,
                                                           formatDescription: tmcdFormat)
        if timecodeInput.isReadyForMoreMediaData {
            _ = try Self.safeAppend(timecodeInput, tmcdSample)
        }
        timecodeInput.markAsFinished()

        // MARK: Pump video + audio (synchronous pull loop; no real-time constraint).
        var videoDone = false
        var audioDone = false
        let totalSeconds = max(duration.seconds, 0.0001)

        while !(videoDone && audioDone) {
            if reader.status == .failed {
                throw ConversionWriterError.failed(reader.error?.localizedDescription ?? "reader failed")
            }

            // Drain autoreleased CoreMedia/AVFoundation objects every iteration. Without this,
            // sample buffers from copyNextSampleBuffer accumulate and iOS terminates the app for
            // memory use (a "crash" with no catchable Swift error) on large files.
            let progressed = try autoreleasepool { () -> Bool in
                var didWork = false

                if !videoDone, videoInput.isReadyForMoreMediaData {
                    if let sb = videoOutput.copyNextSampleBuffer() {
                        if try !Self.safeAppend(videoInput, sb) {
                            videoInput.markAsFinished()
                            videoDone = true
                        } else if let progress {
                            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                            progress(min(1.0, max(0.0, pts.seconds / totalSeconds)))
                        }
                        didWork = true
                    } else {
                        videoInput.markAsFinished()
                        videoDone = true
                        didWork = true
                    }
                }

                if !audioDone, audioInput.isReadyForMoreMediaData {
                    if let sb = audioOutput.copyNextSampleBuffer() {
                        if let mono = Self.makeMonoSampleBuffer(from: sb,
                                                                channel: scratchChannel,
                                                                channelCount: channelCount,
                                                                sampleRate: sampleRate) {
                            if try !Self.safeAppend(audioInput, mono) {
                                audioInput.markAsFinished()
                                audioDone = true
                            }
                        }
                        didWork = true
                    } else {
                        audioInput.markAsFinished()
                        audioDone = true
                        didWork = true
                    }
                }

                return didWork
            }

            if !progressed {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }

        if reader.status == .reading { reader.cancelReading() }

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        if writer.status != .completed {
            throw ConversionWriterError.failed(writer.error?.localizedDescription ?? "writer did not complete")
        }
        progress?(1.0)
    }

    /// Append a sample buffer, converting any AVFoundation NSException into a thrown Swift error.
    private static func safeAppend(_ input: AVAssetWriterInput, _ sampleBuffer: CMSampleBuffer) throws -> Bool {
        var appended = false
        try catchingObjCException { appended = input.append(sampleBuffer) }
        return appended
    }

    // MARK: - Timecode media

    static func makeTimecodeFormatDescription(rate: FrameRate) throws -> CMTimeCodeFormatDescription {
        var flags: UInt32 = 0
        if rate.isDropFrame { flags |= kCMTimeCodeFlag_DropFrame }
        flags |= kCMTimeCodeFlag_24HourMax

        var fmt: CMTimeCodeFormatDescription?
        let status = CMTimeCodeFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32,
            frameDuration: rate.frameDuration,
            frameQuanta: UInt32(rate.countingBase),
            flags: flags,
            extensions: nil,
            formatDescriptionOut: &fmt
        )
        guard status == noErr, let fmt else {
            throw ConversionWriterError.writerSetup("CMTimeCodeFormatDescriptionCreate \(status)")
        }
        return fmt
    }

    static func makeTimecodeSampleBuffer(frameNumber: Int,
                                         duration: CMTime,
                                         formatDescription: CMTimeCodeFormatDescription) throws -> CMSampleBuffer {
        // tmcd media: one big-endian Int32 frame number.
        var beValue = Int32(frameNumber).bigEndian
        let dataSize = MemoryLayout<Int32>.size

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw ConversionWriterError.writerSetup("CMBlockBufferCreate \(status)")
        }
        status = withUnsafeBytes(of: &beValue) { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!,
                                          blockBuffer: blockBuffer,
                                          offsetIntoDestination: 0,
                                          dataLength: dataSize)
        }
        guard status == kCMBlockBufferNoErr else {
            throw ConversionWriterError.writerSetup("CMBlockBufferReplaceDataBytes \(status)")
        }

        var timing = CMSampleTimingInfo(duration: duration,
                                        presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        var sampleSize = dataSize
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw ConversionWriterError.writerSetup("CMSampleBufferCreateReady(tmcd) \(status)")
        }
        return sampleBuffer
    }

    // MARK: - Audio downmix to scratch channel

    /// Extract a single channel from a deinterleaved Float32 PCM sample buffer into a mono buffer.
    static func makeMonoSampleBuffer(from sampleBuffer: CMSampleBuffer,
                                     channel: Int,
                                     channelCount: Int,
                                     sampleRate: Double) -> CMSampleBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        let listSize = MemoryLayout<AudioBufferList>.size + max(0, channelCount - 1) * MemoryLayout<AudioBuffer>.size
        let ablMemory = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        let ablPointer = UnsafeMutableAudioBufferListPointer(
            ablMemory.assumingMemoryBound(to: AudioBufferList.self)
        )
        ablPointer.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(max(1, channelCount))
        defer { ablMemory.deallocate() }

        var srcBlock: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPointer.unsafeMutablePointer,
            bufferListSize: listSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &srcBlock
        )
        guard status == noErr else { return nil }

        var mono = [Float](repeating: 0, count: frameCount)
        let ch = min(channel, max(0, ablPointer.count - 1))
        if ablPointer.count > ch {
            let buffer = ablPointer[ch]
            let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            if let base = buffer.mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<min(frameCount, available) { mono[i] = base[i] }
            }
        }

        // Build mono Float32 format description.
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                             asbd: &asbd,
                                             layoutSize: 0,
                                             layout: nil,
                                             magicCookieSize: 0,
                                             magicCookie: nil,
                                             extensions: nil,
                                             formatDescriptionOut: &format) == noErr,
              let format else { return nil }

        let byteCount = frameCount * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                 memoryBlock: nil,
                                                 blockLength: byteCount,
                                                 blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil,
                                                 offsetToData: 0,
                                                 dataLength: byteCount,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        let copyStatus = mono.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!,
                                          blockBuffer: block,
                                          offsetIntoDestination: 0,
                                          dataLength: byteCount)
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var sampleSize = MemoryLayout<Float>.size
        var out: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                        dataBuffer: block,
                                        formatDescription: format,
                                        sampleCount: frameCount,
                                        sampleTimingEntryCount: 1,
                                        sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1,
                                        sampleSizeArray: &sampleSize,
                                        sampleBufferOut: &out) == noErr,
              let out else { return nil }
        return out
    }
}
