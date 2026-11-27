import SwiftUI

struct TabStripView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let palette: NovaPalette

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.tabs) { tab in
                        TabChipView(
                            tab: tab,
                            isActive: tab.id == viewModel.activeTabID,
                            palette: palette,
                            onSelect: {
                                viewModel.selectTab(tab.id)
                            },
                            onClose: {
                                viewModel.closeTab(tab.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            HStack(spacing: 4) {
                Button {
                    viewModel.createNewTab(isIncognito: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Privada")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(palette.incognitoAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette.incognitoAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .accessibilityLabel("Nueva pestaña privada")
            }
            .padding(.trailing, 12)
        }
        .frame(height: 36)
        .background(palette.chromeBackground)
        .overlay(
            Rectangle()
                .fill(palette.border)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

private struct TabChipView: View {
    let tab: BrowserTab
    let isActive: Bool
    let palette: NovaPalette
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    if tab.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else if tab.isIncognito {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 11))
                            .foregroundColor(palette.incognitoAccent)
                    } else {
                        Image(systemName: tab.isStartPage ? "sparkles" : "globe")
                            .font(.system(size: 11))
                            .foregroundColor(isActive ? palette.accent : palette.secondaryText)
                    }

                    Text(tab.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? palette.primaryText : palette.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(palette.secondaryText)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar pestaña \(tab.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? palette.elevatedSurface : palette.addressBarBackground.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? palette.border : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
