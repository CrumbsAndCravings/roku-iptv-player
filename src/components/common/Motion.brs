' Motion and sound shared by the screens, after the web app's (its src/styles/shell.css
' and motion.css): springs that overshoot a touch and settle, short animations that run
' once and tidy up after themselves, and the click sounds (held and played by MainScene,
' onSound there; made by tools/make_sounds.py).

' --- Sounds ----------------------------------------------------------------------------

' Plays one of the click sounds: "move", "select" or "back". MainScene leaves them out
' when they're turned off (Account menu).
sub Sound(name as String)
    m.global.sound = name
end sub

' A list's focus moved (its itemFocused or rowItemFocused, `value`): the move sound when
' it's the viewer moving along it, rather than the list being filled or refreshed.
sub MovedSound(list as Object, value as Dynamic)
    if m.movedAt = invalid then m.movedAt = {}
    text = FormatJson(value)
    if m.movedAt[list.id] = text then return
    m.movedAt[list.id] = text
    if list.HasFocus() then Sound("move")
end sub

' --- Curves ----------------------------------------------------------------------------

' The web app's spring: quick, overshooting a touch, settling (620 ms for the tab lens,
' 420 ms for the tab bar's swell). Progress from 0 to 1, evenly spaced in time.
function SpringCurve() as Object
    return [0, 0.012, 0.045, 0.095, 0.157, 0.227, 0.303, 0.382, 0.461, 0.538, 0.612, 0.682, 0.747, 0.805, 0.858, 0.905, 0.945, 0.979, 1.008, 1.031, 1.05, 1.063, 1.073, 1.079, 1.083, 1.083, 1.082, 1.079, 1.075, 1.069, 1.063, 1.057, 1.05, 1.044, 1.037, 1.031, 1.026, 1.02, 1.015, 1.011, 1.007, 1.004, 1.001, 0.999, 0.997, 0.996, 0.995, 0.994, 1]
end function

' Its jelly: a shape springing back, overshooting further and wobbling (760 ms).
function JellyCurve() as Object
    return [0, 0.036, 0.132, 0.271, 0.436, 0.61, 0.78, 0.934, 1.064, 1.167, 1.239, 1.282, 1.297, 1.289, 1.262, 1.222, 1.174, 1.122, 1.072, 1.025, 0.985, 0.954, 0.931, 0.917, 0.912, 0.913, 0.921, 0.932, 0.946, 0.962, 0.977, 0.991, 1.003, 1.013, 1.02, 1.024, 1.026, 1.026, 1.024, 1.021, 1.016, 1.012, 1.007, 1.003, 0.999, 0.997, 0.994, 0.993, 1]
end function

' A pop: down a little, up past where it rests, and back (360 ms, the web app's tab-pop).
function PopCurve() as Object
    return [0.86, 1.0, 1.1, 1.12, 1.08, 1.03, 1.0]
end function

' Values from `a` to `b` along `curve`: numbers, or [x, y] pairs.
function CurveValues(a as Dynamic, b as Dynamic, curve as Object) as Object
    values = []
    for each t in curve
        if IsArr(a) then
            values.Push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
        else
            values.Push(a + (b - a) * t)
        end if
    end for
    return values
end function

' The same scale on both sides, for each value of `curve`.
function ScaleValues(curve as Object) as Object
    values = []
    for each s in curve
        values.Push([s, s])
    end for
    return values
end function

' --- Tweens ----------------------------------------------------------------------------

' Moves `node`'s field `fieldName` ("opacity", "translation", "scale", "width"...) through `values`
' (numbers or [x, y] pairs), evenly spaced over `seconds`, after `delay` seconds. A new
' tween of the same field takes over from one still running, from wherever it got to.
' Each runs once and is then removed.
function Tween(node as Object, fieldName as String, values as Object, seconds as Float, ease as String, delay as Float) as Object
    if m.tweens = invalid then
        m.tweens = {}
        m.tweenCount = 0
    end if
    if node.id = "" then
        m.tweenCount = m.tweenCount + 1
        node.id = "tweened" + m.tweenCount.ToStr()
    end if
    key = node.id + "." + fieldName
    StopTween(node, fieldName)
    anim = m.top.CreateChild("Animation")
    anim.AddFields({ tweenKey: key })
    anim.duration = seconds
    anim.delay = delay
    anim.easeFunction = ease
    kind = "FloatFieldInterpolator"
    if IsArr(values[0]) then kind = "Vector2DFieldInterpolator"
    lerp = anim.CreateChild(kind)
    keys = []
    last = values.Count() - 1
    for i = 0 to last
        keys.Push(i / last)
    end for
    lerp.key = keys
    lerp.keyValue = values
    lerp.fieldToInterp = key
    m.tweens[key] = anim
    anim.ObserveField("state", "onTweenDone")
    anim.control = "start"
    return anim
end function

' Stops a tween of node's field where it is.
sub StopTween(node as Object, fieldName as String)
    if m.tweens = invalid or node.id = "" then return
    key = node.id + "." + fieldName
    anim = m.tweens[key]
    if anim = invalid then return
    m.tweens.Delete(key)
    anim.UnobserveField("state")
    anim.control = "stop"
    m.top.RemoveChild(anim)
end sub

sub onTweenDone(event as Object)
    anim = event.GetRoSGNode()
    if anim.state <> "stopped" then return
    anim.UnobserveField("state")
    current = m.tweens[anim.tweenKey]
    if current <> invalid and current.IsSameNode(anim) then m.tweens.Delete(anim.tweenKey)
    m.top.RemoveChild(anim)
end sub

' Fades `node` to `opacity`.
sub FadeTo(node as Object, opacity as Float, seconds as Float)
    Tween(node, "opacity", [node.opacity, opacity], seconds, "outQuad", 0)
end sub

' Springs `node`'s scale to `scale` (420 ms).
sub SpringScale(node as Object, scale as Float)
    Tween(node, "scale", CurveValues(node.scale, [scale, scale], SpringCurve()), 0.42, "linear", 0)
end sub

' A pop, as when a tab is chosen. node.scaleRotateCenter should be its middle.
sub PopNode(node as Object)
    Tween(node, "scale", ScaleValues(PopCurve()), 0.36, "outQuad", 0)
end sub
