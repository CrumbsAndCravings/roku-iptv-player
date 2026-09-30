sub init()
    m.top.backgroundUri = ""
    m.top.backgroundColor = "0x0B0B0FFF"
    m.stack = m.top.FindNode("stack")
    m.screens = []
    m.global.AddFields({ creds: {} })
    m.global.AddField("search", "node", false)
    ' v0.1 kept Continue Watching here; its only entries came from a failed play.
    RegDelete("watch", "items")

    creds = LoadCreds()
    if creds = invalid then
        resetTo("LoginScreen")
    else
        m.global.creds = creds
        resetTo("HomeScreen")
    end if
end sub

function pushScreen(name as String) as Object
    if m.screens.Count() > 0 then
        current = m.screens.Peek()
        current.visible = false
    end if
    screen = m.stack.CreateChild(name)
    screen.ObserveField("action", "onAction")
    m.screens.Push(screen)
    return screen
end function

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
