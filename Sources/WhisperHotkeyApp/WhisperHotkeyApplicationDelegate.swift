@preconcurrency import AVFoundation
import AppKit
import Foundation
import OSLog
import WhisperHotkeyASR
import WhisperHotkeyCore
import WhisperHotkeyShell
import WhisperHotkeySystem

enum PipelineDeliveryDisposition: Equatable {
    case ignore
    case pauseSentence(String)
    case finalTranscript(String)
}

@MainActor
final class WhisperHotkeyApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let postPasteSubmitDelay: Duration = .milliseconds(80)
    private static let firstRunDefaultsVersion = 1
    private static let preparedDefaults: UserDefaults = {
        let defaults = UserDefaults.standard
        FirstRunPreferenceBootstrap.applyIfNeeded(
            defaults: defaults,
            version: firstRunDefaultsVersion
        ) {
            let availableModels = Set(DictationModel.allCases.filter { model in
                (try? WhisperRuntimeDiscovery.discover(
                    model: model,
                    engine: .whisperCppMetal,
                    decodingProfile: .precision
                )) != nil
            })
            let profile = FirstRunPerformanceProfile.recommended(
                physicalMemory: ProcessInfo.processInfo.physicalMemory,
                availableModels: availableModels
            )
            defaults.set(
                HotkeyKey.rightOption.rawValue,
                forKey: "dictationHotkey"
            )
            defaults.set(
                HotkeyActivationMode.toggle.rawValue,
                forKey: WhisperHotkeyPreferenceKeys.dictationMode
            )
            defaults.set(true, forKey: "toggleDictationEnabled")
            defaults.set(
                profile.model.rawValue,
                forKey: WhisperHotkeyPreferenceKeys.dictationModel
            )
            defaults.set(
                profile.engine.rawValue,
                forKey: WhisperHotkeyPreferenceKeys.recognitionEngine
            )
            defaults.set(
                profile.parakeetVariant.rawValue,
                forKey: WhisperHotkeyPreferenceKeys.parakeetModel
            )
            defaults.set(
                profile.decodingProfile.rawValue,
                forKey: WhisperHotkeyPreferenceKeys.decodingProfile
            )
            profile.processingMode.persist(defaults: defaults)
        }
        return defaults
    }()
    private static let unavailableAdvancedSettingsState = AdvancedSettingsState(
        selectedHotkey: .rightOption,
        activationMode: .toggle,
        selectedModel: .baseEnglish,
        selectedEngine: .whisperCppMetal,
        decodingProfile: .precision,
        processingMode: .afterRecording,
        internalDictionaryEntries: [],
        keepsLatestDictation: true,
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
        let pipeline: Task<Void, Never>?
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
        rawValue: WhisperHotkeyApplicationDelegate.preparedDefaults.string(
            forKey: "dictationHotkey"
        ) ?? ""
    ) ?? .rightOption
    private var selectedDictationMode =
        WhisperHotkeyApplicationDelegate.loadDictationMode(
            defaults: WhisperHotkeyApplicationDelegate.preparedDefaults
        )
    private var selectedModel = DictationModel.selected(
        defaults: WhisperHotkeyApplicationDelegate.preparedDefaults
    )
    private var selectedParakeetVariant = ParakeetVariant.selected(
        defaults: WhisperHotkeyApplicationDelegate.preparedDefaults
    )
    private var parakeetInstallTask: Task<Void, Never>?
    private var parakeetInstallPanel: ModelDownloadProgressPanel?
    private var selectedEngine = RecognitionEngine.selected(
        defaults: WhisperHotkeyApplicationDelegate.preparedDefaults
    )
    private var decodingProfile = DecodingProfile.selected(
        defaults: WhisperHotkeyApplicationDelegate.preparedDefaults
    )
    private var processingMode = ModelProcessingMode.selected(
        defaults: WhisperHotkeyApplicationDelegate.preparedDefaults
    )
    private var internalDictionary = InternalDictionary.selected(
        defaults: WhisperHotkeyApplicationDelegate.preparedDefaults
    )
    private var lastDictation = LastDictationBuffer(
        isEnabled: LastDictationRetentionPreference.isEnabled()
    )
    private var recordingLimit = RecordingLimit.selected()
    private var customThemes = CustomBadgeTheme.load()
    private var selectedTheme = BadgeThemeSelection.selected()
    private var automaticallyChecksForUpdates =
        AutomaticUpdateCheckPreference.isEnabled()
    private var softwareUpdateStatus: SoftwareUpdateStatus = .idle
    private let softwareUpdateChecker: any SoftwareUpdateChecking =
        GitHubReleaseUpdateChecker()
    private var availableSoftwareUpdate: SoftwareUpdateRelease?
    private var softwareUpdateProgressPanel: ModelDownloadProgressPanel?

    private lazy var delivery = TextDeliveryService(clipboard: clipboard)
    private lazy var pipelineCoordinator = RecognitionPipelineCoordinator(
        providers: .whisper(recognizer: recognizer),
        delivery: { [weak self] event in
            await MainActor.run {
                self?.handlePipelineDelivery(event)
            }
        }
    )
    private lazy var hotkeyMonitor = GlobalHotkeyMonitor(
        contextProvider: contextProvider,
        shouldIgnorePointerDown: { [weak self] in
            guard let self else {
                return false
            }
            return badge.containsInteractivePoint(NSEvent.mouseLocation)
        },
        immediateCaptureHandler: { [weak self] action, timestampNanoseconds in
            self?.handleImmediateCaptureEdge(
                action,
                timestampNanoseconds: timestampNanoseconds
            )
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
    private var modelDownloadController: ModelDownloadController?
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
    private var primedAudioCaptureToken: WhisperAudioCaptureToken?
    private var primedBadgeVisible = false
    private var captureTimingTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var maximumDurationTask: Task<Void, Never>?
    private var recordingPresentationTask: Task<Void, Never>?
    private var recordingSegmentationTask: Task<Void, Never>?
    private var cancellationPresentationTask: Task<Void, Never>?
    private var errorPresentationTask: Task<Void, Never>?
    private var badgeAnchorResolutionTask: Task<Void, Never>?
    private var submitAfterPasteTask: Task<Void, Never>?
    private var completionCaptureGraceTask: Task<Void, Never>?
    private var pipelineBeginTask: Task<Void, Never>?
    private var recognizerCleanupTask: Task<Void, Never>?
    private var modelConfigurationTask: Task<Void, Never>?
    private var scheduledTerminationTask: Task<Void, Never>?
    private var softwareUpdateTask: Task<Void, Never>?
    private var softwareUpdateInstallationTask: Task<Void, Never>?
    private var insertionContext: DictationInsertionContext?
    private var deliversToInternalDictionaryDraft = false
    private var completionBehavior = CompletionBehavior.insert
    private var hasRequestedInputMonitoringRegistration = false
    private var badgeCaretRect: CGRect?
    private var badgeFieldRect: CGRect?
    private var pauseSessionTranscript: String?
    private var pauseSessionDidInsert = false
    private var pauseBoundaryInProgress = false
    private var pauseSessionPrompt: String?
    private var pauseDeliveryContext: DictationInsertionContext?
    private var predecodeAccumulator = PredecodedTranscriptAccumulator()
    private var predecodeBoundaryInProgress = false
    private var predecodeFailed = false
    private var sessionGeneration: UInt64 = 0
    private var pendingReviewRequest: PostProcessRequest?
    private var activeReviewRequest: PostProcessRequest?
    private var presentedReviewPreview: PostProcessPreview?
    private var reviewController: PostProcessReviewController?
    private var reviewSession: PostProcessingReviewSession?
    /// Bounds the reviewing phase. Without it, a processing task that never
    /// reports back (cancelled, superseded, or hung inside URLSession) leaves
    /// the badge showing forever and the hotkey refusing new dictations.
    private var reviewWatchdogTask: Task<Void, Never>?
    /// Created on demand only: when post-processing is disabled the app
    /// never instantiates the processor, its session, or the key provider.
    /// A fresh instance per dictation keeps model/thinking/effort preference
    /// changes effective immediately; construction is inert (no network).
    private func makeTranscriptProcessor() -> DeepSeekTranscriptProcessor {
        let environmentModel = ProcessInfo.processInfo.environment[
            "DEEPSEEK_PROCESSOR_MODEL"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (environmentModel?.isEmpty == false)
            ? environmentModel!
            : PostProcessingPreference.selectedModel()
        let effort = DeepSeekReasoningEffort(
            rawValue: PostProcessingPreference.selectedReasoningEffort()
        ) ?? .low
        let thinkingEnabled = PostProcessingPreference.isThinkingEnabled()
        let configuration = DeepSeekConfiguration(
            model: model,
            timeout: DeepSeekConfiguration.timeout(
                thinkingEnabled: thinkingEnabled,
                reasoningEffort: effort
            ),
            maxOutputTokens: DeepSeekConfiguration.maxOutputTokens(
                thinkingEnabled: thinkingEnabled
            ),
            thinkingEnabled: thinkingEnabled,
            reasoningEffort: effort,
            customProfilePrompt: PostProcessingPreference.customPrompt()
        )
        return DeepSeekTranscriptProcessor(
            apiKeyProvider: {
                guard let key = try ProcessorKeychain.read() else {
                    throw ProcessorError.missingKey
                }
                return key
            },
            configuration: configuration
        )
    }
    private var startupError: String?
    private var startupBadgeVisible = false
    private var runtimeReadyForHotkey = false
    private var isTerminating = false
    private var terminationCleanupStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Offer the Applications install before anything claims the control
        // socket or starts the runtime, because accepting relaunches the app
        // from its new location and terminates this instance.
        guard !InstallLocationPromptController().runIfNeeded() else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        guard startControlServer() else {
            return
        }
        // Construct the reusable hidden panel before the first gesture so its
        // AppKit setup is never paid on the capture-critical path.
        _ = badge
        menuBarController.update(
            .starting,
            toggleDictationEnabled: effectiveToggleDictationEnabled,
            selectedHotkey: selectedHotkey,
            hasLastDictation: lastDictation.transcript != nil
        )
        reconcileRuntime(showSetupIfNeeded: true)
        configureModelReadiness()
        showFirstRunSettingsIfNeeded()
        if automaticallyChecksForUpdates {
            checkForUpdates()
        }
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
            if let pipeline = pendingWork.pipeline {
                await pipeline.value
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
        registerForInputMonitoringIfNeeded()
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
        case .primeCapture:
            presentPrimedCaptureIfCurrent()

        case .cancelPrimedCapture:
            dismissPrimedCapturePresentation()

        case .pressed:
            if !machine.phase.isBusy, machine.phase != .failed {
                badgeCaretRect = nil
                badgeFieldRect = nil
                insertionContext = nil
                deliversToInternalDictionaryDraft =
                    advancedSettingsWindowController?
                        .internalDictionaryDraftIsFocused == true
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
        if (event == .cancel || event == .reviewCancelled),
           machine.phase == .cancelled
        {
            scheduleCancellationPresentationFinished()
        }
    }

    @discardableResult
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

        case .requestProcessing:
            guard let request = pendingReviewRequest else {
                fail("Transcription result was unavailable.")
                return false
            }
            pendingReviewRequest = nil
            activeReviewRequest = request
            let session = reviewSession ?? PostProcessingReviewSession(
                processor: makeTranscriptProcessor(),
                isSessionCurrent: { [weak self] generation in
                    self?.sessionGeneration == generation
                        && self?.machine.phase == .reviewing
                },
                onPreview: { [weak self] preview in
                    self?.apply(.showReview(preview), transcript: nil)
                }
            )
            reviewSession = session
            session.start(request, generation: sessionGeneration)
            startReviewWatchdog(for: request)
            return true

        case .showReview(let preview):
            reviewWatchdogTask?.cancel()
            reviewWatchdogTask = nil
            // Enhancement replaces the dictated text outright: the processed
            // rewrite goes through the existing insertion path with no review
            // step. A failed rewrite still inserts the raw transcript, so the
            // feature can never swallow a dictation.
            presentedReviewPreview = nil
            activeReviewRequest = nil
            guard machine.phase == .reviewing else { return true }
            process(
                .reviewAccepted,
                transcript: PostProcessingReviewFlow.acceptedText(for: preview)
            )
            return true

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
        completionCaptureGraceTask?.cancel()
        completionCaptureGraceTask = nil
        pipelineBeginTask?.cancel()
        pipelineBeginTask = nil
        completionBehavior = .insert
        pauseSessionDidInsert = false
        pauseBoundaryInProgress = false
        pauseSessionTranscript = nil
        pauseSessionPrompt = nil
        pauseDeliveryContext = nil
        predecodeAccumulator.reset()
        predecodeBoundaryInProgress = false
        predecodeFailed = false

        // Model preparation belongs to its own actor and starts independently
        // of recorder adoption and badge/Accessibility work.
        let pipelineCoordinator = pipelineCoordinator
        let activationMode = hotkeyActivationMode
        let sessionProcessingMode = processingMode
        pipelineBeginTask?.cancel()
        pipelineBeginTask = Task.detached(priority: .userInitiated) {
            await pipelineCoordinator.beginSession(
                generation: generation,
                activationMode: activationMode,
                processingMode: sessionProcessingMode
            )
        }

        do {
            if let token = primedAudioCaptureToken {
                primedAudioCaptureToken = nil
                try recorder.adoptPrimedCapture(token)
                scheduleCaptureTimingReport(for: token)
            } else {
                try recorder.start(
                    pauseSegmentation:
                        isPauseMode || processingMode.decodesWhileSpeaking
                )
            }
            primedBadgeVisible = false
            process(.captureStarted)
            startRecordingPresentation(
                generation: generation,
                limit: recordingLimit.seconds
            )
        } catch {
            fail(error)
            return false
        }

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

    /// Called synchronously by the event monitor. This method only creates a
    /// token and enqueues work on the recorder-owned capture runtime.
    private func handleImmediateCaptureEdge(
        _ action: HotkeyAction,
        timestampNanoseconds: UInt64
    ) {
        switch action {
        case .primeCapture:
            guard !machine.phase.isBusy,
                  machine.phase != .failed,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  primedAudioCaptureToken == nil
            else {
                return
            }
            primedAudioCaptureToken = recorder.primeCapture(
                pauseSegmentation:
                    isPauseMode || processingMode.decodesWhileSpeaking,
                requestedAtUptimeNanoseconds: timestampNanoseconds
            )

        case .cancelPrimedCapture:
            guard let token = primedAudioCaptureToken else { return }
            primedAudioCaptureToken = nil
            recorder.cancelPrimedCapture(token)

        default:
            return
        }
    }

    private func presentPrimedCaptureIfCurrent() {
        guard primedAudioCaptureToken != nil,
              !machine.phase.isBusy,
              machine.phase != .failed,
              !primedBadgeVisible
        else {
            return
        }
        primedBadgeVisible = true
        badge.present(.listening)
        badge.updateListening(
            elapsed: 0,
            limit: TimeInterval(recordingLimit.seconds),
            level: 0
        )
    }

    private func dismissPrimedCapturePresentation() {
        guard primedBadgeVisible, !machine.phase.isBusy else { return }
        primedBadgeVisible = false
        badge.hide()
    }

    private func scheduleCaptureTimingReport(
        for token: WhisperAudioCaptureToken
    ) {
        captureTimingTask?.cancel()
        let recorder = recorder
        let logger = logger
        captureTimingTask = Task { @MainActor [weak self] in
            for _ in 0..<20 {
                if Task.isCancelled { return }
                if let timing = recorder.captureTiming(for: token),
                   let firstBuffer = timing.requestToFirstBufferNanoseconds,
                   let firstCommit = timing
                    .requestToFirstCommittedSampleNanoseconds
                {
                    logger.info(
                        "Capture timing first-buffer=\(firstBuffer / 1_000_000, privacy: .public)ms first-commit=\(firstCommit / 1_000_000, privacy: .public)ms"
                    )
                    self?.captureTimingTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            self?.captureTimingTask = nil
        }
    }

    private func finalizeRecording() -> Bool {
        stopRecordingPresentation()
        maximumDurationTask?.cancel()
        maximumDurationTask = nil

        if isPauseMode || processingMode.decodesWhileSpeaking {
            do {
                let result = try recorder.stopPauseSession()
                return scheduleCoordinatorFinalization(
                    audio: result.recording,
                    finalTailAudio: result.finalSegment
                )
            } catch {
                fail(error)
                return false
            }
        }

        do {
            return scheduleCoordinatorFinalization(audio: try recorder.stop())
        } catch {
            fail(error)
            return false
        }
    }

    private func finalizePredecodedSession() -> Bool {
        do {
            let result = try recorder.stopPauseSession()
            return scheduleCoordinatorFinalization(
                audio: result.recording,
                finalTailAudio: result.finalSegment
            )
        } catch {
            fail(error)
            return false
        }
    }

    private func finalizePauseSession() -> Bool {
        return finalizePredecodedSession()
    }

    private func scheduleCoordinatorFinalization(
        audio: WhisperAudioFile,
        finalTailAudio: WhisperAudioFile? = nil
    ) -> Bool {
        let generation = sessionGeneration
        let precedingRecognition = recognitionTask
        let sessionPreload = preloadTask
        let pipelineBegin = pipelineBeginTask
        let coordinator = pipelineCoordinator
        let recognitionPrompt = RecognitionPrompt.combined(
            dictionaryPrompt: internalDictionary.prompt,
            contextPrompt: pauseSessionPrompt
        )
        let shouldSubmit = completionBehavior == .insertAndSubmit
            && !deliversToInternalDictionaryDraft
        if isPauseMode {
            pauseDeliveryContext = insertionContext
        }
        recognitionTask = Task { @MainActor [weak self] in
            var handedOffToCoordinator = false
            defer {
                if !handedOffToCoordinator {
                    Self.deleteFinalizationAudio(
                        audio,
                        finalTailAudio: finalTailAudio
                    )
                }
                if let self,
                   generation == self.sessionGeneration
                {
                    // A coordinator delivery can transition a non-pause
                    // session to idle before finish() returns. Cleanup must
                    // not depend on the old transcribing-phase guard.
                    self.preloadTask = nil
                    self.recognitionTask = nil
                    self.pipelineBeginTask = nil
                }
            }
            do {
                if let precedingRecognition {
                    await precedingRecognition.value
                }
                if let sessionPreload {
                    await sessionPreload.value
                }
                if let pipelineBegin {
                    await pipelineBegin.value
                }
                guard let self,
                      !Task.isCancelled,
                      self.runtimeReadyForHotkey,
                      !self.isTerminating,
                      generation == self.sessionGeneration,
                      self.machine.phase == .transcribing
                else {
                    return
                }
                handedOffToCoordinator = true
                let outcome = try await coordinator.finish(
                    audio: audio,
                    finalTailAudio: finalTailAudio,
                    prompt: recognitionPrompt
                )
                guard generation == self.sessionGeneration else {
                    return
                }
                if !self.isPauseMode {
                    // Delivery normally advances transcribing -> inserting ->
                    // idle inside the coordinator callback. If that callback
                    // was suppressed without a generation change, use the
                    // canonical outcome once so the badge cannot remain stuck.
                    if self.machine.phase == .transcribing {
                        self.handleFinalTranscript(outcome.text, delivery: nil)
                    }
                    return
                }
                guard self.machine.phase == .transcribing else { return }
                self.completionBehavior = .insert
                if !self.pauseSessionDidInsert,
                   outcome.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    self.fail(
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
                    guard generation == self.sessionGeneration,
                          self.machine.phase == .transcribing
                    else {
                        return
                    }
                    guard self.delivery.pressReturn() else {
                        self.fail("Could not press Return in the destination app.")
                        return
                    }
                }
                self.deliversToInternalDictionaryDraft = false
                self.process(.chunkedSessionFinished)
            } catch is CancellationError {
                return
            } catch let error as RecognitionPipelineError {
                guard let self,
                      generation == self.sessionGeneration,
                      self.machine.phase == .transcribing
                else { return }
                if error == .noSpeechDetected {
                    self.fail(
                        "No speech detected.",
                        presentationDuration: BadgePresentationDuration.noSpeech
                    )
                } else if error != .staleGeneration {
                    self.fail("Transcription was interrupted: try again.")
                }
            } catch {
                guard let self,
                      generation == self.sessionGeneration,
                      self.machine.phase == .transcribing
                else { return }
                self.fail(error)
            }
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
        guard audio.speechPresence != .absent,
              !predecodeFailed,
              machine.phase == .listening
        else {
            audio.delete()
            return
        }
        let generation = sessionGeneration
        let coordinator = pipelineCoordinator
        let prompt = internalDictionary.prompt
        let pipelineBegin = pipelineBeginTask
        Task { @MainActor [weak self] in
            if let pipelineBegin {
                await pipelineBegin.value
            }
            guard let self,
                  !Task.isCancelled,
                  self.runtimeReadyForHotkey,
                  !self.isTerminating,
                  self.sessionGeneration == generation,
                  self.machine.phase == .listening,
                  !self.predecodeFailed,
                  audio.speechPresence != .absent
            else {
                audio.delete()
                return
            }
            await coordinator.submitStreamingAudio(
                audio,
                prompt: prompt,
                pass: .provisional,
                completeness: .provisional,
                expectedGeneration: generation
            )
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
        guard audio.speechPresence != .absent,
              machine.phase == .listening,
              isPauseMode
        else {
            audio.delete()
            return
        }
        let generation = sessionGeneration
        let coordinator = pipelineCoordinator
        let pipelineBegin = pipelineBeginTask
        Task { @MainActor [weak self] in
            if let pipelineBegin {
                await pipelineBegin.value
            }
            guard let self,
                  !Task.isCancelled,
                  self.runtimeReadyForHotkey,
                  !self.isTerminating,
                  self.sessionGeneration == generation,
                  self.machine.phase == .listening,
                  self.isPauseMode,
                  audio.speechPresence != .absent
            else {
                audio.delete()
                return
            }
            // Read the bounded context only after the prior sentence's
            // immediate delivery has updated pauseSessionPrompt.
            let recognitionPrompt = RecognitionPrompt.combined(
                dictionaryPrompt: self.internalDictionary.prompt,
                contextPrompt: self.pauseSessionPrompt
            )
            await coordinator.submitStreamingAudio(
                audio,
                prompt: recognitionPrompt,
                pass: .provisional,
                completeness: .completeSentence,
                expectedGeneration: generation
            )
        }
    }

    private static func deleteFinalizationAudio(
        _ audio: WhisperAudioFile,
        finalTailAudio: WhisperAudioFile?
    ) {
        audio.delete()
        if let finalTailAudio, finalTailAudio !== audio {
            finalTailAudio.delete()
        }
    }

    private func deliverPauseChunk(_ transcript: String) {
        if deliversToInternalDictionaryDraft {
            let trimmed = transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                advancedSettingsWindowController?
                    .appendDictatedInternalDictionaryDraft(trimmed)
                lastDictation.retainSuccessful(trimmed)
                pauseSessionDidInsert = true
                logger.info("Pause-mode chunk added to dictionary draft")
                updateMenuBar()
            }
            return
        }
        let context = pauseDeliveryContext
            ?? contextProvider.captureInsertionContext()
        switch delivery.deliver(transcript: transcript, context: context) {
        case .inserted:
            let trimmed = transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                if pauseSessionDidInsert {
                    pauseSessionTranscript?.append(" ")
                    pauseSessionTranscript?.append(contentsOf: trimmed)
                } else {
                    pauseSessionTranscript = trimmed
                }
                lastDictation.retainSuccessful(
                    pauseSessionTranscript ?? ""
                )
            }
            pauseSessionDidInsert = true
            pauseSessionPrompt = pauseSessionTranscript.flatMap(
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

    /// RecognitionPipelineCoordinator is the only caller that crosses into
    /// text delivery. Providers and accumulator tasks never paste directly.
    private func handlePipelineDelivery(
        _ event: RecognitionPipelineDelivery
    ) {
        switch Self.pipelineDeliveryDisposition(
            event,
            currentGeneration: sessionGeneration,
            phase: machine.phase,
            isPauseMode: isPauseMode,
            isTerminating: isTerminating
        ) {
        case .ignore:
            return
        case .pauseSentence(let text):
            deliverPauseChunk(text)
        case .finalTranscript(let text):
            // The coordinator owns recognition delivery, but the app state
            // machine still owns insertion and badge teardown. Skipping this
            // transition leaves Toggle Mode in `.transcribing` forever even
            // though the text was pasted successfully.
            handleFinalTranscript(text, delivery: event)
        }
    }

    static func pipelineDeliveryDisposition(
        _ event: RecognitionPipelineDelivery,
        currentGeneration: UInt64,
        phase: DictationPhase,
        isPauseMode: Bool,
        isTerminating: Bool
    ) -> PipelineDeliveryDisposition {
        guard !isTerminating,
              event.generation == currentGeneration
        else { return .ignore }

        if isPauseMode {
            guard phase == .listening || phase == .transcribing,
                  event.kind == .pauseSentence || event.kind == .finalTranscript
            else { return .ignore }
            return .pauseSentence(event.text)
        }

        guard phase == .transcribing, event.kind == .finalTranscript else {
            return .ignore
        }
        return .finalTranscript(event.text)
    }

    /// Routes a final (non-pause) transcript. Local voice commands and the
    /// post-processing review gate run before the direct insertion path,
    /// which stays byte-identical when the feature is disabled, no key is
    /// stored, or the transcript is empty.
    private func handleFinalTranscript(
        _ text: String,
        delivery: RecognitionPipelineDelivery?
    ) {
        let enabled = PostProcessingPreference.isEnabled()
        // `try?` over a `String?`-returning function nests optionals; the
        // explicit flatten keeps "no stored key" and "keychain denied"
        // distinct from "key present".
        let apiKeyAvailable = enabled
            && ((try? ProcessorKeychain.read()) ?? nil) != nil
        let route = PostProcessingReviewFlow.routeFinalTranscript(
            text,
            postProcessingEnabled: enabled,
            apiKeyAvailable: apiKeyAvailable,
            profile: PostProcessingPreference.selectedProfile(),
            protectedTerms: delivery?.protectedTerms ?? [],
            uncertainSpans: delivery?.uncertainSpans ?? [],
            internalDictionaryEntries: internalDictionary.entries,
            frontmostApp: NSWorkspace.shared.frontmostApplication?.localizedName
        )
        switch route {
        case .directInsert:
            process(.transcriptReady, transcript: text)
        case .voiceCommand(let command):
            handleVoiceCommand(command)
        case .review(let request):
            pendingReviewRequest = request
            process(.processingRequested)
        }
    }

    /// Local, deterministic command handling: commands never reach the
    /// processor and never make a network request.
    private func handleVoiceCommand(_ command: VoiceCommand) {
        switch command {
        case .setProfile(let profile):
            PostProcessingPreference.setProfile(profile)
            logger.info(
                "Post-processing profile changed to \(profile.rawValue, privacy: .public)"
            )
            process(.chunkedSessionFinished)

        case .scratchLastSegment, .cancel:
            process(.cancel)

        case .send:
            // Commands are only parsed on final-transcript delivery, so a
            // review is never pending here; the branch keeps the documented
            // accept-if-reviewing contract for any future call site.
            if machine.phase == .reviewing,
               let preview = presentedReviewPreview
            {
                reviewController?.dismiss()
                process(
                    .reviewAccepted,
                    transcript: PostProcessingReviewFlow.acceptedText(
                        for: preview
                    )
                )
            } else {
                process(.chunkedSessionFinished)
            }

        case .showOriginal:
            if machine.phase == .reviewing,
               let preview = presentedReviewPreview
            {
                reviewController?.dismiss()
                process(.reviewAccepted, transcript: preview.rawText)
            } else {
                process(.chunkedSessionFinished)
            }
        }
    }

    /// Falls back to the raw transcript when enhancement has not reported a
    /// result within its own request budget plus a margin. The deadline is
    /// derived from the same configuration the processor uses, so a legitimate
    /// slow thinking pass is never cut short — only a stuck one is.
    private func startReviewWatchdog(for request: PostProcessRequest) {
        reviewWatchdogTask?.cancel()
        let effort = DeepSeekReasoningEffort(
            rawValue: PostProcessingPreference.selectedReasoningEffort()
        ) ?? .low
        // Two attempts (the processor retries once) plus a margin.
        let deadline = DeepSeekConfiguration.timeout(
            thinkingEnabled: PostProcessingPreference.isThinkingEnabled(),
            reasoningEffort: effort
        ) * 2 + 5
        let generation = sessionGeneration
        let rawText = request.rawText
        reviewWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.sessionGeneration == generation,
                  self.machine.phase == .reviewing
            else {
                return
            }
            self.logger.error(
                "Post-processing did not report back within \(Int(deadline), privacy: .public)s; inserting the raw transcript"
            )
            PostProcessingPreference.recordLastRun(
                "no response in \(Int(deadline)) s — raw text inserted"
            )
            self.reviewSession?.cancel()
            self.reviewWatchdogTask = nil
            self.presentedReviewPreview = nil
            self.activeReviewRequest = nil
            self.process(.reviewAccepted, transcript: rawText)
        }
    }

    /// Presents one review preview through the shared review controller.
    /// The controller owns the key handling (Enter / Escape / Cmd+Z / Tab);
    /// this closure only maps its choices onto state-machine events and the
    /// existing delivery path.
    private func presentReview(_ preview: PostProcessPreview) {
        presentedReviewPreview = preview
        let controller: PostProcessReviewController
        if let existing = reviewController {
            controller = existing
        } else {
            let created = PostProcessReviewController(badge: badge)
            reviewController = created
            controller = created
        }
        controller.present(
            preview,
            accept: { [weak self] acceptedPreview, choice in
                guard let self else { return }
                self.reviewController?.dismiss()
                guard self.machine.phase == .reviewing else { return }
                self.presentedReviewPreview = nil
                switch choice {
                case .cancel:
                    self.process(.reviewCancelled)
                case .acceptProcessed:
                    self.process(
                        .reviewAccepted,
                        transcript: PostProcessingReviewFlow.acceptedText(
                            for: acceptedPreview
                        )
                    )
                case .restoreRaw:
                    self.process(
                        .reviewAccepted,
                        transcript: PostProcessingReviewFlow.restoredText(
                            for: acceptedPreview
                        )
                    )
                }
            },
            onProfileChange: { [weak self] newProfile in
                guard let self,
                      self.machine.phase == .reviewing,
                      let request = self.activeReviewRequest
                else {
                    return
                }
                let updated = PostProcessRequest(
                    rawText: request.rawText,
                    profile: newProfile,
                    locale: request.locale,
                    context: request.context,
                    alternatives: request.alternatives,
                    uncertainSpans: request.uncertainSpans,
                    protectedTerms: request.protectedTerms
                )
                self.activeReviewRequest = updated
                self.reviewSession?.start(
                    updated,
                    generation: self.sessionGeneration
                )
            }
        )
    }

    private func deliver(_ transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if deliversToInternalDictionaryDraft {
            insertionContext = nil
            deliversToInternalDictionaryDraft = false
            guard !trimmed.isEmpty else {
                fail(
                    "No speech detected.",
                    presentationDuration: BadgePresentationDuration.noSpeech
                )
                return false
            }
            advancedSettingsWindowController?
                .appendDictatedInternalDictionaryDraft(trimmed)
            lastDictation.retainSuccessful(trimmed)
            logger.info("Dictation added to dictionary draft")
            completionBehavior = .insert
            process(.deliveryFinished)
            return true
        }
        let result = delivery.deliver(
            transcript: transcript,
            context: insertionContext
        )
        insertionContext = nil

        switch result {
        case .inserted:
            lastDictation.retainSuccessful(trimmed)
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
        completionCaptureGraceTask?.cancel()
        completionCaptureGraceTask = nil
        pipelineBeginTask?.cancel()
        pipelineBeginTask = nil
        completionBehavior = .insert
        deliversToInternalDictionaryDraft = false
        pauseSessionDidInsert = false
        pauseBoundaryInProgress = false
        pauseSessionTranscript = nil
        pauseSessionPrompt = nil
        pauseDeliveryContext = nil
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
        primedAudioCaptureToken = nil
        primedBadgeVisible = false
        insertionContext = nil
        reviewSession?.cancel()
        reviewWatchdogTask?.cancel()
        reviewWatchdogTask = nil
        reviewController?.dismiss()
        pendingReviewRequest = nil
        activeReviewRequest = nil
        presentedReviewPreview = nil

        let precedingCleanup = recognizerCleanupTask
        let recognizer = recognizer
        let pipelineCoordinator = pipelineCoordinator
        recognizerCleanupTask = Task.detached(priority: .userInitiated) {
            if let precedingCleanup {
                await precedingCleanup.value
            }
            await pipelineCoordinator.cancel()
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
        // While a review is pending, PostProcessReviewController owns the
        // badge panel; no other state may replace its presentation.
        if machine.phase == .reviewing,
           presentation != .hidden,
           presentation != .enhancing
        {
            return
        }
        if presentation == .hidden {
            badgeAnchorResolutionTask?.cancel()
            badgeAnchorResolutionTask = nil
            badge.hide()
            badgeCaretRect = nil
            badgeFieldRect = nil
            return
        }
        if presentation == .listening {
            // Order the panel immediately at the pointer fallback. Exact AX
            // geometry is advisory and may block for hundreds of
            // milliseconds, so resolve it on the next MainActor turn after
            // capture/model work has already started.
            badgeCaretRect = nil
            badgeFieldRect = nil
            badge.present(.listening)
            badge.updateListening(
                elapsed: 0,
                limit: TimeInterval(recordingLimit.seconds),
                level: 0
            )
            scheduleInitialBadgeAnchorResolution()
            return
        }
        badge.present(
            presentation,
            caretFrame: badgeCaretRect,
            fieldFrame: badgeFieldRect
        )
    }

    private func scheduleInitialBadgeAnchorResolution() {
        badgeAnchorResolutionTask?.cancel()
        let generation = sessionGeneration
        badgeAnchorResolutionTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  generation == sessionGeneration,
                  machine.phase == .listening,
                  badge.acceptsAutomaticAnchorUpdates
            else {
                return
            }
            let anchor = contextProvider.currentBadgeAnchor()
            guard !Task.isCancelled,
                  generation == sessionGeneration,
                  machine.phase == .listening,
                  badge.updateAutomaticAnchor(
                    caretFrame: anchor.caretRect,
                    fieldFrame: anchor.fieldRect
                  )
            else {
                return
            }
            badgeCaretRect = anchor.caretRect
            badgeFieldRect = anchor.fieldRect
            badgeAnchorResolutionTask = nil
        }
    }

    private func startRecordingPresentation(
        generation: UInt64,
        limit: Int
    ) {
        recordingPresentationTask?.cancel()
        recordingSegmentationTask?.cancel()
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
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
        }

        // Segment rotation and decode submission have their own cadence. A
        // slow badge/Accessibility update must never delay a closed segment
        // from reaching the recognition actor, while the recorder runtime
        // continues accepting microphone buffers independently of both.
        recordingSegmentationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self,
                      generation == sessionGeneration,
                      machine.phase == .listening
                else {
                    return
                }
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
                    try await Task.sleep(for: .milliseconds(25))
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
        recordingSegmentationTask?.cancel()
        recordingSegmentationTask = nil
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
              completionCaptureGraceTask == nil,
              machine.phase == .preparing || machine.phase == .listening
        else {
            return
        }
        completionBehavior = behavior
        captureInsertionContext(suppliedContext)
        guard let grace = recorder.completionCaptureGrace else {
            process(.maximumDurationReached)
            return
        }
        let generation = sessionGeneration
        completionCaptureGraceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(grace))
            } catch {
                return
            }
            guard let self,
                  generation == sessionGeneration,
                  runtimeReadyForHotkey,
                  !isTerminating,
                  machine.phase == .preparing || machine.phase == .listening
            else {
                return
            }
            completionCaptureGraceTask = nil
            process(.maximumDurationReached)
        }
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
                hasLastDictation: lastDictation.transcript != nil
            )
            return
        }
        guard runtimeReadyForHotkey else {
            menuBarController.update(
                .unavailable,
                toggleDictationEnabled: effectiveToggleDictationEnabled,
                selectedHotkey: selectedHotkey,
                hasLastDictation: lastDictation.transcript != nil
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
        case .reviewing:
            // The review panel is the review surface; the menu bar keeps the
            // transcript-in-progress state while it is open.
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
            hasLastDictation: lastDictation.transcript != nil
        )
    }

    private var advancedSettingsState: AdvancedSettingsState {
        AdvancedSettingsState(
            selectedHotkey: selectedHotkey,
            activationMode: hotkeyActivationMode,
            selectedModel: selectedModel,
            selectedParakeetVariant: selectedParakeetVariant,
            selectedEngine: selectedEngine,
            decodingProfile: decodingProfile,
            processingMode: processingMode,
            internalDictionaryEntries: internalDictionary.entries,
            keepsLatestDictation: lastDictation.isEnabled,
            recordingLimit: recordingLimit,
            selectedTheme: selectedTheme,
            customThemes: customThemes,
            availableModels: availableModels,
            availableEngines: availableEngines,
            configurationEnabled: !machine.phase.isBusy,
            automaticallyChecksForUpdates: automaticallyChecksForUpdates,
            softwareUpdateStatus: softwareUpdateStatus,
            postProcessingEnabled: PostProcessingPreference.isEnabled(),
            postProcessingProfile: PostProcessingPreference.selectedProfile(),
            postProcessingModel: PostProcessingPreference.selectedModel(),
            postProcessingThinkingEnabled:
                PostProcessingPreference.isThinkingEnabled(),
            postProcessingCustomPrompt:
                PostProcessingPreference.customPrompt(),
            postProcessingCustomPromptNames:
                CustomPromptLibrary.prompts().map(\.name),
            postProcessingSelectedCustomPrompt:
                CustomPromptLibrary.selectedIndex(),
            postProcessingLastRun: PostProcessingPreference.lastRun(),
            postProcessingReasoningEffort:
                PostProcessingPreference.selectedReasoningEffort()
        )
    }

    /// Opens Settings once, on a genuinely new installation, so the hotkey,
    /// model, and behavior chosen by the first-run profile are visible instead
    /// of having to be discovered through the menu bar icon.
    private func showFirstRunSettingsIfNeeded() {
        let defaults = Self.preparedDefaults
        guard !defaults.bool(
            forKey: WhisperHotkeyPreferenceKeys.hasPresentedFirstRunSettings
        ) else {
            return
        }
        defaults.set(
            true,
            forKey: WhisperHotkeyPreferenceKeys.hasPresentedFirstRunSettings
        )
        showAdvancedSettings()
    }

    private func showAdvancedSettings() {
        // Deliberately not gated on `machine.phase.isBusy`. Opening a window is
        // not a configuration change: the state it publishes already carries
        // `configurationEnabled: !isBusy`, so every control arrives disabled
        // during a dictation. Refusing to open at all made the menu item do
        // nothing at exactly the moment a user reaches for it, with no
        // feedback to explain why.
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
                    selectParakeetVariant: { [weak self] variant in
                        self?.selectParakeetVariant(variant)
                    },
                    selectRecognitionPreset: { [weak self] preset in
                        self?.applyRecognitionPreset(preset)
                    },
                    selectRecognitionChoice: { [weak self] choice in
                        self?.applyRecognitionChoice(choice)
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
                    addInternalDictionaryEntries: { [weak self] entries in
                        self?.addInternalDictionaryEntries(entries)
                    },
                    removeInternalDictionaryEntry: { [weak self] entry in
                        self?.removeInternalDictionaryEntry(entry)
                    },
                    setKeepsLatestDictation: { [weak self] enabled in
                        self?.setKeepsLatestDictation(enabled)
                    },
                    selectRecordingLimit: { [weak self] limit in
                        self?.selectRecordingLimit(limit)
                    },
                    selectTheme: { [weak self] theme in
                        self?.selectTheme(theme)
                    },
                    saveCustomTheme: { [weak self] theme in
                        self?.saveCustomTheme(theme)
                    },
                    loginItemChanged: { [weak self] in
                        self?.setupWindowController.refresh()
                    },
                    setAutomaticallyChecksForUpdates: { [weak self] enabled in
                        self?.setAutomaticallyChecksForUpdates(enabled)
                    },
                    checkForUpdates: { [weak self] in
                        self?.checkForUpdates()
                    },
                    installUpdate: { [weak self] in
                        self?.installAvailableUpdate()
                    },
                    cancelModelInstall: { [weak self] in
                        self?.parakeetInstallTask?.cancel()
                    },
                    setPostProcessingEnabled: { [weak self] enabled in
                        self?.setPostProcessingEnabled(enabled)
                    },
                    selectPostProcessingProfile: { [weak self] profile in
                        self?.selectPostProcessingProfile(profile)
                    },
                    selectPostProcessingModel: { [weak self] model in
                        self?.selectPostProcessingModel(model)
                    },
                    setPostProcessingThinkingEnabled: { [weak self] enabled in
                        self?.setPostProcessingThinkingEnabled(enabled)
                    },
                    selectPostProcessingReasoningEffort: { [weak self] effort in
                        self?.selectPostProcessingReasoningEffort(effort)
                    },
                    setPostProcessingCustomPrompt: { [weak self] prompt in
                        self?.setPostProcessingCustomPrompt(prompt)
                    },
                    selectPostProcessingCustomPrompt: { [weak self] index in
                        guard self?.machine.phase.isBusy == false else { return }
                        CustomPromptLibrary.setSelectedIndex(index)
                    },
                    addPostProcessingCustomPrompt: { [weak self] in
                        guard self?.machine.phase.isBusy == false else { return }
                        let count = CustomPromptLibrary.prompts().count + 1
                        CustomPromptLibrary.add(
                            CustomPrompt(
                                name: "Prompt \(count)",
                                prompt: PostProcessingPreference
                                    .defaultCustomPrompt
                            )
                        )
                    },
                    removePostProcessingCustomPrompt: { [weak self] in
                        guard self?.machine.phase.isBusy == false else { return }
                        CustomPromptLibrary.removeSelected()
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

    private func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        AutomaticUpdateCheckPreference.setEnabled(enabled)
        advancedSettingsWindowController?.refreshIfVisible()
        if enabled {
            checkForUpdates()
        }
    }

    private func checkForUpdates() {
        guard softwareUpdateTask == nil else {
            return
        }
        softwareUpdateStatus = .checking
        availableSoftwareUpdate = nil
        advancedSettingsWindowController?.refreshIfVisible()
        let checker = softwareUpdateChecker
        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        softwareUpdateTask = Task { [weak self] in
            do {
                let result = try await checker.check(
                    currentVersion: currentVersion
                )
                guard let self, !Task.isCancelled else {
                    return
                }
                switch result {
                case .current:
                    softwareUpdateStatus = .current
                case .available(let release):
                    availableSoftwareUpdate = release
                    softwareUpdateStatus = .available(
                        version: release.version,
                        installable: release.isInstallable
                    )
                }
                softwareUpdateTask = nil
                advancedSettingsWindowController?.refreshIfVisible()
            } catch is CancellationError {
                self?.softwareUpdateTask = nil
            } catch {
                guard let self, !Task.isCancelled else {
                    return
                }
                softwareUpdateStatus = .failed
                softwareUpdateTask = nil
                advancedSettingsWindowController?.refreshIfVisible()
            }
        }
    }

    private func installAvailableUpdate() {
        guard softwareUpdateInstallationTask == nil,
              !machine.phase.isBusy,
              let release = availableSoftwareUpdate,
              release.isInstallable
        else {
            return
        }
        softwareUpdateStatus = .downloading
        advancedSettingsWindowController?.refreshIfVisible()
        // The disk image is over a hundred megabytes and the install then
        // mounts and verifies it, so the update reports progress instead of
        // leaving the menu bar looking stalled.
        let panel = ModelDownloadProgressPanel(
            title: "Updating to \(release.version)",
            totalByteCount: nil,
            onCancel: { [weak self] in
                self?.cancelSoftwareUpdateInstallation()
            }
        )
        panel.show()
        softwareUpdateProgressPanel = panel
        let installer = SoftwareUpdateInstaller(
            progress: { [weak self] written, total in
                Task { @MainActor in
                    self?.softwareUpdateProgressPanel?.update(
                        completedByteCount: written,
                        totalByteCount: total
                    )
                }
            }
        )
        let applicationURL = Bundle.main.bundleURL
        let installedVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        softwareUpdateInstallationTask = Task { [weak self] in
            do {
                let update = try await installer.prepare(
                    release: release,
                    installedApplicationURL: applicationURL,
                    installedVersion: installedVersion
                )
                guard let self, !Task.isCancelled else {
                    try? FileManager.default.removeItem(
                        at: update.cleanupDirectoryURL
                    )
                    return
                }
                softwareUpdateStatus = .installing
                // Verifying and copying the mounted app has no byte count to
                // report, so the bar stops claiming a percentage.
                softwareUpdateProgressPanel?.showIndeterminate(
                    "Verifying and installing…"
                )
                advancedSettingsWindowController?.refreshIfVisible()
                do {
                    try ApplicationRelauncher().scheduleUpdate(
                        update,
                        version: release.version
                    )
                } catch {
                    try? FileManager.default.removeItem(
                        at: update.cleanupDirectoryURL
                    )
                    throw error
                }
                softwareUpdateInstallationTask = nil
                dismissSoftwareUpdateProgress()
                NSApp.terminate(nil)
            } catch is CancellationError {
                self?.softwareUpdateInstallationTask = nil
                self?.dismissSoftwareUpdateProgress()
            } catch {
                guard let self, !Task.isCancelled else {
                    return
                }
                softwareUpdateStatus = .installationFailed
                softwareUpdateInstallationTask = nil
                dismissSoftwareUpdateProgress()
                advancedSettingsWindowController?.refreshIfVisible()
            }
        }
    }

    private func dismissSoftwareUpdateProgress() {
        softwareUpdateProgressPanel?.close()
        softwareUpdateProgressPanel = nil
    }

    private func cancelSoftwareUpdateInstallation() {
        softwareUpdateInstallationTask?.cancel()
        softwareUpdateInstallationTask = nil
        dismissSoftwareUpdateProgress()
        // Cancelling returns to the offer, not to a failure.
        if let release = availableSoftwareUpdate {
            softwareUpdateStatus = .available(
                version: release.version,
                installable: release.isInstallable
            )
        } else {
            softwareUpdateStatus = .idle
        }
        advancedSettingsWindowController?.refreshIfVisible()
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
        // The older boolean is still honoured for anyone who set it before
        // `dictationMode` existed. Only when neither key was ever written does
        // this fall through to the current default, which is Toggle: holding a
        // modifier for the length of a sentence is the step new users most
        // often fail to discover.
        guard defaults.object(forKey: "toggleDictationEnabled") != nil else {
            return .toggle
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
        guard !machine.phase.isBusy, selectedModel != model else {
            return
        }
        guard modelAvailable(model) else {
            // Selecting a model that was too large to bundle used to do
            // nothing at all. Offer to fetch it instead.
            offerModelDownload(model)
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

    private func selectParakeetVariant(_ variant: ParakeetVariant) {
        guard !machine.phase.isBusy, selectedParakeetVariant != variant else {
            return
        }
        guard ParakeetModelInstaller.isInstalled(variant) else {
            offerParakeetInstall(variant) { [weak self] installed in
                guard installed else { return }
                self?.selectParakeetVariant(variant)
            }
            return
        }
        selectedParakeetVariant = variant
        UserDefaults.standard.set(
            variant.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.parakeetModel
        )
        configureModelReadiness(reloadSelectedModel: true)
        reconcileRuntime(showSetupIfNeeded: false)
        setupWindowController.refresh()
    }

    /// Applies a preset by writing everything it resolves, in one step, so the
    /// configuration can never sit half-applied and read as Custom.
    private func applyRecognitionPreset(_ preset: RecognitionPreset) {
        guard !machine.phase.isBusy,
              RecognitionPreset.selectable.contains(preset)
        else {
            return
        }
        let resolution = preset.resolution
        guard ParakeetModelInstaller.isInstalled(resolution.parakeetVariant)
        else {
            // Both presets ship inside the app, so this only happens if the
            // bundled copy is missing. Offer the download rather than
            // selecting a configuration that cannot run.
            offerParakeetInstall(resolution.parakeetVariant) { [weak self] in
                guard $0 else { return }
                self?.applyRecognitionPreset(preset)
            }
            return
        }
        let defaults = UserDefaults.standard
        selectedParakeetVariant = resolution.parakeetVariant
        defaults.set(
            resolution.parakeetVariant.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.parakeetModel
        )
        selectedEngine = resolution.engine
        defaults.set(
            resolution.engine.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.recognitionEngine
        )
        processingMode = resolution.processingMode
        defaults.set(
            resolution.processingMode.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.modelProcessingMode
        )
        configureModelReadiness(reloadSelectedModel: true)
        reconcileRuntime(showSetupIfNeeded: false)
        setupWindowController.refresh()
        advancedSettingsWindowController?.refreshIfVisible()
        updateMenuBar()
    }

    /// Fetches a Parakeet checkpoint before it is selected, rather than during
    /// the first dictation that needs it. Downloading behind a Transcribing
    /// badge gave no progress, no cancel, and no timeout.
    private func offerParakeetInstall(
        _ variant: ParakeetVariant,
        completion: @escaping (Bool) -> Void
    ) {
        guard parakeetInstallTask == nil else {
            completion(false)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText =
            "Parakeet \(variant.displayName) is not installed."
        alert.informativeText = """
            This checkpoint is downloaded on first use rather than included in \
            the app. It is about \(variant.approximateDownloadDescription) and \
            is compiled for this Mac after the transfer.
            """
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(false)
            return
        }

        // Progress is reported inside Settings, which is the window the user
        // started this from. The floating panel is kept only as the fallback
        // for an install triggered from the menu bar with Settings closed.
        if let controller = advancedSettingsWindowController,
           controller.window?.isVisible == true {
            controller.beginModelInstall(
                title: "Preparing Parakeet \(variant.displayName)…"
            )
        } else {
            let panel = ModelDownloadProgressPanel(
                title: "Downloading Parakeet \(variant.displayName)",
                totalByteCount: nil
            ) { [weak self] in
                self?.parakeetInstallTask?.cancel()
            }
            panel.show()
            parakeetInstallPanel = panel
        }

        // The progress handler is called off the main actor, so it hops back
        // through a box that holds one weak reference rather than capturing
        // the enclosing optional.
        let owner = ParakeetInstallObserver(delegate: self)
        parakeetInstallTask = Task { [weak self] in
            var failure: String?
            var cancelled = false
            do {
                try await ParakeetModelInstaller.install(variant) { phase in
                    owner.report(phase)
                }
            } catch is CancellationError {
                cancelled = true
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                guard let self else { return }
                self.finishParakeetInstall()
                if let failure {
                    self.presentInstallFailure(
                        "Parakeet \(variant.displayName)",
                        message: failure
                    )
                }
            }
            completion(failure == nil && !cancelled)
        }
    }

    /// Applies one option from the flat recognition list, writing whichever of
    /// the three underlying preferences it implies. Routed through the existing
    /// selectors so install offers, availability and readiness all still apply.
    private func applyRecognitionChoice(_ choice: RecognitionChoice) {
        guard !machine.phase.isBusy else { return }
        switch choice.engine {
        case .parakeetCoreML:
            selectParakeetVariant(choice.parakeetVariant)
        case .whisperCppMetal:
            selectModel(choice.model)
        }
        selectEngine(choice.engine)
    }

    /// Slices of the single bar the user sees. Downloading owns most of it
    /// because it is by far the longest phase and the only one that reports a
    /// real measurement; compiling and the first load are estimated.
    private enum InstallStage {
        static let downloading = 0.0...0.85
        static let compiling = 0.85...0.97
        static let loading = 0.97...1.0
        /// Measured on an M-series Mac for the 0.6B checkpoints. Only used to
        /// pace the bar; the phase ends when it ends.
        static let compileSeconds: TimeInterval = 25
        static let loadSeconds: TimeInterval = 4
    }

    fileprivate func updateParakeetInstallPanel(
        _ phase: ParakeetModelInstaller.Phase
    ) {
        let inWindow = advancedSettingsWindowController?.window?.isVisible
            == true
        switch phase {
        case let .downloading(fraction):
            if inWindow {
                advancedSettingsWindowController?.updateModelInstall(
                    fraction: fraction,
                    in: InstallStage.downloading,
                    detail: "Downloading… \(Int(fraction * 100))%"
                )
            } else {
                parakeetInstallPanel?.update(
                    completedByteCount: Int64(fraction * 1000),
                    totalByteCount: 1000
                )
            }
        case .compiling:
            if inWindow {
                advancedSettingsWindowController?.estimateModelInstall(
                    over: InstallStage.compileSeconds,
                    in: InstallStage.compiling,
                    detail: "Compiling for this Mac…"
                )
            } else {
                parakeetInstallPanel?.showIndeterminate(
                    "Compiling for this Mac…"
                )
            }
        }
    }

    private func finishParakeetInstall() {
        parakeetInstallPanel?.close()
        parakeetInstallPanel = nil
        parakeetInstallTask = nil
        advancedSettingsWindowController?.finishModelInstall()
    }

    fileprivate func presentInstallFailure(
        _ subject: String,
        message: String
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(subject) could not be installed."
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Names whichever model the active engine actually runs. Parakeet keeps
    /// its own selection, so reporting the whisper model there would be wrong.
    private var activeModelSummary: String {
        if selectedEngine == .parakeetCoreML {
            return "\(selectedEngine.displayName) "
                + selectedParakeetVariant.displayName
        }
        return "\(selectedModel.displayName), \(selectedEngine.displayName)"
    }

    /// Fetches a model that did not fit in the download, then selects it.
    private func offerModelDownload(_ model: DictationModel) {
        guard let entry = ModelDownloadCatalog.entry(for: model),
              modelDownloadController == nil
        else {
            return
        }
        let controller = ModelDownloadController(entry: entry)
        modelDownloadController = controller
        controller.confirmAndStart { [weak self] result in
            guard let self else {
                return
            }
            modelDownloadController = nil
            switch result {
            case .success:
                advancedSettingsWindowController?.refreshIfVisible()
                selectModel(model)
            case .failure(.cancelled):
                break
            case let .failure(error):
                presentModelDownloadFailure(model, error: error)
            }
        }
    }

    private func presentModelDownloadFailure(
        _ model: DictationModel,
        error: ModelDownloadError
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(model.menuTitle) could not be installed."
        switch error {
        case .checksumMismatch:
            alert.informativeText = """
                The downloaded file did not match its expected checksum and \
                was discarded. Nothing was installed.
                """
        case let .transportFailed(detail):
            alert.informativeText = "The download did not finish.\n\n\(detail)"
        case let .installFailed(detail):
            alert.informativeText = detail
        case .notDownloadable, .cancelled:
            alert.informativeText = "The download did not finish."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func selectEngine(_ engine: RecognitionEngine) {
        guard !machine.phase.isBusy,
              selectedEngine != engine,
              let model = resolvedModel(for: engine)
        else {
            return
        }
        // Carry the engine to a model it can actually run rather than refusing
        // the switch, which would strand the user on the current engine.
        if model != selectedModel {
            selectedModel = model
            UserDefaults.standard.set(
                model.rawValue,
                forKey: WhisperHotkeyPreferenceKeys.dictationModel
            )
        }
        if engine == .parakeetCoreML,
           !ParakeetModelInstaller.isInstalled(selectedParakeetVariant) {
            let variant = selectedParakeetVariant
            offerParakeetInstall(variant) { [weak self] installed in
                guard installed else { return }
                self?.selectEngine(engine)
            }
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
              selectedEngine.usesWhisperDecoding,
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

    private func setPostProcessingEnabled(_ enabled: Bool) {
        guard !machine.phase.isBusy else { return }
        PostProcessingPreference.setEnabled(enabled)
        updateMenuBar()
    }

    private func selectPostProcessingProfile(_ profile: SemanticProfileID) {
        guard !machine.phase.isBusy else { return }
        PostProcessingPreference.setProfile(profile)
        updateMenuBar()
    }

    private func selectPostProcessingModel(_ model: String) {
        guard !machine.phase.isBusy else { return }
        PostProcessingPreference.setModel(model)
        updateMenuBar()
    }

    private func setPostProcessingThinkingEnabled(_ enabled: Bool) {
        guard !machine.phase.isBusy else { return }
        PostProcessingPreference.setThinkingEnabled(enabled)
        updateMenuBar()
    }

    private func selectPostProcessingReasoningEffort(_ effort: String) {
        guard !machine.phase.isBusy else { return }
        PostProcessingPreference.setReasoningEffort(effort)
        updateMenuBar()
    }

    private func setPostProcessingCustomPrompt(_ prompt: String) {
        guard !machine.phase.isBusy else { return }
        PostProcessingPreference.setCustomPrompt(prompt)
        updateMenuBar()
    }

    private func addInternalDictionaryEntries(_ entries: [String]) {
        guard !machine.phase.isBusy else {
            return
        }
        let updated = internalDictionary.adding(entries)
        guard updated != internalDictionary else {
            return
        }
        internalDictionary = updated
        updated.persist()
        advancedSettingsWindowController?.refreshIfVisible()
    }

    private func removeInternalDictionaryEntry(_ entry: String) {
        guard !machine.phase.isBusy else {
            return
        }
        let updated = internalDictionary.removing(entry)
        guard updated != internalDictionary else {
            return
        }
        internalDictionary = updated
        updated.persist()
        advancedSettingsWindowController?.refreshIfVisible()
    }

    private func setKeepsLatestDictation(_ enabled: Bool) {
        guard !machine.phase.isBusy,
              lastDictation.isEnabled != enabled
        else {
            return
        }
        lastDictation.setEnabled(enabled)
        LastDictationRetentionPreference.setEnabled(enabled)
        updateMenuBar()
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

    private func selectTheme(_ theme: BadgeThemeSelection) {
        guard !machine.phase.isBusy, selectedTheme != theme else {
            return
        }
        selectedTheme = theme
        theme.persist()
        badge.applyTheme(theme)
        advancedSettingsWindowController?.refreshIfVisible()
    }

    private func saveCustomTheme(_ theme: CustomBadgeTheme) {
        guard !machine.phase.isBusy else {
            return
        }
        if let index = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[index] = theme
        } else {
            guard customThemes.count < CustomBadgeTheme.maximumCount else {
                return
            }
            customThemes.append(theme)
        }
        CustomBadgeTheme.persist(customThemes)
        selectedTheme = .custom(theme)
        selectedTheme.persist()
        badge.applyTheme(selectedTheme)
        advancedSettingsWindowController?.refreshIfVisible()
    }

    private func copyLastDictation() {
        guard lastDictation.isEnabled,
              let transcript = lastDictation.transcript
        else {
            return
        }
        if !delivery.copyToClipboard(transcript) {
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
        softwareUpdateTask?.cancel()
        softwareUpdateTask = nil
        softwareUpdateInstallationTask?.cancel()
        softwareUpdateInstallationTask = nil
        let pendingWork = PendingRecognizerWork(
            precedingCleanup: recognizerCleanupTask,
            modelConfiguration: modelConfigurationTask,
            preload: preloadTask,
            recognition: recognitionTask,
            pipeline: Task.detached { [pipelineCoordinator] in
                await pipelineCoordinator.cancel()
            }
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
        badgeAnchorResolutionTask?.cancel()
        badgeAnchorResolutionTask = nil
        submitAfterPasteTask?.cancel()
        submitAfterPasteTask = nil
        completionCaptureGraceTask?.cancel()
        completionCaptureGraceTask = nil
        captureTimingTask?.cancel()
        captureTimingTask = nil
        pipelineBeginTask?.cancel()
        pipelineBeginTask = nil
        completionBehavior = .insert
        deliversToInternalDictionaryDraft = false
        pauseSessionDidInsert = false
        pauseBoundaryInProgress = false
        pauseSessionTranscript = nil
        pauseSessionPrompt = nil
        pauseDeliveryContext = nil
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
        primedAudioCaptureToken = nil
        primedBadgeVisible = false
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
            helperAvailable: helperAvailable,
            engine: selectedEngine
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
            model: activeModelSummary,
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

    /// An engine counts as available when it can run with some installed
    /// model, not only with the one currently selected. Gating on the selected
    /// model alone created a dead end: with an uninstalled whisper model
    /// selected, every whisper engine greyed out, and because the Model row
    /// shows Parakeet's own checkpoints while Parakeet is active there was no
    /// way left in the window to choose an installed whisper model again.
    private var availableEngines: Set<RecognitionEngine> {
        Set(RecognitionEngine.allCases.filter { engine in
            DictationModel.allCases.contains {
                engineAvailable(engine, model: $0)
            }
        })
    }

    /// The selected model when the engine can run it, otherwise the first
    /// installed one. Returns nil when the engine has no usable model at all.
    private func resolvedModel(
        for engine: RecognitionEngine
    ) -> DictationModel? {
        if engineAvailable(engine, model: selectedModel) {
            return selectedModel
        }
        return DictationModel.allCases.first {
            engineAvailable(engine, model: $0)
        }
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
        if !selectedEngine.usesLocalHelper {
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

    /// Registers the app with TCC for `kTCCServiceListenEvent`.
    ///
    /// An app has no row in the Input Monitoring list until it asks for the
    /// permission at least once, and there is no row to switch on for an app
    /// that never asked. Nothing called this outside the setup window's
    /// button, so an install that had never pressed that button could not be
    /// granted the permission from System Settings at all. Asking here makes
    /// the row exist. The system prompts at most once and the call is cheap
    /// after that, so running it on every reconcile is safe.
    private func registerForInputMonitoringIfNeeded() {
        guard !hasRequestedInputMonitoringRegistration,
              SystemPermissionController.preflight().inputMonitoring != .granted
        else {
            return
        }
        hasRequestedInputMonitoringRegistration = true
        _ = SystemPermissionController.requestInputMonitoring()
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
        let activeModel = try? WhisperRuntimeDiscovery.discover(
            model: selectedModel,
            engine: selectedEngine,
            parakeetVariant: selectedParakeetVariant
        ).modelURL
        reveal(
            activeModel ?? WhisperHotkeyPaths.modelURL(for: selectedModel),
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
            if selectedEngine == .parakeetCoreML {
                return "Parakeet model missing: open Settings."
            }
            return "Whisper model missing: run setup."
        case .helperUnavailable, .commandLineUnavailable:
            return "Whisper tools missing: run setup."
        case .microphoneUnavailable, .captureFailed, .noActiveRecording:
            return "Microphone failed: run setup."
        case .recognitionTimedOut:
            return "Transcription timed out."
        case .helperProtocolFailure, .helperFailed, .commandLineFailed,
            .modelInstallFailed:
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

/// Forwards install progress from FluidAudio's arbitrary queue to the delegate
/// on the main actor. Exists so the progress closure captures one weak
/// reference instead of the delegate's own mutable `self`.
private final class ParakeetInstallObserver: @unchecked Sendable {
    private weak var delegate: WhisperHotkeyApplicationDelegate?

    init(delegate: WhisperHotkeyApplicationDelegate) {
        self.delegate = delegate
    }

    func report(_ phase: ParakeetModelInstaller.Phase) {
        Task { @MainActor [weak delegate] in
            delegate?.updateParakeetInstallPanel(phase)
        }
    }
}

// MARK: - Post-processing review flow

/// Decision core for the post-processing review flow, kept free of UI and
/// network so WhisperHotkeyAppTests can drive it with a stubbed processor.
enum PostProcessingReviewFlow {
    /// Where one final transcript goes: straight to the existing insertion
    /// path, to a local voice command, or into a post-processing review.
    enum FinalTranscriptRoute: Equatable {
        case directInsert(String)
        case voiceCommand(VoiceCommand)
        case review(PostProcessRequest)
    }

    /// The review gate: commands run only when the feature is enabled and a
    /// key is available, so the disabled path stays byte-identical to today.
    /// The trimmed-transcript check mirrors the direct path's empty check.
    static func routeFinalTranscript(
        _ transcript: String,
        postProcessingEnabled: Bool,
        apiKeyAvailable: Bool,
        profile: SemanticProfileID,
        protectedTerms: [String],
        uncertainSpans: [String],
        internalDictionaryEntries: [String],
        frontmostApp: String?
    ) -> FinalTranscriptRoute {
        let trimmed = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard postProcessingEnabled, apiKeyAvailable else {
            return .directInsert(transcript)
        }
        if let command = VoiceCommandParser.parse(transcript) {
            return .voiceCommand(command)
        }
        guard !trimmed.isEmpty else {
            return .directInsert(transcript)
        }
        let request = PostProcessRequest(
            rawText: transcript,
            profile: profile,
            locale: "en-US",
            context: PostProcessContext(frontmostApp: frontmostApp),
            alternatives: [],
            uncertainSpans: uncertainSpans,
            protectedTerms: protectedTerms.isEmpty
                ? internalDictionaryEntries
                : protectedTerms
        )
        return .review(request)
    }

    /// The text accepting a review delivers through the existing clipboard
    /// transaction + Command-V path. An unavailable preview has no processed
    /// result, so accepting inserts the raw transcript.
    static func acceptedText(for preview: PostProcessPreview) -> String {
        preview.processed?.finalText ?? preview.rawText
    }

    /// The text restoring the raw transcript delivers.
    static func restoredText(for preview: PostProcessPreview) -> String {
        preview.rawText
    }

    /// A short, privacy-safe reason for the Settings status row: error codes
    /// only, never transcript text.
    static func describe(_ error: any Error) -> String {
        guard let processorError = error as? ProcessorError else {
            return "unexpected error"
        }
        switch processorError {
        case .missingKey:
            return "no API key"
        case .transport(let code):
            return code == .timedOut ? "timed out" : "network \(code.rawValue)"
        case .httpStatus(let status):
            return "HTTP \(status)"
        case .emptyOutput:
            return "empty model output"
        case .invalidOutput:
            return "unreadable model output"
        }
    }

    /// Runs the processor and builds the preview shown by the review panel.
    /// Any failure — transport, timeout, validation — yields the
    /// unavailable state, in which the raw transcript is shown and Enter
    /// still inserts it.
    static func process(
        request: PostProcessRequest,
        using processor: any TranscriptProcessor
    ) async -> PostProcessPreview {
        let started = Date()
        do {
            let result = try await processor.process(request)
            try PostProcessLimits.validateResult(result)
            let report = PreservationChecker.report(request, result)
            PostProcessingPreference.recordLastRun(
                String(
                    format: "enhanced in %.1f s",
                    Date().timeIntervalSince(started)
                )
            )
            return PostProcessPreview(
                rawText: request.rawText,
                processed: result,
                report: report,
                profile: request.profile,
                unavailable: false
            )
        } catch {
            PostProcessingPreference.recordLastRun(
                "failed (\(describe(error))) — raw text inserted"
            )
            return PostProcessPreview(
                rawText: request.rawText,
                processed: nil,
                report: PreservationReport(issues: [], pass: false),
                profile: request.profile,
                unavailable: true
            )
        }
    }
}

/// Owns one in-flight processing task per review. Results that settle after
/// the session was invalidated (cancel, a newer session) are never presented.
@MainActor
final class PostProcessingReviewSession {
    private let processor: any TranscriptProcessor
    private let isSessionCurrent: (UInt64) -> Bool
    private let onPreview: (PostProcessPreview) -> Void
    private var processingTask: Task<Void, Never>?

    init(
        processor: any TranscriptProcessor,
        isSessionCurrent: @escaping (UInt64) -> Bool,
        onPreview: @escaping (PostProcessPreview) -> Void
    ) {
        self.processor = processor
        self.isSessionCurrent = isSessionCurrent
        self.onPreview = onPreview
    }

    func start(_ request: PostProcessRequest, generation: UInt64) {
        processingTask?.cancel()
        processingTask = Task { [weak self, processor] in
            let preview = await PostProcessingReviewFlow.process(
                request: request,
                using: processor
            )
            guard !Task.isCancelled,
                  let self,
                  self.isSessionCurrent(generation)
            else {
                return
            }
            self.onPreview(preview)
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
    }
}
