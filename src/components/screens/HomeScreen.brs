sub init()
    m.rows = m.top.FindNode("rows")
    m.backdrop = m.top.FindNode("backdrop")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroMeta = m.top.FindNode("heroMeta")
    m.heroPlot = m.top.FindNode("heroPlot")
    m.status = m.top.FindNode("status")
    m.navKeys = m.top.FindNode("navKeys")
    m.heroTimer = m.top.FindNode("heroTimer")
    m.hero = m.top.FindNode("hero")
    m.backdropIn = m.top.FindNode("backdropIn")
    m.backdropFade = m.top.FindNode("backdropFade")
    m.tabBar = m.top.FindNode("tabBar")
    m.lens = m.top.FindNode("lens")
    m.lensShape = m.top.FindNode("lensShape")
    m.lensClear = m.top.FindNode("lensClear")
    m.lensLit = m.top.FindNode("lensLit")
    m.lensTop = m.top.FindNode("lensTop")
    m.lensView = m.top.FindNode("lensView")
    m.lensShine = m.top.FindNode("lensShine")
    m.lensGlass = m.top.FindNode("lensGlass")
    m.lensRim = m.top.FindNode("lensRim")
    m.heroItem = invalid
    m.backdropTarget = 1.0
    m.settleBackdrop = false
    m.backdrop.ObserveField("loadStatus", "onBackdropLoaded")
    SlidesInit(m.backdrop, m.top.FindNode("backdropFront"), m.top.FindNode("slideTimer"))

    m.heroTitle.font = MakeFont("Fredoka-SemiBold", 40)
    m.heroMeta.font = MakeFont("Nunito-ExtraBold", 18)
    ' Plots come from the provider and may not be in a Latin script, so they use the system font.
    m.heroPlot.font = "font:SmallSystemFont"
    m.rows.rowLabelFont = MakeFont("Fredoka-Medium", 21)
    m.status.font = MakeFont("Nunito-SemiBold", 20)

    m.tabNames = ["Home", "Movies", "Series", "Categories", "Search"]
    m.tab = 0
    m.tabCursor = 0
    m.navFocused = true
    m.firstLoad = true
    m.lensAt = -1
    m.lensState = ""
    m.okDown = false
    buildTabs()
    styleTabs()

    m.generation = 0
    m.taskCount = 0
    m.tasks = {}
    m.pendingRows = {}
    m.infoTargets = {}
    m.rowQueue = []
    m.inFlight = 0
    ' Rows already loaded this session, by "kind:categoryId", so switching tabs and
    ' coming back doesn't ask the provider again.
    m.rowCache = {}
    m.plan = []
    m.planIndex = 0
    m.focusedItem = invalid
    m.failed = false
    m.lastError = ""
    ' Rows picked for you: [{ slot, row, k, n }] (addPersonalRows).
    m.personal = []
    m.picksKey = ""
    m.watchingPicks = false
    m.listStamp = ""
    ' The poster menu (* on a poster) and the menu it opens next, if any.
    m.menuItem = invalid
    m.menuActions = []
    m.rateChoices = []
    m.nextDialog = ""
    m.serverTask = invalid
    m.serverTyped = ""
    m.serverError = ""
    m.picksTimer = m.top.FindNode("picksTimer")
    m.picksTimer.ObserveField("fire", "askPicks")
    ' 0.5.9 and 0.5.10 had a guard that switched these rows off after a launch that
    ' stopped part way (it hid My List after 0.5.9's crash); its marks go.
    RegDelete("taste", "guard")
    RegDelete("taste", "off")

    m.rows.ObserveField("rowItemFocused", "onRowItemFocused")
    m.rows.ObserveField("rowItemSelected", "onRowItemSelected")
    m.heroTimer.ObserveField("fire", "onHeroTimer")
    ' Another device changed Continue Watching.
    m.global.ObserveFieldScoped("syncedAt", "onSyncedElsewhere")

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
    m.lastError = ""
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

