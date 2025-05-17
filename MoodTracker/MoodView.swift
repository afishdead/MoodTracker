// MoodView.swift
import SwiftUI
import CoreData
import Charts

struct MoodView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Mood.timestamp, ascending: false)],
        animation: .default)
    private var moods: FetchedResults<Mood>

    @State private var selectedMood: String? = nil
    @State private var comment: String = ""
    @FocusState private var commentFieldIsFocused: Bool

    let moodOptions = ["😄", "😊", "😐", "😟", "😭", "😠"]
    let moodScale: [String: Int] = ["😄": 6, "😊": 5, "😐": 4, "😟": 3, "😭": 2, "😠": 1]
    let reverseMoodScale: [Int: String] = [6: "😄", 5: "😊", 4: "😐", 3: "😟", 2: "😭", 1: "😠"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    moodInputSection()
                    Divider().padding(.top)
                    moodChartSection()
                    Divider().padding(.top)
                    moodHistorySection()
                }
                .padding()
            }
            .navigationTitle("気分メモ")
        }
    }

    @ViewBuilder
    private func moodInputSection() -> some View {
        Text("今日の気分は？").font(.title2)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
            ForEach(moodOptions, id: \.self) { mood in
                Text(mood)
                    .font(.largeTitle)
                    .padding()
                    .background(selectedMood == mood ? Color.blue.opacity(0.3) : Color.clear)
                    .clipShape(Circle())
                    .onTapGesture { selectedMood = mood }
            }
        }

        TextField("コメントを追加（任意）", text: $comment)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal)
            .focused($commentFieldIsFocused)

        Button("記録する") {
            addMood()
            commentFieldIsFocused = false
        }
        .disabled(selectedMood == nil)
    }

    @ViewBuilder
    private func moodChartSection() -> some View {
        Text("1日の気分変化").font(.headline)

        ScrollView(.horizontal) {
            Chart(timeSeriesData()) { entry in
                LineMark(
                    x: .value("時間", entry.timestamp),
                    y: .value("気分スコア", entry.score)
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("時間", entry.timestamp),
                    y: .value("気分スコア", entry.score)
                )
                .annotation(position: .top) {
                    if !entry.comment.isEmpty {
                        Text(entry.comment)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
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
            .frame(height: 260) // 高さを拡張
            .padding(.horizontal)
            .padding(.top, 20) // 上マージン追加
            .frame(minWidth: 600)
        }
    }

    @ViewBuilder
    private func moodHistorySection() -> some View {
        Text("最近の記録").font(.headline)

        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(moods) { mood in
                VStack(alignment: .leading, spacing: 4) {
                    Text(mood.emoji ?? "").font(.largeTitle)
                    if let comment = mood.comment, !comment.isEmpty {
                        Text(comment).font(.body)
                    }
                    if let timestamp = mood.timestamp {
                        Text(timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
        }
        .padding(.horizontal)
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

    struct MoodEntry: Identifiable {
        let id = UUID()
        let date: Date
        let emoji: String
        let count: Int
    }

    private func aggregateMoodsByDay() -> [MoodEntry] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: moods) { mood in
            calendar.startOfDay(for: mood.timestamp ?? Date())
        }

        return grouped.compactMap { (date, moods) in
            let freq = Dictionary(grouping: moods, by: { $0.emoji ?? "?" }).mapValues { $0.count }
            if let (mostEmoji, count) = freq.max(by: { $0.value < $1.value }) {
                return MoodEntry(date: date, emoji: mostEmoji, count: count)
            } else {
                return nil
            }
        }.sorted { $0.date < $1.date }
    }

    struct MoodTimeEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let emoji: String
        let score: Int
        let comment: String
    }

    private func timeSeriesData() -> [MoodTimeEntry] {
        moods.compactMap { mood in
            guard let emoji = mood.emoji,
                  let score = moodScale[emoji],
                  let timestamp = mood.timestamp else {
                return nil
            }
            return MoodTimeEntry(
                timestamp: timestamp,
                emoji: emoji,
                score: score,
                comment: mood.comment ?? ""
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }
}
