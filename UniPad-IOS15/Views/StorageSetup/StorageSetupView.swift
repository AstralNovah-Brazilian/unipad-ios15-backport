import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

@MainActor
struct StorageSetupView: View {
    @StateObject private var vm = StorageSetupViewModel()
    @State private var showFolderPicker = false

    var body: some View {
        ZStack {
            AppColors.background1
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.blue)

                VStack(spacing: 8) {
                    Text("Choose UniPack Folder")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Choose where UniPad should save and load your UniPacks.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if vm.isReady {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.selectedFolderName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(vm.selectedFolderPath)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(16)
                    .background(AppColors.darkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    #if canImport(UIKit)
                    showFolderPicker = true
                    #endif
                } label: {
                    Text(vm.isReady ? "Change Folder" : "Choose Folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(AppColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                Spacer()
            }
            .padding(24)
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showFolderPicker) {
            StorageFolderPicker { url in
                vm.selectFolder(url)
            }
        }
        #endif
    }
}

#if canImport(UIKit)
private struct StorageFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#endif
