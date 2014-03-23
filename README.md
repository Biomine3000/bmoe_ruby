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

* `subscriptions` can be either a single array or nested arrays (arbitrary depth)
* `to` as either a single `routing-id` or array of multiple ids
* does not route to nodes already listed in `route`
* can add all route destinations to `route` before routing (but
  currently disabled since other servers discard objects that have themselves in `route`)
* incoming and outgoing server-to-server connections
* automatically reconnect outgoing servers
* generates object ids and routing ids as UUIDs (subject to change)
* sends `routing/subscribe/notification` and `routing/disconnect`
* sends `routing/announcement/neighbors` periodically (only if routes or recipients are believed to have changed)
* sends `ping` periodically when idle
* responds to `ping`
* supports _local_ clients with a duplicate `routing-id` – all of them will
  get the Object targeted to that id (subject to that connection's 
  subscriptions)

Client features:

* verbose debug output
* send `text/plain` messages from terminal with `message` nature
* use the command `/subscribe *` to establish subscriptions
  (multiple subscription rules can be given as space-separated strings)
* prefix a line or command with `#nature1 #nature2 …` to add natures
* send arbitrary objects with `/json {…}payload`; payload can be plain text
  or base64-encoded arbitrary data prefixed with `base64:`
* send files with `/file filename` (mime-type autodetected)
* send alternative encodings with `/enc message` or `/encode encoding message`
* send pings with `/ping`
* `pong` in reply to `ping`
* `/quit`

