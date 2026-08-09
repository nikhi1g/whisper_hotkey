import Foundation
import WhisperHotkeyCore

/// The raw evidence fields that can contribute to a word error estimate.
///
/// The list is intentionally provider-neutral.  A provider adapter may expose
/// only a subset of these fields; the estimator records the rest as missing
/// instead of treating them as low confidence or inventing values.
public enum ConfidenceFeatureID: String, CaseIterable, Codable, Hashable, Sendable {
    case posterior
    case minimumTokenProbability
    case meanTokenLogProbability
    case geometricMeanTokenProbability
    case entropy
    case beamScore
    case beamRank
    case wordDurationSeconds
    case boundaryProximity
    case noSpeechProbability
    case weakTokenFraction
    case repetitionRisk
    case truncationRisk
    case decodeTemperature
    case fallbackTemperatureCount
    case nBestDisagreement
    case crossEngineDisagreement
}

/// Why a confidence feature is unavailable.  Missing evidence is observable
/// in the feature vector and is never converted into a confidence penalty.
public enum ConfidenceMissingReason: String, Codable, Hashable, Sendable {
    case providerDidNotExpose
    case wordTimingUnavailable
    case utteranceEvidenceUnavailable
    case complementaryResultUnavailable
    case alternativeUnavailable
    case invalidValue
}

/// A bounded, content-free feature vector for one recognized word.
public struct ConfidenceFeatures: Codable, Hashable, Sendable {
    public let calibrationKey: ConfidenceCalibrationKey
    public let wordID: StableWordID?
    public let values: [ConfidenceFeatureID: Double]
    public let missing: [ConfidenceFeatureID: ConfidenceMissingReason]

    public init(
        calibrationKey: ConfidenceCalibrationKey,
        wordID: StableWordID? = nil,
        values: [ConfidenceFeatureID: Double] = [:],
        missing: [ConfidenceFeatureID: ConfidenceMissingReason] = [:]
    ) {
        precondition(values.count <= ConfidenceFeatureID.allCases.count)
        precondition(missing.count <= ConfidenceFeatureID.allCases.count)
        precondition(Set(values.keys).isDisjoint(with: Set(missing.keys)))
        self.calibrationKey = calibrationKey
        self.wordID = wordID
        self.values = values
        self.missing = missing
    }

    public var availableFeatureIDs: [ConfidenceFeatureID] {
        ConfidenceFeatureID.allCases.filter { values[$0] != nil }
    }

    public var missingFeatureIDs: [ConfidenceFeatureID] {
        ConfidenceFeatureID.allCases.filter { missing[$0] != nil }
    }

    public var availableFeatureCount: Int { values.count }

    public var missingFeatureCount: Int { missing.count }

    public func value(for feature: ConfidenceFeatureID) -> Double? {
        values[feature]
    }

    public func missingReason(
        for feature: ConfidenceFeatureID
    ) -> ConfidenceMissingReason? {
        missing[feature]
    }

    public func has(_ feature: ConfidenceFeatureID) -> Bool {
        values[feature] != nil
    }

    /// Stable field order for benchmark serialization and diagnostics.
    public var orderedValues: [(ConfidenceFeatureID, Double)] {
        ConfidenceFeatureID.allCases.compactMap { feature in
            values[feature].map { (feature, $0) }
        }
    }

    /// Stable missing-field order for benchmark serialization and diagnostics.
    public var orderedMissing: [
        (ConfidenceFeatureID, ConfidenceMissingReason)
    ] {
        ConfidenceFeatureID.allCases.compactMap { feature in
            missing[feature].map { (feature, $0) }
        }
    }
}

/// Identifies the exact provider/runtime profile for a calibration artifact.
/// Calibrators are never silently shared across different keys.
public struct ConfidenceCalibrationKey: Codable, Hashable, Sendable {
    public let engine: RecognitionEngineID
    public let modelIdentifier: String
    public let modelVersion: String?
    public let quantization: String?
    public let computeUnits: String?
    public let decodingProfile: String
    public let runtimeVersion: String?

    public init(
        engine: RecognitionEngineID,
        modelIdentifier: String,
        modelVersion: String? = nil,
        quantization: String? = nil,
        computeUnits: String? = nil,
        decodingProfile: String = DecodingProfile.defaultProfile.rawValue,
        runtimeVersion: String? = nil
    ) {
        precondition(!modelIdentifier.isEmpty)
        precondition(!decodingProfile.isEmpty)
        self.engine = engine
        self.modelIdentifier = modelIdentifier
        self.modelVersion = modelVersion
        self.quantization = quantization
        self.computeUnits = computeUnits
        self.decodingProfile = decodingProfile
        self.runtimeVersion = runtimeVersion
    }

    public init(
        engine: RecognitionEngineID,
        model: ModelIdentity,
        decodingProfile: String = DecodingProfile.defaultProfile.rawValue,
        runtimeVersion: String? = nil
    ) {
        self.init(
            engine: engine,
            modelIdentifier: model.identifier,
            modelVersion: model.version,
            quantization: model.quantization,
            computeUnits: model.computeUnits,
            decodingProfile: decodingProfile,
            runtimeVersion: runtimeVersion
        )
    }

    public var modelID: String { modelIdentifier }

    public var profile: String { decodingProfile }

    /// Builds a key from the metadata carried by a provider-neutral result.
    /// A missing strategy is retained as `unknown`; it is not replaced with a
    /// universal default that could mix precision and adaptive decodes.
    public init(result: RecognitionResult, runtimeVersion: String? = nil) {
        self.init(
            engine: result.engine,
            model: result.model,
            decodingProfile: Self.normalizedProfile(
                result.passMetadata.strategy
            ),
            runtimeVersion: runtimeVersion
        )
    }

    private static func normalizedProfile(_ strategy: String?) -> String {
        switch strategy?.lowercased() {
        case "beam", "precision":
            return DecodingProfile.precision.rawValue
        case "adaptive", "greedy", "smartdecode", "smart_decode":
            return DecodingProfile.adaptive.rawValue
        case let strategy? where !strategy.isEmpty:
            return strategy
        default:
            return "unknown"
        }
    }
}

