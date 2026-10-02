import SwiftUI

struct RoleRuntimeContextSheet: View {
    let role: RoleProfile
    @State private var context: RoleRuntimeContext?
    @State private var group = "Роль"
    @State private var errorText: String?
    @State private var loading = true
    @State private var service = RoleInstructionService()
    @Environment(\.dismiss) private var dismiss
    private var groups: [String] {
        var result: [String] = []
        for block in context?.blocks ?? [] where !result.contains(block.group) { result.append(block.group) }
        return result
    }
    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView() }
                else if let context {
                    ScrollView {
                        VStack(alignment: .leading, spacing: TFSpacing.lg) {
                            TFCard {
                                VStack(alignment: .leading, spacing: TFSpacing.md) {
                                    Text(context.notice ?? "Изменения применятся при следующем запуске роли.")
                                        .tfText(.caption).foregroundStyle(Color.tfSub)
                                    if !groups.isEmpty {
                                        Menu {
                                            ForEach(groups, id: \.self) { item in Button(item) { group = item } }
                                        } label: {
                                            HStack {
                                                Text(group).tfText(.body)
                                                Spacer()
                                                Image(systemName: "chevron.down")
                                            }.foregroundStyle(Color.tfText)
                                        }
                                        .accessibilityIdentifier("roleContext.groups")
                                    }
                                }
                            }
                            if let blocks = context.blocks {
                                TFCard(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(blocks.filter { $0.group == group }) { block in
                                            NavigationLink {
                                                RoleInstructionEditor(role: role.role, block: block, canEdit: context.canEdit == true, service: service)
                                            } label: {
                                                TFListRow(icon: "doc.text", iconStyle: .plain, title: block.title,
                                                          subtitle: block.source,
                                                          trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                                            }
                                            .buttonStyle(TFTapRowStyle())
                                            .accessibilityIdentifier("roleContext.block.\(block.id)")
                                            TFDivider(inset: TFSpacing.lg)
                                        }
                                    }
                                }
                            } else {
                                ForEach(context.layers) { layer in
                                    TFSectionHeader(layer.title)
                                    TFCard {
                                        VStack(alignment: .leading, spacing: TFSpacing.md) {
                                            Text(layer.source).tfText(.caption).foregroundStyle(Color.tfSub)
                                            Text(layer.text).tfText(.body).textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }.padding(TFSpacing.lg)
                    }
                } else {
                    ContentUnavailableView("Не удалось загрузить инструкции", systemImage: "exclamationmark.triangle", description: Text(errorText ?? ""))
                }
            }
            .tfNativeHeader("Контекст роли", displayMode: .inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .background(Color.tfBackground)
            .task { await load() }
            .refreshable { await load() }
        }
    }
    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do {
            context = try await service.context(role: role.role)
            if !groups.contains(group) { group = groups.first ?? "Роль" }
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }
}
