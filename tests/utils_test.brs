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
    check("Describe hevc", DescribeCodecs("hevc", "Main 10", "eac3"), "HEVC Main 10 video, Dolby E-AC-3 audio")
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