/// Raw, intentionally uncalibrated error estimate.
public struct ConfidenceRawEstimate: Codable, Hashable, Sendable {
    public let rawErrorProbability: Double?
    public let features: ConfidenceFeatures
    public let usedFeatureIDs: [ConfidenceFeatureID]

    public init(
        rawErrorProbability: Double?,
        features: ConfidenceFeatures,
        usedFeatureIDs: [ConfidenceFeatureID]
    ) {
        self.rawErrorProbability = rawErrorProbability
        self.features = features
        self.usedFeatureIDs = usedFeatureIDs
    }

    public var rawCorrectProbability: Double? {
        rawErrorProbability.map { 1 - $0 }
    }

    public var isCalibrated: Bool { false }

    public var hasProbabilityEvidence: Bool {
        rawErrorProbability != nil
    }
}

public enum ConfidenceCalibrationStatus: String, Codable, Hashable, Sendable {
    case calibrated
    case uncalibrated
    case noEvidence
    case calibrationKeyMismatch
}

/// Combined raw and calibrated estimate for one word.
public struct ConfidenceEstimate: Codable, Hashable, Sendable {
    public let raw: ConfidenceRawEstimate
    public let calibratedErrorProbability: Double?
    public let status: ConfidenceCalibrationStatus

    public init(
        raw: ConfidenceRawEstimate,
        calibratedErrorProbability: Double? = nil,
        status: ConfidenceCalibrationStatus
    ) {
        self.raw = raw
        self.calibratedErrorProbability = calibratedErrorProbability
        self.status = status
    }

    public var errorProbability: Double? {
        calibratedErrorProbability ?? raw.rawErrorProbability
    }

    public var correctProbability: Double? {
        errorProbability.map { 1 - $0 }
    }

    public var isCalibrated: Bool { status == .calibrated }

    public var isUnknown: Bool { status == .noEvidence }
}

/// Labeled calibration input.  Fitting accepts only the `.calibration`
/// split; validation and test labels can be evaluated but never tune a model.
public struct ConfidenceCalibrationExample: Codable, Hashable, Sendable {
    public let key: ConfidenceCalibrationKey
    public let rawErrorProbability: Double
    public let isError: Bool
    public let split: ConfidenceCalibrationSplit

    public init(
        key: ConfidenceCalibrationKey,
        rawErrorProbability: Double,
        isError: Bool,
        split: ConfidenceCalibrationSplit = .calibration
    ) {
        precondition(rawErrorProbability.isFinite)
        precondition((0...1).contains(rawErrorProbability))
        self.key = key
        self.rawErrorProbability = rawErrorProbability
        self.isError = isError
        self.split = split
    }

    public init(
        rawErrorProbability: Double,
        isError: Bool,
        key: ConfidenceCalibrationKey,
        split: ConfidenceCalibrationSplit = .calibration
    ) {
        self.init(
            key: key,
            rawErrorProbability: rawErrorProbability,
            isError: isError,
            split: split
        )
    }

    public init(
        key: ConfidenceCalibrationKey,
        rawProbability: Double,
        labelIsError: Bool,
        split: ConfidenceCalibrationSplit = .calibration
    ) {
        self.init(
            key: key,
            rawErrorProbability: rawProbability,
            isError: labelIsError,
            split: split
        )
    }

    public var rawProbability: Double { rawErrorProbability }

    public var label: Bool { isError }
}

public enum ConfidenceCalibrationSplit: String, Codable, Hashable, Sendable {
    case calibration
    case validation
    case test
}

public enum ConfidenceCalibrationMethod: String, Codable, Hashable, Sendable {
    case temperature
    case platt
    case isotonic
}

public enum ConfidenceCalibrationError: Error, Equatable, Sendable {
    case noLabeledExamples
    case insufficientClassCoverage
    case calibrationSplitRequired
    case mixedCalibrationKeys
    case tooManyExamples
    case invalidProbability
    case invalidTemperature
}

public struct IsotonicCalibrationPoint: Codable, Hashable, Sendable {
    public let maximumRawErrorProbability: Double
    public let calibratedErrorProbability: Double

    public init(
        maximumRawErrorProbability: Double,
        calibratedErrorProbability: Double
    ) {
        precondition(maximumRawErrorProbability.isFinite)
        precondition((0...1).contains(maximumRawErrorProbability))
        precondition(calibratedErrorProbability.isFinite)
        precondition((0...1).contains(calibratedErrorProbability))
        self.maximumRawErrorProbability = maximumRawErrorProbability
        self.calibratedErrorProbability = calibratedErrorProbability
    }
}

/// Deterministic post-hoc calibration model.
public struct ConfidenceCalibrator: Codable, Hashable, Sendable {
    public let method: ConfidenceCalibrationMethod
    public let key: ConfidenceCalibrationKey
    public let version: String
    public let fittedExampleCount: Int
    public let temperature: Double?
    public let plattSlope: Double?
    public let plattIntercept: Double?
    public let isotonicPoints: [IsotonicCalibrationPoint]

    private init(
        method: ConfidenceCalibrationMethod,
        key: ConfidenceCalibrationKey,
        version: String,
        fittedExampleCount: Int,
        temperature: Double? = nil,
        plattSlope: Double? = nil,
        plattIntercept: Double? = nil,
        isotonicPoints: [IsotonicCalibrationPoint] = []
    ) {
        precondition(!version.isEmpty)
        precondition(fittedExampleCount > 0)
        self.method = method
        self.key = key
        self.version = version
        self.fittedExampleCount = fittedExampleCount
        self.temperature = temperature
        self.plattSlope = plattSlope
        self.plattIntercept = plattIntercept
        self.isotonicPoints = isotonicPoints
    }

    public func calibrate(rawErrorProbability: Double) -> Double {
        let raw = Self.clampProbability(rawErrorProbability)
        switch method {
        case .temperature:
            let temperature = max(self.temperature ?? 1, 0.000_001)
            return Self.sigmoid(Self.logit(raw) / temperature)
        case .platt:
            let slope = plattSlope ?? 1
            let intercept = plattIntercept ?? 0
            return Self.sigmoid(slope * Self.logit(raw) + intercept)
        case .isotonic:
            guard !isotonicPoints.isEmpty else { return raw }
            return isotonicPoints.first {
                raw <= $0.maximumRawErrorProbability
            }?.calibratedErrorProbability ?? isotonicPoints.last!.calibratedErrorProbability
        }
    }

