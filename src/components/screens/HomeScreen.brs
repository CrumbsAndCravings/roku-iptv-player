sub init()
    m.rows = m.top.FindNode("rows")
    m.backdrop = m.top.FindNode("backdrop")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroMeta = m.top.FindNode("heroMeta")
    m.heroPlot = m.top.FindNode("heroPlot")
    m.status = m.top.FindNode("status")
    m.navKeys = m.top.FindNode("navKeys")
    m.heroTimer = m.top.FindNode("heroTimer")

    m.heroTitle.font = MakeFont("Outfit-Bold", 38)
    m.heroMeta.font = MakeFont("Outfit-SemiBold", 18)
    ' Plots come from the provider and may not be in a Latin script, so they use the system font.
    m.heroPlot.font = "font:SmallSystemFont"
    m.rows.rowLabelFont = MakeFont("Outfit-SemiBold", 20)
    m.status.font = MakeFont("Outfit-Regular", 20)

    m.tabNames = ["Home", "Movies", "Series", "Search"]
    m.tab = 0
    m.tabCursor = 0
    m.navFocused = true
    m.firstLoad = true
    m.tabPills = BuildPills(m.top.FindNode("tabs"), m.tabNames, 18)
    styleTabs()

    m.generation = 0
    m.taskCount = 0
    m.tasks = {}
    m.pendingRows = {}
    m.infoTargets = {}
    m.rowQueue = []
    m.inFlight = 0
    m.plan = []
    m.planIndex = 0
    m.focusedItem = invalid
    m.failed = false
    m.lastError = ""

    m.rows.ObserveField("rowItemFocused", "onRowItemFocused")
    m.rows.ObserveField("rowItemSelected", "onRowItemSelected")
    m.heroTimer.ObserveField("fire", "onHeroTimer")

    loadCategories()
end sub

' --- Tasks -----------------------------------------------------------------

function startTask(request as Object, callback as String) as String
    m.taskCount = m.taskCount + 1
    key = "t" + m.taskCount.ToStr()
    request.taskKey = key
    request.generation = m.generation
    task = CreateObject("roSGNode", "XtreamTask")
    task.request = request
    task.ObserveField("result", callback)
    m.tasks[key] = task
    task.control = "RUN"
    return key
end function

' Returns the task's result with its content node attached, and forgets the task.
function finishTask(event as Object) as Object
    task = event.GetRoSGNode()
    result = event.GetData()
    result.content = task.content
    task.UnobserveField("result")
    m.tasks.Delete(FieldStr(result.request, "taskKey"))
    return result
end function

' Row requests go through a small queue so a slow TV isn't parsing ten catalogs at once.
sub queueRow(request as Object, placeholder as Object)
    m.rowQueue.Push({ request: request, placeholder: placeholder })
    pumpQueue()
end sub

sub pumpQueue()
    while m.inFlight < 3 and m.rowQueue.Count() > 0
        job = m.rowQueue.Shift()
        key = startTask(job.request, "onRowLoaded")
        m.pendingRows[key] = job.placeholder
        m.inFlight = m.inFlight + 1
    end while
end sub

' --- Loading -----------------------------------------------------------------

sub loadCategories()
    m.failed = false
    m.status.text = "Loading your library…"
    m.categories = { vod: invalid, series: invalid }
    startTask({ mode: "categories", kind: "vod" }, "onCategories")
    startTask({ mode: "categories", kind: "series" }, "onCategories")
end sub

sub onCategories(event as Object)
    result = finishTask(event)
    kind = FieldStr(result.request, "kind")
    if result.ok then
        m.categories[kind] = result.categories
    else
        m.categories[kind] = []
        m.lastError = result.error
    end if
    if m.categories.vod = invalid or m.categories.series = invalid then return
    showTab(m.tab)
end sub

function buildPlan(tabIndex as Integer) as Object
    plan = []
    vod = m.categories.vod
    series = m.categories.series
    if tabIndex = 0 then
        ' Home mixes the provider's first few movie and series categories.
        for i = 0 to 5
            if i < vod.Count() then plan.Push({ kind: "vod", categoryId: vod[i].id, title: vod[i].name + "  ·  Movies" })
            if i < series.Count() then plan.Push({ kind: "series", categoryId: series[i].id, title: series[i].name + "  ·  Series" })
        end for
    else if tabIndex = 1 then
        for each category in vod
            plan.Push({ kind: "vod", categoryId: category.id, title: category.name })
        end for
    else
        for each category in series
            plan.Push({ kind: "series", categoryId: category.id, title: category.name })
        end for
    end if
    return plan
end function

