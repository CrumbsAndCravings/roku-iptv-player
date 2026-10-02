sub init()
    m.top.functionName = "work"
end sub

sub work()
    req = m.top.request
    http = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    http.SetUrl(FieldStr(req, "url") + "/v1/progress?space=" + FieldStr(req, "space"))
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.RetainBodyOnError(true)
    http.AddHeader("Authorization", "Bearer " + FieldStr(req, "key"))
    http.AddHeader("Content-Type", "application/json")
    body = FormatJson({ entries: req.entries, removed: req.removed })
    result = { ok: false, error: "Couldn't start the request." }
    if http.AsyncPostFromString(body) then
        msg = Wait(20000, port)
        if type(msg) <> "roUrlEvent" then
            http.AsyncCancel()
            result = { ok: false, error: "The sync service took too long to answer." }
        else if msg.GetResponseCode() = 200 then
            state = ParseJson(msg.GetString())
            if IsAA(state) then
                result = { ok: true, state: state }
            else
                result = { ok: false, error: "The sync service's answer wasn't readable." }
            end if
        else
            result = { ok: false, error: "The sync service answered HTTP " + msg.GetResponseCode().ToStr() + "." }
        end if
    end if
    m.top.result = result
end sub
