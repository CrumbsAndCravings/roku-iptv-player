' Shared helpers. Xtream servers are loose with types (numbers arrive as strings,
' empty objects arrive as []), so everything read from the API goes through these.

function IsAA(value as Dynamic) as Boolean
    return type(value) = "roAssociativeArray"
end function

function IsArr(value as Dynamic) as Boolean
    return type(value) = "roArray"
end function

function ToStr(value as Dynamic) as String
    t = type(value)
    if t = "String" or t = "roString" then return value
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" then return value.ToStr()
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Str(value).Trim()
    if t = "Boolean" or t = "roBoolean" then
        if value then return "true"
        return "false"
    end if
    return ""
end function

function ToInt(value as Dynamic) as Integer
    t = type(value)
    if t = "Integer" or t = "roInt" or t = "roInteger" then return value
    if t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Int(value)
    if t = "String" or t = "roString" then return value.Trim().ToInt()
    if t = "Boolean" or t = "roBoolean" then
        if value then return 1
    end if
    return 0
end function

' Reads aa[key] without crashing when aa is not an associative array.
function Field(aa as Dynamic, key as String) as Dynamic
    if not IsAA(aa) then return invalid
    return aa[key]
end function

function FieldStr(aa as Dynamic, key as String) as String
    return ToStr(Field(aa, key)).Trim()
end function

function FirstText(values as Object) as String
    for each value in values
        text = ToStr(value).Trim()
        if text <> "" then return text
    end for
    return ""
end function

' backdrop_path is usually an array of URLs, sometimes a single string.
function FirstUrl(value as Dynamic) as String
    if IsArr(value) then
        for each entry in value
            url = ToStr(entry).Trim()
            if url <> "" then return url
        end for
        return ""
    end if
    return ToStr(value).Trim()
end function

' TMDB serves every size from the same path, so ask for one that fits a 720p screen.
function SizedImage(url as String, size as String) as String
    marker = "image.tmdb.org/t/p/"
    found = Instr(1, url, marker)
    if found = 0 then return url
    start = found + Len(marker)
    slash = Instr(start, url, "/")
    if slash = 0 then return url
    return Left(url, start - 1) + size + Mid(url, slash)
end function

function YearOf(dateText as String) as String
    year = Left(dateText.Trim(), 4)
    if Len(year) = 4 and year.ToInt() > 1900 then return year
    return ""
end function

' "01:45:30" or "45:30" -> seconds
function ClockToSeconds(clock as String) as Integer
    total = 0
    for each part in clock.Trim().Split(":")
        total = total * 60 + part.ToInt()
    end for
    return total
end function

function Pad2(n as Integer) as String
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
end function

' 5234 -> "1:27:14"
function FormatClock(seconds as Integer) as String
    h = seconds \ 3600
    mins = (seconds MOD 3600) \ 60
    secs = seconds MOD 60
    if h > 0 then return h.ToStr() + ":" + Pad2(mins) + ":" + Pad2(secs)
    return mins.ToStr() + ":" + Pad2(secs)
end function

' 5234 -> "1h 27m"
function FormatRuntime(seconds as Integer) as String
    totalMins = (seconds + 30) \ 60
    h = totalMins \ 60
    mins = totalMins MOD 60
    if h > 0 and mins > 0 then return h.ToStr() + "h " + mins.ToStr() + "m"
    if h > 0 then return h.ToStr() + "h"
    return mins.ToStr() + "m"
end function

function MetaLine(item as Object) as String
    parts = []
    if item.year <> "" then parts.Push(item.year)
    if item.durationSecs > 0 then parts.Push(FormatRuntime(item.durationSecs))
    if item.genre <> "" then
        genres = item.genre.Split(",")
        text = genres[0].Trim()
        if genres.Count() > 1 then text = text + ", " + genres[1].Trim()
        parts.Push(text)
    end if
    tenths = Int(item.score.ToFloat() * 10 + 0.5)
    if tenths > 0 then
        whole = tenths \ 10
        fraction = tenths MOD 10
        parts.Push("Rated " + whole.ToStr() + "." + fraction.ToStr())
    end if
    return parts.Join("   ·   ")
