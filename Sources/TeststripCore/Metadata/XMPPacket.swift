import Foundation

public struct XMPPacket: Equatable, Sendable {
    public var metadata: AssetMetadata

    private static let xmpMetaNamespace = "adobe:ns:meta/"
    private static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    private static let xmpNamespace = "http://ns.adobe.com/xap/1.0/"
    private static let dcNamespace = "http://purl.org/dc/elements/1.1/"
    private static let teststripNamespace = "https://teststrip.app/xmp/1.0/"
    private static let photoshopNamespace = "http://ns.adobe.com/photoshop/1.0/"

    public init(metadata: AssetMetadata) {
        self.metadata = metadata
    }

    public func xmlData() throws -> Data {
        let document = Self.emptyDocument()
        let description = Self.rdfDescription(in: document.rootElement()!)!
        applyManagedMetadata(to: description)
        return document.xmlData(options: [.nodePrettyPrint])
    }

    public func xmlData(mergingInto existingData: Data) throws -> Data {
        let document = try XMLDocument(data: existingData)
        guard let root = document.rootElement(),
              root.localName == "xmpmeta",
              root.uri == Self.xmpMetaNamespace
        else {
            throw TeststripError.invalidState("invalid XMP root element: \(document.rootElement()?.name ?? "missing")")
        }
        guard let description = Self.rdfDescription(in: root) else {
            throw TeststripError.invalidState("invalid XMP RDF description")
        }

        Self.removeManagedMetadata(from: description)
        applyManagedMetadata(to: description)
        return document.xmlData(options: [.nodePrettyPrint])
    }

    private static func emptyDocument() -> XMLDocument {
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
        return document
    }

    private func applyManagedMetadata(to description: XMLElement) {
        // AI-unconfirmed labels are provisional and must never reach the XMP
        // sidecar; project down to the confirmed subset before emitting.
        let metadata = self.metadata.confirmedProjection
        Self.ensureNamespace(prefix: "xmp", uri: Self.xmpNamespace, in: description)
        Self.ensureNamespace(prefix: "dc", uri: Self.dcNamespace, in: description)
        Self.ensureNamespace(prefix: "ts", uri: Self.teststripNamespace, in: description)
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
        // XMP Basic uses xmp:Rating="-1" as the "rejected" sentinel. Teststrip represents
        // rejection as a pick flag, so the sentinel maps to flag reject with no star rating
        // and takes precedence over a stale ts:Pick left behind by an external rejection.
        let parsedRating = try rating(from: Self.attribute(description, localName: "Rating", uri: Self.xmpNamespace))
        let parsedFlag = try flag(from: Self.attribute(description, localName: "Pick", uri: Self.teststripNamespace))
        let isRejectedSentinel = parsedRating == -1
        var metadata = try AssetMetadata.validated(
            rating: isRejectedSentinel ? 0 : parsedRating,
            colorLabel: try colorLabel(from: Self.attribute(description, localName: "Label", uri: Self.xmpNamespace)),
            flag: isRejectedSentinel ? .reject : parsedFlag,
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

    /// Reads `photoshop:SidecarForExtension`, the attribute Adobe tools use to bind a basename-shared
    /// sidecar such as `frame.xmp` to one original in a RAW+JPEG pair. Returns nil when the attribute
    /// is absent or the data is not a readable XMP packet.
    public static func sidecarForExtension(in data: Data) -> String? {
        guard let document = try? XMLDocument(data: data),
              let root = document.rootElement(),
              root.localName == "xmpmeta",
              root.uri == Self.xmpMetaNamespace,
              let description = Self.rdfDescription(in: root)
        else {
            return nil
        }
        return attribute(description, localName: "SidecarForExtension", uri: Self.photoshopNamespace)
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

    private static func removeManagedMetadata(from description: XMLElement) {
        removeAttribute(from: description, localName: "Rating", uri: xmpNamespace)
        removeAttribute(from: description, localName: "Label", uri: xmpNamespace)
        removeAttribute(from: description, localName: "Pick", uri: teststripNamespace)
        removeChild(from: description, localName: "subject", uri: dcNamespace)
        removeChild(from: description, localName: "description", uri: dcNamespace)
        removeChild(from: description, localName: "creator", uri: dcNamespace)
        removeChild(from: description, localName: "rights", uri: dcNamespace)
    }

    private static func removeAttribute(from element: XMLElement, localName: String, uri: String) {
        let names = element.attributes?.compactMap { attribute -> String? in
            guard attribute.localName == localName, attribute.uri == uri else { return nil }
            return attribute.name
        } ?? []
        for name in names {
            element.removeAttribute(forName: name)
        }
    }

    private static func removeChild(from element: XMLElement, localName: String, uri: String) {
        let indexes = (element.children ?? []).enumerated().compactMap { index, child -> Int? in
            guard let child = child as? XMLElement,
                  child.localName == localName,
                  child.uri == uri
            else {
                return nil
            }
            return index
        }
        for index in indexes.reversed() {
            element.removeChild(at: index)
        }
    }

    private static func ensureNamespace(prefix: String, uri: String, in element: XMLElement) {
        if element.namespaces?.contains(where: { $0.name == prefix && $0.stringValue == uri }) == true {
            return
        }
        element.addNamespace(XMLNode.namespace(withName: prefix, stringValue: uri) as! XMLNode)
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
