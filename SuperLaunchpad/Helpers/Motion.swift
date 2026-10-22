import AppKit
import SwiftUI

// Picks the animation for each launcher transition. With Reduce Motion on,
// zooms become plain cross-fades, and motion that only moves things (springs,
// the page settle, the jiggle) becomes instant or a still cue. Fades keep
// their timing: they don't move anything on screen.
//
// Views build it from `@Environment(\.accessibilityReduceMotion)`, which
// updates live; AppKit-side code without an environment uses `current`.
struct Motion: Equatable {
    let reduced: Bool

    static var current: Motion {
        Motion(reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    // MARK: - Launcher show / hide

    // Fade plus a slight zoom from 105 %, or only the fade.
    func launcherScale(isVisible: Bool) -> CGFloat {
        isVisible || reduced ? 1 : AnimationDuration.launcherHiddenScale
    }

    func launcherAnimation(isVisible: Bool) -> Animation {
        let duration = isVisible ? AnimationDuration.show : AnimationDuration.hide
        return reduced ? .easeInOut(duration: duration) : .spring(duration: duration, bounce: 0)
    }

    // MARK: - Folder open / close

    // Fade plus a pop-out from 85 %, or a cross-fade.
    func folderScale(isOpen: Bool) -> CGFloat {
        isOpen || reduced ? 1 : AnimationDuration.folderClosedScale
    }

    var folderAnimation: Animation {
        reduced
            ? .easeInOut(duration: AnimationDuration.folder)
            : .spring(duration: AnimationDuration.folder, bounce: 0)
    }

    // MARK: - Paging

    // The pager jumps straight to the target page instead of springing.
    var settlesInstantly: Bool {
        reduced
    }

    // The active page dot grows with a small bounce, or switches at once.
    var pageIndicatorAnimation: Animation? {
        reduced ? nil : .spring(duration: AnimationDuration.pageIndicator, bounce: AnimationDuration.pageIndicatorBounce)
    }

    // MARK: - Drag and edit mode

    // Reflow, lift and drop of a dragged icon.
    var dragAnimation: Animation? {
        reduced ? nil : .spring(duration: Drag.springDuration, bounce: 0)
    }

    // Icons rock in edit mode…
    func wiggles(isEditing: Bool) -> Bool {
        isEditing && !reduced
    }

    // …or, with Reduce Motion, shrink slightly and stay still.
    func editScale(isEditing: Bool) -> CGFloat {
        isEditing && reduced ? Edit.reducedMotionScale : 1
    }
}
