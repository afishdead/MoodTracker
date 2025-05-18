// MoodView.swift - Fully Reintegrated Version
import SwiftUI
import CoreData
import Charts

struct MoodTimeEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let emoji: String
    let score: Int
    let comment: String
}

struct MoodView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) var colorScheme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Mood.timestamp, ascending: false)],
        animation: .default)
    private var moods: FetchedResults<Mood>

    @State private var selectedMood: String? = nil
    @State private var comment: String = ""
    @FocusState private var commentFieldIsFocused: Bool
    @State private var selectedDate: Date? = nil
    @State private var isSheetPresented: Bool = false
    @State private var currentMonth: Date = Calendar.current.startOfMonth(for: Date())

    let moodOptions = ["😄", "😊", "😐", "😟", "😭", "😠"]
    let moodScale: [String: Int] = ["😄": 6, "😊": 5, "😐": 4, "😟": 3, "😭": 2, "😠": 1]
    let reverseMoodScale: [Int: String] = [6: "😄", 5: "😊", 4: "😐", 3: "😟", 2: "😭", 1: "😠"]

    var greetingMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "おはようございます ☀️"
        case 11..<17: return "こんにちは 😊"
        case 17..<22: return "こんばんは 🌙"
        default: return "ゆっくり休んでください 😴"
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
                    Text("本日記録数: \(todayCount()) 件")
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
            .sheet(isPresented: $isSheetPresented) {
                if let selected = selectedDate {
                    MoodDayDetailView(date: selected, moods: moods)
                }
            }
        }
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

    private func timeSeriesData() -> [MoodTimeEntry] {
        moods.compactMap { mood in
            guard let emoji = mood.emoji,
                  let score = moodScale[emoji],
                  let timestamp = mood.timestamp else {
                return nil
            }
            return MoodTimeEntry(timestamp: timestamp, emoji: emoji, score: score, comment: mood.comment ?? "")
        }.sorted { $0.timestamp < $1.timestamp }
    }

    private func moodChartSection() -> some View {
        let calendar = Calendar.current
        let data = timeSeriesData()
        let dayChanges = zip(data, data.dropFirst()).compactMap { prev, current in
            let prevDay = calendar.startOfDay(for: prev.timestamp)
            let currentDay = calendar.startOfDay(for: current.timestamp)
            return prevDay != currentDay ? current.timestamp : nil
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("最近の気分変化")
                .font(.headline)
                .foregroundColor(.primaryColor)

            ScrollView(.horizontal, showsIndicators: false) {
                Chart {
                    ForEach(data) { item in
                        LineMark(
                            x: .value("時間", item.timestamp),
                            y: .value("気分スコア", item.score)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
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
                                    .lineLimit(1)
                            }
                        }
                    }

                    ForEach(dayChanges, id: \.self) { changeDate in
                        RuleMark(x: .value("Date Change", changeDate))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.gray)
                            .annotation(position: .topLeading) {
                                Text(changeDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                    }
                }
                .chartScrollableAxes(.horizontal) // 横スクロールだけにする
                .chartXVisibleDomain(length: 12 * 60 * 60) // 例: 12時間分を初期表示
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1, 2, 3, 4, 5, 6]) { val in
                        if let intVal = val.as(Int.self), let emoji = reverseMoodScale[intVal] {
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                Text(emoji).font(.caption)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0.5...6.5)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel() {
                            if let dateValue = value.as(Date.self) {
                                Text(dateValue.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                            }
                        }
                    }
                }

                .frame(height: 280)
                .padding(.top, 24)
                .padding(.horizontal)
                .frame(minWidth: 600)
            }

        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
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

    private func todayCount() -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return moods.filter { $0.timestamp != nil && $0.timestamp! >= today }.count
    }

    private func analysisMessage() -> String {
        guard !moods.isEmpty else { return "まだ記録がありません。" }
        let recent = moods.prefix(5)
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


    private func moodCalendarView() -> some View {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: currentMonth)
        let today = Date()

        let range = calendar.range(of: .day, in: .month, for: currentMonth) ?? 1..<31
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let prefixEmptyDays = (firstWeekday + 6) % 7 // Adjust for Sunday = 1

        let groupedByDay = Dictionary(grouping: moods) { mood in
            calendar.startOfDay(for: mood.timestamp ?? Date())
        }

        let moodAverages: [Date: Double] = groupedByDay.reduce(into: [:]) { result, pair in
            let (date, entries) = pair
            if calendar.isDate(date, equalTo: currentMonth, toGranularity: .month) {
                let scores = entries.compactMap { moodScale[$0.emoji ?? ""] }
                guard !scores.isEmpty else { return }
                let avg = Double(scores.reduce(0, +)) / Double(scores.count)
                result[date] = avg
            }
        }

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
                // 曜日ヘッダー
                ForEach(weekDays, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.gray)
                }

                // 空白マス
                ForEach(0..<prefixEmptyDays, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }

                // 日にちのマス
                ForEach(range, id: \.self) { day in
                    if let cellDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                        let avg = moodAverages[cellDate] ?? 0
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
        Text("最近の記録")
            .font(.headline)
            .foregroundColor(.purple)

        return LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(moods) { mood in
                HStack(alignment: .top, spacing: 12) {
                    Text(mood.emoji ?? "")
                        .font(.system(size: 24))
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                        .shadow(radius: 1)

                    VStack(alignment: .leading, spacing: 2) {
                        if let comment = mood.comment, !comment.isEmpty {
                            Text(comment).font(.footnote)
                        }
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
        .padding(.horizontal)
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
extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components)!
    }
}

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

    static var textColor: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? .white : .black
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
