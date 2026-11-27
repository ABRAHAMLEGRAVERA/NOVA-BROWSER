import SwiftUI

struct StartPageView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let palette: NovaPalette
    let isIncognito: Bool

    @State private var searchQuery: String = ""
    @State private var isEditingShortcuts: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 136), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header Emblem
                VStack(spacing: 10) {
                    if isIncognito {
                        ZStack {
                            Circle()
                                .fill(palette.incognitoAccent.opacity(0.16))
                                .frame(width: 60, height: 60)
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(palette.incognitoAccent)
                        }
                        Text("Navegación privada")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(palette.primaryText)
                        Text("Esta pestaña no guarda historial ni cookies al cerrarse.")
                            .font(.system(size: 13))
                            .foregroundColor(palette.secondaryText)
                            .multilineTextAlignment(.center)
                    } else {
                        NovaEmblemView(size: 56, accent: palette.accent)
                        Text("NOVA")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .tracking(2.5)
                            .foregroundColor(palette.primaryText)
                    }
                }
                .padding(.top, 36)

                // Start Page Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.secondaryText)

                    TextField("Buscar en \(viewModel.settings.searchEngine.displayName) o escribir dirección", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundColor(palette.primaryText)
                        .keyboardType(.webSearch)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit {
                            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            searchQuery = ""
                            viewModel.submitAddressOrSearch(trimmed)
                        }

                    if !searchQuery.isEmpty {
                        Button {
                            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            searchQuery = ""
                            viewModel.submitAddressOrSearch(trimmed)
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(palette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Buscar")
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .frame(maxWidth: 560)
                .background(palette.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)

                // Quick Shortcuts Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Accesos rápidos")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(palette.primaryText)

                        Spacer()

                        Button(isEditingShortcuts ? "Listo" : "Editar") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isEditingShortcuts.toggle()
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(palette.accent)
                        .buttonStyle(.plain)

                        Button {
                            viewModel.editingShortcut = nil
                            viewModel.showShortcutEditor = true
                        } label: {
                            Label("Añadir", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(palette.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(viewModel.shortcuts) { shortcut in
                            ShortcutTileView(
                                shortcut: shortcut,
                                palette: palette,
                                isEditing: isEditingShortcuts,
                                onTap: {
                                    if isEditingShortcuts {
                                        viewModel.editingShortcut = shortcut
                                        viewModel.showShortcutEditor = true
                                    } else if let url = URL(string: shortcut.urlString) {
                                        viewModel.navigate(to: url)
                                    }
                                },
                                onEdit: {
                                    viewModel.editingShortcut = shortcut
                                    viewModel.showShortcutEditor = true
                                },
                                onDelete: {
                                    viewModel.deleteShortcut(shortcut)
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: 720)

                // Favorites Preview Section
                if !viewModel.bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Favoritos")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(palette.primaryText)

                            Spacer()

                            Button("Ver todos") {
                                viewModel.libraryInitialTab = .bookmarks
                                viewModel.showLibrary = true
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(palette.accent)
                            .buttonStyle(.plain)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.bookmarks.prefix(8)) { bookmark in
                                    Button {
                                        if let url = URL(string: bookmark.urlString) {
                                            viewModel.navigate(to: url)
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(hex: "#F59E0B"))
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(bookmark.title)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(palette.primaryText)
                                                    .lineLimit(1)
                                                Text(bookmark.host)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(palette.secondaryText)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .frame(maxWidth: 200, alignment: .leading)
                                        .background(palette.elevatedSurface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(palette.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 720)
                }

                // Minimal Privacy Summary
                HStack(spacing: 8) {
                    Image(systemName: viewModel.settings.adBlockerEnabled ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 13))
                        .foregroundColor(viewModel.settings.adBlockerEnabled ? palette.shieldActive : palette.secondaryText)

                    Text(
                        viewModel.settings.adBlockerEnabled
                            ? "Escudo NOVA activo · \(viewModel.settings.totalBlockedLifetime) elementos bloqueados"
                            : "Escudo NOVA desactivado"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvasBackground)
    }
}

private struct ShortcutTileView: View {
    let shortcut: QuickShortcut
    let palette: NovaPalette
    let isEditing: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: shortcut.colorHex).opacity(0.16))
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(hex: shortcut.colorHex).opacity(0.32), lineWidth: 1)
                            )

                        Text(shortcut.monogram)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: shortcut.colorHex))
                    }

                    VStack(spacing: 2) {
                        Text(shortcut.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(palette.primaryText)
                            .lineLimit(1)

                        Text(shortcut.host)
                            .font(.system(size: 10))
                            .foregroundColor(palette.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(palette.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(action: onEdit) {
                    Label("Editar acceso", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Eliminar", systemImage: "trash")
                }
            }

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .background(Circle().fill(palette.elevatedSurface))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Eliminar \(shortcut.title)")
            }
        }
    }
}
