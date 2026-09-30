' Pure helpers for the player's seeking, kept here so they can be tested off-device.

' Seconds per step while Left/Right is held: 10 for the first 1.5 seconds, 30 for the
' next 1.5, then doubling every 1.5 seconds, capped at 10 minutes.
function HoldStep(heldMs as Integer) as Integer
    if heldMs < 1500 then return 10
    stepSize = 30
    stages = (heldMs - 1500) \ 1500
    for i = 1 to stages
        stepSize = stepSize * 2
        if stepSize >= 600 then return 600
    end for
    return stepSize
end function

' Keeps a seek target inside the video. Duration 0 means unknown (no upper bound).
function ClampSeek(target as Float, duration as Float) as Float
    if duration > 0 and target > duration - 3 then target = duration - 3
    if target < 0 then target = 0.0
    return target
end function

' 0..1 share of the bar for a position.
function BarFraction(position as Float, duration as Float) as Float
    if duration <= 0 then return 0.0
    fraction = position / duration
    if fraction < 0 then return 0.0
    if fraction > 1 then return 1.0
    return fraction
end function
