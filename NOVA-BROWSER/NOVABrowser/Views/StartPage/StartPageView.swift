import SwiftUI

struct StartPageView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let palette: NovaPalette
    let isIncognito: Bool

    @State private var searchQuery: String = ""
    @State private var isEditingShortcuts: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 94, maximum: 132), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                // Minimal Safari-inspired Header Emblem
                VStack(spacing: 10) {
                    if isIncognito {
                        ZStack {
                            Circle()
                                .fill(palette.incognitoAccent.opacity(0.16))
                                .frame(width: 58, height: 58)
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(palette.incognitoAccent)
                        }
                        Text("Navegación privada")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(palette.primaryText)
                        Text("Esta pestaña no guarda historial, cookies ni contraseñas al cerrarse.")
                            .font(.system(size: 13))
                            .foregroundColor(palette.secondaryText)
                            .multilineTextAlignment(.center)
                    } else {
                        NovaEmblemView(size: 52, accent: palette.accent)
                        Text("NOVA")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .tracking(2.5)
                            .foregroundColor(palette.primaryText)
                    }
                }
                .padding(.top, 32)

                // Start Page Capsule Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(palette.secondaryText)

                    TextField("Buscar en Google o escribir dirección", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
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
                .frame(height: 44)
                .frame(maxWidth: 540)
                .background(palette.elevatedSurface)
                .overlay(
                    Capsule()
                        .stroke(palette.border, lineWidth: 0.6)
                )
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)

                // Quick Shortcuts Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Favoritos frecuentes")
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
                .frame(maxWidth: 700)

                // Bookmarks Preview Section
                if !viewModel.bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Marcadores")
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
                                                .stroke(palette.border, lineWidth: 0.6)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 700)
                }

                // Minimal Safari-style Privacy & Passwords Report Pills
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: viewModel.settings.adBlockerEnabled ? "checkmark.shield.fill" : "shield.slash")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.settings.adBlockerEnabled ? palette.shieldActive : palette.secondaryText)

                        Text(
                            viewModel.settings.adBlockerEnabled
                                ? "Escudo activo · \(viewModel.settings.totalBlockedLifetime) bloqueados"
                                : "Escudo desactivado"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(palette.elevatedSurface)
                    .overlay(Capsule().stroke(palette.border, lineWidth: 0.6))
                    .clipShape(Capsule())

                    Button {
                        viewModel.showPasswords = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 11))
                                .foregroundColor(palette.accent)
                            Text("Contraseñas (\(viewModel.passwordStore.credentials.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(palette.primaryText)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(palette.elevatedSurface)
                        .overlay(Capsule().stroke(palette.border, lineWidth: 0.6))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 20)
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
                VStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: shortcut.colorHex).opacity(0.16))
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(hex: shortcut.colorHex).opacity(0.32), lineWidth: 0.8)
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
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .background(palette.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.border, lineWidth: 0.6)
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
