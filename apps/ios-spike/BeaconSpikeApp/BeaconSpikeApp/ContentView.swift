import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = SpikeCaptureViewModel()
    @State private var exportRequest: ExportRequest?

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture Status") {
                    LabeledContent("Authorization", value: viewModel.authorizationStatus)
                    LabeledContent("Monitoring", value: viewModel.monitoringStatus)
                    LabeledContent("Entries Logged", value: "\(viewModel.logEntryCount)")
                }

                Section("Controls") {
                    Button("Request Authorization + Start") {
                        viewModel.requestAuthorizationAndStart()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop Monitoring") {
                        viewModel.stopMonitoring()
                    }

                    Button("Refresh Log Count") {
                        Task {
                            await viewModel.refreshLogEntryCount()
                        }
                    }

                    Button("Capture SSID Probe") {
                        viewModel.captureSSIDProbeManually()
                    }

                    Button("Capture Focus Snapshot") {
                        viewModel.captureFocusSnapshotManually()
                    }

                    Button("Clear Log", role: .destructive) {
                        viewModel.clearLog()
                    }

                    Button("Export NDJSON") {
                        if let fileURL = viewModel.prepareExportFileURL() {
                            exportRequest = ExportRequest(fileURL: fileURL)
                        }
                    }
                }

                if let lastError = viewModel.lastError {
                    Section("Last Error") {
                        Text(lastError)
                            .foregroundStyle(.red)
                    }
                }

                Section("Log File") {
                    Text(viewModel.logFilePath)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }

                Section("Recent Events") {
                    if viewModel.events.isEmpty {
                        Text("No events captured yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.message)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Beacon Spike")
        }
        .task {
            await viewModel.refreshLogEntryCount()
        }
        .sheet(item: $exportRequest, onDismiss: {
            exportRequest = nil
        }) { request in
            ActivityView(activityItems: [request.fileURL])
        }
    }
}

private struct ExportRequest: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

#Preview {
    ContentView()
}
