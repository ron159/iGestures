import SwiftUI

struct GestureRecorderSheet: View {
  @Environment(\.dismiss) private var dismiss

  @ObservedObject var model: AppModel
  @State private var name: String
  @State private var shortcut: KeyboardShortcut
  @State private var training: GestureTrainingSession
  @State private var points: [GesturePoint] = []
  @State private var feedback: String

  private let existingMappings: [GestureMapping]
  private let initialAppScope: AppScope
  private let initialIsEnabled: Bool
  private let isEditing: Bool
  let onSave: (GestureMappingDraft) -> Void

  init(
    model: AppModel,
    existingMappings: [GestureMapping],
    editingMapping: GestureMapping? = nil,
    onSave: @escaping (GestureMappingDraft) -> Void
  ) {
    self.model = model
    self.existingMappings = existingMappings
    self.initialAppScope = editingMapping?.appScope ?? .all
    self.initialIsEnabled = editingMapping?.isEnabled ?? true
    self.isEditing = editingMapping != nil
    self.onSave = onSave
    _name = State(
      initialValue:
        editingMapping?.name ?? String(localized: "New Gesture")
    )
    _shortcut = State(
      initialValue:
        editingMapping?.shortcut
        ?? ShortcutRecordingSession.emptyShortcut
    )
    _training = State(
      initialValue: GestureTrainingSession(
        existingMappings: existingMappings,
        editingMappingID: editingMapping?.id
      )
    )
    _feedback = State(
      initialValue: String(
        localized: "Draw the same gesture three times."
      )
    )
  }

  var body: some View {
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

      GestureDrawingPad(points: $points) {
        handleStroke($0)
      }
      .frame(height: 300)

      Text(feedback)
        .foregroundStyle(feedbackColor)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        TextField(String(localized: "Gesture Name"), text: $name)
        ShortcutRecorderView(shortcut: $shortcut, model: model)
          .frame(width: 140)
      }

      if let conflict = shortcutConflict {
        Label(
          conflict.localizedDescription,
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
      }

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
              shortcut: shortcut,
              appScope: initialAppScope,
              isEnabled: initialIsEnabled
            )
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSave)
      }
    }
    .padding(24)
    .frame(width: 640)
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
      && shortcut.isValid
  }

  private var shortcutConflict: SystemShortcutConflict? {
    SystemShortcutConflictDetector().conflict(for: shortcut)
  }

  private var feedbackColor: Color {
    training.phase == .readyToSave ? .green : .secondary
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
        localized: "Gesture verified. Choose a shortcut and save."
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
    .overlay {
      if points.isEmpty {
        Label(
          String(localized: "Draw here"),
          systemImage: "cursorarrow.motionlines"
        )
        .foregroundStyle(.secondary)
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
}
