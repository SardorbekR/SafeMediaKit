/// An analyzer that attaches to one live video stream and emits verdicts as
/// the stream changes.
///
/// Create one analyzer per stream. Implementations must deliver every verdict
/// exactly once and in order; do not use a buffering policy that can evict a
/// pending verdict. They must also end promptly when the consuming task is
/// cancelled and detach from any attached media pipeline in ``endAnalysis()``.
///
/// Before yielding a sensitive verdict, a custom implementation must pause or
/// censor its media pipeline and keep it protected until ``continueStream()``
/// or ``endAnalysis()``. The host must conceal or stop its pipeline before
/// ending analysis. Apple's attached capture and decompression paths provide
/// post-detection protection automatically; an asynchronous verdict sequence
/// alone cannot protect frames rendered between detection and delivery to the
/// host.
///
/// Keep every verdict in the current process and on device. Apple's developer
/// agreement prohibits transmitting information about whether Sensitive
/// Content Analysis flagged media.
@MainActor
public protocol SafeMediaStreamAnalyzing: Sendable {
    /// Returns whether stream analysis can be attempted in the current
    /// environment.
    func availability() async -> SafeMediaAvailability

    /// Attaches the configured media pipeline and returns a fresh, ordered
    /// stream of verdicts.
    ///
    /// Returning means attachment succeeded. Keep the sequence alive for the
    /// monitoring lifetime. After a thrown setup error, the engine refreshes
    /// availability and uses the unavailable action if analysis became
    /// unavailable; otherwise setup errors, stream errors, and unexpected
    /// normal completion use the policy's failure action.
    /// ``endAnalysis()`` may be called while this method is suspended; that
    /// call must invalidate the in-progress attachment and tear down any source
    /// that attaches after invalidation.
    func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error>

    /// Resumes analysis and permits the configured stream to continue.
    ///
    /// For Apple's analyzer this also removes the framework's video
    /// censorship, so call it only after the interface is ready to reveal or
    /// safely obscure subsequent frames. The engine calls this when continuing
    /// a sensitive verdict that paused analyzer-level protection. A
    /// non-sensitive blur or failure may pause only the engine's verdict
    /// consumption and does not call the analyzer.
    func continueStream()

    /// Stops analysis and detaches from the configured media pipeline.
    ///
    /// Implementations must make repeated calls safe.
    func endAnalysis()
}

public extension SafeMediaStreamAnalyzing {
    /// Reports stream analysis as available for analyzers without a separate
    /// preflight.
    func availability() async -> SafeMediaAvailability {
        .available
    }
}
