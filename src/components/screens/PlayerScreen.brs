' Player with custom controls.
'
' Controls hidden:  OK pauses and shows them; Up/Down shows them; Left/Right shows the
'                   bar and previews a seek. Play/Pause, rewind, fast-forward and instant
'                   replay work too. Back leaves.
' Controls shown:   three rows. Top: Back. Middle: play/pause with Left/Right seeking.
'                   Bottom: Audio & subtitles, Episodes, Next episode, Restart.
' Seeking previews a target on the bar and jumps once Left/Right has been released
' for a moment, since every jump makes an IPTV stream rebuffer.

sub init()
    m.video = m.top.FindNode("video")
    m.spinner = m.top.FindNode("spinner")
    m.keys = m.top.FindNode("keys")

    m.controls = m.top.FindNode("controls")
    m.backBg = m.top.FindNode("backBg")
    m.backLabel = m.top.FindNode("backLabel")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.playBg = m.top.FindNode("playBg")
    m.playIcon = m.top.FindNode("playIcon")
    m.elapsed = m.top.FindNode("elapsed")
    m.remaining = m.top.FindNode("remaining")
    m.barFill = m.top.FindNode("barFill")
    m.barPreview = m.top.FindNode("barPreview")
    m.knob = m.top.FindNode("knob")
    m.bubble = m.top.FindNode("bubble")
    m.bubbleLabel = m.top.FindNode("bubbleLabel")
    m.buttonRow = m.top.FindNode("buttonRow")

    m.upNext = m.top.FindNode("upNext")
    m.upNextTitle = m.top.FindNode("upNextTitle")
    m.upNextHint = m.top.FindNode("upNextHint")
    m.errorBox = m.top.FindNode("errorBox")
    m.errorDetail = m.top.FindNode("errorDetail")
    m.errorTitle = m.top.FindNode("errorTitle")
    m.errorHint = m.top.FindNode("errorHint")
    m.tracks = m.top.FindNode("tracks")
    m.audioList = m.top.FindNode("audioList")
    m.subsList = m.top.FindNode("subsList")
    m.tracksNote = m.top.FindNode("tracksNote")
    m.episodes = m.top.FindNode("episodes")
    m.episodeList = m.top.FindNode("episodeList")

    m.countdown = m.top.FindNode("countdown")
    m.hideTimer = m.top.FindNode("hideTimer")
    m.holdTimer = m.top.FindNode("holdTimer")
    m.commitTimer = m.top.FindNode("commitTimer")

    m.backLabel.font = MakeFont("Fredoka-Medium", 18)
    m.titleLabel.font = MakeFont("Fredoka-Medium", 22)
    m.elapsed.font = MakeFont("Nunito-ExtraBold", 17)
    m.remaining.font = MakeFont("Nunito-ExtraBold", 17)
    m.bubbleLabel.font = MakeFont("Fredoka-SemiBold", 17)
    m.top.FindNode("upNextEyebrow").font = MakeFont("Nunito-ExtraBold", 14)
    m.upNextTitle.font = MakeFont("Fredoka-Medium", 22)
    m.upNextHint.font = MakeFont("Nunito-SemiBold", 17)
    m.errorTitle.font = MakeFont("Fredoka-SemiBold", 28)
    m.errorDetail.font = MakeFont("Nunito-SemiBold", 18)
    m.errorHint.font = MakeFont("Nunito-ExtraBold", 18)
    m.top.FindNode("tracksTitle").font = MakeFont("Fredoka-SemiBold", 34)
    m.top.FindNode("audioHeading").font = MakeFont("Nunito-ExtraBold", 15)
    m.top.FindNode("subsHeading").font = MakeFont("Nunito-ExtraBold", 15)
    m.tracksNote.font = MakeFont("Nunito-SemiBold", 18)
    m.top.FindNode("episodesTitle").font = MakeFont("Fredoka-SemiBold", 34)
    m.spinner.poster.uri = "pkg:/images/spinner.png"
    m.spinner.poster.blendColor = "0xC9B8FFFF"
    m.spinner.poster.width = 64
    m.spinner.poster.height = 64

    m.video.notificationInterval = 1
    m.video.ObserveField("state", "onState")
    m.video.ObserveField("position", "onPosition")
    m.video.ObserveField("availableAudioTracks", "onTracksChanged")
    m.video.ObserveField("availableSubtitleTracks", "onTracksChanged")
    m.countdown.ObserveField("fire", "onCountdown")
    m.hideTimer.ObserveField("fire", "onHideTimer")
    m.holdTimer.ObserveField("fire", "onHoldTick")
    m.commitTimer.ObserveField("fire", "commitSeek")

    m.playback = invalid
    m.kind = "movie"
    m.index = 0
    m.startAt = 0
    m.lastSaved = 0
    m.closing = false
    m.secondsLeft = 0
    m.attempt = 0
    m.started = false
    m.failed = false
    m.errors = []
    m.check = { blocked: "", warning: "" }
    m.tryAnyway = false

    m.row = "bar"
    m.buttons = []
    m.buttonPills = []
    m.buttonIndex = 0
    m.seeking = false
    m.seekTarget = 0.0
    m.holdKey = ""
    m.holdDirection = 1
    m.holdClock = CreateObject("roTimespan")
    m.introShown = false

    m.panel = ""
    m.audioOptions = []
    m.subOptions = []
    m.trackColumn = 1
    m.audioCursor = 0
    m.subCursor = 0
    m.episodeCursor = 0
    m.audioPrefDone = false
    m.subPrefDone = false
