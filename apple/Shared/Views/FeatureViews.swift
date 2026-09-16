import SwiftUI
#if os(iOS)
import CoreMotion
#endif

struct AccountsWorkspaceView: View {
    private enum Tab: String, CaseIterable, Identifiable { case overview = "Overview", finance = "Money", reports = "Reports", timesheets = "Timesheets", cis = "CIS", handover = "Accountant handover"; var id: String { rawValue } }
    @Environment(AppState.self) private var appState
    @State private var tab: Tab = .overview
    @State private var exporting = false
    @State private var exportDocument = CRMCSVDocument(text: "")
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text("Accounts").font(.system(size: 29, weight: .bold)); Text("Payments, payroll, CIS and accountant records in one place.").foregroundStyle(.secondary) }; Spacer(); if tab == .handover { Button { prepareHandover() } label: { Label("Export accountant CSV", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).tint(.orange) } }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            #if os(macOS)
            Picker("Accounts section", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 12)
            #else
            Picker("Accounts section", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).padding(.horizontal, 20).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading)
            #endif
            Divider()
            switch tab { case .overview: accountsOverview; case .finance: FinanceCentreView(); case .reports: ReportsView(); case .timesheets: TimesheetView(); case .cis: CISView(); case .handover: accountantHandover }
        }.navigationTitle("Accounts").fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "ProLine-Accountant-Handover-\(SupabaseService.today)") { result in if case .failure = result { appState.errorMessage = "The accountant export could not be saved." } }
    }
    private var activeJobs: [Lead] { appState.leads.filter { [.won, .scheduled, .inProgress, .completed, .waitingForPayment, .paid].contains($0.stage) } }
    private var collected: Double { activeJobs.reduce(0) { $0 + max(0, $1.value - $1.balance) } }
    private var due: Double { activeJobs.reduce(0) { $0 + max(0, $1.balance) } }
    private var payroll: Double { appState.timesheets.reduce(0) { $0 + $1.amount } }
    private var accountsOverview: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) { accountMetric("Customer money in", collected, "arrow.down.circle.fill", .green); accountMetric("Customer money due", due, "clock.badge.exclamationmark.fill", .orange); accountMetric("Labour recorded", payroll, "person.2.fill", .blue); accountMetric("Deposits waiting", activeJobs.filter { !$0.depositPaid && $0.deposit > 0 }.reduce(0) { $0 + $1.deposit }, "creditcard.fill", .red) }; VStack(alignment: .leading, spacing: 12) { Text("Simple weekly routine").font(.title3.bold()); routine("1", "Record deposits", "Open Money and mark customer deposits when they arrive."); routine("2", "Approve timesheets", "Check worker days, rates and job references before payment."); routine("3", "Check CIS", "Review deductions and export the monthly contractor return."); routine("4", "Send to accountant", "Export the handover CSV containing jobs, money, wages and payment details.") }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)) }.padding(24) } }
    private func accountMetric(_ title: String, _ value: Double, _ icon: String, _ colour: Color) -> some View { HStack { Image(systemName: icon).font(.title2).foregroundStyle(colour).frame(width: 44, height: 44).background(colour.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading) { Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)) }
    private func routine(_ number: String, _ title: String, _ detail: String) -> some View { HStack(alignment: .top, spacing: 12) { Text(number).font(.headline).foregroundStyle(.white).frame(width: 28, height: 28).background(.orange, in: Circle()); VStack(alignment: .leading, spacing: 2) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary) } } }
    private var accountantHandover: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { Label("Accountant-ready export", systemImage: "building.columns.fill").font(.title2.bold()).foregroundStyle(.orange); Text("One CSV includes customer job values, deposits, outstanding balances, timesheets and worker payments. Your accountant can filter the record_type column or import each group into their software.").foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 10) { handoverLine("Customer jobs", "\(appState.leads.count) records"); handoverLine("Timesheet entries", "\(appState.timesheets.count) records"); handoverLine("Worker payments", "\(appState.workerPayments.count) records") }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)); Button { prepareHandover() } label: { Label("Export accountant handover", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large) }.frame(maxWidth: 680, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .topLeading) } }
    private func handoverLine(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) } }
    private func prepareHandover() { var rows = ["record_type,date,reference,name,description,gross_amount,deposit,paid_or_deducted,balance,status,notes"]; rows += appState.leads.map { csvRow(["job", $0.createdAt, $0.jobRef, $0.name, $0.jobType, money($0.value), money($0.deposit), $0.depositPaid ? "yes" : "no", money($0.balance), $0.stage.rawValue, $0.address]) }; rows += appState.timesheets.map { entry in let worker = appState.users.first { $0.id == entry.userID }; let job = appState.leads.first { $0.id == entry.leadID }; return csvRow(["timesheet", entry.date, job?.jobRef ?? entry.leadID, worker?.name ?? entry.userID, entry.type, money(entry.amount), "", "", "", "recorded", ""]) }; rows += appState.workerPayments.map { payment in let worker = appState.users.first { $0.id == payment.userID }; return csvRow(["worker_payment", payment.date, payment.id, worker?.name ?? payment.userID, "Worker payment", money(payment.amount), "", "yes", "", "paid", payment.notes ?? ""]) }; exportDocument = CRMCSVDocument(text: rows.joined(separator: "\n")); exporting = true }
    private func money(_ value: Double) -> String { String(format: "%.2f", value) }
    private func csvRow(_ values: [String]) -> String { values.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") }
}

struct RoofingToolsView: View {
    private enum Tool: String, CaseIterable, Identifiable { case pitch = "Pitch finder", gauge = "Gauger"; var id: String { rawValue } }
    @State private var tool: Tool = ProcessInfo.processInfo.arguments.contains("--worker-preview-tools") ? .gauge : .pitch
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text("Roofing tools").font(.system(size: 29, weight: .bold)); Text("Fast site calculations without leaving the CRM.").foregroundStyle(.secondary) }; Spacer() }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            Picker("Tool", selection: $tool) { ForEach(Tool.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 12)
            Divider()
            ScrollView { Group { switch tool { case .pitch: RoofPitchFinder(); case .gauge: TileGaugeFinder() } }.frame(maxWidth: 720).padding(24).frame(maxWidth: .infinity, alignment: .top) }
        }.navigationTitle("Tools")
    }
}

private struct RoofPitchFinder: View {
    @State private var rise = ""
    @State private var run = ""
    @State private var showsCalculator = false
    private var riseValue: Double { Double(rise.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var runValue: Double { Double(run.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var angle: Double? { guard riseValue > 0, runValue > 0 else { return nil }; return atan(riseValue / runValue) * 180 / .pi }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ToolIntro(icon: "angle", title: "Pitch finder", detail: "Put your iPhone against the roof and read the pitch.")
            #if os(iOS)
            LiveRoofLevel()
            DisclosureGroup(isExpanded: $showsCalculator) {
                pitchCalculator.padding(.top, 14)
            } label: {
                Label("Calculate from rise and run", systemImage: "ruler")
                    .font(.headline)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            #else
            Label("Live level is available on iPhone", systemImage: "iphone.gen3").foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            pitchCalculator
            #endif
        }
    }
    private var pitchCalculator: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) { ToolNumberField(title: "Rise", placeholder: "1200", unit: "mm", value: $rise); ToolNumberField(title: "Run", placeholder: "2400", unit: "mm", value: $run) }
            if let angle {
                HStack(spacing: 16) {
                    Text("\(angle, specifier: "%.1f")°").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) { Text("Calculated pitch").fontWeight(.semibold); Text("1 : \(runValue / riseValue, specifier: "%.2f") · \(pitchAdvice(angle))").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else { Text("Enter the vertical rise and horizontal run.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func pitchAdvice(_ angle: Double) -> String { angle < 15 ? "Very low pitch" : angle < 22.5 ? "Low pitch" : "Pitched roof" }
}

private struct TileGaugeFinder: View {
    private enum Step: Int, CaseIterable { case tile = 1, roof, result }
    private enum RidgeType: String, CaseIterable, Identifiable {
        case mortar = "Mortar ridge"
        case dry = "Dry ridge"
        var id: String { rawValue }
    }
    private static let tiles = [
        TileSpecification(make:"Somerset / Bridgwater",name:"Somerset No. 13 (reclaimed)",pitch:"30° historic guidance",minGauge:295,maxGauge:325,headlap:"Set to suit the reclaimed batch",tileLength:394,minPitchDegrees:30,gaugeBasis:"Somerset trade working range—measure and trial-lay the reclaimed batch"),
        TileSpecification(make:"Somerset / Bridgwater",name:"Sandtoft Bridgwater Double Roman",pitch:"30°",minGauge:345,maxGauge:345,headlap:"75 mm fixed",tileLength:420,minPitchDegrees:30,fasciaProjection:"45–55 mm"),
        TileSpecification(make:"Somerset / Bridgwater",name:"BCC / Bridgwater Double Roman (legacy)",pitch:"30°—verify batch",minGauge:295,maxGauge:325,headlap:"Set to suit the reclaimed batch",tileLength:394,minPitchDegrees:30,gaugeBasis:"Somerset trade working range—measure and trial-lay the reclaimed batch"),
        TileSpecification(make:"Marley", name:"Modern", pitch:"17.5° smooth at 100 mm headlap", minGauge:320,maxGauge:345,headlap:"75–100 mm",tileLength:420,minPitchDegrees:17.5), TileSpecification(make:"Marley",name:"Duo Modern",pitch:"17.5° smooth",minGauge:320,maxGauge:345,headlap:"75–100 mm",minPitchDegrees:17.5),
        TileSpecification(make:"Marley",name:"Double Roman",pitch:"22.5° smooth",minGauge:320,maxGauge:345,headlap:"75–100 mm"), TileSpecification(make:"Marley",name:"Ludlow Major",pitch:"22.5° smooth",minGauge:320,maxGauge:345,headlap:"75–100 mm"),
        TileSpecification(make:"Marley",name:"Ludlow Plus",pitch:"22.5°",minGauge:287,maxGauge:312,headlap:"75–100 mm"), TileSpecification(make:"Marley",name:"Mendip",pitch:"15° smooth",minGauge:320,maxGauge:345,headlap:"75–100 mm"),
        TileSpecification(make:"Marley",name:"Mendip 12.5",pitch:"12.5°",minGauge:320,maxGauge:345,headlap:"75–100 mm"), TileSpecification(make:"Marley",name:"Edgemere",pitch:"17.5°",minGauge:320,maxGauge:345,headlap:"75–100 mm"),
        TileSpecification(make:"Marley",name:"Duo Edgemere",pitch:"17.5°",minGauge:320,maxGauge:345,headlap:"75–100 mm"), TileSpecification(make:"Marley",name:"Wessex",pitch:"15°",minGauge:320,maxGauge:345,headlap:"75–100 mm"),
        TileSpecification(make:"Marley",name:"Anglia",pitch:"25° smooth",minGauge:320,maxGauge:345,headlap:"75–100 mm"), TileSpecification(make:"Marley",name:"Concrete Plain Tile",pitch:"35°",minGauge:88,maxGauge:100,headlap:"65–88 mm"),
        TileSpecification(make:"BMI Redland",name:"Richmond 10 Slate",pitch:"17.5° at 100 mm",minGauge:293,maxGauge:343,headlap:"75–125 mm"), TileSpecification(make:"BMI Redland",name:"MockBond Richmond 10",pitch:"17.5° at 100 mm",minGauge:293,maxGauge:343,headlap:"75–125 mm"),
        TileSpecification(make:"BMI Redland",name:"Mini Stonewold",pitch:"17.5° at 100 mm",minGauge:293,maxGauge:343,headlap:"75–125 mm"), TileSpecification(make:"BMI Redland",name:"MockBond Mini Stonewold",pitch:"17.5° at 100 mm",minGauge:293,maxGauge:343,headlap:"75–125 mm"),
        TileSpecification(make:"BMI Redland",name:"50 Double Roman",pitch:"17.5° at 100 mm",minGauge:293,maxGauge:343,headlap:"75–125 mm"), TileSpecification(make:"BMI Redland",name:"Grovebury",pitch:"17.5° at 100 mm",minGauge:293,maxGauge:343,headlap:"75–125 mm"),
        TileSpecification(make:"BMI Redland",name:"Regent",pitch:"12.5° system dependent",minGauge:293,maxGauge:343,headlap:"75–125 mm"), TileSpecification(make:"BMI Redland",name:"Renown",pitch:"17.5° at 100 mm",minGauge:293,maxGauge:343,headlap:"75–125 mm"),
        TileSpecification(make:"Sandtoft",name:"20/20 Clay",pitch:"15° at 100 mm",minGauge:210,maxGauge:255,headlap:"75–100 mm",tileLength:330,minPitchDegrees:15,fasciaProjection:"45–55 mm"), TileSpecification(make:"Sandtoft",name:"Calderdale Edge",pitch:"17.5° at 100 mm",minGauge:320,maxGauge:345,headlap:"75–100 mm",minPitchDegrees:17.5,fasciaProjection:"45–55 mm"),
        TileSpecification(make:"Sandtoft",name:"Double Roman",pitch:"22.5°",minGauge:320,maxGauge:345,headlap:"75–100 mm"), TileSpecification(make:"Sandtoft",name:"Danum TLE",pitch:"17.5° at 100 mm",minGauge:300,maxGauge:345,headlap:"75–100 mm"),
        TileSpecification(make:"Sandtoft",name:"Standard Pattern",pitch:"17.5° at 100 mm",minGauge:260,maxGauge:305,headlap:"75–100 mm"), TileSpecification(make:"Sandtoft",name:"Concrete Plain Tile",pitch:"35°",minGauge:88,maxGauge:100,headlap:"65–88 mm")
    ]
    @State private var tileID = "Marley Modern"
    @State private var search = ""
    @State private var step: Step = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? .result : (ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-details") ? .roof : .tile)
    @State private var apexMeasurement = ""
    @State private var roofIsNotSquare = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result")
    @State private var leftApexMeasurement = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "4980" : ""
    @State private var centreApexMeasurement = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "5000" : ""
    @State private var rightApexMeasurement = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "5020" : ""
    @State private var ridgeType: RidgeType = .mortar
    @State private var topBattenSetback = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "100" : ""
    @State private var roofPitch = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "30" : ""
    private var tile: TileSpecification { Self.tiles.first { $0.id == tileID } ?? Self.tiles[0] }
    private var matches: [TileSpecification] { let q=search.trimmingCharacters(in:.whitespaces); return q.isEmpty ? Self.tiles : Self.tiles.filter { $0.fullName.localizedCaseInsensitiveContains(q) } }
    private func number(_ value: String) -> Double { Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var ridgeSetback: Double? { number(topBattenSetback) > 0 ? number(topBattenSetback) : nil }
    private var enteredRafterLengths: [Double] {
        roofIsNotSquare
            ? [number(leftApexMeasurement), number(centreApexMeasurement), number(rightApexMeasurement)]
            : [number(apexMeasurement)]
    }
    private var gaugeableLengths: [Double] { enteredRafterLengths.map { max(0, $0 - (ridgeSetback ?? 0)) } }
    private var gaugeableLength: Double { gaugeableLengths.max() ?? 0 }
    private var shortestGaugeableLength: Double { gaugeableLengths.min() ?? 0 }
    private var roofLengthDifference: Double { max(0, gaugeableLength - shortestGaugeableLength) }
    private var courses: Int? { guard gaugeableLength > 0 else { return nil }; return max(1, Int(ceil(gaugeableLength / tile.maxGauge))) }
    private var actualGauge: Double? { guard let courses else { return nil }; return gaugeableLength / Double(courses) }
    private var shortestActualGauge: Double? { guard let courses else { return nil }; return shortestGaugeableLength / Double(courses) }
    private var pitchIsSuitable: Bool { guard let limit = tile.minPitchDegrees, number(roofPitch) > 0 else { return true }; return number(roofPitch) >= limit && number(roofPitch) <= 90 }
    private var canCalculate: Bool { !enteredRafterLengths.contains(where: { $0 <= 0 }) && ridgeSetback != nil && pitchIsSuitable }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ToolIntro(icon: "ruler", title: "Gauger", detail: "Choose the tile, enter two measurements and get the batten gauge.")
            Group {
                switch step {
                case .tile: tileStep
                case .roof: roofStep
                case .result: resultStep
                }
            }
        }
    }

    private var stepStrip: some View {
        HStack(spacing: 8) {
            stepBadge(.tile, "Choose tile", "square.grid.2x2")
            Rectangle().fill(step.rawValue > 1 ? Color.orange : Color.secondary.opacity(0.2)).frame(height: 2)
            stepBadge(.roof, "Roof details", "house")
            Rectangle().fill(step.rawValue > 2 ? Color.orange : Color.secondary.opacity(0.2)).frame(height: 2)
            stepBadge(.result, "Set-out", "checkmark")
        }.padding(.vertical, 4)
    }

    private func stepBadge(_ item: Step, _ title: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: step.rawValue > item.rawValue ? "checkmark.circle.fill" : "\(item.rawValue).circle.fill")
                .font(.title2).foregroundStyle(step.rawValue >= item.rawValue ? .orange : .secondary)
            Text(title).font(.caption).fontWeight(step == item ? .semibold : .regular).foregroundStyle(step.rawValue >= item.rawValue ? .primary : .secondary)
        }.frame(minWidth: 82)
    }

    private var tileStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose tile").font(.title2.bold())
            HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("Type tile name or manufacturer",text:$search).textFieldStyle(.plain); if !search.isEmpty { Button { search="" } label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).foregroundStyle(.secondary) } }.padding(12).background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:10))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { product in
                        Button { tileID = product.id; search = "" } label: {
                            HStack { VStack(alignment:.leading,spacing:2){Text(product.name).fontWeight(tileID == product.id ? .semibold:.regular);Text(product.make).font(.caption).foregroundStyle(.secondary)}; Spacer(); if tileID == product.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.orange) } }.padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if product.id != matches.last?.id { Divider() }
                    }
                }
            }.frame(maxHeight: 230).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected").font(.caption.bold()).foregroundStyle(.secondary)
                Text(tile.fullName).font(.headline)
                HStack { compactSpec("MAX GAUGE", gaugeValue(tile.maxGauge)); compactSpec("HEADLAP", tile.headlap); compactSpec("MIN PITCH", tile.pitch) }
            }.padding(16).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Button { withAnimation { step = .roof } } label: { Label("Use this tile", systemImage: "arrow.right").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
        }
    }

    private var roofStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Button("Back") { withAnimation { step = .tile } }; Spacer(); Text(tile.name).font(.caption.bold()).foregroundStyle(.secondary) }
            Text("Enter roof measurements").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                Text("Ridge type").font(.headline)
                Picker("Ridge type", selection: $ridgeType) {
                    ForEach(RidgeType.allCases) { type in Text(type.rawValue).tag(type) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Roof is not square", isOn: $roofIsNotSquare)
                Text(roofIsNotSquare ? "Measure from the first-batten line to the apex at the left, centre and right." : "Measure from the first-batten line to the rafter apex.")
                    .font(.caption).foregroundStyle(.secondary)
                if roofIsNotSquare {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ToolNumberField(title: "Left", placeholder: "e.g. 4980", unit: "mm", value: $leftApexMeasurement)
                        ToolNumberField(title: "Centre", placeholder: "e.g. 5000", unit: "mm", value: $centreApexMeasurement)
                        ToolNumberField(title: "Right", placeholder: "e.g. 5020", unit: "mm", value: $rightApexMeasurement)
                    }
                } else {
                    ToolNumberField(title: "First-batten line to rafter apex", placeholder: "e.g. 5000", unit: "mm", value: $apexMeasurement)
                }
            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            ToolNumberField(title: "Top batten down from apex", placeholder: "e.g. 100", unit: "mm", value: $topBattenSetback)
            Text(ridgeSetbackHelp).font(.caption).foregroundStyle(.secondary)
            ToolNumberField(title: "Roof pitch", placeholder: "e.g. 30", unit: "°", value: $roofPitch)
            if !pitchIsSuitable { Label("This tile is unsuitable at the entered pitch. Minimum stored limit: \(tile.pitch).", systemImage: "xmark.octagon.fill").font(.callout.bold()).foregroundStyle(.red) }
            Button { withAnimation { step = .result } } label: { Label("Calculate gauge", systemImage: "ruler").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).disabled(!canCalculate)
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading) { Text("Your gauge").font(.title2.bold()); Text(tile.fullName).foregroundStyle(.secondary) }; Spacer(); Button("Edit") { withAnimation { step = .roof } } }
            if let courses, let actualGauge {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        resultMetric("COURSES", "\(courses)", .primary)
                        resultMetric(roofIsNotSquare ? "GAUGE RANGE" : "ACTUAL GAUGE", roofIsNotSquare ? gaugeRangeText(courses: courses) : String(format: "%.1f mm", actualGauge), resultGaugeIsInvalid ? .red : .orange)
                    }
                    if resultGaugeIsInvalid { Label("At least one calculated gauge is outside the permitted \(gaugeDescription). This roof needs an adjusted or separate set-out before fixing battens.", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red) }
                    if roofIsNotSquare {
                        Label("The three measurements differ by \(Int(roofLengthDifference.rounded())) mm. Courses are based on the longest rafter so the maximum gauge is not exceeded.", systemImage: "arrow.left.and.right").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(18).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                if roofIsNotSquare {
                    nonSquareCourseSchedule(courses: courses)
                }
                VStack(alignment: .leading, spacing: 12) {
                    instruction(1, "First batten", "Set the tile tail to \(tile.fasciaProjection ?? "the manufacturer’s stated projection") beyond the fascia.")
                    instruction(2, "Top batten", "Mark it \(Int(ridgeSetback ?? 0)) mm down from the apex for the \(ridgeType.rawValue.lowercased()) detail.")
                    instruction(3, "Gauge the roof", roofIsNotSquare ? "Use \(courses) courses and keep the batten lines level. The calculated range is \(gaugeRangeText(courses: courses))." : "Mark \(courses) equal courses at \(String(format: "%.1f", actualGauge)) mm.")
                }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                Label("Check the tile and \(ridgeType.rawValue.lowercased()) manufacturer details before fixing battens.", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
            } else { ToolEmpty(text: "Return to roof details and enter valid measurements.") }
            Button("Start another roof") { reset() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
        }
    }

    private var ridgeSetbackHelp: String {
        ridgeType == .mortar
            ? "Use the setback required by the mortar ridge tile detail."
            : "Use the top-batten position stated for the dry ridge system."
    }
    private var ridgeAdvice: String {
        ridgeType == .mortar
            ? "Use the selected mortar ridge tile detail and its required mechanical fixing."
            : "Use the dry ridge kit instructions and its required mechanical fixings."
    }
    private var gaugeDescription: String { tile.minGauge == tile.maxGauge ? gaugeValue(tile.maxGauge) : "\(gaugeValue(tile.minGauge))–\(gaugeValue(tile.maxGauge))" }
    private func gaugeValue(_ value: Double) -> String { value.rounded() == value ? "\(Int(value)) mm" : String(format: "%.1f mm", value) }
    private func gaugeIsInvalid(_ gauge: Double) -> Bool { gauge < tile.minGauge || gauge > tile.maxGauge }
    private var resultGaugeIsInvalid: Bool {
        guard let longest = actualGauge, let shortest = shortestActualGauge else { return true }
        return gaugeIsInvalid(longest) || gaugeIsInvalid(shortest)
    }
    private func gaugeRangeText(courses: Int) -> String {
        let values = gaugeableLengths.map { $0 / Double(courses) }
        guard let minimum = values.min(), let maximum = values.max() else { return "—" }
        return String(format: "%.1f–%.1f mm", minimum, maximum)
    }
    private func compactSpec(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption2.bold()).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.75) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func resultMetric(_ title: String, _ value: String, _ colour: Color) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption2.bold()).foregroundStyle(.secondary); Text(value).font(.title2.bold()).foregroundStyle(colour).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func instruction(_ number: Int, _ title: String, _ detail: String) -> some View { HStack(alignment: .top, spacing: 12) { Text("\(number)").font(.caption.bold()).foregroundStyle(.white).frame(width: 26, height: 26).background(.orange, in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.semibold); Text(detail).font(.callout).foregroundStyle(.secondary) } } }
    private func setOutDiagram(courses: Int, gauge: Double) -> some View {
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROOF BATTEN SET-OUT").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
                    Text(tile.name).font(.title2.weight(.semibold))
                    Text("\(ridgeType.rawValue) · Construction view").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(courses) courses").font(.title3.weight(.semibold))
                    Text(roofIsNotSquare ? gaugeRangeText(courses: courses) : "\(String(format: "%.1f", gauge)) mm equal gauge").foregroundStyle(.secondary)
                }
            }
            RoofBattenConstructionView(courses: courses, irregularity: roofIsNotSquare ? roofLengthDifference : 0)
                .frame(minHeight: 330, idealHeight: 430, maxHeight: 480)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                setOutCard("FIRST BATTEN", "0 mm datum")
                setOutCard("TOP SETBACK", "\(Int(ridgeSetback ?? 0)) mm from apex")
                setOutCard("GAUGE RANGE", gaugeDescription)
                setOutCard(roofIsNotSquare ? "ACTUAL RANGE" : "ACTUAL GAUGE", roofIsNotSquare ? gaugeRangeText(courses: courses) : "\(String(format: "%.1f", gauge)) mm")
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
    private func setOutCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.headline).minimumScaleFactor(0.75).lineLimit(1)
        }.padding(13).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
    }
    private func nonSquareCourseSchedule(courses: Int) -> some View {
        let labels = ["Left", "Centre", "Right"]
        let lengths = gaugeableLengths
        let gauges = lengths.map { $0 / Double(courses) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Non-square roof course schedule").font(.headline)
                Text("Every figure is measured up the rafter from the top edge of the first batten. The smaller figure beneath each mark is that section’s equal gauge.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        scheduleHeader("Course", width: 78, alignment: .leading)
                        ForEach(labels, id: \.self) { scheduleHeader($0, width: 142, alignment: .trailing) }
                    }
                    Divider()
                    ForEach(0...courses, id: \.self) { course in
                        HStack(spacing: 0) {
                            Text(course == 0 ? "First" : course == courses ? "Top" : "C\(course)")
                                .font(.callout.weight(course == 0 || course == courses ? .semibold : .regular))
                                .foregroundStyle(course == 0 || course == courses ? Color.red : Color.primary)
                                .frame(width: 78, alignment: .leading)
                            ForEach(0..<3, id: \.self) { index in
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Int((Double(course) * gauges[index]).rounded())) mm")
                                        .font(.callout.monospacedDigit().weight(.semibold))
                                    if course > 0 {
                                        Text("+\(String(format: "%.1f", gauges[index])) gauge")
                                            .font(.caption2.monospacedDigit()).foregroundStyle(gaugeIsInvalid(gauges[index]) ? .red : .secondary)
                                    } else {
                                        Text("datum").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.frame(width: 142, alignment: .trailing)
                            }
                        }.padding(.vertical, 9)
                        if course < courses { Divider() }
                    }
                }.padding(.horizontal, 14)
                    .frame(minWidth: 518)
            }
            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(labels[index].uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f", gauges[index])) mm").font(.headline.monospacedDigit())
                        Text("\(Int(lengths[index].rounded())) mm total").font(.caption2).foregroundStyle(.secondary)
                    }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                        .background((gaugeIsInvalid(gauges[index]) ? Color.red : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
    private func scheduleHeader(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title.uppercased()).font(.caption2.bold()).tracking(0.7).foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment).padding(.vertical, 10)
    }
    private func reset() { step = .tile; apexMeasurement = ""; roofIsNotSquare = false; leftApexMeasurement = ""; centreApexMeasurement = ""; rightApexMeasurement = ""; topBattenSetback = ""; roofPitch = "" }
}

