import AppKit
import LumenCore
import SwiftUI

/// «Артефакты»: всё, что Lumen и боты выдали вложением — файлы (make_file), снимки страниц, показанные картинки.
/// Ничего не лежит в проектах: открыть сбоку, скачать в «Загрузки», перейти в разговор, откуда это.
struct ArtifactsView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var items: [(attachment: Attachment, message: ChatMessage, title: String)] = []
    @State private var query = ""
    @State private var filter = 0

    private var shown: [(attachment: Attachment, message: ChatMessage, title: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { it in
            (filter == 0 || (filter == 1) == (it.attachment.kind != .image))
                && (q.isEmpty || (it.attachment.name + " " + it.title).lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Артефакты").font(.geist(28, .semibold))
                Text("Файлы и картинки, которые выдали Lumen и боты. В проекты они не пишутся — открой сбоку или скачай.")
                    .font(.geist(14)).foregroundStyle(p.mutedFg)
            }
            HStack(spacing: 12) {
                SearchField(text: $query, placeholder: "Поиск по имени и разговору")
                MiniSegmented(value: $filter, options: [(0, "Все \(items.count)"), (1, "Файлы"), (2, "Картинки")])
            }
            if shown.isEmpty {
                Text(items.isEmpty ? "Пока пусто. Попроси Lumen или бота «сделай файл…» — он появится здесь и под ответом."
                                   : "Ничего не нашлось.")
                    .font(.geist(14)).foregroundStyle(p.mutedFg)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)], spacing: 12) {
                        ForEach(shown, id: \.attachment.id) { it in card(it) }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 40).padding(.top, 48)
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(p.foreground)
        .task { reload() }
    }

    private func reload() {
        let rows = (try? app.store.artifacts()) ?? []
        items = rows.flatMap { row in row.message.attachments.map { (attachment: $0, message: row.message, title: row.title) } }
    }

    private func card(_ it: (attachment: Attachment, message: ChatMessage, title: String)) -> some View {
        let a = it.attachment
        return VStack(alignment: .leading, spacing: 0) {
            Button { app.preview(a) } label: {
                Group {
                    if a.kind == .image, let img = ThumbCache.image(a.url) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else if a.kind != .image, let text = try? String(contentsOf: a.url, encoding: .utf8) {
                        // начало текста — как превью
                        Text(String(text.prefix(400))).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.mutedFg)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                    } else {
                        Icon("file", 24).foregroundStyle(p.mutedFg).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 130).frame(maxWidth: .infinity).clipped()
                .background(p.card)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Открыть сбоку")
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).tw(13, .medium, lh: 18).lineLimit(1)
                    Button { if let c = app.conversations.first(where: { $0.id == it.message.conversationID }) { app.openChat(c) } } label: {
                        Text("«\(it.title)» · \(RelativeWhen.string(it.message.createdAt)) · \(a.sizeText)")
                            .tw(11, lh: 14).foregroundStyle(p.mutedFg).lineLimit(1)
                    }
                    .buttonStyle(.plain).help("Перейти в разговор")
                }
                Spacer(minLength: 0)
                IconButton(icon: "download", help: "Скачать в «Загрузки»") { app.download(a) }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
    }
}
