sub init()
    m.backdrop = m.top.FindNode("backdrop")
    m.body = m.top.FindNode("body")
    m.dim = m.top.FindNode("dim")
    m.title = m.top.FindNode("title")
    m.meta = m.top.FindNode("meta")
    m.plot = m.top.FindNode("plot")
    m.credits = m.top.FindNode("credits")
    m.buttonsGroup = m.top.FindNode("buttons")
    m.status = m.top.FindNode("status")
    m.compat = m.top.FindNode("compat")
    m.panel = m.top.FindNode("episodesPanel")
    m.seasonsGroup = m.top.FindNode("seasons")
    m.episodes = m.top.FindNode("episodes")
    m.scroll = m.top.FindNode("scroll")
    m.scrollBody = m.top.FindNode("scrollBody")
    m.scrollDim = m.top.FindNode("scrollDim")
    m.keys = m.top.FindNode("keys")
    m.backdropIn = m.top.FindNode("backdropIn")
    m.backdropFade = m.top.FindNode("backdropFade")
    m.backdropTarget = 1.0
    m.backdrop.ObserveField("loadStatus", "onBackdropLoaded")

    m.title.font = MakeFont("Fredoka-SemiBold", 42)
    m.meta.font = MakeFont("Nunito-ExtraBold", 18)
    m.plot.font = "font:SmallSystemFont"
    m.credits.font = "font:SmallestSystemFont"
    m.status.font = MakeFont("Nunito-SemiBold", 19)
    m.compat.font = MakeFont("Nunito-ExtraBold", 17)

    m.zone = "buttons"
    m.scrolled = false
    m.pills = []
    m.buttonActions = []
    m.buttonIndex = 0
    m.seasonPills = []
    m.seasonIndex = 0
    m.seriesNode = invalid
    m.queue = []
    m.entry = invalid
    m.task = invalid

    m.episodes.ObserveField("itemSelected", "onEpisodeSelected")
end sub

sub onItem()
    item = m.top.item
    if item = invalid then return
    m.item = item
    m.kind = item.kind
    showInfo()
    if m.kind = "movie" then
        buildMovieButtons()
        updateMovieCompat()
        if not item.hasInfo then runTask({ mode: "vodInfo", id: item.itemId }, "onMovieInfo")
    else
        m.status.text = "Loading episodes…"
        runTask({ mode: "seriesInfo", id: item.itemId }, "onSeriesInfo")
    end if
end sub

sub runTask(request as Object, callback as String)
    m.task = CreateObject("roSGNode", "XtreamTask")
    m.task.request = request
    m.task.ObserveField("result", callback)
    m.task.control = "RUN"
end sub

sub showInfo()
    item = m.item
    m.title.text = item.title
    m.meta.text = MetaLine(item)
    m.plot.text = item.description
    credits = []
    if item.starring <> "" then credits.Push("Starring " + item.starring)
    if item.directedBy <> "" then credits.Push("Directed by " + item.directedBy)
    m.credits.text = credits.Join("   ·   ")
    m.backdropIn.control = "stop"
    m.backdropTarget = ShowBackdrop(m.backdrop, item.backdrop, item.HDPosterUrl)
end sub

sub onBackdropLoaded()
    if m.backdrop.loadStatus <> "ready" then return
    m.backdropFade.keyValue = [0.0, m.backdropTarget]
    m.backdropIn.control = "start"
end sub

' --- Movies ------------------------------------------------------------------

sub onMovieInfo(event as Object)
    result = event.GetData()
    m.task = invalid
    if not result.ok then return
    ApplyInfo(m.item, result.info)
    if m.item.HDPosterUrl = "" and result.info.poster <> "" then m.item.HDPosterUrl = SizedImage(result.info.poster, "w185")
    showInfo()
    updateMovieCompat()
end sub

' --- Will it play on this TV? ------------------------------------------------------

sub updateMovieCompat()
    item = m.item
    check = PlaybackCheck(item.ext, item.videoCodec, item.videoProfile, item.audioCodec)
    item.problem = check.blocked
    m.compat.text = CompatLine(check, item.ext)
end sub

function CompatLine(check as Object, ext as String) as String
    if check.blocked <> "" then
        if IsUnsupportedContainer(ext) then return "Won't play on this " + DeviceWord() + ": Roku devices can't play " + UCase(ext) + " files."
        return "Won't play on this " + DeviceWord() + ": it can't decode " + check.blocked + "."
    end if
    if check.warning <> "" then return "May not play fully on this " + DeviceWord() + ": it doesn't support " + check.warning + "."
    return ""
end function

' Marks each episode this TV can't play, and explains on the page.
sub updateSeriesCompat()
    blockedCount = 0
    total = 0
    reason = ""
    for s = 0 to m.seriesNode.GetChildCount() - 1
        season = m.seriesNode.GetChild(s)
        for e = 0 to season.GetChildCount() - 1
            ep = season.GetChild(e)
            check = PlaybackCheck(ep.ext, ep.videoCodec, ep.videoProfile, ep.audioCodec)
            ep.problem = check.blocked
            total = total + 1
            if check.blocked <> "" then
                blockedCount = blockedCount + 1
                reason = CompatLine(check, ep.ext)
            end if
        end for
    end for
    if blockedCount = 0 then
        m.compat.text = ""
    else if blockedCount = total then
        m.compat.text = reason
    else
        m.compat.text = blockedCount.ToStr() + " of " + total.ToStr() + " episodes won't play on this " + DeviceWord() + ". They're marked in the list."
    end if
