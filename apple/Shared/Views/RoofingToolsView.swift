import SwiftUI
#if os(iOS)
import CoreMotion
#endif

struct RoofingToolsView: View {
    private enum Tool: String, CaseIterable, Identifiable { case pitch = "Pitch finder", gauge = "Gauger"; var id: String { rawValue } }
    @State private var tool: Tool = ProcessInfo.processInfo.arguments.contains("--worker-preview-tools") ? .gauge : .pitch
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fast site calculations without leaving the CRM.").foregroundStyle(.secondary)
                }; Spacer()
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            Picker("Tool", selection: $tool) { ForEach(Tool.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(
                .horizontal, 24
            ).padding(.bottom, 12)
            Divider()
            ScrollView {
                Group {
                    switch tool {
                    case .pitch: RoofPitchFinder();
                    case .gauge: TileGaugeFinder()
                    }
                }.frame(maxWidth: 720).padding(24).frame(maxWidth: .infinity, alignment: .top)
            }
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
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            #else
                Label("Live level is available on iPhone", systemImage: "iphone.gen3").foregroundStyle(.secondary).padding(14).frame(
                    maxWidth: .infinity, alignment: .leading
                ).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                pitchCalculator
            #endif
        }
    }
    private var pitchCalculator: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ToolNumberField(title: "Rise", placeholder: "1200", unit: "mm", value: $rise);
                ToolNumberField(title: "Run", placeholder: "2400", unit: "mm", value: $run)
            }
            if let angle {
                HStack(spacing: 16) {
                    Text("\(angle, specifier: "%.1f")°").font(.largeTitle.bold()).monospacedDigit().foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calculated pitch").fontWeight(.semibold);
                        Text("1 : \(runValue / riseValue, specifier: "%.2f") · \(pitchAdvice(angle))").font(.caption).foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
                    Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Enter the vertical rise and horizontal run.").font(.caption).foregroundStyle(.secondary)
            }
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
        TileSpecification(
            make: "Somerset / Bridgwater", name: "Somerset No. 13 (reclaimed)", pitch: "30° historic guidance", minGauge: 295,
            maxGauge: 325, headlap: "Set to suit the reclaimed batch", tileLength: 394, minPitchDegrees: 30,
            gaugeBasis: "Somerset trade working range—measure and trial-lay the reclaimed batch"),
        TileSpecification(
            make: "Somerset / Bridgwater", name: "Sandtoft Bridgwater Double Roman", pitch: "30°", minGauge: 345, maxGauge: 345,
            headlap: "75 mm fixed", tileLength: 420, minPitchDegrees: 30, fasciaProjection: "45–55 mm"),
        TileSpecification(
            make: "Somerset / Bridgwater", name: "BCC / Bridgwater Double Roman (legacy)", pitch: "30°—verify batch", minGauge: 295,
            maxGauge: 325, headlap: "Set to suit the reclaimed batch", tileLength: 394, minPitchDegrees: 30,
            gaugeBasis: "Somerset trade working range—measure and trial-lay the reclaimed batch"),
        TileSpecification(
            make: "Marley", name: "Modern", pitch: "17.5° smooth at 100 mm headlap", minGauge: 320, maxGauge: 345, headlap: "75–100 mm",
            tileLength: 420, minPitchDegrees: 17.5),
        TileSpecification(
            make: "Marley", name: "Duo Modern", pitch: "17.5° smooth", minGauge: 320, maxGauge: 345, headlap: "75–100 mm",
            minPitchDegrees: 17.5),
        TileSpecification(make: "Marley", name: "Double Roman", pitch: "22.5° smooth", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Ludlow Major", pitch: "22.5° smooth", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Ludlow Plus", pitch: "22.5°", minGauge: 287, maxGauge: 312, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Mendip", pitch: "15° smooth", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Mendip 12.5", pitch: "12.5°", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Edgemere", pitch: "17.5°", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Duo Edgemere", pitch: "17.5°", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Wessex", pitch: "15°", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Anglia", pitch: "25° smooth", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(make: "Marley", name: "Concrete Plain Tile", pitch: "35°", minGauge: 88, maxGauge: 100, headlap: "65–88 mm"),
        TileSpecification(
            make: "BMI Redland", name: "Richmond 10 Slate", pitch: "17.5° at 100 mm", minGauge: 293, maxGauge: 343, headlap: "75–125 mm"),
        TileSpecification(
            make: "BMI Redland", name: "MockBond Richmond 10", pitch: "17.5° at 100 mm", minGauge: 293, maxGauge: 343, headlap: "75–125 mm"),
        TileSpecification(
            make: "BMI Redland", name: "Mini Stonewold", pitch: "17.5° at 100 mm", minGauge: 293, maxGauge: 343, headlap: "75–125 mm"),
        TileSpecification(
            make: "BMI Redland", name: "MockBond Mini Stonewold", pitch: "17.5° at 100 mm", minGauge: 293, maxGauge: 343,
            headlap: "75–125 mm"),
        TileSpecification(
            make: "BMI Redland", name: "50 Double Roman", pitch: "17.5° at 100 mm", minGauge: 293, maxGauge: 343, headlap: "75–125 mm"),
        TileSpecification(
            make: "BMI Redland", name: "Grovebury", pitch: "17.5° at 100 mm", minGauge: 293, maxGauge: 343, headlap: "75–125 mm"),
        TileSpecification(
            make: "BMI Redland", name: "Regent", pitch: "12.5° system dependent", minGauge: 293, maxGauge: 343, headlap: "75–125 mm"),
        TileSpecification(
            make: "BMI Redland", name: "Renown", pitch: "17.5° at 100 mm", minGauge: 293, maxGauge: 343, headlap: "75–125 mm"),
        TileSpecification(
            make: "Sandtoft", name: "20/20 Clay", pitch: "15° at 100 mm", minGauge: 210, maxGauge: 255, headlap: "75–100 mm",
            tileLength: 330, minPitchDegrees: 15, fasciaProjection: "45–55 mm"),
        TileSpecification(
            make: "Sandtoft", name: "Calderdale Edge", pitch: "17.5° at 100 mm", minGauge: 320, maxGauge: 345, headlap: "75–100 mm",
            minPitchDegrees: 17.5, fasciaProjection: "45–55 mm"),
        TileSpecification(make: "Sandtoft", name: "Double Roman", pitch: "22.5°", minGauge: 320, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(
            make: "Sandtoft", name: "Danum TLE", pitch: "17.5° at 100 mm", minGauge: 300, maxGauge: 345, headlap: "75–100 mm"),
        TileSpecification(
            make: "Sandtoft", name: "Standard Pattern", pitch: "17.5° at 100 mm", minGauge: 260, maxGauge: 305, headlap: "75–100 mm"),
        TileSpecification(make: "Sandtoft", name: "Concrete Plain Tile", pitch: "35°", minGauge: 88, maxGauge: 100, headlap: "65–88 mm"),
    ]
    @State private var tileID = "Marley Modern"
    @State private var search = ""
    @State private var step: Step =
        ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result")
        ? .result : (ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-details") ? .roof : .tile)
    @State private var apexMeasurement = ""
    @State private var roofIsNotSquare = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result")
    @State private var leftApexMeasurement = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "4980" : ""
    @State private var centreApexMeasurement = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "5000" : ""
    @State private var rightApexMeasurement = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "5020" : ""
    @State private var ridgeType: RidgeType = .mortar
    @State private var topBattenSetback = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "100" : ""
    @State private var roofPitch = ProcessInfo.processInfo.arguments.contains("--worker-preview-gauge-result") ? "30" : ""
    private var tile: TileSpecification { Self.tiles.first { $0.id == tileID } ?? Self.tiles[0] }
    private var matches: [TileSpecification] {
        let q = search.trimmingCharacters(in: .whitespaces);
        return q.isEmpty ? Self.tiles : Self.tiles.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
    }
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
    private var pitchIsSuitable: Bool {
        guard let limit = tile.minPitchDegrees, number(roofPitch) > 0 else { return true };
        return number(roofPitch) >= limit && number(roofPitch) <= 90
    }
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
            Rectangle().fill(step.rawValue > 1 ? Color.accentColor : Color.secondary.opacity(0.2)).frame(height: 2)
            stepBadge(.roof, "Roof details", "house")
            Rectangle().fill(step.rawValue > 2 ? Color.accentColor : Color.secondary.opacity(0.2)).frame(height: 2)
            stepBadge(.result, "Set-out", "checkmark")
        }.padding(.vertical, 4)
    }

    private func stepBadge(_ item: Step, _ title: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: step.rawValue > item.rawValue ? "checkmark.circle.fill" : "\(item.rawValue).circle.fill")
                .font(.title2).foregroundStyle(step.rawValue >= item.rawValue ? Color.accentColor : .secondary)
            Text(title).font(.caption).fontWeight(step == item ? .semibold : .regular).foregroundStyle(
                step.rawValue >= item.rawValue ? .primary : .secondary)
        }.frame(minWidth: 82)
    }

    private var tileStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose tile").font(.title2.bold())
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary);
                TextField("Type tile name or manufacturer", text: $search).textFieldStyle(.plain);
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { product in
                        Button {
                            tileID = product.id; search = ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.name).fontWeight(tileID == product.id ? .semibold : .regular);
                                    Text(product.make).font(.caption).foregroundStyle(.secondary)
                                }; Spacer();
                                if tileID == product.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                            }.padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if product.id != matches.last?.id { Divider() }
                    }
                }
            }.frame(maxHeight: 230).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected").font(.caption.bold()).foregroundStyle(.secondary)
                Text(tile.fullName).font(.headline)
                HStack {
                    compactSpec("MAX GAUGE", gaugeValue(tile.maxGauge)); compactSpec("HEADLAP", tile.headlap);
                    compactSpec("MIN PITCH", tile.pitch)
                }
            }.padding(16).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Button {
                withAnimation { step = .roof }
            } label: {
                Label("Use this tile", systemImage: "arrow.right").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var roofStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Back") { withAnimation { step = .tile } }; Spacer();
                Text(tile.name).font(.caption.bold()).foregroundStyle(.secondary)
            }
            Text("Enter roof measurements").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                Text("Ridge type").font(.headline)
                Picker("Ridge type", selection: $ridgeType) {
                    ForEach(RidgeType.allCases) { type in Text(type.rawValue).tag(type) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Roof is not square", isOn: $roofIsNotSquare)
                Text(
                    roofIsNotSquare
                        ? "Measure from the first-batten line to the apex at the left, centre and right."
                        : "Measure from the first-batten line to the rafter apex."
                )
                .font(.caption).foregroundStyle(.secondary)
                if roofIsNotSquare {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ToolNumberField(title: "Left", placeholder: "e.g. 4980", unit: "mm", value: $leftApexMeasurement)
                        ToolNumberField(title: "Centre", placeholder: "e.g. 5000", unit: "mm", value: $centreApexMeasurement)
                        ToolNumberField(title: "Right", placeholder: "e.g. 5020", unit: "mm", value: $rightApexMeasurement)
                    }
                } else {
                    ToolNumberField(
                        title: "First-batten line to rafter apex", placeholder: "e.g. 5000", unit: "mm", value: $apexMeasurement)
                }
            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            ToolNumberField(title: "Top batten down from apex", placeholder: "e.g. 100", unit: "mm", value: $topBattenSetback)
            Text(ridgeSetbackHelp).font(.caption).foregroundStyle(.secondary)
            ToolNumberField(title: "Roof pitch", placeholder: "e.g. 30", unit: "°", value: $roofPitch)
            if !pitchIsSuitable {
                Label(
                    "This tile is unsuitable at the entered pitch. Minimum stored limit: \(tile.pitch).", systemImage: "xmark.octagon.fill"
                ).font(.callout.bold()).foregroundStyle(.red)
            }
            Button {
                withAnimation { step = .result }
            } label: {
                Label("Calculate gauge", systemImage: "ruler").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!canCalculate)
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Your gauge").font(.title2.bold()); Text(tile.fullName).foregroundStyle(.secondary)
                }; Spacer(); Button("Edit") { withAnimation { step = .roof } }
            }
            if let courses, let actualGauge {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        resultMetric("COURSES", "\(courses)", .primary)
                        resultMetric(
                            roofIsNotSquare ? "GAUGE RANGE" : "ACTUAL GAUGE",
                            roofIsNotSquare ? gaugeRangeText(courses: courses) : String(format: "%.1f mm", actualGauge),
                            resultGaugeIsInvalid ? .red : Color.accentColor)
                    }
                    if resultGaugeIsInvalid {
                        Label(
                            "At least one calculated gauge is outside the permitted \(gaugeDescription). This roof needs an adjusted or separate set-out before fixing battens.",
                            systemImage: "exclamationmark.triangle.fill"
                        ).font(.callout).foregroundStyle(.red)
                    }
                    if roofIsNotSquare {
                        Label(
                            "The three measurements differ by \(Int(roofLengthDifference.rounded())) mm. Courses are based on the longest rafter so the maximum gauge is not exceeded.",
                            systemImage: "arrow.left.and.right"
                        ).font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(18).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                if roofIsNotSquare {
                    nonSquareCourseSchedule(courses: courses)
                }
                VStack(alignment: .leading, spacing: 12) {
                    instruction(
                        1, "First batten",
                        "Set the tile tail to \(tile.fasciaProjection ?? "the manufacturer’s stated projection") beyond the fascia.")
                    instruction(
                        2, "Top batten",
                        "Mark it \(Int(ridgeSetback ?? 0)) mm down from the apex for the \(ridgeType.rawValue.lowercased()) detail.")
                    instruction(
                        3, "Gauge the roof",
                        roofIsNotSquare
                            ? "Use \(courses) courses and keep the batten lines level. The calculated range is \(gaugeRangeText(courses: courses))."
                            : "Mark \(courses) equal courses at \(String(format: "%.1f", actualGauge)) mm.")
                }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                Label(
                    "Check the tile and \(ridgeType.rawValue.lowercased()) manufacturer details before fixing battens.",
                    systemImage: "checkmark.shield"
                ).font(.caption).foregroundStyle(.secondary)
            } else {
                ToolEmpty(text: "Return to roof details and enter valid measurements.")
            }
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
    private var gaugeDescription: String {
        tile.minGauge == tile.maxGauge ? gaugeValue(tile.maxGauge) : "\(gaugeValue(tile.minGauge))–\(gaugeValue(tile.maxGauge))"
    }
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
    private func compactSpec(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary);
            Text(value).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func resultMetric(_ title: String, _ value: String, _ colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary);
            Text(value).font(.title2.bold()).foregroundStyle(colour).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func instruction(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.caption.bold()).foregroundStyle(.white).frame(width: 26, height: 26).background(
                Color.accentColor, in: Circle());
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold); Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
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
                    Text(roofIsNotSquare ? gaugeRangeText(courses: courses) : "\(String(format: "%.1f", gauge)) mm equal gauge")
                        .foregroundStyle(.secondary)
                }
            }
            RoofBattenConstructionView(courses: courses, irregularity: roofIsNotSquare ? roofLengthDifference : 0)
                .frame(minHeight: 330, idealHeight: 430, maxHeight: 480)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                setOutCard("FIRST BATTEN", "0 mm datum")
                setOutCard("TOP SETBACK", "\(Int(ridgeSetback ?? 0)) mm from apex")
                setOutCard("GAUGE RANGE", gaugeDescription)
                setOutCard(
                    roofIsNotSquare ? "ACTUAL RANGE" : "ACTUAL GAUGE",
                    roofIsNotSquare ? gaugeRangeText(courses: courses) : "\(String(format: "%.1f", gauge)) mm")
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func setOutCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.headline).minimumScaleFactor(0.75).lineLimit(1)
        }.padding(13).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func nonSquareCourseSchedule(courses: Int) -> some View {
        let labels = ["Left", "Centre", "Right"]
        let lengths = gaugeableLengths
        let gauges = lengths.map { $0 / Double(courses) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Non-square roof course schedule").font(.headline)
                Text(
                    "Every figure is measured up the rafter from the top edge of the first batten. The smaller figure beneath each mark is that section’s equal gauge."
                )
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
                                            .font(.caption2.monospacedDigit()).foregroundStyle(
                                                gaugeIsInvalid(gauges[index]) ? .red : .secondary)
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
                        .background(
                            (gaugeIsInvalid(gauges[index]) ? Color.red : Color.accentColor).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func scheduleHeader(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title.uppercased()).font(.caption2.bold()).tracking(0.7).foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment).padding(.vertical, 10)
    }
    private func reset() {
        step = .tile; apexMeasurement = ""; roofIsNotSquare = false; leftApexMeasurement = ""; centreApexMeasurement = "";
        rightApexMeasurement = ""; topBattenSetback = ""; roofPitch = ""
    }
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
                line(
                    top, CGPoint(x: top.x, y: min(size.height * 0.98, top.y + size.height * 0.12)), colour: Color.secondary.opacity(0.34),
                    width: 8)
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
                line(left, right, colour: fixed ? Color.red : Color.accentColor, width: fixed ? 7 : 4.5)
            }

            // Fascia and a simple half-round gutter sit below the first batten as visual context.
            line(frontLeft, frontRight, colour: Color.primary.opacity(0.68), width: 14)
            let gutterLeft = CGPoint(x: frontLeft.x - 2, y: frontLeft.y + 18)
            let gutterRight = CGPoint(x: frontRight.x - 2, y: frontRight.y + 18)
            line(gutterLeft, gutterRight, colour: Color.secondary.opacity(0.72), width: 13)
            line(
                CGPoint(x: gutterLeft.x, y: gutterLeft.y - 3), CGPoint(x: gutterRight.x, y: gutterRight.y - 3),
                colour: Color.white.opacity(0.5), width: 2)
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
    init(
        make: String, name: String, pitch: String, minGauge: Double, maxGauge: Double, headlap: String, tileLength: Double? = nil,
        minPitchDegrees: Double? = nil, fasciaProjection: String? = nil, gaugeBasis: String? = nil
    ) {
        self.make = make; self.name = name; self.pitch = pitch; self.minGauge = minGauge; self.maxGauge = maxGauge; self.headlap = headlap;
        self.tileLength = tileLength; self.minPitchDegrees = minPitchDegrees; self.fasciaProjection = fasciaProjection;
        self.gaugeBasis = gaugeBasis
    }
    var fullName: String { "\(make) \(name)" }; var id: String { fullName }
}
private struct TileSpecCard: View {
    let title, value: String;
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary); Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(2)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).background(
            Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

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
        private var colour: Color { heldReading == nil ? Color.accentColor : .green }
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                if level.available {
                    VStack(spacing: 16) {
                        HStack {
                            Label(
                                heldReading == nil ? "LIVE READING" : "READING HELD",
                                systemImage: heldReading == nil ? "sensor.fill" : "checkmark.circle.fill"
                            )
                            .font(.caption.bold()).foregroundStyle(colour)
                            Spacer()
                            Text(pitchBand).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Text(level.receivingData ? String(format: "%.1f°", degrees) : "—")
                            .font(.largeTitle.bold())
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
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

                    Text("Phone position").font(.caption.bold()).foregroundStyle(.secondary)
                    Picker("Phone position", selection: $position) { ForEach(RoofPhonePosition.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                        .onChange(of: position) { _, _ in heldReading = nil }

                    Button {
                        heldReading = heldReading == nil ? level.degrees(for: position) : nil
                    } label: {
                        Label(
                            heldReading == nil ? "Hold this reading" : "Take another reading",
                            systemImage: heldReading == nil ? "pause.fill" : "arrow.counterclockwise"
                        )
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).tint(heldReading == nil ? Color.accentColor : .green).controlSize(.large).disabled(
                        !level.receivingData)
                } else {
                    ContentUnavailableView(
                        "Motion sensor unavailable", systemImage: "sensor",
                        description: Text("This feature needs a real iPhone. Use rise and run below instead."))
                }
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

private struct ToolIntro: View {
    let icon, title, detail: String;
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 48, height: 48).background(
                Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12));
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold()); Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
private struct ToolNumberField: View {
    let title, placeholder, unit: String; @Binding var value: String;
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary);
            HStack {
                TextField(placeholder, text: $value).textFieldStyle(.plain); Text(unit).foregroundStyle(.secondary)
            }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay(
                RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }.frame(maxWidth: .infinity)
    }
}
private struct ToolEmpty: View {
    let text: String;
    var body: some View {
        Label(text, systemImage: "info.circle").foregroundStyle(.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
