import SwiftUI
import RunCoachCore

/// Réglages → Coach IA : choix Groq ou Gemini, une clé personnelle par fournisseur (Keychain), test de chaque modèle,
/// diagnostic, et ce que chaque fournisseur fait des données (§6.7).
struct AISettingsView: View {
    @Environment(CoachService.self) private var coach
    @State private var key = ""
    @State private var testLines: [String] = []
    @State private var isTesting = false

    var body: some View {
        @Bindable var coach = coach
        Form {
            Section {
                Picker("Fournisseur", selection: $coach.providerId) {
                    ForEach(LLMProvider.presets, id: \.id) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Les deux sont gratuits. Chaque fournisseur garde sa propre clé : tu peux changer à tout moment.")
            }

            Section {
                SecureField(coach.hasKey ? "Clé enregistrée (la remplacer)" : "Colle ta clé ici", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer la clé") {
                    coach.setKey(key)
                    key = ""
                    testLines = []
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if coach.hasKey {
                    Button("Supprimer la clé", role: .destructive) {
                        coach.setKey("")
                        testLines = []
                    }
                }
            } header: {
                Text("Clé \(coach.provider.name)")
            } footer: {
                Text(keyHelp + " La clé reste dans le trousseau de l'iPhone.")
            }

            Section {
                ForEach(Array(coach.provider.models.enumerated()), id: \.offset) { index, model in
                    HStack {
                        Text(model)
                            .font(.subheadline.monospaced())
                        Spacer()
                        Text(index == 0 ? "le plus capable" : index == coach.provider.models.count - 1 ? "le plus léger" : "")
                            .font(.caption)
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
                Button {
                    Task {
                        isTesting = true
                        testLines = await coach.testModels()
                        isTesting = false
                    }
                } label: {
                    HStack {
                        Text("Tester chaque modèle")
                        if isTesting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!coach.hasKey || isTesting)
                ForEach(testLines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Color.rc.textSecondary)
                }
                NavigationLink("Diagnostic") { AIDiagnosticView() }
            } header: {
                Text("Modèles")
            } footer: {
                Text("Plan, bilan et questions d'entraînement commencent par le plus capable ; un simple échange commence par le plus léger. Quand un modèle atteint son quota, le coach passe au suivant. Le test envoie une question minuscule, sans aucune donnée personnelle, et consomme une requête par modèle.")
            }

            Section {
                Text("Le coach reçoit des résumés chiffrés : âge, volumes, allures, bilan de forme, charge, sommeil, FC au repos, séances prévues, ce que tu as noté dans « Blessures ou antécédents », et tes messages. Jamais ta position, tes tracés, le nom des lieux ni ton prénom.")
                Text(dataNotice)
                    .foregroundStyle(coach.providerId == LLMProvider.gemini.id ? Color.rc.warning : Color.rc.textPrimary)
            } header: {
                Text("Tes données")
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Coach IA")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: coach.providerId) {
            key = ""
            testLines = []
        }
    }

    private var keyHelp: String {
        coach.providerId == LLMProvider.gemini.id
            ? "Crée-la sur aistudio.google.com, rubrique « Get API key »."
            : "Crée-la sur console.groq.com, rubrique « API Keys »."
    }

    /// Vérifié dans les pages officielles le 2026-11-13 (ARCHITECTURE.md §6.7).
    private var dataNotice: String {
        coach.providerId == LLMProvider.gemini.id
            ? "Gemini : en Europe, les conditions de Google appliquent au quota gratuit les règles de l'offre payante : tes requêtes ne servent pas à améliorer ses produits. Il n'y a pas d'interrupteur à activer. Mais ces mêmes conditions réservent l'API à un usage professionnel (« not for consumer use ») : un usage personnel reste une zone grise, à toi de décider."
            : "Groq : tes requêtes ne sont pas conservées par défaut, sauf des journaux techniques de 30 jours au plus. Pour les couper, active Zero Data Retention : console.groq.com, Settings, Data Controls. Données conservées aux États-Unis."
    }
}

/// Journal des appels à l'IA depuis l'ouverture de l'app : modèle, code HTTP, durée, message d'erreur du fournisseur.
struct AIDiagnosticView: View {
    @Environment(CoachService.self) private var coach

    var body: some View {
        List {
            if coach.diagnostics.isEmpty {
                Text("Aucun appel depuis l'ouverture de l'app.")
                    .foregroundStyle(Color.rc.textSecondary)
            }
            ForEach(Array(coach.diagnostics.enumerated().reversed()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Diagnostic IA")
        .navigationBarTitleDisplayMode(.inline)
    }
}