end function

' --- Search ------------------------------------------------------------------

' Lowercases and simplifies text for matching: accents folded, apostrophes dropped,
' other punctuation turned into single spaces. Regexes are built once and reused.
function NormalizeSearch(text as String) as String
    if m.searchRegexes = invalid then
        m.searchRegexes = {
            nonAscii: CreateObject("roRegex", "[^\x00-\x7F]", "")
            folds: [
                [CreateObject("roRegex", "[áàâäãåÁÀÂÄÃÅ]", ""), "a"]
                [CreateObject("roRegex", "[éèêëÉÈÊË]", ""), "e"]
                [CreateObject("roRegex", "[íìîïÍÌÎÏ]", ""), "i"]
                [CreateObject("roRegex", "[óòôöõøÓÒÔÖÕØ]", ""), "o"]
                [CreateObject("roRegex", "[úùûüÚÙÛÜ]", ""), "u"]
                [CreateObject("roRegex", "[ñÑ]", ""), "n"]
                [CreateObject("roRegex", "[çÇ]", ""), "c"]
                [CreateObject("roRegex", "[‘’]", ""), "'"]
            ]
            apostrophes: CreateObject("roRegex", "['`]", "")
            punctuation: CreateObject("roRegex", "[\s\-_.:,;!?""()\[\]{}|/\\&+*#@~<>=]+", "")
        }
    end if
    r = m.searchRegexes
    t = LCase(text)
    if r.nonAscii.IsMatch(t) then
        for each fold in r.folds
            t = fold[0].ReplaceAll(t, fold[1])
        end for
    end if
    t = r.apostrophes.ReplaceAll(t, "")
    t = r.punctuation.ReplaceAll(t, " ")
    return t.Trim()
end function

' --- Xtream URLs -------------------------------------------------------------

' Accepts "example.com:8080", "http://example.com:8080/" or a pasted M3U link,
' and returns just the scheme, host and port.
function NormalizeServer(raw as String) as String
    server = raw.Trim()
    if server = "" then return ""
    lower = LCase(server)
    if Left(lower, 7) <> "http://" and Left(lower, 8) <> "https://" then server = "http://" + server
    schemeEnd = Instr(1, server, "://")
    slash = Instr(schemeEnd + 3, server, "/")
    if slash > 0 then server = Left(server, slash - 1)
    question = Instr(1, server, "?")
    if question > 0 then server = Left(server, question - 1)
    return server
end function

' Pulls server, username and password out of a pasted link: get.php or player_api.php
' with ?username=&password=, or a path like /playlist/<user>/<pass>/m3u_plus (also
' /live/, /movie/ and /series/ stream links).
function ParseProviderLink(raw as String) as Object
    text = raw.Trim()
    result = { server: NormalizeServer(text), username: "", password: "" }
    path = CreateObject("roRegex", "^[a-z]+://[^/?]+/(playlist|live|movie|series)/([^/?]+)/([^/?]+)", "i").Match(text)
    if path.Count() > 3 then
        result.username = path[2].DecodeUriComponent()
        result.password = path[3].DecodeUriComponent()
        return result
    end if
    question = Instr(1, text, "?")
    if question = 0 then return result
    query = Mid(text, question + 1)
    for each pair in query.Split("&")
        eq = Instr(1, pair, "=")
        if eq > 0 then
            key = LCase(Left(pair, eq - 1))
            value = Mid(pair, eq + 1)
            value = value.DecodeUriComponent()
            if key = "username" then result.username = value
            if key = "password" then result.password = value
        end if
    end for
    return result
end function

function ApiUrl(creds as Object, action as String, params as Dynamic) as String
    url = creds.server + "/player_api.php?username=" + creds.username.EncodeUriComponent() + "&password=" + creds.password.EncodeUriComponent()
    if action <> "" then url = url + "&action=" + action
    if IsAA(params) then
        for each key in params
            value = ToStr(params[key])
            url = url + "&" + key + "=" + value.EncodeUriComponent()
        end for
    end if
    return url
