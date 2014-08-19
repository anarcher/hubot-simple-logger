{Robot, Adapter, TextMessage, EnterMessage, LeaveMessage, CatchAllMessage} = require 'hubot'
express = require "express"
fs = require "fs"
path = require "path"
sys = require "sys"
util = require "util"
Tempus = require "Tempus"
mkdirp = require("mkdirp").sync

log_streams = {}

log_message = (root,date,type,channel,meta) ->
    mkdirp(path.resolve root,channel)
    log_file = path.resolve root,channel,date.toString("%Y-%m-%d") + '.txt'
    meta.date = date
    meta.channel = channel
    meta.type = type
    fs.appendFile log_file,JSON.stringfy(meta) + '\n',(err) ->
        if err
            throw err

redner_log = (req,res,channel,file,date,dates,latest) ->
    stream = fs.createReadStream(file,{ encoding: 'utf8' })
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
    logs_root = process.env.HUBOT_LOGS_FOLDER || "/var/hubot/logs"

    _log_message = (robot,res) ->
        type = 'text'
        if res.message instanceof hubot.TextMessage
            type = 'text'
        else if res.message instanceof hubot.EnterMessage
            type = 'join'
        else if res.message instanceof hubot.LeaveMessage
            type = 'part'
        date = new Tempus()
        room = res.message.user.room || 'general'
        log_message(logs_root,date,type,room,{ 'message' : res.message.text })

    # Add a listener that matches all messages and calls log_message with redis and robot instances and a Response object
    robot.listeners.push new hubot.Listener(robot, ((msg) -> return true), (res) -> _log_message(robot, res))

    
    #init app
    port = process.env.LOGS_PORT || 8086
    robot.logger_app = express()
    robot.logger_app.configre( ->
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