end sub

sub onPlayback()
    m.playback = m.top.playback
    m.kind = m.playback.kind
    m.index = ToInt(m.playback.index)
    m.tryAnyway = false
    startItem(ToInt(m.playback.startAt))
end sub

sub onTakeFocus()
    m.keys.SetFocus(true)
end sub

' The movie, or the current episode in the queue, as { id, ext, title, code, codecs }.
function currentItem() as Object
    p = m.playback
    if m.kind = "movie" then
        return {
            id: FieldStr(p, "id")
            ext: FieldStr(p, "ext")
            title: FieldStr(p, "title")
            code: ""
            videoCodec: FieldStr(p, "videoCodec")
            videoProfile: FieldStr(p, "videoProfile")
            audioCodec: FieldStr(p, "audioCodec")
        }
    end if
    return p.queue[m.index]
end function

function streamKind() as String
    if m.kind = "movie" then return "movie"
    return "series"
end function

function hasNextEpisode() as Boolean
    return m.kind = "episode" and m.index + 1 < m.playback.queue.Count()
end function

sub startItem(startAt as Integer)
    m.startAt = startAt
    m.attempt = 0
    m.started = false
    m.failed = false
    m.errors = []
    m.introShown = false
    m.audioPrefDone = false
    m.subPrefDone = false
    cancelSeek()
    closePanel(false)
    hideControls()
    m.upNext.visible = false
    m.errorBox.visible = false

    item = currentItem()
    if m.kind = "movie" then
        m.titleLabel.text = item.title
    else
        m.titleLabel.text = m.playback.seriesName + "   ·   " + item.code + "  " + item.title
    end if
    buildButtons()

    ' Files this TV can't decode would only fail after a wait, so explain up front.
    m.check = PlaybackCheck(item.ext, FieldStr(item, "videoCodec"), FieldStr(item, "videoProfile"), FieldStr(item, "audioCodec"))
    if m.check.blocked <> "" and not m.tryAnyway then
        showUnplayable()
        return
    end if
    loadStream()
end sub

sub showUnplayable()
    item = currentItem()
    m.failed = true
    m.video.control = "stop"
    m.video.visible = false
    m.spinner.visible = false
    m.errorTitle.text = "Your TV can't play this file"
    m.errorDetail.text = UnplayableText(m.check.blocked, item.ext) + Chr(10) + Chr(10) + fileLine(item)
    m.errorHint.text = "OK to try anyway   ·   Back to return"
    m.errorBox.visible = true
