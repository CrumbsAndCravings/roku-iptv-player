sub init()
    m.heading = m.top.FindNode("heading")
    m.count = m.top.FindNode("count")
    m.grid = m.top.FindNode("grid")
    m.message = m.top.FindNode("message")
    m.focusTitle = m.top.FindNode("focusTitle")
    m.focusMeta = m.top.FindNode("focusMeta")
    m.heading.font = MakeFont("Fredoka-SemiBold", 32)
    m.count.font = MakeFont("Nunito-SemiBold", 16)
    m.message.font = MakeFont("Nunito-SemiBold", 22)
    m.focusTitle.font = MakeFont("Fredoka-Medium", 22)
    m.focusMeta.font = MakeFont("Nunito-SemiBold", 16)

    m.key = ""
    m.loading = false
    m.lastAsked = CreateObject("roTimespan")
    m.task = LibraryTask()
    m.task.ObserveFieldScoped("browsed", "onBrowsed")
    m.task.ObserveFieldScoped("status", "onLibraryStatus")
    m.grid.ObserveField("itemSelected", "onSelected")
    m.grid.ObserveField("itemFocused", "onFocused")
end sub

sub onCategory()
    category = m.top.category
    m.heading.text = FieldStr(category, "title")
    m.key = FieldStr(category, "kind") + ":" + FieldStr(category, "categoryId")
    m.count.text = ""
    m.message.text = "Gathering titles…"
    ask()
end sub

' Asks the library worker for this category's titles (answered from the Roku's copy).
sub ask()
    m.lastAsked.Mark()
    category = m.top.category
    m.task.browse = { kind: FieldStr(category, "kind"), categoryId: FieldStr(category, "categoryId") }
end sub

sub onBrowsed()
    list = m.task.browsed
    if list = invalid or not list.HasField("forKey") or list.forKey <> m.key then return
    m.loading = list.loading = true
    total = ToInt(list.total)
    shown = list.GetChildCount()
    if shown = 0 then
        m.grid.content = invalid
        m.focusTitle.text = ""
        m.focusMeta.text = ""
        if m.loading then
            m.message.text = "Your library is still loading. This category's titles will appear here as they arrive."
        else
            m.message.text = "Nothing in this category yet."
        end if
        m.count.text = ""
        return
    end if
    m.message.text = ""
    focused = m.grid.itemFocused
    m.grid.content = list
    if focused > 0 and focused < shown then m.grid.jumpToItem = focused
    text = Commas(total) + " titles, newest first"
    if shown < total then text = "The newest " + Commas(shown) + " of " + Commas(total) + " titles"
    if m.loading then text = text + ". Your library is still loading, so more may appear."
    m.count.text = text
    onFocused()
end sub

' While the library is still arriving, refresh the page now and then.
sub onLibraryStatus()
    if m.loading and m.lastAsked.TotalSeconds() >= 5 then ask()
end sub

sub onFocused()
    content = m.grid.content
    if content = invalid then return
    item = content.GetChild(m.grid.itemFocused)
    if item = invalid then return
    m.focusTitle.text = item.title
    meta = item.year
    if item.problem <> "" then
        if meta <> "" then meta = meta + "   ·   "
        meta = meta + "Won't play on this " + DeviceWord()
    end if
    m.focusMeta.text = meta
end sub

sub onSelected()
    content = m.grid.content
    if content = invalid then return
    item = content.GetChild(m.grid.itemSelected)
    if item = invalid then return
    m.top.action = { name: "openDetails", item: item }
end sub

sub onTakeFocus()
    m.grid.SetFocus(true)
end sub