end sub

sub buildMovieButtons()
    m.entry = ProgressFind("m:" + m.item.itemId)
    if m.entry <> invalid and ToInt(m.entry.pos) > 0 then
        setButtons(["Resume from " + FormatClock(ToInt(m.entry.pos)), "Play from start"], ["resume", "restart"])
    else
        setButtons(["Play"], ["play"])
    end if
end sub

sub playMovie(startAt as Integer)
    item = m.item
    ext = item.ext
    if ext = "" then ext = "mp4"
    m.top.action = {
        name: "play"
        playback: {
            kind: "movie"
            title: item.title
            id: item.itemId
            ext: ext
            startAt: startAt
            videoCodec: item.videoCodec
            videoProfile: item.videoProfile
            audioCodec: item.audioCodec
            tmdbId: item.tmdbId
            entry: { k: "m:" + item.itemId, kind: "movie", id: item.itemId, name: item.title, poster: item.HDPosterUrl, bd: item.backdrop, ext: ext }
        }
    }
end sub

' --- Series ------------------------------------------------------------------

sub onSeriesInfo(event as Object)
    result = event.GetData()
    series = event.GetRoSGNode().content
    m.task = invalid
    if not result.ok then
        m.status.text = result.error
        return
    end if
    ApplyInfo(m.item, result.info)
    if m.item.backdrop = "" and m.item.HDPosterUrl = "" and result.info.poster <> "" then m.item.HDPosterUrl = SizedImage(result.info.poster, "w185")
    showInfo()

    if series = invalid or series.GetChildCount() = 0 then
        m.status.text = "Your provider hasn't listed any episodes for this show."
        return
    end if
    m.status.text = ""
    m.seriesNode = series
    m.queue = []
    for s = 0 to series.GetChildCount() - 1
        season = series.GetChild(s)
        for e = 0 to season.GetChildCount() - 1
            ep = season.GetChild(e)
            m.queue.Push({
                id: ep.itemId
                ext: ep.ext
                season: ToInt(ep.seasonNo)
                episode: ToInt(ep.episodeNo)
                code: EpisodeCode(ep.seasonNo, ep.episodeNo)
                title: ep.title
                videoCodec: ep.videoCodec
                videoProfile: ep.videoProfile
                audioCodec: ep.audioCodec
            })
        end for
    end for

    names = []
    for s = 0 to series.GetChildCount() - 1
        names.Push(series.GetChild(s).title)
    end for
    m.seasonPills = BuildPills(m.seasonsGroup, names, 18)
    m.panel.visible = true
    updateSeriesCompat()
    refreshSeriesProgress(true)
end sub

' Re-reads Continue Watching and updates the buttons and episode progress bars.
sub refreshSeriesProgress(pickSeason as Boolean)
    m.entry = ProgressFind("s:" + m.item.itemId)
    entryId = ""
    if m.entry <> invalid then entryId = FieldStr(m.entry, "id")
    fraction = ProgressFraction(m.entry)
    entrySeason = -1
    for s = 0 to m.seriesNode.GetChildCount() - 1
        season = m.seriesNode.GetChild(s)
        for e = 0 to season.GetChildCount() - 1
            ep = season.GetChild(e)
            if entryId <> "" and ep.itemId = entryId then
                ep.progress = fraction
                entrySeason = s
            else
                ep.progress = 0.0
            end if
        end for
    end for
    if pickSeason then
        if entrySeason >= 0 then
            showSeason(entrySeason)
        else
            showSeason(0)
        end if
    end if

    if entrySeason >= 0 then
        code = EpisodeCode(Field(m.entry, "season"), Field(m.entry, "episode"))
        ' After an episode finishes, the entry points at the next one with no progress yet.
        verb = "Play "
        if ToInt(m.entry.pos) > 0 then verb = "Resume "
        setButtons([verb + code, "Episodes"], ["resumeEpisode", "episodes"])
    else
        setButtons(["Play " + m.queue[0].code, "Episodes"], ["playFirst", "episodes"])
    end if
end sub

sub showSeason(index as Integer)
    if m.seriesNode = invalid then return
    m.seasonIndex = index
    m.episodes.content = m.seriesNode.GetChild(index)
    styleSeasons()
end sub

function queueIndexOf(episodeId as String) as Integer
    if episodeId = "" then return -1
    for i = 0 to m.queue.Count() - 1
        if m.queue[i].id = episodeId then return i
    end for
    return -1
end function

sub playEpisode(index as Integer, startAt as Integer)
    item = m.item
    m.top.action = {
        name: "play"
        playback: {
            kind: "episode"
            seriesId: item.itemId
            seriesName: item.title
            seriesTmdbId: item.tmdbId
            poster: item.HDPosterUrl
            backdrop: item.backdrop
            queue: m.queue
            index: index
            startAt: startAt
        }
    }
