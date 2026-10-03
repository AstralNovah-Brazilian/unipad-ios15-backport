import SwiftUI

struct TemporaryStoreNoticeView: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.orange)

            Text(NSLocalizedString("temporary_store_notice", comment: ""))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(
                NSLocalizedString("temporary_store_notice_dismiss", comment: "")
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.darkSurfaceHigh)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppColors.orange.opacity(0.6), lineWidth: 1)
        )
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}
