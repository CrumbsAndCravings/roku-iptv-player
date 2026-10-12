' Keeps a whole film's pictures on the TV (see PreviewTask.xml). Runs until its source is
' emptied, then deletes them. tmp:/ counts towards the app's memory: a two-hour film's
' pictures come to about 7 MB, and they go when the film's stream does.

sub init()
    m.top.functionName = "work"
end sub

sub work()
    port = CreateObject("roMessagePort")
    m.top.ObserveField("source", port)
    m.top.ObserveField("poke", port)
    m.fs = CreateObject("roFileSystem")
    clock = CreateObject("roTimespan")
    m.dir = ""
    begin(m.top.source)
    nextLook = 0
    lastLook = -100000
    while m.dir <> ""
        msg = Wait(500, port)
        if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "source" then
                begin(msg.GetData())
                nextLook = 0
            else if msg.GetField() = "poke" and clock.TotalMilliseconds() - lastLook > 2000 then
                ' Choosing a jump: whatever the helper has made since, now.
                nextLook = 0
            end if
        end if
        if m.dir <> "" and clock.TotalMilliseconds() >= nextLook then
            look()
            lastLook = clock.TotalMilliseconds()
            ' The helper converts a few times faster than the film plays, so a look
            ' every 8 seconds brings a handful of pictures each time.
            nextLook = lastLook + 8000
        end if
    end while
end sub

' A new film (or none): this task's pictures for the last one go. Only its own folder:
' the next film's task may be filling one of its own by now.
sub begin(source as Dynamic)
    if m.dir <> "" then clear(m.dir)
    m.dir = ""
    m.seq = 0
    m.config = { url: FieldStr(source, "url") }
    m.previews = { list: FieldStr(source, "list"), bundle: FieldStr(source, "bundle") }
    m.every = ToInt(Field(source, "every"))
    dir = FieldStr(source, "dir")
    if dir = "" or m.config.url = "" or m.previews.list = "" or m.previews.bundle = "" or m.every <= 0 then return
    ' Folders an earlier task left behind (it ended before it could empty its own).
    m.fs.CreateDirectory("tmp:/pv")
    for each name in listing("tmp:/pv")
        if "tmp:/pv/" + name <> dir then clear("tmp:/pv/" + name)
    end for
    m.fs.CreateDirectory(dir)
    m.dir = dir
end sub

' Asks what's new, fetches those pictures in one file and splits it, one JPEG each
' (<dir>/<n>.jpg); then tells the screen which arrived and what the helper said.
sub look()
    text = fetchText(HelperPicturesUrl(m.config, m.previews, m.seq), 6000)
    data = invalid
    if text <> invalid then data = ParseJson(text)
    if not IsAA(data) then return
    news = ParseHelperPictures(data)
    if news.seq > m.seq and news.count > 0 then
        file = m.dir + "/in.bif"
        if fetchFile(HelperBundleUrl(m.config, m.previews, m.seq, news.seq), file, 30000) then
            added = split(file)
            if added <> invalid then
                m.seq = news.seq
                if added.Count() > 0 then m.top.added = added
            end if
        end if
        m.fs.Delete(file)
    else if news.seq < m.seq then
        ' The helper started the session again: all of its pictures are new.
        m.seq = 0
    end if
    m.top.news = news
end sub

' The pictures' numbers, as strings, once each is its own file; invalid for a file that
' isn't a BIF.
function split(file as String) as Dynamic
    bytes = CreateObject("roByteArray")
    if not bytes.ReadFile(file) then return invalid
    index = ReadBifIndex(bytes)
    if index = invalid then return invalid
    added = []
    for each picture in index
        key = PictureNumber(picture.seconds, m.every).ToStr()
        if bytes.WriteFile(m.dir + "/" + key + ".jpg", picture.start, picture.length) then added.Push(key)
    end for
    return added
end function

function fetchText(url as String, timeoutMs as Integer) as Dynamic
    port = CreateObject("roMessagePort")
    http = request(url, port)
    if not http.AsyncGetToString() then return invalid
    msg = Wait(timeoutMs, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return invalid
    end if
    if msg.GetResponseCode() <> 200 then return invalid
    return msg.GetString()
end function

function fetchFile(url as String, file as String, timeoutMs as Integer) as Boolean
    port = CreateObject("roMessagePort")
    http = request(url, port)
    if not http.AsyncGetToFile(file) then return false
    msg = Wait(timeoutMs, port)
    if type(msg) <> "roUrlEvent" then
        http.AsyncCancel()
        return false
    end if
    return msg.GetResponseCode() = 200
end function

function request(url as String, port as Object) as Object
    http = CreateObject("roUrlTransfer")
    http.SetMessagePort(port)
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    return http
end function

function listing(dir as String) as Object
    names = m.fs.GetDirectoryListing(dir)
    if names = invalid then return []
    return names
end function

sub clear(dir as String)
    for each name in listing(dir)
        m.fs.Delete(dir + "/" + name)
    end for
    m.fs.Delete(dir)
end sub
