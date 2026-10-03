import SwiftUI
import Combine

struct unipadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    @StateObject private var midiBanner = MidiBannerCoordinator()
    @StateObject private var modelStoreStatus: ModelStoreStatus
    @ObservedObject private var workspaceManager = WorkspaceManager.shared

    init() {
        let opened = ModelContainerFactory.make()
        _modelStoreStatus = StateObject(
            wrappedValue: ModelStoreStatus(
                openError: opened.persistentStoreError
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if workspaceManager.hasConfiguredWorkspace {
                    appContent
                } else {
                    StorageSetupView()
                }
            }
            .environmentObject(router)
            .environmentObject(midiBanner)
            .environmentObject(modelStoreStatus)
            .preferredColorScheme(.dark)
        }
    }

    private var appContent: some View {
        ZStack {
            NavigationView {
                routedView
            }
            .navigationViewStyle(StackNavigationViewStyle())

            if router.showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if midiBanner.isVisible {
                MidiConnectionBannerView(
                    message: midiBanner.message,
                    onOpen: {
                        midiBanner.openMidiPanel(router: router)
                    },
                    onDismiss: {
                        midiBanner.dismiss()
                    }
                )
                .padding(.top, 16)
                .transition(
                    .move(edge: .top)
                    .combined(with: .opacity)
                )
            }
        }
        .overlay(alignment: .bottom) {
            if modelStoreStatus.showsNotice,
               !router.showSplash,
               router.currentRoute == .main {
                TemporaryStoreNoticeView {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        modelStoreStatus.dismissNotice()
                    }
                }
                .padding(.bottom, 16)
                .transition(
                    .move(edge: .bottom)
                    .combined(with: .opacity)
                )
            }
        }
        .onOpenURL { url in
            router.handleDeepLink(url)
        }
        .onAppear {
            midiBanner.start()
            modelStoreStatus.reportIfNeeded(
                to: FirebaseManager.shared.crashlytics
            )
        }
        .onReceive(
            MidiManager.shared.$isConnected.removeDuplicates()
        ) { connected in
            midiBanner.handleConnectionStateChanged(
                connected,
                scenePhase: scenePhase,
                router: router
            )
        }
        .onChange(of: scenePhase) { newPhase in
            midiBanner.handleScenePhaseChanged(
                newPhase,
                router: router
            )
        }
    }

    @ViewBuilder
    private var routedView: some View {
        switch router.currentRoute {
        case .main:
            MainView()
        case .play(let path):
            PlayView(packPath: path)
        case .store:
            StoreView()
        case .settings:
            SettingsView()
        case .settingsStorage:
            SettingsView(initialCategory: .storage)
        case .theme:
            ThemeView()
        case .midiSelect:
            MidiSelectView()
        case .transfer(let config):
            TransferView(config: config)
        case .importByUrl(let code):
            ImportByUrlView(code: code)
        }
    }
}
