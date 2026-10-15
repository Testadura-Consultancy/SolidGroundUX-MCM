# Website publishing (SolidGroundUX Web Content Manager)

The `Publish website` action transfers the last generated **public** output directory to a destination defined by `config/publishing.cfg` in the selected website repository. You can edit this file with **Manage Config**. On first use, Publish creates an example file if one does not exist.

Configuration example:

```ini
[local-test]
type = local
path = /srv/www/testadura

[my-server]
type = rsync
host = web.example.org
user = publisher
port = 22
path = /var/www/testadura
identity_file = ~/.ssh/id_ed25519

[hostnet]
type = sftp
host = YOUR_SFTP_HOST
user = YOUR_USERNAME
port = 22
path = /ABSOLUTE/REMOTE/WEBROOT
```

The profile names are displayed for selection. All paths must be **absolute**, refer to a dedicated site directory, and be at least two path components deep. Remote rsync paths must not contain spaces. Never use a shared webroot that contains unrelated files.

## Dependencies

- `local`: rsync installed locally, permission to write the destination.
- `rsync`: rsync locally and remotely; SSH key or SSH-agent access with remote filesystem permissions. Optional `identity_file` is a path to a private key on the publishing **machine**, not its contents.
- `sftp`: lftp and SSH-agent / `~/.ssh/config` configured for passwordless SSH authentication. `identity_file` is **not** supported for SFTP profiles: use SSH configuration instead. For Ubuntu: `sudo apt install lftp`.

Publish first previews changes (rsync --dry-run or lftp mirror --dry-run), then asks explicitly before transfer. It **never removes** existing destination files; deleted or renamed pages therefore need a separate remote cleanup. A completed transfer does not verify a public URL, and an SFTP preview cannot be tested offline. SSH server keys should be checked/trusted before the first upload. Do not put passwords or private keys in `publishing.cfg`.

The action checks that the generated directory contains `index.html`, rejects symlinks in the output, and refuses an output path ending in `-preview`. Generate the public site first. It does not automatically regenerate, perform a content validation, or implement atomic publication/rollback.

Files changed in this package: `55-web-content-management.sh`, `manage-web-content.sh` (no framework or Web Server module changes).
