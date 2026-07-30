import Foundation
import XCTest

@testable import iGestures

final class ScriptLibraryTests: XCTestCase {
  private var directoryURL: URL!

  override func setUpWithError() throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directoryURL)
    directoryURL = nil
  }

  func testBuiltInScriptsAreUniqueConfirmedAndValid() {
    let items = BuiltInScriptLibrary.items

    XCTAssertFalse(items.isEmpty)
    XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    XCTAssertTrue(items.allSatisfy(\.script.isConfirmed))
    XCTAssertTrue(
      items.allSatisfy {
        GestureAction.script($0.script).isValid
      }
    )
  }

  func testUserScriptsRoundTrip() async throws {
    let item = makeItem(name: "Deploy", isConfirmed: false)
    let store = ScriptLibraryStore(directoryURL: directoryURL)

    try await store.save([item])
    let reloaded = try await ScriptLibraryStore(
      directoryURL: directoryURL
    ).load()
    let storedJSON = try String(
      contentsOf: store.fileURL,
      encoding: .utf8
    )

    XCTAssertEqual(reloaded, [item])
    XCTAssertTrue(storedJSON.contains(#""schemaVersion" : 1"#))
  }

  func testCorruptPrimaryRecoversBackup() async throws {
    let first = makeItem(name: "First")
    let second = makeItem(name: "Second")
    let store = ScriptLibraryStore(directoryURL: directoryURL)
    try await store.save([first])
    try await store.save([second])
    try Data("not json".utf8).write(
      to: store.fileURL,
      options: .atomic
    )

    let recovered = try await ScriptLibraryStore(
      directoryURL: directoryURL
    ).load()

    XCTAssertEqual(recovered, [first])
  }

  func testInvalidSaveDoesNotReplaceCurrentItems() async throws {
    let current = makeItem(name: "Current")
    let invalid = makeItem(name: " ")
    let store = ScriptLibraryStore(directoryURL: directoryURL)
    try await store.save([current])

    do {
      try await store.save([invalid])
      XCTFail("Expected invalid name")
    } catch {
      XCTAssertEqual(
        error as? ScriptLibraryStoreError,
        .invalidName
      )
    }

    let currentItems = await store.currentItems()
    XCTAssertEqual(currentItems, [current])
  }

  func testBuiltInIdentifierCannotBeUsedForUserScript() async {
    let builtIn = BuiltInScriptLibrary.items[0]
    let item = ScriptLibraryItem(
      id: builtIn.id,
      name: "Reserved",
      summary: "",
      category: .system,
      script: builtIn.script
    )
    let store = ScriptLibraryStore(directoryURL: directoryURL)

    do {
      try await store.save([item])
      XCTFail("Expected reserved identifier")
    } catch {
      XCTAssertEqual(
        error as? ScriptLibraryStoreError,
        .reservedIdentifier
      )
    }
  }

  func testUnknownSchemaIsRejected() async throws {
    let store = ScriptLibraryStore(directoryURL: directoryURL)
    try Data(#"{"schemaVersion":99,"items":[]}"#.utf8).write(
      to: store.fileURL,
      options: .atomic
    )

    do {
      _ = try await store.load()
      XCTFail("Expected unsupported schema")
    } catch {
      XCTAssertEqual(
        error as? ScriptLibraryStoreError,
        .unsupportedSchema(found: 99)
      )
    }
  }

  private func makeItem(
    name: String,
    isConfirmed: Bool = true
  ) -> ScriptLibraryItem {
    ScriptLibraryItem(
      name: name,
      summary: "A reusable script",
      category: .productivity,
      script: AutomationScript(
        kind: .shell,
        source: "printf ok",
        isConfirmed: isConfirmed
      )
    )
  }
}
