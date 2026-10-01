' Blocking JSON GET for task threads.

' userAgent replaces Roku's own when set (see AppUserAgent).
function fetchJson(url as String, userAgent = "" as String) as Object
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(url)
    if userAgent <> "" then http.AddHeader("User-Agent", userAgent)
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
    if code <> 200 then
        headers = msg.GetResponseHeaders()
        body = msg.GetString()
        detail = HttpDetail(code, headers, body)
        blocked = IsCloudflareBlock(headers, body)
        if blocked then
            text = "Cloudflare, the provider's firewall, turned this Roku away: " + detail + "."
        else if IsRefusalCode(code) then
            text = "The server refused the request: " + detail + "."
        else
            text = "The server answered " + detail + "."
        end if
        return { ok: false, code: code, cloudflare: IsCloudflare(headers), cfBlock: blocked, error: text }
    end if

    data = ParseJson(msg.GetString())
    if data = invalid then return { ok: false, error: "The server's answer wasn't readable. Check the server address." }
    return { ok: true, data: data }
end function

' Asks for a video's headers without downloading it, to see whether the server would
' send it. userAgent "" means Roku's own.
function checkStream(url as String, userAgent as String) as Object
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.RetainBodyOnError(true)
    if userAgent <> "" then http.AddHeader("User-Agent", userAgent)
    if not http.AsyncHead() then return { ok: false, code: 0, agent: userAgent, detail: "the request couldn't start" }
    msg = Wait(10000, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return { ok: false, code: 0, agent: userAgent, detail: "no answer in 10 seconds" }
    end if
    code = msg.GetResponseCode()
    if code < 0 then return { ok: false, code: code, agent: userAgent, detail: "couldn't connect (" + msg.GetFailureReason() + ")" }
    return { ok: code >= 200 and code < 300, code: code, agent: userAgent, detail: HttpDetail(code, msg.GetResponseHeaders(), msg.GetString()) }
end function
