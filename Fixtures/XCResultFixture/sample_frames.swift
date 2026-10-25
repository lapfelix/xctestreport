// Prints the average RGB of the top tenth of a video at each requested time (seconds).
// Usage: xcrun swift sample_frames.swift <video> <time>...
import AVFoundation
import CoreGraphics
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let arguments = CommandLine.arguments.dropFirst()
guard let path = arguments.first else {
    FileHandle.standardError.write(Data("Usage: sample_frames.swift <video> <time>...\n".utf8))
    exit(2)
}

let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

for argument in arguments.dropFirst() {
    guard let seconds = Double(argument) else { exit(2) }
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    guard let image = try? await generator.image(at: time).image else {
        print("\(argument) none")
        continue
    }
    let width = 32, height = 32
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        // Scale the whole frame into 32x32; the top three rows are the top tenth.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else {
        print("\(argument) none")
        continue
    }
    var sums = [0, 0, 0]
    let rows = 3
    for row in 0..<rows {
        for column in 0..<width {
            let index = (row * width + column) * 4
            for channel in 0..<3 { sums[channel] += Int(pixels[index + channel]) }
        }
    }
    let count = rows * width
    print("\(argument) \(sums[0] / count) \(sums[1] / count) \(sums[2] / count)")
}