private struct RoofBattenConstructionView: View {
    let courses: Int
    let irregularity: Double

    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
            func mix(_ a: CGPoint, _ b: CGPoint, _ amount: Double) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
            }
            func line(_ start: CGPoint, _ end: CGPoint, colour: Color, width: Double) {
                var path = Path(); path.move(to: start); path.addLine(to: end)
                context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func plane(_ points: [CGPoint], colour: Color) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to: first)
                for item in points.dropFirst() { path.addLine(to: item) }
                path.closeSubpath(); context.fill(path, with: .color(colour))
            }

            let skew = min(0.045, irregularity / 4000)
            let ridgeLeft = point(0.28, 0.22)
            let ridgeRight = point(0.76, 0.31)
            let frontLeft = point(0.10, 0.73)
            let frontRight = point(0.72, 0.84 + skew)
            let backLeft = point(0.40, 0.08)
            let backRight = point(0.93, 0.18)
            let structural = Color.secondary.opacity(0.48)

            plane([backLeft, backRight, ridgeRight, ridgeLeft], colour: Color.secondary.opacity(0.055))
            plane([ridgeLeft, ridgeRight, frontRight, frontLeft], colour: Color.secondary.opacity(0.075))

            // Wall plate and posts give the drawing the silhouette of a complete roof structure.
            line(point(0.10, 0.78), point(0.72, 0.89 + skew), colour: Color.secondary.opacity(0.48), width: 10)
            for fraction in stride(from: 0.04, through: 0.96, by: 0.23) {
                let top = mix(point(0.10, 0.78), point(0.72, 0.89 + skew), fraction)
                line(top, CGPoint(x: top.x, y: min(size.height * 0.98, top.y + size.height * 0.12)), colour: Color.secondary.opacity(0.34), width: 8)
            }

            // Both slopes and the ridge make this read as a pitched roof, not a flat diagram.
            for fraction in stride(from: 0.02, through: 0.98, by: 0.16) {
                line(mix(backLeft, backRight, fraction), mix(ridgeLeft, ridgeRight, fraction), colour: structural, width: 6)
                line(mix(frontLeft, frontRight, fraction), mix(ridgeLeft, ridgeRight, fraction), colour: structural, width: 7)
            }
            line(ridgeLeft, ridgeRight, colour: Color.secondary.opacity(0.72), width: 11)

            // Battens follow the foreground roof plane. First and top courses are emphasised.
            for course in 0...max(1, courses) {
                let fraction = Double(course) / Double(max(1, courses))
                let position = 0.07 + fraction * 0.84
                let left = mix(frontLeft, ridgeLeft, position)
                let right = mix(frontRight, ridgeRight, position)
                let fixed = course == 0 || course == courses
                line(left, right, colour: fixed ? Color.red : Color.orange, width: fixed ? 7 : 4.5)
            }

            // Fascia and a simple half-round gutter sit below the first batten as visual context.
            line(frontLeft, frontRight, colour: Color.primary.opacity(0.68), width: 14)
            let gutterLeft = CGPoint(x: frontLeft.x - 2, y: frontLeft.y + 18)
            let gutterRight = CGPoint(x: frontRight.x - 2, y: frontRight.y + 18)
            line(gutterLeft, gutterRight, colour: Color.secondary.opacity(0.72), width: 13)
            line(CGPoint(x: gutterLeft.x, y: gutterLeft.y - 3), CGPoint(x: gutterRight.x, y: gutterRight.y - 3), colour: Color.white.opacity(0.5), width: 2)
        }
        .accessibilityLabel("Pitched roof construction showing rafters, ridge, fascia, gutter and \(courses + 1) batten lines")
    }
}

private struct TileSpecification: Identifiable {
    let make, name, pitch: String
    let minGauge, maxGauge: Double
    let headlap: String
    let tileLength, minPitchDegrees: Double?
    let fasciaProjection: String?
    let gaugeBasis: String?
    init(make: String, name: String, pitch: String, minGauge: Double, maxGauge: Double, headlap: String, tileLength: Double? = nil, minPitchDegrees: Double? = nil, fasciaProjection: String? = nil, gaugeBasis: String? = nil) { self.make = make; self.name = name; self.pitch = pitch; self.minGauge = minGauge; self.maxGauge = maxGauge; self.headlap = headlap; self.tileLength = tileLength; self.minPitchDegrees = minPitchDegrees; self.fasciaProjection = fasciaProjection; self.gaugeBasis = gaugeBasis }
    var fullName:String{"\(make) \(name)"}; var id:String{fullName}
}
private struct TileSpecCard: View { let title, value: String; var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption2.bold()).foregroundStyle(.secondary); Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(2) }.padding(12).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) } }

#if os(iOS)
private enum RoofPhonePosition: String, CaseIterable, Identifiable {
    case longEdge = "Side", shortEdge = "End", back = "Flat"
    var id: String { rawValue }
}

private final class RoofLevelModel: ObservableObject {
    @Published var gravityX = 0.0
    @Published var gravityY = 0.0
    @Published var gravityZ = -1.0
    @Published var available = true
    @Published var receivingData = false
    private let manager = CMMotionManager()
    func start() {
        guard manager.isDeviceMotionAvailable else { available = false; return }
        available = true
        manager.deviceMotionUpdateInterval = 0.08
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if error != nil { self.available = false; self.receivingData = false; return }
            guard let gravity = motion?.gravity else { return }
            let smoothing = self.receivingData ? 0.28 : 1.0
            self.gravityX += (gravity.x - self.gravityX) * smoothing
            self.gravityY += (gravity.y - self.gravityY) * smoothing
            self.gravityZ += (gravity.z - self.gravityZ) * smoothing
            self.receivingData = true
        }
    }
    func stop() { manager.stopDeviceMotionUpdates(); receivingData = false }
    func degrees(for position: RoofPhonePosition) -> Double {
        let radians: Double
        switch position {
        case .longEdge: radians = atan2(abs(gravityY), hypot(gravityX, gravityZ))
        case .shortEdge: radians = atan2(abs(gravityX), hypot(gravityY, gravityZ))
        case .back: radians = atan2(hypot(gravityX, gravityY), abs(gravityZ))
        }
        return min(90, max(0, radians * 180 / .pi))
    }
}

private struct LiveRoofLevel: View {
    @StateObject private var level = RoofLevelModel()
    @State private var position: RoofPhonePosition = .longEdge
    @State private var heldReading: Double?
    private var degrees: Double { heldReading ?? level.degrees(for: position) }
    private var rounded: Int { Int(degrees.rounded()) }
    private var colour: Color { heldReading == nil ? .orange : .green }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if level.available {
                VStack(spacing: 16) {
                    HStack {
                        Label(heldReading == nil ? "LIVE READING" : "READING HELD", systemImage: heldReading == nil ? "sensor.fill" : "checkmark.circle.fill")
                            .font(.caption.bold()).foregroundStyle(colour)
                        Spacer()
                        Text(pitchBand).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(level.receivingData ? String(format: "%.1f°", degrees) : "—")
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.16)).frame(height: 8)
                        Capsule().fill(colour).frame(width: max(8, CGFloat(degrees / 90) * 280), height: 8)
                    }
                        .frame(maxWidth: 280)
                    Text(level.receivingData ? positionHelp : "Waiting for the motion sensor…")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))

                Text("Phone position").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("Phone position", selection: $position) { ForEach(RoofPhonePosition.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .onChange(of: position) { _, _ in heldReading = nil }

                Button { heldReading = heldReading == nil ? level.degrees(for: position) : nil } label: {
                    Label(heldReading == nil ? "Hold this reading" : "Take another reading", systemImage: heldReading == nil ? "pause.fill" : "arrow.counterclockwise")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).tint(heldReading == nil ? .orange : .green).controlSize(.large).disabled(!level.receivingData)
            } else { ContentUnavailableView("Motion sensor unavailable", systemImage: "sensor", description: Text("This feature needs a real iPhone. Use rise and run below instead.")) }
        }.onAppear { level.start() }.onDisappear { level.stop() }
    }
    private var pitchBand: String {
        if !level.receivingData { return "" }
        if degrees < 15 { return "Very low pitch" }
        if degrees < 22.5 { return "Low pitch" }
        return "Pitched roof"
    }
    private var positionHelp: String {
        switch position {
        case .longEdge: return "Put the long side of the phone against the roof slope."
        case .shortEdge: return "Put the top or bottom of the phone against the roof slope."
        case .back: return "Lay the back of the phone flat on the roof surface."
        }
    }
}
#endif