end function

' --- HTTP errors ------------------------------------------------------------

' One short line from an error page: scripts, tags and extra spaces removed.
function BriefText(body as String, limit as Integer) as String
    text = CreateObject("roRegex", "<(script|style)[^>]*>.*?</(script|style)>", "is").ReplaceAll(body, " ")
    text = CreateObject("roRegex", "<[^>]*>", "s").ReplaceAll(text, " ")
    text = CreateObject("roRegex", "&nbsp;", "i").ReplaceAll(text, " ")
    text = CreateObject("roRegex", "\s+", "").ReplaceAll(text, " ").Trim()
    ' Error pages often repeat their title as a heading: "404 Not Found 404 Not Found".
    repeated = CreateObject("roRegex", "^(.{4,60}?) \1(?: |$)", "").Match(text)
    if repeated.Count() > 1 then text = (repeated[1] + " " + Mid(text, Len(repeated[0]) + 1)).Trim()
    if Len(text) > limit then text = Left(text, limit - 1).Trim() + "…"
    return text
end function

' The HTTP status inside Roku's playback error text, like "response code:(403)", or 0.
function HttpCodeIn(text as String) as Integer
    found = CreateObject("roRegex", "(?:response code|http)[^0-9]{0,12}([45]\d\d)\b", "i").Match(text)
    if found.Count() > 1 then return found[1].ToInt()
    return 0
end function

' How ARAN+ introduces itself when a provider turns away requests that say "Roku".
function AppUserAgent() as String
    return "ARANplus/0.5.4"
end function

' A plain desktop web browser, for providers whose servers only answer browsers (a
' phone's browser gets in while the Roku gets "404 Not Found").
function BrowserUserAgent() as String
    return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
end function

' The ways ARAN+ can introduce itself, starting with `current`: "" is Roku's own.
function UserAgentsToTry(current as String) as Object
    agents = [current]
    for each agent in ["", AppUserAgent(), BrowserUserAgent()]
        if agent <> current then agents.Push(agent)
    end for
    return agents
end function

' "as a Roku", "as ARAN+" or "as a web browser", for messages.
function UserAgentName(agent as String) as String
    if agent = "" then return "as a Roku"
    if agent = BrowserUserAgent() then return "as a web browser"
    return "as ARAN+"
end function

' True when Cloudflare itself turned the request away, with one of its own pages.
function IsCloudflareBlock(headers as Dynamic, body as String) as Boolean
    return IsCloudflare(headers) and CloudflareKind(headers, body) <> ""
end function

' Statuses that mean "not you, not now", where asking again only makes it worse.
function IsRefusalCode(code as Integer) as Boolean
    return code = 401 or code = 403 or code = 429
end function

' True when the answer passed through Cloudflare (it may still come from the provider).
function IsCloudflare(headers as Dynamic) as Boolean
    return Instr(1, LCase(FieldStr(headers, "server")), "cloudflare") > 0 or FieldStr(headers, "cf-ray") <> ""
end function

' What kind of Cloudflare refusal it was: a browser check (it needs JavaScript, so no TV
' app can pass it), a numbered error, or a plain block.
function CloudflareKind(headers as Dynamic, body as String) as String
    text = BriefText(body, 4000)
    lower = LCase(text)
    if LCase(FieldStr(headers, "cf-mitigated")) = "challenge" then return " (browser check)"
    if Instr(1, lower, "just a moment") > 0 or Instr(1, LCase(body), "challenge-platform") > 0 then return " (browser check)"
    found = CreateObject("roRegex", "(?:error code:?|error)\s*(1\d{3})", "i").Match(text)
    if found.Count() > 1 then return " (error " + found[1] + ")"
    if Instr(1, lower, "you have been blocked") > 0 then return " (blocked)"
    return ""
end function

