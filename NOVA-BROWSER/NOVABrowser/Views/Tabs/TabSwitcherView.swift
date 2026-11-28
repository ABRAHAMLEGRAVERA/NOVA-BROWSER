import SwiftUI

struct TabSwitcherView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: BrowserViewModel
    let palette: NovaPalette

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.incognitoTabsCount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Pestañas privadas (\(viewModel.incognitoTabsCount))", systemImage: "eye.slash.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(palette.incognitoAccent)

                                Spacer()

                                Button("Cerrar privadas") {
                                    viewModel.closeAllIncognitoTabs()
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                            }

                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(viewModel.tabs.filter { $0.isIncognito }) { tab in
                                    tabCard(tab)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Pestañas (\(viewModel.normalTabsCount))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(palette.primaryText)

                            Spacer()

                            if viewModel.tabs.count > 1 {
                                Button("Cerrar todas") {
                                    viewModel.closeAllTabs()
                                    presentationMode.wrappedValue.dismiss()
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                            }
                        }

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(viewModel.tabs.filter { !$0.isIncognito }) { tab in
                                tabCard(tab)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(palette.canvasBackground)
            .navigationTitle("Pestañas abiertas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.createNewTab(isIncognito: false)
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Label("Nueva", systemImage: "plus")
                        }

                        Button {
                            viewModel.createNewTab(isIncognito: true)
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Label("Privada", systemImage: "eye.slash")
                        }
                        .foregroundColor(palette.incognitoAccent)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func tabCard(_ tab: BrowserTab) -> some View {
        let isActive = tab.id == viewModel.activeTabID
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: tab.isIncognito ? "eye.slash.fill" : (tab.isStartPage ? "sparkles" : "globe"))
                    .font(.system(size: 13))
                    .foregroundColor(tab.isIncognito ? palette.incognitoAccent : palette.accent)

                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)

                Spacer()

                Button {
                    viewModel.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar \(tab.title)")
            }

            Divider()

            Text(tab.urlString ?? "Página de inicio NOVA")
                .font(.system(size: 12))
                .foregroundColor(palette.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)

            HStack {
                if tab.isDesktopMode {
                    Text("Escritorio")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Spacer()
                if isActive {
                    Text("Activa")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(palette.accent)
                }
            }
        }
        .padding(12)
        .background(palette.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? (tab.isIncognito ? palette.incognitoAccent : palette.accent) : palette.border, lineWidth: isActive ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectTab(tab.id)
            presentationMode.wrappedValue.dismiss()
        }
    }
}
