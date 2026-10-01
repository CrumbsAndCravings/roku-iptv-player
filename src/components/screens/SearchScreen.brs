sub init()
    m.results = m.top.FindNode("results")
    m.message = m.top.FindNode("message")
    m.status = m.top.FindNode("status")
    m.focusTitle = m.top.FindNode("focusTitle")
    m.debounce = m.top.FindNode("debounce")

    m.top.FindNode("heading").font = MakeFont("Fredoka-SemiBold", 32)
    m.message.font = MakeFont("Nunito-SemiBold", 22)
    m.status.font = MakeFont("Nunito-SemiBold", 16)
    m.focusTitle.font = MakeFont("Nunito-ExtraBold", 20)
    m.results.rowLabelFont = MakeFont("Fredoka-Medium", 21)

    m.zone = "keyboard"
    m.query = ""
    m.pending = invalid

    holder = m.top.FindNode("keyboardHolder")
    m.keyboard = holder.CreateChild("DynamicMiniKeyboard")
    if m.keyboard = invalid then m.keyboard = holder.CreateChild("MiniKeyboard")
    styleKeyboard()
    layoutResults()
    m.keyboard.ObserveField("text", "onText")

    ' One search worker per session, so the library is only indexed once.
    task = m.global.search
    if task = invalid then
        task = CreateObject("roSGNode", "SearchTask")
        m.global.search = task
        task.control = "RUN"
    end if
    m.task = task
    task.ObserveFieldScoped("results", "onResults")
    task.ObserveFieldScoped("status", "onStatus")
    onStatus()

    m.results.ObserveField("rowItemSelected", "onSelected")
    m.results.ObserveField("rowItemFocused", "onResultFocused")
    m.debounce.ObserveField("fire", "onDebounce")
    showMessage("Type a title. Results appear as you type.")
end sub

sub styleKeyboard()
    kb = m.keyboard
    if kb.HasField("palette") then
        palette = CreateObject("roSGNode", "RSGPalette")
        palette.colors = {
            KeyboardColor: "0x241C42FF"
            PrimaryTextColor: "0xF7F3FFFF"
            SecondaryTextColor: "0xA195CCFF"
            FocusColor: "0xC9B8FFFF"
            FocusItemColor: "0x151028FF"
            InputFieldColor: "0x30275AFF"
            TextEditBoxColor: "0x30275AFF"
        }
        kb.palette = palette
    end if
    if kb.HasField("keyColor") then
        kb.keyColor = "0xD8CEF5FF"
        kb.focusedKeyColor = "0x151028FF"
    end if
    editBox = kb.textEditBox
    if editBox <> invalid then
        editBox.hintText = "Movies and series"
        if editBox.HasField("hintTextColor") then editBox.hintTextColor = "0x8579B0FF"
        if editBox.HasField("textColor") then editBox.textColor = "0xF7F3FFFF"
    end if
end sub

' The keyboard's size differs between keyboard types, so place the results beside it.
sub layoutResults()
    rect = m.keyboard.BoundingRect()
    x = 36 + Int(rect.width) + 40
    if rect.width <= 0 then x = 480
    if x < 420 then x = 420
    if x > 620 then x = 620
    width = 1232 - x
    m.results.translation = [x, 96]
    m.results.itemSize = [width, 250]
    m.message.translation = [x, 150]
    m.message.width = width
    m.focusTitle.translation = [x, 626]
    m.focusTitle.width = width
end sub

sub onTakeFocus()
    if m.zone = "results" and hasResults() then
        m.results.SetFocus(true)
    else
        focusKeyboard()
    end if
end sub

' --- Typing & results ------------------------------------------------------------

sub onText()
    m.debounce.control = "stop"
    m.debounce.control = "start"
end sub

sub onDebounce()
    m.query = m.keyboard.text
    m.task.query = m.query
    if m.query.Trim() = "" then
        m.results.content = invalid
        m.focusTitle.text = ""
        showMessage("Type a title. Results appear as you type.")
    end if
end sub

sub onResults()
    results = m.task.results
    if results = invalid or m.query.Trim() = "" then return
    if not results.HasField("forQuery") then return
    if results.forQuery <> m.query then return
    ' Don't reshuffle the rows while someone is browsing them.
    if m.zone = "results" then
        m.pending = results
        return
    end if
    applyResults(results)
end sub

sub applyResults(results as Object)
    m.pending = invalid
    m.results.content = results
    if results.GetChildCount() = 0 then
        m.focusTitle.text = ""
        if isIndexing() then
            showMessage("No matches for “" + m.query.Trim() + "” yet. Still loading your library.")
        else
            showMessage("No matches for “" + m.query.Trim() + "”.")
        end if
    else
        showMessage("")
        onResultFocused()
    end if
end sub

sub showMessage(text as String)
    m.message.text = text
    m.message.visible = (text <> "")
end sub

function hasResults() as Boolean
    content = m.results.content
    if content = invalid then return false
    return content.GetChildCount() > 0
end function

function isIndexing() as Boolean
    status = m.task.status
    if not IsAA(status) then return true
    if status.stopped = true then return false
    return ToInt(status.total) = 0 or ToInt(status.done) < ToInt(status.total)
end function

sub onStatus()
    status = m.task.status
    stopped = IsAA(status) and status.stopped = true
    if stopped and ToInt(status.total) = 0 then
        m.status.text = "Your provider isn't answering, so search can't load your library. Try again later."
        return
    end if
    if not IsAA(status) or ToInt(status.total) = 0 then
        m.status.text = "Getting your library ready for search…"
        return
    end if
    done = ToInt(status.done)
    total = ToInt(status.total)
    titles = ToInt(status.titles)
    if stopped then
        m.status.text = "Searching " + titles.ToStr() + " titles. Your provider stopped answering, so the rest wait until you open ARAN+ again."
    else if done < total then
        m.status.text = "Loading your library: " + done.ToStr() + " of " + total.ToStr() + " lists (" + titles.ToStr() + " titles so far)"
    else
        m.status.text = "Searching all " + titles.ToStr() + " titles"
    end if
end sub

function selectedItem(position as Dynamic) as Dynamic
    content = m.results.content
    if content = invalid or position = invalid or position.Count() < 2 then return invalid
    row = content.GetChild(position[0])
    if row = invalid then return invalid
    return row.GetChild(position[1])
end function

sub onSelected()
    item = selectedItem(m.results.rowItemSelected)
    if item = invalid then return
    m.top.action = { name: "openDetails", item: item }
end sub

sub onResultFocused()
    item = selectedItem(m.results.rowItemFocused)
    if item = invalid then
        m.focusTitle.text = ""
        return
    end if
    text = item.title
    if item.problem <> "" then text = text + "   ·   Won't play on this " + DeviceWord()
    m.focusTitle.text = text
end sub

' --- Focus -------------------------------------------------------------------

sub focusKeyboard()
    m.zone = "keyboard"
    m.keyboard.SetFocus(true)
    if m.pending <> invalid then applyResults(m.pending)
end sub

sub focusResults()
    if not hasResults() then return
    m.zone = "results"
    m.results.SetFocus(true)
    onResultFocused()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.zone = "keyboard" then
        ' Right past the keyboard's last column (or fast-forward) moves to the results.
        if key = "right" or key = "fastforward" then
            focusResults()
            return true
        end if
        return false
    end if
    ' Results didn't use the key: Left on a row's first poster, Up on the top row, or Back.
    if key = "left" or key = "back" or key = "rewind" then
        focusKeyboard()
        return true
    end if
    return true
end function