' Which category rows each tab shows. Categories in languages you don't watch are left
' out (search still finds their titles), names are tidied ("EN | ACTION ★" -> "Action"),
' and categories of new releases come first.
function buildPlan(tabIndex as Integer) as Object
    langs = LanguagePrefs()
    year = CreateObject("roDateTime").GetYear()
    demote4K = not IsUhdScreen()
    vod = OrganizeCategories(m.categories.vod, langs, year, demote4K)
    series = OrganizeCategories(m.categories.series, langs, year, demote4K)
    plan = []
    if tabIndex = 0 then
        ' Newest everything: new-release categories first, then the rest with movies and
        ' series taking turns and each language taking turns, up to 18 rows.
        newest = TakeTurns(planEntries(vod, "vod", true), planEntries(series, "series", true))
        rest = LanguageTurns(TakeTurns(planEntries(vod, "vod", false), planEntries(series, "series", false)), langs)
        newest.Append(rest)
        ' Then the categories you watch move up, after the first two (common/Taste.brs).
        newest = TasteOrder(newest, likings(), 2)
        for each entry in newest
            if plan.Count() >= 18 then exit for
            if entry.kind = "series" then
                entry.title = entry.label + "  ·  Series"
            else
                entry.title = entry.label + "  ·  Movies"
            end if
            plan.Push(entry)
        end for
    else if tabIndex = 1 then
        plan = TasteOrder(planEntries(vod, "vod", invalid), likings(), 1)
    else
        plan = TasteOrder(planEntries(series, "series", invalid), likings(), 1)
    end if
    return plan
end function

' The likings that order the rows (TasteOrder).
function likings() as Object
    return TasteScores()
end function

' Plan entries for organized categories of one kind; with wantNew true or false, only
' the categories of new releases or only the others.
function planEntries(list as Object, kind as String, wantNew as Dynamic) as Object
    entries = []
    for each category in list
        if wantNew = invalid or category.isNew = wantNew then entries.Push({ kind: kind, categoryId: category.id, label: category.label, title: category.label, lang: category.lang, demoted: category.demoted })
    end for
    return entries
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
    m.personal = []
    if tabIndex = 0 then
        continueRow = ContinueWatchingRow()
        if continueRow <> invalid then root.AppendChild(continueRow)
        addPersonalRows(root)
    end if
    appendRows(root, 5)
    m.rows.content = root
    styleTabs()

    if root.GetChildCount() = 0 then
        m.failed = true
        if m.lastError <> "" then
            showLoadError()
            return
        else
            m.status.text = "Your provider didn't list anything here."
        end if
        clearHero()
        focusNav()
        return
    end if

    m.status.text = ""
    m.failed = false
    ' The library worker starts a few seconds in, so Home's own rows load first.
    if m.personal.Count() > 0 then
        if m.global.search <> invalid then
            askPicks()
        else
            m.picksTimer.control = "start"
        end if
    end if
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
        cached = m.rowCache[entry.kind + ":" + entry.categoryId]
        if cached <> invalid then
            cached.title = entry.title
            root.AppendChild(cached)
        else
            row = root.CreateChild("ContentNode")
            row.title = entry.title
            for i = 0 to 7
                MakeItem(row, { placeholder: true })
            end for
            queueRow({ mode: "row", kind: entry.kind, categoryId: entry.categoryId, title: entry.title, limit: 40 }, row)
        end if
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
    loaded = result.content
    if result.ok and loaded <> invalid and loaded.GetChildCount() > 0 then
        ' A "See all" tile ends the row; its page lists the whole category from the
        ' library stored on the Roku.
        MakeItem(loaded, { kind: "seeAll", title: "See all", categoryId: FieldStr(result.request, "categoryId"), listKind: FieldStr(result.request, "kind") })
        m.rowCache[FieldStr(result.request, "kind") + ":" + FieldStr(result.request, "categoryId")] = loaded
    end if
    if result.request.generation <> m.generation or placeholder = invalid then return

    root = m.rows.content
    index = indexOfRow(root, placeholder)
    if index < 0 then return
    if result.ok and loaded <> invalid and loaded.GetChildCount() > 0 then
        root.ReplaceChild(loaded, index)
    else if not result.ok then
        ' The server is saying no or not answering. Asking for every other category would
        ' look like a flood and could keep this connection blocked longer, so stop here.
        root.RemoveChildIndex(index)
        m.rowQueue = []
        m.planIndex = m.plan.Count()
        m.lastError = result.error
        if root.GetChildCount() = 0 then
            showLoadError()
            return
        end if
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
    MovedSound(m.rows, m.rows.rowItemFocused)
    refreshHero()
    root = m.rows.content
    focus = m.rows.rowItemFocused
    if root = invalid or focus = invalid or focus.Count() = 0 then return
    if focus[0] >= root.GetChildCount() - 3 then appendRows(root, 3)
end sub

