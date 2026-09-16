import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
@preconcurrency import Speech
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct PhoneActionMenu: View {
    let number: String
    var label: String = "Phone"
    var body: some View {
        Menu {
            if let url = ContactLinks.telephone(number) { Link(destination: url) { Label("Call", systemImage: "phone.fill") } }
            if let url = ContactLinks.message(number) { Link(destination: url) { Label("Text message", systemImage: "message.fill") } }
            if let url = ContactLinks.whatsApp(number) { Link(destination: url) { Label("WhatsApp", systemImage: "bubble.left.and.bubble.right.fill") } }
            Divider()
            Button { copyNumber() } label: { Label("Copy number", systemImage: "doc.on.doc") }
        } label: { Label(label, systemImage: "phone.fill") }
    }
    private func copyNumber() {
        #if os(iOS)
        UIPasteboard.general.string = number
        #elseif os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(number, forType: .string)
        #endif
    }
}

struct LeadDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let leadID: String
    @State private var tab = "Info"
    @State private var showingEdit = false
    @State private var showingSurveySchedule = false
    @State private var newNote = ""
    @State private var confirmingDelete = false
    @State private var addingPhoto = false
    @State private var addingMaterial = false
    @State private var addingFile = false
    @State private var addingTask = false
    @State private var confirmingDeposit = false
    @State private var confirmingFinalPayment = false
    @State private var showingJobUpdate = false
    var lead: Lead? { appState.leads.first { $0.id == leadID } }

    var body: some View {
        if let lead {
            #if os(macOS)
            macDetail(lead)
            #else
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) { ForEach(["Info","Survey","Quotes","Tasks","Photos","Materials","Notes","Files"], id: \.self) { Text($0) } }.pickerStyle(.segmented).padding()
                Group {
                    switch tab {
                    case "Survey": LeadSurveyView(lead: lead)
                    case "Quotes": LeadQuotesView(lead: lead)
                    case "Tasks": tasks(lead)
                    case "Photos": photos(lead)
                    case "Materials": materials(lead)
                    case "Notes": notes(lead)
                    case "Files": files(lead)
                    default: info(lead)
                    }
                }
            }.navigationTitle(lead.name).toolbar {
                Button { showingJobUpdate = true } label: { Label("Update job", systemImage: "mic.fill") }
                Button("Edit") { showingEdit = true }
                Menu { Button { showingSurveySchedule = true } label: { Label(lead.surveyDate == nil ? "Schedule survey" : "Edit survey", systemImage: "calendar.badge.clock") }; Divider(); ForEach(LeadStage.allCases) { stage in Button(stage.rawValue) { Task { await appState.move(lead, to: stage) } } }; if appState.isAdmin { Divider(); Button("Delete Lead", role: .destructive) { confirmingDelete = true } } } label: { Image(systemName: "ellipsis.circle") }
            }.sheet(isPresented: $showingEdit) { EditLeadView(lead: lead) }
                .sheet(isPresented: $showingSurveySchedule) { ScheduleSurveySheet(lead: lead) }
                .sheet(isPresented: $addingTask) { AddLeadTaskSheet(lead: lead) }
                .sheet(isPresented: $showingJobUpdate) { JobUpdateSheet(leadID: lead.id) }
                .confirmationDialog("Record deposit payment?", isPresented: $confirmingDeposit, titleVisibility: .visible) { Button("Record \(lead.deposit.formatted(.currency(code: "GBP"))) deposit") { Task { await appState.recordDeposit(for: lead) } } } message: { Text("This reduces the outstanding balance. You can correct it later by editing the lead.") }
                .confirmationDialog("Mark this job as paid?", isPresented: $confirmingFinalPayment, titleVisibility: .visible) { Button("Mark paid") { Task { await appState.recordFinalPayment(for: lead) } } } message: { Text("This clears the balance and moves the job to Paid.") }
                .confirmationDialog("Delete \(lead.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) { Button("Delete Lead", role: .destructive) { Task { if await appState.deleteLead(lead) { dismiss() } } } } message: { Text("This permanently removes the customer lead and its job records.") }
            #endif
        } else { ContentUnavailableView("Lead not found", systemImage: "person.crop.circle.badge.questionmark") }
    }

    #if os(macOS)
    private func macDetail(_ lead: Lead) -> some View {
        VStack(spacing: 0) {
            macTitleBar(lead)
            ScrollView {
                VStack(spacing: 0) {
                    macProfileHeader(lead)
                    macTabs
                    HStack(alignment: .top, spacing: 0) {
                        Group {
                            switch tab {
                            case "Survey": LeadSurveyView(lead: lead)
                            case "Quotes": LeadQuotesView(lead: lead)
                            case "Tasks": macTasks(lead)
                            case "Photos": photos(lead)
                            case "Materials": macMaterials(lead)
                            case "Notes": macNotes(lead)
                            case "Files": files(lead)
                            default: macInfo(lead)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        if tab == "Info" { Divider(); macRightRail(lead).frame(width: 350) }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(lead.name)
        .toolbar(.hidden)
        .sheet(isPresented: $showingEdit) { EditLeadView(lead: lead) }
        .sheet(isPresented: $showingSurveySchedule) { ScheduleSurveySheet(lead: lead) }
        .sheet(isPresented: $addingTask) { AddLeadTaskSheet(lead: lead) }
        .sheet(isPresented: $showingJobUpdate) { JobUpdateSheet(leadID: lead.id) }
        .confirmationDialog("Record deposit payment?", isPresented: $confirmingDeposit, titleVisibility: .visible) {
            Button("Record \(lead.deposit.formatted(.currency(code: "GBP"))) deposit") { Task { await appState.recordDeposit(for: lead) } }
        } message: { Text("This reduces the outstanding balance. You can correct it later by editing the lead.") }
        .confirmationDialog("Mark this job as paid?", isPresented: $confirmingFinalPayment, titleVisibility: .visible) {
            Button("Mark paid") { Task { await appState.recordFinalPayment(for: lead) } }
        } message: { Text("This clears the balance and moves the job to Paid.") }
        .confirmationDialog("Delete \(lead.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Lead", role: .destructive) { Task { if await appState.deleteLead(lead) { dismiss() } } }
        } message: { Text("This permanently removes the customer lead and its job records.") }
    }

    private func macTitleBar(_ lead: Lead) -> some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.headline).frame(width: 34, height: 34).background(.background, in: Circle()).overlay(Circle().stroke(.quaternary)) }.buttonStyle(.plain)
            Text(lead.name).font(.title3.bold())
            Spacer()
            Button { showingJobUpdate = true } label: { Label("Update job", systemImage: "mic.fill") }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
            Button("Edit") { showingEdit = true }.controlSize(.large)
            Menu {
                Button { showingSurveySchedule = true } label: { Label(lead.surveyDate == nil ? "Schedule survey" : "Edit survey", systemImage: "calendar.badge.clock") }
                Divider()
                ForEach(LeadStage.allCases) { stage in Button("Move to \(stage.displayName)") { Task { await appState.move(lead, to: stage) } } }
                if appState.isAdmin {
                    Divider()
                    Button("Delete Lead", role: .destructive) { confirmingDelete = true }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 34, height: 34) }.menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 24).frame(height: 62).background(.background).overlay(alignment: .bottom) { Divider() }
    }

    private func macProfileHeader(_ lead: Lead) -> some View {
        HStack(spacing: 20) {
            Text(initials(lead.name)).font(.system(size: 30, weight: .medium)).frame(width: 92, height: 92).background(Color(nsColor: .controlBackgroundColor), in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(lead.name).font(.system(size: 30, weight: .bold))
                HStack(spacing: 8) { Circle().fill(stageColor(lead.stage)).frame(width: 9, height: 9); Text(lead.stage.displayName) }
                Text([nonEmpty(lead.jobType), nonEmpty(lead.source), "Value \(money(lead.value))"].compactMap { $0 }.joined(separator: "  •  ")).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                if !lead.phone.isEmpty { PhoneActionMenu(number: lead.phone, label: "Contact").frame(width: 112, height: 42).foregroundStyle(.white).background(.blue, in: RoundedRectangle(cornerRadius: 8)).buttonStyle(.plain) }
                if let mailURL = ContactLinks.email(lead.email) { Link(destination: mailURL) { Label("Email", systemImage: "envelope").frame(width: 112, height: 42).background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary)) }.buttonStyle(.plain) }
                Button { addingTask = true } label: { Label("Add task", systemImage: "checkmark.square").frame(width: 120, height: 42).background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary)) }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 36).padding(.vertical, 28)
    }

    private var macTabs: some View {
        HStack(spacing: 38) {
            ForEach(["Info","Survey","Quotes","Tasks","Photos","Materials","Notes","Files"], id: \.self) { item in
                Button { tab = item } label: { Text(item).fontWeight(tab == item ? .semibold : .regular).foregroundStyle(tab == item ? Color.blue : Color.primary).padding(.vertical, 14).overlay(alignment: .bottom) { Rectangle().fill(tab == item ? Color.blue : Color.clear).frame(height: 2) } }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(.horizontal, 36).overlay(alignment: .bottom) { Divider() }
    }

    private func macTasks(_ lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tasks").font(.title2.bold())
                    Text("\(lead.tasks.filter(\.completed).count) of \(lead.tasks.count) completed")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { addingTask = true } label: { Label("Add task", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
            }

            if lead.tasks.isEmpty {
                ContentUnavailableView("No tasks yet", systemImage: "checklist", description: Text("Add the next action for this lead."))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                VStack(spacing: 0) {
                    ForEach(lead.tasks) { task in
                        Button {
                            Task { await appState.toggleLeadTask(leadID: lead.id, taskID: task.id) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(task.completed ? Color.green : Color.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .fontWeight(.medium)
                                        .strikethrough(task.completed)
                                        .foregroundStyle(task.completed ? .secondary : .primary)
                                    HStack(spacing: 8) {
                                        Text(task.isTemplate == true ? "Job checklist" : "Task")
                                        if let due = task.dueDate {
                                            Label(String(due.prefix(10)), systemImage: "calendar")
                                                .foregroundStyle(!task.completed && due < SupabaseService.today ? Color.red : Color.secondary)
                                        }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(task.completed ? "Completed" : "Mark complete")
                                    .font(.caption).foregroundStyle(task.completed ? Color.green : Color.blue)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 18).frame(minHeight: 66).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete task", role: .destructive) {
                                Task { await appState.deleteLeadTask(leadID: lead.id, taskID: task.id) }
                            }
                        }
                        if task.id != lead.tasks.last?.id { Divider().padding(.leading, 52) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func macMaterials(_ lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Materials").font(.title2.bold())
                    Text("Plan, order and track everything needed for this job.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { addingMaterial = true } label: { Label("Add material", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
            }

            if lead.materials.isEmpty {
                ContentUnavailableView("No materials yet", systemImage: "shippingbox", description: Text("Add materials manually or ask the assistant to build a list from the job description."))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                VStack(spacing: 0) {
                    ForEach(lead.materials) { material in
                        HStack(spacing: 16) {
                            Image(systemName: material.delivered ? "shippingbox.fill" : "shippingbox")
                                .font(.title3).foregroundStyle(material.delivered ? Color.green : Color.orange)
                                .frame(width: 34, height: 34).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(material.name).fontWeight(.semibold)
                                Text([material.supplier, material.cost.map { $0.formatted(.currency(code: "GBP")) }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(material.quantity.formatted()) \(material.unit)").fontWeight(.medium)
                            Button { toggleMaterial(material, in: lead, delivered: false) } label: {
                                Label("Ordered", systemImage: material.ordered ? "checkmark.circle.fill" : "circle")
                            }.buttonStyle(.bordered).tint(material.ordered ? .blue : .secondary)
                            Button { toggleMaterial(material, in: lead, delivered: true) } label: {
                                Label("Delivered", systemImage: material.delivered ? "checkmark.circle.fill" : "circle")
                            }.buttonStyle(.bordered).tint(material.delivered ? .green : .secondary)
                        }
                        .padding(.horizontal, 18).frame(minHeight: 70)
                        if material.id != lead.materials.last?.id { Divider().padding(.leading, 68) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(isPresented: $addingMaterial) { AddMaterialSheet(lead: lead) }
    }

    private func macNotes(_ lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Notes").font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                Text("Add a job update").font(.headline)
                TextEditor(text: $newNote).frame(minHeight: 90).padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                HStack {
                    Text("Notes are saved to this customer and job.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { addNote(to: lead) } label: { Label("Save note", systemImage: "paperplane") }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(18).background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

            if lead.notes.isEmpty {
                ContentUnavailableView("No notes yet", systemImage: "note.text", description: Text("Job updates and assistant-created notes will appear here."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 0) {
                    ForEach(lead.notes) { note in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "note.text").foregroundStyle(.orange).frame(width: 30, height: 30)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(note.content).textSelection(.enabled)
                                Text([note.author, note.date].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(18)
                        if note.id != lead.notes.last?.id { Divider().padding(.leading, 62) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func macInfo(_ lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            detailSection("Contact") {
                if !lead.phone.isEmpty { HStack(spacing: 14) { Image(systemName: "phone").frame(width: 22); Text("Phone"); Spacer(); PhoneActionMenu(number: lead.phone, label: lead.phone) }.padding(.horizontal, 16).frame(height: 50).overlay(alignment: .bottom) { Divider().padding(.leading, 52) } }
                detailRow("Email", icon: "envelope", value: lead.email, link: ContactLinks.email(lead.email))
                detailRow("Address", icon: "mappin.circle", value: lead.address)
                detailRow("Preferred contact", icon: "person", value: !lead.phone.isEmpty ? "Phone" : (!lead.email.isEmpty ? "Email" : "Not set"))
            }
            detailSection("Job", trailing: AnyView(Button("Edit") { showingEdit = true }.buttonStyle(.plain).foregroundStyle(.blue))) {
                detailRow("Type", icon: "briefcase", value: lead.jobType)
                detailRow("Stage", icon: "circle.fill", value: lead.stage.displayName, tint: stageColor(lead.stage))
                detailRow("Reference", icon: "tag", value: lead.jobRef)
                detailRow("Value", icon: "sterlingsign.circle", value: money(lead.value))
                detailRow("Balance", icon: "wallet.pass", value: money(lead.balance))
                if !lead.depositPaid && lead.deposit > 0 {
                    Button { confirmingDeposit = true } label: { Label("Record \(money(lead.deposit)) deposit", systemImage: "checkmark.circle") }.buttonStyle(.plain).foregroundStyle(.blue).padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                }
                if lead.balance > 0 && [.won, .scheduled, .inProgress, .completed].contains(lead.stage) {
                    Button { confirmingFinalPayment = true } label: { Label("Mark \(money(lead.balance)) balance paid", systemImage: "sterlingsign.circle") }.buttonStyle(.plain).foregroundStyle(.green).padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                }
            }
            let entries = appState.timesheets.filter { $0.leadID == lead.id }
            let labourCost = entries.reduce(0) { $0 + $1.amount }
            let materialCost = lead.materials.reduce(0) { $0 + (($1.cost ?? 0) * max(1, $1.quantity)) }
            let forecastProfit = lead.value - labourCost - materialCost
            detailSection("Job cost & profit") {
                detailRow("Labour days", icon: "person.2", value: entries.reduce(0) { $0 + ($1.type == "half" ? 0.5 : $1.type == "off" ? 0 : 1) }.formatted())
                detailRow("Labour cost", icon: "clock", value: money(labourCost))
                detailRow("Materials recorded", icon: "shippingbox", value: money(materialCost))
                detailRow("Forecast profit", icon: forecastProfit >= 0 ? "chart.line.uptrend.xyaxis" : "exclamationmark.triangle", value: money(forecastProfit), tint: forecastProfit >= lead.value * 0.2 ? .green : forecastProfit >= 0 ? .orange : .red)
            }
            Text("Dates").font(.headline)
            HStack(spacing: 0) {
                dateCell("Added", icon: "calendar", value: displayDate(lead.createdAt)); Divider().frame(height: 52)
                dateCell("Last contacted", icon: "clock", value: displayDate(lead.updatedAt)); Divider().frame(height: 52)
                dateCell("Target close", icon: "scope", value: lead.startDate.map(displayDate) ?? "Not set")
            }.padding(.vertical, 10).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        }.padding(36)
    }

    private func macRightRail(_ lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Next action").font(.title3.bold())
            if let task = lead.tasks.first(where: { !$0.completed }) {
                VStack(alignment: .leading, spacing: 16) {
                    Label(task.title, systemImage: "checkmark.square").font(.headline)
                    if let due = task.dueDate { Text(displayDate(due)).font(.caption).foregroundStyle(.secondary) }
                    Button("Complete") { complete(task, for: lead) }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark").font(.system(size: 38)).foregroundStyle(.secondary).frame(width: 74, height: 74).background(.quaternary, in: Circle())
                    Text("Nothing scheduled").font(.title3.bold())
                    Text("Add a reminder so this lead doesn’t get missed.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Add next action") { addingTask = true }.buttonStyle(.borderedProminent).tint(Color(red: 1, green: 0.28, blue: 0.03)).controlSize(.large).frame(maxWidth: .infinity)
                    Button(lead.surveyDate == nil ? "Book survey" : "Edit survey") { showingSurveySchedule = true }.buttonStyle(.plain).foregroundStyle(.blue)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            Divider()
            Text("Quick notes").font(.headline)
            TextEditor(text: $newNote).font(.body).frame(minHeight: 130).padding(8).background(.background, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
            Button { addNote(to: lead) } label: { Label("Save note", systemImage: "paperplane").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(28)
    }

    private func detailSection<Content: View>(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { HStack { Text(title).font(.headline); Spacer(); trailing }; VStack(spacing: 0) { content() }.background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary)) }
    }
    private func detailRow(_ title: String, icon: String, value: String, link: URL? = nil, tint: Color = .primary) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).foregroundStyle(tint).frame(width: 22); Text(title); Spacer(); if let link { Link(value.isEmpty ? "Not added" : value, destination: link) } else { Text(value.isEmpty ? "Not added" : value).foregroundStyle(value.isEmpty ? .secondary : .primary) } }.padding(.horizontal, 16).frame(height: 50).overlay(alignment: .bottom) { Divider().padding(.leading, 52) }
    }
    private func dateCell(_ title: String, icon: String, value: String) -> some View { HStack(spacing: 12) { Image(systemName: icon).font(.title3); VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value) }; Spacer() }.padding(.horizontal, 18).frame(maxWidth: .infinity) }
    private func complete(_ task: CRMTask, for lead: Lead) { Task { await appState.toggleLeadTask(leadID: lead.id, taskID: task.id) } }
    private func addNote(to lead: Lead) { let value = newNote; newNote = ""; Task { await appState.addJobNote(leadID: lead.id, content: value) } }
    private func initials(_ name: String) -> String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
    private func money(_ value: Double) -> String { value.formatted(.currency(code: "GBP")) }
    private func nonEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }
    private func displayDate(_ raw: String) -> String { raw.isEmpty ? "Not set" : String(raw.prefix(10)) }
    private func stageColor(_ stage: LeadStage) -> Color { switch stage { case .newLead: .orange; case .surveyBooked: .green; case .quotePreparing, .quoteSent: .purple; case .won, .completed, .paid: .green; case .waitingForPayment: .indigo; case .lost: .red; default: .teal } }
    #endif

    private func info(_ lead: Lead) -> some View { Form { Section("Customer") { LabeledContent("Name", value: lead.name); if !lead.phone.isEmpty { PhoneActionMenu(number: lead.phone, label: lead.phone) }; if let mail = ContactLinks.email(lead.email) { Link(destination: mail) { LabeledContent("Email", value:lead.email) } } else if !lead.email.isEmpty { LabeledContent("Email", value:lead.email) }; LabeledContent("Address", value:lead.address) }; jobHealth(lead); Section("Job") { LabeledContent("Reference", value:lead.jobRef); LabeledContent("Type", value:lead.jobType); LabeledContent("Stage", value:lead.stage.rawValue); LabeledContent("Value", value:lead.value.formatted(.currency(code:"GBP"))); LabeledContent("Deposit", value:lead.deposit.formatted(.currency(code:"GBP")));LabeledContent("Balance", value:lead.balance.formatted(.currency(code:"GBP"))); LabeledContent("Source", value:lead.source);if !lead.depositPaid && lead.deposit > 0{Button("Record deposit paid"){confirmingDeposit=true}};if lead.balance > 0 && [.won,.scheduled,.inProgress,.completed].contains(lead.stage){Button("Mark balance paid"){confirmingFinalPayment=true}} }; Section("Dates") { if let value=lead.surveyDate { LabeledContent("Survey", value:[value,lead.surveyTime].compactMap{$0}.joined(separator:" · ")) }; if let value=lead.startDate { LabeledContent("Starts", value:value) }; if let value=lead.endDate { LabeledContent("Ends", value:value) } } }.formStyle(.grouped) }
    private func jobHealth(_ lead: Lead) -> some View { let entries = appState.timesheets.filter { $0.leadID == lead.id }; let labour = entries.reduce(0) { $0 + $1.amount }; let materials = lead.materials.reduce(0) { $0 + (($1.cost ?? 0) * max(1, $1.quantity)) }; let spent = labour + materials; let remaining = lead.value - spent; return Section("Job cost & profit") { LabeledContent("Labour days", value: entries.reduce(0) { $0 + ($1.type == "half" ? 0.5 : $1.type == "off" ? 0 : 1) }.formatted()); LabeledContent("Labour cost", value: labour.formatted(.currency(code:"GBP"))); LabeledContent("Materials recorded", value: materials.formatted(.currency(code:"GBP"))); LabeledContent("Forecast profit", value: remaining.formatted(.currency(code:"GBP"))); ProgressView(value: lead.value > 0 ? min(1, spent / lead.value) : 0).tint(remaining >= lead.value * 0.2 ? .green : remaining >= 0 ? .orange : .red); Text(remaining < 0 ? "Over budget — review labour and materials." : remaining < lead.value * 0.2 ? "Profit margin is getting tight." : "Currently on track for profit.").font(.caption).foregroundStyle(remaining < 0 ? .red : remaining < lead.value * 0.2 ? .orange : .green) } }

    private func tasks(_ lead: Lead) -> some View { List { Section { ForEach(lead.tasks) { task in Button { Task { await appState.toggleLeadTask(leadID:lead.id,taskID:task.id) } } label: { HStack { Label(task.title, systemImage:task.completed ? "checkmark.circle.fill":"circle").foregroundStyle(task.completed ? .secondary:.primary); Spacer(); if let due=task.dueDate { Text(String(due.prefix(10))).font(.caption).foregroundStyle(!task.completed && due < SupabaseService.today ? .red:.secondary) } } }.buttonStyle(.plain).contextMenu { Button("Delete task",role:.destructive) { Task { await appState.deleteLeadTask(leadID:lead.id,taskID:task.id) } } } } } header: { Text("\(lead.tasks.filter{$0.completed}.count) of \(lead.tasks.count) completed") }; Section { Button { addingTask=true } label:{Label("Add task",systemImage:"plus")} } } }
    private func photos(_ lead: Lead) -> some View { List { Section { Button { addingPhoto=true } label:{Label("Upload photo",systemImage:"plus")} }; ForEach(["Before","During","After"], id:\.self) { category in Section(category) { ForEach(lead.photos.filter{$0.category==category}) { photo in SecureAttachmentLink(locator:photo.url,label:photo.caption ?? "Photo",icon:"photo").contextMenu { Button("Delete photo",role:.destructive) { Task { await appState.deleteLeadPhoto(leadID:lead.id,photoID:photo.id) } } } } } } }.sheet(isPresented:$addingPhoto){AddPhotoSheet(lead:lead)} }
    private func materials(_ lead: Lead) -> some View { List { Section { Button { addingMaterial=true } label:{Label("Add material",systemImage:"plus")} };ForEach(lead.materials) { material in VStack(alignment:.leading) { HStack { Text(material.name).font(.headline); Spacer(); Text("\(material.quantity.formatted()) \(material.unit)") }; Text([material.supplier, material.cost.map{$0.formatted(.currency(code:"GBP"))}].compactMap{$0}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary); HStack { Button{toggleMaterial(material,in:lead,delivered:false)}label:{Label("Ordered", systemImage:material.ordered ? "checkmark.circle.fill":"circle")}; Button{toggleMaterial(material,in:lead,delivered:true)}label:{Label("Delivered", systemImage:material.delivered ? "checkmark.circle.fill":"circle")} }.font(.caption).buttonStyle(.plain) } } }.sheet(isPresented:$addingMaterial){AddMaterialSheet(lead:lead)} }
    private func notes(_ lead: Lead) -> some View { List { Section("Add Note") { HStack { TextField("Note", text:$newNote, axis:.vertical); Button("Add") { let value=newNote; newNote=""; Task { await appState.addJobNote(leadID:lead.id,content:value) } }.disabled(newNote.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } }; ForEach(lead.notes) { note in VStack(alignment:.leading) { Text(note.content); Text("\(note.author) · \(note.date)").font(.caption).foregroundStyle(.secondary) } } } }
    private func files(_ lead: Lead) -> some View { List { Section { Button { addingFile=true } label:{Label("Upload file",systemImage:"plus")} };ForEach(lead.files){file in if let raw=file.url { SecureAttachmentLink(locator:raw,label:file.name,icon:file.type=="image" ? "photo":"doc").contextMenu { Button("Delete file",role:.destructive) { Task { await appState.deleteLeadFile(leadID:lead.id,fileID:file.id) } } } } else { fileLabel(file) }} }.sheet(isPresented:$addingFile){AddFileSheet(lead:lead)} }
    private func fileLabel(_ file:CRMFile)->some View{Label{VStack(alignment:.leading){Text(file.name);Text([file.type,file.size,file.date].compactMap{$0}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}}icon:{Image(systemName:file.type=="image" ? "photo":"doc")}}
    private func toggleMaterial(_ material:CRMMaterial,in lead:Lead,delivered:Bool){var changed=lead;guard let i=changed.materials.firstIndex(where:{$0.id==material.id})else{return};if delivered{changed.materials[i].delivered.toggle();if changed.materials[i].delivered{changed.materials[i].ordered=true}}else{changed.materials[i].ordered.toggle()};Task{await appState.saveLead(changed)}}
}

private final class SpeechAudioBufferSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}

private func makeSpeechAudioTap(for sink: SpeechAudioBufferSink) -> AVAudioNodeTapBlock {
    { buffer, _ in
        sink.append(buffer)
    }
}

@MainActor
private final class JobUpdateSpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_GB"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggleRecording() async {
        if isRecording { stopRecording() } else { await startRecording() }
    }

    func startRecording() async {
        errorMessage = nil
        guard recognizer != nil else { errorMessage = "Speech recognition is not available on this device."; return }
        guard await speechAccessAllowed() else {
            errorMessage = "Speech recognition permission is off. Enable it for ProLine CRM in Privacy & Security settings."
            return
        }
        #if os(iOS)
        guard await microphoneAccessAllowed() else {
            errorMessage = "Microphone permission is off. Enable it for ProLine CRM in Privacy & Security settings."
            return
        }
        #endif

        stopRecording()
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        request = newRequest

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "ProLine CRM could not start the microphone: \(error.localizedDescription)"
            return
        }
        #endif

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { errorMessage = "No working microphone input was found."; return }
        removeInputTapIfNeeded()
        let bufferSink = SpeechAudioBufferSink(request: newRequest)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeSpeechAudioTap(for: bufferSink))
        tapInstalled = true
        guard let recognizer else { return }
        recognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            Task { @MainActor in
                if let text = result?.bestTranscription.formattedString { self?.transcript = text }
                if error != nil || result?.isFinal == true { self?.stopRecording() }
            }
        }
        do {
            audioEngine.prepare(); try audioEngine.start(); isRecording = true
        } catch {
            removeInputTapIfNeeded(); request = nil; recognitionTask = nil
            errorMessage = "ProLine CRM could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        if audioEngine.isRunning { audioEngine.stop() }
        removeInputTapIfNeeded()
        request?.endAudio(); recognitionTask?.cancel(); request = nil; recognitionTask = nil; isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func removeInputTapIfNeeded() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func speechAccessAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        @unknown default: return false
        }
    }

    #if os(iOS)
    private func microphoneAccessAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
        @unknown default: return false
        }
    }
    #endif
}

struct JobUpdateSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let leadID: String
    @StateObject private var speech = JobUpdateSpeechRecognizer()
    @State private var analysis: JobNoteAnalysis?
    @State private var progressNote = ""
    @State private var selectedSuggestionIDs: Set<String> = []
    @State private var selectedMaterialIDs: Set<String> = []
    @State private var includeProgressNote = true
    @State private var isAnalysing = false
    @State private var isSaving = false

    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    private var cleanTranscript: String { speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let lead {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Update job", systemImage: "mic.fill").font(.title2.bold())
                            Text("\(lead.name) · \(lead.jobRef)").foregroundStyle(.secondary)
                            Text("Describe what was completed today and anything needed next. Nothing is saved until you review and confirm it.").font(.callout).foregroundStyle(.secondary).padding(.top, 2)
                        }
                        transcriptCard
                        if isAnalysing {
                            HStack(spacing: 12) { ProgressView(); Text("Comparing this update with the job tasks and materials…").foregroundStyle(.secondary) }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        } else if let analysis { reviewCard(analysis, lead: lead) }
                    } else { ContentUnavailableView("Job not found", systemImage: "exclamationmark.triangle") }
                }.padding(20)
            }
            .navigationTitle("Job update")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { speech.stopRecording(); dismiss() }.disabled(isSaving) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    if let analysis {
                        Button { apply(analysis) } label: {
                            if isSaving { ProgressView().frame(maxWidth: .infinity) } else { Label("Confirm and save update", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }
                        }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).disabled(isSaving || (!includeProgressNote && selectedSuggestionIDs.isEmpty && selectedMaterialIDs.isEmpty))
                    } else {
                        Button { analyse() } label: { Label("Review proposed changes", systemImage: "sparkles").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).disabled(cleanTranscript.isEmpty || isAnalysing)
                    }
                }.padding(14).background(.bar)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
        .onDisappear { speech.stopRecording() }
        .onChange(of: speech.transcript) { _, _ in if analysis != nil { analysis = nil; selectedSuggestionIDs = []; selectedMaterialIDs = [] } }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(speech.isRecording ? "Listening…" : "Spoken update").font(.headline)
                    Text(speech.isRecording ? "Speak naturally, then tap Stop." : "You can also type or correct the transcript.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await speech.toggleRecording() } } label: {
                    Label(speech.isRecording ? "Stop" : "Record", systemImage: speech.isRecording ? "stop.fill" : "mic.fill").font(.headline).padding(.horizontal, 8).frame(minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(speech.isRecording ? .red : .orange)
            }
            TextEditor(text: $speech.transcript).frame(minHeight: 130).padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(speech.isRecording ? Color.orange : Color.secondary.opacity(0.2), lineWidth: speech.isRecording ? 2 : 1))
            if let error = speech.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red) }
            if cleanTranscript.isEmpty { Text("Example: “I’ve felted and battened the front side, and I need 12 packs of batten in the morning.”").font(.caption).foregroundStyle(.secondary) }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }

    private func reviewCard(_ analysis: JobNoteAnalysis, lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review before saving", systemImage: "checkmark.shield").font(.headline)
            if analysis.analysisMode == "note_only" {
                Label("AI suggestions are temporarily unavailable. Your spoken update is still ready to save as a progress note.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }
            Toggle(isOn: $includeProgressNote) {
                VStack(alignment: .leading, spacing: 3) { Text("Add progress note").fontWeight(.semibold); Text("Saved in this job’s Notes timeline").font(.caption).foregroundStyle(.secondary) }
            }
            if includeProgressNote { TextEditor(text: $progressNote).frame(minHeight: 86).padding(8).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)) }
            Divider(); Text("Tasks for \(lead.name)").font(.headline)
            if analysis.suggestions.isEmpty {
                Text("No task changes were confidently identified. You can save the progress note only.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(analysis.suggestions) { suggestion in
                    let selected = selectedSuggestionIDs.contains(suggestion.id)
                    Button { toggle(suggestion.id) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selected ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(suggestion.action == .complete ? "Mark task completed" : "Add next-action task").font(.caption.bold()).foregroundStyle(suggestion.action == .complete ? .green : .orange)
                                Text(suggestion.title).fontWeight(.semibold).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                if let dueDate = suggestion.dueDate { Label(dueDate, systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
                                Text(suggestion.reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }; Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if suggestion.id != analysis.suggestions.last?.id { Divider().padding(.leading, 34) }
                }
                Text("Selected tasks will be saved inside \(lead.name)’s job—not as general tasks.").font(.caption).foregroundStyle(.secondary)
            }
            if let materials = analysis.materials, !materials.isEmpty {
                Divider(); Text("Proposed materials").font(.headline)
                ForEach(materials) { material in
                    let selected = selectedMaterialIDs.contains(material.id)
                    Button { toggleMaterialSuggestion(material.id) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selected ? .orange : .secondary)
                            Image(systemName: "shippingbox").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(material.name).fontWeight(.semibold).foregroundStyle(.primary)
                                Text("\(material.quantity.formatted()) \(material.unit)").font(.callout.bold()).foregroundStyle(.orange)
                                Text(material.reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }; Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text("Selected items will be added to this job’s Materials list.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Existing job: \(lead.tasks.filter { !$0.completed }.count) open tasks · \(lead.tasks.filter(\.completed).count) completed").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.25)))
    }

    private func analyse() {
        speech.stopRecording(); let transcript = cleanTranscript; guard !transcript.isEmpty else { return }
        Task {
            isAnalysing = true; defer { isAnalysing = false }
            if let result = await appState.analyseJobNote(leadID: leadID, note: transcript) {
                analysis = result; progressNote = result.summary; selectedSuggestionIDs = Set(result.suggestions.map(\.id)); selectedMaterialIDs = Set((result.materials ?? []).map(\.id))
            }
        }
    }

    private func apply(_ analysis: JobNoteAnalysis) {
        let selected = analysis.suggestions.filter { selectedSuggestionIDs.contains($0.id) }
        let selectedMaterials = (analysis.materials ?? []).filter { selectedMaterialIDs.contains($0.id) }
        Task {
            isSaving = true; defer { isSaving = false }
            if await appState.applyJobUpdate(leadID: leadID, progressNote: includeProgressNote ? progressNote : nil, suggestions: selected, materials: selectedMaterials) { dismiss() }
        }
    }

    private func toggle(_ id: String) { if selectedSuggestionIDs.contains(id) { selectedSuggestionIDs.remove(id) } else { selectedSuggestionIDs.insert(id) } }
    private func toggleMaterialSuggestion(_ id: String) { if selectedMaterialIDs.contains(id) { selectedMaterialIDs.remove(id) } else { selectedMaterialIDs.insert(id) } }
}

private struct AddLeadTaskSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var title = ""
    @State private var hasDueDate = true
    @State private var dueDate = Date()
    @State private var priority = "medium"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Next action", text: $title)
                TextField("Details, access or expected result", text: $notes, axis: .vertical).lineLimit(2...5)
                Picker("Priority", selection: $priority) { Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high") }
                Toggle("Set due date", isOn: $hasDueDate)
                if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
            }
            .navigationTitle("Add task for \(lead.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let due = hasDueDate ? SupabaseService.localDay(for: dueDate) : nil
                        Task { if await appState.addLeadTask(leadID: lead.id, title: title, dueDate: due, priority: priority, notes: notes.isEmpty ? nil : notes) { dismiss() } }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 390)
    }
}

private struct AddPhotoSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var caption = ""
    @State private var category = "Before"
    @State private var selected: PickedAttachment?
    @State private var choosing = false
    @State private var uploading = false
    var body: some View {
        NavigationStack {
            Form {
                Button { choosing = true } label: { Label(selected?.filename ?? "Choose photo…", systemImage: "photo.badge.plus") }
                TextField("Caption", text: $caption)
                Picker("Category", selection: $category) { ForEach(["Before", "During", "After"], id: \.self) { Text($0) } }
                if uploading { ProgressView("Uploading securely…") }
            }
            .navigationTitle("Upload Photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(uploading) }
                ToolbarItem(placement: .confirmationAction) { Button("Upload") { upload() }.disabled(selected == nil || uploading) }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in selected = loadAttachment(result) }
        }.frame(minWidth: 420, minHeight: 300)
    }
    private func upload() { guard let selected else { return }; uploading = true; Task { if await appState.uploadLeadPhoto(leadID: lead.id, data: selected.data, filename: selected.filename, contentType: selected.contentType, category: category, caption: caption.isEmpty ? nil : caption) { dismiss() }; uploading = false } }
}

private struct AddFileSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var selected: PickedAttachment?
    @State private var choosing = false
    @State private var uploading = false
    var body: some View {
        NavigationStack {
            Form {
                Button { choosing = true } label: { Label(selected?.filename ?? "Choose document or image…", systemImage: "doc.badge.plus") }
                if let selected { LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(selected.data.count), countStyle: .file)) }
                if uploading { ProgressView("Uploading securely…") }
            }
            .navigationTitle("Upload File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(uploading) }
                ToolbarItem(placement: .confirmationAction) { Button("Upload") { upload() }.disabled(selected == nil || uploading) }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.item]) { result in selected = loadAttachment(result) }
        }.frame(minWidth: 420, minHeight: 260)
    }
    private func upload() { guard let selected else { return }; uploading = true; Task { if await appState.uploadLeadFile(leadID: lead.id, data: selected.data, filename: selected.filename, contentType: selected.contentType) { dismiss() }; uploading = false } }
}

