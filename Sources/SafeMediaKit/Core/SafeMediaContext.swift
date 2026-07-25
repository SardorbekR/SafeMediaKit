/// The product context in which media is being evaluated.
///
/// The engine carries this value into each decision so a host app can apply
/// context-specific presentation or local workflow behavior.
public enum SafeMediaContext: Sendable, Hashable {
    /// Media received in a conversation.
    case incomingMessage

    /// Media selected for upload or sending.
    case outgoingUpload

    /// Media displayed as a small feed preview.
    case feedThumbnail

    /// Media displayed as a person's profile image.
    case profileAvatar

    /// Media displayed in a full-screen viewer.
    case fullScreenViewer

    /// Media submitted in a classroom workflow.
    case classroomSubmission

    /// A preview generated from a video file.
    case videoFilePreview

    /// A live video stream, including a video call or live broadcast.
    case liveVideo
}
