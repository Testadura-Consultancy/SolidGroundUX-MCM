#!/usr/bin/env python3
"""Loopback-only staged file upload receiver; Nginx MUST apply HTTPS and Basic Auth.

Install as a systemd service with a dedicated non-public writable directory.
This service does not implement authentication: direct network access is prohibited.
"""
import argparse
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
from io import BytesIO
from zipfile import ZipFile, BadZipFile

MAX_FILES = 10
MAX_FILE_BYTES = 25 * 1024 * 1024
MAX_REQUEST_BYTES = 101 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 500
MAX_ARCHIVE_UNPACKED = 100 * 1024 * 1024
ALLOWED_EXTENSIONS = {".md", ".zip", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf", ".txt"}
SAFE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*\Z")


def validate_upload(filename: str, payload: bytes) -> None:
    """Validate staged files, including ZIP paths and expansion limits.

    This is not ingestion: archive entries remain unextracted until the WCM
    ingestion planner reviews them on the receiving machine.
    """
    if not SAFE_NAME.fullmatch(filename) or filename in {".", ".."}:
        raise ValueError("Unsafe filename")
    extension = Path(filename).suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise ValueError("Unsupported file extension")
    if not payload or len(payload) > MAX_FILE_BYTES:
        raise ValueError("Invalid file size")
    if extension == ".md":
        if b"\x00" in payload:
            raise ValueError("Invalid Markdown content")
        payload.decode("utf-8")
    if extension != ".zip":
        return
    try:
        with ZipFile(BytesIO(payload)) as archive:
            entries = archive.infolist()
            if len(entries) > MAX_ARCHIVE_ENTRIES:
                raise ValueError("Too many ZIP entries")
            seen = set()
            unpacked = 0
            for entry in entries:
                name = entry.filename
                parts = name.rstrip("/").split("/")
                if (not name or name.startswith("/") or "\\" in name or
                    "\x00" in name or any(x in {"", ".", ".."} for x in parts) or
                    re.match(r"^[A-Za-z]:", name)):
                    raise ValueError("Unsafe ZIP path")
                if name in seen:
                    raise ValueError("Duplicate ZIP entry")
                seen.add(name)
                mode = (entry.external_attr >> 16) & 0o170000
                if mode not in (0, 0o100000, 0o040000):
                    raise ValueError("Unsupported ZIP entry type")
                if entry.flag_bits & 1:
                    raise ValueError("Encrypted ZIP entry")
                unpacked += entry.file_size
                if unpacked > MAX_ARCHIVE_UNPACKED:
                    raise ValueError("ZIP exceeds unpacked size limit")
    except BadZipFile as exc:
        raise ValueError("Invalid ZIP archive") from exc



class Handler(BaseHTTPRequestHandler):
    directory: Path
    hostname: str

    def respond(self, code: int, message: str):
        body = json.dumps({"message": message}, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/api/markdown-upload":
            return self.respond(404, "Unknown endpoint")
        # Require an explicit JavaScript request from our own origin; prevents a
        # cross-site HTML form from silently using cached Basic Auth credentials.
        if self.headers.get("Origin") != f"https://{self.hostname}" or self.headers.get("X-Testadura-Upload") != "1":
            return self.respond(403, "Invalid origin or request header")
        size = self.headers.get("Content-Length", "")
        if not size.isdigit() or not (0 < int(size) <= MAX_REQUEST_BYTES):
            return self.respond(413, "Upload exceeds size limit")
        content_type = self.headers.get("Content-Type", "")
        if not content_type.lower().startswith("multipart/form-data;"):
            return self.respond(415, "Expected multipart upload")
        raw = self.rfile.read(int(size))
        try:
            parsed = BytesParser(policy=default).parsebytes(
                b"MIME-Version: 1.0\r\nContent-Type: " + content_type.encode("ascii") + b"\r\n\r\n" + raw
            )
            if not parsed.is_multipart():
                return self.respond(400, "Invalid multipart body")
            parts = list(parsed.iter_parts())
            if not (1 <= len(parts) <= MAX_FILES):
                return self.respond(400, "Select 1 to 10 files")
            validated = []
            for part in parts:
                if part.get_content_disposition() != "form-data" or part.get_param("name", header="content-disposition") != "files":
                    return self.respond(400, "Unexpected upload field")
                filename = part.get_filename()
                # Distinguish malformed multipart metadata from a repeated filename.
                # Filename safety is checked separately by validate_upload().
                if not filename:
                    return self.respond(400, "Missing filename in upload part")
                if filename in {name for name, _ in validated}:
                    return self.respond(400, "Duplicate filename in upload request")
                payload = part.get_payload(decode=True)
                if payload is None:
                    return self.respond(400, "Invalid upload payload")
                validate_upload(filename, payload)
                validated.append((filename, payload))
        except (ValueError, UnicodeError, TypeError) as exc:
            return self.respond(400, f"Invalid upload: {type(exc).__name__}")
        created = []
        try:
            for filename, payload in validated:
                # O_EXCL prevents overwrites even when requests arrive concurrently.
                fd = os.open(self.directory / filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o640)
                created.append(filename)
                with os.fdopen(fd, "wb") as stream:
                    stream.write(payload)
                    stream.flush()
                    os.fsync(stream.fileno())
        except FileExistsError:
            for name in created:
                (self.directory / name).unlink(missing_ok=True)
            return self.respond(409, "At least one filename already exists")
        except OSError:
            for name in created:
                (self.directory / name).unlink(missing_ok=True)
            return self.respond(500, "Could not store uploaded files")
        self.respond(201, f"Stored {len(created)} file(s)")

    def do_GET(self):
        self.respond(405, "POST only")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--port", type=int, default=18765)
    args = parser.parse_args()
    folder = Path(args.directory).resolve(strict=True)
    if not folder.is_dir() or not os.access(folder, os.W_OK) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", args.hostname):
        parser.error("Invalid directory or hostname")
    Handler.directory = folder
    Handler.hostname = args.hostname
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
