' Audio and subtitle choices for the player's track panel, built from the Video node's
' availableAudioTracks / availableSubtitleTracks. Each option is { id, label, language }.

function LanguageName(code as String) as String
    names = {
        eng: "English", en: "English", hin: "Hindi", hi: "Hindi", urd: "Urdu", ur: "Urdu"
        pan: "Punjabi", pa: "Punjabi", ara: "Arabic", ar: "Arabic", ben: "Bengali", bn: "Bengali"
        tam: "Tamil", ta: "Tamil", tel: "Telugu", te: "Telugu", mal: "Malayalam", ml: "Malayalam"
        kan: "Kannada", kn: "Kannada", mar: "Marathi", mr: "Marathi", guj: "Gujarati", gu: "Gujarati"
        per: "Persian", fas: "Persian", fa: "Persian", tur: "Turkish", tr: "Turkish"
        fre: "French", fra: "French", fr: "French", spa: "Spanish", es: "Spanish"
        ger: "German", deu: "German", de: "German", ita: "Italian", it: "Italian"
        por: "Portuguese", pt: "Portuguese", rus: "Russian", ru: "Russian", pol: "Polish", pl: "Polish"
        dut: "Dutch", nld: "Dutch", nl: "Dutch", swe: "Swedish", sv: "Swedish", dan: "Danish", da: "Danish"
        nor: "Norwegian", nob: "Norwegian", fin: "Finnish", fi: "Finnish", gre: "Greek", ell: "Greek", el: "Greek"
        heb: "Hebrew", he: "Hebrew", rum: "Romanian", ron: "Romanian", ro: "Romanian", hun: "Hungarian", hu: "Hungarian"
        cze: "Czech", ces: "Czech", cs: "Czech", jpn: "Japanese", ja: "Japanese", kor: "Korean", ko: "Korean"
        chi: "Chinese", zho: "Chinese", zh: "Chinese", tha: "Thai", th: "Thai", vie: "Vietnamese", vi: "Vietnamese"
        ind: "Indonesian", may: "Malay", msa: "Malay", ms: "Malay", fil: "Filipino", tgl: "Tagalog"
    }
    c = LCase(code.Trim())
    if c = "" or c = "und" or c = "unk" then return ""
    name = names[c]
    if name = invalid then return UCase(c)
    return name
end function

' "English" + "Commentary" -> "English · Commentary"; skips a description that just repeats the language.
function TrackLabel(language as String, detail as String, fallback as String) as String
    label = LanguageName(language)
    if detail <> "" and LCase(detail) <> LCase(label) then
        if label = "" then
            label = detail
        else
            label = label + " · " + detail
        end if
    end if
    if label = "" then label = fallback
    return label
end function

function AudioOptions(tracks as Dynamic) as Object
    options = []
    if not IsArr(tracks) then return options
    for each track in tracks
        id = FieldStr(track, "Track")
        if id <> "" then
            number = options.Count() + 1
            language = FieldStr(track, "Language")
            options.Push({ id: id, label: TrackLabel(language, FieldStr(track, "Name"), "Track " + number.ToStr()), language: LCase(language) })
        end if
    end for
    return options
end function

' Always starts with "Off".
function SubtitleOptions(tracks as Dynamic) as Object
    options = [{ id: "", label: "Off", language: "off" }]
    if not IsArr(tracks) then return options
    for each track in tracks
        id = FirstText([Field(track, "TrackName"), Field(track, "Track")])
        if id <> "" then
            number = options.Count()
            language = FieldStr(track, "Language")
            options.Push({ id: id, label: TrackLabel(language, FieldStr(track, "Description"), "Subtitles " + number.ToStr()), language: LCase(language) })
        end if
    end for
    return options
end function

function OptionIndex(options as Object, key as String, value as String) as Integer
    for i = 0 to options.Count() - 1
        if options[i][key] = value then return i
    end for
    return -1
end function
