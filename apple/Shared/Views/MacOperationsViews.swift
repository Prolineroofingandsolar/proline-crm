#if os(macOS)
  import SwiftUI

  struct MacContactsView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var selectedID: String?
    @State private var showingAdd = false
    @State private var editing: CRMContact?
    @State private var deleting: CRMContact?

    private var rows: [CRMContact] {
      appState.contacts.filter { contact in
        search.isEmpty
          || [contact.name, contact.phone, contact.email, contact.address].contains {
            $0.localizedCaseInsensitiveContains(search)
          }
      }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var selected: CRMContact? { rows.first { $0.id == (selectedID ?? rows.first?.id) } }
    private func related(_ contact: CRMContact) -> [Lead] {
      appState.leads.filter {
        (!$0.phone.isEmpty && $0.phone == contact.phone)
          || (!$0.email.isEmpty && $0.email.caseInsensitiveCompare(contact.email) == .orderedSame)
      }
    }

    var body: some View {
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("Contacts").font(.system(size: 29, weight: .bold))
              Text("Customers and every job connected to them.").foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              showingAdd = true
            } label: {
              Label("New contact", systemImage: "plus").foregroundStyle(.white).padding(
                .horizontal, 15
              ).frame(height: 38).background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
          }.padding(.horizontal, 24).padding(.top, 18)
          HStack {
            HStack {
              Image(systemName: "magnifyingglass")
              TextField("Search name, phone, email or address…", text: $search)
            }.padding(.horizontal, 10).frame(width: 340, height: 36).background(
              .background, in: RoundedRectangle(cornerRadius: 7)
            ).overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
            Spacer()
            Text("\(rows.count) contacts").font(.caption).foregroundStyle(.secondary)
          }.padding(24)
          HStack {
            Text("Contact").frame(maxWidth: .infinity, alignment: .leading)
            Text("Phone").frame(width: 145, alignment: .leading)
            Text("Email").frame(width: 210, alignment: .leading)
            Text("Jobs").frame(width: 55, alignment: .leading)
          }.font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 24).frame(
            height: 40
          ).background(.background).overlay(alignment: .bottom) { Divider() }
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(rows) { contact in
                Button {
                  selectedID = contact.id
                } label: {
                  HStack {
                    HStack(spacing: 10) {
                      Circle().fill(Color.blue.opacity(0.1)).frame(width: 38, height: 38).overlay(
                        Text(initials(contact.name)).font(.caption.bold()).foregroundStyle(.blue))
                      VStack(alignment: .leading) {
                        Text(contact.name).fontWeight(.semibold)
                        Text(contact.address.isEmpty ? "Address not added" : contact.address).font(
                          .caption
                        ).foregroundStyle(.secondary).lineLimit(1)
                      }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(contact.phone.isEmpty ? "—" : contact.phone).frame(
                      width: 145, alignment: .leading)
                    Text(contact.email.isEmpty ? "—" : contact.email).frame(
                      width: 210, alignment: .leading
                    ).lineLimit(1)
                    Text("\(related(contact).count)").frame(width: 55, alignment: .leading)
                  }.font(.subheadline).padding(.horizontal, 24).frame(height: 64).background(
                    selected?.id == contact.id ? Color.orange.opacity(0.06) : .clear
                  ).overlay(alignment: .bottom) { Divider() }
                }.buttonStyle(.plain)
              }
            }.overlay {
              if rows.isEmpty {
                ContentUnavailableView(
                  "No matching contacts", systemImage: "person.crop.circle.badge.questionmark")
              }
            }
          }
        }
        if let contact = selected {
          Divider()
          inspector(contact).frame(width: 330)
        }
      }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Contacts").sheet(
        isPresented: $showingAdd
      ) { ContactEditor(contact: nil) }.sheet(item: $editing) { ContactEditor(contact: $0) }
        .confirmationDialog(
          "Delete \(deleting?.name ?? "contact")?",
          isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
          titleVisibility: .visible
        ) {
          Button("Delete contact", role: .destructive) {
            if let deleting {
              Task { await appState.deleteContact(deleting) }
              self.deleting = nil
            }
          }
        }
    }
    private func inspector(_ contact: CRMContact) -> some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Circle().fill(Color.orange.opacity(0.12)).frame(width: 58, height: 58).overlay(
              Text(initials(contact.name)).font(.title3.bold()).foregroundStyle(.orange))
            VStack(alignment: .leading) {
              Text(contact.name).font(.title2.bold())
              Text("Customer since \(contact.createdAt.prefix(10))").font(.caption).foregroundStyle(
                .secondary)
            }
            Spacer()
          }
          HStack {
            if let url = ContactLinks.telephone(contact.phone),
              !contact.phone.isEmpty
            {
              Link(destination: url) {
                Label("Call", systemImage: "phone.fill").frame(maxWidth: .infinity)
              }
            }
            if let url = ContactLinks.email(contact.email) {
              Link(destination: url) {
                Label("Email", systemImage: "envelope").frame(maxWidth: .infinity)
              }
            }
          }.buttonStyle(.bordered)
          GroupBox("Contact details") {
            VStack(alignment: .leading, spacing: 12) {
              ContactLine("phone", contact.phone.isEmpty ? "Not added" : contact.phone)
              ContactLine("envelope", contact.email.isEmpty ? "Not added" : contact.email)
              ContactLine(
                "mappin.and.ellipse", contact.address.isEmpty ? "Not added" : contact.address)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
          }
          GroupBox("Related work") {
            VStack(spacing: 0) {
              if related(contact).isEmpty {
                Text("No related leads or jobs").foregroundStyle(.secondary).padding()
              }
              ForEach(related(contact)) { lead in
                NavigationLink {
                  LeadDetailView(leadID: lead.id)
                } label: {
                  HStack {
                    VStack(alignment: .leading) {
                      Text(lead.name).fontWeight(.medium)
                      Text("\(lead.jobRef) · \(lead.stage.displayName)").font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(lead.value, format: .currency(code: "GBP").precision(.fractionLength(0)))
                  }.padding(.vertical, 8)
                }.buttonStyle(.plain)
              }
            }
          }
          HStack {
            Button("Edit") { editing = contact }.buttonStyle(.borderedProminent)
            Spacer()
            Button("Delete", role: .destructive) { deleting = contact }
          }
        }.padding(16)
      }
    }
    private func initials(_ name: String) -> String {
      name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
  }

  private struct ContactLine: View {
    let icon, value: String
    init(_ icon: String, _ value: String) {
      self.icon = icon
      self.value = value
    }
    var body: some View {
      Label(value, systemImage: icon).font(.subheadline).textSelection(.enabled)
    }
  }

  struct MacFilesView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var type = "All files"
    private var all: [(Lead, CRMFile)] {
      appState.leads.flatMap { lead in lead.files.map { (lead, $0) } }
    }
    private var rows: [(Lead, CRMFile)] {
      all.filter { lead, file in
        (search.isEmpty || file.name.localizedCaseInsensitiveContains(search)
          || lead.name.localizedCaseInsensitiveContains(search)
          || lead.jobRef.localizedCaseInsensitiveContains(search))
          && (type == "All files"
            || (type == "Images" ? file.type == "image" : file.type != "image"))
      }.sorted { $0.1.date > $1.1.date }
    }
    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Files").font(.system(size: 29, weight: .bold))
            Text("Quotes, surveys, photos and paperwork across every job.").foregroundStyle(
              .secondary)
          }
          Spacer()
          Text("\(all.count)").font(.title2.bold())
          Text("documents").foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.top, 18)
        HStack(spacing: 12) {
          FileMetric("All files", all.count, "folder", .blue)
          FileMetric("Images", all.filter { $0.1.type == "image" }.count, "photo", .purple)
          FileMetric("Documents", all.filter { $0.1.type != "image" }.count, "doc.text", .orange)
          FileMetric("Jobs with files", Set(all.map { $0.0.id }).count, "briefcase", .green)
        }.padding(24)
        HStack {
          HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search files or customers…", text: $search)
          }.padding(.horizontal, 10).frame(width: 310, height: 36).background(
            .background, in: RoundedRectangle(cornerRadius: 7)
          ).overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
          Picker("", selection: $type) {
            ForEach(["All files", "Images", "Documents"], id: \.self) { Text($0) }
          }.pickerStyle(.segmented).frame(width: 280)
          Spacer()
          Text("\(rows.count) results").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.bottom, 16)
        HStack {
          Text("File").frame(maxWidth: .infinity, alignment: .leading)
          Text("Customer / job").frame(width: 230, alignment: .leading)
          Text("Type").frame(width: 100, alignment: .leading)
          Text("Added").frame(width: 110, alignment: .leading)
          Text("").frame(width: 30)
        }.font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 24).frame(
          height: 40
        ).background(.background).overlay(alignment: .bottom) { Divider() }
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(rows, id: \.1.id) { lead, file in
              HStack {
                Image(systemName: file.type == "image" ? "photo.fill" : "doc.fill").font(.title2)
                  .foregroundStyle(file.type == "image" ? .purple : .blue).frame(width: 38)
                VStack(alignment: .leading) {
                  Text(file.name).fontWeight(.semibold)
                  Text(file.size ?? "Size not recorded").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                NavigationLink {
                  LeadDetailView(leadID: lead.id)
                } label: {
                  VStack(alignment: .leading) {
                    Text(lead.name)
                    Text(lead.jobRef).font(.caption).foregroundStyle(.secondary)
                  }
                }.buttonStyle(.plain).frame(width: 230, alignment: .leading)
                Text(file.type.capitalized).frame(width: 100, alignment: .leading)
                Text(file.date).frame(width: 110, alignment: .leading)
                Group {
                  if let raw = file.url, let url = URL(string: raw) {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                  } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(
                      "No file URL saved")
                  }
                }.frame(width: 30)
              }.font(.subheadline).padding(.horizontal, 24).frame(height: 62).overlay(
                alignment: .bottom
              ) { Divider() }
            }
          }.overlay {
            if rows.isEmpty {
              ContentUnavailableView("No matching files", systemImage: "doc.text.magnifyingglass")
            }
          }
        }
      }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Files")
    }
  }
  private struct FileMetric: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color
    init(_ title: String, _ value: Int, _ icon: String, _ tint: Color) {
      self.title = title
      self.value = value
      self.icon = icon
      self.tint = tint
    }
    var body: some View {
      HStack(spacing: 12) {
        Image(systemName: icon).font(.title2).foregroundStyle(tint)
        VStack(alignment: .leading) {
          Text("\(value)").font(.title2.bold())
          Text(title).font(.caption).foregroundStyle(.secondary)
        }
      }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
        .background, in: RoundedRectangle(cornerRadius: 10)
      ).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
  }

  struct MacReportsView: View {
    @Environment(AppState.self) private var appState
    @State private var exporting = false
    @State private var exportDocument = CRMCSVDocument(text: "")
    private var paid: Double {
      appState.leads.filter { $0.stage == .paid }.reduce(0) { $0 + $1.value }
    }
    private var pipeline: Double {
      appState.leads.filter { ![.paid, .lost].contains($0.stage) }.reduce(0) { $0 + $1.value }
    }
    private var outstanding: Double {
      appState.leads.filter { $0.stage != .lost }.reduce(0) { $0 + $1.balance }
    }
    private var average: Double {
      let valued = appState.leads.filter { $0.value > 0 }
      return valued.isEmpty ? 0 : valued.reduce(0) { $0 + $1.value } / Double(valued.count)
    }
    private var maximumStage: Double {
      max(
        1,
        LeadStage.allCases.map { stage in
          appState.leads.filter { $0.stage == stage }.reduce(0) { $0 + $1.value }
        }.max() ?? 1)
    }
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("Reports").font(.system(size: 29, weight: .bold))
              Text("A live commercial view of the roofing business.").foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              exportDocument = CRMCSVDocument(text: CRMReportExport.csv(leads: appState.leads))
              exporting = true
            } label: { Label("Export job report", systemImage: "square.and.arrow.up") }
              .buttonStyle(.borderedProminent).disabled(appState.leads.isEmpty)
          }
          HStack(spacing: 12) {
            ReportMetric("Paid revenue", paid, "sterlingsign.circle", .green)
            ReportMetric("Open pipeline", pipeline, "chart.line.uptrend.xyaxis", .blue)
            ReportMetric("Outstanding", outstanding, "exclamationmark.circle", .orange)
            ReportMetric("Average job", average, "briefcase", .purple)
          }
          HStack(alignment: .top, spacing: 16) {
            reportPanel("Pipeline funnel") {
              VStack(spacing: 12) {
                ForEach(LeadStage.allCases) { stage in
                  let rows = appState.leads.filter { $0.stage == stage }
                  let value = rows.reduce(0) { $0 + $1.value }
                  HStack {
                    Text(stage.displayName).frame(width: 115, alignment: .leading)
                    GeometryReader { proxy in
                      RoundedRectangle(cornerRadius: 4).fill(stageTint(stage).opacity(0.75)).frame(
                        width: max(3, proxy.size.width * value / maximumStage))
                    }.frame(height: 12)
                    Text("\(rows.count)").frame(width: 28, alignment: .trailing)
                    Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).frame(
                      width: 90, alignment: .trailing)
                  }.font(.caption)
                }
              }
            }
            reportPanel("Lead sources") {
              VStack(spacing: 12) {
                ForEach(
                  Dictionary(grouping: appState.leads, by: \.source).sorted {
                    $0.value.count > $1.value.count
                  }.prefix(8), id: \.key
                ) { source, leads in
                  HStack {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text(source.isEmpty ? "Unknown" : source)
                    Spacer()
                    Text("\(leads.count)").fontWeight(.semibold)
                    Text(sourcePercent(leads.count)).foregroundStyle(.secondary).frame(
                      width: 38, alignment: .trailing)
                  }.font(.subheadline)
                }
              }
            }.frame(width: 340)
          }
          reportPanel("Outstanding balances") {
            VStack(spacing: 0) {
              ForEach(
                appState.leads.filter { $0.balance > 0 && $0.stage != .lost }.sorted {
                  $0.balance > $1.balance
                }.prefix(12)
              ) { lead in
                NavigationLink {
                  LeadDetailView(leadID: lead.id)
                } label: {
                  HStack {
                    VStack(alignment: .leading) {
                      Text(lead.name).fontWeight(.medium)
                      Text("\(lead.jobRef) · \(lead.stage.displayName)").font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(lead.balance, format: .currency(code: "GBP")).fontWeight(.semibold)
                      .foregroundStyle(.orange)
                  }.padding(.vertical, 9).overlay(alignment: .bottom) { Divider() }
                }.buttonStyle(.plain)
              }
              if appState.leads.allSatisfy({ $0.balance <= 0 || $0.stage == .lost }) {
                DashboardEmpty(
                  "Nothing outstanding", "All recorded balances are clear.", "checkmark.seal")
              }
            }
          }
        }.padding(24)
      }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Reports")
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "ProLine-Job-Report-\(SupabaseService.today)") { result in
          if case .failure = result { appState.errorMessage = "The report could not be exported." }
        }
    }
    private func reportPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
      -> some View
    {
      VStack(alignment: .leading, spacing: 14) {
        Text(title).font(.headline)
        content()
      }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
        .background, in: RoundedRectangle(cornerRadius: 11)
      ).overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
    }
    private func stageTint(_ stage: LeadStage) -> Color {
      switch stage {
      case .newLead: .blue
      case .surveyBooked: .orange
      case .quotePreparing, .quoteSent: .purple
      case .won, .paid: .green
      case .scheduled: .teal
      case .inProgress: .cyan
      case .completed: .mint
      case .waitingForPayment: .indigo
      case .lost: .gray
      }
    }
    private func sourcePercent(_ count: Int) -> String {
      let percentage = Double(count) / Double(max(1, appState.leads.count)) * 100
      return "\(Int(percentage.rounded()))%"
    }
  }
  private struct ReportMetric: View {
    let title: String
    let value: Double
    let icon: String
    let tint: Color
    init(_ title: String, _ value: Double, _ icon: String, _ tint: Color) {
      self.title = title
      self.value = value
      self.icon = icon
      self.tint = tint
    }
    var body: some View {
      HStack(spacing: 12) {
        Image(systemName: icon).font(.title2).foregroundStyle(tint)
        VStack(alignment: .leading) {
          Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(
            .title2.bold())
          Text(title).font(.caption).foregroundStyle(.secondary)
        }
      }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(
        .background, in: RoundedRectangle(cornerRadius: 10)
      ).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
  }
#endif
