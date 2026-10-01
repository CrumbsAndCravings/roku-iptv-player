' In-memory title index for search. Names and records are parallel arrays of plain
' strings (not associative arrays) to keep memory low on catalogs of tens of thousands.
'
' names[i]    " " + NormalizeSearch(title), the leading space marks a word start
' records[i]  kind letter, id, ext, poster URL, title, category id, date added (seconds)
'             joined by Chr(30); "-" for blanks
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
                title = FieldStr(raw, "name")
                category = FieldStr(raw, "category_id")
                if category = "" then category = fallbackCategory
                index.names.Push(" " + NormalizeSearch(title))
                index.records.Push(letter + sep + id + sep + orDash(FieldStr(raw, "container_extension")) + sep + orDash(FieldStr(raw, iconField)) + sep + orDash(title) + sep + orDash(category) + sep + ToInt(raw[addedField]).ToStr())
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
' Its `total` field holds how many the category has.
function IndexBrowse(index as Object, kind as String, categoryId as String, limit as Integer) as Object
    letter = "m"
    itemKind = "movie"
    if kind = "series" then
        letter = "s"
        itemKind = "series"
    end if
    sep = searchSeparator()
    marker = sep + categoryId + sep
    found = []
    records = index.records
    for i = 0 to records.Count() - 1
        record = records[i]
        ' A quick look for the id before splitting keeps big libraries fast.
        if Left(record, 1) = letter and Instr(1, record, marker) > 0 then
            parts = record.Split(sep)
            ' Newest first: a negated date sorts the latest to the top.
            if parts.Count() >= 7 and parts[5] = categoryId then found.Push({ order: 0# - parts[6].ToInt(), parts: parts })
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
    MakeItem(row, values)
end sub

' --- Keeping the index between launches ---------------------------------------------
'
' Loading a whole library from the provider takes minutes, so a finished index is
' saved and searched straight away on later launches (SearchTask refreshes it in the
' background once it's a day old). The file is a header line (format, owner, time
' saved, title count, category count), then every name, then every record, then every
' category (key, kind, id, title count, name; tab-separated), one per line.

function searchFileFormat() as String
    return "aranplus-search-2"
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
    if header.Count() < 5 or header[0] <> searchFileFormat() or header[1] <> owner then return invalid
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
