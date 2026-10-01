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
    else if mode = "probe" then
        result = runProbe(req)
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
    ' Some providers turn away apps they don't recognise: Cloudflare rules that refuse
    ' anything saying "Roku", or servers that answer "404 Not Found" to anything but a
    ' web browser. When the answer looks like that, ask again as ARAN+, then as a web
    ' browser, and keep whichever gets through for this server.
    agents = UserAgentsToTry(FieldStr(creds, "userAgent"))
    tried = 0
    for each agent in agents
        creds.userAgent = agent
        res = api(creds, "", invalid)
        tried = tried + 1
        if not clientTurnedAway(res) then exit for
    end for
    if clientTurnedAway(res) then creds.userAgent = agents[0]
    if not res.ok then
        ' The address shows typos (a missing port, http vs https) at a glance.
        text = res.error + Chr(10) + "Address: " + creds.server
        code = ToInt(res.code)
        if tried > 1 and clientTurnedAway(res) then text = text + Chr(10) + "Asking again as ARAN+ and as a web browser got the same answer."
        if flagged(res, "cfBlock") then
            text = text + Chr(10) + "Only the provider can allow it, or give you another address."
        else if IsRefusalCode(code) then
            text = text + Chr(10) + "Often a typo in the login, an old address the provider has retired, a trial that has ended, or a block on your internet connection after too many attempts."
        else if code = 404 then
            text = text + Chr(10) + "Nothing at this address answers as an Xtream server. Ask the provider for the Xtream or API address (often with a port like :8080), or paste their whole M3U link into Server."
        end if
        res.error = text
        return res
    end if
    return ParseAuth(res.data)
end function

' Answers that can mean "not this app" rather than "wrong login".
function clientTurnedAway(res as Object) as Boolean
    if res.ok then return false
    code = ToInt(res.code)
    if code = 403 or code = 404 or code = 503 then return true
    return code = 401 and flagged(res, "cloudflare")
end function

function flagged(res as Object, key as String) as Boolean
    value = res[key]
    if type(value) = "Boolean" or type(value) = "roBoolean" then return value
    return false
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

' Asks the server about one video under each user agent in `agents`.
function runProbe(req as Object) as Object
    results = []
    for each agent in req.agents
        results.Push(checkStream(FieldStr(req, "url"), ToStr(agent)))
    end for
    return { ok: true, results: results }
end function