end sub

sub onEpisodeSelected()
    season = m.episodes.content
    if season = invalid then return
    ep = season.GetChild(m.episodes.itemSelected)
    if ep = invalid then return
    index = queueIndexOf(ep.itemId)
    if index < 0 then return
    startAt = 0
    if m.entry <> invalid and FieldStr(m.entry, "id") = ep.itemId then startAt = ToInt(m.entry.pos)
    playEpisode(index, startAt)
end sub

' --- Buttons -----------------------------------------------------------------

sub setButtons(labels as Object, actions as Object)
    m.pills = BuildPills(m.buttonsGroup, labels, 20)
    m.buttonActions = actions
    if m.buttonIndex >= labels.Count() then m.buttonIndex = 0
    styleButtons()
end sub

sub styleButtons()
    focus = -1
    if m.zone = "buttons" then focus = m.buttonIndex
    StylePills(m.pills, focus, -1)
end sub

sub styleSeasons()
    focus = -1
    if m.zone = "seasons" then focus = m.seasonIndex
    StylePills(m.seasonPills, focus, m.seasonIndex)
    ' Keep the chosen season on screen when there are more than fit.
    if m.seasonPills.Count() > 0 then
        pill = m.seasonPills[m.seasonIndex]
        position = pill.translation
        bg = pill.GetChild(0)
        right = position[0] + bg.width
        offset = 0
        if right > 1160 then offset = right - 1160
        m.seasonsGroup.translation = [-offset, 0]
    end if
end sub

sub activateButton()
    if m.buttonIndex >= m.buttonActions.Count() then return
    action = m.buttonActions[m.buttonIndex]
    if action = "play" or action = "restart" then
        playMovie(0)
    else if action = "resume" then
        playMovie(ToInt(m.entry.pos))
    else if action = "playFirst" then
        playEpisode(0, 0)
    else if action = "resumeEpisode" then
        index = queueIndexOf(FieldStr(m.entry, "id"))
        if index < 0 then index = 0
        playEpisode(index, ToInt(m.entry.pos))
    else if action = "episodes" then
        enterZone("episodes")
        jumpToSavedEpisode()
    end if
end sub

sub jumpToSavedEpisode()
    season = m.episodes.content
    if season = invalid or m.entry = invalid then return
    entryId = FieldStr(m.entry, "id")
    for e = 0 to season.GetChildCount() - 1
        if season.GetChild(e).itemId = entryId then
            m.episodes.jumpToItem = e
            return
        end if
    end for
end sub

' --- Focus -------------------------------------------------------------------

sub enterZone(zone as String)
    m.zone = zone
    if zone = "buttons" then
        setScrolled(false)
        m.keys.SetFocus(true)
    else if zone = "seasons" then
        setScrolled(true)
        m.keys.SetFocus(true)
    else if zone = "episodes" then
        setScrolled(true)
        m.episodes.SetFocus(true)
    end if
    styleButtons()
    styleSeasons()
end sub

sub setScrolled(scrolled as Boolean)
    if scrolled = m.scrolled then return
    m.scrolled = scrolled
    target = [0, 0]
    dimTo = 0.0
    if scrolled then
        target = [0, -392]
        dimTo = 0.6
    end if
    m.scrollBody.keyValue = [m.body.translation, target]
    m.scrollDim.keyValue = [m.dim.opacity, dimTo]
    m.scroll.control = "start"
end sub

sub onTakeFocus()
    if m.kind = "movie" then
        buildMovieButtons()
    else if m.seriesNode <> invalid then
        refreshSeriesProgress(false)
    end if
    enterZone(m.zone)
end sub

function hasEpisodes() as Boolean
    return m.seriesNode <> invalid and m.seasonPills.Count() > 0
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if m.zone = "episodes" then
        ' Keys the episode list didn't use.
        if key = "up" then
            enterZone("seasons")
            return true
        else if key = "back" then
            enterZone("buttons")
            return true
        end if
        return key <> "back"
    end if

    if m.zone = "seasons" then
        if key = "left" and m.seasonIndex > 0 then
            showSeason(m.seasonIndex - 1)
        else if key = "right" and m.seasonIndex < m.seasonPills.Count() - 1 then
            showSeason(m.seasonIndex + 1)
        else if key = "down" or key = "OK" then
            if m.episodes.content <> invalid and m.episodes.content.GetChildCount() > 0 then enterZone("episodes")
        else if key = "up" or key = "back" then
            enterZone("buttons")
        end if
        return true
    end if

    ' Buttons
    if key = "left" and m.buttonIndex > 0 then
        m.buttonIndex = m.buttonIndex - 1
        styleButtons()
    else if key = "right" and m.buttonIndex < m.pills.Count() - 1 then
        m.buttonIndex = m.buttonIndex + 1
        styleButtons()
    else if key = "OK" then
        activateButton()
    else if key = "play" then
        m.buttonIndex = 0
        styleButtons()
        activateButton()
    else if key = "down" and hasEpisodes() then
        enterZone("seasons")
    else if key = "back" then
        return false
    end if
    return true
end function