sub refreshHero()
    item = focusedItem()
    if item = invalid then return
    if item.placeholder or item.kind = "seeAll" then return
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
    if TitleKey(item) <> "" then meta = meta + "   ·   * for options"
    m.heroMeta.color = "0xC3B8E6FF"
    if item.problem <> "" then
        meta = "Won't play on this " + DeviceWord() + " (" + item.problem + ")   ·   " + meta
        m.heroMeta.color = "0xFFD98AFF"
    end if
    m.heroMeta.text = meta
    m.heroPlot.text = item.description
    ' A new title floats in; a refresh of the same title (details arriving) doesn't.
    isNew = true
    if m.heroItem <> invalid then isNew = not m.heroItem.IsSameNode(item)
    m.heroItem = item
    ' Its lines come up one after another, and its picture settles as it fades in.
    if isNew then
        Tween(m.hero, "translation", [[48, 126], [48, 112]], 0.45, "outExpo", 0)
        delay = 0.0
        for each part in [m.heroTitle, m.heroMeta, m.heroPlot]
            part.opacity = 0.0
            Tween(part, "opacity", [0.0, 1.0], 0.4, "outQuad", delay)
            delay = delay + 0.07
        end for
        m.settleBackdrop = true
        SlidesStop()
    end if
    ' The same title again (its details arrived) keeps its pictures turning.
    if isNew or not SlidesRunning() then
        m.backdropIn.control = "stop"
        m.backdropTarget = ShowBackdrop(m.backdrop, item.backdrop, item.HDPosterUrl)
    end if
    ' With more than one backdrop, they take turns (common/Slides.brs).
    if not SlidesRunning() then SlidesStart(BackdropPictures(item), m.backdropTarget)
end sub

sub onBackdropLoaded()
    ' The moving banner's next picture is its own to show.
    if SlidesBackLoaded() then return
    if m.backdrop.loadStatus <> "ready" then return
    m.backdropFade.keyValue = [0.0, m.backdropTarget]
    m.backdropIn.control = "start"
    if m.settleBackdrop then
        m.settleBackdrop = false
        Tween(m.backdrop, "scale", [[1.06, 1.06], [1.0, 1.0]], 1.6, "outCubic", 0)
    end if
end sub

sub clearHero()
    SlidesStop()
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
    item.problem = WontPlay(check)
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
    Sound("select")
    if item.kind = "seeAll" then
        title = row.title
        if m.tab = 1 then title = title + "  ·  Movies"
        if m.tab = 2 then title = title + "  ·  Series"
        m.top.action = { name: "openCategory", category: { kind: item.listKind, categoryId: item.categoryId, title: title } }
        return
    end if
    m.top.action = { name: "openDetails", item: item }
end sub

sub onTakeFocus()
    if m.tab = 0 and m.rows.content <> invalid then
        refreshContinueWatching()
        syncListRow()
        ' What you just watched leaves the picks, and may change them.
        if m.global.search <> invalid then askPicks()
    end if
    ' Pick up what other devices watched (at most once a minute).
    m.top.action = { name: "syncSoon" }
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
    ' The intro has the keys until it's over (MainScene then gives them back).
    if m.global.introPlaying <> true then m.rows.SetFocus(true)
    styleTabs()
end sub

' Focus goes to navKeys, an empty sibling of the rows, rather than to this screen.
' Focusing an ancestor of the RowList could leave the RowList still taking keys, so
' OK on a tab opened the poster underneath instead.
sub focusNav()
    m.navFocused = true
    m.tabCursor = m.tab
    if m.global.introPlaying <> true then m.navKeys.SetFocus(true)
    styleTabs()
end sub

sub activateTab()
    ' Search and Categories are their own screens; the tab bar stays on the current tab
    ' behind them.
    if m.tabNames[m.tabCursor] = "Search" then
        m.tabCursor = m.tab
        styleTabs()
        m.top.action = { name: "openSearch" }
        return
    end if
    if m.tabNames[m.tabCursor] = "Categories" then
        if m.failed then
            loadCategories()
            return
        end if
        ' Still loading the category lists: nothing to show yet.
        if m.categories.vod = invalid or m.categories.series = invalid then return
        m.tabCursor = m.tab
        styleTabs()
        langs = LanguagePrefs()
        year = CreateObject("roDateTime").GetYear()
        demote4K = not IsUhdScreen()
        m.top.action = { name: "openCategories", lists: { vod: OrganizeCategories(m.categories.vod, langs, year, demote4K), series: OrganizeCategories(m.categories.series, langs, year, demote4K), langs: langs } }
        return
    end if
    if m.failed then
        loadCategories()
        return
    end if
    if m.tabCursor <> m.tab then showTab(m.tabCursor)
    focusRows()
