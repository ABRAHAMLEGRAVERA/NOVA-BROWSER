import SwiftUI

struct AddressSuggestionsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let palette: NovaPalette

    private var query: String {
        viewModel.addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingBookmarks: [BookmarkItem] {
        guard !query.isEmpty else { return Array(viewModel.bookmarks.prefix(4)) }
        return viewModel.bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.urlString.localizedCaseInsensitiveContains(query)
        }.prefix(4).map { $0 }
    }

    private var matchingHistory: [HistoryEntry] {
        guard !query.isEmpty else { return Array(viewModel.history.prefix(4)) }
        var seen = Set<String>()
        return viewModel.history.filter { entry in
            let matches = entry.title.localizedCaseInsensitiveContains(query) ||
                entry.urlString.localizedCaseInsensitiveContains(query)
            guard matches, !seen.contains(entry.urlString) else { return false }
            seen.insert(entry.urlString)
            return true
        }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !query.isEmpty {
                Button {
                    viewModel.submitAddressOrSearch(query)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: URLResolver.looksLikeDomainOrHost(query) ? "arrow.right.circle.fill" : "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundColor(palette.accent)
                        Text(URLResolver.looksLikeDomainOrHost(query) ? "Ir a \(query)" : "Buscar «\(query)» en \(viewModel.settings.searchEngine.displayName)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(palette.primaryText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().background(palette.border)
            }

            if !matchingBookmarks.isEmpty {
                Text("FAVORITOS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                ForEach(matchingBookmarks) { item in
                    suggestionRow(
                        icon: "star.fill",
                        iconColor: Color(hex: "#F59E0B"),
                        title: item.title,
                        subtitle: item.urlString
                    ) {
                        viewModel.isEditingAddressBar = false
                        if let url = URL(string: item.urlString) {
                            viewModel.navigate(to: url)
                        }
                    }
                }
            }

            if !matchingHistory.isEmpty {
                Text("HISTORIAL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                ForEach(matchingHistory) { entry in
                    suggestionRow(
                        icon: "clock",
                        iconColor: palette.secondaryText,
                        title: entry.title,
                        subtitle: entry.urlString
                    ) {
                        viewModel.isEditingAddressBar = false
                        if let url = URL(string: entry.urlString) {
                            viewModel.navigate(to: url)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: 600)
        .background(palette.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 6)
    }

    private func suggestionRow(icon: String, iconColor: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
