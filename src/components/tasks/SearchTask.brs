sub init()
    m.top.functionName = "work"
end sub

sub work()
    port = CreateObject("roMessagePort")
    m.top.ObserveField("query", port)
    m.top.ObserveField("stop", port)
    m.top.ObserveField("browse", port)
    m.top.ObserveField("countsRequest", port)
    m.top.ObserveField("picksRequest", port)
    creds = m.global.creds
    owner = FieldStr(creds, "server") + " " + FieldStr(creds, "username")
    lastQuery = m.top.query

    ' The library is kept on the Roku and searched straight away. Once it's a day old, a
    ' fresh copy loads slowly in the background while searches keep using the saved
    ' one, and replaces it when complete. Only the very first load makes you wait.
    live = LoadSearchIndex(SearchCachePath(), owner)
    refreshing = live <> invalid
    ' A request for picks made as this worker started, before it was listening.
    askedEarly = IsAA(m.top.picksRequest) and m.top.picksRequest.Count() > 0
    if refreshing then
        report(1, 1, live)
        if lastQuery <> "" then publish(live, lastQuery)
        if askedEarly then answerPicks(live, false)
        if NowSeconds() - live.savedAt < 86400 then
            answerQueries(port, live, lastQuery)
            return
        end if
        building = NewSearchIndex()
    else
        live = NewSearchIndex()
        building = live
        if askedEarly then answerPicks(live, true)
    end if

    ' Gentle on the provider, which stopped answering after bursts of requests: at most
    ' one request a second for the first load (two at a time) and one every two seconds
    ' for a background refresh, none while a video plays, and a stop after three
    ' failures in a row. Each list is parsed and dropped before the next.
    maxInFlight = 2
    spacingMs = 1000
    if refreshing then
        maxInFlight = 1
        spacingMs = 2000
    end if

    ' Xtream has no search call, so we index every list. Series come in one request for
    ' the whole library (about 5 MB in 3 seconds for 7,000 series on one provider),
    ' which saves dozens of requests. Movies are too many for that, so they come one
    ' category at a time; so do series if the big request fails.
    ' Only categories in the languages you watch (all of them when none are set): fewer
    ' requests, and no French or Arabic titles crowding the results.
    lists = {}
    year = CreateObject("roDateTime").GetYear()
    langs = LanguagePrefs()
    for each kind in ["vod", "series"]
        action = "get_vod_categories"
        if kind = "series" then action = "get_series_categories"
        lists[kind] = []
        res = fetchJson(ApiUrl(creds, action, invalid), FieldStr(creds, "userAgent"))
        if res.ok then
            categories = []
            for each category in ParseCategories(res.data)
                if CategoryWanted(ClassifyCategory(category.name, year), langs) then categories.Push(category)
            end for
            IndexSetCategories(building, kind, categories, year)
            for each category in categories
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
    if not refreshing then
        report(done, total, live, total = 0)
        if lastQuery <> "" then publish(live, lastQuery)
    end if

    inflight = {}
    failures = 0
    failedLists = 0
    stopped = false
    complete = false
    sinceStart = CreateObject("roTimespan")
    pauseMs = 0
    while true
        if inflight.Count() < maxInFlight and jobs.Count() > 0 and sinceStart.TotalMilliseconds() >= pauseMs then
            sinceStart.Mark()
            if m.global.playing = true then
                pauseMs = 2000
            else
                pauseMs = spacingMs
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
                    inflight[identity.ToStr()] = { http: http, kind: job.kind, id: job.id, all: job.all, clock: CreateObject("roTimespan") }
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
                        IndexAdd(building, data, entry.kind, seriesAllowed)
                    else
                        IndexAdd(building, data, entry.kind, invalid, entry.id)
                    end if
                else if msg.GetResponseCode() <> 200 or entry.all then
                    failed = true
                end if
                data = invalid
            end if
        else if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "stop" then return
            if msg.GetField() = "browse" then
                answerBrowse(live, not refreshing and not complete)
            else if msg.GetField() = "countsRequest" then
                answerCounts(live)
            else if msg.GetField() = "picksRequest" then
                answerPicks(live, not refreshing and not complete)
            else if m.top.query <> lastQuery then
                ' Typing queues several queries; only the latest matters.
                lastQuery = m.top.query
                publish(live, lastQuery)
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
            finished = (jobs.Count() = 0 and inflight.Count() = 0)
            if finished and not complete then
                complete = true
                ' Keep the library (a few broken categories don't spoil it). A refresh
                ' that stopped early keeps the saved one and tries again next time.
                if not stopped and failedLists <= 3 then
                    SaveSearchIndex(building, SearchCachePath(), owner, NowSeconds())
                    live = building
                end if
            end if
            if not refreshing then
                report(done, total, live, stopped)
                ' Refresh an open search as more of the library arrives.
                if lastQuery <> "" and (done MOD 4 = 0 or finished or wasAll) then publish(live, lastQuery)
            else if finished then
                report(1, 1, live)
                if lastQuery <> "" then publish(live, lastQuery)
            end if
        end if
    end while
