/// Temporary switches for testing. Set back to false before shipping.
enum DevFlags {
    /// Skip the arm and speech steps in both baseline and check flows.
    /// Arm and speech results fall back to placeholder values.
    static let faceOnly = true
}
