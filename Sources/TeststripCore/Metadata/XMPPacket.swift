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
        let root = document.rootElement()
        func text(_ name: String) -> String? {
            root?.elements(forName: name).first?.stringValue
        }
        let keywordNodes = root?.elements(forName: "keywords").first?.elements(forName: "keyword") ?? []
        let keywords = keywordNodes.compactMap(\.stringValue)
        let metadata = AssetMetadata(
            rating: Int(text("rating") ?? "0") ?? 0,
            colorLabel: text("colorLabel").flatMap(ColorLabel.init(rawValue:)),
            flag: text("flag").flatMap(PickFlag.init(rawValue:)),
            keywords: keywords,
            caption: text("caption"),
            creator: text("creator"),
            copyright: text("copyright")
        )
        return XMPPacket(metadata: metadata)
    }
}