end sub

' --- The tab bar ---------------------------------------------------------------
'
' Glass, as in the web app (HomeScreen.xml): the tab names, and a glass lens that rests
' on the current tab. With the bar focused it's lit lavender and follows the cursor,
' springing from tab to tab and stretching as it goes, the faster the more; OK swells
' the bar and lifts the lens, which wobbles back as the tab opens. Each tab has a 112
' wide slot, 4 in from the bar's ends.

sub buildTabs()
    m.tabLabels = []
    m.tabCopies = []
    labels = m.top.FindNode("tabLabels")
    copies = m.top.FindNode("lensView")
    for i = 0 to m.tabNames.Count() - 1
        m.tabLabels.Push(tabLabel(labels, i, "0xE4DEF2FF"))
        ' Inside the lens, dark on its lavender.
        m.tabCopies.Push(tabLabel(copies, i, "0x151028FF"))
    end for
end sub

function tabLabel(parent as Object, index as Integer, color as String) as Object
    label = parent.CreateChild("Label")
    label.font = MakeFont("Fredoka-Medium", 18)
    label.text = m.tabNames[index]
    label.color = color
    label.width = 112
    label.height = 40
    label.horizAlign = "center"
    label.vertAlign = "center"
    label.translation = [tabX(index), 4]
    label.scaleRotateCenter = [56, 20]
    return label
end function

function tabX(index as Integer) as Integer
    return 4 + index * 112
end function

sub styleTabs()
    for i = 0 to m.tabLabels.Count() - 1
        if i = m.tab then
            m.tabLabels[i].color = "0xC9B8FFFF"
        else
            m.tabLabels[i].color = "0xE4DEF2FF"
        end if
    end for
    if m.navFocused then
        moveLens(m.tabCursor)
    else
        moveLens(m.tab)
    end if
    lightLens(m.navFocused)
end sub

' Springs the lens to a tab (the web app's spring, 620 ms), stretched along the way by
' its speed: longer one way and thinner the other, as a moving drop is.
sub moveLens(index as Integer)
    if index = m.lensAt then return
    toX = tabX(index)
    if m.lensAt < 0 then
        m.lensAt = index
        m.lens.translation = [toX, 4]
        m.lensTop.translation = [toX, 4]
        m.lensView.translation = [-toX, -4]
        return
    end if
    m.lensAt = index
    fromX = m.lens.translation[0]
    curve = SpringCurve()
    last = curve.Count() - 1
    stepMs = 620 / last
    ' How much of the stretch is left after each step (it comes and goes over ~70 ms).
    keep = Exp(-stepMs / 70)
    stretch = m.lensShape.scale[0]
    places = []
    views = []
    shapes = []
    x = fromX
    for i = 0 to last
        previous = x
        x = fromX + (toX - fromX) * curve[i]
        places.Push([x, 4])
        views.Push([-x, -4])
        want = 1 + Abs(x - previous) / stepMs * 0.22
        if want > 1.3 then want = 1.3
        stretch = want + (stretch - want) * keep
        if i = last then stretch = 1.0
        shapes.Push([stretch, 1 / Sqr(stretch)])
    end for
    Tween(m.lens, "translation", places, 0.62, "linear", 0)
    Tween(m.lensTop, "translation", places, 0.62, "linear", 0)
    Tween(m.lensView, "translation", views, 0.62, "linear", 0)
    Tween(m.lensShape, "scale", shapes, 0.62, "linear", 0)
    Tween(m.lensShine, "scale", shapes, 0.62, "linear", 0)
end sub

' Lit lavender (the bar has focus, the dark names show inside it) or clear glass.
sub lightLens(lit as Boolean)
    state = "clear"
    if lit then state = "lit"
    if state = m.lensState then return
    m.lensState = state
    if lit then
        FadeTo(m.lensLit, 0.95, 0.2)
        FadeTo(m.lensClear, 0.0, 0.2)
        FadeTo(m.lensView, 1.0, 0.2)
        FadeTo(m.lensGlass, 1.0, 0.2)
    else
        FadeTo(m.lensLit, 0.0, 0.2)
        FadeTo(m.lensClear, 0.1, 0.2)
        FadeTo(m.lensView, 0.0, 0.2)
        FadeTo(m.lensGlass, 0.6, 0.2)
    end if
    FadeTo(m.lensRim, rimOpacity(), 0.2)