    public func calibrate(
        rawErrorProbability: Double,
        for calibrationKey: ConfidenceCalibrationKey
    ) -> Double? {
        guard key == calibrationKey else { return nil }
        return calibrate(rawErrorProbability: rawErrorProbability)
    }

    public static func fitTemperature(
        examples: [ConfidenceCalibrationExample],
        key: ConfidenceCalibrationKey,
        version: String = "w05-temperature-v1"
    ) throws -> Self {
        let selected = try calibrationExamples(examples, key: key)
        let scores = selected.map(\.rawErrorProbability)
        let labels = selected.map { $0.isError ? 1.0 : 0.0 }

        // Temperature is optimized in log-space with a fixed ternary search.
        // The bounded search is deterministic and avoids a platform-specific
        // optimizer while remaining stable for small synthetic calibration
        // splits.
        var low = log(0.05)
        var high = log(20.0)
        for _ in 0..<80 {
            let first = low + (high - low) / 3
            let second = high - (high - low) / 3
            let firstLoss = temperatureLoss(
                scores: scores,
                labels: labels,
                temperature: exp(first)
            )
            let secondLoss = temperatureLoss(
                scores: scores,
                labels: labels,
                temperature: exp(second)
            )
            if firstLoss <= secondLoss {
                high = second
            } else {
                low = first
            }
        }
        let temperature = exp((low + high) / 2)
        guard temperature.isFinite, temperature > 0 else {
            throw ConfidenceCalibrationError.invalidTemperature
        }
        return Self(
            method: .temperature,
            key: key,
            version: version,
            fittedExampleCount: selected.count,
            temperature: temperature
        )
    }

    public static func fitPlatt(
        examples: [ConfidenceCalibrationExample],
        key: ConfidenceCalibrationKey,
        version: String = "w05-platt-v1"
    ) throws -> Self {
        let selected = try calibrationExamples(examples, key: key)
        let scores = selected.map { Self.logit($0.rawErrorProbability) }
        let labels = selected.map { $0.isError ? 1.0 : 0.0 }

        // A two-parameter logistic model fitted with deterministic Newton
        // steps.  A tiny L2 term keeps near-separable synthetic fixtures
        // finite without changing the post-hoc nature of the calibration.
        let regularization = 0.001
        var slope = 1.0
        var intercept = 0.0
        for _ in 0..<100 {
            var gradientSlope = regularization * slope
            var gradientIntercept = regularization * intercept
            var hessianSS = regularization
            var hessianSI = 0.0
            var hessianII = regularization

            for (score, label) in zip(scores, labels) {
                let probability = Self.sigmoid(slope * score + intercept)
                let residual = probability - label
                let curvature = max(probability * (1 - probability), 1e-9)
                gradientSlope += residual * score
                gradientIntercept += residual
                hessianSS += curvature * score * score
                hessianSI += curvature * score
                hessianII += curvature
            }

            let determinant = hessianSS * hessianII - hessianSI * hessianSI
            guard determinant.isFinite, abs(determinant) > 1e-12 else {
                break
            }
            let deltaSlope = (
                hessianII * gradientSlope - hessianSI * gradientIntercept
            ) / determinant
            let deltaIntercept = (
                -hessianSI * gradientSlope + hessianSS * gradientIntercept
            ) / determinant
            slope -= deltaSlope
            intercept -= deltaIntercept
            if max(abs(deltaSlope), abs(deltaIntercept)) < 1e-10 {
                break
            }
        }
        guard slope.isFinite, intercept.isFinite else {
            throw ConfidenceCalibrationError.invalidProbability
        }
        return Self(
            method: .platt,
            key: key,
            version: version,
            fittedExampleCount: selected.count,
            plattSlope: slope,
            plattIntercept: intercept
        )
    }

    public static func fitIsotonic(
        examples: [ConfidenceCalibrationExample],
        key: ConfidenceCalibrationKey,
        version: String = "w05-isotonic-v1"
    ) throws -> Self {
        let selected = try calibrationExamples(examples, key: key)
        struct Block {
            var minimum: Double
            var maximum: Double
            var positive: Double
            var count: Double

            var mean: Double { positive / count }
        }

        var blocks = selected
            .enumerated()
            .sorted {
                if $0.element.rawErrorProbability != $1.element.rawErrorProbability {
                    return $0.element.rawErrorProbability < $1.element.rawErrorProbability
                }
                return $0.offset < $1.offset
            }
            .map { item in
                let score = item.element.rawErrorProbability
                return Block(
                    minimum: score,
                    maximum: score,
                    positive: item.element.isError ? 1 : 0,
                    count: 1
                )
            }

        while blocks.count > 1 {
            var merged = false
            for index in 0..<(blocks.count - 1) {
                guard blocks[index].mean > blocks[index + 1].mean else {
                    continue
                }
                let right = blocks.remove(at: index + 1)
                let left = blocks.remove(at: index)
                blocks.insert(
                    Block(
                        minimum: min(left.minimum, right.minimum),
                        maximum: max(left.maximum, right.maximum),
                        positive: left.positive + right.positive,
                        count: left.count + right.count
                    ),
                    at: index
                )
                merged = true
                break
            }
            if !merged { break }
        }

        let points = blocks.map {
            IsotonicCalibrationPoint(
                maximumRawErrorProbability: $0.maximum,
                calibratedErrorProbability: $0.mean
            )
        }
        return Self(
            method: .isotonic,
            key: key,
            version: version,
            fittedExampleCount: selected.count,
            isotonicPoints: points
        )
    }

    public static func temperature(
        from examples: [ConfidenceCalibrationExample],
        key: ConfidenceCalibrationKey,
        version: String = "w05-temperature-v1"
    ) throws -> Self {
        try fitTemperature(examples: examples, key: key, version: version)
    }

