' Player with custom controls.
'
' Controls hidden:  OK pauses and shows them; Up/Down shows them; Left/Right shows the
'                   bar and previews a seek. Play/Pause, rewind, fast-forward and instant
'                   replay work too. Back leaves.
' Controls shown:   three rows. Top: Back. Middle: play/pause with Left/Right seeking.
'                   Bottom: Audio & subtitles, Episodes, Next episode, Restart.
' Seeking previews a target on the bar and jumps once Left/Right has been released
' for a moment, since every jump makes an IPTV stream rebuffer.
'
' Files this Roku can't play go through the helper on a computer at home when there is
' one (common/Helper.brs): it converts them into HLS while you watch.

sub init()
    m.video = m.top.FindNode("video")
    m.spinner = m.top.FindNode("spinner")
    m.keys = m.top.FindNode("keys")

    m.controls = m.top.FindNode("controls")
    ' Whether the controls are up (they may still be fading away when not).
    m.controlsOn = false
    m.controlsIn = m.top.FindNode("controlsIn")
    m.controlsInFade = m.top.FindNode("controlsInFade")
    m.controlsOut = m.top.FindNode("controlsOut")
    m.controlsOutFade = m.top.FindNode("controlsOutFade")
    m.controlsOut.ObserveField("state", "onControlsGone")
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
    m.thumb = m.top.FindNode("thumb")
    m.thumbPics = m.top.FindNode("thumbPics")
    m.thumbFront = invalid
    m.thumbLoader = invalid
    m.thumbShown = ""
    m.thumbLoading = ""
    m.thumbLoadAt = 0.0
    m.thumbMissing = {}
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
    m.autoSubTimer = m.top.FindNode("autoSubTimer")

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
    m.autoSubTimer.ObserveField("fire", "autoSubtitles")
    m.toast = m.top.FindNode("toast")
    m.toastText = m.top.FindNode("toastText")
    m.toastText.font = MakeFont("Nunito-SemiBold", 18)
    m.toastTimer = m.top.FindNode("toastTimer")
    m.toastTimer.ObserveField("fire", "hideToast")
    m.pauseTimer = m.top.FindNode("pauseTimer")
    m.pauseTimer.ObserveField("fire", "onPauseDone")
    m.afterPause = ""

    m.playback = invalid
    m.kind = "movie"
    m.index = 0
    ' The episode already counted as finished (noteTaste, markFinished).
    m.tasteEpisode = -1
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
    m.probeTask = invalid
    resetProbe()
    m.helperTask = invalid
    m.stopTask = invalid
    m.helperToken = 0
    m.helperUsed = false
    ' The helper's latest session, kept across titles: stopping it frees the provider.
    m.helperSession = ""
    resetHelper()

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
    m.audioChecked = false
    m.subPrefDone = false
    resetOnline()
end sub

sub onPlayback()
    ' Search indexing waits while a video plays.
    m.global.playing = true
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
    resetProbe()
    resetHelper()
    m.introShown = false
    m.audioPrefDone = false
    m.audioChecked = false
    m.subPrefDone = false
    resetOnline()
    lookUpSaved()
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

    ' Files this TV can't decode would only fail after a wait, so explain up front, or
    ' play them through the helper on a computer at home, with the titles that played
    ' badly on their own before (only DTS sound, say).
    m.check = PlaybackCheck(item.ext, FieldStr(item, "videoCodec"), FieldStr(item, "videoProfile"), FieldStr(item, "audioCodec"))
    if HelperRoute(m.check, { listed: HelperListed(itemKey()) }, HelperOn(), false) then
        m.helperFromStart = true
        startHelper(resumePoint(startAt))
        return
    end if
    if m.check.blocked <> "" and not m.tryAnyway then
        showUnplayable()
        return
    end if
    if m.helperUsed then
        ' The helper may still hold the provider's one connection; free it first.
        m.video.control = "stop"
        stopHelper()
        pauseThen("direct")
        return
    end if
    loadStream()
end sub

' Resuming backs up a few seconds, so the scene picks up where it left off.
function resumePoint(startAt as Integer) as Integer
    if startAt > 10 then return startAt - 5
    return 0
end function

' "m:<id>" for a movie, "e:<id>" for an episode, as in helper/titles.
function itemKey() as String
    if m.kind = "movie" then return "m:" + currentItem().id
    return "e:" + currentItem().id
end function

sub showUnplayable()
    item = currentItem()
    m.failed = true
    m.video.control = "stop"
    m.video.visible = false
    m.spinner.visible = false
    m.errorTitle.text = "Your " + DeviceWord() + " can't play this file"
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
    userAgent = FieldStr(m.global.creds, "userAgent")
    if userAgent <> "" then content.HttpHeaders = ["User-Agent: " + userAgent]
    if m.attempt = 0 then
        fmt = StreamFormatFor(item.ext)
        if fmt <> "" then content.streamFormat = fmt
    end if
    ' Back up a few seconds so the scene picks up where it left off.
    if m.startAt > 10 then content.playStart = m.startAt - 5
    attachOnlineSubtitle(content, false)

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
    position = Int(positionSecs())
    m.lastPos = position
    if m.pendingSeek >= 0 and Abs(position - m.pendingSeek) < 15 then m.pendingSeek = -1
    ' A minute of playing since the helper's stream last opened again: it's fine.
    if m.helperReopens > 0 and position - m.offset > 60 then m.helperReopens = 0
    if Abs(position - m.lastSaved) >= 15 then saveProgress()
    if m.controlsOn then renderBar()
end sub

' Where the video is, in seconds from the file's start. Through the helper, a growing
' playlist starts at m.offset and Roku counts from there (a whole film's is at 0).
function positionSecs() as Float
    return m.offset + m.video.position
end function

' The file's length. Through the helper, the length the helper read from the file,
' since its stream only lists what is converted so far.
function durationSecs() as Float
    if m.route <> "helper" then return m.video.duration
    if m.helperStarted <> invalid and m.helperStarted.duration > 0 then return m.helperStarted.duration
    if m.helperInfo <> invalid and m.helperInfo.duration > 0 then return m.helperInfo.duration
    if m.video.duration > 0 then return m.offset + m.video.duration
    return 0
end function

