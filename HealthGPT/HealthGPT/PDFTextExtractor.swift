import Foundation
import PDFKit
import Vision
import CoreGraphics

struct PDFTextExtractor {

    /// Extracts text from a PDF. Tries embedded text first, then OCR fallback if needed.
    static func extractText(from url: URL) async -> String? {
        guard let document = PDFDocument(url: url) else {
            print("❌ Could not load PDF from URL: \(url.lastPathComponent)")
            return nil
        }

        // --- 1) Try embedded text (fast path)
        var embeddedText: [String] = []
        for i in 0..<document.pageCount {
            if let text = document.page(at: i)?
                .string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                embeddedText.append(text)
            }
        }

        let combinedEmbedded = embeddedText
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !combinedEmbedded.isEmpty {
            print("✅ Extracted embedded PDF text: \(combinedEmbedded.count) characters.")
            return combinedEmbedded
        }

        // --- 2) OCR fallback (throttled & memory-friendly)
        print("🔍 No embedded text found. Falling back to OCR…")
        var ocrPieces: [String] = []
        ocrPieces.reserveCapacity(document.pageCount)

        for i in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: i) else { return }

                // 220 dpi is usually enough for high-quality OCR and runs cooler than 300 dpi
                guard let cgImage = renderPageToCGImage(page, dpi: 220) else {
                    print("⚠️ Page \(i + 1): could not render to image.")
                    return
                }

                if let pageText = ocrText(from: cgImage) {
                    print("✅ Page \(i + 1): OCR produced \(pageText.count) chars.")
                    ocrPieces.append(pageText)
                } else {
                    print("⚠️ Page \(i + 1): OCR returned no text.")
                }
            }
        }

        let joinedOCR = ocrPieces
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return joinedOCR.isEmpty ? nil : joinedOCR
    }

    // MARK: - Rendering

    /// Renders a PDF page to a CGImage with a pixel cap to keep memory/thermals under control.
    private static func renderPageToCGImage(_ page: PDFPage, dpi: CGFloat = 220) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        var scale = max(dpi, 72) / 72.0

        // Cap total pixels to ~10 MP (prevents RAM spikes on huge pages)
        let maxPixels: CGFloat = 10_000_000
        let estPixels = (pageRect.width * scale) * (pageRect.height * scale)
        if estPixels > maxPixels {
            scale *= sqrt(maxPixels / max(1, estPixels))
        }

        let pixelWidth  = Int((pageRect.width  * scale).rounded(.toNearestOrAwayFromZero))
        let pixelHeight = Int((pageRect.height * scale).rounded(.toNearestOrAwayFromZero))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)

        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: scale, y: -scale)

        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: - Vision OCR

    private static func ocrText(from cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.015
        // Limit languages to reduce compute if you only need a few
        request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])

            // request.results is already `[VNRecognizedTextObservation]?`
            guard let observations = request.results, !observations.isEmpty else {
                return nil
            }

            // Collect best candidates in order; keep as lines to avoid heavy layout work
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let text = lines
                .joined(separator: "\n")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return text.isEmpty ? nil : text
        } catch {
            print("❌ Vision OCR failed: \(error.localizedDescription)")
            return nil
        }
    }
}

