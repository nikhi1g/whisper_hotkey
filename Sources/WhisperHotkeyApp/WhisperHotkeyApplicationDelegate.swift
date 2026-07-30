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
    private static let postPasteSubmitDelay: Duration = .milliseconds(80)
    private static let unavailableAdvancedSettingsState = AdvancedSettingsState(
        selectedHotkey: .rightCommand,
        activationMode: .hold,
        selectedModel: .baseEnglish,
        selectedEngine: .whisperCppMetal,
        decodingProfile: .precision,
        processingMode: .afterRecording,
        internalDictionaryEntries: [],
        recordingLimit: .minutes10,
        availableModels: [],
        availableEngines: [],
        configurationEnabled: false
    )

    private enum CompletionBehavior {
        case insert
        case insertAndSubmit
    }

    private struct PendingRecognizerWork {
        let precedingCleanup: Task<Void, Never>?
        let modelConfiguration: Task<Void, Never>?
        let preload: Task<Void, Never>?
        let recognition: Task<Void, Never>?
    }

    private let logger = Logger(
        subsystem: WhisperHotkeyPaths.bundleIdentifier,
        category: "lifecycle"
    )
    private let recorder = WhisperAudioRecorder()
    private let recognizer = WhisperRecognizer()
    private let contextProvider = AccessibilityContextProvider()
    private lazy var badgeFocusMonitor = AccessibilityFocusMonitor {
        [weak self] in
        self?.refreshBadgeAnchorAfterFocusChange()
    }
    private let clipboard = ClipboardTransactionController()
    private let loginItemManager = LoginItemManager()
    private lazy var badge = CaretBadgeController(
        actions: CaretBadgeActions(
            stopAndInsert: { [weak self] in
                self?.finishFromBadge(.insert)
            },
            sendAndSubmit: { [weak self] in
                self?.finishFromBadge(.insertAndSubmit)
            }
        ),
        theme: selectedTheme
    )
    private var selectedHotkey = HotkeyKey(
        rawValue: UserDefaults.standard.string(forKey: "dictationHotkey") ?? ""
    ) ?? .rightCommand
    private var selectedDictationMode =
        WhisperHotkeyApplicationDelegate.loadDictationMode()
    private var selectedModel = DictationModel.selected()
    private var selectedEngine = RecognitionEngine.selected()
    private var decodingProfile = DecodingProfile.selected()
    private var processingMode = ModelProcessingMode.selected()
    private var internalDictionary = InternalDictionary.selected()
    private var recordingLimit = RecordingLimit.selected()
    private var selectedTheme = BadgeTheme.selected()

    private lazy var delivery = TextDeliveryService(clipboard: clipboard)
    private lazy var hotkeyMonitor = GlobalHotkeyMonitor(
        contextProvider: contextProvider,
        shouldIgnorePointerDown: { [weak self] in
            guard let self else {
                return false
            }
            return badge.containsInteractivePoint(NSEvent.mouseLocation)
        }
    ) { [weak self] action, insertionContext, timestampNanoseconds in
        self?.handleHotkey(
            action,
            insertionContext: insertionContext,
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
    private var advancedSettingsWindowController:
        AdvancedSettingsWindowController?
    private lazy var menuBarController = MenuBarController(
        toggleDictationEnabled: effectiveToggleDictationEnabled,
        selectedHotkey: selectedHotkey,
        hasLastDictation: false,
        actions: MenuBarActions(
            showSetup: { [weak self] in
                guard let self else {
                    return
                }
                _ = self.setupWindowController.showIfNeeded(force: true)
                self.reconcileRuntime(showSetupIfNeeded: false)
            },
            showAdvancedSettings: { [weak self] in
                self?.showAdvancedSettings()
            },
            cancelDictation: { [weak self] in
                self?.process(.cancel)
            },
            copyLastDictation: { [weak self] in
                self?.copyLastDictation()
            },
            restart: { [weak self] in
                self?.restartApplication()
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
    private var recordingPresentationTask: Task<Void, Never>?
    private var cancellationPresentationTask: Task<Void, Never>?
    private var errorPresentationTask: Task<Void, Never>?
    private var submitAfterPasteTask: Task<Void, Never>?
    private var recognizerCleanupTask: Task<Void, Never>?
    private var modelConfigurationTask: Task<Void, Never>?
    private var scheduledTerminationTask: Task<Void, Never>?
    private var insertionContext: DictationInsertionContext?
    private var completionBehavior = CompletionBehavior.insert
    private var badgeCaretRect: CGRect?
    private var badgeFieldRect: CGRect?
    private var lastDictation: String?
    private var pauseSessionDidInsert = false
    private var pauseBoundaryInProgress = false
    private var pauseSessionPrompt: String?
    private var predecodeAccumulator = PredecodedTranscriptAccumulator()
    private var predecodeBoundaryInProgress = false
    private var predecodeFailed = false
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
            toggleDictationEnabled: effectiveToggleDictationEnabled,
            selectedHotkey: selectedHotkey,
            hasLastDictation: lastDictation != nil
        )
        reconcileRuntime(showSetupIfNeeded: true)
        configureModelReadiness()
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
            if let modelConfiguration = pendingWork.modelConfiguration {
                await modelConfiguration.value
            }
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
            badge.present(.error("Control service failed: see logs"))
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
                hotkeyMonitor.setHotkey(selectedHotkey)
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
                badge.present(.error("Hotkey unavailable: run setup"))
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
        insertionContext suppliedContext: DictationInsertionContext?,
        eventTime: TimeInterval
    ) {
        guard !isTerminating, runtimeReadyForHotkey else {
            return
        }

        switch action {
        case .pressed:
            if !machine.phase.isBusy, machine.phase != .failed {
                let anchor = contextProvider.currentBadgeAnchor()
                badgeCaretRect = anchor.caretRect
                badgeFieldRect = anchor.fieldRect
                insertionContext = nil
            }
            process(.hotkeyPressed(at: eventTime))

        case .released:
            if isPauseMode {
                finishFromKeyboard(.insert, insertionContext: suppliedContext)
            } else {
                if machine.phase == .preparing || machine.phase == .listening {
                    completionBehavior = .insert
                    captureInsertionContext(suppliedContext)
                }
                process(.hotkeyReleased(at: eventTime))
            }

        case .stopAndInsert:
            finishFromKeyboard(.insert, insertionContext: suppliedContext)

        case .insertAndSubmit:
            finishFromKeyboard(
                .insertAndSubmit,
                insertionContext: suppliedContext
            )

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
        if event == .cancel, machine.phase == .cancelled {
            scheduleCancellationPresentationFinished()
        }
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
        cancellationPresentationTask?.cancel()
        cancellationPresentationTask = nil
        errorPresentationTask?.cancel()
        errorPresentationTask = nil
        maximumDurationTask?.cancel()
        submitAfterPasteTask?.cancel()
        submitAfterPasteTask = nil
        completionBehavior = .insert
        pauseSessionDidInsert = false
        pauseBoundaryInProgress = false
        pauseSessionPrompt = nil
        predecodeAccumulator.reset()
        predecodeBoundaryInProgress = false
        predecodeFailed = false

        let precedingCleanup = recognizerCleanupTask
        if processingMode.keepsModelReady {
            preloadTask = Task.detached(
                priority: .userInitiated
            ) { [recognizer] in
                if let precedingCleanup {
                    await precedingCleanup.value
                }
                guard !Task.isCancelled else {
                    return
                }
                try? await recognizer.preload()
            }
        } else {
            preloadTask = nil
        }

        do {
            try recorder.start(
                pauseSegmentation:
                    isPauseMode || processingMode.decodesWhileSpeaking
            )
            process(.captureStarted)
            startRecordingPresentation(
                generation: generation,
                limit: recordingLimit.seconds
            )
        } catch {
            fail(error)
            return false
        }

        let maximumDuration = Duration.seconds(recordingLimit.seconds)
        maximumDurationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: maximumDuration)
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
            captureInsertionContext(contextProvider.captureInsertionContext())
            completionBehavior = .insert
            process(.maximumDurationReached)
        }
        return true
    }

    private func finalizeRecording() -> Bool {
        stopRecordingPresentation()
        maximumDurationTask?.cancel()
        maximumDurationTask = nil

        if isPauseMode {
            return finalizePauseSession()
        }
        if processingMode.decodesWhileSpeaking {
            return finalizePredecodedSession()
        }

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
        let recognitionPrompt = internalDictionary.prompt
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
                let transcript = try await recognizer.transcribe(
                    audio,
                    prompt: recognitionPrompt
                )
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
                fail("Transcription was interrupted: try again.")
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

    private func finalizePredecodedSession() -> Bool {
        let recording: WhisperAudioFile
        let finalSegment: WhisperAudioFile
        do {
            let result = try recorder.stopPauseSession()
            recording = result.recording
            finalSegment = result.finalSegment
        } catch {
            fail(error)
            return false
        }
        enqueuePredecodeChunkIfNeeded(finalSegment)

        let generation = sessionGeneration
        let precedingRecognition = recognitionTask
        let sessionPreload = preloadTask
        recognitionTask = Task { @MainActor [weak self, recognizer] in
            defer { recording.delete() }
            if let precedingRecognition {
                await precedingRecognition.value
            }
            if let sessionPreload {
                await sessionPreload.value
            }
            await recognizer.finishContinuousSession()

            guard let self,
                  !Task.isCancelled,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  generation == sessionGeneration,
                  machine.phase == .transcribing
            else {
                return
            }

            do {
                let transcript: String
                if predecodeFailed {
                    transcript = try await recognizer.transcribe(
                        recording,
                        prompt: internalDictionary.prompt
                    )
                } else {
                    transcript = predecodeAccumulator.transcript
                }
                guard generation == sessionGeneration,
                      machine.phase == .transcribing
                else {
                    return
                }
                preloadTask = nil
                recognitionTask = nil
                process(.transcriptReady, transcript: transcript)
            } catch is CancellationError {
                return
            } catch {
                guard generation == sessionGeneration,
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

    private func finalizePauseSession() -> Bool {
        let recording: WhisperAudioFile
        let finalSegment: WhisperAudioFile
        do {
            let result = try recorder.stopPauseSession()
            recording = result.recording
            finalSegment = result.finalSegment
        } catch {
            fail(error)
            return false
        }
        enqueuePauseChunkIfNeeded(finalSegment)

        let generation = sessionGeneration
        let precedingRecognition = recognitionTask
        let sessionPreload = preloadTask
        let shouldSubmit = completionBehavior == .insertAndSubmit
        recognitionTask = Task { @MainActor [weak self, recognizer] in
            defer { recording.delete() }
            if let precedingRecognition {
                await precedingRecognition.value
            }
            if let sessionPreload {
                await sessionPreload.value
            }
            await recognizer.finishContinuousSession()

            guard let self,
                  !Task.isCancelled,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  generation == sessionGeneration,
                  machine.phase == .transcribing
            else {
                return
            }
            preloadTask = nil
            recognitionTask = nil
            completionBehavior = .insert

            guard pauseSessionDidInsert else {
                fail(
                    "No speech detected.",
                    presentationDuration: BadgePresentationDuration.noSpeech
                )
                return
            }
            if shouldSubmit {
                do {
                    try await Task.sleep(for: Self.postPasteSubmitDelay)
                } catch {
                    return
                }
                guard generation == sessionGeneration,
                      machine.phase == .transcribing
                else {
                    return
                }
                guard delivery.pressReturn() else {
                    fail("Could not press Return in the destination app.")
                    return
                }
            }
            process(.chunkedSessionFinished)
        }
        return true
    }

    private func flushPredecodeChunkAndContinue() {
        guard processingMode.decodesWhileSpeaking,
              !isPauseMode,
              !predecodeBoundaryInProgress,
              !predecodeFailed,
              machine.phase == .listening
        else {
            return
        }
        predecodeBoundaryInProgress = true
        defer { predecodeBoundaryInProgress = false }

        let audio: WhisperAudioFile
        do {
            audio = try recorder.rotatePauseSegment()
        } catch {
            predecodeFailed = true
            return
        }
        enqueuePredecodeChunkIfNeeded(audio)
    }

    private func enqueuePredecodeChunkIfNeeded(_ audio: WhisperAudioFile) {
        guard audio.speechPresence != .absent else {
            audio.delete()
            return
        }

        let generation = sessionGeneration
        let precedingRecognition = recognitionTask
        let sessionPreload = preloadTask
        recognitionTask = Task { @MainActor [weak self, recognizer] in
            defer { audio.delete() }
            if let precedingRecognition {
                await precedingRecognition.value
            }
            if let sessionPreload {
                await sessionPreload.value
            }
            guard let self,
                  !Task.isCancelled,
                  !predecodeFailed,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  generation == sessionGeneration,
                  machine.phase == .listening
                    || machine.phase == .transcribing
            else {
                return
            }

            do {
                let transcript = try await recognizer.transcribeChunk(
                    audio,
                    prompt: internalDictionary.prompt
                )
                guard !Task.isCancelled,
                      generation == sessionGeneration,
                      machine.phase == .listening
                        || machine.phase == .transcribing
                else {
                    return
                }
                predecodeAccumulator.append(transcript)
            } catch is CancellationError {
                return
            } catch let error as WhisperASRError where error == .noSpeech {
                return
            } catch {
                guard generation == sessionGeneration,
                      machine.phase == .listening
                        || machine.phase == .transcribing
                else {
                    return
                }
                predecodeFailed = true
            }
        }
    }

    private func flushPauseChunkAndContinue() {
        guard isPauseMode,
              !pauseBoundaryInProgress,
              machine.phase == .listening
        else {
            return
        }
        pauseBoundaryInProgress = true
        defer { pauseBoundaryInProgress = false }

        let audio: WhisperAudioFile
        do {
            audio = try recorder.rotatePauseSegment()
        } catch {
            fail(error)
            return
        }
        enqueuePauseChunkIfNeeded(audio)
    }

    private func enqueuePauseChunkIfNeeded(_ audio: WhisperAudioFile) {
        guard audio.speechPresence != .absent else {
            audio.delete()
            return
        }

        let generation = sessionGeneration
        let precedingRecognition = recognitionTask
        let sessionPreload = preloadTask
        let recognitionPrompt = RecognitionPrompt.combined(
            dictionaryPrompt: internalDictionary.prompt,
            contextPrompt: pauseSessionPrompt
        )
        recognitionTask = Task { @MainActor [weak self, recognizer] in
            defer { audio.delete() }
            if let precedingRecognition {
                await precedingRecognition.value
            }
            if let sessionPreload {
                await sessionPreload.value
            }
            guard let self,
                  !Task.isCancelled,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  generation == sessionGeneration,
                  machine.phase == .listening
                    || machine.phase == .transcribing
            else {
                return
            }
            do {
                let transcript = try await recognizer.transcribeChunk(
                    audio,
                    prompt: recognitionPrompt
                )
                guard !Task.isCancelled,
                      generation == sessionGeneration,
                      machine.phase == .listening
                        || machine.phase == .transcribing
                else {
                    return
                }
                deliverPauseChunk(transcript)
            } catch is CancellationError {
                return
            } catch let error as WhisperASRError where error == .noSpeech {
                return
            } catch {
                guard generation == sessionGeneration,
                      machine.phase == .listening
                        || machine.phase == .transcribing
                else {
                    return
                }
                fail(error)
            }
        }
    }

    private func deliverPauseChunk(_ transcript: String) {
        let context = contextProvider.captureInsertionContext()
        switch delivery.deliver(transcript: transcript, context: context) {
        case .inserted:
            let trimmed = transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                if pauseSessionDidInsert {
                    lastDictation?.append(" ")
                    lastDictation?.append(contentsOf: trimmed)
                } else {
                    lastDictation = trimmed
                }
            }
            pauseSessionDidInsert = true
            pauseSessionPrompt = lastDictation.flatMap(
                DictationContextPrompt.boundedTail
            )
            logger.info("Pause-mode chunk inserted")
            updateMenuBar()

        case .emptyTranscript:
            break

        case .clipboardUnavailable:
            fail("Clipboard unavailable: try again.")
        }
    }

    private func deliver(_ transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lastDictation = trimmed
        }
        let result = delivery.deliver(
            transcript: transcript,
            context: insertionContext
        )
        insertionContext = nil

        switch result {
        case .inserted:
            logger.info("Dictation inserted")
            if completionBehavior == .insertAndSubmit {
                completionBehavior = .insert
                scheduleSubmitAfterPaste()
                return true
            }
            completionBehavior = .insert
            process(.deliveryFinished)
            return true

        case .clipboardUnavailable:
            fail("Clipboard unavailable: try again.")
            return false

        case .emptyTranscript:
            fail(
                "No speech detected.",
                presentationDuration: BadgePresentationDuration.noSpeech
            )
            return false
        }
    }

    private func cancelSession() {
        sessionGeneration &+= 1
        stopRecordingPresentation()
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        submitAfterPasteTask?.cancel()
        submitAfterPasteTask = nil
        completionBehavior = .insert
        pauseSessionDidInsert = false
        pauseBoundaryInProgress = false
        pauseSessionPrompt = nil
        predecodeAccumulator.reset()
        predecodeBoundaryInProgress = false
        predecodeFailed = false
        let cancelledPreload = preloadTask
        cancelledPreload?.cancel()
        preloadTask = nil
        let cancelledRecognition = recognitionTask
        cancelledRecognition?.cancel()
        recognitionTask = nil
        recorder.cancel()
        insertionContext = nil

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

    private func scheduleCancellationPresentationFinished() {
        cancellationPresentationTask?.cancel()
        cancellationPresentationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    for: BadgePresentationDuration.cancelledMenuState
                )
            } catch {
                return
            }
            guard let self, machine.phase == .cancelled else {
                return
            }
            cancellationPresentationTask = nil
            process(.cancellationPresentationFinished)
        }
    }

    private func fail(_ error: Error) {
        logger.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
        let duration = (error as? WhisperASRError) == .noSpeech
            ? BadgePresentationDuration.noSpeech
            : BadgePresentationDuration.standardError
        fail(
            userFacingMessage(for: error),
            presentationDuration: duration
        )
    }

    private func fail(
        _ message: String,
        presentationDuration: Duration =
            BadgePresentationDuration.standardError
    ) {
        process(.failed(message))
        errorPresentationTask?.cancel()
        errorPresentationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: presentationDuration)
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
        if presentation == .listening {
            badge.updateListening(
                elapsed: 0,
                limit: TimeInterval(recordingLimit.seconds),
                level: 0
            )
        }
    }

    private func startRecordingPresentation(
        generation: UInt64,
        limit: Int
    ) {
        recordingPresentationTask?.cancel()
        badgeFocusMonitor.start()
        let startedAt = ProcessInfo.processInfo.systemUptime
        recordingPresentationTask = Task { @MainActor [weak self] in
            var displayedLevel: Float = 0
            while !Task.isCancelled {
                guard let self,
                      generation == sessionGeneration,
                      machine.phase == .listening
                else {
                    return
                }
                let sampledLevel = recorder.normalizedInputLevel
                displayedLevel = max(sampledLevel, displayedLevel * 0.58)
                badge.updateListening(
                    elapsed: ProcessInfo.processInfo.systemUptime - startedAt,
                    limit: TimeInterval(limit),
                    level: displayedLevel
                )
                if isPauseMode,
                   recorder.trailingSilenceDuration
                    >= recorder.pauseBoundarySilence
                {
                    flushPauseChunkAndContinue()
                } else if processingMode.decodesWhileSpeaking,
                          BackgroundPredecodePolicy.shouldRotate(
                            segmentDuration: recorder.currentSegmentDuration,
                            containsSpeech:
                                recorder.currentSegmentSpeechPresence
                                    == .present,
                            trailingSilence: recorder.trailingSilenceDuration
                          )
                {
                    flushPredecodeChunkAndContinue()
                }
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
        }
    }

    private func stopRecordingPresentation() {
        badgeFocusMonitor.stop()
        recordingPresentationTask?.cancel()
        recordingPresentationTask = nil
    }

    private func refreshBadgeAnchorAfterFocusChange() {
        guard
            machine.phase == .listening,
            badge.acceptsAutomaticAnchorUpdates
        else {
            return
        }
        let anchor = contextProvider.currentBadgeAnchor()
        guard badge.updateAutomaticAnchor(
            caretFrame: anchor.caretRect,
            fieldFrame: anchor.fieldRect
        ) else {
            return
        }
        badgeCaretRect = anchor.caretRect
        badgeFieldRect = anchor.fieldRect
    }

    private func finishFromBadge(_ behavior: CompletionBehavior) {
        finish(
            behavior,
            insertionContext: contextProvider.captureInsertionContext()
        )
    }

    private func finishFromKeyboard(
        _ behavior: CompletionBehavior,
        insertionContext: DictationInsertionContext?
    ) {
        finish(behavior, insertionContext: insertionContext)
    }

    private func finish(
        _ behavior: CompletionBehavior,
        insertionContext suppliedContext: DictationInsertionContext?
    ) {
        guard runtimeReadyForHotkey,
              !isTerminating,
              machine.phase == .preparing || machine.phase == .listening
        else {
            return
        }
        completionBehavior = behavior
        captureInsertionContext(suppliedContext)
        process(.maximumDurationReached)
    }

    private func scheduleSubmitAfterPaste() {
        submitAfterPasteTask?.cancel()
        let generation = sessionGeneration
        submitAfterPasteTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.postPasteSubmitDelay)
            } catch {
                return
            }
            guard let self,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  generation == sessionGeneration,
                  machine.phase == .inserting
            else {
                return
            }
            submitAfterPasteTask = nil
            guard delivery.pressReturn() else {
                fail("Could not press Return in the destination app.")
                return
            }
            logger.info("Dictation inserted and submitted")
            process(.deliveryFinished)
        }
    }

    private func captureInsertionContext(
        _ context: DictationInsertionContext?
    ) {
        insertionContext = context
        if let caretRect = context?.caretRect {
            badgeCaretRect = caretRect
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
        updateMenuBar()
    }

    private func updateMenuBar() {
        defer {
            advancedSettingsWindowController?.refreshIfVisible()
        }
        if startupError != nil {
            menuBarController.update(
                .failed,
                toggleDictationEnabled: effectiveToggleDictationEnabled,
                selectedHotkey: selectedHotkey,
                hasLastDictation: lastDictation != nil
            )
            return
        }
        guard runtimeReadyForHotkey else {
            menuBarController.update(
                .unavailable,
                toggleDictationEnabled: effectiveToggleDictationEnabled,
                selectedHotkey: selectedHotkey,
                hasLastDictation: lastDictation != nil
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
            toggleDictationEnabled: effectiveToggleDictationEnabled,
            selectedHotkey: selectedHotkey,
            hasLastDictation: lastDictation != nil
        )
    }

    private var advancedSettingsState: AdvancedSettingsState {
        AdvancedSettingsState(
            selectedHotkey: selectedHotkey,
            activationMode: hotkeyActivationMode,
            selectedModel: selectedModel,
            selectedEngine: selectedEngine,
            decodingProfile: decodingProfile,
            processingMode: processingMode,
            internalDictionaryEntries: internalDictionary.entries,
            recordingLimit: recordingLimit,
            selectedTheme: selectedTheme,
            availableModels: availableModels,
            availableEngines: availableEngines,
            configurationEnabled: !machine.phase.isBusy
        )
    }

    private func showAdvancedSettings() {
        guard !machine.phase.isBusy else {
            return
        }
        if advancedSettingsWindowController == nil {
            advancedSettingsWindowController = AdvancedSettingsWindowController(
                stateProvider: { [weak self] in
                    self?.advancedSettingsState
                        ?? Self.unavailableAdvancedSettingsState
                },
                actions: AdvancedSettingsActions(
                    selectDictationMode: { [weak self] mode in
                        self?.selectDictationMode(mode)
                    },
                    selectHotkey: { [weak self] hotkey in
                        self?.selectHotkey(hotkey)
                    },
                    selectModel: { [weak self] model in
                        self?.selectModel(model)
                    },
                    selectEngine: { [weak self] engine in
                        self?.selectEngine(engine)
                    },
                    selectDecodingProfile: { [weak self] profile in
                        self?.selectDecodingProfile(profile)
                    },
                    selectProcessingMode: { [weak self] mode in
                        self?.selectProcessingMode(mode)
                    },
                    setInternalDictionary: { [weak self] entries in
                        self?.setInternalDictionary(entries)
                    },
                    selectRecordingLimit: { [weak self] limit in
                        self?.selectRecordingLimit(limit)
                    },
                    selectTheme: { [weak self] theme in
                        self?.selectTheme(theme)
                    },
                    loginItemChanged: { [weak self] in
                        self?.setupWindowController.refresh()
                    }
                ),
                loginItemManager: loginItemManager
            )
        }
        advancedSettingsWindowController?.showSettings()
    }

    private var effectiveToggleDictationEnabled: Bool {
        hotkeyActivationMode != .hold
    }

    private var hotkeyActivationMode: HotkeyActivationMode {
        selectedHotkey.requiresToggleMode && selectedDictationMode == .hold
            ? .toggle
            : selectedDictationMode
    }

    private var isPauseMode: Bool {
        hotkeyActivationMode == .pause
    }

    private func selectDictationMode(_ mode: HotkeyActivationMode) {
        guard !machine.phase.isBusy,
              mode != .hold || !selectedHotkey.requiresToggleMode
        else {
            return
        }
        guard selectedDictationMode != mode else {
            return
        }
        selectedDictationMode = mode
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.dictationMode
        )
        // Preserve downgrade compatibility with the former two-state setting.
        UserDefaults.standard.set(
            mode != .hold,
            forKey: "toggleDictationEnabled"
        )
        hotkeyMonitor.setActivationMode(hotkeyActivationMode)
        updateMenuBar()
    }

    private static func loadDictationMode(
        defaults: UserDefaults = .standard
    ) -> HotkeyActivationMode {
        if let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.dictationMode
        ), let mode = HotkeyActivationMode(rawValue: rawValue) {
            return mode
        }
        return defaults.bool(forKey: "toggleDictationEnabled")
            ? .toggle
            : .hold
    }

    private func selectHotkey(_ hotkey: HotkeyKey) {
        guard !machine.phase.isBusy, selectedHotkey != hotkey else {
            return
        }
        selectedHotkey = hotkey
        UserDefaults.standard.set(hotkey.rawValue, forKey: "dictationHotkey")
        hotkeyMonitor.setHotkey(hotkey)
        hotkeyMonitor.setActivationMode(hotkeyActivationMode)
        updateMenuBar()
    }

    private func selectModel(_ model: DictationModel) {
        guard !machine.phase.isBusy,
              modelAvailable(model),
              selectedModel != model
        else {
            return
        }
        selectedModel = model
        UserDefaults.standard.set(
            model.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.dictationModel
        )
        configureModelReadiness(reloadSelectedModel: true)
        reconcileRuntime(showSetupIfNeeded: false)
        setupWindowController.refresh()
    }

    private func selectEngine(_ engine: RecognitionEngine) {
        guard !machine.phase.isBusy,
              engineAvailable(engine, model: selectedModel),
              selectedEngine != engine
        else {
            return
        }
        selectedEngine = engine
        UserDefaults.standard.set(
            engine.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.recognitionEngine
        )
        configureModelReadiness(reloadSelectedModel: true)
        reconcileRuntime(showSetupIfNeeded: false)
        setupWindowController.refresh()
    }

    private func selectDecodingProfile(_ profile: DecodingProfile) {
        guard !machine.phase.isBusy,
              selectedEngine != .whisperKitCoreML,
              decodingProfile != profile
        else {
            return
        }
        decodingProfile = profile
        UserDefaults.standard.set(
            profile.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.decodingProfile
        )
        configureModelReadiness(reloadSelectedModel: true)
        advancedSettingsWindowController?.refreshIfVisible()
    }

    private func selectProcessingMode(_ mode: ModelProcessingMode) {
        guard !machine.phase.isBusy, processingMode != mode else {
            return
        }
        processingMode = mode
        mode.persist()
        configureModelReadiness()
        updateMenuBar()
    }

    private func setInternalDictionary(_ entries: [String]) {
        guard !machine.phase.isBusy else {
            return
        }
        let updated = InternalDictionary(entries: entries)
        guard updated != internalDictionary else {
            return
        }
        internalDictionary = updated
        updated.persist()
        advancedSettingsWindowController?.refreshIfVisible()
    }

    private func configureModelReadiness(
        reloadSelectedModel: Bool = false
    ) {
        let precedingConfiguration = modelConfigurationTask
        let shouldKeepReady = processingMode.keepsModelReady
        let recognizer = recognizer
        let logger = logger
        modelConfigurationTask = Task.detached(priority: .utility) {
            if let precedingConfiguration {
                await precedingConfiguration.value
            }
            guard !Task.isCancelled else {
                return
            }
            do {
                if reloadSelectedModel {
                    try await recognizer.reloadSelectedModel()
                } else {
                    try await recognizer.setKeepsModelReady(shouldKeepReady)
                }
            } catch is CancellationError {
                return
            } catch {
                logger.error(
                    "Could not update model readiness: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func selectRecordingLimit(_ limit: RecordingLimit) {
        guard !machine.phase.isBusy, recordingLimit != limit else {
            return
        }
        recordingLimit = limit
        UserDefaults.standard.set(
            limit.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.recordingLimit
        )
        updateMenuBar()
    }

    private func selectTheme(_ theme: BadgeTheme) {
        guard !machine.phase.isBusy, selectedTheme != theme else {
            return
        }
        selectedTheme = theme
        UserDefaults.standard.set(
            theme.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.badgeTheme
        )
        badge.applyTheme(theme)
        advancedSettingsWindowController?.refreshIfVisible()
    }

    private func copyLastDictation() {
        guard let lastDictation else {
            return
        }
        if !delivery.copyToClipboard(lastDictation) {
            fail("Clipboard unavailable: try again.")
        }
    }

    private func restartApplication() {
        guard !isTerminating else {
            return
        }
        do {
            try ApplicationRelauncher().schedule()
        } catch {
            logger.error(
                "Could not schedule restart: \(error.localizedDescription, privacy: .public)"
            )
            fail("Could not restart: try again.")
            return
        }
        logger.info("Restart requested from menu")
        NSApp.terminate(nil)
    }

    private func stopSynchronousServices() -> PendingRecognizerWork {
        let pendingWork = PendingRecognizerWork(
            precedingCleanup: recognizerCleanupTask,
            modelConfiguration: modelConfigurationTask,
            preload: preloadTask,
            recognition: recognitionTask
        )
        scheduledTerminationTask?.cancel()
        scheduledTerminationTask = nil
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        stopRecordingPresentation()
        cancellationPresentationTask?.cancel()
        cancellationPresentationTask = nil
        errorPresentationTask?.cancel()
        errorPresentationTask = nil
        submitAfterPasteTask?.cancel()
        submitAfterPasteTask = nil
        completionBehavior = .insert
        pauseSessionDidInsert = false
        pauseBoundaryInProgress = false
        pauseSessionPrompt = nil
        predecodeAccumulator.reset()
        predecodeBoundaryInProgress = false
        predecodeFailed = false
        preloadTask?.cancel()
        preloadTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizerCleanupTask = nil
        modelConfigurationTask?.cancel()
        modelConfigurationTask = nil
        hotkeyMonitor.stop()
        recorder.cancel()
        badge.hide()
        clipboard.completePendingRestoration()
        controlServer?.stop()
        controlServer = nil
        insertionContext = nil
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
            hotkey: selectedHotkey.displayName,
            hotkeyMode: hotkeyActivationMode.rawValue,
            model: "\(selectedModel.displayName), \(selectedEngine.displayName)",
            recordingLimit: recordingLimit.displayName,
            threadCount: WhisperRuntimeDiscovery.recommendedThreadCount(),
            lastError: machine.lastError ?? startupError
        )
    }

    private var microphonePermissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private var modelAvailable: Bool {
        modelAvailable(selectedModel)
    }

    private var availableModels: Set<DictationModel> {
        Set(DictationModel.allCases.filter(modelAvailable))
    }

    private func modelAvailable(_ model: DictationModel) -> Bool {
        engineAvailable(selectedEngine, model: model)
    }

    private var availableEngines: Set<RecognitionEngine> {
        Set(RecognitionEngine.allCases.filter {
            engineAvailable($0, model: selectedModel)
        })
    }

    private func engineAvailable(
        _ engine: RecognitionEngine,
        model: DictationModel
    ) -> Bool {
        (try? WhisperRuntimeDiscovery.discover(
            model: model,
            engine: engine
        )) != nil
    }

    private var helperAvailable: Bool {
        if selectedEngine == .whisperKitCoreML {
            return true
        }
        return WhisperRuntimeDiscovery.helperCandidates().contains {
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
            WhisperHotkeyPaths.modelURL(for: selectedModel),
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
            return "Dictation failed: see logs."
        }
        switch asrError {
        case .noSpeech:
            return "No speech detected."
        case .modelMissing:
            return "Whisper model missing: run setup."
        case .helperUnavailable, .commandLineUnavailable:
            return "Whisper tools missing: run setup."
        case .microphoneUnavailable, .captureFailed, .noActiveRecording:
            return "Microphone failed: run setup."
        case .recognitionTimedOut:
            return "Transcription timed out."
        case .helperProtocolFailure, .helperFailed, .commandLineFailed:
            return "Transcription failed: see logs."
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