end sub

function fileLine(item as Object) as String
    text = "File: " + UCase(FieldStr(item, "ext"))
    codecs = DescribeCodecs(FieldStr(item, "videoCodec"), FieldStr(item, "videoProfile"), FieldStr(item, "audioCodec"))
    if codecs <> "" then return text + ", " + codecs
    return text + ". Your provider didn't list its codecs."
end function

' Attempt 0 tells Roku the format from the file extension. Attempt 1 leaves it out and
' lets Roku work it out from the stream itself, in case the extension is wrong.
sub loadStream()
    item = currentItem()
    content = CreateObject("roSGNode", "ContentNode")
    content.url = StreamUrl(m.global.creds, streamKind(), item.id, item.ext)
    content.title = m.titleLabel.text
    if m.attempt = 0 then
        fmt = StreamFormatFor(item.ext)
        if fmt <> "" then content.streamFormat = fmt
    end if
    ' Back up a few seconds so the scene picks up where it left off.
    if m.startAt > 10 then content.playStart = m.startAt - 5

    m.lastSaved = m.startAt
    m.video.visible = true
    m.video.content = content
    m.video.control = "play"
    m.spinner.visible = true
    m.spinner.control = "start"
    m.keys.SetFocus(true)
end sub

' --- Progress ----------------------------------------------------------------

sub onPosition()
    if m.closing or not m.started then return
    position = Int(m.video.position)
    if Abs(position - m.lastSaved) >= 15 then saveProgress()
    if m.controls.visible then renderBar()
end sub

sub saveProgress()
    if m.playback = invalid or not m.started or m.failed then return
    position = Int(m.video.position)
    duration = Int(m.video.duration)
    if position < 10 then return
    m.lastSaved = position
    if duration > 0 and position >= duration * 0.95 then
        markFinished()
        return
    end if
    ProgressPut(entryFor(m.index, position, duration))
end sub

function entryFor(index as Integer, position as Integer, duration as Integer) as Object
    p = m.playback
    if m.kind = "movie" then
        entry = p.entry
        entry.pos = position
        entry.dur = duration
        return entry
    end if
    ep = p.queue[index]
    return {
        k: "s:" + p.seriesId
        kind: "episode"
        sid: p.seriesId
        id: ep.id
        ext: ep.ext
        name: p.seriesName
        poster: p.poster
        bd: p.backdrop
        season: ep.season
        episode: ep.episode
        etitle: ep.title
        pos: position
        dur: duration
    }
end function

' Movies drop out of Continue Watching; series move on to the next episode.
sub markFinished()
    p = m.playback
    if m.kind = "movie" then
        ProgressRemove(p.entry.k)
    else if hasNextEpisode() then
        ProgressPut(entryFor(m.index + 1, 0, 0))
    else
        ProgressRemove("s:" + p.seriesId)
    end if
end sub

' --- Playback state ------------------------------------------------------------

sub onState()
    if m.closing then return
    state = m.video.state
    m.spinner.visible = (state = "buffering")
    if state = "buffering" then
        m.spinner.control = "start"
    else
        m.spinner.control = "stop"
    end if
    renderPlayButton()

    if state = "playing" then
        m.started = true
        onTracksChanged()
        ' Show the controls briefly the first time, so the buttons are discoverable.
        if not m.introShown then
            m.introShown = true
            showControls("bar")
        else if m.controls.visible then
            restartHideTimer()
        end if
    else if state = "paused" then
        saveProgress()
        if not m.controls.visible then showControls("bar")
        m.hideTimer.control = "stop"
    else if state = "error" then
        onPlaybackError()
    else if state = "finished" then
        ' Roku can report "finished" right after an error. Only a stream that actually
        ' played counts as watched.
        if m.failed or not m.started then return
        markFinished()
        if hasNextEpisode() then
            showUpNext()
        else
            close()
        end if
    end if
end sub

