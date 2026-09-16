import SwiftUI

struct PipelineView: View {
    @Environment(AppState.self) private var appState
    @State private var compactStage: LeadStage = .newLead
    @State private var showingAdd = false
    var body: some View {
        #if os(macOS)
        MacPipelineView(showingAdd: $showingAdd)
            .sheet(isPresented: $showingAdd) { AddLeadView(defaultStage: .newLead) }
        #else
        MobilePipelineBoard(stage: $compactStage, showingAdd: $showingAdd)
            .sheet(isPresented: $showingAdd) { AddLeadView(defaultStage: compactStage) }
        #endif
    }
}

#if os(iOS)
private struct MobilePipelineBoard: View {
    @Environment(AppState.self) private var appState
    @Binding var stage: LeadStage
    @Binding var showingAdd: Bool
    @State private var search = ""
    @State private var workflow = "Sales"
    private var stages:[LeadStage] { workflow == "Sales" ? [.newLead,.surveyBooked,.quotePreparing,.quoteSent] : [.won,.scheduled,.inProgress,.waitingForPayment] }
    private let moveStages:[LeadStage] = [.newLead,.surveyBooked,.quotePreparing,.quoteSent,.won,.scheduled,.inProgress,.completed,.waitingForPayment,.paid,.lost]
    private var filtered:[Lead] { appState.leads.filter { search.isEmpty || [$0.name,$0.jobRef,$0.address,$0.jobType].contains { $0.localizedCaseInsensitiveContains(search) } } }

    var body: some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(spacing:14) {
                    Picker("Pipeline", selection: $workflow) { Text("Sales").tag("Sales"); Text("Jobs").tag("Jobs") }
                        .pickerStyle(.segmented)
                    searchBar
                    stageRail
                    stageColumn(stage)
                }.padding(.horizontal,14).padding(.bottom,24)
            }
        }
        .background(Color(.systemGroupedBackground)).navigationTitle("Pipeline").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement:.topBarTrailing){NavigationLink{CompletedJobsArchiveView()}label:{Image(systemName:"archivebox")};Button{showingAdd=true}label:{Image(systemName:"plus").fontWeight(.bold)}} }
        .onChange(of: workflow) { _, _ in withAnimation(.snappy) { stage = stages[0] } }
    }

    private var searchBar:some View{HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Search customer, postcode or job",text:$search);if !search.isEmpty{Button{search=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)}}}.padding(.horizontal,13).frame(height:46).background(.background,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(.quaternary))}
    private var stageRail:some View{ScrollView(.horizontal,showsIndicators:false){HStack(spacing:9){ForEach(stages){item in let count=filtered.filter{$0.stage==item}.count;Button{withAnimation(.snappy){stage=item}}label:{VStack(alignment:.leading,spacing:7){HStack{Image(systemName:stageIconMobile(item));Spacer();Text("\(count)").font(.caption.bold())};Text(item.displayName).font(.caption.bold()).lineLimit(1);Capsule().fill(stageColorMobile(item)).frame(height:3)}.foregroundStyle(stage==item ? Color.white:Color.primary).padding(11).frame(width:118,height:78,alignment:.leading).background(stage==item ? stageColorMobile(item):Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))}.buttonStyle(.plain)}}.contentMargins(.horizontal,1)}}
    private func stageColumn(_ item:LeadStage)->some View{let rows=filtered.filter{$0.stage==item};return VStack(alignment:.leading,spacing:11){HStack{Button{previousStage()}label:{Image(systemName:"chevron.left").frame(width:28,height:28)}.buttonStyle(.plain).disabled(stage==stages.first);VStack(alignment:.leading,spacing:2){Text(item.displayName).font(.title3.bold());Text("\(rows.count) \(workflow == "Sales" ? "opportunities" : "jobs") · \(rows.reduce(0){$0+$1.value}.formatted(.currency(code:"GBP").precision(.fractionLength(0))))").font(.caption).foregroundStyle(.secondary)};Spacer();Button{nextStage()}label:{Image(systemName:"chevron.right").frame(width:28,height:28)}.buttonStyle(.plain).disabled(stage==stages.last);Button{showingAdd=true}label:{Label("Add",systemImage:"plus").font(.caption.bold())}.buttonStyle(.bordered).tint(stageColorMobile(item))};ForEach(rows){lead in MobilePipelineOpportunity(lead:lead,tint:stageColorMobile(item),stages:moveStages)};if rows.isEmpty{ContentUnavailableView("Nothing in \(item.displayName)",systemImage:"rectangle.stack",description:Text(search.isEmpty ? "Add a lead or move one into this stage.":"No matching customers in this stage." )).frame(maxWidth:.infinity).padding(.vertical,35)}}.padding(14).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))}
    private func previousStage(){guard let index=stages.firstIndex(of:stage),index>0 else{return};withAnimation(.snappy){stage=stages[index-1]}}
    private func nextStage(){guard let index=stages.firstIndex(of:stage),index<stages.count-1 else{return};withAnimation(.snappy){stage=stages[index+1]}}
}

