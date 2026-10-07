sub init()
    m.top.functionName = "work"
end sub

sub work()
    req = m.top.request
    mode = FieldStr(req, "mode")
    if mode = "subtitle-get" then
        result = subtitleGet(req)
    else if mode = "subtitle-save" then
        result = subtitleSave(req)
    else if mode = "subtitle-delay" then
        result = subtitlePost(req, { fileId: FieldStr(req, "fileId"), delayMs: ToInt(req.delayMs) })
    else
        result = progressRound(req)
    end if
    m.top.result = result
end sub

' One request to the sync service: a GET without a body, a POST of `body` as JSON.
' -> { code, text, error } (code 0 when there was no answer).
function syncRequest(req as Object, path as String, body as Dynamic) as Object
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(FieldStr(req, "url") + path)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.RetainBodyOnError(true)
    http.AddHeader("Authorization", "Bearer " + FieldStr(req, "key"))
    started = false
    if body = invalid then
        started = http.AsyncGetToString()
    else
        http.AddHeader("Content-Type", "application/json")
        started = http.AsyncPostFromString(FormatJson(body))
    end if
    if not started then return { code: 0, text: "", error: "Couldn't start the request." }
    msg = Wait(20000, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return { code: 0, text: "", error: "The sync service took too long to answer." }
    end if
    code = msg.GetResponseCode()
    error = ""
    if code <> 200 then error = "The sync service answered HTTP " + code.ToStr() + "."
    return { code: code, text: msg.GetString(), error: error }
end function

' Continue Watching: sends this Roku's list and removals, gets back the merged state.
' After the account moved to a new address, `previous` names the old address's space:
' its list and removals are fetched and sent along, once (movedIn says it's done).
function progressRound(req as Object) as Object
    entries = req.entries
    removed = req.removed
    movedIn = false
    previous = FieldStr(req, "previous")
    if previous <> "" and previous <> FieldStr(req, "space") then
        old = syncRequest(req, "/v1/progress?space=" + previous, invalid)
        if old.code <> 200 then return { ok: false, error: old.error }
        state = ParseJson(old.text)
        if IsAA(state) then
            if IsArr(state.entries) then entries.Append(state.entries)
            if IsArr(state.removed) then removed.Append(state.removed)
        end if
        movedIn = true
    end if
    res = syncRequest(req, "/v1/progress?space=" + FieldStr(req, "space"), { entries: entries, removed: removed })
    if res.code <> 200 then return { ok: false, error: res.error }
    state = ParseJson(res.text)
    if not IsAA(state) then return { ok: false, error: "The sync service's answer wasn't readable." }
    return { ok: true, state: state, movedIn: movedIn }
end function

' --- Subtitles saved for a title (sync/worker.js) --------------------------------------

function subtitlePath(req as Object) as String
    return "/v1/subtitles?space=" + FieldStr(req, "space") + "&k=" + FieldStr(req, "title").EncodeUriComponent()
end function

' The subtitles saved for this title by any device, without the file itself:
' -> { ok, title, found, fileId, name, delayMs, file }
function subtitleGet(req as Object) as Object
    res = syncRequest(req, subtitlePath(req) + "&text=0", invalid)
    result = { ok: false, title: FieldStr(req, "title"), found: false, error: res.error }
    if res.code <> 200 then return result
    data = ParseJson(res.text)
    if not IsAA(data) then return result
    result.ok = true
    if ToStr(Field(data, "found")) = "true" and FieldStr(data, "file") <> "" then
        result.found = true
        result.fileId = FieldStr(data, "fileId")
        result.name = FieldStr(data, "name")
        result.delayMs = ToInt(Field(data, "delayMs"))
        result.file = FieldStr(data, "file")
    end if
    return result
end function

' A download from OpenSubtitles (its link), saved for this title for every device.
' -> { ok, title, fileId, name, file }
function subtitleSave(req as Object) as Object
    result = { ok: false, title: FieldStr(req, "title"), fileId: FieldStr(req, "fileId"), name: FieldStr(req, "name") }
    text = fetchText(FieldStr(req, "link"))
    if text.Trim() = "" then return result
    res = subtitlePost(req, { fileId: result.fileId, name: result.name, delayMs: 0, text: text })
    if res.ok then
        result.ok = true
        result.file = res.file
    end if
    return result
end function

' The file behind OpenSubtitles' download link, or "" when it doesn't arrive.
function fetchText(url as String) as String
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    if not http.AsyncGetToString() then return ""
    msg = Wait(20000, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return ""
    end if
    if msg.GetResponseCode() <> 200 then return ""
    return msg.GetString()
end function

function subtitlePost(req as Object, body as Object) as Object
    res = syncRequest(req, subtitlePath(req), body)
    data = ParseJson(res.text)
    if res.code <> 200 or not IsAA(data) then return { ok: false, title: FieldStr(req, "title"), error: res.error }
    return { ok: true, title: FieldStr(req, "title"), file: FieldStr(data, "file") }
end function