sub onPlaybackError()
    m.errors.Push(describeRokuError())
    if m.attempt = 0 then
        m.attempt = 1
        if m.started then m.startAt = Int(m.video.position)
        m.started = false
        loadStream()
        return
    end if
    m.failed = true
    m.countdown.control = "stop"
    m.upNext.visible = false
    m.video.control = "stop"
    m.video.visible = false
    m.spinner.visible = false
    hideControls()
    closePanel(false)
    m.errorTitle.text = "This video didn't play"
    m.errorDetail.text = diagnosis()
    m.errorHint.text = "OK to try again   ·   Back to return"
    m.errorBox.visible = true
end sub

function describeRokuError() as String
    text = m.video.errorMsg
    if text = "" then text = "unknown error"
    text = text + " (code " + ToStr(m.video.errorCode) + ")"
    detail = ""
    info = m.video.errorInfo
    if IsAA(info) then detail = FieldStr(info, "dbgmsg")
    if detail = "" then detail = ToStr(m.video.errorStr)
    if detail <> "" and detail <> m.video.errorMsg then
        if Len(detail) > 110 then detail = Left(detail, 110) + "…"
        text = text + ": " + detail
    end if
    return text
end function

' What went wrong, what the file is, and whether this TV can decode it.
function diagnosis() as String
    item = currentItem()
    lines = []
    lines.Push("Roku says: " + m.errors.Peek())
    if m.errors.Count() > 1 then lines.Push("Tried twice: with the format hint from the file name, then without it.")

    lines.Push(fileLine(item))

    detected = []
    if ToStr(m.video.videoFormat) <> "" then detected.Push("video " + m.video.videoFormat)
    if ToStr(m.video.audioFormat) <> "" then detected.Push("audio " + m.video.audioFormat)
    if detected.Count() > 0 then lines.Push("Roku detected: " + detected.Join(", "))

    if m.check.blocked <> "" then
        lines.Push(UnplayableText(m.check.blocked, item.ext))
    else if m.check.warning <> "" then
        lines.Push("This TV may not fully support " + m.check.warning + ".")
    else if FieldStr(item, "videoCodec") <> "" then
        lines.Push("This TV says it supports these codecs, so the stream itself is the likely problem.")
    end if

    creds = m.global.creds
    lines.Push("Stream: " + creds.server + "/" + streamKind() + "/" + creds.username + "/••••/" + item.id + "." + item.ext)
    return lines.Join(Chr(10))
end function

' --- Controls ------------------------------------------------------------------

sub buildButtons()
    m.buttons = [{ label: "Audio & subtitles", action: "tracks" }]
    if m.kind = "episode" then
        m.buttons.Push({ label: "Episodes", action: "episodes" })
        if hasNextEpisode() then m.buttons.Push({ label: "Next episode", action: "next" })
    end if
    m.buttons.Push({ label: "Restart", action: "restart" })
    labels = []
    for each button in m.buttons
        labels.Push(button.label)
    end for
    m.buttonPills = BuildPills(m.buttonRow, labels, 17)
    m.buttonIndex = 0
end sub

sub showControls(row as String)
    m.controls.visible = true
    m.row = row
    renderControls()
    restartHideTimer()
end sub

sub hideControls()
    m.controls.visible = false
    m.hideTimer.control = "stop"
end sub

sub restartHideTimer()
    m.hideTimer.control = "stop"
    if m.video.state <> "paused" then m.hideTimer.control = "start"
end sub

sub onHideTimer()
    if m.seeking or m.panel <> "" or m.video.state = "paused" then return
    hideControls()
end sub

sub renderControls()
    if m.row = "top" then
        m.backBg.blendColor = "0xC9B8FFFF"
        m.backBg.opacity = 1.0
        m.backLabel.color = "0x151028FF"
    else
        m.backBg.blendColor = "0x151028FF"
        m.backBg.opacity = 0.6
        m.backLabel.color = "0xF7F3FFFF"
    end if
    buttonFocus = -1
    if m.row = "buttons" then buttonFocus = m.buttonIndex
    StylePills(m.buttonPills, buttonFocus, -1)
    renderPlayButton()
    renderBar()
