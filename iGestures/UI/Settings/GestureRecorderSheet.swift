import SwiftUI

struct GestureRecorderSheet: View {
  @Environment(\.dismiss) private var dismiss

  @ObservedObject var model: AppModel
  @State private var name: String
  @State private var action: GestureAction
  @State private var secondaryAction: GestureAction?
  @State private var appScope: AppScope
  @State private var triggerButton: GestureTriggerButton?
  @State private var deviceScope: InputDeviceScope
  @State private var isEditingScope = false
  @State private var isEditingAction = false
  @State private var isAdvancedOptionsExpanded = false
  @State private var training: GestureTrainingSession
  @State private var points: [GesturePoint] = []
  @State private var feedback: String
  @State private var triggerConflictMessage: String?

  private let existingMappings: [GestureMapping]
  private let initialIsEnabled: Bool
  private let initialCategory: String?
  private let applicationGroupID: UUID?
  private let applicationGroupName: String?
  private let applicationName: String?
  private let initialRepeatModeEnabled: Bool
  private let isEditing: Bool
  private let originalGesture: [GesturePoint]
  let onSave: (GestureMappingDraft) -> Void

  init(
    model: AppModel,
    existingMappings: [GestureMapping],
    editingMapping: GestureMapping? = nil,
    initialAppScope: AppScope = .all,
    initialCategory: String? = nil,
    initialApplicationGroupID: UUID? = nil,
    applicationGroupName: String? = nil,
    applicationName: String? = nil,
    onSave: @escaping (GestureMappingDraft) -> Void
  ) {
    self.model = model
    self.existingMappings = existingMappings
    self.initialIsEnabled = editingMapping?.isEnabled ?? true
    self.initialCategory = editingMapping?.category ?? initialCategory
    self.applicationGroupID =
      editingMapping?.applicationGroupID ?? initialApplicationGroupID
    self.applicationGroupName = applicationGroupName
    self.applicationName = applicationName
    self.initialRepeatModeEnabled =
      editingMapping?.repeatModeEnabled ?? false
    self.isEditing = editingMapping != nil
    self.originalGesture =
      editingMapping?.templates.first?.points ?? []
    self.onSave = onSave
    _name = State(
      initialValue:
        editingMapping?.name ?? String(localized: "New Gesture")
    )
    _action = State(
      initialValue:
        editingMapping?.action
        ?? .keyboardShortcut(
          ShortcutRecordingSession.emptyShortcut
        )
    )
    _secondaryAction = State(
      initialValue: editingMapping?.secondaryAction
    )
    let initialScope = editingMapping?.appScope ?? initialAppScope
    _appScope = State(initialValue: initialScope)
    let initialTrigger = editingMapping?.triggerButton
    _triggerButton = State(initialValue: initialTrigger)
    let initialDeviceScope = editingMapping?.deviceScope ?? .any
    _deviceScope = State(initialValue: initialDeviceScope)
    _training = State(
      initialValue: GestureTrainingSession(
        existingMappings: existingMappings,
        editingMappingID: editingMapping?.id,
        appScope: initialScope,
        applicationGroupID:
          editingMapping?.applicationGroupID
          ?? initialApplicationGroupID,
        triggerButton: initialTrigger,
        defaultTriggerButton: model.triggerButton,
        deviceScope: initialDeviceScope
      )
    )
    _feedback = State(
      initialValue: String(
        localized: "Draw the same gesture three times."
      )
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text(
              isEditing
                ? String(localized: "Record Gesture Again")
                : String(localized: "Record Gesture")
            )
            .font(.title2)
            .fontWeight(.semibold)
            Spacer()
            phaseLabel
              .foregroundStyle(.secondary)
          }

          if !originalGesture.isEmpty {
            Label(
              String(localized: "Original Gesture"),
              systemImage: "scribble"
            )
            .font(.headline)
          }

          GestureDrawingPad(
            points: $points,
            guidePoints: originalGesture
          ) {
            handleStroke($0)
          }
          .frame(height: 300)

          Text(feedback)
            .foregroundStyle(feedbackColor)
            .frame(maxWidth: .infinity, alignment: .leading)

          TextField(String(localized: "Gesture Name"), text: $name)

          GroupBox(String(localized: "Action")) {
            HStack(spacing: 12) {
              Image(systemName: "bolt.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
              Text(GestureActionSummary.text(for: action))
                .frame(maxWidth: .infinity, alignment: .leading)
              Button(
                action.performsAction
                  ? String(localized: "Edit")
                  : String(localized: "Set Action")
              ) {
                isEditingAction = true
              }
            }
            .padding(.vertical, 6)
          }

          VStack(alignment: .leading, spacing: 0) {
            Button {
              withAnimation(.easeInOut(duration: 0.12)) {
                isAdvancedOptionsExpanded.toggle()
              }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                  .font(.system(size: 11, weight: .semibold))
                  .rotationEffect(
                    .degrees(isAdvancedOptionsExpanded ? 90 : 0)
                  )
                  .frame(width: 12, height: 18)
                  .accessibilityHidden(true)
                Text(String(localized: "Advanced Options"))
                  .fontWeight(.medium)
                Spacer()
              }
              .frame(maxWidth: .infinity, minHeight: 28)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAdvancedOptionsExpanded {
              advancedOptions
                .padding(.top, 12)
            }
          }

          if let triggerConflictMessage {
            Label(
              triggerConflictMessage,
              systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
          }

          if let conflict = shortcutConflict {
            Label(
              conflict.localizedDescription,
              systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
          }

        }
        .padding(24)
      }

      Divider()
      footer
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    .frame(
      minWidth: 560,
      idealWidth: 640,
      maxWidth: 760,
      minHeight: 480,
      idealHeight: 700,
      maxHeight: 820
    )
    .sheet(isPresented: $isEditingScope) {
      AppScopeEditor(scope: appScope) { scope in
        appScope = scope
        training.setAppScope(scope)
        points.removeAll(keepingCapacity: true)
        feedback = String(
          localized: "Draw the same gesture three times."
        )
      }
    }
    .sheet(isPresented: $isEditingAction) {
      GestureActionEditorSheet(
        action:
          action.performsAction ? action : .window(.leftHalf),
        model: model
      ) {
        action = $0
      }
    }
  }

  private var advancedOptions: some View {
    Grid(
      alignment: .leading,
      horizontalSpacing: 12,
      verticalSpacing: 12
    ) {
      GridRow {
        Text(String(localized: "Application Scope"))
          .foregroundStyle(.secondary)
        Group {
          if let applicationGroupName {
            Label(applicationGroupName, systemImage: "folder")
          } else if let applicationName {
            Label(applicationName, systemImage: "app")
          } else {
            Button(scopeSummary) {
              isEditingScope = true
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GridRow {
        Text(String(localized: "Gesture Trigger"))
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Picker(
            String(localized: "Gesture Trigger"),
            selection: Binding(
              get: { triggerButton },
              set: { selectTriggerButton($0) }
            )
          ) {
            Text(String(localized: "Use Global Default"))
              .tag(GestureTriggerButton?.none)
            ForEach(
              GestureTriggerButton.commonPresets.filter {
                $0 != model.secondaryTriggerButton
              }
            ) { button in
              Text(triggerButtonName(button))
                .tag(GestureTriggerButton?.some(button))
            }
            Text(String(localized: "Trackpad Modifier Gesture"))
              .tag(GestureTriggerButton?.some(.trackpad))
            if let customButton = triggerButton,
              customButton != .trackpad,
              !GestureTriggerButton.commonPresets.contains(customButton)
            {
              Text(triggerButtonName(customButton))
                .tag(GestureTriggerButton?.some(customButton))
            }
          }
          .labelsHidden()
          .frame(width: 190, alignment: .leading)

          TriggerButtonRecorderView(model: model) { button in
            if deviceScope == .trackpad {
              deviceScope = .mouse(identifier: nil)
              training.setDeviceScope(deviceScope)
            }
            selectTriggerButton(button)
          }
          .frame(width: 170, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GridRow {
        Text(String(localized: "Input Device"))
          .foregroundStyle(.secondary)
        Picker(
          String(localized: "Input Device"),
          selection: Binding(
            get: { deviceScope },
            set: {
              deviceScope = $0
              training.setDeviceScope($0)
              if $0 == .trackpad {
                triggerButton = .trackpad
                training.setTriggerButton(.trackpad)
              }
            }
          )
        ) {
          Text(String(localized: "Any Device"))
            .tag(InputDeviceScope.any)
          Text(String(localized: "Mouse"))
            .tag(InputDeviceScope.mouse(identifier: nil))
          Text(String(localized: "Trackpad"))
            .tag(InputDeviceScope.trackpad)
        }
        .labelsHidden()
        .frame(width: 190, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var footer: some View {
    HStack {
      Button(String(localized: "Start Over")) {
        training.reset()
        points.removeAll(keepingCapacity: true)
        feedback = String(
          localized: "Draw the same gesture three times."
        )
      }

      Spacer()

      Button(String(localized: "Cancel")) {
        dismiss()
      }

      Button(String(localized: "Save Gesture")) {
        onSave(
          GestureMappingDraft(
            name: trimmedName,
            templates: training.templates,
            action: action,
            secondaryAction: secondaryAction,
            appScope: appScope,
            triggerButton: triggerButton,
            category: initialCategory,
            applicationGroupID: applicationGroupID,
            repeatModeEnabled: initialRepeatModeEnabled,
            deviceScope: deviceScope,
            isEnabled: initialIsEnabled
          )
        )
        dismiss()
      }
      .keyboardShortcut(.defaultAction)
      .disabled(!canSave)
    }
  }

  @ViewBuilder
  private var phaseLabel: some View {
    switch training.phase {
    case .collecting(let sampleCount):
      Text(
        String(
          format: String(localized: "Sample %d of 3"),
          sampleCount + 1
        )
      )
    case .testing(let successCount):
      Text(
        String(
          format: String(localized: "Test %d of 2"),
          successCount + 1
        )
      )
    case .readyToSave:
      Label(
        String(localized: "Ready"),
        systemImage: "checkmark.circle.fill"
      )
      .foregroundStyle(.green)
    }
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSave: Bool {
    training.phase == .readyToSave
      && !trimmedName.isEmpty
      && action.isValid
      && (secondaryAction?.isValid ?? true)
  }

  private var shortcutConflict: SystemShortcutConflict? {
    guard case .keyboardShortcut(let shortcut) = action else {
      return nil
    }
    return SystemShortcutConflictDetector().conflict(for: shortcut)
  }

  private var scopeSummary: String {
    switch appScope {
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
      return String(localized: "Trackpad Modifier Gesture")
    }
    return button.localizedName
  }

  private var feedbackColor: Color {
    training.phase == .readyToSave ? .green : .secondary
  }

  private func selectTriggerButton(
    _ button: GestureTriggerButton?
  ) {
    guard
      !AppModel.mappingTriggerConflictsWithSecondary(
        button,
        secondaryTriggerButton: model.secondaryTriggerButton
      )
    else {
      triggerConflictMessage = String(
        localized:
          "This input is reserved as the secondary trigger."
      )
      return
    }
    triggerConflictMessage = nil
    triggerButton = button
    training.setTriggerButton(button)
    points.removeAll(keepingCapacity: true)
    feedback = String(
      localized: "Draw the same gesture three times."
    )
  }

  private func handleStroke(_ stroke: [GesturePoint]) {
    let result: GestureTrainingResult
    switch training.phase {
    case .collecting:
      result = training.recordSample(stroke)
    case .testing:
      result = training.recordTest(stroke)
    case .readyToSave:
      return
    }
    feedback = feedbackText(for: result)
  }

  private func feedbackText(
    for result: GestureTrainingResult
  ) -> String {
    switch result {
    case .sampleAccepted(let count, let required):
      return String(
        format: String(localized: "%d of %d samples recorded."),
        count,
        required
      )
    case .readyForTesting:
      return String(
        localized:
          "Samples recorded. Draw the gesture twice more to test it."
      )
    case .testAccepted(let count, let required):
      return String(
        format: String(localized: "%d of %d tests passed."),
        count,
        required
      )
    case .readyToSave:
      return String(
        localized: "Gesture verified. Choose an action and save."
      )
    case .sampleRejected(.conflicts(let mappingID, _)):
      let name =
        existingMappings.first(where: { $0.id == mappingID })?.name
        ?? String(localized: "another gesture")
      return String(
        format: String(localized: "Too similar to “%@”. Try again."),
        name
      )
    case .sampleRejected(.inconsistent):
      return String(
        localized:
          "That stroke differs from the earlier samples. Try again."
      )
    case .sampleRejected(.invalidStroke):
      return String(
        localized: "The stroke is too short or incomplete. Try again."
      )
    case .testRejected:
      return String(
        localized: "The test did not match. Draw the gesture again."
      )
    case .invalidPhase:
      return String(localized: "Start over and record the gesture again.")
    }
  }
}

private struct GestureDrawingPad: View {
  @Binding var points: [GesturePoint]
  let guidePoints: [GesturePoint]
  let onComplete: ([GesturePoint]) -> Void

  @State private var isDrawing = false

  var body: some View {
    Canvas { context, size in
      let bounds = Path(
        roundedRect: CGRect(origin: .zero, size: size),
        cornerRadius: 10
      )
      context.fill(bounds, with: .color(.black.opacity(0.04)))
      context.stroke(
        bounds,
        with: .color(.secondary.opacity(0.35)),
        lineWidth: 1
      )

      let scaledGuide = scaledGuidePoints(in: size)
      if let firstGuidePoint = scaledGuide.first {
        var guidePath = Path()
        guidePath.move(to: firstGuidePoint)
        for point in scaledGuide.dropFirst() {
          guidePath.addLine(to: point)
        }
        context.stroke(
          guidePath,
          with: .color(.secondary.opacity(0.65)),
          style: StrokeStyle(
            lineWidth: 3,
            lineCap: .round,
            lineJoin: .round,
            dash: [7, 5]
          )
        )
      }

      guard let first = points.first else { return }
      var path = Path()
      path.move(
        to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y))
      )
      for point in points.dropFirst() {
        path.addLine(
          to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
        )
      }
      context.stroke(
        path,
        with: .color(.accentColor),
        style: StrokeStyle(
          lineWidth: 4,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "Gesture drawing area"))
    .accessibilityHint(
      String(localized: "Draw a gesture in this area.")
    )
    .overlay {
      if points.isEmpty && guidePoints.isEmpty {
        Label(
          String(localized: "Draw here"),
          systemImage: "cursorarrow.motionlines"
        )
        .foregroundStyle(.secondary)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if points.isEmpty && !guidePoints.isEmpty {
        Text(String(localized: "Draw over the original gesture"))
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(10)
      }
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          if !isDrawing {
            isDrawing = true
            points.removeAll(keepingCapacity: true)
          }
          points.append(
            GesturePoint(
              x: Float(value.location.x),
              y: Float(value.location.y)
            )
          )
        }
        .onEnded { value in
          points.append(
            GesturePoint(
              x: Float(value.location.x),
              y: Float(value.location.y)
            )
          )
          isDrawing = false
          onComplete(points)
        }
    )
  }

  private func scaledGuidePoints(in size: CGSize) -> [CGPoint] {
    guard !guidePoints.isEmpty else { return [] }
    let minX = guidePoints.map(\.x).min() ?? 0
    let maxX = guidePoints.map(\.x).max() ?? 0
    let minY = guidePoints.map(\.y).min() ?? 0
    let maxY = guidePoints.map(\.y).max() ?? 0
    let width = max(CGFloat(maxX - minX), 0.001)
    let height = max(CGFloat(maxY - minY), 0.001)
    let horizontalScale = max(1, size.width - 56) / width
    let verticalScale = max(1, size.height - 56) / height
    let scale = min(horizontalScale, verticalScale)
    let centerX = CGFloat(minX + maxX) / 2
    let centerY = CGFloat(minY + maxY) / 2

    return guidePoints.map {
      CGPoint(
        x: size.width / 2 + (CGFloat($0.x) - centerX) * scale,
        y: size.height / 2 + (CGFloat($0.y) - centerY) * scale
      )
    }
  }
}
