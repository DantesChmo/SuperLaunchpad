import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct EditingModelEditModeTests {

    private func makeVM() -> LaunchpadViewModel {
        let vm = LaunchpadViewModel(database: nil)
        vm.apps = [app("Mail"), app("Maps", order: 1)]
        vm.show()
        return vm
    }

    private func app(_ name: String, order: Int = 0) -> AppEntry {
        AppEntry(
            bundleIdentifier: "com.test.\(name)",
            displayName: name,
            appPath: "/Applications/\(name).app",
            pageIndex: 0,
            orderIndex: order
        )
    }

    // MARK: - Enter / exit

    @Test func startsOutOfEditMode() {
        #expect(!makeVM().editing.isEditing)
    }

    @Test func longPressEntersAndExitLeaves() {
        let vm = makeVM()
        vm.editing.enterEditMode()
        #expect(vm.editing.isEditing)
        #expect(vm.editing.exitEditMode())
        #expect(!vm.editing.isEditing)
        #expect(!vm.editing.exitEditMode())
    }

    @Test func dragEntersEditModeAndItStaysAfterDrop() {
        let vm = makeVM()
        vm.editing.beginDragSession()
        #expect(vm.editing.isEditing)
        vm.editing.endDragSession()
        #expect(vm.editing.isEditing)
    }

    @Test func cannotEnterWhileSearching() {
        let vm = makeVM()
        vm.search.searchText = "ma"
        vm.editing.enterEditMode()
        vm.editing.setOptionHeld(true)
        #expect(!vm.editing.isEditing)
    }

    @Test func startingSearchExitsEditMode() {
        let vm = makeVM()
        vm.editing.enterEditMode()
        vm.search.searchText = "m"
        #expect(!vm.editing.isEditing)
    }

    @Test func whitespaceQueryKeepsEditMode() {
        let vm = makeVM()
        vm.editing.enterEditMode()
        vm.search.searchText = " "
        #expect(vm.editing.isEditing)
    }

    @Test func hideExitsEditModeAndNextShowStartsClean() {
        let vm = makeVM()
        vm.editing.enterEditMode()
        vm.hide()
        #expect(!vm.editing.isEditing)
        vm.show()
        #expect(!vm.editing.isEditing)
    }

    // MARK: - Option key

    @Test func optionShowsEditModeOnlyWhileHeld() {
        let vm = makeVM()
        vm.editing.setOptionHeld(true)
        #expect(vm.editing.isEditing)
        vm.editing.setOptionHeld(false)
        #expect(!vm.editing.isEditing)
    }

    @Test func longPressWhileOptionHeldStaysAfterRelease() {
        let vm = makeVM()
        vm.editing.setOptionHeld(true)
        vm.editing.enterEditMode()
        vm.editing.setOptionHeld(false)
        #expect(vm.editing.isEditing)
    }

    @Test func dragWhileOptionHeldStaysAfterRelease() {
        let vm = makeVM()
        vm.editing.setOptionHeld(true)
        vm.editing.beginDragSession()
        vm.editing.endDragSession()
        vm.editing.setOptionHeld(false)
        #expect(vm.editing.isEditing)
    }

    @Test func optionReleaseKeepsStickyEditMode() {
        let vm = makeVM()
        vm.editing.enterEditMode()
        vm.editing.setOptionHeld(true)
        vm.editing.setOptionHeld(false)
        #expect(vm.editing.isEditing)
    }

    @Test func exitWhileOptionHeldNeedsANewPress() {
        let vm = makeVM()
        vm.editing.setOptionHeld(true)
        vm.editing.exitEditMode()
        #expect(!vm.editing.isEditing)
        vm.editing.setOptionHeld(false)
        #expect(!vm.editing.isEditing)
        vm.editing.setOptionHeld(true)
        #expect(vm.editing.isEditing)
    }

    @Test func optionIgnoredWhileRenamingFolderOrHidden() {
        let vm = makeVM()
        vm.editing.isRenamingFolder = true
        vm.editing.setOptionHeld(true)
        #expect(!vm.editing.isEditing)

        vm.editing.isRenamingFolder = false
        vm.hide()
        vm.editing.setOptionHeld(true)
        #expect(!vm.editing.isEditing)
    }

    @Test func optionReleaseDuringRenameStillLeaves() {
        let vm = makeVM()
        vm.editing.setOptionHeld(true)
        vm.editing.isRenamingFolder = true
        vm.editing.setOptionHeld(false)
        #expect(!vm.editing.isEditing)
    }

    // MARK: - Launching

    @Test func launchIsSuppressedWhileEditing() {
        let vm = makeVM()
        vm.editing.enterEditMode()
        #expect(!vm.itemActions.launchApp(vm.apps[0]))
        #expect(vm.isVisible)
        #expect(vm.editing.isEditing)
    }

    @Test func launchIsSuppressedWhileOptionHeld() {
        let vm = makeVM()
        vm.editing.setOptionHeld(true)
        #expect(!vm.itemActions.launchApp(vm.apps[0]))
        #expect(vm.isVisible)
    }

    // MARK: - Escape ladder

    @Test func escapeCancelsDragThenExitsEditModeThenClosesFolderThenHides() {
        let vm = makeVM()
        vm.openFolderID = "folder"
        vm.editing.beginDragSession()

        #expect(vm.handleEscape() == .cancelledDrag)
        #expect(vm.editing.isEditing)
        vm.editing.endDragSession()

        #expect(vm.handleEscape() == .exitedEditMode)
        #expect(!vm.editing.isEditing)
        #expect(vm.openFolderID == "folder")

        #expect(vm.handleEscape() == .closedFolder)
        #expect(vm.handleEscape() == .hideLauncher)
    }

    @Test func escapeExitsEditModeBeforeClearingWhitespaceQuery() {
        let vm = makeVM()
        vm.editing.enterEditMode()
        vm.search.searchText = " "
        #expect(vm.handleEscape() == .exitedEditMode)
        #expect(vm.search.searchText == " ")
        #expect(vm.handleEscape() == .clearedSearch)
    }
}
