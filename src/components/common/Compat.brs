' Asks this Roku whether it can play a file, using the container and the codecs the
' provider reports. Answers are cached per component, since a season can have many
' episodes with the same codecs.
'
' Returns { blocked, warning }:
'   blocked  what stops the file playing here, e.g. "HEVC (H.265) video" or "AVI files"
'   warning  what may only partly work, e.g. a profile or audio track the TV can't decode
function PlaybackCheck(ext as String, videoCodec as String, videoProfile as String, audioCodec as String) as Object
    result = { blocked: "", warning: "" }
    if IsUnsupportedContainer(ext) then
        result.blocked = UCase(ext) + " files"
        return result
    end if
    warnings = []
    if videoCodec <> "" then
        codec = RokuVideoCodec(videoCodec)
        if not canDecode("video", codec, "") then
            result.blocked = CodecLabel(videoCodec) + " video"
            return result
        end if
        ' Profile names don't always match Roku's spelling, so a failed profile check
        ' is only a warning.
        if videoProfile <> "" and not canDecode("video", codec, LCase(videoProfile)) then warnings.Push(CodecLabel(videoCodec) + " " + videoProfile + " video")
    end if
    if audioCodec <> "" and not canDecode("audio", LCase(audioCodec), "") then warnings.Push(CodecLabel(audioCodec) + " audio")
    result.warning = warnings.Join(" or ")
    return result
end function

function canDecode(kind as String, codec as String, profile as String) as Boolean
    if m.decodeCache = invalid then m.decodeCache = {}
    key = kind + "|" + codec + "|" + profile
    cached = m.decodeCache[key]
    if cached <> invalid then return cached
    device = CreateObject("roDeviceInfo")
    query = { Codec: codec }
    if profile <> "" then query.Profile = profile
    if kind = "video" then
        answer = device.CanDecodeVideo(query)
    else
        answer = device.CanDecodeAudio(query)
    end if
    ok = true
    if IsAA(answer) and ToStr(answer.result) = "false" then ok = false
    m.decodeCache[key] = ok
    return ok
end function
