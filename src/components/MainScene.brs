sub init()
    m.top.backgroundUri = ""
    m.top.backgroundColor = "0x151028FF"
    applyDialogPalette()
    m.stack = m.top.FindNode("stack")
    m.screens = []
    m.screenCount = 0
    m.global.AddFields({ creds: {}, playing: false, syncedAt: 0 })
    m.syncTask = invalid
    m.syncAgain = false
    m.syncClock = invalid
    m.global.AddField("search", "node", false)
    ' v0.1 kept Continue Watching here; its only entries came from a failed play.
    RegDelete("watch", "items")

    creds = LoadCreds()
    ' A personal build with a different login inside replaces the saved login (and its
    ' Continue Watching, which belongs to the old provider). Online subtitles stay.
    builtIn = BuiltInCreds()
    if builtIn <> invalid then
        stamp = builtIn.server + " " + builtIn.username
        if ToStr(RegRead("account", "builtIn")) <> stamp then
            RegDelete("account", "creds")
            RegDelete("progress", "items")
            RegDelete("progress", "removed")
            RegWrite("account", "builtIn", stamp)
            creds = invalid
        end if
    end if
    if creds = invalid then
        resetTo("LoginScreen")
        ' A personal build with a login inside signs in by itself at launch.
        if BuiltInCreds() <> invalid then m.screens.Peek().autoSignIn = true
    else
        m.global.creds = creds
        resetTo("HomeScreen")
        requestSync(true)
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
        requestSync(true)
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
    else if name = "openCategories" then
        screen = pushScreen("CategoriesScreen")
        screen.lists = action.lists
        screen.takeFocus = true
    else if name = "openCategory" then
        screen = pushScreen("CategoryScreen")
        screen.category = action.category
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
        ' Leaving a video: share where it stopped, and free the helper's connection.
        if FieldStr(action, "helperStop") <> "" then stopHelper(action.helperStop)
        popScreen()
        requestSync(true)
    else if name = "syncNow" then
        requestSync(true)
    else if name = "syncSoon" then
        requestSync(false)
    end if
end sub

' --- Sync ------------------------------------------------------------------------------
'
' Continue Watching is shared with your other devices through the sync service
' (sync/worker.js) when a personal build has one: at launch and sign-in, after a video
' and after a removal (right away), and when Home comes back (at most once a minute).
' Each round sends this Roku's list and removals and folds in everyone else's.

sub requestSync(force as Boolean)
    config = SyncConfig()
    creds = m.global.creds
    if config = invalid or FieldStr(creds, "server") = "" then return
    if m.syncTask <> invalid then
        if force then m.syncAgain = true
        return
    end if
    if not force and m.syncClock <> invalid and m.syncClock.TotalSeconds() < 60 then return
    if m.syncClock = invalid then m.syncClock = CreateObject("roTimespan")
    m.syncClock.Mark()
    m.syncTask = CreateObject("roSGNode", "SyncTask")
    m.syncTask.request = { url: config.url, key: config.key, space: SyncSpace(creds), entries: ProgressList(), removed: ProgressRemovedList() }
    m.syncTask.ObserveField("result", "onSynced")
    m.syncTask.control = "RUN"
end sub

sub onSynced(event as Object)
    result = event.GetData()
    m.syncTask.UnobserveField("result")
    m.syncTask = invalid
    if IsAA(result) and result.ok = true then
        before = FormatJson(ProgressList())
        merged = MergeProgress(ProgressList(), ProgressRemovedList(), result.state)
        ProgressSave(merged.entries, merged.removed)
        ' Home redraws Continue Watching only when another device changed it.
        if FormatJson(merged.entries) <> before then m.global.syncedAt = NowSeconds()
    end if
    if m.syncAgain then
        m.syncAgain = false
        requestSync(true)
    end if
end sub

' After a video that went through the helper on a computer at home, the helper stops
' converting, so the provider's one connection is free for whatever plays next.
sub stopHelper(url as String)
    m.helperStop = CreateObject("roSGNode", "HelperTask")
    m.helperStop.request = { mode: "stop", url: url }
    m.helperStop.control = "RUN"
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
