import XCTest
@testable import NullPlayer

/// An AIMP skin's row-spacing key (BECHA's `clfRowContentOffsetsMode`): its script sets the library
/// table's `Style.RowContentOffsets` to 8, 4 or 2 a side, and the embedded browser's rows grow by
/// what passes the 2 + 2 they already leave.
final class AIMPSkinLibraryRowPaddingTests: XCTestCase {
    private func padding(_ top: String?, _ bottom: String?) -> CGFloat {
        var state = AIMPSkinState()
        if let top { state.script["MLTable"].properties["Style.RowContentOffsets.Top"] = top }
        if let bottom { state.script["MLTable"].properties["Style.RowContentOffsets.Bottom"] = bottom }
        return AIMPSkinLibraryHost.rowPadding(state)
    }

    func testTheModesGrowTheRows() {
        XCTAssertEqual(padding("8", "8"), 12)
        XCTAssertEqual(padding("4", "4"), 4)
        XCTAssertEqual(padding("2", "2"), 0)
        XCTAssertEqual(padding(nil, nil), 0, "no mode chosen: the browser's own rows")
        XCTAssertEqual(padding("1e9", "1e9"), 124, "held to 64 a side")
        XCTAssertEqual(padding("x", "2"), 0)
    }
}
