import CoreGraphics
import Foundation

public enum ActionPresetCategory:
  String,
  Codable,
  CaseIterable,
  Sendable
{
  case window
  case browser
  case website
  case finder
  case appDesktop
  case editing
  case mediaSystem
  case automation
}

public enum ActionPresetScopeHint:
  String,
  Codable,
  Sendable
{
  case allApplications
  case browsers
  case finder
}

public struct ActionPreset:
  Codable,
  Hashable,
  Identifiable,
  Sendable
{
  public let id: String
  public var name: String
  public var summary: String
  public var category: ActionPresetCategory
  public var action: GestureAction
  public var keywords: [String]
  public var scopeHint: ActionPresetScopeHint
  public var isUserDefined: Bool

  public init(
    id: String,
    name: String,
    summary: String = "",
    category: ActionPresetCategory,
    action: GestureAction,
    keywords: [String] = [],
    scopeHint: ActionPresetScopeHint = .allApplications,
    isUserDefined: Bool = false
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.category = category
    self.action = action
    self.keywords = keywords
    self.scopeHint = scopeHint
    self.isUserDefined = isUserDefined
  }

  public var isValid: Bool {
    let normalizedID = id.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let normalizedName = name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return !normalizedID.isEmpty
      && normalizedID.utf8.count <= 160
      && !normalizedName.isEmpty
      && normalizedName.utf8.count <= 120
      && summary.utf8.count <= 500
      && keywords.count <= 20
      && keywords.allSatisfy { $0.utf8.count <= 80 }
      && action.isValid
  }

  public func matches(_ query: String) -> Bool {
    let normalized = query.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalized.isEmpty else { return true }
    return ([id, name, summary] + keywords).contains {
      $0.localizedCaseInsensitiveContains(normalized)
    }
  }
}

public enum ActionPresetLibrary {
  private static let command = CGEventFlags.maskCommand.rawValue
  private static let shift = CGEventFlags.maskShift.rawValue
  private static let control = CGEventFlags.maskControl.rawValue

  public static let builtIn: [ActionPreset] =
    windowPresets
    + browserPresets
    + websitePresets
    + finderPresets
    + appDesktopPresets
    + editingPresets
    + mediaSystemPresets
    + automationPresets

  public static func matching(
    _ query: String,
    in presets: [ActionPreset] = builtIn
  ) -> [ActionPreset] {
    presets.filter { $0.matches(query) }
  }

  private static let windowPresets: [ActionPreset] = [
    window("window.left-half", "Left Half", .leftHalf),
    window("window.right-half", "Right Half", .rightHalf),
    window("window.top-half", "Top Half", .topHalf),
    window("window.bottom-half", "Bottom Half", .bottomHalf),
    window("window.top-left", "Top Left Quarter", .topLeftQuarter),
    window("window.top-right", "Top Right Quarter", .topRightQuarter),
    window(
      "window.bottom-left",
      "Bottom Left Quarter",
      .bottomLeftQuarter
    ),
    window(
      "window.bottom-right",
      "Bottom Right Quarter",
      .bottomRightQuarter
    ),
    window("window.left-third", "Left Third", .leftThird),
    window("window.center-third", "Center Third", .centerThird),
    window("window.right-third", "Right Third", .rightThird),
    window(
      "window.left-two-thirds",
      "Left Two Thirds",
      .leftTwoThirds
    ),
    window(
      "window.right-two-thirds",
      "Right Two Thirds",
      .rightTwoThirds
    ),
    window("window.center", "Center Window", .center),
    window("window.maximize", "Maximize Window", .maximize),
    window(
      "window.maximize-height",
      "Maximize Window Height",
      .maximizeHeight
    ),
    window(
      "window.maximize-width",
      "Maximize Window Width",
      .maximizeWidth
    ),
    window("window.close", "Close Window", .close),
    window("window.minimize", "Minimize Window", .minimize),
    window(
      "window.full-screen",
      "Enter or Exit Full Screen",
      .toggleFullScreen
    ),
    window(
      "window.previous-display",
      "Move to Previous Display",
      .previousDisplay
    ),
    window(
      "window.next-display",
      "Move to Next Display",
      .nextDisplay
    ),
    window(
      "window.restore-frame",
      "Restore Previous Window Position",
      .restorePreviousFrame
    ),
    ActionPreset(
      id: "window.custom",
      name: String(localized: "Custom Window Size and Position"),
      summary: String(
        localized: "Place the window using custom screen proportions."
      ),
      category: .window,
      action: .customWindow(NormalizedWindowFrame()),
      keywords: ["window", "layout", "size", "position"]
    ),
  ]

