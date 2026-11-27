import SwiftUI

struct DownloadsSheetView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var downloadManager: DownloadManager

    @State private var manualURLString: String = ""
    @State private var sharedFileURL: URL? = nil

    var body: some View {
        NavigationView {
            List {
                if let videoURLString = viewModel.activeTab.detectedVideoURLString, !videoURLString.isEmpty {
                    Section(header: Text("Vídeo detectado en la página")) {
                        Button {
                            viewModel.downloadDetectedVideo()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "film.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Descargar vídeo ahora")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(videoURLString)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(
                    header: Text("Descarga rápida por enlace directo"),
                    footer: Text("Los archivos se guardan en Archivos > En mi iPad > NOVA Browser > Descargas.")
                ) {
                    HStack(spacing: 8) {
                        TextField("https://ejemplo.com/video.mp4", text: $manualURLString)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button("Descargar") {
                            if let url = URLResolver.resolveInput(manualURLString, searchEngine: viewModel.settings.searchEngine) {
                                downloadManager.startDirectDownload(url: url)
                                manualURLString = ""
                            }
                        }
                        .disabled(manualURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section(header: Text("Descargas (\(downloadManager.items.count))")) {
                    if downloadManager.items.isEmpty {
                        Text("No hay descargas registradas todavía.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(downloadManager.items) { item in
                            downloadRow(item)
                        }
                        .onDelete { offsets in
                            let targets = offsets.map { downloadManager.items[$0] }
                            for item in targets {
                                downloadManager.deleteDownload(item)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Descargas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if downloadManager.items.contains(where: { $0.state != .downloading }) {
                        Button("Limpiar") {
                            downloadManager.clearFinished()
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
            .sheet(isPresented: Binding(
                get: { sharedFileURL != nil },
                set: { if !$0 { sharedFileURL = nil } }
            )) {
                if let url = sharedFileURL {
                    ShareSheetView(activityItems: [url])
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    @ViewBuilder
    private func downloadRow(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: item.isVideo ? "film" : "doc.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    Text(statusText(for: item))
                        .font(.system(size: 11))
                        .foregroundColor(statusColor(for: item))
                }

                Spacer()

                if item.state == .downloading {
                    Button {
                        downloadManager.cancelDownload(id: item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if item.state == .completed, let fileURL = downloadManager.localFileURL(for: item) {
                    Button {
                        sharedFileURL = fileURL
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Guardar o compartir \(item.filename)")
                }
            }

            if item.state == .downloading {
                if item.progress > 0 {
                    ProgressView(value: item.progress)
                } else {
                    ProgressView()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusText(for item: DownloadItem) -> String {
        switch item.state {
        case .downloading:
            let pct = Int(item.progress * 100)
            return item.totalBytes > 0 ? "\(pct)% · \(item.formattedProgress)" : item.formattedProgress
        case .completed:
            return "Completado · \(item.formattedProgress)"
        case .failed(let message):
            return "Error: \(message)"
        case .cancelled:
            return "Cancelado"
        }
    }

    private func statusColor(for item: DownloadItem) -> Color {
        switch item.state {
        case .downloading: return .blue
        case .completed: return .secondary
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
}
