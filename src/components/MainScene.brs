sub init()
    m.top.backgroundUri = ""
    m.top.backgroundColor = "0x151028FF"
    applyDialogPalette()
    m.stack = m.top.FindNode("stack")
    m.screens = []
    m.screenCount = 0
    m.global.AddFields({ creds: {} })
    m.global.AddField("search", "node", false)
    ' v0.1 kept Continue Watching here; its only entries came from a failed play.
    RegDelete("watch", "items")

    creds = LoadCreds()
    if creds = invalid then
        resetTo("LoginScreen")
        ' A personal build with a login inside signs in by itself at launch.
        if BuiltInCreds() <> invalid then m.screens.Peek().autoSignIn = true
    else
        m.global.creds = creds
        resetTo("HomeScreen")
    end if
end sub

' Roku's own dialogs and keyboards (sign-in fields, account menu) in the ARAN+ colours.
sub applyDialogPalette()
    if not m.top.HasField("palette") then return
    palette = CreateObject("roSGNode", "RSGPalette")
    palette.colors = {
        DialogBackgroundColor: "0x1E1736FF"
        DialogItemColor: "0xF7F3FFFF"
        DialogTextColor: "0xF7F3FFFF"
        DialogFocusColor: "0xC9B8FFFF"
        DialogFocusItemColor: "0x151028FF"
        DialogSecondaryTextColor: "0xC3B8E6FF"
        DialogSecondaryItemColor: "0xFF9ECFFF"
        DialogInputFieldColor: "0x30275AFF"
        DialogKeyboardColor: "0x241C42FF"
        DialogFootprintColor: "0x43377AFF"
    }
    m.top.palette = palette
end sub

function pushScreen(name as String) as Object
    if m.screens.Count() > 0 then
        current = m.screens.Peek()
        current.visible = false
    end if
    screen = m.stack.CreateChild(name)
    screen.ObserveField("action", "onAction")
    m.screens.Push(screen)
    animateIn(screen)
    return screen
end function

' New screens fade in while floating up a little.
sub animateIn(screen as Object)
    m.screenCount = m.screenCount + 1
    screen.id = "screen" + m.screenCount.ToStr()
    screen.opacity = 0.0
    screen.translation = [0, 18]
    anim = m.top.CreateChild("Animation")
    anim.duration = 0.3
    anim.easeFunction = "outCubic"
    fade = anim.CreateChild("FloatFieldInterpolator")
    fade.key = [0.0, 1.0]
    fade.keyValue = [0.0, 1.0]
    fade.fieldToInterp = screen.id + ".opacity"
    slide = anim.CreateChild("Vector2DFieldInterpolator")
    slide.key = [0.0, 1.0]
    slide.keyValue = [[0, 18], [0, 0]]
    slide.fieldToInterp = screen.id + ".translation"
    anim.ObserveField("state", "onScreenAnimation")
    anim.control = "start"
end sub

' Drops finished transitions and makes sure the screen ends fully shown.
sub onScreenAnimation(event as Object)
    anim = event.GetRoSGNode()
    if anim.state <> "stopped" then return
    for each screen in m.screens
        screen.opacity = 1.0
        screen.translation = [0, 0]
    end for
    anim.UnobserveField("state")
    m.top.RemoveChild(anim)
end sub

sub popScreen()
    if m.screens.Count() <= 1 then return
    top = m.screens.Pop()
    top.UnobserveField("action")
    m.stack.RemoveChild(top)
    previous = m.screens.Peek()
    previous.visible = true
    previous.takeFocus = true
end sub

sub resetTo(name as String)
    for each screen in m.screens
        screen.UnobserveField("action")
    end for
    m.screens = []
    m.screenCount = 0
    m.stack.RemoveChildrenIndex(m.stack.GetChildCount(), 0)
    screen = pushScreen(name)
    screen.takeFocus = true
end sub

sub onAction(event as Object)
    action = event.GetData()
    name = FieldStr(action, "name")
    if name = "signedIn" then
        m.global.creds = action.creds
        resetTo("HomeScreen")
    else if name = "signOut" then
        stopSearch()
        ClearAccount()
        m.global.creds = {}
        resetTo("LoginScreen")
    else if name = "openSubtitleSetup" then
        screen = pushScreen("SubtitleSetupScreen")
        screen.takeFocus = true
    else if name = "openSearch" then
        screen = pushScreen("SearchScreen")
        screen.takeFocus = true
    else if name = "openDetails" then
        screen = pushScreen("DetailsScreen")
        screen.item = action.item
        screen.takeFocus = true
    else if name = "play" then
        screen = pushScreen("PlayerScreen")
        screen.playback = action.playback
        screen.takeFocus = true
    else if name = "close" then
        popScreen()
    end if
end sub

' The search worker holds an index of the signed-in library; drop it on sign-out.
sub stopSearch()
    task = m.global.search
    if task <> invalid then
        task.stop = true
        task.control = "stop"
    end if
    m.global.search = invalid
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "back" and m.screens.Count() > 1 then
        popScreen()
        return true
    end if
    return false
end function
