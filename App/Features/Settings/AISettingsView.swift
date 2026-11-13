import SwiftUI
import RunCoachCore

/// Réglages → Coach IA : clé personnelle (Keychain), modèle, test, et ce que le fournisseur fait des données (§6.7).
struct AISettingsView: View {
    @Environment(CoachService.self) private var coach
    @State private var key = ""
    @State private var model = ""
    @State private var baseURL = ""
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var hasKey = false

    var body: some View {
        Form {
            Section {
                SecureField(hasKey ? "Clé enregistrée (la remplacer)" : "Colle ta clé ici", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer la clé") {
                    coach.setKey(key)
                    key = ""
                    hasKey = coach.hasKey
                    testResult = nil
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasKey {
                    Button("Supprimer la clé", role: .destructive) {
                        coach.setKey("")
                        hasKey = false
                        testResult = nil
                    }
                }
            } header: {
                Text("Clé Mistral")
            } footer: {
                Text("Crée-la sur console.mistral.ai (offre gratuite « Experiment »). Elle reste dans le trousseau de l'iPhone, jamais dans le dépôt ni dans un fichier.")
            }

            Section {
                Button {
                    saveProvider()
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
                .disabled(!hasKey || isTesting)
                if let testResult {
                    Text(testResult)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            } footer: {
                Text("Envoie une seule question sans aucune donnée personnelle.")
            }

            Section {
                TextField("Modèle", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Adresse de l'API", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Revenir aux valeurs Mistral") {
                    model = LLMProvider.mistral.model
                    baseURL = LLMProvider.mistral.baseURL.absoluteString
                }
            } header: {
                Text("Modèle")
            } footer: {
                Text("Par défaut, le modèle le plus capable de Mistral (mistral-large-latest). Change-le seulement si Mistral le retire ou si ton quota gratuit ne le permet pas.")
            }

            Section {
                Text("Le coach reçoit des résumés chiffrés : âge, volumes, allures, charge, sommeil. Jamais ta position, tes tracés, le nom des lieux ni ton prénom.")
                Text("Avec l'offre gratuite, Mistral peut utiliser tes requêtes pour entraîner ses modèles. Désactive-le : console.mistral.ai, menu Privacy, interrupteur d'entraînement sur les données.")
                    .foregroundStyle(Color.rc.warning)
            } header: {
                Text("Tes données")
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Coach IA")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasKey = coach.hasKey
            model = coach.provider.model
            baseURL = coach.provider.baseURL.absoluteString
        }
        .onDisappear { saveProvider() }
    }

    /// Adresse en https seulement : la clé ne part jamais en clair.
    private func saveProvider() {
        let name = model.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)), url.scheme == "https", !name.isEmpty {
            coach.provider = LLMProvider(baseURL: url, model: name)
        }
    }
}
