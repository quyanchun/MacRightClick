import SwiftUI

struct ActionsHubView: View {
    var body: some View {
        MenuEditorView()
    }
}

/// 保留给高级页使用的动作分组。
struct ActionListGroupView: View {
    let title: String
    let iconName: String
    let items: [ActionItem]
    var showsIdentifiers = false
    var footer: String?

    var body: some View {
        GroupBox(label: Label(title, systemImage: iconName)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    ActionRowView(action: item.action, showsIdentifier: showsIdentifiers)
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
                if let footer {
                    Divider()
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct ActionRowView: View {
    let action: MenuAction
    var showsIdentifier = false
    var configurationRevision = 0
    var onConfigurationChanged: () -> Void = {}

    @State private var isEnabled = true

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: ActionIcon.image(for: action))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(action.localizedTitle)
                    if isApplicationUnavailable {
                        Label("未安装", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if action.isHighRisk {
                        Label("高级", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if showsIdentifier {
                    Text(action.actionId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let riskDescription = action.riskDescription {
                    Text(riskDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: saveEnabledState
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel("启用 \(action.localizedTitle)")
        }
        .padding(.vertical, 5)
        .onAppear(perform: loadState)
        .onChange(of: configurationRevision) { _ in loadState() }
    }

    private var isApplicationUnavailable: Bool {
        guard let bundleID = action.associatedBundleIdentifier else { return false }
        return !InstalledAppRegistry.shared.isInstalled(bundleID)
    }

    private func loadState() {
        isEnabled = SharedStorageManager.shared.isActionEnabled(action)
    }

    private func saveEnabledState(_ enabled: Bool) {
        let key = "enable_action_\(action.actionId)"
        guard SharedStorageManager.shared.applyConfigurationChanges(
            booleanValues: [key: enabled],
            stringArrayValues: [
                SharedStorageManager.Keys.actionProfile: [ActionProfile.custom.rawValue]
            ]
        ) else {
            showConfigurationSaveFailure(action.localizedTitle)
            return
        }
        isEnabled = enabled
        postConfigChanged()
        onConfigurationChanged()
    }


}

struct ActionItem: Identifiable {
    let id: String
    let action: MenuAction
}
