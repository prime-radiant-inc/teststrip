import Foundation

public struct XMPPacket: Equatable, Sendable {
    public var metadata: AssetMetadata

    private static let xmpMetaNamespace = "adobe:ns:meta/"
    private static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    private static let xmpNamespace = "http://ns.adobe.com/xap/1.0/"
    private static let dcNamespace = "http://purl.org/dc/elements/1.1/"
    private static let teststripNamespace = "https://teststrip.app/xmp/1.0/"

    public init(metadata: AssetMetadata) {
        self.metadata = metadata
    }

    public func xmlData() throws -> Data {
        let root = XMLElement(name: "x:xmpmeta")
        root.addNamespace(XMLNode.namespace(withName: "x", stringValue: Self.xmpMetaNamespace) as! XMLNode)

        let document = XMLDocument(rootElement: root)
        let rdf = XMLElement(name: "rdf:RDF")
        rdf.addNamespace(XMLNode.namespace(withName: "rdf", stringValue: Self.rdfNamespace) as! XMLNode)
        root.addChild(rdf)

        let description = XMLElement(name: "rdf:Description")
        description.addAttribute(XMLNode.attribute(withName: "rdf:about", stringValue: "") as! XMLNode)
        description.addNamespace(XMLNode.namespace(withName: "xmp", stringValue: Self.xmpNamespace) as! XMLNode)
        description.addNamespace(XMLNode.namespace(withName: "dc", stringValue: Self.dcNamespace) as! XMLNode)
        description.addNamespace(XMLNode.namespace(withName: "ts", stringValue: Self.teststripNamespace) as! XMLNode)
        rdf.addChild(description)

        func addAttribute(_ name: String, _ value: String?) {
            guard let value else { return }
            description.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
        }

        addAttribute("xmp:Rating", "\(metadata.rating)")
        addAttribute("xmp:Label", metadata.colorLabel.map(Self.xmpLabel))
        addAttribute("ts:Pick", metadata.flag?.rawValue)
        Self.addContainer(
            propertyName: "dc:subject",
            containerName: "rdf:Bag",
            values: metadata.keywords,
            to: description
        )
        Self.addContainer(
            propertyName: "dc:description",
            containerName: "rdf:Alt",
            values: metadata.caption.map { [$0] } ?? [],
            languageTagged: true,
            to: description
        )
        Self.addContainer(
            propertyName: "dc:creator",
            containerName: "rdf:Seq",
            values: metadata.creator.map { [$0] } ?? [],
            to: description
        )
        Self.addContainer(
            propertyName: "dc:rights",
            containerName: "rdf:Alt",
            values: metadata.copyright.map { [$0] } ?? [],
            languageTagged: true,
            to: description
        )

        return document.xmlData(options: [.nodePrettyPrint])
    }

    public static func parse(_ data: Data) throws -> XMPPacket {
        let document = try XMLDocument(data: data)
        guard let root = document.rootElement(),
              root.localName == "xmpmeta",
              root.uri == Self.xmpMetaNamespace
        else {
            throw TeststripError.invalidState("invalid XMP root element: \(document.rootElement()?.name ?? "missing")")
        }
        guard let description = Self.rdfDescription(in: root) else {
            throw TeststripError.invalidState("invalid XMP RDF description")
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
            guard let colorLabel = ColorLabel(rawValue: value.lowercased()) else {
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

        let keywords = Self.containerValues(
            in: description,
            propertyLocalName: "subject",
            containerLocalName: "Bag"
        )
        var metadata = try AssetMetadata.validated(
            rating: try rating(from: Self.attribute(description, localName: "Rating", uri: Self.xmpNamespace)),
            colorLabel: try colorLabel(from: Self.attribute(description, localName: "Label", uri: Self.xmpNamespace)),
            flag: try flag(from: Self.attribute(description, localName: "Pick", uri: Self.teststripNamespace)),
            keywords: keywords
        )
        metadata.caption = Self.containerValues(
            in: description,
            propertyLocalName: "description",
            containerLocalName: "Alt"
        ).first
        metadata.creator = Self.containerValues(
            in: description,
            propertyLocalName: "creator",
            containerLocalName: "Seq"
        ).first
        metadata.copyright = Self.containerValues(
            in: description,
            propertyLocalName: "rights",
            containerLocalName: "Alt"
        ).first
        return XMPPacket(metadata: metadata)
    }

    private static func addContainer(
        propertyName: String,
        containerName: String,
        values: [String],
        languageTagged: Bool = false,
        to description: XMLElement
    ) {
        guard !values.isEmpty else { return }
        let property = XMLElement(name: propertyName)
        let container = XMLElement(name: containerName)
        for value in values {
            let item = XMLElement(name: "rdf:li", stringValue: value)
            if languageTagged {
                item.addAttribute(XMLNode.attribute(withName: "xml:lang", stringValue: "x-default") as! XMLNode)
            }
            container.addChild(item)
        }
        property.addChild(container)
        description.addChild(property)
    }

    private static func rdfDescription(in root: XMLElement) -> XMLElement? {
        guard let rdf = child(root, localName: "RDF", uri: rdfNamespace) else { return nil }
        return child(rdf, localName: "Description", uri: rdfNamespace)
    }

    private static func child(_ element: XMLElement, localName: String, uri: String) -> XMLElement? {
        element.children?.compactMap { $0 as? XMLElement }.first {
            $0.localName == localName && $0.uri == uri
        }
    }

    private static func attribute(_ element: XMLElement, localName: String, uri: String) -> String? {
        element.attributes?.first {
            $0.localName == localName && $0.uri == uri
        }?.stringValue
    }

    private static func containerValues(
        in description: XMLElement,
        propertyLocalName: String,
        containerLocalName: String
    ) -> [String] {
        guard let property = child(description, localName: propertyLocalName, uri: dcNamespace),
              let container = child(property, localName: containerLocalName, uri: rdfNamespace)
        else {
            return []
        }
        return container.children?.compactMap { child in
            guard let item = child as? XMLElement,
                  item.localName == "li",
                  item.uri == rdfNamespace
            else {
                return nil
            }
            return item.stringValue
        } ?? []
    }

    private static func xmpLabel(for colorLabel: ColorLabel) -> String {
        colorLabel.rawValue.prefix(1).uppercased() + colorLabel.rawValue.dropFirst()
    }
}