end sub

sub renderPlayButton()
    if m.video.state = "paused" then
        m.playIcon.uri = "pkg:/images/icon_play.png"
    else
        m.playIcon.uri = "pkg:/images/icon_pause.png"
    end if
    if m.row = "bar" then
        m.playBg.blendColor = "0xC9B8FFFF"
        m.playBg.opacity = 1.0
        m.playIcon.blendColor = "0x151028FF"
    else
        m.playBg.blendColor = "0xF7F3FFFF"
        m.playBg.opacity = 0.2
        m.playIcon.blendColor = "0xF7F3FFFF"
    end if
end sub

sub renderBar()
    barX = 228
    barWidth = 896
    duration = m.video.duration
    position = m.video.position
    shown = position
    if m.seeking then shown = m.seekTarget

    m.elapsed.text = FormatClock(Int(shown))
    if duration > 0 then
        timeLeft = duration - shown
        if timeLeft < 0 then timeLeft = 0
        m.remaining.text = "-" + FormatClock(Int(timeLeft))
    else
        m.remaining.text = ""
    end if

    playedFraction = BarFraction(position, duration)
    shownFraction = BarFraction(shown, duration)
    m.barFill.width = barWidth * playedFraction
    if m.seeking and duration > 0 then
        low = playedFraction
        high = shownFraction
        if high < low then
            low = shownFraction
            high = playedFraction
        end if
        m.barPreview.translation = [barX + barWidth * low, 584]
        m.barPreview.width = barWidth * (high - low)
        m.barPreview.visible = true
    else
        m.barPreview.visible = false
    end if

    knobX = barX + barWidth * shownFraction
    m.knob.translation = [knobX - 9, 577.5]
    m.knob.visible = (m.row = "bar")

    m.bubble.visible = m.seeking
    if m.seeking then
        m.bubbleLabel.text = FormatClock(Int(shown))
        bubbleX = knobX - 52
        if bubbleX < barX - 40 then bubbleX = barX - 40
        if bubbleX > 1232 - 104 then bubbleX = 1232 - 104
        m.bubble.translation = [bubbleX, 530]
    end if
end sub

sub setRow(row as String)
    m.row = row
    renderControls()
    restartHideTimer()
end sub

sub togglePause()
    if m.video.state = "paused" then
        m.video.control = "resume"
    else
        m.video.control = "pause"
        showControls(m.row)
    end if
end sub

sub runButton()
    if m.buttonIndex >= m.buttons.Count() then return
    action = m.buttons[m.buttonIndex].action
    if action = "tracks" then
        openTracks()
    else if action = "episodes" then
        openEpisodes()
    else if action = "next" then
        goToEpisode(m.index + 1)
    else if action = "restart" then
        cancelSeek()
        m.video.seek = 0
        m.lastSaved = 0
        if m.video.state = "paused" then m.video.control = "resume"
        setRow("bar")
    end if
end sub

' Jumps to another episode in the queue; Continue Watching follows.
sub goToEpisode(index as Integer)
    saveProgress()
    ProgressPut(entryFor(index, 0, 0))
    m.index = index
    m.tryAnyway = false
    startItem(0)
end sub

sub leave()
    if not m.failed then saveProgress()
    close()
end sub

' --- Seeking -------------------------------------------------------------------

sub beginHold(key as String, direction as Integer)
    ' Already held: the hold timer does the stepping (guards against key repeats).
    if m.holdKey = key then return
    m.commitTimer.control = "stop"
    if not m.seeking then
        m.seeking = true
        m.seekTarget = m.video.position
    end if
    m.holdKey = key
    m.holdDirection = direction
    m.holdClock.Mark()
    stepSeek(10)
    m.holdTimer.control = "start"
end sub

sub onHoldTick()
    if m.holdKey = "" then
        m.holdTimer.control = "stop"
        return
    end if
    held = m.holdClock.TotalMilliseconds()
    ' A missed key release shouldn't leave the target running away.
    if held > 20000 then
        endHold()
        return
    end if
    ' Taps shorter than half a second are a single step.
    if held >= 500 then stepSeek(HoldStep(held))
