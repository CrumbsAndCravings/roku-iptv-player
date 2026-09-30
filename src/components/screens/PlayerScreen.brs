sub init()
    m.video = m.top.FindNode("video")
    m.upNext = m.top.FindNode("upNext")
    m.upNextTitle = m.top.FindNode("upNextTitle")
    m.upNextHint = m.top.FindNode("upNextHint")
    m.errorBox = m.top.FindNode("errorBox")
    m.errorDetail = m.top.FindNode("errorDetail")
    m.countdown = m.top.FindNode("countdown")

    m.top.FindNode("upNextEyebrow").font = MakeFont("Outfit-SemiBold", 14)
    m.upNextTitle.font = MakeFont("Outfit-SemiBold", 22)
    m.upNextHint.font = MakeFont("Outfit-Regular", 17)
    m.top.FindNode("errorTitle").font = MakeFont("Outfit-Bold", 28)
    m.errorDetail.font = MakeFont("Outfit-Regular", 18)
    m.top.FindNode("errorHint").font = MakeFont("Outfit-SemiBold", 18)

    for each barName in ["trickPlayBar", "bufferingBar", "retrievingBar"]
        bar = m.video.GetField(barName)
        if bar <> invalid then bar.filledBarBlendColor = "0xF5B83DFF"
    end for
    m.video.notificationInterval = 1
    m.video.ObserveField("state", "onState")
    m.video.ObserveField("position", "onPosition")
    m.countdown.ObserveField("fire", "onCountdown")

    m.playback = invalid
    m.index = 0
    m.startAt = 0
    m.lastSaved = 0
    m.closing = false
    m.secondsLeft = 0
    m.attempt = 0
    m.started = false
    m.failed = false
    m.errors = []
end sub

sub onPlayback()
    m.playback = m.top.playback
    m.kind = m.playback.kind
    m.index = ToInt(m.playback.index)
    startItem(ToInt(m.playback.startAt))
end sub

sub onTakeFocus()
    if m.upNext.visible or m.errorBox.visible then
        m.top.SetFocus(true)
    else
        m.video.SetFocus(true)
    end if
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

sub startItem(startAt as Integer)
    m.startAt = startAt
    m.attempt = 0
    m.started = false
    m.failed = false
    m.errors = []
    m.upNext.visible = false
    m.errorBox.visible = false
    loadStream()
end sub

' Attempt 0 tells Roku the format from the file extension. Attempt 1 leaves it out and
' lets Roku work it out from the stream itself, in case the extension is wrong.
sub loadStream()
    item = currentItem()
    content = CreateObject("roSGNode", "ContentNode")
    content.url = StreamUrl(m.global.creds, streamKind(), item.id, item.ext)
    if m.kind = "movie" then
        content.title = item.title
    else
        content.title = item.code + "   " + item.title
        content.secondaryTitle = m.playback.seriesName
    end if
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
    m.video.SetFocus(true)
end sub

' --- Progress ----------------------------------------------------------------

sub onPosition()
    if m.closing or not m.started then return
    position = Int(m.video.position)
    if Abs(position - m.lastSaved) >= 15 then saveProgress()
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
    else if m.index + 1 < p.queue.Count() then
        ProgressPut(entryFor(m.index + 1, 0, 0))
    else
        ProgressRemove("s:" + p.seriesId)
    end if
end sub

' --- Playback state ------------------------------------------------------------

sub onState()
    if m.closing then return
    state = m.video.state
    if state = "playing" then
        m.started = true
    else if state = "error" then
        onPlaybackError()
    else if state = "finished" then
        ' Roku can report "finished" right after an error. Only a stream that actually
        ' played counts as watched.
        if m.failed or not m.started then return
        markFinished()
        if m.kind = "episode" and m.index + 1 < m.playback.queue.Count() then
            showUpNext()
        else
            close()
        end if
    else if state = "paused" then
        saveProgress()
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
    m.errorDetail.text = diagnosis()
    m.errorBox.visible = true
    m.top.SetFocus(true)
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

    codecs = DescribeCodecs(FieldStr(item, "videoCodec"), FieldStr(item, "videoProfile"), FieldStr(item, "audioCodec"))
    fileLine = "File: " + UCase(FieldStr(item, "ext"))
    if codecs <> "" then
        fileLine = fileLine + ", " + codecs
    else
        fileLine = fileLine + ". Your provider didn't list its codecs."
    end if
    lines.Push(fileLine)

    detected = []
    if ToStr(m.video.videoFormat) <> "" then detected.Push("video " + m.video.videoFormat)
    if ToStr(m.video.audioFormat) <> "" then detected.Push("audio " + m.video.audioFormat)
    if detected.Count() > 0 then lines.Push("Roku detected: " + detected.Join(", "))

    support = decoderSupport(item)
    if support <> "" then lines.Push(support)

    creds = m.global.creds
    lines.Push("Stream: " + creds.server + "/" + streamKind() + "/" + creds.username + "/••••/" + item.id + "." + item.ext)
    return lines.Join(Chr(10))
end function

function decoderSupport(item as Object) as String
    device = CreateObject("roDeviceInfo")
    problems = []
    videoCodec = FieldStr(item, "videoCodec")
    if videoCodec <> "" then
        codec = RokuVideoCodec(videoCodec)
        basic = device.CanDecodeVideo({ Codec: codec })
        if IsAA(basic) and ToStr(basic.result) = "false" then
            problems.Push(UCase(videoCodec) + " video")
        else
            profile = LCase(FieldStr(item, "videoProfile"))
            if profile <> "" then
                withProfile = device.CanDecodeVideo({ Codec: codec, Profile: profile })
                if IsAA(withProfile) and ToStr(withProfile.result) = "false" then problems.Push(UCase(videoCodec) + " " + FieldStr(item, "videoProfile") + " video")
            end if
        end if
    end if
    audioCodec = FieldStr(item, "audioCodec")
    if audioCodec <> "" then
        audio = device.CanDecodeAudio({ Codec: LCase(audioCodec) })
        if IsAA(audio) and ToStr(audio.result) = "false" then problems.Push(UCase(audioCodec) + " audio")
    end if
    if problems.Count() > 0 then return "This TV can't decode " + problems.Join(" or ") + ". Other apps on this TV will hit the same wall with this file."
    if videoCodec <> "" or audioCodec <> "" then return "This TV says it supports these codecs, so the stream itself is the likely problem."
    return ""
end function

' --- Up next -------------------------------------------------------------------

sub showUpNext()
    upcoming = m.playback.queue[m.index + 1]
    m.upNextTitle.text = upcoming.code + "  " + upcoming.title
    m.secondsLeft = 8
    updateCountdown()
    m.upNext.visible = true
    m.countdown.control = "start"
    m.top.SetFocus(true)
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
    startItem(0)
end sub

sub close()
    m.closing = true
    m.countdown.control = "stop"
    m.video.control = "stop"
    m.top.action = { name: "close" }
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.errorBox.visible then
        if key = "OK" then
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
    if key = "back" then
        saveProgress()
        close()
        return true
    end if
    return false
end function
