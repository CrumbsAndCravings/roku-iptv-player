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
    m.errorDetail.font = "font:SmallSystemFont"
    m.top.FindNode("errorHint").font = MakeFont("Outfit-Regular", 18)

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
    m.lastSaved = 0
    m.closing = false
    m.secondsLeft = 0
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

sub startItem(startAt as Integer)
    p = m.playback
    creds = m.global.creds
    content = CreateObject("roSGNode", "ContentNode")
    if m.kind = "movie" then
        content.url = StreamUrl(creds, "movie", p.id, p.ext)
        content.title = p.title
        fmt = StreamFormatFor(p.ext)
    else
        ep = p.queue[m.index]
        content.url = StreamUrl(creds, "series", ep.id, ep.ext)
        content.title = episodeLabel(ep) + "   " + ep.title
        content.secondaryTitle = p.seriesName
        fmt = StreamFormatFor(ep.ext)
    end if
    if fmt <> "" then content.streamFormat = fmt
    ' Back up a few seconds so the scene picks up where it left off.
    if startAt > 10 then content.playStart = startAt - 5

    m.lastSaved = startAt
    m.upNext.visible = false
    m.errorBox.visible = false
    m.video.content = content
    m.video.control = "play"
    m.video.SetFocus(true)
end sub

function episodeLabel(ep as Object) as String
    return "S" + ToStr(ep.season) + ":E" + ToStr(ep.episode)
end function

' --- Progress ----------------------------------------------------------------

sub onPosition()
    if m.closing then return
    position = Int(m.video.position)
    if Abs(position - m.lastSaved) >= 15 then saveProgress()
end sub

sub saveProgress()
    if m.playback = invalid then return
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
    if state = "finished" then
        markFinished()
        if m.kind = "episode" and m.index + 1 < m.playback.queue.Count() then
            showUpNext()
        else
            close()
        end if
    else if state = "paused" then
        saveProgress()
    else if state = "error" then
        detail = m.video.errorMsg
        if detail = "" then detail = "The stream stopped with error " + ToStr(m.video.errorCode) + "."
        m.errorDetail.text = detail + " Some files use formats Roku can't decode; other titles should still work."
        m.errorBox.visible = true
        m.top.SetFocus(true)
    end if
end sub

sub showUpNext()
    upcoming = m.playback.queue[m.index + 1]
    m.upNextTitle.text = episodeLabel(upcoming) + "  " + upcoming.title
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
    if m.upNext.visible then
        if key = "OK" or key = "play" then
            playNext()
        else if key = "back" then
            close()
        end if
        return true
    end if
    if key = "back" then
        if not m.errorBox.visible then saveProgress()
        close()
        return true
    end if
    return false
end function
