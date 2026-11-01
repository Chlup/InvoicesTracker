import SwiftUI

extension View {
    /// The look of the page of an invoice in a preview: cut to the corners of a sheet of paper, 4 points, and lifted
    /// off the ground it lies on by the shadow of paper (`Elevation.paper`). `ground` is the colour of that ground.
    /// The page is white whatever the appearance, and its edge is soft where it is cut to the corners, so the surface
    /// behind it is of the colour of the ground: the edge blends into the ground in a dark window too, and not into a
    /// colour of its own. Give the page its size first.
    ///
    /// Where the ground is as light as the page, as the colour of a card in a light window is, the soft shadow alone
    /// leaves the edge hardly seen, above the page most of all, where the shadow does not reach. There `edge` is a ring
    /// a point wide around the page, outside it, as the prototype draws the page of the PDF sheet (a ring of the grey
    /// fill, `0 0 0 1px`). Without it the page has no ring of its own.
    func paperPage(on ground: Color, edge: Color? = nil) -> some View {
        let paper = RoundedRectangle(cornerRadius: 4)
        return clipShape(paper)
            .background {
                paper.surface(ground, elevation: .paper)
            }
            .overlay {
                if let edge {
                    paper.inset(by: -1).strokeBorder(edge, lineWidth: 1)
                }
            }
    }
}