private struct MobilePipelineOpportunity:View {
    @Environment(AppState.self) private var appState
    let lead:Lead;let tint:Color;let stages:[LeadStage]
    @State private var completing=false
    @State private var confirmingJobCompletion=false
    @State private var showingSchedule=false
    private var next:CRMTask?{lead.tasks.first{!$0.completed}}
    var body:some View{VStack(spacing:0){NavigationLink{LeadDetailView(leadID:lead.id)}label:{MobilePipelineCard(lead:lead,tint:tint)}.buttonStyle(.plain);HStack(spacing:4){if !lead.phone.isEmpty,let url=URL(string:"tel:\(lead.phone.filter{!$0.isWhitespace})"){Link(destination:url){Label("Call",systemImage:"phone.fill").frame(maxWidth:.infinity)}}else{Label("No phone",systemImage:"phone.slash").frame(maxWidth:.infinity).foregroundStyle(.secondary)};Divider().frame(height:20);Button{completeNext()}label:{if completing{ProgressView().frame(maxWidth:.infinity)}else{Label(next == nil ? "No task":"Complete",systemImage:next == nil ? "checklist.unchecked":"checkmark.circle").frame(maxWidth:.infinity)}}.disabled(next == nil || completing);Divider().frame(height:20);Menu{ForEach(stages){destination in Button{Task{await appState.move(lead,to:destination)}}label:{Label(destination.displayName,systemImage:stageIconMobile(destination))}};Divider();Button{showingSchedule=true}label:{Label(lead.startDate == nil ? "Schedule job":"Edit schedule",systemImage:"calendar.badge.clock")};Button{confirmingJobCompletion=true}label:{Label("Complete job",systemImage:"archivebox")}}label:{Label("Move",systemImage:"arrow.right.circle").frame(maxWidth:.infinity)}}.font(.caption.bold()).buttonStyle(.plain).foregroundStyle(tint).padding(.horizontal,8).frame(height:42).background(.background).overlay(alignment:.top){Divider()}}
        .clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(.quaternary)).shadow(color:.black.opacity(0.035),radius:3,y:1)
        .sheet(isPresented:$showingSchedule){ScheduleJobSheet(lead:lead)}
        .confirmationDialog("Complete this job?",isPresented:$confirmingJobCompletion,titleVisibility:.visible){Button("Complete job"){Task{await appState.move(lead,to:.completed)}};Button("Cancel",role:.cancel){}}message:{Text("\(lead.name) will move to Completed. Move it to Waiting for Payment when the final invoice is due.")}
    }
    private func completeNext(){guard let next else{return};completing=true;Task{await appState.toggleLeadTask(leadID:lead.id,taskID:next.id);completing=false}}
}

private struct MobilePipelineCard:View {
    let lead:Lead;let tint:Color
    private var next:CRMTask?{lead.tasks.first{!$0.completed}}
    var body:some View{VStack(alignment:.leading,spacing:12){HStack(alignment:.top,spacing:11){Circle().fill(tint.opacity(0.14)).frame(width:46,height:46).overlay(Text(lead.name.prefix(1)).font(.headline).foregroundStyle(tint));VStack(alignment:.leading,spacing:3){Text(lead.name).font(.headline);Text(lead.address.isEmpty ? "Address not added":lead.address).font(.caption).foregroundStyle(.secondary).lineLimit(1);Text(lead.jobType).font(.subheadline)};Spacer();VStack(alignment:.trailing,spacing:5){Text(lead.value,format:.currency(code:"GBP").precision(.fractionLength(0))).font(.headline);Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)}};HStack(spacing:7){Text(lead.source.isEmpty ? "Direct":lead.source).font(.caption2).padding(.horizontal,7).padding(.vertical,4).background(tint.opacity(0.1),in:Capsule()).foregroundStyle(tint);if let next{Label(next.title,systemImage:"circle").font(.caption).foregroundStyle(.secondary).lineLimit(1)}else{Text("No next action").font(.caption).foregroundStyle(.orange)};Spacer();Text(lead.jobRef).font(.caption2).foregroundStyle(.tertiary)}}.padding(14).background(.background)}
}
private func stageColorMobile(_ s:LeadStage)->Color{switch s{case .newLead:.blue;case .surveyBooked:.orange;case .quotePreparing,.quoteSent:.purple;case .won,.paid:.green;case .scheduled:.teal;case .inProgress:.cyan;case .completed:.mint;case .waitingForPayment:.indigo;case .lost:.gray}}
private func stageIconMobile(_ s:LeadStage)->String{switch s{case .newLead:"message.fill";case .surveyBooked:"calendar";case .quotePreparing:"doc.text.fill";case .quoteSent:"paperplane.fill";case .won:"checkmark.circle.fill";case .scheduled:"calendar.badge.clock";case .inProgress:"hammer.fill";case .completed:"flag.checkered";case .waitingForPayment:"clock.fill";case .paid:"sterlingsign.circle.fill";case .lost:"archivebox.fill"}}
#endif

