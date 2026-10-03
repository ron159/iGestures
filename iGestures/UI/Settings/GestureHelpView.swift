import AppKit
import SwiftUI

struct GestureHelpView: View {
  @ObservedObject var model: AppModel
  @ObservedObject private var diagnostics: GestureDiagnosticsState
  let showSettings: () -> Void
  @State private var practice: PracticeTarget?
  @State private var context = GestureMatchContext()
  @State private var showOverridden = false

  init(model: AppModel, showSettings: @escaping () -> Void) {
    self.model = model
    self.showSettings = showSettings
    _diagnostics = ObservedObject(wrappedValue: model.diagnosticsState)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(String(localized: "Gesture Help")).font(.title2.bold())
          Text(model.currentApplicationName ?? String(localized: "No Active Application"))
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button(String(localized: "Refresh"), systemImage: "arrow.clockwise") {
          refreshContext()
        }
      }
      Picker(String(localized: "Gesture Help"), selection: $model.gestureHelpPage) {
        Text(String(localized: "Current App Gestures")).tag(GestureHelpPage.reference)
        Text(String(localized: "Recent Gesture Diagnostics")).tag(GestureHelpPage.diagnostics)
      }
      .pickerStyle(.segmented)

      if !model.isEnabled {
        Label(String(localized: "Gesture recognition is disabled."), systemImage: "pause.circle")
      } else if model.permissionState != .granted {
        Button(String(localized: "Review Permissions…")) { openPermissions() }
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if model.gestureHelpPage == .reference {
            reference
          } else {
            diagnosticList
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
      }
      Text(
        String(
          localized:
            "Practice never runs actions. Recorded paths stay in this window unless you save a sample."
        )
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(minWidth: 530, idealWidth: 610, minHeight: 430, idealHeight: 660)
    .onAppear { refreshContext() }
    .preferredColorScheme(model.interfaceAppearance.preferredColorScheme)
    .onChange(of: model.currentApplicationBundleIdentifier) { refreshContext() }
    .sheet(item: $practice) { target in
      GesturePracticeView(model: model, target: target, context: context)
    }
  }

  private var reference: some View {
    let entries = GestureAssistance.reference(
      snapshot: model.assistanceSnapshot,
      bundleID: model.currentApplicationBundleIdentifier,
      defaultTrigger: model.triggerButton, context: context,
      exclusions: model.applicationExclusions,
      trackpadGestureEnabled: model.isTrackpadGestureEnabled,
      recognizer: GestureRecognizer(configuration: model.recognitionSensitivity.configuration)
    )
    return VStack(alignment: .leading, spacing: 12) {
      Text(
        String(
          localized:
            "Shows rules for the current app and active configuration sets. Conditional rules list what they need."
        )
      )
      .font(.callout).foregroundStyle(.secondary)
      if entries.isEmpty {
        Text(
          String(
            localized:
              "No gestures are available here. Check app exclusions, enabled rules and configuration sets."
          )
        )
        .padding(.vertical)
      }
      ForEach(entries.filter { $0.overriddenBy == nil }) { entry in
        referenceRow(entry)
      }
      if entries.contains(where: { $0.overriddenBy != nil }) {
        DisclosureGroup(String(localized: "Rules With Another Match"), isExpanded: $showOverridden)
        {
          ForEach(entries.filter { $0.overriddenBy != nil }) { entry in
            referenceRow(entry)
          }
        }
      }
    }
  }

  private func referenceRow(_ entry: GestureReferenceEntry) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        mappingHeader(entry.mapping)
        Text(triggerSummary(entry.mapping)).font(.callout)
        if entry.requiresConditions {
          Label(
            String(localized: "Additional Conditions Required"),
            systemImage: "line.3.horizontal.decrease.circle"
          )
          .foregroundStyle(.orange)
        }
        if entry.mapping.contextCondition != .any || !entry.mapping.requiredChordButtons.isEmpty
          || entry.mapping.deviceScope != .any
        {
          Text(conditionSummary(entry.mapping)).font(.caption).foregroundStyle(.secondary)
        }
        if let winner = entry.overriddenBy {
          Text(
            String(
              format: entry.mapping.inputVariant.requiresDrawnGesture
                ? String(localized: "The saved drawing currently matches “%@” instead.")
                : String(localized: "This input currently matches “%@” instead."), winner.name)
          )
          .font(.callout).foregroundStyle(.secondary)
          Button(String(localized: "View Matching Rule")) { edit(winner.mappingID) }
        }
        mappingButtons(entry.mapping, bundleID: model.currentApplicationBundleIdentifier)
      }
      .padding(6).frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var diagnosticList: some View {
    VStack(alignment: .leading, spacing: 12) {
      if diagnostics.records.isEmpty {
        Text(String(localized: "No recent gesture diagnostics."))
      }
      ForEach(diagnostics.records.reversed()) { record in
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
              Text(record.summary).font(.headline)
              Spacer()
              Text(record.timestamp, style: .time).foregroundStyle(.secondary)
            }
            if let detail = record.detail {
              Text(detail.guidance).font(.callout)
              if let bundleID = detail.applicationBundleID {
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
              }
              ForEach(detail.suggestions) { suggestion in
                if let mapping = model.mappings.first(where: { $0.id == suggestion.mappingID }) {
                  Divider()
                  mappingHeader(mapping)
                  mappingButtons(
                    mapping,
                    bundleID: detail.applicationBundleID ?? model.currentApplicationBundleIdentifier
                  )
                }
              }
              if detail.reason == .actionFailed {
                Button(String(localized: "Review Permissions…")) { openPermissions() }
              }
            }
          }
          .padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      if !diagnostics.records.isEmpty {
        Button(String(localized: "Clear Diagnostics")) { model.clearDiagnostics() }
      }
    }
  }

  private func mappingHeader(_ mapping: GestureMapping) -> some View {
    HStack(spacing: 12) {
      if let template = mapping.templates.first, mapping.inputVariant == .draw {
        GestureTemplatePreview(template: template).frame(width: 64, height: 48)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(mapping.name).font(.headline)
        Text(GestureActionSummary.text(for: mapping.action)).font(.callout)
      }
      Spacer()
      Text(sourceName(mapping)).font(.caption).foregroundStyle(.secondary)
    }
  }

  private func mappingButtons(_ mapping: GestureMapping, bundleID: String?) -> some View {
    HStack {
      if mapping.inputVariant == .draw {
        Button(String(localized: "Practice / Add Sample…")) {
          practice = PracticeTarget(mapping: mapping, bundleID: bundleID)
        }
      }
      Button(String(localized: "Edit Rule…")) { edit(mapping.id) }
    }
  }

  private func edit(_ id: UUID) {
    model.requestMappingSettings(id)
    showSettings()
  }

  private func openPermissions() {
    model.requestPermissionsSettings()
    showSettings()
  }

  private func sourceName(_ mapping: GestureMapping) -> String {
    if let id = mapping.applicationGroupID,
      let group = model.gestureApplicationGroups.first(where: { $0.id == id })
    {
      return String(format: String(localized: "Group: %@"), group.name)
    }
    if case .only = mapping.appScope {
      return String(localized: "Application Rule")
    }
    return String(localized: "Global Rule")
  }

  private func triggerSummary(_ mapping: GestureMapping) -> String {
    let trigger = (mapping.triggerButton ?? model.triggerButton).localizedName
    let variant: String =
      switch mapping.inputVariant {
      case .draw: String(localized: "Draw Gesture")
      case .doubleClick: String(localized: "Double Click")
      case .longPress: String(localized: "Long Press")
      case .scrollWheel(.up): String(localized: "Hold Button + Scroll Up")
      case .scrollWheel(.down): String(localized: "Hold Button + Scroll Down")
      case .scrollWheel(.either): String(localized: "Hold Button + Scroll Either Way")
      }
    return "\(trigger) · \(variant)"
  }

  private func conditionSummary(_ mapping: GestureMapping) -> String {
    var parts = mapping.requiredChordButtons.map(\.localizedName)
    let condition = mapping.contextCondition
    if condition.requiredModifiers != 0 {
      parts.append(
        String(format: String(localized: "Hold %@"), modifierNames(condition.requiredModifiers)))
    }
    if condition.forbiddenModifiers != 0 {
      parts.append(
        String(format: String(localized: "Release %@"), modifierNames(condition.forbiddenModifiers))
      )
    }
    if !condition.displayIDs.isEmpty {
      parts.append(
        String(
          format: String(localized: "Displays: %@"),
          condition.displayIDs.map(String.init).joined(separator: ", ")))
    }
    parts += condition.connectedDeviceIdentifiers
    switch mapping.deviceScope {
    case .any: break
    case .trackpad: parts.append(String(localized: "Trackpad"))
    case .mouse(let identifier): parts.append(identifier ?? String(localized: "Mouse"))
    }
    return parts.joined(separator: " · ")
  }

  private func modifierNames(_ value: UInt64) -> String {
    [
      (CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"),
      (.maskCommand, "⌘"), (.maskSecondaryFn, "fn"),
    ]
    .filter { value & $0.0.rawValue != 0 }.map(\.1).joined()
  }

  private func refreshContext() {
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    let displayID =
      (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
      .uint32Value
    context = GestureMatchContext(
      modifierFlags: UInt64(NSEvent.modifierFlags.rawValue), displayID: displayID,
      connectedDeviceIdentifiers: EventTapManager.connectedInputDeviceIdentifiers()
    )
  }
}

private struct PracticeTarget: Identifiable {
  let mapping: GestureMapping
  let bundleID: String?
  var id: UUID { mapping.id }
}

private struct GesturePracticeView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: AppModel
  let target: PracticeTarget
  let context: GestureMatchContext
  @State private var points: [GesturePoint] = []
  @State private var completedStroke: [GesturePoint] = []
  @State private var report: GestureDiagnosticDetail?
  @State private var sampleMessage: String?
  @State private var isSavingSample = false

  private var mapping: GestureMapping? { model.mappings.first { $0.id == target.id } }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(target.mapping.name).font(.title2.bold())
          Text(
            String(
              localized:
                "Practice simulates this rule's trigger and required modifiers. No action is executed."
            )
          )
          .font(.callout).foregroundStyle(.secondary)
          Text(String(localized: "Live gestures are paused while practicing."))
            .font(.caption).foregroundStyle(.secondary)
          if let bundleID = target.bundleID {
            Text(bundleID).font(.caption).foregroundStyle(.secondary)
          }
          GestureDrawingPad(
            points: $points, guidePoints: target.mapping.templates.first?.points ?? []
          ) {
            completedStroke = $0
            sampleMessage = nil
            evaluate($0)
          }
          .frame(height: 260)
          if let report {
            Text(report.summary).font(.headline)
            Text(report.guidance).font(.callout).foregroundStyle(.secondary)
            if !report.suggestions.isEmpty {
              HStack(spacing: 16) {
                ForEach(report.suggestions) { suggestion in
                  if let candidate = model.mappings.first(where: { $0.id == suggestion.mappingID }),
                    let template = candidate.templates.first
                  {
                    VStack {
                      GestureTemplatePreview(template: template).frame(width: 80, height: 52)
                      Text(candidate.name).font(.caption).lineLimit(2)
                    }
                  }
                }
              }
            }
          }
          if let sampleMessage { Text(sampleMessage).font(.callout) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Button(String(localized: "Save as Additional Sample")) {
          Task { await saveSample() }
        }
        .disabled(isSavingSample || completedStroke.isEmpty || mapping == nil)
        Spacer()
        Button(String(localized: "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }
    .padding(24).frame(width: 570, height: 640)
    .onAppear { model.setGesturePracticeActive(true) }
    .onDisappear { model.setGesturePracticeActive(false) }
  }

  private func evaluate(_ stroke: [GesturePoint]) {
    guard let mapping else { return }
    let trigger = mapping.triggerButton ?? model.triggerButton
    let simulated = GestureMatchContext(
      inputDevice: trigger == .trackpad ? .trackpad : context.inputDevice,
      modifierFlags: mapping.contextCondition.requiredModifiers,
      displayID: context.displayID, connectedDeviceIdentifiers: context.connectedDeviceIdentifiers,
      heldButtons: Set(mapping.requiredChordButtons).union([trigger])
    )
    report = GestureAssistance.diagnose(
      stroke, snapshot: model.assistanceSnapshot, bundleID: target.bundleID,
      trigger: trigger, defaultTrigger: model.triggerButton, context: simulated,
      recognizer: GestureRecognizer(configuration: model.recognitionSensitivity.configuration)
    )
  }

  private func saveSample() async {
    isSavingSample = true
    defer { isSavingSample = false }
    do {
      try await model.addGestureSample(completedStroke, mappingID: target.id)
      sampleMessage = String(
        localized: "Sample added. Your existing samples and actions are preserved.")
      completedStroke = []
    } catch {
      switch error {
      case GestureAssistance.SampleError.full:
        sampleMessage = String(
          localized: "This gesture already has five samples. Edit the rule to record it again.")
      case GestureAssistance.SampleError.conflict(let name):
        sampleMessage = String(format: String(localized: "Too similar to “%@”. Try again."), name)
      case GestureAssistance.SampleError.tooDifferent:
        sampleMessage = String(
          localized:
            "This drawing is too different. Edit the rule to retrain it, or try a closer variation."
        )
      default:
        sampleMessage =
          model.mappingStoreError
          ?? String(localized: "The stroke is too short or incomplete. Try again.")
      }
    }
  }
}

extension GestureDiagnosticDetail {
  var summary: String {
    switch reason {
    case .matched:
      String(format: String(localized: "Would run: %@"), suggestions.first?.name ?? "")
    case .strokeTooShort: String(localized: "The gesture is too short.")
    case .invalidStroke: String(localized: "The gesture path is incomplete.")
    case .noMatch: String(localized: "No matching gesture in this context.")
    case .ambiguous:
      String(
        format: String(localized: "Similar gestures: %@"),
        suggestions.prefix(2).map(\.name).joined(separator: " / "))
    case .applicationScope: String(localized: "A similar gesture belongs to another application.")
    case .trigger: String(localized: "A similar gesture uses another trigger.")
    case .conditions: String(localized: "A similar gesture requires different conditions.")
    case .actionFailed:
      String(
        format: String(localized: "“%@” matched, but its action failed."),
        suggestions.first?.name ?? "")
    }
  }

  var guidance: String {
    switch reason {
    case .matched: String(localized: "This is a recognition test; the action was not executed.")
    case .strokeTooShort, .invalidStroke:
      String(
        localized: "Draw a longer, continuous stroke. A small movement is kept as a normal click.")
    case .noMatch:
      String(
        localized:
          "Compare the closest rules below. Practice the intended gesture or add a sample of your drawing style."
      )
    case .ambiguous:
      String(
        localized:
          "Compare these drawings. Make their shapes more distinct or assign them different triggers or scopes."
      )
    case .applicationScope:
      String(
        localized:
          "Check the rule's application scope and group. Its action was not run in this application."
      )
    case .trigger, .conditions:
      String(
        localized:
          "Check the rule's trigger, held buttons, modifiers, display and input device conditions.")
    case .actionFailed:
      switch actionFailure {
      case .targetNotFound:
        String(
          localized:
            "The target window, app or menu item was unavailable. Check the target and Accessibility permission."
        )
      case .timedOut:
        String(
          localized:
            "The action timed out. Check whether its target application or script is responding.")
      case .notConfirmed:
        String(
          localized: "The script was not approved to run. Review its contents in the rule editor.")
      case .processFailed(let code):
        String(
          format: String(
            localized:
              "The script exited with code %d. Review the script and its Automation permissions."),
          Int(code))
      case .launchFailed:
        String(
          localized:
            "The target could not be launched. Check the configured application, URL or file.")
      case .outputLimitExceeded:
        String(
          localized: "The script produced too much output. Reduce its output in the rule editor.")
      default:
        String(
          localized:
            "Check the configured action and its permissions. Changing the gesture drawing will not repair an action failure."
        )
      }
    }
  }
}

extension GestureDiagnosticRecord {
  var summary: String {
    if let detail { return detail.summary }
    return switch outcome {
    case .executed:
      String(
        format: String(localized: "Executed: %@"),
        mappingName ?? String(localized: "Unnamed Gesture"))
    case .noMatch: String(localized: "Gesture was not recognized")
    case .ambiguous: String(localized: "Gesture result was ambiguous")
    case .actionFailed:
      String(
        format: String(localized: "Action failed: %@"),
        mappingName ?? String(localized: "Unnamed Gesture"))
    case .cancelled: String(localized: "Gesture was cancelled")
    }
  }
}
