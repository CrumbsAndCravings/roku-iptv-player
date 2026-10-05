sub init()
    m.card = m.top.FindNode("card")
    m.ring = m.top.FindNode("ring")
    m.base = m.top.FindNode("base")
    m.poster = m.top.FindNode("poster")
    m.fallback = m.top.FindNode("fallback")
    m.track = m.top.FindNode("track")
    m.fill = m.top.FindNode("fill")
    m.caption = m.top.FindNode("caption")
    m.captionBand = m.top.FindNode("captionBand")
    m.pulse = m.top.FindNode("pulse")
    m.imageIn = m.top.FindNode("imageIn")
    m.imageFade = m.top.FindNode("imageFade")
    m.buildIn = m.top.FindNode("buildIn")
    m.fillIn = m.top.FindNode("fillIn")
    m.fillGrow = m.top.FindNode("fillGrow")
    m.posterOpacity = 1.0
    ' Builds in on its first title, and when its row's titles replace the placeholders.
    m.buildNext = true
    m.poster.ObserveField("loadStatus", "onPosterLoaded")
    ' Titles come from the provider and may not be in a Latin script.
    m.fallback.font = "font:SmallestBoldSystemFont"
    m.caption.font = MakeFont("Nunito-ExtraBold", 14)
end sub

sub onContentChange()
    item = m.top.itemContent
    if item = invalid then return
    if item.placeholder then
        m.buildNext = true
        settle()
        m.base.blendColor = "0x241C42FF"
        m.poster.opacity = 1.0
        m.poster.uri = ""
        m.fallback.text = ""
        m.caption.text = ""
        m.captionBand.visible = false
        m.track.visible = false
        m.fill.visible = false
        m.pulse.control = "start"
        return
    end if
    m.pulse.control = "stop"
    m.base.opacity = 1.0
    ' Only the first few build in; later ones are off screen, or arriving as you scroll.
    place = 8
    if m.buildNext then place = placeInRow(item)
    m.buildNext = false
    building = place < 8
    if building then
        buildIn(place)
    else
        settle()
    end if
    if item.kind = "category" or item.kind = "seeAll" then
        showNameCard(item)
        return
    end if
    m.base.blendColor = "0x241C42FF"
    m.fallback.font = "font:SmallestBoldSystemFont"
    m.fallback.color = "0x9083BDFF"
    m.fallback.height = 160
    m.fallback.text = item.title
    m.caption.text = item.caption
    m.caption.color = "0xC3B8E6FF"
    opacity = 1.0
    if item.problem <> "" then
        opacity = 0.35
        m.caption.text = "Won't play"
        m.caption.color = "0xFFD98AFF"
    end if
    showPoster(item.HDPosterUrl, opacity)
    showProgress = item.progress > 0
    m.track.visible = showProgress
    m.fill.visible = showProgress
    m.fillIn.control = "stop"
    if showProgress then
        width = 120 * item.progress
        if building then
            m.fill.width = 0
            m.fillGrow.keyValue = [0.0, width]
            m.fillIn.delay = m.buildIn.delay + 0.25
            m.fillIn.control = "start"
        else
            m.fill.width = width
        end if
    end if
    m.captionBand.visible = m.caption.text <> ""
end sub

' The picture shows once it's loaded, fading in; one already here just shows.
sub showPoster(uri as String, opacity as Float)
    m.posterOpacity = opacity
    m.imageIn.control = "stop"
    if m.poster.uri = uri and m.poster.loadStatus = "ready" then
        m.poster.opacity = opacity
        return
    end if
    m.poster.opacity = 0.0
    m.poster.uri = uri
end sub

sub onPosterLoaded()
    if m.poster.loadStatus <> "ready" then return
    m.imageFade.keyValue = [0.0, m.posterOpacity]
    m.imageIn.control = "start"
end sub

' Where the poster is in its row, counting up to 8.
function placeInRow(item as Object) as Integer
    row = item.GetParent()
    if row = invalid then return 8
    count = row.GetChildCount()
    if count > 8 then count = 8
    for i = 0 to count - 1
        if row.GetChild(i).IsSameNode(item) then return i
    end for
    return 8
end function

' In from the right after the posters before it in its row (45 ms each, as on the web).
sub buildIn(place as Integer)
    m.buildIn.control = "stop"
    m.buildIn.delay = place * 0.045
    m.card.opacity = 0.0
    m.card.translation = [18, 0]
    m.buildIn.control = "start"
end sub

sub settle()
    m.buildIn.control = "stop"
    m.card.opacity = 1.0
    m.card.translation = [0, 0]
end sub

' A category ("Punjabi", "Movies · 312") or the "See all" tile at the end of a row.
sub showNameCard(item as Object)
    m.imageIn.control = "stop"
    m.poster.uri = ""
    m.poster.opacity = 1.0
    m.track.visible = false
    m.fill.visible = false
    m.fallback.font = MakeFont("Fredoka-Medium", 19)
    m.fallback.height = 136
    m.fallback.color = "0xF7F3FFFF"
    m.fallback.text = item.title
    m.caption.text = item.caption
    m.caption.color = "0xC3B8E6FF"
    m.captionBand.visible = false
    if item.kind = "seeAll" then
        m.base.blendColor = "0x30275AFF"
        m.fallback.text = "See all ›"
    else
        m.base.blendColor = "0x43377AFF"
    end if
end sub

sub onFocusChange()
    amount = 0.0
    if m.top.gridHasFocus then
        amount = m.top.focusPercent
    else if m.top.rowListHasFocus then
        amount = m.top.focusPercent * m.top.rowFocusPercent
    end if
    ' A small lift, so a focused poster doesn't run into its close neighbours.
    scale = 1 + 0.06 * amount
    m.card.scale = [scale, scale]
    m.ring.opacity = amount
end sub
