import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsAlignedControlMetrics {
  static let labelWidth: CGFloat = 166
  static let controlWidth: CGFloat = 190
}

struct SettingsAlignedSelectionMenu<Value: Hashable>: View {
  let title: String
  let selection: Value
  let options: [(title: String, value: Value)]
  let onSelect: (Value) -> Void

  var body: some View {
    Menu {
      ForEach(options.indices, id: \.self) { index in
        let option = options[index]
        Button {
          onSelect(option.value)
        } label: {
          optionLabel(
            option.title,
            isSelected: option.value == selection
          )
        }
      }
    } label: {
      HStack(spacing: 8) {
        Text(title)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 8)
        Image(systemName: "chevron.up.chevron.down")
          .foregroundStyle(.secondary)
      }
      .frame(width: SettingsAlignedControlMetrics.labelWidth)
    }
    .menuIndicator(.hidden)
    .menuStyle(.button)
    .buttonStyle(.bordered)
  }

  @ViewBuilder
  private func optionLabel(
    _ title: String,
    isSelected: Bool
  ) -> some View {
    if isSelected {
      Label(title, systemImage: "checkmark")
    } else {
      Text(title)
    }
  }
}

private enum GestureTarget: Hashable {
  case global
  case group(UUID)
  case application(String)
}

private enum GestureWorkspaceDestination: Hashable {
  case gestures(GestureTarget)
  case general
  case permissions
  case advanced
  case about
}

private struct SettingsTopSafeAreaInsetKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
  fileprivate var settingsTopSafeAreaInset: CGFloat {
    get { self[SettingsTopSafeAreaInsetKey.self] }
    set { self[SettingsTopSafeAreaInsetKey.self] = newValue }
  }
}

private struct SettingsContentPadding: ViewModifier {
  @Environment(\.settingsTopSafeAreaInset) private var topSafeAreaInset

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
      .padding(.top, max(16, topSafeAreaInset + 12))
  }
}

private struct SubtleScrollIndicatorConfigurator: NSViewRepresentable {
  @Environment(\.colorScheme) private var colorScheme

  func makeNSView(context: Context) -> ScrollIndicatorConfigurationView {
    let view = ScrollIndicatorConfigurationView()
    update(view)
    return view
  }

  func updateNSView(
    _ nsView: ScrollIndicatorConfigurationView,
    context: Context
  ) {
    update(nsView)
  }

  private func update(_ view: ScrollIndicatorConfigurationView) {
    view.indicatorOpacity = colorScheme == .dark ? 0.28 : 0.32
  }
}

private final class ScrollIndicatorConfigurationView: NSView {
  var indicatorOpacity: CGFloat = 1 {
    didSet {
      applyIndicatorOpacity()
    }
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    applyIndicatorOpacity()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyIndicatorOpacity()
  }

  private func applyIndicatorOpacity(retryAfterLayout: Bool = true) {
    guard let scrollView = enclosingScrollView else {
      if retryAfterLayout {
        DispatchQueue.main.async { [weak self] in
          self?.applyIndicatorOpacity(retryAfterLayout: false)
        }
      }
      return
    }

    scrollView.verticalScroller?.alphaValue = indicatorOpacity
    scrollView.horizontalScroller?.alphaValue = indicatorOpacity
  }
}

