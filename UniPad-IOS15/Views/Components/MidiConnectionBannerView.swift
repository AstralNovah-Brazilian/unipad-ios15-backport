import SwiftUI

struct MidiConnectionBannerView: View {
    let message: String
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pianokeys.inverse")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(NSLocalizedString("midi_open_panel", comment: ""), action: onOpen)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.blue)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.88))
        .clipShape(Capsule())
        .padding(.horizontal, 20)
    }
}
