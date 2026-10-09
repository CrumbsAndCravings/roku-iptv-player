' Rounded "pill" buttons: a white 9-patch tinted per state, under a glass sheen and rim
' (glass_pill.9.png), so the page shows faintly through the ones you're not on. The one
' you're on springs up a little (Motion.brs, which every screen using these includes).

function BuildPills(parent as Object, labels as Object, fontSize as Integer) as Object
    parent.RemoveChildrenIndex(parent.GetChildCount(), 0)
    pills = []
    x = 0
    for each text in labels
        pill = parent.CreateChild("Group")
        pill.translation = [x, 0]
        pill.AddFields({ aim: 1.0 })
        bg = pill.CreateChild("Poster")
        bg.uri = "pkg:/images/pill.9.png"
        label = pill.CreateChild("Label")
        label.font = MakeFont("Fredoka-Medium", fontSize)
        label.text = text
        width = label.localBoundingRect().width + fontSize * 2.4
        estimate = Len(text) * fontSize * 0.55 + fontSize * 2.4
        if width < estimate * 0.6 then width = estimate
        if width < fontSize * 5 then width = fontSize * 5
        height = fontSize * 2.1
        bg.width = width
        bg.height = height
        label.width = width
        label.height = height
        label.horizAlign = "center"
        label.vertAlign = "center"
        sheen = pill.CreateChild("Poster")
        sheen.uri = "pkg:/images/glass_pill.9.png"
        sheen.width = width
        sheen.height = height
        pill.scaleRotateCenter = [width / 2, height / 2]
        pills.Push(pill)
        x = x + width + 14
    end for
    return pills
end function

' focusIndex is -1 when the row doesn't have focus. selectedIndex (-1 for none) marks
' a choice that stays highlighted, like the current season.
sub StylePills(pills as Object, focusIndex as Integer, selectedIndex as Integer)
    for i = 0 to pills.Count() - 1
        pill = pills[i]
        bg = pill.GetChild(0)
        label = pill.GetChild(1)
        sheen = pill.GetChild(2)
        aim = 1.0
        if i = focusIndex then
            bg.blendColor = "0xC9B8FFFF"
            bg.opacity = 1.0
            sheen.opacity = 0.7
            label.color = "0x151028FF"
            aim = 1.06
        else if i = selectedIndex then
            bg.blendColor = "0x43377AFF"
            bg.opacity = 0.9
            sheen.opacity = 1.0
            label.color = "0xF7F3FFFF"
        else
            bg.blendColor = "0x30275AFF"
            bg.opacity = 0.62
            sheen.opacity = 1.0
            label.color = "0xD8CEF5FF"
        end if
        if pill.aim <> aim then
            pill.aim = aim
            SpringScale(pill, aim)
        end if
    end for
end sub