private struct SidebarMaterialBackground: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .sidebar
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct GesturesSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var selectedDestination: GestureWorkspaceDestination? =
    .gestures(.global)
  @State private var selectedGestureTarget: GestureTarget = .global
  @State private var selectedMappingIDs: Set<UUID> = []
  @State private var isPresentingRecorder = false
  @State private var isPresentingPresets = false
  @State private var isAddingGroup = false
  @State private var newGroupName = ""
  @State private var isGroupsSectionExpanded = true
  @State private var isApplicationsSectionExpanded = true
  @State private var groupPendingDeletion: GestureApplicationGroup?
  @State private var mappingIDsPendingDeletion: Set<UUID> = []
  @State private var searchText = ""

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        targetSidebar(topSafeAreaInset: geometry.safeAreaInsets.top)
          .frame(width: SettingsSidebarMetrics.width)
          .frame(maxHeight: .infinity)

        Divider()

        selectedWorkspace
          .environment(
            \.settingsTopSafeAreaInset,
            geometry.safeAreaInsets.top
          )
          .frame(
            minWidth: SettingsSidebarMetrics.minimumWorkspaceWidth,
            maxWidth: .infinity,
            maxHeight: .infinity
          )
          .clipped()
      }
      .ignoresSafeArea(.container, edges: .top)
    }
    .sheet(isPresented: $isPresentingRecorder) {
      GestureRecorderSheet(
        model: model,
        existingMappings: model.mappings,
        initialAppScope: newGestureScope,
        initialApplicationGroupID: selectedApplicationGroup?.id,
        applicationGroupName: selectedApplicationGroup?.name,
        applicationName: selectedApplicationName
      ) { draft in
        if let id = model.createMapping(draft) {
          selectedMappingIDs = [id]
        }
      }
    }
    .sheet(isPresented: $isPresentingPresets) {
      GesturePresetLibraryView(
        model: model,
        appScope: newGestureScope,
        applicationGroupID: selectedApplicationGroup?.id
      )
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
      selectFirstVisibleMapping()
      handleSettingsNavigationRequest()
    }
    .onChange(of: visibleMappingIDs) {
      selectFirstVisibleMapping()
    }
    .onChange(of: selectedDestination) {
      guard let selectedDestination,
        case .gestures(let target) = selectedDestination
      else {
        return
      }
      selectedGestureTarget = target
      selectFirstVisibleMapping()
    }
    .onChange(of: model.settingsNavigationRequest) {
      handleSettingsNavigationRequest()
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
        if selectedDestination == .gestures(.group(group.id)) {
          selectedDestination = .gestures(.global)
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
    .confirmationDialog(
      deleteMappingsDialogTitle,
      isPresented: Binding(
        get: { !mappingIDsPendingDeletion.isEmpty },
        set: {
          if !$0 {
            mappingIDsPendingDeletion = []
          }
        }
      )
    ) {
      Button(String(localized: "Delete"), role: .destructive) {
        let ids = mappingIDsPendingDeletion
        mappingIDsPendingDeletion = []
        selectedMappingIDs.subtract(ids)
        model.deleteMappings(ids: ids)
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    }
  }

  @ViewBuilder
  private var selectedWorkspace: some View {
    switch selectedDestination ?? .gestures(selectedGestureTarget) {
    case .gestures:
      gestureWorkspace
    case .general:
      GeneralSettingsView(model: model)
    case .permissions:
      PermissionsSettingsView(model: model)
    case .advanced:
      AdvancedSettingsView(model: model)
    case .about:
      AboutSettingsView(model: model)
    }
  }

  private func targetSidebar(topSafeAreaInset: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: "iGestures")
        .font(.title2.weight(.bold))
        .padding(.horizontal, 16)
        .padding(.top, topSafeAreaInset + 8)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)

      List(selection: $selectedDestination) {
        Section {
          sidebarPrimaryDestinationRow(
            title: String(localized: "Global"),
            systemImage: "globe",
            count: mappingCount(for: .global),
            addLabel: String(localized: "Add Gesture")
          ) {
            presentRecorder(for: .global)
          }
          .tag(GestureWorkspaceDestination.gestures(.global))

          sidebarExpandableCategoryRow(
            title: String(localized: "Groups"),
            systemImage: "folder.fill",
            count: model.gestureApplicationGroups.count,
            isExpanded: $isGroupsSectionExpanded,
            addLabel: String(localized: "Add Group")
          ) {
            newGroupName = ""
            isAddingGroup = true
          }

          if isGroupsSectionExpanded {
            ForEach(model.gestureApplicationGroups) { group in
              sidebarDestinationRow(
                title: group.name,
                systemImage: "folder",
                count: mappingCount(for: .group(group.id)),
                addLabel: String(localized: "Add Gesture")
              ) {
                presentRecorder(for: .group(group.id))
              }
              .tag(
                GestureWorkspaceDestination.gestures(.group(group.id))
              )
              .padding(.leading, 14)
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
                .padding(.leading, 28)
              }
            }
          }

          sidebarExpandableCategoryRow(
            title: String(localized: "Applications"),
            systemImage: "square.grid.2x2",
            count: ungroupedApplicationBundleIdentifiers.count,
            isExpanded: $isApplicationsSectionExpanded,
            addLabel: String(localized: "Add Application")
          ) {
            chooseApplication()
          }

          if isApplicationsSectionExpanded {
            ForEach(ungroupedApplicationBundleIdentifiers, id: \.self) {
              bundleIdentifier in
              applicationSidebarRow(
                bundleIdentifier: bundleIdentifier,
                groupID: nil
              )
              .padding(.leading, 8)
            }
          }
        } header: {
          sidebarDomainHeader(title: String(localized: "Gestures"))
        }

        Section {
          settingsSidebarRow(
            title: String(localized: "General"),
            systemImage: "slider.horizontal.3"
          )
          .tag(GestureWorkspaceDestination.general)
          settingsSidebarRow(
            title: String(localized: "Permissions"),
            systemImage: "hand.raised"
          )
          .tag(GestureWorkspaceDestination.permissions)
          settingsSidebarRow(
            title: String(localized: "Advanced"),
            systemImage: "wrench.and.screwdriver"
          )
          .tag(GestureWorkspaceDestination.advanced)
          settingsSidebarRow(
            title: String(localized: "About"),
            systemImage: "info.circle"
          )
          .tag(GestureWorkspaceDestination.about)
        } header: {
          sidebarDomainHeader(title: String(localized: "Settings"))
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)

      if sidebarMissingPermissionCount > 0 {
        sidebarPermissionNotice
          .padding(.horizontal, 10)
          .padding(.bottom, 10)
      }
    }
    .background(SidebarMaterialBackground())
  }

  private var gestureWorkspace: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        workspaceHeader
        Divider()

        if model.isLoadingMappings {
          ProgressView(String(localized: "Loading Gestures…"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          gestureList
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
      .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)

      Divider()
      gestureInspector
        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var workspaceHeader: some View {
    HStack(spacing: 12) {
      workspaceTitle
        .layoutPriority(1)
      Spacer()
      workspaceActions
    }
    .modifier(SettingsContentPadding())
  }

  private var workspaceTitle: some View {
    Label(targetTitle, systemImage: targetSystemImage)
      .font(.title2)
      .fontWeight(.semibold)
      .lineLimit(1)
  }

  private var workspaceActions: some View {
    HStack(spacing: 2) {
      Button {
        presentRecorder(for: selectedGestureTarget)
      } label: {
        Label(
          String(localized: "New Gesture"),
          systemImage: "plus"
        )
        .frame(height: 18)
      }
      .buttonStyle(.borderedProminent)

      Menu {
        Button {
          isPresentingPresets = true
        } label: {
          Label(
            String(localized: "Gesture Templates"),
            systemImage: "square.grid.2x2"
          )
        }
        Divider()
        Button(String(localized: "Enable Selected Gestures")) {
          model.setMappingsEnabled(
            ids: selectedMappingIDs,
            isEnabled: true
          )
        }
        .disabled(!selectedMappings.contains { !$0.isEnabled })
        Button(String(localized: "Disable Selected Gestures")) {
          model.setMappingsEnabled(
            ids: selectedMappingIDs,
            isEnabled: false
          )
        }
        .disabled(!selectedMappings.contains { $0.isEnabled })
        Divider()
        Button(
          String(localized: "Delete Selected Gestures"),
          role: .destructive
        ) {
          mappingIDsPendingDeletion = selectedMappingIDs
        }
        .disabled(selectedMappingIDs.isEmpty)
      } label: {
        Image(systemName: "chevron.down")
          .frame(width: 18, height: 18)
      }
      .menuIndicator(.hidden)
      .menuStyle(.button)
      .buttonStyle(.borderedProminent)
      .help(String(localized: "More Gesture Actions"))
      .accessibilityLabel(String(localized: "More Gesture Actions"))
    }
    .disabled(model.isLoadingMappings)
    .controlSize(.large)
  }

  private var gestureList: some View {
    let displayedMappings = filteredMappings
    return VStack(spacing: 0) {
      HStack {
        TextField(
          String(localized: "Search gestures"),
          text: $searchText
        )
        .textFieldStyle(.roundedBorder)

        Text("\(displayedMappings.count)")
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      if displayedMappings.isEmpty {
        emptyGestureList
      } else {
        List(selection: $selectedMappingIDs) {
          ForEach(displayedMappings, id: \.mapping.id) { item in
            GestureLibraryRow(model: model, mapping: item.mapping)
              .tag(item.mapping.id)
              .contextMenu {
                gestureContextMenu(mappingID: item.mapping.id)
              }
          }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyGestureList: some View {
    ContentUnavailableView {
      Label(
        emptyGestureListTitle,
        systemImage: "scribble.variable"
      )
    } description: {
      Text(emptyGestureListDescription)
    } actions: {
      Button(String(localized: "Record Gesture")) {
        isPresentingRecorder = true
      }
    }
    .frame(maxWidth: .infinity, minHeight: 150)
  }

  private var emptyGestureListTitle: String {
    guard selectedApplicationGroupMembership != nil else {
      return String(localized: "No Gestures for This Target")
    }
    return String(localized: "No Additional Gestures for This Application")
  }

  private var emptyGestureListDescription: String {
    guard let group = selectedApplicationGroupMembership else {
      return String(
        localized: "Add or record a gesture for the selected target."
      )
    }
    let inheritedCount = model.mappings.count {
      $0.applicationGroupID == group.id
    }
    return String(
      format: String(
        localized:
          "This application inherits %1$d shared gestures from “%2$@”. Add or record an extra gesture for this application."
      ),
      inheritedCount,
      group.name
    )
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
            },
          applicationName: directApplicationName(for: mapping)
        ) {
          selectedMappingIDs.remove(mapping.id)
        }
        .id(mapping.id)
        .background(SubtleScrollIndicatorConfigurator())
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
    selectedGestureTarget
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

  private var selectedApplicationName: String? {
    guard case .application(let bundleID) = selected else { return nil }
    return applicationName(bundleIdentifier: bundleID)
  }

  private var selectedApplicationGroupMembership: GestureApplicationGroup? {
    guard case .application(let bundleID) = selected else { return nil }
    return model.gestureApplicationGroups.first {
      $0.bundleIdentifiers.contains(bundleID)
    }
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
    guard selectedMappingIDs.count == 1,
      let selectedMappingID = selectedMappingIDs.first
    else {
      return nil
    }
    return model.mappings.first { $0.id == selectedMappingID }
  }

  private var selectedMappings: [GestureMapping] {
    model.mappings.filter { selectedMappingIDs.contains($0.id) }
  }

  private var selectedMappingIndex: Int {
    guard let selectedMappingID = selectedMappingIDs.first else { return 0 }
    return model.mappings.firstIndex { $0.id == selectedMappingID } ?? 0
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

  private func selectFirstVisibleMapping() {
    let visibleIDs = Set(visibleMappingIDs)
    selectedMappingIDs.formIntersection(visibleIDs)
    if selectedMappingIDs.isEmpty,
      let firstVisibleMappingID = visibleMappingIDs.first
    {
      selectedMappingIDs = [firstVisibleMappingID]
    }
  }

  private func handleSettingsNavigationRequest() {
    guard let request = model.settingsNavigationRequest else { return }
    switch request {
    case .permissions:
      selectedDestination = .permissions
    }
    model.consumeSettingsNavigationRequest()
  }

  private func presentRecorder(for target: GestureTarget) {
    selectedGestureTarget = target
    selectedDestination = .gestures(target)
    DispatchQueue.main.async {
      isPresentingRecorder = true
    }
  }

  private func sidebarDestinationRow(
    title: String,
    systemImage: String,
    count: Int,
    addLabel: String,
    addAction: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 10) {
      sidebarNavigationIcon(systemImage)
      Text(title)
        .lineLimit(1)
      Spacer()
      sidebarTrailingControls(
        count: count,
        addLabel: addLabel,
        addAction: addAction
      )
    }
    .frame(maxWidth: .infinity, minHeight: 30)
  }

  private func sidebarPrimaryDestinationRow(
    title: String,
    systemImage: String,
    count: Int,
    addLabel: String,
    addAction: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 10) {
      sidebarNavigationIcon(systemImage)
      Text(title)
        .font(.body.weight(.medium))
        .lineLimit(1)
      Spacer()
      sidebarTrailingControls(
        count: count,
        addLabel: addLabel,
        addAction: addAction
      )
    }
    .frame(maxWidth: .infinity, minHeight: 38)
  }

  private func sidebarExpandableCategoryRow(
    title: String,
    systemImage: String,
    count: Int,
    isExpanded: Binding<Bool>,
    addLabel: String,
    addAction: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 4) {
      Button {
        withAnimation(.easeInOut(duration: 0.12)) {
          isExpanded.wrappedValue.toggle()
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            .frame(width: 12, height: 18)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

          sidebarNavigationIcon(systemImage)
          Text(title)
            .font(.body.weight(.medium))
            .lineLimit(1)
          Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(title)

      sidebarTrailingControls(
        count: count,
        addLabel: addLabel,
        addAction: addAction
      )
    }
    .frame(maxWidth: .infinity, minHeight: 34)
  }

  private func sidebarTrailingControls(
    count: Int,
    addLabel: String,
    addAction: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 4) {
      Text(count > 0 ? "\(count)" : "")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(width: 24, alignment: .trailing)

      Button(action: addAction) {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 18, height: 18)
          .foregroundStyle(.primary)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .help(addLabel)
      .accessibilityLabel(addLabel)
    }
  }

  private func sidebarNavigationIcon(_ systemImage: String) -> some View {
    Image(systemName: systemImage)
      .symbolRenderingMode(.monochrome)
      .font(.system(size: 18, weight: .medium))
      .frame(width: 24, height: 24)
      .foregroundStyle(.primary)
      .accessibilityHidden(true)
  }

  private func settingsSidebarRow(
    title: String,
    systemImage: String
  ) -> some View {
    HStack(spacing: 10) {
      sidebarNavigationIcon(systemImage)
      Text(title)
        .font(.body.weight(.medium))
    }
    .frame(minHeight: 38)
  }

  private func sidebarDomainHeader(title: String) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .textCase(nil)
      .padding(.top, 4)
      .accessibilityAddTraits(.isHeader)
  }

  private var sidebarPermissionNotice: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        sidebarPermissionOverview,
        systemImage: "exclamationmark.shield.fill"
      )
      .font(.callout.weight(.semibold))

      Text(
        String(
          localized:
            "iGestures needs permission to observe mouse gestures and post the configured shortcut."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Button(String(localized: "Open System Settings")) {
        selectedDestination = .permissions
        model.requestAccess()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
  }

  private var sidebarPermissionOverview: String {
    String(
      format: String(localized: "Permissions needing attention: %d"),
      sidebarMissingPermissionCount
    )
  }

  private var sidebarMissingPermissionCount: Int {
    let diagnostics = model.permissionDiagnostics
    return [
      diagnostics.accessibilityTrusted,
      diagnostics.listenEventAccess,
      diagnostics.postEventAccess,
    ].filter { !$0 }.count
  }

  @ViewBuilder
  private func applicationIcon(
    bundleIdentifier: String
  ) -> some View {
    if let metadata = ApplicationMetadataCache.shared.metadata(
      for: bundleIdentifier
    ) {
      Image(nsImage: metadata.icon)
        .resizable()
        .frame(width: 20, height: 20)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    } else {
      sidebarNavigationIcon("app.dashed")
    }
  }

  private func applicationSidebarRow(
    bundleIdentifier: String,
    groupID: UUID?
  ) -> some View {
    HStack(spacing: 10) {
      applicationIcon(bundleIdentifier: bundleIdentifier)
      Text(applicationName(bundleIdentifier: bundleIdentifier))
        .lineLimit(1)
      Spacer()
      let count = mappingCount(for: .application(bundleIdentifier))
      sidebarTrailingControls(
        count: count,
        addLabel: String(localized: "Add Gesture")
      ) {
        presentRecorder(for: .application(bundleIdentifier))
      }
    }
    .frame(maxWidth: .infinity, minHeight: 30)
    .tag(
      GestureWorkspaceDestination.gestures(
        .application(bundleIdentifier)
      )
    )
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
            }
          }
        }
      }

      Divider()
      Button(role: .destructive) {
        model.removeManagedApplication(bundleIdentifier)
        if selectedDestination
          == .gestures(
            .application(bundleIdentifier)
          )
        {
          selectedDestination = .gestures(.global)
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
    ApplicationMetadataCache.shared.metadata(
      for: bundleIdentifier
    )?.displayName
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

  private func mappingCount(for target: GestureTarget) -> Int {
    model.mappings.lazy.filter { mapping in
      switch target {
      case .global:
        guard mapping.applicationGroupID == nil else { return false }
        switch mapping.appScope {
        case .all, .allExcept:
          return true
        case .only:
          return false
        }
      case .group(let groupID):
        return mapping.applicationGroupID == groupID
      case .application(let bundleID):
        guard mapping.applicationGroupID == nil,
          case .only(let bundleIDs) = mapping.appScope
        else {
          return false
        }
        return bundleIDs.contains(bundleID)
      }
    }.count
  }

  private var deleteMappingsDialogTitle: String {
    mappingIDsPendingDeletion.count == 1
      ? String(localized: "Delete this gesture?")
      : String(localized: "Delete Selected Gestures")
  }

  @ViewBuilder
  private func gestureContextMenu(mappingID: UUID) -> some View {
    let mappingIDs = contextMappingIDs(for: mappingID)
    if !model.gestureApplicationGroups.isEmpty {
      Menu(String(localized: "Move to Group")) {
        ForEach(model.gestureApplicationGroups) { group in
          Button(group.name) {
            selectedMappingIDs = mappingIDs
            model.moveMappings(
              ids: mappingIDs,
              toApplicationGroupID: group.id
            )
          }
        }
      }
    }

    let applicationBundleIdentifiers =
      sortedApplicationBundleIdentifiers(
        allManagedApplicationBundleIdentifiers
      )
    Menu(String(localized: "Move to Application")) {
      if !applicationBundleIdentifiers.isEmpty {
        ForEach(applicationBundleIdentifiers, id: \.self) { bundleID in
          Button(applicationName(bundleIdentifier: bundleID)) {
            selectedMappingIDs = mappingIDs
            model.moveMappings(
              ids: mappingIDs,
              toApplicationBundleIdentifier: bundleID
            )
          }
        }
        Divider()
      }
      Button(String(localized: "Choose Application…")) {
        moveMappingsToChosenApplication(mappingIDs)
      }
    }

    Divider()
    Button(role: .destructive) {
      selectedMappingIDs = mappingIDs
      mappingIDsPendingDeletion = mappingIDs
    } label: {
      Label(String(localized: "Delete Gesture"), systemImage: "trash")
    }
  }

  private func contextMappingIDs(for mappingID: UUID) -> Set<UUID> {
    selectedMappingIDs.contains(mappingID)
      ? selectedMappingIDs
      : [mappingID]
  }

  private func directApplicationName(
    for mapping: GestureMapping
  ) -> String? {
    guard mapping.applicationGroupID == nil,
      case .only(let bundleIDs) = mapping.appScope,
      bundleIDs.count == 1,
      let bundleID = bundleIDs.first
    else {
      return nil
    }
    return applicationName(bundleIdentifier: bundleID)
  }

  private func addGroup() {
    let group = trimmedGroupName
    guard !group.isEmpty else { return }
    if let id = model.addGestureApplicationGroup(group) {
      selectedDestination = .gestures(.group(id))
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
    selectedDestination = .gestures(.application(bundleID))
  }

  private func moveMappingsToChosenApplication(_ mappingIDs: Set<UUID>) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(
      fileURLWithPath: "/Applications",
      isDirectory: true
    )
    panel.prompt = String(localized: "Move")
    panel.message = String(
      localized: "Choose an application for the selected gestures."
    )

    guard panel.runModal() == .OK,
      let url = panel.url,
      let bundleID = Bundle(url: url)?.bundleIdentifier
    else {
      return
    }
    selectedMappingIDs = mappingIDs
    model.moveMappings(
      ids: mappingIDs,
      toApplicationBundleIdentifier: bundleID
    )
  }

}

private struct GestureLibraryRow: View {
  let model: AppModel
  let mapping: GestureMapping

  var body: some View {
    HStack(spacing: 12) {
      GestureTemplatePreview(
        template: mapping.templates.first ?? .emptyPreview
      )
      .frame(width: 76, height: 54)
      .accessibilityHidden(true)

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
          .accessibilityLabel(conflict.localizedDescription)
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
      .accessibilityLabel(
        String(
          format: String(localized: "Enable gesture %@"),
          mapping.name
        )
      )
    }
    .padding(.leading, 8)
    .padding(.trailing, 4)
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
  private struct ScopeEditorPresentation: Identifiable {
    let id = UUID()
  }

  private struct SecondaryActionEditorItem: Identifiable {
    let id = UUID()
    let action: GestureAction
  }

  @ObservedObject var model: AppModel
  let mapping: GestureMapping
  let index: Int
  let mappingCount: Int
  let applicationGroupName: String?
  let applicationName: String?
  let onDelete: () -> Void

  @State private var name: String
  @FocusState private var isNameFocused: Bool
  @State private var isEditingAction = false
  @State private var secondaryActionEditorItem: SecondaryActionEditorItem?
  @State private var scopeEditorPresentation: ScopeEditorPresentation?
  @State private var isRetraining = false
  @State private var isConfirmingDeletion = false

  init(
    model: AppModel,
    mapping: GestureMapping,
    index: Int,
    mappingCount: Int,
    applicationGroupName: String?,
    applicationName: String?,
    onDelete: @escaping () -> Void
  ) {
    self.model = model
    self.mapping = mapping
    self.index = index
    self.mappingCount = mappingCount
    self.applicationGroupName = applicationGroupName
    self.applicationName = applicationName
    self.onDelete = onDelete
    _name = State(initialValue: mapping.name)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Gesture Settings"))
        .font(.headline)

      VStack(alignment: .leading, spacing: 16) {
        gesturePreview
          .frame(maxWidth: .infinity, alignment: .center)
        mappingFieldsStack
      }

      actionEditor
      secondaryActionEditor
      inspectorToolbar
    }
    .modifier(SettingsContentPadding())
    .onChange(of: mapping.name) {
      name = mapping.name
    }
    .onChange(of: mapping.id) {
      synchronizeDraftsWithMapping()
    }
    .onDisappear {
      commitName()
    }
    .sheet(item: $scopeEditorPresentation) { _ in
      AppScopeEditor(scope: mapping.appScope) {
        model.setMappingAppScope(id: mapping.id, appScope: $0)
      }
    }
    .sheet(isPresented: $isRetraining) {
      GestureRecorderSheet(
        model: model,
        existingMappings: model.mappings,
        editingMapping: mapping,
        applicationGroupName: applicationGroupName,
        applicationName: applicationName
      ) { draft in
        model.updateMapping(id: mapping.id, with: draft)
      }
    }
    .sheet(isPresented: $isEditingAction) {
      GestureActionEditorSheet(
        action:
          mapping.action.performsAction
          ? mapping.action : .window(.leftHalf),
        model: model
      ) {
        model.setMappingAction(id: mapping.id, action: $0)
      }
    }
    .sheet(item: $secondaryActionEditorItem) { item in
      GestureActionEditorSheet(
        action: item.action,
        model: model
      ) {
        model.setMappingSecondaryAction(
          id: mapping.id,
          action: $0
        )
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

  private func synchronizeDraftsWithMapping() {
    name = mapping.name
    isNameFocused = false
    isEditingAction = false
    secondaryActionEditorItem = nil
    scopeEditorPresentation = nil
    isRetraining = false
    isConfirmingDeletion = false
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

  private var mappingFieldsStack: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
      GridRow {
        mappingFieldLabel(String(localized: "Gesture Name"))
        mappingNameField
      }
      GridRow {
        mappingFieldLabel(String(localized: "Application Scope"))
        mappingScopeControl
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      GridRow(alignment: .top) {
        mappingFieldLabel(String(localized: "Trigger"))
        mappingTriggerControls
      }
      GridRow {
        mappingFieldLabel(String(localized: "Input Device"))
        HStack(spacing: 12) {
          mappingDevicePicker
          mappingRepeatToggle
            .fixedSize()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var mappingNameField: some View {
    TextField(String(localized: "Gesture Name"), text: $name)
      .focused($isNameFocused)
      .onSubmit(commitName)
      .onChange(of: isNameFocused) {
        if !isNameFocused {
          commitName()
        }
      }
  }

  @ViewBuilder
  private var mappingScopeControl: some View {
    if let applicationGroupName {
      Label(applicationGroupName, systemImage: "folder")
        .lineLimit(1)
        .frame(
          width: SettingsAlignedControlMetrics.controlWidth,
          alignment: .leading
        )
    } else if let applicationName {
      Label(applicationName, systemImage: "app")
        .lineLimit(1)
        .frame(
          width: SettingsAlignedControlMetrics.controlWidth,
          alignment: .leading
        )
    } else {
      Button {
        scopeEditorPresentation = ScopeEditorPresentation()
      } label: {
        Text(scopeSummary(mapping.appScope))
          .lineLimit(1)
          .frame(
            width: SettingsAlignedControlMetrics.labelWidth,
            alignment: .leading
          )
      }
      .buttonStyle(.bordered)
    }
  }

  private var mappingTriggerControls: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        mappingTriggerMenu
        mappingTriggerRecorder
      }
      VStack(alignment: .leading, spacing: 8) {
        mappingTriggerMenu
        mappingTriggerRecorder
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var mappingTriggerMenu: some View {
    SettingsAlignedSelectionMenu(
      title: mappingTriggerSummary,
      selection: mapping.triggerButton,
      options: mappingTriggerOptions
    ) { button in
      model.setMappingTriggerButton(
        id: mapping.id,
        triggerButton: button
      )
    }
  }

  private var mappingTriggerOptions:
    [(
      title: String,
      value: GestureTriggerButton?
    )]
  {
    var options: [(title: String, value: GestureTriggerButton?)] = [
      (String(localized: "Use Global Default"), nil)
    ]
    options.append(
      contentsOf: GestureTriggerButton.commonPresets.filter {
        $0 != model.secondaryTriggerButton
      }.map { button in
        (triggerButtonName(button), button)
      }
    )
    if let customButton = mapping.triggerButton,
      !GestureTriggerButton.commonPresets.contains(customButton)
    {
      options.append((triggerButtonName(customButton), customButton))
    }
    return options
  }

  private var mappingTriggerSummary: String {
    mapping.triggerButton.map(triggerButtonName)
      ?? String(localized: "Use Global Default")
  }

  private var mappingTriggerRecorder: some View {
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
    .frame(width: 170, alignment: .leading)
  }

  private var mappingDevicePicker: some View {
    SettingsAlignedSelectionMenu(
      title: mappingDeviceSummary,
      selection: mapping.deviceScope,
      options: mappingDeviceOptions
    ) { scope in
      model.setMappingDeviceScope(
        id: mapping.id,
        deviceScope: scope
      )
    }
  }

  private var mappingDeviceOptions:
    [(
      title: String,
      value: InputDeviceScope
    )]
  {
    var options: [(title: String, value: InputDeviceScope)] = [
      (String(localized: "Any Device"), .any),
      (String(localized: "Mouse"), .mouse(identifier: nil)),
      (String(localized: "Trackpad"), .trackpad),
    ]
    if case .mouse(let identifier?) = mapping.deviceScope {
      options.append((identifier, .mouse(identifier: identifier)))
    }
    return options
  }

  private var mappingDeviceSummary: String {
    switch mapping.deviceScope {
    case .any:
      String(localized: "Any Device")
    case .mouse(let identifier):
      identifier ?? String(localized: "Mouse")
    case .trackpad:
      String(localized: "Trackpad")
    }
  }

  private var mappingRepeatToggle: some View {
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
          "Repeat the last successful action with another trigger press."
      )
    )
  }

  private func mappingFieldLabel(_ title: String) -> some View {
    Text(title)
      .foregroundStyle(.secondary)
  }

  private var actionEditor: some View {
    GroupBox(String(localized: "Action")) {
      HStack(spacing: 12) {
        Image(
          systemName:
            mapping.action.performsAction
            ? "bolt.circle" : "minus.circle"
        )
        .font(.title3)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
        Text(GestureActionSummary.text(for: mapping.action))
          .frame(maxWidth: .infinity, alignment: .leading)
        if mapping.action.performsAction {
          Button(
            String(localized: "Clear Action"),
            role: .destructive
          ) {
            model.setMappingAction(id: mapping.id, action: .none)
          }
          .fixedSize()
          .layoutPriority(1)
        }
        Button(
          mapping.action.performsAction
            ? String(localized: "Edit")
            : String(localized: "Set Action")
        ) {
          isEditingAction = true
        }
        .fixedSize()
        .layoutPriority(1)
      }
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var secondaryActionEditor: some View {
    if let secondaryButton = model.secondaryTriggerButton {
      GroupBox(
        String(
          format: String(localized: "Secondary Action · %@"),
          triggerButtonName(secondaryButton)
        )
      ) {
        VStack(alignment: .leading, spacing: 12) {
          Toggle(
            String(localized: "Use a higher-priority action"),
            isOn: Binding(
              get: { mapping.secondaryAction != nil },
              set: {
                model.setMappingSecondaryAction(
                  id: mapping.id,
                  action: $0 ? .window(.leftHalf) : nil
                )
              }
            )
          )
          Text(
            String(
              localized:
                "Hold the primary and secondary triggers together, then draw this gesture."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          HStack(spacing: 12) {
            Image(
              systemName:
                mapping.secondaryAction == nil
                ? "minus.circle" : "bolt.badge.plus"
            )
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            Text(
              GestureActionSummary.text(
                for: mapping.secondaryAction ?? .none
              )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            if let secondaryAction = mapping.secondaryAction {
              Button(
                String(localized: "Clear Action"),
                role: .destructive
              ) {
                model.setMappingSecondaryAction(
                  id: mapping.id,
                  action: nil
                )
              }
              .fixedSize()
              .layoutPriority(1)
              Button(String(localized: "Edit")) {
                secondaryActionEditorItem = SecondaryActionEditorItem(
                  action: secondaryAction
                )
              }
              .fixedSize()
              .layoutPriority(1)
            } else {
              Button(String(localized: "Set Action")) {
                secondaryActionEditorItem = SecondaryActionEditorItem(
                  action: .window(.leftHalf)
                )
              }
              .fixedSize()
              .layoutPriority(1)
            }
          }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var inspectorToolbar: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        orderingButtons
        Spacer()
        deleteButton
      }

      HStack(spacing: 8) {
        orderingButtons
        Spacer()
        compactDeleteButton
      }
    }
  }

  private var orderingButtons: some View {
    HStack(spacing: 8) {
      Button {
        model.moveMapping(from: index, to: index - 1)
      } label: {
        Image(systemName: "chevron.up")
      }
      .disabled(index == 0)
      .help(String(localized: "Move Up"))
      .accessibilityLabel(String(localized: "Move Up"))

      Button {
        model.moveMapping(from: index, to: index + 1)
      } label: {
        Image(systemName: "chevron.down")
      }
      .disabled(index == mappingCount - 1)
      .help(String(localized: "Move Down"))
      .accessibilityLabel(String(localized: "Move Down"))

      Button {
        model.duplicateMapping(id: mapping.id)
      } label: {
        Image(systemName: "plus.square.on.square")
      }
      .help(String(localized: "Duplicate Gesture"))
      .accessibilityLabel(String(localized: "Duplicate Gesture"))
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
    .fixedSize()
  }

  private var compactDeleteButton: some View {
    Button(role: .destructive) {
      isConfirmingDeletion = true
    } label: {
      Image(systemName: "trash")
    }
    .help(String(localized: "Delete Gesture"))
    .accessibilityLabel(String(localized: "Delete Gesture"))
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
    guard trimmedName != mapping.name else { return }
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
  button.localizedName
}

private struct GesturePresetLibraryView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: AppModel
  let appScope: AppScope
  let applicationGroupID: UUID?
  @State private var selectedIDs: Set<UUID> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Gesture Templates"))
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
          ) {
            HStack(spacing: 12) {
              GestureTemplatePreview(template: preset.template)
                .frame(width: 52, height: 42)
                .accessibilityHidden(true)

              VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                Text(GestureActionSummary.text(for: preset.action))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
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
          for preset in GesturePresetLibrary.builtIn
          where
            selectedIDs.contains(preset.id)
          {
            _ = model.createMapping(
              GestureMappingDraft(
                name: preset.name,
                templates: [preset.template],
                action: preset.action,
                appScope: appScope,
                applicationGroupID: applicationGroupID
              )
            )
          }
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selectedIDs.isEmpty)
      }
    }
    .padding(24)
    .frame(
      minWidth: 520,
      idealWidth: 580,
      maxWidth: 700,
      minHeight: 440,
      idealHeight: 560,
      maxHeight: 720
    )
  }
}

struct GestureTemplatePreview: View {
  let template: GestureTemplate

  var body: some View {
    Canvas(rendersAsynchronously: true) { context, size in
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
    let metadata = ApplicationMetadataCache.shared.metadata(for: bundleID)

    HStack(spacing: 10) {
      if let metadata {
        Image(nsImage: metadata.icon)
          .resizable()
          .frame(width: 28, height: 28)
          .accessibilityHidden(true)
      } else {
        Image(systemName: "app.dashed")
          .frame(width: 28, height: 28)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(metadata?.displayName ?? bundleID)
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
      .accessibilityLabel(
        String(
          format: String(localized: "Remove %@"),
          metadata?.displayName ?? bundleID
        )
      )
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

@MainActor
enum GestureActionSummary {
  static func text(for action: GestureAction) -> String {
    switch action {
    case .none:
      return String(localized: "No Action")
    case .keyboardShortcut(let shortcut):
      return KeyboardShortcutFormatter.string(for: shortcut)
    case .openURL:
      return String(localized: "Open URL")
    case .openPath(let path):
      let expanded = NSString(string: path).expandingTildeInPath
      let name = URL(fileURLWithPath: expanded).lastPathComponent
      return name.isEmpty
        ? String(localized: "Open File or Folder")
        : name
    case .launchApplication(let bundleIdentifier):
      return ApplicationMetadataCache.shared.metadata(
        for: bundleIdentifier
      )?.displayName
        ?? String(localized: "Open Application")
    case .system(let action):
      return systemActionName(action)
    case .window(let action):
      return windowActionName(action)
    case .customWindow:
      return String(localized: "Custom Window Size and Position")
    case .typeText:
      return String(localized: "Type Fixed Text")
    case .applicationMenu(let menuAction):
      return menuAction.normalizedPath.isEmpty
        ? String(localized: "Choose Application Menu Item")
        : menuAction.normalizedPath.joined(separator: " › ")
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
    case .spotlight:
      String(localized: "Spotlight Search")
    case .launchpad:
      String(localized: "Launchpad")
    case .previousSpace:
      String(localized: "Previous Desktop")
    case .nextSpace:
      String(localized: "Next Desktop")
    case .screenshotFullScreen:
      String(localized: "Capture Entire Screen")
    case .screenshotSelection:
      String(localized: "Capture Screen Selection")
    case .screenshotToolbar:
      String(localized: "Open Screenshot Toolbar")
    case .playPause:
      String(localized: "Play or Pause")
    case .previousTrack:
      String(localized: "Previous Track")
    case .nextTrack:
      String(localized: "Next Track")
    case .emojiPicker:
      String(localized: "Emoji and Symbols")
    case .forceQuit:
      String(localized: "Force Quit Applications")
    }
  }

  static func windowActionName(
    _ action: WindowGestureAction
  ) -> String {
    switch action {
    case .leftHalf:
      String(localized: "Window · Left Half")
    case .rightHalf:
      String(localized: "Window · Right Half")
    case .topHalf:
      String(localized: "Window · Top Half")
    case .bottomHalf:
      String(localized: "Window · Bottom Half")
    case .topLeftQuarter:
      String(localized: "Window · Top Left")
    case .topRightQuarter:
      String(localized: "Window · Top Right")
    case .bottomLeftQuarter:
      String(localized: "Window · Bottom Left")
    case .bottomRightQuarter:
      String(localized: "Window · Bottom Right")
    case .leftThird:
      String(localized: "Window · Left Third")
    case .centerThird:
      String(localized: "Window · Center Third")
    case .rightThird:
      String(localized: "Window · Right Third")
    case .leftTwoThirds:
      String(localized: "Window · Left Two Thirds")
    case .rightTwoThirds:
      String(localized: "Window · Right Two Thirds")
    case .center:
      String(localized: "Window · Center")
    case .maximize:
      String(localized: "Window · Maximize")
    case .maximizeHeight:
      String(localized: "Window · Maximize Height")
    case .maximizeWidth:
      String(localized: "Window · Maximize Width")
    case .close:
      String(localized: "Window · Close")
    case .minimize:
      String(localized: "Window · Minimize")
    case .toggleFullScreen:
      String(localized: "Window · Enter or Exit Full Screen")
    case .previousDisplay:
      String(localized: "Window · Previous Display")
    case .nextDisplay:
      String(localized: "Window · Next Display")
    case .restorePreviousFrame:
      String(localized: "Window · Restore Previous Position")
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
    _action = State(
      initialValue:
        action.performsAction ? action : .window(.leftHalf)
    )
    self.model = model
    self.onSave = onSave
  }

  var body: some View {
    VStack(spacing: 0) {
      Text(String(localized: "Action"))
        .font(.title2)
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)

      Divider()

      ScrollView {
        GestureActionEditor(action: $action, model: model)
          .padding(24)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Divider()

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
      .padding(.horizontal, 24)
      .padding(.vertical, 16)
    }
    .frame(
      minWidth: 520,
      idealWidth: 620,
      maxWidth: 760,
      minHeight: 420,
      idealHeight: 620,
      maxHeight: 760
    )
  }
}

struct GestureActionEditor: View {
  private struct PresetLibraryPresentation: Identifiable {
    let id = UUID()
  }

  private enum Kind: String, CaseIterable, Identifiable {
    case keyboardShortcut
    case openURL
    case openPath
    case launchApplication
    case system
    case window
    case customWindow
    case typeText
    case applicationMenu
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
      case .openPath:
        String(localized: "Open File or Folder")
      case .launchApplication:
        String(localized: "Open Application")
      case .system:
        String(localized: "System Action")
      case .window:
        String(localized: "Window Management")
      case .customWindow:
        String(localized: "Custom Window Layout")
      case .typeText:
        String(localized: "Type Fixed Text")
      case .applicationMenu:
        String(localized: "Application Menu Item")
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
  @ObservedObject var model: AppModel
  @State private var presetSearchText = ""
  @State private var presetLibraryPresentation: PresetLibraryPresentation?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ActionPresetSearchSection(
        searchText: $presetSearchText,
        action: $action,
        model: model,
        onBrowseLibrary: {
          presetLibraryPresentation = PresetLibraryPresentation()
        }
      )

      Divider()

      Picker(String(localized: "Action Type"), selection: kind) {
        ForEach(Kind.allCases) { kind in
          Text(kind.label).tag(kind)
        }
      }

      switch action {
      case .none:
        EmptyView()
      case .keyboardShortcut:
        ShortcutRecorderView(
          shortcut: keyboardShortcut,
          model: model
        )
        .frame(width: 180)
      case .openURL:
        VStack(alignment: .leading, spacing: 8) {
          WebsitePresetPicker(
            action: $action,
            model: model
          )
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
        }
      case .openPath(let path):
        HStack {
          Text(path.isEmpty ? String(localized: "No file selected") : path)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button(String(localized: "Choose File or Folder…")) {
            choosePath()
          }
        }
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
      case .window:
        Picker(
          String(localized: "Window Action"),
          selection: windowAction
        ) {
          ForEach(WindowGestureAction.allCases, id: \.self) {
            Text(GestureActionSummary.windowActionName($0)).tag($0)
          }
        }
      case .customWindow:
        CustomWindowActionEditor(frame: customWindowFrame)
      case .typeText:
        VStack(alignment: .leading, spacing: 6) {
          TextEditor(text: fixedText)
            .frame(height: 80)
            .border(.secondary.opacity(0.3))
          Label(
            String(
              localized:
                "Use this only for non-sensitive text. Passwords and secrets should not be stored in gestures."
            ),
            systemImage: "exclamationmark.shield"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      case .applicationMenu:
        ApplicationMenuActionEditor(menuAction: applicationMenuAction)
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
    .sheet(item: $presetLibraryPresentation) { _ in
      ActionPresetLibrarySheet(
        action: $action,
        model: model
      )
    }
  }

  private var kind: Binding<Kind> {
    Binding(
      get: {
        switch action {
        case .none:
          .window
        case .keyboardShortcut:
          .keyboardShortcut
        case .openURL:
          .openURL
        case .openPath:
          .openPath
        case .launchApplication:
          .launchApplication
        case .system:
          .system
        case .window:
          .window
        case .customWindow:
          .customWindow
        case .typeText:
          .typeText
        case .applicationMenu:
          .applicationMenu
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
        case .openPath:
          action = .openPath("")
        case .launchApplication:
          action = .launchApplication(bundleIdentifier: "")
        case .system:
          action = .system(.missionControl)
        case .window:
          action = .window(.leftHalf)
        case .customWindow:
          action = .customWindow(NormalizedWindowFrame())
        case .typeText:
          action = .typeText("")
        case .applicationMenu:
          action = .applicationMenu(
            ApplicationMenuAction(path: [])
          )
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

  private var windowAction: Binding<WindowGestureAction> {
    Binding(
      get: {
        guard case .window(let value) = action else {
          return .leftHalf
        }
        return value
      },
      set: { action = .window($0) }
    )
  }

  private var customWindowFrame: Binding<NormalizedWindowFrame> {
    Binding(
      get: {
        guard case .customWindow(let value) = action else {
          return NormalizedWindowFrame()
        }
        return value
      },
      set: { action = .customWindow($0) }
    )
  }

  private var fixedText: Binding<String> {
    stringValue(
      extract: {
        guard case .typeText(let value) = $0 else { return "" }
        return value
      },
      embed: GestureAction.typeText
    )
  }

  private var applicationMenuAction: Binding<ApplicationMenuAction> {
    Binding(
      get: {
        guard case .applicationMenu(let value) = action else {
          return ApplicationMenuAction(path: [])
        }
        return value
      },
      set: { action = .applicationMenu($0) }
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

  private func choosePath() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = false
    panel.prompt = String(localized: "Choose")
    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }
    action = .openPath(url.path)
  }
}

private struct WebsitePresetPicker: View {
  @Binding var action: GestureAction
  @ObservedObject var model: AppModel
  @State private var isPresented = false
  @State private var searchText = ""

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: 10) {
        if let selectedPreset {
          WebsitePresetIcon(presetID: selectedPreset.id)
          Text(selectedPreset.name)
            .lineLimit(1)
        } else {
          WebsitePresetIcon(presetID: "")
          Text(String(localized: "Choose Preset Website…"))
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        .quaternary.opacity(0.35),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(.quaternary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(String(localized: "Choose Preset Website…"))
    .accessibilityValue(selectedPreset?.name ?? currentURL)
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      VStack(alignment: .leading, spacing: 12) {
        Text(String(localized: "Preset Websites"))
          .font(.headline)

        TextField(
          String(localized: "Search Websites"),
          text: $searchText
        )
        .textFieldStyle(.roundedBorder)

        if matchingPresets.isEmpty {
          ContentUnavailableView(
            String(localized: "No Preset Websites"),
            systemImage: "globe",
            description: Text(
              String(localized: "Try another website search.")
            )
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(spacing: 4) {
              ForEach(matchingPresets) { preset in
                websiteRow(preset)
              }
            }
          }
        }
      }
      .padding(16)
      .frame(width: 340, height: 390)
    }
  }

  private var currentURL: String {
    guard case .openURL(let value) = action else { return "" }
    return value
  }

  private var selectedPreset: ActionPreset? {
    ActionPresetLibrary.websitePresets(
      in: model.allActionPresets
    ).first {
      guard case .openURL(let value) = $0.action else { return false }
      return value == currentURL
    }
  }

  private var matchingPresets: [ActionPreset] {
    ActionPresetLibrary.websitePresets(
      matching: searchText,
      in: model.allActionPresets
    )
  }

  private func websiteRow(_ preset: ActionPreset) -> some View {
    Button {
      action = preset.action
      model.recordActionPresetUse(id: preset.id)
      searchText = ""
      isPresented = false
    } label: {
      HStack(spacing: 10) {
        WebsitePresetIcon(presetID: preset.id)
        VStack(alignment: .leading, spacing: 2) {
          Text(preset.name)
            .foregroundStyle(.primary)
          Text(host(for: preset))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        if preset.id == selectedPreset?.id {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        preset.id == selectedPreset?.id
          ? Color.accentColor.opacity(0.14)
          : Color.clear,
        in: RoundedRectangle(cornerRadius: 7)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(preset.name)
  }

  private func host(for preset: ActionPreset) -> String {
    guard case .openURL(let value) = preset.action else { return "" }
    return URLComponents(string: value)?.host ?? value
  }
}

private struct WebsitePresetIcon: View {
  private struct Style {
    let monogram: String?
    let systemImage: String?
    let color: Color
  }

  let presetID: String

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 7)
        .fill(style.color)
      if let systemImage = style.systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
      } else if let monogram = style.monogram {
        Text(monogram)
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
      } else {
        Image(systemName: "globe")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
      }
    }
    .frame(width: 26, height: 26)
    .accessibilityHidden(true)
  }

  private var style: Style {
    switch presetID {
    case "website.google":
      Style(monogram: "G", systemImage: nil, color: .blue)
    case "website.bing":
      Style(monogram: "B", systemImage: nil, color: .teal)
    case "website.chatgpt":
      Style(monogram: nil, systemImage: "sparkles", color: .green)
    case "website.claude":
      Style(monogram: "C", systemImage: nil, color: .orange)
    case "website.gemini":
      Style(monogram: nil, systemImage: "sparkles", color: .indigo)
    case "website.perplexity":
      Style(monogram: "P", systemImage: nil, color: .cyan)
    case "website.github":
      Style(
        monogram: nil,
        systemImage: "chevron.left.forwardslash.chevron.right",
        color: Color(nsColor: .darkGray)
      )
    case "website.stack-overflow":
      Style(monogram: "S", systemImage: nil, color: .orange)
    case "website.mdn":
      Style(monogram: "M", systemImage: nil, color: .blue)
    case "website.youtube":
      Style(monogram: nil, systemImage: "play.fill", color: .red)
    case "website.bilibili":
      Style(monogram: "B", systemImage: nil, color: .pink)
    case "website.gmail":
      Style(monogram: nil, systemImage: "envelope.fill", color: .red)
    case "website.google-drive":
      Style(monogram: nil, systemImage: "triangle.fill", color: .green)
    case "website.notion":
      Style(monogram: "N", systemImage: nil, color: .black)
    case "website.figma":
      Style(monogram: "F", systemImage: nil, color: .purple)
    default:
      Style(monogram: nil, systemImage: nil, color: .secondary)
    }
  }
}

private struct ActionPresetSearchSection: View {
  @Binding var searchText: String
  @Binding var action: GestureAction
  @ObservedObject var model: AppModel
  let onBrowseLibrary: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField(
          String(localized: "Search Actions"),
          text: $searchText
        )
        .textFieldStyle(.roundedBorder)

        Button(action: onBrowseLibrary) {
          Label(
            String(localized: "Browse Action Library"),
            systemImage: "square.grid.2x2"
          )
        }
      }

      if !normalizedSearchText.isEmpty {
        if matchingPresets.isEmpty {
          Text(String(localized: "No matching quick actions."))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          VStack(spacing: 4) {
            ForEach(matchingPresets.prefix(6)) { preset in
              Button {
                apply(preset)
              } label: {
                ActionPresetCompactRow(preset: preset)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(6)
          .background(.quaternary.opacity(0.35))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }
    }
  }

  private var normalizedSearchText: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var matchingPresets: [ActionPreset] {
    ActionPresetLibrary.matching(
      normalizedSearchText,
      in: model.allActionPresets
    )
  }

  private func apply(_ preset: ActionPreset) {
    action = preset.action
    model.recordActionPresetUse(id: preset.id)
    searchText = ""
  }
}

private struct ActionPresetCompactRow: View {
  let preset: ActionPreset

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: preset.category.systemImage)
        .frame(width: 20)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(preset.name)
        if !preset.summary.isEmpty {
          Text(preset.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer()
      Text(preset.category.label)
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
    .padding(.vertical, 3)
  }
}

private struct ActionPresetLibrarySheet: View {
  private enum Mode: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recent
    case mine
    case scripts

    var id: Self { self }

    var label: String {
      switch self {
      case .all:
        String(localized: "All")
      case .favorites:
        String(localized: "Favorites")
      case .recent:
        String(localized: "Recent")
      case .mine:
        String(localized: "My Presets")
      case .scripts:
        String(localized: "Scripts")
      }
    }
  }

  @Environment(\.dismiss) private var dismiss
  let action: Binding<GestureAction>?
  @ObservedObject var model: AppModel
  @State private var searchText = ""
  @State private var selectedCategory: ActionPresetCategory?
  @State private var mode: Mode = .all
  @State private var isSavingPreset = false

  init(
    action: Binding<GestureAction>? = nil,
    model: AppModel
  ) {
    self.action = action
    self.model = model
    _mode = State(initialValue: action == nil ? .scripts : .all)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(String(localized: "Action Library"))
          .font(.title2)
        Spacer()
        Button(String(localized: "Done")) {
          dismiss()
        }
      }

      Picker(String(localized: "Library"), selection: $mode) {
        ForEach(Mode.allCases) {
          Text($0.label).tag($0)
        }
      }
      .pickerStyle(.segmented)

      if mode == .scripts {
        ScriptLibraryView(
          model: model,
          showsTitle: false,
          onSelect: scriptSelection
        )
      } else {
        TextField(
          String(localized: "Search actions, commands, and folders"),
          text: $searchText
        )
        .textFieldStyle(.roundedBorder)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            categoryButton(nil, label: String(localized: "All"))
            ForEach(ActionPresetCategory.allCases, id: \.self) {
              categoryButton($0, label: $0.label)
            }
          }
        }

        if filteredPresets.isEmpty {
          ContentUnavailableView(
            String(localized: "No Actions"),
            systemImage: "sparkles",
            description: Text(
              String(localized: "Try another search or category.")
            )
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(filteredPresets) { preset in
            ActionPresetLibraryRow(
              preset: preset,
              isFavorite:
                model.favoriteActionPresetIDs.contains(preset.id),
              onSelect: selectionHandler(for: preset),
              onToggleFavorite: {
                model.toggleFavoriteActionPreset(id: preset.id)
              },
              onDelete:
                preset.isUserDefined
                ? {
                  model.deleteCustomActionPreset(id: preset.id)
                }
                : nil
            )
          }
          .listStyle(.inset)
        }

        HStack {
          if action != nil {
            Button {
              isSavingPreset = true
            } label: {
              Label(
                String(localized: "Save Current Action as Preset"),
                systemImage: "plus"
              )
            }
            .disabled(!(action?.wrappedValue.isValid ?? false))
          }

          Spacer()

          Text(
            String(
              format: String(localized: "%d actions"),
              filteredPresets.count
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
    }
    .padding(20)
    .frame(
      minWidth: 640,
      idealWidth: 760,
      maxWidth: 920,
      minHeight: 500,
      idealHeight: 620,
      maxHeight: 780
    )
    .sheet(isPresented: $isSavingPreset) {
      if let action {
        SaveActionPresetSheet(
          action: action.wrappedValue,
          model: model
        )
      }
    }
  }

  private var filteredPresets: [ActionPreset] {
    let allPresets = model.allActionPresets
    let modePresets: [ActionPreset]
    switch mode {
    case .all:
      modePresets = allPresets
    case .favorites:
      modePresets = allPresets.filter {
        model.favoriteActionPresetIDs.contains($0.id)
      }
    case .recent:
      let byID = Dictionary(
        uniqueKeysWithValues: allPresets.map { ($0.id, $0) }
      )
      modePresets = model.recentActionPresetIDs.compactMap {
        byID[$0]
      }
    case .mine:
      modePresets = model.customActionPresets
    case .scripts:
      modePresets = []
    }
    return modePresets.filter {
      (selectedCategory == nil || $0.category == selectedCategory)
        && $0.matches(searchText)
    }
  }

  private func categoryButton(
    _ category: ActionPresetCategory?,
    label: String
  ) -> some View {
    Button {
      selectedCategory = category
    } label: {
      HStack(spacing: 5) {
        if let category {
          Image(systemName: category.systemImage)
        }
        Text(label)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        selectedCategory == category
          ? Color.accentColor.opacity(0.18)
          : Color.secondary.opacity(0.08)
      )
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var scriptSelection: ((ScriptLibraryItem) -> Void)? {
    guard let action else { return nil }
    return { item in
      action.wrappedValue = .script(item.script)
      if let preset = ActionPresetLibrary.builtIn.first(where: {
        $0.action == .script(item.script)
      }) {
        model.recordActionPresetUse(id: preset.id)
      }
      dismiss()
    }
  }

  private func selectionHandler(
    for preset: ActionPreset
  ) -> (() -> Void)? {
    guard let action else { return nil }
    return {
      action.wrappedValue = preset.action
      model.recordActionPresetUse(id: preset.id)
      dismiss()
    }
  }
}

private struct ActionPresetLibraryRow: View {
  let preset: ActionPreset
  let isFavorite: Bool
  let onSelect: (() -> Void)?
  let onToggleFavorite: () -> Void
  let onDelete: (() -> Void)?

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: preset.category.systemImage)
        .font(.title3)
        .frame(width: 28)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      if let onSelect {
        Button(action: onSelect) {
          presetDetails
        }
        .buttonStyle(.plain)
      } else {
        presetDetails
      }

      Button(action: onToggleFavorite) {
        Image(systemName: isFavorite ? "star.fill" : "star")
          .foregroundStyle(isFavorite ? .yellow : .secondary)
      }
      .buttonStyle(.borderless)
      .help(
        isFavorite
          ? String(localized: "Remove from Favorites")
          : String(localized: "Add to Favorites")
      )
      .accessibilityLabel(
        isFavorite
          ? String(localized: "Remove from Favorites")
          : String(localized: "Add to Favorites")
      )

      if let onDelete {
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help(String(localized: "Delete Preset"))
        .accessibilityLabel(String(localized: "Delete Preset"))
      }
    }
    .padding(.vertical, 4)
  }

  private var presetDetails: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(preset.name)
        .foregroundStyle(.primary)
      HStack(spacing: 8) {
        Text(preset.category.label)
        if let hint = preset.scopeHint.label {
          Text("·")
          Text(hint)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      if !preset.summary.isEmpty {
        Text(preset.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

private struct SaveActionPresetSheet: View {
  @Environment(\.dismiss) private var dismiss
  let action: GestureAction
  @ObservedObject var model: AppModel
  @State private var name = ""
  @State private var category: ActionPresetCategory = .editing

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Save Action Preset"))
        .font(.title2)
      TextField(String(localized: "Preset Name"), text: $name)
      Picker(String(localized: "Category"), selection: $category) {
        ForEach(ActionPresetCategory.allCases, id: \.self) {
          Label($0.label, systemImage: $0.systemImage).tag($0)
        }
      }
      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Save")) {
          guard
            model.createCustomActionPreset(
              name: name,
              category: category,
              action: action
            ) != nil
          else {
            return
          }
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          name.trimmingCharacters(
            in: .whitespacesAndNewlines
          ).isEmpty || !action.isValid
        )
      }
    }
    .padding(20)
    .frame(width: 420)
  }
}

private struct CustomWindowActionEditor: View {
  @Binding var frame: NormalizedWindowFrame

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      GeometryReader { proxy in
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 8)
            .fill(.secondary.opacity(0.12))
          RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.opacity(0.65))
            .frame(
              width: proxy.size.width * previewWidth,
              height: proxy.size.height * previewHeight
            )
            .offset(
              x: proxy.size.width * previewX,
              y: proxy.size.height * previewY
            )
        }
      }
      .frame(height: 130)

      Grid(alignment: .leading, horizontalSpacing: 16) {
        GridRow {
          percentageStepper(
            String(localized: "Horizontal Position"),
            value: $frame.x
          )
          percentageStepper(
            String(localized: "Vertical Position"),
            value: $frame.y
          )
        }
        GridRow {
          percentageStepper(
            String(localized: "Width"),
            value: $frame.width
          )
          percentageStepper(
            String(localized: "Height"),
            value: $frame.height
          )
        }
      }

      if !frame.isValid {
        Label(
          String(
            localized:
              "The window rectangle must stay within the visible screen."
          ),
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    }
  }

  private var previewX: Double {
    max(0, min(1, frame.x))
  }

  private var previewY: Double {
    max(0, min(1, frame.y))
  }

  private var previewWidth: Double {
    max(0.02, min(1 - previewX, frame.width))
  }

  private var previewHeight: Double {
    max(0.02, min(1 - previewY, frame.height))
  }

  private func percentageStepper(
    _ title: String,
    value: Binding<Double>
  ) -> some View {
    Stepper(
      value: value,
      in: 0...1,
      step: 0.05
    ) {
      Text("\(title): \(Int(value.wrappedValue * 100))%")
        .font(.caption)
    }
  }
}

private struct ApplicationMenuActionEditor: View {
  @Binding var menuAction: ApplicationMenuAction

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField(
        String(localized: "File > Export > PDF"),
        text: menuPath
      )
      Text(
        String(
          localized:
            "Enter menu titles from the menu bar to the command, separated by >."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var menuPath: Binding<String> {
    Binding(
      get: {
        menuAction.path.joined(separator: " > ")
      },
      set: {
        menuAction.path = $0.split(whereSeparator: {
          $0 == ">" || $0 == "›"
        }).map {
          String($0).trimmingCharacters(
            in: .whitespacesAndNewlines
          )
        }.filter { !$0.isEmpty }
      }
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
          .accessibilityLabel(
            String(
              format: String(localized: "Remove step %d"),
              index + 1
            )
          )
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

extension ActionPresetCategory {
  fileprivate var label: String {
    switch self {
    case .window:
      String(localized: "Window")
    case .browser:
      String(localized: "Browser")
    case .website:
      String(localized: "Websites")
    case .finder:
      String(localized: "Finder")
    case .appDesktop:
      String(localized: "Apps and Desktop")
    case .editing:
      String(localized: "Editing and Input")
    case .mediaSystem:
      String(localized: "Media and System")
    case .automation:
      String(localized: "Automation")
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .window:
      "macwindow"
    case .browser:
      "globe"
    case .website:
      "link"
    case .finder:
      "folder"
    case .appDesktop:
      "square.grid.2x2"
    case .editing:
      "text.cursor"
    case .mediaSystem:
      "play.circle"
    case .automation:
      "gearshape.2"
    }
  }
}

extension ActionPresetScopeHint {
  fileprivate var label: String? {
    switch self {
    case .allApplications:
      nil
    case .browsers:
      String(localized: "Recommended for browser groups")
    case .finder:
      String(localized: "Recommended for Finder")
    }
  }
}
