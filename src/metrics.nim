import strutils, httpclient, parseutils, tables, asyncdispatch, uri

type
  Metrics* = object
    playerCounts, botCounts: Table[string, int]

proc parseMetrics(metrics: string): Metrics =
  for line in metrics.splitLines():
    if line.len == 0: continue
    if line[0] == '#': continue
    const playerCountsPrefix = "loadbalancer_server_player_count{uri="
    const botCountsPrefix = "loadbalancer_server_bot_count{uri="
    if line.startsWith(playerCountsPrefix):
      let uri = line.captureBetween('"', start = playerCountsPrefix.len)
      result.playerCounts[uri] = parseFloat(line.split("} ")[1]).int
    if line.startsWith(botCountsPrefix):
      let uri = line.captureBetween('"', start = botCountsPrefix.len)
      result.botCounts[uri] = parseFloat(line.split("} ")[1]).int

proc getMetrics*(): Future[Metrics] {.async.} =
  var client = newAsyncHttpClient()
  defer: client.close()
  let metrics = await client.getContent("https://stardust.dev/route/metrics")
  return parseMetrics(metrics)

proc getPlayUrl*(uri: string): string =
  var u = parseUri(uri)
  u.scheme = ""
  result = "https://stardust.dev/play/?ServerURI=" & $u
  if result.endsWith("/"):
    result = result[0 .. ^2]
  if result.endsWith("/game"):
    result = result[0 .. ^6]

proc getServerName*(uri: string): string =
  let u = parseUri(uri)
  return u.hostname[0 .. 3]

proc getActiveServers*(metrics: Metrics): seq[string] =
  for key, val in metrics.playerCounts:
    if val - metrics.botCounts.getOrDefault(key) > 0:
      result.add(key)

proc `$`*(metric: Metrics): string =
  return system.`$`(metric)

when isMainModule:
  let metrics = """
# HELP loadbalancer_server_player_count Number of players on each server.
# TYPE loadbalancer_server_player_count gauge
loadbalancer_server_player_count{uri="wss://fra1.stardust.dev/game2/"} 7.0
loadbalancer_server_player_count{uri="wss://nyc1.stardust.dev/game2/"} 4.0
loadbalancer_server_player_count 0.0
# HELP loadbalancer_server_bot_count Number of bots on each server.
# TYPE loadbalancer_server_bot_count gauge
loadbalancer_server_bot_count{uri="wss://fra1.stardust.dev/game2/"} 7.0
loadbalancer_server_bot_count{uri="wss://nyc1.stardust.dev/game2/"} 3.0
loadbalancer_server_bot_count 0.0
  """
  let parsed = parseMetrics(metrics)
  doAssert parsed.playerCounts["wss://fra1.stardust.dev/game2/"] == 7
  doAssert parsed.playerCounts["wss://nyc1.stardust.dev/game2/"] == 4
  doAssert parsed.botCounts["wss://fra1.stardust.dev/game2/"] == 7
  doAssert parsed.botCounts["wss://nyc1.stardust.dev/game2/"] == 3
  echo parsed

  doAssert(getPlayUrl("wss://nyc1.stardust.dev/game2/") == "https://stardust.dev/play/?ServerURI=nyc1.stardust.dev/game2")
  doAssert(getPlayUrl("wss://nyc1.stardust.dev/game/") == "https://stardust.dev/play/?ServerURI=nyc1.stardust.dev")

  doAssert(getServerName("wss://nyc1.stardust.dev/game2/") == "nyc1")

  doAssert(getActiveServers(parsed) == @["wss://nyc1.stardust.dev/game2/"])
  echo "All Good"