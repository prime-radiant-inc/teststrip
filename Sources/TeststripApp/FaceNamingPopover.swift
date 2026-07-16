import TeststripCore

/// Which surface is currently editing a face's name. The loupe face-box overlay
/// (`FaceBoxOverlayView`) and the People inspector rows (`PhotoFacesSectionView`)
/// are on screen together and both offer a naming popover for the same face;
/// this tag lets only the surface the user actually clicked present its popover,
/// so the two never contend for a single presentation.
public enum FaceEditSurface {
    case inspector
    case loupe
}

/// Whether a given surface should present its naming popover for a given row.
/// True only when that surface both owns the current edit and is editing this
/// face — so `AppModel.editingFaceID` can still drive cross-surface highlight
/// (the loupe box lights up while you name from the inspector) without a second
/// popover fighting to appear.
public enum FaceNamingPopover {
    public static func isPresented(
        editingFaceID: FaceID?,
        editingSource: FaceEditSurface?,
        rowFaceID: FaceID,
        surface: FaceEditSurface
    ) -> Bool {
        editingFaceID == rowFaceID && editingSource == surface
    }
}
