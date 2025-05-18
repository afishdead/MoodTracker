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
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Mood.timestamp, ascending: false)],
        animation: .default)
    private var moods: FetchedResults<Mood>

    @State private var selectedMood: String? = nil
    @State private var comment: String = ""
    @FocusState private var commentFieldIsFocused: Bool

    @State private var selectedDate: Date? = nil
    @State private var isSheetPresented: Bool = false

    let moodOptions = ["😄", "😊", "😐", "😟", "😭", "😠"]
    let moodScale: [String: Int] = ["😄": 6, "😊": 5, "😐": 4, "😟": 3, "😭": 2, "😠": 1]
    let reverseMoodScale: [Int: String] = [6: "😄", 5: "😊", 4: "😐", 3: "😟", 2: "😭", 1: "😠"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    moodInputSection()
                    Divider()
                    moodChartSection()
                    Text(analysisMessage())
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("本日記録数: \(todayCount()) 件")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Divider()
                    moodCalendarView()
                    Divider()
                    moodHistorySection()
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("気分メモ")
            .sheet(isPresented: $isSheetPresented) {
                if let selected = selectedDate {
                    MoodDayDetailView(date: selected, moods: moods)
                }
            }
        }
    }

    private func moodInputSection() -> some View {
        VStack(alignment: .leading) {
            Text("今日の気分は？")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Color.purple)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(moodOptions, id: \.self) { mood in
                        Text(mood)
                            .font(.system(size: 30))
                            .frame(width: 50, height: 50)
                            .background(selectedMood == mood ? Color.purple.opacity(0.2) : Color.clear)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.purple, lineWidth: selectedMood == mood ? 2 : 0))
                            .shadow(radius: 1)
                            .onTapGesture { selectedMood = mood }
                    }
                }
                .padding(.horizontal)
            }

            TextField("コメントを追加（任意）", text: $comment)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
                .focused($commentFieldIsFocused)

            Button(action: {
                addMood()
                commentFieldIsFocused = false
            }) {
                Text("記録する")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(selectedMood == nil ? Color.gray.opacity(0.3) : Color.purple.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(selectedMood == nil)
            .padding(.top, 4)
        }
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

        return VStack(alignment: .leading) {
            Text("1日の気分変化")
                .font(.headline)
                .foregroundColor(.purple)

            ScrollView(.horizontal) {
                Chart {
                    ForEach(data) { item in
                        LineMark(
                            x: .value("時間", item.timestamp),
                            y: .value("気分スコア", item.score)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor.opacity(0.7))

                        PointMark(
                            x: .value("時間", item.timestamp),
                            y: .value("気分スコア", item.score)
                        )
                        .foregroundStyle(Color.accentColor)
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
                            .annotation(position: .top, alignment: .leading) {
                                Text(changeDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                VStack {
                                    Text(date.formatted(.dateTime.month().day()))
                                    Text(date.formatted(.dateTime.hour().minute()))
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }
                .chartYScale(domain: 1...6)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1, 2, 3, 4, 5, 6]) { val in
                        if let intVal = val.as(Int.self), let emoji = reverseMoodScale[intVal] {
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel { Text(emoji) }
                        }
                    }
                }
                .frame(height: 260)
                .padding(.horizontal)
                .padding(.top, 20)
                .frame(minWidth: 600)
            }
        }
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
        return Color(hue: 0.33 * normalized, saturation: 0.6, brightness: 0.95)
    }

    private func moodCalendarView() -> some View {
        VStack(alignment: .leading) {
            Text("今月の気分カレンダー")
                .font(.headline)
                .padding(.bottom, 4)

            let calendar = Calendar.current
            let today = Date()
            let range = calendar.range(of: .day, in: .month, for: today) ?? (1..<31)
            let components = calendar.dateComponents([.year, .month], from: today)
            let startOfMonth = calendar.date(from: components) ?? Date()

            let groupedByDay = Dictionary(grouping: moods) { mood in
                calendar.startOfDay(for: mood.timestamp ?? Date())
            }

            let moodAverages: [Int: Double] = groupedByDay.reduce(into: [:]) { result, pair in
                let (date, entries) = pair
                let scores = entries.compactMap { moodScale[$0.emoji ?? ""] }
                guard !scores.isEmpty else { return }
                let avg = Double(scores.reduce(0, +)) / Double(scores.count)
                let day = calendar.component(.day, from: date)
                result[day] = avg
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(range, id: \.self) { day in
                    let avg = moodAverages[day] ?? 0
                    let color = colorForMoodScore(avg)
                    VStack {
                        Text("\(day)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .frame(minWidth: 36, minHeight: 40)
                    .background(color)
                    .cornerRadius(6)
                    .onTapGesture {
                        if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                            selectedDate = date
                            isSheetPresented = true
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
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
