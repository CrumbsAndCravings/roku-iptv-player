' Blocking JSON GET for task threads.

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
    if code <> 200 then
        headers = msg.GetResponseHeaders()
        detail = HttpDetail(code, headers, msg.GetString())
        blocked = IsCloudflare(headers)
        if blocked and (code = 401 or code = 403) then
            text = "The provider's firewall blocked this Roku: " + detail + "."
        else if code = 401 or code = 403 then
            text = "The server refused the login: " + detail + "."
        else
            text = "The server answered " + detail + "."
        end if
        return { ok: false, code: code, cloudflare: blocked, error: text }
    end if

    data = ParseJson(msg.GetString())
    if data = invalid then return { ok: false, error: "The server's answer wasn't readable. Check the server address." }
    return { ok: true, data: data }
end function
