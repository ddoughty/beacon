import BeaconSpikeCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum AnalyzeCommandError: LocalizedError {
    case usage

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
                Usage: BeaconSpikeAnalyze <path-to-phase0-signals.ndjson> [--require-clvisit]
                """
        }
    }
}

@main
struct BeaconSpikeAnalyzeCommand {
    static func main() {
        do {
            let options = try parseArguments()
            let analyzer = SpikeLogAnalyzer()
            let summary = try analyzer.analyze(fileURL: URL(fileURLWithPath: options.filePath))
            printSummary(summary, filePath: options.filePath)
            if options.requireCLVisit && (!summary.hasVisitArrival || !summary.hasVisitDeparture) {
                fputs(
                    "Missing CLVisit evidence. Require both clvisit_arrival and clvisit_departure entries.\n",
                    stderr
                )
                exit(3)
            }
        } catch let error as AnalyzeCommandError {
            fputs((error.errorDescription ?? "Invalid arguments") + "\n", stderr)
            exit(2)
        } catch {
            fputs("BeaconSpikeAnalyze failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func parseArguments() throws -> (filePath: String, requireCLVisit: Bool) {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            throw AnalyzeCommandError.usage
        }

        var filePath: String?
        var requireCLVisit = false
        for argument in args {
            if argument == "--require-clvisit" {
                requireCLVisit = true
                continue
            }
            guard filePath == nil else {
                throw AnalyzeCommandError.usage
            }
            filePath = argument
        }

        guard let filePath else {
            throw AnalyzeCommandError.usage
        }

        return (filePath: filePath, requireCLVisit: requireCLVisit)
    }

    private static func printSummary(_ summary: SpikeLogAnalysisSummary, filePath: String) {
        print("Spike log analysis")
        print("File: \(filePath)")
        print("Entries: \(summary.totalEntries) total, \(summary.transitionEntryCount) transition_sample")
        if let firstRecordedAt = summary.firstRecordedAt, let lastRecordedAt = summary.lastRecordedAt {
            print("Window: \(timestampString(for: firstRecordedAt)) -> \(timestampString(for: lastRecordedAt))")
        }
        print("CLVisit arrival present: \(yesNo(summary.hasVisitArrival))")
        print("CLVisit departure present: \(yesNo(summary.hasVisitDeparture))")
        print("")
        print("| Signal | Samples | p50 (s) | p95 (s) | p99 (s) | max (s) |")
        print("| --- | ---: | ---: | ---: | ---: | ---: |")
        for signalSummary in summary.signalSummaries {
            print(
                "| \(signalSummary.signalType.rawValue) | \(signalSummary.sampleCount) | " +
                    "\(delayString(signalSummary.p50DelaySeconds)) | \(delayString(signalSummary.p95DelaySeconds)) | " +
                    "\(delayString(signalSummary.p99DelaySeconds)) | \(delayString(signalSummary.maxDelaySeconds)) |"
            )
        }
        print("")
        print("Hybrid fast-path")
        print("Stage metadata present: \(yesNo(summary.hybridFastPath.stageMetadataPresent))")
        print("Confirmation linkage present: \(yesNo(summary.hybridFastPath.confirmationLinkagePresent))")
        print("")
        print("| Metric | Value |")
        print("| --- | ---: |")
        print("| provisional transitions emitted | \(countString(summary.hybridFastPath.provisionalTransitionsEmitted)) |")
        print(
            "| provisional transitions confirmed by CLVisit | " +
                "\(optionalCountString(summary.hybridFastPath.provisionalTransitionsConfirmed)) |"
        )
        print(
            "| provisional confirmation rate (%) | " +
                "\(delayString(summary.hybridFastPath.provisionalConfirmationRatePercent)) |"
        )
        print(
            "| provisional p50 time-to-first-detection (s) | " +
                "\(delayString(summary.hybridFastPath.provisionalP50DetectionSeconds)) |"
        )
        print(
            "| provisional p95 time-to-first-detection (s) | " +
                "\(delayString(summary.hybridFastPath.provisionalP95DetectionSeconds)) |"
        )
        print(
            "| provisional p95 time-to-confirmation (s) | " +
                "\(delayString(summary.hybridFastPath.confirmationP95Seconds)) |"
        )
        let shortStop = shortStopString(
            falsePositives: summary.hybridFastPath.shortStopFalsePositives,
            observed: summary.hybridFastPath.shortStopObservationCount
        )
        print(
            "| short-stop false positives (<15 min) | " +
                "\(shortStop) |"
        )
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func delayString(_ delay: Double?) -> String {
        guard let delay else {
            return "n/a"
        }
        return String(format: "%.1f", delay)
    }

    private static func countString(_ value: Int) -> String {
        "\(value)"
    }

    private static func optionalCountString(_ value: Int?) -> String {
        guard let value else {
            return "n/a"
        }
        return "\(value)"
    }

    private static func shortStopString(falsePositives: Int?, observed: Int?) -> String {
        guard let falsePositives, let observed else {
            return "n/a"
        }
        return "\(falsePositives) / \(observed)"
    }

    private static func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
