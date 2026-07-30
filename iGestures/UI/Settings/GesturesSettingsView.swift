import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum GestureTarget: Hashable {
  case global
  case group(UUID)
  case application(String)
}

struct GesturesSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var selectedTarget: GestureTarget? = .global
  @State private var selectedMappingID: UUID?
  @State private var isPresentingRecorder = false
  @State private var isPresentingPresets = false
  @State private var isAddingGroup = false
  @State private var newGroupName = ""
  @State private var expandedGroupIDs: Set<UUID> = []
  @State private var groupPendingDeletion: GestureApplicationGroup?
  @State private var searchText = ""

  var body: some View {
    HSplitView {
      targetSidebar
        .frame(minWidth: 160, idealWidth: 225, maxWidth: 320)

      gestureWorkspace
        .frame(
          minWidth: 0,
          maxWidth: .infinity,
          maxHeight: .infinity
        )
    }
    .sheet(isPresented: $isPresentingRecorder) {
      GestureRecorderSheet(
        model: model,
        existingMappings: model.mappings,
        initialAppScope: newGestureScope,
        initialApplicationGroupID: selectedApplicationGroup?.id,
        applicationGroupName: selectedApplicationGroup?.name
      ) { draft in
        selectedMappingID = model.createMapping(draft)
      }
    }
    .sheet(isPresented: $isPresentingPresets) {
      GesturePresetLibraryView(model: model)
    }
    .alert(
      String(localized: "New Group"),
      isPresented: $isAddingGroup
    ) {
      TextField(
        String(localized: "Group Name"),
        text: $newGroupName
      )
      Button(String(localized: "Cancel"), role: .cancel) {
        newGroupName = ""
      }
      Button(String(localized: "Add")) {
        addGroup()
      }
      .disabled(trimmedGroupName.isEmpty)
    }
    .onAppear {
      expandedGroupIDs.formUnion(
        model.gestureApplicationGroups.map(\.id)
      )
      selectFirstVisibleMapping()
    }
    .onChange(of: visibleMappingIDs) {
      selectFirstVisibleMapping()
    }
    .onChange(of: model.gestureApplicationGroups.map(\.id)) {
      expandedGroupIDs.formUnion(
        model.gestureApplicationGroups.map(\.id)
      )
    }
    .confirmationDialog(
      String(localized: "Delete this application group?"),
      isPresented: Binding(
        get: { groupPendingDeletion != nil },
        set: {
          if !$0 {
            groupPendingDeletion = nil
          }
        }
      ),
      presenting: groupPendingDeletion
    ) { group in
      Button(String(localized: "Delete Group"), role: .destructive) {
        model.deleteGestureApplicationGroup(id: group.id)
        if selectedTarget == .group(group.id) {
          selectedTarget = .global
        }
        groupPendingDeletion = nil
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: { group in
      Text(
        String(
          format: String(
            localized:
              "Applications in “%@” will become ungrouped. Its gestures will be preserved as application-specific gestures."
          ),
          group.name
        )
      )
    }
  }

  private var targetSidebar: some View {
    VStack(spacing: 0) {
      List(selection: $selectedTarget) {
        Label(
          String(localized: "Global"),
          systemImage: "globe"
        )
        .tag(GestureTarget.global)

        Section {
          ForEach(model.gestureApplicationGroups) { group in
            DisclosureGroup(
              isExpanded: Binding(
                get: { expandedGroupIDs.contains(group.id) },
                set: {
                  if $0 {
                    expandedGroupIDs.insert(group.id)
                  } else {
                    expandedGroupIDs.remove(group.id)
                  }
                }
              )
            ) {
              ForEach(
                sortedApplicationBundleIdentifiers(
                  group.bundleIdentifiers
                ),
                id: \.self
              ) { bundleIdentifier in
                applicationSidebarRow(
                  bundleIdentifier: bundleIdentifier,
                  groupID: group.id
                )
                .padding(.leading, 14)
              }
            } label: {
              Label(group.name, systemImage: "folder")
            }
            .tag(GestureTarget.group(group.id))
            .contextMenu {
              Button {
                chooseApplication(destinationGroupID: group.id)
              } label: {
                Label(
                  String(localized: "Add Application"),
                  systemImage: "plus.app"
                )
              }
              Divider()
              Button(role: .destructive) {
                groupPendingDeletion = group
              } label: {
                Label(
                  String(localized: "Delete Group"),
                  systemImage: "trash"
                )
              }
              .disabled(
                group.bundleIdentifiers.isEmpty
                  && model.mappings.contains {
                    $0.applicationGroupID == group.id
                  }
              )
              .help(
                String(
                  localized:
                    "Add an application or remove the group’s gestures before deleting this group."
                )
              )
            }
          }
        } header: {
          sidebarHeader(
            String(localized: "Groups"),
            actionLabel: String(localized: "Add Group"),
            action: {
              newGroupName = ""
              isAddingGroup = true
            }
          )
        }

        Section {
          ForEach(ungroupedApplicationBundleIdentifiers, id: \.self) {
            bundleIdentifier in
            applicationSidebarRow(
              bundleIdentifier: bundleIdentifier,
              groupID: nil
            )
          }
        } header: {
          sidebarHeader(
            String(localized: "Applications"),
            actionLabel: String(localized: "Add Application"),
            action: { chooseApplication() }
          )
        }
      }
      .listStyle(.sidebar)

      Divider()

      Menu {
        Button {
          newGroupName = ""
          isAddingGroup = true
        } label: {
          Label(
            String(localized: "Add Group"),
            systemImage: "folder.badge.plus"
          )
        }
        Button {
          chooseApplication()
        } label: {
          Label(
            String(localized: "Add Application"),
            systemImage: "plus.app"
          )
        }
        if let group = selectedApplicationGroup {
          Button {
            chooseApplication(destinationGroupID: group.id)
          } label: {
            Label(
              String(
                format: String(
                  localized: "Add Application to “%@”"
                ),
                group.name
              ),
              systemImage: "folder.badge.plus"
            )
          }
        }
      } label: {
        Label(String(localized: "Add"), systemImage: "plus")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .menuStyle(.borderlessButton)
      .padding(12)
    }
  }

  private var gestureWorkspace: some View {
    VStack(spacing: 0) {
      triggerConfiguration
      Divider()
      workspaceHeader
      Divider()

      if model.isLoadingMappings {
        ProgressView(String(localized: "Loading Gestures…"))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        gestureList
        Divider()
        gestureInspector
      }

      if let error = model.mappingStoreError {
        Divider()
        Text(error)
          .font(.callout)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
      }
    }
  }

  private var triggerConfiguration: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 16) {
        triggerConfigurationTitle
          .frame(maxWidth: .infinity, alignment: .leading)
        triggerButtonControls
        Divider()
          .frame(height: 34)
        triggerDurationControl
      }

      VStack(alignment: .leading, spacing: 12) {
        triggerConfigurationTitle
        triggerButtonControls
        triggerDurationControl
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.secondary.opacity(0.045))
  }

  private var triggerConfigurationTitle: some View {
    VStack(alignment: .leading, spacing: 3) {
      Label(
        String(localized: "Gesture Trigger"),
        systemImage: "computermouse"
      )
      .font(.headline)
      Text(
        String(
          localized:
            "Hold the trigger button and draw a gesture."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var triggerButtonControls: some View {
    LabeledContent(String(localized: "Trigger Mouse Button")) {
      HStack(spacing: 8) {
        Picker(
          "",
          selection: Binding(
            get: { model.triggerButton },
            set: { model.setTriggerButton($0) }
          )
        ) {
          ForEach(GestureTriggerButton.commonPresets) { button in
            Text(triggerButtonName(button)).tag(button)
          }
          if !GestureTriggerButton.commonPresets.contains(
            model.triggerButton
          ) {
            Text(triggerButtonName(model.triggerButton))
              .tag(model.triggerButton)
          }
        }
        .labelsHidden()
        .frame(width: 165)

        TriggerButtonRecorderView(model: model) {
          model.setTriggerButton($0)
        }
      }
    }
  }

  private var triggerDurationControl: some View {
    LabeledContent(String(localized: "Trigger Hold Duration")) {
      Stepper(
        value: Binding(
          get: { model.triggerDuration },
          set: { model.setTriggerDuration($0) }
        ),
        in: triggerDurationRange,
        step: 0.05
      ) {
        Text(triggerDurationLabel(model.triggerDuration))
          .monospacedDigit()
      }
    }
  }

  private var workspaceHeader: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        workspaceTitle
        Spacer()
        workspaceActions
      }

      VStack(alignment: .leading, spacing: 12) {
        workspaceTitle
        workspaceActions
      }
    }
    .padding(16)
  }

  private var workspaceTitle: some View {
    Label(targetTitle, systemImage: targetSystemImage)
      .font(.title2)
      .fontWeight(.semibold)
      .lineLimit(1)
  }

  private var workspaceActions: some View {
    HStack(spacing: 12) {
      Button {
        isPresentingPresets = true
      } label: {
        Label(
          String(localized: "Presets"),
          systemImage: "square.grid.2x2"
        )
      }
      .disabled(model.isLoadingMappings)

      Button {
        isPresentingRecorder = true
      } label: {
        Label(
          String(localized: "Add Gesture"),
          systemImage: "plus"
        )
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.isLoadingMappings)
    }
  }

  private var gestureList: some View {
    VStack(spacing: 0) {
      HStack {
        TextField(
          String(localized: "Search gestures"),
          text: $searchText
        )
        .textFieldStyle(.roundedBorder)

        Text("\(filteredMappings.count)")
          .foregroundStyle(.secondary)

        Menu {
          Button(String(localized: "Enable Results")) {
            model.setMappingsEnabled(
              ids: Set(filteredMappings.map(\.mapping.id)),
              isEnabled: true
            )
          }
          Button(String(localized: "Disable Results")) {
            model.setMappingsEnabled(
              ids: Set(filteredMappings.map(\.mapping.id)),
              isEnabled: false
            )
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .disabled(filteredMappings.isEmpty)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      if filteredMappings.isEmpty {
        ContentUnavailableView {
          Label(
            String(localized: "No Gestures for This Target"),
            systemImage: "scribble.variable"
          )
        } description: {
          Text(
            String(
              localized:
                "Add or record a gesture for the selected target."
            )
          )
        } actions: {
          Button(String(localized: "Record Gesture")) {
            isPresentingRecorder = true
          }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
      } else {
        List(selection: $selectedMappingID) {
          ForEach(filteredMappings, id: \.mapping.id) { item in
            GestureLibraryRow(model: model, mapping: item.mapping)
              .tag(item.mapping.id)
          }
        }
        .listStyle(.inset)
        .frame(minHeight: 150, idealHeight: 220, maxHeight: 285)
      }
    }
  }

  @ViewBuilder
  private var gestureInspector: some View {
    if let mapping = selectedMapping {
      ScrollView {
        GestureMappingInspector(
          model: model,
          mapping: mapping,
          index: selectedMappingIndex,
          mappingCount: model.mappings.count,
          applicationGroupName:
            mapping.applicationGroupID.flatMap {
              applicationGroupName($0)
            }
        ) {
          selectedMappingID = nil
        }
        .id(mapping.id)
      }
    } else {
      ContentUnavailableView {
        Label(
          String(localized: "Gesture Settings"),
          systemImage: "slider.horizontal.3"
        )
      } description: {
        Text(String(localized: "Select a gesture to edit its settings."))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var selected: GestureTarget {
    selectedTarget ?? .global
  }

  private var targetTitle: String {
    switch selected {
    case .global:
      String(localized: "Global")
    case .group(let groupID):
      applicationGroupName(groupID)
        ?? String(localized: "Application Group")
    case .application(let bundleID):
      applicationName(bundleIdentifier: bundleID)
    }
  }

  private var targetSystemImage: String {
    switch selected {
    case .global:
      "globe"
    case .group:
      "folder"
    case .application:
      "app"
    }
  }

  private var selectedApplicationGroup: GestureApplicationGroup? {
    guard case .group(let groupID) = selected else { return nil }
    return model.gestureApplicationGroups.first { $0.id == groupID }
  }

  private var ungroupedApplicationBundleIdentifiers: [String] {
    let grouped = Set(
      model.gestureApplicationGroups.flatMap(\.bundleIdentifiers)
    )
    return sortedApplicationBundleIdentifiers(
      allManagedApplicationBundleIdentifiers.filter {
        !grouped.contains($0)
      }
    )
  }

  private var allManagedApplicationBundleIdentifiers: [String] {
    Array(
      Set(
        model.managedApplicationBundleIdentifiers
          + model.gestureApplicationGroups.flatMap(
            \.bundleIdentifiers
          )
          + model.mappings.flatMap { mapping -> [String] in
            guard case .only(let bundleIdentifiers) = mapping.appScope
            else {
              return []
            }
            return bundleIdentifiers
          }
      )
    )
  }

  private var targetMappings: [(index: Int, mapping: GestureMapping)] {
    model.mappings.enumerated().compactMap { index, mapping in
      let matchesTarget: Bool
      switch selected {
      case .global:
        guard mapping.applicationGroupID == nil else {
          matchesTarget = false
          break
        }
        switch mapping.appScope {
        case .all, .allExcept:
          matchesTarget = true
        case .only:
          matchesTarget = false
        }
      case .group(let groupID):
        matchesTarget = mapping.applicationGroupID == groupID
      case .application(let bundleID):
        if mapping.applicationGroupID == nil,
          case .only(let bundleIDs) = mapping.appScope
        {
          matchesTarget = bundleIDs.contains(bundleID)
        } else {
          matchesTarget = false
        }
      }
      return matchesTarget ? (index, mapping) : nil
    }
  }

  private var filteredMappings: [(index: Int, mapping: GestureMapping)] {
    targetMappings.filter { item in
      searchText.isEmpty
        || item.mapping.name.localizedCaseInsensitiveContains(
          searchText
        )
        || GestureActionSummary.text(for: item.mapping.action)
          .localizedCaseInsensitiveContains(searchText)
    }
  }

  private var visibleMappingIDs: [UUID] {
    filteredMappings.map(\.mapping.id)
  }

  private var selectedMapping: GestureMapping? {
    guard let selectedMappingID else { return nil }
    return model.mappings.first { $0.id == selectedMappingID }
  }

  private var selectedMappingIndex: Int {
    model.mappings.firstIndex { $0.id == selectedMappingID } ?? 0
  }

  private var newGestureScope: AppScope {
    switch selected {
    case .global:
      .all
    case .group:
      .only(selectedApplicationGroup?.bundleIdentifiers ?? [])
    case .application(let bundleID):
      .only([bundleID])
    }
  }

  private var trimmedGroupName: String {
    newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var triggerDurationRange: ClosedRange<TimeInterval> {
    GestureInputConfiguration
      .minimumTriggerDuration...GestureInputConfiguration.maximumTriggerDuration
  }

  private func selectFirstVisibleMapping() {
    guard
      let selectedMappingID,
      visibleMappingIDs.contains(selectedMappingID)
    else {
      selectedMappingID = visibleMappingIDs.first
      return
    }
  }

  @ViewBuilder
  private func sidebarHeader(
    _ title: String,
    actionLabel: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Text(title)
      Spacer()
      Button(action: action) {
        Image(systemName: "plus")
      }
      .buttonStyle(.borderless)
      .help(actionLabel)
    }
  }

  @ViewBuilder
  private func applicationIcon(
    bundleIdentifier: String
  ) -> some View {
    if let url = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: bundleIdentifier
    ) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable()
        .frame(width: 22, height: 22)
    } else {
      Image(systemName: "app.dashed")
        .frame(width: 22, height: 22)
    }
  }

  private func applicationSidebarRow(
    bundleIdentifier: String,
    groupID: UUID?
  ) -> some View {
    HStack(spacing: 9) {
      applicationIcon(bundleIdentifier: bundleIdentifier)
      Text(applicationName(bundleIdentifier: bundleIdentifier))
        .lineLimit(1)
    }
    .tag(GestureTarget.application(bundleIdentifier))
    .contextMenu {
      if groupID != nil {
        Button {
          model.moveManagedApplication(
            bundleIdentifier,
            toGroupID: nil
          )
        } label: {
          Label(
            String(localized: "Remove from Group"),
            systemImage: "folder.badge.minus"
          )
        }
      }

      if model.gestureApplicationGroups.contains(where: {
        $0.id != groupID
      }) {
        Menu(String(localized: "Move to Group")) {
          ForEach(
            model.gestureApplicationGroups.filter {
              $0.id != groupID
            }
          ) { group in
            Button(group.name) {
              model.moveManagedApplication(
                bundleIdentifier,
                toGroupID: group.id
              )
              expandedGroupIDs.insert(group.id)
            }
          }
        }
      }

      Divider()
      Button(role: .destructive) {
        model.removeManagedApplication(bundleIdentifier)
        if selectedTarget == .application(bundleIdentifier) {
          selectedTarget = .global
        }
      } label: {
        Label(
          String(localized: "Remove Application"),
          systemImage: "minus.circle"
        )
      }
    }
  }

  private func applicationName(bundleIdentifier: String) -> String {
    NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: bundleIdentifier
    )?.deletingPathExtension().lastPathComponent
      ?? bundleIdentifier
  }

  private func applicationGroupName(_ id: UUID) -> String? {
    model.gestureApplicationGroups.first { $0.id == id }?.name
  }

  private func sortedApplicationBundleIdentifiers(
    _ bundleIdentifiers: [String]
  ) -> [String] {
    bundleIdentifiers.sorted {
      applicationName(bundleIdentifier: $0)
        .localizedStandardCompare(
          applicationName(bundleIdentifier: $1)
        ) == .orderedAscending
    }
  }

  private func addGroup() {
    let group = trimmedGroupName
    guard !group.isEmpty else { return }
    if let id = model.addGestureApplicationGroup(group) {
      expandedGroupIDs.insert(id)
      selectedTarget = .group(id)
    }
    newGroupName = ""
  }

  private func chooseApplication(destinationGroupID: UUID? = nil) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(
      fileURLWithPath: "/Applications",
      isDirectory: true
    )
    panel.prompt = String(localized: "Add")
    if let destinationGroupID,
      let groupName = applicationGroupName(destinationGroupID)
    {
      panel.message = String(
        format: String(
          localized: "Choose an application to add to “%@”."
        ),
        groupName
      )
    } else {
      panel.message = String(
        localized:
          "Choose an application to add to the gesture sidebar."
      )
    }

    guard panel.runModal() == .OK,
      let url = panel.url,
      let bundleID = Bundle(url: url)?.bundleIdentifier
    else {
      return
    }
    model.addManagedApplication(
      bundleID,
      toGroupID: destinationGroupID
    )
    if let destinationGroupID {
      expandedGroupIDs.insert(destinationGroupID)
    }
    selectedTarget = .application(bundleID)
  }

  private func triggerDurationLabel(
    _ duration: TimeInterval
  ) -> String {
    guard duration > 0 else {
      return String(localized: "No Delay")
    }
    return String(
      format: String(localized: "%.2f seconds"),
      duration
    )
  }
}

private struct GestureLibraryRow: View {
  @ObservedObject var model: AppModel
  let mapping: GestureMapping

  var body: some View {
    HStack(spacing: 12) {
      GestureTemplatePreview(
        template: mapping.templates.first ?? .emptyPreview
      )
      .frame(width: 76, height: 54)

      VStack(alignment: .leading, spacing: 5) {
        Text(mapping.name)
          .fontWeight(.medium)
        HStack(spacing: 6) {
          Text(GestureActionSummary.text(for: mapping.action))
          Text("·")
          Text(scopeSummary(mapping.appScope))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }

      Spacer()

      if let conflict = shortcutConflict {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .help(conflict.localizedDescription)
      }

      Toggle(
        "",
        isOn: Binding(
          get: { mapping.isEnabled },
          set: {
            model.setMappingEnabled(
              id: mapping.id,
              isEnabled: $0
            )
          }
        )
      )
      .labelsHidden()
    }
    .padding(.vertical, 5)
  }

  private var shortcutConflict: SystemShortcutConflict? {
    guard case .keyboardShortcut(let shortcut) = mapping.action else {
      return nil
    }
    return SystemShortcutConflictDetector().conflict(for: shortcut)
  }
}

private struct GestureMappingInspector: View {
  @ObservedObject var model: AppModel
  let mapping: GestureMapping
  let index: Int
  let mappingCount: Int
  let applicationGroupName: String?
  let onDelete: () -> Void

  @State private var name: String
  @State private var actionDraft: GestureAction
  @State private var isEditingScope = false
  @State private var isRetraining = false
  @State private var isConfirmingDeletion = false

  init(
    model: AppModel,
    mapping: GestureMapping,
    index: Int,
    mappingCount: Int,
    applicationGroupName: String?,
    onDelete: @escaping () -> Void
  ) {
    self.model = model
    self.mapping = mapping
    self.index = index
    self.mappingCount = mappingCount
    self.applicationGroupName = applicationGroupName
    self.onDelete = onDelete
    _name = State(initialValue: mapping.name)
    _actionDraft = State(initialValue: mapping.action)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(String(localized: "Gesture Settings"))
          .font(.headline)
        Spacer()
        Toggle(
          String(localized: "Enable"),
          isOn: Binding(
            get: { mapping.isEnabled },
            set: {
              model.setMappingEnabled(
                id: mapping.id,
                isEnabled: $0
              )
            }
          )
        )
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 20) {
          gesturePreview
          mappingFields
        }
        .frame(minWidth: 620)

        VStack(alignment: .leading, spacing: 16) {
          gesturePreview
          mappingFields
        }
      }

      actionEditor
      inspectorToolbar
    }
    .padding(16)
    .onChange(of: mapping.name) {
      name = mapping.name
    }
    .onChange(of: mapping.action) {
      actionDraft = mapping.action
    }
    .sheet(isPresented: $isEditingScope) {
      AppScopeEditor(scope: mapping.appScope) {
        model.setMappingAppScope(id: mapping.id, appScope: $0)
      }
    }
    .sheet(isPresented: $isRetraining) {
      GestureRecorderSheet(
        model: model,
        existingMappings: model.mappings,
        editingMapping: mapping,
        applicationGroupName: applicationGroupName
      ) { draft in
        model.updateMapping(id: mapping.id, with: draft)
      }
    }
    .confirmationDialog(
      String(localized: "Delete this gesture?"),
      isPresented: $isConfirmingDeletion
    ) {
      Button(String(localized: "Delete"), role: .destructive) {
        model.deleteMapping(id: mapping.id)
        onDelete()
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    }
  }

  private var gesturePreview: some View {
    VStack(alignment: .leading, spacing: 8) {
      GestureTemplatePreview(
        template: mapping.templates.first ?? .emptyPreview
      )
      .frame(width: 190, height: 150)

      Button {
        isRetraining = true
      } label: {
        Label(
          String(localized: "Record Gesture Again"),
          systemImage: "scribble.variable"
        )
        .frame(maxWidth: .infinity)
      }
    }
    .frame(width: 190)
  }

  private var mappingFields: some View {
    Grid(
      alignment: .leading,
      horizontalSpacing: 12,
      verticalSpacing: 12
    ) {
      GridRow {
        Text(String(localized: "Gesture Name"))
          .foregroundStyle(.secondary)
        TextField(String(localized: "Gesture Name"), text: $name)
          .onSubmit(commitName)
      }

      GridRow {
        Text(String(localized: "Application Scope"))
          .foregroundStyle(.secondary)
        if let applicationGroupName {
          Label(applicationGroupName, systemImage: "folder")
        } else {
          Button(scopeSummary(mapping.appScope)) {
            isEditingScope = true
          }
        }
      }

      GridRow {
        Text(String(localized: "Trigger"))
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Picker(
            "",
            selection: Binding(
              get: { mapping.triggerButton },
              set: {
                model.setMappingTriggerButton(
                  id: mapping.id,
                  triggerButton: $0
                )
              }
            )
          ) {
            Text(String(localized: "Use Global Default"))
              .tag(GestureTriggerButton?.none)
            ForEach(GestureTriggerButton.commonPresets) { button in
              Text(triggerButtonName(button))
                .tag(GestureTriggerButton?.some(button))
            }
            if let customButton = mapping.triggerButton,
              !GestureTriggerButton.commonPresets.contains(customButton)
            {
              Text(triggerButtonName(customButton))
                .tag(GestureTriggerButton?.some(customButton))
            }
          }
          .labelsHidden()
          .frame(width: 180)

          TriggerButtonRecorderView(model: model) { button in
            model.setMappingTriggerButton(
              id: mapping.id,
              triggerButton: button
            )
            if mapping.deviceScope == .trackpad {
              model.setMappingDeviceScope(
                id: mapping.id,
                deviceScope: .mouse(identifier: nil)
              )
            }
          }
        }
      }

      GridRow {
        Text(String(localized: "Input Device"))
          .foregroundStyle(.secondary)
        Picker(
          "",
          selection: Binding(
            get: { mapping.deviceScope },
            set: {
              model.setMappingDeviceScope(
                id: mapping.id,
                deviceScope: $0
              )
            }
          )
        ) {
          Text(String(localized: "Any Device"))
            .tag(InputDeviceScope.any)
          Text(String(localized: "Mouse"))
            .tag(InputDeviceScope.mouse(identifier: nil))
          Text(String(localized: "Trackpad"))
            .tag(InputDeviceScope.trackpad)
          if case .mouse(let identifier?) = mapping.deviceScope {
            Text(identifier)
              .tag(InputDeviceScope.mouse(identifier: identifier))
          }
        }
        .labelsHidden()
      }

      GridRow {
        Text("")
        Toggle(
          String(localized: "Repeat"),
          isOn: Binding(
            get: { mapping.repeatModeEnabled },
            set: {
              model.setMappingRepeatModeEnabled(
                id: mapping.id,
                enabled: $0
              )
            }
          )
        )
        .help(
          String(
            localized:
              "Repeat the last successful action with another trigger click."
          )
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var actionEditor: some View {
    GroupBox(String(localized: "Action")) {
      VStack(alignment: .leading, spacing: 12) {
        GestureActionEditor(action: $actionDraft, model: model)

        HStack {
          Text(GestureActionSummary.text(for: actionDraft))
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button(String(localized: "Cancel")) {
            actionDraft = mapping.action
          }
          .disabled(actionDraft == mapping.action)
          Button(String(localized: "Save")) {
            model.setMappingAction(
              id: mapping.id,
              action: actionDraft
            )
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            !actionDraft.isValid || actionDraft == mapping.action
          )
        }
      }
      .padding(.top, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var inspectorToolbar: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        orderingButtons
        Spacer()
        deleteButton
      }

      VStack(alignment: .leading, spacing: 8) {
        orderingButtons
        deleteButton
      }
    }
  }

  private var orderingButtons: some View {
    HStack(spacing: 8) {
      Button {
        model.moveMapping(from: index, to: index - 1)
      } label: {
        Label(String(localized: "Move Up"), systemImage: "chevron.up")
      }
      .disabled(index == 0)

      Button {
        model.moveMapping(from: index, to: index + 1)
      } label: {
        Label(
          String(localized: "Move Down"),
          systemImage: "chevron.down"
        )
      }
      .disabled(index == mappingCount - 1)

      Button {
        model.duplicateMapping(id: mapping.id)
      } label: {
        Label(
          String(localized: "Duplicate Gesture"),
          systemImage: "plus.square.on.square"
        )
      }
    }
  }

  private var deleteButton: some View {
    Button(role: .destructive) {
      isConfirmingDeletion = true
    } label: {
      Label(
        String(localized: "Delete Gesture"),
        systemImage: "trash"
      )
    }
  }

  private func commitName() {
    let trimmedName = name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !trimmedName.isEmpty else {
      name = mapping.name
      return
    }
    name = trimmedName
    model.renameMapping(id: mapping.id, name: trimmedName)
  }
}

private func scopeSummary(_ scope: AppScope) -> String {
  switch scope {
  case .all:
    String(localized: "All Apps")
  case .only(let bundleIDs):
    String(
      format: String(localized: "Only %d Apps"),
      bundleIDs.count
    )
  case .allExcept(let bundleIDs):
    String(
      format: String(localized: "Except %d Apps"),
      bundleIDs.count
    )
  }
}

private func triggerButtonName(
  _ button: GestureTriggerButton
) -> String {
  if button == .trackpad {
    return String(localized: "Trackpad")
  }
  return switch button.buttonNumber {
  case 0:
    String(localized: "Left Mouse Button")
  case 1:
    String(localized: "Right Mouse Button")
  case 2:
    String(localized: "Middle Mouse Button")
  default:
    String(
      format: String(localized: "Mouse Button %d"),
      Int(button.buttonNumber) + 1
    )
  }
}

private struct GesturePresetLibraryView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: AppModel
  @State private var selectedIDs: Set<UUID> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Gesture Presets"))
        .font(.title2)
        .fontWeight(.semibold)

      Text(
        String(
          localized:
            "Choose presets to copy into your library. Existing gestures are never replaced."
        )
      )
      .foregroundStyle(.secondary)

      List(GesturePresetLibrary.builtIn) { preset in
        HStack(spacing: 12) {
          Toggle(
            "",
            isOn: Binding(
              get: { selectedIDs.contains(preset.id) },
              set: {
                if $0 {
                  selectedIDs.insert(preset.id)
                } else {
                  selectedIDs.remove(preset.id)
                }
              }
            )
          )
          .labelsHidden()

          GestureTemplatePreview(template: preset.template)
            .frame(width: 52, height: 42)

          VStack(alignment: .leading, spacing: 3) {
            Text(preset.name)
            Text(GestureActionSummary.text(for: preset.action))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      }
      .listStyle(.inset)

      HStack {
        Button(String(localized: "Select All")) {
          selectedIDs = Set(
            GesturePresetLibrary.builtIn.map(\.id)
          )
        }
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Add Selected")) {
          model.installPresets(
            GesturePresetLibrary.builtIn.filter {
              selectedIDs.contains($0.id)
            }
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selectedIDs.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 560, height: 520)
  }
}

struct GestureTemplatePreview: View {
  let template: GestureTemplate

  var body: some View {
    Canvas { context, size in
      let points = GesturePreviewLayout.scaledPoints(
        template.points,
        in: size
      )
      guard let first = points.first else { return }
      var path = Path()
      path.move(to: first)
      for point in points.dropFirst() {
        path.addLine(to: point)
      }
      context.stroke(
        path,
        with: .color(.accentColor),
        style: StrokeStyle(
          lineWidth: 3,
          lineCap: .round,
          lineJoin: .round
        )
      )

      let markerSize = min(size.width, size.height) < 80 ? 8.0 : 11.0
      let startMarker = Path(
        ellipseIn: CGRect(
          x: first.x - markerSize / 2,
          y: first.y - markerSize / 2,
          width: markerSize,
          height: markerSize
        )
      )
      context.fill(startMarker, with: .color(.white))
      context.stroke(
        startMarker,
        with: .color(.secondary),
        lineWidth: 1.5
      )

      if let last = points.last {
        let endMarker = Path(
          ellipseIn: CGRect(
            x: last.x - markerSize / 2,
            y: last.y - markerSize / 2,
            width: markerSize,
            height: markerSize
          )
        )
        context.fill(endMarker, with: .color(.accentColor))
        context.stroke(
          endMarker,
          with: .color(.white.opacity(0.85)),
          lineWidth: 1.5
        )
      }
    }
    .background(
      .secondary.opacity(0.08),
      in: RoundedRectangle(
        cornerRadius: 6
      ))
  }

}

enum GesturePreviewLayout {
  static func scaledPoints(
    _ gesturePoints: [GesturePoint],
    in size: CGSize
  ) -> [CGPoint] {
    let points = gesturePoints.filter(\.isFinite)
    guard !points.isEmpty else { return [] }

    let minX = points.map(\.x).min() ?? 0
    let maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxY = points.map(\.y).max() ?? 0
    let width = CGFloat(maxX - minX)
    let height = CGFloat(maxY - minY)
    let inset = max(7, min(size.width, size.height) * 0.12)
    let availableWidth = max(1, size.width - inset * 2)
    let availableHeight = max(1, size.height - inset * 2)

    let scale: CGFloat
    if width <= .ulpOfOne, height <= .ulpOfOne {
      scale = 1
    } else if width <= .ulpOfOne {
      scale = availableHeight / height
    } else if height <= .ulpOfOne {
      scale = availableWidth / width
    } else {
      scale = min(
        availableWidth / width,
        availableHeight / height
      )
    }

    let centerX = CGFloat(minX + maxX) / 2
    let centerY = CGFloat(minY + maxY) / 2
    return points.map {
      CGPoint(
        x: size.width / 2 + (CGFloat($0.x) - centerX) * scale,
        y: size.height / 2 + (CGFloat($0.y) - centerY) * scale
      )
    }
  }
}

extension GestureTemplate {
  fileprivate static let emptyPreview = GestureTemplate(
    points: [],
    aspectRatio: 1,
    startDirection: GesturePoint(x: 0, y: 0),
    endDirection: GesturePoint(x: 0, y: 0)
  )
}

struct AppScopeEditor: View {
  private enum Kind: String, CaseIterable, Identifiable {
    case all
    case only
    case allExcept

    var id: Self { self }

    var label: String {
      switch self {
      case .all:
        String(localized: "All Apps")
      case .only:
        String(localized: "Only These Apps")
      case .allExcept:
        String(localized: "All Except These Apps")
      }
    }
  }

  @Environment(\.dismiss) private var dismiss
  @State private var kind: Kind
  @State private var bundleIDs: [String]

  let onSave: (AppScope) -> Void

  init(
    scope: AppScope,
    onSave: @escaping (AppScope) -> Void
  ) {
    self.onSave = onSave
    switch scope {
    case .all:
      _kind = State(initialValue: .all)
      _bundleIDs = State(initialValue: [])
    case .only(let values):
      _kind = State(initialValue: .only)
      _bundleIDs = State(initialValue: values)
    case .allExcept(let values):
      _kind = State(initialValue: .allExcept)
      _bundleIDs = State(initialValue: values)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Application Scope"))
        .font(.title2)

      Picker(String(localized: "Scope"), selection: $kind) {
        ForEach(Kind.allCases) { kind in
          Text(kind.label).tag(kind)
        }
      }
      .pickerStyle(.radioGroup)

      if kind != .all {
        HStack {
          Text(String(localized: "Applications"))
            .font(.headline)
          Spacer()
          Button(String(localized: "Choose Applications…")) {
            chooseApplications()
          }
        }

        if bundleIDs.isEmpty {
          ContentUnavailableView {
            Label(
              String(localized: "No Applications Selected"),
              systemImage: "app.dashed"
            )
          } description: {
            Text(
              String(
                localized:
                  "Select one or more applications for this scope."
              )
            )
          }
          .frame(height: 160)
        } else {
          List(bundleIDs.sorted(), id: \.self) { bundleID in
            applicationRow(bundleID: bundleID)
          }
          .frame(height: 180)
          .listStyle(.inset)
        }
      }

      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Save")) {
          onSave(scope)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(kind != .all && bundleIDs.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 480)
  }

  private var scope: AppScope {
    let values = Array(Set(bundleIDs)).sorted()

    switch kind {
    case .all:
      return .all
    case .only:
      return .only(values)
    case .allExcept:
      return .allExcept(values)
    }
  }

  @ViewBuilder
  private func applicationRow(bundleID: String) -> some View {
    let applicationURL =
      NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleID
      )
    let name =
      applicationURL?.deletingPathExtension().lastPathComponent
      ?? bundleID

    HStack(spacing: 10) {
      if let applicationURL {
        Image(
          nsImage: NSWorkspace.shared.icon(
            forFile: applicationURL.path
          )
        )
        .resizable()
        .frame(width: 28, height: 28)
      } else {
        Image(systemName: "app.dashed")
          .frame(width: 28, height: 28)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
        Text(bundleID)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(role: .destructive) {
        bundleIDs.removeAll { $0 == bundleID }
      } label: {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .help(String(localized: "Remove Application"))
    }
  }

  private func chooseApplications() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(
      fileURLWithPath: "/Applications",
      isDirectory: true
    )
    panel.prompt = String(localized: "Choose")
    panel.message = String(
      localized: "Choose applications for this gesture scope."
    )

    guard panel.runModal() == .OK else { return }
    let selectedBundleIDs = panel.urls.compactMap {
      Bundle(url: $0)?.bundleIdentifier
    }
    bundleIDs = Array(
      Set(bundleIDs + selectedBundleIDs)
    ).sorted()
  }
}

enum GestureActionSummary {
  static func text(for action: GestureAction) -> String {
    switch action {
    case .keyboardShortcut(let shortcut):
      return KeyboardShortcutFormatter.string(for: shortcut)
    case .openURL:
      return String(localized: "Open URL")
    case .launchApplication(let bundleIdentifier):
      return NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )?.deletingPathExtension().lastPathComponent
        ?? String(localized: "Open Application")
    case .system(let action):
      return systemActionName(action)
    case .appleShortcut(let name):
      return name.isEmpty
        ? String(localized: "Run Shortcut")
        : name
    case .sequence(let sequence):
      return String(
        format: String(localized: "Sequence · %d Steps"),
        sequence.steps.count
      )
    case .script(let script):
      return script.kind == .appleScript
        ? String(localized: "AppleScript")
        : String(localized: "Shell Script")
    }
  }

  static func systemActionName(
    _ action: SystemGestureAction
  ) -> String {
    switch action {
    case .missionControl:
      String(localized: "Mission Control")
    case .showDesktop:
      String(localized: "Show Desktop")
    case .lockScreen:
      String(localized: "Lock Screen")
    case .sleep:
      String(localized: "Sleep")
    case .volumeUp:
      String(localized: "Volume Up")
    case .volumeDown:
      String(localized: "Volume Down")
    case .mute:
      String(localized: "Mute")
    case .brightnessUp:
      String(localized: "Brightness Up")
    case .brightnessDown:
      String(localized: "Brightness Down")
    case .appSwitcher:
      String(localized: "Application Switcher")
    }
  }
}

struct GestureActionEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var action: GestureAction

  let model: AppModel
  let onSave: (GestureAction) -> Void

  init(
    action: GestureAction,
    model: AppModel,
    onSave: @escaping (GestureAction) -> Void
  ) {
    _action = State(initialValue: action)
    self.model = model
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(String(localized: "Action"))
        .font(.title2)
      GestureActionEditor(action: $action, model: model)
      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Save")) {
          onSave(action)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!action.isValid)
      }
    }
    .padding(24)
    .frame(width: 520)
  }
}

struct GestureActionEditor: View {
  private enum Kind: String, CaseIterable, Identifiable {
    case keyboardShortcut
    case openURL
    case launchApplication
    case system
    case appleShortcut
    case sequence
    case script

    var id: Self { self }

    var label: String {
      switch self {
      case .keyboardShortcut:
        String(localized: "Keyboard Shortcut")
      case .openURL:
        String(localized: "Open URL")
      case .launchApplication:
        String(localized: "Open Application")
      case .system:
        String(localized: "System Action")
      case .appleShortcut:
        String(localized: "Run Apple Shortcut")
      case .sequence:
        String(localized: "Action Sequence")
      case .script:
        String(localized: "Script")
      }
    }
  }

  @Binding var action: GestureAction
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker(String(localized: "Action Type"), selection: kind) {
        ForEach(Kind.allCases) { kind in
          Text(kind.label).tag(kind)
        }
      }

      switch action {
      case .keyboardShortcut:
        ShortcutRecorderView(
          shortcut: keyboardShortcut,
          model: model
        )
        .frame(width: 180)
      case .openURL:
        TextField(
          String(localized: "https://example.com"),
          text: stringValue(
            extract: {
              guard case .openURL(let value) = $0 else { return "" }
              return value
            },
            embed: GestureAction.openURL
          )
        )
      case .launchApplication(let bundleIdentifier):
        HStack {
          Text(
            GestureActionSummary.text(
              for: .launchApplication(
                bundleIdentifier: bundleIdentifier
              )
            )
          )
          Spacer()
          Button(String(localized: "Choose Application…")) {
            chooseApplication()
          }
        }
      case .system:
        Picker(
          String(localized: "System Action"),
          selection: systemAction
        ) {
          ForEach(SystemGestureAction.allCases, id: \.self) {
            Text(GestureActionSummary.systemActionName($0)).tag($0)
          }
        }
      case .appleShortcut:
        TextField(
          String(localized: "Shortcut Name"),
          text: stringValue(
            extract: {
              guard case .appleShortcut(let name) = $0 else {
                return ""
              }
              return name
            },
            embed: { .appleShortcut(name: $0) }
          )
        )
      case .sequence:
        SequenceActionEditor(sequence: sequence, model: model)
      case .script:
        ScriptActionEditor(script: script, model: model)
      }
    }
  }

  private var kind: Binding<Kind> {
    Binding(
      get: {
        switch action {
        case .keyboardShortcut:
          .keyboardShortcut
        case .openURL:
          .openURL
        case .launchApplication:
          .launchApplication
        case .system:
          .system
        case .appleShortcut:
          .appleShortcut
        case .sequence:
          .sequence
        case .script:
          .script
        }
      },
      set: {
        switch $0 {
        case .keyboardShortcut:
          action = .keyboardShortcut(
            ShortcutRecordingSession.emptyShortcut
          )
        case .openURL:
          action = .openURL("https://")
        case .launchApplication:
          action = .launchApplication(bundleIdentifier: "")
        case .system:
          action = .system(.missionControl)
        case .appleShortcut:
          action = .appleShortcut(name: "")
        case .sequence:
          action = .sequence(
            GestureActionSequence(
              steps: [
                GestureActionStep(action: .system(.missionControl))
              ]
            )
          )
        case .script:
          action = .script(
            AutomationScript(
              kind: .appleScript,
              source: ""
            )
          )
        }
      }
    )
  }

  private var keyboardShortcut: Binding<KeyboardShortcut> {
    Binding(
      get: {
        action.keyboardShortcut
          ?? ShortcutRecordingSession.emptyShortcut
      },
      set: { action = .keyboardShortcut($0) }
    )
  }

  private var systemAction: Binding<SystemGestureAction> {
    Binding(
      get: {
        guard case .system(let value) = action else {
          return .missionControl
        }
        return value
      },
      set: { action = .system($0) }
    )
  }

  private var sequence: Binding<GestureActionSequence> {
    Binding(
      get: {
        guard case .sequence(let value) = action else {
          return GestureActionSequence(steps: [])
        }
        return value
      },
      set: { action = .sequence($0) }
    )
  }

  private var script: Binding<AutomationScript> {
    Binding(
      get: {
        guard case .script(let value) = action else {
          return AutomationScript(kind: .appleScript, source: "")
        }
        return value
      },
      set: { action = .script($0) }
    )
  }

  private func stringValue(
    extract: @escaping (GestureAction) -> String,
    embed: @escaping (String) -> GestureAction
  ) -> Binding<String> {
    Binding(
      get: { extract(action) },
      set: { action = embed($0) }
    )
  }

  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(
      fileURLWithPath: "/Applications",
      isDirectory: true
    )
    panel.prompt = String(localized: "Choose")
    guard panel.runModal() == .OK,
      let url = panel.url,
      let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
    else {
      return
    }
    action = .launchApplication(
      bundleIdentifier: bundleIdentifier
    )
  }
}