private struct ToolIntro: View { let icon, title, detail: String; var body: some View { HStack(alignment: .top, spacing: 14) { Image(systemName: icon).font(.title2).foregroundStyle(.orange).frame(width: 48, height: 48).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11)); VStack(alignment: .leading, spacing: 4) { Text(title).font(.title2.bold()); Text(detail).foregroundStyle(.secondary) } } } }
private struct ToolNumberField: View { let title, placeholder, unit: String; @Binding var value: String; var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption.bold()).foregroundStyle(.secondary); HStack { TextField(placeholder, text: $value).textFieldStyle(.plain); Text(unit).foregroundStyle(.secondary) }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary)) }.frame(maxWidth: .infinity) } }
private struct ToolEmpty: View { let text: String; var body: some View { Label(text, systemImage: "info.circle").foregroundStyle(.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12)) } }

struct FinanceCentreView: View {
    @Environment(AppState.self) private var appState
    private var liveJobs: [Lead] { appState.leads.filter { [.won, .scheduled, .inProgress, .completed, .waitingForPayment, .paid].contains($0.stage) } }
    private var depositsDue: [Lead] { liveJobs.filter { !$0.depositPaid && $0.deposit > 0 && $0.stage != .paid } }
    private var collected: Double { liveJobs.reduce(0) { $0 + max(0, $1.value - $1.balance) } }
    private var outstanding: Double { liveJobs.reduce(0) { $0 + max(0, $1.balance) } }
    private var materialCost: Double { liveJobs.reduce(0) { total, lead in total + lead.materials.reduce(0) { $0 + (($1.cost ?? 0) * $1.quantity) } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text("Customer Money").font(.system(size: 29, weight: .bold)); Text("See what has come in and what customers still owe.").foregroundStyle(.secondary) }
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    financeMetric("Collected", collected, "banknote.fill", .green)
                    financeMetric("To collect", outstanding, "sterlingsign.circle.fill", .orange)
                    financeMetric("Deposits due", depositsDue.reduce(0) { $0 + $1.deposit }, "exclamationmark.circle.fill", .red)
                    financeMetric("Materials logged", materialCost, "shippingbox.fill", .purple)
                }
                financePanel("Outstanding deposits", systemImage: "creditcard") {
                        if depositsDue.isEmpty { ContentUnavailableView("No deposits outstanding", systemImage: "checkmark.circle", description: Text("Deposits awaiting payment will appear here.")) }
                        else { ForEach(depositsDue) { lead in HStack { VStack(alignment: .leading, spacing: 3) { Text(lead.name).fontWeight(.semibold); Text("\(lead.jobRef) · \(lead.jobType)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(lead.deposit, format: .currency(code: "GBP")).fontWeight(.semibold); Button("Mark paid") { Task { await appState.recordDeposit(for: lead) } }.buttonStyle(.borderedProminent).tint(.green); NavigationLink { LeadDetailView(leadID: lead.id) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain) }; Divider() } }
                }
            }.padding(24)
        }.background(Color.primary.opacity(0.025)).navigationTitle("Finance")
    }
    private func financeMetric(_ title: String, _ value: Double, _ icon: String, _ colour: Color) -> some View { HStack(spacing: 13) { Image(systemName: icon).font(.title2).foregroundStyle(colour).frame(width: 42, height: 42).background(colour.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading) { Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)) }
    private func financePanel<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 13) { Label(title, systemImage: systemImage).font(.headline); content() }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)) }
}

struct FleetView: View {
    @Environment(AppState.self) private var appState
    @State private var showingRenewal = false
    @State private var showingVehicle = false
    @State private var editingVehicle: FleetVehicleSelection?
    @State private var deletingVehicle: FleetVehicleSelection?
    private var renewals: [GeneralTask] { appState.generalTasks.filter { task in
        !task.completed && ["Fleet", "Vehicle", "Renewal"].contains(task.category)
            && !task.title.localizedCaseInsensitiveContains("insurance")
            && !task.title.localizedCaseInsensitiveContains("road tax")
    }.sorted { ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") } }
    private var vehicles: [(GeneralTask, FleetVehicleInfo)] { appState.generalTasks.filter { $0.category == "Fleet Vehicle" }.compactMap { task in guard let data = task.notes?.data(using: .utf8), let info = try? JSONDecoder().decode(FleetVehicleInfo.self, from: data) else { return nil }; return (task, info) } }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { HStack { VStack(alignment: .leading, spacing: 3) { Text("Fleet").font(.system(size: 29, weight: .bold)); Text("Keep vans roadworthy, serviced and ready for work.").foregroundStyle(.secondary) }; Spacer(); Button { showingRenewal = true } label: { Label("Add reminder", systemImage: "calendar.badge.plus") }.buttonStyle(.bordered); Button { showingVehicle = true } label: { Label("Add vehicle", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.orange) }; LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) { fleetMetric("Vehicles", vehicles.count, "car.2.fill", .blue); fleetMetric("Open reminders", renewals.count, "calendar.badge.exclamationmark", .orange); fleetMetric("Due within 30 days", renewals.filter(isUrgent).count, "exclamationmark.triangle.fill", .red) }; Text("Vehicles").font(.title2.bold()); if vehicles.isEmpty { ContentUnavailableView("No vehicles added", systemImage: "car.2", description: Text("Add your vans to keep their important details together.")) } else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 14)], spacing: 14) { ForEach(vehicles, id: \.0.id) { task, info in vehicleCard(task, info) } } }; VStack(alignment: .leading, spacing: 12) { Label("Upcoming reminders", systemImage: "calendar.badge.exclamationmark").font(.headline); if renewals.isEmpty { Text("No open MOT, service or breakdown reminders.").foregroundStyle(.secondary).padding(.vertical, 18) } else { ForEach(renewals) { task in HStack { Button { Task { await appState.toggleGeneralTask(task) } } label: { Image(systemName: "circle") }.buttonStyle(.plain); VStack(alignment: .leading, spacing: 3) { Text(task.title).fontWeight(.semibold); Text(task.dueDate.map { "Due \($0)" } ?? "No date").font(.caption).foregroundStyle(isUrgent(task) ? .red : .secondary) }; Spacer(); if isUrgent(task) { Text("Due soon").font(.caption.bold()).foregroundStyle(.red) } }; Divider() } } }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)) }.padding(24) }.navigationTitle("Fleet").sheet(isPresented: $showingRenewal) { AddRenewalView() }.sheet(isPresented: $showingVehicle) { AddVehicleView() }.sheet(item: $editingVehicle) { AddVehicleView(existing: $0) }.confirmationDialog("Delete this vehicle?", isPresented: Binding(get: { deletingVehicle != nil }, set: { if !$0 { deletingVehicle = nil } }), titleVisibility: .visible) { Button("Delete vehicle", role: .destructive) { guard let vehicle = deletingVehicle else { return }; deletingVehicle = nil; Task { await appState.deleteGeneralTask(vehicle.task) } }; Button("Cancel", role: .cancel) { deletingVehicle = nil } } message: { Text("The vehicle card will be deleted. Existing MOT and service reminders will remain in Tasks.") } }
    private func isUrgent(_ task: GeneralTask) -> Bool { guard let due = task.dueDate, let limit = Calendar.current.date(byAdding: .day, value: 30, to: .now) else { return false }; return due <= SupabaseService.localDay(for: limit) }
    private func vehicleName(_ task: GeneralTask) -> String { task.title.components(separatedBy: " — ").first ?? task.title }
    private func fleetMetric(_ title: String, _ value: Int, _ icon: String, _ colour: Color) -> some View { HStack { Image(systemName: icon).font(.title2).foregroundStyle(colour).frame(width: 44, height: 44).background(colour.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading) { Text("\(value)").font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)) }
    private func vehicleCard(_ task: GeneralTask, _ info: FleetVehicleInfo) -> some View { VStack(alignment: .leading, spacing: 12) { HStack { Image(systemName: "car.side.fill").font(.title).foregroundStyle(.orange).frame(width: 50, height: 50).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading) { Text(task.title.uppercased()).font(.title3.bold()); Text([info.make, info.model].filter { !$0.isEmpty }.joined(separator: " ")).foregroundStyle(.secondary) }; Spacer(); Menu { Button { editingVehicle = .init(task: task, info: info) } label: { Label("Edit vehicle", systemImage: "pencil") }; Button(role: .destructive) { deletingVehicle = .init(task: task, info: info) } label: { Label("Delete vehicle", systemImage: "trash") } } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).fixedSize() }; if !info.status.isEmpty { Text(info.status).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.green.opacity(0.12), in: Capsule()).foregroundStyle(.green) }; Divider(); vehicleRow("Driver", info.driver.isEmpty ? "Unassigned" : info.driver, "person"); vehicleRow("Mileage", info.mileage.isEmpty ? "Not recorded" : info.mileage, "gauge.with.dots.needle.67percent"); vehicleRow("MOT", info.motDate.isEmpty ? "Not set" : info.motDate, "checkmark.seal"); vehicleRow("Service", info.serviceDate.isEmpty ? "Not set" : info.serviceDate, "wrench.and.screwdriver") }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary)) }
    private func vehicleRow(_ label: String, _ value: String, _ icon: String) -> some View { HStack { Label(label, systemImage: icon).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) } .font(.caption) }
}

private struct FleetVehicleInfo: Codable { var make: String; var model: String; var driver: String; var mileage: String; var motDate: String; var serviceDate: String; var status: String }
private struct FleetVehicleSelection: Identifiable { var id: String { task.id }; let task: GeneralTask; let info: FleetVehicleInfo }

private struct AddVehicleView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var registration = ""; @State private var make = ""; @State private var model = ""; @State private var driver = ""; @State private var mileage = ""
    @State private var hasMOT = false; @State private var mot = Date(); @State private var hasService = false; @State private var service = Date()
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
    var body: some View { NavigationStack { Form {
        Section("Vehicle details") {
            HStack {
                TextField("Registration number", text: $registration).textCase(.uppercase)
                Button { lookupMOT() } label: { if lookingUpMOT { ProgressView().controlSize(.small) } else { Label("Look up", systemImage:"magnifyingglass") } }
                    .disabled(registration.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || lookingUpMOT)
            }
            if let motLookupMessage { Text(motLookupMessage).font(.caption).foregroundStyle(motLookupMessage.hasPrefix("Found") ? .green:.red) }
            HStack { TextField("Make", text: $make); TextField("Model", text: $model) }
        }
        Section("Use") { TextField("Assigned driver", text: $driver); TextField("Current mileage", text: $mileage) }
        Section("MOT") { Toggle("Track MOT", isOn: $hasMOT); if hasMOT { DatePicker("MOT expires", selection: $mot, displayedComponents: .date) } else { Text("Use Look up to retrieve the current MOT expiry.").font(.caption).foregroundStyle(.secondary) } }
        Section("Servicing") { Toggle("Track next service", isOn: $hasService); if hasService { DatePicker("Next service", selection: $service, displayedComponents: .date) } else { Text("Set this manually from the van's service schedule.").font(.caption).foregroundStyle(.secondary) } }
        Section { Label("Saving creates the vehicle card and its renewal reminders automatically.", systemImage: "bell.badge").font(.caption).foregroundStyle(.secondary) }
    }.disabled(isSaving).navigationTitle(existing == nil ? "Add vehicle" : "Edit vehicle").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }; ToolbarItem(placement: .confirmationAction) { Button { save() } label: { if isSaving { ProgressView() } else { Text(existing == nil ? "Save vehicle" : "Save changes") } }.disabled(registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving) } } }.frame(minWidth: 540, minHeight: 680) }
    private func dateString(_ date: Date, enabled: Bool) -> String { enabled ? PayrollMath.key(date) : "" }
    private func lookupMOT() {
        lookingUpMOT=true;motLookupMessage=nil
        Task {
            do {
                let vehicle=try await SupabaseService.shared.lookupMOT(registration:registration)
                registration=vehicle.registration;make=vehicle.make;model=vehicle.model
                if !vehicle.odometerValue.isEmpty { mileage=[vehicle.odometerValue,vehicle.odometerUnit].filter{!$0.isEmpty}.joined(separator:" ") }
                if let expiry=SupabaseService.date(from:vehicle.motExpiryDate),!vehicle.motExpiryDate.isEmpty {
                    mot=expiry;hasMOT=true
                    motLookupMessage="Found \(vehicle.make) \(vehicle.model) · MOT expires \(vehicle.motExpiryDate)"
                } else {
                    hasMOT=false
                    motLookupMessage="Found \(vehicle.make) \(vehicle.model), but DVSA supplied no current MOT expiry."
                }
            } catch { motLookupMessage=error.localizedDescription }
            lookingUpMOT=false
        }
    }
    private func save() {
        let reg = registration.uppercased().filter { !$0.isWhitespace }
        let motDate = dateString(mot, enabled: hasMOT), serviceDate = dateString(service, enabled: hasService)
        let info = FleetVehicleInfo(make: make, model: model, driver: driver, mileage: mileage, motDate: motDate, serviceDate: serviceDate, status: "Active")
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
                if hasMOT { await appState.addGeneralTask(title: "\(reg) — MOT", dueDate: motDate, priority: "high", category: "Fleet", assignedTo: [], notes: nil) }
                if hasService { await appState.addGeneralTask(title: "\(reg) — Service", dueDate: serviceDate, priority: "medium", category: "Fleet", assignedTo: [], notes: nil) }
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
    var body: some View { NavigationStack { Form { Section("Vehicle") { TextField("Registration or van name", text: $vehicle); Picker("Reminder", selection: $type) { ForEach(["MOT", "Service", "Breakdown cover"], id: \.self) { Text($0) } }; DatePicker("Due date", selection: $dueDate, displayedComponents: .date) }; Section("Details") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5) }; Section { Text("ProLine will place this in Tasks and schedule a notification before it is due.").font(.caption).foregroundStyle(.secondary) } }.disabled(isSaving).navigationTitle("Add vehicle reminder").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }; ToolbarItem(placement: .confirmationAction) { Button { Task { isSaving = true; defer { isSaving = false }; let date = PayrollMath.key(dueDate); if await appState.addGeneralTask(title: "\(vehicle) — \(type)", dueDate: date, priority: "high", category: "Fleet", notes: notes.isEmpty ? nil : notes) { dismiss() } } } label: { if isSaving { ProgressView() } else { Text("Save") } }.disabled(vehicle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving) } } }.frame(minWidth: 460, minHeight: 380) }
}

