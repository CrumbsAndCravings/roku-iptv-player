' Turns Xtream Codes API responses into plain data and ContentNodes.
' No network or m.top access here, so tests can feed in sample responses.

function ParseAuth(data as Dynamic) as Object
    user = Field(data, "user_info")
    if not IsAA(user) or ToInt(user.auth) <> 1 then return { ok: false, error: "That username or password wasn't accepted." }
    status = LCase(FieldStr(user, "status"))
    if status <> "" and status <> "active" then return { ok: false, error: "The server says this account is " + status + "." }
    return { ok: true }
end function

function ParseCategories(data as Dynamic) as Object
    list = []
    if IsArr(data) then
        for each raw in data
            name = FieldStr(raw, "category_name")
            id = FieldStr(raw, "category_id")
            if id <> "" and name <> "" and not IsAdultName(name) then list.Push({ id: id, name: name })
        end for
    end if
    return list
end function

function IsAdultName(name as String) as Boolean
    n = LCase(name)
    for each word in ["xxx", "adult", "18+", "porn"]
        if Instr(1, n, word) > 0 then return true
    end for
    return false
end function

' One home-screen row: the newest `limit` titles from get_vod_streams or get_series.
function BuildRow(data as Dynamic, kind as String, title as String, limit as Integer) as Object
    sortField = "added"
    if kind = "series" then sortField = "last_modified"
    list = []
    if IsArr(data) then
        for each raw in data
            if IsAA(raw) and ToInt(raw.is_adult) <> 1 then
                raw.sortKey = ToInt(raw[sortField])
                list.Push(raw)
            end if
        end for
    end if
    list.SortBy("sortKey", "r")

    row = CreateObject("roSGNode", "ContentNode")
    row.title = title
    count = 0
    for each raw in list
        if count >= limit then exit for
        if kind = "series" then
            addSeriesItem(row, raw)
        else
            addMovieItem(row, raw)
        end if
        count = count + 1
    end for
    return row
end function

sub addMovieItem(row as Object, raw as Object)
    MakeItem(row, {
        title: FieldStr(raw, "name")
        HDPosterUrl: SizedImage(FieldStr(raw, "stream_icon"), "w185")
        kind: "movie"
        itemId: FieldStr(raw, "stream_id")
        ext: FieldStr(raw, "container_extension")
        problem: containerProblem(FieldStr(raw, "container_extension"))
        tmdbId: FirstText([Field(raw, "tmdb"), Field(raw, "tmdb_id")])
        score: FieldStr(raw, "rating")
        year: YearOf(FirstText([Field(raw, "year"), Field(raw, "releaseDate")]))
        description: FieldStr(raw, "plot")
        genre: FieldStr(raw, "genre")
    })
end sub

' Codec checks need the TV, so tasks only flag containers Roku never plays.
function containerProblem(ext as String) as String
    if IsUnsupportedContainer(ext) then return UCase(ext) + " files"
    return ""
end function

sub addSeriesItem(row as Object, raw as Object)
    MakeItem(row, {
        title: FieldStr(raw, "name")
        HDPosterUrl: SizedImage(FieldStr(raw, "cover"), "w185")
        kind: "series"
        itemId: FieldStr(raw, "series_id")
        seriesId: FieldStr(raw, "series_id")
        tmdbId: FirstText([Field(raw, "tmdb"), Field(raw, "tmdb_id")])
        backdrop: SizedImage(FirstUrl(Field(raw, "backdrop_path")), "w780")
        description: FieldStr(raw, "plot")
        year: YearOf(FirstText([Field(raw, "releaseDate"), Field(raw, "release_date"), Field(raw, "year")]))
        genre: FieldStr(raw, "genre")
        score: FieldStr(raw, "rating")
        starring: FieldStr(raw, "cast")
        directedBy: FieldStr(raw, "director")
        hasInfo: true
    })
end sub

' get_vod_info -> fields for ApplyInfo (plus the full-size poster URL).
function ParseVodInfo(data as Dynamic) as Object
    info = Field(data, "info")
    if not IsAA(info) then info = {}
    movie = Field(data, "movie_data")
    duration = ToInt(info.duration_secs)
    if duration = 0 then duration = ClockToSeconds(FieldStr(info, "duration"))
    result = {
        description: FirstText([info.plot, info.description])
        year: YearOf(FirstText([info.releasedate, info.release_date, info.year]))
        genre: FieldStr(info, "genre")
        score: FieldStr(info, "rating")
        starring: FirstText([info.cast, info.actors])
        directedBy: FieldStr(info, "director")
        durationSecs: duration
        backdrop: SizedImage(FirstUrl(info.backdrop_path), "w780")
        poster: FirstText([info.movie_image, info.cover_big])
        ext: FieldStr(movie, "container_extension")
        tmdbId: FirstText([info.tmdb_id, info.tmdb])
    }
    result.Append(CodecFields(info))
    return result
