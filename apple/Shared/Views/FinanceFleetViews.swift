import SwiftUI

struct FinanceCentreView: View {
    @Environment(AppState.self) private var appState
    private var liveJobs: [Lead] {
        appState.leads.filter { [.won, .scheduled, .inProgress, .completed, .waitingForPayment, .paid].contains($0.stage) }
    }
    private var depositsDue: [Lead] { liveJobs.filter { !$0.depositPaid && $0.deposit > 0 && $0.stage != .paid } }
    private var collected: Double { liveJobs.reduce(0) { $0 + max(0, $1.value - $1.balance) } }
    private var outstanding: Double { liveJobs.reduce(0) { $0 + max(0, $1.balance) } }
    private var materialCost: Double {
        liveJobs.reduce(0) { total, lead in total + lead.materials.reduce(0) { $0 + (($1.cost ?? 0) * $1.quantity) } }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("See what has come in and what customers still owe.").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    financeMetric("Collected", collected, "banknote.fill", .green)
                    financeMetric("To collect", outstanding, "sterlingsign.circle.fill", Color.accentColor)
                    financeMetric("Deposits due", depositsDue.reduce(0) { $0 + $1.deposit }, "exclamationmark.circle.fill", .red)
                    financeMetric("Materials logged", materialCost, "shippingbox.fill", .purple)
                }
                financePanel("Outstanding deposits", systemImage: "creditcard") {
                    if depositsDue.isEmpty {
                        ContentUnavailableView(
                            "No deposits outstanding", systemImage: "checkmark.circle",
                            description: Text("Deposits awaiting payment will appear here."))
                    } else {
                        ForEach(depositsDue) { lead in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(lead.name).fontWeight(.semibold);
                                    Text("\(lead.jobRef) · \(lead.jobType)").font(.caption).foregroundStyle(.secondary)
                                }; Spacer(); Text(lead.deposit, format: .currency(code: "GBP")).fontWeight(.semibold);
                                Button("Mark paid") { Task { await appState.recordDeposit(for: lead) } }.buttonStyle(.borderedProminent)
                                    .tint(.green);
                                NavigationLink {
                                    LeadDetailView(leadID: lead.id)
                                } label: {
                                    Image(systemName: "chevron.right")
                                }.buttonStyle(.plain)
                            }; Divider()
                        }
                    }
                }
            }.padding(24)
        }.background(Color.primary.opacity(0.025)).navigationTitle("Finance")
    }
    private func financeMetric(_ title: String, _ value: Double, _ icon: String, _ colour: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary).frame(width: 42, height: 42);
            VStack(alignment: .leading) {
                Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(.title2.bold());
                Text(title).font(.caption).foregroundStyle(.secondary)
            }; Spacer()
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func financePanel<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: systemImage).font(.headline); content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading).background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct FleetView: View {
    @Environment(AppState.self) private var appState
    @State private var showingRenewal = false
    @State private var showingVehicle = false
    @State private var editingVehicle: FleetVehicleSelection?
    @State private var deletingVehicle: FleetVehicleSelection?
    private var renewals: [GeneralTask] {
        appState.generalTasks.filter { task in
            !task.completed && ["Fleet", "Vehicle", "Renewal"].contains(task.category)
                && !task.title.localizedCaseInsensitiveContains("insurance")
                && !task.title.localizedCaseInsensitiveContains("road tax")
        }.sorted { ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") }
    }
    private var vehicles: [(GeneralTask, FleetVehicleInfo)] {
        appState.generalTasks.filter { $0.category == "Fleet Vehicle" }.compactMap { task in
            guard let data = task.notes?.data(using: .utf8), let info = try? JSONDecoder().decode(FleetVehicleInfo.self, from: data) else {
                return nil
            }; return (task, info)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep vans roadworthy, serviced and ready for work.").foregroundStyle(.secondary)
                    }; Spacer();
                    Button {
                        showingRenewal = true
                    } label: {
                        Label("Add reminder", systemImage: "calendar.badge.plus")
                    }.buttonStyle(.bordered);
                    Button {
                        showingVehicle = true
                    } label: {
                        Label("Add vehicle", systemImage: "plus")
                    }.buttonStyle(.borderedProminent)
                }; Text("Vehicles").font(.title2.bold());
                if vehicles.isEmpty {
                    ContentUnavailableView(
                        "No vehicles added", systemImage: "car.2",
                        description: Text("Add your vans to keep their important details together."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 14)], spacing: 14) {
                        ForEach(vehicles, id: \.0.id) { task, info in vehicleCard(task, info) }
                    }
                };
                VStack(alignment: .leading, spacing: 12) {
                    Label("Upcoming reminders", systemImage: "calendar.badge.exclamationmark").font(.headline);
                    if renewals.isEmpty {
                        Text("No open MOT, service or breakdown reminders.").foregroundStyle(.secondary).padding(.vertical, 18)
                    } else {
                        ForEach(renewals) { task in
                            HStack {
                                Button {
                                    Task { await appState.toggleGeneralTask(task) }
                                } label: {
                                    Image(systemName: "circle")
                                }.buttonStyle(.plain);
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).fontWeight(.semibold);
                                    Text(task.dueDate.map { "Due \($0)" } ?? "No date").font(.caption).foregroundStyle(
                                        isUrgent(task) ? .red : .secondary)
                                }; Spacer(); if isUrgent(task) { Text("Due soon").font(.caption.bold()).foregroundStyle(.red) }
                            }; Divider()
                        }
                    }
                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }.padding(24)
        }.navigationTitle("Fleet").sheet(isPresented: $showingRenewal) { AddRenewalView() }.sheet(isPresented: $showingVehicle) {
            AddVehicleView()
        }.sheet(item: $editingVehicle) { AddVehicleView(existing: $0) }.confirmationDialog(
            "Delete this vehicle?", isPresented: Binding(get: { deletingVehicle != nil }, set: { if !$0 { deletingVehicle = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete vehicle", role: .destructive) {
                guard let vehicle = deletingVehicle else { return }; deletingVehicle = nil;
                Task { await appState.deleteGeneralTask(vehicle.task) }
            }; Button("Cancel", role: .cancel) { deletingVehicle = nil }
        } message: {
            Text("The vehicle card will be deleted. Existing MOT and service reminders will remain in Tasks.")
        }
    }
    private func isUrgent(_ task: GeneralTask) -> Bool {
        guard let due = task.dueDate, let limit = Calendar.current.date(byAdding: .day, value: 30, to: .now) else { return false };
        return due <= SupabaseService.localDay(for: limit)
    }
    private func vehicleName(_ task: GeneralTask) -> String { task.title.components(separatedBy: " — ").first ?? task.title }
    private func fleetMetric(_ title: String, _ value: Int, _ icon: String, _ colour: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary).frame(width: 44, height: 44);
            VStack(alignment: .leading) {
                Text("\(value)").font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary)
            }; Spacer()
        }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func vehicleCard(_ task: GeneralTask, _ info: FleetVehicleInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "car.side.fill").font(.title).foregroundStyle(Color.accentColor).frame(width: 50, height: 50).background(
                    Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12));
                VStack(alignment: .leading) {
                    Text(task.title.uppercased()).font(.title3.bold());
                    Text([info.make, info.model].filter { !$0.isEmpty }.joined(separator: " ")).foregroundStyle(.secondary)
                }; Spacer();
                Menu {
                    Button {
                        editingVehicle = .init(task: task, info: info)
                    } label: {
                        Label("Edit vehicle", systemImage: "pencil")
                    };
                    Button(role: .destructive) {
                        deletingVehicle = .init(task: task, info: info)
                    } label: {
                        Label("Delete vehicle", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }.menuStyle(.borderlessButton).fixedSize()
            };
            if !info.status.isEmpty {
                Text(info.status).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(
                    .green.opacity(0.12), in: Capsule()
                ).foregroundStyle(.green)
            }; Divider(); vehicleRow("Driver", info.driver.isEmpty ? "Unassigned" : info.driver, "person");
            vehicleRow("Mileage", info.mileage.isEmpty ? "Not recorded" : info.mileage, "gauge.with.dots.needle.67percent");
            vehicleRow("MOT", info.motDate.isEmpty ? "Not set" : info.motDate, "checkmark.seal");
            vehicleRow("Service", info.serviceDate.isEmpty ? "Not set" : info.serviceDate, "wrench.and.screwdriver")
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func vehicleRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium)
        }.font(.caption)
    }
}

