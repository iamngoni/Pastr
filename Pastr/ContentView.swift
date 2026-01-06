//
//  ContentView.swift
//  Pastr
//
//  Created by Ngonidzashe  Mangudya on 2026/01/06.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
            Text("Pastr runs in the menu bar.")
                .font(.headline)
            Text("Use Cmd+B to open the quick paste panel.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
}