end sub

sub stepSeek(seconds as Integer)
    m.seekTarget = ClampSeek(m.seekTarget + seconds * m.holdDirection, m.video.duration)
    if not m.controls.visible then showControls("bar")
    renderBar()
    restartHideTimer()
end sub

sub endHold()
    m.holdKey = ""
    m.holdTimer.control = "stop"
    if m.seeking then m.commitTimer.control = "start"
end sub

sub commitSeek()
    m.commitTimer.control = "stop"
    if not m.seeking then return
    m.seeking = false
    m.video.seek = m.seekTarget
    m.lastSaved = Int(m.seekTarget)
    renderBar()
    restartHideTimer()
end sub

sub cancelSeek()
    m.holdKey = ""
    m.holdTimer.control = "stop"
    m.commitTimer.control = "stop"
    m.seeking = false
end sub

sub jumpBy(seconds as Integer)
    cancelSeek()
    target = ClampSeek(m.video.position + seconds, m.video.duration)
    m.video.seek = target
    m.lastSaved = Int(target)
    showControls("bar")
end sub

' --- Keys ----------------------------------------------------------------------

function directionOf(key as String) as Integer
    if key = "left" or key = "rewind" then return -1
    return 1
end function

function isSeekKey(key as String) as Boolean
    return key = "left" or key = "right" or key = "rewind" or key = "fastforward"
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    ' Releases only matter for ending a held Left/Right.
    if not press then
        if key = m.holdKey then endHold()
        return true
    end if

    if m.panel = "tracks" then return onTrackKey(key)
    if m.panel = "episodes" then return onEpisodeKey(key)

    if m.errorBox.visible then
        if key = "OK" then
            m.tryAnyway = true
            startItem(m.startAt)
        else if key = "back" then
            close()
        end if
        return true
    end if

    if m.upNext.visible then
        if key = "OK" or key = "play" then
            playNext()
        else if key = "back" then
            close()
        end if
        return true
    end if

    ' Back cancels a seek preview, then hides the controls, then leaves.
    if key = "back" then
        if m.seeking then
            cancelSeek()
            renderBar()
        else if m.controls.visible then
            hideControls()
        else
            leave()
        end if
        return true
    else if key = "play" then
        togglePause()
        return true
    else if key = "replay" then
        jumpBy(-10)
        return true
    else if key = "options" then
        openTracks()
        return true
    end if

    if not m.controls.visible then
        if key = "OK" then
            if m.video.state <> "paused" then m.video.control = "pause"
            showControls("bar")
        else if key = "up" or key = "down" then
            showControls("bar")
        else if isSeekKey(key) then
            showControls("bar")
            beginHold(key, directionOf(key))
        end if
        return true
    end if

    restartHideTimer()
    if m.row = "bar" then
        if key = "OK" then
            if m.seeking then
                commitSeek()
            else
                togglePause()
            end if
        else if isSeekKey(key) then
            beginHold(key, directionOf(key))
        else if key = "up" then
            setRow("top")
        else if key = "down" then
            setRow("buttons")
        end if
    else if m.row = "top" then
        if key = "OK" then
            leave()
        else if key = "down" then
            setRow("bar")
        end if
    else if m.row = "buttons" then
        if key = "left" and m.buttonIndex > 0 then
            m.buttonIndex = m.buttonIndex - 1
            renderControls()
        else if key = "right" and m.buttonIndex < m.buttons.Count() - 1 then
            m.buttonIndex = m.buttonIndex + 1
            renderControls()
        else if key = "OK" then
            runButton()
        else if key = "up" then
            setRow("bar")
        end if
    end if
    return true
end function

' --- Up next -------------------------------------------------------------------

sub showUpNext()
    upcoming = m.playback.queue[m.index + 1]
    m.upNextTitle.text = upcoming.code + "  " + upcoming.title
    m.secondsLeft = 8
    updateCountdown()
    hideControls()
    closePanel(false)
    m.upNext.visible = true
    m.countdown.control = "start"
