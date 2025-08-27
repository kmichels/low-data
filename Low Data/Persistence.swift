//
//  Persistence.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import CoreData
import os.log

public struct PersistenceController {
    public static let shared = PersistenceController()
    private let logger = Logger(subsystem: "com.lowdata", category: "Persistence")

    @MainActor
    public static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample trusted network
        let trustedNetwork = CDTrustedNetwork(context: viewContext)
        trustedNetwork.id = UUID()
        trustedNetwork.name = "Home WiFi"
        trustedNetwork.dateAdded = Date()
        trustedNetwork.isEnabled = true
        
        // Create sample process profiles
        let dropboxProfile = CDProcessProfile(context: viewContext)
        dropboxProfile.processIdentifier = "com.dropbox.Dropbox"
        dropboxProfile.processName = "Dropbox"
        dropboxProfile.processType = "application"
        dropboxProfile.averageBandwidth = 1_000_000 // 1 MB/s
        dropboxProfile.lastSeen = Date()
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    public let container: NSPersistentContainer

    public init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Low_Data")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure for performance
        container.persistentStoreDescriptions.forEach { description in
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        
        let loadLogger = Logger(subsystem: "com.lowdata", category: "Persistence")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                loadLogger.error("Failed to load persistent store: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            loadLogger.info("Persistent store loaded successfully: \(storeDescription)")
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    /// Creates a background context for heavy operations
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}
