import AppKit

/// Cuelume's Success recipe, rendered locally into a bundled WAV.
/// See scripts/render-success-sound.py and Resources/Cuelume-LICENSE.txt.
@MainActor
final class CompletionSound {
    static let shared = CompletionSound()

    private lazy var sound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "Success", withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false)
        else { return nil }
        // Relative to the original recipe; respects the user's system volume.
        sound.volume = 0.35
        return sound
    }()

    private init() {}

    func play() {
        guard let sound else { return }
        // Reuse the sound and avoid stacking chimes on rapid regeneration.
        sound.stop()
        sound.play()
    }
}
