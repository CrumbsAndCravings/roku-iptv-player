' Helpers for OpenSubtitles (online subtitles). No network here, so tests can cover it.

' Provider titles carry tags and years: "EN - The Batman (2022)" -> { query: "The Batman", year: "2022" }.
function CleanTitleForSearch(title as String) as Object
    text = title.Trim()
    year = ""
    yearPattern = CreateObject("roRegex", "\s*[\(\[]?((19|20)\d\d)[\)\]]?\s*$", "")
    found = yearPattern.Match(text)
    if found.Count() > 1 and Len(text) > 6 then
        year = found[1]
        text = yearPattern.Replace(text, "")
    end if
    ' Leading tags such as "EN - ", "|EN| ", "[4K] ", "FHD | ".
    tag = CreateObject("roRegex", "^\s*(\[[^\]]*\]|\|[^|]*\||[A-Z0-9]{2,3}\s*[-|]\s)\s*", "")
    for i = 1 to 3
        if tag.IsMatch(text) then text = tag.Replace(text, "")
    end for
    ' Trailing tags such as "[MULTI-SUB]" or "(4K)".
    trailing = CreateObject("roRegex", "\s*(\[[^\]]*\]|\([^)]*\))\s*$", "")
    text = trailing.Replace(text, "")
    return { query: text.Trim(), year: year }
end function

' OpenSubtitles wants parameters in alphabetical order with lowercase values; other
' orders get redirected.
function OsQuery(params as Object) as String
    keys = params.Keys()
    keys.Sort()
    parts = []
    for each key in keys
        value = LCase(ToStr(params[key]))
        if value <> "" then parts.Push(LCase(key) + "=" + value.EncodeUriComponent())
    end for
    return parts.Join("&")
end function

' /subtitles response -> the best few candidates, best first: made for this exact file,
' then human-made over machine-translated, then regular over SDH, then most downloaded.
function ParseOsResults(data as Dynamic) as Object
    candidates = []
    list = Field(data, "data")
    if not IsArr(list) then return candidates
    seen = {}
    for each entry in list
        attrs = Field(entry, "attributes")
        files = Field(attrs, "files")
        if IsArr(files) and files.Count() > 0 then
            fileId = FieldStr(files[0], "file_id")
            if fileId <> "" and not seen.DoesExist(fileId) then
                seen[fileId] = true
                hashMatch = ToStr(Field(attrs, "moviehash_match")) = "true"
                machine = ToStr(Field(attrs, "machine_translated")) = "true" or ToStr(Field(attrs, "ai_translated")) = "true"
                sdh = ToStr(Field(attrs, "hearing_impaired")) = "true"
                downloads = ToInt(Field(attrs, "download_count"))
                if downloads > 9999999 then downloads = 9999999
                rank = 0
                if not hashMatch then rank = rank + 4
                if machine then rank = rank + 2
                if sdh then rank = rank + 1
                candidates.Push({
                    fileId: fileId
                    release: FirstText([Field(attrs, "release"), Field(files[0], "file_name")])
                    hashMatch: hashMatch
                    machine: machine
                    sdh: sdh
                    downloads: downloads
                    order: rank * 10000000 + (9999999 - downloads)
                })
            end if
        end if
    end for
    candidates.SortBy("order")
    best = []
    for each candidate in candidates
        if best.Count() < 6 then best.Push(candidate)
    end for
    return best
end function

function SubtitleLabel(candidate as Object) as String
    if ToStr(candidate.saved) = "true" then return "English · saved for this title"
    if candidate.hashMatch then
        label = "English · matches this file"
    else
        release = candidate.release
        if Len(release) > 34 then release = Left(release, 33) + "…"
        if release = "" then release = "online"
        label = "English · " + release
    end if
    if candidate.sdh then label = label + " · SDH"
    if candidate.machine then label = label + " · auto-translated"
    return label
end function

' --- Subtitles saved for a title on the sync service (sync/worker.js) ----------------

' What the sync service keeps for a title ({ fileId, name, delayMs, file }) as a choice in
' the Subtitles column.
function SavedCandidate(saved as Object) as Object
    return { fileId: saved.fileId, release: saved.name, hashMatch: false, machine: false, sdh: false, downloads: 0, saved: true }
end function

' The column's online choices: the saved ones first, then search results that aren't
' the same file. -> { saved, found }
function SplitSavedCandidates(candidates as Object) as Object
    saved = []
    found = []
    for each candidate in candidates
        if ToStr(candidate.saved) = "true" then saved.Push(candidate)
    end for
    for each candidate in candidates
        if ToStr(candidate.saved) <> "true" then
            same = false
            for each kept in saved
                if kept.fileId = candidate.fileId then same = true
            end for
            if not same then found.Push(candidate)
        end if
    end for
    return { saved: saved, found: found }
