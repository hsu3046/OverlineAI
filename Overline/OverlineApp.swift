//
//  OverlineApp.swift
//  Overline
//
//  Created by Yu Hitomi on 6/24/26.
//

import SwiftUI

@main
struct OverlineApp: App {
    @State private var library = ReadingLibrary.shared
    @State private var intentRouter = AppIntentRouter.shared
    @State private var quoteSpeechPlayer = QuoteSpeechPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(intentRouter)
                .environment(quoteSpeechPlayer)
                .preferredColorScheme(.light)
        }
    }
}
