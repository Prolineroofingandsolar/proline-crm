import SwiftUI

/// One-tap record of how a call went, offered when the user comes back to the app.
struct CallOutcomeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let pending: PendingCall
    @State private var outcome: CallOutcome = .spoke
    @State private var note = ""
    @State private var followUp = true
    @State private var followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Outcome", selection: $outcome) { ForEach(CallOutcome.allCases) { Text($0.short).tag($0) } }
                        .pickerStyle(.segmented)
                    TextField("What was said?", text: $note, axis: .vertical).lineLimit(2...5)
                } header: {
                    Text(pending.leadName)
                }
                Section {
                    Toggle("Follow up", isOn: $followUp)
                    if followUp { DatePicker("On", selection: $followUpDate, displayedComponents: .date) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Log call")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving)
                }
            }
            .onChange(of: outcome) { _, value in if value != .spoke { followUp = true } }
        }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private func save() {
        saving = true
        Task {
            if await appState.logCall(leadID: pending.id, outcome: outcome, note: note, followUp: followUp ? followUpDate : nil) {
                dismiss()
            }
            saving = false
        }
    }
}
