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
    tenths = Int(item.rating.ToFloat() * 10 + 0.5)
    if tenths > 0 then
        whole = tenths \ 10
        fraction = tenths MOD 10
        parts.Push("Rated " + whole.ToStr() + "." + fraction.ToStr())
    end if
    return parts.Join("   ·   ")
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

' Pulls server, username and password out of a pasted get.php / player_api.php link.
function ParseProviderLink(raw as String) as Object
    text = raw.Trim()
    result = { server: NormalizeServer(text), username: "", password: "" }
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

' Every item node gets the full set of custom fields, so screens never read a
' missing field (which would come back invalid and crash string comparisons).
function MakeItem(parent as Object, values as Object) as Object
    fields = {
        kind: ""
        itemId: ""
        seriesId: ""
        ext: ""
        backdrop: ""
        year: ""
        genre: ""
        rating: ""
        cast: ""
        director: ""
        durationSecs: 0
        seasonNumber: 0
        episodeNumber: 0
        hasInfo: false
        placeholder: false
        progress: 0.0
        caption: ""
    }
    fields.Append(values)
    node = parent.CreateChild("ContentNode")
    node.Update(fields, true)
    return node
end function

' Copies details fetched from get_vod_info / get_series_info onto an item node.
sub ApplyInfo(item as Object, info as Dynamic)
    if not IsAA(info) then return
    for each key in ["description", "year", "genre", "rating", "cast", "director", "backdrop", "ext"]
        value = FieldStr(info, key)
        if value <> "" then item.SetField(key, value)
    end for
    duration = ToInt(info.durationSecs)
    if duration > 0 then item.durationSecs = duration
    item.hasInfo = true
end sub

' Shows a backdrop when there is one, otherwise a dimmed, zoomed poster.
sub ShowBackdrop(target as Object, backdrop as String, poster as String)
    if backdrop <> "" then
        uri = backdrop
        target.opacity = 1.0
    else if poster <> "" then
        uri = SizedImage(poster, "w342")
        target.opacity = 0.35
    else
        uri = ""
    end if
    if target.uri <> uri then target.uri = uri
end sub

function MakeFont(name as String, size as Integer) as Object
    f = CreateObject("roSGNode", "Font")
    f.uri = "pkg:/fonts/" + name + ".ttf"
    f.size = size
    return f
end function

function NowSeconds() as Integer
    return CreateObject("roDateTime").AsSeconds()
end function
