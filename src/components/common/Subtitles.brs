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

' The saved file's address, moved `delayMs` later (earlier when negative) by the service.
function SavedSubtitleUrl(file as String, delayMs as Integer) as String
    if delayMs = 0 then return file
    return file + "&delay=" + delayMs.ToStr()
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
