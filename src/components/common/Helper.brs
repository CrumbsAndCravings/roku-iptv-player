' The helper on a computer at home (the Samsung repo's helper/, started with
' npm run helper): it fetches a file from the provider and converts what this Roku
' can't play into HLS with FFmpeg while you watch. For a film of known length it lists
' the whole film in six-second pieces from the start (a VOD playlist) and makes each
' piece when Roku asks for it, so the stream's clock is the film's and Roku jumps by
' itself; otherwise it writes a playlist that grows from where it was started. For a
' whole film it also makes a picture for every ten seconds, which the TV keeps.
' Settings come from account.json
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

' What the file holds, and what the helper would do with each track.
function HelperInfoUrl(config as Object, kind as String, id as String, ext as String) as String
    return helperBase(config, "/v1/info") + "&" + HelperFileQuery(kind, id, ext)
end function

' The file's OpenSubtitles fingerprint, read by the helper, so the Roku makes no
' requests to the provider of its own.
function HelperHashUrl(config as Object, kind as String, id as String, ext as String) as String
    return helperBase(config, "/v1/hash") + "&" + HelperFileQuery(kind, id, ext)
end function

' Starts the converted video, playing from `start` seconds; the helper answers once the
' first piece is ready (ParseHelperStart). choice is { video, height, hevc, track }
' (HelperVideo, HelperHeight, whether this Roku decodes HEVC, HelperTrack). The whole
' film's playlist (vod=1) in MPEG-TS pieces; the picture and the one sound track
' become H.264 and stereo AAC.
function HelperStartUrl(config as Object, kind as String, id as String, ext as String, start as Integer, choice as Object) as String
    if start < 0 then start = 0
    url = helperBase(config, "/v1/hls/start") + "&" + HelperFileQuery(kind, id, ext) + "&start=" + start.ToStr() + "&vod=1&format=ts"
    video = FieldStr(choice, "video")
    if video <> "" then url = url + "&video=" + video
    height = ToInt(Field(choice, "height"))
    if height > 0 then url = url + "&height=" + height.ToStr()
    if not helperFlag(choice, "hevc") then url = url + "&hevc=0"
    track = Field(choice, "track")
    if track <> invalid and ToInt(track) >= 0 then url = url + "&a=" + ToInt(track).ToStr()
    return url
end function

function HelperErrorUrl(config as Object) as String
    return helperBase(config, "/v1/last-error")
end function

' Stops the helper's FFmpeg for `session` (all of it when ""), so the provider's one
' connection is free again.
function HelperStopUrl(config as Object, session as String) as String
    url = helperBase(config, "/v1/stop")
    if session <> "" then url = url + "&session=" + session.EncodeUriComponent()
    return url
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

' Which of the helper's sound tracks is in the viewer's language (prefs "audio"): the
' helper's stream carries one; -1 for none (the file's first).
function HelperTrack(audio as Dynamic, language as String) as Integer
    if not IsArr(audio) or language = "" then return -1
    wanted = LanguageName(language)
    if wanted = "" then return -1
    for i = 0 to audio.Count() - 1
        if LanguageName(FieldStr(audio[i], "language")) = wanted then return i
    end for
    return -1
end function

' For a growing playlist (a file of unknown length): whether a jump to `target` stays
' inside what the helper has converted so far. Its stream starts at `offset` and Roku
' has `available` seconds of it listed; a margin of two pieces keeps the jump off the
' part still being written. A whole film's playlist jumps anywhere.
function HelperSeekInside(target as Float, offset as Integer, available as Float) as Boolean
    if available <= 0 or target < offset then return false
    return target <= offset + available - 12
end function

' A helper stream that ends more than a minute before the file does has stopped early
' (FFmpeg was stopped, or the provider's connection dropped).
function HelperEndedEarly(position as Integer, duration as Integer) as Boolean
    return duration > 0 and position < duration - 60
end function

' The file's sound tracks for the Audio column, from the helper's description: its
' stream carries one, so choosing another starts it again with that one. Each option is
' { id: "helper:<n>", label, language, format }.
function HelperAudioOptions(audio as Dynamic) as Object
    options = []
    if not IsArr(audio) then return options
    for i = 0 to audio.Count() - 1
        codec = LCase(FieldStr(audio[i], "codec"))
        language = LCase(FieldStr(audio[i], "language"))
        label = TrackLabel(language, FieldStr(audio[i], "title"), "Track " + (i + 1).ToStr())
        if codec <> "" then label = label + " · " + CodecLabel(codec)
        options.Push({ id: "helper:" + i.ToStr(), label: label, language: language, format: codec })
    end for
    return options
end function

' --- What the helper says ------------------------------------------------------------

