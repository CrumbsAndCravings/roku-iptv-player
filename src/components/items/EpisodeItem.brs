sub init()
    m.highlight = m.top.FindNode("highlight")
    m.ring = m.top.FindNode("ring")
    m.stillCorners = m.top.FindNode("stillCorners")
    m.still = m.top.FindNode("still")
    m.track = m.top.FindNode("track")
    m.fill = m.top.FindNode("fill")
    m.title = m.top.FindNode("title")
    m.runtime = m.top.FindNode("runtime")
    m.plot = m.top.FindNode("plot")
    m.title.font = MakeFont("Fredoka-Medium", 21)
    m.runtime.font = MakeFont("Nunito-SemiBold", 18)
    m.plot.font = "font:SmallestSystemFont"
end sub

sub onContentChange()
    item = m.top.itemContent
    if item = invalid then return
    m.still.uri = item.HDPosterUrl
    m.title.text = ToStr(item.episodeNo) + ".  " + item.title
    m.runtime.text = ""
    m.runtime.color = "0xA195CCFF"
    m.still.opacity = 1.0
    if item.problem <> "" then
        m.runtime.text = "Won't play"
        m.runtime.color = "0xFFD98AFF"
        m.still.opacity = 0.35
    else if item.durationSecs > 0 then
        m.runtime.text = FormatRuntime(item.durationSecs)
    end if
    m.plot.text = item.description
    showProgress = item.progress > 0
    m.track.visible = showProgress
    m.fill.visible = showProgress
    if showProgress then m.fill.width = 134 * item.progress
end sub

sub onFocusChange()
    amount = 0.0
    if m.top.listHasFocus then amount = m.top.focusPercent
    m.highlight.opacity = amount
    m.ring.opacity = amount
    ' The still's rounded corners are painted in whatever colour sits behind it.
    if amount > 0.5 then
        m.stillCorners.blendColor = "0x2C2350FF"
    else
        m.stillCorners.blendColor = "0x151028FF"
    end if
end sub
