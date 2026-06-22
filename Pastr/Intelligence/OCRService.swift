import Foundation
import Vision
import CoreGraphics
import AppKit

/// Extracts text from image clips using on-device Vision OCR. Works on macOS 14+.
enum OCRService {
    /// Recognise text in image data. Returns `nil` if nothing legible is found.
    /// Runs synchronously on the calling (background) queue.
    static func recognizeText(in imageData: Data) -> String? {
        guard let cgImage = cgImage(from: imageData) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Skip tiny artefacts; we only want real text.
        request.minimumTextHeight = 0.0

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func cgImage(from data: Data) -> CGImage? {
        if let bitmap = NSBitmapImageRep(data: data),
           let cg = bitmap.cgImage {
            return cg
        }
        if let image = NSImage(data: data) {
            var rect = CGRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return nil
    }
}
