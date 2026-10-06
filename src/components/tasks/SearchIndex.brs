' In-memory title index for search. Names and records are parallel arrays of plain
' strings (not associative arrays) to keep memory low on catalogs of tens of thousands.
'
' names[i]    " " + NormalizeSearch(title), the leading space marks a word start
' records[i]  kind letter, id, ext, poster URL, title, category id, date added (seconds),
'             year, joined by Chr(30); "-" for blanks
'
' categories holds the provider's categories ({ key, kind, id, name, label, norm, count }),
' so search can offer them and a category's page can list all its titles from here,
' without asking the provider.

function NewSearchIndex() as Object
    return { names: [], records: [], seen: {}, savedAt: 0, categories: [], catIndex: {} }
end function

' Records the provider's categories for one kind ("vod" or "series"): a list of
' { id, name } as ParseCategories returns. Labels come from ClassifyCategory.
sub IndexSetCategories(index as Object, kind as String, list as Object, year as Integer)
    letter = "m"
    if kind = "series" then letter = "s"
    for each category in list
        addCategory(index, letter + ":" + FieldStr(category, "id"), kind, FieldStr(category, "id"), FieldStr(category, "name"), 0, year)
    end for
end sub

sub addCategory(index as Object, key as String, kind as String, id as String, name as String, count as Integer, year as Integer)
    if id = "" or index.catIndex.DoesExist(key) then return
    label = ClassifyCategory(name, year).label
    index.catIndex[key] = index.categories.Count()
    index.categories.Push({ key: key, kind: kind, id: id, name: name, label: label, norm: " " + NormalizeSearch(label), count: count })
end sub

function searchSeparator() as String
    return Chr(30)
end function

' Adds a get_vod_streams or get_series response. kind is "vod" or "series". With
' `allowed` (category id -> true), titles in other categories are left out: the
' whole-library answer also holds the adult categories that ParseCategories hides.
' fallbackCategory is the category the list was asked for, for titles that don't say.
sub IndexAdd(index as Object, data as Dynamic, kind as String, allowed = invalid as Dynamic, fallbackCategory = "" as String)
    if not IsArr(data) then return
    letter = "m"
    idField = "stream_id"
    iconField = "stream_icon"
    addedField = "added"
    if kind = "series" then
        letter = "s"
        idField = "series_id"
        iconField = "cover"
        addedField = "last_modified"
    end if
    sep = searchSeparator()
    for each raw in data
        if IsAA(raw) and ToInt(raw.is_adult) <> 1 and inCategories(raw, allowed) then
            id = FieldStr(raw, idField)
            key = letter + id
            if id <> "" and not index.seen.DoesExist(key) then
                index.seen[key] = true
                named = SplitTitle(FieldStr(raw, "name"))
                title = named.title
                year = YearOf(FirstText([Field(raw, "year"), Field(raw, "releaseDate"), Field(raw, "release_date")]))
                if year = "" then year = named.year
                category = FieldStr(raw, "category_id")
                if category = "" then category = fallbackCategory
                index.names.Push(" " + NormalizeSearch(title))
                index.records.Push(letter + sep + id + sep + orDash(FieldStr(raw, "container_extension")) + sep + orDash(FieldStr(raw, iconField)) + sep + orDash(title) + sep + orDash(category) + sep + ToInt(raw[addedField]).ToStr() + sep + orDash(year))
                position = index.catIndex[letter + ":" + category]
                if position <> invalid then index.categories[position].count = index.categories[position].count + 1
            end if
        end if
    end for
end sub

function inCategories(raw as Object, allowed as Dynamic) as Boolean
    if not IsAA(allowed) then return true
    category = FieldStr(raw, "category_id")
    return category = "" or allowed.DoesExist(category)
end function

function orDash(text as String) as String
    if text = "" then return "-"
    return text
end function

function fromDash(text as String) as String
    if text = "-" then return ""
    return text
end function

