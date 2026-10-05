' Off-device checks for the pure helpers in Utils.brs.
' Run with: npm test

sub Main()
    m.failures = 0
    m.count = 0

    ' Loose API types
    check("ToStr int", ToStr(42), "42")
    check("ToStr string", ToStr("abc"), "abc")
    check("ToStr invalid", ToStr(invalid), "")
    check("ToStr bool", ToStr(true), "true")
    checkInt("ToInt string", ToInt(" 17 "), 17)
    checkInt("ToInt float string", ToInt("7.9"), 7)
    checkInt("ToInt float", ToInt(3.7), 3)
    checkInt("ToInt invalid", ToInt(invalid), 0)
    check("FieldStr on array", FieldStr([], "name"), "")
    check("FieldStr number", FieldStr({ id: 99 }, "id"), "99")
    check("FirstText skips blanks", FirstText([invalid, "  ", "Plot"]), "Plot")
    check("FirstUrl array", FirstUrl(["", "https://a/b.jpg"]), "https://a/b.jpg")
    check("FirstUrl string", FirstUrl("https://a/c.jpg"), "https://a/c.jpg")
    check("FirstUrl empty array", FirstUrl([]), "")

    ' Artwork
    check("SizedImage tmdb", SizedImage("https://image.tmdb.org/t/p/w600_and_h900_bestv2/abc.jpg", "w185"), "https://image.tmdb.org/t/p/w185/abc.jpg")
    check("SizedImage original", SizedImage("http://image.tmdb.org/t/p/original/xyz.png", "w780"), "http://image.tmdb.org/t/p/w780/xyz.png")
    check("SizedImage other host", SizedImage("http://cdn.example.com/p/abc.jpg", "w185"), "http://cdn.example.com/p/abc.jpg")

    ' Dates and times
    check("YearOf date", YearOf("2019-05-24"), "2019")
    check("YearOf junk", YearOf("n/a"), "")
    checkInt("ClockToSeconds h:m:s", ClockToSeconds("01:45:30"), 6330)
    checkInt("ClockToSeconds m:s", ClockToSeconds("45:30"), 2730)
    checkInt("ClockToSeconds empty", ClockToSeconds(""), 0)
    check("FormatClock hours", FormatClock(5234), "1:27:14")
    check("FormatClock minutes", FormatClock(605), "10:05")
    check("FormatRuntime", FormatRuntime(5234), "1h 27m")
    check("FormatRuntime exact hour", FormatRuntime(7200), "2h")
    check("FormatRuntime short", FormatRuntime(2700), "45m")

    ' Server addresses
    check("Normalize bare host", NormalizeServer("line.example.com:8080"), "http://line.example.com:8080")
    check("Normalize trailing slash", NormalizeServer(" http://line.example.com:8080/ "), "http://line.example.com:8080")
    check("Normalize https", NormalizeServer("https://tv.example.org"), "https://tv.example.org")
    check("Normalize m3u link", NormalizeServer("http://a.b:80/get.php?username=u&password=p&type=m3u_plus"), "http://a.b:80")

    ' Refused requests
    q = Chr(34)
    check("http detail empty", HttpDetail(403, { server: "nginx/1.18.0 (Ubuntu)" }, ""), "HTTP 403 from nginx, no reason given")
    check("http detail no server", HttpDetail(403, {}, "  "), "HTTP 403, no reason given")
    check("http detail html", HttpDetail(403, { server: "Apache" }, "<html><head><title>403 Forbidden</title><style>body{color:red}</style></head><body><h1>Forbidden</h1></body></html>"), "HTTP 403 from Apache: " + q + "403 Forbidden Forbidden" + q)
    check("http detail json", HttpDetail(401, { server: "XUI" }, "{" + q + "message" + q + ":" + q + "Line expired" + q + "}"), "HTTP 401 from XUI: " + q + "Line expired" + q)
    check("http detail cloudflare", HttpDetail(403, { server: "cloudflare", "cf-ray": "8abc-YYZ" }, "error code: 1020"), "HTTP 403 from Cloudflare (error 1020)")
    check("http detail cloudflare page", HttpDetail(403, { "cf-ray": "8abc" }, "<span>Error</span> <span>1006</span> Access denied"), "HTTP 403 from Cloudflare (error 1006)")
    check("cloudflare challenge", HttpDetail(403, { server: "cloudflare", "cf-mitigated": "challenge" }, ""), "HTTP 403 from Cloudflare (browser check)")
    check("cloudflare challenge page", HttpDetail(403, { server: "cloudflare" }, "<html><head><title>Just a moment...</title><script src=" + q + "/cdn-cgi/challenge-platform/x.js" + q + "></script></head></html>"), "HTTP 403 from Cloudflare (browser check)")
    check("cloudflare block page", HttpDetail(403, { server: "cloudflare" }, "<h1>Sorry, you have been blocked</h1><p>You are unable to access example.com</p>"), "HTTP 403 from Cloudflare (blocked)")
    check("cloudflare plain", HttpDetail(403, { server: "cloudflare" }, ""), "HTTP 403 via Cloudflare, no reason given")
    check("cloudflare passes origin text", HttpDetail(403, { server: "cloudflare", "cf-ray": "8abc" }, "Access Denied"), "HTTP 403 via Cloudflare: " + q + "Access Denied" + q)
    check("cloudflare block flag", IsCloudflareBlock({ server: "cloudflare" }, "error code: 1020").ToStr(), "true")
    check("cloudflare origin flag", IsCloudflareBlock({ server: "cloudflare" }, "").ToStr(), "false")
    agents = UserAgentsToTry("")
    checkInt("agents count", agents.Count(), 3)
    check("agents roku first", agents[0], "")
    check("agents then app", UserAgentName(agents[1]), "as ARAN+")
    check("agents then browser", UserAgentName(agents[2]), "as a web browser")
    check("agents saved first", UserAgentName(UserAgentsToTry(BrowserUserAgent())[0]), "as a web browser")
    checkInt("agents no repeats", UserAgentsToTry(AppUserAgent()).Count(), 3)
    check("refusal 403", IsRefusalCode(403).ToStr(), "true")
    check("refusal 429", IsRefusalCode(429).ToStr(), "true")
    check("refusal 404", IsRefusalCode(404).ToStr(), "false")
    checkInt("roku http code", HttpCodeIn("There was an error in the HTTP response. (code -1): reader pick stream error:HTTP error:Transfer error: HTTP response code said error response code:(403):403:extra"), 403)
    checkInt("roku http 404", HttpCodeIn("HTTP 404 not found"), 404)
    checkInt("roku no http code", HttpCodeIn("buffer:loop:demux error 2024"), 0)
    check("cloudflare by ray", IsCloudflare({ "CF-RAY": "8abc" }).ToStr(), "true")
    check("not cloudflare", IsCloudflare({ server: "nginx" }).ToStr(), "false")
    check("http detail nginx 404", HttpDetail(404, { server: "openresty" }, "<html><head><title>404 Not Found</title></head><body><center><h1>404 Not Found</h1></center><hr><center>nginx</center></body></html>"), "HTTP 404 from openresty: " + q + "404 Not Found nginx" + q)
    check("brief text no repeat", BriefText("Forbidden", 70), "Forbidden")
    long = String(200, "x")
    checkInt("brief text cut", Len(BriefText(long, 70)), 70)
    check("brief text spaces", BriefText(" a" + Chr(10) + Chr(9) + "b&nbsp;c ", 70), "a b c")
    path = ParseProviderLink("http://a.b:80/playlist/jane/s3cret/m3u_plus?output=hls")
    check("link playlist server", path.server, "http://a.b:80")
    check("link playlist user", path.username, "jane")
    check("link playlist pass", path.password, "s3cret")
    check("link stream user", ParseProviderLink("http://a.b/movie/joe/pw%40x/123.mkv").password, "pw@x")
    check("link plain server", ParseProviderLink("http://a.b:8080").username, "")
    link = ParseProviderLink("http://a.b:80/get.php?username=jane&password=s3cret&type=m3u_plus&output=ts")
    check("Link server", link.server, "http://a.b:80")
    check("Link username", link.username, "jane")
    check("Link password", link.password, "s3cret")

    creds = { server: "http://a.b:80", username: "jane", password: "s3cret" }
    check("StreamUrl movie", StreamUrl(creds, "movie", "123", "mkv"), "http://a.b:80/movie/jane/s3cret/123.mkv")
    check("StreamUrl series", StreamUrl(creds, "series", "456", "mp4"), "http://a.b:80/series/jane/s3cret/456.mp4")
    check("StreamFormat mkv", StreamFormatFor("MKV"), "mkv")
    check("StreamFormat m3u8", StreamFormatFor("m3u8"), "hls")
    check("StreamFormat avi", StreamFormatFor("avi"), "")

    ' Episode codes and codec descriptions
    check("EpisodeCode ints", EpisodeCode(1, 2), "S1:E2")
    check("EpisodeCode strings", EpisodeCode("3", "10"), "S3:E10")
    check("Describe hevc", DescribeCodecs("hevc", "Main 10", "eac3"), "HEVC (H.265) Main 10 video, Dolby E-AC-3 audio")
    check("Describe divx", DescribeCodecs("mpeg4", "Advanced Simple Profile", "mp3"), "MPEG-4 (DivX/Xvid) Advanced Simple Profile video, MP3 audio")
    check("Codec label unknown", CodecLabel("msmpeg4v3"), "MSMPEG4V3")
    check("AVI unsupported", boolText(IsUnsupportedContainer("AVI")), "true")
    check("MKV supported", boolText(IsUnsupportedContainer("mkv")), "false")
    check("MP4 supported", boolText(IsUnsupportedContainer("mp4")), "false")
    check("Unplayable AVI text", Left(UnplayableText("AVI files", "avi"), 48), "This is an AVI file. Roku devices can't play AVI")
    m.deviceWord = "TV"
    check("Unplayable HEVC text on a TV", Left(UnplayableText("HEVC (H.265) video", "mkv"), 81), "This file uses HEVC (H.265) video, which this TV's hardware can't decode, so no a")
    m.deviceWord = "Roku"
    check("Unplayable HEVC text on a stick", Left(UnplayableText("HEVC (H.265) video", "mkv"), 62), "This file uses HEVC (H.265) video, which this Roku can't decod")
    check("Describe h264 only", DescribeCodecs("h264", "", ""), "H.264 video")
    check("Describe unknown", DescribeCodecs("", "", "wmav2"), "WMAV2 audio")
    check("Roku codec h264", RokuVideoCodec("h264"), "mpeg4 avc")
    check("Roku codec hevc", RokuVideoCodec("HEVC"), "hevc")

    ' Custom item fields must not reuse ContentNode's built-in metadata names: a built-in
    ' keeps its own type and silently drops our value (this broke episode numbers in v0.1).
    builtIn = {}
    for each name in ["title", "titleseason", "description", "releasedate", "rating", "starrating", "userstarrating", "shortdescriptionline1", "shortdescriptionline2", "episodenumber", "seasonnumber", "numepisodes", "actors", "directors", "director", "categories", "genres", "contenttype", "length", "hdposterurl", "sdposterurl", "fhdposterurl", "hdgridposterurl", "sdgridposterurl", "hdbackgroundimageurl", "sdbackgroundimageurl", "url", "streamformat", "streamurls", "streams", "stream", "playstart", "playduration", "bookmarkposition", "watched", "live", "ishd", "hdbranded", "fullhd", "framerate", "subtitletracks", "subtitleconfig", "subtitleurl", "secondarytitle", "id", "album", "artist", "artists", "language", "closedcaptions", "tracks"]
        builtIn[name] = true
    end for
    for each name in ItemDefaults()
        m.count = m.count + 1
        if builtIn.DoesExist(LCase(name)) then
            m.failures = m.failures + 1
            print "FAIL item field '" + name + "' collides with a ContentNode built-in"
        end if
    end for

    check("sync space text", SyncSpaceText({ server: "HTTP://Host.Example:80/", username: "Jane" }), "http://host.example" + Chr(10) + "Jane")
    check("sync space https port", SyncSpaceText({ server: "https://host.example:443", username: "j" }), "https://host.example" + Chr(10) + "j")
    check("sync space other port kept", SyncSpaceText({ server: "host.example:8080", username: "j" }), "http://host.example:8080" + Chr(10) + "j")
    check("commas small", Commas(12), "12")
    check("commas thousands", Commas(1234), "1,234")
    check("commas millions", Commas(1234567), "1,234,567")

    ' Provider categories
    c = ClassifyCategory("EN | ACTION ★", 2026)
    check("cat en tag", c.lang, "en")
    check("cat en label", c.label, "Action")
    c = ClassifyCategory("|IN| BOLLYWOOD 2024", 2026)
    check("cat bollywood", c.lang, "hi")
    check("cat bollywood label", c.label, "Bollywood 2024")
    check("cat old year not new", c.isNew.ToStr(), "false")
    check("cat punjabi", ClassifyCategory("PUNJABI MOVIES", 2026).lang, "pa")
    check("cat punjabi label", ClassifyCategory("PUNJABI MOVIES", 2026).label, "Punjabi")
    check("cat arabic tag", ClassifyCategory("AR | AFLAM", 2026).lang, "other")
    check("cat tamil", ClassifyCategory("TAMIL MOVIES", 2026).lang, "other")
    check("cat urdu", ClassifyCategory("PAKISTANI DRAMAS", 2026).lang, "other")
    check("cat hindi dubbed", ClassifyCategory("SOUTH INDIAN HINDI DUBBED", 2026).lang, "hi")
    check("cat south indian", ClassifyCategory("SOUTH INDIAN MOVIES", 2026).lang, "other")
    check("cat no language", ClassifyCategory("ACTION", 2026).lang, "")
    check("cat platform label", ClassifyCategory("NETFLIX MOVIES", 2026).label, "Netflix")
    check("cat sci-fi", ClassifyCategory("SCI-FI & FANTASY", 2026).label, "Sci-Fi & Fantasy")
    check("cat sci-fi not finnish", ClassifyCategory("SCI-FI & FANTASY", 2026).lang, "")
    check("cat new releases", ClassifyCategory("NEW RELEASES 2026", 2026).isNew.ToStr(), "true")
    check("cat last year new", ClassifyCategory("MOVIES 2025", 2026).isNew.ToStr(), "true")
    check("cat in theaters", ClassifyCategory("IN THEATERS NOW", 2026).isNew.ToStr(), "true")
    check("cat in theaters not hindi", ClassifyCategory("IN THEATERS NOW", 2026).lang, "")
    c = ClassifyCategory("EN - KIDS", 2026)
    check("cat kids", c.kids.ToStr(), "true")
    check("cat kids label", c.label, "Kids")
    check("cat hindi prefix", ClassifyCategory("IN | ACTION", 2026).label, "Hindi Action")
    check("cat uk top 10", ClassifyCategory("|UK| TOP 10 THIS WEEK", 2026).isNew.ToStr(), "true")
    check("cat 4k label", ClassifyCategory("4K UHD MOVIES", 2026).label, "4K UHD")
    check("cat platform split", ClassifyCategory("EN | NETFLIX | DRAMA", 2026).label, "Netflix · Drama")
    langs = ["en", "hi", "pa"]
    check("cat wanted unknown", CategoryWanted({ lang: "" }, langs).ToStr(), "true")
    check("cat wanted other", CategoryWanted({ lang: "other" }, langs).ToStr(), "false")
    check("cat wanted all", CategoryWanted({ lang: "other" }, []).ToStr(), "true")
    organized = OrganizeCategories([{ id: "1", name: "AR | ACTION" }, { id: "2", name: "EN | DRAMA" }, { id: "3", name: "IN | COMEDY" }, { id: "4", name: "NEW RELEASES" }, { id: "5", name: "HORROR" }], langs, 2026)
    ids = []
    for each entry in organized
        ids.Push(entry.id)
    end for
    check("cat organized order", ids.Join(","), "4,2,5,3")
    check("cat take turns", TakeTurns([1, 2, 3], ["a"]).Count().ToStr(), "4")

    ' The provider in use: "EN ✪ ACTION [4K]" for movies, "EN ◉ NETFLIX" for series
    c = ClassifyCategory("EN ✪ ACTION [4K]", 2026)
    check("real en", c.lang, "en")
    check("real en label", c.label, "Action · 4K")
    check("real en turkish stays english", ClassifyCategory("EN ◉ TURKISH", 2026).lang, "en")
    check("real quebec", ClassifyCategory("CA ◉ QUEBECOISE", 2026).lang, "other")
    check("real quebec accents", ClassifyCategory("CA ◉ TÉLÉRÉALITÉS ET VARIÉTÉS", 2026).lang, "other")
    check("real gujarati typo", ClassifyCategory("IN ✪ GUJARTI", 2026).lang, "other")
    check("real malayalam", ClassifyCategory("IN ✪ MALAYALAM", 2026).lang, "other")
    check("real punjabi", ClassifyCategory("IN ✪ PUNJABI", 2026).lang, "pa")
    check("real punjabi label", ClassifyCategory("IN ✪ PUNJABI", 2026).label, "Punjabi")
    check("real bollywood", ClassifyCategory("IN ✪ BOLLYWOOD", 2026).lang, "hi")
    check("real indian series", ClassifyCategory("IN ◉ INDIAN", 2026).lang, "hi")
    check("real arabic script", ClassifyCategory("VIP ✪ كأس العالم 2026", 2026).lang, "other")
    c = ClassifyCategory("VIP ✪ FIFA World Cup 2026", 2026)
    check("real world cup", c.lang, "")
    check("real world cup label", c.label, "FIFA World Cup 2026")
    check("real world cup new", c.isNew.ToStr(), "true")
    check("real tv shows", ClassifyCategory("EN ◉ TV SHOWS", 2026).label, "TV Shows")
    check("real uk series", ClassifyCategory("UK ◉ UK SERIES", 2026).label, "UK Series")
    check("real french code kept", ClassifyCategory("FR ✪ ACTION", 2026).label, "FR · Action")
    check("real box office new", ClassifyCategory("EN ✪ BOX OFFICE", 2026).isNew.ToStr(), "true")
    check("real movie series", ClassifyCategory("EN ✪ MOVIE SERIES", 2026).label, "Movie Series")
    check("real slash words", ClassifyCategory("EN ✪ CONCERTS/MUSICAL", 2026).label, "Concerts/Musical")
    check("real sci-fi", ClassifyCategory("EN ✪ SCI-FI", 2026).label, "Sci-Fi")
    turns = LanguageTurns([{ lang: "en", id: "1" }, { lang: "en", id: "2" }, { lang: "hi", id: "3" }, { lang: "pa", id: "4" }, { lang: "", id: "5" }], langs)
    order = []
    for each entry in turns
        order.Push(entry.id)
    end for
    check("languages take turns", order.Join(","), "1,3,4,2,5")
    check("real plain series", ClassifyCategory("EN ◉ SERIES", 2026).label, "English")
    check("real 4k label", Is4KLabel("Action · 4K").ToStr(), "true")
    check("real not 4k", Is4KLabel("Box Office").ToStr(), "false")
    shown4k = OrganizeCategories([{ id: "1", name: "EN ✪ ACTION [4K]" }, { id: "2", name: "EN ✪ ACTION" }, { id: "3", name: "EN ✪ 4K [2024/2025]" }], langs, 2026, true)
    check("4k demoted last", shown4k[0].id + "," + shown4k[1].id + "," + shown4k[2].id, "2,1,3")
    check("4k not new when demoted", shown4k[2].isNew.ToStr(), "false")
    turns4k = LanguageTurns([{ lang: "en", id: "a", demoted: true }, { lang: "en", id: "b", demoted: false }], langs)
    check("4k after the turns", turns4k[0].id + turns4k[1].id, "ba")

    ' Titles with a provider tag and a year
    t = SplitTitle("EN ★ Alterity - 2026")
    check("title tag", t.title, "Alterity")
    check("title year", t.year, "2026")
    check("title punjabi", SplitTitle("PUN ★ Nikka Zaildar 4 - 2025").title, "Nikka Zaildar 4")
    check("title punctuation", SplitTitle("BL ★ Don't Be Shy! - 2026").title, "Don't Be Shy!")
    check("title pipe tag", SplitTitle("IN | Chumbak").title, "Chumbak")
    check("title plain", SplitTitle("Up").title, "Up")
    check("title capitals kept", SplitTitle("UFO - 2018").title, "UFO")
    check("title no tag", SplitTitle("M3GAN").title, "M3GAN")
    check("title hyphen kept", SplitTitle("Spider-Man: No Way Home - 2021").title, "Spider-Man: No Way Home")
    check("title no year", SplitTitle("EN ★ Heat").year, "")

    ' Audio and subtitle tracks, shaped like the Video node's availableAudioTracks / availableSubtitleTracks
    check("Language 3-letter", LanguageName("hin"), "Hindi")
    check("Language 2-letter", LanguageName("EN"), "English")
    check("Language unknown code", LanguageName("xyz"), "XYZ")
    check("Language undefined", LanguageName("und"), "")
    audio = AudioOptions([{ Track: "1", Language: "hin", Name: "" }, { Track: "2", Language: "eng", Name: "Commentary" }, { Track: "3", Language: "und", Name: "" }, { Language: "eng" }])
    checkInt("audio count skips missing ids", audio.Count(), 3)
    check("audio plain", audio[0].label, "Hindi")
    check("audio with name", audio[1].label, "English · Commentary")
    check("audio fallback", audio[2].label, "Track 3")
    check("audio language kept", audio[0].language, "hin")
    withFormat = AudioOptions([{ Track: "1", Language: "eng", Name: "", Format: "DTS" }, { Track: "2", Language: "eng", Name: "", Format: "AC3" }])
    check("audio format label", withFormat[0].label, "English · DTS")
    check("audio format kept", withFormat[1].format, "ac3")
    check("audio no format", audio[0].format, "")
    subs = SubtitleOptions([{ TrackName: "mkv/3", Language: "eng", Description: "English" }, { TrackName: "mkv/4", Language: "eng", Description: "SDH" }, { TrackName: "mkv/5", Language: "", Description: "" }])
    checkInt("subs count with off", subs.Count(), 4)
    check("subs off first", subs[0].label, "Off")
    check("subs repeated description", subs[1].label, "English")
    check("subs with description", subs[2].label, "English · SDH")
    check("subs fallback", subs[3].label, "Subtitles 3")
    checkInt("subs by language", OptionIndex(subs, "language", "eng"), 1)
    checkInt("subs by id", OptionIndex(subs, "id", "mkv/4"), 2)
    checkInt("subs missing", OptionIndex(subs, "language", "fre"), -1)
    checkInt("no tracks", SubtitleOptions(invalid).Count(), 1)

    ' Seeking
    checkInt("hold tap", HoldStep(0), 10)
    checkInt("hold 1.4s", HoldStep(1499), 10)
    checkInt("hold 1.5s", HoldStep(1500), 30)
    checkInt("hold 2.9s", HoldStep(2999), 30)
    checkInt("hold 3s doubles", HoldStep(3000), 60)
    checkInt("hold 4.5s doubles", HoldStep(4500), 120)
    checkInt("hold 6s doubles", HoldStep(6000), 240)
    checkInt("hold 7.5s doubles", HoldStep(7500), 480)
    checkInt("hold capped", HoldStep(9000), 600)
    checkInt("hold long capped", HoldStep(60000), 600)
    checkInt("clamp below zero", Int(ClampSeek(-25.0, 3600.0)), 0)
    checkInt("clamp past end", Int(ClampSeek(4000.0, 3600.0)), 3597)
    checkInt("clamp unknown duration", Int(ClampSeek(4000.0, 0.0)), 4000)
    checkInt("bar half", Int(BarFraction(1800.0, 3600.0) * 100), 50)
    checkInt("bar unknown", Int(BarFraction(10.0, 0.0) * 100), 0)
    checkInt("bar over", Int(BarFraction(4000.0, 3600.0) * 100), 100)

    ' OpenSubtitles file fingerprint, checked against a Python reference (tools: struct '<Q' sums)
    head = [165, 77, 202, 24, 37, 48, 187, 29, 109, 19, 44, 222, 214, 35, 123, 46, 217, 30, 63, 114, 31, 203, 25, 113, 23, 68, 148, 214, 73, 60, 157, 92, 52, 96, 190, 49, 32, 30, 105, 254, 218, 160, 238, 232, 185, 153, 127, 92, 124, 41, 153, 253, 175, 229, 147, 37, 60, 214, 84, 175, 77, 250, 215, 20]
    tail = [39, 160, 174, 179, 254, 233, 35, 47, 138, 242, 33, 31, 158, 228, 145, 197, 177, 11, 236, 181, 86, 59, 252, 30, 111, 147, 66, 126, 203, 200, 254, 41, 85, 229, 205, 142, 70, 220, 142, 212, 183, 194, 118, 77, 42, 90, 77, 118, 119, 6, 248, 93, 134, 144, 2, 74, 214, 189, 163, 64, 27, 233, 200, 203]
    check("hash small file", OsHashHex(head, tail, 131072&), "4d9a760e894662f2")
    check("hash 5GB file", OsHashHex(head, tail, 5368709120&), "4d9a760fc94462f2")
    check("hash huge size", OsHashHex(head, tail, 6148914691236517205&), "a2efcb63de99b847")
    ff = []
    for i = 1 to 64
        ff.Push(255)
    end for
    check("hash wraps at 64 bits", OsHashHex(ff, ff, 12884901895&), "00000002fffffff7")
    check("content-range total", ParseContentRangeTotal("bytes 0-65535/5368709120").ToStr(), "5368709120")
    check("content-range unknown", ParseContentRangeTotal("bytes 0-65535/*").ToStr(), "-1")
    check("content-range missing", ParseContentRangeTotal("").ToStr(), "-1")

    ' Title cleanup for text searches
    cleaned = CleanTitleForSearch("EN - The Batman (2022)")
    check("clean tag and year", cleaned.query, "The Batman")
    check("clean year", cleaned.year, "2022")
    check("clean pipe tag", CleanTitleForSearch("|EN| Supernatural").query, "Supernatural")
    check("clean bracket tags", CleanTitleForSearch("[4K] Dune: Part Two [MULTI-SUB]").query, "Dune: Part Two")
    check("clean keeps hyphenated names", CleanTitleForSearch("Spider-Man: No Way Home (2021)").query, "Spider-Man: No Way Home")
    check("clean keeps short numeric titles", CleanTitleForSearch("1917").query, "1917")
    check("clean keeps colon titles", CleanTitleForSearch("CSI: Miami").query, "CSI: Miami")

    ' Query strings are sorted with lowercase values
    check("os query", OsQuery({ type: "episode", languages: "en", parent_tmdb_id: 1622, season_number: 1, episode_number: 2, moviehash: "ABCDEF0123456789" }), "episode_number=2&languages=en&moviehash=abcdef0123456789&parent_tmdb_id=1622&season_number=1&type=episode")
    check("os query escapes", OsQuery({ query: "That '70s Show", type: "movie" }), "query=that%20'70s%20show&type=movie")

    ' Picking the best results
    results = ParseOsResults(ParseJson("{""data"":[" + osResult("11", "Popular.Release", 5000, false, false, false) + "," + osResult("12", "Exact.Match", 10, true, false, false) + "," + osResult("13", "Machine", 90000, false, true, false) + "," + osResult("14", "SDH.Release", 6000, false, false, true) + "," + osResult("11", "Duplicate", 1, false, false, false) + "]}"))
    checkInt("os results deduped", results.Count(), 4)
    check("os hash match first", results[0].fileId, "12")
    check("os human before sdh", results[1].fileId, "11")
    check("os sdh next", results[2].fileId, "14")
    check("os machine last", results[3].fileId, "13")
    check("os label match", SubtitleLabel(results[0]), "English · matches this file")
    saved = SavedCandidate({ fileId: "9", name: "Show.S01E02.WEB", delayMs: -1000, file: "https://sync.example/v1/subtitles/file?t=ab" })
    check("saved label", SubtitleLabel(saved), "English · saved for this title")
    split = SplitSavedCandidates([results[0], saved, { fileId: "9", release: "x", hashMatch: true, machine: false, sdh: false, downloads: 1 }])
    check("saved first", split.saved.Count().ToStr() + " " + split.saved[0].fileId, "1 9")
    check("search results without the saved file", split.found.Count().ToStr() + " " + split.found[0].fileId, "1 " + results[0].fileId)
    checkInt("no saved ones", SplitSavedCandidates(results).saved.Count(), 0)
    check("saved url as is", SavedSubtitleUrl("https://s/f?t=ab", 0), "https://s/f?t=ab")
    check("saved url moved", SavedSubtitleUrl("https://s/f?t=ab", -1000), "https://s/f?t=ab&delay=-1000")
    check("os label sdh", SubtitleLabel(results[2]), "English · SDH.Release · SDH")
    check("os label machine", SubtitleLabel(results[3]), "English · Machine · auto-translated")
    checkInt("os results empty", ParseOsResults(ParseJson("{""data"":[]}")).Count(), 0)
    checkInt("os results garbage", ParseOsResults(invalid).Count(), 0)

    ' Episode title cleanup (same pattern as XtreamTask)
    prefix = CreateObject("roRegex", "^.*?S\d+\s*E\d+\s*[-:.]*\s*", "i")
    check("Episode prefix", prefix.Replace("Breaking Bad - S01E02 - Cat's in the Bag", ""), "Cat's in the Bag")
    check("Episode no prefix", prefix.Replace("Pilot", ""), "Pilot")

    ' --- OpenSubtitles account: saved on this Roku, else the build's own
    q = Chr(34)
    built = OsAccountSettings({ opensubtitles: { apiKey: " k3y ", username: "jane", password: "pw" } })
    check("os built-in key", built.apiKey, "k3y")
    check("os built-in user", built.username, "jane")
    check("os built-in none", ToStr(type(OsAccountSettings({ opensubtitles: { username: "jane" } }))), "Invalid")
    check("os built-in missing", ToStr(type(OsAccountSettings(invalid))), "Invalid")
    saved = "{" + q + "apiKey" + q + ":" + q + "tv" + q + "," + q + "username" + q + ":" + q + "sam" + q + "," + q + "token" + q + ":" + q + "t" + q + "}"
    check("os saved wins", PickOsAccount(saved, built).apiKey, "tv")
    check("os saved keeps token", PickOsAccount(saved, built).token, "t")
    check("os nothing saved", PickOsAccount(invalid, built).apiKey, "k3y")
    check("os broken saved", PickOsAccount("{broken", built).apiKey, "k3y")
    check("os saved without key", PickOsAccount("{" + q + "username" + q + ":" + q + "sam" + q + "}", built).apiKey, "k3y")
    check("os removed here", ToStr(type(PickOsAccount(FormatJson({ removed: true }), built))), "Invalid")
    check("os none at all", ToStr(type(PickOsAccount(invalid, invalid))), "Invalid")

    ' --- The helper on a computer at home (Helper.brs)
    q = Chr(34)
    config = TranscoderSettings({ transcoder: { url: "http://192.168.1.20:8090//", key: "k/y&1 2" } })
    check("helper url trimmed", config.url, "http://192.168.1.20:8090")
    check("helper key", config.key, "k/y&1 2")
    check("helper no key", ToStr(type(TranscoderSettings({ transcoder: { url: "http://x:8090" } }))), "Invalid")
    check("helper no settings", ToStr(type(TranscoderSettings({ sync: { url: "u", key: "k" } }))), "Invalid")
    check("helper bad json", ToStr(type(TranscoderSettings(invalid))), "Invalid")
    check("helper file query", HelperFileQuery("series", "77 a/b", "MKV"), "kind=series&id=77%20a%2Fb&ext=mkv")
    check("helper file query no ext", HelperFileQuery("movie", "5", ""), "kind=movie&id=5&ext=mp4")
    check("helper info url", HelperInfoUrl(config, "movie", "5", "avi"), "http://192.168.1.20:8090/v1/info?key=k%2Fy%261%202&kind=movie&id=5&ext=avi")
    check("helper hash url", HelperHashUrl(config, "series", "77", "mkv"), "http://192.168.1.20:8090/v1/hash?key=k%2Fy%261%202&kind=series&id=77&ext=mkv")
    check("helper start url", HelperStartUrl(config, "series", "77", "mkv", 754, { video: "convert", height: 720, hevc: false, track: 1 }), "http://192.168.1.20:8090/v1/hls/start?key=k%2Fy%261%202&kind=series&id=77&ext=mkv&start=754&vod=1&format=ts&video=convert&height=720&hevc=0&a=1")
    check("helper start url plain", HelperStartUrl(config, "movie", "5", "avi", -3, { video: "copy", height: 0, hevc: true, track: -1 }), "http://192.168.1.20:8090/v1/hls/start?key=k%2Fy%261%202&kind=movie&id=5&ext=avi&start=0&vod=1&format=ts&video=copy")
    check("helper error url", HelperErrorUrl(config), "http://192.168.1.20:8090/v1/last-error?key=k%2Fy%261%202")
    check("helper stop url", HelperStopUrl(config, ""), "http://192.168.1.20:8090/v1/stop?key=k%2Fy%261%202")
    check("helper stop session", HelperStopUrl(config, "22743af74dc8dd4b7e614db635c3f8ee"), "http://192.168.1.20:8090/v1/stop?key=k%2Fy%261%202&session=22743af74dc8dd4b7e614db635c3f8ee")

    blocked = { blocked: "AVI files", warning: "" }
    fine = { blocked: "", warning: "" }
    check("route blocked", boolText(HelperRoute(blocked, {}, true, false)), "true")
    check("route off", boolText(HelperRoute(blocked, {}, false, false)), "false")
    check("route tried", boolText(HelperRoute(blocked, {}, true, true)), "false")
    check("route plays itself", boolText(HelperRoute(fine, {}, true, false)), "false")
    check("route listed", boolText(HelperRoute(fine, { listed: true }, true, false)), "true")
    check("route failed", boolText(HelperRoute(fine, { failed: true, refused: false }, true, false)), "true")
    check("route refused", boolText(HelperRoute(fine, { failed: true, refused: true }, true, false)), "false")
    check("route silent", boolText(HelperRoute(fine, { silent: true }, true, false)), "true")
    check("route odd flags", boolText(HelperRoute(fine, { listed: "yes", failed: invalid }, true, false)), "false")
    check("video copy", HelperVideo("copy", true), "copy")
    check("video hevc this roku can't", HelperVideo("copy", false), "convert")
    check("video divx", HelperVideo("try", true), "convert")
    check("video wmv", HelperVideo("convert", true), "convert")
    checkInt("height 720p", HelperHeight(720), 720)
    checkInt("height unknown", HelperHeight(0), 720)
    checkInt("height 4k", HelperHeight(2160), 1080)
    tracks = [{ codec: "dts", language: "eng" }, { codec: "ac3", language: "hin" }]
    checkInt("track hindi", HelperTrack(tracks, "hin"), 1)
    checkInt("track two letters", HelperTrack(tracks, "en"), 0)
    checkInt("track missing", HelperTrack(tracks, "pan"), -1)
    checkInt("track no pref", HelperTrack(tracks, ""), -1)
    checkInt("track no list", HelperTrack(invalid, "eng"), -1)
    check("seek inside", boolText(HelperSeekInside(700, 600, 300)), "true")
    check("seek near the edge", boolText(HelperSeekInside(890, 600, 300)), "false")
    check("seek before start", boolText(HelperSeekInside(590, 600, 300)), "false")
    check("seek nothing listed", boolText(HelperSeekInside(600, 600, 0)), "false")
    check("ended early", boolText(HelperEndedEarly(3000, 6133)), "true")
    check("ended at the end", boolText(HelperEndedEarly(6100, 6133)), "false")
    check("ended unknown length", boolText(HelperEndedEarly(30, 0)), "false")

    info = ParseHelperInfo(ParseJson("{" + q + "duration" + q + ":2400," + q + "video" + q + ":{" + q + "codec" + q + ":" + q + "hevc" + q + "," + q + "width" + q + ":1920," + q + "height" + q + ":1080}," + q + "audio" + q + ":[{" + q + "codec" + q + ":" + q + "dts" + q + "," + q + "channels" + q + ":6," + q + "language" + q + ":" + q + "eng" + q + "," + q + "plan" + q + ":" + q + "ac3" + q + "},{" + q + "codec" + q + ":" + q + "ac3" + q + "," + q + "channels" + q + ":2," + q + "language" + q + ":" + q + "hin" + q + "," + q + "plan" + q + ":" + q + "copy" + q + "}]," + q + "videoPlan" + q + ":" + q + "copy" + q + "," + q + "encoder" + q + ":" + q + "h264_nvenc" + q + "}"))
    checkInt("info duration", info.duration, 2400)
    check("hash", ParseHelperHash({ hash: "5253E30C096B95C4", size: 190324675 }), "5253e30c096b95c4")
    check("hash none", ParseHelperHash({ hash: "", size: 0 }), "")
    check("hash odd", ParseHelperHash({ hash: "../x" }), "")
    started = ParseHelperStart(ParseJson("{" + q + "session" + q + ":" + q + "22743af7" + q + "," + q + "url" + q + ":" + q + "/v1/hls/s/22743af7/index.m3u8" + q + "," + q + "vod" + q + ":true," + q + "start" + q + ":0," + q + "from" + q + ":300," + q + "duration" + q + ":600," + q + "video" + q + ":" + q + "convert" + q + "," + q + "videoCodec" + q + ":" + q + "hevc" + q + "," + q + "audioTrack" + q + ":1," + q + "audioPlan" + q + ":" + q + "aac" + q + "}"))
    check("start url", started.url, "/v1/hls/s/22743af7/index.m3u8")
    check("start vod", boolText(started.vod), "true")
    checkInt("start clock", started.start, 0)
    checkInt("start plays from", started.playFrom, 300)
    checkInt("start track", started.audioTrack, 1)
    growing = ParseHelperStart({ session: "s", url: "/v1/hls/s/s/index.m3u8", start: 754, duration: 0 })
    check("growing not vod", boolText(growing.vod), "false")
    checkInt("growing clock", growing.start, 754)
    check("start odd url", ParseHelperStart({ url: "http://elsewhere/x.m3u8" }).url, "")
    pictures = ParseHelperStart(ParseJson("{" + q + "session" + q + ":" + q + "22743af7" + q + "," + q + "vod" + q + ":true," + q + "previews" + q + ":{" + q + "every" + q + ":6," + q + "prefix" + q + ":" + q + "/v1/hls/s/22743af7/p" + q + "}}")).previews
    checkInt("previews every", pictures.every, 6)
    check("preview first", HelperPreviewUrl(pictures, 0), "/v1/hls/s/22743af7/p00000.jpg")
    check("preview inside a piece", HelperPreviewUrl(pictures, 125.5), "/v1/hls/s/22743af7/p00020.jpg")
    check("preview piece start", HelperPreviewUrl(pictures, 126), "/v1/hls/s/22743af7/p00021.jpg")
    check("preview two hours", HelperPreviewUrl(pictures, 7199), "/v1/hls/s/22743af7/p01199.jpg")
    check("preview past 5 digits", HelperPreviewUrl(pictures, 600000), "/v1/hls/s/22743af7/p100000.jpg")
    check("preview before the start", HelperPreviewUrl(pictures, -1), "")
    check("preview none", HelperPreviewUrl(growing.previews, 60), "")
    check("previews older helper", ToStr(type(growing.previews)), "Invalid")
    check("previews elsewhere", ToStr(type(ParseHelperStart({ previews: { every: 6, prefix: "http://elsewhere/p" } }).previews)), "Invalid")
    check("previews no interval", ToStr(type(ParseHelperStart({ previews: { every: 0, prefix: "/v1/hls/s/s/p" } }).previews)), "Invalid")
    check("previews odd", ToStr(type(ParseHelperStart({ previews: "yes" }).previews)), "Invalid")
    check("info codec", info.videoCodec, "hevc")
    checkInt("info height", info.height, 1080)
    check("info plan", info.videoPlan, "copy")
    checkInt("info tracks", info.audio.Count(), 2)
    check("info track language", info.audio[1].language, "hin")
    checkInt("info channels", info.audio[0].channels, 6)
    check("info odd plan", ParseHelperInfo({ videoPlan: "maybe" }).videoPlan, "copy")
    checkInt("info garbage", ParseHelperInfo(invalid).audio.Count(), 0)
    check("plan line", HelperPlanLine(info, { video: "convert", audioTrack: 0, audioPlan: "aac" }), "Through the helper on your computer: picture converted to H.264, DTS sound converted to AAC.")
    check("plan line kept", HelperPlanLine({ audio: [{ codec: "aac" }] }, { video: "copy", audioTrack: 0, audioPlan: "aac" }), "Through the helper on your computer: picture kept as it is, AAC sound kept.")
    check("plan line unknown", HelperPlanLine(invalid, invalid), "Through the helper on your computer, which didn't describe the file.")
    options = HelperAudioOptions([{ codec: "dts", language: "eng", title: "" }, { codec: "ac3", language: "hin", title: "Original" }, { codec: "aac", language: "" }])
    checkInt("helper audio options", options.Count(), 3)
    check("helper audio id", options[1].id, "helper:1")
    check("helper audio label", options[0].label, "English · DTS")
    check("helper audio label title", options[1].label, "Hindi · Original · Dolby AC-3")
    check("helper audio label unknown", options[2].label, "Track 3 · AAC")
    check("helper audio language", options[1].language, "hin")
    check("helper no answer", HelperFailure(0, ""), "The helper on your computer didn't answer. Is the computer on, with the helper running?")
    check("helper wrong key", Left(HelperFailure(401, "{}"), 63), "The helper on your computer turned this app away: its key doesn")
    check("helper says", HelperFailure(502, "{" + q + "error" + q + ":" + q + "Couldn't read movie 5.avi from the provider" + q + "}"), "Your computer says: Couldn't read movie 5.avi from the provider")
    check("helper older", Left(HelperFailure(404, "{" + q + "error" + q + ":" + q + "Nothing here." + q + "}"), 69), "The helper on your computer doesn't know this request, so it may be o")
    check("helper bare code", HelperFailure(500, "oops"), "The helper on your computer answered HTTP 500.")
    titles = AddHelperTitle(["m:1", "e:2", 3], "e:2")
    check("titles newest first", FormatJson(titles), "[" + q + "e:2" + q + "," + q + "m:1" + q + "," + q + "3" + q + "]")
    many = []
    for i = 1 to 250
        many.Push("m:" + i.ToStr())
    end for
    checkInt("titles capped", AddHelperTitle(many, "e:9").Count(), 200)
    checkInt("titles from nothing", AddHelperTitle(invalid, "m:7").Count(), 1)

    ' Motion: the web app's spring and jelly curves, and values along them
    spring = SpringCurve()
    jelly = JellyCurve()
    checkInt("SpringCurve keys", spring.Count(), 49)
    checkInt("JellyCurve keys", jelly.Count(), 49)
    check("SpringCurve ends", boolText(spring[0] = 0 and spring[48] = 1), "true")
    check("JellyCurve ends", boolText(jelly[0] = 0 and jelly[48] = 1), "true")
    peak = 0
    for each t in spring
        if t > peak then peak = t
    end for
    check("SpringCurve overshoots a touch", boolText(peak > 1.05 and peak < 1.1), "true")
    numbers = CurveValues(10, 30, [0, 0.5, 1])
    checkInt("CurveValues numbers", ToInt(numbers[0]) * 10000 + ToInt(numbers[1]) * 100 + ToInt(numbers[2]), 102030)
    pairs = CurveValues([0, 4], [10, 8], [0, 0.5, 1])
    checkInt("CurveValues pairs", pairs.Count(), 3)
    checkInt("CurveValues pair middle", ToInt(pairs[1][0]) * 10 + ToInt(pairs[1][1]), 56)
    sizes = ScaleValues(PopCurve())
    check("ScaleValues even", boolText(sizes[2][0] = sizes[2][1] and sizes[2][0] > 1), "true")

    print ""
    if m.failures = 0 then
        print "ALL PASSED (" + m.count.ToStr() + " checks)"
    else
        print "FAILED: " + m.failures.ToStr() + " of " + m.count.ToStr() + " checks"
    end if
end sub

function osResult(fileId as String, release as String, downloads as Integer, hashMatch as Boolean, machine as Boolean, sdh as Boolean) as String
    attrs = { release: release, download_count: downloads, moviehash_match: hashMatch, machine_translated: machine, hearing_impaired: sdh, files: [{ file_id: fileId.ToInt() }] }
    return FormatJson({ attributes: attrs })
end function

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
