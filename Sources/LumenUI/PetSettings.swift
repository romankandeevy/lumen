import AppKit
import LumenCore
import SwiftUI

/// Настройки питомца: включить, выбрать, нарисовать своего, вернуть на место (раздел «Питомец»)
struct PetSettings: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var request = ""
    @State private var drawing = false
    @State private var note: String?

    /// Пресеты и нарисованный, если есть
    private var options: [PetSpec] { PetPresets.all + (app.customPet.map { [$0] } ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Питомец на экране", "Поверх всех окон. Перетащи мышью, нажми — погладишь.") {
                LSwitch(isOn: Binding(get: { app.prefs.petEnabled }, set: { app.setPetEnabled($0) }))
            }
            GroupTitle(text: "Кто на экране").padding(.top, 24)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 12)], spacing: 12) {
                ForEach(options) { spec in card(spec) }
            }
            GroupTitle(text: "Нарисовать своего").padding(.top, 24)
            Text("Опиши словами — Lumen нарисует. То же можно в чате: /create-pet рыжий лис в шарфе.")
                .tw(13, lh: 18).foregroundStyle(p.mutedFg).padding(.top, 6)
            HStack(spacing: 8) {
                GlowField(placeholder: "Например: чёрный кот в очках", text: $request, onSubmit: draw)
                LButton(title: drawing ? "Рисую…" : "Нарисовать", icon: "sparkles", kind: .primary, small: true, busy: drawing, action: draw)
                    .disabled(drawing || request.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 12)
            if let note {
                Text(note).tw(13, lh: 18).foregroundStyle(p.mutedFg).padding(.top, 8)
            }
            row("Вернуть на место", "Если питомец уехал за экран или затерялся.") {
                LButton(title: "Вернуть", icon: "refresh-cw", kind: .outline, small: true) { app.resetPetPlace() }
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private func card(_ spec: PetSpec) -> some View {
        let active = app.prefs.petID == spec.id
        return Button { app.choosePet(spec.id) } label: {
            VStack(spacing: 8) {
                PetPreview(spec: spec).frame(width: 64, height: 64)
                Text(spec.name).tw(13, .medium, lh: 18)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(active ? p.glow : p.border, lineWidth: active ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func draw() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !drawing else { return }
        drawing = true
        note = nil
        Task {
            let result = await app.draftPet(text)
            drawing = false
            switch result {
            case .success(let spec):
                app.setCustomPet(spec)
                request = ""
                note = "Готово: «\(spec.name)» на экране."
            case .failure(.noAnswer):
                note = "Не получилось: модель не ответила. Проверь вход в Claude в «Модели и оплата»."
            case .failure(.invalid):
                note = "Не получилось нарисовать. Опиши проще и попробуй ещё раз."
            }
        }
    }

    /// Строка: название и пояснение слева, управление справа, линия снизу — как в остальных настройках
    private func row<C: View>(_ title: String, _ hint: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tw(14, lh: 20)
                Text(hint).tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }
}

/// Питомец в маленьком виде: без движения, поза по умолчанию
struct PetPreview: NSViewRepresentable {
    let spec: PetSpec

    func makeNSView(context: Context) -> PetView {
        let view = PetView()
        view.moving = false
        return view
    }

    func updateNSView(_ view: PetView, context: Context) {
        view.spec = spec
    }
}
