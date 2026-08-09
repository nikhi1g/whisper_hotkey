import Foundation
import XCTest
@testable import WhisperHotkeyASR
import WhisperHotkeyCore

final class ConfidenceEstimatorTests: XCTestCase {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private var whisperKey: ConfidenceCalibrationKey {
        ConfidenceCalibrationKey(
            engine: .whisperTurbo,
            modelIdentifier: "turbo-q5",
            modelVersion: "1",
            quantization: "q5",
            computeUnits: "metal",
            decodingProfile: "precision"
        )
    }

    private func result(
        posterior: Double? = 0.8,
        tokenLogProbabilities: [Double] = [-0.2, -0.4],
        wordStart: Double? = 0.2,
        wordEnd: Double? = 0.5,
        alternatives: [RecognitionAlternative] = [],
        complementaryResult: Bool = false,
        utteranceEvidence: UtteranceEvidence = UtteranceEvidence(
            noSpeechProbability: 0.02,
            weakTokenFraction: 0.05
        )
    ) -> RecognitionResult {
        let id = StableWordID(
            sessionID: sessionID,
            providerDecodeID: "decode-1",
            wordIndex: 0
        )
        let word = RecognizedWord(
            id: id,
            text: complementaryResult ? "wrong" : "hello",
            startSeconds: wordStart,
            endSeconds: wordEnd,
            rawEvidence: WordEvidence(
                tokenLogProbabilities: tokenLogProbabilities,
                posterior: posterior,
                entropy: 0.2,
                beamScore: -0.4,
                beamRank: 0,
                availability: [.posterior, .entropy, .beamScore, .beamRank]
            )
        )
        return RecognitionResult(
            sessionID: sessionID,
            engine: .whisperTurbo,
            model: ModelIdentity(
                identifier: "turbo-q5",
                version: "1",
                quantization: "q5",
                computeUnits: "metal"
            ),
            pass: .primaryFullSession,
            text: word.text,
            words: [word],
            alternatives: alternatives,
            utteranceEvidence: utteranceEvidence,
            timing: RecognitionTiming(audioDurationSeconds: 1.5),
            passMetadata: RecognitionPassMetadata(
                strategy: "precision",
                protocolVersion: 2
            )
        )
    }

    private func example(
        _ score: Double,
        error: Bool,
        split: ConfidenceCalibrationSplit = .calibration,
        key: ConfidenceCalibrationKey? = nil
    ) -> ConfidenceCalibrationExample {
        ConfidenceCalibrationExample(
            key: key ?? whisperKey,
            rawErrorProbability: score,
            isError: error,
            split: split
        )
    }

    func testProviderAwareExtractionPreservesEvidenceAndMissingFields() {
        let extracted = ConfidenceEstimator.extractFeatures(
            result: result(),
            wordIndex: 0
        )

        XCTAssertEqual(extracted.value(for: .posterior), 0.8)
        XCTAssertEqual(
            extracted.value(for: .minimumTokenProbability) ?? -1,
            exp(-0.4),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            extracted.value(for: .geometricMeanTokenProbability) ?? -1,
            exp(-0.3),
            accuracy: 0.000_001
        )
        XCTAssertEqual(extracted.value(for: .wordDurationSeconds), 0.3)
        XCTAssertNotNil(extracted.value(for: .boundaryProximity))
        XCTAssertEqual(
            extracted.missingReason(for: .crossEngineDisagreement),
            .complementaryResultUnavailable
        )
        XCTAssertEqual(
            extracted.missingReason(for: .nBestDisagreement),
            .alternativeUnavailable
        )
        XCTAssertFalse(extracted.missingFeatureIDs.isEmpty)

        let raw = ConfidenceEstimator.rawEstimate(features: extracted)
        XCTAssertNotNil(raw.rawErrorProbability)
        XCTAssertFalse(raw.isCalibrated)
        XCTAssertTrue(raw.usedFeatureIDs.contains(.posterior))
    }

