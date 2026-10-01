' Makes sense of provider category names like "EN | ACTION ★", "|IN| BOLLYWOOD 2024" or
' "PUNJABI MOVIES": which language a category is in, whether it holds new releases or
' kids' titles, and a tidy name to show ("Action", "Bollywood 2024", "Punjabi").
' `year` is the current year, since new-release categories often name it.
'
' Returns { lang, isNew, kids, label }. lang is "en", "hi", "pa", "other" (any language
' we don't single out) or "" when the name doesn't say.

function ClassifyCategory(name as String, year as Integer) as Object
    segments = categorySegments(name)
    words = {}
    for each segment in segments
        for each word in CreateObject("roRegex", "[^A-Z0-9+]+", "").Split(segment)
            if word <> "" then words[word] = true
        end for
    end for
    upper = UCase(name)

    ' A code like "EN ✪" or "|FR|" is the provider saying the language outright, so it
    ' wins, except that "IN" covers all of India and the name says which language.
    code = ""
    codeText = ""
    for each segment in segments
        code = languageCode(segment)
        if code <> "" then
            codeText = segment
            exit for
        end if
    end for
    named = languageFromWords(words, upper)
    if code = "en" or code = "other" or code = "pa" then
        lang = code
    else if code = "hi" then
        lang = "hi"
        if named = "pa" or named = "other" then lang = named
    else
        lang = named
        if lang = "" then lang = scriptLanguage(name)
    end if

    isNew = hasAnyWord(words, ["NEW", "LATEST", "RECENT", "RECENTLY", "TRENDING", "POPULAR", "THEATRICAL"])
    for each phrase in ["JUST ADDED", "TOP 10", "THIS WEEK", "IN CINEMA", "IN THEATER", "IN THEATRE", "BOX OFFICE", "NOW PLAYING", "NOW SHOWING"]
        if Instr(1, upper, phrase) > 0 then isNew = true
    end for
    for each candidate in [year, year - 1]
        if words.DoesExist(candidate.ToStr()) then isNew = true
    end for

    kids = hasAnyWord(words, ["KIDS", "KID", "CHILDREN", "CHILD", "CARTOON", "CARTOONS", "JUNIOR"])
    label = categoryLabel(segments, lang)
    ' Other languages keep their code, so French "Action" isn't mistaken for English.
    if lang = "other" and codeText <> "" then label = codeText + " · " + label
    return { lang: lang, isNew: isNew, kids: kids, label: label }
end function

' The language a name spells out in words: "PUNJABI", "BOLLYWOOD", "TAMIL", "ENGLISH".
function languageFromWords(words as Object, upper as String) as String
    if hasAnyWord(words, ["PUNJABI", "PUNJAB", "POLLYWOOD"]) then return "pa"
    if hasAnyWord(words, ["HINDI", "BOLLYWOOD"]) then return "hi"
    if hasAnyWord(words, otherLanguageWords()) or Instr(1, upper, "SOUTH INDIAN") > 0 or Instr(1, upper, "K-DRAMA") > 0 then return "other"
    if hasAnyWord(words, ["ENGLISH", "HOLLYWOOD"]) then return "en"
    if hasAnyWord(words, ["INDIAN", "INDIA", "DESI"]) then return "hi"
    return ""
end function

' Names written in another script: Devanagari is Hindi, Gurmukhi is Punjabi, and
' Arabic, Greek, Cyrillic, other Indian scripts, Thai, Chinese, Japanese or Korean
' count as other languages.
function scriptLanguage(name as String) as String
    for i = 1 to Len(name)
        c = Asc(Mid(name, i, 1))
        if c >= &h0900 and c <= &h097F then return "hi"
        if c >= &h0A00 and c <= &h0A7F then return "pa"
        if (c >= &h0370 and c <= &h08FF) or (c >= &h0980 and c <= &h0FFF) or (c >= &h10A0 and c <= &h11FF) or (c >= &h3040 and c <= &h30FF) or (c >= &h3400 and c <= &h9FFF) or (c >= &hAC00 and c <= &hD7AF) then return "other"
    end for
    return ""