' Best matches as a ContentNode with up to two rows, Movies and Series, of `limit` each.
' Every word typed must appear in the title. Titles starting with the query rank first,
' then titles where it starts a word, then the rest; shorter titles first within each.
'
' Every match in the whole library is ranked (there is no cap on how many are looked
' at), and movies and series are ranked separately, so a short query that matches
' thousands of movies can't push the series out. One or two letters only match the
' start of a word: "th" finds "The Office" but not "Other", which keeps typing quick.
function IndexSearch(index as Object, query as String, limit as Integer) as Object
    root = CreateObject("roSGNode", "ContentNode")
    q = NormalizeSearch(query)
    if q = "" then return root
    words = []
    for each word in q.Split(" ")
        if word <> "" then words.Push(word)
    end for
    phrase = " " + q
    shortQuery = Len(q) < 3

    ' One number per match (rank, then title length, then position in the index), which
    ' sorts the right way and takes far less memory than an object per match.
    scale = searchScale()
    movieKeys = []
    seriesKeys = []
    names = index.names
    records = index.records
    for i = 0 to names.Count() - 1
        name = names[i]
        if shortQuery then
            matched = Instr(1, name, phrase) > 0
        else
            matched = true
            for each word in words
                if Instr(1, name, word) = 0 then
                    matched = false
                    exit for
                end if
            end for
        end if
        if matched then
            rank = 2
            if Left(name, Len(phrase)) = phrase then
                rank = 0
            else if Instr(1, name, phrase) > 0 then
                rank = 1
            end if
            size = Len(name)
            if size > 999 then size = 999
            key = (rank * 1000 + size) * scale + i
            if Left(records[i], 1) = "s" then
                seriesKeys.Push(key)
            else
                movieKeys.Push(key)
            end if
        end if
    end for

    categories = categoryRow(index, words, phrase, shortQuery)
    if categories.GetChildCount() > 0 then root.AppendChild(categories)
    movies = searchRow(index, movieKeys, "Movies", "movie", limit)
    series = searchRow(index, seriesKeys, "Series", "series", limit)
    if movies.GetChildCount() > 0 then root.AppendChild(movies)
    if series.GetChildCount() > 0 then root.AppendChild(series)
    return root
end function

' Categories whose tidy name matches, like "Punjabi" for "punj": names starting with
' the query first, then the biggest. Each opens a page of all its titles.
function categoryRow(index as Object, words as Object, phrase as String, shortQuery as Boolean) as Object
    row = CreateObject("roSGNode", "ContentNode")
    row.title = "Categories"
    matches = []
    for each category in index.categories
        norm = category.norm
        matched = category.count > 0
        if matched and shortQuery then
            matched = Instr(1, norm, phrase) > 0
        else if matched then
            for each word in words
                if Instr(1, norm, word) = 0 then
                    matched = false
                    exit for
                end if
            end for
        end if
        if matched then
            rank = 1
            if Left(norm, Len(phrase)) = phrase then rank = 0
            ' Bigger categories first within a rank; counts stay below a million.
            matches.Push({ order: rank * 1000000 + (999999 - category.count), category: category })
        end if
    end for
    matches.SortBy("order")
    for each match in matches
        if row.GetChildCount() >= 20 then exit for
        category = match.category
        kindName = "Movies"
        if category.kind = "series" then kindName = "Series"
        MakeItem(row, { kind: "category", title: category.label, caption: kindName + " · " + category.count.ToStr(), categoryId: category.id, listKind: category.kind })
    end for
    return row
end function

' All titles of one category, newest first, as a ContentNode of items (up to `limit`).
' Its `total` field holds how many the category has. With a query, only titles whose
' name holds every word typed, best matches first (names starting with it, then words
' starting with it), newest first among equals; `total` is then the number of matches.
function IndexBrowse(index as Object, kind as String, categoryId as String, limit as Integer, query = "" as String) as Object
    letter = "m"
    itemKind = "movie"
    if kind = "series" then
        letter = "s"
        itemKind = "series"
    end if
    sep = searchSeparator()
    marker = sep + categoryId + sep
    q = NormalizeSearch(query)
    words = []
    for each word in q.Split(" ")
        if word <> "" then words.Push(word)
    end for
    phrase = " " + q
    found = []
    records = index.records
    names = index.names
    for i = 0 to records.Count() - 1
        record = records[i]
        ' A quick look for the id before splitting keeps big libraries fast.
        if Left(record, 1) = letter and Instr(1, record, marker) > 0 and nameMatches(names[i], words, phrase) then
            parts = record.Split(sep)
            if parts.Count() >= 7 and parts[5] = categoryId then
                ' Newest first: a negated date sorts the latest to the top. With a query,
                ' the match's rank (in tens of billions) comes before the date.
                order = 0# - parts[6].ToInt()
                if q <> "" then order = order + matchRank(names[i], phrase) * 10000000000#
                found.Push({ order: order, parts: parts })
            end if
        end if
    end for
    found.SortBy("order")
    list = CreateObject("roSGNode", "ContentNode")
    list.AddFields({ total: found.Count() })
    for each match in found
        if list.GetChildCount() >= limit then exit for
        addSearchItem(list, match.parts, itemKind)
    end for
    return list
