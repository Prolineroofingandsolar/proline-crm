import SwiftUI

struct CRMCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var selected = Date()
    private var key: String { PayrollMath.key(selected) }
    var body: some View {
        #if os(macOS)
            MacCalendarView(selected: $selected)
        #else
            MobileScheduleCalendar(selected: $selected).navigationTitle("Calendar")
        #endif
    }
}

#if os(iOS)
    private struct MobileScheduleCalendar: View {
        @Environment(AppState.self) private var appState
        @Binding var selected: Date
        private var days: [Date] {
            (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) }
        }
        private var allUpcoming: [(Date, Lead, Bool)] {
            days.flatMap { day in events(day).map { (day, $0, $0.surveyDate == PayrollMath.key(day)) } }
        }
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Survey", systemImage: "circle.fill").foregroundStyle(Color.accentColor);
                        Label("Booked", systemImage: "circle.fill").foregroundStyle(.blue);
                        Label("In progress", systemImage: "circle.fill").foregroundStyle(.green); Spacer();
                        DatePicker("Choose date", selection: $selected, displayedComponents: .date).labelsHidden()
                    }.font(.caption.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) { ForEach(days, id: \.self) { day in dayButton(day) } }
                    }
                    Text("Next 14 days").font(.title2.bold())
                    if allUpcoming.isEmpty {
                        ContentUnavailableView(
                            "Nothing booked", systemImage: "calendar",
                            description: Text("Scheduled surveys and jobs will appear here without needing to select each day."))
                    }
                    ForEach(Array(allUpcoming.enumerated()), id: \.offset) { _, item in
                        NavigationLink {
                            LeadDetailView(leadID: item.1.id)
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3).fill(
                                    item.2 ? Color.accentColor : (item.1.stage == .inProgress ? Color.green : Color.blue)
                                ).frame(width: 5, height: 48);
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.1.name).fontWeight(.semibold);
                                    Text(
                                        "\(item.0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(item.2 ? "Survey" : item.1.jobType)"
                                    ).font(.caption).foregroundStyle(.secondary)
                                }; Spacer(); Text(item.1.jobRef).font(.caption2.bold()).foregroundStyle(.secondary);
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.padding(13).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }.background(Color(.systemGroupedBackground))
        }
        private func events(_ day: Date) -> [Lead] {
            let key = PayrollMath.key(day);
            return appState.leads.filter {
                $0.surveyDate == key || (($0.startDate ?? "9999") <= key && ($0.endDate ?? $0.startDate ?? "0000") >= key)
            }
        }
        private func dayButton(_ day: Date) -> some View {
            let rows = events(day); let isSelected = Calendar.current.isDate(day, inSameDayAs: selected);
            return Button {
                selected = day
            } label: {
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption.bold());
                    Text("\(Calendar.current.component(.day, from: day))").font(.headline);
                    HStack(spacing: 3) {
                        ForEach(Array(rows.prefix(3).enumerated()), id: \.offset) { _, lead in
                            Circle().fill(
                                lead.surveyDate == PayrollMath.key(day)
                                    ? Color.accentColor : (lead.stage == .inProgress ? Color.green : Color.blue)
                            ).frame(width: 6, height: 6)
                        }
                    }
                }.frame(width: 48, height: 68).background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                ).overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            }.buttonStyle(.plain)
        }
    }
#endif

#if os(macOS)
    private struct MacCalendarView: View {
        @Environment(AppState.self) private var appState; @Binding var selected: Date; @State private var month = Date()
        private let calendar = Calendar.current
        private var days: [Date?] {
            guard let range = calendar.range(of: .day, in: .month, for: month),
                let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
            else { return [] }; let offset = (calendar.component(.weekday, from: first) + 5) % 7;
            return Array(repeating: nil, count: offset) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
        }
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Surveys, starts and live roofing work in one place.").foregroundStyle(.secondary)
                    }; Spacer();
                    Button {
                        month = calendar.date(byAdding: .month, value: -1, to: month)!
                    } label: {
                        Image(systemName: "chevron.left")
                    };
                    Button("Today") {
                        month = .now; selected = .now
                    };
                    Button {
                        month = calendar.date(byAdding: .month, value: 1, to: month)!
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }.padding(24);
                HStack {
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.title2.bold()); Spacer();
                    Label("Surveys", systemImage: "circle.fill").foregroundStyle(Color.accentColor);
                    Label("Jobs", systemImage: "circle.fill").foregroundStyle(.blue)
                }.padding(.horizontal, 24).padding(.bottom, 14);
                HStack(spacing: 0) {
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) {
                        Text($0).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 6);
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                        CalendarDay(
                            date: date, selected: date.map { calendar.isDate($0, inSameDayAs: selected) } ?? false,
                            leads: date.map { events($0) } ?? []
                        ) { if let date { selected = date } }
                    }
                }.padding(.horizontal, 24); let selectedEvents = events(selected);
                HStack {
                    Text(selected.formatted(date: .complete, time: .omitted)).font(.headline); Spacer();
                    Text("\(selectedEvents.count) events").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.top, 18);
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        if selectedEvents.isEmpty {
                            ContentUnavailableView(
                                "No work scheduled", systemImage: "calendar",
                                description: Text("Choose another date or add dates to a lead."))
                        };
                        ForEach(selectedEvents) { lead in
                            NavigationLink {
                                LeadDetailView(leadID: lead.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(lead.name).fontWeight(.semibold); Text(lead.jobType).foregroundStyle(.secondary);
                                    Label(
                                        lead.surveyDate == PayrollMath.key(selected) ? "Survey" : "\(lead.stage.displayName) job",
                                        systemImage: lead.surveyDate == PayrollMath.key(selected) ? "ruler" : "hammer"
                                    ).font(.caption).foregroundStyle(
                                        lead.surveyDate == PayrollMath.key(selected) ? Color.accentColor : .blue)
                                }.padding(14).frame(width: 230, alignment: .leading).background(
                                    .background, in: RoundedRectangle(cornerRadius: 8)
                                ).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 20)
                }; Spacer(minLength: 0)
            }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Calendar")
        }
        private func events(_ date: Date) -> [Lead] {
            let key = PayrollMath.key(date);
            return appState.leads.filter {
                $0.surveyDate == key || (($0.startDate ?? "9999") <= key && ($0.endDate ?? $0.startDate ?? "0000") >= key)
            }
        }
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
                                    .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.accentColor : Color.primary)
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
                .background(selected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
                .overlay(Rectangle().stroke(selected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: selected ? 1.5 : 0.5))
            }
            .buttonStyle(.plain)
            .disabled(date == nil)
        }

        private func eventPill(_ lead: Lead) -> some View {
            let survey = lead.surveyDate == key
            return Text(survey ? "Survey · \(lead.name)" : "\(lead.name) · \(lead.jobRef)")
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(survey ? Color.accentColor : Color.blue)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((survey ? Color.accentColor : Color.blue).opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
    }
#endif