' Sums up a failed response, like: HTTP 403 from nginx: "Forbidden". A photo of the
' screen then shows who answered and what they said.
function HttpDetail(code as Integer, headers as Dynamic, body as String) as String
    detail = "HTTP " + code.ToStr()
    if IsCloudflare(headers) then
        kind = CloudflareKind(headers, body)
        if kind <> "" then return detail + " from Cloudflare" + kind
        ' Every answer from a site behind Cloudflare carries its name, so without one of
        ' Cloudflare's own pages this most likely came from the provider's server.
        detail = detail + " via Cloudflare"
    else
        software = CreateObject("roRegex", "[/ (]", "").Split(FieldStr(headers, "server"))
        if software.Count() > 0 and software[0] <> "" then detail = detail + " from " + software[0]
    end if

    trimmed = body.Trim()
    said = ""
    if Left(trimmed, 1) = "{" then
        data = ParseJson(trimmed)
        said = FirstText([Field(data, "message"), Field(data, "error")])
    end if
    if said = "" then said = trimmed
    said = BriefText(said, 70)
    if said = "" then return detail + ", no reason given"
    return detail + ": " + Chr(34) + said + Chr(34)
end function

' kind is "movie", "series" or "live"
function StreamUrl(creds as Object, kind as String, id as String, ext as String) as String
    return creds.server + "/" + kind + "/" + creds.username.EncodeUriComponent() + "/" + creds.password.EncodeUriComponent() + "/" + id + "." + ext
end function

function StreamFormatFor(ext as String) as String
    e = LCase(ext)
    if e = "m3u8" then return "hls"
    if e = "mp4" or e = "m4v" or e = "mov" then return "mp4"
    if e = "mkv" then return "mkv"
    return ""
end function

' --- Content nodes -------------------------------------------------------------

' Custom fields every item node gets, so screens never read a missing field (which
' would come back invalid and crash string comparisons).
' Names must not match ContentNode's built-in metadata fields: a built-in keeps its own
' type and silently drops our value (EpisodeNumber, for one, is a string).
function ItemDefaults() as Object
    return {
        kind: ""
        itemId: ""
        seriesId: ""
        ext: ""
        backdrop: ""
        year: ""
        genre: ""
        score: ""
        starring: ""
        directedBy: ""
        durationSecs: 0
        seasonNo: 0
        episodeNo: 0
        videoCodec: ""
        videoProfile: ""
        audioCodec: ""
        problem: ""
        tmdbId: ""
        hasInfo: false
        placeholder: false
        progress: 0.0
        caption: ""
        categoryId: ""
        listKind: ""
    }
end function

function MakeItem(parent as Object, values as Object) as Object
    fields = ItemDefaults()
    fields.Append(values)
    node = parent.CreateChild("ContentNode")
    node.Update(fields, true)
    return node
end function

' Copies details fetched from get_vod_info / get_series_info onto an item node.
sub ApplyInfo(item as Object, info as Dynamic)
    if not IsAA(info) then return
    for each key in ["description", "year", "genre", "score", "starring", "directedBy", "backdrop", "ext", "videoCodec", "videoProfile", "audioCodec", "tmdbId"]
        value = FieldStr(info, key)
        if value <> "" then item.SetField(key, value)
    end for
    duration = ToInt(info.durationSecs)
    if duration > 0 then item.durationSecs = duration
    item.hasInfo = true
end sub

' "S1:E2"
function EpisodeCode(seasonNo as Dynamic, episodeNo as Dynamic) as String
    return "S" + ToInt(seasonNo).ToStr() + ":E" + ToInt(episodeNo).ToStr()
end function

' Provider codec name (ffprobe style) -> "HEVC (H.265)"
function CodecLabel(codec as String) as String
    names = { h264: "H.264", avc: "H.264", hevc: "HEVC (H.265)", h265: "HEVC (H.265)", mpeg4: "MPEG-4 (DivX/Xvid)", mpeg2video: "MPEG-2", vp9: "VP9", av1: "AV1", wmv3: "Windows Media", vc1: "VC-1", aac: "AAC", ac3: "Dolby AC-3", eac3: "Dolby E-AC-3", dts: "DTS", mp3: "MP3", truehd: "Dolby TrueHD", opus: "Opus", flac: "FLAC", vorbis: "Vorbis" }
    label = names[LCase(codec)]
    if label = invalid then return UCase(codec)
    return label
