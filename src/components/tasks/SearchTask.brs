sub init()
    m.top.functionName = "work"
end sub

sub work()
    port = CreateObject("roMessagePort")
    m.top.ObserveField("query", port)
    m.top.ObserveField("stop", port)
    creds = m.global.creds
    owner = FieldStr(creds, "server") + " " + FieldStr(creds, "username")
    lastQuery = m.top.query

    ' A library saved in the last day is ready at once.
    index = LoadSearchIndex(SearchCachePath(), owner, NowSeconds(), 86400)
    if index <> invalid then
        report(1, 1, index)
        if lastQuery <> "" then publish(index, lastQuery)
        while true
            msg = Wait(0, port)
            if type(msg) = "roSGNodeEvent" then
                if msg.GetField() = "stop" then return
                ' Typing queues several queries; only the latest matters.
                if m.top.query <> lastQuery then
                    lastQuery = m.top.query
                    publish(index, lastQuery)
                end if
            end if
        end while
    end if
    index = NewSearchIndex()

    ' Xtream has no search call, so we index every list. Series come in one request for
    ' the whole library (about 5 MB in 3 seconds for 7,000 series on one provider),
    ' which saves dozens of requests. Movies are too many for that, so they come one
    ' category at a time; so do series if the big request fails.
    lists = {}
    for each kind in ["vod", "series"]
        action = "get_vod_categories"
        if kind = "series" then action = "get_series_categories"
        lists[kind] = []
        res = fetchJson(ApiUrl(creds, action, invalid), FieldStr(creds, "userAgent"))
        if res.ok then
            for each category in ParseCategories(res.data)
                lists[kind].Push({ kind: kind, id: category.id, all: false })
            end for
        end if
    end for
    seriesAllowed = {}
    for each job in lists.series
        seriesAllowed[job.id] = true
    end for
    jobs = []
    if lists.series.Count() > 0 then jobs.Push({ kind: "series", id: "", all: true })
    jobs.Append(lists.vod)
    total = jobs.Count()
    done = 0
    report(done, total, index, total = 0)
    if lastQuery <> "" then publish(index, lastQuery)

    ' Gentle on the provider: two lists at a time, started a moment apart, none while a
    ' video plays, and a stop after three failures in a row. Bursts of requests made
    ' one provider stop answering for a while, and while it sulks videos don't start
    ' either. Each list is parsed and dropped before the next, so memory stays low.
    inflight = {}
    failures = 0
    failedLists = 0
    stopped = false
    saved = false
    sinceStart = CreateObject("roTimespan")
    pauseMs = 0
    while true
        if inflight.Count() < 2 and jobs.Count() > 0 and sinceStart.TotalMilliseconds() >= pauseMs then
            sinceStart.Mark()
            if m.global.playing = true then
                pauseMs = 2000
            else
                pauseMs = 250
                job = jobs.Shift()
                action = "get_vod_streams"
                if job.kind = "series" then action = "get_series"
                http = CreateObject("roUrlTransfer")
                http.SetMessagePort(port)
                if job.all then
                    http.SetUrl(ApiUrl(creds, action, invalid))
                else
                    http.SetUrl(ApiUrl(creds, action, { category_id: job.id }))
                end if
                if FieldStr(creds, "userAgent") <> "" then http.AddHeader("User-Agent", FieldStr(creds, "userAgent"))
                http.SetCertificatesFile("common:/certs/ca-bundle.crt")
                http.InitClientCertificates()
                http.EnableEncodings(true)
                if http.AsyncGetToString() then
                    identity = http.GetIdentity()
                    inflight[identity.ToStr()] = { http: http, kind: job.kind, all: job.all, clock: CreateObject("roTimespan") }
                else
                    done = done + 1
                end if
            end if
        end if

        msg = Wait(100, port)
        failed = false
        finishedOne = false
        wasAll = false
        if type(msg) = "roUrlEvent" then
            identity = msg.GetSourceIdentity()
            key = identity.ToStr()
            entry = inflight[key]
            if entry <> invalid then
                inflight.Delete(key)
                finishedOne = true
                wasAll = entry.all
                data = invalid
                if msg.GetResponseCode() = 200 then data = ParseJson(msg.GetString())
                if IsArr(data) then
                    if entry.all then
                        IndexAdd(index, data, entry.kind, seriesAllowed)
                    else
                        IndexAdd(index, data, entry.kind)
                    end if
                else if msg.GetResponseCode() <> 200 or entry.all then
                    failed = true
                end if
                data = invalid
            end if
        else if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "stop" then return
            ' Typing queues several queries; only the latest matters.
            if m.top.query <> lastQuery then
                lastQuery = m.top.query
                publish(index, lastQuery)
            end if
        else
            ' Give up on downloads that have hung.
            for each key in inflight.Keys()
                if inflight[key].clock.TotalSeconds() > 45 then
                    if inflight[key].all then wasAll = true
                    inflight[key].http.AsyncCancel()
                    inflight.Delete(key)
                    finishedOne = true
                    failed = true
                end if
            end for
        end if

        if finishedOne then
            done = done + 1
            ' The whole-series request didn't work: take series category by category,
            ' alternating with the movies still to come.
            if wasAll and failed then
                jobs = alternate(lists.series, jobs)
                total = total + lists.series.Count()
            else if failed then
                failedLists = failedLists + 1
            end if
            ' A provider that keeps failing may be counting requests; stop asking.
            if failed then
                failures = failures + 1
            else
                failures = 0
            end if
            if failures >= 3 and jobs.Count() > 0 then
                jobs.Clear()
                stopped = true
                total = done + inflight.Count()
            end if
            report(done, total, index, stopped)
            finished = (jobs.Count() = 0 and inflight.Count() = 0)
            ' Keep the library for next time (a few broken categories don't spoil it).
            if finished and not stopped and failedLists <= 3 and not saved then saved = SaveSearchIndex(index, SearchCachePath(), owner, NowSeconds())
            ' Refresh an open search as more of the library arrives.
            if lastQuery <> "" and (done MOD 4 = 0 or finished or wasAll) then publish(index, lastQuery)
        end if
    end while
end sub

sub publish(index as Object, query as String)
    results = IndexSearch(index, query, 40)
    results.AddFields({ forQuery: query })
    m.top.results = results
end sub

sub report(done as Integer, total as Integer, index as Object, stopped = false as Boolean)
    m.top.status = { done: done, total: total, titles: index.names.Count(), stopped: stopped }
end sub

' a and b merged, taking turns: a1, b1, a2, b2, ...
function alternate(a as Object, b as Object) as Object
    merged = []
    longest = a.Count()
    if b.Count() > longest then longest = b.Count()
    for i = 0 to longest - 1
        if i < a.Count() then merged.Push(a[i])
        if i < b.Count() then merged.Push(b[i])
    end for
    return merged
end function
