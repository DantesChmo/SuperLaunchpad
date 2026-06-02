import Testing
@testable import SuperLaunchpad

struct SuperLaunchpadSmokeTests {

    @Test func moduleImportsSuccessfully() {
        #expect(Grid.appsPerPage == 35)
    }
}