    public static func platt(
        from examples: [ConfidenceCalibrationExample],
        key: ConfidenceCalibrationKey,
        version: String = "w05-platt-v1"
    ) throws -> Self {
        try fitPlatt(examples: examples, key: key, version: version)
    }

    public static func isotonic(
        from examples: [ConfidenceCalibrationExample],
        key: ConfidenceCalibrationKey,
        version: String = "w05-isotonic-v1"
    ) throws -> Self {
        try fitIsotonic(examples: examples, key: key, version: version)
    }

    private static func calibrationExamples(
        _ examples: [ConfidenceCalibrationExample],
        key: ConfidenceCalibrationKey
    ) throws -> [ConfidenceCalibrationExample] {
        guard !examples.isEmpty else {
            throw ConfidenceCalibrationError.noLabeledExamples
        }
        guard examples.count <= 10_000 else {
            throw ConfidenceCalibrationError.tooManyExamples
        }
        guard examples.allSatisfy({ $0.key == key }) else {
            throw ConfidenceCalibrationError.mixedCalibrationKeys
        }
        let selected = examples.filter { $0.split == .calibration }
        guard !selected.isEmpty else {
            throw ConfidenceCalibrationError.calibrationSplitRequired
        }
        guard selected.contains(where: \.isError),
              selected.contains(where: { !$0.isError })
        else {
            throw ConfidenceCalibrationError.insufficientClassCoverage
        }
        guard selected.allSatisfy({
            $0.rawErrorProbability.isFinite
                && (0...1).contains($0.rawErrorProbability)
        }) else {
            throw ConfidenceCalibrationError.invalidProbability
        }
        return selected
    }

    private static func temperatureLoss(
        scores: [Double],
        labels: [Double],
        temperature: Double
    ) -> Double {
        guard temperature > 0 else { return .infinity }
        var total = 0.0
        for (score, label) in zip(scores, labels) {
            let logit = Self.logit(score) / temperature
            // Stable binary cross entropy from logits.
            total += max(logit, 0) - logit * label + log1p(exp(-abs(logit)))
        }
        return total / Double(max(scores.count, 1))
    }

    fileprivate static func clampProbability(_ value: Double) -> Double {
        min(max(value, 1e-7), 1 - 1e-7)
    }

    fileprivate static func logit(_ probability: Double) -> Double {
        let clamped = clampProbability(probability)
        return log(clamped / (1 - clamped))
    }

    fileprivate static func sigmoid(_ value: Double) -> Double {
        if value >= 0 {
            let z = exp(-value)
            return 1 / (1 + z)
        }
        let z = exp(value)
        return z / (1 + z)
    }
}

/// An explicit operating-point provenance.  No default verifier threshold is
/// supplied: an uncalibrated threshold must be requested by name, while a
/// calibrated threshold must carry an artifact identity and matching key.
public enum ConfidenceThresholdSource: Codable, Hashable, Sendable {
    case uncalibrated
    case calibrationArtifact(
        artifactID: String,
        calibratorVersion: String,
        key: ConfidenceCalibrationKey
    )
}

public struct ConfidenceThreshold: Codable, Hashable, Sendable {
    public let errorProbability: Double
    public let source: ConfidenceThresholdSource

    public init(
        errorProbability: Double,
        source: ConfidenceThresholdSource
    ) {
        precondition(errorProbability.isFinite)
        precondition((0...1).contains(errorProbability))
        self.errorProbability = errorProbability
        self.source = source
    }

    public static func uncalibrated(_ errorProbability: Double) -> Self {
        Self(errorProbability: errorProbability, source: .uncalibrated)
    }

    public static func calibrated(
        _ errorProbability: Double,
        artifactID: String,
        calibrator: ConfidenceCalibrator
    ) -> Self {
        precondition(!artifactID.isEmpty)
        return Self(
            errorProbability: errorProbability,
            source: .calibrationArtifact(
                artifactID: artifactID,
                calibratorVersion: calibrator.version,
                key: calibrator.key
            )
        )
    }

    public var isCalibrated: Bool {
        if case .calibrationArtifact = source { return true }
        return false
    }
}

public struct ConfidenceEstimator: Sendable {
    public let calibrator: ConfidenceCalibrator?
    public let runtimeVersion: String?

    public init(
        calibrator: ConfidenceCalibrator? = nil,
        runtimeVersion: String? = nil
    ) {
        self.calibrator = calibrator
        self.runtimeVersion = runtimeVersion
    }

    public func estimate(
        result: RecognitionResult,
        wordIndex: Int,
        complementaryResult: RecognitionResult? = nil,
        audioDurationSeconds: Double? = nil
    ) -> ConfidenceEstimate {
        let features = Self.extractFeatures(
            result: result,
            wordIndex: wordIndex,
            complementaryResult: complementaryResult,
            audioDurationSeconds: audioDurationSeconds,
            runtimeVersion: runtimeVersion
        )
        return estimate(features: features)
    }

    public func estimate(features: ConfidenceFeatures) -> ConfidenceEstimate {
        let raw = Self.rawEstimate(features: features)
        guard let rawProbability = raw.rawErrorProbability else {
            return ConfidenceEstimate(
                raw: raw,
                calibratedErrorProbability: nil,
                status: .noEvidence
            )
        }
        guard let calibrator else {
            return ConfidenceEstimate(
                raw: raw,
                calibratedErrorProbability: nil,
                status: .uncalibrated
            )
        }
        guard calibrator.key == features.calibrationKey else {
            return ConfidenceEstimate(
                raw: raw,
                calibratedErrorProbability: nil,
                status: .calibrationKeyMismatch
            )
        }
        return ConfidenceEstimate(
            raw: raw,
            calibratedErrorProbability: calibrator.calibrate(
                rawErrorProbability: rawProbability
            ),
            status: .calibrated
        )
    }

