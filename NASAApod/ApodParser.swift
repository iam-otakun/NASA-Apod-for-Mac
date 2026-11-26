//
//  ApodParser.swift
//  NASA APOD
//
//  A 1:1 Swift port of the extraction logic in the SwiftBar plugin
//  (NASA-Apod.12h.py v1.9.3), which itself was rebuilt after NASA's
//  page redesign. The rules that matter:
//
//  - The day's media hangs in the hero block in front of the entry's
//    own title (`h2.display-48`): an `hds-media-inner` figure whose
//    link is the original picture, or a <video> on video days.
//  - og:image is the site's template image and must NEVER be used;
//    the image-article links elsewhere on the page are navigation
//    for other days.
//  - The date comes from the byline near the entry's own title
//    ("November 25, 2026"); the page's other date strings belong to
//    the previous entry's navigation and are a day off.
//

import Foundation

enum ApodParser {

    enum Hero {
        case image(displayURL: String, originalURL: String)
        case video(url: String)
    }

    private static let titlePattern = #"display-48 margin-top-0 margin-bottom-3">([^<]+)<"#

    // MARK: - Small regex / string helpers

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// First match in `s` (optionally from `from`): the whole match,
    /// its capture groups and its range.
    private static func firstMatch(_ pattern: String, in s: String, from: String.Index? = nil,
                                   options: NSRegularExpression.Options = []) -> (whole: String, groups: [String], range: Range<String.Index>)? {
        guard let re = regex(pattern, options: options) else { return nil }
        let searchRange = NSRange((from ?? s.startIndex)..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: searchRange),
              let wholeRange = Range(m.range, in: s) else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: s) {
                groups.append(String(s[r]))
            } else {
                groups.append("")
            }
        }
        return (String(s[wholeRange]), groups, wholeRange)
    }

    private static func replacing(_ pattern: String, in s: String, with template: String,
                                  options: NSRegularExpression.Options = []) -> String {
        guard let re = regex(pattern, options: options) else { return s }
        return re.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s), withTemplate: template)
    }

    /// The index `offset` characters before `index`, clamped.
    private static func before(_ index: String.Index, by offset: Int, in s: String) -> String.Index {
        return s.index(index, offsetBy: -offset, limitedBy: s.startIndex) ?? s.startIndex
    }

    /// The index `offset` characters after `index`, clamped.
    private static func after(_ index: String.Index, by offset: Int, in s: String) -> String.Index {
        return s.index(index, offsetBy: offset, limitedBy: s.endIndex) ?? s.endIndex
    }

    static func htmlUnescape(_ s: String) -> String {
        var out = s
        // Numeric entities first, then the named ones, &amp; last so an
        // escaped "&amp;#39;" is not unescaped twice.
        if let re = regex(#"&#(\d+);"#) {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, options: [], range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let code = Int(ns.substring(with: m.range(at: 1))) ?? 0
                if let scalar = Unicode.Scalar(code) {
                    result += String(Character(scalar))
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        out = out.replacingOccurrences(of: "&#x27;", with: "'")
        out = out.replacingOccurrences(of: "&#39;", with: "'")
        out = out.replacingOccurrences(of: "&apos;", with: "'")
        out = out.replacingOccurrences(of: "&quot;", with: "\"")
        out = out.replacingOccurrences(of: "&lt;", with: "<")
        out = out.replacingOccurrences(of: "&gt;", with: ">")
        out = out.replacingOccurrences(of: "&nbsp;", with: " ")
        out = out.replacingOccurrences(of: "&amp;", with: "&")
        return out
    }

    /// HTML fragment -> plain text, same normalisation as the plugin:
    /// <br> becomes a newline, tags are dropped, entities unescaped,
    /// each line's whitespace collapsed, empty lines removed.
    static func plain(_ fragment: String) -> String {
        var s = replacing(#"<br\s*/?>"#, in: fragment, with: "\n", options: .caseInsensitive)
        s = replacing(#"<[^>]+>"#, in: s, with: "")
        s = htmlUnescape(s)
        let lines = s.components(separatedBy: "\n").map { line in
            line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Title

    /// The entry's own title (raw text of the display-48 heading).
    static func title(in page: String) -> String? {
        guard let m = firstMatch(titlePattern, in: page) else { return nil }
        return htmlUnescape(m.groups[0].trimmingCharacters(in: .whitespaces))
    }

    private static func titleRange(in page: String) -> Range<String.Index>? {
        return firstMatch(titlePattern, in: page)?.range
    }

    // MARK: - Date (the plugin's _page_date)

    /// The entry date `yyyy-MM-dd`, from the "Month D, YYYY" byline in
    /// the window around the entry's own title.
    static func pageDate(in page: String) -> String? {
        let months = ["January": 1, "February": 2, "March": 3, "April": 4, "May": 5, "June": 6,
                      "July": 7, "August": 8, "September": 9, "October": 10, "November": 11, "December": 12]
        let segment: String
        if let tr = titleRange(in: page) {
            let lo = before(tr.lowerBound, by: 4000, in: page)
            let hi = after(tr.lowerBound, by: 8000, in: page)
            segment = String(page[lo..<hi])
        } else {
            segment = page
        }
        let pattern = #"(January|February|March|April|May|June|July|August|September|October|November|December) (\d{1,2}), (\d{4})"#
        guard let m = firstMatch(pattern, in: segment), let month = months[m.groups[0]] else { return nil }
        return String(format: "%@-%02d-%02d", m.groups[2], month, Int(m.groups[1]) ?? 0)
    }

    // MARK: - Hero media (the plugin's _hero)

    static func hero(in page: String) -> Hero? {
        guard let tr = titleRange(in: page) else { return nil }
        let winStart = before(tr.lowerBound, by: 30000, in: page)
        let win = String(page[winStart..<tr.lowerBound])

        if let figRange = win.range(of: "<figure class=\"hds-media-inner", options: .backwards) {
            let segEnd = after(figRange.lowerBound, by: 6000, in: win)
            let seg = String(win[figRange.lowerBound..<segEnd])
            let aMatch = firstMatch(#"<a[^>]+href="([^"]+)""#, in: seg)
            let imgMatch = firstMatch(#"<img[^>]+src="([^"]+)""#, in: seg)
            if let imgMatch {
                let display = htmlUnescape(imgMatch.groups[0])
                let href = aMatch.map { htmlUnescape($0.groups[0]) } ?? ""
                let original: String
                let hrefPath = href.components(separatedBy: "?").first ?? href
                if href.contains("/content/dam/") || firstMatch(#"\.(jpg|jpeg|png)$"#, in: hrefPath, options: .caseInsensitive) != nil {
                    original = href
                } else {
                    original = display
                        .replacingOccurrences(of: "dynamicimage/assets/science/", with: "content/dam/science/")
                        .components(separatedBy: "?").first ?? display
                }
                return .image(displayURL: display, originalURL: original)
            }
        }

        if let videoRange = win.range(of: "<video", options: .backwards) {
            let segEnd = after(videoRange.lowerBound, by: 4000, in: win)
            let seg = String(win[videoRange.lowerBound..<segEnd])
            if let sourceMatch = firstMatch(#"<source[^>]+src="([^"]+)""#, in: seg) {
                return .video(url: htmlUnescape(sourceMatch.groups[0]))
            }
        }
        return nil
    }

    // MARK: - Credit & explanation (the plugin's _entry_text)

    static func entryText(in page: String) -> (credit: String, explanation: String) {
        guard let tr = titleRange(in: page) else { return ("", "") }

        // Credit: the last hds-credits block in the 6 KB before the
        // title; its first <div> holds the "Credit: ..." line.
        var credit = ""
        let preStart = before(tr.lowerBound, by: 6000, in: page)
        let pre = String(page[preStart..<tr.lowerBound])
        if let creditsRange = pre.range(of: "hds-credits", options: .backwards) {
            let segEnd = after(creditsRange.lowerBound, by: 3000, in: pre)
            let seg = String(pre[creditsRange.lowerBound..<segEnd])
            if let divMatch = firstMatch(#"<div>(.*?)</div>"#, in: seg, options: .dotMatchesLineSeparators) {
                credit = plain(divMatch.groups[0])
            }
        }

        // Explanation: the media-detail-hero__description paragraph
        // after the title. The page also carries a JSON-escaped copy
        // of the article (literal \n, \', \/), so candidates are
        // un-escaped first and only one containing "Explanation:"
        // counts.
        var explanation = ""
        var pos = tr.upperBound
        for _ in 0..<6 {
            guard let ei = page.range(of: "media-detail-hero__description", range: pos..<page.endIndex) else { break }
            guard let gt = page.range(of: ">", range: ei.upperBound..<page.endIndex),
                  let pe = page.range(of: "</p>", range: gt.upperBound..<page.endIndex) else { break }
            var frag = String(page[gt.upperBound..<pe.lowerBound])
            frag = frag.replacingOccurrences(of: "\\/", with: "/")
            frag = frag.replacingOccurrences(of: "\\'", with: "'")
            frag = frag.replacingOccurrences(of: "\\n", with: "\n")
            frag = frag.replacingOccurrences(of: "\\t", with: "\t")
            frag = frag.replacingOccurrences(of: "\\\"", with: "\"")
            if frag.contains("Explanation:") {
                frag = replacing(#"^.*?<strong>\s*Explanation:\s*</strong>"#, in: frag, with: "",
                                 options: [.caseInsensitive, .dotMatchesLineSeparators])
                if let cut = frag.range(of: "Tomorrow's picture") {
                    frag = String(frag[..<cut.lowerBound])
                    frag = replacing(#"<strong>\s*$"#, in: frag, with: "", options: .caseInsensitive)
                }
                explanation = plain(frag)
                break
            }
            pos = ei.upperBound
        }
        return (credit, explanation)
    }
}
