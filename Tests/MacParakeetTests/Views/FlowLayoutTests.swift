import AppKit
import SwiftUI
import XCTest
@testable import MacParakeet

@MainActor
final class FlowLayoutTests: XCTestCase {
    func testItemsStayOnOneLineWhenTheyFitAndWrapWhenTheyDoNot() {
        XCTAssertEqual(measuredHeight(width: 400), 20)
        XCTAssertEqual(measuredHeight(width: 250), 48)
    }

    func testOversizedItemIsConstrainedToAvailableWidth() {
        let content = FlowLayout(spacing: 8) {
            Text(String(repeating: "Long speaker name ", count: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 200)
        let view = NSHostingView(rootView: content)

        XCTAssertEqual(view.fittingSize.width, 200)
        XCTAssertGreaterThan(view.fittingSize.height, 20)
    }

    private func measuredHeight(width: CGFloat) -> CGFloat {
        let content = FlowLayout(spacing: 8) {
            ForEach(0..<3) { _ in
                Color.clear.frame(width: 120, height: 20)
            }
        }
        .frame(width: width)
        return NSHostingView(rootView: content).fittingSize.height
    }
}
