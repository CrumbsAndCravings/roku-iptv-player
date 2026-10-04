' In-memory stand-in for Registry.brs, since the off-device interpreter has no registry.

function fakeRegistry() as Object
    globals = GetGlobalAA()
    if globals.fakeRegistry = invalid then globals.fakeRegistry = {}
    return globals.fakeRegistry
end function

function RegRead(section as String, key as String) as Dynamic
    return fakeRegistry()[section + "/" + key]
end function

sub RegWrite(section as String, key as String, value as String)
    fakeRegistry()[section + "/" + key] = value
end sub

sub RegDelete(section as String, key as String)
    fakeRegistry().Delete(section + "/" + key)
end sub

' The helper (Registry.brs) is off unless a test switches it on with
' GetGlobalAA().helperOn = true.
function HelperOn() as Boolean
    value = GetGlobalAA().helperOn
    if type(value) = "Boolean" or type(value) = "roBoolean" then return value
    return false
end function