end function

' Every word typed appears in the name; one or two letters only at the start of a word.
function nameMatches(name as String, words as Object, phrase as String) as Boolean
    if words.Count() = 0 then return true
    if Len(phrase) < 4 then return Instr(1, name, phrase) > 0
    for each word in words
        if Instr(1, name, word) = 0 then return false
    end for
    return true
end function

' 0 when the name starts with the query, 1 when a word does, 2 otherwise.
function matchRank(name as String, phrase as String) as Integer
    if Left(name, Len(phrase)) = phrase then return 0
    if Instr(1, name, phrase) > 0 then return 1
    return 2
end function

' Positions in the index stay below this, so they fit in the low digits of a match key.
function searchScale() as Double
    return 10000000#
end function

function searchRow(index as Object, keys as Object, title as String, kind as String, limit as Integer) as Object
    row = CreateObject("roSGNode", "ContentNode")
    row.title = title
    keys.Sort()
    scale = searchScale()
    sep = searchSeparator()
    for each key in keys
        if row.GetChildCount() >= limit then exit for
        position = Int(key - Int(key / scale) * scale)
        parts = index.records[position].Split(sep)
        if parts.Count() >= 5 then addSearchItem(row, parts, kind)
    end for
    return row
end function

sub addSearchItem(row as Object, parts as Object, kind as String)
    MakeItem(row, searchItemValues(parts, kind))
end sub

' A title's fields for MakeItem, from its record.
function searchItemValues(parts as Object, kind as String) as Object
    ext = fromDash(parts[2])
    values = {
        title: fromDash(parts[4])
        HDPosterUrl: SizedImage(fromDash(parts[3]), "w185")
        kind: kind
        itemId: parts[1]
        ext: ext
        problem: containerProblem(ext)
    }
    if kind = "series" then values.seriesId = parts[1]
    if parts.Count() >= 8 then values.year = fromDash(parts[7])
    return values
end function

' --- Picked for you -----------------------------------------------------------------
'
' Home's My List, "Top picks for you" and "Because you watched" rows, from the stored
' library and what you watch (common/Taste.brs), so nothing is asked of the provider.
' Two passes over the library: one to find the titles named (IndexFind), one to pick
' (IndexPersonal). The rows go back to Home as plain lists of fields, and Home makes
' them into rows itself.

' The records of the titles in `keys` ("m:<id>" or "s:<id>"): { "m:123": parts }.
' Titles the library doesn't hold (other languages) are left out.
function IndexFind(index as Object, keys as Object) as Object
    sep = searchSeparator()
    wanted = {}
    for each key in keys
        if Len(key) > 2 then wanted[Left(key, 1) + sep + Mid(key, 3) + sep] = key
    end for
    found = {}
    if wanted.Count() = 0 then return found
    for each record in index.records
        cut = Instr(3, record, sep)
        if cut > 0 then
            key = wanted[Left(record, cut)]
            if key <> invalid and not found.DoesExist(key) then found[key] = record.Split(sep)
        end if
    end for
    return found
end function

' Each found title's category: { "m:123": "vod:12" }.
function CategoriesFrom(found as Object) as Object
    out = {}
    for each key in found
        parts = found[key]
        if parts.Count() >= 6 and parts[5] <> "-" then
            kind = "vod"
            if parts[0] = "s" then kind = "series"
            out[key] = kind + ":" + parts[5]
        end if
    end for
    return out
end function

' My List's row as fields, in its order: from the library when it holds the title, else
' its name card (MyListValues).
function ListItems(list as Object, found as Object) as Object
    items = []
    for each entry in list
        parts = found[FieldStr(entry, "k")]
        if parts <> invalid and parts.Count() >= 5 then
            kind = "movie"
            if parts[0] = "s" then kind = "series"
            items.Push(searchItemValues(parts, kind))
        else
            items.Push(MyListValues(entry, ""))
        end if
    end for
    return items