    func testMissingProviderEvidenceRemainsUnknown() {
        let textOnly = RecognitionResult(
            sessionID: sessionID,
            engine: .parakeetUnifiedCoreML,
            model: ModelIdentity(identifier: "parakeet-unified-en-0.6b"),
            text: "hello"
        )
        let features = ConfidenceEstimator.extractFeatures(
            result: textOnly,
            wordIndex: 0
        )
        let raw = ConfidenceEstimator.rawEstimate(features: features)

        XCTAssertNil(raw.rawErrorProbability)
        XCTAssertEqual(
            features.missingFeatureIDs.count,
            ConfidenceFeatureID.allCases.count
        )
        XCTAssertNil(
            ConfidenceEstimator().estimate(features: features)
                .calibratedErrorProbability
        )
        XCTAssertEqual(
            ConfidenceEstimator().estimate(features: features).status,
            .noEvidence
        )
    }

    func testComplementaryDisagreementIsAnExplicitFeature() {
        let primary = result()
        let complementary = result(complementaryResult: true)
        let features = ConfidenceEstimator.extractFeatures(
            result: primary,
            wordIndex: 0,
            complementaryResult: complementary
        )

        XCTAssertEqual(features.value(for: .crossEngineDisagreement), 1)
        let agreement = ConfidenceEstimator.extractFeatures(
            result: primary,
            wordIndex: 0,
            complementaryResult: result()
        )
        XCTAssertEqual(agreement.value(for: .crossEngineDisagreement), 0)
    }

    func testCalibratorsAreDeterministicAndUseOnlyCalibrationSplit() throws {
        let examples = [
            example(0.02, error: false),
            example(0.12, error: false),
            example(0.24, error: true),
            example(0.42, error: false),
            example(0.65, error: true),
            example(0.90, error: true),
            example(0.99, error: true, split: .test),
        ]

        let first = try ConfidenceCalibrator.fitTemperature(
            examples: examples,
            key: whisperKey
        )
        let second = try ConfidenceCalibrator.fitTemperature(
            examples: examples,
            key: whisperKey
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.fittedExampleCount, 6)
        XCTAssertEqual(first.method, .temperature)
        XCTAssertLessThan(
            first.calibrate(rawErrorProbability: 0.2),
            first.calibrate(rawErrorProbability: 0.8)
        )

        XCTAssertThrowsError(
            try ConfidenceCalibrator.fitPlatt(
                examples: [example(0.4, error: true, split: .test)],
                key: whisperKey
            )
        ) { error in
            XCTAssertEqual(
                error as? ConfidenceCalibrationError,
                .calibrationSplitRequired
            )
        }
    }

