// ContentView.swift
import SwiftUI
import CoreData

struct MoodView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Mood.timestamp, ascending: false)],
        animation: .default)
    private var moods: FetchedResults<Mood>

    @State private var selectedMood: String? = nil
    @State private var comment: String = ""

    let moodOptions = ["😄", "😊", "😐", "😟", "😭", "😠"]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("今日の気分は？").font(.title2)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                    ForEach(moodOptions, id: \.self) { mood in
                        Text(mood)
                            .font(.largeTitle)
                            .padding()
                            .background(selectedMood == mood ? Color.blue.opacity(0.3) : Color.clear)
                            .clipShape(Circle())
                            .onTapGesture {
                                selectedMood = mood
                            }
                    }
                }

                TextField("コメントを追加（任意）", text: $comment)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                Button("記録する") {
                    addMood()
                }
                .disabled(selectedMood == nil)

                List {
                    ForEach(moods) { mood in
                        VStack(alignment: .leading) {
                            Text(mood.emoji ?? "").font(.largeTitle)
                            Text(mood.comment ?? "").font(.body)
                            Text(mood.timestamp!, style: .date)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())

                Spacer()
            }
            .padding()
            .navigationTitle("気分メモ")
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
}
