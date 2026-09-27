import SwiftUI
import UserNotifications

@main
/// Punto de entrada nativo. Mantiene una única fuente de datos local durante la vida de la app.
struct MiTensionApp: App {
    @StateObject private var store = ReadingStore()

    init() {
        UNUserNotificationCenter.current().delegate = LocalReminders.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color.aquaDark)
        }
    }
}
