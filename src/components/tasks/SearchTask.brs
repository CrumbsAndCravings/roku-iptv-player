sub init()
    m.top.functionName = "work"
end sub

sub work()
    port = CreateObject("roMessagePort")
    m.top.ObserveField("query", port)
    m.top.ObserveField("stop", port)
    creds = m.global.creds
    index = NewSearchIndex()

    ' One job per category. Xtream has no search call, so we index every list. Movie and
    ' series lists take turns, so both kinds of results show up while it indexes.
    lists = {}
    for each kind in ["vod", "series"]
        action = "get_vod_categories"
        if kind = "series" then action = "get_series_categories"
        lists[kind] = []
        res = fetchJson(ApiUrl(creds, action, invalid), FieldStr(creds, "userAgent"))
        if res.ok then
            for each category in ParseCategories(res.data)
                lists[kind].Push({ kind: kind, id: category.id })
            end for
        end if
    end for
    jobs = []
    longest = lists.vod.Count()
    if lists.series.Count() > longest then longest = lists.series.Count()
    for i = 0 to longest - 1
        if i < lists.vod.Count() then jobs.Push(lists.vod[i])
        if i < lists.series.Count() then jobs.Push(lists.series[i])
    end for
    total = jobs.Count()
    done = 0
    lastQuery = m.top.query
    report(done, total, index)
    if lastQuery <> "" then publish(index, lastQuery)

    inflight = {}
    refusals = 0
    while true
        ' Three downloads at a time; each list is parsed and dropped before the next,
        ' so memory stays low even for very large catalogs.
        while inflight.Count() < 3 and jobs.Count() > 0
            job = jobs.Shift()
            action = "get_vod_streams"
            if job.kind = "series" then action = "get_series"
            http = CreateObject("roUrlTransfer")
            http.SetMessagePort(port)
            http.SetUrl(ApiUrl(creds, action, { category_id: job.id }))
            if FieldStr(creds, "userAgent") <> "" then http.AddHeader("User-Agent", FieldStr(creds, "userAgent"))
            http.SetCertificatesFile("common:/certs/ca-bundle.crt")
            http.InitClientCertificates()
            http.EnableEncodings(true)
            if http.AsyncGetToString() then
                identity = http.GetIdentity()
                inflight[identity.ToStr()] = { http: http, kind: job.kind, clock: CreateObject("roTimespan") }
            else
                done = done + 1
            end if
        end while

        msg = Wait(1000, port)
        if type(msg) = "roUrlEvent" then
            identity = msg.GetSourceIdentity()
            key = identity.ToStr()
            entry = inflight[key]
            if entry <> invalid then
                inflight.Delete(key)
                code = msg.GetResponseCode()
                if code = 200 then IndexAdd(index, ParseJson(msg.GetString()), entry.kind)
                done = done + 1
                ' A server that keeps saying no may be counting requests; stop asking.
                if IsRefusalCode(code) then
                    refusals = refusals + 1
                else
                    refusals = 0
                end if
                if refusals >= 3 and jobs.Count() > 0 then
                    jobs.Clear()
                    total = done + inflight.Count()
                end if
                finished = (jobs.Count() = 0 and inflight.Count() = 0)
                report(done, total, index)
                ' Refresh an open search as more of the library arrives.
                if lastQuery <> "" and (done MOD 8 = 0 or finished) then publish(index, lastQuery)
            end if
        else if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "stop" then return
            lastQuery = msg.GetData()
            publish(index, lastQuery)
        else
            ' Give up on downloads that have hung.
            for each key in inflight.Keys()
                if inflight[key].clock.TotalSeconds() > 45 then
                    inflight[key].http.AsyncCancel()
                    inflight.Delete(key)
                    done = done + 1
                    report(done, total, index)
                end if
            end for
        end if
    end while
end sub

sub publish(index as Object, query as String)
    results = IndexSearch(index, query, 40)
    results.AddFields({ forQuery: query })
    m.top.results = results
end sub

sub report(done as Integer, total as Integer, index as Object)
    m.top.status = { done: done, total: total, titles: index.names.Count() }
end sub
