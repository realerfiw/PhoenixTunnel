# Phoenix Tunnel

Linux binary distribution for Phoenix Tunnel. Download prebuilt cores from Releases.
This repository does not contain the Phoenix Tunnel source code or tunnel-manager script.

## Development release

`v0.1.0-dev.69` is a pre-release for testing, not a stable production release.
Choose `phoenix-linux-amd64` for x86-64 or `phoenix-linux-arm64` for AArch64.
Download the matching third-party license inventory, `LICENSE`, and `SHA256SUMS` as well.

After verifying the downloaded binary against its entry in SHA256SUMS:

```sh
chmod 755 phoenix-linux-amd64
./phoenix-linux-amd64 version
```

For ARM64 use `phoenix-linux-arm64` instead. The raw binary does not install or configure a service.

Release assets include the Phoenix MIT license and dependency license texts.
Builds are currently unsigned and report source commit `unknown`.
The repository tag identifies distribution documentation, not the core source revision.