struct TeamHubView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var message = ""
    @State private var showingPlan = false
    @State private var sending = false

    private var dayKey: String { SupabaseService.localDay(for: selectedDay) }
    private var plans: [TeamDayPlan] { appState.teamDayPlans.filter { $0.day == dayKey } }
    private var messages: [TeamMessage] { Array(appState.teamMessages.reversed()) }

    var body: some View {
        #if os(macOS)
        macChatHub
        #else
        mobileChatHub
        .navigationTitle("Team Hub")
        .sheet(isPresented: $showingPlan) { TeamPlanSheet(defaultDay: selectedDay) }
        .onAppear { appState.markTeamRead() }
        .onChange(of: appState.teamMessages.count) { _, _ in appState.markTeamRead() }
        .task { await liveLoop() }
        #endif
    }

    #if !os(macOS)
    private var mobileChatHub: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Circle().fill(Color(red: 0.12, green: 0.55, blue: 0.33)).frame(width: 42, height: 42)
                    .overlay(Text("PT").font(.caption.bold()).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ProLine Team").font(.headline)
                    HStack(spacing: 4) { Circle().fill(.green).frame(width: 7, height: 7); Text("Live team chat") }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { try? await appState.refreshTeam() } } label: { Image(systemName: "arrow.clockwise") }
                Button { showingPlan = true } label: { Image(systemName: "calendar.badge.plus") }.foregroundStyle(.orange)
            }.padding(.horizontal, 14).frame(height: 62).background(.background)
            Divider()

            VStack(spacing: 9) {
                HStack {
                    Button { selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(selectedDay.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                    Text("· \(plans.count) planned").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay } label: { Image(systemName: "chevron.right") }
                }.buttonStyle(.plain)
                if !plans.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(plans) { plan in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(plan.title).font(.caption.bold()).lineLimit(1); Spacer(); Text(plan.startTime ?? "").font(.caption2).foregroundStyle(.orange) }
                                    if let lead = appState.leads.first(where: { $0.id == plan.leadID }) { Text("\(lead.name) · \(lead.jobRef)").font(.caption2).foregroundStyle(.blue).lineLimit(1) }
                                    if !plan.assignedTo.isEmpty { Label(plan.assignedTo.joined(separator: ", "), systemImage: "person.2.fill").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }.padding(10).frame(width: 220, height: 66, alignment: .topLeading).background(.background, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
                            }
                        }
                    }
                }
            }.padding(.horizontal, 12).padding(.vertical, 9).background(Color.secondary.opacity(0.045))
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if messages.isEmpty { ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right", description: Text("Send the first update to your team.")).frame(minHeight: 330) }
                        ForEach(messages) { item in TeamMessageBubble(message: item, isMine: item.authorID == appState.currentUser?.id).id(item.id) }
                    }.padding(.horizontal, 12).padding(.vertical, 14)
                }
                .background(Color(red: 0.94, green: 0.93, blue: 0.89).opacity(0.55))
                .onAppear { if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 9) {
                Menu { Button { showingPlan = true } label: { Label("Plan work", systemImage: "calendar.badge.plus") }; Divider(); ForEach(appState.leads.filter { ![.paid, .lost].contains($0.stage) }.prefix(20)) { lead in Button { message += message.isEmpty ? "Regarding \(lead.name) (\(lead.jobRef)): " : " \(lead.jobRef)" } label: { Text("\(lead.name) · \(lead.jobRef)") } } } label: { Image(systemName: "plus").font(.headline).frame(width: 34, height: 34).background(Color.secondary.opacity(0.12), in: Circle()) }
                TextField("Message", text: $message, axis: .vertical).lineLimit(1...4).textFieldStyle(.plain).padding(.horizontal, 13).padding(.vertical, 9).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                Button { send() } label: { if sending { ProgressView().controlSize(.small) } else { Image(systemName: "paperplane.fill").foregroundStyle(.white) } }.buttonStyle(.plain).frame(width: 38, height: 38).background(Color(red: 0.12, green: 0.55, blue: 0.33), in: Circle()).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }.padding(.horizontal, 11).padding(.vertical, 9).background(.background)
        }
    }
    #endif

    #if os(macOS)
    private var macChatHub: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Circle().fill(Color.orange.gradient).frame(width: 42, height: 42)
                        .overlay(Image(systemName: "person.3.fill").foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ProLine Team").font(.headline)
                        Text("\(appState.users.count) staff members").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { try? await appState.refreshTeam() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Refresh messages")
                }.padding(16).background(Color(nsColor: .controlBackgroundColor))
                Divider()
                HStack {
                    Button { selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    VStack(spacing: 2) { Text(selectedDay.formatted(date: .abbreviated, time: .omitted)).fontWeight(.semibold); Text("\(plans.count) planned").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button { selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay } label: { Image(systemName: "chevron.right") }
                }.buttonStyle(.plain).padding(14)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if plans.isEmpty {
                            ContentUnavailableView("No work planned", systemImage: "calendar", description: Text("Plan jobs and crews for this day."))
                                .frame(minHeight: 230)
                        } else {
                            ForEach(plans) { plan in planSidebarCard(plan) }
                        }
                    }.padding(12)
                }
                Divider()
                Button { showingPlan = true } label: { Label("Plan work", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).padding(14)
            }
            .frame(minWidth: 290, idealWidth: 330, maxWidth: 380)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Circle().fill(Color(red: 0.12, green: 0.55, blue: 0.33)).frame(width: 42, height: 42)
                        .overlay(Text("PT").font(.caption.bold()).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ProLine Team Chat").font(.headline)
                        HStack(spacing: 5) { Circle().fill(.green).frame(width: 7, height: 7); Text("Live · updates every 10 seconds") }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(appState.teamMessages.count) messages").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).frame(height: 68).background(Color(nsColor: .controlBackgroundColor))
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if messages.isEmpty { ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right", description: Text("Send the first update to your team.")).frame(minHeight: 360) }
                            ForEach(messages) { item in TeamMessageBubble(message: item, isMine: item.authorID == appState.currentUser?.id).id(item.id) }
                        }.padding(.horizontal, 22).padding(.vertical, 18)
                    }
                    .background(Color(red: 0.94, green: 0.93, blue: 0.89).opacity(0.55))
                    .onAppear { if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                    .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                }
                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    Menu { Button { showingPlan = true } label: { Label("Plan work", systemImage: "calendar.badge.plus") }; Divider(); ForEach(appState.leads.filter { ![.paid, .lost].contains($0.stage) }.prefix(20)) { lead in Button { message += message.isEmpty ? "Regarding \(lead.name) (\(lead.jobRef)): " : " \(lead.jobRef)" } label: { Label("\(lead.name) · \(lead.jobRef)", systemImage: "briefcase") } } } label: { Image(systemName: "plus").font(.headline).frame(width: 36, height: 36).background(Color.secondary.opacity(0.12), in: Circle()) }.menuStyle(.borderlessButton).fixedSize()
                    TextField("Message the team", text: $message, axis: .vertical)
                        .lineLimit(1...5).textFieldStyle(.plain).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
                        .onSubmit { send() }
                    Button { send() } label: { if sending { ProgressView().controlSize(.small) } else { Image(systemName: "paperplane.fill").foregroundStyle(.white) } }
                        .buttonStyle(.plain).frame(width: 40, height: 40).background(Color(red: 0.12, green: 0.55, blue: 0.33), in: Circle())
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }.padding(14).background(Color(nsColor: .controlBackgroundColor))
            }.frame(minWidth: 520)
        }
        .navigationTitle("Team Hub")
        .sheet(isPresented: $showingPlan) { TeamPlanSheet(defaultDay: selectedDay) }
        .onAppear { appState.markTeamRead() }
        .onChange(of: appState.teamMessages.count) { _, _ in appState.markTeamRead() }
        .task { await liveLoop() }
    }

    private func planSidebarCard(_ plan: TeamDayPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(plan.title).fontWeight(.semibold).lineLimit(1); Spacer(); Text([plan.startTime, plan.endTime].compactMap { $0 }.joined(separator: "–")).font(.caption.bold()).foregroundStyle(.orange) }
            if let lead = appState.leads.first(where: { $0.id == plan.leadID }) { NavigationLink { LeadDetailView(leadID: lead.id) } label: { Label("\(lead.name) · \(lead.jobRef)", systemImage: "briefcase").font(.caption) }.buttonStyle(.plain).foregroundStyle(.blue) }
            if !plan.assignedTo.isEmpty { Label(plan.assignedTo.joined(separator: ", "), systemImage: "person.2.fill").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    #endif

    private var dayPlanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay } label: { Image(systemName: "chevron.left") }
                DatePicker("Day", selection: $selectedDay, displayedComponents: .date).labelsHidden()
                Button { selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay } label: { Image(systemName: "chevron.right") }
                Spacer(); Text("\(plans.count) planned").font(.caption).foregroundStyle(.secondary)
            }
            Text("Day plan").font(.title2.bold())
            if plans.isEmpty {
                ContentUnavailableView("Nothing planned", systemImage: "calendar.badge.plus", description: Text("Add jobs, staff and timings for this day."))
            } else {
                ForEach(plans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(plan.title).font(.headline); Spacer(); Text([plan.startTime, plan.endTime].compactMap{$0}.joined(separator:"–")).font(.caption.bold()).foregroundStyle(.orange) }
                        if let lead = appState.leads.first(where: { $0.id == plan.leadID }) { NavigationLink { LeadDetailView(leadID: lead.id) } label: { Label("\(lead.name) · \(lead.jobRef)", systemImage: "briefcase") } }
                        if !plan.assignedTo.isEmpty { Label(plan.assignedTo.joined(separator: ", "), systemImage: "person.2.fill").font(.subheadline) }
                        if !plan.notes.isEmpty { Text(plan.notes).font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
            }
            Spacer(minLength: 0)
        }.padding(18)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Team messages").font(.title2.bold()); Spacer(); Text("Updates every 10 seconds").font(.caption).foregroundStyle(.green) }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty { ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right", description: Text("Start the team conversation below.")) }
                    ForEach(messages) { item in
                        TeamMessageBubble(message: item, isMine: item.authorID == appState.currentUser?.id)
                    }
                }.padding(.vertical, 4)
            }
            HStack(alignment: .bottom) {
                TextField("Message the team…", text: $message, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button { send() } label: { if sending { ProgressView() } else { Image(systemName: "paperplane.fill") } }.buttonStyle(.borderedProminent).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
        }.padding(18)
    }

    private func send() {
        let value = message; sending = true
        Task { if await appState.sendTeamMessage(value) { message = "" }; sending = false }
    }

    private func liveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            try? await appState.refreshTeam(showErrors: false)
        }
    }
}

private struct TeamMessageBubble: View {
    let message: TeamMessage
    let isMine: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 90) } else { Circle().fill(Color.orange.opacity(0.18)).frame(width: 30, height: 30).overlay(Text(message.authorName.prefix(1).uppercased()).font(.caption.bold()).foregroundStyle(.orange)) }
            VStack(alignment: .leading, spacing: 5) {
                if !isMine { Text(message.authorName).font(.caption.bold()).foregroundStyle(Color.orange) }
                Text(message.body).textSelection(.enabled)
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text(chatTime(message.createdAt)).font(.caption2).foregroundStyle(.secondary)
                    if isMine { Image(systemName: "checkmark.done").font(.caption2).foregroundStyle(.blue) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(isMine ? Color(red: 0.82, green: 0.95, blue: 0.78) : Color.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.black.opacity(0.05)))
            if !isMine { Spacer(minLength: 90) }
        }
    }
    private func chatTime(_ raw: String) -> String { let value = raw.replacingOccurrences(of: "T", with: " "); return value.count >= 16 ? String(value.dropFirst(11).prefix(5)) : String(value.prefix(16)) }
}

private struct TeamPlanSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var title = ""
    @State private var notes = ""
    @State private var start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 16, minute: 30, second: 0, of: .now) ?? .now
    @State private var leadID = ""
    @State private var assigned: Set<String> = []
    @State private var saving = false
    init(defaultDay: Date) { _day = State(initialValue: defaultDay) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Work") { TextField("Title", text: $title); Picker("Job", selection: $leadID) { Text("General / no job").tag(""); ForEach(appState.leads.filter { ![.paid,.lost].contains($0.stage) }) { Text("\($0.name) · \($0.jobRef)").tag($0.id) } }; TextField("Notes, access or materials", text: $notes, axis: .vertical).lineLimit(2...5) }
                Section("When") { DatePicker("Day", selection: $day, displayedComponents: .date); DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute); DatePicker("Finish", selection: $end, displayedComponents: .hourAndMinute) }
                Section("Team") {
                    ForEach(appState.users) { user in
                        Toggle(user.name, isOn: Binding(
                            get: { assigned.contains(user.name) },
                            set: { isAssigned in
                                if isAssigned { assigned.insert(user.name) }
                                else { assigned.remove(user.name) }
                            }
                        ))
                    }
                }
            }.disabled(saving).navigationTitle("Plan work").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || assigned.isEmpty || saving) } }
        }.frame(minWidth: 480, minHeight: 590)
    }
    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
    private func save() {
        guard let user = appState.currentUser else { return }
        let plan = TeamDayPlan(id: UUID().uuidString, day: SupabaseService.localDay(for: day), title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, startTime: time(start), endTime: time(end), leadID: leadID.isEmpty ? nil : leadID, assignedTo: assigned.sorted(), createdBy: user.id, createdAt: SupabaseService.now)
        saving = true; Task { if await appState.saveTeamDayPlan(plan) { dismiss() }; saving = false }
    }
}

import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    private var today: String { SupabaseService.today }
    var body: some View {
        #if os(macOS)
        MacDashboardView()
        #else
        MobileDashboardView()
        #endif
    }
}

