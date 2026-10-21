#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class FileIOAndExportTests: XCTestCase, @unchecked Sendable {

    func testPSDEncodingAndHeader() throws {
        let doc = try Document(canvasSize: CGSize(width: 128, height: 64))
        let bitmap = BitmapLayer(name: "Art Layer", canvasSize: CGSize(width: 128, height: 64))
        bitmap.tileGrid.setPixel(x: 10, y: 10, color: (255, 0, 0, 255))
        doc.addLayer(bitmap)

        let codec = PSDCodec()
        let psdData = codec.encode(document: doc)

        XCTAssertGreaterThan(psdData.count, 26)
        // Verify '8BPS' signature
        XCTAssertEqual(psdData[0], 0x38)
        XCTAssertEqual(psdData[1], 0x42)
        XCTAssertEqual(psdData[2], 0x50)
        XCTAssertEqual(psdData[3], 0x53)

        // Verify decode
        let decoded = try codec.decode(data: psdData)
        XCTAssertEqual(decoded.width, 128)
        XCTAssertEqual(decoded.height, 64)
    }

    func testPCProFileWrapperRoundtrip() throws {
        let doc = try Document(canvasSize: CGSize(width: 64, height: 64))
        let bitmap = BitmapLayer(name: "Foreground", canvasSize: CGSize(width: 64, height: 64))
        bitmap.tileGrid.setPixel(x: 20, y: 20, color: (0, 255, 128, 255))
        doc.addLayer(bitmap)

        let textLayer = TextLayer(name: "Title", text: "PixelCraft", fontName: "SF Mono", fontSize: 16.0, canvasSize: CGSize(width: 64, height: 64))
        doc.addLayer(textLayer)

        let pcpro = PCProDocument()
        let wrapper = try pcpro.serialize(document: doc)
        XCTAssertNotNil(wrapper.fileWrappers?["manifest.json"])

        let restored = try pcpro.deserialize(wrapper: wrapper)
        XCTAssertEqual(restored.width, 64)
        XCTAssertEqual(restored.height, 64)
        XCTAssertEqual(restored.layers.count, 3)
        XCTAssertEqual(restored.layers[0].name, "Background")
        XCTAssertEqual(restored.layers[1].name, "Foreground")
        XCTAssertEqual(restored.layers[2].name, "Title")
    }

    func testImageExportsPNGAndJPEG() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 32, height: 32))
        grid.setPixel(x: 10, y: 10, color: (255, 100, 50, 180))

        let exporter = ImageExporter()

        // PNG 8-bit
        let png8Data = exporter.export(grid: grid, options: ExportOptions(format: .png8, preserveAlpha: true))
        XCTAssertNotNil(png8Data)
        XCTAssertGreaterThan(png8Data!.count, 100)

        // PNG 16-bit
        let png16Data = exporter.export(grid: grid, options: ExportOptions(format: .png16, preserveAlpha: true))
        XCTAssertNotNil(png16Data)
        XCTAssertGreaterThan(png16Data!.count, 100)

        // JPEG
        let jpegData = exporter.export(grid: grid, options: ExportOptions(format: .jpeg, quality: 0.85, preserveAlpha: false))
        XCTAssertNotNil(jpegData)
        XCTAssertGreaterThan(jpegData!.count, 100)

        // TIFF
        let tiffData = exporter.export(grid: grid, options: ExportOptions(format: .tiff, preserveAlpha: true))
        XCTAssertNotNil(tiffData)
        XCTAssertGreaterThan(tiffData!.count, 100)
    }

    func testImageImporterDecodePNG() throws {
        // Create an image with known pixels: red, green, blue, yellow
        let grid = SparseTileGrid(canvasSize: CGSize(width: 40, height: 20))
        grid.setPixel(x: 0, y: 0, color: (255, 0, 0, 255))
        grid.setPixel(x: 39, y: 0, color: (0, 255, 0, 255))
        grid.setPixel(x: 0, y: 19, color: (0, 0, 255, 255))
        grid.setPixel(x: 39, y: 19, color: (255, 255, 0, 255))

        let exporter = ImageExporter()
        let pngData = try XCTUnwrap(exporter.export(grid: grid, options: ExportOptions(format: .png8, preserveAlpha: true)))

        let importer = ImageImporter.shared
        let decoded = try importer.decode(from: pngData, titleHint: "TestPNG")

        XCTAssertEqual(decoded.width, 40)
        XCTAssertEqual(decoded.height, 20)
        XCTAssertEqual(decoded.aspectRatio, 2.0, accuracy: 0.001)
        XCTAssertEqual(decoded.title, "TestPNG")

        // Ingest into a new grid and verify pixel fidelity
        let targetGrid = SparseTileGrid(canvasSize: CGSize(width: 40, height: 20))
        importer.populate(grid: targetGrid, with: decoded, destinationOrigin: .zero)

        let p00 = targetGrid.getPixel(x: 0, y: 0)
        XCTAssertEqual(p00.r, 255)
        XCTAssertEqual(p00.g, 0)
        XCTAssertEqual(p00.b, 0)
        XCTAssertEqual(p00.a, 255)

        let p39_0 = targetGrid.getPixel(x: 39, y: 0)
        XCTAssertEqual(p39_0.r, 0)
        XCTAssertEqual(p39_0.g, 255)
        XCTAssertEqual(p39_0.b, 0)
        XCTAssertEqual(p39_0.a, 255)

        let p0_19 = targetGrid.getPixel(x: 0, y: 19)
        XCTAssertEqual(p0_19.r, 0)
        XCTAssertEqual(p0_19.g, 0)
        XCTAssertEqual(p0_19.b, 255)
        XCTAssertEqual(p0_19.a, 255)

        let p39_19 = targetGrid.getPixel(x: 39, y: 19)
        XCTAssertEqual(p39_19.r, 255)
        XCTAssertEqual(p39_19.g, 255)
        XCTAssertEqual(p39_19.b, 0)
        XCTAssertEqual(p39_19.a, 255)
    }

    func testImageImporterCreateDocumentAdaptsCanvasSizeAndAspectRatio() throws {
        // Create an image with custom aspect ratio (16:9 320x180)
        let grid = SparseTileGrid(canvasSize: CGSize(width: 320, height: 180))
        grid.setPixel(x: 50, y: 50, color: (120, 200, 80, 255))

        let exporter = ImageExporter()
        let tiffData = try XCTUnwrap(exporter.export(grid: grid, options: ExportOptions(format: .tiff)))

        let importer = ImageImporter.shared
        let decoded = try importer.decode(from: tiffData, titleHint: "Landscape")
        let doc = try importer.createDocument(from: decoded)

        XCTAssertEqual(doc.width, 320)
        XCTAssertEqual(doc.height, 180)
        XCTAssertEqual(doc.aspectRatio, 320.0 / 180.0, accuracy: 0.001)
        XCTAssertEqual(doc.title, "Landscape")
        XCTAssertEqual(doc.layers.count, 1)

        if let baseLayer = doc.activeLayer as? BitmapLayer {
            let p = baseLayer.tileGrid.getPixel(x: 50, y: 50)
            XCTAssertEqual(p.r, 120)
            XCTAssertEqual(p.g, 200)
            XCTAssertEqual(p.b, 80)
            XCTAssertEqual(p.a, 255)
        } else {
            XCTFail("Base layer is not a BitmapLayer")
        }
    }

    func testImageImporterCreateLayerCentered() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 50, height: 50))
        grid.setPixel(x: 25, y: 25, color: (200, 100, 50, 255))

        let exporter = ImageExporter()
        let pngData = try XCTUnwrap(exporter.export(grid: grid, options: ExportOptions(format: .png8)))

        let importer = ImageImporter.shared
        let decoded = try importer.decode(from: pngData, titleHint: "Badge")

        // Canvas is 100x100; badge is 50x50 -> centered offset is (25, 25)
        let targetCanvasSize = CGSize(width: 100, height: 100)
        let layer = importer.createLayer(from: decoded, targetCanvasSize: targetCanvasSize, centerInCanvas: true)

        XCTAssertEqual(layer.name, "Badge")
        // Pixel (25, 25) of badge should now be at (25 + 25, 25 + 25) = (50, 50) on canvas
        let sample = layer.tileGrid.getPixel(x: 50, y: 50)
        XCTAssertEqual(sample.r, 200)
        XCTAssertEqual(sample.g, 100)
        XCTAssertEqual(sample.b, 50)
        XCTAssertEqual(sample.a, 255)

        // Point outside the centered badge rect should be unallocated / transparent
        let emptySample = layer.tileGrid.getPixel(x: 5, y: 5)
        XCTAssertEqual(emptySample.a, 0)
    }

    func testDocumentReplaceInPlace() throws {
        let initialDoc = try Document(title: "Old Doc", canvasSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(initialDoc.width, 800)
        XCTAssertEqual(initialDoc.height, 600)

        let newDoc = try Document(title: "New Photo", canvasSize: CGSize(width: 3840, height: 2160))
        let photoLayer = BitmapLayer(name: "Photo", canvasSize: CGSize(width: 3840, height: 2160))
        photoLayer.tileGrid.setPixel(x: 100, y: 100, color: (42, 84, 126, 255))
        newDoc.addLayer(photoLayer)

        initialDoc.replace(with: newDoc)

        XCTAssertEqual(initialDoc.title, "New Photo")
        XCTAssertEqual(initialDoc.width, 3840)
        XCTAssertEqual(initialDoc.height, 2160)
        XCTAssertEqual(initialDoc.aspectRatio, 3840.0 / 2160.0, accuracy: 0.001)
        XCTAssertEqual(initialDoc.layers.count, 2)
    }
}
