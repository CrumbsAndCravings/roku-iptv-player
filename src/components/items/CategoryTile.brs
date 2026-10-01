sub init()
    m.card = m.top.FindNode("card")
    m.ring = m.top.FindNode("ring")
    m.base = m.top.FindNode("base")
    m.name = m.top.FindNode("name")
    m.caption = m.top.FindNode("caption")
    m.name.font = MakeFont("Fredoka-Medium", 20)
    m.caption.font = MakeFont("Nunito-ExtraBold", 14)
end sub

sub onContentChange()
    item = m.top.itemContent
    if item = invalid then return
    m.name.text = item.title
    m.caption.text = item.caption
end sub

sub onFocusChange()
    amount = 0.0
    if m.top.rowListHasFocus then amount = m.top.focusPercent * m.top.rowFocusPercent
    scale = 1 + 0.05 * amount
    m.card.scale = [scale, scale]
    m.ring.opacity = amount
    if amount > 0.5 then
        m.base.blendColor = "0x43377AFF"
    else
        m.base.blendColor = "0x30275AFF"
    end if
end sub