struct CompletedJobsArchiveView:View {
    @Environment(AppState.self) private var appState
    @State private var search=""
    private var archived:[Lead]{appState.leads.filter{[LeadStage.completed,.paid,.lost].contains($0.stage)}.filter{search.isEmpty || [$0.name,$0.jobRef,$0.address,$0.jobType].contains{$0.localizedCaseInsensitiveContains(search)}}}
    private func archiveDate(_ lead:Lead)->String{lead.completedDate ?? lead.paidDate ?? String(lead.updatedAt.prefix(10))}
    private var years:[String]{Array(Set(archived.map{String(archiveDate($0).prefix(4))})).sorted(by:>)}
    private func months(in year:String)->[String]{Array(Set(archived.map{String(archiveDate($0).prefix(7))}.filter{$0.hasPrefix(year)})).sorted(by:>)}
    private func jobs(in month:String)->[Lead]{archived.filter{archiveDate($0).hasPrefix(month)}.sorted{archiveDate($0)>archiveDate($1)}}
    private func monthTitle(_ key:String)->String{guard let date=SupabaseService.date(from:key+"-01") else{return key};return date.formatted(.dateTime.month(.wide))}
    var body:some View {
        List {
            ForEach(years,id:\.self){year in
                Section(year){
                    ForEach(months(in:year),id:\.self){month in
                        DisclosureGroup {
                            ForEach(jobs(in:month)){lead in
                                NavigationLink{LeadDetailView(leadID:lead.id)}label:{
                                    HStack(spacing:12){
                                        Image(systemName:"checkmark.seal.fill").foregroundStyle(.green)
                                        VStack(alignment:.leading,spacing:3){Text(lead.name).fontWeight(.semibold);Text("\(lead.jobRef) · \(lead.jobType)").font(.caption).foregroundStyle(.secondary)}
                                        Spacer()
                                        VStack(alignment:.trailing,spacing:3){Text(lead.value,format:.currency(code:"GBP").precision(.fractionLength(0))).fontWeight(.semibold);Text(archiveDate(lead)).font(.caption2).foregroundStyle(.secondary)}
                                    }.padding(.vertical,4)
                                }
                            }
                        } label:{HStack{Text(monthTitle(month)).fontWeight(.semibold);Spacer();Text("\(jobs(in:month).count)").font(.caption.bold()).foregroundStyle(.secondary).padding(6).background(.quaternary,in:Circle())}}
                    }
                }
            }
            if archived.isEmpty { ContentUnavailableView("Archive is empty",systemImage:"archivebox",description:Text("Completed, paid and lost work appears here.")) }
        }.navigationTitle("Archive").searchable(text:$search,prompt:"Search archive")
    }
}

struct ScheduleJobSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var saving = false

    init(lead: Lead) {
        self.lead = lead
        let start = lead.startDate.flatMap(SupabaseService.date(from:)) ?? Calendar.current.startOfDay(for: .now)
        _startDate = State(initialValue: start)
        _endDate = State(initialValue: lead.endDate.flatMap(SupabaseService.date(from:)) ?? Calendar.current.date(byAdding: .day, value: 4, to: start) ?? start)
    }

    private var duration: Int {
        max(1, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: endDate)).day ?? 0) + 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    LabeledContent("Customer", value: lead.name)
                    LabeledContent("Work", value: lead.jobType)
                    if !lead.address.isEmpty { LabeledContent("Address", value: lead.address) }
                }
                Section("Schedule") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Expected finish", selection: $endDate, in: startDate..., displayedComponents: .date)
                    LabeledContent("Time allowed", value: "\(duration) \(duration == 1 ? "day" : "days")")
                }
                Section {
                    Label("This job will appear across these dates in the calendar.", systemImage: "calendar.badge.checkmark")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(lead.startDate == nil ? "Schedule job" : "Edit schedule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving || endDate < startDate) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 430)
        #endif
    }

    private func save() {
        saving = true
        Task {
            var changed = lead
            changed.startDate = PayrollMath.key(startDate)
            changed.endDate = PayrollMath.key(endDate)
            changed.stage = .scheduled
            await appState.saveLead(changed)
            saving = false
            if appState.leads.first(where: { $0.id == lead.id })?.startDate == changed.startDate { dismiss() }
        }
    }
}

#if os(macOS)
private struct MacPipelineView: View {
    @Environment(AppState.self) private var appState
    @Binding var showingAdd: Bool
    @State private var workflow = "Sales"
    @State private var mode = "Board"
    @State private var search = ""
    @State private var ownership = "All leads"
    @State private var period = "All time"
    @State private var showFilters = false
    @State private var sourceFilter = "All sources"
    @State private var minimumValue = 0.0

