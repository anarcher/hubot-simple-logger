# hubot simple logger

hubot-simple-logger is message file logger and simple web interface
- this is a fixed version which handles missing text in logs
- it also handles private messages on irc (msg hubot and get your reply in a private channel)

# Install & Use 

- If you want to use with docker, please consider this dockerfile https://github.com/nacyot/docker-hubot-simple-logger


## Environment Variables

    HUBOT_LOGS_PORT=8086                         # Logger web server Port
    HUBOT_LOGS_FOLDER=/data/logs                 # Directory for Log Data

