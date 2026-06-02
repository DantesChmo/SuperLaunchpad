import SwiftUI

struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel

    @State private var displayedFolder: FolderEntry?
    @State private var displayedFolderApps: [AppEntry] = []
    @State private var folderIsOpen = false

    var body: some View {
        GeometryReader { geo in
            let metrics = LayoutMetrics(screenWidth: geo.size.width, screenHeight: geo.size.height)

            ZStack {
                VisualEffectBackground()
                    .ignoresSafeArea()

                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: metrics.topPadding)

                    SearchBarView()

                    Spacer().frame(height: metrics.topPadding * 0.5)

                    if viewModel.pages.isEmpty {
                        Spacer()
                        Text("No applications found")
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                    } else {
                        PagingGridView(
                            pages: viewModel.pages,
                            currentPage: $viewModel.currentPage,
                            metrics: metrics,
                            onLaunch: { app in
                                viewModel.launchApp(app)
                                NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
                            },
                            onOpenFolder: { folder in
                                displayedFolder = folder
                                displayedFolderApps = viewModel.apps
                                    .filter { $0.folderID == folder.id }
                                    .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
                                withAnimation(.spring(duration: 0.25, bounce: 0)) {
                                    folderIsOpen = true
                                }
                                viewModel.openFolder(folder)
                            }
                        )

                        Spacer().frame(height: 12)

                        PageIndicatorView(
                            totalPages: viewModel.pages.count,
                            currentPage: viewModel.currentPage
                        )
                    }

                    Spacer().frame(height: metrics.bottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
                }

                // Folder overlay — always in tree, animated via opacity/scale
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .opacity(folderIsOpen ? 1 : 0)
                    .allowsHitTesting(false)

                Color.black.opacity(folderIsOpen ? 0.4 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(folderIsOpen)
                    .onTapGesture {
                        closeFolder()
                    }

                if let folder = displayedFolder {
                    FolderDetailView(
                        folder: folder,
                        apps: displayedFolderApps,
                        metrics: metrics,
                        onLaunch: { app in
                            viewModel.launchApp(app)
                            NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
                        },
                        onClose: {
                            closeFolder()
                        }
                    )
                    .opacity(folderIsOpen ? 1 : 0)
                    .scaleEffect(folderIsOpen ? 1 : 0.85)
                }
            }
            .opacity(viewModel.isVisible ? 1 : 0)
            .scaleEffect(viewModel.isVisible ? 1 : 1.05)
            .allowsHitTesting(viewModel.isVisible)
            .animation(
                viewModel.isVisible
                    ? .spring(duration: AnimationDuration.show, bounce: 0)
                    : .spring(duration: AnimationDuration.hide, bounce: 0),
                value: viewModel.isVisible
            )
            .onChange(of: viewModel.openFolderID) { _, newValue in
                if newValue == nil, folderIsOpen {
                    if !viewModel.isVisible {
                        // Launchpad closing — skip folder animation, just reset state
                        folderIsOpen = false
                        displayedFolder = nil
                        displayedFolderApps = []
                    } else {
                        // Normal folder close (Escape key, etc.)
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            folderIsOpen = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            guard !folderIsOpen else { return }
                            displayedFolder = nil
                            displayedFolderApps = []
                        }
                    }
                }
            }
        }
    }

    private func closeFolder() {
        withAnimation(.spring(duration: 0.25, bounce: 0)) {
            folderIsOpen = false
        }
        viewModel.closeFolder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !folderIsOpen else { return }
            displayedFolder = nil
            displayedFolderApps = []
        }
    }
}

extension Notification.Name {
    static let hideLaunchpad = Notification.Name("hideLaunchpad")
}
