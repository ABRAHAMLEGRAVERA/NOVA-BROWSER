import SwiftUI
import UIKit

struct PasswordsSheetView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var passwordStore: PasswordStore

    var body: some View {
        NavigationView {
            PasswordsManagerListView(viewModel: viewModel, passwordStore: passwordStore) {
                presentationMode.wrappedValue.dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct PasswordsManagerListView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var passwordStore: PasswordStore
    var onCloseAfterFill: (() -> Void)? = nil

    @State private var searchText: String = ""
    @State private var showEditor: Bool = false
    @State private var editingCredential: PasswordCredential? = nil
    @State private var revealedIDs: Set<UUID> = []

    private var matchingCurrentHost: [PasswordCredential] {
        guard let host = viewModel.activeTab.currentHost, !viewModel.activeTab.isStartPage else { return [] }
        return passwordStore.matchingCredentials(for: host)
    }

    private var filteredCredentials: [PasswordCredential] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return passwordStore.credentials
        }
        return passwordStore.credentials.filter {
            $0.domain.lowercased().contains(q) || $0.username.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if !matchingCurrentHost.isEmpty {
                Section(header: Text("Sugeridas para esta página")) {
                    ForEach(matchingCurrentHost) { cred in
                        credentialRow(cred, showQuickFill: true)
                    }
                }
            }

            Section(header: Text("Todas las contraseñas (\(filteredCredentials.count))")) {
                if filteredCredentials.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                        Text(passwordStore.credentials.isEmpty ? "Aún no hay contraseñas guardadas" : "Sin resultados")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Al iniciar sesión en cualquier sitio, NOVA te preguntará si deseas guardar tus datos de forma segura.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(filteredCredentials) { cred in
                        credentialRow(cred, showQuickFill: !viewModel.activeTab.isStartPage)
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { filteredCredentials[$0] }
                        for item in targets {
                            passwordStore.deleteCredential(item)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, prompt: "Buscar sitio o usuario")
        .navigationTitle("Contraseñas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingCredential = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Añadir contraseña")
            }
        }
        .sheet(isPresented: $showEditor) {
            CredentialEditorSheet(credential: editingCredential) { domain, username, password in
                if let existing = editingCredential {
                    passwordStore.updateCredential(existing, domain: domain, username: username, password: password)
                } else {
                    passwordStore.saveCredential(domain: domain, username: username, password: password)
                }
            }
        }
    }

    @ViewBuilder
    private func credentialRow(_ cred: PasswordCredential, showQuickFill: Bool) -> some View {
        let isRevealed = revealedIDs.contains(cred.id)

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(cred.domain)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(cred.username)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(isRevealed ? cred.password : String(repeating: "•", count: min(max(cred.password.count, 6), 14)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                if showQuickFill {
                    Button("Rellenar") {
                        viewModel.fillCredential(cred)
                        onCloseAfterFill?()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }

                Button {
                    if isRevealed {
                        revealedIDs.remove(cred.id)
                    } else {
                        revealedIDs.insert(cred.id)
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Ocultar contraseña" : "Mostrar contraseña")

                Button {
                    UIPasteboard.general.string = cred.password
                    viewModel.showToast("Contraseña copiada")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copiar contraseña")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingCredential = cred
            showEditor = true
        }
    }
}

private struct CredentialEditorSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let credential: PasswordCredential?
    let onSave: (String, String, String) -> Void

    @State private var domain: String = ""
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Datos de acceso")) {
                    TextField("Sitio web (ej. google.com)", text: $domain)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Usuario o correo", text: $username)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Contraseña", text: $password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle(credential == nil ? "Nueva contraseña" : "Editar contraseña")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(domain, username, password)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(
                        domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.isEmpty
                    )
                }
            }
            .onAppear {
                if let c = credential {
                    domain = c.domain
                    username = c.username
                    password = c.password
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
