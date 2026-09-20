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

## Setup

Run as root on a Linux host with Bash and systemd:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/realerfiw/PhoenixTunnel/main/install.sh)
```

The command opens the Phoenix menu; it does not automatically install the core
or change any tunnel. The menu is saved as `/root/install.sh` and can be reopened
with `bash /root/install.sh`.

1. Choose **Install / update core** on both hosts.
2. On Iran, choose **Manage tunnels > Create tunnel > Iran**. Enter the tunnel
   address, transport and forwarded ports.
3. Copy the private connection code shown at the end.
4. On Kharej, choose **Create tunnel > Kharej** and paste the code.

Creating a tunnel starts its service and enables it after reboot. Each tunnel
has its own name and configuration. Manage tunnels provides restart, stop,
remove, logs, details, validation and status actions.

Files are kept in:

```text
/root/install.sh
/opt/phoenix-tunnel/
  core/phoenix
  configs/
```

The core download is checked against a pinned SHA-256. Required tools are
`curl`, `sha256sum`, `flock`, `jq`, `openssl` and GNU coreutils.
The menu reports missing tools; it does not install system packages automatically.

Keep connection codes private. The destination service must be running on
Kharej, and the selected transport and public ports must be allowed by your
firewall. Existing installations at other paths are left unchanged.