end sub

sub onCountdown()
    m.secondsLeft = m.secondsLeft - 1
    if m.secondsLeft <= 0 then
        playNext()
    else
        updateCountdown()
    end if
end sub

sub updateCountdown()
    m.upNextHint.text = "Starts in " + m.secondsLeft.ToStr() + "   ·   OK to play now"
end sub

sub playNext()
    m.countdown.control = "stop"
    m.index = m.index + 1
    m.tryAnyway = false
    startItem(0)
end sub

sub close()
    m.closing = true
    cancelSeek()
    m.countdown.control = "stop"
    m.hideTimer.control = "stop"
    m.video.control = "stop"
    m.top.action = { name: "close" }
end sub

' --- Panels (audio & subtitles, episodes) ---------------------------------------

sub closePanel(backToControls as Boolean)
    m.panel = ""
    m.tracks.visible = false
    m.episodes.visible = false
    if backToControls then showControls("buttons")
end sub

' Applies the audio and subtitle languages chosen earlier, once per stream, as soon as
' Roku has listed the tracks.
sub onTracksChanged()
    if not m.started then return
    prefs = LoadPrefs()
    if not m.audioPrefDone then
        options = AudioOptions(m.video.availableAudioTracks)
        if options.Count() > 0 then
            m.audioPrefDone = true
            index = OptionIndex(options, "language", FieldStr(prefs, "audio"))
            if index >= 0 and options[index].id <> ToStr(m.video.audioTrack) then m.video.audioTrack = options[index].id
        end if
    end if
    if not m.subPrefDone then
        options = SubtitleOptions(m.video.availableSubtitleTracks)
        if options.Count() > 1 then
            m.subPrefDone = true
            wanted = FieldStr(prefs, "subtitles")
            index = OptionIndex(options, "language", wanted)
            if wanted <> "" and wanted <> "off" and index > 0 then
                m.video.subtitleTrack = options[index].id
                m.video.globalCaptionMode = "On"
            end if
        end if
    end if
end sub

sub openTracks()
    cancelSeek()
    m.audioOptions = AudioOptions(m.video.availableAudioTracks)
    m.subOptions = SubtitleOptions(m.video.availableSubtitleTracks)
    m.audioCursor = activeAudioIndex()
    if m.audioCursor < 0 then m.audioCursor = 0
    m.subCursor = activeSubtitleIndex()
    if m.subCursor < 0 then m.subCursor = 0
    m.trackColumn = 1
    notes = []
    if m.subOptions.Count() = 1 then notes.Push("This file has no built-in subtitles.")
    if m.audioOptions.Count() <= 1 then notes.Push("It has one audio track.")
    m.tracksNote.text = notes.Join(" ")
    hideControls()
    m.panel = "tracks"
    m.tracks.visible = true
    renderTracks()
end sub

function activeAudioIndex() as Integer
    return OptionIndex(m.audioOptions, "id", ToStr(m.video.audioTrack))
end function

function activeSubtitleIndex() as Integer
    if ToStr(m.video.globalCaptionMode) <> "On" then return 0
    return OptionIndex(m.subOptions, "id", ToStr(m.video.subtitleTrack))
end function

sub renderTracks()
    renderOptions(m.audioList, m.audioOptions, activeAudioIndex(), m.audioCursor, m.trackColumn = 0, 440, 8)
    renderOptions(m.subsList, m.subOptions, activeSubtitleIndex(), m.subCursor, m.trackColumn = 1, 440, 8)
end sub

sub chooseTrack()
    if m.trackColumn = 0 then
        if m.audioOptions.Count() = 0 then return
        option = m.audioOptions[m.audioCursor]
        m.video.audioTrack = option.id
        if option.language <> "" then SavePref("audio", option.language)
    else
        option = m.subOptions[m.subCursor]
        if option.id = "" then
            m.video.globalCaptionMode = "Off"
            SavePref("subtitles", "off")
        else
            m.video.subtitleTrack = option.id
            m.video.globalCaptionMode = "On"
            if option.language <> "" then SavePref("subtitles", option.language)
        end if
    end if
    renderTracks()
