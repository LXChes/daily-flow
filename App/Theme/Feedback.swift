import AudioToolbox

/// The optional tick sound: the soft system key click, so no audio asset ships with the app.
/// It follows the silent switch like any system sound.
enum TickSound {
    static func play() {
        AudioServicesPlaySystemSound(1104)
    }
}
