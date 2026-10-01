' Off-device checks for XtreamParse.brs and Progress.brs using sample API responses.
' Run with: npm test

sub Main()
    m.failures = 0
    m.count = 0

    ' --- Auth
    check("auth ok", boolText(ParseAuth(ParseJson("{""user_info"":{""auth"":1,""status"":""Active""}}")).ok), "true")
    check("auth rejected", boolText(ParseAuth(ParseJson("{""user_info"":{""auth"":0}}")).ok), "false")
    expired = ParseAuth(ParseJson("{""user_info"":{""auth"":""1"",""status"":""Expired""}}"))
    check("auth expired", expired.error, "The server says this account is expired.")
    check("auth garbage", boolText(ParseAuth(ParseJson("[]")).ok), "false")

    ' --- Categories
    cats = ParseCategories(ParseJson("[{""category_id"":""12"",""category_name"":""EN | Action""},{""category_id"":13,""category_name"":""XXX Adult""},{""category_id"":"""",""category_name"":""Blank""},{""category_id"":14,""category_name"":""Cricket""}]"))
    checkInt("categories kept", cats.Count(), 2)
    check("category id string", cats[0].id, "12")
    check("category id number", cats[1].id, "14")

    ' --- Movie row: newest first, adult removed, limit respected
    json = "["
    json = json + "{""name"":""Older"",""stream_id"":101,""stream_icon"":""https://image.tmdb.org/t/p/w600_and_h900_bestv2/old.jpg"",""added"":""1690000000"",""container_extension"":""mkv"",""rating"":""6.1""},"
    json = json + "{""name"":""Newest"",""stream_id"":102,""stream_icon"":""https://image.tmdb.org/t/p/w600_and_h900_bestv2/new.jpg"",""added"":""1700000000"",""container_extension"":""mp4"",""rating"":7.4},"
    json = json + "{""name"":""Adult"",""stream_id"":103,""added"":""1710000000"",""is_adult"":""1""},"
    json = json + "{""name"":""Oldest"",""stream_id"":104,""added"":""1680000000"",""container_extension"":""avi""}]"
    streams = ParseJson(json)
    row = BuildRow(streams, "vod", "Action", 2)
    check("row title", row.title, "Action")
    checkInt("row limit", row.GetChildCount(), 2)
    first = row.GetChild(0)
    check("row newest first", first.title, "Newest")
    check("row item id", first.itemId, "102")
    check("row kind", first.kind, "movie")
    check("row ext", first.ext, "mp4")
    check("row rating number", first.score, "7.4")
    check("row poster sized", first.HDPosterUrl, "https://image.tmdb.org/t/p/w185/new.jpg")
    check("row second", row.GetChild(1).title, "Older")
    check("row placeholder flag", boolText(first.placeholder), "false")
    check("row playable has no problem", first.problem, "")
    oldest = BuildRow(streams, "vod", "Action", 10).GetChild(2)
    check("row avi flagged", oldest.problem, "AVI files")

    ' --- Series row
    shows = ParseJson("[{""name"":""Breaking Bad"",""series_id"":55,""cover"":""https://image.tmdb.org/t/p/w600_and_h900_bestv2/bb.jpg"",""plot"":""A teacher turns."",""releaseDate"":""2008-01-20"",""genre"":""Drama, Crime"",""rating"":""9.5"",""backdrop_path"":[""https://image.tmdb.org/t/p/w1280/bd.jpg""],""last_modified"":""1600000000""}]")
    showRow = BuildRow(shows, "series", "Drama", 40)
    show = showRow.GetChild(0)
    check("series kind", show.kind, "series")
    check("series id", show.itemId, "55")
    check("series backdrop sized", show.backdrop, "https://image.tmdb.org/t/p/w780/bd.jpg")
    check("series year", show.year, "2008")
    check("series has info", boolText(show.hasInfo), "true")
    check("series meta", MetaLine(show), "2008   ·   Drama, Crime   ·   Rated 9.5")

    ' --- VOD info, including the "info": [] quirk
    vod = ParseVodInfo(ParseJson("{""info"":{""plot"":""Heist."",""releasedate"":""2019-05-24"",""duration"":""01:30:00"",""genre"":""Thriller"",""rating"":""7.04"",""backdrop_path"":[""https://image.tmdb.org/t/p/w1280/h.jpg""],""cast"":""A, B"",""tmdb_id"":""603"",""video"":{""codec_name"":""h264"",""profile"":""High""},""audio"":{""codec_name"":""aac""}},""movie_data"":{""stream_id"":9,""container_extension"":""mkv""}}"))
    check("vod plot", vod.description, "Heist.")
    check("vod year", vod.year, "2019")
    checkInt("vod duration from clock", vod.durationSecs, 5400)
    check("vod backdrop", vod.backdrop, "https://image.tmdb.org/t/p/w780/h.jpg")
    check("vod ext", vod.ext, "mkv")
    check("vod video codec", vod.videoCodec, "h264")
    check("vod tmdb id", vod.tmdbId, "603")
    check("vod starring", vod.starring, "A, B")
    empty = ParseVodInfo(ParseJson("{""info"":[],""movie_data"":[]}"))
    check("vod empty info", empty.description, "")
    item = MakeItem(CreateObject("roSGNode", "ContentNode"), { title: "Heist", kind: "movie" })
    ApplyInfo(item, vod)
    check("applied meta", MetaLine(item), "2019   ·   1h 30m   ·   Thriller   ·   Rated 7.0")
    check("applied has info", boolText(item.hasInfo), "true")
    check("applied codec", item.videoCodec, "h264")
    check("applied starring", item.starring, "A, B")

    ' --- Series info: seasons keyed by number, unsorted episodes, messy titles
    json = "{"
    json = json + """seasons"":[{""season_number"":1,""name"":""Season 1""},{""season_number"":2,""name"":""The Final Season""}],"
    json = json + """info"":{""name"":""Breaking Bad"",""tmdb"":1396,""plot"":""Chemistry."",""backdrop_path"":[""https://image.tmdb.org/t/p/original/s.jpg""]},"
    json = json + """episodes"":{"
    json = json + """2"":[{""id"":""902"",""episode_num"":1,""title"":""Breaking Bad - S02E01 - Seven Thirty-Seven"",""container_extension"":""mkv"",""info"":[]}],"
    json = json + """1"":[{""id"":""802"",""episode_num"":""2"",""title"":""Breaking Bad - S01E02 - Cat's in the Bag"",""container_extension"":""mp4"",""info"":{""duration_secs"":2880,""movie_image"":""https://image.tmdb.org/t/p/w500/e2.jpg"",""video"":{""codec_name"":""hevc"",""profile"":""Main 10""},""audio"":{""codec_name"":""eac3""}}},"
    json = json + "{""id"":801,""episode_num"":1,""title"":""Breaking Bad - S01E01"",""container_extension"":""mp4"",""info"":{""name"":""Pilot""}}],"
    json = json + """0"":[{""id"":""700"",""episode_num"":1,""title"":""Behind the scenes""}]"
    json = json + "}}"
    info = ParseSeriesInfo(ParseJson(json))
    series = info.content
    check("series info name", info.info.name, "Breaking Bad")
    check("series info tmdb", info.info.tmdbId, "1396")
    check("series info backdrop", info.info.backdrop, "https://image.tmdb.org/t/p/w780/s.jpg")
    checkInt("season count", series.GetChildCount(), 3)
    check("specials first", series.GetChild(0).title, "Specials")
    check("season name from meta", series.GetChild(1).title, "Season 1")
    check("custom season name", series.GetChild(2).title, "The Final Season")
    s1 = series.GetChild(1)
    checkInt("season number field", s1.seasonNo, 1)
    checkInt("episodes in season 1", s1.GetChildCount(), 2)
    check("episodes sorted", s1.GetChild(0).itemId, "801")
    check("episode name from info", s1.GetChild(0).title, "Pilot")
    check("episode title cleaned", s1.GetChild(1).title, "Cat's in the Bag")
    checkInt("episode duration", s1.GetChild(1).durationSecs, 2880)
    checkInt("episode number field", s1.GetChild(1).episodeNo, 2)
    checkInt("episode season field", s1.GetChild(1).seasonNo, 1)
    check("episode video codec", s1.GetChild(1).videoCodec, "hevc")
    check("episode video profile", s1.GetChild(1).videoProfile, "Main 10")
    check("episode audio codec", s1.GetChild(1).audioCodec, "eac3")
    check("episode no codecs", s1.GetChild(0).videoCodec, "")
    check("episode still sized", s1.GetChild(1).HDPosterUrl, "https://image.tmdb.org/t/p/w300/e2.jpg")
    check("episode info [] ok", series.GetChild(2).GetChild(0).title, "Seven Thirty-Seven")

    ' Episodes delivered as a plain array
    arrayInfo = ParseSeriesInfo(ParseJson("{""info"":[],""episodes"":[[{""id"":1,""episode_num"":1,""season"":1,""title"":""S01E01""}],[{""id"":2,""episode_num"":1,""season"":2,""title"":""Two""}]]}"))
    checkInt("array seasons", arrayInfo.content.GetChildCount(), 2)
    check("array fallback title", arrayInfo.content.GetChild(0).GetChild(0).title, "Episode 1")
    check("array second season", arrayInfo.content.GetChild(1).title, "Season 2")
    checkInt("no episodes", ParseSeriesInfo(ParseJson("{""episodes"":[]}")).content.GetChildCount(), 0)

    ' --- Search
    check("normalize case and punctuation", NormalizeSearch("Spider-Man: No Way Home"), "spider man no way home")
    check("normalize apostrophes", NormalizeSearch("Schindler's List"), "schindlers list")
    check("normalize curly apostrophe", NormalizeSearch("Ocean’s Eleven"), "oceans eleven")
    check("normalize accents", NormalizeSearch("Amélie"), "amelie")
    check("normalize prefixes", NormalizeSearch("EN | The Batman (2022)"), "en the batman 2022")
    check("normalize keeps other scripts", NormalizeSearch("दंगल"), "दंगल")
    index = NewSearchIndex()
    json = "["
    json = json + "{""name"":""EN - The Batman (2022)"",""stream_id"":1,""stream_icon"":""https://image.tmdb.org/t/p/w600_and_h900_bestv2/b.jpg"",""container_extension"":""mkv""},"
    json = json + "{""name"":""Batman Begins"",""stream_id"":2,""stream_icon"":"""",""container_extension"":""mp4""},"
    json = json + "{""name"":""Lego Batman Movie"",""stream_id"":3,""container_extension"":""avi""},"
    json = json + "{""name"":""Superbatmania"",""stream_id"":4},"
    json = json + "{""name"":""Adult Batman"",""stream_id"":5,""is_adult"":""1""},"
    json = json + "{""name"":""Batman Begins"",""stream_id"":2}]"
    IndexAdd(index, ParseJson(json), "vod")
    IndexAdd(index, ParseJson("[{""name"":""Batman: The Animated Series"",""series_id"":77,""cover"":""http://x/c.jpg""}]"), "series")
    IndexAdd(index, ParseJson("{}"), "vod")
    checkInt("index skips adult and duplicates", index.names.Count(), 5)
    found = IndexSearch(index, "batman", 40)
    checkInt("search rows", found.GetChildCount(), 2)
    movies = found.GetChild(0)
    check("search movies row", movies.title, "Movies")
    checkInt("search movie count", movies.GetChildCount(), 4)
    check("search starts-with first", movies.GetChild(0).title, "Batman Begins")
    check("search word start next", movies.GetChild(1).title, "Lego Batman Movie")
    check("search longer word start", movies.GetChild(2).title, "EN - The Batman (2022)")
    check("search substring last", movies.GetChild(3).title, "Superbatmania")
    check("search item id", movies.GetChild(0).itemId, "2")
    check("search blank poster", movies.GetChild(0).HDPosterUrl, "")
    check("search poster sized", movies.GetChild(2).HDPosterUrl, "https://image.tmdb.org/t/p/w185/b.jpg")
    check("search avi flagged", movies.GetChild(1).problem, "AVI files")
    check("search series row", found.GetChild(1).title, "Series")
    check("search series kind", found.GetChild(1).GetChild(0).kind, "series")
    check("search series id", found.GetChild(1).GetChild(0).seriesId, "77")
    checkInt("search all words", IndexSearch(index, "batman begins", 40).GetChild(0).GetChildCount(), 1)
    checkInt("search any order", IndexSearch(index, "begins batman", 40).GetChild(0).GetChildCount(), 1)
    checkInt("search punctuation-insensitive", IndexSearch(index, "the-batman", 40).GetChild(0).GetChildCount(), 1)
    checkInt("search no match", IndexSearch(index, "superman", 40).GetChildCount(), 0)
    checkInt("search empty query", IndexSearch(index, "  ", 40).GetChildCount(), 0)
    checkInt("search limit", IndexSearch(index, "bat", 2).GetChild(0).GetChildCount(), 2)

    ' The whole-library series answer also holds categories the app hides.
    whole = NewSearchIndex()
    IndexAdd(whole, [{ name: "Kept Show", series_id: 1, category_id: "10" }, { name: "Hidden Show", series_id: 2, category_id: "99" }, { name: "Loose Show", series_id: 3 }], "series", { "10": true })
    checkInt("index allowed categories", whole.names.Count(), 2)
    checkInt("index allowed search", IndexSearch(whole, "hidden", 40).GetChildCount(), 0)
    checkInt("index no filter", IndexSearch(whole, "show", 40).GetChild(0).GetChildCount(), 2)

    ' One or two letters only match word starts.
    short = NewSearchIndex()
    IndexAdd(short, [{ name: "The Show", series_id: 1 }, { name: "Other Life", series_id: 2 }, { name: "Big Thing", series_id: 3 }], "series")
    checkInt("short query word starts", IndexSearch(short, "th", 40).GetChild(0).GetChildCount(), 2)
    check("short query prefix first", IndexSearch(short, "th", 40).GetChild(0).GetChild(0).title, "The Show")
    checkInt("longer query anywhere", IndexSearch(short, "the", 40).GetChild(0).GetChildCount(), 2)

    ' Saved between launches, for the same login.
    path = "tmp:/search-test.txt"
    check("index saved", SaveSearchIndex(short, path, "http://a.b jane", 1000).ToStr(), "true")
    back = LoadSearchIndex(path, "http://a.b jane")
    checkInt("index loaded", back.names.Count(), 3)
    checkInt("index saved time", back.savedAt, 1000)
    check("index loaded search", IndexSearch(back, "big", 40).GetChild(0).GetChild(0).title, "Big Thing")
    check("index other login", ToStr(LoadSearchIndex(path, "http://a.b joe") = invalid), "true")

    ' A big library: thousands of movie matches must not crowd out the series, and the
    ' best match counts even when it was indexed last.
    big = NewSearchIndex()
    films = []
    for n = 1 to 2500
        films.Push({ name: "The Long Movie Number " + n.ToStr(), stream_id: n })
    end for
    IndexAdd(big, films, "vod")
    IndexAdd(big, [{ name: "The Show", series_id: 1 }, { name: "The Other Show", series_id: 2 }], "series")
    IndexAdd(big, [{ name: "The", stream_id: 9999 }], "vod")
    crowd = IndexSearch(big, "the", 40)
    checkInt("search keeps series beside many movies", crowd.GetChildCount(), 2)
    check("search series row", crowd.GetChild(1).title, "Series")
    checkInt("search series count", crowd.GetChild(1).GetChildCount(), 2)
    check("search series best first", crowd.GetChild(1).GetChild(0).title, "The Show")
    check("search exact match indexed last", crowd.GetChild(0).GetChild(0).title, "The")
    checkInt("search movie row capped", crowd.GetChild(0).GetChildCount(), 40)
    check("search shorter first", crowd.GetChild(0).GetChild(1).title, "The Long Movie Number 1")

    ' --- Continue Watching storage
    RegDelete("progress", "items")
    ProgressPut({ k: "m:1", kind: "movie", id: "1", name: "One", poster: "", bd: "", ext: "mp4", pos: 600, dur: 6000 })
    ProgressPut({ k: "s:55", kind: "episode", sid: "55", id: "802", name: "Breaking Bad", poster: "", bd: "", ext: "mp4", season: 1, episode: 2, etitle: "Cat", pos: 100, dur: 2880 })
    ProgressPut({ k: "m:1", kind: "movie", id: "1", name: "One", poster: "", bd: "", ext: "mp4", pos: 1200, dur: 6000 })
    list = ProgressList()
    checkInt("progress count", list.Count(), 2)
    check("progress newest first", list[0].k, "m:1")
    checkInt("progress updated", ToInt(list[0].pos), 1200)
    cw = ContinueWatchingRow()
    check("cw row title", cw.title, "Continue Watching")
    check("cw series caption", cw.GetChild(1).caption, "S1:E2")
    check("cw series opens show", cw.GetChild(1).itemId, "55")
    check("cw progress", Str(cw.GetChild(0).progress).Trim(), "0.2")
    ProgressRemove("m:1")
    checkInt("progress removed", ProgressList().Count(), 1)
    for i = 1 to 25
        ProgressPut({ k: "m:x" + i.ToStr(), kind: "movie", id: i.ToStr(), name: "", poster: "", bd: "", ext: "mp4", pos: 60, dur: 100 })
    end for
    checkInt("progress capped", ProgressList().Count(), 20)
    RegDelete("progress", "items")
    check("cw empty", boolText(ContinueWatchingRow() = invalid), "true")

    print ""
    if m.failures = 0 then
        print "ALL PASSED (" + m.count.ToStr() + " checks)"
    else
        print "FAILED: " + m.failures.ToStr() + " of " + m.count.ToStr() + " checks"
    end if
end sub

function boolText(value as Boolean) as String
    if value then return "true"
    return "false"
end function

sub check(name as String, actual as String, expected as String)
    m.count = m.count + 1
    if actual <> expected then
        m.failures = m.failures + 1
        print "FAIL " + name + ": expected [" + expected + "] got [" + actual + "]"
    end if
end sub

sub checkInt(name as String, actual as Integer, expected as Integer)
    check(name, actual.ToStr(), expected.ToStr())
end sub
