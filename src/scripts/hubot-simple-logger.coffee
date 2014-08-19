{Robot, Adapter, TextMessage, EnterMessage, LeaveMessage, CatchAllMessage} = require 'hubot'
express = require "express"
fs = require "fs"
path = require "path"
sys = require "sys"
util = require "util"
Tempus = require "Tempus"
mkdirp = require("mkdirp").sync


