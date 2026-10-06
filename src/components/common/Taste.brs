' What you watch, so Home puts what you like first, as Netflix does. A short history
' lives in the registry (taste/history). The library worker (tasks/SearchTask.brs) turns
' it into a liking for each category, since it knows every title's category from the
' library stored on the Roku (LikingFrom here, IndexPersonal in tasks/SearchIndex.brs), and
' picks titles from there, so none of this asks the provider for anything. Home saves
' the likings (taste/scores) to order its rows. Tested in tests/parse_test.brs.
'
' History entries, newest first, at most TasteMax():
'   k   "m:<streamId>" or "s:<seriesId>"
'   n   the name, for "Because you watched" (its first 32 characters)
'   w   how much you liked it: 1 started (3 minutes in), 2 half watched, 3 finished;
'       a series gains half a point an episode, up to 4; -1 taken off Continue
'       Watching before a fifth of it
'   r   your rating, when you gave one (Details, or * on Home): -1 "Not for me",
'       1 "I like this", 2 "Love this!" (TasteRate). It counts for more than watching
'       (tasteWeight), and rated titles are the last to drop off the history.
'   t   when (seconds)

function TasteMax() as Integer
    return 30
end function

function TasteHistory() as Object
    raw = RegRead("taste", "history")
    list = invalid
    if raw <> invalid then list = ParseJson(raw)
    if not IsArr(list) then return []
    clean = []
    for each entry in list
        if IsAA(entry) and FieldStr(entry, "k") <> "" then clean.Push(entry)
    end for
    return clean
end function

' How much a movie watched so far counts: 0 under 3 minutes (a peek), then 1, and 2
' from half way. A finished one counts 3 (TasteFinished).
function TasteWeightFor(position as Integer, duration as Integer) as Float
    if position < 180 then return 0.0
    if duration > 0 and position >= duration / 2 then return 2.0
    return 1.0
end function

' `list` with `key` first and its weight changed by `mode`: "atLeast" raises it to
' `weight`, "add" adds `weight` (from 1 for a new title, at most 4), "set" sets it.
' invalid when nothing would change, so nothing is written.
function TasteWith(list as Object, key as String, name as String, weight as Float, mode as String, now as Integer) as Dynamic
    old = invalid
    for each entry in list
        if FieldStr(entry, "k") = key then
            old = entry
            exit for
        end if
    end for
    before = 0.0
    if old <> invalid then before = TasteNumber(old.w)
    after = weight
    if mode = "atLeast" then
        if old <> invalid and before >= weight then return invalid
    else if mode = "add" then
        after = 1.0
        if old <> invalid and before > 0 then after = before + weight
        if after > 4 then after = 4.0
        if old <> invalid and after = before then return invalid
    else if old <> invalid and before = weight then
        return invalid
    end if
    if name = "" and old <> invalid then name = FieldStr(old, "n")
    if Len(name) > 32 then name = Left(name, 32)
    entry = { k: key, n: name, w: after, t: now }
    if old <> invalid and ToInt(Field(old, "r")) <> 0 then entry.r = ToInt(old.r)
    return tasteFront(list, entry)
end function

' `entry` first, then the rest of `list` without its title, at most TasteMax(): when
' there are too many, the oldest title without a rating goes first.
function tasteFront(list as Object, entry as Object) as Object
    out = [entry]
    for each item in list
        if FieldStr(item, "k") <> entry.k then out.Push(item)
    end for
    while out.Count() > TasteMax()
        drop = out.Count() - 1
        for i = out.Count() - 1 to 1 step -1
            if ToInt(Field(out[i], "r")) = 0 then
                drop = i
                exit for
            end if
        end for
        out.Delete(drop)
    end while
    return out
end function

