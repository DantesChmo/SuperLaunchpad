import SwiftUI

// The expanded folder popup. Shows when the user clicks a folder tile.
// Has its own internal pager (4×3 grid) for folders with more than 12 apps.
struct FolderDetailView: View {
    let folder: FolderEntry
    let apps: [AppEntry]
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    // A freshly created folder opens with its title already in edit mode.
    var startsRenaming = false
    // Reports when the title edit starts and ends.
    var onRenamingChange: (Bool) -> Void = { _ in }
    // App currently lifted by a drag: it keeps its cell but is drawn by the
    // lifted copy.
    var hiddenAppID: String? = nil
    // Where the card and its grid are (in `Drag.coordinateSpace`) and which
    // page is shown, for the drag gesture on the launcher root.
    var onFramesChange: (GridDragController.FolderFrames?) -> Void = { _ in }

    @State private var currentPage: Int = 0
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @FocusState private var titleFieldFocused: Bool
    @State private var cardFrame: CGRect = .zero
    @State private var gridFrame: CGRect = .zero

    // Splits the flat `apps` array into pages of `FolderGrid.appsPerPage`
    // (12). `stride(from:to:by:)` walks indices in steps; for each step we
    // slice the apps array. Using `min(...)` on the upper bound handles the
    // (possibly partial) last page.
    private var folderPages: [[AppEntry]] {
        guard !apps.isEmpty else { return [] }
        return stride(from: 0, to: apps.count, by: FolderGrid.appsPerPage).map { start in
            Array(apps[start..<min(start + FolderGrid.appsPerPage, apps.count)])
        }
    }

    // Slot math shared with the drag gesture: 4 columns of `itemWidth`.
    private var geometry: GridGeometry {
        .folder(metrics: metrics)
    }

    // Width of the popup card: the grid plus the horizontal padding on both
    // sides.
    private var containerWidth: CGFloat {
        gridWidth + FolderGrid.cardHorizontalPadding * 2
    }

    private var gridWidth: CGFloat {
        geometry.gridSize.width
    }

    // Icons inside the popup are a touch smaller than on the main grid
    // (`FolderGrid.iconScale`) so a 4-column folder doesn't look like an
    // oversized clone of the 7-column main grid.
    private var folderIconSize: CGFloat {
        geometry.hitSize.width
    }

    private var folderItemWidth: CGFloat {
        geometry.cellSize.width
    }