    func testPlattAndIsotonicCalibrationStayBoundedAndMonotonic() throws {
        let examples = [
            example(0.05, error: false),
            example(0.10, error: false),
            example(0.20, error: true),
            example(0.35, error: false),
            example(0.50, error: true),
            example(0.70, error: true),
            example(0.95, error: true),
        ]
        let platt = try ConfidenceCalibrator.fitPlatt(
            examples: examples,
            key: whisperKey
        )
        let isotonic = try ConfidenceCalibrator.fitIsotonic(
            examples: examples,
            key: whisperKey
        )

        for calibrator in [platt, isotonic] {
            let values = stride(from: 0.0, through: 1.0, by: 0.05).map {
                calibrator.calibrate(rawErrorProbability: $0)
            }
            XCTAssertTrue(values.allSatisfy { (0...1).contains($0) })
            XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy(<=))
        }
        XCTAssertFalse(isotonic.isotonicPoints.isEmpty)
    }

    func testMetricsReportRequiredLabelBasedMeasures() {
        let predictions = [
            ConfidenceLabeledPrediction(errorProbability: 0.01, isError: false),
            ConfidenceLabeledPrediction(errorProbability: 0.90, isError: true),
            ConfidenceLabeledPrediction(errorProbability: 0.20, isError: false),
            ConfidenceLabeledPrediction(errorProbability: 0.60, isError: true),
        ]
        let metrics = ConfidenceMetrics.evaluate(
            predictions,
            binCount: 2,
            verifierBudgets: [0.5],
            falseUnlockThreshold: 0.2
        )

        XCTAssertEqual(metrics.sampleCount, 4)
        XCTAssertEqual(metrics.errorCount, 2)
        XCTAssertEqual(metrics.brierScore ?? -1, 0.052_525, accuracy: 0.000_001)
        XCTAssertEqual(metrics.auprc ?? -1, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(metrics.rocAuc ?? -1, 1.0, accuracy: 0.000_001)
        XCTAssertNotNil(metrics.ece)
        XCTAssertNotNil(metrics.mce)
        XCTAssertNotNil(metrics.nce)
        XCTAssertEqual(metrics.falseUnlockRate, 0)
        XCTAssertEqual(metrics.riskCoverage.last?.coverage, 1)
        XCTAssertEqual(metrics.errorRecallAtVerifierBudget.first?.errorRecall, 1)
    }

    func testFalseUnlockRateIsAbsentWithoutAnExplicitOperatingPoint() {
        let metrics = ConfidenceMetrics.evaluate([
            ConfidenceLabeledPrediction(errorProbability: 0.1, isError: false),
            ConfidenceLabeledPrediction(errorProbability: 0.8, isError: true),
        ])
        XCTAssertNil(metrics.falseUnlockRate)
        XCTAssertNil(metrics.falseUnlockThreshold)
    }

    func testEstimatorRequiresMatchingCalibrationKeyAndThresholdProvenance() throws {
        let examples = [
            example(0.1, error: false),
            example(0.8, error: true),
        ]
        let calibrator = try ConfidenceCalibrator.fitPlatt(
            examples: examples,
            key: whisperKey
        )
        let matchingResult = result()
        let estimate = ConfidenceEstimator(calibrator: calibrator).estimate(
            result: matchingResult,
            wordIndex: 0
        )
        XCTAssertEqual(estimate.status, .calibrated)
        XCTAssertNotNil(estimate.calibratedErrorProbability)

        let mismatch = ConfidenceCalibrationKey(
            engine: .parakeetTDTCoreML,
            modelIdentifier: "other"
        )
        let mismatchedFeatures = ConfidenceFeatures(
            calibrationKey: mismatch,
            values: [.posterior: 0.8]
        )
        let mismatched = ConfidenceEstimator(calibrator: calibrator).estimate(
            features: mismatchedFeatures
        )
        XCTAssertEqual(mismatched.status, .calibrationKeyMismatch)
        XCTAssertNil(mismatched.calibratedErrorProbability)

        let calibratedThreshold = ConfidenceThreshold.calibrated(
            0.3,
            artifactID: "synthetic-w05",
            calibrator: calibrator
        )
        XCTAssertFalse(
            ConfidenceEstimator(calibrator: calibrator).shouldVerify(
                estimate: mismatched,
                threshold: calibratedThreshold
            )
        )
        let uncalibratedThreshold = ConfidenceThreshold.uncalibrated(0.1)
        XCTAssertTrue(
            ConfidenceEstimator().shouldVerify(
                estimate: ConfidenceEstimator().estimate(
                    result: matchingResult,
                    wordIndex: 0
                ),
                threshold: uncalibratedThreshold
            )
        )
    }

    func testApplyingCalibrationPreservesCanonicalTextAndOnlyAddsWordScores() throws {
        let examples = [
            example(0.1, error: false),
            example(0.8, error: true),
        ]
        let calibrator = try ConfidenceCalibrator.fitTemperature(
            examples: examples,
            key: whisperKey
        )
        let source = result()
        let calibrated = ConfidenceEstimator(calibrator: calibrator)
            .applyingCalibration(to: source)

        XCTAssertEqual(calibrated.text, source.text)
        XCTAssertEqual(calibrated.words.map(\.id), source.words.map(\.id))
        XCTAssertNotNil(calibrated.words[0].calibratedErrorProbability)
    }
}