' `list` with your rating of `key` (-1, 1 or 2; 0 takes it away), the title first.
' Watching it counts as before. invalid when nothing would change.
function TasteRated(list as Object, key as String, name as String, rating as Integer, now as Integer) as Dynamic
    old = invalid
    for each entry in list
        if FieldStr(entry, "k") = key then
            old = entry
            exit for
        end if
    end for
    if old <> invalid and ToInt(Field(old, "r")) = rating then return invalid
    if old = invalid and rating = 0 then return invalid
    entry = { k: key, n: name, w: 0, t: now }
    if old <> invalid then
        entry.w = TasteNumber(old.w)
        if name = "" then entry.n = FieldStr(old, "n")
    end if
    if Len(entry.n) > 32 then entry.n = Left(entry.n, 32)
    if rating <> 0 then entry.r = rating
    return tasteFront(list, entry)
end function

' Your rating of a title: -1, 1, 2, or 0 for none.
function TasteRating(key as String) as Integer
    for each entry in TasteHistory()
        if FieldStr(entry, "k") = key then return ToInt(Field(entry, "r"))
    end for
    return 0
end function

' Rates a title (Details, or * on Home): -1 "Not for me", 1 "I like this", 2 "Love
' this!", 0 for no rating.
sub TasteRate(key as String, name as String, rating as Integer)
    if key = "" then return
    list = TasteRated(TasteHistory(), key, name, rating, NowSeconds())
    if list <> invalid then RegWrite("taste", "history", FormatJson(list))
end sub

' The words for a rating, as the buttons say it.
function TasteRatingLabel(rating as Integer) as String
    if rating = -1 then return "Not for me"
    if rating = 1 then return "I like this"
    if rating = 2 then return "Love this!"
    return "Rate"
end function

' How much a title counts towards its category: "Not for me" counts against it, more
' than leaving early does; a like adds 1.5 and a love 3 to what watching it counted
' (at least 1, so a title rated before it's watched counts too).
function tasteWeight(entry as Object) as Dynamic
    rating = ToInt(Field(entry, "r"))
    w = TasteNumber(Field(entry, "w"))
    if rating = -1 then return -3
    if rating = 1 or rating = 2 then
        if w < 1 then w = 1
        if rating = 1 then return w + 1.5
        return w + 3
    end if
    return w
end function

sub tasteChange(key as String, name as String, weight as Float, mode as String)
    if key = "" then return
    list = TasteWith(TasteHistory(), key, name, weight, mode, NowSeconds())
    if list = invalid then return
    RegWrite("taste", "history", FormatJson(list))
end sub

