sub init()
    m.top.backgroundUri = ""
    m.top.backgroundColor = "0x151028FF"
    applyDialogPalette()
    m.stack = m.top.FindNode("stack")
    m.screens = []
    m.screenCount = 0
    m.moving = {}
    prefs = LoadPrefs()
    m.global.AddFields({ creds: {}, playing: false, syncedAt: 0, soundsOn: FieldStr(prefs, "sounds") <> "off", introPlaying: false })
    ' alwaysNotify, so the same sound twice plays twice.
    m.global.AddField("sound", "string", true)
    m.global.ObserveField("sound", "onSound")
    m.sounds = { move: m.top.FindNode("moveSound"), select: m.top.FindNode("selectSound"), back: m.top.FindNode("backSound") }
    m.moveClock = CreateObject("roTimespan")
    m.intro = invalid
    m.syncTask = invalid
    m.syncAgain = false
    m.syncClock = invalid
    m.global.AddField("search", "node", false)
    ' v0.1 kept Continue Watching here; its only entries came from a failed play.
    RegDelete("watch", "items")

    ' A personal build with an OpenSubtitles account inside replaces the one saved here
    ' when the build's own changes (a new key); otherwise the saved one stays.
    os = BuiltInOsAccount()
    if os <> invalid then
        osStamp = os.apiKey + " " + os.username
        if ToStr(RegRead("opensubtitles", "builtIn")) <> osStamp then
            SaveOsAccount(os)
            RegWrite("opensubtitles", "builtIn", osStamp)
        end if
    end if

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
    if FieldStr(prefs, "intro") <> "off" then showIntro()
end sub

' --- Intro and sounds ------------------------------------------------------------------

' The intro (Intro.xml) plays over the first screen, which loads underneath meanwhile.
' It takes the keys, so any key skips it.
sub showIntro()
    m.intro = m.top.CreateChild("Intro")
    if m.intro.done then
        onIntroDone()
        return
    end if
    ' Screens leave the focus alone meanwhile (HomeScreen's focusRows).
    m.global.introPlaying = true
    m.intro.ObserveField("done", "onIntroDone")
    m.intro.SetFocus(true)
end sub

sub onIntroDone()
    if m.intro = invalid then return
    m.intro.UnobserveField("done")
    m.top.RemoveChild(m.intro)
    m.intro = invalid
    m.global.introPlaying = false
    if m.screens.Count() > 0 then m.screens.Peek().takeFocus = true
end sub

' A click sound a screen asked for (Sound() in common/Motion.brs).
sub onSound()
    playSound(m.global.sound)
end sub

' Plays "move", "select" or "back", unless they're turned off (Account menu), a video
' is playing or the intro is. Moves closer together than 60 ms (a key held down) tick once.
sub playSound(name as String)
    if not m.global.soundsOn or m.global.playing = true or m.intro <> invalid then return
    node = m.sounds[name]
    if node = invalid then return
    if name = "move" then
        if m.moveClock.TotalMilliseconds() < 60 then return
        m.moveClock.Mark()
    end if
    node.control = "stop"
    node.control = "play"
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
    previous = invalid
    if m.screens.Count() > 0 then previous = m.screens.Peek()
    screen = m.stack.CreateChild(name)
    ' Ids are never reused, so an animation can't land on the wrong screen.
    m.screenCount = m.screenCount + 1
    screen.id = "screen" + m.screenCount.ToStr()
    screen.scaleRotateCenter = [640, 360]
    screen.ObserveField("action", "onAction")
    m.screens.Push(screen)
    moveScreen(screen, entrance(name))
    if previous <> invalid then moveScreen(previous, "sink")
    return screen
end function

sub popScreen()
    if m.screens.Count() <= 1 then return
    top = m.screens.Pop()
    top.UnobserveField("action")
    moveScreen(top, exitFor(top.Subtype()))
    previous = m.screens.Peek()
    previous.visible = true
    moveScreen(previous, "back")
    previous.takeFocus = true
end sub

sub resetTo(name as String)
    for each screen in m.screens
        screen.UnobserveField("action")
    end for
    for each key in m.moving.Keys()
        stopMoving(m.moving[key].screen)
    end for
    m.moving = {}
    m.screens = []
    m.stack.RemoveChildrenIndex(m.stack.GetChildCount(), 0)
    screen = pushScreen(name)
    screen.takeFocus = true
    ' Signing in by itself during the intro: the intro keeps the keys.
    if m.intro <> invalid then m.intro.SetFocus(true)