sub saveProgress()
    if m.playback = invalid or not m.started or m.failed then return
    position = Int(positionSecs())
    duration = Int(durationSecs())
    if position < 10 then return
    m.lastSaved = position
    noteTaste(position, duration)
    if duration > 0 and position >= duration * 0.95 then
        markFinished()
        return
    end if
    ProgressPut(entryFor(m.index, position, duration))
    ' Share the spot with other devices every 5 minutes too, not only when leaving.
    if m.syncClock = invalid then m.syncClock = CreateObject("roTimespan")
    if m.syncClock.TotalSeconds() >= 300 then
        m.syncClock.Mark()
        m.top.action = { name: "syncNow" }
    end if
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

' What you're watching, for the rows picked for you (common/Taste.brs): a movie by how
' far you are, a series once you're 3 minutes into an episode.
sub noteTaste(position as Integer, duration as Integer)
    p = m.playback
    if m.kind = "movie" then
        TasteWatched(FieldStr(p.entry, "k"), FieldStr(p.entry, "name"), TasteWeightFor(position, duration))
    else if position >= 180 then
        TasteWatched("s:" + p.seriesId, p.seriesName, 1)
    end if
end sub

' Movies drop out of Continue Watching; series move on to the next episode.
sub markFinished()
    p = m.playback
    ' Watched to the end: a movie counts most, a series a little more each episode.
    if m.kind = "movie" then
        TasteFinished(FieldStr(p.entry, "k"), FieldStr(p.entry, "name"))
    else if m.tasteEpisode <> m.index then
        m.tasteEpisode = m.index
        TasteEpisodeDone("s:" + p.seriesId, p.seriesName)
    end if
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
        if m.route = "helper" then m.helperPlayed = true
        onTracksChanged()
        if not m.audioChecked then
            m.audioChecked = true
            checkAudioPlayable()
        end if
        if m.pendingSubtitle <> "" then
            m.video.subtitleTrack = m.pendingSubtitle
            m.video.globalCaptionMode = "On"
            m.pendingSubtitle = ""
        end if
        if not m.autoChecked then
            m.autoChecked = true
            m.autoSubTimer.control = "start"
        end if
        ' Show the controls briefly the first time, so the buttons are discoverable.
        if not m.introShown then
            m.introShown = true
            showControls("bar")
        else if m.controlsOn then
            restartHideTimer()
        end if
    else if state = "paused" then
        saveProgress()
        if not m.controlsOn then showControls("bar")
        m.hideTimer.control = "stop"
    else if state = "error" then
        onPlaybackError()
    else if state = "finished" then
        ' Roku can report "finished" right after an error. Only a stream that actually
        ' played counts as watched.
        if m.failed or not m.started then return
        ' The helper's stream ends early when its FFmpeg was stopped (a long pause,
        ' another device) or the provider's connection dropped: not the end of the film.
        if m.route = "helper" and HelperEndedEarly(m.lastPos, Int(durationSecs())) then
            m.errors.Push("the stream from your computer ended at " + FormatClock(m.lastPos) + " of " + FormatClock(Int(durationSecs())))
            helperFailed()
            return
        end if
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
    if m.route = "helper" then
        helperFailed()
        return
    end if
    if m.started then m.startAt = Int(positionSecs())
    m.started = false
    ' A refused request won't change with a different format hint, so ask the server
    ' directly, as a Roku and as ARAN+, whether it would send this video.
    if not m.probed and isHttpRefusal() then
        m.probed = true
        startProbe()
        return
    end if
    if m.attempt = 0 and not m.probed then
        retryWithoutHint()
        return
    end if
    directFailed()
end sub

' The stream didn't play on its own: try it through the helper on your computer, unless
' the provider turned it down every way (it won't do better through the helper).
sub directFailed()
    if HelperRoute(m.check, { failed: true, refused: m.probeRefused }, HelperOn(), m.helperTried) then
        startHelper(m.startAt)
        return
    end if
    showPlaybackError()
end sub

sub retryWithoutHint()
    m.attempt = 1
    m.formatRetried = true
    loadStream()
end sub

sub resetProbe()
    if m.probeTask <> invalid then m.probeTask.UnobserveField("result")
    m.probeTask = invalid
    m.probed = false
    m.probeLines = []
    m.probeRefused = false
    m.formatRetried = false
    m.agentSwitched = false
end sub

function rokuErrorText() as String
    text = ToStr(m.video.errorMsg) + " " + ToStr(m.video.errorStr)
    info = m.video.errorInfo
    if IsAA(info) then text = text + " " + FieldStr(info, "dbgmsg")
    return text
end function

' Roku's code -1 is an HTTP error; the text usually carries the status too.
function isHttpRefusal() as Boolean
    if m.video.errorCode = -1 then return true
    return HttpCodeIn(rokuErrorText()) >= 400
end function

sub startProbe()
    m.video.control = "stop"
    m.spinner.visible = true
    m.spinner.control = "start"
    m.probeTask = CreateObject("roSGNode", "XtreamTask")
    m.probeTask.request = { mode: "probe", url: currentStreamUrl(), agents: UserAgentsToTry(FieldStr(m.global.creds, "userAgent")) }
    m.probeTask.ObserveField("result", "onProbeResult")
    m.probeTask.control = "RUN"
end sub

sub onProbeResult(event as Object)
    result = event.GetData()
    m.probeTask = invalid
    if m.closing then return
    results = result.results
    if not IsArr(results) or results.Count() < 2 then
        directFailed()
        return
    end if
    current = results[0]
    m.probeLines = []
    better = invalid
    allRefused = true
    for each res in results
        m.probeLines.Push(probeLine(res))
        if res.ok and better = invalid and res.agent <> current.agent then better = res
        if res.ok or ToInt(res.code) < 400 then allRefused = false
    end for
    if better <> invalid and not current.ok then
        ' The server sends it under another name, so use that from now on.
        creds = m.global.creds
        creds.userAgent = better.agent
        m.global.creds = creds
        SaveCreds(creds)
        m.agentSwitched = true
        loadStream()
        return
    end if
    m.probeRefused = allRefused
    if current.ok and m.attempt = 0 then
        retryWithoutHint()
        return
    end if
    directFailed()
end sub

function probeLine(res as Object) as String
    who = "Checked " + UserAgentName(FieldStr(res, "agent")) + ": "
    if res.ok then return who + "the server would send it."
    return who + FieldStr(res, "detail") + "."
end function