    var body: some View {
        VStack(spacing: 16) {
            title

            if folderPages.isEmpty {
                Text("Empty Folder")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 120)
            } else {
                // Inner horizontal pager — re-uses the same
                // `SinglePageBehavior` snapping rule as the main grid.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(folderPages.enumerated()), id: \.offset) { index, page in
                            folderPageGrid(page)
                                .frame(width: gridWidth, height: folderGridHeight)
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(SinglePageBehavior())
                // `scrollPosition` wants a `Binding<Int?>` but our state is
                // non-optional. The custom Binding adapter unwraps for write
                // and re-wraps for read.
                .scrollPosition(id: Binding(
                    get: { currentPage },
                    set: { if let v = $0 { currentPage = v } }
                ))
                .frame(width: gridWidth, height: folderGridHeight)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Drag.coordinateSpace))
                } action: { frame in
                    gridFrame = frame
                    reportFrames()
                }

                if folderPages.count > 1 {
                    PageIndicatorView(
                        totalPages: folderPages.count,
                        currentPage: currentPage
                    ) { delta in
                        currentPage = min(max(currentPage + delta, 0), folderPages.count - 1)
                    }
                    // Swallow the tap on the indicator. Without this, the
                    // tap propagates up to the dimmed background and closes
                    // the folder — unwanted UX.
                    .onTapGesture {
                    }
                }
            }
        }
        .padding(.horizontal, FolderGrid.cardHorizontalPadding)
        .padding(.vertical, 24)
        .frame(width: containerWidth)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20)
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(Drag.coordinateSpace))
        } action: { frame in
            cardFrame = frame
            reportFrames()
        }
        .onChange(of: currentPage) {
            reportFrames()
        }
        // Same swallow-the-tap trick: tapping anywhere inside the popup card
        // must NOT close the folder. Only taps on the surrounding dim layer
        // (in LaunchpadView) should close it. Clicking a non-focusable area
        // does not take focus from the title field, so end the edit here.
        .onTapGesture {
            commitRename()
        }
        // `.contain` keeps the card one container element; otherwise the
        // identifier below would be stamped onto every child, title included.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-detail")
        .accessibilityLabel(folder.title)
        // VoiceOver stays inside the open popup, and its escape gesture
        // closes it like a click on the dimmed backdrop does.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            onClose()
        }
        .onAppear {
            if startsRenaming {
                beginRename()
            }
        }
        // The folder also closes while editing (backdrop click, launcher
        // hidden): the edit still counts.
        .onDisappear {
            commitRename()
            onFramesChange(nil)
        }
        .onChange(of: isRenaming) { _, renaming in
            onRenamingChange(renaming)
        }
    }

    @ViewBuilder
    private var title: some View {
        if isRenaming {
            TextField("", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: gridWidth)
                .focused($titleFieldFocused)
                .onSubmit {
                    commitRename()
                }
                // Escape cancels only the edit: the field editor consumes it,
                // so it never reaches `LaunchpadPanel.keyDown`, which would
                // close the folder.
                .onExitCommand {
                    cancelRename()
                }
                // Focus is requested once the field is in the window. Asked for
                // in `beginRename()`, before the field exists, it may not land
                // (after an Escape it doesn't), and the true→false bounce
                // would read as a lost focus and commit at once.
                .task {
                    titleFieldFocused = true
                }
                // Only a focus the field really had and lost ends the edit.
                .onChange(of: titleFieldFocused) { wasFocused, focused in
                    if wasFocused, !focused {
                        commitRename()
                    }
                }
                .accessibilityLabel("Folder name")
                .accessibilityIdentifier("folder-title-field")
        } else {
            Text(folder.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .onTapGesture {
                    beginRename()
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Renames the folder")
                .accessibilityAction {
                    beginRename()
                }
                .accessibilityIdentifier("folder-title")
        }
    }

    private func reportFrames() {
        onFramesChange(GridDragController.FolderFrames(card: cardFrame, grid: gridFrame, page: currentPage))
    }

    private func beginRename() {
        draftTitle = folder.title
        isRenaming = true
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        titleFieldFocused = false
        if let title = FolderRename.committedTitle(draft: draftTitle, current: folder.title) {
            onRename(title)
        }
    }

    // Focus is cleared with the edit, so the next field's `.task` is a real
    // false→true change.
    private func cancelRename() {
        isRenaming = false
        titleFieldFocused = false
    }

    private var folderGridHeight: CGFloat {
        geometry.gridSize.height
    }

    private func folderPageGrid(_ page: [AppEntry]) -> some View {
        let columns = Array(repeating: GridItem(.fixed(folderItemWidth), spacing: 0), count: FolderGrid.columns)

        return VStack {
            LazyVGrid(columns: columns, alignment: .center, spacing: FolderGrid.rowSpacing) {
                ForEach(page) { app in
                    FolderAppIconView(
                        app: app,
                        iconSize: folderIconSize,
                        labelFont: metrics.labelFont,
                        labelWidth: folderItemWidth * FolderGrid.iconScale
                    ) {
                        onLaunch(app)
                    }
                    .opacity(app.id == hiddenAppID ? 0 : 1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// What committing an inline title edit renames the folder to: nil when the
// draft is blank or unchanged, so the title simply reverts.
enum FolderRename {
    static func committedTitle(draft: String, current: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != current else { return nil }
        return trimmed
    }
}

// `private` means: only `FolderDetailView` can use this type. We have a
// near-duplicate of `GridItemContainer` here rather than reusing it because
// the popup wants its own (smaller) icon and label sizes — passing those in
// would require parameterising `GridItemContainer` further, and the cost of
// a small dedicated copy is lower than the cost of widening the public type.
private struct FolderAppIconView: View {
    let app: AppEntry
    let iconSize: CGFloat
    let labelFont: CGFloat
    let labelWidth: CGFloat
    let onTap: () -> Void

    @State private var isHovering = false
    @Environment(\.enterEditMode) private var enterEditMode
    @Environment(\.isEditing) private var isEditing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Same outer/inner VStack pattern as `GridItemContainer` — see the
        // comment there for why two stacks (hover hit-box vs. cell sizing).
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                iconImage
                    .frame(width: iconSize, height: iconSize)

                Text(app.displayName)
                    .font(.system(size: labelFont))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: labelWidth)
            }
            .frame(width: iconSize, height: iconSize + 6 + labelFont * 3)
            .scaleEffect(Motion(reduced: reduceMotion).hoverScale(isHovering: isHovering))
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                onTap()
            }
            .editModeGestures(enterEditMode)
        }
        .launcherItemAccessibility(
            label: app.displayName,
            hint: isEditing ? String(localized: "Drag to move") : String(localized: "Opens the app"),
            onActivate: onTap
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("folder-app-icon")
    }

    @ViewBuilder
    private var iconImage: some View {
        if let nsImage = IconCache.shared.image(for: app) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