end function

' "HEVC (H.265) Main 10 video, Dolby E-AC-3 audio"
function DescribeCodecs(videoCodec as String, videoProfile as String, audioCodec as String) as String
    parts = []
    if videoCodec <> "" then
        label = CodecLabel(videoCodec)
        if videoProfile <> "" then label = label + " " + videoProfile
        parts.Push(label + " video")
    end if
    if audioCodec <> "" then parts.Push(CodecLabel(audioCodec) + " audio")
    return parts.Join(", ")
end function

' Containers no Roku device plays, whatever codecs are inside.
function IsUnsupportedContainer(ext as String) as Boolean
    e = LCase(ext)
    for each bad in ["avi", "divx", "wmv", "asf", "flv", "rm", "rmvb"]
        if e = bad then return true
    end for
    return false
end function

' Plain-English explanation for a file this TV can't play. `blocked` comes from PlaybackCheck.
function UnplayableText(blocked as String, ext as String) as String
    if IsUnsupportedContainer(ext) then
        return "This is an " + UCase(ext) + " file. Roku devices can't play " + UCase(ext) + " files, so no Roku app can play this one. Your provider may have another version of this title."
    end if
    if DeviceWord() = "TV" then
        return "This file uses " + blocked + ", which this TV's hardware can't decode, so no app on this TV can play it. Most current Roku streaming sticks can, and this app would run on one plugged into the TV."
    end if
    return "This file uses " + blocked + ", which this Roku can't decode, so no app on it can play this file. Your provider may have another version of this title."
end function

' True when the Roku is sending a 4K picture to the screen.
function IsUhdScreen() as Boolean
    mode = LCase(CreateObject("roDeviceInfo").GetVideoMode())
    return Instr(1, mode, "2160") > 0 or Instr(1, mode, "4k") > 0
end function

' "TV" on a Roku TV, "Roku" on a streaming stick or box, for messages.
function DeviceWord() as String
    if m.deviceWord = invalid then
        m.deviceWord = "Roku"
        if CreateObject("roDeviceInfo").GetModelType() = "TV" then m.deviceWord = "TV"
    end if
    return m.deviceWord
end function

' Maps provider codec names to the names roDeviceInfo.CanDecodeVideo/Audio expects.
function RokuVideoCodec(videoCodec as String) as String
    c = LCase(videoCodec)
    if c = "h264" or c = "avc" then return "mpeg4 avc"
    if c = "mpeg2video" then return "mpeg2"
    if c = "mpeg4" then return "mpeg4 2"
    return c
end function

' Points `target` at the backdrop, or at a dimmed, zoomed poster when there is none, and
' returns the opacity it should end at. A new picture starts hidden so the screen can
' fade it in once it has loaded.
function ShowBackdrop(target as Object, backdrop as String, poster as String) as Float
    opacity = 1.0
    uri = ""
    if backdrop <> "" then
        uri = backdrop
    else if poster <> "" then
        uri = SizedImage(poster, "w342")
        opacity = 0.35
    end if
    if target.uri <> uri then
        target.opacity = 0.0
        target.uri = uri
    else
        target.opacity = opacity
    end if
    return opacity
end function

function MakeFont(name as String, size as Integer) as Object
    f = CreateObject("roSGNode", "Font")
    f.uri = "pkg:/fonts/" + name + ".ttf"
    f.size = size
    return f
end function

' Where the search index is kept between launches. cachefs: survives restarts of the
' app, though Roku may clear it when it needs the space.
function SearchCachePath() as String
    return "cachefs:/aranplus-search.txt"
end function

