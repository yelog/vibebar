import SwiftUI
import VibeBarCore

@MainActor
final class HooksSettingsViewModel: ObservableObject {
    @Published var hooks: [HookConfig] = []
    @Published var isLoading = false
    @Published var editingHook: HookConfig?
    @Published var showingAddSheet = false
    @Published var errorMessage: String?

    private let store = HooksConfigStore()

    func loadHooks() {
        isLoading = true
        let config = store.load()
        hooks = config.hooks
        isLoading = false
    }

    func addHook(_ hook: HookConfig) {
        do {
            let config = try store.addHook(hook)
            hooks = config.hooks
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateHook(_ hook: HookConfig) {
        do {
            let config = try store.updateHook(hook)
            hooks = config.hooks
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteHook(id: String) {
        do {
            let config = try store.deleteHook(id: id)
            hooks = config.hooks
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleHook(id: String, enabled: Bool) {
        do {
            let config = try store.setHookEnabled(id: id, enabled: enabled)
            hooks = config.hooks
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func testHook(_ hook: HookConfig) async {
        do {
            try await HooksExecutor.shared.test(hook)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HooksSettingsView: View {
    @StateObject private var viewModel = HooksSettingsViewModel()
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.hooks.isEmpty {
                emptyStateView
            } else {
                hooksListView
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .sheet(isPresented: $viewModel.showingAddSheet) {
            HookEditView(hook: nil) { newHook in
                viewModel.addHook(newHook)
            }
        }
        .sheet(item: $viewModel.editingHook) { hook in
            HookEditView(hook: hook) { updatedHook in
                viewModel.updateHook(updatedHook)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            viewModel.loadHooks()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.string(.hooksTitle))
                .font(.system(size: 20, weight: .semibold))

            Text(l10n.string(.hooksDesc))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button {
                    viewModel.showingAddSheet = true
                } label: {
                    Label(l10n.string(.hooksAddHook), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(l10n.string(.hooksNoHooks))
                .font(.headline)
                .foregroundColor(.secondary)

            Text(l10n.string(.hooksDesc))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hooksListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.hooks, id: \.id) { hook in
                    HookRowView(
                        hook: hook,
                        onToggle: { enabled in
                            viewModel.toggleHook(id: hook.id, enabled: enabled)
                        },
                        onEdit: {
                            viewModel.editingHook = hook
                        },
                        onDelete: {
                            viewModel.deleteHook(id: hook.id)
                        },
                        onTest: {
                            Task {
                                await viewModel.testHook(hook)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct HookRowView: View {
    let hook: HookConfig
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            Toggle("", isOn: Binding(
                get: { hook.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(hook.name)
                    .font(.system(size: 14, weight: .medium))

                HStack(spacing: 8) {
                    Label(hook.action.type.displayName, systemImage: hook.action.type == .shell ? "terminal" : "network")

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(hook.triggers.count) triggers")
                        .foregroundColor(.secondary)

                    if let tools = hook.tools, !tools.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(tools.map { $0.displayName }.joined(separator: ", "))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onTest) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Test Hook")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(l10n.string(.hooksEditHook))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help(l10n.string(.hooksDeleteHook))
            }
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}