end function

' Whether a category belongs on screen. With no languages chosen, everything does;
' categories whose language we can't tell always do.
function CategoryWanted(info as Object, langs as Object) as Boolean
    if langs.Count() = 0 or info.lang = "" then return true
    for each wanted in langs
        if LCase(ToStr(wanted)) = info.lang then return true
    end for
    return false
end function

' The categories to show for one kind ("vod" or "series"), each with a tidy label and a
' new-releases flag, ordered: new releases first, then by language in the order chosen
' (unknown counts as the first language), otherwise in the provider's order. With
' demote4K (a screen that isn't 4K), 4K categories go last: on a 720p or 1080p TV they
' only cost bandwidth.
function OrganizeCategories(list as Object, langs as Object, year as Integer, demote4K = false as Boolean) as Object
    shown = []
    position = 0
    for each category in list
        info = ClassifyCategory(FieldStr(category, "name"), year)
        if CategoryWanted(info, langs) then
            rank = languageRank(info.lang, langs) + 1
            if info.isNew then rank = 0
            if demote4K and Is4KLabel(info.label) then rank = langs.Count() + 2
            demoted = demote4K and Is4KLabel(info.label)
            shown.Push({ id: FieldStr(category, "id"), name: FieldStr(category, "name"), label: info.label, lang: info.lang, isNew: info.isNew and not demoted, demoted: demoted, order: rank * 100000 + position })
        end if
        position = position + 1
    end for
    shown.SortBy("order")
    return shown
end function

function Is4KLabel(label as String) as Boolean
    return CreateObject("roRegex", "(?:^|\W)(?:4K|UHD)(?:\W|$)", "i").IsMatch(label)
end function

' Entries grouped by language (in the order chosen; unknown counts as the first), then
' merged with each language taking a turn, so a Punjabi row isn't buried under fifty
' English ones.
function LanguageTurns(entries as Object, langs as Object) as Object
    groups = []
    for i = 0 to langs.Count()
        groups.Push([])
    end for
    last = []
    for each entry in entries
        if entry.DoesExist("demoted") and entry.demoted = true then
            last.Push(entry)
        else
            groups[languageRank(FieldStr(entry, "lang"), langs)].Push(entry)
        end if
    end for
    merged = []
    round = 0
    added = true
    while added
        added = false
        for each group in groups
            if round < group.Count() then
                merged.Push(group[round])
                added = true
            end if
        end for
        round = round + 1
    end while
    merged.Append(last)
    return merged
end function

' a and b merged, taking turns: a1, b1, a2, b2, ...
function TakeTurns(a as Object, b as Object) as Object
    merged = []
    longest = a.Count()
    if b.Count() > longest then longest = b.Count()
    for i = 0 to longest - 1
        if i < a.Count() then merged.Push(a[i])
        if i < b.Count() then merged.Push(b[i])
    end for
    return merged
end function

function languageRank(lang as String, langs as Object) as Integer
    for i = 0 to langs.Count() - 1
        if LCase(ToStr(langs[i])) = lang then return i
    end for
    return 0
end function

' "EN | ACTION ★" -> ["EN", "ACTION"]. Splits on the separators providers use; a hyphen
' only counts with spaces around it, so "SCI-FI" stays whole.
function categorySegments(name as String) as Object
    clean = ""
    for i = 1 to Len(name)
        ch = Mid(name, i, 1)
        code = Asc(ch)
        ' Drop emoji and decorative symbols, keep accented letters.
        if code < 128 or (code >= 192 and code <= 383) then
            clean = clean + ch
        else
            clean = clean + " | "
        end if
    end for
    clean = UCase(clean)
    clean = CreateObject("roRegex", "\s+-\s+|[|\[\]():*#=~]", "").ReplaceAll(clean, "|")
    segments = []
    for each part in clean.Split("|")
        part = CreateObject("roRegex", "\s+", "").ReplaceAll(part, " ").Trim()
        if part <> "" and part <> "-" then segments.Push(part)
    end for
    return segments
