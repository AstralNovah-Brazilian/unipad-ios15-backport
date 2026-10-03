import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)
                .font(.system(size: 16))

            TextField(placeholder, text: $text)
                .foregroundColor(AppColors.textPrimary)
                .font(.system(size: 14))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.darkSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
