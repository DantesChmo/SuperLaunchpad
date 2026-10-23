import AppKit
import Testing
@testable import SuperLaunchpad

struct ItemMenuTests {

    private func actions(_ sections: ItemMenu.Sections) -> [[ItemMenu.Action]] {
        sections.map { $0.map(\.action) }
    }

    private func isEnabled(_ action: ItemMenu.Action, in sections: ItemMenu.Sections) -> Bool? {
        sections.joined().first { $0.action == action }?.isEnabled
    }

    // MARK: - App menu

    @Test func appMenuListsActionsInSections() {
        let sections = ItemMenu.items(for: ItemMenu.AppState(isRemovable: true, canEditLayout: true))
        #expect(actions(sections) == [[.open, .showInFinder], [.hide, .moveToTrash], [.editLayout]])
        #expect(sections.joined().allSatisfy { $0.isEnabled })
    }

    @Test func hiddenAppOffersUnhideInsteadOfHide() {
        let sections = ItemMenu.items(for: ItemMenu.AppState(isRemovable: true, canEditLayout: true, isHidden: true))
        #expect(actions(sections) == [[.open, .showInFinder], [.unhide, .moveToTrash], [.editLayout]])
        #expect(isEnabled(.unhide, in: sections) == true)
    }

    @Test func moveToTrashIsDisabledForSystemApps() {
        let sections = ItemMenu.items(for: ItemMenu.AppState(isRemovable: false, canEditLayout: true))
        #expect(isEnabled(.moveToTrash, in: sections) == false)
        #expect(isEnabled(.open, in: sections) == true)
    }

    @Test func editLayoutFollowsCanEditLayout() {
        let app = ItemMenu.items(for: ItemMenu.AppState(isRemovable: true, canEditLayout: false))
        let folder = ItemMenu.items(for: ItemMenu.FolderState(appCount: 2, canEditLayout: false))
        #expect(isEnabled(.editLayout, in: app) == false)
        #expect(isEnabled(.editLayout, in: folder) == false)
    }

    // MARK: - Folder menu

    @Test func folderMenuListsActionsInSections() {
        let sections = ItemMenu.items(for: ItemMenu.FolderState(appCount: 3, canEditLayout: true))
        #expect(actions(sections) == [[.open, .rename], [.sortByName, .disband], [.editLayout]])
        #expect(sections.joined().allSatisfy { $0.isEnabled })
    }

    @Test(arguments: [(0, false), (1, false), (2, true)])
    func sortByNameNeedsTwoApps(appCount: Int, enabled: Bool) {
        let sections = ItemMenu.items(for: ItemMenu.FolderState(appCount: appCount, canEditLayout: true))
        #expect(isEnabled(.sortByName, in: sections) == enabled)
        #expect(isEnabled(.disband, in: sections) == true)
    }

    // MARK: - Clicks

    @Test(arguments: [
        (NSEvent.ModifierFlags(), ItemMenu.ClickAction.launch),
        (.command, .launchKeepingLauncher),
        ([.command, .option], .showInFinder),
        (.control, .none),
        ([.control, .command], .none),
        (.shift, .launch),
        // Not a modifier the click looks at.
        ([.command, .capsLock], .launchKeepingLauncher)
    ] as [(NSEvent.ModifierFlags, ItemMenu.ClickAction)])
    func clickActionByModifiers(modifiers: NSEvent.ModifierFlags, expected: ItemMenu.ClickAction) {
        #expect(ItemMenu.clickAction(modifiers: modifiers, isEditing: false) == expected)
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .command, [.command, .option]] as [NSEvent.ModifierFlags])
    func clicksDoNothingInEditMode(modifiers: NSEvent.ModifierFlags) {
        #expect(ItemMenu.clickAction(modifiers: modifiers, isEditing: true) == ItemMenu.ClickAction.none)
    }
}
