import SwiftUI
import Testing
@testable import SuperLaunchpad

struct MotionTests {

    private let full = Motion(reduced: false)
    private let reduced = Motion(reduced: true)

    // MARK: - Launcher show / hide

    @Test func launcherZoomsWithoutReduceMotion() {
        #expect(full.launcherScale(isVisible: false) == AnimationDuration.launcherHiddenScale)
        #expect(full.launcherScale(isVisible: true) == 1)
    }

    @Test(arguments: [false, true])
    func launcherOnlyFadesWithReduceMotion(isVisible: Bool) {
        #expect(reduced.launcherScale(isVisible: isVisible) == 1)
    }

    @Test func launcherAnimationKeepsShowAndHideDurations() {
        #expect(full.launcherAnimation(isVisible: true) == .spring(duration: AnimationDuration.show, bounce: 0))
        #expect(full.launcherAnimation(isVisible: false) == .spring(duration: AnimationDuration.hide, bounce: 0))
        #expect(reduced.launcherAnimation(isVisible: true) == .easeInOut(duration: AnimationDuration.show))
        #expect(reduced.launcherAnimation(isVisible: false) == .easeInOut(duration: AnimationDuration.hide))
    }

    // MARK: - Folder open / close

    @Test func folderPopsOutWithoutReduceMotion() {
        #expect(full.folderScale(isOpen: false) == AnimationDuration.folderClosedScale)
        #expect(full.folderScale(isOpen: true) == 1)
        #expect(full.folderAnimation == .spring(duration: AnimationDuration.folder, bounce: 0))
    }

    @Test(arguments: [false, true])
    func folderCrossFadesWithReduceMotion(isOpen: Bool) {
        #expect(reduced.folderScale(isOpen: isOpen) == 1)
        #expect(reduced.folderAnimation == .easeInOut(duration: AnimationDuration.folder))
    }

    // MARK: - Paging, drag, page dots

    @Test func movementIsInstantWithReduceMotion() {
        #expect(reduced.settlesInstantly)
        #expect(reduced.pageIndicatorAnimation == nil)
        #expect(reduced.dragAnimation == nil)
    }

    @Test func movementAnimatesWithoutReduceMotion() {
        #expect(!full.settlesInstantly)
        #expect(full.pageIndicatorAnimation != nil)
        #expect(full.dragAnimation == .spring(duration: Drag.springDuration, bounce: 0))
    }

    // MARK: - Hover

    @Test func hoverBumpsOnlyWithoutReduceMotion() {
        #expect(full.hoverScale(isHovering: true) == AnimationDuration.hoverScale)
        #expect(full.hoverScale(isHovering: false) == 1)
        #expect(reduced.hoverScale(isHovering: true) == 1)
        #expect(reduced.hoverScale(isHovering: false) == 1)
    }

    // MARK: - Edit mode

    @Test func iconsWiggleOnlyWhenEditingWithoutReduceMotion() {
        #expect(full.wiggles(isEditing: true))
        #expect(!full.wiggles(isEditing: false))
        #expect(!reduced.wiggles(isEditing: true))
        #expect(!reduced.wiggles(isEditing: false))
    }

    @Test func reduceMotionShrinksEditingIconsInstead() {
        #expect(reduced.editScale(isEditing: true) == Edit.reducedMotionScale)
        #expect(reduced.editScale(isEditing: false) == 1)
        #expect(full.editScale(isEditing: true) == 1)
        #expect(full.editScale(isEditing: false) == 1)
    }

    // MARK: - Keyboard focus

    @Test func focusRingShrinksOnOnlyWithoutReduceMotion() {
        #expect(full.focusRingAppearScale == KeyboardFocus.appearScale)
        #expect(reduced.focusRingAppearScale == 1)
    }

    @Test func folderPagesToTheFocusInstantlyWithReduceMotion() {
        #expect(full.folderPageAnimation == .spring(duration: KeyboardFocus.folderPageDuration, bounce: 0))
        #expect(reduced.folderPageAnimation == nil)
    }
}
