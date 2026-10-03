#if canImport(UIKit)
import MediaPlayer

@MainActor
enum MPVolumeViewHelper {
    private static let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: .zero)
        view.isHidden = true
        return view
    }()

    static func setVolume(_ volume: Float) {
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = min(max(volume, 0), 1)
    }
}
#endif