end function

function hasAnyWord(words as Object, candidates as Object) as Boolean
    for each candidate in candidates
        if words.DoesExist(candidate) then return true
    end for
    return false
end function

' A whole segment that is a language or country code, like "EN", "IN" or "AR".
function languageCode(segment as String) as String
    codes = {
        EN: "en", ENG: "en", UK: "en", GB: "en", US: "en", USA: "en", AU: "en", NZ: "en", IE: "en"
        IN: "hi", IND: "hi", HI: "hi", HIN: "hi"
        PB: "pa", PJ: "pa", PUN: "pa", PAN: "pa"
    }
    ' CA is Quebec (French) in IPTV movie lists; EX is ex-Yugoslavia; AS is Asian.
    other = ["CA", "EX", "SW", "AS", "AR", "ARA", "ARB", "FR", "FRA", "DE", "GER", "ES", "SPA", "IT", "ITA", "PT", "POR", "BR", "TR", "TUR", "NL", "PL", "RU", "RUS", "GR", "AL", "RO", "BG", "HU", "CZ", "SK", "SE", "NO", "DK", "FI", "IR", "PER", "KU", "AF", "AFR", "SO", "PH", "VN", "TH", "ID", "MY", "CN", "CHN", "KR", "KOR", "JP", "JAP", "PK", "BD", "LK", "NP", "TA", "TE", "ML", "KN", "LAT", "MX", "CO", "EXYU", "EX-YU", "QC", "IL", "AM", "UA", "LT", "LV", "EE", "HR", "RS", "BA", "MK", "SI", "CY", "MT", "IS", "ZA", "NG", "KE", "ET", "EG", "MA", "DZ", "TN", "LB", "SY", "IQ", "SA", "AE", "KW", "QA"]
    if codes.DoesExist(segment) then return codes[segment]
    for each code in other
        if segment = code then return "other"
    end for
    return ""
end function

function otherLanguageWords() as Object
    return ["ARABIC", "ARAB", "FRENCH", "FRANCAIS", "GERMAN", "DEUTSCH", "SPANISH", "ESPANOL", "LATINO", "ITALIAN", "PORTUGUESE", "BRAZIL", "BRASIL", "TURKISH", "TURKCE", "DUTCH", "POLISH", "POLSKA", "RUSSIAN", "GREEK", "ALBANIAN", "ROMANIAN", "BULGARIAN", "HUNGARIAN", "CZECH", "SLOVAK", "SWEDISH", "NORWEGIAN", "DANISH", "FINNISH", "NORDIC", "SCANDINAVIAN", "PERSIAN", "FARSI", "IRANIAN", "KURDISH", "AFGHAN", "PASHTO", "SOMALI", "FILIPINO", "PINOY", "TAGALOG", "VIETNAMESE", "THAI", "INDONESIAN", "MALAY", "CHINESE", "MANDARIN", "CANTONESE", "KOREAN", "KDRAMA", "JAPANESE", "URDU", "PAKISTANI", "PAKISTAN", "BANGLA", "BENGALI", "NEPALI", "SINHALA", "TAMIL", "TELUGU", "MALAYALAM", "KANNADA", "MARATHI", "GUJARATI", "ODIA", "ASSAMESE", "BHOJPURI", "EXYU", "BALKAN", "SERBIAN", "CROATIAN", "BOSNIAN", "MACEDONIAN", "ARMENIAN", "GEORGIAN", "HEBREW", "ISRAELI", "AFRICAN", "AFRICA", "QUEBEC", "HAITIAN", "UKRAINIAN", "LITHUANIAN", "LATVIAN", "ESTONIAN", "GUJARTI", "QUEBECOISE", "QUEBECOIS", "SWEDEN", "DENMARK", "NORWAY", "FINLAND", "RUSSIA", "BULGARIA", "ROMANIA", "ALBANIA", "POLAND", "GREECE", "GERMANY", "FRANCE", "SPAIN", "ITALY", "PORTUGAL", "NETHERLANDS", "TURKEY", "CHINA", "JAPAN", "KOREA", "MALAYSIA", "THAILAND", "INDONESIA", "INDONISIA", "PHILIPPINES", "NOLLYWOOD"]
