import SwiftUI
import RunCoachCore

/// Réglages → Coach IA : choix Groq ou Gemini, une clé personnelle par fournisseur (Keychain), modèle, test,
/// et ce que chaque fournisseur fait des données (§6.7).
struct AISettingsView: View {
    @Environment(CoachService.self) private var coach
    @State private var key = ""
    @State private var model = ""
    @State private var testResult: String?
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
                    testResult = nil
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if coach.hasKey {
                    Button("Supprimer la clé", role: .destructive) {
                        coach.setKey("")
                        testResult = nil
                    }
                }
                Button {
                    coach.setModel(model)
                    Task {
                        isTesting = true
                        testResult = await coach.testKey()
                        isTesting = false
                    }
                } label: {
                    HStack {
                        Text("Tester")
                        if isTesting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!coach.hasKey || isTesting)
                if let testResult {
                    Text(testResult)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            } header: {
                Text("Clé \(coach.provider.name)")
            } footer: {
                Text(keyHelp + " La clé reste dans le trousseau de l'iPhone. Le test n'envoie aucune donnée personnelle.")
            }

            Section {
                TextField("Modèle", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { coach.setModel(model) }
                Button("Modèle par défaut") {
                    model = defaultModel
                    coach.setModel("")
                }
            } header: {
                Text("Modèle")
            } footer: {
                Text("Par défaut : \(defaultModel). Change-le seulement si le fournisseur le retire.")
            }

            Section {
                Text("Le coach reçoit des résumés chiffrés : âge, volumes, allures, bilan de forme, charge, sommeil, séances prévues. Jamais ta position, tes tracés, le nom des lieux ni ton prénom.")
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
        .onAppear { model = coach.provider.model }
        .onChange(of: coach.providerId) {
            model = coach.provider.model
            key = ""
            testResult = nil
        }
        .onDisappear { coach.setModel(model == defaultModel ? "" : model) }
    }

    private var defaultModel: String {
        (LLMProvider.presets.first { $0.id == coach.providerId } ?? .groq).model
    }

    private var keyHelp: String {
        coach.providerId == LLMProvider.gemini.id
            ? "Crée-la sur aistudio.google.com, rubrique « Get API key »."
            : "Crée-la sur console.groq.com, rubrique « API Keys »."
    }

    /// Vérifié dans les pages officielles le 2026-11-13 (ARCHITECTURE.md §6.7).
    private var dataNotice: String {
        coach.providerId == LLMProvider.gemini.id
            ? "Gemini : en Europe, Google n'utilise pas tes requêtes pour entraîner ses modèles, même en gratuit. Mais ses conditions réservent l'API à un usage professionnel (« not for consumer use ») et demandent l'offre payante pour une app proposée à des utilisateurs en Europe : un usage personnel reste une zone grise, à toi de décider."
            : "Groq : tes requêtes ne sont pas conservées par défaut, sauf des journaux techniques de 30 jours au plus. Pour les couper, active Zero Data Retention : console.groq.com, Settings, Data Controls. Données conservées aux États-Unis."
    }
}
