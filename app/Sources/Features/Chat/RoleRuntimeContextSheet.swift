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
                    List {
                        Section {
                            Text(context.notice ?? "Изменения применятся при следующем запуске роли.")
                            if !groups.isEmpty {
                                Picker("Раздел", selection: $group) {
                                    ForEach(groups, id: \.self) { Text($0).tag($0) }
                                }.accessibilityIdentifier("roleContext.groups")
                            }
                        }
                        if let blocks = context.blocks {
                            ForEach(blocks.filter { $0.group == group }) { block in
                                NavigationLink {
                                    RoleInstructionEditor(role: role.role, block: block, canEdit: context.canEdit == true, service: service)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(block.title)
                                        Text(block.source).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.accessibilityIdentifier("roleContext.block.\(block.id)")
                            }
                        } else {
                            ForEach(context.layers) { layer in
                                Section(layer.title) {
                                    Text(layer.source).font(.caption)
                                    Text(layer.text).textSelection(.enabled)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Не удалось загрузить инструкции", systemImage: "exclamationmark.triangle", description: Text(errorText ?? ""))
                }
            }
            .navigationTitle("Контекст роли")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
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
