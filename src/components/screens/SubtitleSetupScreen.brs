sub init()
    m.top.FindNode("heading").font = MakeFont("Fredoka-SemiBold", 44)
    m.top.FindNode("intro").font = MakeFont("Nunito-SemiBold", 21)
    m.top.FindNode("tipsHeading").font = MakeFont("Fredoka-Medium", 22)
    m.top.FindNode("tips").font = MakeFont("Nunito-SemiBold", 18)
    m.status = m.top.FindNode("status")
    m.status.font = MakeFont("Nunito-ExtraBold", 19)

    m.labels = ["API KEY", "USERNAME (OPTIONAL)", "PASSWORD (OPTIONAL)"]
    m.hints = ["From your OpenSubtitles profile", "For about 20 downloads a day", ""]
    m.values = ["", "", ""]
    existing = LoadOsAccount()
    m.hasAccount = existing <> invalid
    if m.hasAccount then
        m.values = [FieldStr(existing, "apiKey"), FieldStr(existing, "username"), FieldStr(existing, "password")]
    end if
    m.index = 0
    m.busy = false
    m.task = invalid

    fields = m.top.FindNode("fields")
    m.fields = []
    for i = 0 to 2
        group = fields.CreateChild("Group")
        group.translation = [0, i * 78]
        bg = group.CreateChild("Poster")
        bg.uri = "pkg:/images/pill.9.png"
        bg.width = 580
        bg.height = 64
        caption = group.CreateChild("Label")
        caption.translation = [22, 9]
        caption.font = MakeFont("Nunito-ExtraBold", 13)
        caption.text = m.labels[i]
        value = group.CreateChild("Label")
        value.translation = [22, 27]
        value.width = 536
        value.font = MakeFont("Nunito-SemiBold", 22)
        m.fields.Push({ bg: bg, caption: caption, value: value })
    end for
    buildButtons()
    render()
    if m.hasAccount then showStatus("Connected. Change anything and save to check again.", true)
end sub

sub buildButtons()
    m.buttonLabels = ["Save and check"]
    if m.hasAccount then m.buttonLabels.Push("Remove")
    m.buttons = BuildPills(m.top.FindNode("buttons"), m.buttonLabels, 22)
end sub

sub onTakeFocus()
    m.top.SetFocus(true)
end sub

' The key is shown with only its last four characters.
function displayValue(i as Integer) as String
    text = m.values[i]
    if text = "" then return ""
    if i = 2 then return String(Len(text), "•")
    if i = 0 and Len(text) > 4 then return String(Len(text) - 4, "•") + Right(text, 4)
    return text
end function

sub render()
    for i = 0 to 2
        f = m.fields[i]
        text = displayValue(i)
        isHint = text = ""
        if isHint then text = m.hints[i]
        f.value.text = text
        if i = m.index then
            f.bg.blendColor = "0xC9B8FFFF"
            f.caption.color = "0x5A4E86FF"
            f.value.color = "0x151028FF"
            if isHint then f.value.color = "0x6B5F96FF"
        else
            f.bg.blendColor = "0x241C42FF"
            f.caption.color = "0x9083BDFF"
            f.value.color = "0xF7F3FFFF"
            if isHint then f.value.color = "0x6B5F96FF"
        end if
    end for
    buttonFocus = -1
    if m.index >= 3 then buttonFocus = m.index - 3
    StylePills(m.buttons, buttonFocus, -1)
end sub

sub showStatus(text as String, good as Boolean)
    m.status.text = text
    if good then
        m.status.color = "0xC9B8FFFF"
    else
        m.status.color = "0xFF9ECFFF"
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press or m.busy then return key <> "back"
    last = 2 + m.buttons.Count()
    if key = "up" and m.index > 0 then
        if m.index > 3 then
            m.index = 2
        else
            m.index = m.index - 1
        end if
    else if key = "down" and m.index < 3 then
        m.index = m.index + 1
    else if key = "right" and m.index >= 3 and m.index < last then
        m.index = m.index + 1
    else if key = "left" and m.index > 3 then
        m.index = m.index - 1
    else if key = "OK" then
        if m.index < 3 then
            openKeyboard(m.index)
        else if m.buttonLabels[m.index - 3] = "Remove" then
            remove()
        else
            save()
        end if
    else if key = "back" then
        return false
    end if
    render()
    return true
end function

sub openKeyboard(index as Integer)
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = m.labels[index]
    dialog.text = m.values[index]
    dialog.buttons = ["Done", "Cancel"]
    if index = 2 then dialog.textEditBox.secureMode = true
    dialog.ObserveField("buttonSelected", "onKeyboardButton")
    dialog.ObserveField("wasClosed", "onKeyboardClosed")
    m.editing = index
    m.top.GetScene().dialog = dialog
end sub

sub onKeyboardButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    if dialog.buttonSelected = 0 then
        m.values[m.editing] = dialog.text.Trim()
        m.status.text = ""
        if m.editing < 2 then m.index = m.editing + 1
    end if
    dialog.close = true
    render()
end sub

sub onKeyboardClosed()
    m.top.SetFocus(true)
end sub

sub save()
    apiKey = m.values[0]
    username = m.values[1]
    password = m.values[2]
    if apiKey = "" then
        showStatus("Enter your API key first.", false)
        m.index = 0
        return
    end if
    if username <> "" and password = "" then
        showStatus("Add the password for " + username + ", or clear the username.", false)
        m.index = 2
        return
    end if
    m.busy = true
    showStatus("Checking with OpenSubtitles…", true)
    m.task = CreateObject("roSGNode", "SubtitleTask")
    m.task.request = { mode: "login", account: { apiKey: apiKey, username: username, password: password } }
    m.task.ObserveField("result", "onChecked")
    m.task.control = "RUN"
end sub

sub onChecked(event as Object)
    result = event.GetData()
    m.busy = false
    m.task = invalid
    if not result.ok then
        showStatus(result.error, false)
        return
    end if
    account = result.request.account
    if IsAA(result.account) then account = result.account
    SaveOsAccount(account)
    m.hasAccount = true
    buildButtons()
    allowed = ToInt(result.allowed)
    if result.name <> "" then
        text = "Connected as " + result.name + "."
    else
        text = "Key works. Without a login you get about 5 downloads a day."
    end if
    if allowed > 0 and result.name <> "" then text = text + " " + allowed.ToStr() + " downloads a day."
    showStatus(text, true)
    render()
end sub

sub remove()
    RegDelete("opensubtitles", "account")
    m.values = ["", "", ""]
    m.hasAccount = false
    m.index = 0
    buildButtons()
    showStatus("Removed. Online subtitles are off.", true)
end sub