end sub

function onTrackKey(key as String) as Boolean
    if key = "back" or key = "options" then
        closePanel(true)
        return true
    else if key = "left" and m.audioOptions.Count() > 0 then
        m.trackColumn = 0
    else if key = "right" then
        m.trackColumn = 1
    else if key = "up" then
        if m.trackColumn = 0 and m.audioCursor > 0 then m.audioCursor = m.audioCursor - 1
        if m.trackColumn = 1 and m.subCursor > 0 then m.subCursor = m.subCursor - 1
    else if key = "down" then
        if m.trackColumn = 0 and m.audioCursor < m.audioOptions.Count() - 1 then m.audioCursor = m.audioCursor + 1
        if m.trackColumn = 1 and m.subCursor < m.subOptions.Count() - 1 then m.subCursor = m.subCursor + 1
    else if key = "OK" then
        chooseTrack()
        return true
    end if
    renderTracks()
    return true
end function

sub openEpisodes()
    cancelSeek()
    m.episodeCursor = m.index
    hideControls()
    m.panel = "episodes"
    m.episodes.visible = true
    renderEpisodes()
end sub

sub renderEpisodes()
    options = []
    for each ep in m.playback.queue
        options.Push({ id: ep.id, label: ep.code + "   " + ep.title })
    end for
    renderOptions(m.episodeList, options, m.index, m.episodeCursor, true, 1040, 9)
end sub

function onEpisodeKey(key as String) as Boolean
    if key = "back" then
        closePanel(true)
    else if key = "up" and m.episodeCursor > 0 then
        m.episodeCursor = m.episodeCursor - 1
        renderEpisodes()
    else if key = "down" and m.episodeCursor < m.playback.queue.Count() - 1 then
        m.episodeCursor = m.episodeCursor + 1
        renderEpisodes()
    else if key = "OK" then
        if m.episodeCursor = m.index then
            closePanel(true)
        else
            goToEpisode(m.episodeCursor)
        end if
    end if
    return true
end function

' Draws a window of options around the cursor. The active one gets an amber dot.
sub renderOptions(group as Object, options as Object, activeIndex as Integer, cursor as Integer, focused as Boolean, width as Integer, visibleCount as Integer)
    group.RemoveChildrenIndex(group.GetChildCount(), 0)
    if options.Count() = 0 then
        empty = group.CreateChild("Label")
        empty.font = MakeFont("Nunito-SemiBold", 20)
        empty.color = "0x8579B0FF"
        empty.text = "Default"
        return
    end if
    first = cursor - (visibleCount \ 2)
    if first > options.Count() - visibleCount then first = options.Count() - visibleCount
    if first < 0 then first = 0
    last = first + visibleCount - 1
    if last > options.Count() - 1 then last = options.Count() - 1
    y = 0
    for i = first to last
        row = group.CreateChild("Group")
        row.translation = [0, y]
        bg = row.CreateChild("Poster")
        bg.uri = "pkg:/images/pill.9.png"
        bg.width = width
        bg.height = 44
        dot = row.CreateChild("Rectangle")
        dot.translation = [20, 18]
        dot.width = 8
        dot.height = 8
        dot.visible = (i = activeIndex)
        label = row.CreateChild("Label")
        label.translation = [44, 0]
        label.width = width - 60
        label.height = 44
        label.vertAlign = "center"
        label.font = MakeFont("Nunito-ExtraBold", 20)
        label.text = options[i].label
        if focused and i = cursor then
            bg.blendColor = "0xC9B8FFFF"
            bg.opacity = 1.0
            label.color = "0x151028FF"
            dot.color = "0x151028FF"
        else
            bg.opacity = 0.0
            dot.color = "0xFF9ECFFF"
            label.color = "0xA195CCFF"
            if i = activeIndex then label.color = "0xF7F3FFFF"
        end if
        y = y + 50
    end for
end sub