sub showPlaybackError()
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
    if m.route = "helper" then return helperDiagnosis(item)
    lines = []
    lines.Push("Roku says: " + m.errors.Peek())
    if m.formatRetried then lines.Push("Tried twice: with the format hint from the file name, then without it.")
    if m.agentSwitched then lines.Push("The server accepted another way of asking, so it tried again " + UserAgentName(FieldStr(m.global.creds, "userAgent")) + ".")
    lines.Append(m.probeLines)
    if m.probeRefused then
        lines.Push("The server turned this video down every way. The trial may not include it, may allow one device at a time, or may have ended.")
        lines.Push(fileLine(item))
        lines.Push(streamLine(item))
        return lines.Join(Chr(10))
    end if

    lines.Push(fileLine(item))

    detected = []
    if ToStr(m.video.videoFormat) <> "" then detected.Push("video " + m.video.videoFormat)
    if ToStr(m.video.audioFormat) <> "" then detected.Push("audio " + m.video.audioFormat)
    if detected.Count() > 0 then lines.Push("Roku detected: " + detected.Join(", "))

    if m.check.blocked <> "" then
        lines.Push(UnplayableText(m.check.blocked, item.ext))
    else if m.check.warning <> "" then
        lines.Push("This " + DeviceWord() + " may not fully support " + m.check.warning + ".")
    else if FieldStr(item, "videoCodec") <> "" then
        lines.Push("This " + DeviceWord() + " says it supports these codecs, so the stream itself is the likely problem.")
    end if

    lines.Push(streamLine(item))
    return lines.Join(Chr(10))
end function

function streamLine(item as Object) as String
    creds = m.global.creds
    return "Stream: " + creds.server + "/" + streamKind() + "/" + creds.username + "/••••/" + item.id + "." + item.ext
end function

' --- The helper on a computer at home ------------------------------------------------
'
' The helper (common/Helper.brs) fetches the file from the provider and converts it
' into HLS while you watch: first what the file holds, then (with online subtitles set
' up) its fingerprint, then the stream from where it should play. For a film of known
' length the playlist lists the whole film and the stream's clock is the film's, so Roku
' jumps by itself; otherwise the playlist grows from where it started (m.offset), and
' positions are m.offset plus Roku's.

sub resetHelper()
    m.route = "direct"
    m.offset = 0
    m.helperInfo = invalid
    m.helperHash = ""
    m.helperHashAsked = false
    m.helperStarted = invalid
    m.helperVod = false
    m.helperTrack = -1
    m.helperVideo = "convert"
    m.helperTried = false
    m.helperFromStart = false
    m.helperPlayed = false
    m.helperProblem = ""
    m.helperSaid = ""
    m.helperReopens = 0
    m.helperPreviews = invalid
    forgetThumbs()
    m.pendingSeek = -1
    m.lastPos = 0
    ' Answers about the title before are dropped.
    m.helperToken = m.helperToken + 1
    if m.helperTask <> invalid then m.helperTask.UnobserveField("result")
    m.helperTask = invalid
    if m.pauseTimer <> invalid then m.pauseTimer.control = "stop"
end sub

' Moves this title to the helper, from `startAt` seconds.
sub startHelper(startAt as Integer)
    m.route = "helper"
    m.helperTried = true
    m.startAt = startAt
    m.started = false
    m.failed = false
    m.errorBox.visible = false
    ' The provider allows one connection, so let go of it before the helper asks.
    state = m.video.state
    wasStreaming = state = "playing" or state = "paused" or state = "buffering"
    m.video.control = "stop"
    m.spinner.visible = true
    m.spinner.control = "start"
    if wasStreaming then
        pauseThen("helper")
    else
        helperGo()
    end if
end sub

' Gives the provider a moment to notice a closed connection, then goes on.
sub pauseThen(what as String)
    m.afterPause = what
    m.spinner.visible = true
    m.spinner.control = "start"
    m.pauseTimer.control = "stop"
    m.pauseTimer.control = "start"
end sub

sub onPauseDone()
    m.pauseTimer.control = "stop"
    if m.closing then return
    if m.afterPause = "direct" then
        loadStream()
    else
        helperGo()
    end if
end sub

' The next step: what the file holds (once per title), its fingerprint for online
' subtitles (once, before the stream: asking during it would stop the helper's FFmpeg),
' then the stream.
sub helperGo()
    if m.closing then return
    item = currentItem()
    config = TranscoderConfig()
    if m.helperInfo = invalid then
        runHelper({ mode: "info", url: HelperInfoUrl(config, streamKind(), item.id, item.ext) }, "onHelperInfo")
    else if not m.helperHashAsked and LoadOsAccount() <> invalid then
        runHelper({ mode: "hash", url: HelperHashUrl(config, streamKind(), item.id, item.ext) }, "onHelperHash")
    else
        requestStart(m.startAt)
    end if
end sub

sub runHelper(request as Object, callback as String)
    if m.helperTask <> invalid then m.helperTask.UnobserveField("result")
    request.token = m.helperToken
    m.helperTask = CreateObject("roSGNode", "HelperTask")
    m.helperTask.request = request
    m.helperTask.ObserveField("result", callback)
    m.helperTask.control = "RUN"
end sub

' Results for a title that's no longer playing are dropped.
function helperResultFor(event as Object) as Dynamic
    result = event.GetData()
    m.helperTask = invalid
    if m.closing or ToInt(Field(Field(result, "request"), "token")) <> m.helperToken then return invalid
    return result
end function

sub onHelperInfo(event as Object)
    result = helperResultFor(event)
    if result = invalid then return
    if not result.ok then
        m.helperProblem = FieldStr(result, "error")
        showPlaybackError()
        return
    end if
    info = result.info
    m.helperInfo = info
    canPicture = false
    if info.videoCodec <> "" then canPicture = canDecode("video", RokuVideoCodec(info.videoCodec), "")
    m.helperVideo = HelperVideo(info.videoPlan, canPicture)
    helperGo()
end sub

' Without a fingerprint the search goes on by title, so a failure here isn't one.
sub onHelperHash(event as Object)
    result = helperResultFor(event)
    if result = invalid then return
    m.helperHashAsked = true
    if result.ok then m.helperHash = FieldStr(result, "hash")
    helperGo()
end sub

' Asks the helper for the stream, playing from `startAt` seconds; it answers once the
' first piece is ready.
sub requestStart(startAt as Integer)
    if startAt < 0 then startAt = 0
    m.startAt = startAt
    m.started = false
    m.helperPlayed = false
    m.pendingSeek = -1
    m.spinner.visible = true
    m.spinner.control = "start"
    if m.helperInfo = invalid then
        helperGo()
        return
    end if
    item = currentItem()
    track = m.helperTrack
    if track < 0 then track = HelperTrack(m.helperInfo.audio, FieldStr(LoadPrefs(), "audio"))
    choice = {
        video: m.helperVideo
        height: HelperHeight(screenHeight())
        hevc: canDecode("video", "hevc", "")
        track: track
    }
    runHelper({ mode: "start", url: HelperStartUrl(TranscoderConfig(), streamKind(), item.id, item.ext, startAt, choice) }, "onHelperStart")
