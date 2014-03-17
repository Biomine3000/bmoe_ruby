bmoe_ruby
=========

Biomine Object Exchange implemented in Ruby.

Required gems: `json`, `EventMachine`

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
* generates object ids and routing ids as UUIDs (subject to change)
* sends `routing/subscribe/notification` and `routing/disconnect`
* sends `routing/announcement/neighbors` periodically (only if routing or recipients are believed to have changed)
