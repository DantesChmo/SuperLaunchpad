import SwiftUI

// Root SwiftUI view rendered inside the NSPanel.
struct LaunchpadView: View {
    let viewModel: LaunchpadViewModel
    let pager: PagerController

    // Local view state that only this view needs. Keeping it as `@State`
    // (rather than on the ViewModel) is intentional: this is purely UI
    // animation state, useless outside this view's lifetime.
    //
    // Why mirror `viewModel.openFolderID` into `displayedFolder` instead of
    // reading it directly? We need to keep showing the closing-folder
    // contents while it animates out — if we read straight from the ViewModel
    // it would already be `nil` when the close animation runs.
    @State private var displayedFolder: FolderEntry?
    @State private var displayedFolderApps: [AppEntry] = []
    @State private var folderIsOpen = false

    var body: some View {
        // `GeometryReader` measures the available space; we use it to compute
        // screen-relative `LayoutMetrics`. Inside the panel it equals the
        // screen frame, so the proportions match the system Launchpad.
        GeometryReader { geo in
            let metrics = LayoutMetrics(screenWidth: geo.size.width, screenHeight: geo.size.height)

            // Layered composition — the visual stack from back to front:
            //   1. Frosted desktop background (NSVisualEffectView).
            //   2. Dark overlay so icon labels are readable.
            //   3. The grid + chrome.
            //   4. Folder-open dimming + folder detail (when applicable).
            ZStack {
                VisualEffectBackground()
                    .ignoresSafeArea()

                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: metrics.topPadding)

                    SearchBarView(viewModel: viewModel)

                    Spacer().frame(height: metrics.topPadding * 0.5)

                    if viewModel.isSearching {
                        SearchResultsView(
                            viewModel: viewModel,
                            metrics: metrics,
                            onLaunch: { app in
                                viewModel.launchApp(app)
                                NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
                            }
                        )
                        .transition(.opacity)
                    } else if viewModel.pages.isEmpty {
                        Spacer()
                        Text("No applications found")
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                    } else {
                        PagingGridView(
                            viewModel: viewModel,
                            pages: viewModel.pages,
                            pager: pager,
                            metrics: metrics,
                            onLaunch: { app in
                                viewModel.launchApp(app)
                                // Notification → AppDelegate → hidePanel. We
                                // don't call panel directly because views
                                // shouldn't know about AppKit windows.
                                NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
                            },
                            onOpenFolder: { folder in
                                // Snapshot the folder + its apps into local
                                // @State so the close animation has stable
                                // data even after ViewModel changes.
                                displayedFolder = folder
                                displayedFolderApps = viewModel.apps
                                    .filter { $0.folderID == folder.id }
                                    .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
                                // `withAnimation` makes the opacity/scale
                                // changes that depend on `folderIsOpen`
                                // animate together.
                                withAnimation(.spring(duration: 0.25, bounce: 0)) {
                                    folderIsOpen = true
                                }
                                viewModel.openFolder(folder)
                            }
                        )

                        Spacer().frame(height: 12)

                        CurrentPageIndicator(viewModel: viewModel)
                    }

                    Spacer().frame(height: metrics.bottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Short crossfade between the grid and search results; no
                // paging animation.
                .animation(.easeInOut(duration: Search.resultsTransition), value: viewModel.isSearching)
                // `.contentShape(Rectangle())` makes the otherwise transparent
                // VStack area tappable — without this, taps would only hit the
                // actual icon rects, not the gaps between them.
                .contentShape(Rectangle())
                .onTapGesture {
                    // Click outside any icon → hide the launcher.
                    NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
                }

                // Folder overlay layer. The blur and dim are inserted only
                // while a folder is open: a full-screen material is a backdrop
                // blur that keeps sampling the screen every frame even at
                // opacity 0, which costs frame time while the grid pages.
                // `folderIsOpen` flips inside `withAnimation`, so the
                // `.opacity` transitions fade them in and out with the same
                // spring; the instant reset on hide flips it without
                // animation, so they disappear at once.
                if folderIsOpen {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)

                    // Dark backdrop behind the folder popup. Tap to dismiss.
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeFolder()
                        }
                        .transition(.opacity)
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
                        },
                        onRename: { title in
                            // The popup shows the snapshot, so refresh it
                            // unless it is already gone (a commit on close);
                            // the grid tile follows `viewModel.folders`.
                            guard viewModel.renameFolder(folder.id, to: title),
                                  displayedFolder?.id == folder.id,
                                  let renamed = viewModel.folders.first(where: { $0.id == folder.id }) else { return }
                            displayedFolder = renamed
                        },
                        onRenamingChange: { renaming in
                            viewModel.isRenamingFolder = renaming
                        }
                    )
                    // A different folder gets fresh edit state.
                    .id(folder.id)
                    // Pop-out animation: fade in + scale up from 85%.
                    .opacity(folderIsOpen ? 1 : 0)
                    .scaleEffect(folderIsOpen ? 1 : 0.85)
                }
            }
            // Whole-launcher show/hide animation:
            //   • fade from 0 → 1
            //   • scale from 105% → 100% (slight zoom-in, like macOS).
            .opacity(viewModel.isVisible ? 1 : 0)
            .scaleEffect(viewModel.isVisible ? 1 : 1.05)
            // Don't capture clicks while invisible — they would otherwise hit
            // the fully-transparent panel and block desktop clicks.
            .allowsHitTesting(viewModel.isVisible)
            // `.animation(_:value:)` re-runs the animation whenever `value`
            // changes. Two different durations for show vs hide give the
            // hide a snappier feel.
            .animation(
                viewModel.isVisible
                    ? .spring(duration: AnimationDuration.show, bounce: 0)
                    : .spring(duration: AnimationDuration.hide, bounce: 0),
                value: viewModel.isVisible
            )
            // React to programmatic folder dismissals (e.g. Escape key handled
            // in `LaunchpadPanel.keyDown`). The animations below mirror what
            // `closeFolder()` does locally.
            .onChange(of: viewModel.openFolderID) { _, newValue in
                if newValue == nil, folderIsOpen {
                    if !viewModel.isVisible {
                        // The whole launcher is closing — skip the folder
                        // close animation (it would compete with the panel
                        // fade-out and look janky). Just clear state.
                        folderIsOpen = false
                        displayedFolder = nil
                        displayedFolderApps = []
                    } else {
                        // User pressed Escape while launcher is still visible —
                        // play the close animation, then clear the snapshot
                        // after the animation completes (~0.3s).
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            folderIsOpen = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            // Guard: if the user re-opened the folder during
                            // the delay, don't blow away the freshly set data.
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
        // Same delayed cleanup as in `onChange` — keep the snapshot alive
        // until the close animation has visibly finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !folderIsOpen else { return }
            displayedFolder = nil
            displayedFolderApps = []
        }
    }
}

// Reads `currentPage` in its own body so a page change re-renders only the
// dots, not the whole launcher with its pages.
private struct CurrentPageIndicator: View {
    let viewModel: LaunchpadViewModel

    var body: some View {
        PageIndicatorView(totalPages: viewModel.pages.count, currentPage: viewModel.currentPage)
    }
}

// Application-wide notification used to decouple views from the AppDelegate
// that owns the actual NSPanel. Any view can post it to dismiss the launcher.
extension Notification.Name {
    static let hideLaunchpad = Notification.Name("hideLaunchpad")
}
