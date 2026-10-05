' The intro (Intro.xml). Times are seconds from the sting's start, as in
' tools/make_sounds.py's BEAT: the knock at 0.1, the boom at 0.5, the pings at 0.68 and
' 0.82, and the flight into the app (with the whoosh) at 1.55.

sub init()
    m.stage = m.top.FindNode("stage")
    m.glow = m.top.FindNode("glow")
    m.rays = m.top.FindNode("rays")
    m.logo = m.top.FindNode("logo")
    m.letters = m.top.FindNode("letters")
    m.plusMark = m.top.FindNode("plusMark")
    m.plusGlow = m.top.FindNode("plusGlow")
    m.plusCore = m.top.FindNode("plusCore")
    m.plusFlash = m.top.FindNode("plusFlash")
    m.sparks = m.top.FindNode("sparks")
    m.sting = m.top.FindNode("sting")
    m.waitTimer = m.top.FindNode("waitTimer")
    m.leaveTimer = m.top.FindNode("leaveTimer")
    m.doneTimer = m.top.FindNode("doneTimer")
    m.anims = []
    m.started = false
    m.leaving = false

    m.waitTimer.ObserveField("fire", "begin")
    m.leaveTimer.ObserveField("fire", "leave")
    m.doneTimer.ObserveField("fire", "finish")
    if not layOut() then
        finish()
        return
    end if
    ' It starts once the sting is ready to play with it.
    m.sting.ObserveField("loadStatus", "onStingLoaded")
    m.sting.uri = "pkg:/sounds/intro.wav"
    m.waitTimer.control = "start"
end sub

' Places the letters, the plus, its sparks and the rays (images/intro.json).
function layOut() as Boolean
    pieces = ParseJson(ReadAsciiFile("pkg:/images/intro.json"))
    if not IsAA(pieces) or not IsArr(pieces.letters) or not IsAA(pieces.plus) then return false
    m.logo.translation = [(1280 - pieces.width) / 2, (720 - pieces.height) / 2]
    for i = 0 to pieces.letters.Count() - 1
        piece = pieces.letters[i]
        letter = m.letters.CreateChild("Poster")
        letter.id = "letter" + i.ToStr()
        letter.uri = piece.uri
        letter.width = piece.w
        letter.height = piece.h
        letter.translation = [piece.x, piece.y]
        letter.scaleRotateCenter = [piece.w / 2, piece.h / 2]
        letter.opacity = 0.0
    end for

    plus = pieces.plus
    middle = [plus.x + plus.w / 2, plus.y + plus.h / 2]
    m.plusMark.translation = middle
    m.sparks.translation = middle
    ' The flight is through the plus's middle.
    m.logo.scaleRotateCenter = middle
    centre(m.plusGlow, plus.w)
    core = plus.size + plus.flashPad * 2
    centre(m.plusCore, core)
    centre(m.plusFlash, core)

    for i = 0 to 5
        arm = m.sparks.CreateChild("Group")
        arm.rotation = (60 * i + 15) * 3.14159265 / 180
        spark = arm.CreateChild("Poster")
        spark.id = "spark" + i.ToStr()
        spark.uri = "pkg:/images/intro_spark.png"
        spark.width = 28
        spark.height = 28
        spark.translation = [-14, -14]
        spark.scaleRotateCenter = [14, 14]
        spark.opacity = 0.0
    end for

    colors = ["0xB9A3FFFF", "0xFF9ECFFF", "0xFFD98AFF", "0xFFFFFFFF"]
    for i = 0 to 15
        arm = m.rays.CreateChild("Group")
        arm.rotation = (22.5 * i + (i mod 2) * 7) * 3.14159265 / 180
        ray = arm.CreateChild("Poster")
        ray.id = "ray" + i.ToStr()
        ray.uri = "pkg:/images/intro_ray.png"
        ray.width = 81
        ray.height = 6
        ray.translation = [102, -3]
        ray.blendColor = colors[i mod 4]
        ray.opacity = 0.0
    end for
    return true
end function

' A square picture `size` wide, centred on its group's origin.
sub centre(poster as Object, size as Float)
    poster.width = size
    poster.height = size
    poster.translation = [-size / 2, -size / 2]
end sub

sub onStingLoaded()
    status = m.sting.loadStatus
    if status = "ready" or status = "failed" then begin()
end sub