end function

' The provider's ffprobe summary of the file, when it has one.
function CodecFields(info as Dynamic) as Object
    video = Field(info, "video")
    audio = Field(info, "audio")
    return {
        videoCodec: FieldStr(video, "codec_name")
        videoProfile: FieldStr(video, "profile")
        audioCodec: FieldStr(audio, "codec_name")
    }
end function

' get_series_info -> { info: {...}, content: ContentNode of seasons, each holding episodes }
function ParseSeriesInfo(data as Dynamic) as Object
    info = Field(data, "info")
    if not IsAA(info) then info = {}
    seriesName = FieldStr(info, "name")

    ' "episodes" is normally {"1": [...], "2": [...]}, but PHP turns it into a
    ' plain array when the season keys happen to be sequential.
    bySeason = {}
    raw = Field(data, "episodes")
    if IsAA(raw) then
        for each key in raw
            if IsArr(raw[key]) then bySeason[key] = raw[key]
        end for
    else if IsArr(raw) then
        for each list in raw
            if IsArr(list) and list.Count() > 0 then
                seasonKey = FieldStr(list[0], "season")
                if seasonKey = "" then
                    nextNumber = bySeason.Count() + 1
                    seasonKey = nextNumber.ToStr()
                end if
                bySeason[seasonKey] = list
            end if
        end for
    end if

    seasonNames = {}
    seasonsMeta = Field(data, "seasons")
    if IsArr(seasonsMeta) then
        for each season in seasonsMeta
            name = FieldStr(season, "name")
            if name <> "" then seasonNames[FieldStr(season, "season_number")] = name
        end for
    end if

    numbers = []
    for each key in bySeason
        numbers.Push(key.ToInt())
    end for
    numbers.Sort()

    ' Strips "Show Name - S01E02 - " style prefixes from episode titles.
    prefix = CreateObject("roRegex", "^.*?S\d+\s*E\d+\s*[-:.]*\s*", "i")

    seriesNode = CreateObject("roSGNode", "ContentNode")
    for each number in numbers
        key = number.ToStr()
        episodes = bySeason[key]
        if episodes = invalid then episodes = []
        sorted = []
        for each ep in episodes
            if IsAA(ep) then
                ep.sortKey = ToInt(ep.episode_num)
                sorted.Push(ep)
            end if
        end for
        sorted.SortBy("sortKey", "")
        if sorted.Count() > 0 then
            season = seriesNode.CreateChild("ContentNode")
            title = seasonNames[key]
            if title = invalid then title = "Season " + key
            if number = 0 then title = "Specials"
            season.title = title
            season.AddFields({ seasonNo: number })
            for each ep in sorted
                addEpisode(season, ep, number, seriesName, prefix)
            end for
        end if
    end for

    return {
        content: seriesNode
        info: {
            name: seriesName
            description: FieldStr(info, "plot")
            year: YearOf(FirstText([info.releaseDate, info.release_date, info.year]))
            genre: FieldStr(info, "genre")
            score: FieldStr(info, "rating")
            starring: FieldStr(info, "cast")
            directedBy: FieldStr(info, "director")
            backdrop: SizedImage(FirstUrl(info.backdrop_path), "w780")
            poster: FieldStr(info, "cover")
            tmdbId: FirstText([info.tmdb_id, info.tmdb])
        }
    }
end function

sub addEpisode(season as Object, ep as Object, seasonNo as Integer, seriesName as String, prefix as Object)
    info = Field(ep, "info")
    if not IsAA(info) then info = {}
    number = ToInt(ep.episode_num)
    title = CleanEpisodeTitle(FirstText([info.name, ep.title]), seriesName, prefix)
    if title = "" then title = "Episode " + number.ToStr()
    duration = ToInt(info.duration_secs)
    if duration = 0 then duration = ClockToSeconds(FieldStr(info, "duration"))
    values = {
        title: title
        description: FieldStr(info, "plot")
        HDPosterUrl: SizedImage(FieldStr(info, "movie_image"), "w300")
        kind: "episode"
        itemId: FieldStr(ep, "id")
        ext: FieldStr(ep, "container_extension")
        problem: containerProblem(FieldStr(ep, "container_extension"))
        seasonNo: seasonNo
        episodeNo: number
        durationSecs: duration
    }
    values.Append(CodecFields(info))
    MakeItem(season, values)
end sub

' "Show Name - S01E02 - The Title" -> "The Title". Returns "" when nothing is left.
function CleanEpisodeTitle(raw as String, seriesName as String, prefix as Object) as String
    title = raw.Trim()
    if seriesName <> "" and Left(title, Len(seriesName)) = seriesName then title = Mid(title, Len(seriesName) + 1)
    if prefix.IsMatch(title) then title = prefix.Replace(title, "")
    title = title.Trim()
    if Left(title, 1) = "-" then title = Mid(title, 2)
    return title.Trim()
end function