#if os(iOS)
private struct MobileDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var showingBusinessSummary = false
    @State private var editingGeneralTask: GeneralTask?
    @State private var editingJobTask: JobChecklistItem?
    private var today:String { SupabaseService.today }
    private var urgent:[CompanyAction] { Array(attentionActions.prefix(4)) }
    private var attentionActions: [CompanyAction] {
        let ranked = appState.companyActions.filter { $0.priority >= .urgent }
        var seen = Set<String>()
        return ranked.filter { action in
            let key = action.leadID.map { "lead-\($0)" } ?? action.generalTaskID.map { "task-\($0)" } ?? action.id
            return seen.insert(key).inserted
        }
    }
    private var dailyLeads:[Lead] {
        Array(appState.leads.filter { $0.surveyDate == today || $0.startDate == today || ($0.stage == .inProgress && ($0.endDate ?? today) >= today) }
            .sorted { ($0.surveyDate ?? $0.startDate ?? "9999") < ($1.surveyDate ?? $1.startDate ?? "9999") }.prefix(3))
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack { VStack(alignment:.leading,spacing:3){Text(greeting).font(.largeTitle.bold());Text(Date.now.formatted(date:.complete,time:.omitted)).font(.subheadline).foregroundStyle(.secondary)};Spacer();Circle().fill(.orange.gradient).frame(width:46,height:46).overlay(Text(appState.currentUser?.name.prefix(1) ?? "P").font(.headline).foregroundStyle(.white)) }
                HStack {
                    Text("Action required").font(.title3.bold())
                    Spacer()
                    Button("View all") { appState.selectedSection = .tasks }.font(.subheadline.bold())
                    Text("\(urgent.count)").font(.caption.bold()).padding(.horizontal,8).padding(.vertical,4).background(.quaternary,in:Capsule())
                }
                if urgent.isEmpty { ContentUnavailableView("You’re all caught up",systemImage:"checkmark.circle",description:Text("No operational actions need attention right now.")) }
                else {
                    VStack(spacing: 0) {
                        ForEach(urgent) { action in
                            MobileCompanyActionRow(action:action, complete: { complete(action) }, open: { open(action) })
                            if action.id != urgent.last?.id { Divider().padding(.leading, 60) }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                }
                HStack { Text("Today").font(.title3.bold()); Spacer(); Text("\(dailyLeads.count) scheduled").font(.caption).foregroundStyle(.secondary) }
                if dailyLeads.isEmpty {
                    Label("No surveys or job starts today", systemImage: "calendar")
                        .foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 0) {
                        ForEach(dailyLeads) { lead in
                            NavigationLink { LeadDetailView(leadID: lead.id) } label: { mobileScheduleRow(lead) }.buttonStyle(.plain)
                            if lead.id != dailyLeads.last?.id { Divider().padding(.leading, 54) }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                }
                DisclosureGroup(isExpanded: $showingBusinessSummary) {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                        mobileMetric("Open leads", count([.newLead,.surveyBooked,.quotePreparing,.quoteSent]), "person.2.fill", .blue)
                        mobileMetric("Active jobs", count([.scheduled,.inProgress]), "hammer.fill", .orange)
                        mobileMetric("Awaiting payment", count([.waitingForPayment]), "clock.fill", .indigo)
                        mobileMetric("Due tasks", "\(appState.taskActions.filter{($0.dueDate ?? "9999") <= today}.count)", "checkmark.circle.fill", .purple)
                    }.padding(.top, 12)
                    VStack(spacing:0) {
                        ForEach(appState.leads.sorted{$0.updatedAt>$1.updatedAt}.prefix(3)){lead in
                            NavigationLink{LeadDetailView(leadID:lead.id)}label:{CompactRecentUpdate(lead:lead)}.buttonStyle(.plain)
                            if lead.id != appState.leads.sorted(by: {$0.updatedAt>$1.updatedAt}).prefix(3).last?.id { Divider().padding(.leading,34) }
                        }
                    }.padding(.horizontal, 12).background(.background, in: RoundedRectangle(cornerRadius: 12))
                } label: {
                    HStack(spacing:8) {
                        Image(systemName:"chart.line.uptrend.xyaxis").foregroundStyle(.orange)
                        Text("Business summary").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Metrics and recent changes").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary)).tint(.secondary)
            }.padding()
        }
        .background(Color(.systemGroupedBackground)).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingGeneralTask) { AddTaskView(task: $0) }
        .sheet(item: $editingJobTask) { EditJobTaskView(item: $0) }
    }
    private var greeting:String { let first=appState.currentUser?.name.split(separator:" ").first.map(String.init) ?? "team";return "Hello, \(first)" }
    private func count(_ stages:Set<LeadStage>)->String{"\(appState.leads.filter{stages.contains($0.stage)}.count)"}
    private func mobileMetric(_ title:String,_ value:String,_ icon:String,_ color:Color)->some View{VStack(alignment:.leading,spacing:10){Image(systemName:icon).foregroundStyle(color).font(.title3);Text(value).font(.title2.bold()).minimumScaleFactor(0.7);Text(title).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(15).background(.background,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(color.opacity(0.12)))}
    private func mobileScheduleRow(_ lead: Lead) -> some View {
        HStack(spacing: 12) {
            Image(systemName: lead.surveyDate == today ? "ruler" : "hammer.fill").foregroundStyle(lead.surveyDate == today ? .blue : .orange)
                .frame(width: 38, height: 38).background((lead.surveyDate == today ? Color.blue : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) { Text(lead.name).fontWeight(.semibold); Text("\(lead.jobType) · \(lead.surveyDate == today ? "Survey" : lead.stage.displayName)").font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(13)
    }
    private func complete(_ action: CompanyAction) {
        if let taskID = action.generalTaskID, let task = appState.generalTasks.first(where: { $0.id == taskID }) {
            Task { await appState.toggleGeneralTask(task) }
        } else if let leadID = action.leadID, let taskID = action.leadTaskID {
            Task { await appState.toggleLeadTask(leadID: leadID, taskID: taskID) }
        }
    }
    private func open(_ action: CompanyAction) {
        if let taskID = action.generalTaskID, let task = appState.generalTasks.first(where: { $0.id == taskID }) {
            editingGeneralTask = task
        } else if let leadID = action.leadID,
                  let lead = appState.leads.first(where: { $0.id == leadID }),
                  let taskID = action.leadTaskID,
                  let task = lead.tasks.first(where: { $0.id == taskID }) {
            editingJobTask = JobChecklistItem(lead: lead, task: task)
        } else if let leadID = action.leadID {
            appState.openLead(leadID)
        } else if action.kind == .timesheet {
            appState.selectedSection = .tasks
        }
    }
}

private struct CompactRecentUpdate:View{let lead:Lead;var body:some View{HStack(spacing:9){Circle().fill(Color.secondary.opacity(0.1)).frame(width:25,height:25).overlay(Text(lead.name.prefix(1)).font(.caption2.bold()).foregroundStyle(.secondary));VStack(alignment:.leading,spacing:1){Text(lead.name).font(.subheadline.weight(.medium));Text(lead.stage.displayName).font(.caption2).foregroundStyle(.secondary)};Spacer();Text(lead.jobRef).font(.caption2).foregroundStyle(.tertiary);Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.tertiary)}.frame(height:43)}}
private struct MobileCompanyActionRow: View {
    let action: CompanyAction
    let complete: () -> Void
    let open: () -> Void
    private var canComplete: Bool { action.kind == .generalTask || action.kind == .jobTask }
    var body: some View {
        HStack(spacing: 12) {
            if canComplete {
                Button(action: complete) {
                    Image(systemName: "circle").font(.title2).foregroundStyle(action.priority.tint)
                        .frame(width: 38, height: 38).background(action.priority.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel("Complete \(action.title)")
            } else {
                Image(systemName: actionIcon).font(.headline).foregroundStyle(action.priority.tint)
                    .frame(width: 38, height: 38).background(action.priority.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            Button(action: open) {
                HStack(spacing: 10) {
                    VStack(alignment:.leading,spacing:3){Text(action.title).fontWeight(.semibold).foregroundStyle(.primary);Text(action.detail).font(.caption).foregroundStyle(.secondary);Text(action.reason).font(.caption2.weight(.medium)).foregroundStyle(action.priority.tint)}
                    Spacer()
                    Image(systemName:"chevron.right").foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(action.title)")
        }.padding(13)
    }
    private var actionIcon: String { switch action.kind { case .survey: "calendar"; case .jobStart, .overdueJob: "hammer.fill"; case .quoteFollowUp: "phone.fill"; case .deposit, .balance: "sterlingsign.circle.fill"; case .timesheet: "clock.badge.exclamationmark"; case .generalTask: "checklist"; case .jobTask: "hammer" } }
}
#endif

#if os(macOS)
private struct MacDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var showingBusinessSummary = false
    private var today: String { SupabaseService.today }
    private var openLeads: [Lead] { appState.leads.filter { [.newLead, .surveyBooked, .quotePreparing, .quoteSent].contains($0.stage) } }
    private var upcoming: [Lead] { appState.leads.filter { ($0.surveyDate ?? $0.startDate ?? "") >= today }.sorted { ($0.surveyDate ?? $0.startDate ?? "9999") < ($1.surveyDate ?? $1.startDate ?? "9999") } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(greeting).font(.system(size: 29, weight: .bold))
                        Text("Your highest-priority work is ready.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(Date.now.formatted(date: .long, time: .omitted), systemImage: "calendar").foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    DashboardMetric("Open leads", "\(openLeads.count)", "person.2", .blue)
                    Divider().frame(height: 48)
                    DashboardMetric("Live jobs", "\(appState.leads.filter { $0.stage == .inProgress }.count)", "hammer", .orange)
                    Divider().frame(height: 48)
                    DashboardMetric("Awaiting payment", "\(appState.leads.filter { $0.stage == .waitingForPayment }.count)", "clock", .indigo)
                    Divider().frame(height: 48)
                    DashboardMetric("Due to collect", appState.leads.filter { ![.paid, .lost].contains($0.stage) }.reduce(0) { $0 + $1.balance }.formatted(.currency(code: "GBP").precision(.fractionLength(0))), "sterlingsign.circle", .green)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                HStack(alignment: .top, spacing: 16) {
                    MacAICommandCenter().frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        PanelHeader("Coming up", "", "calendar", .blue)
                        ForEach(upcoming.prefix(6)) { lead in
                            NavigationLink { LeadDetailView(leadID: lead.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) { Text(lead.name).fontWeight(.medium); Text(lead.jobType).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    VStack(alignment: .trailing) { Text(lead.surveyDate ?? lead.startDate ?? "").font(.caption.bold()); Text(lead.surveyDate != nil ? "Survey" : "Job starts").font(.caption2).foregroundStyle(.secondary) }
                                }.padding(.horizontal, 15).frame(height: 54).overlay(alignment: .bottom) { Divider() }
                            }.buttonStyle(.plain)
                        }
                        if upcoming.isEmpty { DashboardEmpty("No upcoming work", "Add survey and start dates to see them here.", "calendar.badge.plus") }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary)).frame(width: 350)
                }
                DisclosureGroup(isExpanded: $showingBusinessSummary) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ForEach([LeadStage.newLead, .surveyBooked, .quotePreparing, .quoteSent, .won, .scheduled, .inProgress]) { stage in
                                let rows = appState.leads.filter { $0.stage == stage }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Circle().fill(stageColor(stage)).frame(width: 8, height: 8); Text(stage.displayName).font(.caption).lineLimit(1); Spacer(); Text("\(rows.count)").font(.caption.bold()) }
                                    Text(rows.reduce(0) { $0 + $1.value }, format: .currency(code: "GBP").precision(.fractionLength(0))).font(.subheadline.bold())
                                }.padding(10).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        DashboardJobsMap()
                    }.padding(.top, 14)
                } label: {
                    HStack { Label("Business summary", systemImage: "chart.line.uptrend.xyaxis").font(.headline); Spacer(); Text("Pipeline health, map and recent context").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary)).tint(.secondary)
            }.padding(24)
        }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Today")
    }
    private var greeting: String { let hour = Calendar.current.component(.hour, from: .now); let word = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"; return "\(word), \(appState.currentUser?.name.split(separator: " ").first.map(String.init) ?? "team")" }
    private func stageColor(_ s: LeadStage) -> Color { switch s { case .newLead: .blue; case .surveyBooked: .orange; case .quotePreparing, .quoteSent: .purple; case .won: .green; case .scheduled: .teal; case .inProgress: .cyan; default: .gray } }
}
private struct DashboardMetric:View{let title,value,icon:String;let tint:Color;init(_ title:String,_ value:String,_ icon:String,_ tint:Color){self.title=title;self.value=value;self.icon=icon;self.tint=tint};var body:some View{HStack(spacing:13){Image(systemName:icon).font(.title2).foregroundStyle(tint).frame(width:43,height:43).background(tint.opacity(0.1),in:RoundedRectangle(cornerRadius:9));VStack(alignment:.leading){Text(value).font(.title2.bold());Text(title).font(.caption).foregroundStyle(.secondary)}}.padding(15).frame(maxWidth:.infinity,alignment:.leading)}}
private struct MacAICommandCenter: View {
    @Environment(AppState.self) private var appState
    @State private var editingGeneralTask: GeneralTask?
    @State private var editingJobTask: JobChecklistItem?
    private var actions: [CompanyAction] {
        let ranked = appState.companyActions.filter { $0.priority >= .urgent }
        var seen = Set<String>()
        return Array(ranked.filter { action in
            let key = action.leadID.map { "lead-\($0)" } ?? action.generalTaskID.map { "task-\($0)" } ?? action.id
            return seen.insert(key).inserted
        }.prefix(6))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "bolt.fill").font(.title3).foregroundStyle(.orange).frame(width: 38, height: 38).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) { Text("Needs attention").font(.headline); Text("The most important work is ranked first.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text("\(actions.count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                Button { appState.openAssistant(with: "Create my daily company plan. Rank what I need to do first, identify risks, and suggest the next best actions.") } label: { Label("Ask ProLine", systemImage: "sparkles") }.buttonStyle(.bordered)
            }.padding(16).overlay(alignment: .bottom) { Divider() }
            if actions.isEmpty { DashboardEmpty("You’re clear for now", "New priorities will appear here as work changes.", "checkmark.seal") }
            ForEach(actions) { action in
                HStack(spacing: 12) {
                    Image(systemName: icon(action.kind)).foregroundStyle(action.priority.tint).frame(width: 34, height: 34).background(action.priority.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) { Text(action.title).fontWeight(.semibold); Text(action.detail).font(.caption).foregroundStyle(.secondary); Text(action.reason).font(.caption2.weight(.medium)).foregroundStyle(action.priority.tint) }
                    Spacer()
                    actionControl(action)
                }.padding(.horizontal, 16).padding(.vertical, 10).overlay(alignment: .bottom) { Divider().padding(.leading, 62) }
            }
        }.background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25)))
            .sheet(item: $editingGeneralTask) { AddTaskView(task: $0) }
            .sheet(item: $editingJobTask) { EditJobTaskView(item: $0) }
    }
    @ViewBuilder private func actionControl(_ action: CompanyAction) -> some View {
        if let taskID = action.generalTaskID, let task = appState.generalTasks.first(where: { $0.id == taskID }) {
            HStack { Button("Complete") { Task { await appState.toggleGeneralTask(task) } }; Button("Open") { editingGeneralTask = task } }.buttonStyle(.bordered)
        } else if let leadID = action.leadID, let taskID = action.leadTaskID,
                  let lead = appState.leads.first(where: { $0.id == leadID }),
                  let task = lead.tasks.first(where: { $0.id == taskID }) {
            HStack { Button("Complete") { Task { await appState.toggleLeadTask(leadID: leadID, taskID: taskID) } }; Button("Open") { editingJobTask = JobChecklistItem(lead: lead, task: task) } }.buttonStyle(.bordered)
        } else if let leadID = action.leadID {
            NavigationLink { LeadDetailView(leadID: leadID) } label: { Label("Open", systemImage: "arrow.right") }.buttonStyle(.bordered)
        } else {
            Button("Ask AI") { appState.openAssistant(with: "Help me resolve this operational issue: \(action.title) — \(action.detail).") }.buttonStyle(.bordered)
        }
    }
    private func icon(_ kind: CompanyActionKind) -> String { switch kind { case .generalTask: "checklist"; case .jobTask: "hammer"; case .survey: "calendar"; case .jobStart: "hammer.fill"; case .overdueJob: "exclamationmark.triangle.fill"; case .quoteFollowUp: "doc.text"; case .deposit, .balance: "sterlingsign.circle"; case .timesheet: "clock.badge.exclamationmark" } }
}
private struct PanelHeader:View{let title,count,icon:String;let tint:Color;init(_ title:String,_ count:String,_ icon:String,_ tint:Color){self.title=title;self.count=count;self.icon=icon;self.tint=tint};var body:some View{HStack{Label(title,systemImage:icon).font(.headline).foregroundStyle(tint);Spacer();if !count.isEmpty{Text(count).font(.caption.bold()).padding(.horizontal,7).padding(.vertical,3).background(.quaternary,in:Capsule())}}.padding(15).overlay(alignment:.bottom){Divider()}}}
struct DashboardEmpty:View{let title,detail,icon:String;init(_ title:String,_ detail:String,_ icon:String){self.title=title;self.detail=detail;self.icon=icon};var body:some View{VStack(spacing:6){Image(systemName:icon).font(.title).foregroundStyle(.secondary);Text(title).fontWeight(.semibold);Text(detail).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity).padding(28)}}
#endif

struct JobChecklistItem: Identifiable {
    let lead: Lead
    let task: CRMTask
    var id: String { "\(lead.id)-\(task.id)" }
}

struct TasksView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAdd = false
    @State private var editingTask: GeneralTask?
    @State private var editingJobTask: JobChecklistItem?
    @State private var search = ""
    @State private var scope = "Open"
    @State private var priority = "All priorities"
    @State private var expandedJobIDs:Set<String> = []
    private var today:String{SupabaseService.today}
    private var mine:[GeneralTask]{appState.visibleGeneralTasks.filter{$0.category != "Fleet Vehicle" && FleetTaskPolicy.shouldShowInTaskList($0) && NotificationScope.includes($0,for:appState.currentUser)}}
    private var rows:[GeneralTask]{mine.filter{task in
        let text=search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.category.localizedCaseInsensitiveContains(search)
        let state=switch scope{case "Today":!task.completed && task.dueDate==today;case "Overdue":!task.completed && (task.dueDate ?? "9999") < today;case "Completed":task.completed;case "All":true;case "Mine":!task.completed && isMyTask(task);default:!task.completed}
        return text && state && (priority=="All priorities" || task.priority.capitalized==priority)
    }.sorted{($0.dueDate ?? "9999",$0.priority)==($1.dueDate ?? "9999",$1.priority) ? $0.title<$1.title : ($0.dueDate ?? "9999")<($1.dueDate ?? "9999")}}
    private var checklistItems:[JobChecklistItem]{appState.leads
        .filter { ![LeadStage.completed, .lost].contains($0.stage) }
        .flatMap{lead in lead.tasks.map{JobChecklistItem(lead:lead,task:$0)}}}
    private var checklistRows:[JobChecklistItem]{checklistItems.filter{item in
        let matchesSearch=search.isEmpty || item.task.title.localizedCaseInsensitiveContains(search) || item.lead.name.localizedCaseInsensitiveContains(search) || item.lead.jobRef.localizedCaseInsensitiveContains(search)
        let matchesState=switch scope{case "Today":!item.task.completed && item.task.dueDate==today;case "Overdue":!item.task.completed && (item.task.dueDate ?? "9999")<today;case "Completed":item.task.completed;case "All":true;case "Mine":!item.task.completed && LeadOwnership.isAssigned(item.lead,to:appState.currentUser);default:!item.task.completed}
        return matchesSearch && matchesState && (priority=="All priorities" || priority=="Medium")
    }.sorted{($0.task.dueDate ?? "9999",$0.lead.name)<($1.task.dueDate ?? "9999",$1.lead.name)}}
    private var visibleCount:Int{rows.count+checklistRows.count}
    private var jobTaskGroups:[JobTaskGroup]{appState.leads.compactMap{lead in
        let items=checklistRows.filter{$0.lead.id==lead.id}
        return items.isEmpty ? nil:JobTaskGroup(lead:lead,items:items)
    }.sorted {
        let left = $0.items.first(where: { !$0.task.completed })?.task.dueDate ?? "9999-12-31"
        let right = $1.items.first(where: { !$0.task.completed })?.task.dueDate ?? "9999-12-31"
        return left == right ? $0.lead.name.localizedCaseInsensitiveCompare($1.lead.name) == .orderedAscending : left < right
    }}
    var body: some View {
        #if os(macOS)
        VStack(alignment:.leading,spacing:0){
            HStack{VStack(alignment:.leading,spacing:3){Text("Tasks").font(.system(size:29,weight:.bold));Text("Keep every customer promise and job action on track.").foregroundStyle(.secondary)};Spacer();Button{showingAdd=true}label:{Label("New task",systemImage:"plus").foregroundStyle(.white).padding(.horizontal,16).frame(height:38).background(Color(red:1,green:0.29,blue:0.04),in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)}.padding(.horizontal,24).padding(.top,18)
            HStack(spacing:12){TaskMetric(title:"Open",value:mine.filter{!$0.completed}.count+checklistItems.filter{!$0.task.completed}.count,icon:"checklist",tint:.blue);TaskMetric(title:"Due today",value:mine.filter{!$0.completed && $0.dueDate==today}.count+checklistItems.filter{!$0.task.completed && $0.task.dueDate==today}.count,icon:"calendar",tint:.orange);TaskMetric(title:"Overdue",value:mine.filter{!$0.completed && ($0.dueDate ?? "9999")<today}.count+checklistItems.filter{!$0.task.completed && ($0.task.dueDate ?? "9999")<today}.count,icon:"exclamationmark.triangle",tint:.red);TaskMetric(title:"Job checklists",value:checklistItems.filter{!$0.task.completed}.count,icon:"hammer",tint:.purple)}.padding(.horizontal,24).padding(.top,16)
            HStack(spacing:8){HStack{Image(systemName:"magnifyingglass");TextField("Search tasks…",text:$search)}.padding(.horizontal,10).frame(width:280,height:36).background(.background,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).stroke(.quaternary));Picker("",selection:$scope){ForEach(["Open","Today","Overdue","Completed"],id:\.self){Text($0)}}.pickerStyle(.segmented).frame(width:330);Menu(priority){Button("All priorities"){priority="All priorities"};ForEach(["High","Medium","Low"],id:\.self){p in Button(p){priority=p}}};Spacer();Text("\(visibleCount) tasks").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,24).padding(.vertical,16)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:14) {
                    if !rows.isEmpty {
                        VStack(spacing:0) {
                            HStack{Label("All general tasks",systemImage:"checklist").font(.headline);Spacer();Text("\(rows.count)").font(.caption.bold()).foregroundStyle(.secondary)}.padding(16)
                            Divider()
                            ForEach(rows) { task in
                                MacGeneralTaskCardRow(task:task,userName:owner(task),action:{Task{await appState.toggleGeneralTask(task)}},onEdit:{editingTask=task},onDelete:{Task{await appState.deleteGeneralTask(task)}})
                                if task.id != rows.last?.id { Divider().padding(.leading,54) }
                            }
                        }.background(.background,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(.quaternary))
                    }
                    ForEach(jobTaskGroups) { group in
                        MacJobTaskCard(group:group,isExpanded:expandedJobIDs.contains(group.id),toggleExpanded:{withAnimation(.easeInOut(duration:0.2)){if expandedJobIDs.contains(group.id){expandedJobIDs.remove(group.id)}else{expandedJobIDs.insert(group.id)}}},toggleTask:{taskID in Task{await appState.toggleLeadTask(leadID:group.lead.id,taskID:taskID)}},editTask:{task in editingJobTask=JobChecklistItem(lead:group.lead,task:task)})
                    }
                }.padding(.horizontal,24).padding(.bottom,24)
            }.overlay { if visibleCount == 0 { ContentUnavailableView("No tasks here",systemImage:"checkmark.circle",description:Text("Try another filter or create a new task.")) } }
        }.background(Color(nsColor:.windowBackgroundColor)).navigationTitle("Tasks").onAppear{if expandedJobIDs.isEmpty{expandedJobIDs=Set(jobTaskGroups.prefix(3).map(\.id))}}.sheet(isPresented:$showingAdd){AddTaskView()}.sheet(item:$editingTask){AddTaskView(task:$0)}.sheet(item:$editingJobTask){EditJobTaskView(item:$0)}
        #else
        ScrollView {
            LazyVStack(alignment:.leading,spacing:14) {
                HStack(alignment:.firstTextBaseline) {
                    VStack(alignment:.leading,spacing:3) {
                        Text("\(visibleCount) tasks \(scope == "Completed" ? "completed" : "pending")").font(.title3.bold())
                        Text("\(rows.count) general · \(checklistRows.count) job-related").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Picker("Task view",selection:$scope) {
                    Text("To Do").tag("Open")
                    Text("Mine").tag("Mine")
                    Text("Done").tag("Completed")
                    Text("All").tag("All")
                }.pickerStyle(.segmented)

                if !rows.isEmpty {
                    VStack(spacing:0) {
                        HStack { Label("General tasks",systemImage:"checklist").font(.headline);Spacer();Text("\(rows.count)").font(.caption.bold()).foregroundStyle(.secondary) }.padding(15)
                        Divider()
                        ForEach(rows) { task in
                            MobileGeneralTaskRow(task:task,owner:owner(task),toggle:{Task{await appState.toggleGeneralTask(task)}},edit:{editingTask=task})
                            if task.id != rows.last?.id { Divider().padding(.leading,50) }
                        }
                    }.background(.background,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.quaternary)).shadow(color:.black.opacity(0.035),radius:8,y:3)
                }

                ForEach(jobTaskGroups) { group in
                    MobileJobTaskCard(group:group,isExpanded:expandedJobIDs.contains(group.id),toggleExpanded:{
                        withAnimation(.easeInOut(duration:0.2)){if expandedJobIDs.contains(group.id){expandedJobIDs.remove(group.id)}else{expandedJobIDs.insert(group.id)}}
                    },toggleTask:{taskID in Task{await appState.toggleLeadTask(leadID:group.lead.id,taskID:taskID)}},editTask:{task in editingJobTask=JobChecklistItem(lead:group.lead,task:task)})
                }
                if visibleCount == 0 { ContentUnavailableView("No tasks here",systemImage:"checkmark.circle",description:Text("Try another view or add a general task.")) .padding(.top,60) }
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground)).navigationTitle("Tasks").searchable(text:$search,prompt:"Search tasks")
        .toolbar {
            ToolbarItemGroup(placement:.topBarTrailing) {
                if appState.isAdmin { Button { Task { await appState.startTaskLiveActivity() } } label: { Image(systemName:"livephoto") }.accessibilityLabel("Start task Live Activity") }
                Button{showingAdd=true}label:{Image(systemName:"plus")}.accessibilityLabel("Add general task")
            }
        }
        .onAppear { if expandedJobIDs.isEmpty { expandedJobIDs = Set(jobTaskGroups.prefix(2).map(\.id)) } }
        .sheet(isPresented:$showingAdd){AddTaskView()}.sheet(item:$editingTask){AddTaskView(task:$0)}.sheet(item:$editingJobTask){EditJobTaskView(item:$0)}
        #endif
    }
    private func isMyTask(_ task:GeneralTask)->Bool{guard let user=appState.currentUser else{return false};return task.assignedTo.contains(user.id)}
    private func owner(_ task:GeneralTask)->String{guard let id=task.assignedTo.first else{return appState.currentUser?.name ?? "Me"};return appState.users.first{$0.id==id}?.name ?? "Team member"}
}

