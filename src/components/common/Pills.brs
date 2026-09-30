' Rounded "pill" buttons drawn with a white 9-patch that is tinted per state.

function BuildPills(parent as Object, labels as Object, fontSize as Integer) as Object
    parent.RemoveChildrenIndex(parent.GetChildCount(), 0)
    pills = []
    x = 0
    for each text in labels
        pill = parent.CreateChild("Group")
        pill.translation = [x, 0]
        bg = pill.CreateChild("Poster")
        bg.uri = "pkg:/images/pill.9.png"
        label = pill.CreateChild("Label")
        label.font = MakeFont("Outfit-SemiBold", fontSize)
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
        pills.Push(pill)
        x = x + width + 14
    end for
    return pills
end function

' focusIndex is -1 when the row doesn't have focus. selectedIndex (-1 for none) marks
' a choice that stays highlighted, like the current season.
sub StylePills(pills as Object, focusIndex as Integer, selectedIndex as Integer)
    for i = 0 to pills.Count() - 1
        bg = pills[i].GetChild(0)
        label = pills[i].GetChild(1)
        if i = focusIndex then
            bg.blendColor = "0xF5F5F7FF"
            bg.opacity = 1.0
            label.color = "0x0B0B0FFF"
        else if i = selectedIndex then
            bg.blendColor = "0x3A3A48FF"
            bg.opacity = 1.0
            label.color = "0xF5F5F7FF"
        else
            bg.blendColor = "0x2B2B36FF"
            bg.opacity = 0.85
            label.color = "0xC9C9D4FF"
        end if
    end for
end sub