end sub

' Searches a ready library until the screen goes away.
sub answerQueries(port as Object, index as Object, lastQuery as String)
    while true
        msg = Wait(0, port)
        if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "stop" then return
            if msg.GetField() = "browse" then
                answerBrowse(index, false)
            else if msg.GetField() = "countsRequest" then
                answerCounts(index)
            else if msg.GetField() = "picksRequest" then
                answerPicks(index, false)
            else if m.top.query <> lastQuery then
                ' Typing queues several queries; only the latest matters.
                lastQuery = m.top.query
                publish(index, lastQuery)
            end if
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

' A category's titles for its "See all" page, from the stored library only. `loading`
' says the library is still arriving, so the page can ask again later.
sub answerBrowse(index as Object, loading as Boolean)
    request = m.top.browse
    query = FieldStr(request, "query")
    list = IndexBrowse(index, FieldStr(request, "kind"), FieldStr(request, "categoryId"), 1000, query)
    list.AddFields({ forKey: FieldStr(request, "kind") + ":" + FieldStr(request, "categoryId") + ":" + query, loading: loading })
    m.top.browsed = list
end sub

' How many titles each category holds ("vod:123" -> 104), for the Categories tab.
sub answerCounts(index as Object)
    counts = {}
    for each category in index.categories
        counts[category.kind + ":" + category.id] = category.count
    end for
    m.top.counts = counts
end sub

' Home's rows picked for you (common/Taste.brs): `picksRequest` { history, watching,
' because: [{ k, n }], forKey } -> `picks`, a ContentNode of rows (Top picks for you,
' then a "Because you watched" row for each of `because`), each tagged with its `slot`
' ("picks", or the title's key), and the likings worked out (`scores`, which Home keeps
' to order its rows). `loading` says the library is still arriving.
sub answerPicks(index as Object, loading as Boolean)
    request = m.top.picksRequest
    history = Field(request, "history")
    if not IsArr(history) then history = []
    watching = Field(request, "watching")
    if not IsArr(watching) then watching = []
    because = Field(request, "because")
    if not IsArr(because) then because = []
    keys = []
    exclude = {}
    for each source in [history, watching]
        for each entry in source
            key = FieldStr(entry, "k")
            if key <> "" then
                keys.Push(key)
                exclude[key] = true
            end if
            name = FieldStr(entry, "n")
            if name = "" then name = FieldStr(entry, "name")
            if name <> "" then exclude[" " + NormalizeSearch(name)] = true
        end for
    end for
    categories = IndexCategoriesOf(index, keys)
    now = NowSeconds()
    scores = LikingFrom(history, watching, categories, now)
    root = CreateObject("roSGNode", "ContentNode")
    picks = IndexPicks(index, scores, exclude, 30, now)
    picks.AddFields({ slot: "picks" })
    root.AppendChild(picks)
    for each title in because
        key = FieldStr(title, "k")
        category = categories[key]
        if category <> invalid then
            row = IndexBecause(index, key, FieldStr(title, "n"), category, exclude, 20)
        else
            row = CreateObject("roSGNode", "ContentNode")
        end if
        row.AddFields({ slot: key })
        root.AppendChild(row)
    end for
    root.AddFields({ forKey: FieldStr(request, "forKey"), scores: scores, loading: loading })
    m.top.picks = root
end sub
