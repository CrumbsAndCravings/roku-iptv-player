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
    buildSymbols()
    m.keyboard.ObserveField("text", "onText")

    ' One library worker per session, so the library is only indexed once.
    task = LibraryTask()
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
    m.results.itemSize = [width, 232]
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

' --- Symbols -------------------------------------------------------------------------
'
' Roku's mini keyboard has only letters and numbers, so a few rows of symbols sit under
' it. Down from the keyboard's bottom row reaches them; OK types one.

sub buildSymbols()
    m.symbolRows = [["&", "'", "-", ":", ".", ",", "!"], ["?", "(", ")", "+", "#", "@", "/"]]
    m.symbolRow = 0
    m.symbolCol = 0
    m.symbolKeys = []
    group = m.top.FindNode("symbols")
    rect = m.keyboard.BoundingRect()
    width = Int(rect.width)
    if width < 300 then width = 404
    top = 96 + Int(rect.y + rect.height) + 14
    if rect.height <= 0 then top = 540
    group.translation = [36, top]
    columns = m.symbolRows[0].Count()
    gap = 8
    keyWidth = Int((width - gap * (columns - 1)) / columns)
    keyHeight = 42
    font = MakeFont("Nunito-ExtraBold", 22)
    for r = 0 to m.symbolRows.Count() - 1
        row = []
        for c = 0 to m.symbolRows[r].Count() - 1
            key = group.CreateChild("Group")
            key.translation = [c * (keyWidth + gap), r * (keyHeight + gap)]
            key.scaleRotateCenter = [keyWidth / 2, keyHeight / 2]
            bg = key.CreateChild("Poster")
            bg.uri = "pkg:/images/pill.9.png"
            bg.width = keyWidth
            bg.height = keyHeight
            label = key.CreateChild("Label")
            label.width = keyWidth
            label.height = keyHeight
            label.horizAlign = "center"
            label.vertAlign = "center"
            label.font = font
            label.text = m.symbolRows[r][c]
            row.Push(key)
        end for
        m.symbolKeys.Push(row)
    end for
    styleSymbols()
end sub

sub styleSymbols()
    for r = 0 to m.symbolKeys.Count() - 1
        for c = 0 to m.symbolKeys[r].Count() - 1
            key = m.symbolKeys[r][c]
            bg = key.GetChild(0)
            label = key.GetChild(1)
            focused = m.zone = "symbols" and r = m.symbolRow and c = m.symbolCol
            if focused then
                bg.blendColor = "0xC9B8FFFF"
                label.color = "0x151028FF"
                key.scale = [1.08, 1.08]
            else
                bg.blendColor = "0x30275AFF"
                label.color = "0xD8CEF5FF"
                key.scale = [1.0, 1.0]
            end if
        end for
    end for
end sub

sub focusSymbols()
    m.zone = "symbols"
    m.top.FindNode("symbolFocus").SetFocus(true)
    styleSymbols()
end sub

sub typeSymbol()
    text = m.keyboard.text + m.symbolRows[m.symbolRow][m.symbolCol]
    m.keyboard.text = text
    editBox = m.keyboard.textEditBox
    if editBox <> invalid and editBox.HasField("cursorPosition") then editBox.cursorPosition = Len(text)
end sub

function onSymbolKey(key as String) as Boolean
    columns = m.symbolRows[m.symbolRow].Count()
    if key = "left" and m.symbolCol > 0 then
        m.symbolCol = m.symbolCol - 1
    else if key = "right" or key = "fastforward" then
        if m.symbolCol < columns - 1 and key = "right" then
            m.symbolCol = m.symbolCol + 1
        else
            focusResults()
            styleSymbols()
            return true
        end if
    else if key = "up" then
        if m.symbolRow = 0 then
            focusKeyboard()
            styleSymbols()
            return true
        end if
        m.symbolRow = m.symbolRow - 1
    else if key = "down" and m.symbolRow < m.symbolRows.Count() - 1 then
        m.symbolRow = m.symbolRow + 1
    else if key = "OK" then
        typeSymbol()
    else if key = "back" then
        focusKeyboard()
        styleSymbols()
        return true
    end if
    styleSymbols()
    return true
end function

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
    if item.kind = "category" then
        kindName = "Movies"
        if item.listKind = "series" then kindName = "Series"
        m.top.action = { name: "openCategory", category: { kind: item.listKind, categoryId: item.categoryId, title: item.title + "  ·  " + kindName } }
        return
    end if
    m.top.action = { name: "openDetails", item: item }
end sub

sub onResultFocused()
    item = selectedItem(m.results.rowItemFocused)
    if item = invalid then
        m.focusTitle.text = ""
        return
    end if
    text = item.title
    if item.kind = "category" then text = item.title + "   ·   " + item.caption + " titles   ·   OK to see all"
    if item.problem <> "" then text = text + "   ·   Won't play on this " + DeviceWord()
    m.focusTitle.text = text
end sub

' --- Focus -------------------------------------------------------------------

sub focusKeyboard()
    m.zone = "keyboard"
    styleSymbols()
    m.keyboard.SetFocus(true)
    if m.pending <> invalid then applyResults(m.pending)
end sub

sub focusResults()
    if not hasResults() then return
    m.zone = "results"
    styleSymbols()
    m.results.SetFocus(true)
    onResultFocused()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.zone = "symbols" then return onSymbolKey(key)
    if m.zone = "keyboard" then
        ' Right past the keyboard's last column (or fast-forward) moves to the results;
        ' Down past its bottom row reaches the symbols.
        if key = "right" or key = "fastforward" then
            focusResults()
            return true
        else if key = "down" then
            focusSymbols()
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
