{Robot, Adapter, Listener, TextMessage, EnterMessage, LeaveMessage,TopicMessage, CatchAllMessage} = require 'hubot'
express = require "express"
fs = require "fs"
path = require "path"
sys = require "sys"
util = require "util"
Tempus = require "tempus"
mkdirp = require("mkdirp").sync
Autolinker = require("autolinker")
Convert = require('ansi-to-html')

log_streams = {}

log_message = (root,date,type,channel,meta) ->
    mkdirp(path.resolve root,channel)
    log_file = path.resolve root,channel,date.toString("%Y-%m-%d") + '.txt'
    meta.date = date
    meta.channel = channel
    meta.type = type
    fs.appendFile log_file,JSON.stringify(meta) + '\n',(err) ->
        if err
            throw err

escapeHtml = (text) ->
  map =
    "&": "&amp;"
    "<": "&lt;"
    ">": "&gt;"
    "\"": "&quot;"
    "'": "&#039;"

  text.replace /[&<>"']/g, (m) ->
    map[m]


render_log = (req,res,channel,file,date,dates,latest) ->
    stream = fs.createReadStream(file,{ encoding: 'utf8' })
    convert = new Convert({newLine: true, fg: 'black', bg: 'white'})
    buffer = ''
    events = []
    pad2 = (n) ->
        return '0' + n if n < 10
        return '' +n

    parse_events = (last) ->
        rows = buffer.split('\n')
        if last
            until_row = rows.length + 1
        else
            until_row = rows.length

        i = 0

        while i < until_row
            json = rows[i]
            i++
            continue unless json?

            event = null
            try
                event = JSON.parse(json)
            catch e
                null

            continue unless event?

            event.date = new Tempus(event.date)
            event.time = event.date.toString("%H:%M:%S")
            event.timestamp = event.date.toString("%H:%M:%S:%L")

            if event.message?
                try
                    event.message = escapeHtml  event.message
                catch error
                    # Do not process event.messages that aren't text strings,
                    # just log them. Alternatively, one could call:
                    # event.message = escapeHtml JSON.stringify(event.message)
                    debugmsg = JSON.stringify event.message
                    console.log "message is not text: #{debugmsg}"
                    continue
                event.message = event.message.replace(/\r\n|\r|\n/g, "<br/>")
                event.message = convert.toHtml event.message

            continue unless event.date?

            events.push(event)

        if !last
            buffer = rows[rows.length - 1] || ''
        else
            buffer = ''

    stream.on 'data',(data) ->
        buffer += data
        parse_events(false)

    stream.on 'end',() ->
        parse_events(true)
        indexPosition = dates.indexOf(date)
        res.render('log',{
            Autolinker: Autolinker,
            events: events,
            channel: channel,
            page : date,
            previous: dates[indexPosition - 1],
            next: dates[indexPosition + 1],
            isLatest: latest
        })
    stream.on 'error',(err) ->
        stream.destory()
        res.send(''+err,404)

escapeHTML = (str) ->
    str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

module.exports = (robot) ->
    logs_root = process.env.HUBOT_LOGS_FOLDER || "/var/log/hubot/"

    _log_message = (res) ->
        type = 'text'
        if res.message instanceof TextMessage
            type = 'text'
        else if res.message instanceof EnterMessage
            type = 'join'
        else if res.message instanceof LeaveMessage
            type = 'part'
        else if res.message instanceof TopicMessage
            type = 'topic'
        else
            return
        date = new Tempus()
        room = res.message.user.room || 'general'
        user = res.message.user.name || res.message.user.id || 'unknown'
        log_message(logs_root,date,type,room,{ 'message' : res.message.text , 'user' : user })

    # Add a listener that matches all messages and calls log_message with redis and robot instances and a Response object
    robot.listeners.push new Listener(robot, ((msg) -> return true), (res) -> _log_message(res))

    #Override send methods in the Response protyoep so taht we can log hubot's replies
    #This is kind of evil,but there doesn't appear to be a better way
    log_response = (room,strings...) ->
        for string in strings
            date = new Tempus()
            log_message(logs_root,date,'text',room,{ 'message' : string , 'user' : robot.name })

    response_orig =
        send: robot.Response.prototype.send
        reply: robot.Response.prototype.reply

    robot.Response.prototype.send = (strings...) ->

        if not @message.room == null
            log_response @message.room, strings...
        response_orig.send.call @,strings...

    robot.Response.prototype.reply = (strings...) ->
        log_response @message.room, strings...
        response_orig.reply.call @,strings...

    #init app
    port = process.env.LOGS_PORT || 8086
    robot.logger_app = express()
    robot.logger_app.configure( ->
        robot.logger_app.set 'views', __dirname + '/../views'
        robot.logger_app.set 'view options', { layout: true }
        robot.logger_app.set 'view engine', 'jade'
        robot.logger_app.use express.bodyParser()
        robot.logger_app.use express.methodOverride()
        if process.env.HUBOT_LOGGER_HTTP_LOGIN? && process.env.HUBOT_LOGGER_HTTP_PASSWORD?
            robot.logger_app.use express.basicAuth process.env.HUBOT_LOGGER_HTTP_LOGIN, process.env.HUBOT_LOGGER_HTTP_PASSWORD
        robot.logger_app.use robot.logger_app.router
    )

    robot.logger_app.get "/logs", (req, res) ->
        res.redirect "/logs/channels"

    robot.logger_app.get "/logs/channels", (req, res) ->
      files = fs.readdirSync(logs_root)
      res.render('channels.jade', {
        channels: files,
        title: 'channel index'
      })

    robot.logger_app.get "/logs/:channel/index", (req, res) ->
      channel = req.params.channel
      fs.readdir logs_root + "/" + channel, (err, filenames) ->
        if err
          res.send '' + err, 404

        dates = filenames.map (filename) ->
          filename.replace(/\..*$/, '')
        dates.sort().reverse()

        res.render('index.jade', {
          dates: dates,
          channel: channel,
          page: 'index'
        })

    robot.logger_app.get "/logs/:channel/latest", (req, res) ->
      channel = req.params.channel
      fs.readdir logs_root + "/" + channel, (err, filenames) ->
        if err
          res.send '' + err, 404

        dates = filenames.map (filename) ->
          filename.replace(/\..*$/, '')
        dates.sort()

        date = dates[dates.length - 1] 
        render_log(req, res, channel, path.resolve(logs_root, channel, date + ".txt"), date, dates, true)

    robot.logger_app.get "/logs/:channel/:date", (req, res) ->
      channel = req.params.channel
      fs.readdir logs_root + "/" + channel, (err, filenames) ->
        if err
          res.send '' + err, 404

        dates = filenames.map (filename) ->
          filename.replace(/\..*$/, '')
        dates.sort()

        date = req.params.date
        render_log(req, res, channel, path.resolve(logs_root, channel, date + ".txt"), date, dates, true)

    robot.logger_app.listen(port)
