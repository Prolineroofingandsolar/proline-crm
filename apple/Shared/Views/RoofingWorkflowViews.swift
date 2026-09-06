import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct LeadSurveyView: View {
    @Environment(AppState.self) private var appState
    let lead: Lead
    @State private var editing: RoofSurvey?
    private var rows: [RoofSurvey] { appState.surveys.filter { $0.leadID == lead.id }.sorted { $0.updatedAt > $1.updatedAt } }

    var body: some View {
        workflowContainer {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text("Roof surveys").font(.title2.bold()); Text("Capture measurements, access, hazards and recommendations.").foregroundStyle(.secondary) }
                    Spacer()
                    Button { editing = newSurvey } label: { Label("New survey", systemImage: "ruler") }.buttonStyle(.borderedProminent).tint(.orange)
                }
                if rows.isEmpty {
                    ContentUnavailableView("No survey recorded", systemImage: "ruler", description: Text("Create a structured site survey for this customer."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(rows) { survey in
                        Button { editing = survey } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Label(survey.status.displayName, systemImage: survey.status == .completed ? "checkmark.seal.fill" : "ruler").foregroundStyle(survey.status == .completed ? .green : .orange); Spacer(); Text(survey.updatedAt.prefix(10)).foregroundStyle(.secondary) }
                                #if os(iOS)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                    metric("Roof", survey.roofType.isEmpty ? "Not set" : survey.roofType)
                                    metric("Covering", survey.covering.isEmpty ? "Not set" : survey.covering)
                                    metric("Measured area", survey.measurements.reduce(0) { $0 + $1.area }.formatted(.number.precision(.fractionLength(1))) + " m²")
                                    metric("Hazards", "\(survey.hazards.count)")
                                }
                                #else
                                HStack(spacing: 24) {
                                    metric("Roof", survey.roofType.isEmpty ? "Not set" : survey.roofType)
                                    metric("Covering", survey.covering.isEmpty ? "Not set" : survey.covering)
                                    metric("Measured area", survey.measurements.reduce(0) { $0 + $1.area }.formatted(.number.precision(.fractionLength(1))) + " m²")
                                    metric("Hazards", "\(survey.hazards.count)")
                                }
                                #endif
                                if !survey.findings.isEmpty { Text(survey.findings).lineLimit(2).foregroundStyle(.secondary) }
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    }
                }
            }
            #if os(macOS)
            .padding(30)
            #else
            .padding(16)
            #endif
        }
        .sheet(item: $editing) { SurveyEditor(lead: lead, survey: $0) }
    }

    private var newSurvey: RoofSurvey { RoofSurvey(id: UUID().uuidString, leadID: lead.id, status: .planned, surveyorID: appState.currentUser?.id, scheduledAt: lead.surveyDate, completedAt: nil, roofType: "Pitched", covering: "Tiles", storeys: 2, pitchDegrees: nil, accessNotes: "", scaffoldRequired: false, asbestosSuspected: false, hazards: [], measurements: [], findings: "", recommendations: "", createdAt: SupabaseService.now, updatedAt: SupabaseService.now) }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).fontWeight(.semibold) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct LeadQuotesView: View {
    @Environment(AppState.self) private var appState
    let lead: Lead
    @State private var editing: CRMQuote?
    private var rows: [CRMQuote] { appState.quotes.filter { $0.leadID == lead.id }.sorted { $0.updatedAt > $1.updatedAt } }

    var body: some View {
        workflowContainer {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text("Quotes & estimates").font(.title2.bold()); Text("Price labour and materials, calculate VAT and track acceptance.").foregroundStyle(.secondary) }
                    Spacer()
                    Button { editing = newQuote } label: { Label("New quote", systemImage: "doc.badge.plus") }.buttonStyle(.borderedProminent).tint(.orange)
                }
                if rows.isEmpty {
                    ContentUnavailableView("No quotes yet", systemImage: "doc.text", description: Text("Create an itemised estimate from this lead or survey."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(rows) { quote in
                        Button { editing = quote } label: {
                            HStack(spacing: 18) {
                                Image(systemName: "doc.text.fill").font(.title).foregroundStyle(quoteTint(quote.status)).frame(width: 46, height: 46).background(quoteTint(quote.status).opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 4) { Text(quote.quoteNumber).font(.headline); Text("\(quote.lineItems.count) line items · Valid until \(quote.validUntil ?? "not set")").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(quote.status.displayName).font(.caption.bold()).foregroundStyle(quoteTint(quote.status)).padding(.horizontal, 8).padding(.vertical, 4).background(quoteTint(quote.status).opacity(0.1), in: Capsule())
                                Text(quote.total, format: .currency(code: "GBP")).font(.title3.bold()).frame(width: 120, alignment: .trailing)
                            }.padding(16).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    }
                }
            }.padding(30)
        }
        .sheet(item: $editing) { QuoteEditor(lead: lead, quote: $0) }
    }

    private var newQuote: CRMQuote {
        let quoteID = UUID().uuidString
        let expiry = Calendar.current.date(byAdding: .day, value: 30, to: .now).map { SupabaseService.localDay(for: $0) }
        return CRMQuote(id: quoteID, leadID: lead.id, quoteNumber: QuoteReference.make(date: .now, nonce: quoteID), status: .draft, lineItems: [], vatRate: 20, discount: 0, validUntil: expiry, terms: "Payment terms: deposit on acceptance, balance on completion.", customerMessage: "Thank you for the opportunity to quote for your roofing work.", sentAt: nil, acceptedAt: nil, createdAt: SupabaseService.now, updatedAt: SupabaseService.now)
    }
}

private struct SurveyEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var draft: RoofSurvey
    @State private var hazard = ""
    @State private var saving = false
    init(lead: Lead, survey: RoofSurvey) { self.lead = lead; _draft = State(initialValue: survey) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Visit") { Picker("Status", selection: $draft.status) { ForEach(SurveyStatus.allCases) { Text($0.displayName).tag($0) } }; TextField("Scheduled date", text: Binding(optional: $draft.scheduledAt, default: "")) }
                Section("Roof") { TextField("Roof type", text: $draft.roofType); TextField("Covering", text: $draft.covering); Stepper("\(draft.storeys) storeys", value: $draft.storeys, in: 1...10); TextField("Pitch (degrees)", value: $draft.pitchDegrees, format: .number); Toggle("Scaffold required", isOn: $draft.scaffoldRequired); Toggle("Possible asbestos", isOn: $draft.asbestosSuspected) }
                Section("Measurements") {
                    ForEach($draft.measurements) { $item in
                        #if os(iOS)
                        VStack(alignment: .leading, spacing: 9) {
                            TextField("Area name", text: $item.label)
                            HStack {
                                TextField("Length", value: $item.length, format: .number).keyboardType(.decimalPad)
                                Text("×").foregroundStyle(.secondary)
                                TextField("Width", value: $item.width, format: .number).keyboardType(.decimalPad)
                                Text("\(item.area.formatted(.number.precision(.fractionLength(1)))) m²").font(.caption.bold()).foregroundStyle(.orange)
                            }
                        }.padding(.vertical, 4)
                        #else
                        HStack { TextField("Area", text: $item.label); TextField("Length", value: $item.length, format: .number).frame(width: 75); Text("×"); TextField("Width", value: $item.width, format: .number).frame(width: 75); Text("= \(item.area.formatted(.number.precision(.fractionLength(1)))) m²") }
                        #endif
                    }
                    .onDelete { draft.measurements.remove(atOffsets: $0) }
                    Button { draft.measurements.append(SurveyMeasurement(id: UUID().uuidString, label: "Roof area", length: 0, width: 0, unit: "m")) } label: { Label("Add measurement", systemImage: "plus") }
                }
                Section("Safety & access") { TextField("Access notes", text: $draft.accessNotes, axis: .vertical); HStack { TextField("Add hazard", text: $hazard); Button("Add") { let value = hazard.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { draft.hazards.append(value); hazard = "" } } }; ForEach(draft.hazards, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }.onDelete { draft.hazards.remove(atOffsets: $0) } }
                Section("Assessment") { TextField("Findings", text: $draft.findings, axis: .vertical).lineLimit(3...8); TextField("Recommendations", text: $draft.recommendations, axis: .vertical).lineLimit(3...8) }
            }
            .navigationTitle("Survey · \(lead.name)")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving) } }
        }
        #if os(macOS)
        .frame(minWidth: 650, minHeight: 720)
        #endif
    }
    private func save() { saving = true; if draft.status == .completed && draft.completedAt == nil { draft.completedAt = SupabaseService.now }; Task { if await appState.saveSurvey(draft) { dismiss() }; saving = false } }
}

