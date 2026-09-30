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
    return { server: FieldStr(creds, "server"), username: FieldStr(creds, "username"), password: FieldStr(creds, "password") }
end function

sub SaveCreds(creds as Object)
    RegWrite("account", "creds", FormatJson(creds))
end sub

sub ClearAccount()
    RegDelete("account", "creds")
    RegDelete("watch", "items")
end sub