private struct SequenceActionEditor: View {
  @Binding var sequence: GestureActionSequence
  let model: AppModel
  @State private var editingStepIndex: Int?
  @State private var isEditingFallback = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(sequence.steps.indices, id: \.self) { index in
        HStack {
          Text("\(index + 1).")
          Button(
            GestureActionSummary.text(
              for: sequence.steps[index].action
            )
          ) {
            editingStepIndex = index
          }
          Stepper(
            value: $sequence.steps[index].delayAfter,
            in: 0...5,
            step: 0.25
          ) {
            Text(
              String(
                format: String(localized: "%.2f s delay"),
                sequence.steps[index].delayAfter
              )
            )
          }
          Button(role: .destructive) {
            sequence.steps.remove(at: index)
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
        }
      }

      HStack {
        Button(String(localized: "Add Step")) {
          guard sequence.steps.count < 20 else { return }
          sequence.steps.append(
            GestureActionStep(action: .system(.missionControl))
          )
        }

        Picker(
          String(localized: "On Failure"),
          selection: failureKind
        ) {
          Text(String(localized: "Stop")).tag(0)
          Text(String(localized: "Continue")).tag(1)
          Text(String(localized: "Run Fallback")).tag(2)
        }

        if case .fallback(let action) = sequence.failurePolicy {
          Button(GestureActionSummary.text(for: action)) {
            isEditingFallback = true
          }
        }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { editingStepIndex != nil },
        set: {
          if !$0 {
            editingStepIndex = nil
          }
        }
      )
    ) {
      if let index = editingStepIndex,
        sequence.steps.indices.contains(index)
      {
        GestureActionEditorSheet(
          action: sequence.steps[index].action,
          model: model
        ) {
          sequence.steps[index].action = $0
        }
      }
    }
    .sheet(isPresented: $isEditingFallback) {
      if case .fallback(let action) = sequence.failurePolicy {
        GestureActionEditorSheet(action: action, model: model) {
          sequence.failurePolicy = .fallback($0)
        }
      }
    }
  }

  private var failureKind: Binding<Int> {
    Binding(
      get: {
        switch sequence.failurePolicy {
        case .stop:
          0
        case .continue:
          1
        case .fallback:
          2
        }
      },
      set: {
        switch $0 {
        case 1:
          sequence.failurePolicy = .continue
        case 2:
          sequence.failurePolicy = .fallback(
            .system(.showDesktop)
          )
        default:
          sequence.failurePolicy = .stop
        }
      }
    )
  }
}

