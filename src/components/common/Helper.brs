' The helper on a computer at home (the Samsung repo's helper/, started with
' npm run helper): it fetches a file from the provider with FFmpeg and converts what
' this Roku can't play into HLS while you watch. Settings come from account.json
' ("transcoder", TranscoderSettings in Utils.brs). These functions build its addresses
' and make the choices; tasks/HelperTask.brs makes the requests, and
' screens/PlayerScreen.brs plays the result. Tested in tests/utils_test.brs and
' tests/parse_test.brs.

' --- Addresses -----------------------------------------------------------------------

' The part of an address that names one file. kind is "movie" or "series".
function HelperFileQuery(kind as String, id as String, ext as String) as String
    e = LCase(ext)
    if e = "" then e = "mp4"
    return "kind=" + kind + "&id=" + id.EncodeUriComponent() + "&ext=" + e.EncodeUriComponent()
end function

function helperBase(config as Object, path as String) as String
    return config.url + path + "?key=" + ToStr(config.key).EncodeUriComponent()
end function

' What the file holds, and what the helper would do with each track. `start` lets the
' helper keep the connection that read the file's start for a stream from there; with
' `wantHash` it also fingerprints the file for OpenSubtitles in the same reads.
function HelperInfoUrl(config as Object, kind as String, id as String, ext as String, audio as String, start as Integer, wantHash as Boolean) as String
    if start < 0 then start = 0
    url = helperBase(config, "/v1/info") + "&" + HelperFileQuery(kind, id, ext) + "&start=" + start.ToStr()
    if wantHash then url = url + "&hash=1"
    if audio <> "" then url = url + "&audio=" + audio
    return url
end function

' The converted video as HLS, from `start` seconds. choice is { video, height, audio,
' track } (HelperVideo, HelperHeight, HelperAudio, HelperTrack).
function HelperHlsUrl(config as Object, kind as String, id as String, ext as String, start as Integer, choice as Object) as String
    if start < 0 then start = 0
    url = helperBase(config, "/v1/hls/index.m3u8") + "&" + HelperFileQuery(kind, id, ext) + "&start=" + start.ToStr() + "&video=" + FieldStr(choice, "video")
    height = ToInt(Field(choice, "height"))
    if height > 0 then url = url + "&height=" + height.ToStr()
    audio = FieldStr(choice, "audio")
    if audio <> "" then url = url + "&audio=" + audio
    track = Field(choice, "track")
    if track <> invalid and ToInt(track) >= 0 then url = url + "&track=" + ToInt(track).ToStr()
    return url
end function

' An online subtitle file (OpenSubtitles' link) with its times moved `start` seconds
' earlier: Roku times subtitles from where the helper's stream starts.
function HelperSubtitleUrl(config as Object, link as String, start as Integer) as String
    return helperBase(config, "/v1/subtitles.srt") + "&start=" + start.ToStr() + "&src=" + link.EncodeUriComponent()
end function

function HelperErrorUrl(config as Object) as String
    return helperBase(config, "/v1/last-error")
end function

' Stops the helper's FFmpeg, so the provider's one connection is free again.
function HelperStopUrl(config as Object) as String
    return helperBase(config, "/v1/stop")
end function

' --- Choices -------------------------------------------------------------------------

' Whether a title plays through the helper.
'   check     PlaybackCheck's answer: { blocked, warning }
'   state     { listed, failed, refused, silent }: on the remembered list (helper/titles);
'             the direct stream failed after its retry; the stream check found the
'             provider refusing it every way; no sound track this Roku can play
'   setUp     a helper is set up
'   tried     the helper already had its turn with this title
function HelperRoute(check as Object, state as Object, setUp as Boolean, tried as Boolean) as Boolean
    if not setUp or tried then return false
    if FieldStr(check, "blocked") <> "" then return true
    if helperFlag(state, "listed") then return true
    ' A stream the provider turns away won't come through the helper either.
    if helperFlag(state, "failed") then return not helperFlag(state, "refused")
    return helperFlag(state, "silent")
end function

function helperFlag(aa as Dynamic, key as String) as Boolean
    value = Field(aa, key)
    if type(value) = "Boolean" or type(value) = "roBoolean" then return value
    return false
end function

' "copy" when this Roku decodes the picture as it is ("copy" in the helper's plan, and
' a format this Roku can decode), otherwise "convert".
function HelperVideo(videoPlan as String, canDecodePicture as Boolean) as String
    if videoPlan = "copy" and canDecodePicture then return "copy"
    return "convert"
end function

' Converted pictures no taller than the screen (720 lines on a 720p TV), never more
' than 1080: more only costs the computer work.
function HelperHeight(screenLines as Integer) as Integer
    if screenLines <= 0 then return 720
    if screenLines > 1080 then return 1080
    return screenLines
end function

