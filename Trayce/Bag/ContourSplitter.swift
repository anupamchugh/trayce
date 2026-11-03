import CoreGraphics

/// Splits a flat-lay photo into items without a neural model: pixels that differ from the
/// background (sampled at the corners) are grouped into connected blobs, and each blob is cropped.
nonisolated enum ContourSplitter {
    static func items(in image: CGImage, gridWidth: Int = 240) -> [CGImage] {
        let w = gridWidth
        let h = max(1, Int(Double(image.height) / Double(image.width) * Double(w)))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        let corners = [rgb(1, 1), rgb(w - 2, 1), rgb(1, h - 2), rgb(w - 2, h - 2)]
        let bg = (corners.map(\.0).reduce(0, +) / 4, corners.map(\.1).reduce(0, +) / 4, corners.map(\.2).reduce(0, +) / 4)
        var foreground = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let p = rgb(x, y)
            foreground[y * w + x] = abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) > 60
        }}

        // Connected components, 4-neighbour flood fill.
        var seen = [Bool](repeating: false, count: w * h)
        var boxes: [CGRect] = []
        for start in 0..<(w * h) where foreground[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var (minX, minY, maxX, maxY, count) = (w, h, 0, 0, 0)
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                count += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < w && ny < h {
                    let n = ny * w + nx
                    if foreground[n] && !seen[n] { seen[n] = true; stack.append(n) }
                }
            }
            // Ignore specks: anything under 0.3 % of the frame.
            if count * 1000 > w * h * 3 {
                boxes.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
            }
        }

        // The bitmap's first row is the image's top row, the same as `CGImage.cropping(to:)`.
        let scale = Double(image.width) / Double(w)
        return boxes.compactMap { box in
            let r = CGRect(x: box.minX * scale, y: box.minY * scale,
                           width: box.width * scale, height: box.height * scale).insetBy(dx: -6, dy: -6)
            return image.cropping(to: r.integral)
        }
    }
}
