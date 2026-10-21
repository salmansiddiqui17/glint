import CoreGraphics
import Testing
@testable import GlintCore

struct RendererTests {
    func render(_ image: CGImage, _ selection: CGRect, scale: CGFloat, standard: Bool = false,
                _ annotations: [Annotation] = []) -> CGImage? {
        Renderer.renderSelection(image, scale: scale, annotations: annotations, selection: selection,
                                 standardResolution: standard)
    }

    // MARK: Cropping and resolution (FR-42, FR-45, NFR-10)

    @Test func cropsNativePixels() throws {
        let image = makeTestImage(width: 200, height: 100)   // a 100×50 pt display at 2×
        let cropped = try #require(render(image, CGRect(x: 10, y: 5, width: 30, height: 20), scale: 2))
        #expect(cropped.width == 60 && cropped.height == 40)
    }

    @Test(arguments: [false, true])
    func outputAlwaysMatchesTheBadgeEvenAtTheImageEdge(standard: Bool) throws {
        let image = makeTestImage(width: 200, height: 100)
        let selection = CGRect(x: 90, y: 40, width: 20.4, height: 20)   // runs past the image's right edge
        let cropped = try #require(render(image, selection, scale: 2, standard: standard))
        let badge = OutputGeometry.outputPixelSize(for: selection, scale: 2,
                                                   imageSize: PixelSize(width: 200, height: 100),
                                                   standardResolution: standard)
        #expect(PixelSize(width: cropped.width, height: cropped.height) == badge)
    }

    @Test func cropUsesTopLeftOrigin() throws {
        let image = makeTestImage(width: 20, height: 10)     // red marker in the top-left pixel
        let cropped = try #require(render(image, CGRect(x: 0, y: 0, width: 4, height: 4), scale: 1))
        #expect(topLeftPixelIsRed(cropped))
        let elsewhere = try #require(render(image, CGRect(x: 10, y: 5, width: 4, height: 4), scale: 1))
        #expect(!topLeftPixelIsRed(elsewhere))
    }

