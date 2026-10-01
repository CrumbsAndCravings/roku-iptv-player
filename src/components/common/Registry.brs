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
    RegDelete("opensubtitles", "account")
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
