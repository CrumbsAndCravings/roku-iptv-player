' In-memory title index for search. Names and records are parallel arrays of plain
' strings (not associative arrays) to keep memory low on catalogs of tens of thousands.
'
' names[i]    " " + NormalizeSearch(title), the leading space marks a word start
' records[i]  kind letter, id, ext, poster URL, title joined by Chr(30); "-" for blanks

function NewSearchIndex() as Object
    return { names: [], records: [], seen: {} }
end function

function searchSeparator() as String
    return Chr(30)
end function

' Adds a get_vod_streams or get_series response. kind is "vod" or "series".
sub IndexAdd(index as Object, data as Dynamic, kind as String)
    if not IsArr(data) then return
    letter = "m"
    idField = "stream_id"
    iconField = "stream_icon"
    if kind = "series" then
        letter = "s"
        idField = "series_id"
        iconField = "cover"
    end if
    sep = searchSeparator()
    for each raw in data
        if IsAA(raw) and ToInt(raw.is_adult) <> 1 then
            id = FieldStr(raw, idField)
            key = letter + id
            if id <> "" and not index.seen.DoesExist(key) then
                index.seen[key] = true
                title = FieldStr(raw, "name")
                index.names.Push(" " + NormalizeSearch(title))
                index.records.Push(letter + sep + id + sep + orDash(FieldStr(raw, "container_extension")) + sep + orDash(FieldStr(raw, iconField)) + sep + orDash(title))
            end if
        end if
    end for
end sub

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
function IndexSearch(index as Object, query as String, limit as Integer) as Object
    root = CreateObject("roSGNode", "ContentNode")
    q = NormalizeSearch(query)
    if q = "" then return root
    words = []
    for each word in q.Split(" ")
        if word <> "" then words.Push(word)
    end for
    phrase = " " + q

    matches = []
    names = index.names
    for i = 0 to names.Count() - 1
        name = names[i]
        matched = true
        for each word in words
            if Instr(1, name, word) = 0 then
                matched = false
                exit for
            end if
        end for
        if matched then
            rank = 2
            if Left(name, Len(phrase)) = phrase then
                rank = 0
            else if Instr(1, name, phrase) > 0 then
                rank = 1
            end if
            matches.Push({ k: rank * 100000 + Len(name), i: i })
            if matches.Count() >= 2000 then exit for
        end if
    end for
    matches.SortBy("k")

    movies = CreateObject("roSGNode", "ContentNode")
    movies.title = "Movies"
    series = CreateObject("roSGNode", "ContentNode")
    series.title = "Series"
    sep = searchSeparator()
    for each match in matches
        parts = index.records[match.i].Split(sep)
        if parts.Count() >= 5 then
            if parts[0] = "m" and movies.GetChildCount() < limit then
                addSearchItem(movies, parts, "movie")
            else if parts[0] = "s" and series.GetChildCount() < limit then
                addSearchItem(series, parts, "series")
            end if
        end if
        if movies.GetChildCount() >= limit and series.GetChildCount() >= limit then exit for
    end for
    if movies.GetChildCount() > 0 then root.AppendChild(movies)
    if series.GetChildCount() > 0 then root.AppendChild(series)
    return root
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