    private var visibleStages: [LeadStage] {
        switch workflow {
        case "Jobs": [.won, .scheduled, .inProgress, .waitingForPayment]
        case "Archive": [.completed, .paid, .lost]
        default: [.newLead, .surveyBooked, .quotePreparing, .quoteSent]
        }
    }
    private var openLeads: [Lead] { filtered.filter { ![.paid,.lost].contains($0.stage) } }
    private var filtered: [Lead] {
        appState.leads.filter { lead in
            let textMatch = search.isEmpty || [lead.name,lead.jobRef,lead.address,lead.jobType].contains { $0.localizedCaseInsensitiveContains(search) }
            let ownerMatch = ownership == "All leads" || ownership == "My leads" && LeadOwnership.isAssigned(lead, to: appState.currentUser)
            let periodMatch = period == "All time" || lead.createdAt.prefix(7) == SupabaseService.today.prefix(7)
            let sourceMatch = sourceFilter == "All sources" || lead.source == sourceFilter
            return textMatch && ownerMatch && periodMatch && sourceMatch && lead.value >= minimumValue
        }
    }
    private var scopedLeads: [Lead] { filtered.filter { visibleStages.contains($0.stage) } }
    private var totalPipeline: Double { openLeads.reduce(0) { $0 + $1.value } }
    private var forecast: Double { openLeads.reduce(0) { $0 + $1.value * probability($1.stage) } }
    private var winRate: Int { let decided=appState.leads.filter{[.won,.scheduled,.inProgress,.completed,.waitingForPayment,.paid,.lost].contains($0.stage)}; guard !decided.isEmpty else{return 0}; return Int((Double(decided.filter{$0.stage != .lost}.count)/Double(decided.count)*100).rounded()) }
    private var overdue: Int { let today=SupabaseService.today; return appState.visibleGeneralTasks.filter{!$0.completed && ($0.dueDate ?? "9999") < today}.count + appState.leads.filter{($0.endDate ?? "9999") < today && ![.completed,.waitingForPayment,.paid,.lost].contains($0.stage)}.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pipeline").font(.system(size: 29, weight: .bold))
                    Text(workflow == "Sales" ? "Turn enquiries into won work." : workflow == "Jobs" ? "Schedule, deliver and collect payment." : "Paid and lost work kept out of the way.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingAdd = true } label: { Label("Add lead", systemImage: "plus").fontWeight(.semibold).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36).background(Color(red: 1, green: 0.29, blue: 0.04), in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain)
            }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 14)
            toolbar.padding(.horizontal, 26).padding(.bottom, 14)
            if mode == "Board" { board } else { list }
        }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Pipeline")
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            PipelineMetric(icon:"cylinder.split.1x2",title:"Pipeline",value:totalPipeline.formatted(.currency(code:"GBP").precision(.fractionLength(0))),color:.orange)
            Divider().frame(height:44)
            PipelineMetric(icon:"scope",title:"Forecast",value:forecast.formatted(.currency(code:"GBP").precision(.fractionLength(0))),color:.purple)
            Divider().frame(height:44)
            PipelineMetric(icon:"chart.line.uptrend.xyaxis",title:"Win rate",value:"\(winRate)%",color:.green)
            Divider().frame(height:44)
            PipelineMetric(icon:"clock",title:"Overdue",value:"\(overdue)",color:overdue > 0 ? .red:.secondary)
            Spacer()
            Image(systemName:"house.lodge").font(.system(size:46,weight:.ultraLight)).foregroundStyle(.secondary.opacity(0.18)).padding(.trailing,24)
        }.padding(.vertical,12).background(.background,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(.quaternary))
    }

    private var toolbar: some View {
        HStack(spacing:10) {
            Picker("Workflow", selection: $workflow) { ForEach(["Sales", "Jobs", "Archive"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width: 310)
            HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("Search this pipeline…",text:$search) }.padding(.horizontal,10).frame(width:280,height:36).background(.background,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).stroke(.quaternary))
            Spacer()
            Button { showFilters.toggle() } label:{Label("Filters",systemImage:"line.3.horizontal.decrease")}
                .popover(isPresented:$showFilters){VStack(alignment:.leading,spacing:14){Text("Pipeline options").font(.headline);Picker("View",selection:$mode){Label("Board",systemImage:"square.grid.2x2").tag("Board");Label("List",systemImage:"list.bullet").tag("List")}.pickerStyle(.segmented);Picker("Ownership",selection:$ownership){Text("All leads").tag("All leads");Text("My leads").tag("My leads")};Picker("Period",selection:$period){Text("All time").tag("All time");Text("This month").tag("This month")};Picker("Source",selection:$sourceFilter){Text("All sources").tag("All sources");ForEach(Array(Set(appState.leads.map(\.source))).filter{!$0.isEmpty}.sorted(),id:\.self){Text($0).tag($0)}};TextField("Minimum value",value:$minimumValue,format:.number);Button("Clear filters"){ownership="All leads";period="All time";sourceFilter="All sources";minimumValue=0;showFilters=false}.frame(maxWidth:.infinity,alignment:.trailing)}.padding().frame(width:300)}
        }.controlSize(.large)
    }

    private var todayStrip: some View {
        let today=SupabaseService.today
        let surveys=appState.leads.filter{$0.surveyDate==today}.count
        let quotes=appState.leads.filter{$0.stage == .quoteSent}.count
        let deposits=appState.leads.filter{[.won,.scheduled,.inProgress].contains($0.stage) && !$0.depositPaid && $0.deposit > 0}.count
        return HStack(spacing:9){Image(systemName:"flag.fill").foregroundStyle(.orange);Text("Today:").bold();Text("\(surveys) surveys").foregroundStyle(.blue);Text("•").foregroundStyle(.secondary);Text("\(quotes) quotes to chase").foregroundStyle(.purple);Text("•").foregroundStyle(.secondary);Text("\(deposits) deposits overdue").foregroundStyle(deposits > 0 ? .red:.secondary);Spacer()}.font(.subheadline).padding(.horizontal,14).frame(height:44).background(.background,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(.quaternary))
    }

    private var board: some View { ScrollView(.horizontal) { LazyHStack(alignment:.top,spacing:12) { ForEach(visibleStages) { stage in MacStageColumn(stage:stage,leads:scopedLeads.filter{$0.stage==stage},allowsAdd:workflow != "Archive",onAdd:{showingAdd=true}) } }.padding(.horizontal,26).padding(.bottom,20) }.scrollIndicators(.visible) }
    private var list: some View { List(scopedLeads) { lead in NavigationLink { LeadDetailView(leadID:lead.id) } label:{HStack{StageDot(stage:lead.stage);LeadRow(lead:lead);Spacer();Text(lead.value,format:.currency(code:"GBP"));Text(lead.assignedTo).foregroundStyle(.secondary).frame(width:110,alignment:.leading)}} }.listStyle(.inset).padding(.horizontal,18) }
    private func probability(_ stage:LeadStage)->Double { switch stage {case .newLead:0.15;case .surveyBooked:0.30;case .quotePreparing:0.45;case .quoteSent:0.60;case .won,.scheduled,.inProgress,.completed,.waitingForPayment,.paid:1;case .lost:0} }
}