private struct FleetVehicleInfo: Codable {
    var make: String; var model: String; var driver: String; var mileage: String; var motDate: String; var serviceDate: String;
    var status: String
}
private struct FleetVehicleSelection: Identifiable { var id: String { task.id }; let task: GeneralTask; let info: FleetVehicleInfo }

private struct AddVehicleView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var registration = ""; @State private var make = ""; @State private var model = ""; @State private var driver = "";
    @State private var mileage = ""
    @State private var hasMOT = false; @State private var mot = Date(); @State private var hasService = false;
    @State private var service = Date()
    @State private var lookingUpMOT = false
    @State private var isSaving = false
    @State private var motLookupMessage: String?
    private let existing: FleetVehicleSelection?
    init(existing: FleetVehicleSelection? = nil) {
        self.existing = existing
        _registration = State(initialValue: existing?.task.title ?? "")
        _make = State(initialValue: existing?.info.make ?? "")
        _model = State(initialValue: existing?.info.model ?? "")
        _driver = State(initialValue: existing?.info.driver ?? "")
        _mileage = State(initialValue: existing?.info.mileage ?? "")
        _hasMOT = State(initialValue: !(existing?.info.motDate ?? "").isEmpty)
        _mot = State(initialValue: existing.flatMap { SupabaseService.date(from: $0.info.motDate) } ?? .now)
        _hasService = State(initialValue: !(existing?.info.serviceDate ?? "").isEmpty)
        _service = State(initialValue: existing.flatMap { SupabaseService.date(from: $0.info.serviceDate) } ?? .now)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle details") {
                    HStack {
                        TextField("Registration number", text: $registration).textCase(.uppercase)
                        Button {
                            lookupMOT()
                        } label: {
                            if lookingUpMOT { ProgressView().controlSize(.small) } else { Label("Look up", systemImage: "magnifyingglass") }
                        }
                        .disabled(registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lookingUpMOT)
                    }
                    if let motLookupMessage {
                        Text(motLookupMessage).font(.caption).foregroundStyle(motLookupMessage.hasPrefix("Found") ? .green : .red)
                    }
                    HStack {
                        TextField("Make", text: $make); TextField("Model", text: $model)
                    }
                }
                Section("Use") {
                    TextField("Assigned driver", text: $driver); TextField("Current mileage", text: $mileage)
                }
                Section("MOT") {
                    Toggle("Track MOT", isOn: $hasMOT);
                    if hasMOT {
                        DatePicker("MOT expires", selection: $mot, displayedComponents: .date)
                    } else {
                        Text("Use Look up to retrieve the current MOT expiry.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Servicing") {
                    Toggle("Track next service", isOn: $hasService);
                    if hasService {
                        DatePicker("Next service", selection: $service, displayedComponents: .date)
                    } else {
                        Text("Set this manually from the van's service schedule.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Label("Saving creates the vehicle card and its renewal reminders automatically.", systemImage: "bell.badge").font(
                        .caption
                    ).foregroundStyle(.secondary)
                }
            }.disabled(isSaving).navigationTitle(existing == nil ? "Add vehicle" : "Edit vehicle").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) };
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text(existing == nil ? "Save vehicle" : "Save changes") }
                    }.disabled(registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }.frame(minWidth: 540, minHeight: 680)
    }
    private func dateString(_ date: Date, enabled: Bool) -> String { enabled ? PayrollMath.key(date) : "" }
    private func lookupMOT() {
        lookingUpMOT = true; motLookupMessage = nil
        Task {
            do {
                let vehicle = try await SupabaseService.shared.lookupMOT(registration: registration)
                registration = vehicle.registration; make = vehicle.make; model = vehicle.model
                if !vehicle.odometerValue.isEmpty {
                    mileage = [vehicle.odometerValue, vehicle.odometerUnit].filter { !$0.isEmpty }.joined(separator: " ")
                }
                if let expiry = SupabaseService.date(from: vehicle.motExpiryDate), !vehicle.motExpiryDate.isEmpty {
                    mot = expiry; hasMOT = true
                    motLookupMessage = "Found \(vehicle.make) \(vehicle.model) · MOT expires \(vehicle.motExpiryDate)"
                } else {
                    hasMOT = false
                    motLookupMessage = "Found \(vehicle.make) \(vehicle.model), but DVSA supplied no current MOT expiry."
                }
            } catch { motLookupMessage = error.localizedDescription }
            lookingUpMOT = false
        }
    }
    private func save() {
        let reg = registration.uppercased().filter { !$0.isWhitespace }
        let motDate = dateString(mot, enabled: hasMOT), serviceDate = dateString(service, enabled: hasService)
        let info = FleetVehicleInfo(
            make: make, model: model, driver: driver, mileage: mileage, motDate: motDate, serviceDate: serviceDate, status: "Active")
        guard let data = try? JSONEncoder().encode(info), let json = String(data: data, encoding: .utf8) else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            if let existing {
                var changed = existing.task
                changed.title = reg
                changed.notes = json
                guard await appState.saveGeneralTask(changed) else { return }
            } else {
                guard await appState.addFleetVehicle(registration: reg, detailsJSON: json) else { return }
                if hasMOT {
                    await appState.addGeneralTask(
                        title: "\(reg) — MOT", dueDate: motDate, priority: "high", category: "Fleet", assignedTo: [], notes: nil)
                }
                if hasService {
                    await appState.addGeneralTask(
                        title: "\(reg) — Service", dueDate: serviceDate, priority: "medium", category: "Fleet", assignedTo: [], notes: nil)
                }
            }
            dismiss()
        }
    }
}

private struct AddRenewalView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vehicle = ""
    @State private var type = "MOT"
    @State private var dueDate = Date()
    @State private var notes = ""
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Registration or van name", text: $vehicle);
                    Picker("Reminder", selection: $type) { ForEach(["MOT", "Service", "Breakdown cover"], id: \.self) { Text($0) } };
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                }; Section("Details") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5) };
                Section {
                    Text("ProLine will place this in Tasks and schedule a notification before it is due.").font(.caption).foregroundStyle(
                        .secondary)
                }
            }.disabled(isSaving).navigationTitle("Add vehicle reminder").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) };
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true; defer { isSaving = false }; let date = PayrollMath.key(dueDate);
                            if await appState.addGeneralTask(
                                title: "\(vehicle) — \(type)", dueDate: date, priority: "high", category: "Fleet",
                                notes: notes.isEmpty ? nil : notes)
                            {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }.disabled(vehicle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }.frame(minWidth: 460, minHeight: 380)
    }
}
