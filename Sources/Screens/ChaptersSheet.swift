import SwiftUI

/// Fəsillər və əlfəcinlər. Now Playing-dən açılır; səsli kitablar üçün əsas naviqasiya.
struct ChaptersSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingBookmark = false
    @State private var bookmarkNote = ""

    var body: some View {
        NavigationStack {
            List {
                if !player.chapters.isEmpty { chapterSection }
                bookmarkSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.base)
            .navigationTitle(player.chapters.isEmpty
                             ? LocalizedStringKey("bookmarks.title")
                             : LocalizedStringKey("chapters.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
            .alert("bookmarks.add", isPresented: $isAddingBookmark) {
                TextField("bookmarks.notePlaceholder", text: $bookmarkNote)
                Button("action.cancel", role: .cancel) { bookmarkNote = "" }
                Button("action.save") {
                    player.addBookmark(note: bookmarkNote)
                    bookmarkNote = ""
                }
            } message: {
                Text(String(format: String(localized: "bookmarks.addAt"), player.snapshot.position.timeLabel))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Bölmələr

    private var chapterSection: some View {
        Section {
            ForEach(player.chapters) { chapter in
                ChapterRow(
                    number: chapter.id + 1,
                    title: chapter.title,
                    start: chapter.start,
                    duration: chapter.duration,
                    isCurrent: player.currentChapter?.id == chapter.id
                ) {
                    player.selectChapter(chapter)
                }
            }
        } header: {
            Text("chapters.section")
        }
    }

    private var bookmarkSection: some View {
        Section {
            Button {
                isAddingBookmark = true
            } label: {
                Label("bookmarks.addHere", systemImage: "bookmark")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .disabled(player.current == nil)

            ForEach(bookmarks) { bookmark in
                BookmarkRow(bookmark: bookmark, chapterTitle: chapterTitle(at: bookmark.position)) {
                    player.jump(to: bookmark)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        player.deleteBookmark(bookmark)
                    } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("bookmarks.section")
        } footer: {
            if bookmarks.isEmpty {
                Text("bookmarks.empty")
            }
        }
    }

    private var bookmarks: [Bookmark] {
        player.current?.sortedBookmarks ?? []
    }

    private func chapterTitle(at seconds: Double) -> String? {
        player.chapters.last { $0.start <= seconds }.map { chapter in
            chapter.title.isEmpty
                ? String(format: String(localized: "chapters.numbered"), chapter.id + 1)
                : chapter.title
        }
    }
}

private struct ChapterRow: View {
    let number: Int
    let title: String
    let start: Double
    let duration: Double
    let isCurrent: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                Group {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .foregroundStyle(Theme.Colors.accent)
                    } else {
                        Text("\(number)")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(Theme.Text.rowTitle)
                        .foregroundStyle(isCurrent ? Theme.Colors.accent : Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Text(start.timeLabel)
                        .font(Theme.Text.numeric)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Text(duration.timeLabel)
                    .font(Theme.Text.numeric)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var displayTitle: String {
        title.isEmpty ? String(format: String(localized: "chapters.numbered"), number) : title
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let chapterTitle: String?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Text.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Text(bookmark.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Text(bookmark.position.timeLabel)
                    .font(Theme.Text.numeric)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if !bookmark.note.isEmpty { return bookmark.note }
        return chapterTitle ?? String(localized: "bookmarks.untitled")
    }
}
