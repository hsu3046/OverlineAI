import AppKit
import SwiftUI
import WidgetKit

@main struct RenderWidgets {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let text = String(repeating: "책을 읽다가 마음에 남은 문장을 만났습니다. 한 조각씩 모아 둔 문장은 시간이 지나 나만의 생각으로 이어집니다. 다시 읽을 때마다 새로운 의미를 발견합니다. ", count: 5)
        for (name, family, width, height, tone) in [
            ("small", WidgetFamily.systemSmall, 158.0, 158.0, "rose"),
            ("medium", .systemMedium, 378.0, 176.0, "yellow"),
            ("large", .systemLarge, 338.0, 354.0, "purple")
        ] {
            let quote = WidgetQuote(id: UUID(), bookID: WidgetSamples.book.id, text: text,
                bookTitle: "나의 독서 노트", author: "글조각 서랍", page: "p.128", tone: tone, createdAt: .now)
            let entry = QuoteEntry(date: .now, quote: quote, books: [WidgetSamples.book])
            let widget = QuoteWidgetView(entry: entry, family: family)
            let view = widget
                .environment(\.colorScheme, .light)
                .padding(16).frame(width: width, height: height).background(widget.widgetBackground)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Unable to render widget") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { fatalError("Unable to encode widget") }
            try data.write(to: output.appendingPathComponent("\(name).png"))
        }
    }
}