    /// Extracts all provider-available features without retaining word text.
    public static func extractFeatures(
        result: RecognitionResult,
        wordIndex: Int,
        complementaryResult: RecognitionResult? = nil,
        audioDurationSeconds: Double? = nil,
        runtimeVersion: String? = nil
    ) -> ConfidenceFeatures {
        let key = ConfidenceCalibrationKey(
            result: result,
            runtimeVersion: runtimeVersion
        )
        guard result.words.indices.contains(wordIndex) else {
            return ConfidenceFeatures(
                calibrationKey: key,
                missing: Dictionary(
                    uniqueKeysWithValues: ConfidenceFeatureID.allCases.map {
                        ($0, .providerDidNotExpose)
                    }
                )
            )
        }
        let word = result.words[wordIndex]
        let evidence = word.rawEvidence
        var values: [ConfidenceFeatureID: Double] = [:]
        var missing: [ConfidenceFeatureID: ConfidenceMissingReason] = [:]

        func add(
            _ feature: ConfidenceFeatureID,
            _ value: Double?,
            missingReason: ConfidenceMissingReason = .providerDidNotExpose,
            valid: (Double) -> Bool = { $0.isFinite }
        ) {
            guard let value else {
                missing[feature] = missingReason
                return
            }
            if valid(value) {
                values[feature] = value
            } else {
                missing[feature] = .invalidValue
            }
        }

        add(
            .posterior,
            evidence.posterior,
            valid: { $0.isFinite && (0...1).contains($0) }
        )

        let tokenProbabilities = evidence.tokenLogProbabilities
            .filter { $0.isFinite && $0 <= 0 }
            .map { min(max(exp($0), 0), 1) }
        add(
            .minimumTokenProbability,
            tokenProbabilities.min(),
            missingReason: .providerDidNotExpose,
            valid: { $0.isFinite && (0...1).contains($0) }
        )
        if tokenProbabilities.isEmpty {
            let reason: ConfidenceMissingReason = evidence.tokenLogProbabilities.isEmpty
                ? .providerDidNotExpose
                : .invalidValue
            missing[.meanTokenLogProbability] = reason
            missing[.geometricMeanTokenProbability] = reason
        } else {
            let meanLogProbability = evidence.tokenLogProbabilities
                .filter { $0.isFinite && $0 <= 0 }
                .reduce(0, +) / Double(tokenProbabilities.count)
            values[.meanTokenLogProbability] = meanLogProbability
            values[.geometricMeanTokenProbability] = exp(meanLogProbability)
        }

        add(
            .entropy,
            evidence.entropy,
            valid: { $0.isFinite && $0 >= 0 }
        )
        add(.beamScore, evidence.beamScore)
        add(
            .beamRank,
            evidence.beamRank.map(Double.init),
            valid: { $0.isFinite && $0 >= 0 }
        )

        if let start = word.startSeconds,
           let end = word.endSeconds,
           start.isFinite,
           end.isFinite,
           end >= start {
            values[.wordDurationSeconds] = end - start
            let duration = audioDurationSeconds ?? result.timing.audioDurationSeconds
            if let duration, duration.isFinite, duration > 0 {
                let leftDistance = max(0, start)
                let rightDistance = max(0, duration - end)
                let nearestBoundary = min(leftDistance, rightDistance)
                values[.boundaryProximity] = min(
                    max(1 - nearestBoundary / 0.5, 0),
                    1
                )
            } else {
                missing[.boundaryProximity] = .wordTimingUnavailable
            }
        } else {
            missing[.wordDurationSeconds] = .wordTimingUnavailable
            missing[.boundaryProximity] = .wordTimingUnavailable
        }

        let utterance = result.utteranceEvidence
        if utterance == .unavailable {
            missing[.noSpeechProbability] = .utteranceEvidenceUnavailable
            missing[.weakTokenFraction] = .utteranceEvidenceUnavailable
            missing[.repetitionRisk] = .utteranceEvidenceUnavailable
            missing[.truncationRisk] = .utteranceEvidenceUnavailable
            missing[.decodeTemperature] = .utteranceEvidenceUnavailable
            missing[.fallbackTemperatureCount] = .utteranceEvidenceUnavailable
        } else {
            add(
                .noSpeechProbability,
                utterance.maximumNoSpeechProbability
                    ?? utterance.noSpeechProbability,
                valid: { $0.isFinite && (0...1).contains($0) }
            )
            add(
                .weakTokenFraction,
                utterance.weakTokenFraction,
                valid: { $0.isFinite && (0...1).contains($0) }
            )
            values[.repetitionRisk] = utterance.repetitionDetected ? 1 : 0
            values[.truncationRisk] = utterance.truncated ? 1 : 0
            add(
                .decodeTemperature,
                utterance.temperature ?? result.passMetadata.temperature,
                valid: { $0.isFinite && $0 > 0 }
            )
            values[.fallbackTemperatureCount] = Double(
                utterance.fallbackTemperatures.count
            )
        }

        if result.alternatives.isEmpty {
            missing[.nBestDisagreement] = .alternativeUnavailable
        } else if let alternateWord = result.alternatives.first?.words.first(
            where: { $0.id.wordIndex == wordIndex }
        ) {
            values[.nBestDisagreement] = normalizedWord(
                alternateWord.text
            ) == normalizedWord(word.text) ? 0 : 1
        } else {
            missing[.nBestDisagreement] = .alternativeUnavailable
        }

        if let complementaryResult,
           let complementaryWord = nearestTimedWord(
               to: word,
               in: complementaryResult.words
           ) {
            values[.crossEngineDisagreement] = normalizedWord(
                complementaryWord.text
            ) == normalizedWord(word.text) ? 0 : 1
        } else {
            missing[.crossEngineDisagreement] = .complementaryResultUnavailable
        }

        // Keep the two maps disjoint even when an input provider supplied an
        // invalid optional field.  This makes missing evidence explicit and
        // keeps `availableFeatureCount` truthful.
        for feature in values.keys {
            missing.removeValue(forKey: feature)
        }
        for feature in ConfidenceFeatureID.allCases where
            values[feature] == nil && missing[feature] == nil {
            missing[feature] = .providerDidNotExpose
        }
        return ConfidenceFeatures(
            calibrationKey: key,
            wordID: word.id,
            values: values,
            missing: missing
        )
    }

