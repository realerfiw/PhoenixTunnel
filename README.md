# Phoenix Tunnel

Phoenix Tunnel core for Linux.

Phoenix Tunnel creates an authenticated connection between two Linux hosts and
forwards selected services through that connection. One endpoint runs as the
server/listener and the other as the client/connector; each forwarded service
is defined by a static mapping from a listening address to a target address.

## Features

- TCP forwarding over an authenticated HTTP/2 and TLS 1.3 carrier.
- UDP forwarding over HTTP/2 or HTTP/3 and QUIC DATAGRAM.
- `auto` carrier selection, with explicit `h2` and `h3` modes when needed.
- Multiple independent mappings and separate tunnel processes.
- Session recovery for eligible TCP flows after a short carrier interruption.

Phoenix is designed for configured private mappings, not as an open proxy.

## Download

Download the latest build from [Releases](https://github.com/realerfiw/PhoenixTunnel/releases).

- `phoenix-linux-amd64` — x86-64
- `phoenix-linux-arm64` — ARM64

Download `SHA256SUMS` and the matching license files with the core.

## Install the core

On a supported Linux host, run:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/realerfiw/PhoenixTunnel/main/install.sh)
```

The installer detects the host architecture, verifies the downloaded core with
`SHA256SUMS`, and installs the core as `/opt/phoenix-tunnel/phoenix`. A copy of
the installer is saved as `/opt/phoenix-tunnel/install.sh` for later reuse. It
does not create, remove, start, stop, or restart any tunnel service.