private struct PickedAttachment {
    let data: Data
    let filename: String
    let contentType: String
}

private func loadAttachment(_ result: Result<URL, Error>) -> PickedAttachment? {
    guard case let .success(url) = result else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url), data.count <= 25 * 1_024 * 1_024 else { return nil }
    let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    return PickedAttachment(data: data, filename: url.lastPathComponent, contentType: contentType)
}

private struct SecureAttachmentLink: View {
    let locator: String
    let label: String
    let icon: String
    @State private var destination: URL?
    @State private var failed = false
    var body: some View {
        Group {
            if let destination { Link(destination: destination) { Label(label, systemImage: icon) } }
            else if failed { Label(label, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
            else { HStack { ProgressView().controlSize(.small); Text(label) } }
        }
        .task(id: locator) { do { destination = try await SupabaseService.shared.signedAttachmentURL(for: locator) } catch { failed = true } }
    }
}
private struct AddMaterialSheet:View{@Environment(AppState.self)private var appState;@Environment(\.dismiss)private var dismiss;let lead:Lead;@State private var name="";@State private var quantity=1.0;@State private var unit="item";@State private var cost=0.0;@State private var supplier="";@State private var isSaving=false;var body:some View{NavigationStack{Form{TextField("Material",text:$name);TextField("Quantity",value:$quantity,format:.number);TextField("Unit",text:$unit);TextField("Cost",value:$cost,format:.number);TextField("Supplier",text:$supplier)}.disabled(isSaving).navigationTitle("Add Material").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.disabled(isSaving)};ToolbarItem(placement:.confirmationAction){Button{var changed=lead;changed.materials.append(CRMMaterial(id:UUID().uuidString,name:name,quantity:quantity,unit:unit,cost:cost,supplier:supplier.isEmpty ? nil:supplier,ordered:false,delivered:false));Task{isSaving=true;defer{isSaving=false};if await appState.saveLead(changed){dismiss()}}}label:{if isSaving{ProgressView()}else{Text("Save")}}.disabled(name.isEmpty || isSaving)}}}.frame(minWidth:420,minHeight:380)}}