end function

' "Top picks for you" and the "Because you watched" rows, in one pass over the library.
' Returns { picks: [fields], because: [[fields], ...] } (one list for each of `because`).
'
' Top picks: titles from the 6 categories you like most (`scores`, LikingFrom), the more
' liked and the newer the higher, at most 8 from one category, 30 in all.
' Because you watched (`because`: [{ k, n, category }]): first the same series of films
' (titles starting with the same words, like "Carry On Jatta 2" after "Carry On Jatta"),
' then the newest from its category, 20 in all.
' Each title once in a row, and none you've watched: `exclude` holds their keys ("m:123")
' and their names as the index writes them (" carry on jatta"), for their other copies.
function IndexPersonal(index as Object, scores as Object, exclude as Object, because as Object, now as Integer) as Object
    sep = searchSeparator()
    ' The liked categories, each as a share of the most liked one.
    ranked = []
    for each key in scores
        if TasteNumber(scores[key]) > 0 then ranked.Push({ order: 0 - TasteNumber(scores[key]), key: key })
    end for
    ranked.SortBy("order")
    top = {}
    markers = { m: [], s: [] }
    if ranked.Count() > 0 then
        best = 0 - ranked[0].order
        for each item in ranked
            if top.Count() >= 6 then exit for
            top[item.key] = (0 - item.order) / best
            cut = Instr(1, item.key, ":")
            letter = "m"
            if Left(item.key, cut - 1) = "series" then letter = "s"
            markers[letter].Push(sep + Mid(item.key, cut + 1) + sep)
        end for
    end if
    titles = []
    for each title in because
        category = FieldStr(title, "category")
        cut = Instr(1, category, ":")
        id = Mid(category, cut + 1)
        titles.Push({ k: FieldStr(title, "k"), letter: Left(FieldStr(title, "k"), 1), id: id, marker: sep + id + sep, stem: titleStem(FieldStr(title, "n")), own: " " + NormalizeSearch(FieldStr(title, "n")), found: [] })
    end for

    picked = []
    records = index.records
    names = index.names
    for i = 0 to records.Count() - 1
        record = records[i]
        letter = Left(record, 1)
        parts = invalid
        ' A quick look for an id before splitting keeps big libraries fast.
        wanted = markers[letter]
        if wanted <> invalid then
            for each marker in wanted
                if Instr(1, record, marker) > 0 then
                    parts = record.Split(sep)
                    exit for
                end if
            end for
            if parts <> invalid and parts.Count() >= 7 then
                kind = "vod"
                if letter = "s" then kind = "series"
                liking = top[kind + ":" + parts[5]]
                if liking <> invalid and not exclude.DoesExist(letter + ":" + parts[1]) then
                    picked.Push({ order: 0 - liking * freshness(parts, now), at: i, category: kind + ":" + parts[5] })
                end if
            end if
        end if
        for each title in titles
            if title.letter = letter then
                family = title.stem <> "" and Left(names[i], Len(title.stem)) = title.stem
                if family or Instr(1, record, title.marker) > 0 then
                    if parts = invalid then parts = record.Split(sep)
                    if parts.Count() >= 7 then
                        key = letter + ":" + parts[1]
                        if key <> title.k and not exclude.DoesExist(key) and (family or parts[5] = title.id) then
                            ' The family first (in tens of billions), then the newest.
                            order = 0# - parts[6].ToInt()
                            if not family then order = order + 10000000000#
                            title.found.Push({ order: order, at: i })
                        end if
                    end if
                end if
            end if
        end for
    end for

    out = { picks: [], because: [] }
    picked.SortBy("order")
    perCategory = {}
    seen = {}
    for each match in picked
        if out.picks.Count() >= 30 then exit for
        name = names[match.at]
        taken = TasteNumber(perCategory[match.category])
        if taken < 8 and not seen.DoesExist(name) and not exclude.DoesExist(name) then
            seen[name] = true
            perCategory[match.category] = taken + 1
            out.picks.Push(recordValues(records[match.at]))
        end if
    end for
    for each title in titles
        items = []
        title.found.SortBy("order")
        seen = {}
        seen[title.own] = true
        for each match in title.found
            if items.Count() >= 20 then exit for
            name = names[match.at]
            if not seen.DoesExist(name) and not exclude.DoesExist(name) then
                seen[name] = true
                items.Push(recordValues(records[match.at]))
            end if
        end for
        out.because.Push(items)
    end for
    return out
