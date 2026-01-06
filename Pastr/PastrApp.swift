//
//  PastrApp.swift
//  Pastr
//
//  Created by Ngonidzashe  Mangudya on 2026/01/06.
//

import SwiftUI
import CoreData

@main
struct PastrApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
