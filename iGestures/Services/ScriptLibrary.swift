import Foundation

public enum ScriptLibraryCategory:
  String,
  Codable,
  CaseIterable,
  Sendable
{
  case system
  case finder
  case productivity
}

public struct ScriptLibraryItem:
  Codable,
  Equatable,
  Hashable,
  Identifiable,
  Sendable
{
  public let id: UUID
  public var name: String
  public var summary: String
  public var category: ScriptLibraryCategory
  public var script: AutomationScript

  public init(
    id: UUID = UUID(),
    name: String,
    summary: String,
    category: ScriptLibraryCategory,
    script: AutomationScript
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.category = category
    self.script = script
  }
}

public enum BuiltInScriptLibrary {
  public static let items: [ScriptLibraryItem] = [
    ScriptLibraryItem(
      id: UUID(
        uuidString: "00000000-0000-0000-0002-000000000001"
      )!,
      name: String(localized: "Toggle Dark Mode"),
      summary: String(
        localized:
          "Switch between the light and dark system appearances."
      ),
      category: .system,
      script: AutomationScript(
        kind: .appleScript,
        source:
          """
          tell application "System Events"
            tell appearance preferences
              set dark mode to not dark mode
            end tell
          end tell
          """,
        timeout: 5,
        isConfirmed: true
      )
    ),
    ScriptLibraryItem(
      id: UUID(
        uuidString: "00000000-0000-0000-0002-000000000002"
      )!,
      name: String(localized: "Start Screen Saver"),
      summary: String(
        localized: "Start the macOS screen saver immediately."
      ),
      category: .system,
      script: AutomationScript(
        kind: .shell,
        source: #"/usr/bin/open -a ScreenSaverEngine"#,
        timeout: 5,
        isConfirmed: true
      )
    ),
    ScriptLibraryItem(
      id: UUID(
        uuidString: "00000000-0000-0000-0002-000000000003"
      )!,
      name: String(localized: "Toggle Dock Auto-Hide"),
      summary: String(
        localized:
          "Toggle Dock auto-hide and restart the Dock to apply it."
      ),
      category: .system,
      script: AutomationScript(
        kind: .shell,
        source:
          """
          current=$(/usr/bin/defaults read com.apple.dock autohide 2>/dev/null || printf "0")
          if [[ "$current" == "1" ]]; then
            next=false
          else
            next=true
          fi
          /usr/bin/defaults write com.apple.dock autohide -bool "$next"
          /usr/bin/killall Dock
          """,
        timeout: 10,
        isConfirmed: true
      )
    ),
    ScriptLibraryItem(
      id: UUID(
        uuidString: "00000000-0000-0000-0002-000000000004"
      )!,
      name: String(localized: "Toggle Hidden Files"),
      summary: String(
        localized:
          "Show or hide hidden files and restart Finder to apply it."
      ),
      category: .finder,
      script: AutomationScript(
        kind: .shell,
        source:
          """
          current=$(/usr/bin/defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || printf "0")
          if [[ "$current" == "1" ]]; then
            next=false
          else
            next=true
          fi
          /usr/bin/defaults write com.apple.finder AppleShowAllFiles -bool "$next"
          /usr/bin/killall Finder
          """,
        timeout: 10,
        isConfirmed: true
      )
    ),
    ScriptLibraryItem(
      id: UUID(
        uuidString: "00000000-0000-0000-0002-000000000005"
      )!,
      name: String(localized: "Copy Finder Selection Paths"),
      summary: String(
        localized:
          "Copy the full paths of selected Finder items to the clipboard."
      ),
      category: .finder,
      script: AutomationScript(
        kind: .appleScript,
        source:
          """
          tell application "Finder"
            set selectedItems to selection
            if (count of selectedItems) is 0 then return
            set pathList to {}
            repeat with selectedItem in selectedItems
              set end of pathList to POSIX path of (selectedItem as alias)
            end repeat
          end tell
          set previousDelimiters to AppleScript's text item delimiters
          set AppleScript's text item delimiters to linefeed
          set the clipboard to pathList as text
          set AppleScript's text item delimiters to previousDelimiters
          """,
        timeout: 10,
        isConfirmed: true
      )
    ),
    ScriptLibraryItem(
      id: UUID(
        uuidString: "00000000-0000-0000-0002-000000000006"
      )!,
      name: String(localized: "Open Terminal at Finder Folder"),
      summary: String(
        localized:
          "Open Terminal in the front Finder window's folder."
      ),
      category: .finder,
      script: AutomationScript(
        kind: .appleScript,
        source:
          """
          tell application "Finder"
            if (count of Finder windows) > 0 then
              set targetFolder to (target of front Finder window) as alias
            else
              set targetFolder to path to home folder
            end if
          end tell
          tell application "Terminal"
            activate
            do script "cd " & quoted form of POSIX path of targetFolder
          end tell
          """,
        timeout: 10,
        isConfirmed: true
      )
    ),
    ScriptLibraryItem(
      id: UUID(
        uuidString: "00000000-0000-0000-0002-000000000007"
      )!,
      name: String(localized: "Clear Clipboard"),
      summary: String(
        localized: "Remove the current text content from the clipboard."
      ),
      category: .productivity,
      script: AutomationScript(
        kind: .shell,
        source: #"printf "" | /usr/bin/pbcopy"#,
        timeout: 5,
        isConfirmed: true
      )
    ),
  ]
}