end sub

function rimOpacity() as Float
    if m.lensState = "lit" then return 0.55
    return 0.3
end function

' OK held on the bar: it swells and the lens lifts, its rim catching more colour. Let go,
' and both spring back, the lens wobbling like jelly.
sub pressBar(down as Boolean)
    if down then
        SpringScale(m.tabBar, 1.04)
        lifted = [1.1, 1.22]
        Tween(m.lensShape, "scale", CurveValues(m.lensShape.scale, lifted, SpringCurve()), 0.42, "linear", 0)
        Tween(m.lensShine, "scale", CurveValues(m.lensShine.scale, lifted, SpringCurve()), 0.42, "linear", 0)
        FadeTo(m.lensRim, 0.9, 0.15)
    else
        SpringScale(m.tabBar, 1.0)
        Tween(m.lensShape, "scale", CurveValues(m.lensShape.scale, [1.0, 1.0], JellyCurve()), 0.76, "linear", 0)
        Tween(m.lensShine, "scale", CurveValues(m.lensShine.scale, [1.0, 1.0], JellyCurve()), 0.76, "linear", 0)
        FadeTo(m.lensRim, rimOpacity(), 0.3)
        PopNode(m.tabLabels[m.tabCursor])
        PopNode(m.tabCopies[m.tabCursor])
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if m.navFocused then return onNavKey(key, press)
    if not press then return false
    if key = "options" then
        ' On a poster, * offers My List, a rating and (on Continue Watching) taking it
        ' off; elsewhere it's the account menu.
        item = focusedItem()
        if TitleKey(item) <> "" then
            showTitleMenu(item)
        else
            showAccountMenu()
        end if
        return true
    end if

    ' The rows didn't use this key: Up on the first row, or Left on a row's first poster.
    if key = "up" or key = "left" then
        Sound("move")
        focusNav()
        return true
    else if key = "back" then
        Sound("back")
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
    ' OK acts on release, so the release can't land on the rows once they have focus,
    ' and only after a press here (not one that closed a dialog). Held, the bar swells.
    if key = "OK" then
        if press then
            m.okDown = true
            pressBar(true)
        else if m.okDown = true then
            m.okDown = false
            pressBar(false)
            Sound("select")
            activateTab()
        end if
        return true
    end if
    if not press then return key <> "back"
    if key = "left" then
        if m.tabCursor > 0 then
            m.tabCursor = m.tabCursor - 1
            Sound("move")
        end if
        styleTabs()
    else if key = "right" then
        if m.tabCursor < m.tabNames.Count() - 1 then
            m.tabCursor = m.tabCursor + 1
            Sound("move")
        end if
        styleTabs()
    else if key = "down" then
        ' Down into the tab's own rows is a move; onto another tab or screen, a choice.
        if m.tabCursor = m.tab and not m.failed then
            Sound("move")
        else
            Sound("select")
        end if
        activateTab()
    else if key = "options" then
        showAccountMenu()
    else if key = "back" then
        return false
    end if
    return true
end function

' --- Picked for you -----------------------------------------------------------------
'
' "Top picks for you" and "Because you watched" rows under Continue Watching, from what
' you watch (common/Taste.brs) and the library stored on the Roku (the library worker's
' answerPicks), so they cost the provider nothing. They're laid out as placeholders
' straight away, so nothing jumps when they arrive. With no stored library yet (the
' worker builds it the first time), they wait for the next launch.

sub addPersonalRows(root as Object)
    ' My List first, as name cards until the library worker brings their pictures.
    list = MyList()
    m.listStamp = FormatJson(list)
    if list.Count() > 0 then
        row = MyListRow(list, {})
        root.AppendChild(row)
        m.personal.Push({ slot: "list", row: row, k: "", n: "" })
    end if
    if not LibrarySaved() then return
    history = TasteHistory()
    if history.Count() = 0 and ProgressList().Count() = 0 then return
    slots = [{ slot: "picks", title: "Top picks for you", k: "", n: "" }]
    for each title in TasteBecause(history, 2)
        slots.Push({ slot: title.k, title: "Because you watched " + title.n, k: title.k, n: title.n })
    end for
    for each slot in slots
        row = root.CreateChild("ContentNode")
        row.title = slot.title
        for i = 0 to 7
            MakeItem(row, { placeholder: true })
        end for
        m.personal.Push({ slot: slot.slot, row: row, k: slot.k, n: slot.n })
    end for
