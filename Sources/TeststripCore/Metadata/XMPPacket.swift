import Foundation

public struct XMPPacket: Equatable, Sendable {
    public var metadata: AssetMetadata

    public init(metadata: AssetMetadata) {
        self.metadata = metadata
    }

    public func xmlData() throws -> Data {
        let document = XMLDocument(rootElement: XMLElement(name: "xmpmeta"))
        let root = document.rootElement()!
        root.addAttribute(XMLNode.attribute(withName: "xmlns:ts", stringValue: "https://teststrip.app/xmp") as! XMLNode)

        func add(_ name: String, _ value: String?) {
            guard let value else { return }
            let element = XMLElement(name: name, stringValue: value)
            root.addChild(element)
        }

        add("rating", "\(metadata.rating)")
        add("colorLabel", metadata.colorLabel?.rawValue)
        add("flag", metadata.flag?.rawValue)
        add("caption", metadata.caption)
        add("creator", metadata.creator)
        add("copyright", metadata.copyright)

        let keywords = XMLElement(name: "keywords")
        for keyword in metadata.keywords {
            keywords.addChild(XMLElement(name: "keyword", stringValue: keyword))
        }
        root.addChild(keywords)

        return document.xmlData(options: [.nodePrettyPrint])
    }

    public static func parse(_ data: Data) throws -> XMPPacket {
        let document = try XMLDocument(data: data)
        guard let root = document.rootElement(), root.name == "xmpmeta" else {
            throw TeststripError.invalidState("invalid XMP root element: \(document.rootElement()?.name ?? "missing")")
        }

        func text(_ name: String) -> String? {
            root.elements(forName: name).first?.stringValue
        }

        func rating(from value: String?) throws -> Int {
            guard let value else { return 0 }
            guard let rating = Int(value) else {
                throw TeststripError.invalidState("invalid XMP rating: \(value)")
            }
            return rating
        }

        func colorLabel(from value: String?) throws -> ColorLabel? {
            guard let value else { return nil }
            guard let colorLabel = ColorLabel(rawValue: value) else {
                throw TeststripError.invalidState("invalid XMP color label: \(value)")
            }
            return colorLabel
        }

        func flag(from value: String?) throws -> PickFlag? {
            guard let value else { return nil }
            guard let flag = PickFlag(rawValue: value) else {
                throw TeststripError.invalidState("invalid XMP flag: \(value)")
            }
            return flag
        }

        let keywordNodes = root.elements(forName: "keywords").first?.elements(forName: "keyword") ?? []
        let keywords = keywordNodes.compactMap(\.stringValue)
        var metadata = try AssetMetadata.validated(
            rating: try rating(from: text("rating")),
            colorLabel: try colorLabel(from: text("colorLabel")),
            flag: try flag(from: text("flag")),
            keywords: keywords
        )
        metadata.caption = text("caption")
        metadata.creator = text("creator")
        metadata.copyright = text("copyright")
        return XMPPacket(metadata: metadata)
    }
}
