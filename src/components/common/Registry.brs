' Small wrappers around the Roku registry (persistent key/value storage on the TV).
' Tests swap this file for tests/fake_registry.brs.

function RegRead(section as String, key as String) as Dynamic
    sec = CreateObject("roRegistrySection", section)
    if sec.Exists(key) then return sec.Read(key)
    return invalid
end function

sub RegWrite(section as String, key as String, value as String)
    sec = CreateObject("roRegistrySection", section)
    sec.Write(key, value)
    sec.Flush()
end sub

sub RegDelete(section as String, key as String)
    sec = CreateObject("roRegistrySection", section)
    sec.Delete(key)
    sec.Flush()
end sub

function LoadCreds() as Dynamic
    raw = RegRead("account", "creds")
    if raw = invalid then return invalid
    creds = ParseJson(raw)
    if not IsAA(creds) then return invalid
    if FieldStr(creds, "server") = "" or FieldStr(creds, "username") = "" then return invalid
    return { server: FieldStr(creds, "server"), username: FieldStr(creds, "username"), password: FieldStr(creds, "password"), userAgent: FieldStr(creds, "userAgent") }
end function

sub SaveCreds(creds as Object)
    RegWrite("account", "creds", FormatJson(creds))
end sub

sub ClearAccount()
    RegDelete("account", "creds")
    RegDelete("progress", "items")
    RegDelete("progress", "removed")
    RegDelete("opensubtitles", "account")
    RegDelete("helper", "titles")
    DeleteFile(SearchCachePath())
end sub

' Player preferences, e.g. { audio: "hin", subtitles: "eng" } (language codes, or "off").
function LoadPrefs() as Object
    raw = RegRead("prefs", "player")
    prefs = invalid
    if raw <> invalid then prefs = ParseJson(raw)
    if not IsAA(prefs) then prefs = {}
    return prefs
end function

sub SavePref(key as String, value as String)
    prefs = LoadPrefs()
    prefs[key] = value
    RegWrite("prefs", "player", FormatJson(prefs))
end sub

' OpenSubtitles account: { apiKey, username, password, token, baseUrl }. Stays on the TV.
function LoadOsAccount() as Dynamic
    raw = RegRead("opensubtitles", "account")
    if raw = invalid then return invalid
    account = ParseJson(raw)
    if not IsAA(account) or FieldStr(account, "apiKey") = "" then return invalid
    return account
end function

sub SaveOsAccount(account as Object)
    RegWrite("opensubtitles", "account", FormatJson(account))
end sub

' A login built into this package (src/source/account.json, which git ignores), so a
' personal build can sign in by itself. invalid when there isn't one.
function BuiltInCreds() as Dynamic
    data = ParseJson(ReadAsciiFile("pkg:/source/account.json"))
    if not IsAA(data) then return invalid
    creds = { server: NormalizeServer(FieldStr(data, "server")), username: FieldStr(data, "username"), password: FieldStr(data, "password") }
    if creds.server = "" or creds.username = "" or creds.password = "" then return invalid
    return creds
end function

' Languages whose categories to show, like ["en", "hi", "pa"]; empty means all of them.
' A personal build sets them in src/source/account.json ("languages").
function LanguagePrefs() as Object
    raw = RegRead("prefs", "languages")
    if raw <> invalid then
        saved = ParseJson(raw)
        if IsArr(saved) then return saved
    end if
    builtIn = Field(ParseJson(ReadAsciiFile("pkg:/source/account.json")), "languages")
    if IsArr(builtIn) then return builtIn
    return []
end function

' Where Continue Watching syncs to: { url, key } from a personal build's account.json
' ("sync"), or invalid when there's no sync service.
function SyncConfig() as Dynamic
    sync = Field(ParseJson(ReadAsciiFile("pkg:/source/account.json")), "sync")
    url = FieldStr(sync, "url")
    key = FieldStr(sync, "key")
    if url = "" or key = "" then return invalid
    if Right(url, 1) = "/" then url = Left(url, Len(url) - 1)
    return { url: url, key: key }
end function

' This login's list on the sync service: 16 hex digits of SHA-256(SyncSpaceText).
function SyncSpace(creds as Object) as String
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(SyncSpaceText(creds))
    digest = CreateObject("roEVPDigest")
    digest.Setup("sha256")
    return LCase(Left(digest.Process(bytes), 16))
end function

' The helper on a computer at home that converts what this Roku can't play: { url, key }
' from a personal build's account.json ("transcoder"), or invalid. Read once per
' component.
function TranscoderConfig() as Dynamic
    if m.transcoderConfig = invalid then m.transcoderConfig = { value: TranscoderSettings(ParseJson(ReadAsciiFile("pkg:/source/account.json"))) }
    return m.transcoderConfig.value
end function

' True when a helper is set up. Without one, everything plays as before.
function HelperOn() as Boolean
    return TranscoderConfig() <> invalid
end function