private struct PipelineMetric: View { let icon,title,value:String;let color:Color;var body:some View{HStack(spacing:12){Image(systemName:icon).font(.title2).foregroundStyle(color);VStack(alignment:.leading,spacing:2){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.system(size:18,weight:.semibold,design:.rounded))}}.padding(.horizontal,24).frame(minWidth:180,alignment:.leading)} }

private struct MacStageColumn: View {
    @Environment(AppState.self) private var appState
    let stage:LeadStage;let leads:[Lead];let allowsAdd:Bool;let onAdd:()->Void
    private var tint:Color { stageColor(stage) }
    var body:some View{VStack(spacing:0){HStack(spacing:10){RoundedRectangle(cornerRadius:6).fill(tint.gradient).frame(width:36,height:36).overlay(Image(systemName:stageIcon(stage)).foregroundStyle(.white));VStack(alignment:.leading,spacing:2){Text(stage.displayName).font(.headline);HStack{Text("\(leads.count)");Text(leads.reduce(0){$0+$1.value},format:.currency(code:"GBP").precision(.fractionLength(0)))}.font(.caption).foregroundStyle(.secondary)};Spacer()}.padding(10);GeometryReader{geo in Capsule().fill(.quaternary).overlay(alignment:.leading){Capsule().fill(tint).frame(width:max(12,geo.size.width*min(1,Double(leads.count)/8)))} }.frame(height:3).padding(.horizontal,10).padding(.bottom,8);ScrollView{LazyVStack(spacing:8){ForEach(leads){lead in MacLeadCard(lead:lead,tint:tint).draggable(lead.id)};if allowsAdd{Button(action:onAdd){Label("Add lead",systemImage:"plus").frame(maxWidth:.infinity).padding(.vertical,10)}.buttonStyle(.plain).foregroundStyle(tint).background(.background.opacity(0.55),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(tint.opacity(0.25),style:StrokeStyle(lineWidth:1,dash:[4])))}}.padding(8)} }.frame(width:260).background(Color(nsColor:.controlBackgroundColor).opacity(0.55),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.quaternary)).dropDestination(for:String.self){ids,_ in guard let id=ids.first,let lead=appState.leads.first(where:{$0.id==id}) else{return false};Task{await appState.move(lead,to:stage)};return true}}
}

private struct MacLeadCard: View {
    @Environment(AppState.self) private var appState
    let lead: Lead
    let tint: Color
    @State private var completing = false
    @State private var confirmingJobCompletion = false
    @State private var showingSchedule = false

    private var initials: String { lead.name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined() }
    private var nextTask: CRMTask? { lead.tasks.first { !$0.completed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { LeadDetailView(leadID: lead.id) } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(tint.opacity(0.14)).frame(width: 46, height: 46).overlay(Text(initials).font(.headline).foregroundStyle(tint))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lead.name).font(.headline).lineLimit(1)
                            Text(lead.address.isEmpty ? "Address not set" : lead.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(lead.jobType).font(.caption).lineLimit(1)
                            Text(lead.value, format: .currency(code: "GBP")).font(.subheadline.bold())
                        }
                        Spacer()
                    }
                    HStack {
                        Text(lead.source.isEmpty ? "Direct" : lead.source).font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).background(tint.opacity(0.11), in: Capsule()).foregroundStyle(tint)
                        Text(age).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(lead.tasks.filter(\.completed).count)/\(lead.tasks.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)

