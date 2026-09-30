' Helpers for OpenSubtitles (online subtitles). No network here, so tests can cover it.

' OpenSubtitles "moviehash": file size plus the sum of the first and last 64 KB read as
' little-endian 64-bit words, modulo 2^64, as 16 hex digits. It identifies the exact
' release, so matching subtitles are timed for this file. head and tail are byte arrays
' (roByteArray, or plain arrays in tests); size is the whole file's length.
function OsHashHex(head as Object, tail as Object, size as Dynamic) as String
    two32 = 4294967296&
    sumLo = 0&
    sumHi = 0&
    for each chunk in [head, tail]
        count = chunk.Count()
        n = count - (count MOD 8)
        i = 0
        while i < n
            lo = chunk[i] + chunk[i + 1] * 256 + chunk[i + 2] * 65536 + chunk[i + 3] * 16777216&
            hi = chunk[i + 4] + chunk[i + 5] * 256 + chunk[i + 6] * 65536 + chunk[i + 7] * 16777216&
            sumLo = sumLo + lo
            sumHi = sumHi + hi
            i = i + 8
        end while
    end for
    total = 0& + size
    low = sumLo + (total MOD two32)
    high = sumHi + (total \ two32) + (low \ two32)
    low = low MOD two32
    high = high MOD two32
    return hex8(high) + hex8(low)
end function

function hex8(value as Dynamic) as String
    digits = "0123456789abcdef"
    n = 0& + value
    text = ""
    for i = 1 to 8
        d = n MOD 16
        index = Int(d) + 1
        text = Mid(digits, index, 1) + text
        n = n \ 16
    end for
    return text
end function

' "bytes 0-65535/1234567890" -> 1234567890 (as a LongInteger); -1 when unknown.
function ParseContentRangeTotal(header as String) as Dynamic
    slash = Instr(1, header, "/")
    if slash = 0 then return -1&
    digits = Mid(header, slash + 1).Trim()
    if digits = "" then return -1&
    total = 0&
    for i = 1 to Len(digits)
        c = Asc(Mid(digits, i, 1)) - 48
        if c < 0 or c > 9 then return -1&
        total = total * 10 + c
    end for
    return total
end function

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
