import AppKit
import SwiftUI

import VibeBarCore

enum SessionSupplementalLinePrefix: Sendable, Equatable {
    case userInput
    case runningTask
}

enum SessionSupplementalLineTone: Sendable, Equatable {
    case secondary
    case tertiary
}

struct SessionSupplementalLine: Sendable, Equatable {
    var text: String
    var prefix: SessionSupplementalLinePrefix?
    var tone: SessionSupplementalLineTone
}

struct SessionCompactDetailLines: Sendable, Equatable {
    var row2: SessionSupplementalLine?
    var row3: SessionSupplementalLine?
}

@MainActor
enum SessionCompactDetailLineBuilder {
    static func build(
        for session: SessionSnapshot,
        context: SessionRowPresentationContext,
        maxDirectoryLength: Int
    ) -> SessionCompactDetailLines {
        let lastUserMessage = SessionDisplayFormatter.supplementalLastUserMessageText(for: session)
        let runningSummary = SessionDisplayFormatter.runningSummaryText(for: session)
        let secondaryText = lastUserMessage == nil
            ? SessionDisplayFormatter.secondaryText(for: session, context: context)
            : nil
        let directoryText = SessionDisplayFormatter.directoryText(
            for: session,
            context: context,
            maxLength: maxDirectoryLength
        )

        let row2: SessionSupplementalLine? = {
            if let lastUserMessage {
                return SessionSupplementalLine(
                    text: lastUserMessage,
                    prefix: .userInput,
                    tone: .secondary
                )
            }

            guard let secondaryText else {
                return nil
            }

            let prefix: SessionSupplementalLinePrefix? =
                runningSummary != nil && secondaryText == runningSummary ? .runningTask : nil

            return SessionSupplementalLine(
                text: secondaryText,
                prefix: prefix,
                tone: .secondary
            )
        }()

        let row3: SessionSupplementalLine? = {
            if lastUserMessage != nil, let runningSummary {
                return SessionSupplementalLine(
                    text: runningSummary,
                    prefix: .runningTask,
                    tone: .tertiary
                )
            }

            guard let directoryText else {
                return nil
            }

            return SessionSupplementalLine(
                text: directoryText,
                prefix: nil,
                tone: .tertiary
            )
        }()

        return SessionCompactDetailLines(row2: row2, row3: row3)
    }
}

struct SessionSupplementalLinePrefixView: View {
    let prefix: SessionSupplementalLinePrefix?
    let color: NSColor
    var pointSize: CGFloat = 10

    var body: some View {
        Group {
            if let prefix {
                Image(nsImage: SessionSupplementalLineIconRenderer.image(
                    for: prefix,
                    color: color,
                    pointSize: pointSize
                ))
                .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: pointSize, height: pointSize)
        .accessibilityHidden(true)
    }
}

@MainActor
enum SessionSupplementalLineAttributedStringBuilder {
    static func build(
        _ line: SessionSupplementalLine,
        font: NSFont,
        color: NSColor,
        iconSize: CGFloat = 10
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(prefixAttachment(prefix: line.prefix, color: color, iconSize: iconSize))
        result.append(NSAttributedString(
            string: line.text,
            attributes: [
                .font: font,
                .foregroundColor: color,
            ]
        ))
        return result
    }

    private static func prefixAttachment(
        prefix: SessionSupplementalLinePrefix?,
        color: NSColor,
        iconSize: CGFloat
    ) -> NSAttributedString {
        let image: NSImage
        if let prefix {
            image = SessionSupplementalLineIconRenderer.image(
                for: prefix,
                color: color,
                pointSize: iconSize
            )
        } else {
            image = SessionSupplementalLineIconRenderer.placeholder(pointSize: iconSize)
        }

        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttribute(
            .baselineOffset,
            value: floor((fontBaselineOffset(for: iconSize))),
            range: NSRange(location: 0, length: attachmentString.length)
        )
        attachmentString.append(NSAttributedString(string: " "))
        return attachmentString
    }

    private static func fontBaselineOffset(for iconSize: CGFloat) -> CGFloat {
        iconSize <= 10 ? -1 : -0.5
    }
}

@MainActor
enum SessionSupplementalLineIconRenderer {
    private struct CacheKey: Hashable {
        let prefix: SessionSupplementalLinePrefix
        let pointSize: Int
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int
    }

    private static var cache: [CacheKey: NSImage] = [:]
    private static var placeholderCache: [Int: NSImage] = [:]