private struct QuoteEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var draft: CRMQuote
    @State private var saving = false
    @State private var exporting = false
    @State private var aiBrief = ""
    @State private var generating = false
    @State private var generationError: String?
    @State private var quotePhotos: [AssistantAttachment] = []
    @State private var choosingPhotos = false
    @State private var photoError: String?
    @State private var suggestedPriceSummary: String?
    @State private var pricingBasis: String?
    @State private var step = 0
    #if os(iOS)
    @State private var choosingPhotoLibrary = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var shareFile: QuoteShareFile?
    #endif
    init(lead: Lead, quote: CRMQuote) { self.lead = lead; _draft = State(initialValue: quote) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) { Text("Prepare quotation").font(.title.bold()); Text("\(lead.name) · \(lead.address)").foregroundStyle(.secondary).lineLimit(2) }
                        Spacer(); Text(draft.total, format: .currency(code: "GBP")).font(.title2.bold()).foregroundStyle(.orange)
                    }
                    quoteJourney
                    quoteStep
                }.padding(20).frame(maxWidth: 920)
            }.background(Color.secondary.opacity(0.035))
            .navigationTitle("Quote · \(lead.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if step > 0 { ToolbarItem { Button("Back") { withAnimation { step -= 1 } } } }
                ToolbarItem(placement: .confirmationAction) {
                    if step < 4 { Button("Continue") { withAnimation { step += 1 } }.buttonStyle(.borderedProminent).tint(.orange) }
                    else { Button(saving ? "Saving…" : "Save quote") { save() }.disabled(saving || draft.quoteNumber.isEmpty || draft.lineItems.isEmpty) }
                }
            }
            .fileExporter(isPresented: $exporting, document: QuotePDFDocument(data: QuotePDFRenderer.data(quote: draft, lead: lead)), contentType: .pdf, defaultFilename: "\(draft.quoteNumber)-\(lead.name.replacingOccurrences(of: " ", with: "-"))") { result in
                if case .failure = result { appState.errorMessage = "The quote PDF could not be exported." }
            }
            .fileImporter(isPresented: $choosingPhotos, allowedContentTypes: [.image], allowsMultipleSelection: true, onCompletion: importPhotos)
            #if os(iOS)
            .photosPicker(isPresented: $choosingPhotoLibrary, selection: $selectedPhotoItems, maxSelectionCount: max(1, 4 - quotePhotos.count), matching: .images)
            .onChange(of: selectedPhotoItems) { _, items in Task { await importPhotoLibraryItems(items) } }
            .sheet(item: $shareFile) { QuoteShareSheet(url: $0.url) }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 760)
        #endif
    }
    @ViewBuilder private var quoteStep: some View {
        switch step {
        case 0: jobStep
        case 1: scopeStep
        case 2: priceStep
        case 3: card("Guarantee and terms", icon: "checkmark.shield") { TextField("Guarantee and payment terms", text: $draft.terms, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder) }
        default: reviewCard
        }
    }
    private var scopeStep: some View {
        Group {
            card("Customer wording", icon: "text.quote") { TextField("Introduction", text: $draft.customerMessage, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder) }
            card("Scope of works", icon: "hammer") {
                let indexes = draft.lineItems.indices.filter { draft.lineItems[$0].category.caseInsensitiveCompare("Scope") == .orderedSame }
                if indexes.isEmpty { Text("Generate a draft or add a scope section.").foregroundStyle(.secondary) }
                ForEach(indexes, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 7) {
                        TextField("Bold scope heading", text: scopeHeadingBinding(index)).font(.headline).textFieldStyle(.roundedBorder)
                        TextField("Normal description underneath", text: scopeDetailsBinding(index), axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { draft.lineItems.remove(at: index) } label: { Label("Remove section", systemImage: "trash") }.buttonStyle(.borderless)
                    }.padding(.vertical, 5)
                }
                Button { draft.lineItems.insert(QuoteLineItem(id: UUID().uuidString, description: "New scope section\nDescribe the work included.", category: "Scope", quantity: 1, unit: "scope", unitPrice: 0), at: 0) } label: { Label("Add scope section", systemImage: "plus") }
            }
        }
    }
    private var priceStep: some View {
        card("Price", icon: "sterlingsign.circle") {
            let indexes = draft.lineItems.indices.filter { draft.lineItems[$0].category.caseInsensitiveCompare("Scope") != .orderedSame }
            ForEach(indexes, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Price description", text: $draft.lineItems[index].description).textFieldStyle(.roundedBorder)
                    HStack { TextField("Quantity", value: $draft.lineItems[index].quantity, format: .number); TextField("Unit", text: $draft.lineItems[index].unit); TextField("Unit price", value: $draft.lineItems[index].unitPrice, format: .number) }.textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { draft.lineItems.remove(at: index) } label: { Label("Remove price", systemImage: "trash") }.buttonStyle(.borderless)
                }.padding(.vertical, 5)
            }
            Button { draft.lineItems.append(QuoteLineItem(id: UUID().uuidString, description: "All works (materials + labour)", category: "Price", quantity: 1, unit: "job", unitPrice: 0)) } label: { Label("Add price", systemImage: "plus") }
            Divider()
            LabeledContent("Subtotal", value: draft.subtotal.formatted(.currency(code: "GBP")))
            TextField("Discount", value: $draft.discount, format: .number).textFieldStyle(.roundedBorder)
            TextField("VAT %", value: $draft.vatRate, format: .number).textFieldStyle(.roundedBorder)
            LabeledContent("Total", value: draft.total.formatted(.currency(code: "GBP"))).fontWeight(.bold)
        }
    }
    private var jobStep: some View {
        Group {
            card("Quote details", icon: "doc.text") {
                ViewThatFits {
                    HStack { TextField("Quote number", text: $draft.quoteNumber); Picker("Status", selection: $draft.status) { ForEach(QuoteStatus.allCases) { Text($0.displayName).tag($0) } }; TextField("Valid until", text: Binding(optional: $draft.validUntil, default: "")) }
                    VStack { TextField("Quote number", text: $draft.quoteNumber); Picker("Status", selection: $draft.status) { ForEach(QuoteStatus.allCases) { Text($0.displayName).tag($0) } }; TextField("Valid until", text: Binding(optional: $draft.validUntil, default: "")) }
                }.textFieldStyle(.roundedBorder)
            }
            card("Build with Gemini", icon: "sparkles") {
                Text("Describe the work and add up to four roof photos. Gemini also uses the latest notes, materials and survey. Everything remains editable before saving.").font(.callout).foregroundStyle(.secondary)
                TextField("Describe the roof, defects and proposed work…", text: $aiBrief, axis: .vertical).lineLimit(4...8).textFieldStyle(.roundedBorder)
                if !quotePhotos.isEmpty { attachedPhotoChips }
                HStack {
                    photoSourceButton
                    Spacer()
                    Button { generateWithGemini() } label: { if generating { ProgressView().controlSize(.small) } else { Label("Generate draft", systemImage: "sparkles") } }.buttonStyle(.borderedProminent).tint(.orange).disabled(generating)
                }
                if let photoError { Label(photoError, systemImage: "photo.badge.exclamationmark").foregroundStyle(.red).font(.caption) }
                if let generationError { Label(generationError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption) }
                if let suggestedPriceSummary { priceSuggestion(suggestedPriceSummary) }
                Text("Photos help identify visible work only. Check measurements, quantities and price yourself before sending.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var journeySteps: [(String, String)] { [("Job", "house"), ("Scope", "hammer"), ("Price", "sterlingsign.circle"), ("Terms", "checkmark.shield"), ("Review", "doc.text.magnifyingglass")] }
    private var quoteJourney: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(step + 1) of \(journeySteps.count) · \(journeySteps[step].0)").font(.headline)
            HStack(spacing: 6) {
                ForEach(journeySteps.indices, id: \.self) { index in
                    Button { withAnimation { step = index } } label: {
                        VStack(spacing: 5) {
                            Image(systemName: journeySteps[index].1)
                            Text(journeySteps[index].0).font(.caption2).lineLimit(1)
                        }
                        .foregroundStyle(index == step ? .white : (index < step ? Color.orange : Color.secondary))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(index == step ? Color.orange : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.22)))
    }
    private var reviewCard: some View {
        card("Ready to send", icon: "checkmark.circle.fill") {
            Text("Check the essentials, then create the polished PDF and email it from the share sheet.").font(.callout).foregroundStyle(.secondary)
            Divider()
            LabeledContent("Customer", value: lead.name)
            LabeledContent("Property", value: lead.address.isEmpty ? "Not entered" : lead.address)
            LabeledContent("Scope sections", value: "\(draft.lineItems.filter { $0.category.caseInsensitiveCompare("Scope") == .orderedSame }.count)")
            LabeledContent("Quote total", value: draft.total.formatted(.currency(code: "GBP"))).fontWeight(.bold)
            if draft.lineItems.isEmpty { Label("Add at least one scope or price item before saving.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            #if os(iOS)
            Button { sharePDF() } label: { Label("Preview, email or share PDF", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).tint(.orange).disabled(draft.lineItems.isEmpty)
            #else
            Button { exporting = true } label: { Label("Export finished PDF", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).tint(.orange).disabled(draft.lineItems.isEmpty)
            #endif
        }
    }
    private func save() { saving = true; Task { if await appState.saveQuote(draft) { dismiss() }; saving = false } }
    private func generateWithGemini() {
        generating = true; generationError = nil
        Task {
            if let generated = await appState.generateQuoteDraft(for: lead, brief: aiBrief, photos: quotePhotos) {
                var pricedItems = draft.lineItems.filter { $0.category.caseInsensitiveCompare("Scope") != .orderedSame }
                let scope = generated.scopeItems.map {
                    QuoteLineItem(id: UUID().uuidString, description: "\($0.heading)\n\($0.details)", category: "Scope", quantity: 1, unit: "scope", unitPrice: 0)
                }
                if let recommended = generated.recommendedPrice, recommended > 0 {
                    if let index = pricedItems.firstIndex(where: { $0.category.caseInsensitiveCompare("Price") == .orderedSame }) {
                        pricedItems[index].quantity = 1; pricedItems[index].unit = "job"; pricedItems[index].unitPrice = recommended
                    } else { pricedItems.append(QuoteLineItem(id: UUID().uuidString, description: "All works (materials + labour)", category: "Price", quantity: 1, unit: "job", unitPrice: recommended)) }
                    let low = generated.priceRangeLow ?? recommended, high = generated.priceRangeHigh ?? recommended
                    suggestedPriceSummary = "Gemini estimate: \(recommended.formatted(.currency(code: "GBP"))) ex VAT · likely range \(low.formatted(.currency(code: "GBP")))–\(high.formatted(.currency(code: "GBP")))"
                    pricingBasis = generated.pricingBasis
                }
                if pricedItems.isEmpty {
                    draft.lineItems = scope + [QuoteLineItem(id: UUID().uuidString, description: "All works (materials + labour)", category: "Price", quantity: 1, unit: "job", unitPrice: max(0, lead.value))]
                } else { draft.lineItems = scope + pricedItems }
                draft.customerMessage = generated.introduction
                draft.terms = "\(generated.guarantee)\n\n\(generated.terms)"
            } else { generationError = appState.assistantErrorMessage ?? "The quote draft could not be generated." }
            generating = false
        }
    }
    private func importPhotos(_ result: Result<[URL], Error>) {
        photoError = nil
        guard case let .success(urls) = result else { photoError = "The selected photos could not be opened."; return }
        for url in urls.prefix(max(0, 4 - quotePhotos.count)) {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count <= 8 * 1_024 * 1_024 else { photoError = "Each photo must be smaller than 8 MB."; continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
            guard mime.hasPrefix("image/") else { photoError = "Choose image files only."; continue }
            quotePhotos.append(AssistantAttachment(filename: url.lastPathComponent, mimeType: mime, data: data))
        }
        if quotePhotos.reduce(0, { $0 + $1.data.count }) > 16 * 1_024 * 1_024 { quotePhotos.removeLast(); photoError = "Keep the selected photos under 16 MB in total." }
    }
    private func scopeHeadingBinding(_ index: Int) -> Binding<String> {
        Binding(get: { splitScope(draft.lineItems[index].description).heading }, set: { draft.lineItems[index].description = "\($0)\n\(splitScope(draft.lineItems[index].description).details)" })
    }
    private func scopeDetailsBinding(_ index: Int) -> Binding<String> {
        Binding(get: { splitScope(draft.lineItems[index].description).details }, set: { draft.lineItems[index].description = "\(splitScope(draft.lineItems[index].description).heading)\n\($0)" })
    }
    private func splitScope(_ value: String) -> (heading: String, details: String) {
        let parts = value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }
    @ViewBuilder private var photoSourceButton: some View {
        #if os(iOS)
        Menu {
            Button { choosingPhotoLibrary = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
            Button { choosingPhotos = true } label: { Label("Files", systemImage: "folder") }
        } label: { Label(quotePhotos.isEmpty ? "Add roof photos" : "Add another photo", systemImage: "photo.badge.plus") }
        .buttonStyle(.bordered).disabled(quotePhotos.count >= 4)
        #else
        Button { choosingPhotos = true } label: { Label(quotePhotos.isEmpty ? "Add roof photos" : "Add another photo", systemImage: "photo.badge.plus") }
            .buttonStyle(.bordered).disabled(quotePhotos.count >= 4)
        #endif
    }
    private var attachedPhotoChips: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Array(quotePhotos.enumerated()), id: \.offset) { index, photo in
                    HStack {
                        Image(systemName: "photo.fill").foregroundStyle(.orange)
                        Text(photo.filename).lineLimit(1)
                        Button { quotePhotos.remove(at: index) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                    .font(.caption).padding(9).background(Color.orange.opacity(0.08), in: Capsule())
                }
            }
        }
    }
    private func priceSuggestion(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(summary, systemImage: "sterlingsign.circle.fill").font(.headline).foregroundStyle(.orange)
            if let pricingBasis { Text(pricingBasis).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    #if os(iOS)
    private func sharePDF() {
        let data = QuotePDFRenderer.data(quote: draft, lead: lead)
        guard !data.isEmpty else { appState.errorMessage = "The quote PDF could not be created."; return }
        let base = "\(draft.quoteNumber)-\(lead.name)".components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(base.isEmpty ? "ProLine-Quote.pdf" : "\(base).pdf")
        do { try data.write(to: url, options: .atomic); shareFile = QuoteShareFile(url: url) }
        catch { appState.errorMessage = "The quote PDF could not be prepared: \(error.localizedDescription)" }
    }
    @MainActor private func importPhotoLibraryItems(_ items: [PhotosPickerItem]) async {
        photoError = nil
        for item in items.prefix(max(0, 4 - quotePhotos.count)) {
            guard let data = try? await item.loadTransferable(type: Data.self), data.count <= 8 * 1_024 * 1_024 else { photoError = "Each photo must be smaller than 8 MB."; continue }
            let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
            quotePhotos.append(AssistantAttachment(filename: "Roof photo \(quotePhotos.count + 1).\(type?.preferredFilenameExtension ?? "jpg")", mimeType: type?.preferredMIMEType ?? "image/jpeg", data: data))
        }
        selectedPhotoItems = []
        if quotePhotos.reduce(0, { $0 + $1.data.count }) > 16 * 1_024 * 1_024 { quotePhotos.removeLast(); photoError = "Keep the selected photos under 16 MB in total." }
    }
    #endif
    @ViewBuilder private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Label(title, systemImage: icon).font(.headline); content() }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.16)))
    }
}

#if os(iOS)
private struct QuoteShareFile: Identifiable { let id = UUID(); let url: URL }
private struct QuoteShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

@ViewBuilder private func workflowContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    #if os(macOS)
    content()
    #else
    ScrollView { content() }
    #endif
}

private func quoteTint(_ status: QuoteStatus) -> Color {
    switch status { case .draft: .gray; case .sent: .purple; case .accepted: .green; case .declined: .red; case .expired: .orange }
}

private extension Binding where Value == String {
    init(optional source: Binding<String?>, default fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
