sub init()
    m.card = m.top.FindNode("card")
    m.ring = m.top.FindNode("ring")
    m.base = m.top.FindNode("base")
    m.poster = m.top.FindNode("poster")
    m.fallback = m.top.FindNode("fallback")
    m.track = m.top.FindNode("track")
    m.fill = m.top.FindNode("fill")
    m.caption = m.top.FindNode("caption")
    m.pulse = m.top.FindNode("pulse")
    ' Titles come from the provider and may not be in a Latin script.
    m.fallback.font = "font:SmallestBoldSystemFont"
    m.caption.font = MakeFont("Nunito-ExtraBold", 14)
end sub

sub onContentChange()
    item = m.top.itemContent
    if item = invalid then return
    if item.placeholder then
        m.poster.opacity = 1.0
        m.poster.uri = ""
        m.fallback.text = ""
        m.caption.text = ""
        m.track.visible = false
        m.fill.visible = false
        m.pulse.control = "start"
        return
    end if
    m.pulse.control = "stop"
    m.base.opacity = 1.0
    m.poster.uri = item.HDPosterUrl
    m.fallback.text = item.title
    m.caption.text = item.caption
    m.caption.color = "0xC3B8E6FF"
    m.poster.opacity = 1.0
    if item.problem <> "" then
        m.poster.opacity = 0.35
        m.caption.text = "Won't play"
        m.caption.color = "0xFFD98AFF"
    end if
    showProgress = item.progress > 0
    m.track.visible = showProgress
    m.fill.visible = showProgress
    if showProgress then m.fill.width = 100 * item.progress
end sub

sub onFocusChange()
    amount = 0.0
    if m.top.rowListHasFocus then amount = m.top.focusPercent * m.top.rowFocusPercent
    scale = 1 + 0.1 * amount
    m.card.scale = [scale, scale]
    m.ring.opacity = amount
end sub
