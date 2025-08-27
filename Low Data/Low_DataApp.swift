//
//  Low_DataApp.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import SwiftUI

@main
struct Low_DataApp: App {
    @StateObject private var container = DependencyContainer.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, container.persistenceController.container.viewContext)
                .dependencyContainer(container)
        }
    }
}