end sub

sub askPicks()
    if m.personal.Count() = 0 then return
    ' Only with a stored library: building one asks the provider for every category.
    if m.global.search = invalid and not LibrarySaved() then return
    because = []
    list = []
    for each entry in m.personal
        if entry.slot = "list" then
            list = MyList()
        else if entry.slot <> "picks" then
            because.Push({ k: entry.k, n: entry.n })
        end if
    end for
    m.picksKey = m.generation.ToStr() + ":" + NowSeconds().ToStr()
    task = LibraryTask()
    if not m.watchingPicks then
        m.watchingPicks = true
        task.ObserveFieldScoped("picked", "onPicks")
    end if
    task.picksRequest = { history: TasteHistory(), watching: ProgressList(), because: because, list: list, forKey: m.picksKey }
end sub

' The library worker's answer: plain lists of fields (answerPicks), made into rows here
' and put in place of the placeholders.
sub onPicks(event as Object)
    picked = event.GetData()
    if not IsAA(picked) or FieldStr(picked, "forKey") <> m.picksKey then return
    ' Kept to order the rows next time (TasteOrder).
    TasteSaveScores(picked.scores)
    root = m.rows.content
    answers = Field(picked, "rows")
    if root <> invalid and IsArr(answers) then
        for each answer in answers
            for each entry in m.personal
                if entry.row <> invalid and entry.slot = FieldStr(answer, "slot") then
                    index = indexOfRow(root, entry.row)
                    items = Field(answer, "items")
                    if index >= 0 and IsArr(items) and items.Count() > 0 then
                        row = CreateObject("roSGNode", "ContentNode")
                        row.title = entry.row.title
                        for each values in items
                            MakeItem(row, values)
                        end for
                        root.ReplaceChild(row, index)
                        entry.row = row
                    else if index >= 0 and entry.slot <> "list" then
                        ' Nothing to pick: the row goes.
                        removeRow(root, index)
                        entry.row = invalid
                    end if
                end if
            end for
        end for
        refreshHero()
    end if
end sub

' Takes a row off, keeping the focus on the same poster when it was below.
sub removeRow(root as Object, index as Integer)
    root.RemoveChildIndex(index)
    focus = m.rows.rowItemFocused
    if focus <> invalid and focus.Count() > 1 and focus[0] > index then m.rows.jumpToRowItem = [focus[0] - 1, focus[1]]
end sub

' My List changed (on Details, or with * here): its row follows, under Continue
' Watching, keeping the pictures it had and the focus on the same poster.
sub syncListRow()
    root = m.rows.content
    if m.tab <> 0 or root = invalid then return
    list = MyList()
    stamp = FormatJson(list)
    if stamp = m.listStamp then return
    m.listStamp = stamp
    entry = invalid
    for each candidate in m.personal
        if candidate.slot = "list" then entry = candidate
    end for
    old = invalid
    if entry <> invalid then old = entry.row
    oldIndex = -1
    if old <> invalid then oldIndex = indexOfRow(root, old)
    if list.Count() = 0 then
        if oldIndex >= 0 then removeRow(root, oldIndex)
        if entry <> invalid then entry.row = invalid
        return
    end if
    posters = {}
    if old <> invalid then
        for i = 0 to old.GetChildCount() - 1
            child = old.GetChild(i)
            posters[TitleKey(child)] = child.HDPosterUrl
        end for
    end if
    row = MyListRow(list, posters)
    if oldIndex >= 0 then
        root.ReplaceChild(row, oldIndex)
    else
        index = 0
        if root.GetChildCount() > 0 and root.GetChild(0).HasField("isContinue") then index = 1
        root.InsertChild(row, index)
        focus = m.rows.rowItemFocused
        if focus <> invalid and focus.Count() > 1 and focus[0] >= index then m.rows.jumpToRowItem = [focus[0] + 1, focus[1]]
    end if
    if entry = invalid then
        m.personal.Unshift({ slot: "list", row: row, k: "", n: "" })
    else
        entry.row = row
    end if
end sub

' --- Continue Watching ---------------------------------------------------------------