end sub

sub onHelperStart(event as Object)
    result = helperResultFor(event)
    if result = invalid then return
    if not result.ok then
        m.helperProblem = FieldStr(result, "error")
        showPlaybackError()
        return
    end if
    m.helperStarted = result.started
    openHelper()
end sub

' Plays the stream the helper started (m.helperStarted).
sub openHelper()
    started = m.helperStarted
    showing = onlineSubtitleShowing()
    m.helperSession = started.session
    m.helperVod = started.vod
    m.helperUsed = true
    ' Another session's pictures are another film's, or another sound track's.
    m.helperPreviews = invalid
    if started.vod then m.helperPreviews = started.previews
    forgetThumbs()
    ' A whole film's clock is the film's; a growing playlist's starts where it did.
    m.offset = started.start
    at = started.start
    if started.vod then at = started.playFrom
    content = CreateObject("roSGNode", "ContentNode")
    content.url = TranscoderConfig().url + started.url
    content.title = m.titleLabel.text
    content.streamFormat = "hls"
    if started.vod and at > 0 then content.playStart = at
    attachOnlineSubtitle(content, showing)
    ' The new stream numbers its tracks afresh.
    m.audioPrefDone = false
    m.subPrefDone = false
    m.startAt = at
    m.lastSaved = at
    m.lastPos = at
    m.started = false
    m.video.visible = true
    m.video.content = content
    m.video.control = "play"
    m.spinner.visible = true
    m.spinner.control = "start"
    m.keys.SetFocus(true)
end sub

function screenHeight() as Integer
    return ToInt(Field(CreateObject("roDeviceInfo").GetDisplaySize(), "h"))
end function

' The helper's stream failed. One that had played opens again from where it got to
' (the helper may have been restarted, or dropped the stream after a long pause),
' twice at most. One that never played is asked for once more. Otherwise ask the
' helper why, then explain.
sub helperFailed()
    target = Int(positionSecs())
    if m.lastPos > target then target = m.lastPos
    if m.pendingSeek >= 0 then target = Int(m.pendingSeek)
    limit = 1
    if m.helperPlayed then limit = 2
    m.started = false
    m.video.control = "stop"
    if m.helperReopens < limit then
        m.helperReopens = m.helperReopens + 1
        requestStart(target)
        return
    end if
    m.startAt = target
    m.spinner.visible = true
    m.spinner.control = "start"
    runHelper({ mode: "lastError", url: HelperErrorUrl(TranscoderConfig()) }, "onHelperLastError")
end sub

sub onHelperLastError(event as Object)
    result = helperResultFor(event)
    if result = invalid then return
    if result.ok then
        m.helperSaid = FieldStr(result, "said")
    else
        m.helperProblem = FieldStr(result, "error")
    end if
    showPlaybackError()
end sub

' The helper's stream carries one sound track: choosing another starts the stream again
' with it, from here.
sub chooseHelperTrack(n as Integer)
    if m.helperStarted <> invalid and n = m.helperStarted.audioTrack then return
    ' Where it is now, before stopping (a stopped video's position goes back to 0).
    at = Int(positionSecs())
    if not m.started or m.lastPos > at then at = m.lastPos
    m.helperTrack = n
    m.video.control = "stop"
    closePanel(false)
    requestStart(at)
end sub

' Stops the helper's FFmpeg, so the provider's one connection is free for a stream
' straight from the provider.
sub stopHelper()
    m.helperUsed = false
    if not HelperOn() then return
    m.stopTask = CreateObject("roSGNode", "HelperTask")
    m.stopTask.request = { mode: "stop", url: HelperStopUrl(TranscoderConfig(), m.helperSession) }
    m.stopTask.control = "RUN"
end sub

' What went wrong through the helper: who said what, what the helper was doing, the
' file, and the helper's address (its key stays hidden).
function helperDiagnosis(item as Object) as String
    config = TranscoderConfig()
    lines = []
    if m.helperProblem <> "" then
        lines.Push(m.helperProblem)
    else
        if m.errors.Count() > 0 then lines.Push("Roku says: " + m.errors.Peek())
        if m.helperSaid <> "" then lines.Push("Your computer says: " + m.helperSaid)
    end if
    if m.helperFromStart then
        lines.Push("This " + DeviceWord() + " can't play this file itself, so it went through the helper on your computer.")
    else
        lines.Push("It didn't play on its own, so it was tried through the helper on your computer.")
    end if
    if m.helperInfo <> invalid and m.helperStarted <> invalid then lines.Push(HelperPlanLine(m.helperInfo, m.helperStarted))
    lines.Push(fileLine(item))
    if config <> invalid then
        lines.Push("Helper: " + config.url)
        if m.helperProblem = HelperFailure(0, "") then lines.Push("Often the computer is asleep or off, the helper's window was closed, or the computer's address has changed (a fixed address in the router keeps it).")
    end if
    text = lines.Join(Chr(10))
    if config <> invalid and Len(config.key) >= 3 then text = text.Replace(config.key, "••••")
    return text
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
    if not m.controlsOn then
        m.controlsOn = true
        m.controlsOut.control = "stop"
        fadeFrom = 0.0
        if m.controls.visible then fadeFrom = m.controls.opacity
        m.controls.visible = true
        m.controlsInFade.keyValue = [fadeFrom, 1.0]
        m.controlsIn.control = "start"
    end if
    m.row = row
    renderControls()
    restartHideTimer()
end sub

sub hideControls()
    m.hideTimer.control = "stop"
    if not m.controlsOn then return
    m.controlsOn = false
    m.controlsIn.control = "stop"
    m.controlsOutFade.keyValue = [m.controls.opacity, 0.0]
    m.controlsOut.control = "start"
end sub

