import SwiftUI

struct LibrarySheetView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: BrowserViewModel

    @State private var selectedSection: LibrarySection
    @State private var searchQuery: String = ""
    @State private var showClearHistoryConfirm: Bool = false
    @State private var editingBookmark: BookmarkItem? = nil
    @State private var showAddBookmarkSheet: Bool = false

    init(viewModel: BrowserViewModel) {
        self.viewModel = viewModel
        _selectedSection = State(initialValue: viewModel.libraryInitialTab)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Sección", selection: $selectedSection) {
                    ForEach(LibrarySection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filtrar \(selectedSection.rawValue.lowercased())...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if selectedSection == .bookmarks {
                    bookmarksList
                } else {
                    historyList
                }
            }
            .navigationTitle(selectedSection.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedSection == .bookmarks {
                        Button {
                            editingBookmark = nil
                            showAddBookmarkSheet = true
                        } label: {
                            Label("Añadir", systemImage: "plus")
                        }
                    } else if !viewModel.history.isEmpty {
                        Button("Borrar historial") {
                            showClearHistoryConfirm = true
                        }
                        .foregroundColor(.red)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("¿Borrar todo el historial?", isPresented: $showClearHistoryConfirm) {
                Button("Borrar", role: .destructive) {
                    viewModel.clearHistory()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminarán todas las páginas visitadas del historial.")
            }
            .sheet(isPresented: $showAddBookmarkSheet) {
                BookmarkEditorSheet(bookmark: editingBookmark) { title, urlString in
                    if let existing = editingBookmark {
                        viewModel.updateBookmark(existing, title: title, urlString: urlString)
                    } else {
                        viewModel.addBookmark(title: title, urlString: urlString)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var filteredBookmarks: [BookmarkItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return viewModel.bookmarks }
        return viewModel.bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.urlString.localizedCaseInsensitiveContains(q)
        }
    }

    private var filteredHistory: [HistoryEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return viewModel.history }
        return viewModel.history.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.urlString.localizedCaseInsensitiveContains(q)
        }
    }

    private var bookmarksList: some View {
        Group {
            if filteredBookmarks.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "star")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(viewModel.bookmarks.isEmpty ? "No tienes favoritos guardados" : "Sin resultados")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredBookmarks) { item in
                        Button {
                            if let url = URL(string: item.urlString) {
                                viewModel.navigate(to: url)
                                presentationMode.wrappedValue.dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(Color(hex: "#F59E0B"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(item.urlString)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .contextMenu {
                            Button {
                                if let url = URL(string: item.urlString) {
                                    viewModel.createNewTab(url: url)
                                    presentationMode.wrappedValue.dismiss()
                                }
                            } label: {
                                Label("Abrir en nueva pestaña", systemImage: "plus.square.on.square")
                            }
                            Button {
                                editingBookmark = item
                                showAddBookmarkSheet = true
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                viewModel.deleteBookmark(item)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        let itemsToDelete = offsets.map { filteredBookmarks[$0] }
                        for item in itemsToDelete {
                            viewModel.deleteBookmark(item)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
    }

    private var historyList: some View {
        Group {
            if filteredHistory.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(viewModel.history.isEmpty ? "El historial está vacío" : "Sin resultados")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredHistory) { entry in
                        Button {
                            if let url = URL(string: entry.urlString) {
                                viewModel.navigate(to: url)
                                presentationMode.wrappedValue.dismiss()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(entry.urlString)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(entry.visitedAt, style: .time)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { offsets in
                        let entriesToDelete = offsets.map { filteredHistory[$0] }
                        for entry in entriesToDelete {
                            viewModel.deleteHistoryEntry(entry)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
    }
}

struct BookmarkEditorSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let bookmark: BookmarkItem?
    let onSave: (String, String) -> Void

    @State private var title: String
    @State private var urlString: String

    init(bookmark: BookmarkItem?, onSave: @escaping (String, String) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave
        _title = State(initialValue: bookmark?.title ?? "")
        _urlString = State(initialValue: bookmark?.urlString ?? "https://")
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("Título", text: $title)
                TextField("URL", text: $urlString)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .navigationTitle(bookmark == nil ? "Añadir favorito" : "Editar favorito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(title, urlString)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