' The helper's description of a file (/v1/info).
function ParseHelperInfo(data as Dynamic) as Object
    video = Field(data, "video")
    plan = FieldStr(data, "videoPlan")
    if plan <> "try" and plan <> "convert" then plan = "copy"
    audio = []
    tracks = Field(data, "audio")
    if IsArr(tracks) then
        for each track in tracks
            if IsAA(track) then audio.Push({ codec: FieldStr(track, "codec"), channels: ToInt(track.channels), language: FieldStr(track, "language"), title: FieldStr(track, "title"), plan: FieldStr(track, "plan") })
        end for
    end if
    return {
        duration: ToInt(Field(data, "duration"))
        videoCodec: FieldStr(video, "codec")
        width: ToInt(Field(video, "width"))
        height: ToInt(Field(video, "height"))
        videoPlan: plan
        audio: audio
    }
end function

' A started stream (/v1/hls/start): `url` is the playlist's address on the helper,
' `start` where the stream's clock starts in the film (0 for a whole film's playlist,
' whose clock is the film's), `playFrom` where to start playing, `vod` whether the
' playlist lists the whole film, and `previews` its pictures (parseHelperPreviews).
function ParseHelperStart(data as Dynamic) as Object
    url = FieldStr(data, "url")
    if Left(url, 1) <> "/" then url = ""
    return {
        session: FieldStr(data, "session")
        url: url
        vod: helperFlag(data, "vod")
        start: ToInt(Field(data, "start"))
        playFrom: ToInt(Field(data, "from"))
        duration: ToInt(Field(data, "duration"))
        video: FieldStr(data, "video")
        audioTrack: ToInt(Field(data, "audioTrack"))
        audioPlan: FieldStr(data, "audioPlan")
        previews: parseHelperPreviews(Field(data, "previews"))
    }
end function

' The pictures of a whole film's playlist: one for each `every` seconds, which the helper
' makes as it converts. `list` and `bundle` (helper 1.8 and newer) are where the TV asks
' what's new and fetches those pictures in one file (PreviewTask); "" from an older helper,
' which has no such file, so the TV shows just the time. invalid without pictures.
function parseHelperPreviews(data as Dynamic) as Dynamic
    every = ToInt(Field(data, "every"))
    prefix = FieldStr(data, "prefix")
    if every <= 0 or Left(prefix, 1) <> "/" then return invalid
    list = FieldStr(data, "list")
    bundle = FieldStr(data, "bundle")
    if Left(list, 1) <> "/" or Left(bundle, 1) <> "/" then
        list = ""
        bundle = ""
    end if
    return { every: every, prefix: prefix, list: list, bundle: bundle }
end function

' --- Pictures for choosing a jump -------------------------------------------------------
'
' The TV keeps a whole film's pictures itself (tasks/PreviewTask.brs), so a press shows
' its picture at once. Picture n is for `every` seconds from n x every (it shows their
' middle). A session's files need no key: its random name is one.

' What's new since picture number `after` (previews.json).
function HelperPicturesUrl(config as Object, previews as Object, after as Integer) as String
    return config.url + previews.list + "?after=" + after.ToStr()
end function

' Pictures numbered after `after` up to `upto`, as one BIF (previews.bif).
function HelperBundleUrl(config as Object, previews as Object, after as Integer, upto as Integer) as String
    return config.url + previews.bundle + "?after=" + after.ToStr() + "&upto=" + upto.ToStr()
end function

' The helper's answer from previews.json: the latest picture number, how many are new,
' the stretches converted ([from, to] seconds) and where it's converting now (invalid
' when it isn't).
function ParseHelperPictures(data as Dynamic) as Object
    converted = []
    for each range in toRanges(Field(data, "converted"))
        converted.Push(range)
    end for
    running = invalid
    ranges = toRanges([Field(data, "running")])
    if ranges.Count() = 1 then running = ranges[0]
    return { seq: ToInt(Field(data, "seq")), count: ToInt(Field(data, "count")), converted: converted, running: running }
end function

function toRanges(value as Dynamic) as Object
    ranges = []
    if not IsArr(value) then return ranges
    for each range in value
        if IsArr(range) and range.Count() = 2 then
            low = ToInt(range[0])
            high = ToInt(range[1])
            if high > low and low >= 0 then ranges.Push([low, high])
        end if
    end for
    return ranges
end function

' Which picture shows `seconds` into the film.
function PictureNumber(seconds as Float, every as Integer) as Integer
    if every <= 0 or seconds < 0 then return -1
    return Int(seconds / every)
end function

