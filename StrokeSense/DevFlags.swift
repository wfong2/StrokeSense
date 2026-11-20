/// Temporary switches for testing. All false for normal use and demos.
enum DevFlags {
    /// Skip the face step in both baseline and check flows.
    static let skipFace = false
    /// Skip the arm step in both baseline and check flows.
    static let skipArms = false
    /// Skip the speech step in both baseline and check flows.
    static let skipSpeech = false
    /// Show a participant code and a training label (normal / simulated) on
    /// the arm and speech screens, saved with each recording as training data
    /// (training/arm_classifier, training/speech_classifier).
    static let dataCollection = false
}