            Divider().padding(.vertical, 8)
            HStack(spacing: 7) {
                Circle().fill(.orange.gradient).frame(width: 20, height: 20).overlay(Text(lead.assignedTo.prefix(1)).font(.caption2.bold()).foregroundStyle(.white))
                Text(lead.assignedTo.isEmpty ? "Unassigned" : lead.assignedTo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let task = nextTask {
                    Button { complete(task) } label: {
                        HStack(spacing: 5) {
                            if completing { ProgressView().controlSize(.mini) } else { Image(systemName: "circle") }
                            Text(task.title).lineLimit(1)
                        }.font(.caption2).padding(.horizontal, 7).padding(.vertical, 5)
                    }
                    .buttonStyle(.plain).foregroundStyle(tint)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.5)))
                    .frame(maxWidth: 112).help("Mark task complete")
                    .disabled(completing)
                } else {
                    NavigationLink { LeadDetailView(leadID: lead.id) } label: { Label("Add task", systemImage: "plus").font(.caption2) }.buttonStyle(.plain).foregroundStyle(tint)
                }
                Menu {
                    Button { showingSchedule = true } label: { Label(lead.startDate == nil ? "Schedule job" : "Edit schedule", systemImage: "calendar.badge.clock") }
                    Divider()
                    Button { confirmingJobCompletion = true } label: { Label("Complete job", systemImage: "archivebox") }
                } label: { Image(systemName:"ellipsis").font(.caption) }.menuStyle(.borderlessButton).frame(width:18)
            }
        }
        .padding(10).background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary)).shadow(color: .black.opacity(0.035), radius: 3, y: 1)
        .sheet(isPresented: $showingSchedule) { ScheduleJobSheet(lead: lead) }
        .confirmationDialog("Complete and archive this job?", isPresented: $confirmingJobCompletion, titleVisibility: .visible) {
            Button("Complete job") { Task { await appState.move(lead, to: .completed) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("\(lead.name) will leave the live pipeline and move into Completed Jobs.") }
    }

    private var age: String {
        guard let date = SupabaseService.date(from: lead.createdAt) else { return lead.jobRef }
        let days = max(0, Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0)
        return "\(days)d"
    }

    private func complete(_ task: CRMTask) {
        completing = true
        Task {
            await appState.toggleLeadTask(leadID: lead.id, taskID: task.id)
            completing = false
        }
    }
}

private struct StageDot:View{let stage:LeadStage;var body:some View{Circle().fill(stageColor(stage)).frame(width:9,height:9)}}
private func stageColor(_ s:LeadStage)->Color{switch s{case .newLead:.blue;case .surveyBooked:.orange;case .quotePreparing:.purple;case .quoteSent:Color(red:0.45,green:0.2,blue:0.8);case .won:.green;case .scheduled:.teal;case .inProgress:.cyan;case .completed:.mint;case .waitingForPayment:.indigo;case .paid:.green;case .lost:.gray}}
private func stageIcon(_ s:LeadStage)->String{switch s{case .newLead:"message";case .surveyBooked:"calendar";case .quotePreparing:"doc.text";case .quoteSent:"paperplane";case .won:"checkmark.circle";case .scheduled:"calendar.badge.clock";case .inProgress:"hammer";case .completed:"flag.checkered";case .waitingForPayment:"clock";case .paid:"sterlingsign.circle";case .lost:"archivebox"}}
#endif

struct LeadCard: View { let lead:Lead;var body:some View{VStack(alignment:.leading,spacing:7){HStack{Text(lead.name).font(.headline);Spacer();Text(lead.jobRef).font(.caption).foregroundStyle(.secondary)};Text(lead.jobType).font(.caption).foregroundStyle(.orange);Text(lead.address).font(.caption).foregroundStyle(.secondary).lineLimit(2);if lead.value>0{Text(lead.value,format:.currency(code:"GBP")).font(.subheadline.bold())}}.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:12)).shadow(color:.black.opacity(0.06),radius:3,y:1)} }
struct LeadRow: View { let lead:Lead;var body:some View{VStack(alignment:.leading){Text(lead.name).font(.headline);Text("\(lead.jobRef) · \(lead.stage.displayName)").font(.caption).foregroundStyle(.secondary)}} }