' Whether picture n is coming: its moment is converted (the TV fetches it on its next
' look), or just ahead of where the helper is converting. Before the helper's first
' answer (`news` invalid) every picture may be. Otherwise there's nothing to wait for.
function PictureComing(n as Integer, every as Integer, news as Dynamic) as Boolean
    if n < 0 then return false
    if not IsAA(news) then return true
    middle = n * every + every / 2
    for each range in news.converted
        if middle >= range[0] and middle < range[1] then return true
    end for
    running = news.running
    return IsArr(running) and middle >= running[0] and middle < running[1] + 30
end function

' The five moments in the row of pictures while choosing a jump: where you'd land in the
' middle, and where the next two presses either way would (`step` seconds apart). -1 for
' one outside the film (a duration of 0 is unknown, so there's no end).
function StripTimes(target as Float, stepSize as Integer, duration as Float) as Object
    times = []
    for k = -2 to 2
        t = target + k * stepSize
        if t < 0 or (duration > 0 and t > duration) then t = -1
        times.Push(t)
    end for
    return times
end function

' The pictures in a BIF (Roku's format for them; the helper's previews.bif): for each,
' its time in seconds and where its JPEG is in `bytes` (a roByteArray, or an array of
' byte values). invalid for anything that isn't a BIF this can read.
function ReadBifIndex(bytes as Object) as Dynamic
    size = bytes.Count()
    if size < 72 then return invalid
    magic = [137, 66, 73, 70, 13, 10, 26, 10]
    for i = 0 to 7
        if bytes[i] <> magic[i] then return invalid
    end for
    count = bifWord(bytes, 12)
    unit = bifWord(bytes, 16)
    if unit = 0 then unit = 1000
    if count < 0 or unit < 0 then return invalid
    indexEnd = 64 + (count + 1) * 8
    if indexEnd > size then return invalid
    pictures = []
    for i = 0 to count - 1
        at = 64 + i * 8
        stamp = bifWord(bytes, at)
        start = bifWord(bytes, at + 4)
        finish = bifWord(bytes, at + 12)
        if stamp < 0 or start < indexEnd or finish <= start or finish > size then return invalid
        pictures.Push({ seconds: stamp * unit / 1000, start: start, length: finish - start })
    end for
    return pictures
end function

' A little-endian 32-bit value; -1 past 2^31 (the end entry's 0xffffffff, or nonsense).
function bifWord(bytes as Object, at as Integer) as Integer
    if bytes[at + 3] > 127 then return -1
    return bytes[at] + bytes[at + 1] * 256 + bytes[at + 2] * 65536 + bytes[at + 3] * 16777216
end function

' The OpenSubtitles fingerprint in the helper's answer (/v1/hash): 16 hex digits, or "".
function ParseHelperHash(data as Dynamic) as String
    hash = LCase(FieldStr(data, "hash"))
    if CreateObject("roRegex", "^[0-9a-f]{16}$", "").IsMatch(hash) then return hash
    return ""
end function

' Why a request to the helper failed, in plain words. code 0 means no answer.
function HelperFailure(code as Integer, body as String) as String
    if code <= 0 then return "The helper on your computer didn't answer. Is the computer on, with the helper running?"
    if code = 401 then return "The helper on your computer turned this app away: its key doesn't match. Copy " + Chr(34) + "transcoder" + Chr(34) + " from the helper's personal.json into account.json and build the app again."
    if code = 404 then return "The helper on your computer doesn't know this request, so it may be older than this app. Update it (git pull in the Samsung repo) and start it again."
    said = ""
    trimmed = body.Trim()
    if Left(trimmed, 1) = "{" then said = FieldStr(ParseJson(trimmed), "error")
    if said <> "" then return "Your computer says: " + said
    return "The helper on your computer answered HTTP " + code.ToStr() + "."
end function

' What the helper was doing, for the error screen: "Through the helper on your
' computer: picture converted to H.264, DTS sound converted to AAC." `info` is its
' description of the file, `started` the stream it started (ParseHelperStart).
function HelperPlanLine(info as Dynamic, started as Dynamic) as String
    if not IsAA(info) or not IsAA(started) then return "Through the helper on your computer, which didn't describe the file."
    parts = []
    if FieldStr(started, "video") = "copy" then
        parts.Push("picture kept as it is")
    else
        parts.Push("picture converted to H.264")
    end if
    tracks = Field(info, "audio")
    n = ToInt(Field(started, "audioTrack"))
    if IsArr(tracks) and n >= 0 and n < tracks.Count() then
        codec = LCase(FieldStr(tracks[n], "codec"))
        if FieldStr(started, "audioPlan") = "aac" and codec <> "aac" then
            parts.Push(CodecLabel(codec) + " sound converted to AAC")
        else
            parts.Push(CodecLabel(codec) + " sound kept")
        end if
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
