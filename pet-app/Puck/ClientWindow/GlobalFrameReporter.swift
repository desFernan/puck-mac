//
//  GlobalFrameReporter.swift
//  Puck
//
//  Reports a view's frame in SwiftUI's global space.
//
//  Distinct from PaneFrameReporter, which answers a different question: that
//  one converts to AppKit screen coordinates because the pet lives in them.
//  This one stays in SwiftUI's space, where the only thing it is used for is
//  comparing two views in the same window -- and a conversion neither side
//  needs is a conversion that can be wrong.
//

import SwiftUI

struct GlobalFrameReporter: View {
    let onChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { onChange(frame) }
                .onChange(of: frame) { onChange(frame) }
        }
    }
}