private struct JobTaskGroup:Identifiable{let lead:Lead;let items:[JobChecklistItem];var id:String{lead.id}}

#if os(iOS)
private struct MobileGeneralTaskRow:View{
    let task:GeneralTask;let owner:String;let toggle:()->Void;let edit:()->Void
    var body:some View{HStack(spacing:12){Button(action:toggle){Image(systemName:task.completed ? "checkmark.circle.fill":"circle").font(.title2).foregroundStyle(task.completed ? .green:.secondary)}.buttonStyle(.plain);Button(action:edit){VStack(alignment:.leading,spacing:3){Text(task.title).fontWeight(.medium).foregroundStyle(.primary).strikethrough(task.completed);Text([task.category,task.dueDate,owner].compactMap{$0}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)}.padding(.horizontal,15).padding(.vertical,12)}
}

private struct MobileJobTaskCard:View{
    @Environment(AppState.self) private var appState
    let group:JobTaskGroup;let isExpanded:Bool;let toggleExpanded:()->Void;let toggleTask:(String)->Void;let editTask:(CRMTask)->Void
    private var completed:Int{group.items.filter(\.task.completed).count}
    private var progress:Double{group.items.isEmpty ? 0:Double(completed)/Double(group.items.count)}
    var body:some View{VStack(spacing:0){Button(action:toggleExpanded){HStack(spacing:12){Text(group.lead.name.prefix(1)).font(.headline).foregroundStyle(.orange).frame(width:42,height:42).background(Color.orange.opacity(0.13),in:RoundedRectangle(cornerRadius:12));VStack(alignment:.leading,spacing:6){HStack(spacing:7){Text(group.lead.name).font(.headline).foregroundStyle(.primary).lineLimit(1);Text(group.lead.jobType).font(.caption).foregroundStyle(.secondary).padding(.horizontal,7).padding(.vertical,3).background(Color.secondary.opacity(0.09),in:Capsule()).lineLimit(1)};HStack(spacing:9){ProgressView(value:progress).tint(.orange).frame(maxWidth:125);Text("\(completed)/\(group.items.count) done").font(.caption).foregroundStyle(.secondary)}};Spacer();Text(isExpanded ? "Close":"Open").font(.subheadline.bold()).foregroundStyle(.orange);Image(systemName:isExpanded ? "chevron.up":"chevron.down").font(.caption.bold()).foregroundStyle(.secondary)}.padding(15).contentShape(Rectangle())}.buttonStyle(.plain);if isExpanded{Divider();ForEach(group.items){item in VStack(spacing:0){HStack(spacing:12){Button{toggleTask(item.task.id)}label:{Image(systemName:item.task.completed ? "checkmark.circle.fill":"circle").font(.title2).foregroundStyle(item.task.completed ? .green:.secondary)}.buttonStyle(.plain);Button{editTask(item.task)}label:{VStack(alignment:.leading,spacing:4){Text(item.task.title).foregroundStyle(.primary).strikethrough(item.task.completed);HStack(spacing:8){if let due=item.task.dueDate{Label(due,systemImage:"calendar").foregroundStyle(!item.task.completed && due<SupabaseService.today ? .red:.secondary)};Text((item.task.priority ?? "medium").capitalized).foregroundStyle(item.task.priority == "high" ? .red:.secondary);if let steps=item.task.subtasks,!steps.isEmpty{Text("\(steps.filter(\.completed).count)/\(steps.count) steps").foregroundStyle(.orange)}}.font(.caption2);if let notes=item.task.notes,!notes.isEmpty{Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)}}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain);Button{editTask(item.task)}label:{Image(systemName:"pencil.circle").font(.title3)}.buttonStyle(.plain).foregroundStyle(.orange).accessibilityLabel("Edit task")}.padding(.horizontal,17).padding(.vertical,12);if let steps=item.task.subtasks,!steps.isEmpty{VStack(spacing:0){ForEach(steps){step in Button{Task{await appState.toggleLeadSubtask(leadID:group.lead.id,taskID:item.task.id,subtaskID:step.id)}}label:{HStack{Image(systemName:step.completed ? "checkmark.circle.fill":"circle").foregroundStyle(step.completed ? .green:.orange);Text(step.title).font(.subheadline).foregroundStyle(.primary).strikethrough(step.completed);Spacer()}.padding(.leading,52).padding(.trailing,17).frame(minHeight:40)}.buttonStyle(.plain)}}};if item.id != group.items.last?.id{Divider().padding(.leading,52)}}};Divider();NavigationLink{if appState.isAdmin{LeadDetailView(leadID:group.lead.id)}else{WorkerJobDetailView(leadID:group.lead.id)}}label:{Label("Open job",systemImage:"arrow.right.circle").font(.subheadline.bold()).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,17).padding(.vertical,12)}}}.background(.background,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.quaternary)).shadow(color:.black.opacity(0.035),radius:8,y:3)}
}
#endif

#if os(macOS)
private struct TaskMetric:View{let title:String;let value:Int;let icon:String;let tint:Color;var body:some View{HStack(spacing:13){Image(systemName:icon).font(.title2).foregroundStyle(tint).frame(width:42,height:42).background(tint.opacity(0.1),in:RoundedRectangle(cornerRadius:9));VStack(alignment:.leading){Text("\(value)").font(.title2.bold());Text(title).font(.caption).foregroundStyle(.secondary)}}.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.quaternary))}}
private struct MacGeneralTaskCardRow:View{let task:GeneralTask;let userName:String;let action:()->Void;let onEdit:()->Void;let onDelete:()->Void;@State private var confirmingDelete=false;private var tint:Color{task.priority=="high" ? .red:task.priority=="low" ? .green:.orange};var body:some View{HStack(spacing:13){Button(action:action){Image(systemName:task.completed ? "checkmark.circle.fill":"circle").font(.title2).foregroundStyle(task.completed ? .green:.secondary)}.buttonStyle(.plain);Button(action:onEdit){VStack(alignment:.leading,spacing:3){Text(task.title).fontWeight(.medium).foregroundStyle(.primary).strikethrough(task.completed);Text([task.category,task.dueDate,userName].compactMap{$0}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain);Text(task.priority.capitalized).font(.caption.bold()).foregroundStyle(tint).padding(.horizontal,8).padding(.vertical,4).background(tint.opacity(0.1),in:Capsule());Menu{Button("Edit",action:onEdit);Button(task.completed ? "Mark incomplete":"Mark complete",action:action);Divider();Button("Delete",role:.destructive){confirmingDelete=true}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton)}.padding(.horizontal,16).frame(minHeight:62).confirmationDialog("Delete this task?",isPresented:$confirmingDelete){Button("Delete",role:.destructive,action:onDelete)}}}
private struct MacJobTaskCard:View{@Environment(AppState.self) private var appState;let group:JobTaskGroup;let isExpanded:Bool;let toggleExpanded:()->Void;let toggleTask:(String)->Void;let editTask:(CRMTask)->Void;private var completed:Int{group.items.filter(\.task.completed).count};private var progress:Double{group.items.isEmpty ? 0:Double(completed)/Double(group.items.count)};var body:some View{VStack(spacing:0){Button(action:toggleExpanded){HStack(spacing:14){Text(group.lead.name.prefix(1)).font(.title3.bold()).foregroundStyle(.orange).frame(width:46,height:46).background(Color.orange.opacity(0.13),in:RoundedRectangle(cornerRadius:11));VStack(alignment:.leading,spacing:7){HStack{Text(group.lead.name).font(.headline).foregroundStyle(.primary);Text(group.lead.jobType).font(.caption).foregroundStyle(.secondary).padding(.horizontal,8).padding(.vertical,3).background(Color.secondary.opacity(0.09),in:Capsule());Text(group.lead.jobRef).font(.caption).foregroundStyle(.secondary)};HStack(spacing:10){ProgressView(value:progress).tint(.orange).frame(width:180);Text("\(completed)/\(group.items.count) done").font(.caption).foregroundStyle(.secondary)}};Spacer();Text(isExpanded ? "Close":"Open").font(.subheadline.bold()).foregroundStyle(.orange);Image(systemName:isExpanded ? "chevron.up":"chevron.down").font(.caption.bold()).foregroundStyle(.secondary)}.padding(16).contentShape(Rectangle())}.buttonStyle(.plain);if isExpanded{Divider();ForEach(group.items){item in VStack(spacing:0){HStack(spacing:13){Button{toggleTask(item.task.id)}label:{Image(systemName:item.task.completed ? "checkmark.circle.fill":"circle").font(.title2).foregroundStyle(item.task.completed ? .green:.secondary)}.buttonStyle(.plain);Button{editTask(item.task)}label:{VStack(alignment:.leading,spacing:3){Text(item.task.title).fontWeight(.medium).foregroundStyle(.primary).strikethrough(item.task.completed);HStack{if let due=item.task.dueDate{Label(due,systemImage:"calendar").foregroundStyle(!item.task.completed && due<SupabaseService.today ? .red:.secondary)};Text((item.task.priority ?? "medium").capitalized);if let steps=item.task.subtasks,!steps.isEmpty{Text("\(steps.filter(\.completed).count)/\(steps.count) steps").foregroundStyle(.orange)}}.font(.caption).foregroundStyle(.secondary);if let notes=item.task.notes,!notes.isEmpty{Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)}}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain);Button("Edit"){editTask(item.task)}.buttonStyle(.bordered)}.padding(.horizontal,18).frame(minHeight:68);if let steps=item.task.subtasks,!steps.isEmpty{ForEach(steps){step in Button{Task{await appState.toggleLeadSubtask(leadID:group.lead.id,taskID:item.task.id,subtaskID:step.id)}}label:{HStack{Image(systemName:step.completed ? "checkmark.circle.fill":"circle").foregroundStyle(step.completed ? .green:.orange);Text(step.title).foregroundStyle(.primary).strikethrough(step.completed);Spacer()}.padding(.leading,58).padding(.trailing,18).frame(height:38)}.buttonStyle(.plain)}};if item.id != group.items.last?.id{Divider().padding(.leading,56)}}};Divider();NavigationLink{if appState.isAdmin{LeadDetailView(leadID:group.lead.id)}else{WorkerJobDetailView(leadID:group.lead.id)}}label:{Label("Open job",systemImage:"arrow.right.circle").font(.subheadline.bold()).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,18).padding(.vertical,12)}}}.background(.background,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(.quaternary)).shadow(color:.black.opacity(0.025),radius:6,y:2)}}
#endif

private struct EditJobTaskView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let item: JobChecklistItem
    @State private var title: String
    @State private var notes: String
    @State private var priority: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var subtasks: [CRMSubtask]
    @State private var newSubtask = ""
    @State private var isSaving = false

    init(item: JobChecklistItem) {
        self.item = item
        _title = State(initialValue: item.task.title)
        _notes = State(initialValue: item.task.notes ?? "")
        _priority = State(initialValue: item.task.priority ?? "medium")
        _hasDueDate = State(initialValue: item.task.dueDate != nil)
        _dueDate = State(initialValue: item.task.dueDate.flatMap { SupabaseService.date(from: $0) } ?? .now)
        _subtasks = State(initialValue: item.task.subtasks ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Action required") {
                    TextField("What needs doing?", text: $title)
                    TextField("Details, access or expected result", text: $notes, axis: .vertical).lineLimit(3...7)
                }
                Section("Planning") {
                    Picker("Priority", selection: $priority) { Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high") }
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                }
                Section("Subtasks") {
                    ForEach($subtasks) { $subtask in
                        HStack {
                            Button { subtask.completed.toggle() } label: { Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(subtask.completed ? .green : .orange) }.buttonStyle(.plain)
                            TextField("Step", text: $subtask.title)
                            Button(role: .destructive) { subtasks.removeAll { $0.id == subtask.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add a step", text: $newSubtask).onSubmit { addSubtask() }
                        Button("Add") { addSubtask() }.disabled(newSubtask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Related job") { LabeledContent("Customer", value: item.lead.name); LabeledContent("Reference", value: item.lead.jobRef) }
            }
            .disabled(isSaving)
            .navigationTitle("Edit job task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button { save() } label: { if isSaving { ProgressView() } else { Text("Save") } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving) }
            }
        }.frame(minWidth: 420, minHeight: 450)
    }

    private func save() {
        let due = hasDueDate ? SupabaseService.localDay(for: dueDate) : nil
        Task {
            isSaving = true; defer { isSaving = false }
            if await appState.updateLeadTask(leadID: item.lead.id, taskID: item.task.id, title: title, dueDate: due, priority: priority, notes: notes, subtasks: subtasks) { dismiss() }
        }
    }
    private func addSubtask() {
        let clean = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        subtasks.append(CRMSubtask(id: UUID().uuidString, title: clean, completed: false)); newSubtask = ""
    }
}

private struct AddTaskView: View {
    @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss
    let task:GeneralTask?
    @State private var title:String;@State private var dueDate:Date;@State private var hasDate:Bool;@State private var priority:String;@State private var category:String;@State private var assignee:String;@State private var notes:String;@State private var isSaving=false
    init(task:GeneralTask?=nil){self.task=task;_title=State(initialValue:task?.title ?? "");_dueDate=State(initialValue:task?.dueDate.flatMap{SupabaseService.date(from:$0)} ?? .now);_hasDate=State(initialValue:task?.dueDate != nil || task == nil);_priority=State(initialValue:task?.priority ?? "medium");_category=State(initialValue:task?.category ?? "General");_assignee=State(initialValue:task?.assignedTo.first ?? "");_notes=State(initialValue:task?.notes ?? "")}
    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $title)
                TextField("Category", text: $category)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                Picker("Assigned to", selection: $assignee) {
                    if appState.isAdmin {
                        Text("Me").tag("")
                        ForEach(appState.users) { Text($0.name).tag($0.id) }
                    } else if let current = appState.currentUser {
                        Text("Me").tag(current.id)
                    }
                }
                Picker("Priority", selection: $priority) {
                    Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
                }
                Toggle("Due date", isOn: $hasDate)
                if hasDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
            }
            .disabled(isSaving)
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { if isSaving { ProgressView() } else { Text("Save") } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 440)
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            let saved: Bool
            if var changed = task {
                changed.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                changed.category = category
                changed.notes = notes.isEmpty ? nil : notes
                changed.priority = priority
                changed.dueDate = hasDate ? PayrollMath.key(dueDate) : nil
                changed.assignedTo = assignee.isEmpty ? (appState.currentUser.map { [$0.id] } ?? []) : [assignee]
                saved = await appState.saveGeneralTask(changed)
            } else {
                saved = await appState.addGeneralTask(title: title, dueDate: hasDate ? PayrollMath.key(dueDate) : nil, priority: priority, category: category, assignedTo: assignee.isEmpty ? nil : [assignee], notes: notes.isEmpty ? nil : notes)
            }
            if saved { dismiss() }
        }
    }
}

