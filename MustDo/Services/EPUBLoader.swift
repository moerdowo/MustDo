import Foundation

/// Unzips an EPUB and returns the URL of its entry XHTML inside a temp dir.
enum EPUBLoader {
    enum EPUBError: LocalizedError {
        case unzipFailed(Int32)
        case containerMissing
        case opfMissing
        case noSpine
        var errorDescription: String? {
            switch self {
            case .unzipFailed(let c): return "unzip failed with code \(c)"
            case .containerMissing: return "EPUB missing META-INF/container.xml"
            case .opfMissing: return "EPUB OPF file missing"
            case .noSpine: return "EPUB spine has no entries"
            }
        }
    }

    struct UnpackedEPUB {
        let rootDir: URL
        let opfDir: URL
        let firstDocument: URL
        let spine: [URL]
    }

    static func unpack(epubURL: URL) throws -> UnpackedEPUB {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("mustdo-epub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", epubURL.path, "-d", dest.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EPUBError.unzipFailed(process.terminationStatus) }

        let containerURL = dest.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBError.containerMissing
        }
        let containerData = try Data(contentsOf: containerURL)
        let opfPath = try parseContainerOPFPath(containerData) ?? "OEBPS/content.opf"
        let opfURL = dest.appendingPathComponent(opfPath)
        guard FileManager.default.fileExists(atPath: opfURL.path) else { throw EPUBError.opfMissing }
        let opfDir = opfURL.deletingLastPathComponent()
        let opfData = try Data(contentsOf: opfURL)
        let spineHrefs = try parseOPFSpine(opfData)
        let spineURLs = spineHrefs.map { opfDir.appendingPathComponent($0) }
        guard let first = spineURLs.first else { throw EPUBError.noSpine }
        return UnpackedEPUB(rootDir: dest, opfDir: opfDir, firstDocument: first, spine: spineURLs)
    }

    private static func parseContainerOPFPath(_ data: Data) throws -> String? {
        let delegate = ContainerDelegate()
        let p = XMLParser(data: data)
        p.delegate = delegate
        p.shouldProcessNamespaces = false
        p.parse()
        return delegate.fullPath
    }

    private static func parseOPFSpine(_ data: Data) throws -> [String] {
        let delegate = OPFDelegate()
        let p = XMLParser(data: data)
        p.delegate = delegate
        p.shouldProcessNamespaces = false
        p.parse()
        var ordered: [String] = []
        for idref in delegate.spineIdrefs {
            if let href = delegate.manifest[idref] { ordered.append(href) }
        }
        return ordered
    }

    private final class ContainerDelegate: NSObject, XMLParserDelegate {
        var fullPath: String?
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            if elementName == "rootfile", let p = attributeDict["full-path"] {
                fullPath = p
            }
        }
    }

    private final class OPFDelegate: NSObject, XMLParserDelegate {
        var manifest: [String: String] = [:]
        var spineIdrefs: [String] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
            } else if elementName == "itemref", let idref = attributeDict["idref"] {
                spineIdrefs.append(idref)
            }
        }
    }
}
