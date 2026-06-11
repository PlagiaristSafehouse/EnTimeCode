import Foundation
import AVFoundation

struct AudioFormatInfo: Sendable {
    let sampleRate: Double
    let channelCount: Int
}

/// A block of deinterleaved PCM: `samples[channel][frame]`.
struct AudioBlock: Sendable {
    /// Frame index (in samples) of the first frame in this block, from the start of the track.
    let startFrame: Int
    let samples: [[Float]]
}

enum AudioReaderError: Error {
    case noAudioTrack
    case cannotCreateReader
    case readFailed(String)
}

/// Reads a video's audio track as deinterleaved Float32 PCM, streamed in blocks so long
/// recordings don't have to be held entirely in memory.
struct AudioChannelReader {
    let asset: AVAsset

    init(url: URL) {
        self.asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    }

    init(asset: AVAsset) {
        self.asset = asset
    }

    func format() async throws -> AudioFormatInfo {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioReaderError.noAudioTrack
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let asbd = descriptions.first.flatMap({
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }) else {
            throw AudioReaderError.readFailed("Missing audio stream description")
        }
        return AudioFormatInfo(sampleRate: asbd.mSampleRate, channelCount: Int(asbd.mChannelsPerFrame))
    }

    /// Stream the audio as blocks. `onBlock` is called sequentially on the calling task.
    func read(onBlock: (AudioBlock) throws -> Void) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioReaderError.noAudioTrack
        }
        let info = try await format()
        let channelCount = max(1, info.channelCount)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioReaderError.cannotCreateReader
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AudioReaderError.readFailed("Cannot add audio output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioReaderError.readFailed(reader.error?.localizedDescription ?? "startReading failed")
        }

        var frameCursor = 0
        var keepGoing = true
        while keepGoing && reader.status == .reading {
            // Drain autoreleased CoreMedia objects each iteration to bound memory on long tracks.
            try autoreleasepool {
                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    keepGoing = false
                    return
                }

                let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
                if frameCount == 0 { return }

                var blockBuffer: CMBlockBuffer?
                let listSize = MemoryLayout<AudioBufferList>.size + (channelCount - 1) * MemoryLayout<AudioBuffer>.size
                let ablMemory = UnsafeMutableRawPointer.allocate(
                    byteCount: listSize,
                    alignment: MemoryLayout<AudioBufferList>.alignment
                )
                let ablPointer = UnsafeMutableAudioBufferListPointer(
                    ablMemory.assumingMemoryBound(to: AudioBufferList.self)
                )
                ablPointer.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(channelCount)
                defer { ablMemory.deallocate() }

                let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                    sampleBuffer,
                    bufferListSizeNeededOut: nil,
                    bufferListOut: ablPointer.unsafeMutablePointer,
                    bufferListSize: listSize,
                    blockBufferAllocator: kCFAllocatorDefault,
                    blockBufferMemoryAllocator: kCFAllocatorDefault,
                    flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                    blockBufferOut: &blockBuffer
                )
                guard status == noErr else {
                    throw AudioReaderError.readFailed("AudioBufferList status \(status)")
                }

                var channels: [[Float]] = []
                channels.reserveCapacity(channelCount)

                if ablPointer.count == channelCount {
                    // Non-interleaved: one buffer per channel.
                    for ch in 0..<channelCount {
                        let buffer = ablPointer[ch]
                        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                        if let base = buffer.mData?.assumingMemoryBound(to: Float.self) {
                            channels.append(Array(UnsafeBufferPointer(start: base, count: count)))
                        } else {
                            channels.append([Float](repeating: 0, count: count))
                        }
                    }
                } else if ablPointer.count == 1 {
                    // Interleaved fallback.
                    let buffer = ablPointer[0]
                    let total = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let perChannel = total / channelCount
                    if let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        for ch in 0..<channelCount {
                            var out = [Float](repeating: 0, count: perChannel)
                            for i in 0..<perChannel { out[i] = ptr[i * channelCount + ch] }
                            channels.append(out)
                        }
                    } else {
                        for _ in 0..<channelCount {
                            channels.append([Float](repeating: 0, count: perChannel))
                        }
                    }
                } else {
                    throw AudioReaderError.readFailed("Unexpected buffer count \(ablPointer.count)")
                }

                try onBlock(AudioBlock(startFrame: frameCursor, samples: channels))
                frameCursor += frameCount
            }
        }

        if reader.status == .failed {
            throw AudioReaderError.readFailed(reader.error?.localizedDescription ?? "reader failed")
        }
    }
}
