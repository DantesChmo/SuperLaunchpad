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
    // A folder just made by a drop opens with its title in edit mode.
    @State private var folderStartsRenaming = false
    // Icon drags on the grid and in the folder popup. Lives here, not in the
    // grid, so a drag out of a folder survives the popup closing.
    @State private var drag = GridDragController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var motion: Motion {
        Motion(reduced: reduceMotion)
    }

    var body: some View {
        // `GeometryReader` measures the available space; we use it to compute
        // screen-relative `LayoutMetrics`. Inside the panel it equals the
        // screen frame, so the proportions match the system Launchpad. The
        // content goes in the part the Dock leaves free; the backgrounds
        // still cover the whole screen.
        GeometryReader { geo in
            let dock = viewModel.dockInsets.edgeInsets
            let metrics = LayoutMetrics(
                screenWidth: geo.size.width - dock.leading - dock.trailing,
                screenHeight: geo.size.height - dock.bottom
            )

            // Layered composition — the visual stack from back to front:
            //   1. Frosted desktop background (NSVisualEffectView).
            //   2. Dark overlay so icon labels are readable.
            //   3. The grid + chrome.
            //   4. Folder-open dimming + folder detail (when applicable).
            ZStack {
                VisualEffectBackground()
                    .ignoresSafeArea()

                Color.black
                    .opacity(contrast == .increased ? LabelContrast.increasedDimOpacity : LabelContrast.dimOpacity)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Spacer().frame(height: metrics.topPadding)

                    SearchBarView(viewModel: viewModel)

                    Spacer().frame(height: metrics.topPadding * 0.5)

                    if viewModel.isSearching {
                        SearchResultsView(
                            viewModel: viewModel,
                            metrics: metrics,
                            onLaunch: { app in
                                click(app)
                            }
                        )
                        .transition(.opacity)
                    } else if viewModel.pages.isEmpty {
                        Spacer()
                        Text("No applications found")
                            .foregroundStyle(.white.opacity(contrast == .increased ? LabelContrast.increasedSecondaryOpacity : LabelContrast.secondaryOpacity))
                        Spacer()
                    } else {
                        PagingGridView(
                            viewModel: viewModel,
                            pages: viewModel.pages,
                            pager: pager,
                            drag: drag,
                            metrics: metrics,
                            onLaunch: { app in
                                click(app)
                            },
                            onOpenFolder: { folder in
                                openFolder(folder)
                            }
                        )

                        Spacer().frame(height: 12)

                        CurrentPageIndicator(viewModel: viewModel, pager: pager)
                    }

                    Spacer().frame(height: metrics.bottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(dock)
                // Short crossfade between the grid and search results; no
                // paging animation.
                .animation(.easeInOut(duration: Search.resultsTransition), value: viewModel.isSearching)
                // `.contentShape(Rectangle())` makes the otherwise transparent
                // VStack area tappable — without this, taps would only hit the
                // actual icon rects, not the gaps between them.
                .contentShape(Rectangle())
                .onTapGesture {
                    // Click outside any icon → leave edit mode, or hide the
                    // launcher.
                    guard !viewModel.exitEditMode() else { return }
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
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    // Dark backdrop behind the folder popup. Tap to dismiss.
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeFolder()
                        }
                        // VoiceOver closes the folder with the card's escape
                        // action instead.
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }

                if let folder = displayedFolder {
                    FolderDetailView(
                        folder: folder,
                        apps: folderPreviewApps,
                        metrics: metrics,
                        onLaunch: { app in
                            guard !drag.isTapSuppressed else { return }
                            click(app)
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
                        startsRenaming: folderStartsRenaming,
                        onRenamingChange: { renaming in
                            viewModel.isRenamingFolder = renaming
                        },
                        hiddenAppID: drag.session?.sourceFolderID == folder.id ? drag.session?.itemID : nil,
                        onFramesChange: { frames in
                            drag.folderFrames = frames
                        }
                    )
                    // A different folder gets fresh edit state.
                    .id(folder.id)
                    .padding(dock)
                    // Pop-out animation: fade in + scale up from 85% (only
                    // the fade with Reduce Motion).
                    .opacity(folderIsOpen ? 1 : 0)
                    .scaleEffect(motion.folderScale(isOpen: folderIsOpen))
                }

                if let removal = viewModel.pendingRemoval {
                    AppRemovalDialog(
                        removal: removal,
                        onConfirm: {
                            Task {
                                await viewModel.confirmRemoval {
                                    NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
                                }
                            }
                        },
                        onCancel: {
                            viewModel.cancelRemoval()
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Uninstall.dialogAnimation), value: viewModel.pendingRemoval != nil)
            // Below the drag modifier, so the lifted icon doesn't wiggle.
            .environment(\.isEditing, viewModel.isEditing)
            .environment(\.enterEditMode, EnterEditModeAction(viewModel: viewModel))
            .environment(\.removeApp, RemoveAppAction(viewModel: viewModel))
            .environment(\.itemMenu, ItemMenuAction(viewModel: viewModel))
            .environment(\.runningApps, viewModel.runningApps)
            .modifier(LaunchpadDragGesture(
                viewModel: viewModel,
                pager: pager,
                drag: drag,
                metrics: metrics,
                folderApps: folderIsOpen && displayedFolder?.id == viewModel.openFolderID ? displayedFolderApps : nil,
                onLeaveFolder: {
                    closeFolder()
                },
                onLayoutChange: {
                    refreshFolderSnapshot()
                },
                onFolderCreated: { folderID in
                    guard let folder = viewModel.folders.first(where: { $0.id == folderID }) else { return }
                    openFolder(folder, renaming: true)
                }
            ))
            // Whole-launcher show/hide animation:
            //   • fade from 0 → 1
            //   • scale from 105% → 100% (slight zoom-in, like macOS);
            //     Reduce Motion keeps only the fade.
            .opacity(viewModel.isVisible ? 1 : 0)
            .scaleEffect(motion.launcherScale(isVisible: viewModel.isVisible))
            // Don't capture clicks while invisible — they would otherwise hit
            // the fully-transparent panel and block desktop clicks.
            .allowsHitTesting(viewModel.isVisible)
            // `.animation(_:value:)` re-runs the animation whenever `value`
            // changes. Two different durations for show vs hide give the
            // hide a snappier feel.
            .animation(motion.launcherAnimation(isVisible: viewModel.isVisible), value: viewModel.isVisible)
            // An app moved to the Trash (or uninstalled elsewhere) leaves the
            // open folder.
            .onChange(of: viewModel.apps.count) {
                refreshFolderSnapshot()
            }
            // Open or Rename in a folder's context menu.
            .onChange(of: viewModel.folderOpenRequest) { _, request in
                guard let request, let folder = viewModel.folders.first(where: { $0.id == request.folderID }) else { return }
                openFolder(folder, renaming: request.renaming)
            }
            .onChange(of: viewModel.isEditing) { _, editing in
                AccessibilityNotification.Announcement(editing ? "Editing" : "Done editing").post()
            }
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
                        // after the animation completes.
                        withAnimation(motion.folderAnimation) {
                            folderIsOpen = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationDuration.folderCleanupDelay) {
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

    // A click on an app, launching it or showing it in Finder by its
    // modifiers (none in edit mode).
    private func click(_ app: AppEntry) {
        guard viewModel.click(app, modifiers: NSEvent.modifierFlags) else { return }
        // Notification → AppDelegate → hidePanel. We don't call panel
        // directly because views shouldn't know about AppKit windows.
        NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
    }

    private func openFolder(_ folder: FolderEntry, renaming: Bool = false) {
        // Snapshot the folder + its apps into local @State so the close
        // animation has stable data even after ViewModel changes.
        displayedFolder = folder
        displayedFolderApps = viewModel.folderApps(folder.id)
        folderStartsRenaming = renaming
        // `withAnimation` makes the opacity/scale changes that depend on
        // `folderIsOpen` animate together.
        withAnimation(motion.folderAnimation) {
            folderIsOpen = true
        }
        viewModel.openFolder(folder)
    }

    // The open folder's apps after an edit (a reorder inside it).
    private func refreshFolderSnapshot() {
        guard folderIsOpen, let id = displayedFolder?.id, id == viewModel.openFolderID else { return }
        displayedFolderApps = viewModel.folderApps(id)
    }

    // The folder's apps as the popup shows them while an app is dragged
    // inside it.
    private var folderPreviewApps: [AppEntry] {
        guard let session = drag.session, session.isInFolder, session.sourceFolderID == displayedFolder?.id else {
            return displayedFolderApps
        }
        return session.preview(displayedFolderApps)
    }

    private func closeFolder() {
        withAnimation(motion.folderAnimation) {
            folderIsOpen = false
        }
        viewModel.closeFolder()
        // Same delayed cleanup as in `onChange` — keep the snapshot alive
        // until the close animation has visibly finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationDuration.folderCleanupDelay) {
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
    let pager: PagerController

    var body: some View {
        PageIndicatorView(totalPages: viewModel.displayedPageCount, currentPage: viewModel.currentPage) { delta in
            pager.step(by: delta)
        }
    }
}

private extension DockInsets {
    var edgeInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: left, bottom: bottom, trailing: right)
    }
}

// Application-wide notification used to decouple views from the AppDelegate
// that owns the actual NSPanel. Any view can post it to dismiss the launcher.
extension Notification.Name {
    static let hideLaunchpad = Notification.Name("hideLaunchpad")
}