    public static func rawEstimate(
        features: ConfidenceFeatures
    ) -> ConfidenceRawEstimate {
        let weights: [ConfidenceFeatureID: Double]
        switch features.calibrationKey.engine {
        case .whisperTurbo:
            weights = [
                .posterior: 0.42,
                .minimumTokenProbability: 0.20,
                .geometricMeanTokenProbability: 0.10,
                .entropy: 0.05,
                .weakTokenFraction: 0.08,
                .noSpeechProbability: 0.04,
                .repetitionRisk: 0.03,
                .truncationRisk: 0.04,
                .nBestDisagreement: 0.04,
                .crossEngineDisagreement: 0.04,
            ]
        case .parakeetTDTCoreML, .parakeetCppTDT:
            weights = [
                .posterior: 0.56,
                .minimumTokenProbability: 0.18,
                .geometricMeanTokenProbability: 0.08,
                .weakTokenFraction: 0.05,
                .noSpeechProbability: 0.04,
                .repetitionRisk: 0.03,
                .truncationRisk: 0.04,
                .nBestDisagreement: 0.02,
                .crossEngineDisagreement: 0.04,
            ]
        case .parakeetUnifiedCoreML:
            weights = [:]
        }

        var weightedSignal = 0.0
        var totalWeight = 0.0
        var used: [ConfidenceFeatureID] = []
        for feature in ConfidenceFeatureID.allCases {
            guard let value = features.values[feature],
                  let weight = weights[feature],
                  weight > 0
            else { continue }
            let errorSignal: Double
            switch feature {
            case .posterior,
                 .minimumTokenProbability,
                 .geometricMeanTokenProbability:
                errorSignal = 1 - min(max(value, 0), 1)
            case .meanTokenLogProbability:
                errorSignal = 1 - min(max(exp(value), 0), 1)
            case .entropy:
                errorSignal = value / (1 + value)
            case .beamScore,
                 .beamRank,
                 .wordDurationSeconds,
                 .decodeTemperature,
                 .fallbackTemperatureCount:
                // These are retained for a later fitted estimator but have
                // no provider-independent scale for a raw probability.
                continue
            case .boundaryProximity,
                 .noSpeechProbability,
                 .weakTokenFraction,
                 .repetitionRisk,
                 .truncationRisk,
                 .nBestDisagreement,
                 .crossEngineDisagreement:
                errorSignal = min(max(value, 0), 1)
            }
            weightedSignal += weight * errorSignal
            totalWeight += weight
            used.append(feature)
        }

        // Timing-only or text-only provider output is unknown.  It must not
        // become an apparently safe zero-error probability.
        let rawProbability: Double?
        if totalWeight > 0 {
            rawProbability = min(max(weightedSignal / totalWeight, 0), 1)
        } else {
            rawProbability = nil
        }
        return ConfidenceRawEstimate(
            rawErrorProbability: rawProbability,
            features: features,
            usedFeatureIDs: used
        )
    }

    public func applyingCalibration(
        to result: RecognitionResult,
        complementaryResult: RecognitionResult? = nil,
        audioDurationSeconds: Double? = nil
    ) -> RecognitionResult {
        var words = result.words
        for index in words.indices {
            let estimate = estimate(
                result: result,
                wordIndex: index,
                complementaryResult: complementaryResult,
                audioDurationSeconds: audioDurationSeconds
            )
            words[index].calibratedErrorProbability =
                estimate.calibratedErrorProbability
        }
        return RecognitionResult(
            sessionID: result.sessionID,
            generation: result.generation,
            engine: result.engine,
            model: result.model,
            pass: result.pass,
            text: result.text,
            words: words,
            segments: result.segments,
            alternatives: result.alternatives,
            utteranceEvidence: result.utteranceEvidence,
            timing: result.timing,
            completeness: result.completeness,
            passMetadata: result.passMetadata
        )
    }

    public func shouldVerify(
        estimate: ConfidenceEstimate,
        threshold: ConfidenceThreshold
    ) -> Bool {
        guard let probability = estimate.errorProbability else { return false }
        switch threshold.source {
        case .uncalibrated:
            return probability >= threshold.errorProbability
        case .calibrationArtifact(_, _, let key):
            guard estimate.status == .calibrated,
                  estimate.raw.features.calibrationKey == key,
                  calibrator?.key == key
            else { return false }
            return probability >= threshold.errorProbability
        }
    }

    private static func normalizedWord(_ value: String) -> String {
        value.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func nearestTimedWord(
        to word: RecognizedWord,
        in words: [RecognizedWord]
    ) -> RecognizedWord? {
        guard let start = word.startSeconds, let end = word.endSeconds else {
            return nil
        }
        let midpoint = (start + end) / 2
        return words
            .compactMap { candidate -> (RecognizedWord, Double)? in
                guard let candidateStart = candidate.startSeconds,
                      let candidateEnd = candidate.endSeconds
                else { return nil }
                let candidateMidpoint = (candidateStart + candidateEnd) / 2
                let distance = abs(midpoint - candidateMidpoint)
                return distance <= 0.75 ? (candidate, distance) : nil
            }
            .min { left, right in left.1 < right.1 }?.0
    }
}

public struct ConfidenceLabeledPrediction: Codable, Hashable, Sendable {
    public let errorProbability: Double
    public let isError: Bool

    public init(errorProbability: Double, isError: Bool) {
        precondition(errorProbability.isFinite)
        precondition((0...1).contains(errorProbability))
        self.errorProbability = errorProbability
        self.isError = isError
    }

    public init(rawErrorProbability: Double, isError: Bool) {
        self.init(errorProbability: rawErrorProbability, isError: isError)
    }
}

public struct RiskCoveragePoint: Codable, Hashable, Sendable {
    public let coverage: Double
    public let risk: Double
    public let selectedCount: Int
    public let errorCount: Int

    public init(
        coverage: Double,
        risk: Double,
        selectedCount: Int,
        errorCount: Int
    ) {
        self.coverage = coverage
        self.risk = risk
        self.selectedCount = selectedCount
        self.errorCount = errorCount
    }
}

public struct ConfidenceBudgetMetric: Codable, Hashable, Sendable {
    public let verifierBudget: Double
    public let selectedCount: Int
    public let errorRecall: Double?

