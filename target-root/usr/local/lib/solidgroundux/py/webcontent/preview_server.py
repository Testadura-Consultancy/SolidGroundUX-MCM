#!/usr/bin/env python3
# =====================================================================================
# SolidGroundUX MCM - Local Website Preview Server
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2631102
#   Source      : preview_server.py
#   Type        : module
#   Purpose     : Manage an isolated localhost-only Python website preview process
#
# Description:
#   Starts a non-interactive http.server on the first free port beginning at the
#   requested port. Keeps per-directory process identity in the user's cache;
#   never terminates processes not demonstrably started by this module.
#
# Usage:
#   ```bash
#   python3 -m webcontent.preview_server start --directory /tmp/site --port 8080
#   python3 -m webcontent.preview_server stop --directory /tmp/site
#   ```
# =====================================================================================
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time


def _registry(directory: Path) -> Path:
    root = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))).expanduser()
    if not root.is_absolute():
        raise ValueError('Cache location must be absolute')
    folder = root / 'solidgroundux' / 'web-previews'
    folder.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    key = hashlib.sha256(str(directory).encode('utf-8')).hexdigest()
    return folder / (key + '.json')


def _start_id(pid: int) -> str:
    try:
        # Linux /proc starttime, to distinguish reused process identifiers.
        raw = Path(f'/proc/{pid}/stat').read_text(encoding='utf-8')
        return raw.rsplit(')', 1)[1].split()[19]
    except (OSError, IndexError, ValueError):
        return ''


def _owned(record: dict, directory: Path) -> bool:
    try:
        pid = int(record['pid'])
        port = int(record['port'])
        if pid <= 0 or not 1 <= port <= 65535:
            return False
        if record.get('start_id') != _start_id(pid) or not record.get('start_id'):
            return False
        command = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
        return (b'-m' in command and b'http.server' in command
                and b'--bind' in command and b'127.0.0.1' in command
                and b'--directory' in command and os.fsencode(str(directory)) in command
                and str(port).encode('ascii') in command)
    except (OSError, ValueError, TypeError, KeyError):
        return False


def _current(path: Path, directory: Path) -> dict | None:
    try:
        record = json.loads(path.read_text(encoding='utf-8'))
        if isinstance(record, dict) and _owned(record, directory):
            return record
    except (OSError, ValueError, TypeError):
        pass
    return None


def _available(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        try:
            probe.bind(('127.0.0.1', port))
            return True
        except OSError:
            return False


def _serve(directory: Path, preferred_port: int, path: Path) -> str:
    record = _current(path, directory)
    if record:
        return f"http://localhost:{record['port']}/"
    for port in range(preferred_port, 65536):
        if not _available(port):
            continue
        # Do not use Popen as a context manager: leaving it would wait for the
        # long-running HTTP server and block the caller indefinitely.
        process = subprocess.Popen(
            [sys.executable, '-m', 'http.server', str(port), '--bind', '127.0.0.1',
             '--directory', str(directory)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True,
        )
        # Confirm the candidate stayed alive: another process can win the port race.
        for _ in range(15):
            if process.poll() is not None:
                break
            if not _available(port):
                start_id = _start_id(process.pid)
                if start_id:
                    temporary = path.with_name(f'.{path.stem}.{os.getpid()}.tmp')
                    temporary.write_text(json.dumps({'pid': process.pid, 'port': port,
                        'start_id': start_id}) + '\n', encoding='utf-8')
                    os.chmod(temporary, 0o600)
                    os.replace(temporary, path)
                    return f'http://localhost:{port}/'
            time.sleep(0.1)
    raise RuntimeError(f'No free localhost port found from {preferred_port}')


def _stop(path: Path, directory: Path) -> None:
    record = _current(path, directory)
    if record:
        os.kill(int(record['pid']), signal.SIGTERM)
    path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description='SolidGroundUX local website preview')
    parser.add_argument('action', choices=('start', 'stop', 'status'))
    parser.add_argument('--directory', required=True)
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    try:
        directory = Path(args.directory).expanduser().resolve(strict=True)
        if not directory.is_dir() or not (directory / 'index.html').is_file():
            raise ValueError('Preview requires an existing website with index.html')
        if not 1 <= args.port <= 65535:
            raise ValueError('Port must be between 1 and 65535')
        path = _registry(directory)
        lock = path.with_suffix('.lock')
        if lock.is_symlink():
            raise ValueError('Refusing symbolic link lock')
        with lock.open('a+b') as handle:
            os.chmod(lock, 0o600)
            fcntl.flock(handle, fcntl.LOCK_EX)
            if args.action == 'start':
                print(_serve(directory, args.port, path))
            elif args.action == 'stop':
                _stop(path, directory)
                print('Stopped')
            else:
                record = _current(path, directory)
                if not record:
                    return 1
                print(f"http://localhost:{record['port']}/")
        return 0
    except (OSError, ValueError, RuntimeError) as exc:
        print(f'Local preview: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
