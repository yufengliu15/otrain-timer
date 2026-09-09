import Foundation

final class RSS: NSObject, XMLParserDelegate {
  private var notices: [ServiceNotice] = []
  private var fields: [String: String] = [:]
  private var element = ""
  private var inItem = false
  private var foundRSS = false
  private var affectedLines: Set<String> = []

  static func parse(_ data: Data) throws -> [ServiceNotice] {
    let delegate = RSS()
    let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), delegate.foundRSS else { throw FeedError.invalidRSS }
    var seen: Set<String> = []
    return delegate.notices.filter { seen.insert($0.id).inserted }
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
  ) {
    if elementName == "rss" || elementName == "rdf:RDF" { foundRSS = true }
    if elementName == "item" {
      fields = [:]
      affectedLines = []
      inItem = true
    }
    element = elementName
    if elementName == "category" { fields["category"] = "" }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if inItem { fields[element, default: ""] += string }
  }

  func parser(_ parser: XMLParser, foundCDATA cdataBlock: Data) {
    if let string = String(data: cdataBlock, encoding: .utf8) {
      self.parser(parser, foundCharacters: string)
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if elementName == "category", let category = fields["category"],
      category.hasPrefix("affectedRoutes-")
    {
      affectedLines.formUnion(
        category.dropFirst("affectedRoutes-".count).components(
          separatedBy: CharacterSet(charactersIn: ",; ")
        ).filter { !$0.isEmpty })
    }
    guard elementName == "item" else { return }
    inItem = false
    let title = Self.plain(fields["title"] ?? "Service notice")
    let detail = Self.plain(fields["description"] ?? "")
    let link = (fields["link"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let url = URL(string: link).flatMap { ["https", "http"].contains($0.scheme) ? $0 : nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    let published = fields["pubDate"].flatMap {
      let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: " EDT", with: " -0400")
        .replacingOccurrences(of: " EST", with: " -0500")
        .replacingOccurrences(of: " GMT", with: " +0000")
        .replacingOccurrences(of: " UTC", with: " +0000")
      return formatter.date(from: value)
    }
    notices.append(
      ServiceNotice(
        id: fields["guid"] ?? (link.isEmpty ? title + detail : link),
        title: title, detail: detail, url: url, published: published, affectedLines: affectedLines))
  }

  static func plain(_ html: String) -> String {
    var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    for (entity, replacement) in [
      ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"),
      ("&gt;", ">"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&lsquo;", "‘"), ("&rsquo;", "’"),
      ("&ndash;", "–"), ("&mdash;", "—"),
    ] {
      text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