end function


' Saved subtitles need the sync service from October 2026 on; an older one answers 404.
function OldSyncText() as String
    return "Subtitles can't be saved for next time, because your sync service is an older version. Update it in Cloudflare: see " + Chr(34) + "Update it" + Chr(34) + " in the Roku repo's sync/README.md."
end function

' Why downloaded subtitles weren't saved for next time (SyncTask's subtitle-save).
function SubtitleSaveText(code as Integer, error as String) as String
    if code = 404 then return OldSyncText()
    text = "These subtitles couldn't be saved for next time."
    if error <> "" then text = text + " " + error
    return text
end function

' --- Subtitles the app draws itself ------------------------------------------------
'
' Online subtitles (OpenSubtitles' and the saved ones) are drawn by the player rather
' than handed to Roku's, which only reads a subtitle file when a stream opens: drawn,
' they come on and move in time at once, without opening the stream again.

' SRT or WebVTT text -> cues [{ s, e, t }]: start and end in ms, the words (lines
' joined by Chr(10), tags taken out), in order of start.
function ParseCues(text as String) as Object
    cues = []
    if Left(text, 1) = Chr(65279) then text = Mid(text, 2)
    lines = text.Replace(Chr(13), "").Split(Chr(10))
    ' Made once for the whole file: a TV is slow to make them.
    patterns = cuePatterns()
    i = 0
    while i < lines.Count()
        found = patterns.timing.Match(lines[i])
        i = i + 1
        if found.Count() > 2 then
            start = cueTimeWith(patterns, found[1])
            finish = cueTimeWith(patterns, found[2])
            words = []
            while i < lines.Count() and lines[i].Trim() <> ""
                words.Push(lines[i])
                i = i + 1
            end while
            said = cueWordsWith(patterns, words.Join(Chr(10)))
            if start >= 0 and finish > start and said <> "" then cues.Push({ s: start, e: finish, t: said })
        end if
    end while
    cues.SortBy("s")
    return cues
end function

function cuePatterns() as Object
    return {
        timing: CreateObject("roRegex", "^\s*(\S+)\s+-->\s+(\S+)", "")
        time: CreateObject("roRegex", "^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?$", "")
        tags: CreateObject("roRegex", "<[^>]*>", "")
        styles: CreateObject("roRegex", "\{\\[^}]*\}", "")
    }
end function

' "01:02:03,456", "02:03.456" or "02:03" -> ms; -1 when it isn't a time.
function CueTime(token as String) as Integer
    return cueTimeWith(cuePatterns(), token)
end function

function cueTimeWith(patterns as Object, token as String) as Integer
    found = patterns.time.Match(token.Trim())
    if found.Count() < 4 then return -1
    hours = 0
    if found[1] <> "" then hours = found[1].ToInt()
    fraction = 0
    if found.Count() > 4 and found[4] <> "" then fraction = Left(found[4] + "00", 3).ToInt()
    return ((hours * 60 + found[2].ToInt()) * 60 + found[3].ToInt()) * 1000 + fraction
end function

' A cue's words without formatting: <i>, <font ...>, {\an8} and the like go, and the
' few entities WebVTT uses read as themselves.
function CueWords(text as String) as String
    return cueWordsWith(cuePatterns(), text)
end function

function cueWordsWith(patterns as Object, text as String) as String
    text = patterns.tags.ReplaceAll(text, "")
    text = patterns.styles.ReplaceAll(text, "")
    text = text.Replace("&nbsp;", " ").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&amp;", "&")
    lines = []
    for each line in text.Split(Chr(10))
        if line.Trim() <> "" then lines.Push(line.Trim())
    end for
    return lines.Join(Chr(10))
end function

' What shows at `t` ms: the cue that started last before it, with any earlier ones
' still on above it; "" between cues.
function CueTextAt(cues as Object, t as Integer) as String
    low = 0
    high = cues.Count() - 1
    last = -1
    while low <= high
        half = (low + high) \ 2
        if cues[half].s <= t then
            last = half
            low = half + 1
        else
            high = half - 1
        end if
    end while
    if last < 0 then return ""
    texts = []
    i = last
    while i >= 0 and last - i < 4
        if cues[i].e > t then texts.Unshift(cues[i].t)
        i = i - 1
    end while
    return texts.Join(Chr(10))
end function

' How the timing reads: 300 -> "0.3 s later", -1200 -> "1.2 s earlier", 0 -> "on time".
function DelayLabel(delayMs as Integer) as String
    if delayMs = 0 then return "on time"
    size = delayMs
    if size < 0 then size = 0 - size
    text = (size \ 1000).ToStr() + "." + ((size MOD 1000) \ 100).ToStr() + " s"
    if delayMs > 0 then return text + " later"
    return text + " earlier"
end function
