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
    cover = ParseVodInfo(ParseJson("{""info"":{""video"":{""codec_name"":""mjpeg"",""profile"":""Baseline""},""audio"":{""codec_name"":""aac""}},""movie_data"":{""container_extension"":""mkv""}}"))
    check("cover art isn't the video", cover.videoCodec, "")
    check("cover art profile dropped", cover.videoProfile, "")
    check("cover art audio kept", cover.audioCodec, "aac")
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

    ' Provider tags and years come off titles in rows and in search.
    tagged = BuildRow(ParseJson("[{""name"":""EN ★ Alterity - 2026"",""stream_id"":1,""added"":""5""}]"), "vod", "Row", 40)
    check("row title untagged", tagged.GetChild(0).title, "Alterity")
    check("row year from title", tagged.GetChild(0).year, "2026")
    plain = NewSearchIndex()
    IndexAdd(plain, ParseJson("[{""name"":""EN ★ Alterity - 2026"",""stream_id"":1}]"), "vod")
    check("search title untagged", IndexSearch(plain, "alterity", 40).GetChild(0).GetChild(0).title, "Alterity")
    check("search year from title", IndexSearch(plain, "alterity", 40).GetChild(0).GetChild(0).year, "2026")

    ' Categories: counted, offered in search and browsed newest first, all from the index.
    lib = NewSearchIndex()
    IndexSetCategories(lib, "vod", [{ id: "7", name: "PUNJABI MOVIES" }, { id: "8", name: "EN | ACTION" }], 2026)
    IndexSetCategories(lib, "series", [{ id: "9", name: "PUNJABI SERIES" }], 2026)
    IndexAdd(lib, [{ name: "Carry On Jatta", stream_id: 1, category_id: "7", added: "1700000000" }, { name: "Jatt & Juliet", stream_id: 2, category_id: "7", added: "1800000000" }, { name: "Mad Max", stream_id: 3, category_id: "8", added: "1750000000" }], "vod")
    IndexAdd(lib, [{ name: "Some Show", series_id: 4, last_modified: "1600000000" }], "series", invalid, "9")
    found = IndexSearch(lib, "punjabi", 40)
    check("cat row first", found.GetChild(0).title, "Categories")
    checkInt("cat row count", found.GetChild(0).GetChildCount(), 2)
    check("cat row label", found.GetChild(0).GetChild(0).title, "Punjabi")
    check("cat row bigger first", found.GetChild(0).GetChild(0).caption, "Movies · 2")
    check("cat row kind", found.GetChild(0).GetChild(0).listKind, "vod")
    check("cat row series", found.GetChild(0).GetChild(1).caption, "Series · 1")
    checkInt("cat row only categories", found.GetChildCount(), 1)
    browsed = IndexBrowse(lib, "vod", "7", 1000)
    checkInt("browse count", browsed.GetChildCount(), 2)
    check("browse newest first", browsed.GetChild(0).title, "Jatt & Juliet")
    checkInt("browse total", browsed.total, 2)
    check("browse fallback category", IndexBrowse(lib, "series", "9", 1000).GetChild(0).title, "Some Show")
    checkInt("browse limit", IndexBrowse(lib, "vod", "7", 1).GetChildCount(), 1)
    checkInt("browse limit total", IndexBrowse(lib, "vod", "7", 1).total, 2)
    within = IndexBrowse(lib, "vod", "7", 1000, "jatt")
    checkInt("browse search matches", within.total, 2)
    check("browse search best first", within.GetChild(0).title, "Jatt & Juliet")
    checkInt("browse search one", IndexBrowse(lib, "vod", "7", 1000, "juliet").total, 1)
    checkInt("browse search none", IndexBrowse(lib, "vod", "7", 1000, "zz").total, 0)
    checkInt("browse search short", IndexBrowse(lib, "vod", "7", 1000, "ca").total, 1)
    checkInt("browse search stays in category", IndexBrowse(lib, "vod", "8", 1000, "jatt").total, 0)
    check("lib saved", SaveSearchIndex(lib, "tmp:/lib-test.txt", "owner", 5).ToStr(), "true")
    again = LoadSearchIndex("tmp:/lib-test.txt", "owner")
    checkInt("lib categories loaded", again.categories.Count(), 3)
    check("lib browse after load", IndexBrowse(again, "vod", "7", 10).GetChild(0).title, "Jatt & Juliet")
    checkInt("lib counts loaded", IndexSearch(again, "punjabi", 40).GetChild(0).GetChildCount(), 2)
    older = "aranplus-search-3" + Chr(9) + "owner" + Chr(9) + "5" + Chr(9) + "1" + Chr(9) + "0" + Chr(10) + " heat" + Chr(10) + "m" + Chr(30) + "1" + Chr(30) + "mkv" + Chr(30) + "-" + Chr(30) + "Heat" + Chr(30) + "7" + Chr(30) + "100"
    WriteAsciiFile("tmp:/lib-old.txt", older)
    check("lib previous format loads", IndexSearch(LoadSearchIndex("tmp:/lib-old.txt", "owner"), "heat", 40).GetChild(0).GetChild(0).title, "Heat")

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
    ' Home removes a series poster by "s:" + its itemId (the series id).
    ProgressRemove("s:" + cw.GetChild(1).itemId)
    checkInt("progress series removed", ProgressList().Count(), 0)
    check("removal remembered for sync", ProgressRemovedList()[0].k, "s:55")
    checkInt("removals both kept", ProgressRemovedList().Count(), 2)

    ' Sync merges: the newest change per title wins; removals win ties.
    mine = [{ k: "m:1", at: 100, pos: 10 }, { k: "m:2", at: 300, pos: 20 }]
    theirs = { entries: [{ k: "m:1", at: 200, pos: 99 }, { k: "m:3", at: 50, pos: 5 }, { k: "m:4", at: 400, pos: 1 }], removed: [{ k: "m:3", at: 60 }] }
    merged = MergeProgress(mine, [{ k: "m:2", at: 250 }, { k: "m:4", at: 400 }], theirs)
    keys = []
    for each entry in merged.entries
        keys.Push(entry.k)
    end for
    check("merge keeps newest per title, newest first", keys.Join(","), "m:2,m:1")
    checkInt("merge newer copy wins", ToInt(merged.entries[1].pos), 99)
    check("merge removal beats older entry", boolText(merged.entries.Count() = 2), "true")
    checkInt("merge removals kept", merged.removed.Count(), 3)
    check("merge removals newest first", merged.removed[0].k, "m:4")
    checkInt("merge nothing remote", MergeProgress(mine, [], invalid).entries.Count(), 2)
    for i = 1 to 25
        ProgressPut({ k: "m:x" + i.ToStr(), kind: "movie", id: i.ToStr(), name: "", poster: "", bd: "", ext: "mp4", pos: 60, dur: 100 })
    end for
    checkInt("progress capped", ProgressList().Count(), 20)
    RegDelete("progress", "items")
    check("cw empty", boolText(ContinueWatchingRow() = invalid), "true")

    ' --- The helper: remembered titles and "won't play" marks
    check("helper titles empty", FormatJson(HelperTitles()), "[]")
    RememberHelperTitle("m:5")
    RememberHelperTitle("e:9")
    RememberHelperTitle("m:5")
    check("helper titles saved", FormatJson(HelperTitles()), "[""m:5"",""e:9""]")
    check("helper listed", boolText(HelperListed("e:9")), "true")
    check("helper not listed", boolText(HelperListed("e:10")), "false")
    RegWrite("helper", "titles", "{broken")
    check("helper titles broken", FormatJson(HelperTitles()), "[]")
    check("avi won't play", containerProblem("avi"), "AVI files")
    GetGlobalAA().helperOn = true
    check("avi through the helper", containerProblem("avi"), "")
    GetGlobalAA().helperOn = false
    check("mkv plays", containerProblem("mkv"), "")

    ' Taste: what you watch (common/Taste.brs)
    checkInt("TasteWeightFor peek", TasteWeightFor(100, 6000), 0)
    checkInt("TasteWeightFor started", TasteWeightFor(200, 6000), 1)
    checkInt("TasteWeightFor half", TasteWeightFor(3000, 6000), 2)
    now = 1760000000
    list = TasteWith([], "m:1", "Carry On Jatta 3 And A Very Long Name Indeed", 1, "atLeast", now)
    checkInt("TasteWith new", list.Count(), 1)
    checkInt("TasteWith name kept short", Len(list[0].n), 32)
    check("TasteWith lower is no change", boolText(TasteWith(list, "m:1", "", 1, "atLeast", now) = invalid), "true")
    list = TasteWith(list, "m:2", "Jawan", 2, "atLeast", now + 10)
    check("TasteWith newest first", list[0].k + " " + list[1].k, "m:2 m:1")
    list = TasteWith(list, "m:1", "", 3, "atLeast", now + 20)
    check("TasteWith raised moves up and keeps the name", list[0].k + " " + list[0].n, "m:1 Carry On Jatta 3 And A Very Long")
    series = TasteWith([], "s:9", "Panchayat", 0.5, "add", now)
    series = TasteWith(series, "s:9", "Panchayat", 0.5, "add", now)
    check("TasteWith episodes add up", Str(series[0].w).Trim(), "1.5")
    for i = 1 to 10
        series = TasteWith(series, "s:9", "Panchayat", 0.5, "add", now)
        if series = invalid then exit for
    end for
    check("TasteWith stops at 4", boolText(series = invalid), "true")
    disliked = TasteWith(list, "m:2", "", -1, "set", now)
    checkInt("TasteWith set", disliked[0].w, -1)
    grown = []
    for i = 1 to 40
        grown = TasteWith(grown, "m:" + i.ToStr(), "T", 1, "atLeast", now + i)
    end for
    checkInt("TasteWith keeps TasteMax", grown.Count(), TasteMax())

    plan = [{ kind: "vod", categoryId: "1" }, { kind: "vod", categoryId: "2" }, { kind: "series", categoryId: "3" }, { kind: "vod", categoryId: "4" }, { kind: "vod", categoryId: "5" }]
    order = TasteOrder(plan, { "vod:4": 2.5, "series:3": 1, "vod:1": 9 }, 1)
    ids = []
    for each entry in order
        ids.Push(entry.categoryId)
    end for
    check("TasteOrder liked up after the first", ids.Join(","), "1,4,3,2,5")
    check("TasteOrder without likings", boolText(TasteOrder(plan, {}, 2).Count() = 5), "true")

    history = [{ k: "m:1", n: "Old", w: 3, t: now - 30 * 86400 }, { k: "m:2", n: "New", w: 2, t: now }, { k: "m:3", n: "Gone", w: -1, t: now }]
    watching = [{ k: "s:5", at: now, pos: 100, dur: 1000 }, { k: "m:2", at: now, pos: 10, dur: 100 }]
    liking = LikingFrom(history, watching, { "m:1": "vod:7", "m:2": "vod:7", "m:3": "vod:8", "s:5": "series:4" }, now)
    check("LikingFrom halves after 30 days", Str(liking["vod:7"]).Trim(), "3.5")
    check("LikingFrom counts against", Str(liking["vod:8"]).Trim(), "-1")
    check("LikingFrom counts Continue Watching", Str(liking["series:4"]).Trim(), "1")
    because = TasteBecause([{ k: "m:1", n: "A", w: 1 }, { k: "m:2", n: "B", w: 2 }, { k: "m:3", n: "C", w: 3 }], 2)
    check("TasteBecause half watched first", because[0].n + because[1].n, "BC")
    because = TasteBecause([{ k: "m:1", n: "A", w: 1 }], 2)
    check("TasteBecause falls back to started", because[0].n, "A")
    checkInt("TasteBecause none", TasteBecause([{ k: "m:1", n: "A", w: -1 }], 2).Count(), 0)

    ' Picked for you, from the stored library (tasks/SearchIndex.brs)
    picksLib = NewSearchIndex()
    IndexSetCategories(picksLib, "vod", [{ id: "7", name: "PUNJABI MOVIES" }, { id: "8", name: "EN | ACTION" }], 2026)
    IndexAdd(picksLib, [{ name: "Carry On Jatta", stream_id: 1, category_id: "7", added: now - 400 * 86400 }, { name: "Carry On Jatta 2", stream_id: 2, category_id: "7", added: now - 200 * 86400 }, { name: "Carry On Jatta 3", stream_id: 3, category_id: "8", added: now - 10 * 86400 }, { name: "Jatt & Juliet", stream_id: 4, category_id: "7", added: now - 5 * 86400 }, { name: "Die Hard", stream_id: 5, category_id: "8", added: now }, { name: "Carry On Jatta 2", stream_id: 6, category_id: "8", added: now }], "vod")
    IndexAdd(picksLib, [{ name: "Panchayat", series_id: 1, category_id: "7" }], "series")
    found = IndexCategoriesOf(picksLib, ["m:1", "m:5", "s:1", "m:99"])
    check("IndexCategoriesOf", found["m:1"] + " " + found["m:5"] + " " + found["s:1"] + " " + boolText(found["m:99"] = invalid), "vod:7 vod:8 series:7 true")
    exclude = { "m:1": true }
    exclude[" " + NormalizeSearch("Carry On Jatta")] = true
    picks = IndexPicks(picksLib, { "vod:7": 3, "vod:8": 0.5 }, exclude, 10, now)
    titles = []
    for i = 0 to picks.GetChildCount() - 1
        titles.Push(picks.GetChild(i).title)
    end for
    check("IndexPicks liked and new first, each title once", titles.Join(", "), "Jatt & Juliet, Carry On Jatta 2, Die Hard, Carry On Jatta 3")
    checkInt("IndexPicks nothing liked", IndexPicks(picksLib, {}, {}, 10, now).GetChildCount(), 0)
    check("titleStem", titleStem("The Carry On Jatta") + "|" + titleStem("Jawan") + "|" + titleStem("Up"), " carry on| jawan|")
    more = IndexBecause(picksLib, "m:1", "Carry On Jatta", "vod:7", { "m:1": true }, 10)
    titles = []
    for i = 0 to more.GetChildCount() - 1
        titles.Push(more.GetChild(i).title)
    end for
    check("IndexBecause the family first, then the category", titles.Join(", "), "Carry On Jatta 2, Carry On Jatta 3, Jatt & Juliet")
    check("IndexBecause title", more.title, "Because you watched Carry On Jatta")

    ' Ratings (common/Taste.brs)
    rated = TasteRated([{ k: "m:1", n: "Jawan", w: 2, t: now }], "m:1", "", 2, now + 5)
    check("TasteRated keeps watching and name", rated[0].n + " " + Str(rated[0].w).Trim() + " " + rated[0].r.ToStr(), "Jawan 2 2")
    check("TasteRated same is no change", boolText(TasteRated(rated, "m:1", "", 2, now) = invalid), "true")
    unrated = TasteRated(rated, "m:1", "", 0, now)
    check("TasteRated takes it away", boolText(unrated[0].DoesExist("r")), "false")
    check("TasteRated nothing to take", boolText(TasteRated([], "m:9", "X", 0, now) = invalid), "true")
    fresh = TasteRated([], "m:9", "Pathaan", 1, now)
    check("TasteRated before watching", fresh[0].k + " " + fresh[0].r.ToStr(), "m:9 1")
    watchedAfter = TasteWith(fresh, "m:9", "Pathaan", 2, "atLeast", now)
    checkInt("TasteWith keeps the rating", watchedAfter[0].r, 1)
    full = [{ k: "m:0", n: "Loved", w: 0, r: 2, t: now }]
    for i = 1 to TasteMax() + 5
        full = TasteWith(full, "m:" + (100 + i).ToStr(), "T", 1, "atLeast", now + i)
    end for
    kept = false
    for each entry in full
        if entry.k = "m:0" then kept = true
    end for
    check("rated titles stay in a full history", boolText(kept and full.Count() = TasteMax()), "true")
    ratedLiking = LikingFrom([{ k: "m:1", w: 3, r: -1, t: now }, { k: "m:2", w: 0, r: 2, t: now }, { k: "m:3", w: 1, r: 1, t: now }], [], { "m:1": "vod:1", "m:2": "vod:2", "m:3": "vod:3" }, now)
    check("ratings count", Str(ratedLiking["vod:1"]).Trim() + " " + Str(ratedLiking["vod:2"]).Trim() + " " + Str(ratedLiking["vod:3"]).Trim(), "-3 4 2.5")
    because = TasteBecause([{ k: "m:1", n: "Watched", w: 3 }, { k: "m:2", n: "Hated", w: 3, r: -1 }, { k: "m:3", n: "Loved", w: 0, r: 2 }], 2)
    check("TasteBecause loved first, never not-for-me", because[0].n + "," + because[1].n, "Loved,Watched")
    check("TasteRatingLabel", TasteRatingLabel(-1) + "|" + TasteRatingLabel(2) + "|" + TasteRatingLabel(0), "Not for me|Love this!|Rate")

    ' My List (common/MyList.brs)
    saved = MyListWith([], "m:1", "Jawan", "mkv", true, now)
    saved = MyListWith(saved, "s:7", "Panchayat", "", true, now + 1)
    check("MyListWith newest first", saved[0].k + " " + saved[1].k + " " + saved[1].x, "s:7 m:1 mkv")
    saved = MyListWith(saved, "m:1", "Jawan", "mkv", true, now + 2)
    checkInt("MyListWith once each", saved.Count(), 2)
    check("MyListWith readds to the front", saved[0].k, "m:1")
    saved = MyListWith(saved, "m:1", "", "", false, now)
    check("MyListWith takes out", saved.Count().ToStr() + " " + saved[0].k, "1 s:7")
    cards = MyListRow([{ k: "m:5", n: "Die Hard", x: "mp4" }, { k: "s:1", n: "Panchayat" }], { "m:5": "http://p/5.jpg" })
    check("MyListRow cards", cards.title + ": " + cards.GetChild(0).title + " " + cards.GetChild(0).HDPosterUrl + " " + cards.GetChild(0).ext + ", " + cards.GetChild(1).kind + " " + cards.GetChild(1).seriesId, "My List: Die Hard http://p/5.jpg mp4, series 1")
    check("TitleKey", TitleKey(cards.GetChild(0)) + " " + TitleKey(cards.GetChild(1)) + " " + TitleKey(invalid), "m:5 s:1 ")
    listRow = IndexListRow(picksLib, [{ k: "m:4", n: "Jatt & Juliet" }, { k: "m:77", n: "Not Here", x: "avi" }, { k: "s:1", n: "Panchayat" }])
    check("IndexListRow in order, from the library or as a name card", listRow.GetChild(0).title + ", " + listRow.GetChild(1).title + " " + listRow.GetChild(1).ext + ", " + listRow.GetChild(2).kind, "Jatt & Juliet, Not Here avi, series")

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
