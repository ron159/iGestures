public enum EventSourceMarker {
  public static let syntheticEventUserData: Int64 = 0x4D_47_56_4E_45_58_54

  public static func isSynthetic(_ userData: Int64) -> Bool {
    userData == syntheticEventUserData
  }
}
