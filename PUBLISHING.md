# Website publishing (SolidGroundUX Web Content Management)

Publishing is the **last stage** of the static-website workflow. It transfers
already generated **HTML** to a destination. It does not read, regenerate, or
configure the original Markdown/source repository.

- **Documentation website:** **Assemble Markdown → Generate Website → Publish Website**.
- **Ordinary WWW website:** **Generate Website → Publish Website**.

Documentation bundles, HTML generation and publishing belong to **Management
Console Modules (MCM)**. SDK copies of older documentation tools are not the
maintained implementation of this workflow.

## Publish Website

From Web Content Management select **Publish Website**. On initial configuration
or when selecting **Modify**, the prompts occur in this order:

1. **Source directory (generated HTML)** — local generated site directory, for example `/tmp/sgnd-www`; it must contain `index.html`.
2. **Destination host (`user@host`)** — SSH account and server, for example `sysadmin@td-web`.
3. **Remote website** — select an existing Nginx website or create a new one.
   - **Select existing website** discovers active hostnames and document roots on the selected server; selecting one fills in its hostname and directory.
   - **Create new website** asks for the website hostname. When remote Nginx roots can be read, the tool proposes a sibling directory under their parent; the remote directory remains editable. If discovery is unavailable, enter the directory manually.
4. **Synchronization** — choose `Update` or `Mirror`.

Once configured, the operation shows the five saved settings and the final actions:

```text
Publish Website

Source directory    : /tmp/sgnd-www
Destination host    : sysadmin@td-web
Remote directory    : /srv/storage/www/sgndux
Website hostname    : sgndux.testadura.hq
Synchronization     : Mirror

1) Publish
2) Modify
Q) Cancel
```

The settings are **state-saved**; a second publication can reuse them without
re-entering the source or server. Publishing does **not** require selecting a
Markdown repository or maintaining destination profiles in `config/publishing.cfg`.

## Safety and remote site setup

- The source must be an existing generated directory containing `index.html`. The action refuses `/`, preview output locations and source trees containing symlinks.
- The remote path must be a dedicated absolute directory, not a shared webroot containing unrelated sites.
- **Update** transfers changes without removing unmatched remote files. **Mirror** uses rsync deletion for destination files absent from the generated site; the tool warns before this operation and asks for confirmation.
- Publishing uses SSH/rsync, checks access and offers to provision a missing Nginx site using the remote MCM Web Server action. It does not replace an incompatible existing site silently.
- DNS registration can be offered separately. A successful transfer does not guarantee successful DNS resolution or browser verification; inspect any warnings independently of the transfer result.
- Ensure that the remote server has Nginx and the needed SolidGroundUX management commands available for automatic site provisioning, and that SSH authentication/privileges are configured.

## HTTP, HTTPS and certificate trust

Creating a website for publication does **not** require HTTPS. Test the HTTP
site first, then use **Web Server → Manage sites → Configure HTTPS** for a
selected site if TLS is desired. The existing HTTPS workflow supports a
self-signed test certificate or an existing certificate and can optionally
redirect HTTP to HTTPS.

For a self-signed certificate, use **Web Server → Manage sites → Export public
HTTPS certificate** on the selected website. It reports the public certificate
path, a SHA-256 fingerprint, and an `scp` command to retrieve the `.crt` from
the administrator's `~/sgnd-certificates/` directory. Only the public
certificate is exported: **never distribute the server's private key**.

After verifying the certificate identity/fingerprint and hostname, you can
trust a self-signed certificate on a test workstation according to its
certificate-store policy. For CA-issued certificates, trust the issuing CA
instead of treating an arbitrary server certificate as a root. Importing a
certificate does not repair a hostname mismatch or insecure page resources.

## Related documentation

- [AUTHORING.md](AUTHORING.md) — Markdown syntax, metadata and content layout.
- [README.md](README.md) — MCM responsibilities and architecture.
