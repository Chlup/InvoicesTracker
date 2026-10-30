import SwiftUI

extension View {
    /// Pads the view the way the window pads the page of a screen: 24 points on the leading side, 16 on the trailing
    /// side and above, and 24 below (`DesignMetrics.pageLeading`, `pageTrailing`, `pageTop` and `pageBottom`). Only
    /// the `edges` given are padded, so that a page in two parts, such as the tabs of Nastavení over what scrolls
    /// under them, pads each part on the edges it has at the window. Every screen pads its page with this and not
    /// with numbers of its own.
    func pagePadding(_ edges: Edge.Set = .all) -> some View {
        padding(
            EdgeInsets(
                top: edges.contains(.top) ? DesignMetrics.pageTop : 0,
                leading: edges.contains(.leading) ? DesignMetrics.pageLeading : 0,
                bottom: edges.contains(.bottom) ? DesignMetrics.pageBottom : 0,
                trailing: edges.contains(.trailing) ? DesignMetrics.pageTrailing : 0))
    }
}
