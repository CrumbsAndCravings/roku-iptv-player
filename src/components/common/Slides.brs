' The moving banner, after Netflix's: when a title has more than one backdrop (the
' provider's details list several, BackdropList in Utils.brs), they take turns once you
' rest on it, cross-fading every few seconds, each slowly zooming in. Used by Home's
' banner and by Details; the pictures come from the image hosts, not the provider's
' video connection. Needs Motion.brs (Tween).
'
' Two posters: `back`, the screen's own backdrop, which shows the first picture, and
' `front` on top of it. Showing back, the next picture loads into front and fades in;
' showing front, it loads into back (hidden under front) and front fades away. The
' screen's backdrop loaded handler hands back's loads over first (SlidesBackLoaded).

function SlideSeconds() as Integer
    return 7
end function

sub SlidesInit(back as Object, front as Object, timer as Object)
    m.slides = { back: back, front: front, timer: timer, pictures: [], index: 0, onTop: false, opacity: 1.0, loading: "" }
    front.opacity = 0.0
    front.ObserveField("loadStatus", "onSlideFront")
    timer.duration = SlideSeconds()
    timer.repeat = true
    timer.ObserveField("fire", "onSlideTimer")
end sub

function SlidesRunning() as Boolean
    return m.slides.pictures.Count() > 1
end function

' Starts `pictures` (a title's backdrops; the first is the one showing) taking turns at
' `opacity`. Fewer than two, nothing happens.
sub SlidesStart(pictures as Object, opacity as Float)
    SlidesStop()
    if pictures.Count() < 2 then return
    s = m.slides
    s.pictures = pictures
    s.index = 0
    s.opacity = opacity
    s.timer.control = "start"
    ' The first picture zooms in slowly while it shows.
    slowZoom(s.back)
end sub

' Back to the screen's own backdrop alone, for the next title.
sub SlidesStop()
    s = m.slides
    s.timer.control = "stop"
    s.pictures = []
    s.loading = ""
    s.onTop = false
    StopTween(s.front, "opacity")
    StopTween(s.front, "scale")
    s.front.opacity = 0.0
end sub

sub onSlideTimer()
    s = m.slides
    ' Not while the screen is under another one.
    if s.pictures.Count() < 2 or s.loading <> "" or not m.top.visible then return
    s.index = (s.index + 1) MOD s.pictures.Count()
    uri = s.pictures[s.index]
    ' A poster asked for the picture it already holds doesn't load again, so it goes on
    ' straight away (two pictures take turns in the same two posters).
    if s.onTop then
        s.loading = "back"
        if s.back.uri = uri and s.back.loadStatus = "ready" then
            SlidesBackLoaded()
        else
            s.back.uri = uri
        end if
    else
        s.loading = "front"
        StopTween(s.front, "scale")
        s.front.scale = [1.0, 1.0]
        if s.front.uri = uri and s.front.loadStatus = "ready" then
            onSlideFront()
        else
            s.front.uri = uri
        end if
    end if
end sub

sub onSlideFront()
    s = m.slides
    if s.loading <> "front" then return
    status = s.front.loadStatus
    if status = "loading" or status = "none" then return
    s.loading = ""
    if status <> "ready" then return
    s.onTop = true
    Tween(s.front, "opacity", [s.front.opacity, s.opacity], 1.4, "inOutQuad", 0)
    slowZoom(s.front)
end sub

' The screen's backdrop has loaded (or failed): when it was the next picture, front
' fades away to show it. True when the load was the slideshow's, so the screen leaves it.
function SlidesBackLoaded() as Boolean
    s = m.slides
    if s.loading <> "back" then return false
    status = s.back.loadStatus
    if status = "loading" or status = "none" then return true
    s.loading = ""
    if status <> "ready" then return true
    s.onTop = false
    StopTween(s.back, "opacity")
    s.back.opacity = s.opacity
    StopTween(s.back, "scale")
    s.back.scale = [1.0, 1.0]
    slowZoom(s.back)
    Tween(s.front, "opacity", [s.front.opacity, 0.0], 1.4, "inOutQuad", 0)
    return true
end function

' A slow push in, a little longer than the picture shows.
sub slowZoom(poster as Object)
    Tween(poster, "scale", [poster.scale, [1.06, 1.06]], SlideSeconds() + 2, "linear", 0)
end sub

' A title's backdrops for the banner, from its `backdrops` field (one URL a line).
function BackdropPictures(item as Object) as Object
    pictures = []
    if item = invalid or item.backdrop = "" then return pictures
    pictures.Push(item.backdrop)
    for each url in ToStr(item.backdrops).Split(Chr(10))
        if url <> "" and url <> item.backdrop then pictures.Push(url)
    end for
    return pictures
end function