public struct ScriptLibraryStoreLimits: Equatable, Sendable {
  public let maximumFileSize: Int
  public let maximumItemCount: Int
  public let maximumNameLength: Int
  public let maximumSummaryLength: Int

  public init(
    maximumFileSize: Int = 1 * 1_024 * 1_024,
    maximumItemCount: Int = 100,
    maximumNameLength: Int = 120,
    maximumSummaryLength: Int = 500
  ) {
    self.maximumFileSize = max(1, maximumFileSize)
    self.maximumItemCount = max(1, maximumItemCount)
    self.maximumNameLength = max(1, maximumNameLength)
    self.maximumSummaryLength = max(0, maximumSummaryLength)
  }
}

public enum ScriptLibraryStoreError: Error, Equatable, Sendable {
  case fileTooLarge(limit: Int)
  case unsupportedSchema(found: Int)
  case tooManyItems(limit: Int)
  case duplicateIdentifier
  case reservedIdentifier
  case invalidName
  case invalidSummary
  case invalidScript
  case invalidData
  case recoveryFailed
  case fileSystemFailure
}

public actor ScriptLibraryStore {
  public static let defaultFileName = "script-library.json"
  public static let defaultBackupFileName =
    "script-library.backup.json"

  public nonisolated let fileURL: URL
  public nonisolated let backupURL: URL
  public nonisolated let limits: ScriptLibraryStoreLimits

  private let fileManager: FileManager
  private var items: [ScriptLibraryItem] = []

  private struct Database: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let items: [ScriptLibraryItem]

    init(items: [ScriptLibraryItem]) {
      self.schemaVersion = Self.currentSchemaVersion
      self.items = items
    }
  }

  public init(
    directoryURL: URL,
    limits: ScriptLibraryStoreLimits = ScriptLibraryStoreLimits(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = directoryURL.appendingPathComponent(
      Self.defaultFileName,
      isDirectory: false
    )
    self.backupURL = directoryURL.appendingPathComponent(
      Self.defaultBackupFileName,
      isDirectory: false
    )
    self.limits = limits
    self.fileManager = fileManager
  }

  public static func live(
    bundleIdentifier: String,
    limits: ScriptLibraryStoreLimits = ScriptLibraryStoreLimits()
  ) throws -> ScriptLibraryStore {
    guard !bundleIdentifier.isEmpty else {
      throw ScriptLibraryStoreError.fileSystemFailure
    }
    let baseURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return ScriptLibraryStore(
      directoryURL: baseURL.appendingPathComponent(
        bundleIdentifier,
        isDirectory: true
      ),
      limits: limits
    )
  }

  @discardableResult
  public func load() throws -> [ScriptLibraryItem] {
    try ensureDirectoryExists()
    guard fileManager.fileExists(atPath: fileURL.path) else {
      items = []
      return items
    }

    do {
      items = try decodeAndValidate(readData(at: fileURL))
      return items
    } catch {
      guard fileManager.fileExists(atPath: backupURL.path) else {
        throw normalize(error)
      }
      do {
        let backupData = try readData(at: backupURL)
        let recovered = try decodeAndValidate(backupData)
        try backupData.write(to: fileURL, options: .atomic)
        items = recovered
        return recovered
      } catch {
        throw ScriptLibraryStoreError.recoveryFailed
      }
    }
  }

  public func currentItems() -> [ScriptLibraryItem] {
    items
  }

  public func save(_ newItems: [ScriptLibraryItem]) throws {
    try validate(newItems)
    let data = try encode(newItems)
    try ensureDirectoryExists()

    if fileManager.fileExists(atPath: fileURL.path) {
      let existingData = try readData(at: fileURL)
      try existingData.write(to: backupURL, options: .atomic)
    }
    try data.write(to: fileURL, options: .atomic)
    items = newItems
  }

  public nonisolated func validate(
    _ candidateItems: [ScriptLibraryItem]
  ) throws {
    guard candidateItems.count <= limits.maximumItemCount else {
      throw ScriptLibraryStoreError.tooManyItems(
        limit: limits.maximumItemCount
      )
    }

    let identifiers = candidateItems.map(\.id)
    guard Set(identifiers).count == identifiers.count else {
      throw ScriptLibraryStoreError.duplicateIdentifier
    }
    let reservedIdentifiers = Set(
      BuiltInScriptLibrary.items.map(\.id)
    )
    guard reservedIdentifiers.isDisjoint(with: identifiers) else {
      throw ScriptLibraryStoreError.reservedIdentifier
    }

    for item in candidateItems {
      let trimmedName = item.name.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard
        !trimmedName.isEmpty,
        trimmedName == item.name,
        item.name.count <= limits.maximumNameLength
      else {
        throw ScriptLibraryStoreError.invalidName
      }
      guard item.summary.count <= limits.maximumSummaryLength else {
        throw ScriptLibraryStoreError.invalidSummary
      }
      guard
        GestureAction.script(item.script).isValid(
          allowingUnconfirmedScripts: true
        )
      else {
        throw ScriptLibraryStoreError.invalidScript
      }
    }
  }

  private func encode(
    _ candidateItems: [ScriptLibraryItem]
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(Database(items: candidateItems))
      guard data.count <= limits.maximumFileSize else {
        throw ScriptLibraryStoreError.fileTooLarge(
          limit: limits.maximumFileSize
        )
      }
      return data
    } catch let error as ScriptLibraryStoreError {
      throw error
    } catch {
      throw ScriptLibraryStoreError.invalidData
    }
  }

  private func decodeAndValidate(
    _ data: Data
  ) throws -> [ScriptLibraryItem] {
    guard data.count <= limits.maximumFileSize else {
      throw ScriptLibraryStoreError.fileTooLarge(
        limit: limits.maximumFileSize
      )
    }
    do {
      let database = try JSONDecoder().decode(
        Database.self,
        from: data
      )
      guard
        database.schemaVersion == Database.currentSchemaVersion
      else {
        throw ScriptLibraryStoreError.unsupportedSchema(
          found: database.schemaVersion
        )
      }
      try validate(database.items)
      return database.items
    } catch let error as ScriptLibraryStoreError {
      throw error
    } catch {
      throw ScriptLibraryStoreError.invalidData
    }
  }

  private func readData(at url: URL) throws -> Data {
    do {
      let attributes = try fileManager.attributesOfItem(
        atPath: url.path
      )
      if let size = attributes[.size] as? NSNumber,
        size.intValue > limits.maximumFileSize
      {
        throw ScriptLibraryStoreError.fileTooLarge(
          limit: limits.maximumFileSize
        )
      }
      return try Data(contentsOf: url)
    } catch let error as ScriptLibraryStoreError {
      throw error
    } catch {
      throw ScriptLibraryStoreError.fileSystemFailure
    }
  }

  private func ensureDirectoryExists() throws {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      throw ScriptLibraryStoreError.fileSystemFailure
    }
  }

  private func normalize(_ error: Error) -> ScriptLibraryStoreError {
    error as? ScriptLibraryStoreError ?? .fileSystemFailure
  }
}