  private static let browserPresets: [ActionPreset] = [
    shortcut(
      "browser.back",
      "Back",
      .browser,
      33,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.forward",
      "Forward",
      .browser,
      30,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.new-tab",
      "New Tab",
      .browser,
      17,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.close-tab",
      "Close Tab",
      .browser,
      13,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.refresh",
      "Refresh",
      .browser,
      15,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.previous-tab",
      "Previous Tab",
      .browser,
      48,
      control | shift,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.next-tab",
      "Next Tab",
      .browser,
      48,
      control,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.reopen-tab",
      "Reopen Closed Tab",
      .browser,
      17,
      command | shift,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.address-bar",
      "Focus Address Bar",
      .browser,
      37,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.page-top",
      "Go to Page Top",
      .browser,
      126,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.page-bottom",
      "Go to Page Bottom",
      .browser,
      125,
      command,
      scopeHint: .browsers
    ),
    shortcut(
      "browser.find",
      "Find on Page",
      .browser,
      3,
      command,
      scopeHint: .browsers
    ),
  ]

  private static let websitePresets: [ActionPreset] = [
    website(
      "website.google",
      "Google",
      "https://www.google.com/",
      keywords: ["search", "谷歌"]
    ),
    website(
      "website.bing",
      "Bing",
      "https://www.bing.com/",
      keywords: ["search", "microsoft", "必应"]
    ),
    website(
      "website.chatgpt",
      "ChatGPT",
      "https://chatgpt.com/",
      keywords: ["ai", "openai"]
    ),
    website(
      "website.claude",
      "Claude",
      "https://claude.ai/",
      keywords: ["ai", "anthropic"]
    ),
    website(
      "website.gemini",
      "Gemini",
      "https://gemini.google.com/",
      keywords: ["ai", "google"]
    ),
    website(
      "website.perplexity",
      "Perplexity",
      "https://www.perplexity.ai/",
      keywords: ["ai", "search"]
    ),
    website("website.github", "GitHub", "https://github.com/"),
    website(
      "website.stack-overflow",
      "Stack Overflow",
      "https://stackoverflow.com/",
      keywords: ["developer", "questions"]
    ),
    website(
      "website.mdn",
      "MDN Web Docs",
      "https://developer.mozilla.org/",
      keywords: ["developer", "documentation"]
    ),
    website(
      "website.youtube",
      "YouTube",
      "https://www.youtube.com/",
      keywords: ["video"]
    ),
    website(
      "website.bilibili",
      "Bilibili",
      "https://www.bilibili.com/",
      keywords: ["video", "哔哩哔哩", "B站"]
    ),
    website("website.gmail", "Gmail", "https://mail.google.com/"),
    website(
      "website.google-drive",
      "Google Drive",
      "https://drive.google.com/",
      keywords: ["files", "cloud", "云端硬盘"]
    ),
    website("website.notion", "Notion", "https://www.notion.com/"),
    website("website.figma", "Figma", "https://www.figma.com/"),
  ]

