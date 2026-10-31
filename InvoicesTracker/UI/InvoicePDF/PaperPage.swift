import SwiftUI

extension View {
    /// The look of the page of an invoice in a preview: cut to the corners of a sheet of paper, 4 points, and lifted
    /// off the ground it lies on by the shadow of paper (`Elevation.paper`). `ground` is the colour of that ground.
    /// The page is white whatever the appearance, and its edge is soft where it is cut to the corners, so the surface
    /// behind it is of the colour of the ground: the edge blends into the ground in a dark window too, and not into a
    /// colour of its own. Give the page its size first.
    func paperPage(on ground: Color) -> some View {
        let paper = RoundedRectangle(cornerRadius: 4)
        return clipShape(paper)
            .background {
                paper.surface(ground, elevation: .paper)
            }
    }
}
