import SwiftUI

struct ShortcutEditorSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let shortcut: QuickShortcut?
    let onSave: (UUID?, String, String, String) -> Void

    @State private var title: String
    @State private var urlString: String
    @State private var selectedHex: String

    private let colorOptions: [String] = [
        "#2563EB", "#DC2626", "#059669", "#7C3AED",
        "#EA580C", "#0284C7", "#DB2777", "#475569"
    ]

    init(shortcut: QuickShortcut?, onSave: @escaping (UUID?, String, String, String) -> Void) {
        self.shortcut = shortcut
        self.onSave = onSave
        _title = State(initialValue: shortcut?.title ?? "")
        _urlString = State(initialValue: shortcut?.urlString ?? "https://")
        _selectedHex = State(initialValue: shortcut?.colorHex ?? "#2563EB")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Detalles del acceso rápido")) {
                    TextField("Nombre (ej. YouTube)", text: $title)
                    TextField("Dirección web (ej. https://youtube.com)", text: $urlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("Color del icono")) {
                    HStack(spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                selectedHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedHex == hex ? 2.5 : 0)
                                            .padding(-3)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(shortcut == nil ? "Nuevo acceso rápido" : "Editar acceso rápido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(shortcut?.id, title, urlString, selectedHex)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
