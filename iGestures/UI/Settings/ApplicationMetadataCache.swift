import AppKit

@MainActor
final class ApplicationMetadataCache {
  struct Metadata {
    let displayName: String
    let icon: NSImage
  }

  static let shared = ApplicationMetadataCache()

  private var metadataByBundleIdentifier: [String: Metadata] = [:]

  private init() {}

  func metadata(for bundleIdentifier: String) -> Metadata? {
    if let cached = metadataByBundleIdentifier[bundleIdentifier] {
      return cached
    }

    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )
    else {
      return nil
    }

    let metadata = Metadata(
      displayName:
        applicationURL.deletingPathExtension().lastPathComponent,
      icon: NSWorkspace.shared.icon(forFile: applicationURL.path)
    )
    metadataByBundleIdentifier[bundleIdentifier] = metadata
    return metadata
  }
}
