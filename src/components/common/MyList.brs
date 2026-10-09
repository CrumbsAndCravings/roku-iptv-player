' My List: titles you've saved to watch later (+ My List on Details, or * on a poster on
' Home). Kept in the registry (mylist/items), newest first, at most MyListMax(), small
' on purpose since the registry holds about 16 KB for everything: no pictures, which
' the library stored on the Roku supplies (ListItems in tasks/SearchIndex.brs).
' Tested in tests/parse_test.brs.
'
' Entries: { k: "m:<streamId>" | "s:<seriesId>", n: name, x: container extension
' (movies), t: when added (seconds) }

function MyListMax() as Integer
    return 40
end function

function MyList() as Object
    raw = RegRead("mylist", "items")
    list = invalid
    if raw <> invalid then list = ParseJson(raw)
    if not IsArr(list) then return []
    clean = []
    for each entry in list
        if IsAA(entry) and FieldStr(entry, "k") <> "" then clean.Push(entry)
    end for
    return clean
end function

function MyListHas(key as String) as Boolean
    for each entry in MyList()
        if FieldStr(entry, "k") = key then return true
    end for
    return false
end function

' `list` with `key` added first (`add`) or taken out.
function MyListWith(list as Object, key as String, name as String, ext as String, add as Boolean, now as Integer) as Object
    out = []
    if add then
        if Len(name) > 40 then name = Left(name, 40)
        entry = { k: key, n: name, t: now }
        if ext <> "" then entry.x = ext
        out.Push(entry)
    end if
    for each entry in list
        if FieldStr(entry, "k") <> key and out.Count() < MyListMax() then out.Push(entry)
    end for
    return out
end function

' Adds a title, or takes it out when it's there already. Returns whether it's in now.
' Adding one counts towards what you like (common/Taste.brs), as starting it would.
function MyListToggle(key as String, name as String, ext as String) as Boolean
    adding = not MyListHas(key)
    RegWrite("mylist", "items", FormatJson(MyListWith(MyList(), key, name, ext, adding, NowSeconds())))
    if adding then TasteWatched(key, name, 1)
    return adding
end function

' The row Home shows, from the list alone: name cards, with the pictures in `posters`
' ({ "m:123": url }) where they're known. The library worker's ListItems brings the
' rest.
function MyListRow(list as Object, posters as Object) as Object
    row = CreateObject("roSGNode", "ContentNode")
    row.title = "My List"
    for each entry in list
        MakeItem(row, MyListValues(entry, FieldStr(posters, FieldStr(entry, "k"))))
    end for
    return row
end function

' One title's fields for MakeItem: its name card, with `poster` when it's known.
function MyListValues(entry as Object, poster as String) as Object
    key = FieldStr(entry, "k")
    id = Mid(key, 3)
    values = { title: FieldStr(entry, "n"), kind: "movie", itemId: id, ext: FieldStr(entry, "x"), HDPosterUrl: poster }
    if Left(key, 1) = "s" then
        values.kind = "series"
        values.seriesId = id
    end if
    return values
end function

' The key of a poster's title ("m:123" or "s:45"), or "" for anything else (a category
' card, See all, a placeholder).
function TitleKey(item as Dynamic) as String
    if item = invalid then return ""
    if item.placeholder = true then return ""
    if item.kind = "movie" then return "m:" + item.itemId
    if item.kind = "series" then return "s:" + item.itemId
    return ""
end function
