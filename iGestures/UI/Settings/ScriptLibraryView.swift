import SwiftUI

struct ScriptLibraryView: View {
  @ObservedObject var model: AppModel
  let showsTitle: Bool
  let onSelect: ((ScriptLibraryItem) -> Void)?
  @State private var searchText = ""
  @State private var editingItem: ScriptLibraryItem?
  @State private var deletingItem: ScriptLibraryItem?

  init(
    model: AppModel,
    showsTitle: Bool = true,
    onSelect: ((ScriptLibraryItem) -> Void)? = nil
  ) {
    self.model = model
    self.showsTitle = showsTitle
    self.onSelect = onSelect
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      if let error = model.scriptLibraryError {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
      }

      if model.isLoadingScriptLibrary {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        scriptList
      }
    }
    .padding(showsTitle ? 20 : 0)
    .sheet(item: $editingItem) { item in
      ScriptLibraryItemEditor(
        item: item,
        model: model
      ) {
        model.updateUserScript($0)
      }
    }
    .confirmationDialog(
      String(localized: "Delete this script?"),
      isPresented: Binding(
        get: { deletingItem != nil },
        set: {
          if !$0 {
            deletingItem = nil
          }
        }
      ),
      presenting: deletingItem
    ) { item in
      Button(String(localized: "Delete"), role: .destructive) {
        model.deleteUserScript(id: item.id)
        deletingItem = nil
      }
      Button(String(localized: "Cancel"), role: .cancel) {
        deletingItem = nil
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      if showsTitle {
        ViewThatFits(in: .horizontal) {
          HStack {
            title
            Spacer()
            addButton
          }
          VStack(alignment: .leading, spacing: 10) {
            title
            addButton
          }
        }
      } else {
        HStack {
          Spacer()
          addButton
        }
      }

      Text(
        String(
          localized:
            "Save scripts you use often, then choose them directly while editing a gesture action."
        )
      )
      .foregroundStyle(.secondary)

      Label(
        String(
          localized:
            "Shell scripts run directly without opening Terminal. AppleScript may request Automation access the first time it controls another app."
        ),
        systemImage: "lock.shield"
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      TextField(
        String(localized: "Search Scripts"),
        text: $searchText
      )
      .textFieldStyle(.roundedBorder)
    }
  }

  private var title: some View {
    Label(
      String(localized: "Script Library"),
      systemImage: "books.vertical"
    )
    .font(.title2)
    .fontWeight(.semibold)
  }

  private var addButton: some View {
    Button {
      editingItem = ScriptLibraryItem(
        name: String(localized: "New Script"),
        summary: "",
        category: .productivity,
        script: AutomationScript(
          kind: .appleScript,
          source: "-- Enter AppleScript here"
        )
      )
    } label: {
      Label(
        String(localized: "New Script"),
        systemImage: "plus"
      )
    }
    .buttonStyle(.borderedProminent)
  }

  private var scriptList: some View {
    List {
      Section(String(localized: "Built-In Scripts")) {
        ForEach(filteredBuiltInItems) { item in
          scriptRow(item, isBuiltIn: true)
        }
      }

      Section(String(localized: "My Scripts")) {
        if filteredUserItems.isEmpty {
          Text(
            searchText.isEmpty
              ? String(localized: "No saved scripts yet.")
              : String(localized: "No matching scripts.")
          )
          .foregroundStyle(.secondary)
        } else {
          ForEach(filteredUserItems) { item in
            scriptRow(item, isBuiltIn: false)
          }
        }
      }
    }
    .listStyle(.inset)
  }

  private var filteredBuiltInItems: [ScriptLibraryItem] {
    filtered(BuiltInScriptLibrary.items)
  }

  private var filteredUserItems: [ScriptLibraryItem] {
    filtered(model.userScriptLibrary)
  }

  private func filtered(
    _ items: [ScriptLibraryItem]
  ) -> [ScriptLibraryItem] {
    let query = searchText.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !query.isEmpty else { return items }
    return items.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.summary.localizedCaseInsensitiveContains(query)
        || $0.category.localizedName
          .localizedCaseInsensitiveContains(query)
    }
  }

  private func scriptRow(
    _ item: ScriptLibraryItem,
    isBuiltIn: Bool
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(
        systemName:
          item.script.kind == .appleScript
          ? "scroll" : "terminal"
      )
      .foregroundStyle(.secondary)
      .frame(width: 24)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(item.name)
            .fontWeight(.medium)
          Text(item.category.localizedName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              .secondary.opacity(0.12),
              in: Capsule()
            )
        }
        Text(item.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(
          item.script.kind == .appleScript
            ? String(localized: "AppleScript")
            : String(localized: "Shell Script")
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }

      Spacer()

      if let onSelect {
        Button {
          onSelect(item)
        } label: {
          Label(
            String(localized: "Choose"),
            systemImage: "checkmark"
          )
        }
      }

      if isBuiltIn {
        Button {
          _ = model.createUserScript(copying: item)
        } label: {
          Label(
            String(localized: "Copy to My Scripts"),
            systemImage: "plus.square.on.square"
          )
        }
      } else {
        Button(String(localized: "Edit")) {
          editingItem = item
        }
        Button(role: .destructive) {
          deletingItem = item
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help(String(localized: "Delete"))
        .accessibilityLabel(String(localized: "Delete"))
      }
    }
    .padding(.vertical, 5)
  }
}

private struct ScriptLibraryItemEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var item: ScriptLibraryItem

  let model: AppModel
  let onSave: (ScriptLibraryItem) -> Void

  init(
    item: ScriptLibraryItem,
    model: AppModel,
    onSave: @escaping (ScriptLibraryItem) -> Void
  ) {
    _item = State(initialValue: item)
    self.model = model
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        item.name.isEmpty
          ? String(localized: "New Script")
          : item.name
      )
      .font(.title2)
      .fontWeight(.semibold)

      Form {
        TextField(String(localized: "Name"), text: $item.name)
        TextField(
          String(localized: "Description"),
          text: $item.summary,
          axis: .vertical
        )
        Picker(
          String(localized: "Category"),
          selection: $item.category
        ) {
          ForEach(ScriptLibraryCategory.allCases, id: \.self) {
            Text($0.localizedName).tag($0)
          }
        }

        ScriptActionEditor(
          script: $item.script,
          model: model,
          showsLibraryPicker: false
        )
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Save")) {
          item.name = item.name.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          onSave(item)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
      }
    }
    .padding(24)
    .frame(
      minWidth: 540,
      idealWidth: 640,
      maxWidth: 780,
      minHeight: 480,
      idealHeight: 620,
      maxHeight: 780
    )
  }

  private var isValid: Bool {
    let name = item.name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return !name.isEmpty
      && name.count <= 120
      && item.summary.count <= 500
      && GestureAction.script(item.script).isValid(
        allowingUnconfirmedScripts: true
      )
  }
}

extension ScriptLibraryCategory {
  var localizedName: String {
    switch self {
    case .system:
      String(localized: "System")
    case .finder:
      String(localized: "Finder")
    case .productivity:
      String(localized: "Productivity")
    }
  }
}