sub onControlsGone()
    if m.controlsOut.state = "stopped" and not m.controlsOn then m.controls.visible = false
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
    icon = "pkg:/images/icon_pause.png"
    if m.video.state = "paused" then icon = "pkg:/images/icon_play.png"
    ' Play turning into pause (and back) pops.
    if m.playIcon.uri <> icon then
        m.playIcon.uri = icon
        Tween(m.playIcon, "scale", [[0.6, 0.6], [1.0, 1.0]], 0.32, "outExpo", 0)
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
    duration = durationSecs()
    position = positionSecs()
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
    renderThumb(shown, knobX)
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
        seekTo(0)
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
        m.seekTarget = positionSecs()
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
    m.seekTarget = ClampSeek(m.seekTarget + seconds * m.holdDirection, durationSecs())
    if not m.controlsOn then showControls("bar")
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
    seekTo(m.seekTarget)
    renderBar()
    restartHideTimer()
end sub

sub cancelSeek()
    m.holdKey = ""
    m.holdTimer.control = "stop"
    m.commitTimer.control = "stop"
    m.seeking = false
    clearThumb()
end sub

sub jumpBy(seconds as Integer)
    cancelSeek()
    seekTo(ClampSeek(positionSecs() + seconds, durationSecs()))
    showControls("bar")
end sub

' Jumps to `target` seconds into the file. Through the helper, Roku jumps anywhere in a
' whole film's playlist (the helper makes the pieces it asks for) and within what a
' growing one has converted; anything else starts the helper's stream again there.
sub seekTo(target as Float)
    m.lastSaved = Int(target)
    if m.route <> "helper" then
        m.video.seek = target
        return
    end if
    if m.helperVod or HelperSeekInside(target, m.offset, m.video.duration) then
        m.pendingSeek = target
        m.video.seek = target - m.offset
        return
    end if
    m.video.control = "stop"
    requestStart(Int(target))
end sub

' --- Preview pictures ----------------------------------------------------------------
'
' While choosing where to jump in a whole film from the helper, a picture of that moment
' sits above the time. The helper writes one for each six-second piece it converts
' (HelperPreviewUrl); where it hasn't converted yet there's none, just the time, and
' nothing more is asked of the provider. One picture loads at a time, into a Poster of
' its own (a fresh Poster's loadStatus can only be about its own picture), and the last
' one stays up until the next is ready. A missing one is asked for again after 10 s.

sub renderThumb(seconds as Float, knobX as Float)
    path = ""
    if m.seeking and m.helperVod then path = HelperPreviewUrl(m.helperPreviews, seconds)
    if path = "" then
        if m.thumb.visible then clearThumb()
        return
    end if
    url = TranscoderConfig().url + path
    x = knobX - 132
    if x < 48 then x = 48
    if x > 1232 - 264 then x = 1232 - 264
    m.thumb.translation = [x, 368]
    ' Kept visible (if see-through) while the first picture loads.
    m.thumb.visible = true
    if m.thumbLoader <> invalid and UpTime(0) - m.thumbLoadAt > 4 then dropThumbLoad()
    if url <> m.thumbShown and m.thumbLoader = invalid and not isThumbMissing(url) then loadThumb(url)
    if m.thumbShown <> "" and not isThumbMissing(url) then
        m.thumb.opacity = 1
    else
        m.thumb.opacity = 0
    end if
end sub

sub loadThumb(url as String)
    pic = m.thumbPics.CreateChild("Poster")
    pic.width = 256
    pic.height = 144
    pic.loadWidth = 256
    pic.loadHeight = 144
    pic.loadDisplayMode = "scaleToFit"
    pic.opacity = 0
    m.thumbLoader = pic
    m.thumbLoading = url
    m.thumbLoadAt = UpTime(0)
    pic.ObserveField("loadStatus", "onThumbStatus")
    pic.uri = url
    ' A picture Roku still holds may be ready already.
    thumbStatus()
end sub

sub onThumbStatus()
    thumbStatus()
end sub