private struct EditLeadView: View {
    @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss
    @State var lead: Lead
    @State private var depositPlan: DepositPlan
    @State private var addressSearch = AddressSearchService()
    @State private var selectingAddress = false
    @State private var selectedAddress = ""
    @State private var isSaving = false
    private var validDates:Bool{[lead.surveyDate,lead.startDate,lead.endDate].allSatisfy{$0 == nil || $0?.isEmpty == true || SupabaseService.date(from:$0!) != nil}}
    private var validEmail:Bool{lead.email.isEmpty || (lead.email.contains("@") && lead.email.contains("."))}
    private var validDeposit:Bool{lead.deposit >= 0 && lead.deposit <= lead.value}
    init(lead: Lead) {
        _lead = State(initialValue: lead)
        _depositPlan = State(initialValue: DepositPlan.matching(total: lead.value, deposit: lead.deposit))
    }
    var body: some View { NavigationStack { Form { Section("Customer") { TextField("Name",text:$lead.name); TextField("Phone",text:$lead.phone); TextField("Email",text:$lead.email); addressLookup }; Section("Job") { TextField("Job type",text:$lead.jobType); Picker("Stage",selection:$lead.stage){ForEach(LeadStage.allCases){Text($0.rawValue).tag($0)}}; TextField("Value",value:$lead.value,format:.number).onChange(of:lead.value){_,total in if let amount=depositPlan.amount(for:total){lead.deposit=amount}}; Picker("Deposit calculation",selection:$depositPlan){ForEach(DepositPlan.allCases){Text($0.rawValue).tag($0)}}.onChange(of:depositPlan){_,plan in if let amount=plan.amount(for:lead.value){lead.deposit=amount}}; if depositPlan == .custom { TextField("Deposit",value:$lead.deposit,format:.number) } else { LabeledContent("Deposit to collect",value:lead.deposit.formatted(.currency(code:"GBP"))) }; if !validDeposit { Text("Deposit cannot be more than the job total.").font(.caption).foregroundStyle(.red) }; Toggle("Deposit paid",isOn:$lead.depositPaid); TextField("Source",text:$lead.source); assigneePicker }; Section { OptionalDateField(label:"Survey date",icon:"calendar.badge.clock",value:$lead.surveyDate); if lead.surveyDate != nil { TextField("Survey arrival time",text:Binding($lead.surveyTime,default:""),prompt:Text("e.g. 09:30")) }; OptionalDateField(label:"Job start",icon:"hammer",value:$lead.startDate); OptionalDateField(label:"Expected finish",icon:"flag.checkered",value:$lead.endDate);if !validDates{Text("One of the saved dates is invalid. Please select it again.").foregroundStyle(.red)}} header: { Text("Schedule") } footer: { Text("Use the calendar buttons to schedule the survey and job. Dates can be cleared at any time.") } }.disabled(isSaving).navigationTitle("Edit Lead").toolbar { ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.disabled(isSaving)}; ToolbarItem(placement:.confirmationAction){Button{Task{isSaving=true;defer{isSaving=false};if await appState.saveLead(lead){dismiss()}}}label:{if isSaving{ProgressView()}else{Text("Save")}}.disabled(lead.name.trimmingCharacters(in:.whitespaces).isEmpty || !validDates || !validEmail || !validDeposit || isSaving)} } }
        #if os(macOS)
        .frame(minWidth:460,minHeight:600)
        #endif
    }

    private var assigneePicker: some View {
        Group {
            if appState.isAdmin {
                Picker("Assigned to", selection: $lead.assignedTo) {
                    Text("Unassigned").tag("")
                    ForEach(appState.users) { user in Text(user.name).tag(user.name) }
                    if !lead.assignedTo.isEmpty && !appState.users.contains(where: { $0.name.caseInsensitiveCompare(lead.assignedTo) == .orderedSame }) {
                        Text("Legacy: \(lead.assignedTo)").tag(lead.assignedTo)
                    }
                }
            } else {
                LabeledContent("Assigned to", value: lead.assignedTo.isEmpty ? "Unassigned" : lead.assignedTo)
            }
        }
    }

    private var addressLookup: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                TextField("Start typing an address…", text: $lead.address)
                if selectingAddress { ProgressView().controlSize(.small) }
            }
            .onChange(of: lead.address) { _, value in
                if value == selectedAddress { addressSearch.clear() }
                else if !selectingAddress { addressSearch.search(value) }
            }
            if !addressSearch.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(addressSearch.suggestions) { suggestion in
                        Button { choose(suggestion) } label: {
                            HStack { Image(systemName:"mappin.circle.fill").foregroundStyle(.orange); VStack(alignment:.leading){Text(suggestion.title);if !suggestion.subtitle.isEmpty{Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)}};Spacer() }
                                .padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if suggestion.id != addressSearch.suggestions.last?.id { Divider() }
                    }
                }.padding(.horizontal,8).background(.background,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(.quaternary))
            }
            if let error=addressSearch.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func choose(_ suggestion: AddressSuggestion) {
        selectingAddress = true; addressSearch.clear()
        Task {
            let resolved = await addressSearch.resolve(suggestion)
            let value = [resolved.street,resolved.town,resolved.postcode].filter{!$0.isEmpty}.joined(separator:", ")
            selectedAddress = value; lead.address = value; addressSearch.clear(); selectingAddress = false
        }
    }
}

