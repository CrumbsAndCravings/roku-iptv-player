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

' Sign-out. The watch history, ratings and My List stay for the same account signing
' back in (at a new address too); another account signing in clears them (NoteLogin).
' Continue Watching comes back from the sync service.
sub ClearAccount()
    RegDelete("account", "creds")
    RegDelete("progress", "items")
    RegDelete("progress", "removed")
    RegDelete("opensubtitles", "account")
    RegDelete("helper", "titles")
    DeleteFile(SearchCachePath())
    RegDelete("search", "saved")
end sub

' The account last signed in on this TV: { server, username, pass } (pass is
' PasswordStamp's, not the password), or invalid.
function LastLogin() as Dynamic
    raw = RegRead("account", "last")
    last = invalid
    if raw <> invalid then last = ParseJson(raw)
    if not IsAA(last) or FieldStr(last, "username") = "" then return invalid
    return last
end function

' A sign-in (or a login a build carries): the same account at a new address keeps
' everything, and Continue Watching follows from the old address's sync space at the
' next sync (sync/previous, SyncTask); another account clears what this TV learnt about
' the last one (watch history, ratings, My List).
sub NoteLogin(creds as Object)
    now = { server: NormalizeServer(FieldStr(creds, "server")), username: FieldStr(creds, "username"), pass: PasswordStamp(FieldStr(creds, "password")) }
    last = LastLogin()
    if last <> invalid then
        change = LoginChange(last, now)
        if change = "moved" then
            NoteMovedFrom(FieldStr(last, "server"), now)
        else if change = "other" then
            RegDelete("taste", "history")
            RegDelete("taste", "scores")
            RegDelete("mylist", "items")
            RegDelete("sync", "previous")
        end if
    end if
    RegWrite("account", "last", FormatJson(now))
end sub

' The account moved from `server` to now's address: its old sync space is fetched once
' at the next sync and folded into the new one.
sub NoteMovedFrom(server as String, now as Object)
    old = SyncSpace({ server: server, username: now.username })
    if server <> "" and old <> SyncSpace(now) then RegWrite("sync", "previous", old)
end sub

' A short fingerprint of a password, to tell the same account from another without
' keeping the password itself after a sign-out.
function PasswordStamp(text as String) as String
    if text = "" then return ""
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(text)
    digest = CreateObject("roEVPDigest")
    digest.Setup("sha256")
    return LCase(Left(digest.Process(bytes), 16))
end function

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
' When this Roku has none (a new install, a cleared registry, after signing out), a
' personal build's own account.json "opensubtitles" is used (PickOsAccount).
function LoadOsAccount() as Dynamic
    return PickOsAccount(RegRead("opensubtitles", "account"), BuiltInOsAccount())
end function

sub SaveOsAccount(account as Object)
    RegWrite("opensubtitles", "account", FormatJson(account))
end sub

' Turns online subtitles off on this Roku, the build's own account too, until sign-out.
sub RemoveOsAccount()
    RegWrite("opensubtitles", "account", FormatJson({ removed: true }))
end sub

' The OpenSubtitles account built into this package, or invalid. Read once per
' component.
function BuiltInOsAccount() as Dynamic
    if m.builtInOs = invalid then m.builtInOs = { value: OsAccountSettings(ParseJson(ReadAsciiFile("pkg:/source/account.json"))) }
    return m.builtInOs.value
end function

' Whether the library worker has a library stored on this Roku (tasks/SearchTask.brs
' sets search/saved when it loads or saves one). Screens check this rather than the file:
' roFileSystem can't be made on the render thread, which crashes the app.
function LibrarySaved() as Boolean
    return RegRead("search", "saved") <> invalid
end function

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
