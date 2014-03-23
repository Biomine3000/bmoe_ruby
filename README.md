bmoe_ruby
=========

Biomine Object Exchange implemented in Ruby.

Required gems: `json`, `eventmachine`

Usage:

    ./run_bmoe_server [port|ip:port] [linked_server:port ...]
    ./run_bmoe_client ip:port

For example:

    # Listen on local port 7890 and link with other.server.net on port 61016:
    ./run_bmoe_server 7890 other.server.net:61016

Server features:

* incoming client connections
* incoming and outgoing server-to-server connections
* automatically reconnect outgoing server links
* `subscriptions` can be either a single array or nested arrays (arbitrary depth)
* `to` as either a single `routing-id` or array of multiple ids
* does not route to nodes already listed in `route`
* adds the routing id of other routing servers to `route`
* generates object ids and routing ids as UUIDs (subject to change)
* sends `routing/subscribe/notification` and `routing/disconnect`
* sends `routing/announcement/neighbors` periodically (only if routes or recipients are believed to have changed)
* sends `ping` periodically to servers if idle, and to clients who are idle
* responds to `ping` intended for self, routes `ping` intended for others
* supports _local_ clients with a duplicate `routing-id` – all of them will
  get the Object targeted to that id (subject to that connection's 
  subscriptions)

Client features:

* verbose debug output
* send `text/plain` messages from terminal with `message` nature
* use the command `/subscribe rule1 rule2 …` to establish subscriptions (e.g.,
  `/subscribe *`)
* prefix a line or command with `#nature1 #nature2 …` to add natures (works
  with plain text and all object-sending commands except `/ping` and
  `/subscribe`)
* send arbitrary objects with `/json {…}payload`; payload can be plain text
  or base64-encoded arbitrary data prefixed with `base64:`
* send files with `/file filename` (mime-type autodetected)
* send text in alternative encodings with `/encode encoding message` or `/enc
  message` (the latter chooses randomly)
* send pings with `/ping` or `/ping target1 target2 …`
* show ping time when receiving `pong` in response to `/ping`
* send `pong` in reply to `ping`
* `/quit`

