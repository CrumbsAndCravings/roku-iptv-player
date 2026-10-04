sub init()
    m.top.functionName = "work"
end sub

sub work()
    req = m.top.request
    mode = FieldStr(req, "mode")
    ' The helper may first have to ask the provider about the file (up to 30 s), and a
    ' start answers once the first piece is made (the helper waits up to a minute).
    timeoutMs = 8000
    if mode = "info" or mode = "hash" then timeoutMs = 50000
    if mode = "start" then timeoutMs = 100000
    if mode = "stop" then timeoutMs = 4000
    res = helperGet(FieldStr(req, "url"), timeoutMs)
    result = { ok: false, error: res.error }
    if res.code = 200 then
        data = ParseJson(res.body)
        if mode = "info" or mode = "start" or mode = "hash" then
            if not IsAA(data) then
                result = { ok: false, error: "The helper's answer wasn't readable." }
            else if mode = "info" then
                result = { ok: true, info: ParseHelperInfo(data) }
            else if mode = "hash" then
                result = { ok: true, hash: ParseHelperHash(data) }
            else
                started = ParseHelperStart(data)
                result = { ok: true, started: started }
                if started.url = "" then result = { ok: false, error: "The helper's answer had no playlist in it." }
            end if
        else if mode = "lastError" then
            ' A reason from minutes ago belongs to something else.
            said = FieldStr(data, "error")
            ago = Field(data, "ago")
            if ago <> invalid and ToInt(ago) > 180 then said = ""
            result = { ok: true, said: said }
        else
            result = { ok: true }
        end if
    end if
    result.request = req
    m.top.result = result
end sub

function helperGet(url as String, timeoutMs as Integer) as Object
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.RetainBodyOnError(true)
    if not http.AsyncGetToString() then return { code: 0, body: "", error: HelperFailure(0, "") }
    msg = Wait(timeoutMs, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return { code: 0, body: "", error: HelperFailure(0, "") }
    end if
    code = msg.GetResponseCode()
    body = msg.GetString()
    if code <> 200 then return { code: code, body: body, error: HelperFailure(code, body) }
    return { code: 200, body: body, error: "" }
end function
