import XCTest

@testable import iGestures

final class ActionPresetLibraryTests: XCTestCase {
  func testBuiltInPresetsAreUniqueValidAndCoverEveryCategory() {
    let presets = ActionPresetLibrary.builtIn

    XCTAssertGreaterThan(presets.count, 60)
    XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
    XCTAssertTrue(presets.allSatisfy(\.isValid))
    XCTAssertEqual(
      Set(presets.map(\.category)),
      Set(ActionPresetCategory.allCases)
    )
  }

  func testSearchMatchesNamesSummariesAndKeywords() {
    let reopen = ActionPresetLibrary.matching("reopen")
    XCTAssertEqual(reopen.map(\.id), ["browser.reopen-tab"])

    let folder = ActionPresetLibrary.matching("folder")
    XCTAssertTrue(folder.contains { $0.id == "finder.downloads" })

    let empty = ActionPresetLibrary.matching("")
    XCTAssertEqual(empty.count, ActionPresetLibrary.builtIn.count)
  }

  func testWebsitePresetsUseHTTPSAndMatchCuratedSet() {
    let presets = ActionPresetLibrary.websitePresets()

    XCTAssertEqual(
      Set(presets.map(\.id)),
      Set([
        "website.bilibili",
        "website.bing",
        "website.chatgpt",
        "website.claude",
        "website.figma",
        "website.gemini",
        "website.github",
        "website.gmail",
        "website.google",
        "website.google-drive",
        "website.mdn",
        "website.notion",
        "website.perplexity",
        "website.stack-overflow",
        "website.youtube",
      ])
    )
    for preset in presets {
      guard case .openURL(let value) = preset.action else {
        return XCTFail("\(preset.id) is not an open URL action")
      }
      XCTAssertEqual(URL(string: value)?.scheme, "https")
    }
  }

  func testWebsitePresetSearchMatchesNameKeywordAndDomain() {
    XCTAssertEqual(
      ActionPresetLibrary.websitePresets(matching: "ChatGPT").map(\.id),
      ["website.chatgpt"]
    )
    XCTAssertEqual(
      ActionPresetLibrary.websitePresets(matching: "哔哩哔哩").map(\.id),
      ["website.bilibili"]
    )
    XCTAssertEqual(
      ActionPresetLibrary.websitePresets(matching: "stackoverflow.com")
        .map(\.id),
      ["website.stack-overflow"]
    )
  }

  func testWebsitePresetSearchRejectsMismatchedPresetShapes() {
    let matchingWebsite = ActionPreset(
      id: "website.example",
      name: "Example",
      category: .website,
      action: .openURL("https://custom.example/")
    )
    let wrongCategory = ActionPreset(
      id: "browser.example",
      name: "Example Browser Action",
      category: .browser,
      action: .openURL("https://custom.example/")
    )
    let wrongAction = ActionPreset(
      id: "website.not-a-url",
      name: "Example System Action",
      category: .website,
      action: .system(.missionControl)
    )

    XCTAssertEqual(
      ActionPresetLibrary.websitePresets(
        matching: "custom.example",
        in: [wrongCategory, wrongAction, matchingWebsite]
      ).map(\.id),
      [matchingWebsite.id]
    )
  }

  func testNewActionTypesRoundTripThroughCodable() throws {
    let actions: [GestureAction] = [
      .openPath("~/Downloads"),
      .customWindow(
        NormalizedWindowFrame(
          x: 0.1,
          y: 0.2,
          width: 0.7,
          height: 0.6
        )
      ),
      .typeText("Hello"),
      .applicationMenu(
        ApplicationMenuAction(path: ["File", "Export", "PDF"])
      ),
    ]

    for action in actions {
      let data = try JSONEncoder().encode(action)
      XCTAssertEqual(
        try JSONDecoder().decode(GestureAction.self, from: data),
        action
      )
    }
  }

  func testCustomWindowFrameValidation() {
    XCTAssertTrue(NormalizedWindowFrame().isValid)
    XCTAssertFalse(
      NormalizedWindowFrame(
        x: 0.8,
        y: 0,
        width: 0.4,
        height: 1
      ).isValid
    )
    XCTAssertFalse(
      NormalizedWindowFrame(
        x: .nan,
        y: 0,
        width: 0.5,
        height: 0.5
      ).isValid
    )
  }

  func testOpenPathRequiresAnAbsoluteOrHomeRelativePath() {
    XCTAssertTrue(GestureAction.openPath("/Applications").isValid)
    XCTAssertTrue(GestureAction.openPath("~").isValid)
    XCTAssertTrue(GestureAction.openPath("~/Downloads").isValid)
    XCTAssertFalse(GestureAction.openPath("Downloads").isValid)
    XCTAssertFalse(GestureAction.openPath("").isValid)
  }
}
