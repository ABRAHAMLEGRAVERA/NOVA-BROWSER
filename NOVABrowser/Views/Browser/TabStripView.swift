import SwiftUI

struct TabStripView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let palette: NovaPalette
    let isCompactWidth: Bool

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(viewModel.tabs) { tab in
                        TabChipView(
                            tab: tab,
                            isActive: tab.id == viewModel.activeTabID,
                            palette: palette,
                            isCompactWidth: isCompactWidth,
                            onSelect: {
                                viewModel.selectTab(tab.id)
                            },
                            onClose: {
                                viewModel.closeTab(tab.id)
                            }
                        )
                    }

                    // '+' New Tab button directly next to the tabs / close button
                    Button {
                        viewModel.createNewTab()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.primaryText.opacity(0.85))
                            .frame(width: 28, height: 26)
                            .background(palette.addressBarBackground.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(palette.border.opacity(0.7), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("t", modifiers: .command)
                    .accessibilityLabel("Nueva pestaña")
                }
                .padding(.horizontal, isCompactWidth ? 8 : 12)
                .padding(.vertical, 4)
            }

            Button {
                viewModel.createNewTab(isIncognito: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11, weight: .semibold))
                    if !isCompactWidth {
                        Text("Privada")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(palette.incognitoAccent)
                .padding(.horizontal, isCompactWidth ? 7 : 9)
                .padding(.vertical, 5)
                .background(palette.incognitoAccent.opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityLabel("Nueva pestaña privada")
            .padding(.trailing, isCompactWidth ? 8 : 12)
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
    let isCompactWidth: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 5) {
                    if tab.isLoading {
                        ProgressView()
                            .scaleEffect(0.58)
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
                        .frame(maxWidth: isCompactWidth ? 110 : 168, alignment: .leading)
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
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(isActive ? palette.elevatedSurface : palette.addressBarBackground.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? palette.border : Color.clear, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: isActive ? Color.black.opacity(0.08) : Color.clear, radius: 2, x: 0, y: 1)
    }
}
