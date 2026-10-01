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
    check("cloudflare by ray", IsCloudflare({ "CF-RAY": "8abc" }).ToStr(), "true")
    check("not cloudflare", IsCloudflare({ server: "nginx" }).ToStr(), "false")
    long = String(200, "x")
    checkInt("brief text cut", Len(BriefText(long, 70)), 70)
    check("brief text spaces", BriefText(" a" + Chr(10) + Chr(9) + "b&nbsp;c ", 70), "a b c")
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
    check("Unplayable HEVC text", Left(UnplayableText("HEVC (H.265) video", "mkv"), 81), "This file uses HEVC (H.265) video, which this TV's hardware can't decode, so no a")
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
    check("os label sdh", SubtitleLabel(results[2]), "English · SDH.Release · SDH")
    check("os label machine", SubtitleLabel(results[3]), "English · Machine · auto-translated")
    checkInt("os results empty", ParseOsResults(ParseJson("{""data"":[]}")).Count(), 0)
    checkInt("os results garbage", ParseOsResults(invalid).Count(), 0)

    ' Episode title cleanup (same pattern as XtreamTask)
    prefix = CreateObject("roRegex", "^.*?S\d+\s*E\d+\s*[-:.]*\s*", "i")
    check("Episode prefix", prefix.Replace("Breaking Bad - S01E02 - Cat's in the Bag", ""), "Cat's in the Bag")
    check("Episode no prefix", prefix.Replace("Pilot", ""), "Pilot")

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