struct ScriptActionEditor: View {
  @Binding var script: AutomationScript
  @ObservedObject var model: AppModel
  var showsLibraryPicker = true

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if showsLibraryPicker {
        Menu {
          Section(String(localized: "Built-In Scripts")) {
            ForEach(BuiltInScriptLibrary.items) { item in
              Button(item.name) {
                script = item.script
              }
            }
          }
          if !model.userScriptLibrary.isEmpty {
            Section(String(localized: "My Scripts")) {
              ForEach(model.userScriptLibrary) { item in
                Button(item.name) {
                  script = item.script
                }
              }
            }
          }
        } label: {
          Label(
            String(localized: "Choose from Script Library"),
            systemImage: "books.vertical"
          )
        }
        Text(
          String(
            localized:
              "Choosing a library script copies it into this gesture. Later library edits will not change the gesture."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Picker(String(localized: "Script Type"), selection: scriptKind) {
        Text(String(localized: "AppleScript"))
          .tag(AutomationScriptKind.appleScript)
        Text(String(localized: "Shell"))
          .tag(AutomationScriptKind.shell)
      }

      TextEditor(text: scriptSource)
        .font(.system(.body, design: .monospaced))
        .frame(height: 120)
        .border(.secondary.opacity(0.3))

      Stepper(
        value: $script.timeout,
        in: 1...30,
        step: 1
      ) {
        Text(
          String(
            format: String(localized: "Timeout: %.0f seconds"),
            script.timeout
          )
        )
      }

      Toggle(
        String(
          localized:
            "I created or reviewed this script and understand it can control this Mac."
        ),
        isOn: $script.isConfirmed
      )
      .foregroundStyle(
        script.isConfirmed ? Color.primary : Color.orange
      )
    }
  }

  private var scriptKind: Binding<AutomationScriptKind> {
    Binding(
      get: { script.kind },
      set: {
        guard script.kind != $0 else { return }
        script.kind = $0
        script.isConfirmed = false
      }
    )
  }

  private var scriptSource: Binding<String> {
    Binding(
      get: { script.source },
      set: {
        guard script.source != $0 else { return }
        script.source = $0
        script.isConfirmed = false
      }
    )
  }
}
