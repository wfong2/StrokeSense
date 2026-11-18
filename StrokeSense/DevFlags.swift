/// Temporary switches for testing. Set all back to false before shipping.
enum DevFlags {
    /// Skip the arm step in both baseline and check flows.
    static let skipArms = false
    /// Skip the speech step in both baseline and check flows.
    /// Speech results fall back to placeholder values.
    static let skipSpeech = true
    /// Show a participant code and a normal / simulated-drift label on the arm
    /// hold screen, saved with each recording as training data
    /// (training/arm_classifier).
    static let armDataCollection = true
}