private struct ScheduleSurveySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var surveyDate: Date
    @State private var surveyTime: Date
    @State private var saving = false

    init(lead: Lead) {
        self.lead = lead
        _surveyDate = State(initialValue: lead.surveyDate.flatMap(SupabaseService.date(from:)) ?? Calendar.current.startOfDay(for:.now))
        let parts = (lead.surveyTime ?? "09:00").split(separator:":").compactMap{Int($0)}
        var components = Calendar.current.dateComponents([.year,.month,.day], from:.now)
        components.hour = parts.first ?? 9; components.minute = parts.count > 1 ? parts[1] : 0
        _surveyTime = State(initialValue: Calendar.current.date(from:components) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") { LabeledContent("Name",value:lead.name);if !lead.address.isEmpty{LabeledContent("Address",value:lead.address)};LabeledContent("Job",value:lead.jobType) }
                Section("Survey appointment") {
                    DatePicker("Survey date",selection:$surveyDate,displayedComponents:.date)
                    DatePicker("Arrival time",selection:$surveyTime,displayedComponents:.hourAndMinute)
                }
                Section { Label("The survey will appear in the calendar and the lead will move to Survey Booked.",systemImage:"calendar.badge.checkmark").font(.callout).foregroundStyle(.secondary) }
            }
            .navigationTitle(lead.surveyDate == nil ? "Schedule survey":"Edit survey")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Save"){save()}.disabled(saving)}
            }
        }
        #if os(macOS)
        .frame(minWidth:480,minHeight:430)
        #endif
    }

    private func save() {
        saving=true
        Task {
            var changed=lead
            changed.surveyDate=PayrollMath.key(surveyDate)
            changed.surveyTime=String(format:"%02d:%02d",Calendar.current.component(.hour,from:surveyTime),Calendar.current.component(.minute,from:surveyTime))
            if lead.stage == .newLead { changed.stage = .surveyBooked }
            await appState.saveLead(changed)
            saving=false
            if appState.leads.first(where:{$0.id==lead.id})?.surveyDate == changed.surveyDate { dismiss() }
        }
    }
}

private struct OptionalDateField: View {
    let label: String
    let icon: String
    @Binding var value: String?
    private var date: Binding<Date> {
        Binding(get: { value.flatMap(SupabaseService.date(from:)) ?? Calendar.current.startOfDay(for: .now) }, set: { value = PayrollMath.key($0) })
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(value == nil ? Color.secondary : Color.orange).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if value == nil { Text("Not scheduled").foregroundStyle(.secondary) }
                else { Text(date.wrappedValue.formatted(date: .long, time: .omitted)).fontWeight(.medium) }
            }
            Spacer()
            if value == nil {
                Button("Choose date") { value = PayrollMath.key(Date.now) }.buttonStyle(.bordered)
            } else {
                DatePicker(label, selection: date, displayedComponents: .date).labelsHidden().datePickerStyle(.compact)
                Button { value = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear \(label.lowercased())")
            }
        }.padding(.vertical, 4)
    }
}
private extension Binding where Value == String { init(_ source:Binding<String?>,default fallback:String){self.init(get:{source.wrappedValue ?? fallback},set:{source.wrappedValue=$0.isEmpty ? nil:$0})} }