' The focused poster when it's in the Continue Watching row, else invalid.
function continueItem() as Dynamic
    root = m.rows.content
    focus = m.rows.rowItemFocused
    if root = invalid or focus = invalid or focus.Count() < 2 or focus[0] <> 0 then return invalid
    row = root.GetChild(0)
    if row = invalid or not row.HasField("isContinue") then return invalid
    return row.GetChild(focus[1])
end function

' * on a poster: My List, a rating, and on Continue Watching taking it off; Account
' last, since * on a poster no longer opens it.
sub showTitleMenu(item as Object)
    key = TitleKey(item)
    m.menuItem = item
    m.menuActions = []
    labels = []
    if MyListHas(key) then
        labels.Push("Remove from My List")
    else
        labels.Push("Add to My List")
    end if
    m.menuActions.Push("list")
    rating = TasteRating(key)
    if rating = 0 then
        labels.Push("Rate it")
    else
        labels.Push("Rated: " + TasteRatingLabel(rating))
    end if
    m.menuActions.Push("rate")
    cw = continueItem()
    if cw <> invalid and cw.IsSameNode(item) then
        labels.Push("Remove from Continue Watching")
        m.menuActions.Push("forget")
    end if
    labels.Push("Account")
    m.menuActions.Push("account")
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = item.title
    dialog.buttons = labels
    dialog.ObserveField("buttonSelected", "onTitleMenuButton")
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onTitleMenuButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    choice = dialog.buttonSelected
    item = m.menuItem
    if item = invalid or choice < 0 or choice >= m.menuActions.Count() then return
    action = m.menuActions[choice]
    key = TitleKey(item)
    if action = "rate" then
        ' The rating choice opens as this menu closes (onDialogClosed).
        m.nextDialog = "rate"
    else if action = "account" then
        m.nextDialog = "account"
    end if
    dialog.close = true
    if action = "list" then
        Sound("select")
        MyListToggle(key, item.title, item.ext)
        syncListRow()
        askPicks()
    else if action = "forget" then
        ' Taken off early, it counts against what it's like.
        TasteNotForMe(key, item.progress)
        ProgressRemove(key)
        refreshContinueWatching()
        m.top.action = { name: "syncNow" }
    end if
end sub

' "Not for me", "I like this" or "Love this!": shapes Top picks, Because you watched and
' the order of the rows (common/Taste.brs).
sub showRateMenu(item as Object)
    m.menuItem = item
    rating = TasteRating(TitleKey(item))
    m.rateChoices = [-1, 1, 2]
    labels = ["Not for me", "I like this", "Love this!"]
    if rating <> 0 then
        labels.Push("Take my rating away")
        m.rateChoices.Push(0)
    end if
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = item.title
    dialog.message = ["How was it? Your ratings shape Top picks for you and the rows you see first."]
    dialog.buttons = labels
    dialog.ObserveField("buttonSelected", "onRateButton")
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onRateButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    choice = dialog.buttonSelected
    dialog.close = true
    item = m.menuItem
    if item = invalid or choice < 0 or choice >= m.rateChoices.Count() then return
    Sound("select")
    TasteRate(TitleKey(item), item.title, m.rateChoices[choice])
    askPicks()
end sub

' --- Account -----------------------------------------------------------------

sub showAccountMenu()
    creds = m.global.creds
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Account"
    dialog.message = ["Signed in as " + FieldStr(creds, "username") + " on " + FieldStr(creds, "server") + "."]
    sounds = "Turn click sounds off"
    if not m.global.soundsOn then sounds = "Turn click sounds on"
    intro = "Turn the intro off"
    if FieldStr(LoadPrefs(), "intro") = "off" then intro = "Turn the intro on"
    dialog.buttons = ["Keep watching", "Online subtitles", sounds, intro, "Change server address", "Sign out"]
    dialog.ObserveField("buttonSelected", "onAccountButton")
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onAccountButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    choice = dialog.buttonSelected
    ' The address keyboard opens as this menu closes (onDialogClosed).
    if choice = 4 then m.nextDialog = "server"
    dialog.close = true
    if choice = 1 then m.top.action = { name: "openSubtitleSetup" }
    if choice = 2 then
        ' Saved on this Roku; MainScene plays them only while they're on.
        turnOn = not m.global.soundsOn
        m.global.soundsOn = turnOn
        if turnOn then
            SavePref("sounds", "on")
            Sound("select")
        else
            SavePref("sounds", "off")
        end if
    end if
    if choice = 3 then
        if FieldStr(LoadPrefs(), "intro") = "off" then
            SavePref("intro", "on")
        else
            SavePref("intro", "off")
        end if
    end if
    if choice = 5 then m.top.action = { name: "signOut" }
