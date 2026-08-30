import SwiftData
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case library, folders, search, more

    var titleKey: LocalizedStringKey {
        switch self {
        case .library: "tab.library"
        case .folders: "tab.folders"
        case .search:  "tab.search"
        case .more:    "tab.more"
        }
    }

    var symbol: String {
        switch self {
        case .library: "music.note.list"
        case .folders: "folder"
        case .search:  "magnifyingglass"
        case .more:    "line.3.horizontal"
        }
    }
}

/// Tab bar, mini-player və Now Playing bir-birinin üstündə dayanır.
/// Naviqasiya yığını hər tabın öz içindədir.
struct RootView: View {
    @Environment(PlayerController.self) private var player
    @State private var tab: AppTab = .library

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.Colors.base.ignoresSafeArea()

            Group {
                switch tab {
                case .library: LibraryScreen()
                case .folders: FoldersScreen()
                case .search:  SearchScreen()
                case .more:    SettingsScreen()
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                if player.current != nil {
                    MiniPlayerBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                TabBar(selection: $tab)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)
            .animation(Theme.Motion.snap, value: player.current?.id)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Bindable(player).isExpanded) {
            NowPlayingScreen()
        }
        .overlay(alignment: .bottom) {
            if let notice = player.notice {
                PlaybackNoticeSheet(notice: notice)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(Theme.Motion.snap, value: player.notice)
    }
}

struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isOn = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.titleKey)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isOn ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .hitTarget()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(height: Theme.Size.tabBar)
        .glassCard(cornerRadius: Theme.Size.tabBar / 2, elevated: true)
        .padding(.horizontal, Theme.Spacing.md)
    }
}
