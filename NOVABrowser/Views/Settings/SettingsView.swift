import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: BrowserViewModel

    @State private var showClearHistoryAlert = false
    @State private var showClearCookiesAlert = false
    @State private var showClearPasswordsAlert = false
    @State private var showClearAllDataAlert = false

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                // 1. Bloqueador de anuncios
                Section(
                    header: Text("Bloqueador de anuncios y rastreadores"),
                    footer: Text("Utiliza reglas nativas WKContentRuleList de WebKit junto con omisión automática inteligente en reproductores de vídeo.")
                ) {
                    Toggle("Activar bloqueador inteligente", isOn: Binding(
                        get: { viewModel.settings.adBlockerEnabled },
                        set: { viewModel.setAdBlockerEnabled($0) }
                    ))

                    HStack {
                        Text("Estado")
                        Spacer()
                        Text(adBlockStatusLabel)
                            .foregroundColor(.secondary)
                    }

                    if let lastUpdated = viewModel.adBlocker.metadata.lastUpdated {
                        HStack {
                            Text("Última actualización")
                            Spacer()
                            Text(lastUpdated, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        viewModel.refreshAdBlockerList()
                    } label: {
                        HStack {
                            Text("Actualizar listas ahora")
                            Spacer()
                            if viewModel.adBlocker.isUpdatingList {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.adBlocker.isUpdatingList)

                    if let msg = viewModel.adBlocker.lastUpdateMessage {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    NavigationLink(destination: ExceptionsManagerView(viewModel: viewModel)) {
                        HStack {
                            Text("Administrar excepciones")
                            Spacer()
                            Text("\(viewModel.settings.whitelistedDomains.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 2. Contraseñas y sesiones
                Section(
                    header: Text("Contraseñas y sesiones"),
                    footer: Text("Las contraseñas se cifran en el Llavero de iOS. Las sesiones y cookies normales se conservan al cerrar el navegador.")
                ) {
                    Toggle("Guardar contraseñas al iniciar sesión", isOn: Binding(
                        get: { viewModel.settings.autoSavePasswords },
                        set: { value in
                            viewModel.updateSettings { $0.autoSavePasswords = value }
                        }
                    ))

                    Button {
                        presentationMode.wrappedValue.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            viewModel.showPasswords = true
                        }
                    } label: {
                        HStack {
                            Text("Administrar contraseñas")
                            Spacer()
                            Text("\(viewModel.passwordStore.credentials.count)")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }

                // 3. Privacidad y datos
                Section(header: Text("Privacidad y datos de navegación")) {
                    Button("Limpiar historial") {
                        showClearHistoryAlert = true
                    }
                    .foregroundColor(.red)

                    Button("Limpiar cookies y sesiones") {
                        showClearCookiesAlert = true
                    }
                    .foregroundColor(.red)

                    Button("Borrar contraseñas guardadas") {
                        showClearPasswordsAlert = true
                    }
                    .foregroundColor(.red)

                    Button("Limpiar todos los datos de navegación") {
                        showClearAllDataAlert = true
                    }
                    .foregroundColor(.red)
                }

                // 4. Favoritos
                Section(header: Text("Favoritos")) {
                    NavigationLink(destination: BookmarksSettingsManagerView(viewModel: viewModel)) {
                        HStack {
                            Text("Administrar favoritos")
                            Spacer()
                            Text("\(viewModel.bookmarks.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 5. Apariencia y modo oscuro web
                Section(
                    header: Text("Apariencia"),
                    footer: Text("El modo oscuro web oscurece páginas claras (y activa el tema oscuro de YouTube) manteniendo imágenes y vídeos con sus colores reales.")
                ) {
                    Picker("Tema de la aplicación", selection: Binding(
                        get: { viewModel.settings.appearanceMode },
                        set: { mode in
                            viewModel.updateSettings { $0.appearanceMode = mode }
                        }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Toggle("Forzar modo oscuro en páginas web", isOn: Binding(
                        get: { viewModel.settings.forceDarkWebPages },
                        set: { enabled in
                            viewModel.setForceDarkWebPages(enabled)
                        }
                    ))
                }

                // 6. Navegación, traductor, vídeo y página de inicio
                Section(
                    header: Text("Navegación, traductor y vídeo"),
                    footer: Text("La optimización de vídeo acelera YouTube y Shorts en iPad Air 2 y permite ventana flotante (PiP) al cambiar a otras apps como WhatsApp.")
                ) {
                    HStack {
                        Text("Motor de búsqueda")
                        Spacer()
                        Text("Google")
                            .foregroundColor(.secondary)
                    }

                    Picker("Idioma de traducción", selection: Binding(
                        get: { viewModel.settings.defaultTranslationLanguage },
                        set: { lang in
                            viewModel.updateSettings { $0.defaultTranslationLanguage = lang }
                        }
                    )) {
                        ForEach(TranslationLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }

                    Toggle("Optimización de vídeo y YouTube", isOn: Binding(
                        get: { viewModel.settings.videoPerformanceMode },
                        set: { value in
                            viewModel.updateSettings { $0.videoPerformanceMode = value }
                        }
                    ))

                    Picker("Página de inicio", selection: Binding(
                        get: { viewModel.settings.homePageMode },
                        set: { mode in
                            viewModel.updateSettings { $0.homePageMode = mode }
                        }
                    )) {
                        ForEach(HomePageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if viewModel.settings.homePageMode == .customURL {
                        TextField("URL de inicio personalizada", text: Binding(
                            get: { viewModel.settings.customHomeURLString },
                            set: { value in
                                viewModel.updateSettings { $0.customHomeURLString = value }
                            }
                        ))
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    }

                    Toggle("Modo escritorio predeterminado", isOn: Binding(
                        get: { viewModel.settings.defaultDesktopMode },
                        set: { value in
                            viewModel.updateSettings { $0.defaultDesktopMode = value }
                        }
                    ))

                    Toggle("Restaurar pestañas al abrir", isOn: Binding(
                        get: { viewModel.settings.restoreTabsOnLaunch },
                        set: { value in
                            viewModel.updateSettings { $0.restoreTabsOnLaunch = value }
                        }
                    ))
                }

                // 7. Acerca de
                Section(header: Text("Información de la aplicación")) {
                    HStack {
                        Text("Aplicación")
                        Spacer()
                        Text("NOVA Browser")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Versión")
                        Spacer()
                        Text(appVersionText)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Motor web")
                        Spacer()
                        Text("WKWebView (WebKit)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Compatibilidad")
                        Spacer()
                        Text("iPadOS 15.0+ · iPad Air 2")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("¿Limpiar historial?", isPresented: $showClearHistoryAlert) {
                Button("Limpiar", role: .destructive) {
                    viewModel.clearHistory()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrará todo el historial de navegación guardado.")
            }
            .alert("¿Limpiar cookies?", isPresented: $showClearCookiesAlert) {
                Button("Limpiar", role: .destructive) {
                    viewModel.clearCookies()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esto cerrará sesión en los sitios web donde hayas iniciado sesión.")
            }
            .alert("¿Borrar contraseñas?", isPresented: $showClearPasswordsAlert) {
                Button("Borrar todas", role: .destructive) {
                    viewModel.passwordStore.deleteAllCredentials()
                    viewModel.showToast("Contraseñas eliminadas")
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminarán todas las contraseñas guardadas en el Llavero de NOVA.")
            }
            .alert("¿Limpiar todos los datos?", isPresented: $showClearAllDataAlert) {
                Button("Limpiar todo", role: .destructive) {
                    viewModel.clearAllBrowsingData()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminarán el historial, las cookies, la caché y el almacenamiento local de sitios web.")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var adBlockStatusLabel: String {
        switch viewModel.adBlocker.status {
        case .ready(let count):
            return "\(count) reglas activas"
        case .compiling:
            return "Compilando..."
        case .disabled:
            return "Desactivado"
        case .idle:
            return "Inactivo"
        case .error:
            return "Protección local"
        }
    }
}

struct ExceptionsManagerView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var newDomain: String = ""

    var body: some View {
        List {
            Section(
                header: Text("Añadir excepción"),
                footer: Text("Los sitios en esta lista cargarán sin bloqueo de anuncios ni rastreadores.")
            ) {
                HStack {
                    TextField("ejemplo.com", text: $newDomain)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button("Añadir") {
                        viewModel.addWhitelistDomain(newDomain)
                        newDomain = ""
                    }
                    .disabled(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section(header: Text("Sitios permitidos")) {
                if viewModel.settings.whitelistedDomains.isEmpty {
                    Text("No hay excepciones configuradas")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.settings.whitelistedDomains, id: \.self) { domain in
                        Text(domain)
                    }
                    .onDelete { offsets in
                        let domains = offsets.map { viewModel.settings.whitelistedDomains[$0] }
                        for d in domains {
                            viewModel.removeWhitelistDomain(d)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Excepciones")
    }
}

struct BookmarksSettingsManagerView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var showAddSheet = false
    @State private var editingBookmark: BookmarkItem? = nil

    var body: some View {
        List {
            if viewModel.bookmarks.isEmpty {
                Text("No hay favoritos guardados")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.bookmarks) { item in
                    Button {
                        editingBookmark = item
                        showAddSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundColor(.primary)
                            Text(item.urlString)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete { offsets in
                    let items = offsets.map { viewModel.bookmarks[$0] }
                    for item in items {
                        viewModel.deleteBookmark(item)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Administrar favoritos")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingBookmark = nil
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            BookmarkEditorSheet(bookmark: editingBookmark) { title, urlString in
                if let existing = editingBookmark {
                    viewModel.updateBookmark(existing, title: title, urlString: urlString)
                } else {
                    viewModel.addBookmark(title: title, urlString: urlString)
                }
            }
        }
    }
}