' A movie or series you've been watching (`weight` from TasteWeightFor; a series counts
' 1 while you watch it).
sub TasteWatched(key as String, name as String, weight as Float)
    if weight > 0 then tasteChange(key, name, weight, "atLeast")
end sub

' A movie watched to the end.
sub TasteFinished(key as String, name as String)
    tasteChange(key, name, 3, "atLeast")
end sub

' An episode watched to the end: its series counts half a point more.
sub TasteEpisodeDone(key as String, name as String)
    tasteChange(key, name, 0.5, "add")
end sub

' Taken off Continue Watching before a fifth of it was watched: not for you.
sub TasteNotForMe(key as String, fraction as Float)
    if fraction < 0.2 then tasteChange(key, "", -1, "set")
end sub

' How much you like each category, as the library worker last worked out: { "vod:12":
' 3.2, "series:7": 1.5 }. Home orders its rows by it (TasteOrder).
function TasteScores() as Object
    raw = RegRead("taste", "scores")
    scores = invalid
    if raw <> invalid then scores = ParseJson(raw)
    if not IsAA(scores) then return {}
    return scores
end function

' Keeps the categories liked most (at most 12), so it stays small.
sub TasteSaveScores(scores as Dynamic)
    if not IsAA(scores) then return
    ranked = []
    for each key in scores
        if TasteNumber(scores[key]) > 0 then ranked.Push({ order: 0 - TasteNumber(scores[key]), key: key })
    end for
    ranked.SortBy("order")
    kept = {}
    for each item in ranked
        if kept.Count() >= 12 then exit for
        kept[item.key] = Int(0 - item.order * 100) / 100
    end for
    RegWrite("taste", "scores", FormatJson(kept))
end sub

' Home's rows (plan entries { kind, categoryId, ... }) with the categories you like
' moved up: after the first `keepFirst` (new releases, so there's always something
' new near the top), those you like, most liked first, then the rest as they were.
function TasteOrder(plan as Object, scores as Object, keepFirst as Integer) as Object
    if scores.Count() = 0 then return plan
    head = []
    liked = []
    rest = []
    for i = 0 to plan.Count() - 1
        entry = plan[i]
        score = TasteNumber(scores[FieldStr(entry, "kind") + ":" + FieldStr(entry, "categoryId")])
        if i < keepFirst then
            head.Push(entry)
        else if score > 0 then
            ' Ties keep their order.
            liked.Push({ order: 0 - score * 1000 + i / 1000, entry: entry })
        else
            rest.Push(entry)
        end if
    end for
    liked.SortBy("order")
    out = head
    for each item in liked
        out.Push(item.entry)
    end for
    out.Append(rest)
    return out
end function

' A number from JSON or a field (an Integer, Float, Double or text), 0 otherwise.
function TasteNumber(value as Dynamic) as Dynamic
    kind = type(value)
    if kind = "Integer" or kind = "roInt" or kind = "roInteger" or kind = "Float" or kind = "roFloat" or kind = "Double" or kind = "roDouble" or kind = "LongInteger" or kind = "roLongInteger" then return value
    if kind = "String" or kind = "roString" then return Val(value)
    return 0
end function

' How much you like each category ("vod:12" -> 3.2): every title's weight, halving
' every 30 days, added to its category. `history` is TasteHistory()'s; `watching` is
' Continue Watching ({ k, at, pos, dur }), which also holds what you watched on your
' other devices: a title there and not in the history counts 1 (2 from half way).
' `categories` says each title's category ({ "m:123": "vod:12" }, CategoriesFrom).
function LikingFrom(history as Object, watching as Object, categories as Object, now as Integer) as Object
    weights = []
    known = {}
    for each entry in history
        key = FieldStr(entry, "k")
        known[key] = true
        weights.Push({ k: key, w: tasteWeight(entry), t: ToInt(entry.t) })
    end for
    for each entry in watching
        key = FieldStr(entry, "k")
        if key <> "" and not known.DoesExist(key) then
            w = 1
            dur = ToInt(Field(entry, "dur"))
            if dur > 0 and ToInt(Field(entry, "pos")) >= dur / 2 then w = 2
            weights.Push({ k: key, w: w, t: ToInt(Field(entry, "at")) })
        end if
    end for
    scores = {}
    for each item in weights
        category = categories[item.k]
        if category <> invalid then
            days = (now - item.t) / 86400
            if days < 0 then days = 0
            scores[category] = TasteNumber(scores[category]) + item.w * 0.5 ^ (days / 30)
        end if
    end for
    return scores
end function

' The titles to build "Because you watched" rows on, at most `count`: the latest ones
' you loved, then liked, then watched at least half of, then started; never one you
' said wasn't for you.
function TasteBecause(history as Object, count as Integer) as Object
    picked = []
    chosen = {}
    for each stage in [{ rating: 2 }, { rating: 1 }, { least: 2 }, { least: 1 }]
        for each entry in history
            if picked.Count() >= count then exit for
            key = FieldStr(entry, "k")
            rating = ToInt(Field(entry, "r"))
            fits = false
            if stage.DoesExist("rating") then
                fits = rating = stage.rating
            else
                fits = rating <> -1 and TasteNumber(entry.w) >= stage.least
            end if
            if fits and FieldStr(entry, "n") <> "" and not chosen.DoesExist(key) then
                chosen[key] = true
                picked.Push({ k: key, n: FieldStr(entry, "n") })
            end if
        end for
    end for
    return picked
end function