    public init(
        verifierBudget: Double,
        selectedCount: Int,
        errorRecall: Double?
    ) {
        self.verifierBudget = verifierBudget
        self.selectedCount = selectedCount
        self.errorRecall = errorRecall
    }
}

/// Privacy-safe, label-based confidence metrics.  No accuracy value is
/// inferred when labels are absent; empty/degenerate metrics remain `nil`.
public struct ConfidenceMetrics: Codable, Hashable, Sendable {
    public let sampleCount: Int
    public let errorCount: Int
    public let auprc: Double?
    public let rocAuc: Double?
    public let brierScore: Double?
    public let expectedCalibrationError: Double?
    public let maximumCalibrationError: Double?
    public let normalizedCrossEntropy: Double?
    public let falseUnlockRate: Double?
    public let falseUnlockThreshold: Double?
    public let riskCoverage: [RiskCoveragePoint]
    public let errorRecallAtVerifierBudget: [ConfidenceBudgetMetric]

    public init(
        sampleCount: Int,
        errorCount: Int,
        auprc: Double?,
        rocAuc: Double?,
        brierScore: Double?,
        expectedCalibrationError: Double?,
        maximumCalibrationError: Double?,
        normalizedCrossEntropy: Double?,
        falseUnlockRate: Double?,
        falseUnlockThreshold: Double?,
        riskCoverage: [RiskCoveragePoint],
        errorRecallAtVerifierBudget: [ConfidenceBudgetMetric]
    ) {
        self.sampleCount = sampleCount
        self.errorCount = errorCount
        self.auprc = auprc
        self.rocAuc = rocAuc
        self.brierScore = brierScore
        self.expectedCalibrationError = expectedCalibrationError
        self.maximumCalibrationError = maximumCalibrationError
        self.normalizedCrossEntropy = normalizedCrossEntropy
        self.falseUnlockRate = falseUnlockRate
        self.falseUnlockThreshold = falseUnlockThreshold
        self.riskCoverage = riskCoverage
        self.errorRecallAtVerifierBudget = errorRecallAtVerifierBudget
    }

    public var ece: Double? { expectedCalibrationError }

    public var mce: Double? { maximumCalibrationError }

    public var nce: Double? { normalizedCrossEntropy }

    public var errorRecallAtVerifierBudgetMap: [Double: Double] {
        Dictionary(
            uniqueKeysWithValues: errorRecallAtVerifierBudget.compactMap {
                metric in metric.errorRecall.map {
                    (metric.verifierBudget, $0)
                }
            }
        )
    }

    public static func evaluate(
        _ predictions: [ConfidenceLabeledPrediction],
        binCount: Int = 10,
        verifierBudgets: [Double] = [0.05, 0.10, 0.25],
        falseUnlockThreshold: Double? = nil,
        maximumRiskCoveragePoints: Int = 4096
    ) -> Self {
        precondition(binCount > 0)
        precondition(maximumRiskCoveragePoints > 0)
        precondition(predictions.count <= 100_000)
        let count = predictions.count
        let errors = predictions.reduce(into: 0) { total, prediction in
            total += prediction.isError ? 1 : 0
        }
        guard count > 0 else {
            return Self(
                sampleCount: 0,
                errorCount: 0,
                auprc: nil,
                rocAuc: nil,
                brierScore: nil,
                expectedCalibrationError: nil,
                maximumCalibrationError: nil,
                normalizedCrossEntropy: nil,
                falseUnlockRate: nil,
                falseUnlockThreshold: falseUnlockThreshold,
                riskCoverage: [],
                errorRecallAtVerifierBudget: []
            )
        }

        var brier = 0.0
        var negativeLogLikelihood = 0.0
        for prediction in predictions {
            let p = ConfidenceCalibrator.clampProbability(
                prediction.errorProbability
            )
            let label = prediction.isError ? 1.0 : 0.0
            brier += (prediction.errorProbability - label)
                * (prediction.errorProbability - label)
            negativeLogLikelihood += -(
                label * log(p) + (1 - label) * log(1 - p)
            )
        }
        brier /= Double(count)
        negativeLogLikelihood /= Double(count)

        var bucketCount = Array(repeating: 0, count: binCount)
        var bucketProbability = Array(repeating: 0.0, count: binCount)
        var bucketLabel = Array(repeating: 0.0, count: binCount)
        for prediction in predictions {
            let bucket = min(
                Int(prediction.errorProbability * Double(binCount)),
                binCount - 1
            )
            bucketCount[bucket] += 1
            bucketProbability[bucket] += prediction.errorProbability
            bucketLabel[bucket] += prediction.isError ? 1 : 0
        }
        var ece = 0.0
        var mce = 0.0
        for bucket in 0..<binCount where bucketCount[bucket] > 0 {
            let probability = bucketProbability[bucket]
                / Double(bucketCount[bucket])
            let label = bucketLabel[bucket] / Double(bucketCount[bucket])
            let gap = abs(probability - label)
            ece += Double(bucketCount[bucket]) / Double(count) * gap
            mce = max(mce, gap)
        }

        let prevalence = Double(errors) / Double(count)
        let entropy = if prevalence == 0 || prevalence == 1 {
            0.0
        } else {
            -prevalence * log(prevalence)
                - (1 - prevalence) * log(1 - prevalence)
        }
        let nce = entropy > 0 ? negativeLogLikelihood / entropy : nil

        let sortedDescending = predictions.enumerated().sorted {
            if $0.element.errorProbability != $1.element.errorProbability {
                return $0.element.errorProbability > $1.element.errorProbability
            }
            return $0.offset < $1.offset
        }
        let auprc = averagePrecision(sortedDescending, positiveCount: errors)
        let rocAuc = areaUnderROC(sortedDescending, positiveCount: errors)

        let sortedAscending = predictions.enumerated().sorted {
            if $0.element.errorProbability != $1.element.errorProbability {
                return $0.element.errorProbability < $1.element.errorProbability
            }
            return $0.offset < $1.offset
        }
        let riskCoverage = makeRiskCoverage(
            sortedAscending,
            maximumPoints: maximumRiskCoveragePoints
        )
        let budgetMetrics = makeBudgetMetrics(
            sortedDescending,
            positiveCount: errors,
            budgets: verifierBudgets
        )

        let falseUnlockRate: Double?
        if let falseUnlockThreshold {
            precondition((0...1).contains(falseUnlockThreshold))
            let unlocked = predictions.filter {
                $0.errorProbability <= falseUnlockThreshold
            }
            falseUnlockRate = unlocked.isEmpty
                ? nil
                : Double(unlocked.filter(\.isError).count)
                    / Double(unlocked.count)
        } else {
            falseUnlockRate = nil
        }

        return Self(
            sampleCount: count,
            errorCount: errors,
            auprc: auprc,
            rocAuc: rocAuc,
            brierScore: brier,
            expectedCalibrationError: ece,
            maximumCalibrationError: mce,
            normalizedCrossEntropy: nce,
            falseUnlockRate: falseUnlockRate,
            falseUnlockThreshold: falseUnlockThreshold,
            riskCoverage: riskCoverage,
            errorRecallAtVerifierBudget: budgetMetrics
        )
    }