' "aac" (every sound track as stereo AAC) unless this Roku decodes both AC-3 and E-AC-3,
' which the helper otherwise keeps or makes.
function HelperAudio(canAc3 as Boolean, canEac3 as Boolean) as String
    if canAc3 and canEac3 then return ""
    return "aac"
end function

' Which of the helper's sound tracks is in the viewer's language (prefs "audio"), so it
' goes first; -1 for none.
function HelperTrack(audio as Dynamic, language as String) as Integer
    if not IsArr(audio) or language = "" then return -1
    wanted = LanguageName(language)
    if wanted = "" then return -1
    for i = 0 to audio.Count() - 1
        if LanguageName(FieldStr(audio[i], "language")) = wanted then return i
    end for
    return -1
end function

' Whether a jump to `target` stays inside what the helper has converted so far: its
' stream starts at `offset` and Roku has `available` seconds of it listed. A margin
' of two segments keeps the jump off the part still being written.
function HelperSeekInside(target as Float, offset as Integer, available as Float) as Boolean
    if available <= 0 or target < offset then return false
    return target <= offset + available - 12
end function

' A helper stream that ends more than a minute before the file does has stopped early
' (FFmpeg was stopped, or the provider's connection dropped).
function HelperEndedEarly(position as Integer, duration as Integer) as Boolean
    return duration > 0 and position < duration - 60
end function

' --- What the helper says ------------------------------------------------------------

' The helper's description of a file (/v1/info). `hash` is its OpenSubtitles
' fingerprint, "" when it wasn't asked for or couldn't be read.
function ParseHelperInfo(data as Dynamic) as Object
    video = Field(data, "video")
    plan = FieldStr(data, "videoPlan")
    if plan <> "try" and plan <> "convert" then plan = "copy"
    audio = []
    tracks = Field(data, "audio")
    if IsArr(tracks) then
        for each track in tracks
            if IsAA(track) then audio.Push({ codec: FieldStr(track, "codec"), channels: ToInt(track.channels), language: FieldStr(track, "language"), plan: FieldStr(track, "plan") })
        end for
    end if
    hash = LCase(FieldStr(data, "hash"))
    if not CreateObject("roRegex", "^[0-9a-f]{16}$", "").IsMatch(hash) then hash = ""
    return {
        duration: ToInt(Field(data, "duration"))
        hash: hash
        videoCodec: FieldStr(video, "codec")
        width: ToInt(Field(video, "width"))
        height: ToInt(Field(video, "height"))
        videoPlan: plan
        audio: audio
    }
end function

' Why a request to the helper failed, in plain words. code 0 means no answer.
function HelperFailure(code as Integer, body as String) as String
    if code <= 0 then return "The helper on your computer didn't answer. Is the computer on, with the helper running?"
    if code = 401 then return "The helper on your computer turned this app away: its key doesn't match. Copy " + Chr(34) + "transcoder" + Chr(34) + " from the helper's personal.json into account.json and build the app again."
    said = ""
    trimmed = body.Trim()
    if Left(trimmed, 1) = "{" then said = FieldStr(ParseJson(trimmed), "error")
    if said <> "" then return "Your computer says: " + said
    return "The helper on your computer answered HTTP " + code.ToStr() + "."
end function

' What the helper was doing, for the error screen: "Through the helper on your
' computer: picture converted to H.264, DTS sound converted."
function HelperPlanLine(info as Dynamic, video as String) as String
    if not IsAA(info) then return "Through the helper on your computer, which didn't describe the file."
    parts = []
    if video = "convert" then
        parts.Push("picture converted to H.264")
    else
        parts.Push("picture kept as it is")
    end if
    tracks = Field(info, "audio")
    if IsArr(tracks) then
        for each track in tracks
            plan = FieldStr(track, "plan")
            if plan <> "copy" and plan <> "" then parts.Push(CodecLabel(FieldStr(track, "codec")) + " sound converted")
        end for
    end if
    return "Through the helper on your computer: " + parts.Join(", ") + "."
end function

' --- Titles that need the helper -----------------------------------------------------

' `list` with `key` first ("m:<id>" for a movie, "e:<id>" for an episode), each key
' once, at most 200.
function AddHelperTitle(list as Dynamic, key as String) as Object
    out = [key]
    if IsArr(list) then
        for each entry in list
            text = ToStr(entry)
            if text <> "" and text <> key and out.Count() < 200 then out.Push(text)
        end for
    end if
    return out
end function

' Titles that play, but not properly, on this Roku (only DTS sound, say), so they go
' through the helper from the start next time. Registry helper/titles.
function HelperTitles() as Object
    raw = RegRead("helper", "titles")
    list = invalid
    if raw <> invalid then list = ParseJson(raw)
    if not IsArr(list) then list = []
    return list
end function

function HelperListed(key as String) as Boolean
    for each entry in HelperTitles()
        if ToStr(entry) = key then return true
    end for
    return false
end function

sub RememberHelperTitle(key as String)
    RegWrite("helper", "titles", FormatJson(AddHelperTitle(HelperTitles(), key)))
end sub
