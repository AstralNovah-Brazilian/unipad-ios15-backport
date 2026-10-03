import SwiftUI

enum DeviceIcon {
    case asset(String)
    case system(String)
}

@MainActor
struct MidiSelectView: View {
    @EnvironmentObject private var router: AppRouter

    @State private var selectedIndex = 0
    @State private var isConnected = false
    @State private var remainingSeconds: Int?
    @State private var autorunTask: Task<Void, Never>?
    @State private var midiListener = MidiSelectListener()

    private let midiDevices: [MidiDevice] = [
        MidiDevice(id: 0, name: NSLocalizedString("midi_lp_s", comment: ""), icon: .asset("midi_lp_s"), makeDriver: { LaunchpadSDriver() }),
        MidiDevice(id: 1, name: NSLocalizedString("midi_lp_mk2", comment: ""), icon: .asset("midi_lp_mk2"), makeDriver: { LaunchpadMK2Driver() }),
        MidiDevice(id: 2, name: NSLocalizedString("midi_lp_pro", comment: ""), icon: .asset("midi_lp_pro"), makeDriver: { LaunchpadProDriver() }),
        MidiDevice(id: 3, name: NSLocalizedString("midi_lp_x", comment: ""), icon: .asset("midi_lp_x"), makeDriver: { LaunchpadXDriver() }),
        MidiDevice(id: 4, name: NSLocalizedString("midi_lp_mini_mk3", comment: ""), icon: .asset("midi_lp_mini_mk3"), makeDriver: { LaunchpadMiniMK3Driver() }),
        MidiDevice(id: 5, name: NSLocalizedString("midi_lp_mk3", comment: ""), icon: .asset("midi_lp_mk3"), makeDriver: { LaunchpadProMK3Driver() }),
        MidiDevice(id: 6, name: NSLocalizedString("midi_midi_fighter", comment: ""), icon: .asset("midi_midifighter"), makeDriver: { MidiFighterDriver() }),
        MidiDevice(id: 7, name: NSLocalizedString("midi_matrix", comment: ""), icon: .asset("midi_matrix"), makeDriver: { MatrixDriver() }),
        MidiDevice(id: 8, name: NSLocalizedString("midi_master_keyboard", comment: ""), icon: .system("pianokeys"), makeDriver: { MasterKeyboardDriver() }),
        MidiDevice(id: 9, name: NSLocalizedString("midi_lp_pro_cfw", comment: ""), icon: .asset("midi_lp_pro"), makeDriver: { LaunchpadProCFWDriver() }),
        MidiDevice(id: 10, name: NSLocalizedString("midi_lp_core_cfw", comment: ""), icon: .asset("midi_lp_pro"), makeDriver: { LaunchpadCoreCFWDriver() })
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                leftPanel
                    .frame(width: geometry.size.width * 0.35)

                deviceGrid
                    .frame(width: geometry.size.width * 0.65)
            }
        }
        .background(AppColors.background1)
        .platformNavigationBarHidden(true)
        .onAppear {
            restoreSelection()
            bindMidiListener()
            isConnected = MidiManager.shared.isConnected
            startAutorunTimer()
        }
        .onDisappear {
            cancelAutorun()
            midiListener.clearHandlers()

            if MidiManager.shared.listener === midiListener {
                MidiManager.shared.listener = nil
            }
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Text(
                isConnected
                    ? NSLocalizedString("launchpadConnecting", comment: "")
                    : NSLocalizedString("midiDevicesNotDetected", comment: "")
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isConnected ? AppColors.textPrimary : AppColors.red)
            .padding(.top, 20)

            Spacer().frame(height: 12)

            VStack(spacing: 8) {
                if let selectedDevice = midiDevices.first(where: { $0.id == selectedIndex }) {
                    deviceIcon(selectedDevice.icon, large: true)

                    Text(selectedDevice.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.vertical, 16)
            .animation(.easeInOut(duration: 0.3), value: selectedIndex)

            Spacer().frame(height: 16)

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
                .padding(.horizontal, 20)

            Spacer()

            Button {
                cancelAutorun()
                applySelection()
                router.pop()
            } label: {
                HStack {
                    Text("OK")

                    if let seconds = remainingSeconds {
                        Text("(\(seconds))")
                            .font(.system(size: 12))
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(AppColors.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func deviceIcon(_ icon: DeviceIcon, large: Bool) -> some View {
        switch icon {
        case .asset(let name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: large ? 120 : 48)
                .clipShape(RoundedRectangle(cornerRadius: large ? 8 : 0))

        case .system(let systemName):
            Image(systemName: systemName)
                .font(.system(size: large ? 80 : 34))
                .foregroundColor(AppColors.blue)
                .frame(height: large ? 120 : 48)
        }
    }

    // MARK: - Device Grid

    private var deviceGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 100, maximum: 160),
                        spacing: 12
                    )
                ],
                spacing: 12
            ) {
                ForEach(midiDevices) { device in
                    DeviceCardView(
                        device: device,
                        isSelected: device.id == selectedIndex
                    ) {
                        cancelAutorun()
                        selectedIndex = device.id
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func restoreSelection() {
        if let activeDevice = midiDevices.first(where: {
            type(of: $0.makeDriver()) == type(of: MidiManager.shared.driver)
        }) {
            selectedIndex = activeDevice.id
        } else {
            selectedIndex = min(
                max(PreferenceManager.shared.launchpadConnectMethod, 0),
                midiDevices.count - 1
            )
        }
    }

    private func applySelection() {
        PreferenceManager.shared.launchpadConnectMethod = selectedIndex

        guard let device = midiDevices.first(where: { $0.id == selectedIndex }) else { return }
        MidiManager.shared.overrideDriver(device.makeDriver())
    }

    private func startAutorunTimer() {
        cancelAutorun()
        remainingSeconds = 5

        autorunTask = Task { @MainActor in
            while let seconds = remainingSeconds, seconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled, let current = remainingSeconds else { return }
                remainingSeconds = current - 1
            }

            guard !Task.isCancelled, remainingSeconds == 0 else { return }
            applySelection()
            router.pop()
            autorunTask = nil
        }
    }

    private func cancelAutorun() {
        autorunTask?.cancel()
        autorunTask = nil
        remainingSeconds = nil
    }

    private func bindMidiListener() {
        midiListener.connectedHandler = {
            isConnected = true
        }

        midiListener.disconnectedHandler = {
            isConnected = false
        }

        midiListener.driverChangeHandler = { driver in
            if let device = midiDevices.first(where: {
                type(of: $0.makeDriver()) == type(of: driver)
            }) {
                selectedIndex = device.id
            }
        }

        MidiManager.shared.listener = midiListener
    }
}

// MARK: - Data

struct MidiDevice: Identifiable {
    let id: Int
    let name: String
    let icon: DeviceIcon
    let makeDriver: () -> MidiDriver
}

private final class MidiSelectListener: MidiManagerListener {
    var connectedHandler: (() -> Void)?
    var disconnectedHandler: (() -> Void)?
    var driverChangeHandler: ((MidiDriver) -> Void)?
    var logHandler: ((String) -> Void)?

    func onConnected() {
        connectedHandler?()
    }

    func onDisconnected() {
        disconnectedHandler?()
    }

    func onChangeDriver(driver: MidiDriver) {
        driverChangeHandler?(driver)
    }

    func onLog(_ message: String) {
        logHandler?(message)
    }

    func clearHandlers() {
        connectedHandler = nil
        disconnectedHandler = nil
        driverChangeHandler = nil
        logHandler = nil
    }
}

// MARK: - Device Card

private struct DeviceCardView: View {
    let device: MidiDevice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                switch device.icon {
                case .asset(let name):
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 48)
                        .opacity(isSelected ? 1.0 : 0.6)

                case .system(let systemName):
                    Image(systemName: systemName)
                        .font(.system(size: 34))
                        .foregroundColor(isSelected ? AppColors.blue : AppColors.textPrimary.opacity(0.6))
                        .frame(height: 48)
                }

                Text(device.name)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(minHeight: 30)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AppColors.darkSurface : AppColors.darkSurfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppColors.blue : Color.clear, lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.3), value: isSelected)
        }
    }
}

struct MidiSelectView_Previews: PreviewProvider {
    static var previews: some View {
        MidiSelectView()
            .environmentObject(AppRouter())
            .preferredColorScheme(.dark)
    }
}