    public static func evaluate(
        _ examples: [ConfidenceCalibrationExample],
        using calibrator: ConfidenceCalibrator? = nil,
        binCount: Int = 10,
        verifierBudgets: [Double] = [0.05, 0.10, 0.25],
        falseUnlockThreshold: Double? = nil,
        maximumRiskCoveragePoints: Int = 4096
    ) -> Self {
        let predictions = examples.compactMap { example -> ConfidenceLabeledPrediction? in
            let probability: Double
            if let calibrator {
                guard calibrator.key == example.key else { return nil }
                probability = calibrator.calibrate(
                    rawErrorProbability: example.rawErrorProbability
                )
            } else {
                probability = example.rawErrorProbability
            }
            return ConfidenceLabeledPrediction(
                errorProbability: probability,
                isError: example.isError
            )
        }
        return evaluate(
            predictions,
            binCount: binCount,
            verifierBudgets: verifierBudgets,
            falseUnlockThreshold: falseUnlockThreshold,
            maximumRiskCoveragePoints: maximumRiskCoveragePoints
        )
    }

    private static func averagePrecision(
        _ sorted: [(offset: Int, element: ConfidenceLabeledPrediction)],
        positiveCount: Int
    ) -> Double? {
        guard positiveCount > 0 else { return nil }
        var truePositives = 0
        var falsePositives = 0
        var previousRecall = 0.0
        var area = 0.0
        var index = 0
        while index < sorted.count {
            let score = sorted[index].element.errorProbability
            var end = index
            while end < sorted.count,
                  sorted[end].element.errorProbability == score {
                end += 1
            }
            for item in sorted[index..<end] {
                if item.element.isError { truePositives += 1 }
                else { falsePositives += 1 }
            }
            let recall = Double(truePositives) / Double(positiveCount)
            let precision = truePositives + falsePositives > 0
                ? Double(truePositives) / Double(truePositives + falsePositives)
                : 0
            area += (recall - previousRecall) * precision
            previousRecall = recall
            index = end
        }
        return area
    }

    private static func areaUnderROC(
        _ sorted: [(offset: Int, element: ConfidenceLabeledPrediction)],
        positiveCount: Int
    ) -> Double? {
        let negativeCount = sorted.count - positiveCount
        guard positiveCount > 0, negativeCount > 0 else { return nil }
        var truePositives = 0.0
        var falsePositives = 0.0
        var previousTPR = 0.0
        var previousFPR = 0.0
        var area = 0.0
        var index = 0
        while index < sorted.count {
            let score = sorted[index].element.errorProbability
            var end = index
            while end < sorted.count,
                  sorted[end].element.errorProbability == score {
                end += 1
            }
            for item in sorted[index..<end] {
                if item.element.isError { truePositives += 1 }
                else { falsePositives += 1 }
            }
            let tpr = truePositives / Double(positiveCount)
            let fpr = falsePositives / Double(negativeCount)
            area += (fpr - previousFPR) * (tpr + previousTPR) / 2
            previousTPR = tpr
            previousFPR = fpr
            index = end
        }
        return area
    }

    private static func makeRiskCoverage(
        _ sorted: [(offset: Int, element: ConfidenceLabeledPrediction)],
        maximumPoints: Int
    ) -> [RiskCoveragePoint] {
        guard !sorted.isEmpty else { return [] }
        let count = sorted.count
        var selectedIndices: [Int]
        if count <= maximumPoints {
            selectedIndices = Array(1...count)
        } else {
            let stride = Double(count) / Double(maximumPoints)
            selectedIndices = (1..<maximumPoints).map {
                max(1, min(count, Int((Double($0) * stride).rounded())))
            }
            selectedIndices.append(count)
            selectedIndices = Array(Set(selectedIndices)).sorted()
        }
        var errorCount = 0
        var next = 0
        var result: [RiskCoveragePoint] = []
        for selectedCount in selectedIndices {
            while next < selectedCount {
                if sorted[next].element.isError { errorCount += 1 }
                next += 1
            }
            result.append(
                RiskCoveragePoint(
                    coverage: Double(selectedCount) / Double(count),
                    risk: Double(errorCount) / Double(selectedCount),
                    selectedCount: selectedCount,
                    errorCount: errorCount
                )
            )
        }
        return result
    }

    private static func makeBudgetMetrics(
        _ sorted: [(offset: Int, element: ConfidenceLabeledPrediction)],
        positiveCount: Int,
        budgets: [Double]
    ) -> [ConfidenceBudgetMetric] {
        var uniqueBudgets: [Double] = []
        for budget in budgets {
            guard budget.isFinite else { continue }
            let clamped = min(max(budget, 0), 1)
            if !uniqueBudgets.contains(clamped) {
                uniqueBudgets.append(clamped)
            }
        }
        uniqueBudgets.sort()
        return uniqueBudgets.map { budget in
            let selectedCount = min(
                sorted.count,
                Int(ceil(Double(sorted.count) * budget))
            )
            let selectedErrors = sorted.prefix(selectedCount)
                .filter(\.element.isError)
                .count
            return ConfidenceBudgetMetric(
                verifierBudget: budget,
                selectedCount: selectedCount,
                errorRecall: positiveCount > 0
                    ? Double(selectedErrors) / Double(positiveCount)
                    : nil
            )
        }
    }
}