    static func image(
        for prefix: SessionSupplementalLinePrefix,
        color: NSColor,
        pointSize: CGFloat
    ) -> NSImage {
        let rgba = rgbaComponents(for: color)
        let key = CacheKey(
            prefix: prefix,
            pointSize: Int(round(pointSize * 10)),
            red: Int(round(rgba.red * 255)),
            green: Int(round(rgba.green * 255)),
            blue: Int(round(rgba.blue * 255)),
            alpha: Int(round(rgba.alpha * 255))
        )
        if let cached = cache[key] {
            return cached
        }

        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            draw(prefix, in: context, rect: bounds, color: NSColor(
                calibratedRed: rgba.red,
                green: rgba.green,
                blue: rgba.blue,
                alpha: rgba.alpha
            ))
            return true
        }
        cache[key] = image
        return image
    }

    static func placeholder(pointSize: CGFloat) -> NSImage {
        let key = Int(round(pointSize * 10))
        if let cached = placeholderCache[key] {
            return cached
        }

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        placeholderCache[key] = image
        return image
    }

    private static func draw(
        _ prefix: SessionSupplementalLinePrefix,
        in context: CGContext,
        rect: CGRect,
        color: NSColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        switch prefix {
        case .userInput:
            drawUserInput(in: context, rect: rect, color: color)
        case .runningTask:
            drawRunningTask(in: context, rect: rect, color: color)
        }
    }

    private static func drawUserInput(
        in context: CGContext,
        rect: CGRect,
        color: NSColor
    ) {
        context.setFillColor(color.cgColor)

        let headRect = CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.minY + rect.height * 0.55,
            width: rect.width * 0.42,
            height: rect.height * 0.34
        )
        context.fillEllipse(in: headRect)

        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.16))
        bodyPath.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.16),
            control: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.52)
        )
        bodyPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.02))
        bodyPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.02))
        bodyPath.closeSubpath()
        context.addPath(bodyPath)
        context.fillPath()

        context.saveGState()
        context.translateBy(
            x: rect.minX + rect.width * 0.66,
            y: rect.minY + rect.height * 0.14
        )
        context.rotate(by: .pi / 4)

        let pencilRect = CGRect(
            x: -rect.width * 0.10,
            y: -rect.height * 0.05,
            width: rect.width * 0.38,
            height: rect.height * 0.16
        )
        let pencilPath = CGPath(
            roundedRect: pencilRect,
            cornerWidth: rect.width * 0.05,
            cornerHeight: rect.height * 0.05,
            transform: nil
        )
        context.addPath(pencilPath)
        context.fillPath()

        let tipPath = CGMutablePath()
        tipPath.move(to: CGPoint(x: pencilRect.maxX, y: pencilRect.minY))
        tipPath.addLine(to: CGPoint(x: pencilRect.maxX + rect.width * 0.10, y: 0))
        tipPath.addLine(to: CGPoint(x: pencilRect.maxX, y: pencilRect.maxY))
        tipPath.closeSubpath()
        context.addPath(tipPath)
        context.fillPath()
        context.restoreGState()
    }

    private static func drawRunningTask(
        in context: CGContext,
        rect: CGRect,
        color: NSColor
    ) {
        let mainPath = CGMutablePath()
        mainPath.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.94))
        mainPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.62))
        mainPath.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.midY))
        mainPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.38))
        mainPath.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06))
        mainPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.38))
        mainPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.midY))
        mainPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.62))
        mainPath.closeSubpath()

        context.setFillColor(color.withAlphaComponent(0.18).cgColor)
        context.addPath(mainPath)
        context.fillPath()

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(max(1, rect.width * 0.08))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(mainPath)
        context.strokePath()

        drawMiniSparkle(
            in: context,
            center: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.80),
            size: rect.width * 0.16,
            color: color
        )
        drawMiniSparkle(
            in: context,
            center: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.18),
            size: rect.width * 0.16,
            color: color
        )
    }

    private static func drawMiniSparkle(
        in context: CGContext,
        center: CGPoint,
        size: CGFloat,
        color: NSColor
    ) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(max(0.75, size * 0.18))
        context.setLineCap(.round)

        context.move(to: CGPoint(x: center.x, y: center.y - size))
        context.addLine(to: CGPoint(x: center.x, y: center.y + size))
        context.strokePath()

        context.move(to: CGPoint(x: center.x - size, y: center.y))
        context.addLine(to: CGPoint(x: center.x + size, y: center.y))
        context.strokePath()
    }

    private static func rgbaComponents(for color: NSColor) -> (
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) {
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        return (
            red: resolved.redComponent,
            green: resolved.greenComponent,
            blue: resolved.blueComponent,
            alpha: resolved.alphaComponent
        )
    }
}
