import SwiftUI
import CoreData
import Charts

// MARK: - Calendar 拡張（先頭に必要）
extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components)!
    }
}

// MARK: - Color 拡張（先頭に必要）
extension Color {
    static let primaryColor = Color(hex: "#A974FF")
    static let accentColor = Color(hex: "#FFD6E8")

    static var backgroundColor: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor.black : UIColor(red: 250/255, green: 249/255, blue: 251/255, alpha: 1)
        })
    }

    static var cardBackground: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1) : .white
        })
    }

    static var subtextColor: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor.lightGray : UIColor.gray
        })
    }

    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - エントリ構造体
struct MoodTimeEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let emoji: String
    let score: Int
    let comment: String
}


// MARK: - 補助型
struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
}

private func trendLine(for entries: [MoodTimeEntry]) -> [TrendPoint] {
    guard entries.count >= 2 else { return [] }

    let xValues = entries.map { $0.timestamp.timeIntervalSince1970 }
    let yValues = entries.map { Double($0.score) }

    let xMean = xValues.reduce(0, +) / Double(xValues.count)
    let yMean = yValues.reduce(0, +) / Double(yValues.count)

    let numerator = zip(xValues, yValues).reduce(0) { $0 + (($1.0 - xMean) * ($1.1 - yMean)) }
    let denominator = xValues.reduce(0) { $0 + pow($1 - xMean, 2) }

    guard denominator != 0 else { return [] }

    let slope = numerator / denominator
    let intercept = yMean - slope * xMean

    guard let first = entries.first?.timestamp,
          let last = entries.last?.timestamp else { return [] }

    let y1 = slope * first.timeIntervalSince1970 + intercept
    let y2 = slope * last.timeIntervalSince1970 + intercept

    return [
        TrendPoint(date: first, score: y1),
        TrendPoint(date: last, score: y2)
    ]
}



