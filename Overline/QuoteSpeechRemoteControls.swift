import MediaPlayer

@MainActor
final class QuoteSpeechRemoteControls {
    private var playTarget: Any?
    private var pauseTarget: Any?
    private var toggleTarget: Any?
    private var nextTarget: Any?
    private var previousTarget: Any?
    private var isActive = false

    func activate(
        onPlay: @escaping @MainActor () -> Void,
        onPause: @escaping @MainActor () -> Void,
        onToggle: @escaping @MainActor () -> Void,
        onNext: @escaping @MainActor () -> Void,
        onPrevious: @escaping @MainActor () -> Void
    ) {
        guard !isActive else { return }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        playTarget = commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in onPlay() }
            return .success
        }
        pauseTarget = commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in onPause() }
            return .success
        }
        toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in onToggle() }
            return .success
        }
        nextTarget = commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in onNext() }
            return .success
        }
        previousTarget = commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in onPrevious() }
            return .success
        }
        isActive = true
    }

    func update(
        bookTitle: String?,
        itemIndex: Int,
        itemCount: Int,
        isPlaying: Bool,
        isPaused: Bool
    ) {
        guard isActive else { return }

        let safeItemCount = max(itemCount, 1)
        let safeItemIndex = min(max(itemIndex, 0), safeItemCount - 1)
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = safeItemIndex + 1 < safeItemCount
        commandCenter.previousTrackCommand.isEnabled = safeItemIndex > 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: bookTitle?.trimmed.nilIfEmpty ?? "글조각 이어듣기",
            MPMediaItemPropertyArtist: "Overline · 글조각 \(safeItemIndex + 1)/\(safeItemCount)",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying && !isPaused ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if isPlaying && !isPaused {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        } else if isPaused {
            MPNowPlayingInfoCenter.default().playbackState = .paused
        } else {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    func deactivate() {
        guard isActive else { return }

        let commandCenter = MPRemoteCommandCenter.shared()
        if let playTarget {
            commandCenter.playCommand.removeTarget(playTarget)
        }
        if let pauseTarget {
            commandCenter.pauseCommand.removeTarget(pauseTarget)
        }
        if let toggleTarget {
            commandCenter.togglePlayPauseCommand.removeTarget(toggleTarget)
        }
        if let nextTarget {
            commandCenter.nextTrackCommand.removeTarget(nextTarget)
        }
        if let previousTarget {
            commandCenter.previousTrackCommand.removeTarget(previousTarget)
        }

        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false

        playTarget = nil
        pauseTarget = nil
        toggleTarget = nil
        nextTarget = nil
        previousTarget = nil
        isActive = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
