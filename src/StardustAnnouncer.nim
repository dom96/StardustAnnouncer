import asyncdispatch, times, options, logging, strformat, random, sequtils, sugar

import dimscord

import metrics

type
  State = ref object
    lastActive: seq[string]
    lastAnnouncement: float

const announcementChannelId = "456504845642235914"
const emotes = [
  ":2716057:", ":VapeNaysh:", ":USA:", ":SpoopyBones:", ":SixTwoSix:",
  ":PrideStar:", ":PogMaThoin:", ":Patrick:", ":OhMyGlob:", ":Ninja:",
  ":BroFist:", ":BaconPancakes:"
]
let botToken = readFile("stardust-announcer.bot-token")

let discord = newDiscordClient(botToken)

# Handle event for on_ready.
proc onReady(s: Shard, r: Ready) {.event(discord).} =
  echo "Ready as " & $r.user

# Handle event for message_create.
proc messageCreate(s: Shard, m: Message) {.event(discord).} =
  if m.author.bot: return
  if m.content == "!ping": # If message content is "!ping".
    discard await discord.api.sendMessage(m.channel_id, "Pong!")
    echo("Got pong from <#", m.channel_id, ">")

proc sendAnnouncement(
  state: State, servers: seq[string]
) {.async.} =
  if epochTime() - state.lastAnnouncement < 1800:
    # Reset last announced servers after 30 minutes of no announcements.
    state.lastActive = @[]
  if servers.len == 0:
    return
  if state.lastActive == servers:
    info("Not sending due to last active")
    return
  if epochTime() - state.lastAnnouncement < 300: # 5 minutes
    info("Not sending due to last announcement")
    return
  # Create message.
  for server in servers:
    let uri = getPlayUrl(servers[0])
    let name = getServerName(servers[0])
    let emote = sample(emotes)
    let msg = fmt"A few players are currently active in `{name}`." &
      "Why not join them for a game?\n\n" &
      fmt"Join via this link: <{uri}> {emote}"
    discard await discord.api.sendMessage(announcementChannelId, msg)

  state.lastAnnouncement = epochTime()
  state.lastActive = servers

proc runMetricsLoop() {.async.} =
  var state = State(lastAnnouncement: epochTime())
  while true:
    await sleepAsync(5000)
    try:
      let metrics = await getMetrics()
      debug("Got metrics: ", metrics)
      await sendAnnouncement(state, getActiveServers(metrics))
    except:
      error("Unable to download metrics: ", getCurrentExceptionMsg())

randomize()
var consoleLog = newConsoleLogger()
addHandler(consoleLog)
# Set up metrics polling.
let runMetricsLoopFut = runMetricsLoop()
runMetricsLoopFut.callback =
  proc (fut: Future[void]) =
    error("Concurrent future failed with ", fut.error.msg)
# Connect to Discord and run the bot.
waitFor discord.startSession()