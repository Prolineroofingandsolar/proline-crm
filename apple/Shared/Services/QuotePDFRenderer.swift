import CoreGraphics
import CoreText
import Foundation
import UniformTypeIdentifiers
import SwiftUI

enum QuotePDFRenderer {
    static func data(quote: CRMQuote, lead: Lead, companyName: String = "ProLine Roofing & Solar") -> Data {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: output as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let orange = CGColor(red: 0.86, green: 0.31, blue: 0.015, alpha: 1), black = CGColor(gray: 0.08, alpha: 1), grey = CGColor(gray: 0.36, alpha: 1)
        let watermarkGrey = CGColor(gray: 0.92, alpha: 0.52), watermarkOrange = CGColor(red: 0.98, green: 0.93, blue: 0.89, alpha: 0.48)
        var page = 0, y: CGFloat = 0, contentX: CGFloat = 84, contentWidth: CGFloat = 462

        @discardableResult func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat, size: CGFloat, bold: Bool = false, italic: Bool = false, underline: Bool = false, color: CGColor = CGColor(gray: 0.08, alpha: 1), alignment: CTTextAlignment = .left, lineSpacing: CGFloat = 3) -> CGFloat {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : (italic ? "Helvetica-Oblique" : "Helvetica")) as CFString, size, nil)
            var align = alignment, spacing = lineSpacing
            let paragraph: CTParagraphStyle = withUnsafePointer(to: &align) { alignPointer in
                withUnsafePointer(to: &spacing) { spacingPointer in
                    let settings = [
                        CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignPointer),
                        CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: spacingPointer)
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph]
            if underline { attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = CTUnderlineStyle.single.rawValue }
            let attributed = NSAttributedString(string: value, attributes: attributes)
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            let height = ceil(suggested.height) + 2
            let path = CGPath(rect: CGRect(x: x, y: box.height - top - height, width: width, height: height), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), path, nil), context)
            return height
        }
        func line(_ top: CGFloat) { context.setStrokeColor(black); context.setLineWidth(3); context.move(to: CGPoint(x: contentX, y: box.height - top)); context.addLine(to: CGPoint(x: box.width - 28, y: box.height - top)); context.strokePath() }
        func decoration(first: Bool) {
            if first {
                context.setFillColor(black); context.fill(CGRect(x: 0, y: 0, width: 57, height: box.height)); context.setFillColor(orange)
                context.beginPath(); context.move(to: .zero); context.addLine(to: CGPoint(x: 57, y: 0)); context.addLine(to: CGPoint(x: 57, y: 320)); context.addLine(to: CGPoint(x: 0, y: 338)); context.closePath(); context.fillPath()
            } else {
                context.setFillColor(black); context.fill(CGRect(x: box.width - 43, y: 0, width: 43, height: 300)); context.setFillColor(orange)
                context.beginPath(); context.move(to: CGPoint(x: box.width - 43, y: 0)); context.addLine(to: CGPoint(x: box.width, y: 0)); context.addLine(to: CGPoint(x: box.width, y: 276)); context.addLine(to: CGPoint(x: box.width - 43, y: 292)); context.closePath(); context.fillPath()
            }
            text("PRO", x: first ? 102 : 74, top: first ? 475 : 315, width: 230, size: 74, bold: true, color: watermarkOrange)
            text("LINE", x: first ? 276 : 248, top: first ? 475 : 315, width: 270, size: 74, bold: true, color: watermarkGrey)
            text("ROOFING & SOLAR", x: first ? 126 : 98, top: first ? 552 : 392, width: 400, size: 25, bold: true, color: watermarkGrey, alignment: .center)
        }
        func beginPage(first: Bool = false) {
            context.beginPDFPage(nil); page += 1; decoration(first: first); contentX = first ? 84 : 78; contentWidth = first ? 462 : 460
            if first {
                text("PRO", x: 88, top: 31, width: 72, size: 27, bold: true); text("LINE", x: 150, top: 31, width: 82, size: 27, bold: true, color: orange)
                text("ROOFING & SOLAR", x: 90, top: 61, width: 150, size: 8, bold: true)
                text("+44 7587 478826", x: 410, top: 26, width: 150, size: 9, bold: true); text("Admin@prolineroofingandsolar.co.uk", x: 365, top: 51, width: 195, size: 8, bold: true); text("75 Hardys Road, Taunton, TA2 8FA", x: 390, top: 76, width: 170, size: 8, bold: true)
                line(116); y = 137
            } else { y = 48 }
        }
        func endPage() { if page == 1 { text("ProLine Roofing & Solar Limited is a registered company in England. Company Registration Number: 16644701", x: 62, top: 818, width: 486, size: 7, color: grey) }; context.endPDFPage() }
        func ensure(_ height: CGFloat) { if y + height > 785 { endPage(); beginPage() } }
        func formattedDate() -> String { let date = ISO8601DateFormatter().date(from: quote.createdAt) ?? Date(); let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_GB"); formatter.dateFormat = "d MMMM yyyy"; return formatter.string(from: date) }

        beginPage(first: true)
        let customerHeading = lead.address.isEmpty ? lead.name : "\(lead.name)\n\(lead.address)"
        let titleHeight = text(customerHeading, x: contentX, top: y, width: 300, size: 14, bold: true, italic: true, underline: true, color: orange, lineSpacing: 4)
        text(formattedDate(), x: 420, top: y, width: 140, size: 13, alignment: .right); y += max(titleHeight, 32) + 22
        y += text("Hi \(lead.name.split(separator: " ").first.map(String.init) ?? lead.name),", x: contentX, top: y, width: contentWidth, size: 11) + 16
        y += text(quote.customerMessage, x: contentX, top: y, width: contentWidth, size: 11, lineSpacing: 5) + 18
        y += text("Please find the full breakdown of the works below.", x: contentX, top: y, width: contentWidth, size: 11, bold: true) + 14
        for item in quote.lineItems.filter({ $0.category.caseInsensitiveCompare("Scope") == .orderedSame }) {
            let parts = item.description.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).map(String.init), heading = parts.first ?? "Proposed works", details = parts.count > 1 ? parts[1] : item.description
            ensure(CGFloat(max(58, (details.count / 78 + 1) * 17 + 28))); y += text("• \(heading)", x: contentX, top: y, width: contentWidth, size: 10.5, bold: true); y += text(details, x: contentX, top: y, width: contentWidth, size: 10.5, lineSpacing: 4) + 6
        }
        ensure(300); y += 18; y += text("Quote Summary", x: contentX, top: y, width: contentWidth, size: 20, bold: true, alignment: .center) + 18
        let termParts = quote.terms.components(separatedBy: "\n\n"), guarantee = termParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !guarantee.isEmpty { y += text(guarantee, x: contentX, top: y, width: contentWidth, size: 11, bold: true, underline: true, alignment: .center) + 30 }
        let base = max(0, quote.subtotal - quote.discount)
        let vatLine = quote.vatRate > 0 ? "VAT at \(quote.vatRate.formatted(.number.precision(.fractionLength(0...2))))%: \(quote.vat.formatted(.currency(code: "GBP")))\nTotal: \(quote.total.formatted(.currency(code: "GBP")))" : "No VAT applicable"
        y += text("Total for All Works (Materials + Labour) -\n\(base.formatted(.currency(code: "GBP")))\n\(vatLine)", x: contentX + 120, top: y, width: contentWidth - 120, size: 14, bold: true, alignment: .right, lineSpacing: 5) + 34
        if termParts.count > 1 { y += text(termParts.dropFirst().joined(separator: "\n\n"), x: contentX, top: y, width: contentWidth, size: 8.5, color: grey, alignment: .center) + 24 }
        ensure(125); text("William Conway", x: contentX, top: max(y + 35, 660), width: 220, size: 15, bold: true); text("W. Conway", x: contentX, top: max(y + 65, 690), width: 250, size: 28, italic: true)
        endPage(); context.closePDF(); return output as Data
    }
}

struct QuotePDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