// MARK: - メインビュー
struct MoodView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) var colorScheme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Mood.timestamp, ascending: true)],
        animation: .default)
    private var moods: FetchedResults<Mood>

    @State private var selectedMood: String? = nil
    @State private var comment: String = ""
    @FocusState private var commentFieldIsFocused: Bool
    @State private var selectedDate: Date? = nil
    @State private var isSheetPresented: Bool = false
    @State private var currentMonth: Date = Calendar.current.startOfMonth(for: Date())

    @State private var timeEntries: [MoodTimeEntry] = []
    @State private var todayMoodCount: Int = 0
    @State private var dailyAverages: [Date: Double] = [:]
    @State private var scrollTarget: UUID? = nil

    let moodOptions = ["😄", "😊", "😐", "😟", "😭", "😠"]
    let moodScale: [String: Int] = ["😄": 6, "😊": 5, "😐": 4, "😟": 3, "😭": 2, "😠": 1]
    let reverseMoodScale: [Int: String] = [6: "😄", 5: "😊", 4: "😐", 3: "😟", 2: "😭", 1: "😠"]

    var greetingMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "おはようございます ☀️"
        case 11..<17: return "こんにちは 😊"
        case 17..<22: return "こんばんは 🌙"
        default: return "おやすみなさい 😴"
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    moodInputSection()
                    Divider()
                    moodChartSection()
                    Text(analysisMessage())
                        .font(.callout)
                        .foregroundColor(.subtextColor)
                    Text("本日記録数: \(todayMoodCount) 件")
                        .font(.caption)
                        .foregroundColor(.subtextColor)
                    Divider()
                    moodCalendarView()
                    Divider()
                    moodHistorySection()
                }
                .padding()
                .background(Color.backgroundColor.ignoresSafeArea())
            }
            .navigationTitle(greetingMessage)
            .onAppear(perform: updateCache)
            .onChange(of: moods.map(\.objectID)) { _ in
                updateCache()
            }

            .sheet(isPresented: $isSheetPresented) {
                if let selected = selectedDate {
                    MoodDayDetailView(date: selected, moods: moods)
                }
            }
        }
    }
    
    private func moodChartSection() -> some View {
        let data = timeEntries
        let trendPoints = trendLine(for: data)
        let chartHeight: CGFloat = 280

        return VStack(alignment: .leading, spacing: 12) {
            Text("最近の気分変化")
                .font(.headline)
                .foregroundColor(.primaryColor)

            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    emojiYAxis(height: chartHeight)

                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack {
                            moodLineChart(data: data)
                            trendLineChart(points: trendPoints)
                        }
                        .frame(height: chartHeight)
                        .padding(.horizontal)
                        .frame(minWidth: 600)
                        .id("chartEnd")
                    }
                }
                .frame(height: chartHeight)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("chartEnd", anchor: .trailing)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
    }
    private func emojiYAxis(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach((1...6).reversed(), id: \.self) { score in
                Text(reverseMoodScale[score] ?? "")
                    .font(.caption)
                    .frame(height: (height - 30) / 6)
            }
        }
        .offset(y: -10)
        .frame(width: 32, height: height)
    }
    private func moodLineChart(data: [MoodTimeEntry]) -> some View {
        Chart {
            ForEach(data) { item in
                LineMark(
                    x: .value("時間", item.timestamp),
                    y: .value("気分スコア", item.score)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.primaryColor.opacity(0.8))

                PointMark(
                    x: .value("時間", item.timestamp),
                    y: .value("気分スコア", item.score)
                )
                .foregroundStyle(Color.primaryColor)
                .annotation(position: .top) {
                    if !item.comment.isEmpty {
                        Text(item.comment)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(width: 80)
                    }
                }
            }
        }
        .chartYScale(domain: 0.5...6.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 2, 3, 4, 5, 6]) { val in
                if let intVal = val.as(Int.self), let emoji = reverseMoodScale[intVal] {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        Text("") // ❌ 数値表示なし（絵文字だけ手前に表示されているので）
                    }
                }
            }

        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                if let date = value.as(Date.self) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        VStack(spacing: 2) {
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            Text(date.formatted(.dateTime.hour().minute()))
                        }
                        .font(.system(size: 9))
                        .multilineTextAlignment(.center)
                    }
                } else {
                    AxisGridLine() // ← グリッドだけは出す（または省略可）
                }
            }
        }
    }
    private func trendLineChart(points: [TrendPoint]) -> some View {
        Chart {
            if points.count == 2 {
                LineMark(
                    x: .value("時間", points[0].date),
                    y: .value("傾向", points[0].score)
                )
                .interpolationMethod(.catmullRom)
                //.interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .foregroundStyle(.gray)

                LineMark(
                    x: .value("時間", points[1].date),
                    y: .value("傾向", points[1].score)
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .foregroundStyle(.gray)
            }
        }
        .chartYScale(domain: 0.5...6.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 2, 3, 4, 5, 6]) { val in
                if let intVal = val.as(Int.self), let emoji = reverseMoodScale[intVal] {
                    AxisGridLine().foregroundStyle(Color.clear)
                    AxisTick()
                    AxisValueLabel {
                        Text("") // 数値表示なし（絵文字だけ手前に表示されているので）
                    }
                }
            }

        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine().foregroundStyle(Color.clear)  // ← グリッドだけは出す（または省略可）
                }
            }
    }

    private func moodCalendarView() -> some View {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: currentMonth)
        let range = calendar.range(of: .day, in: .month, for: currentMonth) ?? 1..<31
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let prefixEmptyDays = (firstWeekday + 6) % 7

        let weekDays = ["日", "月", "火", "水", "木", "金", "土"]

        return VStack(alignment: .leading) {
            HStack {
                Button(action: {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }) {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(currentMonth.formatted(.dateTime.year().month()))
                    .font(.headline)

                Spacer()

                Button(action: {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.bottom, 4)

            Text("今月の気分カレンダー")
                .font(.headline)
                .padding(.bottom, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekDays, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.gray)
                }

                ForEach(0..<prefixEmptyDays, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }

                ForEach(range, id: \.self) { day in
                    if let cellDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                        let avg = dailyAverages[cellDate] ?? 0
                        let color = colorForMoodScore(avg)

                        Text("\(day)")
                            .font(.caption)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(color)
                            .cornerRadius(6)
                            .onTapGesture {
                                selectedDate = cellDate
                                isSheetPresented = true
                            }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func moodHistorySection() -> some View {
        let filtered = moods
            .filter { ($0.comment?.isEmpty == false) }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .prefix(50)

        return VStack(alignment: .leading, spacing: 12) {
            Text("文字記録（最新50件）")
                .font(.headline)
                .foregroundColor(.purple)

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(filtered, id: \.objectID) { mood in
                    HStack(alignment: .top, spacing: 12) {
                        Text(mood.emoji ?? "")
                            .font(.system(size: 24))
                            .frame(width: 36, height: 36)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Circle())
                            .shadow(radius: 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mood.comment ?? "")
                                .font(.footnote)

                            if let timestamp = mood.timestamp {
                                Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(color: .gray.opacity(0.05), radius: 1, x: 0, y: 1)
                }
            }
        }
        .padding(.horizontal)
    }


    private func updateCache() {
        let calendar = Calendar.current
        timeEntries = moods.compactMap { mood in
            guard let emoji = mood.emoji,
                  let score = moodScale[emoji],
                  let timestamp = mood.timestamp else {
                return nil
            }
            return MoodTimeEntry(timestamp: timestamp, emoji: emoji, score: score, comment: mood.comment ?? "")
        }

        todayMoodCount = moods.filter {
            guard let timestamp = $0.timestamp else { return false }
            return calendar.isDateInToday(timestamp)
        }.count

        let grouped = Dictionary(grouping: moods) {
            calendar.startOfDay(for: $0.timestamp ?? Date())
        }
        dailyAverages = grouped.reduce(into: [:]) { result, pair in
            let scores = pair.value.compactMap { moodScale[$0.emoji ?? ""] }
            guard !scores.isEmpty else { return }
            result[pair.key] = Double(scores.reduce(0, +)) / Double(scores.count)
        }
        scrollTarget = timeEntries.last?.id
    }

    private func moodInputSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日の気分は？")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primaryColor)

            GeometryReader { geometry in
                let spacing: CGFloat = 8
                let totalWidth = geometry.size.width
                let itemWidth = (totalWidth - spacing * CGFloat(moodOptions.count - 1)) / CGFloat(moodOptions.count)

                HStack(spacing: spacing) {
                    ForEach(moodOptions, id: \.self) { mood in
                        Text(mood)
                            .font(.system(size: itemWidth * 0.5))
                            .frame(width: itemWidth, height: itemWidth)
                            .background(
                                Circle()
                                    .fill(selectedMood == mood ? Color.primaryColor.opacity(colorScheme == .dark ? 0.4 : 0.2) : .white)
                                    .shadow(color: selectedMood == mood ? Color.primaryColor.opacity(0.3) : .clear, radius: 4)
                            )
                            .overlay(Circle().stroke(Color.primaryColor, lineWidth: selectedMood == mood ? 2 : 1))
                            .onTapGesture { selectedMood = mood }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 60)

            TextField("コメントを追加（任意）", text: $comment)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($commentFieldIsFocused)

            Button(action: {
                addMood()
                commentFieldIsFocused = false
            }) {
                Text("記録する")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(selectedMood == nil ? Color.gray.opacity(0.3) : Color.primaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(selectedMood == nil)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    private func analysisMessage() -> String {
        guard !moods.isEmpty else { return "まだ記録がありません。" }
        let recent = moods.suffix(5)
        let scores = recent.compactMap { moodScale[$0.emoji ?? ""] }
        guard !scores.isEmpty else { return "最近の記録が足りません。" }
        let avg = Double(scores.reduce(0, +)) / Double(scores.count)
        if avg >= 5.0 {
            return "最近はとても良い気分が続いていますね！"
        } else if avg >= 3.5 {
            return "少し波があるようですが、落ち着いています。"
        } else {
            return "ここ数回、気分が沈みがちです。無理せず休んでくださいね。"
        }
    }

    private func colorForMoodScore(_ score: Double) -> Color {
        guard score > 0 else { return Color(UIColor.systemGray5) }
        let normalized = min(max(score - 1, 0), 5) / 5.0
        return Color(hue: 0.33 * normalized, saturation: 0.6, brightness: 0.85)
    }

    private func addMood() {
        withAnimation {
            let newMood = Mood(context: viewContext)
            newMood.timestamp = Date()
            newMood.emoji = selectedMood
            newMood.comment = comment

            do {
                try viewContext.save()
                selectedMood = nil
                comment = ""
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
struct MoodDayDetailView: View {
    let date: Date
    let moods: FetchedResults<Mood>

    var body: some View {
        let calendar = Calendar.current
        let filtered = moods.filter { mood in
            if let ts = mood.timestamp {
                return calendar.isDate(ts, inSameDayAs: date)
            }
            return false
        }

        NavigationView {
            if filtered.isEmpty {
                Text("この日に記録はありません。")
                    .foregroundColor(.gray)
                    .font(.callout)
                    .padding()
                    .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                List(filtered) { mood in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(mood.emoji ?? "")
                                .font(.title2)
                            Text(mood.comment ?? "")
                        }
                        if let ts = mood.timestamp {
                            Text(ts.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
                .navigationBarTitleDisplayMode(.inline)
            }
        }

    }
}