sub showTab(tabIndex as Integer)
    m.tab = tabIndex
    m.tabCursor = tabIndex
    m.generation = m.generation + 1
    m.rowQueue = []
    m.pendingRows = {}
    m.plan = buildPlan(tabIndex)
    m.planIndex = 0

    root = CreateObject("roSGNode", "ContentNode")
    if tabIndex = 0 then
        continueRow = ContinueWatchingRow()
        if continueRow <> invalid then root.AppendChild(continueRow)
    end if
    appendRows(root, 5)
    m.rows.content = root
    styleTabs()

    if root.GetChildCount() = 0 then
        m.failed = true
        if m.lastError <> "" then
            m.status.text = "Couldn't load your library. " + m.lastError + " Press OK to try again."
        else
            m.status.text = "Your provider didn't list anything here."
        end if
        clearHero()
        focusNav()
        return
    end if

    m.status.text = ""
    m.failed = false
    if m.firstLoad then
        m.firstLoad = false
        focusRows()
    end if
end sub

sub appendRows(root as Object, count as Integer)
    added = 0
    while added < count and m.planIndex < m.plan.Count()
        entry = m.plan[m.planIndex]
        m.planIndex = m.planIndex + 1
        row = root.CreateChild("ContentNode")
        row.title = entry.title
        for i = 0 to 7
            MakeItem(row, { placeholder: true })
        end for
        queueRow({ mode: "row", kind: entry.kind, categoryId: entry.categoryId, title: entry.title, limit: 40 }, row)
        added = added + 1
    end while
end sub

sub onRowLoaded(event as Object)
    result = finishTask(event)
    m.inFlight = m.inFlight - 1
    pumpQueue()
    key = FieldStr(result.request, "taskKey")
    placeholder = m.pendingRows[key]
    m.pendingRows.Delete(key)
    if result.request.generation <> m.generation or placeholder = invalid then return

    root = m.rows.content
    index = indexOfRow(root, placeholder)
    if index < 0 then return
    loaded = result.content
    if result.ok and loaded <> invalid and loaded.GetChildCount() > 0 then
        root.ReplaceChild(loaded, index)
    else
        ' Empty or failed category: drop it and pull in the next one instead.
        root.RemoveChildIndex(index)
        appendRows(root, 1)
    end if
    if root.GetChildCount() = 0 then
        m.status.text = "Your provider didn't list anything here."
        clearHero()
        focusNav()
        return
    end if
    focus = m.rows.rowItemFocused
    if focus <> invalid and focus.Count() > 0 and focus[0] = index then refreshHero()
end sub

function indexOfRow(root as Object, row as Object) as Integer
    for i = 0 to root.GetChildCount() - 1
        if root.GetChild(i).IsSameNode(row) then return i
    end for
    return -1
end function

' --- Hero --------------------------------------------------------------------

function focusedItem() as Dynamic
    root = m.rows.content
    if root = invalid then return invalid
    focus = m.rows.rowItemFocused
    if focus = invalid or focus.Count() < 2 or focus[0] < 0 or focus[1] < 0 then return invalid
    row = root.GetChild(focus[0])
    if row = invalid then return invalid
    return row.GetChild(focus[1])
end function

sub onRowItemFocused()
    refreshHero()
    root = m.rows.content
    focus = m.rows.rowItemFocused
    if root = invalid or focus = invalid or focus.Count() = 0 then return
    if focus[0] >= root.GetChildCount() - 3 then appendRows(root, 3)
end sub

sub refreshHero()
    item = focusedItem()
    if item = invalid then return
    if item.placeholder then return
    m.focusedItem = item
    showHero(item)
    if not item.hasInfo and item.kind = "movie" then
        m.heroTimer.control = "stop"
        m.heroTimer.control = "start"
    end if
end sub

sub showHero(item as Object)
    m.heroTitle.text = item.title
    meta = MetaLine(item)
    if item.caption <> "" then
        meta = "Resume  " + item.caption
    end if
    m.heroMeta.color = "0xB4B4C2FF"
    if item.problem <> "" then
        meta = "Won't play on this TV (" + item.problem + ")   ·   " + meta
        m.heroMeta.color = "0xF5B83DFF"
    end if
    m.heroMeta.text = meta
    m.heroPlot.text = item.description
    ShowBackdrop(m.backdrop, item.backdrop, item.HDPosterUrl)
end sub

sub clearHero()
    m.heroTitle.text = ""
    m.heroMeta.text = ""
    m.heroPlot.text = ""
    m.backdrop.uri = ""
end sub

' Movie lists don't include plots or backdrops, so fetch them once the focus settles.
sub onHeroTimer()
    item = m.focusedItem
    if item = invalid then return
    if item.hasInfo or item.kind <> "movie" then return
    item.hasInfo = true
    key = startTask({ mode: "vodInfo", id: item.itemId }, "onHeroInfo")
    m.infoTargets[key] = item
end sub

sub onHeroInfo(event as Object)
    result = finishTask(event)
    key = FieldStr(result.request, "taskKey")
    item = m.infoTargets[key]
    m.infoTargets.Delete(key)
    if item = invalid or not result.ok then return
    ApplyInfo(item, result.info)
    check = PlaybackCheck(item.ext, item.videoCodec, item.videoProfile, item.audioCodec)
    item.problem = check.blocked
    if m.focusedItem <> invalid and m.focusedItem.IsSameNode(item) then showHero(item)
