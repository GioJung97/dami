import Foundation

/// What a complete speech model folder contains. An interrupted download can leave some of these
/// missing, and checking only one would make it look complete and fail forever.
public enum ModelFiles {
    public static let required = [
        "AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc", "TextDecoderContextPrefill.mlmodelc",
        "config.json", "generation_config.json",
    ]

    public static func isComplete(exists: (String) -> Bool) -> Bool {
        required.allSatisfy(exists)
    }
}

public enum ProcessingLimits {
    /// A dictation that takes longer than this to process has probably hung.
    public static func timeout(audioSeconds: Double) -> TimeInterval {
        max(30, audioSeconds)
    }
}
