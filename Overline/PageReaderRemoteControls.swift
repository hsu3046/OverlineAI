import MediaPlayer

@MainActor
final class PageReaderRemoteControls {
    private var playTarget: Any?
    private var pauseTarget: Any?
    private var toggleTarget: Any?
    private var isActive = false

    func activate(
        onPlay: @escaping @MainActor () -> Void,
        onPause: @escaping @MainActor () -> Void,
        onToggle: @escaping @MainActor () -> Void
    ) {
        guard !isActive else { return }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
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
        isActive = true
    }

    func update(pageIndex: Int, pageCount: Int, isPlaying: Bool, isPaused: Bool) {
        guard isActive else { return }

        let safePageCount = max(pageCount, 1)
        let safePageIndex = min(max(pageIndex, 0), safePageCount - 1)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "책 읽어주기",
            MPMediaItemPropertyArtist: "Overline · \(safePageIndex + 1)/\(safePageCount)쪽",
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
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false

        playTarget = nil
        pauseTarget = nil
        toggleTarget = nil
        isActive = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