end sub

' --- A new server address --------------------------------------------------------------
'
' Providers move to new addresses now and then. Changing it here, rather than signing
' out, keeps everything: the new address is checked with a sign-in first, then the same
' account carries on there, Continue Watching following from the old address (NoteLogin
' in Registry.brs, MainScene's signedIn).

sub showServerKeyboard(text as String)
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "Server address"
    dialog.message = ["Your provider's new address, like http://example.com:8080. Your account, Continue Watching, My List and ratings stay."]
    dialog.text = text
    dialog.buttons = ["Check and save", "Cancel"]
    dialog.textEditBox.maxTextLength = 256
    dialog.ObserveField("buttonSelected", "onServerButton")
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onServerButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    choice = dialog.buttonSelected
    typed = dialog.text
    server = NormalizeServer(typed)
    creds = m.global.creds
    if choice = 0 and server <> "" and LCase(server) <> LCase(FieldStr(creds, "server")) then
        m.serverTyped = typed
        m.nextDialog = "checking"
        m.serverTask = CreateObject("roSGNode", "XtreamTask")
        m.serverTask.request = { mode: "auth", creds: { server: server, username: FieldStr(creds, "username"), password: FieldStr(creds, "password") } }
        m.serverTask.ObserveField("result", "onServerChecked")
        m.serverTask.control = "RUN"
    end if
    dialog.close = true
end sub

sub showServerChecking()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Server address"
    dialog.message = ["Checking the new address…"]
    dialog.buttons = ["Cancel"]
    dialog.ObserveField("buttonSelected", "onServerCancel")
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onServerCancel()
    if m.serverTask <> invalid then
        m.serverTask.UnobserveField("result")
        m.serverTask = invalid
    end if
    dialog = m.top.GetScene().dialog
    if dialog <> invalid then dialog.close = true
end sub

sub onServerChecked(event as Object)
    result = event.GetData()
    if m.serverTask = invalid then return
    m.serverTask.UnobserveField("result")
    m.serverTask = invalid
    dialog = m.top.GetScene().dialog
    if IsAA(result) and result.ok = true then
        ' A "Checking" box still to open (the check was quick) doesn't.
        m.nextDialog = ""
        if dialog <> invalid then dialog.close = true
        creds = result.request.creds
        SaveCreds(creds)
        ' Home starts again at the new address, keeping everything.
        m.top.action = { name: "signedIn", creds: creds }
        return
    end if
    m.serverError = "That address didn't work. " + FieldStr(result, "error")
    m.nextDialog = "serverFailed"
    if dialog <> invalid then dialog.close = true
end sub

sub showServerFailed()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Server address"
    dialog.message = [m.serverError, "Nothing has changed: ARAN+ still uses " + FieldStr(m.global.creds, "server") + "."]
    dialog.buttons = ["Try again", "Cancel"]
    dialog.ObserveField("buttonSelected", "onServerFailedButton")
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onServerFailedButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    if dialog.buttonSelected = 0 then m.nextDialog = "serverAgain"
    dialog.close = true
end sub

' A menu that opens another (Rate it, Account) opens it once it has closed.
sub onDialogClosed()
    following = m.nextDialog
    m.nextDialog = ""
    if following = "rate" and m.menuItem <> invalid then
        showRateMenu(m.menuItem)
        return
    else if following = "account" then
        showAccountMenu()
        return
    else if following = "server" then
        showServerKeyboard(FieldStr(m.global.creds, "server"))
        return
    else if following = "serverAgain" then
        showServerKeyboard(m.serverTyped)
        return
    else if following = "checking" then
        showServerChecking()
        return
    else if following = "serverFailed" then
        showServerFailed()
        return
    end if
    restoreFocus()
end sub

sub showLoadError()
    m.failed = true
    text = "Couldn't load your library. " + m.lastError
    if Instr(1, m.lastError, "refused") > 0 then text = text + " The provider may have moved to a new address (ask them, then sign out with * and back in), the trial may have ended, or they may be blocking your connection for a while."
    m.status.text = text + " Press OK to try again."
    clearHero()
    focusNav()
end sub

sub onSyncedElsewhere()
    if m.tab = 0 and m.rows.content <> invalid and m.rows.content.GetChildCount() > 0 then refreshContinueWatching()
end sub