end function

function recordValues(record as String) as Object
    parts = record.Split(searchSeparator())
    kind = "movie"
    if parts[0] = "s" then kind = "series"
    return searchItemValues(parts, kind)
end function

' How new a title is, from 1 (just added) down towards 0: halving every 90 days since
' it was added, or by its year when the date is missing.
function freshness(parts as Object, now as Integer) as Float
    added = parts[6].ToInt()
    if added > 0 then
        days = (now - added) / 86400
        if days < 0 then days = 0
        return 0.5 ^ (days / 90)
    end if
    year = 0
    if parts.Count() >= 8 then year = fromDash(parts[7]).ToInt()
    thisYear = CreateObject("roDateTime").GetYear()
    if year >= thisYear - 1 then return 0.5
    return 0.1
end function

' The start of a title that its sequels share: its first two words (a leading "the" or
' "a" aside), or its one word when it has only one of four letters or more, as the
' index writes names (" carry on"); "" when there's nothing distinctive.
function titleStem(name as String) as String
    words = []
    for each word in NormalizeSearch(name).Split(" ")
        if word <> "" then words.Push(word)
    end for
    if words.Count() > 1 and (words[0] = "the" or words[0] = "a" or words[0] = "an") then words.Shift()
    if words.Count() >= 2 then return " " + words[0] + " " + words[1]
    if words.Count() = 1 and Len(words[0]) >= 4 then return " " + words[0]
    return ""
end function

' --- Keeping the index between launches ---------------------------------------------
'
' Loading a whole library from the provider takes minutes, so a finished index is
' saved and searched straight away on later launches (SearchTask refreshes it in the
' background once it's a day old). The file is a header line (format, owner, time
' saved, title count, category count), then every name, then every record, then every
' category (key, kind, id, title count, name; tab-separated), one per line.

function searchFileFormat() as String
    return "aranplus-search-4"
end function

function SaveSearchIndex(index as Object, path as String, owner as String, savedAt as Integer) as Boolean
    count = index.names.Count()
    if count = 0 then return false
    gap = Chr(9)
    lines = [searchFileFormat() + gap + owner + gap + savedAt.ToStr() + gap + count.ToStr() + gap + index.categories.Count().ToStr()]
    lines.Append(index.names)
    breaks = CreateObject("roRegex", "[\r\n\t]", "")
    for each record in index.records
        if Instr(1, record, Chr(10)) > 0 or Instr(1, record, Chr(13)) > 0 then record = breaks.ReplaceAll(record, " ")
        lines.Push(record)
    end for
    for each category in index.categories
        lines.Push(category.key + gap + category.kind + gap + category.id + gap + category.count.ToStr() + gap + breaks.ReplaceAll(category.name, " "))
    end for
    return WriteAsciiFile(path, lines.Join(Chr(10)))
end function

' The saved index for `owner` (with savedAt set), or invalid.
function LoadSearchIndex(path as String, owner as String) as Dynamic
    text = ReadAsciiFile(path)
    if text = "" then return invalid
    lines = text.Split(Chr(10))
    header = lines[0].Split(Chr(9))
    ' Format 3 is the same without years; its titles show none until the next refresh.
    if header.Count() < 5 or (header[0] <> searchFileFormat() and header[0] <> "aranplus-search-3") or header[1] <> owner then return invalid
    count = header[3].ToInt()
    catCount = header[4].ToInt()
    if count <= 0 or lines.Count() <> 1 + count * 2 + catCount then return invalid
    index = NewSearchIndex()
    index.savedAt = header[2].ToInt()
    for i = 1 to count
        index.names.Push(lines[i])
        index.records.Push(lines[count + i])
    end for
    year = CreateObject("roDateTime").GetYear()
    for i = 1 to catCount
        fields = lines[count * 2 + i].Split(Chr(9))
        if fields.Count() >= 5 then addCategory(index, fields[0], fields[1], fields[2], fields[4], fields[3].ToInt(), year)
    end for
    return index
end function
