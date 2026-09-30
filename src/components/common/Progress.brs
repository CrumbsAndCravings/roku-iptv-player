' Continue Watching, stored in the Roku registry (about 16KB per app) under
' section "progress". (v0.1 used "watch", which held a bogus entry from a failed play.)
' One entry per movie ("m:<streamId>") or per series ("s:<seriesId>"), newest first.
'
' Entry fields:
'   k      key          kind   "movie" | "episode"
'   id     stream or episode id to play          ext   container extension
'   name   movie or series name                  poster, bd  artwork URLs
'   pos    seconds watched                       dur   total seconds
'   sid    series id (episodes)                  season, episode, etitle

function ProgressMax() as Integer
    return 20
end function

function ProgressList() as Object
    raw = RegRead("progress", "items")
    if raw = invalid then return []
    list = ParseJson(raw)
    if not IsArr(list) then return []
    clean = []
    for each entry in list
        if IsAA(entry) and FieldStr(entry, "k") <> "" then clean.Push(entry)
    end for
    return clean
end function

function ProgressFind(key as String) as Dynamic
    for each entry in ProgressList()
        if FieldStr(entry, "k") = key then return entry
    end for
    return invalid
end function

sub ProgressPut(entry as Object)
    entry.at = NowSeconds()
    list = [entry]
    for each item in ProgressList()
        if FieldStr(item, "k") <> entry.k and list.Count() < ProgressMax() then list.Push(item)
    end for
    RegWrite("progress", "items", FormatJson(list))
end sub

sub ProgressRemove(key as String)
    list = []
    for each item in ProgressList()
        if FieldStr(item, "k") <> key then list.Push(item)
    end for
    RegWrite("progress", "items", FormatJson(list))
end sub

function ProgressFraction(entry as Dynamic) as Float
    if not IsAA(entry) then return 0.0
    dur = ToInt(entry.dur)
    if dur <= 0 then return 0.0
    fraction = ToInt(entry.pos) / dur
    if fraction > 1 then return 1.0
    return fraction
end function

' Builds the Continue Watching row, or returns invalid when there is nothing to show.
function ContinueWatchingRow() as Dynamic
    list = ProgressList()
    if list.Count() = 0 then return invalid
    row = CreateObject("roSGNode", "ContentNode")
    row.title = "Continue Watching"
    row.AddFields({ isContinue: true })
    for each entry in list
        kind = FieldStr(entry, "kind")
        caption = ""
        seriesId = ""
        itemKind = "movie"
        if kind = "episode" then
            itemKind = "series"
            seriesId = FieldStr(entry, "sid")
            caption = EpisodeCode(Field(entry, "season"), Field(entry, "episode"))
        end if
        itemId = FieldStr(entry, "id")
        if itemKind = "series" then itemId = seriesId
        MakeItem(row, {
            title: FieldStr(entry, "name")
            HDPosterUrl: FieldStr(entry, "poster")
            kind: itemKind
            itemId: itemId
            seriesId: seriesId
            ext: FieldStr(entry, "ext")
            backdrop: FieldStr(entry, "bd")
            progress: ProgressFraction(entry)
            caption: caption
        })
    end for
    return row
end function
