sub init()
    m.heading = m.top.FindNode("heading")
    m.count = m.top.FindNode("count")
    m.grid = m.top.FindNode("grid")
    m.message = m.top.FindNode("message")
    m.focusTitle = m.top.FindNode("focusTitle")
    m.searchBg = m.top.FindNode("searchBg")
    m.searchLabel = m.top.FindNode("searchLabel")
    m.keys = m.top.FindNode("keys")
    m.debounce = m.top.FindNode("debounce")
    m.heading.font = MakeFont("Fredoka-SemiBold", 32)
    m.count.font = MakeFont("Nunito-SemiBold", 16)
    m.message.font = MakeFont("Nunito-SemiBold", 22)
    m.focusTitle.font = MakeFont("Nunito-ExtraBold", 18)
    m.searchLabel.font = MakeFont("Fredoka-Medium", 18)

    m.key = ""
    m.query = ""
    m.allCount = -1
    m.loading = false
    m.zone = "grid"
    m.lastAsked = CreateObject("roTimespan")
    m.task = LibraryTask()
    m.task.ObserveFieldScoped("browsed", "onBrowsed")
    m.task.ObserveFieldScoped("status", "onLibraryStatus")
    m.grid.ObserveField("itemSelected", "onSelected")
    m.grid.ObserveField("itemFocused", "onFocused")
    m.debounce.ObserveField("fire", "onDebounce")
    styleSearchButton()
end sub

sub onCategory()
    category = m.top.category
    m.heading.text = FieldStr(category, "title")
    m.count.text = ""
    m.message.text = "Gathering titles…"
    ask()
end sub

' Asks the library worker for this category's titles, narrowed by the search when there
' is one (answered from the Roku's copy).
sub ask()
    m.lastAsked.Mark()
    category = m.top.category
    m.key = FieldStr(category, "kind") + ":" + FieldStr(category, "categoryId") + ":" + m.query
    m.task.browse = { kind: FieldStr(category, "kind"), categoryId: FieldStr(category, "categoryId"), query: m.query }
end sub

sub onBrowsed()
    list = m.task.browsed
    if list = invalid or not list.HasField("forKey") or list.forKey <> m.key then return
    m.loading = list.loading = true
    total = ToInt(list.total)
    if m.query = "" then m.allCount = total
    shown = list.GetChildCount()
    styleSearchButton()
    if shown = 0 then
        m.grid.content = invalid
        m.focusTitle.text = ""
        if m.query <> "" then
            m.message.text = "Nothing here matches “" + m.query + "”. Back clears the search."
        else if m.loading then
            m.message.text = "Your library is still loading. This category's titles will appear here as they arrive."
        else
            m.message.text = "Nothing in this category yet."
        end if
        m.count.text = ""
        if m.zone = "grid" and not keyboardOpen() then focusSearch()
        return
    end if
    m.message.text = ""
    m.grid.content = list
    m.grid.jumpToItem = 0
    if m.query <> "" then
        text = Commas(total) + " matching “" + m.query + "”"
        if m.allCount >= 0 then text = text + " of " + Commas(m.allCount)
    else
        text = Commas(total) + " titles, newest first"
        if shown < total then text = "The newest " + Commas(shown) + " of " + Commas(total) + " titles"
    end if
    if m.loading then text = text + ". Still loading your library."
    m.count.text = text
    ' While the keyboard is up it keeps focus; the grid behind just updates.
    if m.zone = "grid" and not keyboardOpen() then m.grid.SetFocus(true)
    onFocused()
end sub

function keyboardOpen() as Boolean
    return m.top.GetScene().dialog <> invalid
end function

' While the library is still arriving, refresh the page now and then.
sub onLibraryStatus()
    if m.loading and m.lastAsked.TotalSeconds() >= 5 then ask()
end sub

sub onFocused()
    MovedSound(m.grid, m.grid.itemFocused)
    content = m.grid.content
    if content = invalid then return
    item = content.GetChild(m.grid.itemFocused)
    if item = invalid then return
    parts = [item.title]
    if item.year <> "" then parts.Push(item.year)
    if item.problem <> "" then parts.Push("Won't play on this " + DeviceWord())
    m.focusTitle.text = parts.Join("   ·   ")
end sub

sub onSelected()
    content = m.grid.content
    if content = invalid then return
    item = content.GetChild(m.grid.itemSelected)
    if item = invalid then return
    Sound("select")
    m.top.action = { name: "openDetails", item: item }
end sub

sub onTakeFocus()
    if m.zone = "search" or m.grid.content = invalid then
        focusSearch()
    else
        focusGrid()
    end if
end sub

' --- Search --------------------------------------------------------------------------

sub focusSearch()
    m.zone = "search"
    m.keys.SetFocus(true)
    styleSearchButton()
end sub

sub focusGrid()
    if m.grid.content = invalid then return
    m.zone = "grid"
    m.grid.SetFocus(true)
    styleSearchButton()
end sub

sub styleSearchButton()
    if m.query = "" then
        m.searchLabel.text = "Search this category"
    else
        shown = m.query
        if Len(shown) > 16 then shown = Left(shown, 15) + "…"
        m.searchLabel.text = "“" + shown + "”  ·  Change"
    end if
    if m.zone = "search" then
        m.searchBg.blendColor = "0xC9B8FFFF"
        m.searchLabel.color = "0x151028FF"
    else
        m.searchBg.blendColor = "0x30275AFF"
        m.searchLabel.color = "0xD8CEF5FF"
    end if
end sub

' Roku's keyboard over the page; the grid behind it narrows as you type.
sub openKeyboard()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "Search " + m.heading.text
    dialog.text = m.query
    dialog.buttons = ["Done", "Clear"]
    dialog.ObserveField("text", "onTyping")
    dialog.ObserveField("buttonSelected", "onKeyboardButton")
    dialog.ObserveField("wasClosed", "onKeyboardClosed")
    m.top.GetScene().dialog = dialog
end sub

sub onTyping()
    m.debounce.control = "stop"
    m.debounce.control = "start"
end sub

sub onDebounce()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    setQuery(dialog.text)
end sub

sub onKeyboardButton()
    dialog = m.top.GetScene().dialog
    if dialog = invalid then return
    m.debounce.control = "stop"
    if dialog.buttonSelected = 1 then
        setQuery("")
    else
        setQuery(dialog.text)
    end if
    dialog.close = true
end sub

sub onKeyboardClosed()
    if m.grid.content <> invalid then
        focusGrid()
    else
        focusSearch()
    end if
end sub

sub setQuery(text as String)
    query = text.Trim()
    if query = m.query then return
    m.query = query
    styleSearchButton()
    ask()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    ' * opens the search from anywhere on the page.
    if key = "options" then
        openKeyboard()
        return true
    end if
    if m.zone = "search" then
        if key = "OK" then
            Sound("select")
            openKeyboard()
        else if key = "down" then
            if m.grid.content <> invalid then Sound("move")
            focusGrid()
        else if key = "back" then
            if m.query = "" then return false
            setQuery("")
        end if
        return true
    end if
    ' Keys the grid didn't use: Up from its top row, and Back.
    if key = "up" then
        Sound("move")
        focusSearch()
        return true
    end if
    if key = "back" and m.query <> "" then
        setQuery("")
        return true
    end if
    return false
end function
