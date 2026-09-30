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