end sub

' --- Selection & focus -------------------------------------------------------

sub onRowItemSelected()
    root = m.rows.content
    selected = m.rows.rowItemSelected
    if root = invalid or selected = invalid or selected.Count() < 2 then return
    row = root.GetChild(selected[0])
    if row = invalid then return
    item = row.GetChild(selected[1])
    if item = invalid then return
    if item.placeholder then return
    if m.navFocused then return
    m.top.action = { name: "openDetails", item: item }
end sub

sub onTakeFocus()
    if m.tab = 0 and m.rows.content <> invalid then refreshContinueWatching()
    restoreFocus()
end sub

sub restoreFocus()
    if m.navFocused then
        focusNav()
    else
        focusRows()
    end if
end sub

sub refreshContinueWatching()
    root = m.rows.content
    continueRow = ContinueWatchingRow()
    hasRow = false
    if root.GetChildCount() > 0 then hasRow = root.GetChild(0).HasField("isContinue")
    if continueRow <> invalid and hasRow then
        root.ReplaceChild(continueRow, 0)
    else if continueRow <> invalid then
        root.InsertChild(continueRow, 0)
    else if hasRow then
        root.RemoveChildIndex(0)
    end if
    focus = m.rows.rowItemFocused
    if root.GetChildCount() > 0 and focus <> invalid and focus.Count() > 0 and focus[0] = 0 then m.rows.jumpToRowItem = [0, 0]
    refreshHero()
end sub

sub focusRows()
    root = m.rows.content
    if root = invalid or root.GetChildCount() = 0 then
        focusNav()
        return
    end if
    m.navFocused = false
    m.rows.SetFocus(true)
    styleTabs()
end sub

' Focus goes to navKeys, an empty sibling of the rows, rather than to this screen.
' Focusing an ancestor of the RowList could leave the RowList still taking keys, so
' OK on a tab opened the poster underneath instead.
sub focusNav()
    m.navFocused = true
    m.tabCursor = m.tab
    m.navKeys.SetFocus(true)
    styleTabs()
end sub

sub activateTab()
    ' Search is its own screen; the tab bar stays on the current tab behind it.
    if m.tabNames[m.tabCursor] = "Search" then
        m.tabCursor = m.tab
        styleTabs()
        m.top.action = { name: "openSearch" }
        return
    end if
    if m.failed then
        loadCategories()
        return
    end if
    if m.tabCursor <> m.tab then showTab(m.tabCursor)
    focusRows()
end sub

sub styleTabs()
    for i = 0 to m.tabPills.Count() - 1
        bg = m.tabPills[i].GetChild(0)
        label = m.tabPills[i].GetChild(1)
        if m.navFocused and i = m.tabCursor then
            bg.blendColor = "0xF5F5F7FF"
            bg.opacity = 1.0
            label.color = "0x0B0B0FFF"
        else if i = m.tab then
            bg.blendColor = "0x2B2B36FF"
            bg.opacity = 0.9
            label.color = "0xF5F5F7FF"
        else
            bg.opacity = 0.0
            label.color = "0x9A9AAAFF"
        end if
    end for
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if m.navFocused then return onNavKey(key, press)
    if not press then return false
    if key = "options" then
        showAccountMenu()
        return true
    end if

    ' The rows didn't use this key: Up on the first row, or Left on a row's first poster.
    if key = "up" or key = "left" then
        focusNav()
        return true
    else if key = "back" then
        focus = m.rows.rowItemFocused
        if focus <> invalid and focus.Count() > 0 and focus[0] > 0 then
            m.rows.jumpToRowItem = [0, 0]
        else
            focusNav()
        end if
        return true
    end if
    return false
end function

function onNavKey(key as String, press as Boolean) as Boolean
    ' OK acts on release, so the release can't land on the rows once they have focus.
    if key = "OK" then
        if not press then activateTab()
        return true
    end if
    if not press then return key <> "back"
    if key = "left" then
        if m.tabCursor > 0 then m.tabCursor = m.tabCursor - 1
        styleTabs()
    else if key = "right" then
        if m.tabCursor < m.tabNames.Count() - 1 then m.tabCursor = m.tabCursor + 1
        styleTabs()
    else if key = "down" then
        activateTab()
    else if key = "options" then
        showAccountMenu()
    else if key = "back" then
        return false
    end if
    return true
end function

' --- Account -----------------------------------------------------------------

sub showAccountMenu()
    creds = m.global.creds
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Account"
    dialog.message = ["Signed in as " + FieldStr(creds, "username") + " on " + FieldStr(creds, "server") + "."]
    dialog.buttons = ["Keep watching", "Sign out"]
    dialog.ObserveField("buttonSelected", "onAccountButton")
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onAccountButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    choice = dialog.buttonSelected
    dialog.close = true
    if choice = 1 then m.top.action = { name: "signOut" }
end sub

sub onDialogClosed()
    restoreFocus()
end sub
