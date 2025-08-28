//
//  ContentView.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var extensionManager = ExtensionManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTrustedNetwork.dateAdded, ascending: false)],
        animation: .default)
    private var trustedNetworks: FetchedResults<CDTrustedNetwork>
    
    @State private var selectedTab = "setup"

    var body: some View {
        TabView(selection: $selectedTab) {
            // Extension Setup Tab
            ExtensionActivationView()
                .tabItem {
                    Label("Setup", systemImage: "gearshape.2")
                }
                .tag("setup")
            
            // Networks Tab
            NavigationView {
                List {
                    ForEach(trustedNetworks) { network in
                        NavigationLink {
                            Text("Network: \(network.name ?? "Unknown")")
                        } label: {
                            VStack(alignment: .leading) {
                                Text(network.name ?? "Unknown")
                                    .font(.headline)
                                Text("Added: \(network.dateAdded ?? Date(), formatter: itemFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteNetworks)
                }
                .navigationTitle("Trusted Networks")
                .toolbar {
                    ToolbarItem {
                        Button(action: addNetwork) {
                            Label("Add Network", systemImage: "wifi.circle.fill")
                        }
                        .disabled(extensionManager.extensionStatus != .running)
                    }
                }
                Text("Select a network")
            }
            .tabItem {
                Label("Networks", systemImage: "wifi")
            }
            .tag("networks")
            
            // Statistics Tab
            Text("Statistics View - Coming Soon")
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar")
                }
                .tag("statistics")
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func addNetwork() {
        withAnimation {
            let newNetwork = CDTrustedNetwork(context: viewContext)
            newNetwork.id = UUID()
            newNetwork.name = "New Network"
            newNetwork.dateAdded = Date()
            newNetwork.isEnabled = true

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteNetworks(offsets: IndexSet) {
        withAnimation {
            offsets.map { trustedNetworks[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}