    @Test func standardResolutionKeepsContentOrientationAndColourSpace() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = makeTestImage(width: 300, height: 150, marker: 3, space: p3)   // 100 × 50 pt at 3×
        let cropped = try #require(render(image, CGRect(x: 0, y: 0, width: 50, height: 20), scale: 3, standard: true))
        #expect(cropped.width == 50 && cropped.height == 20)
        #expect(cropped.colorSpace?.name == CGColorSpace.displayP3)
        #expect(topLeftPixelIsRed(cropped))
        let elsewhere = try #require(render(image, CGRect(x: 10, y: 10, width: 20, height: 20), scale: 3,
                                            standard: true))
        #expect(!topLeftPixelIsRed(elsewhere))
    }

    @Test(arguments: [CGColorSpace.extendedLinearDisplayP3 as String, CGColorSpace.extendedSRGB as String])
    func standardResolutionWorksForExtendedRangeSources(spaceName: String) throws {
        let space = try #require(CGColorSpace(name: spaceName as CFString))
        let image = makeTestImage(width: 300, height: 150, marker: 3, space: space, deep: true)
        let cropped = try #require(render(image, CGRect(x: 0, y: 0, width: 50, height: 20), scale: 3, standard: true))
        #expect(cropped.width == 50 && cropped.height == 20)
        #expect(cropped.colorSpace?.name as String? == spaceName)
        #expect(topLeftPixelIsRed(cropped))
    }

    @Test(arguments: [false, true])
    func opaqueSourcesStayOpaque(deep: Bool) throws {
        let bitmapInfo = deep
            ? CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGImageByteOrderInfo.order16Little.rawValue
            : CGImageAlphaInfo.noneSkipFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue
        let context = try #require(CGContext(data: nil, width: 30, height: 30, bitsPerComponent: deep ? 16 : 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                             bitmapInfo: bitmapInfo))
        let image = try #require(context.makeImage())
        for standard in [false, true] {
            let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 10, height: 10), scale: 3,
                                               standard: standard))
            #expect([.none, .noneSkipFirst, .noneSkipLast].contains(rendered.alphaInfo))
        }
    }

    @Test func returnsNilForEmptySelection() {
        let image = makeTestImage(width: 10, height: 10)
        #expect(render(image, .zero, scale: 1) == nil)
        #expect(render(image, CGRect(x: 2, y: 2, width: 0, height: 5), scale: 2, standard: true) == nil)
    }

    @Test func neverSharesTheFrozenImagesBuffer() throws {
        let image = makeTestImage(width: 200, height: 100)
        let rendered = try #require(render(image, CGRect(x: 10, y: 5, width: 30, height: 20), scale: 2))
        // A crop (`CGImage.cropping`) keeps the source's rows and buffer; a new bitmap has its own.
        #expect(rendered.bytesPerRow < image.bytesPerRow)
        let bytes = try #require(rendered.dataProvider?.data)
        #expect(CFDataGetLength(bytes) <= rendered.bytesPerRow * rendered.height)
    }

    // MARK: Annotations (FR-29 to FR-36, FR-40)

    let blue = RGBA8(red: 0, green: 0, blue: 255, alpha: 255)
    let green = RGBAColor(red: 0, green: 1, blue: 0)

    func isGreen(_ pixel: RGBA8) -> Bool { pixel.green > 200 && pixel.red < 50 && pixel.blue < 50 }

    @Test(arguments: [CGFloat(1), 2, 3])
    func annotationsAreDrawnAtNativePixels(scale: CGFloat) throws {
        let size = Int(100 * scale)
        let image = makeTestImage(width: size, height: size, marker: 0)   // 100 × 100 pt, all blue
        let line = Annotation.line(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50), color: green, width: 4)
        let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 100, height: 100), scale: scale, [line]))
        #expect(rendered.width == size)
        #expect(isGreen(pixelColor(rendered, x: Int(50 * scale), y: Int(50 * scale))))
        #expect(isGreen(pixelColor(rendered, x: Int(50 * scale), y: Int(48.5 * scale))))    // 4 pt thick
        #expect(pixelColor(rendered, x: Int(50 * scale), y: Int(53 * scale)) == blue)
        #expect(pixelColor(rendered, x: Int(50 * scale), y: Int(20 * scale)) == blue)
    }

    @Test func annotationsStayPutWhenTheSelectionMoves() throws {
        let image = makeTestImage(width: 200, height: 200, marker: 0)
        let dot = Annotation.pencil(points: [CGPoint(x: 60, y: 70)], color: green, width: 6)
        let a = try #require(render(image, CGRect(x: 50, y: 50, width: 40, height: 40), scale: 1, [dot]))
        let b = try #require(render(image, CGRect(x: 30, y: 60, width: 40, height: 40), scale: 1, [dot]))
        #expect(isGreen(pixelColor(a, x: 10, y: 20)))
        #expect(isGreen(pixelColor(b, x: 30, y: 10)))
    }

    @Test func onlyThePartInsideTheSelectionIsExported() throws {
        let image = makeTestImage(width: 100, height: 100, marker: 0)
        let outside = Annotation.rectangle(CGRect(x: 60, y: 60, width: 30, height: 30), color: green, width: 3)
        let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 50, height: 50), scale: 1, [outside]))
        for x in stride(from: 0, to: 50, by: 7) {
            for y in stride(from: 0, to: 50, by: 7) {
                #expect(pixelColor(rendered, x: x, y: y) == blue)
            }
        }
    }

    @Test func markerIsTranslucentAndDoesNotDarkenWhereItCrossesItself() throws {
        let image = makeTestImage(width: 100, height: 100, marker: 0)
        let cross = Annotation.marker(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50), CGPoint(x: 50, y: 10),
                                               CGPoint(x: 50, y: 90)], color: green, width: 10)
        let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1, [cross]))
        let single = pixelColor(rendered, x: 25, y: 50), crossing = pixelColor(rendered, x: 50, y: 50)
        #expect(single.green > 50 && single.green < 110 && single.blue > 150)   // 30 % green over blue
        #expect(abs(single.green - crossing.green) <= 2 && abs(single.blue - crossing.blue) <= 2)
    }

    @Test func arrowHeadIsFilled() throws {
        let image = makeTestImage(width: 200, height: 100, marker: 0)
        let arrow = Annotation.arrow(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 190, y: 50), color: green, width: 3)
        let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 200, height: 100), scale: 1, [arrow]))
        #expect(isGreen(pixelColor(rendered, x: 170, y: 53)))    // inside the head, off the shaft
        #expect(isGreen(pixelColor(rendered, x: 100, y: 50)))    // shaft
        #expect(pixelColor(rendered, x: 100, y: 54) == blue)
    }

    @Test func textRendersExactlyAtItsOrigin() throws {
        let image = makeTestImage(width: 200, height: 100, marker: 0)
        let text = TextAnnotation(origin: CGPoint(x: 20, y: 10), string: "W", fontSize: 40, color: green)
        let a = try #require(render(image, CGRect(x: 0, y: 0, width: 200, height: 100), scale: 2, [.text(text)]))
        let b = try #require(render(image, CGRect(x: 10, y: 5, width: 150, height: 80), scale: 2, [.text(text)]))
        let layout = TextLayout(text: "W", fontSize: 40)
        let (bitmap, frame) = try #require(layout.image(scale: 2, color: green))
        // The overlay's bitmap, the full render and an offset render agree pixel for pixel on the ink.
        let left = Int((20 + frame.minX) * 2), top = Int((10 + frame.minY) * 2)
        var inked = 0
        for x in 0..<bitmap.width {
            for y in stride(from: 0, to: bitmap.height, by: 3) where pixelColor(bitmap, x: x, y: y).alpha == 255 {
                inked += 1
                #expect(isGreen(pixelColor(a, x: left + x, y: top + y)))
                #expect(isGreen(pixelColor(b, x: left - 20 + x, y: top - 10 + y)))
            }
        }
        #expect(inked > 20)
    }

    @Test func redactionObscuresTheImageAndEarlierAnnotationsButNotLaterOnes() throws {
        let image = makeTestImage(width: 100, height: 100, marker: 0)
        let earlier = Annotation.line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: 100, y: 20), color: green, width: 2)
        let redaction = Annotation.redaction(CGRect(x: 0, y: 0, width: 48, height: 48), style: .pixelate, width: 3)
        let later = Annotation.line(from: CGPoint(x: 0, y: 30), to: CGPoint(x: 100, y: 30), color: green, width: 2)
        let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1,
                                           [earlier, redaction, later]))
        let block = pixelColor(rendered, x: 12, y: 12)                       // 12 px blocks: rows 12–23
        #expect(pixelColor(rendered, x: 12, y: 20) == block)                 // the earlier line is gone…
        #expect(isGreen(pixelColor(rendered, x: 60, y: 20)))                 // …outside the redaction it isn't
        #expect(isGreen(pixelColor(rendered, x: 12, y: 30)))                 // later annotations stay sharp
    }

    @Test func redactionsInTheExportMatchThePatchesTheOverlayShows() throws {
        let image = makeTestImage(width: 200, height: 200, marker: 40)
        let first = CGRect(x: 10, y: 10, width: 60, height: 50), second = CGRect(x: 40, y: 30, width: 50, height: 50)
        let annotations: [Annotation] = [.redaction(first, style: .blur, width: 3),
                                         .redaction(second, style: .pixelate, width: 3)]
        let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2, annotations))
        // The overlay builds each patch from the ones beneath it, as AnnotationLayers does.
        let firstPatch = try #require(Renderer.redactionPatch(image, scale: 2, below: [], patches: [:], rect: first,
                                                              style: .blur, strokeWidth: 3))
        let secondPatch = try #require(Renderer.redactionPatch(image, scale: 2, below: [annotations[0]],
                                                               patches: [0: firstPatch], rect: second,
                                                               style: .pixelate, strokeWidth: 3))
        #expect(Renderer.redactionPatches(image, scale: 2, annotations: annotations)?.count == 2)
        #expect(Renderer.patchFrame(for: first, scale: 2, imageSize: PixelSize(width: 200, height: 200)) == first)
        #expect(firstPatch.width == 120 && firstPatch.height == 100)
        for (x, y) in [(0, 0), (30, 20), (59, 39), (40, 1)] {                // first patch, outside the second
            let exported = pixelColor(rendered, x: 20 + x, y: 20 + y), shown = pixelColor(firstPatch, x: x, y: y)
            #expect(abs(exported.red - shown.red) <= 1 && abs(exported.blue - shown.blue) <= 1)
        }
        for (x, y) in [(0, 0), (50, 50), (99, 99), (13, 77)] {               // second patch, over the first
            let exported = pixelColor(rendered, x: 80 + x, y: 60 + y)
            let shown = shownColor(secondPatch, frameWidth: 100, x: x, y: y, strength: 12)
            #expect(abs(exported.red - shown.red) <= 1 && abs(exported.blue - shown.blue) <= 1)
        }
    }

    /// Every pixel a different colour: red = 4·x, green = 4·y (from the top-left corner).
    func gradient(width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in 0..<width {
            for y in 0..<height {
                context.setFillColor(CGColor(colorSpace: space, components: [CGFloat(4 * x % 256) / 255,
                                                                              CGFloat(4 * y % 256) / 255, 0.5, 1])!)
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))   // CG is bottom-left
            }
        }
        return context.makeImage()!
    }

    @Test func redactionsCrossingTheSelectionAndTheDisplayEdgeMatchTheOverlay() throws {
        let image = gradient(width: 300, height: 240)                 // a 100 × 80 pt display at 3×
        let lower = Annotation.redaction(CGRect(x: 60, y: 45, width: 30, height: 30), style: .blur, width: 3)
        let upper = Annotation.redaction(CGRect(x: 80, y: 60, width: 40, height: 40), style: .pixelate, width: 3)
        let selection = CGRect(x: 50, y: 40, width: 40, height: 30)
        let rendered = try #require(render(image, selection, scale: 3, [lower, upper]))
        let patches = try #require(Renderer.redactionPatches(image, scale: 3, annotations: [lower, upper]))
        let frame = Renderer.patchFrame(for: CGRect(x: 80, y: 60, width: 40, height: 40), scale: 3,
                                        imageSize: PixelSize(width: 300, height: 240))
        #expect(frame == CGRect(x: 80, y: 60, width: 20, height: 20))       // clipped to the display
        let upperPatch = try #require(patches[1]), lowerPatch = try #require(patches[0])
        // Inside the selection, the export shows each patch where the overlay puts it.
        for (x, y) in [(80.0, 60.0), (85.5, 64.0), (89.6, 69.6)] {
            let exported = pixelColor(rendered, x: Int((x - 50) * 3), y: Int((y - 40) * 3))
            let shown = shownColor(upperPatch, frameWidth: 60, x: Int((x - 80) * 3), y: Int((y - 60) * 3), strength: 12)
            #expect(exported == shown)
        }
        for (x, y) in [(60.0, 45.0), (70.0, 55.0), (79.6, 59.6)] {
            let exported = pixelColor(rendered, x: Int((x - 50) * 3), y: Int((y - 40) * 3))
            let shown = pixelColor(lowerPatch, x: Int((x - 60) * 3), y: Int((y - 45) * 3))
            #expect(exported == shown)
        }
    }

    /// Stroke widths 3, 5 and 50 are strengths 12, 20 and 200: partial blocks on the right and
    /// bottom, and at 200 a single partial block both ways.
    @Test(arguments: [CGFloat(1), 2, 3], [CGFloat(3), 5, 50])
    func pixelateExportsMatchAFullSizePixellate(scale: CGFloat, strokeWidth: CGFloat) throws {
        let image = gradient(width: Int(100 * scale), height: Int(80 * scale))
        let source = pixelColors(image)
        let rect = CGRect(x: 13, y: 7, width: 41, height: 29)
        let region = try #require(Renderer.render(image, scale: scale, annotations: [], patches: [:], region: rect))
        let strength = Redaction.strength(strokeWidth: strokeWidth)
        let reference = try pixelColors(#require(fullSizePixellate(region, strength: strength)))
        // The redaction crossing the selection's right edge, then wholly inside a selection, so the
        // partial last column and row are compared too.
        for selection in [CGRect(x: 0, y: 0, width: 50, height: 40), CGRect(x: 10, y: 4, width: 50, height: 40)] {
            let rendered = try pixelColors(#require(render(image, selection, scale: scale,
                                                           [.redaction(rect, style: .pixelate, width: strokeWidth)])))
            let left = Int((rect.minX - selection.minX) * scale), top = Int((rect.minY - selection.minY) * scale)
            let visible = rect.intersection(selection)
            let columns = Int(visible.width * scale), rows = Int(visible.height * scale)
            if selection.contains(rect) { try #require(columns == reference.first?.count && rows == reference.count) }
            // Indexing past either array would trap and end the whole run, so a size regression stops here.
            try #require(reference.count >= rows && reference.allSatisfy { $0.count >= columns })
            try #require(left >= 1 && rendered.count >= top + max(rows, 6)
                         && rendered.allSatisfy { $0.count >= left + columns })
            for x in 0..<columns {
                for y in 0..<rows where rendered[top + y][left + x] != reference[y][x] {
                    Issue.record("export in \(selection) differs from the reference at \(x),\(y): \(rendered[top + y][left + x]) vs \(reference[y][x])")
                    return
                }
            }
            let outside = source[Int(rect.minY * scale) + 5][Int(rect.minX * scale) - 1]
            #expect(rendered[top + 5][left - 1] == outside)
        }
    }

    @Test func redactionsUnderALaterOneAreCovered() {
        let size = PixelSize(width: 200, height: 200)
        let annotations: [Annotation] = [
            .redaction(CGRect(x: 10, y: 10, width: 20, height: 20), style: .pixelate, width: 3),   // under the 3rd
            .redaction(CGRect(x: 50, y: 50, width: 30, height: 30), style: .blur, width: 3),       // only overlapped
            .line(from: .zero, to: CGPoint(x: 100, y: 100), color: green, width: 3),
            .redaction(CGRect(x: 0, y: 0, width: 60, height: 60), style: .blur, width: 3),
            .redaction(CGRect(x: 15, y: 15, width: 5, height: 5), style: .blur, width: 3),         // on top: shows
            .redaction(CGRect(x: 300, y: 300, width: 5, height: 5), style: .blur, width: 3),       // off the display
        ]
        #expect(Renderer.coveredRedactions(in: annotations, scale: 1, imageSize: size) == [0])
        #expect(Renderer.coveredRedactions(in: annotations, scale: 2, imageSize: size) == [0])
        #expect(Renderer.coveredRedactions(in: [], scale: 1, imageSize: size).isEmpty)
    }

    @Test func aRedactionWithTheSameFrameCoversTheEarlierOne() {
        let rect = CGRect(x: 10, y: 10, width: 40, height: 40)
        let annotations: [Annotation] = [.redaction(rect, style: .pixelate, width: 3),
                                         .redaction(rect, style: .blur, width: 3)]
        #expect(Renderer.coveredRedactions(in: annotations, scale: 1, imageSize: PixelSize(width: 200, height: 200))
            == [0])
    }

    @Test func nestedRedactionsAreAllCoveredButTheOutermost() {
        let annotations: [Annotation] = [
            .redaction(CGRect(x: 20, y: 20, width: 10, height: 10), style: .blur, width: 3),
            .redaction(CGRect(x: 15, y: 15, width: 30, height: 30), style: .pixelate, width: 3),
            .redaction(CGRect(x: 10, y: 10, width: 60, height: 60), style: .blur, width: 3),
        ]
        #expect(Renderer.coveredRedactions(in: annotations, scale: 2, imageSize: PixelSize(width: 200, height: 200))
            == [0, 1])
    }

    @Test func knownPatchesAreUsedAsTheyAre() throws {
        let image = makeTestImage(width: 100, height: 100, marker: 0)
        let rect = CGRect(x: 20, y: 20, width: 30, height: 30)
        let context = try #require(CGContext(data: nil, width: 30, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        let overlayPatch = try #require(context.makeImage())
        let rendered = try #require(Renderer.renderSelection(image, scale: 1,
                                                             annotations: [.redaction(rect, style: .blur, width: 3)],
                                                             selection: CGRect(x: 0, y: 0, width: 100, height: 100),
                                                             standardResolution: false, patches: [0: overlayPatch]))
        #expect(isGreen(pixelColor(rendered, x: 35, y: 35)))            // the overlay's patch, not a new blur
        #expect(pixelColor(rendered, x: 10, y: 10) == blue)
    }

    @Test func onlyRedactionsThatShowInTheSelectionAreMade() throws {
        let image = makeTestImage(width: 100, height: 100, marker: 0)
        let annotations: [Annotation] = [
            .redaction(CGRect(x: 0, y: 0, width: 10, height: 10), style: .pixelate, width: 3),     // far away
            .redaction(CGRect(x: 45, y: 45, width: 10, height: 10), style: .pixelate, width: 3),   // under the next
            .redaction(CGRect(x: 50, y: 50, width: 20, height: 20), style: .pixelate, width: 3),   // in the selection
        ]
        let patches = try #require(Renderer.redactionPatches(image, scale: 1, annotations: annotations,
                                                             covering: CGRect(x: 60, y: 60, width: 30, height: 30)))
        #expect(Set(patches.keys) == [1, 2])
    }

    @Test func aRedactionHiddenUnderAReusedPatchIsNotMadeAgain() throws {
        let image = makeTestImage(width: 100, height: 100, marker: 0)
        let region = CGRect(x: 0, y: 0, width: 100, height: 100)
        let small = Annotation.redaction(CGRect(x: 20, y: 20, width: 20, height: 20), style: .blur, width: 3)
        let big = Annotation.redaction(CGRect(x: 10, y: 10, width: 50, height: 50), style: .pixelate, width: 3)
        let all = try #require(Renderer.redactionPatches(image, scale: 1, annotations: [small, big]))
        let bigPatch = try #require(all[1])
        // The overlay dropped the small one's patch and reuses the big one's: nothing is made.
        let reused = try #require(Renderer.redactionPatches(image, scale: 1, annotations: [small, big],
                                                            covering: region, reusing: [1: bigPatch]))
        #expect(Set(reused.keys) == [1])
        // When the big one is made here, the small one is made too: the big one is made from it.
        let fresh = try #require(Renderer.redactionPatches(image, scale: 1, annotations: [small, big],
                                                           covering: region))
        #expect(Set(fresh.keys) == [0, 1])
        // A patch made between them, reaching past the big one, still gets the small one beneath it.
        let middle = Annotation.redaction(CGRect(x: 35, y: 35, width: 40, height: 40), style: .blur, width: 3)
        let mixed = try #require(Renderer.redactionPatches(image, scale: 1, annotations: [small, middle, big],
                                                           covering: region, reusing: [2: bigPatch]))
        #expect(Set(mixed.keys) == [0, 1, 2])
        // The export is the same either way.
        let a = try #require(Renderer.renderSelection(image, scale: 1, annotations: [small, big], selection: region,
                                                      standardResolution: false, patches: [1: bigPatch]))
        let b = try #require(Renderer.renderSelection(image, scale: 1, annotations: [small, big], selection: region,
                                                      standardResolution: false))
        for (x, y) in [(25, 25), (30, 30), (55, 15), (80, 80)] {
            #expect(pixelColor(a, x: x, y: y) == pixelColor(b, x: x, y: y))
        }
    }

    @Test func aRedactionThatCannotBeMadeFailsTheExport() {
        // FR-36 AC1: never an unredacted export. Only the redaction inside the selection fails.
        let image = makeTestImage(width: 100, height: 100, marker: 0)
        let annotations: [Annotation] = [.redaction(CGRect(x: 20, y: 20, width: 30, height: 30), style: .pixelate, width: 3)]
        let failing: Renderer.Obscure = { _, _, _ in nil }
        #expect(Renderer.renderSelection(image, scale: 1, annotations: annotations,
                                         selection: CGRect(x: 0, y: 0, width: 100, height: 100),
                                         standardResolution: false, obscure: failing) == nil)
        // A selection the redaction doesn't reach still exports.
        #expect(Renderer.renderSelection(image, scale: 1, annotations: annotations,
                                         selection: CGRect(x: 60, y: 60, width: 30, height: 30),
                                         standardResolution: false, obscure: failing) != nil)
    }

    /// Copy Text reads each redaction as one solid block, so no strength leaves the text under it
    /// legible (FR-46); the rest of the selection is drawn as the export draws it.
    @Test(arguments: [RedactionStyle.pixelate, .blur], [(CGFloat(1), false), (2, false), (2, true)])
    func textRecognitionSeesRedactionsAsSolidBlocks(style: RedactionStyle, output: (scale: CGFloat, standard: Bool)) throws {
        let scale = output.scale
        let image = gradient(width: Int(100 * scale), height: Int(80 * scale))
        let rect = CGRect(x: 13, y: 7, width: 41, height: 29), selection = CGRect(x: 5, y: 3, width: 70, height: 50)
        let annotations: [Annotation] = [.redaction(rect, style: style, width: 3)]
        let recognized = try pixelColors(#require(Renderer.renderSelectionForTextRecognition(
            image, scale: scale, annotations: annotations, selection: selection, standardResolution: output.standard)))
        let exported = try pixelColors(#require(render(image, selection, scale: scale, standard: output.standard,
                                                       annotations)))
        // The frame in output pixels. Scaling down to 1× blends the two pixels either side of its
        // edges, so those are left out.
        let pixels = output.standard ? 1 : scale, margin = output.standard ? 2 : 0
        let frame = CGRect(x: (rect.minX - selection.minX) * pixels, y: (rect.minY - selection.minY) * pixels,
                           width: rect.width * pixels, height: rect.height * pixels)
        let inside = frame.insetBy(dx: CGFloat(margin), dy: CGFloat(margin))
        let near = frame.insetBy(dx: CGFloat(-margin), dy: CGFloat(-margin))
        try #require(recognized.count == exported.count && recognized.first?.count == exported.first?.count)
        let solid = recognized[Int(inside.minY)][Int(inside.minX)]
        #expect(solid.alpha == 255)
        for y in recognized.indices {
            for x in recognized[y].indices {
                let pixel = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                if inside.contains(pixel), recognized[y][x] != solid {
                    Issue.record("pixel \(x),\(y) in the redaction is \(recognized[y][x]), not \(solid)")
                    return
                }
                if !near.contains(pixel), recognized[y][x] != exported[y][x] {
                    Issue.record("pixel \(x),\(y) outside the redaction is \(recognized[y][x]), not \(exported[y][x])")
                    return
                }
            }
        }
    }

    @Test func redactionsThatCoverNoPixelsDoNotStopTheExport() throws {
        let image = makeTestImage(width: 200, height: 200, marker: 0)      // 100 × 100 pt at 2×
        let annotations: [Annotation] = [
            .redaction(CGRect(x: 40, y: 40, width: 0.1, height: 20), style: .pixelate, width: 3),   // a sliver
            .redaction(CGRect(x: 120, y: 40, width: 20, height: 20), style: .blur, width: 3),       // off the display
        ]
        let rendered = Renderer.renderSelection(image, scale: 2, annotations: annotations,
                                                selection: CGRect(x: 30, y: 30, width: 120, height: 40),
                                                standardResolution: false)
        #expect(rendered != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func everyRedactionIsRenderedOnce() throws {
        // Forty redactions finish at once; rendering each one's patch from scratch (re-rendering
        // every earlier redaction inside it) would take 2⁴⁰ steps.
        let image = makeTestImage(width: 400, height: 250, marker: 0)
        let redactions = (0..<40).map { index in
            Annotation.redaction(CGRect(x: CGFloat(index % 8) * 50, y: CGFloat(index / 8) * 50, width: 40, height: 40),
                                 style: .pixelate, width: 3)
        }
        let rendered = try #require(render(image, CGRect(x: 0, y: 0, width: 400, height: 250), scale: 1, redactions))
        #expect(rendered.width == 400 && rendered.height == 250)
    }
}