end sub

' --- Screens coming and going ------------------------------------------------------------
'
' As in the web app (its motion.css): a page slides in from the right and leaves the same
' way, Details rises like a card and drops away, the player and Home fade; the page
' underneath sinks back a little and comes up again when you return. Only opacity,
' position and scale move.

function entrance(name as String) as String
    if name = "DetailsScreen" then return "rise"
    if name = "PlayerScreen" or name = "HomeScreen" or name = "LoginScreen" then return "fade"
    return "in"
end function

function exitFor(name as String) as String
    if name = "DetailsScreen" then return "drop"
    if name = "PlayerScreen" then return "fadeOut"
    return "out"
end function

' motion: "in", "rise", "fade" and "back" bring a screen in; "sink" takes it under the
' next one (then hides it); "out", "drop" and "fadeOut" take it away (then remove it).
' A screen's new motion takes over from one still running.
sub moveScreen(screen as Object, motion as String)
    stopMoving(screen)
    seconds = 0.3
    ease = "outExpo"
    after = "show"
    opacity = [0.0, 1.0]
    position = invalid
    size = invalid
    if motion = "in" then
        position = [[28, 0], [0, 0]]
    else if motion = "rise" then
        seconds = 0.38
        position = [[0, 40], [0, 0]]
    else if motion = "fade" then
        ease = "outQuad"
    else if motion = "back" then
        opacity = [screen.opacity, 1.0]
        size = [screen.scale, [1.0, 1.0]]
    else if motion = "sink" then
        seconds = 0.26
        ease = "inCubic"
        opacity = [screen.opacity, 0.0]
        size = [screen.scale, [0.97, 0.97]]
        after = "hide"
    else
        seconds = 0.24
        ease = "inCubic"
        opacity = [screen.opacity, 0.0]
        if motion = "out" then position = [screen.translation, [28, 0]]
        if motion = "drop" then position = [screen.translation, [0, 40]]
        after = "remove"
    end if

    anim = m.top.CreateChild("Animation")
    anim.duration = seconds
    anim.easeFunction = ease
    anim.AddFields({ screenId: screen.id })
    screen.opacity = opacity[0]
    addLerp(anim, "FloatFieldInterpolator", screen.id + ".opacity", opacity)
    if position <> invalid then
        screen.translation = position[0]
        addLerp(anim, "Vector2DFieldInterpolator", screen.id + ".translation", position)
    end if
    if size <> invalid then
        screen.scale = size[0]
        addLerp(anim, "Vector2DFieldInterpolator", screen.id + ".scale", size)
    end if
    m.moving[screen.id] = { anim: anim, screen: screen, after: after }
    anim.ObserveField("state", "onScreenMoved")
    anim.control = "start"
end sub

sub addLerp(anim as Object, kind as String, target as String, values as Object)
    lerp = anim.CreateChild(kind)
    lerp.key = [0.0, 1.0]
    lerp.keyValue = values
    lerp.fieldToInterp = target
end sub

sub onScreenMoved(event as Object)
    anim = event.GetRoSGNode()
    if anim.state <> "stopped" then return
    job = m.moving[anim.screenId]
    if job = invalid or not job.anim.IsSameNode(anim) then
        anim.UnobserveField("state")
        m.top.RemoveChild(anim)
        return
    end if
    m.moving.Delete(anim.screenId)
    anim.UnobserveField("state")
    m.top.RemoveChild(anim)
    screen = job.screen
    if job.after = "remove" then
        m.stack.RemoveChild(screen)
    else if job.after = "hide" then
        ' Left sunk back, so "back" brings it up from there.
        screen.visible = false
    else
        screen.opacity = 1.0
        screen.translation = [0, 0]
        screen.scale = [1.0, 1.0]
    end if
end sub

' Stops a screen's motion where it is, without what was to follow it.
sub stopMoving(screen as Object)
    job = m.moving[screen.id]
    if job = invalid then return
    m.moving.Delete(screen.id)
    job.anim.UnobserveField("state")
    job.anim.control = "stop"
    m.top.RemoveChild(job.anim)
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
        playSound("back")
        popScreen()
        return true
    end if
    return false
end function
