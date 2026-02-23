import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SpikeCaptureViewModel()

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
    }
}

#Preview {
    ContentView()
}
