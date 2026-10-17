import AppKit
import LumenCore
import SwiftUI

// Группы ботов: аватары стопкой, строка в панели, шапка и пустой экран разговора, редактор группы.

/// Знаки участников стопкой
struct GroupAvatars: View {
    let bots: [Bot]
    var size: CGFloat = 22

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(bots.prefix(4)) { b in
                BotAvatar(bot: b, size: size)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(p.background, lineWidth: 1.5))
            }
            if bots.count > 4 {
                Text("+\(bots.count - 4)").font(.geist(size * 0.42, .medium)).foregroundStyle(p.mutedFg)
                    .frame(width: size, height: size)
                    .background(p.secondary, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            }
        }
    }
}

struct GroupRow: View {
    @Bindable var app: AppModel
    let group: BotGroup

    @Environment(\.palette) private var p
    @State private var hover = false

    private var active: Bool {
        switch app.page {
        case .group(let id), .groupEditor(.some(let id)): id == group.id
        default: false
        }
    }

    private var working: Bool {
        app.chat.turns.values.contains { $0.conversation.kind == .group && $0.conversation.groupID == group.id }
    }

    var body: some View {
        Button { app.openGroup(group.id) } label: {
            HStack(spacing: 10) {
                GroupAvatars(bots: app.groupMembers(group), size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.name).tw(14, lh: 20).lineLimit(1)
                    Text(Plural.bots(group.members.count)).tw(11, lh: 14).foregroundStyle(p.mutedFg).lineLimit(1)
                }
                Spacer(minLength: 4)
                if working { LiveDot(color: p.glow) }
            }
            .foregroundStyle(active ? p.foreground : p.foreground.opacity(0.8))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.04) : .clear), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(alignment: .leading) {
                if active { Capsule().fill(p.glow).frame(width: 2, height: 16).offset(x: -2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onRightClick { point in
            app.menu = MenuState(items: [
                MenuItem(title: "Открыть", key: "o") { app.openGroup(group.id) },
                MenuItem(title: "Изменить группу", key: "e") { app.page = .groupEditor(group.id) },
                MenuItem(title: "Удалить группу", key: "d", destructive: true, separated: true) { app.deleteGroup(group) },
            ], anchor: point)
        }
    }
}

/// Пустой разговор группы: участники и как тут всё устроено
struct GroupEmpty: View {
    @Bindable var app: AppModel
    let group: BotGroup
    @Binding var draft: String

    @Environment(\.palette) private var p

    var body: some View {
        let members = app.groupMembers(group)
        VStack(spacing: 0) {
            GroupAvatars(bots: members, size: 48)
            Text(group.name).tw(24, .semibold, lh: 32).tracking(-0.48).padding(.top, 24)
            Text(members.map { "@\($0.id)" }.joined(separator: " · ")).tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.top, 8)
            Text("Пиши всем — ответят по очереди те, кому есть что сказать. «@id …» — ответит только он. Боты сами зовут друг друга.")
                .tw(12, lh: 16).foregroundStyle(p.mutedFg.opacity(0.8)).multilineTextAlignment(.center)
                .frame(maxWidth: 460).padding(.top, 6)
            FlowChips(items: ["Обсудите, с чего начать", "Каждый — по одной идее", "@\(members.first?.id ?? "бот") начни"]) { draft = $0 }
                .padding(.top, 24)
        }
        .frame(maxWidth: 704)
        .padding(.horizontal, 24)
    }
}

/// Создать или изменить группу: название, участники (2–6), цвет
struct GroupEditor: View {
    @Bindable var app: AppModel
    let groupID: String?

    @Environment(\.palette) private var p
    @State private var draft = BotGroup(name: "", members: [])
    @State private var loaded = false

    private var existing: BotGroup? { app.group(groupID) }
    private var valid: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.members.count >= 2 }

    var body: some View {
        PageFrame(title: existing == nil ? "Новая группа" : "Группа «\(existing?.name ?? "")»",
                  lead: "Несколько ботов в одном разговоре — как в Hermes: отвечают по очереди, сами зовут друг друга, молчат, если нечего добавить.") {
            HStack(spacing: 8) {
                LButton(title: "Отмена", kind: .ghost) { cancel() }
                LButton(title: existing == nil ? "Создать" : "Сохранить", icon: "check", kind: .primary) { save() }
                    .disabled(!valid)
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Название").tw(14, .medium, lh: 20)
                        GlowField(placeholder: "Например, Команда сайта", text: $draft.name)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Участники").tw(14, .medium, lh: 20)
                            Spacer()
                            Text("\(draft.members.count) из \(BotGroup.maxMembers) · нужно хотя бы 2").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                        }
                        if app.bots.isEmpty {
                            Text("Ботов пока нет — сначала создай их во «Все боты».").tw(13, lh: 18).foregroundStyle(p.mutedFg)
                        }
                        ForEach(app.bots) { b in memberRow(b) }
                    }
                    if let existing {
                        LButton(title: "Удалить группу", icon: "trash", kind: .ghost, small: true) { app.deleteGroup(existing) }
                            .foregroundStyle(Palette.destructive)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.never)
        }
        .onAppear(perform: load)
    }

    private func memberRow(_ b: Bot) -> some View {
        let on = draft.members.contains(b.id)
        let full = !on && draft.members.count >= BotGroup.maxMembers
        return Button {
            if on { draft.members.removeAll { $0 == b.id } } else if !full { draft.members.append(b.id) }
        } label: {
            HStack(spacing: 12) {
                BotAvatar(bot: b, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(b.name).tw(14, .medium, lh: 20)
                    Text("@\(b.id) · \(b.role)").tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                }
                Spacer()
                Icon(on ? "circle-check" : "plus", 16).foregroundStyle(on ? BotColor.accent(b.hue) : p.mutedFg)
            }
            .padding(12)
            .background(on ? BotColor.faint(b.hue) : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(on ? BotColor.soft(b.hue) : p.border))
            .contentShape(Rectangle())
            .opacity(full ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(full)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing { draft = existing }
    }

    private func save() {
        var g = draft
        g.name = g.name.trimmingCharacters(in: .whitespaces)
        g = app.saveGroup(g)
        app.openGroup(g.id)
    }

    private func cancel() {
        if let existing { app.openGroup(existing.id) } else { app.page = .bots }
    }
}
