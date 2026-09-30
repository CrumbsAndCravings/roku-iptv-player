sub init()
    m.card = m.top.FindNode("card")
    m.frame = m.top.FindNode("frame")
    m.poster = m.top.FindNode("poster")
    m.fallback = m.top.FindNode("fallback")
    m.track = m.top.FindNode("track")
    m.fill = m.top.FindNode("fill")
    m.caption = m.top.FindNode("caption")
    m.fallback.font = "font:SmallestBoldSystemFont"
    m.caption.font = MakeFont("Outfit-SemiBold", 14)
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
        return
    end if
    m.poster.uri = item.HDPosterUrl
    m.fallback.text = item.title
    m.caption.text = item.caption
    m.caption.color = "0xB4B4C2FF"
    m.poster.opacity = 1.0
    if item.problem <> "" then
        m.poster.opacity = 0.35
        m.caption.text = "Won't play"
        m.caption.color = "0xF5B83DFF"
    end if
    showProgress = item.progress > 0
    m.track.visible = showProgress
    m.fill.visible = showProgress
    if showProgress then m.fill.width = 104 * item.progress
end sub

sub onFocusChange()
    amount = 0.0
    if m.top.rowListHasFocus then amount = m.top.focusPercent * m.top.rowFocusPercent
    scale = 1 + 0.08 * amount
    m.card.scale = [scale, scale]
    m.frame.opacity = amount
end sub