  private static let finderPresets: [ActionPreset] = [
    ActionPreset(
      id: "finder.open",
      name: String(localized: "Open Finder"),
      category: .finder,
      action: .launchApplication(bundleIdentifier: "com.apple.finder"),
      keywords: ["finder"],
      scopeHint: .finder
    ),
    shortcut(
      "finder.new-folder",
      "New Folder",
      .finder,
      45,
      command | shift,
      scopeHint: .finder
    ),
    shortcut(
      "finder.parent",
      "Go to Parent Folder",
      .finder,
      126,
      command,
      scopeHint: .finder
    ),
    shortcut(
      "finder.open-selection",
      "Open Selected Item",
      .finder,
      125,
      command,
      scopeHint: .finder
    ),
    shortcut(
      "finder.back",
      "Finder Back",
      .finder,
      33,
      command,
      scopeHint: .finder
    ),
    shortcut(
      "finder.forward",
      "Finder Forward",
      .finder,
      30,
      command,
      scopeHint: .finder
    ),
    shortcut(
      "finder.trash-selection",
      "Move Selected Items to Trash",
      .finder,
      51,
      command,
      scopeHint: .finder
    ),
    path("finder.downloads", "Open Downloads Folder", "~/Downloads"),
    path("finder.applications", "Open Applications Folder", "/Applications"),
    path("finder.home", "Open Home Folder", "~"),
    path("finder.documents", "Open Documents Folder", "~/Documents"),
    path(
      "finder.icloud",
      "Open iCloud Drive",
      "~/Library/Mobile Documents/com~apple~CloudDocs"
    ),
    shortcut(
      "finder.airdrop",
      "Open AirDrop",
      .finder,
      15,
      command | shift,
      scopeHint: .finder
    ),
    shortcut(
      "finder.go-to-folder",
      "Go to Folder",
      .finder,
      5,
      command | shift,
      scopeHint: .finder
    ),
    shortcut(
      "finder.connect-server",
      "Connect to Server",
      .finder,
      40,
      command,
      scopeHint: .finder
    ),
  ]

  private static let appDesktopPresets: [ActionPreset] = [
    shortcut("app.hide", "Hide Current Application", .appDesktop, 4, command),
    shortcut("app.quit", "Quit Current Application", .appDesktop, 12, command),
    system(
      "system.force-quit",
      "Force Quit Applications",
      .forceQuit,
      category: .appDesktop
    ),
    system(
      "system.app-switcher",
      "Application Switcher",
      .appSwitcher,
      category: .appDesktop
    ),
    system(
      "system.spotlight",
      "Spotlight Search",
      .spotlight,
      category: .appDesktop
    ),
    system(
      "system.launchpad",
      "Launchpad",
      .launchpad,
      category: .appDesktop
    ),
    system(
      "desktop.mission-control",
      "Mission Control",
      .missionControl,
      category: .appDesktop
    ),
    system(
      "desktop.show",
      "Show Desktop",
      .showDesktop,
      category: .appDesktop
    ),
    system(
      "desktop.previous",
      "Previous Desktop",
      .previousSpace,
      category: .appDesktop
    ),
    system(
      "desktop.next",
      "Next Desktop",
      .nextSpace,
      category: .appDesktop
    ),
    ActionPreset(
      id: "system.settings",
      name: String(localized: "Open System Settings"),
      category: .appDesktop,
      action: .launchApplication(
        bundleIdentifier: "com.apple.systempreferences"
      ),
      keywords: ["settings", "preferences"]
    ),
  ]

  private static let editingPresets: [ActionPreset] = [
    shortcut("editing.undo", "Undo", .editing, 6, command),
    shortcut("editing.redo", "Redo", .editing, 6, command | shift),
    shortcut("editing.cut", "Cut", .editing, 7, command),
    shortcut("editing.copy", "Copy", .editing, 8, command),
    shortcut("editing.paste", "Paste", .editing, 9, command),
    shortcut("editing.select-all", "Select All", .editing, 0, command),
    shortcut("editing.save", "Save", .editing, 1, command),
    shortcut("editing.find", "Find", .editing, 3, command),
    shortcut("editing.escape", "Escape", .editing, 53, 0),
    ActionPreset(
      id: "editing.type-text",
      name: String(localized: "Type Fixed Text"),
      summary: String(
        localized: "Type a non-sensitive phrase into the active field."
      ),
      category: .editing,
      action: .typeText(String(localized: "Replace with your text")),
      keywords: ["text", "phrase", "input"]
    ),
    ActionPreset(
      id: "editing.application-menu",
      name: String(localized: "Choose Application Menu Item"),
      summary: String(
        localized: "Run an application menu item by its menu path."
      ),
      category: .editing,
      action: .applicationMenu(
        ApplicationMenuAction(
          path: [
            String(localized: "Application"),
            String(localized: "Menu Item"),
          ]
        )
      ),
      keywords: ["menu", "command"]
    ),
  ]

