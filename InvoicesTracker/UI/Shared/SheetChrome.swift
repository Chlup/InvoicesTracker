import SwiftUI

extension View {
    /// What every sheet of the app has at its root, in one place: the colour of a card behind it (`Palette.bgCard`),
    /// which the design draws every dialog on, where a sheet has the glass of the system otherwise, and the cover of
    /// the lock after inactivity (`idleLockCover()`), which every sheet must have. The shape of a sheet, its corners
    /// and its edge, is the system's.
    ///
    /// Give it to the root view of the content of every `.sheet`, never to a view inside it, and never to anything
    /// that is not shown as a sheet: the background is the background of the presentation it is the root of. A sheet
    /// without it is the one place where the app does not look like its design.
    func sheetChrome() -> some View {
        idleLockCover()
            .presentationBackground(Palette.bgCard)
    }

    /// Names the content of a sheet after its title, as the design names its dialog: VoiceOver reads the sheet as a
    /// group under `title`, with the heading, the fields and the buttons in it. A sheet is a window of the system with
    /// no title of its own, so the name is given to the root view of its content, with the title the sheet shows.
    func dialogNamed(_ title: String) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}
