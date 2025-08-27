//
//  Low_DataApp.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import SwiftUI

@main
struct Low_DataApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
