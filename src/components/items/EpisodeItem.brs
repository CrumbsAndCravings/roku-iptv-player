sub init()
    m.highlight = m.top.FindNode("highlight")
    m.still = m.top.FindNode("still")
    m.track = m.top.FindNode("track")
    m.fill = m.top.FindNode("fill")
    m.title = m.top.FindNode("title")
    m.runtime = m.top.FindNode("runtime")
    m.plot = m.top.FindNode("plot")
    m.title.font = MakeFont("Outfit-SemiBold", 21)
    m.runtime.font = MakeFont("Outfit-Regular", 18)
    m.plot.font = "font:SmallestSystemFont"
end sub

sub onContentChange()
    item = m.top.itemContent
    if item = invalid then return
    m.still.uri = item.HDPosterUrl
    m.title.text = ToStr(item.episodeNo) + ".  " + item.title
    m.runtime.text = ""
    if item.durationSecs > 0 then m.runtime.text = FormatRuntime(item.durationSecs)
    m.plot.text = item.description
    showProgress = item.progress > 0
    m.track.visible = showProgress
    m.fill.visible = showProgress
    if showProgress then m.fill.width = 150 * item.progress
end sub

sub onFocusChange()
    amount = 0.0
    if m.top.listHasFocus then amount = m.top.focusPercent
    m.highlight.opacity = amount
end sub