' "EN ★ Alterity - 2026" -> { title: "Alterity", year: "2026" }. Some providers put a
' language tag in front of every title (2 to 4 capitals and a symbol like ★ or |) and
' the year at the end.
function SplitTitle(name as String) as Object
    title = name.Trim()
    letters = 0
    while letters < Len(title) and letters < 5
        c = Asc(Mid(title, letters + 1, 1))
        if c < 65 or c > 90 then exit while
        letters = letters + 1
    end while
    if letters >= 2 and letters <= 4 then
        rest = Mid(title, letters + 1).Trim()
        mark = Left(rest, 1)
        if mark = "|" or (mark <> "" and Asc(mark) > 383) then
            rest = Mid(rest, 2).Trim()
            if rest <> "" then title = rest
        end if
    end if
    year = ""
    found = CreateObject("roRegex", "^(.*\S)\s+-\s+((?:19|20)\d\d)$", "").Match(title)
    if found.Count() > 2 then
        title = found[1]
        year = found[2]
    end if
    return { title: title, year: year }
end function

' The text behind a login's sync "space": the server in lower case without a default
' port, a newline, then the username. Every device signed in to the same provider
' account gets the same text, so the same Continue Watching list. The space itself is
' the first 16 hex digits of its SHA-256 (SyncSpace in Registry.brs).
function SyncSpaceText(creds as Object) as String
    server = LCase(NormalizeServer(FieldStr(creds, "server")))
    if Left(server, 7) = "http://" and Right(server, 3) = ":80" then server = Left(server, Len(server) - 3)
    if Left(server, 8) = "https://" and Right(server, 4) = ":443" then server = Left(server, Len(server) - 4)
    return server + Chr(10) + FieldStr(creds, "username")
end function

' Where the helper on a computer at home is (common/Helper.brs), from a personal
' build's account.json: "transcoder": { url, key }, the values the helper wrote into
' its own personal.json. { url, key } without a trailing "/", or invalid.
function TranscoderSettings(data as Dynamic) as Dynamic
    settings = Field(data, "transcoder")
    url = FieldStr(settings, "url")
    key = FieldStr(settings, "key")
    if url = "" or key = "" then return invalid
    while Right(url, 1) = "/"
        url = Left(url, Len(url) - 1)
    end while
    return { url: url, key: key }
end function

' The OpenSubtitles account a personal build carries (account.json "opensubtitles":
' { apiKey, username, password }), or invalid.
function OsAccountSettings(data as Dynamic) as Dynamic
    settings = Field(data, "opensubtitles")
    apiKey = FieldStr(settings, "apiKey")
    if apiKey = "" then return invalid
    return { apiKey: apiKey, username: FieldStr(settings, "username"), password: FieldStr(settings, "password") }
end function

' Which OpenSubtitles account to use: the one saved on this Roku (`saved`, the
' registry's text), else the build's own (`builtIn`), unless it was removed here on
' purpose ({ removed: true } saved). invalid for none.
function PickOsAccount(saved as Dynamic, builtIn as Dynamic) as Dynamic
    if saved <> invalid then
        account = ParseJson(ToStr(saved))
        if IsAA(account) then
            if FieldStr(account, "apiKey") <> "" then return account
            if FieldStr(account, "removed") = "true" then return invalid
        end if
    end if
    if IsAA(builtIn) and FieldStr(builtIn, "apiKey") <> "" then return builtIn
    return invalid
end function

' 1234567 -> "1,234,567"
function Commas(value as Integer) as String
    digits = Abs(value).ToStr()
    out = ""
    while Len(digits) > 3
        out = "," + Right(digits, 3) + out
        digits = Left(digits, Len(digits) - 3)
    end while
    out = digits + out
    if value < 0 then out = "-" + out
    return out
end function

' The session's library worker (search and category pages), started on first use and
' kept in m.global.search until sign-out.
function LibraryTask() as Object
    task = m.global.search
    if task = invalid then
        task = CreateObject("roSGNode", "SearchTask")
        m.global.search = task
        task.control = "RUN"
    end if
    return task
end function

function NowSeconds() as Integer
    return CreateObject("roDateTime").AsSeconds()
end function
