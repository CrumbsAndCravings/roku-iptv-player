sub init()
    m.top.FindNode("heading").font = MakeFont("Fredoka-SemiBold", 44)
    m.top.FindNode("intro").font = MakeFont("Nunito-SemiBold", 21)
    m.top.FindNode("status").font = MakeFont("Nunito-ExtraBold", 17)
    m.top.FindNode("tipsHeading").font = MakeFont("Fredoka-Medium", 22)
    m.top.FindNode("tips").font = MakeFont("Nunito-SemiBold", 18)
    m.status = m.top.FindNode("status")

    m.labels = ["SERVER", "USERNAME", "PASSWORD"]
    m.hints = ["e.g. http://line.example.com:8080", "", ""]
    m.values = ["", "", ""]
    builtIn = BuiltInCreds()
    if builtIn <> invalid then m.values = [builtIn.server, builtIn.username, builtIn.password]
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
        bg.width = 560
        bg.height = 64
        caption = group.CreateChild("Label")
        caption.translation = [22, 9]
        caption.font = MakeFont("Nunito-ExtraBold", 13)
        caption.text = m.labels[i]
        value = group.CreateChild("Label")
        value.translation = [22, 27]
        value.width = 516
        value.font = MakeFont("Nunito-SemiBold", 22)
        m.fields.Push({ bg: bg, caption: caption, value: value })
    end for
    m.submit = BuildPills(m.top.FindNode("submit"), ["Sign in"], 22)
    render()
end sub

sub onTakeFocus()
    m.top.SetFocus(true)
end sub

sub render()
    for i = 0 to 2
        f = m.fields[i]
        focused = (i = m.index)
        text = m.values[i]
        isHint = false
        if text = "" then
            text = m.hints[i]
            isHint = true
        else if i = 2 then
            text = String(Len(text), "•")
        end if
        f.value.text = text
        if focused then
            f.bg.blendColor = "0xC9B8FFFF"
            f.caption.color = "0x5A4E86FF"
            f.value.color = "0x151028FF"
            if isHint then f.value.color = "0x9083BDFF"
        else
            f.bg.blendColor = "0x241C42FF"
            f.caption.color = "0x9083BDFF"
            f.value.color = "0xF7F3FFFF"
            if isHint then f.value.color = "0x6B5F96FF"
        end if
    end for
    submitFocus = -1
    if m.index = 3 then submitFocus = 0
    StylePills(m.submit, submitFocus, -1)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press or m.busy then return true
    if key = "up" and m.index > 0 then
        m.index = m.index - 1
        render()
        return true
    else if key = "down" and m.index < 3 then
        m.index = m.index + 1
        render()
        return true
    else if key = "OK" then
        if m.index < 3 then
            openKeyboard(m.index)
        else
            submit()
        end if
        return true
    end if
    return key <> "back"
end function

sub openKeyboard(index as Integer)
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = m.labels[index]
    if index = 0 then dialog.message = ["Your server address, or a full M3U link."]
    dialog.text = m.values[index]
    dialog.buttons = ["Done", "Cancel"]
    dialog.textEditBox.maxTextLength = 256
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
        text = dialog.text
        if m.editing = 0 and Instr(1, LCase(text), "username=") > 0 then
            link = ParseProviderLink(text)
            m.values[0] = link.server
            if link.username <> "" then m.values[1] = link.username
            if link.password <> "" then m.values[2] = link.password
        else if m.editing = 2 then
            m.values[2] = text
        else
            m.values[m.editing] = text.Trim()
        end if
        m.index = nextEmptyField()
        m.status.text = ""
    end if
    dialog.close = true
    render()
end sub

sub onKeyboardClosed()
    m.top.SetFocus(true)
end sub

function nextEmptyField() as Integer
    for i = 0 to 2
        if m.values[i] = "" then return i
    end for
    return 3
end function

sub submit()
    creds = { server: NormalizeServer(m.values[0]), username: m.values[1].Trim(), password: m.values[2].Trim() }
    if creds.server = "" or creds.username = "" or creds.password = "" then
        m.status.text = "Fill in the server, username and password first."
        m.index = nextEmptyField()
        render()
        return
    end if
    m.busy = true
    m.status.text = "Checking your login…"
    m.task = CreateObject("roSGNode", "XtreamTask")
    m.task.request = { mode: "auth", creds: creds }
    m.task.ObserveField("result", "onAuthResult")
    m.task.control = "RUN"
end sub

sub onAuthResult(event as Object)
    result = event.GetData()
    m.busy = false
    m.task = invalid
    if result.ok then
        creds = result.request.creds
        SaveCreds(creds)
        m.status.text = ""
        m.top.action = { name: "signedIn", creds: creds }
    else
        m.status.text = result.error
    end if
end sub

sub onAutoSignIn()
    if m.top.autoSignIn and not m.busy then submit()
end sub