  private static let mediaSystemPresets: [ActionPreset] = [
    system("system.lock", "Lock Screen", .lockScreen),
    system("system.sleep", "Sleep", .sleep),
    system(
      "system.screenshot-full",
      "Capture Entire Screen",
      .screenshotFullScreen
    ),
    system(
      "system.screenshot-selection",
      "Capture Screen Selection",
      .screenshotSelection
    ),
    system(
      "system.screenshot-toolbar",
      "Open Screenshot Toolbar",
      .screenshotToolbar
    ),
    system("media.play-pause", "Play or Pause", .playPause),
    system("media.previous", "Previous Track", .previousTrack),
    system("media.next", "Next Track", .nextTrack),
    system("media.volume-up", "Volume Up", .volumeUp),
    system("media.volume-down", "Volume Down", .volumeDown),
    system("media.mute", "Mute", .mute),
    system("display.brightness-up", "Brightness Up", .brightnessUp),
    system("display.brightness-down", "Brightness Down", .brightnessDown),
    system("editing.emoji", "Emoji and Symbols", .emojiPicker),
  ]

  private static let automationPresets: [ActionPreset] =
    BuiltInScriptLibrary.items.enumerated().map { index, item in
      ActionPreset(
        id: "automation.\(index + 1)",
        name: item.name,
        summary: item.summary,
        category: .automation,
        action: .script(item.script),
        keywords: ["script", "automation"]
      )
    }

  private static func shortcut(
    _ id: String,
    _ name: String.LocalizationValue,
    _ category: ActionPresetCategory,
    _ keyCode: UInt16,
    _ modifiers: UInt64,
    scopeHint: ActionPresetScopeHint = .allApplications
  ) -> ActionPreset {
    ActionPreset(
      id: id,
      name: String(localized: name),
      category: category,
      action: .keyboardShortcut(
        KeyboardShortcut(
          keyCode: keyCode,
          modifiers: modifiers
        )
      ),
      keywords: ["keyboard", "shortcut"],
      scopeHint: scopeHint
    )
  }

  private static func window(
    _ id: String,
    _ name: String.LocalizationValue,
    _ action: WindowGestureAction
  ) -> ActionPreset {
    ActionPreset(
      id: id,
      name: String(localized: name),
      category: .window,
      action: .window(action),
      keywords: ["window", "layout"]
    )
  }

  private static func website(
    _ id: String,
    _ name: String.LocalizationValue,
    _ url: String,
    keywords: [String] = []
  ) -> ActionPreset {
    ActionPreset(
      id: id,
      name: String(localized: name),
      category: .website,
      action: .openURL(url),
      keywords: ["website", "web"] + keywords
    )
  }

  private static func system(
    _ id: String,
    _ name: String.LocalizationValue,
    _ action: SystemGestureAction,
    category: ActionPresetCategory = .mediaSystem
  ) -> ActionPreset {
    ActionPreset(
      id: id,
      name: String(localized: name),
      category: category,
      action: .system(action),
      keywords: ["system"]
    )
  }

  private static func path(
    _ id: String,
    _ name: String.LocalizationValue,
    _ value: String
  ) -> ActionPreset {
    ActionPreset(
      id: id,
      name: String(localized: name),
      category: .finder,
      action: .openPath(value),
      keywords: ["finder", "folder"],
      scopeHint: .finder
    )
  }
}
