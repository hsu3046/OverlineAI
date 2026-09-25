//
//  OverlineApp.swift
//  Overline
//
//  Created by Yu Hitomi on 6/24/26.
//

import SwiftUI

@main
struct OverlineApp: App {
    @AppStorage(AppLocale.selectionKey) private var languageSelection = AppLocale.systemLanguageSelection
    @State private var library = ReadingLibrary.shared
    @State private var intentRouter = AppIntentRouter.shared
    @State private var quoteSpeechPlayer = QuoteSpeechPlayer()
    @State private var llmSettings = LLMSettingsStore()

    init() {
        AppLocale.migrateLegacyLanguageSelection()
        AppLocale.syncWidgetLanguage()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, AppLocale.locale(for: languageSelection))
                .environment(library)
                .environment(intentRouter)
                .environment(quoteSpeechPlayer)
                .environment(llmSettings)
                .font(.overline(.body))
                .preferredColorScheme(.light)
        }
    }
}
