sub init()
    m.rows = m.top.FindNode("rows")
    m.subheading = m.top.FindNode("subheading")
    m.top.FindNode("heading").font = MakeFont("Fredoka-SemiBold", 32)
    m.subheading.font = MakeFont("Nunito-SemiBold", 16)
    m.rows.rowLabelFont = MakeFont("Fredoka-Medium", 21)
    m.counts = {}
    m.rows.ObserveField("rowItemSelected", "onSelected")
    ' Title counts come from the library stored on the Roku.
    m.task = LibraryTask()
    m.task.ObserveFieldScoped("counts", "onCounts")
end sub

sub onLists()
    build()
    m.task.countsRequest = true
end sub

sub onCounts()
    counts = m.task.counts
    if not IsAA(counts) then return
    m.counts = counts
    build()
end sub

' Rows: new releases first, then each language (in the order you chose; categories that
' don't say count as your first) with its movies and series. A language with only a few
' categories gets one row for both.
sub build()
    lists = m.top.lists
    if not IsAA(lists) then return
    langs = lists.langs
    if not IsArr(langs) then langs = []
    root = CreateObject("roSGNode", "ContentNode")
    newest = TakeTurns(pickNew(lists.vod, "vod", true), pickNew(lists.series, "series", true))
    addRow(root, "New releases", newest)

    order = []
    for each lang in langs
        order.Push(LCase(ToStr(lang)))
    end for
    for each lang in ["en", "hi", "pa", "other"]
        if not inList(order, lang) then order.Push(lang)
    end for
    first = ""
    if order.Count() > 0 then first = order[0]
    total = 0
    for each lang in order
        movies = byLanguage(lists.vod, "vod", lang, first)
        series = byLanguage(lists.series, "series", lang, first)
        name = languageName(lang)
        if movies.Count() + series.Count() <= 8 then
            movies.Append(series)
            addRow(root, name, movies)
        else
            addRow(root, name + " movies", movies)
            addRow(root, name + " series", series)
        end if
        total = total + movies.Count() + series.Count()
    end for

    focus = m.rows.rowItemFocused
    m.rows.content = root
    if focus <> invalid and focus.Count() = 2 and focus[0] < root.GetChildCount() then m.rows.jumpToRowItem = focus
    count = 0
    if IsArr(lists.vod) then count = count + lists.vod.Count()
    if IsArr(lists.series) then count = count + lists.series.Count()
    m.subheading.text = Commas(count) + " categories in your languages. OK opens one."
end sub

function pickNew(list as Dynamic, kind as String, wantNew as Boolean) as Object
    picked = []
    if not IsArr(list) then return picked
    for each category in list
        if category.isNew = wantNew then picked.Push(tile(category, kind))
    end for
    return picked
end function

function byLanguage(list as Dynamic, kind as String, lang as String, first as String) as Object
    picked = []
    if not IsArr(list) then return picked
    for each category in list
        own = FieldStr(category, "lang")
        if own = "" then own = first
        if not category.isNew and own = lang then picked.Push(tile(category, kind))
    end for
    return picked
end function

function tile(category as Object, kind as String) as Object
    kindName = "Movies"
    if kind = "series" then kindName = "Series"
    caption = kindName
    count = m.counts[kind + ":" + FieldStr(category, "id")]
    if count <> invalid and count > 0 then caption = kindName + " · " + Commas(count)
    return { title: category.label, caption: caption, categoryId: FieldStr(category, "id"), listKind: kind }
end function

sub addRow(root as Object, title as String, tiles as Object)
    if tiles.Count() = 0 then return
    row = root.CreateChild("ContentNode")
    row.title = title
    for each values in tiles
        MakeItem(row, values)
    end for
end sub

function languageName(lang as String) as String
    names = { en: "English", hi: "Hindi", pa: "Punjabi", other: "Other languages" }
    if names.DoesExist(lang) then return names[lang]
    return UCase(lang)
end function

function inList(list as Object, value as String) as Boolean
    for each entry in list
        if entry = value then return true
    end for
    return false
end function

sub onSelected()
    root = m.rows.content
    selected = m.rows.rowItemSelected
    if root = invalid or selected = invalid or selected.Count() < 2 then return
    row = root.GetChild(selected[0])
    if row = invalid then return
    item = row.GetChild(selected[1])
    if item = invalid then return
    kindName = "Movies"
    if item.listKind = "series" then kindName = "Series"
    m.top.action = { name: "openCategory", category: { kind: item.listKind, categoryId: item.categoryId, title: item.title + "  ·  " + kindName } }
end sub

sub onTakeFocus()
    m.rows.SetFocus(true)
end sub