end function

' Segments without language codes, generic words or decoration, joined and title-cased.
' Hindi and Punjabi categories keep their language in the name, so "IN | ACTION" doesn't
' look the same as the English "Action".
function categoryLabel(segments as Object, lang as String) as String
    generic = { MOVIES: true, MOVIE: true, FILMS: true, FILM: true, SERIES: true, "TV SHOWS": true, SHOWS: true, VOD: true, "TV SERIES": true, VIP: true }
    named = []
    for each segment in segments
        if languageCode(segment) = "" and not generic.DoesExist(segment) then named.Push(segment)
    end for
    if named.Count() = 0 then
        for each segment in segments
            if languageCode(segment) = "" then named.Push(segment)
        end for
    end if
    ' "ACTION MOVIES" -> "ACTION"; a lone "MOVIES" or "MOVIE SERIES" stays.
    last = named.Count() - 1
    if last >= 0 then
        trailing = CreateObject("roRegex", "^(.+?)\s+(?:MOVIES|MOVIE|FILMS|FILM|SERIES|TV SHOWS|TV SERIES|SHOWS)$", "").Match(named[last])
        ' Keep "TV SHOWS", "UK SERIES" and "3D MOVIES" whole: two letters alone say little.
        if trailing.Count() > 1 and not generic.DoesExist(trailing[1]) and Len(trailing[1]) > 2 then named[last] = trailing[1]
    end if
    text = titleCase(named.Join(" · "))
    ' A category called just "SERIES" or "MOVIES" is named for its language instead.
    names = { en: "English", hi: "Hindi", pa: "Punjabi" }
    plain = { MOVIES: true, MOVIE: true, FILMS: true, FILM: true, SERIES: true }
    if plain.DoesExist(UCase(text)) and names.DoesExist(lang) then text = names[lang]
    lower = LCase(text)
    if lang = "hi" and Instr(1, lower, "hindi") = 0 and Instr(1, lower, "bollywood") = 0 and Instr(1, lower, "indian") = 0 then text = "Hindi " + text
    if lang = "pa" and Instr(1, lower, "punjab") = 0 and Instr(1, lower, "pollywood") = 0 then text = "Punjabi " + text
    return text.Trim()
end function

' "NETFLIX · SCI-FI 4K" -> "Netflix · Sci-Fi 4K". Short acronyms and words with digits
' stay as they are.
function titleCase(text as String) as String
    keep = { TV: true, HD: true, FHD: true, UHD: true, UK: true, US: true, USA: true, HBO: true, BBC: true, ITV: true, AMC: true, MCU: true, DC: true, VIP: true, NBA: true, NFL: true, UFC: true, WWE: true, II: true, III: true, IV: true, AZ: true, IMDB: true, FIFA: true, "BET+": true, OSN: true, VIU: true }
    words = []
    for each word in text.Split(" ")
        if keep.DoesExist(word) or CreateObject("roRegex", "\d", "").IsMatch(word) then
            words.Push(word)
        else
            words.Push(capitalizeWord(word))
        end if
    end for
    return words.Join(" ")
end function

' "SCI-FI" -> "Sci-Fi", "CONCERTS/MUSICAL" -> "Concerts/Musical": lower case, with a
' capital at the start and after each "-" or "/".
function capitalizeWord(word as String) as String
    lower = LCase(word)
    out = ""
    capital = true
    for i = 1 to Len(lower)
        ch = Mid(lower, i, 1)
        if capital then ch = UCase(ch)
        out = out + ch
        capital = ch = "-" or ch = "/"
    end for
    return out
end function
