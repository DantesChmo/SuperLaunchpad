import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchpadViewModelEditModeTests {

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
        #expect(!makeVM().isEditing)
    }

    @Test func longPressEntersAndExitLeaves() {
        let vm = makeVM()
        vm.enterEditMode()
        #expect(vm.isEditing)
        #expect(vm.exitEditMode())
        #expect(!vm.isEditing)
        #expect(!vm.exitEditMode())
    }

    @Test func dragEntersEditModeAndItStaysAfterDrop() {
        let vm = makeVM()
        vm.beginDragSession()
        #expect(vm.isEditing)
        vm.endDragSession()
        #expect(vm.isEditing)
    }

    @Test func cannotEnterWhileSearching() {
        let vm = makeVM()
        vm.searchText = "ma"
        vm.enterEditMode()
        vm.setOptionHeld(true)
        #expect(!vm.isEditing)
    }

    @Test func startingSearchExitsEditMode() {
        let vm = makeVM()
        vm.enterEditMode()
        vm.searchText = "m"
        #expect(!vm.isEditing)
    }

    @Test func whitespaceQueryKeepsEditMode() {
        let vm = makeVM()
        vm.enterEditMode()
        vm.searchText = " "
        #expect(vm.isEditing)
    }

    @Test func hideExitsEditModeAndNextShowStartsClean() {
        let vm = makeVM()
        vm.enterEditMode()
        vm.hide()
        #expect(!vm.isEditing)
        vm.show()
        #expect(!vm.isEditing)
    }

    // MARK: - Option key

    @Test func optionShowsEditModeOnlyWhileHeld() {
        let vm = makeVM()
        vm.setOptionHeld(true)
        #expect(vm.isEditing)
        vm.setOptionHeld(false)
        #expect(!vm.isEditing)
    }

    @Test func longPressWhileOptionHeldStaysAfterRelease() {
        let vm = makeVM()
        vm.setOptionHeld(true)
        vm.enterEditMode()
        vm.setOptionHeld(false)
        #expect(vm.isEditing)
    }

    @Test func dragWhileOptionHeldStaysAfterRelease() {
        let vm = makeVM()
        vm.setOptionHeld(true)
        vm.beginDragSession()
        vm.endDragSession()
        vm.setOptionHeld(false)
        #expect(vm.isEditing)
    }

    @Test func optionReleaseKeepsStickyEditMode() {
        let vm = makeVM()
        vm.enterEditMode()
        vm.setOptionHeld(true)
        vm.setOptionHeld(false)
        #expect(vm.isEditing)
    }

    @Test func exitWhileOptionHeldNeedsANewPress() {
        let vm = makeVM()
        vm.setOptionHeld(true)
        vm.exitEditMode()
        #expect(!vm.isEditing)
        vm.setOptionHeld(false)
        #expect(!vm.isEditing)
        vm.setOptionHeld(true)
        #expect(vm.isEditing)
    }

    @Test func optionIgnoredWhileRenamingFolderOrHidden() {
        let vm = makeVM()
        vm.isRenamingFolder = true
        vm.setOptionHeld(true)
        #expect(!vm.isEditing)

        vm.isRenamingFolder = false
        vm.hide()
        vm.setOptionHeld(true)
        #expect(!vm.isEditing)
    }

    @Test func optionReleaseDuringRenameStillLeaves() {
        let vm = makeVM()
        vm.setOptionHeld(true)
        vm.isRenamingFolder = true
        vm.setOptionHeld(false)
        #expect(!vm.isEditing)
    }

    // MARK: - Launching

    @Test func launchIsSuppressedWhileEditing() {
        let vm = makeVM()
        vm.enterEditMode()
        #expect(!vm.launchApp(vm.apps[0]))
        #expect(vm.isVisible)
        #expect(vm.isEditing)
    }

    @Test func launchIsSuppressedWhileOptionHeld() {
        let vm = makeVM()
        vm.setOptionHeld(true)
        #expect(!vm.launchApp(vm.apps[0]))
        #expect(vm.isVisible)
    }

    // MARK: - Escape ladder

    @Test func escapeCancelsDragThenExitsEditModeThenClosesFolderThenHides() {
        let vm = makeVM()
        vm.openFolderID = "folder"
        vm.beginDragSession()

        #expect(vm.handleEscape() == .cancelledDrag)
        #expect(vm.isEditing)
        vm.endDragSession()

        #expect(vm.handleEscape() == .exitedEditMode)
        #expect(!vm.isEditing)
        #expect(vm.openFolderID == "folder")

        #expect(vm.handleEscape() == .closedFolder)
        #expect(vm.handleEscape() == .hideLauncher)
    }

    @Test func escapeExitsEditModeBeforeClearingWhitespaceQuery() {
        let vm = makeVM()
        vm.enterEditMode()
        vm.searchText = " "
        #expect(vm.handleEscape() == .exitedEditMode)
        #expect(vm.searchText == " ")
        #expect(vm.handleEscape() == .clearedSearch)
    }
}
