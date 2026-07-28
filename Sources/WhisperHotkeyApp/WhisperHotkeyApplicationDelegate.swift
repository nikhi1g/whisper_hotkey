@preconcurrency import AVFoundation
import AppKit
import Foundation
import OSLog
import WhisperHotkeyASR
import WhisperHotkeyCore
import WhisperHotkeyShell
import WhisperHotkeySystem

@MainActor
final class WhisperHotkeyApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let maximumDuration: Duration = .seconds(600)
    private static let errorPresentationDuration: Duration = .seconds(2)

    private struct PendingRecognizerWork {
        let precedingCleanup: Task<Void, Never>?
        let preload: Task<Void, Never>?
        let recognition: Task<Void, Never>?
    }

    private let logger = Logger(
        subsystem: WhisperHotkeyPaths.bundleIdentifier,
        category: "lifecycle"
    )
    private let recorder = WhisperAudioRecorder()
    private let recognizer = WhisperRecognizer()
    private let targetProvider = AccessibilityTargetProvider()
    private let clipboard = ClipboardTransactionController()
    private let badge = CaretBadgeController()
    private let loginItemManager = LoginItemManager()
    private var toggleDictationEnabled = UserDefaults.standard.bool(
        forKey: "toggleDictationEnabled"
    )

    private lazy var delivery = TextDeliveryService(clipboard: clipboard)
    private lazy var hotkeyMonitor = GlobalHotkeyMonitor(
        targetProvider: targetProvider
    ) { [weak self] action, releaseTarget, timestampNanoseconds in
        self?.handleHotkey(
            action,
            releaseTarget: releaseTarget,
            eventTime: TimeInterval(timestampNanoseconds) / 1_000_000_000
        )
    }
    private lazy var setupWindowController = SetupWindowController(
        readinessProvider: { [weak self] in
            self?.setupReadiness ?? Self.unavailableReadiness
        },
        actions: SetupActions(
            requestMicrophone: { [weak self] in
                self?.requestMicrophonePermission()
            },
            openAccessibilitySettings: { [weak self] in
                self?.requestAccessibilityPermission()
            },
            openInputMonitoringSettings: { [weak self] in
                self?.requestInputMonitoringPermission()
            },
            revealModelLocation: { [weak self] in
                self?.revealModelLocation()
            },
            revealHelperLocation: { [weak self] in
                self?.revealHelperLocation()
            }
        ),
        loginItemManager: loginItemManager
    )
    private lazy var menuBarController = MenuBarController(
        toggleDictationEnabled: toggleDictationEnabled,
        actions: MenuBarActions(
            showSetup: { [weak self] in
                guard let self else {
                    return
                }
                _ = self.setupWindowController.showIfNeeded(force: true)
                self.reconcileRuntime(showSetupIfNeeded: false)
            },
            cancelDictation: { [weak self] in
                self?.process(.cancel)
            },
            toggleDictationMode: { [weak self] in
                self?.toggleDictationMode()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
    )

    private var machine = DictationStateMachine()
    private var controlServer: ControlServer?
    private var preloadTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var maximumDurationTask: Task<Void, Never>?
    private var errorPresentationTask: Task<Void, Never>?
    private var recognizerCleanupTask: Task<Void, Never>?
    private var scheduledTerminationTask: Task<Void, Never>?
    private var releaseTarget: ReleaseTarget?
    private var badgeCaretRect: CGRect?
    private var badgeFieldRect: CGRect?
    private var sessionGeneration: UInt64 = 0
    private var startupError: String?
    private var startupBadgeVisible = false
    private var runtimeReadyForHotkey = false
    private var isTerminating = false
    private var terminationCleanupStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        guard startControlServer() else {
            return
        }
        menuBarController.update(
            .starting,
            toggleDictationEnabled: toggleDictationEnabled
        )
        reconcileRuntime(showSetupIfNeeded: true)
        logger.info("Agent started")
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !terminationCleanupStarted else {
            return .terminateLater
        }
        terminationCleanupStarted = true
        isTerminating = true
        runtimeReadyForHotkey = false
        if machine.phase.isBusy {
            process(.cancel)
        } else {
            sessionGeneration &+= 1
        }
        let pendingWork = stopSynchronousServices()

        let recognizer = recognizer
        let logger = logger
        Task.detached(priority: .userInitiated) {
            if let precedingCleanup = pendingWork.precedingCleanup {
                await precedingCleanup.value
            }
            await recognizer.shutdown()
            if let preload = pendingWork.preload {
                await preload.value
            }
            if let recognition = pendingWork.recognition {
                await recognition.value
            }
            // A wrapper already queued at shutdown must be unable to outlive
            // the final process-group sweep.
            await recognizer.shutdown()
            logger.info("Agent stopped")
            RunLoop.main.perform(inModes: [.modalPanel]) {
                MainActor.assumeIsolated {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        _ = stopSynchronousServices()
    }

    @objc private func applicationDidBecomeActive() {
        guard !isTerminating else {
            return
        }
        reconcileRuntime(showSetupIfNeeded: false)
        setupWindowController.refresh()
    }

    private func startControlServer() -> Bool {
        let server = ControlServer(
            onResponseFlushed: { [weak self] request, response in
                guard response.ok else {
                    return
                }
                await self?.controlResponseDidFlush(request)
            }
        ) { [weak self] request in
                guard let self else {
                    return ControlResponse(
                        ok: false,
                        message: "whisper_hotkey is stopping."
                    )
                }
                return await self.handleControlRequest(request)
            }

        do {
            try server.start()
            controlServer = server
            return true
        } catch ControlTransportError.alreadyRunning {
            logger.error("Another agent owns the control socket")
            NSApp.terminate(nil)
            return false
        } catch {
            startupError = "Control service failed: \(error.localizedDescription)"
            logger.error("\(self.startupError ?? "Control service failed", privacy: .public)")
            badge.present(.error("Control service failed — see logs"))
            scheduledTerminationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                NSApp.terminate(nil)
            }
            return false
        }
    }

    private func handleControlRequest(
        _ request: ControlRequest
    ) -> ControlResponse {
        switch request.command {
        case .status:
            return ControlResponse(
                ok: true,
                message: "whisper_hotkey is running.",
                status: runtimeStatus
            )

        case .cancel:
            let wasBusy = machine.phase.isBusy
            process(.cancel)
            return ControlResponse(
                ok: true,
                message: wasBusy
                    ? "Current dictation cancelled."
                    : "No dictation is active.",
                status: runtimeStatus
            )

        case .setup:
            _ = setupWindowController.showIfNeeded(force: true)
            reconcileRuntime(showSetupIfNeeded: false)
            return ControlResponse(
                ok: true,
                message: "Setup window opened.",
                status: runtimeStatus
            )

        case .enableLogin:
            do {
                let resultingStatus = try loginItemManager.enableExplicitly()
                switch resultingStatus {
                case .enabled:
                    return ControlResponse(
                        ok: true,
                        message: "Login Item enabled.",
                        status: runtimeStatus
                    )
                case .requiresApproval:
                    return ControlResponse(
                        ok: true,
                        message: "Login Item needs approval in System Settings.",
                        status: runtimeStatus
                    )
                case .notRegistered, .notFound, .unknown:
                    return ControlResponse(
                        ok: false,
                        message: "Login Item could not be enabled (\(resultingStatus.rawValue)).",
                        status: runtimeStatus
                    )
                }
            } catch {
                return ControlResponse(
                    ok: false,
                    message: "Could not enable Login Item: \(error.localizedDescription)",
                    status: runtimeStatus
                )
            }

        case .disableLogin:
            do {
                let resultingStatus = try loginItemManager.disableExplicitly()
                switch resultingStatus {
                case .notRegistered, .notFound:
                    return ControlResponse(
                        ok: true,
                        message: "Login Item disabled.",
                        status: runtimeStatus
                    )
                case .enabled, .requiresApproval, .unknown:
                    return ControlResponse(
                        ok: false,
                        message: "Login Item could not be disabled (\(resultingStatus.rawValue)).",
                        status: runtimeStatus
                    )
                }
            } catch {
                return ControlResponse(
                    ok: false,
                    message: "Could not disable Login Item: \(error.localizedDescription)",
                    status: runtimeStatus
                )
            }

        case .stop, .restart:
            return ControlResponse(
                ok: true,
                message: request.command == .restart
                    ? "whisper_hotkey is stopping for restart."
                    : "whisper_hotkey is stopping.",
                status: runtimeStatus
            )
        }
    }

    private func controlResponseDidFlush(_ request: ControlRequest) {
        switch request.command {
        case .stop, .restart:
            // Return from the response-flush Swift task before entering
            // AppKit's synchronous termination loop. This leaves the main
            // actor available for the terminate-later reply.
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        case .status, .cancel, .setup, .enableLogin, .disableLogin:
            break
        }
    }

    private func reconcileRuntime(showSetupIfNeeded: Bool) {
        let readiness = setupReadiness
        var forceSetup = false
        if readiness.isReady {
            do {
                hotkeyMonitor.setActivationMode(hotkeyActivationMode)
                try hotkeyMonitor.start()
                runtimeReadyForHotkey = true
                startupError = nil
                if startupBadgeVisible, !machine.phase.isBusy {
                    badge.hide()
                    startupBadgeVisible = false
                }
            } catch {
                deactivateRuntime()
                startupError = "Hotkey monitor failed: \(error.localizedDescription)"
                logger.error("\(self.startupError ?? "Hotkey monitor failed", privacy: .public)")
                badge.present(.error("Hotkey unavailable — run setup"))
                startupBadgeVisible = true
                forceSetup = true
            }
        } else {
            deactivateRuntime()
        }

        if showSetupIfNeeded || !readiness.isReady || forceSetup {
            _ = setupWindowController.showIfNeeded(
                force: !readiness.isReady || forceSetup
            )
        }
        updateMenuBar()
    }

    private func handleHotkey(
        _ action: HotkeyAction,
        releaseTarget suppliedTarget: ReleaseTarget?,
        eventTime: TimeInterval
    ) {
        guard !isTerminating, runtimeReadyForHotkey else {
            return
        }

        switch action {
        case .pressed:
            if !machine.phase.isBusy, machine.phase != .failed {
                let anchor = targetProvider.currentBadgeAnchor()
                badgeCaretRect = anchor.caretRect
                badgeFieldRect = anchor.fieldRect
                releaseTarget = nil
            }
            process(.hotkeyPressed(at: eventTime))

        case .released:
            if machine.phase == .preparing || machine.phase == .listening {
                captureReleaseTarget(suppliedTarget)
            }
            process(.hotkeyReleased(at: eventTime))

        case .cancel:
            process(.cancel)
        }
    }

    private func process(_ event: DictationEvent, transcript: String? = nil) {
        let effects = machine.handle(event)
        logger.debug("Dictation phase: \(self.machine.phase.rawValue, privacy: .public)")

        for effect in effects {
            guard apply(effect, transcript: transcript) else {
                break
            }
        }
        hotkeyMonitor.synchronizeToggleSession(
            isActive: machine.phase == .preparing || machine.phase == .listening
        )
        updateMenuBar()
    }

    private func apply(
        _ effect: DictationEffect,
        transcript: String?
    ) -> Bool {
        switch effect {
        case .beginSession:
            return beginSession()

        case .finalizeRecording:
            return finalizeRecording()

        case .cancelSession:
            cancelSession()
            return true

        case .deliverTranscript:
            guard let transcript else {
                fail("Transcription result was unavailable.")
                return false
            }
            return deliver(transcript)

        case .showBadge(let presentation):
            presentBadge(presentation)
            return true
        }
    }

    private func beginSession() -> Bool {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        errorPresentationTask?.cancel()
        errorPresentationTask = nil
        maximumDurationTask?.cancel()

        let precedingCleanup = recognizerCleanupTask
        preloadTask = Task.detached(priority: .userInitiated) { [recognizer] in
            if let precedingCleanup {
                await precedingCleanup.value
            }
            guard !Task.isCancelled else {
                return
            }
            try? await recognizer.preload()
        }

        do {
            try recorder.start()
            process(.captureStarted)
        } catch {
            fail(error)
            return false
        }

        maximumDurationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.maximumDuration)
            } catch {
                return
            }
            guard let self,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  generation == sessionGeneration,
                  machine.phase == .preparing || machine.phase == .listening
            else {
                return
            }
            captureReleaseTarget(targetProvider.captureFocusedTarget())
            process(.maximumDurationReached)
        }
        return true
    }

    private func finalizeRecording() -> Bool {
        maximumDurationTask?.cancel()
        maximumDurationTask = nil

        let audio: WhisperAudioFile
        do {
            audio = try recorder.stop()
        } catch {
            fail(error)
            return false
        }

        let generation = sessionGeneration
        let precedingCleanup = recognizerCleanupTask
        let sessionPreload = preloadTask
        recognitionTask = Task { @MainActor [weak self, recognizer] in
            defer {
                audio.delete()
            }
            do {
                if let precedingCleanup {
                    await precedingCleanup.value
                }
                if let sessionPreload {
                    await sessionPreload.value
                }
                try Task.checkCancellation()
                let transcript = try await recognizer.transcribe(audio)
                guard let self,
                      runtimeReadyForHotkey,
                      !isTerminating,
                      generation == sessionGeneration,
                      machine.phase == .transcribing
                else {
                    return
                }
                preloadTask = nil
                recognitionTask = nil
                process(.transcriptReady, transcript: transcript)
            } catch is CancellationError {
                guard !Task.isCancelled,
                      let self,
                      runtimeReadyForHotkey,
                      !isTerminating,
                      generation == sessionGeneration,
                      machine.phase == .transcribing
                else {
                    return
                }
                preloadTask = nil
                recognitionTask = nil
                fail("Transcription was interrupted — try again.")
            } catch {
                guard let self,
                      runtimeReadyForHotkey,
                      !isTerminating,
                      generation == sessionGeneration,
                      machine.phase == .transcribing
                else {
                    return
                }
                preloadTask = nil
                recognitionTask = nil
                fail(error)
            }
        }
        return true
    }

    private func deliver(_ transcript: String) -> Bool {
        let result = delivery.deliver(transcript: transcript, to: releaseTarget)
        releaseTarget = nil

        switch result {
        case .inserted:
            logger.info("Dictation inserted")
            process(.deliveryFinished)
            return true

        case .clipboardUnavailable:
            fail("Clipboard unavailable — try again.")
            return false

        case .emptyTranscript:
            fail("No speech detected.")
            return false
        }
    }

    private func cancelSession() {
        sessionGeneration &+= 1
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        let cancelledPreload = preloadTask
        cancelledPreload?.cancel()
        preloadTask = nil
        let cancelledRecognition = recognitionTask
        cancelledRecognition?.cancel()
        recognitionTask = nil
        recorder.cancel()
        releaseTarget = nil

        let precedingCleanup = recognizerCleanupTask
        let recognizer = recognizer
        recognizerCleanupTask = Task.detached(priority: .userInitiated) {
            if let precedingCleanup {
                await precedingCleanup.value
            }
            await recognizer.cancel()
            if let cancelledPreload {
                await cancelledPreload.value
            }
            if let cancelledRecognition {
                await cancelledRecognition.value
            }
        }
    }

    private func fail(_ error: Error) {
        logger.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
        fail(userFacingMessage(for: error))
    }

    private func fail(_ message: String) {
        process(.failed(message))
        errorPresentationTask?.cancel()
        errorPresentationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.errorPresentationDuration)
            } catch {
                return
            }
            guard let self, machine.phase == .failed else {
                return
            }
            process(.errorPresentationFinished)
        }
    }

    private func presentBadge(_ presentation: BadgePresentation) {
        if presentation == .hidden {
            badge.hide()
            badgeCaretRect = nil
            badgeFieldRect = nil
            return
        }
        badge.present(
            presentation,
            caretFrame: badgeCaretRect,
            fieldFrame: badgeFieldRect
        )
    }

    private func captureReleaseTarget(_ target: ReleaseTarget?) {
        releaseTarget = target
        if let target {
            badgeCaretRect = target.caretRect
            badgeFieldRect = target.fieldRect
        }
    }

    private func deactivateRuntime() {
        let wasReady = runtimeReadyForHotkey
        runtimeReadyForHotkey = false
        hotkeyMonitor.stop()

        if machine.phase.isBusy {
            process(.cancel)
        } else if wasReady {
            sessionGeneration &+= 1
        }
        clipboard.completePendingRestoration()
        clipboard.cancelLease()
        updateMenuBar()
    }

    private func updateMenuBar() {
        if startupError != nil {
            menuBarController.update(
                .failed,
                toggleDictationEnabled: toggleDictationEnabled
            )
            return
        }
        guard runtimeReadyForHotkey else {
            menuBarController.update(
                .unavailable,
                toggleDictationEnabled: toggleDictationEnabled
            )
            return
        }

        let state: MenuBarState = switch machine.phase {
        case .idle:
            .idle
        case .preparing:
            .preparing
        case .listening:
            .listening
        case .transcribing:
            .transcribing
        case .inserting:
            .inserting
        case .cancelled:
            .cancelled
        case .failed:
            .failed
        }
        menuBarController.update(
            state,
            toggleDictationEnabled: toggleDictationEnabled
        )
    }

    private var hotkeyActivationMode: HotkeyActivationMode {
        toggleDictationEnabled ? .toggle : .hold
    }

    private func toggleDictationMode() {
        toggleDictationEnabled.toggle()
        UserDefaults.standard.set(
            toggleDictationEnabled,
            forKey: "toggleDictationEnabled"
        )
        hotkeyMonitor.setActivationMode(hotkeyActivationMode)
        updateMenuBar()
    }

    private func stopSynchronousServices() -> PendingRecognizerWork {
        let pendingWork = PendingRecognizerWork(
            precedingCleanup: recognizerCleanupTask,
            preload: preloadTask,
            recognition: recognitionTask
        )
        scheduledTerminationTask?.cancel()
        scheduledTerminationTask = nil
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        errorPresentationTask?.cancel()
        errorPresentationTask = nil
        preloadTask?.cancel()
        preloadTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizerCleanupTask = nil
        hotkeyMonitor.stop()
        recorder.cancel()
        badge.hide()
        clipboard.completePendingRestoration()
        clipboard.cancelLease()
        controlServer?.stop()
        controlServer = nil
        releaseTarget = nil
        return pendingWork
    }

    private var setupReadiness: SetupReadiness {
        let systemPermissions = SystemPermissionController.preflight()
        return SetupReadiness(
            microphoneGranted: microphonePermissionGranted,
            accessibilityGranted: systemPermissions.accessibility == .granted,
            inputMonitoringGranted: systemPermissions.inputMonitoring == .granted,
            modelAvailable: modelAvailable,
            helperAvailable: helperAvailable
        )
    }

    private var runtimeStatus: RuntimeStatus {
        let readiness = setupReadiness
        return RuntimeStatus(
            running: !isTerminating,
            phase: machine.phase,
            microphoneGranted: readiness.microphoneGranted,
            accessibilityGranted: readiness.accessibilityGranted,
            inputMonitoringGranted: readiness.inputMonitoringGranted,
            loginItemEnabled: loginItemManager.status.isEnabled,
            helperAvailable: readiness.helperAvailable,
            modelAvailable: readiness.modelAvailable,
            clipboardLeaseActive: delivery.clipboardLeaseActive,
            lastError: machine.lastError ?? startupError
        )
    }

    private var microphonePermissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private var modelAvailable: Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: WhisperHotkeyPaths.modelPath,
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
    }

    private var helperAvailable: Bool {
        WhisperRuntimeDiscovery.helperCandidates().contains {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            reconcileRuntime(showSetupIfNeeded: false)
            setupWindowController.refresh()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in
                    self?.reconcileRuntime(showSetupIfNeeded: false)
                    self?.setupWindowController.refresh()
                }
            }

        case .denied, .restricted:
            openSystemSettings("Privacy_Microphone")

        @unknown default:
            openSystemSettings("Privacy_Microphone")
        }
    }

    private func requestAccessibilityPermission() {
        _ = SystemPermissionController.requestAccessibility()
        openSystemSettings("Privacy_Accessibility")
    }

    private func requestInputMonitoringPermission() {
        _ = SystemPermissionController.requestInputMonitoring()
        openSystemSettings("Privacy_ListenEvent")
    }

    private func openSystemSettings(_ privacyPane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(privacyPane)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func revealModelLocation() {
        reveal(
            URL(fileURLWithPath: WhisperHotkeyPaths.modelPath),
            fallback: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/whisper", isDirectory: true)
        )
    }

    private func revealHelperLocation() {
        let candidate = WhisperRuntimeDiscovery.helperCandidates().first
            ?? Bundle.main.executableURL?.deletingLastPathComponent()
        guard let candidate else {
            return
        }
        reveal(candidate, fallback: candidate.deletingLastPathComponent())
    }

    private func reveal(_ item: URL, fallback: URL) {
        let selection = FileManager.default.fileExists(atPath: item.path)
            ? item
            : fallback
        NSWorkspace.shared.activateFileViewerSelecting([selection])
    }

    private func userFacingMessage(for error: Error) -> String {
        guard let asrError = error as? WhisperASRError else {
            return "Dictation failed — see logs."
        }
        switch asrError {
        case .noSpeech:
            return "No speech detected."
        case .modelMissing:
            return "Whisper model missing — run setup."
        case .helperUnavailable, .commandLineUnavailable:
            return "Whisper tools missing — run setup."
        case .microphoneUnavailable, .captureFailed, .noActiveRecording:
            return "Microphone failed — run setup."
        case .recognitionTimedOut:
            return "Transcription timed out."
        case .helperProtocolFailure, .helperFailed, .commandLineFailed:
            return "Transcription failed — see logs."
        }
    }

    private static let unavailableReadiness = SetupReadiness(
        microphoneGranted: false,
        accessibilityGranted: false,
        inputMonitoringGranted: false,
        modelAvailable: false,
        helperAvailable: false
    )
}
