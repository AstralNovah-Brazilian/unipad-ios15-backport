import SwiftUI

struct LoadingView: View {
    var phase = ""
    var progress: Double = 0
    var detail: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("loading", comment: ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer().frame(height: 16)

            ProgressView(value: min(max(progress, 0), 1), total: 1)
                .tint(Color(hex: 0x4FC3F7))
                .background(Color(hex: 0x333333))
                .frame(maxWidth: .infinity, maxHeight: 6)

            Spacer().frame(height: 12)

            if !phase.isEmpty {
                Text(detail ?? phase)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xCCCCCC))
            }
        }
        .padding(24)
        .frame(width: 280)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
