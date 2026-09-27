import SwiftUI
import UIKit

/// Identidad de un archivo temporal para presentar la hoja de compartir.
struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

/// Puente SwiftUI a UIActivityViewController. Compartir es una decisión explícita del usuario.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
