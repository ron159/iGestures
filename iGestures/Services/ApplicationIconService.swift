import AppKit
import Foundation

public enum ApplicationIconChoice:
  String,
  CaseIterable,
  Codable,
  Identifiable,
  Sendable
{
  case systemDefault = "default"
  case lightWave = "light-wave"
  case gestureRunner = "gesture-runner"
  case gestureThinker = "gesture-thinker"
  case purpleMouse = "purple-mouse"

  public var id: String { rawValue }

  var resourceName: String? {
    switch self {
    case .systemDefault:
      nil
    case .lightWave:
      "AppIcon-LightWave"
    case .gestureRunner:
      "AppIcon-GestureRunner"
    case .gestureThinker:
      "AppIcon-GestureThinker"
    case .purpleMouse:
      "AppIcon-PurpleMouse"
    }
  }
}

@MainActor
protocol ApplicationIconApplying: AnyObject {
  func image(for choice: ApplicationIconChoice) -> NSImage?

  @discardableResult
  func apply(_ choice: ApplicationIconChoice) -> Bool
}

@MainActor
final class ApplicationIconService: ApplicationIconApplying {
  private let defaultIconImage: NSImage
  private let imageLoader: (String) -> NSImage?
  private let applyImage: (NSImage?) -> Void
  private var imageCache: [ApplicationIconChoice: NSImage] = [:]

  convenience init(
    bundle: Bundle = .main,
    application: NSApplication = .shared
  ) {
    let applicationIconImage =
      application.applicationIconImage
      ?? NSImage(size: NSSize(width: 128, height: 128))
    let defaultIconImage =
      applicationIconImage.copy() as? NSImage
      ?? applicationIconImage
    self.init(
      defaultIconImage: defaultIconImage,
      imageLoader: { resourceName in
        guard
          let resourceURL = bundle.url(
            forResource: resourceName,
            withExtension: "icns"
          )
        else {
          return nil
        }
        return NSImage(contentsOf: resourceURL)
      },
      applyImage: { image in
        application.applicationIconImage = image
      }
    )
  }

  init(
    defaultIconImage: NSImage,
    imageLoader: @escaping (String) -> NSImage?,
    applyImage: @escaping (NSImage?) -> Void
  ) {
    self.defaultIconImage = defaultIconImage
    self.imageLoader = imageLoader
    self.applyImage = applyImage
  }

  func image(for choice: ApplicationIconChoice) -> NSImage? {
    guard let resourceName = choice.resourceName else {
      return defaultIconImage
    }
    if let cachedImage = imageCache[choice] {
      return cachedImage
    }
    guard let image = imageLoader(resourceName) else {
      return nil
    }
    imageCache[choice] = image
    return image
  }

  @discardableResult
  func apply(_ choice: ApplicationIconChoice) -> Bool {
    guard choice != .systemDefault else {
      applyImage(nil)
      return true
    }
    guard let image = image(for: choice) else {
      return false
    }
    applyImage(image)
    return true
  }
}
