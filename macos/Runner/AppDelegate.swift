import Cocoa
import FlutterMacOS
import AVFoundation
import CoreGraphics
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

// MARK: - Decoder-only seek thumbnail bridge

@_cdecl("mirushin_seek_thumbnail_decode")
func mirushinSeekThumbnailDecode(
  _ input: UnsafePointer<CChar>?,
  _ httpHeaders: UnsafePointer<CChar>?,
  _ targetMs: Int64,
  _ targetWidth: Int32,
  _ rgba: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
  _ rgbaLength: UnsafeMutablePointer<Int32>?,
  _ width: UnsafeMutablePointer<Int32>?,
  _ height: UnsafeMutablePointer<Int32>?,
  _ decodedMs: UnsafeMutablePointer<Int64>?,
  _ error: UnsafeMutablePointer<CChar>?,
  _ errorCapacity: Int32
) -> Int32 {
  guard
    let input = input,
    let rgba = rgba,
    let rgbaLength = rgbaLength,
    let width = width,
    let height = height,
    let decodedMs = decodedMs
  else { return -1 }
  rgba.pointee = nil
  rgbaLength.pointee = 0
  width.pointee = 0
  height.pointee = 0
  decodedMs.pointee = -1

  let value = String(cString: input)
  let url = value.contains("://")
    ? URL(string: value)
    : URL(fileURLWithPath: value)
  guard let url = url else {
    mirushinWriteThumbnailError("Invalid thumbnail input.", error, errorCapacity)
    return -2
  }

  do {
    let headers = mirushinThumbnailHeaders(httpHeaders)
    let options: [String: Any]? = headers.isEmpty
      ? nil
      : ["AVURLAssetHTTPHeaderFieldsKey": headers]
    let asset = options == nil
      ? AVURLAsset(url: url)
      : AVURLAsset(url: url, options: options)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
    var actual = CMTime.zero
    let image = try generator.copyCGImage(
      at: CMTime(seconds: Double(max(0, targetMs)) / 1000.0, preferredTimescale: 600),
      actualTime: &actual
    )
    let outputWidth = max(1, Int(targetWidth))
    let outputHeight = max(1, Int((Double(image.height) * Double(outputWidth) / Double(image.width)).rounded()))
    let byteCount = outputWidth * outputHeight * 4
    guard let pixels = malloc(byteCount)?.bindMemory(to: UInt8.self, capacity: byteCount) else {
      mirushinWriteThumbnailError("Allocate thumbnail pixels failed.", error, errorCapacity)
      return -3
    }
    guard
      let context = CGContext(
        data: pixels,
        width: outputWidth,
        height: outputHeight,
        bitsPerComponent: 8,
        bytesPerRow: outputWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      free(pixels)
      mirushinWriteThumbnailError("Create thumbnail scaler failed.", error, errorCapacity)
      return -4
    }
    context.translateBy(x: 0, y: CGFloat(outputHeight))
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
    rgba.pointee = pixels
    rgbaLength.pointee = Int32(byteCount)
    width.pointee = Int32(outputWidth)
    height.pointee = Int32(outputHeight)
    let seconds = CMTimeGetSeconds(actual)
    decodedMs.pointee = seconds.isFinite ? Int64((seconds * 1000).rounded()) : targetMs
    return 0
  } catch {
    mirushinWriteThumbnailError("AVFoundation thumbnail decode failed.", error, errorCapacity)
    return -5
  }
}

@_cdecl("mirushin_seek_thumbnail_free")
func mirushinSeekThumbnailFree(_ data: UnsafeMutablePointer<UInt8>?) {
  free(data)
}

private func mirushinWriteThumbnailError(
  _ message: String,
  _ output: UnsafeMutablePointer<CChar>?,
  _ capacity: Int32
) {
  guard let output = output, capacity > 0 else { return }
  let bytes = Array(message.utf8CString.prefix(Int(capacity) - 1)) + [0]
  bytes.withUnsafeBufferPointer { buffer in
    output.update(from: buffer.baseAddress!, count: buffer.count)
  }
}

private func mirushinThumbnailHeaders(
  _ input: UnsafePointer<CChar>?
) -> [String: String] {
  guard let input = input else { return [:] }
  var headers: [String: String] = [:]
  for line in String(cString: input).components(separatedBy: "\r\n") {
    guard let colon = line.firstIndex(of: ":") else { continue }
    let name = line[..<colon].trimmingCharacters(in: .whitespaces)
    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    if !name.isEmpty { headers[name] = value }
  }
  return headers
}
