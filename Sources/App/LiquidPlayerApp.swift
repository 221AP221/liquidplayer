import SwiftData
import SwiftUI

@main
struct LiquidPlayerApp: App {
    @State private var player = PlayerController()

    private let container: ModelContainer = {
        let schema = Schema([MediaItem.self, LibraryFolder.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Baza açılmırsa app-ı çökdürmək əvəzinə yaddaşda işləyirik;
            // istifadəçi kitabxananı yenidən qura bilər.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: fallback)
        }
    }()

    var body: some Scene {
        WindowGroup {
            LibraryImportHost {
                RootView()
            }
            .environment(player)
            .task { player.attach(context: container.mainContext) }
        }
        .modelContainer(container)
    }
}

// MARK: - Qovluq idxalı

/// Qovluq seçici bir yerdə dursun deyə ekranlar onu birbaşa açmır —
/// mühitdən gələn `libraryImportAction` çağırırlar.
struct LibraryImportHost<Content: View>: View {
    @Environment(\.modelContext) private var context
    @State private var isPickerPresented = false
    @State private var importer: LibraryImporter?
    @State private var importError: String?

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.libraryImportAction, LibraryImportAction { isPickerPresented = true })
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    startImport(of: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .overlay(alignment: .top) {
                if let importer, !importer.progress.isFinished, importer.progress.total > 0 {
                    ImportProgressBanner(progress: importer.progress)
                        .padding(.horizontal, Theme.Spacing.md)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert(
                "import.failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("action.ok", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
    }

    private func startImport(of url: URL) {
        let newImporter = LibraryImporter(context: context)
        importer = newImporter
        Task {
            do {
                try await newImporter.importFolder(at: url)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

struct ImportProgressBanner: View {
    let progress: LibraryImporter.Progress

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("import.running")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(progress.processed) / \(progress.total) · \(progress.currentFilename)")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .glassCard(cornerRadius: 18, elevated: true)
    }
}

// MARK: - Mühit açarı

struct LibraryImportAction {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func callAsFunction() { handler() }
}

private struct LibraryImportActionKey: EnvironmentKey {
    static let defaultValue = LibraryImportAction {}
}

extension EnvironmentValues {
    var libraryImportAction: LibraryImportAction {
        get { self[LibraryImportActionKey.self] }
        set { self[LibraryImportActionKey.self] = newValue }
    }
}
