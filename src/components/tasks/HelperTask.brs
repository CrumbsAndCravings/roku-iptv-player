sub init()
    m.top.functionName = "work"
end sub

sub work()
    req = m.top.request
    mode = FieldStr(req, "mode")
    ' The helper may first have to ask the provider about the file (up to 30 s).
    timeoutMs = 8000
    if mode = "info" then timeoutMs = 50000
    if mode = "stop" then timeoutMs = 4000
    res = helperGet(FieldStr(req, "url"), timeoutMs)
    result = { ok: false, error: res.error }
    if res.code = 200 then
        data = ParseJson(res.body)
        if mode = "info" then
            if IsAA(data) then
                result = { ok: true, info: ParseHelperInfo(data) }
            else
                result = { ok: false, error: "The helper's answer wasn't readable." }
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
