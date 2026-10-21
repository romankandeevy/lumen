import AppKit
import LumenCore
import SwiftUI

/// «Артефакты»: всё, что Lumen и боты выдали вложением — файлы (make_file), снимки страниц, показанные картинки.
/// Ничего не лежит в проектах: открыть сбоку, скачать в «Загрузки», перейти в разговор, откуда это, или прикрепить к чату.
/// «Прикрепить» копит файлы внизу («2 файла ждут · Открыть чат»), поле ввода забирает их при открытии чата (Рома, 21.10)
struct ArtifactsView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var items: [Item] = []
    @State private var query = ""
    @State private var filter = 0

    struct Item: Identifiable {
        let attachment: Attachment
        let message: ChatMessage
        let title: String
        var id: String { attachment.id }
    }

    private var shown: [Item] {
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
                Text("Файлы и картинки, которые выдали Lumen и боты. Открой сбоку, скачай или прикрепи к чату.")
                    .font(.geist(14)).foregroundStyle(p.mutedFg)
            }
            HStack(spacing: 12) {
                GlowField(placeholder: "Поиск по имени и разговору", text: $query, icon: "search")
                MiniSegmented(value: $filter, options: [(0, "Все \(items.count)"), (1, "Файлы"), (2, "Картинки")])
            }
            if shown.isEmpty {
                Text(items.isEmpty ? "Пока пусто. Попроси Lumen или бота «сделай файл…» — он появится здесь и под ответом."
                                   : "Ничего не нашлось.")
                    .font(.geist(14)).foregroundStyle(p.mutedFg)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 400), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(shown) { it in
                            ArtifactCard(app: app, item: it, attached: app.attachInbox.contains { $0.path == it.attachment.path })
                        }
                    }
                    .padding(.bottom, app.attachInbox.isEmpty ? 24 : 96)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 40).padding(.top, 48)
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { if !app.attachInbox.isEmpty { inboxBar.transition(.move(edge: .bottom).combined(with: .opacity)) } }
        .animation(.easeOut(duration: 0.2), value: app.attachInbox.isEmpty)
        .foregroundStyle(p.foreground)
        .task { reload() }
    }

    /// Что ждёт отправки: сколько файлов, куда пойдут, «Открыть чат» и «Убрать»
    private var inboxBar: some View {
        let n = app.attachInbox.count
        let target = app.chat.conversation.map { "«\($0.title)»" } ?? "новый чат"
        return HStack(spacing: 14) {
            Icon("paperclip", 16).foregroundStyle(p.glow)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(n) " + Plural.form(n, "файл ждёт", "файла ждут", "файлов ждут") + " в поле ввода").font(.geist(14, .medium))
                Text("Уйдут в " + target).font(.geist(12.5)).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer(minLength: 12)
            LButton(title: "Убрать", kind: .ghost, small: true) { app.attachInbox = [] }.fixedSize()
            LButton(title: "Открыть чат", icon: "arrow-right", kind: .glow, small: true) { app.page = .chat }.fixedSize()
        }
        .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 10)
        .frame(maxWidth: 620)
        .popoverChrome()
        .padding(.bottom, 24).padding(.horizontal, 40)
    }

    private func reload() {
        let rows = (try? app.store.artifacts()) ?? []
        items = rows.flatMap { row in row.message.attachments.map { Item(attachment: $0, message: row.message, title: row.title) } }
    }
}

/// Карточка артефакта: превью в рамке (картинка — сверху, текст — первые строки), метка типа,
/// название в две строки, откуда и когда; внизу «Прикрепить», «Скачать» и «Открыть разговор»
private struct ArtifactCard: View {
    @Bindable var app: AppModel
    let item: ArtifactsView.Item
    let attached: Bool

    @Environment(\.palette) private var p
    @State private var hover = false

    private var a: Attachment { item.attachment }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Button { app.preview(a) } label: { preview }
                .buttonStyle(.plain)
                .help("Открыть сбоку")
            VStack(alignment: .leading, spacing: 4) {
                Text(a.name).font(.geist(13.5, .medium)).lineLimit(2).truncationMode(.tail)
                    // всегда место под две строки: карточки в ряду ровные
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                Text("«\(item.title)» · \(RelativeWhen.string(item.message.createdAt)) · \(a.sizeText)").font(.geist(12)).foregroundStyle(p.faint).monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.top, 12)
            HStack(spacing: 4) {
                attachButton
                Spacer(minLength: 4)
                IconButton(icon: "message-square", help: "Открыть разговор «\(item.title)»") {
                    if let c = app.conversations.first(where: { $0.id == item.message.conversationID }) { app.openChat(c) }
                }
                IconButton(icon: "download", help: "Скачать в «Загрузки»") { app.download(a) }
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 10)
        }
        .background(shape.fill(LinearGradient(colors: [p.borderBase.opacity(hover ? 0.06 : 0.045), p.borderBase.opacity(hover ? 0.035 : 0.02)],
                                              startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(attached ? p.glow.opacity(0.45) : p.borderBase.opacity(hover ? 0.12 : 0.07)))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
    }

    /// Превью в рамке со скруглением, с меткой типа слева сверху
    private var preview: some View {
        // рамка фиксированного размера, содержимое — поверх неё: картинка не может раздвинуть карточку
        Color.clear
            .frame(height: 164).frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if a.kind == .image, let img = ThumbCache.image(a.url) {
                    // снимки страниц длинные — показываем верх
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 164, alignment: .top)
                } else if a.kind != .image, let text = try? String(contentsOf: a.url, encoding: .utf8) {
                    // начало текста — как превью; книзу тает
                    Text(String(text.prefix(500))).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(p.mutedFg)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 12).padding(.top, 36)
                        .frame(height: 164, alignment: .top)
                        .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                } else {
                    Icon(a.kind == .pdf ? "file-text" : "file", 28).foregroundStyle(p.faint).frame(maxWidth: .infinity).frame(height: 164)
                }
            }
            .background(p.isLight ? p.secondary : Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(p.borderBase.opacity(0.06)))
            .overlay(alignment: .topLeading) {
                Text(kindLabel).font(.geist(11, .semibold)).foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(8)
            }
            .padding(6)
            .contentShape(Rectangle())
    }

    /// PNG, MD, PDF… — из расширения
    private var kindLabel: String {
        let ext = (a.name as NSString).pathExtension.uppercased()
        if !ext.isEmpty && ext.count <= 5 { return ext }
        switch a.kind { case .image: return "Картинка"; case .pdf: return "PDF"; case .text: return "Текст"; case .file: return "Файл" }
    }

    /// «Прикрепить» — в поле ввода чата; второй раз — убрать
    private var attachButton: some View {
        Button {
            if attached { app.attachInbox.removeAll { $0.path == a.path } } else { app.attachInbox.append(a) }
        } label: {
            HStack(spacing: 6) {
                Icon(attached ? "check" : "paperclip", 14)
                Text(attached ? "Прикреплено" : "Прикрепить").font(.geist(13, .medium))
            }
            .foregroundStyle(attached ? p.accentSoft : p.textControl)
            .padding(.horizontal, 10).frame(height: 30)
            .background(attached ? p.accentTint : p.hover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(attached ? "Убрать из поля ввода" : "Прикрепить к сообщению в чате")
    }
}