struct EmailWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var scanning = false
    @State private var scanSummary: String?
    private var emailTasks: [GeneralTask] {
        appState.visibleGeneralTasks.filter { $0.category.caseInsensitiveCompare("Email") == .orderedSame }
            .sorted { ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Text("Gmail assistant").font(.largeTitle.bold()); Text("Important messages, follow-ups and prepared Gmail drafts.").foregroundStyle(.secondary) }
                    Spacer()
                    Button { scan() } label: { if scanning { ProgressView() } else { Label("Scan now", systemImage: "arrow.clockwise") } }.buttonStyle(.borderedProminent).tint(.orange).disabled(scanning || appState.gmailConnectionStatus?.connected != true)
                }
                HStack(spacing: 12) {
                    emailMetric(appState.gmailConnectionStatus?.connected == true ? "Connected" : "Not connected", "Gmail", appState.gmailConnectionStatus?.connected == true ? .green : .orange)
                    emailMetric("\(emailTasks.filter { !$0.completed }.count)", "Open email actions", .blue)
                    emailMetric(appState.gmailConnectionStatus?.lastScannedAt.map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") } ?? "Never", "Last scan", .gray)
                }
                if let address = appState.gmailConnectionStatus?.gmailAddress { Label(address, systemImage: "envelope.fill").foregroundStyle(.secondary) }
                if let scanSummary { Label(scanSummary, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if appState.gmailConnectionStatus?.connected != true {
                    Button("Connect Gmail") { Task { if let url = await appState.gmailAuthorizationURL() { openURL(url) } } }.buttonStyle(.borderedProminent)
                }
                Text("Email actions").font(.title2.bold())
                if emailTasks.isEmpty {
                    ContentUnavailableView("No email actions yet", systemImage: "envelope.open", description: Text("Scan Gmail now. Important customer emails will appear here and in Tasks; suggested replies stay in Gmail Drafts."))
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVStack(spacing: 10) { ForEach(emailTasks) { task in
                        HStack(spacing: 13) {
                            Button { Task { await appState.toggleGeneralTask(task) } } label: { Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(task.completed ? .green : .orange) }.buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) { Text(task.title).fontWeight(.semibold).strikethrough(task.completed); Text(task.notes ?? "Created from Gmail").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            Spacer(); if let due = task.dueDate { Text(due).font(.caption.bold()).foregroundStyle(!task.completed && due < SupabaseService.today ? .red : .secondary) }
                        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    } }
                }
            }.padding(24)
        }.navigationTitle("Email").task { await appState.refreshGmailConnectionStatus() }
    }
    private func scan() { scanning = true; Task { let count = await appState.scanGmailNow(); await appState.refreshGmailConnectionStatus(); scanSummary = count.map { "Scan complete · \($0) new action\($0 == 1 ? "" : "s")" }; scanning = false } }
    private func emailMetric(_ value: String, _ title: String, _ tint: Color) -> some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.headline).foregroundStyle(tint); Text(title).font(.caption).foregroundStyle(.secondary) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)) }
}

struct CRMCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var selected = Date()
    private var key: String { PayrollMath.key(selected) }
    var body: some View {
        #if os(macOS)
        MacCalendarView(selected:$selected)
        #else
        MobileScheduleCalendar(selected: $selected).navigationTitle("Calendar")
        #endif
    }
}

#if os(iOS)
private struct MobileScheduleCalendar: View {
    @Environment(AppState.self) private var appState
    @Binding var selected: Date
    private var days: [Date] { (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) } }
    private var allUpcoming: [(Date, Lead, Bool)] { days.flatMap { day in events(day).map { (day, $0, $0.surveyDate == PayrollMath.key(day)) } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Label("Survey", systemImage: "circle.fill").foregroundStyle(.orange); Label("Booked", systemImage: "circle.fill").foregroundStyle(.blue); Label("In progress", systemImage: "circle.fill").foregroundStyle(.green); Spacer(); DatePicker("Choose date", selection: $selected, displayedComponents: .date).labelsHidden() }.font(.caption.bold())
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 9) { ForEach(days, id: \.self) { day in dayButton(day) } } }
                Text("Next 14 days").font(.title2.bold())
                if allUpcoming.isEmpty { ContentUnavailableView("Nothing booked", systemImage: "calendar", description: Text("Scheduled surveys and jobs will appear here without needing to select each day.")) }
                ForEach(Array(allUpcoming.enumerated()), id: \.offset) { _, item in
                    NavigationLink { LeadDetailView(leadID: item.1.id) } label: { HStack(spacing: 12) { RoundedRectangle(cornerRadius: 3).fill(item.2 ? Color.orange : (item.1.stage == .inProgress ? Color.green : Color.blue)).frame(width: 5, height: 48); VStack(alignment: .leading, spacing: 3) { Text(item.1.name).fontWeight(.semibold); Text("\(item.0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(item.2 ? "Survey" : item.1.jobType)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(item.1.jobRef).font(.caption2.bold()).foregroundStyle(.secondary); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(13).background(.background, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(.quaternary)) }.buttonStyle(.plain)
                }
            }.padding()
        }.background(Color(.systemGroupedBackground))
    }
    private func events(_ day: Date) -> [Lead] { let key = PayrollMath.key(day); return appState.leads.filter { $0.surveyDate == key || (($0.startDate ?? "9999") <= key && ($0.endDate ?? $0.startDate ?? "0000") >= key) } }
    private func dayButton(_ day: Date) -> some View { let rows = events(day); let isSelected = Calendar.current.isDate(day, inSameDayAs: selected); return Button { selected = day } label: { VStack(spacing: 6) { Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption.bold()); Text("\(Calendar.current.component(.day, from: day))").font(.headline); HStack(spacing: 3) { ForEach(Array(rows.prefix(3).enumerated()), id: \.offset) { _, lead in Circle().fill(lead.surveyDate == PayrollMath.key(day) ? Color.orange : (lead.stage == .inProgress ? Color.green : Color.blue)).frame(width: 6, height: 6) } } }.frame(width: 48, height: 68).background(isSelected ? Color.orange.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(isSelected ? Color.orange : Color.clear, lineWidth: 1.5)) }.buttonStyle(.plain) }
}
#endif

#if os(macOS)
private struct MacCalendarView:View{
    @Environment(AppState.self)private var appState;@Binding var selected:Date;@State private var month=Date()
    private let calendar=Calendar.current
    private var days:[Date?]{guard let range=calendar.range(of:.day,in:.month,for:month),let first=calendar.date(from:calendar.dateComponents([.year,.month],from:month)) else{return []};let offset=(calendar.component(.weekday,from:first)+5)%7;return Array(repeating:nil,count:offset)+range.compactMap{calendar.date(byAdding:.day,value:$0-1,to:first)}}
    var body:some View{VStack(alignment:.leading,spacing:0){HStack{VStack(alignment:.leading,spacing:3){Text("Calendar").font(.system(size:29,weight:.bold));Text("Surveys, starts and live roofing work in one place.").foregroundStyle(.secondary)};Spacer();Button{month=calendar.date(byAdding:.month,value:-1,to:month)!}label:{Image(systemName:"chevron.left")};Button("Today"){month = .now; selected = .now};Button{month=calendar.date(byAdding:.month,value:1,to:month)!}label:{Image(systemName:"chevron.right")}}.padding(24);HStack{Text(month.formatted(.dateTime.month(.wide).year())).font(.title2.bold());Spacer();Label("Surveys",systemImage:"circle.fill").foregroundStyle(.orange);Label("Jobs",systemImage:"circle.fill").foregroundStyle(.blue)}.padding(.horizontal,24).padding(.bottom,14);HStack(spacing:0){ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],id:\.self){Text($0).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth:.infinity)}}.padding(.horizontal,24).padding(.bottom,6);LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:0),count:7),spacing:0){ForEach(Array(days.enumerated()),id:\.offset){_,date in CalendarDay(date:date,selected:date.map{calendar.isDate($0,inSameDayAs:selected)} ?? false,leads:date.map{events($0)} ?? []){if let date{selected=date}}}}.padding(.horizontal,24);let selectedEvents=events(selected);HStack{Text(selected.formatted(date:.complete,time:.omitted)).font(.headline);Spacer();Text("\(selectedEvents.count) events").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,24).padding(.top,18);ScrollView(.horizontal){HStack(spacing:12){if selectedEvents.isEmpty{ContentUnavailableView("No work scheduled",systemImage:"calendar",description:Text("Choose another date or add dates to a lead."))};ForEach(selectedEvents){lead in NavigationLink{LeadDetailView(leadID:lead.id)}label:{VStack(alignment:.leading,spacing:6){Text(lead.name).fontWeight(.semibold);Text(lead.jobType).foregroundStyle(.secondary);Label(lead.surveyDate==PayrollMath.key(selected) ? "Survey":"\(lead.stage.displayName) job",systemImage:lead.surveyDate==PayrollMath.key(selected) ? "ruler":"hammer").font(.caption).foregroundStyle(lead.surveyDate==PayrollMath.key(selected) ? .orange:.blue)}.padding(14).frame(width:230,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.quaternary))}.buttonStyle(.plain)}}.padding(.horizontal,24).padding(.bottom,20)};Spacer(minLength:0)}.background(Color(nsColor:.windowBackgroundColor)).navigationTitle("Calendar")}
    private func events(_ date:Date)->[Lead]{let key=PayrollMath.key(date);return appState.leads.filter{$0.surveyDate==key || (($0.startDate ?? "9999")<=key && ($0.endDate ?? $0.startDate ?? "0000")>=key)}}
}
private struct CalendarDay: View {
    let date: Date?
    let selected: Bool
    let leads: [Lead]
    let action: () -> Void

    private var key: String { date.map(PayrollMath.key) ?? "" }

    var body: some View {
        Button(action: action) {
            Group {
                if let date {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(Calendar.current.component(.day, from: date))")
                                .fontWeight(Calendar.current.isDateInToday(date) ? .bold : .regular)
                                .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.orange : Color.primary)
                            Spacer()
                        }
                        ForEach(Array(leads.prefix(3))) { lead in
                            eventPill(lead)
                        }
                        Spacer()
                    }
                } else {
                    Color.clear
                }
            }
            .padding(7)
            .frame(minHeight: 88, maxHeight: 105)
            .background(selected ? Color.orange.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(selected ? Color.orange : Color.secondary.opacity(0.12), lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .disabled(date == nil)
    }

    private func eventPill(_ lead: Lead) -> some View {
        let survey = lead.surveyDate == key
        return Text(survey ? "Survey · \(lead.name)" : "\(lead.name) · \(lead.jobRef)")
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(survey ? Color.orange : Color.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((survey ? Color.orange : Color.blue).opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}
#endif

struct ContactsView: View {
    @Environment(AppState.self) private var appState; @State private var search = "";@State private var showingAdd=false
    private var rows:[CRMContact]{appState.contacts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.phone.contains(search) || $0.email.localizedCaseInsensitiveContains(search) }}
    var body: some View {
        #if os(macOS)
        MacContactsView()
        #else
        List(rows) { contact in NavigationLink { ContactDetailView(contactID:contact.id) } label:{VStack(alignment: .leading, spacing: 4) { Text(contact.name).font(.headline); Text([contact.phone,contact.email].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary); if !contact.address.isEmpty{Text(contact.address).font(.caption).foregroundStyle(.secondary)}}} }.searchable(text: $search).navigationTitle("Contacts").toolbar{Button{showingAdd=true}label:{Label("New Contact",systemImage:"plus")}}.sheet(isPresented:$showingAdd){ContactEditor(contact:nil)}
        #endif
    }
}

struct ContactDetailView:View{
    @Environment(AppState.self) private var appState;@Environment(\.dismiss)private var dismiss;let contactID:String;@State private var editing=false;@State private var confirmingDelete=false
    private var contact:CRMContact?{appState.contacts.first{$0.id==contactID}}
    private var related:[Lead]{guard let c=contact else{return []};return appState.leads.filter{(!c.phone.isEmpty && $0.phone==c.phone)||(!c.email.isEmpty && $0.email.caseInsensitiveCompare(c.email) == .orderedSame)}}
    var body:some View{if let contact{List{Section("Contact"){LabeledContent("Name",value:contact.name);if !contact.phone.isEmpty{PhoneActionMenu(number:contact.phone,label:contact.phone)};if let u=ContactLinks.email(contact.email){Link(contact.email,destination:u)}else if !contact.email.isEmpty{LabeledContent("Email",value:contact.email)};LabeledContent("Address",value:contact.address.isEmpty ? "Not added":contact.address)};Section("Related leads and jobs"){if related.isEmpty{Text("No related leads").foregroundStyle(.secondary)};ForEach(related){lead in NavigationLink{LeadDetailView(leadID:lead.id)}label:{LeadRow(lead:lead)}}}}.navigationTitle(contact.name).toolbar{Button("Edit"){editing=true};Menu{Button("Delete contact",role:.destructive){confirmingDelete=true}}label:{Image(systemName:"ellipsis.circle")}}.sheet(isPresented:$editing){ContactEditor(contact:contact)}.confirmationDialog("Delete \(contact.name)?",isPresented:$confirmingDelete,titleVisibility:.visible){Button("Delete contact",role:.destructive){Task{if await appState.deleteContact(contact){dismiss()}}}}}else{ContentUnavailableView("Contact not found",systemImage:"person.crop.circle.badge.questionmark")}}
}

struct ContactEditor:View{
    @Environment(AppState.self) private var appState;@Environment(\.dismiss) private var dismiss;let contact:CRMContact?;@State private var name="";@State private var phone="";@State private var email="";@State private var address="";@State private var isSaving=false
    var body:some View{NavigationStack{Form{TextField("Name",text:$name);TextField("Phone",text:$phone);TextField("Email",text:$email);TextField("Address",text:$address,axis:.vertical)}.disabled(isSaving).navigationTitle(contact == nil ? "New Contact":"Edit Contact").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.disabled(isSaving)};ToolbarItem(placement:.confirmationAction){Button{Task{isSaving=true;defer{isSaving=false};let saved:Bool;if var changed=contact{changed.name=name;changed.phone=phone;changed.email=email;changed.address=address;saved=await appState.saveContact(changed)}else{saved=await appState.addContact(name:name,phone:phone,email:email,address:address)};if saved{dismiss()}}}label:{if isSaving{ProgressView()}else{Text("Save")}}.disabled(name.trimmingCharacters(in:.whitespaces).isEmpty || isSaving)}}}.frame(minWidth:420,minHeight:360).onAppear{guard let contact else{return};name=contact.name;phone=contact.phone;email=contact.email;address=contact.address}}
}

struct FilesView: View {
    @Environment(AppState.self) private var appState; @State private var search = ""
    private var items: [(Lead, CRMFile)] { appState.leads.flatMap { lead in lead.files.map { (lead, $0) } }.filter { search.isEmpty || $0.1.name.localizedCaseInsensitiveContains(search) || $0.0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        #if os(macOS)
        MacFilesView()
        #else
        List(items, id: \.1.id) { lead, file in HStack{NavigationLink { LeadDetailView(leadID: lead.id) } label: { Label { VStack(alignment: .leading) { Text(file.name); Text("\(lead.name) · \(file.date)").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: file.type == "image" ? "photo" : "doc") } };Spacer();if let raw=file.url,let url=URL(string:raw){Link(destination:url){Image(systemName:"arrow.up.right.square")}}} }.searchable(text: $search).navigationTitle("Files")
        #endif
    }
}

struct ReportsView: View {
    @Environment(AppState.self) private var appState
    @State private var exporting = false
    @State private var exportDocument = CRMCSVDocument(text: "")
    var body: some View {
        #if os(macOS)
        MacReportsView()
        #else
        List { Section("Financial") { LabeledContent("Total won", value: appState.leads.filter { [.won,.scheduled,.inProgress,.completed,.waitingForPayment,.paid].contains($0.stage) }.reduce(0){$0+$1.value}.formatted(.currency(code:"GBP"))); LabeledContent("Paid revenue", value: appState.leads.filter{$0.stage == .paid}.reduce(0){$0+$1.value}.formatted(.currency(code:"GBP"))); LabeledContent("Outstanding", value: appState.leads.filter{$0.stage != .lost}.reduce(0){$0+$1.balance}.formatted(.currency(code:"GBP"))) }; Section("Pipeline") { ForEach(LeadStage.allCases) { stage in let rows = appState.leads.filter{$0.stage == stage}; LabeledContent(stage.rawValue, value: "\(rows.count) · \(rows.reduce(0){$0+$1.value}.formatted(.currency(code:"GBP")))") } }; Section("Lead Sources") { ForEach(Dictionary(grouping: appState.leads, by: \.source).keys.sorted(), id: \.self) { source in LabeledContent(source.isEmpty ? "Unknown" : source, value: "\(appState.leads.filter{$0.source == source}.count)") } } }.navigationTitle("Reports").toolbar { Button { prepareExport() } label: { Label("Export", systemImage: "square.and.arrow.up") }.disabled(appState.leads.isEmpty) }.fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "ProLine-Job-Report-\(SupabaseService.today)") { result in if case .failure = result { appState.errorMessage = "The report could not be exported." } }
        #endif
    }
    private func prepareExport() { exportDocument = CRMCSVDocument(text: CRMReportExport.csv(leads: appState.leads)); exporting = true }
}

