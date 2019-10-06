import httpclient, asyncdispatch, htmlparser, strformat
import sequtils, strutils, json, uri

import ".."/[types, parser, parserutils, formatters, query]
import utils, consts, media, search

proc getMedia(thread: Thread | Timeline; agent: string) {.async.} =
  await all(getVideos(thread, agent),
            getCards(thread, agent),
            getPolls(thread, agent))

proc finishTimeline*(json: JsonNode; query: Query; after, agent: string): Future[Timeline] {.async.} =
  result = getResult[Tweet](json, query, after)
  if json == nil: return

  if json["new_latent_count"].to(int) == 0: return
  if not json.hasKey("items_html"): return

  let html = parseHtml(json["items_html"].to(string))
  let thread = parseThread(html)

  await getMedia(thread, agent)
  result.content = thread.content

proc getTimeline*(username, after, agent: string): Future[Timeline] {.async.} =
  var params = toSeq({
    "include_available_features": "1",
    "include_entities": "1",
    "include_new_items_bar": "false",
    "reset_error_state": "false"
  })

  if after.len > 0:
    params.add {"max_position": after}

  let headers = genHeaders(agent, base / username, xml=true)
  let json = await fetchJson(base / (timelineUrl % username) ? params, headers)

  result = await finishTimeline(json, Query(), after, agent)

proc getProfileAndTimeline*(username, agent, after: string): Future[(Profile, Timeline)] {.async.} =
  var url = base / username
  if after.len > 0:
    url = url ? {"max_position": after}

  let
    headers = genHeaders(agent, base / username, auth=true)
    html = await fetchHtml(url, headers)
    timeline = parseTimeline(html.select("#timeline > .stream-container"), after)
    profile = parseTimelineProfile(html)

  await getMedia(timeline, agent)
  result = (profile, timeline)