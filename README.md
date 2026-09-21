# Phoenix Tunnel

Reverse tunneling for TCP and UDP services between Linux servers.

Phoenix connects two servers through an authenticated, encrypted tunnel and
forwards selected ports to services on the remote side. It is designed for
explicit port mappings: you choose which ports to expose and where their
traffic should go.

## How it works

The **Kharej** server initiates the tunnel connection to **Iran**. Users connect
to a forwarded port on Iran, and Phoenix carries that traffic to the configured
destination on Kharej. Responses travel back through the tunnel.

```text
User → Iran public port → Phoenix tunnel → Kharej destination service
```

- **Iran — server/listener:** accepts the tunnel connection and exposes the
  forwarded ports.
- **Kharej — client/connector:** connects to Iran and reaches the destination
  services, either locally or at a configured reachable address.

Phoenix transports your service traffic; it does not replace the destination
application. That application must be running on the configured target port.

## Capabilities

- **TCP forwarding** over HTTP/2 with TLS 1.3.
- **UDP forwarding** over HTTP/2 or HTTP/3 with QUIC DATAGRAM.
- **Automatic transport selection**, or explicit `h2` / `h3` configuration.
- **Multiple port mappings** in one tunnel and multiple independent tunnels
  on the same host.
- **Authenticated peers** with TLS certificate verification.
- **Session recovery** for eligible TCP connections after short transport
  interruptions, within the configured recovery limits.

Recovery is not a guarantee of uninterrupted connections: prolonged outages
or a peer process restart can still break active flows.

## Transports

| Mode | Forwarded traffic | Transport |
| --- | --- | --- |
| `auto` | TCP and UDP | TCP uses H2; UDP can use H3 with H2 fallback |
| `h2` | TCP and UDP | HTTP/2 over TCP and TLS |
| `h3` | UDP only | HTTP/3 over QUIC |

Choose `auto` for the general setup, or select a specific transport when the
network requires it. H3 needs UDP connectivity between the two servers.

## Quick start

On both servers, run as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/realerfiw/PhoenixTunnel/main/install.sh)
```

The command opens the installation menu.

1. Select **Install / update core** on both servers.
2. On Iran, select **Manage tunnels → Create tunnel → Iran** and enter the
   public address, tunnel port and service port mappings.
3. Copy the private connection code.
4. On Kharej, select **Manage tunnels → Create tunnel → Kharej** and paste it.

New tunnels start automatically and are enabled after reboot. Keep the
connection code private, use matching core versions on both sides, and allow
the required tunnel and public service ports through your firewall.

The menu requires Linux, Bash, curl and systemd 245 or newer. Ubuntu/Debian
dependency installation is handled by **Install / update core**.

## Linux builds

Prebuilt cores are available in [Releases](https://github.com/realerfiw/PhoenixTunnel/releases):

- `phoenix-linux-amd64` — x86-64 servers
- `phoenix-linux-arm64` — ARM64 servers

For manual downloads, verify the core against `SHA256SUMS` and keep the
accompanying license notices. Builds marked **Pre-release** are development
versions for testing.
