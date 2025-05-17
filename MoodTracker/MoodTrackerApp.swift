// MoodTrackerApp.swift
import SwiftUI
import CoreData

@main
struct MoodTrackerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            MoodView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

// Persistence.swift
struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MoodTracker")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { (_, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
    }
}


// Core Data Entity (Mood)
// Attributes:
// - timestamp: Date
// - emoji: String
// - comment: String
