import SwiftUI

struct MenuEditorView: View {
    @State private var draft: MenuConfiguration
    @State private var saved: MenuConfiguration
    @State private var enabled: [String: Bool]
    @State private var newGroupName = ""
    @State private var dropTargets: [String: MenuDropTarget] = [:]
    @State private var hoveredTarget: String?
    @GestureState private var dragging: MenuDragPreview?
    private let actions = ActionDispatcher.shared.allActions

    init() {
        let storage = SharedStorageManager.shared
        let actions = ActionDispatcher.shared.allActions
        let initial = (storage.menuConfiguration ?? .initial(actions: actions, mode: storage.menuLayoutMode,
            favorites: Set(storage.favoriteActionIds))).normalized(actions: actions)
        _draft = State(initialValue: initial)
        _saved = State(initialValue: initial)
        _enabled = State(initialValue: Dictionary(uniqueKeysWithValues: actions.map {
            ($0.actionId, storage.isActionEnabled($0))
        }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("一级菜单", systemImage: "list.bullet")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(targetArea("root", group: nil, before: draft.entries.first?.id))
                TextField("新分组名称", text: $newGroupName).frame(width: 150)
                Button("添加分组") {
                    draft.entries.append(.group(String(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))))
                    newGroupName = ""
                }.disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(draft.entries) { entry in
                        rootInsertion(before: entry.id)
                        if entry.isGroup {
                            VStack(alignment: .leading, spacing: 0) {
                                groupRow(entry)
                                ForEach(entry.actionIDs, id: \.self) { actionID in
                                    actionRow(actionID, group: entry.id).padding(.leading, 28)
                                }
                                Color.clear.frame(height: 12).padding(.leading, 28)
                                    .background(targetArea("end.\(entry.id)", group: entry.id))
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            // The unindented gutter belongs to the root, even beside a nested action.
                            .background(targetArea("root.\(entry.id)", group: nil, before: entry.id))
                            .opacity(dragging?.id == entry.id ? 0.25 : 1)
                        } else {
                            actionRow(entry.id, group: nil).padding(.horizontal, 8)
                        }
                    }
                    rootInsertion(before: nil)
                }
                .padding(.horizontal, 4)
            }
            HStack {
                Spacer()
                Button("恢复默认布局") {
                    draft = .initial(actions: actions, mode: .flat, favorites: [])
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let dragging {
                dragPreview(dragging)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .coordinateSpace(name: "menuEditor")
        .onPreferenceChange(MenuDropTargets.self) { dropTargets = $0 }
        .onChange(of: draft) { value in
            guard value != saved else { return }
            guard SharedStorageManager.shared.setMenuConfiguration(value.normalized(actions: actions)) else {
                draft = saved
                showConfigurationSaveFailure("菜单编排")
                return
            }
            saved = value
            postConfigChanged()
        }
        .onAppear {
            let storage = SharedStorageManager.shared
            let current = (storage.menuConfiguration ?? .initial(actions: actions, mode: storage.menuLayoutMode,
                favorites: Set(storage.favoriteActionIds))).normalized(actions: actions)
            saved = current
            draft = current
            enabled = Dictionary(uniqueKeysWithValues: actions.map { ($0.actionId, storage.isActionEnabled($0)) })
        }
    }

    private func handle(_ id: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary).frame(width: 22, height: 28)
            .contentShape(Rectangle())
            .help("拖动调整位置")
            .accessibilityLabel("拖动 \(title(for: id))")
            .gesture(dragGesture(id))
    }

    private func actionRow(_ id: String, group: String?) -> some View {
        HStack(spacing: 8) {
            handle(id)
            if let action = actions.first(where: { $0.actionId == id }) {
                Image(nsImage: ActionIcon.image(for: action)).resizable().frame(width: 20, height: 20)
                Text(action.localizedTitle).lineLimit(1)
                if let bundleID = action.associatedBundleIdentifier,
                   !InstalledAppRegistry.shared.isInstalled(bundleID) {
                    Text("未安装").font(.caption).foregroundStyle(.secondary)
                }
                if action.isHighRisk {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange).help(action.riskDescription ?? "高级动作")
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("移到一级菜单") { draft.move(id) }
                ForEach(draft.entries.filter(\.isGroup)) { destination in
                    Button("移到：\(destination.title ?? "分组")") { draft.move(id, toGroup: destination.id) }
                }
            } label: { Image(systemName: "arrow.turn.up.right") }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("移动 \(title(for: id))")
            Toggle("", isOn: Binding(get: { enabled[id] ?? false }, set: { saveEnabled(id, value: $0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("启用 \(title(for: id))")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(targetArea("action.\(id)", group: group, before: id))
        .opacity(dragging?.id == id ? 0.25 : 1)
    }

    private func groupRow(_ entry: MenuEntry) -> some View {
        HStack(spacing: 8) {
            handle(entry.id)
            Image(nsImage: ActionIcon.groupImage(title: entry.title ?? ""))
                .resizable().frame(width: 20, height: 20)
            TextField("分组名称", text: Binding(
                get: { draft.entries.first(where: { $0.id == entry.id })?.title ?? "" },
                set: { value in
                    if let index = draft.entries.firstIndex(where: { $0.id == entry.id }) {
                        draft.entries[index].title = String(value.prefix(40))
                    }
                }
            )).textFieldStyle(.plain).fontWeight(.semibold)
            Button { draft.removeGroup(entry.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help("移除分组，组内动作移到一级")
                .accessibilityLabel("移除分组 \(entry.title ?? "")")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(targetArea("header.\(entry.id)", group: entry.id))
    }

    private func saveEnabled(_ id: String, value: Bool) {
        guard SharedStorageManager.shared.applyConfigurationChanges(
            booleanValues: ["enable_action_\(id)": value],
            stringArrayValues: [SharedStorageManager.Keys.actionProfile: [ActionProfile.custom.rawValue]]
        ) else {
            showConfigurationSaveFailure(title(for: id))
            return
        }
        enabled[id] = value
        postConfigChanged()
    }

    private func rootInsertion(before: String?) -> some View {
        Color.clear.frame(height: 12)
            .background(targetArea("gap.\(before ?? "end")", group: nil, before: before))
    }

    private func targetArea(_ id: String, group: String?, before: String? = nil) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 6)
                .fill(dragging != nil && hoveredTarget == id ? Color.accentColor.opacity(0.18) : Color.clear)
                .overlay(alignment: .top) {
                    if dragging != nil && hoveredTarget == id && (before != nil || group == nil) {
                        Rectangle().fill(Color.accentColor).frame(height: 2)
                    }
                }
                .preference(key: MenuDropTargets.self, value: [id: MenuDropTarget(
                    frame: geometry.frame(in: .named("menuEditor")), group: group, before: before)])
        }
    }

    private func target(at point: CGPoint) -> (key: String, value: MenuDropTarget)? {
        // Nested rows win over their containing root gutter.
        dropTargets.filter { $0.value.frame.contains(point) }.min {
            $0.value.frame.width * $0.value.frame.height < $1.value.frame.width * $1.value.frame.height
        }
    }

    private func dragGesture(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("menuEditor"))
            .updating($dragging) { value, state, _ in
                guard let frame = dropTargets["action.\(id)"]?.frame ?? dropTargets["header.\(id)"]?.frame else { return }
                state = MenuDragPreview(id: id, frame: frame.offsetBy(dx: value.translation.width, dy: value.translation.height))
            }
            .onChanged { value in hoveredTarget = target(at: value.location)?.key }
            .onEnded { value in
                defer { hoveredTarget = nil }
                guard let target = target(at: value.location)?.value else { return }
                if draft.entries.contains(where: { $0.id == id && $0.isGroup }), let group = target.group {
                    draft.move(id, before: group)
                } else {
                    draft.move(id, toGroup: target.group, before: target.before)
                }
            }
    }

    private func dragPreview(_ preview: MenuDragPreview) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary).frame(width: 22)
            if let action = actions.first(where: { $0.actionId == preview.id }) {
                Image(nsImage: ActionIcon.image(for: action)).resizable().frame(width: 20, height: 20)
            } else {
                Image(nsImage: ActionIcon.groupImage(title: title(for: preview.id)))
                    .resizable().frame(width: 20, height: 20)
            }
            Text(title(for: preview.id)).lineLimit(1)
            Spacer(minLength: 4)
        }
        .frame(width: preview.frame.width, height: preview.frame.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .offset(x: preview.frame.minX, y: preview.frame.minY)
    }

    private func title(for id: String) -> String {
        actions.first(where: { $0.actionId == id })?.localizedTitle
            ?? draft.entries.first(where: { $0.id == id })?.title ?? id
    }
}

private struct MenuDragPreview {
    var id: String
    var frame: CGRect
}

private struct MenuDropTarget: Equatable {
    var frame: CGRect
    var group: String?
    var before: String?
}

private struct MenuDropTargets: PreferenceKey {
    static var defaultValue: [String: MenuDropTarget] { [:] }
    static func reduce(value: inout [String: MenuDropTarget], nextValue: () -> [String: MenuDropTarget]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