struct AddLeadView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let defaultStage: LeadStage
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var addressLine = ""
    @State private var town = ""
    @State private var postcode = ""
    @State private var jobType = "Roof Repair"
    @State private var stage: LeadStage
    @State private var value = 0.0
    @State private var deposit = 0.0
    @State private var depositPlan: DepositPlan = .thirty
    @State private var source = "Website"
    @State private var notes = ""
    @State private var priority = "Medium"
    @State private var createFollowUp = true
    @State private var isSaving = false
    @State private var addressSearch = AddressSearchService()
    @State private var isSelectingAddress = false
    @State private var selectedAddressLine = ""
    @State private var selectedCustomerName = ""

    private let jobTypes = ["Roof Repair", "New Roof", "Flat Roof", "Solar Installation", "Solar + Battery", "Guttering", "Fascias & Soffits", "Chimney Repair", "Roof Inspection", "Other"]
    private let sources = ["Website", "Referral", "Google", "Facebook", "Checkatrade", "MyBuilder", "Cold Call", "Returning Customer", "Other"]
    private var emailIsValid: Bool { email.isEmpty || (email.contains("@") && email.split(separator: "@").last?.contains(".") == true) }
    private var contactIsValid: Bool { !phone.trimmingCharacters(in: .whitespaces).isEmpty || !email.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && contactIsValid && emailIsValid && value >= 0 && !isSaving }
    private var fullAddress: String { [addressLine, town, postcode].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ") }
    private var customerMatches: [PreviousCustomer] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query != selectedCustomerName else { return [] }
        var results: [PreviousCustomer] = []
        var seen = Set<String>()
        for lead in appState.leads where lead.name.localizedCaseInsensitiveContains(query) {
            let key = [lead.name, lead.phone, lead.email, lead.address].joined(separator: "|").lowercased()
            if seen.insert(key).inserted { results.append(PreviousCustomer(id: "lead-\(lead.id)", name: lead.name, phone: lead.phone, email: lead.email, address: lead.address, detail: "\(lead.jobRef) · \(lead.jobType)")) }
        }
        for contact in appState.contacts where contact.name.localizedCaseInsensitiveContains(query) {
            let key = [contact.name, contact.phone, contact.email, contact.address].joined(separator: "|").lowercased()
            if seen.insert(key).inserted { results.append(PreviousCustomer(id: "contact-\(contact.id)", name: contact.name, phone: contact.phone, email: contact.email, address: contact.address, detail: "Saved customer")) }
        }
        return Array(results.prefix(6))
    }

    init(defaultStage: LeadStage) { self.defaultStage = defaultStage; _stage = State(initialValue: defaultStage) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    formSection("Contact", icon: "person") {
                        twoColumns {
                            customerLookup
                        } trailing: {
                            field("Phone number", required: true, icon: "phone", prompt: "Phone number", text: $phone)
                        }
                        twoColumns {
                            field("Email address", icon: "envelope", prompt: "Email address", text: $email, error: emailIsValid ? nil : "Enter a valid email address")
                        } trailing: {
                            pickerField("Lead source", icon: "building.2", selection: $source, options: sources)
                        }
                        if !contactIsValid { validation("Add a phone number or email address so the lead can be contacted.") }
                    }
                    Divider()
                    formSection("Job details", icon: "house") {
                        addressLookup
                        twoColumns {
                            field("Town / City", icon: "mappin", prompt: "Town or city", text: $town)
                        } trailing: {
                            field("Postcode", icon: "number", prompt: "Postcode", text: $postcode)
                        }
                    }
                    Divider()
                    formSection("Enquiry", icon: "clipboard") {
                        twoColumns {
                            pickerField("Service required", required: true, icon: "wrench.and.screwdriver", selection: $jobType, options: jobTypes)
                        } trailing: {
                            currencyField
                        }
                        depositField
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(.caption).fontWeight(.medium)
                            TextField("Briefly describe the work required…", text: $notes, axis: .vertical)
                                .lineLimit(2...4).textFieldStyle(.plain).padding(10).background(fieldBackground)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Priority").font(.caption).fontWeight(.medium)
                            Picker("Priority", selection: $priority) {
                                ForEach(["Low", "Medium", "High"], id: \.self) { Text($0) }
                            }.labelsHidden().pickerStyle(.segmented)
                        }
                    }
                }.padding(24)
            }
            Divider()
            footer
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 680, maxWidth: 720, minHeight: 700, idealHeight: 760)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .background(Color.primary.opacity(0.015))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle().fill(Color.orange.gradient).frame(width: 46, height: 46)
                .overlay(Image(systemName: "person.badge.plus").font(.title3.bold()).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) { Text("Add New Lead").font(.title2.bold()); Text("Create a new customer enquiry").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 34, height: 34).background(.quaternary, in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Close")
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var footer: some View {
        #if os(macOS)
        HStack {
            followUpToggle
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button { save() } label: { HStack { if isSaving { ProgressView().controlSize(.small) }; Label(isSaving ? "Saving…" : "Add Lead", systemImage: "plus") } }
                .buttonStyle(.borderedProminent).tint(.orange).keyboardShortcut(.defaultAction).disabled(!canSave)
        }.padding(.horizontal, 24).padding(.vertical, 14).background(.bar)
        #else
        VStack(spacing: 10) {
            followUpToggle
            Button { save() } label: { HStack { if isSaving { ProgressView().tint(.white) }; Label(isSaving ? "Saving…" : "Add Lead", systemImage: "plus").frame(maxWidth:.infinity) } }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).disabled(!canSave)
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.bar)
        #endif
    }

    private var currencyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated value").font(.caption).fontWeight(.medium)
            HStack(spacing: 8) { Image(systemName: "sterlingsign").foregroundStyle(.secondary).frame(width: 18); TextField("0.00", value: $value, format: .number.precision(.fractionLength(2))).textFieldStyle(.plain) }
                .padding(.horizontal, 10).frame(height: 38).background(fieldBackground)
                .onChange(of: value) { _, total in if let amount = depositPlan.amount(for: total) { deposit = amount } }
            if value < 0 { validation("Value cannot be negative.") }
        }
    }

    private var depositField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deposit to collect").font(.caption).fontWeight(.medium)
                    Text("Calculated from the estimated value").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Deposit calculation", selection: $depositPlan) {
                    ForEach(DepositPlan.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
            }
            HStack(spacing: 8) {
                Image(systemName: "sterlingsign").foregroundStyle(.secondary).frame(width: 18)
                if depositPlan == .custom {
                    TextField("0.00", value: $deposit, format: .number.precision(.fractionLength(2))).textFieldStyle(.plain)
                } else {
                    Text(deposit, format: .currency(code: "GBP")).fontWeight(.semibold)
                    Spacer()
                    Text(depositPlan == .none ? "No deposit" : "Auto").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 10).frame(height: 38).background(fieldBackground)
        }
        .onChange(of: depositPlan) { _, plan in if let amount = plan.amount(for: value) { deposit = amount } }
    }

    private var addressLookup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Address").font(.caption).fontWeight(.medium)
            HStack(spacing: 8) {
                Image(systemName: "house").foregroundStyle(.secondary).frame(width: 18)
                TextField("Start typing a property address…", text: $addressLine).textFieldStyle(.plain)
                if isSelectingAddress { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10).frame(height: 38).background(fieldBackground)
            .onChange(of: addressLine) { _, value in
                if value == selectedAddressLine {
                    addressSearch.clear()
                } else if !isSelectingAddress {
                    addressSearch.search(value)
                }
            }

            if !addressSearch.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(addressSearch.suggestions) { suggestion in
                        Button { chooseAddress(suggestion) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).foregroundStyle(.primary).lineLimit(1)
                                    if !suggestion.subtitle.isEmpty { Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                            }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if suggestion.id != addressSearch.suggestions.last?.id { Divider().padding(.leading, 38) }
                    }
                    HStack { Spacer(); Text("Address suggestions provided by Apple Maps").font(.caption2).foregroundStyle(.tertiary).padding(7) }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            }
            if let error = addressSearch.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var customerLookup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Full name *").font(.caption).fontWeight(.medium)
            HStack(spacing: 8) { Image(systemName: "person").foregroundStyle(.secondary).frame(width: 18); TextField("Search existing customer or enter a name", text: $name).textFieldStyle(.plain) }
                .padding(.horizontal, 10).frame(height: 38).background(fieldBackground)
                .onChange(of: name) { _, value in if value != selectedCustomerName { selectedCustomerName = "" } }
            if !customerMatches.isEmpty {
                VStack(spacing: 0) {
                    HStack { Label("Previous customers", systemImage: "clock.arrow.circlepath").font(.caption.bold()).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 10).padding(.vertical, 7)
                    Divider()
                    ForEach(customerMatches) { customer in
                        Button { chooseCustomer(customer) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color.orange.opacity(0.12)).frame(width: 32, height: 32).overlay(Text(customer.name.prefix(1)).font(.caption.bold()).foregroundStyle(.orange))
                                VStack(alignment: .leading, spacing: 2) { Text(customer.name).foregroundStyle(.primary); Text(customer.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer(); Image(systemName: "arrow.down.left.circle").foregroundStyle(.orange)
                            }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if customer.id != customerMatches.last?.id { Divider().padding(.leading, 52) }
                    }
                }.background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary)).shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            }
        }
    }

    @ViewBuilder private var followUpToggle: some View {
        #if os(macOS)
        Toggle("Create follow-up task for tomorrow", isOn: $createFollowUp).toggleStyle(.checkbox)
        #else
        Toggle("Follow up tomorrow", isOn: $createFollowUp).toggleStyle(.switch)
        #endif
    }

    private var fieldBackground: some View { RoundedRectangle(cornerRadius: 7).fill(.background).overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary)) }

    private func formSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Label(title, systemImage: icon).font(.headline); content() }
    }
    @ViewBuilder private func twoColumns<Leading: View, Trailing: View>(@ViewBuilder _ leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) -> some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 18) { leading().frame(maxWidth: .infinity); trailing().frame(maxWidth: .infinity) }
        #else
        VStack(alignment: .leading, spacing: 14) { leading().frame(maxWidth: .infinity); trailing().frame(maxWidth: .infinity) }
        #endif
    }
    private func field(_ label: String, required: Bool = false, icon: String, prompt: String, text: Binding<String>, error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label + (required ? " *" : "")).font(.caption).fontWeight(.medium)
            HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18); TextField(prompt, text: text).textFieldStyle(.plain) }
                .padding(.horizontal, 10).frame(height: 38).background(fieldBackground)
            if let error { validation(error) }
        }
    }
    private func pickerField(_ label: String, required: Bool = false, icon: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label + (required ? " *" : "")).font(.caption).fontWeight(.medium)
            HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18); Picker(label, selection: selection) { ForEach(options, id: \.self) { Text($0) } }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading) }
                .padding(.horizontal, 10).frame(height: 38).background(fieldBackground)
        }
    }
    private func validation(_ message: String) -> some View { Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
    private func chooseAddress(_ suggestion: AddressSuggestion) {
        isSelectingAddress = true
        addressSearch.clear()
        Task {
            let resolved = await addressSearch.resolve(suggestion)
            selectedAddressLine = resolved.street
            addressLine = resolved.street
            town = resolved.town
            postcode = resolved.postcode
            addressSearch.clear()
            isSelectingAddress = false
        }
    }
    private func chooseCustomer(_ customer: PreviousCustomer) {
        selectedCustomerName = customer.name
        name = customer.name
        phone = customer.phone
        email = customer.email
        addressLine = customer.address
        town = ""
        postcode = ""
        selectedAddressLine = customer.address
        source = "Returning Customer"
    }
    private func save() {
        guard canSave else { return }; isSaving = true
        Task {
            let saved = await appState.addLead(name: name.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines), email: email.trimmingCharacters(in: .whitespacesAndNewlines), address: fullAddress, jobType: jobType, stage: stage, value: value, deposit: deposit, source: source, notes: notes, priority: priority, createFollowUp: createFollowUp)
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct PreviousCustomer: Identifiable {
    let id: String
    let name: String
    let phone: String
    let email: String
    let address: String
    let detail: String
}
