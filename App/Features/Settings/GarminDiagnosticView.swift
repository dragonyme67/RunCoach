import SwiftUI
import SwiftData
import RunCoachCore

/// Journal de la connexion et des synchros, pour diagnostiquer sans débogueur (ARCHITECTURE.md §9.5).
/// Hôtes, chemins et codes HTTP seulement : jamais de ticket, de jeton ni de paramètre de requête.
struct GarminDiagnosticView: View {
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        List {
            if sync.diagnostics.isEmpty {
                Text("Rien depuis l'ouverture de l'app.")
                    .foregroundStyle(Color.rc.textSecondary)
            }
            ForEach(Array(sync.diagnostics.enumerated().reversed()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Diagnostic")
        .navigationBarTitleDisplayMode(.inline)
    }
}