sub begin()
    if m.started then return
    m.started = true
    m.waitTimer.control = "stop"
    if m.sting.loadStatus = "ready" then m.sting.control = "play"

    ' The knock: the plus pulses.
    a = stagePart(0.1, 0.46, "linear")
    lerp(a, m.plusMark, "scale", [0, 0.12, 0.25, 0.55, 1], scales([1, 1.4, 1.55, 1.15, 1]))
    lerp(a, m.plusFlash, "opacity", [0, 0.25, 1], [0, 0.6, 0])

    ' The boom: a glow blooms...
    a = stagePart(0.48, 1.5, "linear")
    lerp(a, m.glow, "scale", [0, 0.08, 0.22, 0.5, 1], scales([0.3, 0.85, 1.08, 1.02, 1]))
    lerp(a, m.glow, "opacity", [0, 0.08, 0.22, 0.5, 1], [0, 0.75, 1, 0.6, 0.4])
    ' ...ARAN punches in out of it, a letter at a time...
    for i = 0 to m.letters.GetChildCount() - 1
        letter = m.letters.GetChild(i)
        a = stagePart(0.5 + i * 0.032, 0.56, "outExpo")
        lerp(a, letter, "scale", invalid, [[1.5, 1.5], [1, 1]])
        lerp(a, letter, "opacity", invalid, [0.0, 1.0])
    end for
    ' ...and light rays burst out behind it.
    for i = 0 to m.rays.GetChildCount() - 1
        ray = m.rays.GetChild(i).GetChild(0)
        a = stagePart(0.5 + (i mod 3) * 0.04, 1.1, "outCubic")
        lerp(a, ray, "translation", invalid, [[102, -3], [384, -3]])
        lerp(a, ray, "width", invalid, [81.0, 538.0])
        lerp(a, ray, "opacity", [0, 0.25, 1], [0, 0.9, 0])
    end for

    ' The pings: the plus spins (half a turn; a plus looks the same after a quarter),
    ' swelling and flashing with each, and sparks fly from it.
    a = stagePart(0.68, 0.5, "outCubic")
    lerp(a, m.plusMark, "rotation", invalid, [0.0, 3.14159265])
    a = stagePart(0.68, 0.44, "linear")
    lerp(a, m.plusMark, "scale", [0, 0.15, 0.32, 0.47, 0.64, 1], scales([1, 1.25, 1.06, 1.2, 1.05, 1]))
    lerp(a, m.plusFlash, "opacity", [0, 0.15, 0.32, 0.47, 0.64, 1], [0, 0.7, 0.1, 0.6, 0.1, 0])
    for i = 0 to m.sparks.GetChildCount() - 1
        spark = m.sparks.GetChild(i).GetChild(0)
        a = stagePart(0.68 + (i mod 2) * 0.14, 0.62, "outCubic")
        lerp(a, spark, "translation", invalid, [[-14, -14], [-14, -124]])
        lerp(a, spark, "scale", invalid, [[0.4, 0.4], [1, 1]])
        lerp(a, spark, "opacity", [0, 0.2, 1], [0, 1, 0])
    end for

    for each anim in m.anims
        anim.control = "start"
    end for
    m.leaveTimer.control = "start"
end sub

' Through the plus and into the app: it grows until its middle fills the screen, then
' the app shows through. The sting has its whoosh here.
sub leave()
    if m.leaving then return
    m.leaving = true
    m.started = true
    m.waitTimer.control = "stop"
    m.leaveTimer.control = "stop"
    parts = []
    ' Its glow goes first: a glow made 70 times bigger looks blocky.
    a = stagePart(0, 0.16, "outQuad")
    lerp(a, m.plusCore, "opacity", invalid, [0.0, 1.0])
    lerp(a, m.plusGlow, "opacity", invalid, [1.0, 0.0])
    parts.Push(a)
    a = stagePart(0, 0.7, "inCubic")
    lerp(a, m.logo, "scale", invalid, [[1, 1], [70, 70]])
    parts.Push(a)
    a = stagePart(0.06, 0.26, "inQuad")
    lerp(a, m.letters, "opacity", invalid, [1.0, 0.0])
    parts.Push(a)
    a = stagePart(0.47, 0.38, "outQuad")
    lerp(a, m.stage, "opacity", invalid, [1.0, 0.0])
    parts.Push(a)
    for each anim in parts
        anim.control = "start"
    end for
    m.doneTimer.control = "start"
end sub

sub finish()
    m.doneTimer.control = "stop"
    m.top.done = true
end sub

' Any key skips it (Back too, rather than leaving the app).
function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and not m.leaving then
        ' The sting's whoosh belongs to its own moment.
        m.sting.control = "stop"
        leave()
    end if
    return true
end function

' --- Building blocks ---------------------------------------------------------------------

' One part of the intro: `seconds` long, starting `delay` seconds in.
function stagePart(delay as Float, seconds as Float, ease as String) as Object
    anim = m.top.CreateChild("Animation")
    anim.delay = delay
    anim.duration = seconds
    anim.easeFunction = ease
    m.anims.Push(anim)
    return anim
end function

' Moves node's field `fieldName` through `values` at `keys` (0 to 1; evenly spaced when invalid).
sub lerp(anim as Object, node as Object, fieldName as String, keys as Dynamic, values as Object)
    kind = "FloatFieldInterpolator"
    if IsArr(values[0]) then kind = "Vector2DFieldInterpolator"
    interp = anim.CreateChild(kind)
    if keys = invalid then
        keys = []
        last = values.Count() - 1
        for i = 0 to last
            keys.Push(i / last)
        end for
    end if
    interp.key = keys
    interp.keyValue = values
    interp.fieldToInterp = node.id + "." + fieldName
end sub

function scales(values as Object) as Object
    out = []
    for each s in values
        out.Push([s, s])
    end for
    return out
end function
