import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import RunCoachCore

/// Réglages, ouverts dans la pile de l'écran Aujourd'hui (bouton retour et glissement natifs).
/// Tout ce qui façonne le plan est modifiable ici : objectif, disponibilités, profil, santé (demande de l'utilisateur, 2026-11-13).
struct SettingsView: View {
    @Query private var profiles: [AthleteProfile]
    @Query private var goals: [Goal]
    @Query private var syncStates: [SyncState]
    @Environment(SyncEngine.self) private var sync
    @Environment(CoachService.self) private var coach
    @State private var showOnboarding = false
    @State private var showGarminLogin = false
    @Environment(\.modelContext) private var context
    @AppStorage(Notifications.enabledKey) private var notificationsOn = false
    @AppStorage(Notifications.minuteKey) private var reminderMinute = Notifications.defaultMinute
    @State private var notificationsDenied = false
    @State private var backup: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingRestore: Data?
    @State private var backupMessage: String?

    var body: some View {
        Form {
            Section {
                NavigationLink(value: AppRoute.goal) {
                    row("Objectif", icon: "flag.checkered", value: goalSummary)
                }
                NavigationLink(value: AppRoute.training) {
                    row("Entraînement", icon: "calendar", value: trainingSummary)
                }
                NavigationLink(value: AppRoute.profile) {
                    row("Toi", icon: "person.fill", value: profiles.first.map { $0.firstName.isEmpty ? "" : $0.firstName } ?? "")
                }
                NavigationLink(value: AppRoute.health) {
                    row("Santé", icon: "cross.case.fill", value: ["mild": "Gêne légère", "severe": "Douleur nette"][profiles.first?.pain ?? "none"] ?? "")
                }
            } header: {
                Text("Ton plan")
            }

            Section {
                Button {
                    Task { await coach.generateNextWeek() }
                } label: {
                    HStack {
                        Text("Mettre à jour la semaine prochaine")
                        if coach.isGenerating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(coach.isGenerating)
                if coach.isGenerating, let status = coach.generationStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Color.rc.textSecondary)
                }
                if let notice = coach.notice {
                    Text(notice)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            } footer: {
                Text("Après un changement d'objectif, de jours ou de santé : le plan jusqu'à la course est recalculé et la semaine prochaine régénérée. Les séances déjà faites ne bougent pas.")
            }

            Section {
                NavigationLink(value: AppRoute.ai) {
                    row(coach.provider.name, icon: "sparkles", value: coach.hasKey ? "Clé enregistrée" : "Aucune clé")
                }
            } header: {
                Text("Coach IA")
            } footer: {
                Text("Sans clé, un plan de secours calculé sans IA est proposé. Seuls des résumés chiffrés sont envoyés au coach, jamais ta position.")
            }

            Section {
                HStack {
                    Label("Compte Garmin", systemImage: "applewatch")
                    Spacer()
                    Text(sync.isConnected ? (syncStates.first?.garminDisplayName ?? "Connecté") : "Non connecté")
                        .foregroundStyle(Color.rc.textSecondary)
                }
                if let last = syncStates.first?.lastGarminSyncAt {
                    HStack {
                        Text("Dernière synchro")
                        Spacer()
                        Text(last.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))))
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
                if sync.phase == .syncing {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text(sync.progress ?? "Synchro…")
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
                if let message = sync.message {
                    Text(message)
                        .foregroundStyle(Color.rc.danger)
                }
                if sync.isConnected {
                    Button("Synchroniser maintenant") {
                        Task { await sync.sync(background: false) }
                    }
                    .disabled(sync.phase == .syncing)
                    Button("Se déconnecter", role: .destructive) {
                        Task { await sync.logout() }
                    }
                } else {
                    Button("Se connecter à Garmin") { showGarminLogin = true }
                }
                NavigationLink("Diagnostic", value: AppRoute.garminDiagnostic)
            } header: {
                Text("Garmin")
            } footer: {
                Text("Accès non officiel : Garmin peut le bloquer ou restreindre le compte. Tes identifiants sont saisis sur la page de Garmin, l'app ne les voit jamais. Se déconnecter garde les sorties déjà importées.")
            }

            Section {
                Toggle("Rappels", isOn: $notificationsOn)
                if notificationsOn {
                    DatePicker("Séance du jour à", selection: Binding(
                        get: { Calendar.current.date(bySettingHour: reminderMinute / 60, minute: reminderMinute % 60, second: 0, of: Date()) ?? Date() },
                        set: {
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                            reminderMinute = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(notificationsDenied
                     ? "Notifications refusées : autorise-les dans Réglages iOS → RunCoach."
                     : "Séance du jour, point du dimanche à 19 h, et rappel 2 jours avant que l'app expire.")
            }
            .onChange(of: notificationsOn) { _, on in
                Task {
                    if on { notificationsDenied = !(await Notifications.requestAuthorization()) }
                    await Notifications.reschedule(context: context)
                }
            }
            .onChange(of: reminderMinute) {
                Task { await Notifications.reschedule(context: context) }
            }

            Section {
                Button("Sauvegarder mes données") { exportBackup() }
                Button("Restaurer une sauvegarde") { showImporter = true }
                    .disabled(sync.phase == .syncing)
            } header: {
                Text("Tes données")
            } footer: {
                Text("Un fichier avec tes sorties, ton plan, ton profil et la conversation, à ranger dans Fichiers ou iCloud Drive. Il contient tes tracés GPS et des données de santé : garde-le pour toi. Ni ta connexion Garmin ni ta clé IA n'y sont.")
            }
            Section {
                Button("Refaire la configuration") {
                    showOnboarding = true
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                        .foregroundStyle(Color.rc.textSecondary)
                }
                if let expiry = Notifications.signatureExpiry {
                    HStack {
                        Text("Signature valable jusqu'au")
                        Spacer()
                        Text(expiry.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                            .foregroundStyle(expiry.timeIntervalSinceNow < 2 * 86_400 ? Color.rc.danger : Color.rc.textSecondary)
                    }
                }
            } header: {
                Text("À propos")
            } footer: {
                Text("Cette app ne remplace pas un avis médical. En cas de douleur ou de doute, consulte.")
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlow(onFinish: { showOnboarding = false })
        }
        .fullScreenCover(isPresented: $showGarminLogin) { GarminLoginView() }
        .fileExporter(isPresented: $showExporter, document: backup, contentType: .json,
                      defaultFilename: "RunCoach-sauvegarde-\(DayKey.key(Date()))") { result in
            if case .failure = result { backupMessage = "La sauvegarde n'a pas pu être enregistrée." }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try? Data(contentsOf: url)
            if pendingRestore == nil { backupMessage = "Ce fichier n'a pas pu être lu." }
        }
        .confirmationDialog("Remplacer toutes tes données par cette sauvegarde ?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button("Remplacer", role: .destructive) { restoreBackup() }
            Button("Annuler", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Ce qui est sur l'iPhone sera effacé et remplacé. Pense à sauvegarder d'abord si besoin.")
        }
        .alert(backupMessage ?? "", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func exportBackup() {
        do {
            backup = BackupDocument(data: try Backup.export(context))
            showExporter = true
        } catch {
            backupMessage = "La sauvegarde a échoué."
        }
    }

    private func restoreBackup() {
        guard let data = pendingRestore else { return }
        pendingRestore = nil
        do {
            try Backup.restore(data, into: context)
            backupMessage = "Sauvegarde restaurée. Reconnecte Garmin et ta clé IA si c'est une nouvelle installation."
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func row(_ title: String, icon: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .lineLimit(1)
                .foregroundStyle(Color.rc.textSecondary)
        }
    }

    private var goalSummary: String {
        guard let goal = goals.first(where: { $0.isActive }) else { return "Aucun" }
        return goal.name + (goal.targetTimeS.map { " · " + Fmt.duration($0) } ?? "")
    }

    private var trainingSummary: String {
        guard let profile = profiles.first else { return "" }
        let count = profile.availableWeekdays.count
        return "\(count) jour\(count > 1 ? "s" : "") par semaine"
    }
}
