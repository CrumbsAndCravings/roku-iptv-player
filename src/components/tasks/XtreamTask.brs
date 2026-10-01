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

function api(creds as Object, action as String, params as Dynamic) as Object
    return fetchJson(ApiUrl(creds, action, params), FieldStr(creds, "userAgent"))
end function

function runAuth(creds as Object) as Object
    res = api(creds, "", invalid)
    ' Some providers' Cloudflare rules turn away anything that says it's a Roku. Try once
    ' as ARAN+ itself, and keep using that for this server if it gets through.
    triedApp = false
    if cloudflareRefused(res) and FieldStr(creds, "userAgent") = "" then
        triedApp = true
        creds.userAgent = AppUserAgent()
        res = api(creds, "", invalid)
        if cloudflareRefused(res) then creds.userAgent = ""
    end if
    if not res.ok then
        ' The address shows typos (a missing port, http vs https) at a glance.
        text = res.error + Chr(10) + "Address: " + creds.server
        code = ToInt(res.code)
        if cloudflareRefused(res) then
            if triedApp then text = text + Chr(10) + "Asking again as ARAN+ instead of as a Roku didn't get through either."
            text = text + Chr(10) + "Only the provider can allow it, or give you another address."
        else if code = 401 or code = 403 then
            text = text + Chr(10) + "Often a typo in the login, a trial that isn't active yet or only works in certain apps, or a block on this network."
        end if
        res.error = text
        return res
    end if
    return ParseAuth(res.data)
end function

function cloudflareRefused(res as Object) as Boolean
    if res.ok or res.cloudflare = invalid or res.cloudflare <> true then return false
    code = ToInt(res.code)
    return code = 401 or code = 403 or code = 503
end function

function runCategories(kind as String) as Object
    action = "get_vod_categories"
    if kind = "series" then action = "get_series_categories"
    if kind = "live" then action = "get_live_categories"
    res = api(m.global.creds, action, invalid)
    if not res.ok then return res
    return { ok: true, categories: ParseCategories(res.data) }
end function

function runRow(req as Object) as Object
    kind = FieldStr(req, "kind")
    limit = ToInt(req.limit)
    if limit <= 0 then limit = 40
    action = "get_vod_streams"
    if kind = "series" then action = "get_series"
    res = api(m.global.creds, action, { category_id: FieldStr(req, "categoryId") })
    if not res.ok then return res
    row = BuildRow(res.data, kind, FieldStr(req, "title"), limit)
    m.top.content = row
    return { ok: true, count: row.GetChildCount() }
end function

function runVodInfo(id as String) as Object
    res = api(m.global.creds, "get_vod_info", { vod_id: id })
    if not res.ok then return res
    return { ok: true, info: ParseVodInfo(res.data) }
end function

function runSeriesInfo(id as String) as Object
    res = api(m.global.creds, "get_series_info", { series_id: id })
    if not res.ok then return res
    parsed = ParseSeriesInfo(res.data)
    m.top.content = parsed.content
    return { ok: true, info: parsed.info }
end function
