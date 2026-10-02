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

' Takes a title off Continue Watching and remembers when, so the removal reaches other
' devices through sync instead of their older copy bringing it back.
sub ProgressRemove(key as String)
    list = []
    for each item in ProgressList()
        if FieldStr(item, "k") <> key then list.Push(item)
    end for
    RegWrite("progress", "items", FormatJson(list))
    removed = [{ k: key, at: NowSeconds() }]
    for each gone in ProgressRemovedList()
        if gone.k <> key and removed.Count() < 100 then removed.Push(gone)
    end for
    RegWrite("progress", "removed", FormatJson(removed))
end sub

' Titles taken off Continue Watching: [{ k, at }], newest first.
function ProgressRemovedList() as Object
    raw = RegRead("progress", "removed")
    if raw = invalid then return []
    list = ParseJson(raw)
    if not IsArr(list) then return []
    clean = []
    for each gone in list
        if IsAA(gone) and FieldStr(gone, "k") <> "" then clean.Push({ k: FieldStr(gone, "k"), at: ToInt(gone.at) })
    end for
    return clean
end function

' Folds the synced state ({ entries, removed } from the sync service) into this
' device's lists. For each title the newest change wins, an entry or a removal;
' removals win ties. Returns { entries (newest first, at most ProgressMax()), removed }.
function MergeProgress(local as Object, localRemoved as Object, remote as Dynamic) as Object
    best = {}
    for each source in [local, Field(remote, "entries")]
        if IsArr(source) then
            for each entry in source
                key = FieldStr(entry, "k")
                if key <> "" then
                    known = best[key]
                    if known = invalid or ToInt(entry.at) > ToInt(known.at) then best[key] = entry
                end if
            end for
        end if
    end for
    gone = {}
    for each source in [localRemoved, Field(remote, "removed")]
        if IsArr(source) then
            for each removal in source
                key = FieldStr(removal, "k")
                if key <> "" and (gone[key] = invalid or ToInt(removal.at) > gone[key]) then gone[key] = ToInt(removal.at)
            end for
        end if
    end for

    kept = []
    for each key in best
        entry = best[key]
        if gone[key] = invalid or ToInt(entry.at) > gone[key] then kept.Push({ order: 0 - ToInt(entry.at), entry: entry })
    end for
    kept.SortBy("order")
    entries = []
    for each item in kept
        if entries.Count() < ProgressMax() then entries.Push(item.entry)
    end for

    removals = []
    for each key in gone
        removals.Push({ order: 0 - gone[key], k: key, at: gone[key] })
    end for
    removals.SortBy("order")
    removed = []
    for each item in removals
        if removed.Count() < 100 then removed.Push({ k: item.k, at: item.at })
    end for
    return { entries: entries, removed: removed }
end function

sub ProgressSave(entries as Object, removed as Object)
    RegWrite("progress", "items", FormatJson(entries))
    RegWrite("progress", "removed", FormatJson(removed))
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