struct CRMCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct TimesheetView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        #if os(macOS)
        if appState.usesAdminInterface { MacPayrollView() } else { WorkerWeeklyPayView() }
        #else
        if appState.usesAdminInterface { MobileAdminPayReview() } else { WorkerWeeklyPayView() }
        #endif
    }
}

private struct WorkerWeekDay: Identifiable {
    let date: Date
    let entry: TimesheetEntry?
    var id: String { PayrollMath.key(date) }
}

private struct WorkerWeeklyPayView: View {
    @Environment(AppState.self) private var appState
    @State private var weekStart = PayrollMath.monday(for: .now)
    @State private var editingDay: WorkerWeekDay?
    @State private var confirmingSubmit = false
    private var user: CRMUser? { appState.currentUser }
    private var weekKey: String { PayrollMath.key(weekStart) }
    private var friday: Date { Calendar.current.date(byAdding: .day, value: 4, to: weekStart) ?? weekStart }
    private var payDate: Date { Calendar.current.date(byAdding: .day, value: 11, to: weekStart) ?? friday }
    private var entries: [TimesheetEntry] {
        guard let id = user?.id else { return [] }
        return appState.timesheets.filter { $0.userID == id && $0.date >= weekKey && $0.date <= PayrollMath.key(friday) }
    }
    private var run: PaymentRun? { appState.paymentRuns.first { $0.userID == user?.id && $0.weekStart == weekKey } }
    private var locked: Bool { run.map { $0.status != .due } ?? false }
    private var complete: Bool { Set(entries.map(\.date)).count == 5 }
    private var gross: Double { PayrollMath.gross(entries) }
    private var cis: Double { gross * Double(user?.cisRate ?? 20) / 100 }
    private var canSubmitNow: Bool { Date.now >= friday || weekStart < PayrollMath.monday(for: .now) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button { weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        VStack(spacing: 2) { Text("My work week").font(.title2.bold()); Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(friday.formatted(.dateTime.day().month(.abbreviated)))").foregroundStyle(.secondary) }
                        Spacer()
                        Button { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.right") }.disabled(weekStart >= PayrollMath.monday(for: .now))
                    }
                    HStack(spacing: 12) {
                        payMetric("Days", PayrollMath.days(entries).formatted(), "calendar", .blue)
                        payMetric("Gross", gross.formatted(.currency(code: "GBP")), "sterlingsign", .orange)
                        payMetric("After CIS", (gross - cis).formatted(.currency(code: "GBP")), "banknote", .green)
                    }
                    Label("Expected payment: Friday \(payDate.formatted(.dateTime.day().month(.wide)))", systemImage: "calendar.badge.checkmark").font(.subheadline.bold()).foregroundStyle(.blue)
                }.padding(16).background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { offset in
                        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                        let entry = entries.first { $0.date == PayrollMath.key(date) }
                        Button { editingDay = WorkerWeekDay(date: date, entry: entry) } label: { dayRow(date, entry) }.buttonStyle(.plain).disabled(locked)
                    }
                }

                if let rate = user?.dayRate, rate > 0 {
                    Text("Calculated using your saved \(rate.formatted(.currency(code: "GBP"))) day rate and \(user?.cisRate ?? 20)% CIS rate.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Ask an administrator to add your day rate before submitting.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                if let run {
                    Label(run.status == .submitted ? "Submitted for admin review" : run.status == .scheduled ? "Approved for payment" : run.status == .paid ? "Paid" : "Week reopened", systemImage: run.status == .paid ? "checkmark.seal.fill" : "lock.fill")
                        .font(.headline).foregroundStyle(run.status == .paid ? .green : run.status == .scheduled ? .blue : .orange).padding(14).frame(maxWidth: .infinity).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
                } else {
                    Button { confirmingSubmit = true } label: { Label(complete ? "Submit week for payment" : "Complete all five days", systemImage: "paperplane.fill").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).disabled(!complete || !canSubmitNow || (user?.dayRate ?? 0) <= 0)
                    if complete && !canSubmitNow { Text("Submission opens after Friday’s work is complete.").font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(16).frame(maxWidth: 720)
        }
        .navigationTitle("My Timesheet")
        .sheet(item: $editingDay) { WorkerDayEntrySheet(day: $0) }
        .confirmationDialog("Submit this week?", isPresented: $confirmingSubmit, titleVisibility: .visible) {
            Button("Submit and lock week") { Task { _ = await appState.submitTimesheetWeek(weekStart: weekKey) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your administrator will review it and schedule payment for the following Friday. You cannot edit it after submitting unless they reopen it.") }
    }

    private func dayRow(_ date: Date, _ entry: TimesheetEntry?) -> some View {
        let isOff = entry?.type == "off"
        let iconName = entry == nil ? "plus" : (isOff ? "minus" : "hammer.fill")
        let iconColor: Color = entry == nil || isOff ? .secondary : .orange
        let iconBackground: Color = entry == nil
            ? Color.secondary.opacity(0.1)
            : (isOff ? Color.secondary.opacity(0.14) : Color.orange.opacity(0.14))
        return HStack(spacing: 13) {
            Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.headline).frame(width: 42, alignment: .leading)
            Circle()
                .fill(iconBackground)
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: iconName).foregroundStyle(iconColor))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.map { $0.type == "half" ? "Half day" : $0.type == "off" ? "Off" : "Full day" } ?? "Add work day").fontWeight(.semibold)
                if let entry, entry.type != "off" { Text(appState.leads.first { $0.id == entry.leadID }.map { "\($0.name) · \($0.jobRef)" } ?? "Job not found").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                else { Text(entry == nil ? "Tap to record this day" : "Not working").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let entry, entry.amount > 0 { Text(entry.amount, format: .currency(code: "GBP")).fontWeight(.bold) }
            Image(systemName: locked ? "lock.fill" : "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(entry == nil ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.18)))
    }

    private func payMetric(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View { VStack(alignment: .leading, spacing: 5) { Image(systemName: icon).foregroundStyle(tint); Text(value).font(.headline); Text(title).font(.caption).foregroundStyle(.secondary) }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 11)) }
}

private struct WorkerDayEntrySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let day: WorkerWeekDay
    @State private var kind: String
    @State private var leadID: String
    @State private var saving = false
    init(day: WorkerWeekDay) { self.day = day; _kind = State(initialValue: day.entry?.type ?? "full"); _leadID = State(initialValue: day.entry?.leadID ?? "") }
    private var jobs: [Lead] { appState.leads.filter { [.won, .scheduled, .inProgress, .completed].contains($0.stage) }.sorted { $0.name < $1.name } }
    var body: some View {
        NavigationStack {
            Form {
                Section { Picker("Day", selection: $kind) { Text("Full day").tag("full"); Text("Half day").tag("half"); Text("Off").tag("off") }.pickerStyle(.segmented) }
                if kind != "off" { Section("Job worked on") { Picker("Job", selection: $leadID) { Text("Choose job").tag(""); ForEach(jobs) { Text("\($0.name) · \($0.jobRef)").tag($0.id) } } } }
                Section { LabeledContent("Date", value: day.date.formatted(date: .complete, time: .omitted)); if kind != "off", let rate = appState.currentUser?.dayRate { LabeledContent("Amount", value: (rate * (kind == "half" ? 0.5 : 1)).formatted(.currency(code: "GBP"))) } }
            }.navigationTitle("Record \(day.date.formatted(.dateTime.weekday(.wide)))").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving || (kind != "off" && leadID.isEmpty)) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
    }
    private func save() { Task { saving = true; if await appState.setTimesheetDay(userID: appState.currentUser?.id ?? "", leadID: leadID, date: PayrollMath.key(day.date), kind: kind) { dismiss() }; saving = false } }
}

private struct MobileAdminPayReview: View {
    @Environment(AppState.self) private var appState
    @State private var weekStart = PayrollMath.monday(for: .now)
    @State private var confirmingPaid: AdminPaySummary?
    @State private var addingTimesheet = false
    @State private var quickAddUserID: String?
    private var friday: Date { Calendar.current.date(byAdding: .day, value: 4, to: weekStart) ?? weekStart }
    private var weekKey: String { PayrollMath.key(weekStart) }
    private var entries: [TimesheetEntry] { appState.timesheets.filter { $0.date >= weekKey && $0.date <= PayrollMath.key(friday) } }
    private var defaultEntryDate: Date { let today = Calendar.current.startOfDay(for: .now); return today >= weekStart && today <= friday ? today : weekStart }
    private var summaries: [AdminPaySummary] {
        Dictionary(grouping: entries, by: \.userID).compactMap { userID, rows in
            guard let user = appState.users.first(where: { $0.id == userID }) else { return nil }
            let gross = PayrollMath.gross(rows), rate = user.cisRate ?? 20
            let status = appState.paymentRuns.first { $0.userID == userID && $0.weekStart == weekKey }?.status ?? .due
            return AdminPaySummary(user: user, entries: rows, gross: gross, cis: gross * Double(rate) / 100, status: status)
        }.sorted {
            let leftPriority = $0.status == .submitted ? 0 : 1
            let rightPriority = $1.status == .submitted ? 0 : 1
            return leftPriority == rightPriority
                ? $0.user.name.localizedStandardCompare($1.user.name) == .orderedAscending
                : leftPriority < rightPriority
        }
    }
    var body: some View {
        ScrollView { VStack(spacing: 15) {
            HStack { Button { weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.left") }; Spacer(); VStack { Text("Weekly payments").font(.title2.bold()); Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(friday.formatted(.dateTime.day().month(.abbreviated)))").foregroundStyle(.secondary) }; Spacer(); Button { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.right") }.disabled(weekStart >= PayrollMath.monday(for: .now)) }
            HStack(spacing: 10) { adminMetric("Submitted", summaries.filter { $0.status == .submitted }.count, .orange); adminMetric("Approved", summaries.filter { $0.status == .scheduled }.count, .blue); adminMetric("Net total", summaries.reduce(0) { $0 + $1.gross - $1.cis }.formatted(.currency(code: "GBP")), .green) }
            ForEach(summaries) { summary in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Circle().fill(Color.orange.opacity(0.14)).frame(width: 43, height: 43).overlay(Text(summary.user.name.prefix(1)).fontWeight(.bold).foregroundStyle(.orange)); VStack(alignment: .leading) { Text(summary.user.name).fontWeight(.bold); Text("\(PayrollMath.days(summary.entries).formatted()) days · \(summary.entries.count)/5 recorded").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(summary.status.displayName).font(.caption.bold()).foregroundStyle(summary.status == .submitted ? .orange : summary.status == .scheduled ? .blue : summary.status == .paid ? .green : .secondary) }
                    HStack { amount("Gross", summary.gross); amount("CIS", summary.cis); amount("To pay", summary.gross - summary.cis) }
                    if summary.missingPaymentDetails {
                        Label("Add bank details before approval", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold()).foregroundStyle(.red)
                    }
                    if summary.status == .submitted { Button("Approve for next Friday") { Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: weekKey, status: .scheduled) } }.buttonStyle(.borderedProminent).tint(.orange).frame(maxWidth: .infinity, alignment: .trailing).disabled(summary.missingPaymentDetails) }
                    else if summary.status == .scheduled { HStack { Button("Reopen") { Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: weekKey, status: .due) } }; Spacer(); Button("Mark paid") { confirmingPaid = summary }.buttonStyle(.borderedProminent).tint(.green) } }
                    else if summary.status == .paid { Label("Payment recorded", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    else { Label("Waiting for worker to submit", systemImage: "clock").foregroundStyle(.secondary) }
                    if summary.status == .due || summary.status == .submitted {
                        Button { quickAddUserID = summary.user.id } label: { Label("Log work day", systemImage: "plus").font(.caption.bold()) }
                            .buttonStyle(.bordered).tint(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.quaternary))
            }
            if summaries.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView("No work recorded", systemImage: "calendar", description: Text("Add a work day for a worker or wait for their submission."))
                    Button { addingTimesheet = true } label: { Label("Add work day", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 4) }
                        .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                }
            }
        }.padding(16) }
        .navigationTitle("Subcontractor Pay")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { addingTimesheet = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add work day") } }
        .sheet(isPresented: $addingTimesheet) { AddTimesheetView(defaultDate: defaultEntryDate) }
        .sheet(item: Binding(get: { quickAddUserID.map { QuickAddSeed(userID: $0) } }, set: { quickAddUserID = $0?.userID })) { seed in
            AddTimesheetView(defaultUserID: seed.userID, defaultDate: defaultEntryDate)
        }
        .confirmationDialog("Confirm payment", isPresented: Binding(get: { confirmingPaid != nil }, set: { if !$0 { confirmingPaid = nil } }), titleVisibility: .visible) { Button("Mark paid") { guard let summary = confirmingPaid else { return }; Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: weekKey, status: .paid) }; confirmingPaid = nil }; Button("Cancel", role: .cancel) { confirmingPaid = nil } } message: { Text("Confirm the bank transfer has been made before recording this payment.") }
    }
    private func adminMetric(_ title: String, _ value: Int, _ tint: Color) -> some View { adminMetric(title, "\(value)", tint) }
    private func adminMetric(_ title: String, _ value: String, _ tint: Color) -> some View { VStack(alignment: .leading) { Text(value).font(.headline).foregroundStyle(tint); Text(title).font(.caption).foregroundStyle(.secondary) }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11)) }
    private func amount(_ title: String, _ value: Double) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value, format: .currency(code: "GBP")).fontWeight(.bold) }.frame(maxWidth: .infinity, alignment: .leading) }
}

private struct AdminPaySummary: Identifiable {
    let user: CRMUser; let entries: [TimesheetEntry]; let gross: Double; let cis: Double; let status: PaymentStatus
    var id: String { user.id }
    var missingPaymentDetails: Bool {
        (user.bankAccountNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (user.bankSortCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct QuickAddSeed: Identifiable { let userID: String; var id: String { userID } }

struct AddTimesheetView: View {
    @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss
    let entry: TimesheetEntry?
    let adminCopy: Bool
    @State private var userID = ""; @State private var leadID = ""; @State private var date = Date(); @State private var kind = "full"; @State private var isSaving = false
    init(entry: TimesheetEntry? = nil, defaultUserID: String = "", defaultDate: Date? = nil, adminCopy: Bool = false) { self.entry=entry; self.adminCopy=adminCopy; _userID=State(initialValue:entry?.userID ?? defaultUserID); _leadID=State(initialValue:entry?.leadID ?? ""); _date=State(initialValue:entry.flatMap{SupabaseService.date(from:$0.date)} ?? defaultDate ?? .now); _kind=State(initialValue:entry?.type ?? "full") }
    // Timesheets are calendar days, not instants. ISO8601FormatStyle defaults to UTC,
    // which can turn local midnight on 17 August into 16 August during BST.
    private var dateKey:String{PayrollMath.key(date)}
    private var sourceEntries:[TimesheetEntry]{adminCopy ? appState.adminTimesheetChecks : appState.timesheets}
    private var duplicate:Bool{sourceEntries.contains{$0.userID==userID && $0.date==dateKey && $0.id != entry?.id}}
    var body: some View {
        NavigationStack {
            Form {
                Section("Who and when") {
                    Picker("Worker", selection: $userID) {
                        Text("Select worker").tag("")
                        ForEach(appState.isAdmin ? appState.users : appState.users.filter { $0.id == appState.currentUser?.id }) { Text($0.name).tag($0.id) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Work") {
                    if kind != "off" {
                        Picker("Job", selection: $leadID) {
                            Text("Select job").tag("")
                            ForEach(appState.leads.filter { [.won, .scheduled, .inProgress, .completed].contains($0.stage) }) {
                                Text("\($0.jobRef) · \($0.name)").tag($0.id)
                            }
                        }
                    }
                    Picker("Time", selection: $kind) { Text("Full day").tag("full"); Text("Half day").tag("half"); Text("Off").tag("off") }.pickerStyle(.segmented)
                    if let rate = appState.users.first(where: { $0.id == userID })?.dayRate {
                        LabeledContent("Amount", value: (kind == "off" ? 0 : rate * (kind == "half" ? 0.5 : 1)).formatted(.currency(code: "GBP")))
                    }
                }
                if duplicate {
                    Section { Label("This worker already has an entry for that date.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .disabled(isSaving)
            .navigationTitle(adminCopy ? "Office Timesheet Copy" : (entry == nil ? "Add Work Day" : "Edit Work Day"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { if isSaving { ProgressView() } else { Text("Save") } }
                        .disabled(userID.isEmpty || (leadID.isEmpty && kind != "off") || duplicate || isSaving)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 410)
        .onAppear {
            if userID.isEmpty, !appState.isAdmin { userID = appState.currentUser?.id ?? "" }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            let saved: Bool
            if var changed = entry {
                changed.userID = userID; changed.leadID = kind == "off" ? "" : leadID; changed.date = dateKey
                changed.type = kind
                let rate = appState.users.first { $0.id == userID }?.dayRate ?? 0
                changed.amount = kind == "off" ? 0 : rate * (kind == "half" ? 0.5 : 1)
                saved = adminCopy ? await appState.saveAdminTimesheetCheck(changed) : await appState.saveTimesheet(changed)
            } else {
                saved = adminCopy
                    ? await appState.setAdminTimesheetCheck(userID: userID, leadID: leadID, date: dateKey, kind: kind)
                    : await appState.setTimesheetDay(userID: userID, leadID: leadID, date: dateKey, kind: kind)
            }
            if saved { dismiss() }
        }
    }
}
