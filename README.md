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
is named automatically by role, carrier and tunnel port (for example,
`iran-auto-9090`), with a numeric suffix when needed. Each has its own
configuration. Manage tunnels provides restart, stop,
remove, logs, details, validation and status actions.
Its main screen lists installed tunnels with their local service status
(`UP`, `DOWN`, `INCOMPLETE` or `UNKNOWN`). Back and Exit use `0`.

Files are kept in:

```text
/root/install.sh
/opt/phoenix-tunnel/
  core/phoenix
  configs/
```

The core download is checked against a pinned SHA-256. On Ubuntu/Debian,
**Install / update core** also installs missing dependencies such as `jq`,
`openssl`, `curl` and CA certificates through APT. Other distributions need
the required tools installed manually.

**Remove core** deletes only the core, its license files and empty Phoenix
directories, after all standalone tunnels have been removed. System packages,
the saved menu and non-empty configuration directories are kept.

Keep connection codes private. The destination service must be running on
Kharej, and the selected transport and public ports must be allowed by your
firewall. Existing installations at other paths are left unchanged.

## Logs

New tunnels use a dedicated `phoenix-standalone` journal namespace. For existing
standalone tunnels, choose **Restart tunnel** once to apply the policy; this
briefly interrupts that tunnel, without replacing its configuration.

All standalone Phoenix tunnels on one host share a 100 MiB persistent journal
budget and three-day retention (20 MiB for runtime storage). Rotation removes
old entries automatically. Active files and journal overhead mean this is not
an exact byte-level quota or an exact deletion deadline. System-wide journals
and old entries in the default journal are not purged or capped by this policy.
Namespace support requires systemd 245 or newer; unsupported/custom logging
configurations cause an explicit error before restarting the selected tunnel.

**View logs** displays all retained entries; **View live logs** displays the same
history and follows new entries. Both include older default-journal entries for
the selected service. UTC dates, levels, messages and all application fields
are formatted without event allowlists, priority filters or line-count limits.
Events use compact single-line headings with details wrapped underneath and no
blank rows between records. The UTC date appears when it changes; redundant
application timestamp/level fields are not printed twice. Unknown events,
plain text and nested metrics are retained, with nested fields expanded into
readable paths instead of a long JSON blob.
Recognized structured secret fields are masked, and terminal control characters
are sanitized; stored journal records are not rewritten. Do not share logs
publicly without reviewing them for sensitive data.

No duplicate text-log file is created. The dedicated retention policy remains
after core removal so retained logs continue to age out; OS packages and other
services are not changed. Records already expired, never emitted by the core,
or previously suppressed cannot be recovered. Service-level rate suppression
is disabled for migrated/new tunnels; disk/time retention still applies.
