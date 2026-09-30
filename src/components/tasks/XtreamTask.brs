sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    req = m.top.request
    mode = FieldStr(req, "mode")
    if mode = "auth" then
        result = runAuth(req.creds)
    else if mode = "categories" then
        result = runCategories(FieldStr(req, "kind"))
    else if mode = "row" then
        result = runRow(req)
    else if mode = "vodInfo" then
        result = runVodInfo(FieldStr(req, "id"))
    else if mode = "seriesInfo" then
        result = runSeriesInfo(FieldStr(req, "id"))
    else
        result = { ok: false, error: "Unknown request." }
    end if
    result.request = req
    m.top.result = result
end sub

function fetchJson(url as String) as Object
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.EnableEncodings(true)
    http.RetainBodyOnError(true)
    if not http.AsyncGetToString() then return { ok: false, error: "Couldn't start the request." }

    msg = Wait(45000, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return { ok: false, error: "The server took too long to answer." }
    end if

    code = msg.GetResponseCode()
    if code < 0 then return { ok: false, error: "Couldn't reach the server (" + msg.GetFailureReason() + ")." }
    if code = 401 or code = 403 then return { ok: false, error: "The server refused the login (HTTP " + code.ToStr() + ")." }
    if code <> 200 then return { ok: false, error: "The server answered with HTTP " + code.ToStr() + "." }

    data = ParseJson(msg.GetString())
    if data = invalid then return { ok: false, error: "The server's answer wasn't readable. Check the server address." }
    return { ok: true, data: data }
end function

function runAuth(creds as Object) as Object
    res = fetchJson(ApiUrl(creds, "", invalid))
    if not res.ok then return res
    return ParseAuth(res.data)
end function

function runCategories(kind as String) as Object
    action = "get_vod_categories"
    if kind = "series" then action = "get_series_categories"
    if kind = "live" then action = "get_live_categories"
    res = fetchJson(ApiUrl(m.global.creds, action, invalid))
    if not res.ok then return res
    return { ok: true, categories: ParseCategories(res.data) }
end function

function runRow(req as Object) as Object
    kind = FieldStr(req, "kind")
    limit = ToInt(req.limit)
    if limit <= 0 then limit = 40
    action = "get_vod_streams"
    if kind = "series" then action = "get_series"
    res = fetchJson(ApiUrl(m.global.creds, action, { category_id: FieldStr(req, "categoryId") }))
    if not res.ok then return res
    row = BuildRow(res.data, kind, FieldStr(req, "title"), limit)
    m.top.content = row
    return { ok: true, count: row.GetChildCount() }
end function

function runVodInfo(id as String) as Object
    res = fetchJson(ApiUrl(m.global.creds, "get_vod_info", { vod_id: id }))
    if not res.ok then return res
    return { ok: true, info: ParseVodInfo(res.data) }
end function

function runSeriesInfo(id as String) as Object
    res = fetchJson(ApiUrl(m.global.creds, "get_series_info", { series_id: id }))
    if not res.ok then return res
    parsed = ParseSeriesInfo(res.data)
    m.top.content = parsed.content
    return { ok: true, info: parsed.info }
end function
