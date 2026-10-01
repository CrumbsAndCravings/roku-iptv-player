sub init()
    m.top.functionName = "work"
end sub

sub work()
    req = m.top.request
    mode = FieldStr(req, "mode")
    m.account = req.account
    m.videoAgent = FieldStr(req, "userAgent")
    m.accountChanged = false
    if mode = "login" then
        result = osCheck()
    else if mode = "find" then
        result = osFind(req)
    else if mode = "download" then
        result = osDownload(req)
    else
        result = { ok: false, error: "Unknown request." }
    end if
    if m.accountChanged then result.account = m.account
    result.request = req
    m.top.result = result
end sub

' --- HTTP -----------------------------------------------------------------------

function osBase() as String
    host = FieldStr(m.account, "baseUrl")
    if host = "" then host = "api.opensubtitles.com"
    return "https://" + host + "/api/v1"
end function

function osRequest(method as String, path as String, body as Dynamic) as Object
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(osBase() + path)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.RetainBodyOnError(true)
    http.AddHeader("Api-Key", FieldStr(m.account, "apiKey"))
    http.AddHeader("User-Agent", "ARANplus v0.4.0")
    http.AddHeader("Accept", "application/json")
    token = FieldStr(m.account, "token")
    if token <> "" then http.AddHeader("Authorization", "Bearer " + token)
    if method = "POST" then
        http.AddHeader("Content-Type", "application/json")
        started = http.AsyncPostFromString(FormatJson(body))
    else
        started = http.AsyncGetToString()
    end if
    if not started then return { ok: false, code: 0, data: invalid }

    msg = Wait(20000, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return { ok: false, code: 0, data: invalid, error: "OpenSubtitles took too long to answer." }
    end if
    code = msg.GetResponseCode()
    return { ok: code >= 200 and code < 300, code: code, data: ParseJson(msg.GetString()) }
end function

' Puts OpenSubtitles' own words and the HTTP code in the message, so a photo of the
' screen says exactly what went wrong.
function osError(res as Object) as String
    if FieldStr(res, "error") <> "" then return res.error
    message = serverMessage(res.data)
    code = res.code
    if code < 0 or code = 0 then return "Couldn't reach OpenSubtitles. Check the internet connection."
    said = "OpenSubtitles said HTTP " + code.ToStr()
    if message <> "" then said = said + ": " + message
    if code = 406 or code = 429 then return said + ". Downloads reset within a day."
    return said + "."
end function

function serverMessage(data as Dynamic) as String
    message = FieldStr(data, "message")
    if message <> "" then return message
    errors = Field(data, "errors")
    if IsArr(errors) then
        parts = []
        for each e in errors
            text = ToStr(e)
            if text <> "" then parts.Push(text)
        end for
        return parts.Join(" ")
    end if
    return ""
end function

' Signs in with the saved username and password, keeping the token and the server
' OpenSubtitles says to use (VIP accounts get their own).
function osLogin() as Object
    m.account.token = ""
    res = osRequest("POST", "/login", { username: FieldStr(m.account, "username"), password: FieldStr(m.account, "password") })
    if not res.ok then return res
    m.account.token = FieldStr(res.data, "token")
    baseUrl = FieldStr(res.data, "base_url")
    if baseUrl <> "" then m.account.baseUrl = baseUrl
    m.accountChanged = true
    return res
end function

' --- Modes ----------------------------------------------------------------------

' Checks the key on its own first, then the login, so the message says which one failed.
function osCheck() as Object
    if FieldStr(m.account, "apiKey") = "" then return { ok: false, keyOk: false, error: "Enter your OpenSubtitles API key first." }
    res = osRequest("GET", "/infos/formats", invalid)
    if not res.ok then return { ok: false, keyOk: false, error: "The API key didn't work. " + osError(res) }
    if FieldStr(m.account, "username") = "" then return { ok: true, keyOk: true, name: "", allowed: 5 }
    res = osLogin()
    if not res.ok then return { ok: false, keyOk: true, error: "The key works, but the login didn't. " + osError(res) + " Use your username, not your email." }
    user = Field(res.data, "user")
    return { ok: true, keyOk: true, name: FieldStr(m.account, "username"), allowed: ToInt(Field(user, "allowed_downloads")) }
end function

function osFind(req as Object) as Object
    hash = ""
    videoUrl = FieldStr(req, "videoUrl")
    if videoUrl <> "" then hash = fileHash(videoUrl)

    params = { languages: "en" }
    if hash <> "" then params.moviehash = hash
    if FieldStr(req, "kind") = "episode" then
        params.type = "episode"
        params.season_number = ToInt(req.season)
        params.episode_number = ToInt(req.episode)
        if FieldStr(req, "parentTmdbId") <> "" then
            params.parent_tmdb_id = FieldStr(req, "parentTmdbId")
        else
            params.query = CleanTitleForSearch(FieldStr(req, "title")).query
        end if
    else
        params.type = "movie"
        if FieldStr(req, "tmdbId") <> "" then
            params.tmdb_id = FieldStr(req, "tmdbId")
        else
            cleaned = CleanTitleForSearch(FieldStr(req, "title"))
            params.query = cleaned.query
            if cleaned.year <> "" then params.year = cleaned.year
        end if
    end if

    res = osRequest("GET", "/subtitles?" + OsQuery(params), invalid)
    if not res.ok then return { ok: false, error: osError(res) }
    candidates = ParseOsResults(res.data)

    ' A title search is the fallback when the TMDB id finds nothing.
    if candidates.Count() = 0 and (params.DoesExist("tmdb_id") or params.DoesExist("parent_tmdb_id")) then
        params.Delete("tmdb_id")
        params.Delete("parent_tmdb_id")
        cleaned = CleanTitleForSearch(FieldStr(req, "title"))
        params.query = cleaned.query
        if params.type = "movie" and cleaned.year <> "" then params.year = cleaned.year
        res = osRequest("GET", "/subtitles?" + OsQuery(params), invalid)
        if res.ok then candidates = ParseOsResults(res.data)
    end if
    return { ok: true, candidates: candidates, hashUsed: hash <> "" }
end function

function osDownload(req as Object) as Object
    body = { file_id: ToInt(req.fileId) }
    shift = req.shift
    if shift <> invalid and shift <> 0 then body.timeshift = shift
    res = osRequest("POST", "/download", body)
    ' Tokens expire; sign in again once and retry.
    if (res.code = 401 or res.code = 403) and FieldStr(m.account, "username") <> "" then
        login = osLogin()
        if login.ok then res = osRequest("POST", "/download", body)
    end if
    if not res.ok then return { ok: false, error: osError(res) }
    link = FieldStr(res.data, "link")
    if link = "" then return { ok: false, error: "OpenSubtitles didn't send a subtitle file." }
    return { ok: true, link: link, remaining: ToInt(Field(res.data, "remaining")) }
end function

' --- File fingerprint ----------------------------------------------------------------

' Reads the first and last 64 KB of the video with range requests. Best effort: any
' server that doesn't support ranges just means no fingerprint.
function fileHash(url as String) as String
    head = rangeBytes(url, "bytes=0-65535", "tmp:/oshash-head.bin")
    if head = invalid then return ""
    total = head.total
    if total < 131072 then return ""
    tailStart = total - 65536
    tailEnd = total - 1
    tail = rangeBytes(url, "bytes=" + tailStart.ToStr() + "-" + tailEnd.ToStr(), "tmp:/oshash-tail.bin")
    if tail = invalid then return ""
    return OsHashHex(head.bytes, tail.bytes, total)
end function

function rangeBytes(url as String, range as String, path as String) as Dynamic
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    if m.videoAgent <> "" then http.AddHeader("User-Agent", m.videoAgent)
    http.AddHeader("Range", range)
    DeleteFile(path)
    if not http.AsyncGetToFile(path) then return invalid
    ' A server that ignores Range would send the whole film, so give up quickly.
    msg = Wait(8000, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        DeleteFile(path)
        return invalid
    end if
    total = ParseContentRangeTotal(FieldStr(msg.GetResponseHeaders(), "content-range"))
    bytes = CreateObject("roByteArray")
    ok = msg.GetResponseCode() = 206 and total > 0 and bytes.ReadFile(path)
    DeleteFile(path)
    if not ok or bytes.Count() <> 65536 then return invalid
    return { bytes: bytes, total: total }
end function