' The loading picture is ready (it replaces the one showing) or isn't there (not made
' yet), then on to wherever the target is now.
sub thumbStatus()
    pic = m.thumbLoader
    if pic = invalid then return
    status = pic.loadStatus
    if status <> "ready" and status <> "failed" then return
    pic.UnobserveField("loadStatus")
    m.thumbLoader = invalid
    url = m.thumbLoading
    m.thumbLoading = ""
    if status = "ready" then
        if m.thumbFront <> invalid then m.thumbPics.RemoveChild(m.thumbFront)
        pic.opacity = 1
        m.thumbFront = pic
        m.thumbShown = url
        m.thumbMissing.Delete(url)
    else
        m.thumbPics.RemoveChild(pic)
        m.thumbMissing[url] = UpTime(0)
    end if
    if m.seeking then renderBar()
end sub

' A picture that took too long counts as missing for now.
sub dropThumbLoad()
    pic = m.thumbLoader
    if pic = invalid then return
    pic.UnobserveField("loadStatus")
    m.thumbPics.RemoveChild(pic)
    m.thumbMissing[m.thumbLoading] = UpTime(0)
    m.thumbLoader = invalid
    m.thumbLoading = ""
end sub

function isThumbMissing(url as String) as Boolean
    if not m.thumbMissing.DoesExist(url) then return false
    return UpTime(0) - m.thumbMissing[url] < 10
end function

' Hides the picture and lets go of it, and of one on its way.
sub clearThumb()
    if m.thumbLoader <> invalid then m.thumbLoader.UnobserveField("loadStatus")
    m.thumbLoader = invalid
    m.thumbLoading = ""
    m.thumbFront = invalid
    m.thumbShown = ""
    m.thumbPics.RemoveChildrenIndex(m.thumbPics.GetChildCount(), 0)
    m.thumb.visible = false
    m.thumb.opacity = 0
end sub

' A new stream: what was missing from the last one says nothing about this one.
sub forgetThumbs()
    clearThumb()
    m.thumbMissing = {}
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
        else if m.controlsOn then
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

    if not m.controlsOn then
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
    m.global.playing = false
    m.autoSubTimer.control = "stop"
    if m.osTask <> invalid then m.osTask.UnobserveField("result")
    if m.probeTask <> invalid then m.probeTask.UnobserveField("result")
    if m.helperTask <> invalid then m.helperTask.UnobserveField("result")
    m.pauseTimer.control = "stop"
    cancelSeek()
    m.countdown.control = "stop"
    m.hideTimer.control = "stop"
    m.video.control = "stop"
    m.toastTimer.control = "stop"
    action = { name: "close" }
    ' The scene tells the helper to stop, so the provider's connection is free again.
    if m.helperUsed and HelperOn() then action.helperStop = HelperStopUrl(TranscoderConfig(), m.helperSession)
    m.top.action = action
end sub

' --- Online subtitles (OpenSubtitles) -------------------------------------------
'
' The Subtitles column ends with online choices. Picking one downloads it and reloads
' the stream at the same spot, since Roku only reads subtitle files when a stream
' starts. Choosing one also sets the "online" preference, so later videos without
' built-in English subtitles fetch the best match by themselves.

sub resetOnline()
    m.online = { state: "idle", candidates: [], message: "", link: "", fileId: "", shift: 0.0, auto: false, remaining: -1 }
    m.extraSubtitle = ""
    m.pendingSubtitle = ""
    m.autoChecked = false
    m.autoWaiting = false
    m.saved = invalid
    m.savedLooking = false
    if m.savedTask <> invalid then m.savedTask.UnobserveField("result")
    m.savedTask = invalid
    if m.autoSubTimer <> invalid then m.autoSubTimer.control = "stop"
    if m.osTask <> invalid then m.osTask.UnobserveField("result")
    m.osTask = invalid
end sub

function currentStreamUrl() as String
    item = currentItem()
    return StreamUrl(m.global.creds, streamKind(), item.id, item.ext)
end function

sub runOsTask(request as Object, callback as String)
    if m.osTask <> invalid then m.osTask.UnobserveField("result")
    request.videoUrl = currentStreamUrl()
    request.userAgent = FieldStr(m.global.creds, "userAgent")
    ' Through the helper, it holds the provider's one connection and has fingerprinted
    ' the file already, so the search doesn't read the file itself.
    if m.route = "helper" then
        request.via = "helper"
        request.hash = m.helperHash
    end if
    m.osTask = CreateObject("roSGNode", "SubtitleTask")
    m.osTask.request = request
    m.osTask.ObserveField("result", callback)
    m.osTask.control = "RUN"
end sub

' Results for a video that's no longer playing are dropped.
function osResultFor(event as Object) as Dynamic
    result = event.GetData()
    m.osTask = invalid
    if IsAA(result.account) then SaveOsAccount(result.account)
    if FieldStr(result.request, "videoUrl") <> currentStreamUrl() then return invalid
    return result
end function

' Where this device would show subtitles by itself ("online", or nothing chosen yet):
' built-in English ones (for "online"), else the ones saved for this title on the sync
' service, else (for "online") the best match from OpenSubtitles.
sub autoSubtitles()
    if m.closing or m.failed or m.online.link <> "" then return
    pref = FieldStr(LoadPrefs(), "subtitles")
    if pref <> "online" and pref <> "" then return
    if pref = "online" then
        ' Built-in English subtitles beat a download.
        options = SubtitleOptions(m.video.availableSubtitleTracks)
        index = OptionIndex(options, "language", "eng")
        if index < 0 then index = OptionIndex(options, "language", "en")
        if index > 0 then
            m.video.subtitleTrack = options[index].id
            m.video.globalCaptionMode = "On"
            return
        end if
    end if
    if m.savedLooking then
        ' Decided once the sync service answers.
        m.autoWaiting = true
        return
    end if
    if m.saved <> invalid then
        showSaved(m.saved.delayMs)
        return
    end if
    if pref = "online" and LoadOsAccount() <> invalid then startOnlineSearch(true)
end sub

sub startOnlineSearch(auto as Boolean)
    account = LoadOsAccount()
    if account = invalid then return
    item = currentItem()
    request = { mode: "find", account: account }
    if m.kind = "movie" then
        request.kind = "movie"
        request.tmdbId = FieldStr(m.playback, "tmdbId")
        request.title = item.title
    else
        request.kind = "episode"
        request.parentTmdbId = FieldStr(m.playback, "seriesTmdbId")
        request.title = m.playback.seriesName
        request.season = item.season
        request.episode = item.episode
    end if
    m.online.state = "searching"
    m.online.auto = auto
    runOsTask(request, "onOnlineFound")
    refreshTracksPanel()
end sub

sub onOnlineFound(event as Object)
    result = osResultFor(event)
    if result = invalid then return
    if not result.ok then
        m.online.state = "error"
        m.online.message = result.error
    else if result.candidates.Count() = 0 then
        m.online.state = "none"
    else
        m.online.state = "results"
        m.online.candidates = result.candidates
        if m.online.auto then startOnlineDownload(result.candidates[0].fileId, 0.0)
    end if
    refreshTracksPanel()
end sub

sub startOnlineDownload(fileId as String, shift as Float)
    account = LoadOsAccount()
    if account = invalid or fileId = "" then return
    m.online.state = "downloading"
    runOsTask({ mode: "download", account: account, fileId: fileId, shift: shift }, "onOnlineDownloaded")
    refreshTracksPanel()
end sub

sub onOnlineDownloaded(event as Object)
    result = osResultFor(event)
    if result = invalid then return
    if not result.ok then
        m.online.state = "error"
        m.online.message = result.error
        refreshTracksPanel()
        return
    end if
    m.online.state = "results"
    m.online.link = result.link
    m.online.fileId = FieldStr(result.request, "fileId")
    m.online.shift = result.request.shift
    m.online.remaining = ToInt(result.remaining)
    SavePref("subtitles", "online")
    reloadWithSubtitle(result.link)
    ' A fresh download (not one moved by OpenSubtitles) is saved for every device.
    if m.online.shift = 0 then shareSubtitle(m.online.fileId, result.link)
    refreshTracksPanel()
end sub

' Roku reads subtitle files when a stream loads, so reload at the same spot.
sub reloadWithSubtitle(link as String)
    m.extraSubtitle = link
    m.pendingSubtitle = link
    if m.started then m.startAt = Int(positionSecs())
    m.video.control = "stop"
    if m.route = "helper" then
        requestStart(m.startAt)
    else
        loadStream()
    end if
end sub

' --- Subtitles saved for every device (the sync service, sync/worker.js) -----------
'
' A download is saved there for this title, so the next device to play it shows it
' without one. The Roku plays any device's saved subtitles from the service's address,
' which also moves them for a nudge, so nudging them costs no download.

function syncRequestFor(mode as String) as Dynamic
    config = SyncConfig()
    if config = invalid or FieldStr(m.global.creds, "server") = "" then return invalid
    return { mode: mode, url: config.url, key: config.key, space: SyncSpace(m.global.creds), title: itemKey() }
end function

sub lookUpSaved()
    request = syncRequestFor("subtitle-get")
    if request = invalid then return
    m.savedLooking = true
    m.savedTask = CreateObject("roSGNode", "SyncTask")
    m.savedTask.request = request
    m.savedTask.ObserveField("result", "onSavedLooked")
    m.savedTask.control = "RUN"
end sub

sub onSavedLooked(event as Object)
    result = event.GetData()
    m.savedTask = invalid
    m.savedLooking = false
    if IsAA(result) and FieldStr(result, "title") = itemKey() and ToStr(result.found) = "true" then
        m.saved = { fileId: FieldStr(result, "fileId"), name: FieldStr(result, "name"), delayMs: ToInt(result.delayMs), file: FieldStr(result, "file") }
        m.online.candidates.Unshift(SavedCandidate(m.saved))
        refreshTracksPanel()
    end if
    ' No answer still lets the device search as before.
    if m.autoWaiting then
        m.autoWaiting = false
        autoSubtitles()
    end if
end sub

' The saved subtitles, moved `delayMs` by the service.
sub showSaved(delayMs as Integer)
    if m.saved = invalid then return
    m.saved.delayMs = delayMs
    ' A search or download still out is overtaken.
    if m.osTask <> invalid then m.osTask.UnobserveField("result")
    m.osTask = invalid
    if m.online.state = "searching" or m.online.state = "downloading" then
        m.online.state = "idle"
        if SplitSavedCandidates(m.online.candidates).found.Count() > 0 then m.online.state = "results"
    end if
    link = SavedSubtitleUrl(m.saved.file, delayMs)
    m.online.link = link
    m.online.fileId = m.saved.fileId
    m.online.shift = delayMs / 1000
    reloadWithSubtitle(link)
    refreshTracksPanel()
end sub

function savedShowing() as Boolean
    return m.saved <> invalid and m.online.link <> "" and m.online.fileId = m.saved.fileId
end function

sub shareSubtitle(fileId as String, link as String)
    request = syncRequestFor("subtitle-save")
    if request = invalid then return
    request.fileId = fileId
    request.link = link
    request.name = ""
    for each candidate in m.online.candidates
        if candidate.fileId = fileId and ToStr(candidate.saved) <> "true" then request.name = candidate.release
    end for
    if m.shareTask <> invalid then m.shareTask.UnobserveField("result")
    m.shareTask = CreateObject("roSGNode", "SyncTask")
    m.shareTask.request = request
    m.shareTask.ObserveField("result", "onSubtitleShared")
    m.shareTask.control = "RUN"
end sub

sub onSubtitleShared(event as Object)
    result = event.GetData()
    m.shareTask = invalid
    if not IsAA(result) or ToStr(result.ok) <> "true" or FieldStr(result, "title") <> itemKey() or FieldStr(result, "file") = "" then return
    m.saved = { fileId: FieldStr(result, "fileId"), name: FieldStr(result, "name"), delayMs: 0, file: FieldStr(result, "file") }
    ' What was saved before is replaced.
    m.online.candidates = SplitSavedCandidates(m.online.candidates).found
    refreshTracksPanel()
end sub

' A nudge of the saved subtitles: shown through the service, and saved for every device.
sub nudgeSaved(moveMs as Integer)
    showSaved(m.saved.delayMs + moveMs)
    request = syncRequestFor("subtitle-delay")
    if request = invalid then return
    request.fileId = m.saved.fileId
    request.delayMs = m.saved.delayMs
    if m.delayTask <> invalid then m.delayTask.UnobserveField("result")
    m.delayTask = CreateObject("roSGNode", "SyncTask")
    m.delayTask.request = request
    m.delayTask.control = "RUN"
end sub

' The name Roku knows the online subtitles by: OpenSubtitles' file. A growing helper
' playlist that starts partway has its own clock, which the file's times don't follow,
' so it gets none ("").
function onlineTrackName() as String
    if m.extraSubtitle = "" then return ""
    if m.route = "helper" and m.offset > 0 then return ""
    return m.extraSubtitle
end function

function onlineSubtitleShowing() as Boolean
    if m.extraSubtitle = "" or ToStr(m.video.globalCaptionMode) <> "On" then return false
    return ToStr(m.video.subtitleTrack) = onlineTrackName()
end function

' Online subtitles go with every stream load, since Roku reads them only then.
' `showing` turns them on again once the new stream plays.
sub attachOnlineSubtitle(content as Object, showing as Boolean)
    name = onlineTrackName()
    if name = "" then return
    content.subtitleTracks = [{ Language: "eng", TrackName: name, Description: "Online" }]
    if showing or m.pendingSubtitle <> "" then m.pendingSubtitle = name
end sub

sub chooseOnline(id as String)
    if id = "os:search" then
        startOnlineSearch(false)
    else if id = "os:earlier" and savedShowing() then
        nudgeSaved(-1000)
    else if id = "os:later" and savedShowing() then
        nudgeSaved(1000)
    else if id = "os:earlier" then
        startOnlineDownload(m.online.fileId, m.online.shift - 1.0)
    else if id = "os:later" then
        startOnlineDownload(m.online.fileId, m.online.shift + 1.0)
    else if Left(id, 8) = "os:file:" then
        fileId = Mid(id, 9)
        if fileId = m.online.fileId and m.online.link <> "" then
            m.video.subtitleTrack = onlineTrackName()
            m.video.globalCaptionMode = "On"
            SavePref("subtitles", "online")
        else if m.saved <> invalid and fileId = m.saved.fileId then
            showSaved(m.saved.delayMs)
            SavePref("subtitles", "online")
        else
            startOnlineDownload(fileId, 0.0)
        end if
    end if
    refreshTracksPanel()
end sub

' Built-in tracks (minus the loaded online one, which shows as its search result),
' then subtitles saved for this title on the sync service (no OpenSubtitles account
' needed), then the online choices for the current state.
sub buildSubtitleOptions()
    options = []
    for each option in SubtitleOptions(m.video.availableSubtitleTracks)
        if m.online.link = "" or option.id <> onlineTrackName() then options.Push(option)
    end for
    split = SplitSavedCandidates(m.online.candidates)
    for each candidate in split.saved
        options.Push({ id: "os:file:" + candidate.fileId, label: SubtitleLabel(candidate), language: "eng" })
    end for
    state = m.online.state
    if LoadOsAccount() = invalid then
        options.Push({ id: "os:setup", label: "Find English subtitles online", language: "" })
    else if state = "searching" then
        options.Push({ id: "os:busy", label: "Searching online…", language: "" })
    else if state = "downloading" then
        options.Push({ id: "os:busy", label: "Downloading subtitles…", language: "" })
    else if split.found.Count() = 0 then
        label = "Find English subtitles online"
        if state = "none" or state = "error" then label = "Search online again"
        options.Push({ id: "os:search", label: label, language: "" })
    end if
    if LoadOsAccount() <> invalid then
        for each candidate in split.found
            options.Push({ id: "os:file:" + candidate.fileId, label: SubtitleLabel(candidate), language: "eng" })
        end for
    end if
    if m.online.link <> "" then
        options.Push({ id: "os:earlier", label: "Show subtitles 1s earlier", language: "" })
        options.Push({ id: "os:later", label: "Show subtitles 1s later", language: "" })
    end if
    m.subOptions = options
end sub

sub updateTracksNote()
    notes = []
    playing = LCase(ToStr(m.video.audioFormat))
    if playing <> "" then notes.Push("Audio now: " + CodecLabel(playing) + ".")
    state = m.online.state
    if LoadOsAccount() = invalid and m.online.link = "" then
        notes.Push("To search online, connect OpenSubtitles: on the home screen press * and choose Online subtitles.")
    else if state = "searching" then
        notes.Push("Searching OpenSubtitles for English subtitles…")
    else if state = "downloading" then
        notes.Push("Downloading, then the video picks up where it was.")
    else if state = "none" then
        notes.Push("OpenSubtitles has no English subtitles for this title.")
    else if state = "error" then
        notes.Push(m.online.message)
    else if m.online.link <> "" then
        shiftText = ""
        if m.online.shift <> 0 then shiftText = " Timing moved " + Str(m.online.shift).Trim() + "s."
        if savedShowing() then
            notes.Push("Online subtitles on, saved for all your devices." + shiftText + " If they're out of sync, nudge them earlier or later.")
        else
            notes.Push("Online subtitles on." + shiftText + " If they're out of sync, nudge them earlier or later (each nudge uses a download).")
        end if
    else if SplitSavedCandidates(m.online.candidates).found.Count() > 0 then
        notes.Push("“Matches this file” means timed for your exact video.")
    else if m.online.candidates.Count() > 0 then
        notes.Push("“Saved for this title” came from an earlier download, on this or another device.")
    else if m.subOptions.Count() <= 2 then
        notes.Push("This file has no built-in subtitles.")
    end if
    if m.online.remaining >= 0 then notes.Push("Downloads left today: " + m.online.remaining.ToStr() + ".")
    m.tracksNote.text = notes.Join(" ")
end sub

sub refreshTracksPanel()
    if m.panel <> "tracks" then return
    buildSubtitleOptions()
    if m.subCursor > m.subOptions.Count() - 1 then m.subCursor = m.subOptions.Count() - 1
    updateTracksNote()
    renderTracks()
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

' Some files' audio is in a format this Roku can't play through the TV (DTS is the usual
' one), which plays the picture in silence. Switch to a track it can play, or say why.
sub checkAudioPlayable()
    options = AudioOptions(m.video.availableAudioTracks)
    current = OptionIndex(options, "id", ToStr(m.video.audioTrack))
    format = ""
    if current >= 0 then format = options[current].format
    if format = "" then format = LCase(ToStr(m.video.audioFormat))
    if format = "" or canDecode("audio", format, "") then return
    for each option in options
        if option.format <> "" and canDecode("audio", option.format, "") then
            m.video.audioTrack = option.id
            showToast("Switched to " + option.label + ", because this " + DeviceWord() + " can't play " + CodecLabel(format) + " audio.")
            return
        end if
    end for
    ' No sound this Roku can play: the helper converts it, now and next time.
    if m.route = "direct" and HelperRoute(m.check, { silent: true }, HelperOn(), m.helperTried) then
        RememberHelperTitle(itemKey())
        showToast("This file's sound is " + CodecLabel(format) + ", which this " + DeviceWord() + " can't play, so the helper on your computer converts it.")
        startHelper(Int(positionSecs()))
        return
    end if
    showToast("No sound? This file's audio is " + CodecLabel(format) + ", which this " + DeviceWord() + " can't play. Your provider may have another version of this title.")
end sub

sub showToast(text as String)
    m.toastText.text = text
    m.toast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub hideToast()
    m.toast.visible = false
end sub

sub openTracks()
    cancelSeek()
    ' Through the helper, the file's own tracks: its stream carries one of them.
    if m.route = "helper" and m.helperInfo <> invalid and m.helperStarted <> invalid then
        m.audioOptions = HelperAudioOptions(m.helperInfo.audio)
    else
        m.audioOptions = AudioOptions(m.video.availableAudioTracks)
    end if
    buildSubtitleOptions()
    m.audioCursor = activeAudioIndex()
    if m.audioCursor < 0 then m.audioCursor = 0
    m.subCursor = activeSubtitleIndex()
    if m.subCursor < 0 then m.subCursor = 0
    m.trackColumn = 1
    updateTracksNote()
    hideControls()
    m.panel = "tracks"
    m.tracks.visible = true
    renderTracks()
end sub

function activeAudioIndex() as Integer
    if m.route = "helper" and m.helperStarted <> invalid then return OptionIndex(m.audioOptions, "id", "helper:" + m.helperStarted.audioTrack.ToStr())
    return OptionIndex(m.audioOptions, "id", ToStr(m.video.audioTrack))
end function

function activeSubtitleIndex() as Integer
    if ToStr(m.video.globalCaptionMode) <> "On" then return 0
    current = ToStr(m.video.subtitleTrack)
    if m.online.link <> "" and current = onlineTrackName() then return OptionIndex(m.subOptions, "id", "os:file:" + m.online.fileId)
    return OptionIndex(m.subOptions, "id", current)
end function

sub renderTracks()
    renderOptions(m.audioList, m.audioOptions, activeAudioIndex(), m.audioCursor, m.trackColumn = 0, 440, 8)
    renderOptions(m.subsList, m.subOptions, activeSubtitleIndex(), m.subCursor, m.trackColumn = 1, 440, 8)
end sub

sub chooseTrack()
    if m.trackColumn = 0 then
        if m.audioOptions.Count() = 0 then return
        option = m.audioOptions[m.audioCursor]
        if option.language <> "" then SavePref("audio", option.language)
        if Left(option.id, 7) = "helper:" then
            chooseHelperTrack(Mid(option.id, 8).ToInt())
            return
        end if
        m.video.audioTrack = option.id
    else
        option = m.subOptions[m.subCursor]
        if Left(option.id, 3) = "os:" then
            chooseOnline(option.id)
            return
        end if
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
