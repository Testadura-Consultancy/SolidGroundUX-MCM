#!/usr/bin/env python3
"""Persist named SolidGroundUX documentation bundles (no rendering side effects)."""
import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

DEFAULT_STORE = Path.home() / '.config' / 'solidgroundux' / 'documentation-bundles'


def bundle_path(store, name):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', name) or name in ('.', '..'):
        raise ValueError('Bundle identifier must contain letters, digits, dots, underscores or hyphens')
    return store / (name + '.json')


def load(store, name):
    path = bundle_path(store, name)
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema') != 1 or data.get('id') != name:
        raise ValueError('Unsupported or mismatched bundle file: ' + str(path))
    return data


def save(store, data):
    store.mkdir(parents=True, exist_ok=True)
    target = bundle_path(store, data['id'])
    fd, tmp = tempfile.mkstemp(prefix='.bundle-', suffix='.tmp', dir=str(store))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def check_sources(data):
    if not data['products']:
        raise ValueError('Bundle has no products')
    if not data['output_dir']:
        raise ValueError('Bundle output directory not configured')
    if not Path(data['output_dir']).is_absolute():
        raise ValueError('Output directory must be absolute')
    if Path(data['output_dir']).resolve() == Path('/'):
        raise ValueError('Output directory may not be filesystem root')
    paths = []
    for item in data['products']:
        source = Path(item['source_dir'])
        if not source.is_dir():
            raise ValueError(f"Missing source directory for {item['id']}: {source}")
        paths.append(source.resolve())
    out = Path(data['output_dir']).resolve()
    if any(out == src or src in out.parents for src in paths):
        raise ValueError('Output may not be inside a source directory')


def run(args):
    store = Path(args.store).expanduser()
    if args.command == 'list-json':
        bundles = []
        for path in sorted(store.glob('*.json')):
            try:
                bundles.append(load(store, path.stem))
            except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
                print(f'Warning: invalid bundle {path}: {exc}', file=sys.stderr)
        print(json.dumps(bundles, ensure_ascii=False))
        return
    if args.command == 'list':
        for path in sorted(store.glob('*.json')):
            try:
                data = load(store, path.stem)
                print(f"{data['id']}\t{data['title']}\t{len(data['products'])} product(s)")
            except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
                print(f'Warning: invalid bundle {path}: {exc}', file=sys.stderr)
        return
    if args.command == 'create':
        args.name = args.name.replace(' ', '-')
        path = bundle_path(store, args.name)
        if path.exists():
            raise ValueError('Bundle already exists: ' + args.name)
        save(store, dict(schema=1, id=args.name, title=args.title, output_dir='', overwrite='replace', chapter0='', products=[]))
        print('Created bundle: ' + args.name)
        return
    data = load(store, args.name)
    if args.command == 'show':
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return
    if args.command == 'delete':
        bundle_path(store, args.name).unlink()
        print('Deleted bundle: ' + args.name)
        return
    if args.command == 'set':
        value = args.value
        if args.field == 'overwrite' and value not in ('replace', 'fail'):
            raise ValueError('Overwrite must be replace or fail')
        if args.field == 'output_dir' and value and not Path(value).is_absolute():
            raise ValueError('Output directory must be an absolute path')
        if args.field == 'chapter0':
            # Selecting the already-retained file is a no-op: preserve its
            # original generated location for duplicate-page exclusion.
            if value and Path(value).expanduser().resolve() == Path(data.get('chapter0') or '/nonexistent-sgnd-chapter0').expanduser().resolve() and data.get('chapter0_origin'):
                save(store, data)
                print('Saved bundle: ' + data['id'])
                return
            if value and not Path(value).expanduser().is_file():
                raise ValueError('Chapter 0 Markdown file does not exist')
            if value:
                selected = Path(value).expanduser().resolve()
                data['chapter0_origin'] = str(selected)
                output_content = Path(data['output_dir']).expanduser().resolve() / 'content' if data['output_dir'] else None
                if output_content and selected.is_relative_to(output_content):
                    # Generated output is replaced on every build: retain the selected
                    # introductory page independently so future rebuilds still work.
                    retained = store / 'chapter0' / (data['id'] + '.md')
                    retained.parent.mkdir(parents=True, exist_ok=True)
                    retained.write_bytes(selected.read_bytes())
                    value = str(retained)
                else:
                    value = str(selected)
            else:
                data.pop('chapter0_origin', None)
        data[args.field] = value
    elif args.command == 'add-product':
        if any(p['id'] == args.product_id for p in data['products']):
            raise ValueError('Product already exists')
        bundle_path(store, args.product_id)  # validate identifier
        if not Path(args.source_dir).is_dir():
            raise ValueError('Source directory does not exist')
        data['products'].append(dict(id=args.product_id, title=args.title, source_dir=str(Path(args.source_dir).resolve())))
    elif args.command == 'edit-product':
        matches = [p for p in data['products'] if p['id'] == args.product_id]
        if not matches:
            raise ValueError('Unknown product')
        if args.title is not None:
            matches[0]['title'] = args.title
        if args.source_dir is not None:
            if not Path(args.source_dir).is_dir():
                raise ValueError('Source directory does not exist')
            matches[0]['source_dir'] = str(Path(args.source_dir).resolve())
    elif args.command == 'remove-product':
        before = len(data['products'])
        data['products'] = [p for p in data['products'] if p['id'] != args.product_id]
        if len(data['products']) == before:
            raise ValueError('Unknown product')
    elif args.command == 'move-product':
        matches = [p for p in data['products'] if p['id'] == args.product_id]
        if not matches:
            raise ValueError('Unknown product')
        if not 1 <= args.position <= len(data['products']):
            raise ValueError('Position out of range')
        data['products'].remove(matches[0])
        data['products'].insert(args.position - 1, matches[0])
    elif args.command == 'validate':
        check_sources(data)
        print('Bundle valid: ' + data['title'])
        return
    save(store, data)
    print('Saved bundle: ' + data['id'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--store', default=str(DEFAULT_STORE))
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('list')
    sub.add_parser('list-json')
    p = sub.add_parser('create'); p.add_argument('name'); p.add_argument('title')
    for cmd in ('show', 'delete', 'validate'):
        p = sub.add_parser(cmd); p.add_argument('name')
    p = sub.add_parser('set'); p.add_argument('name'); p.add_argument('field', choices=['title','output_dir','overwrite','chapter0']); p.add_argument('value')
    p = sub.add_parser('add-product'); p.add_argument('name'); p.add_argument('product_id'); p.add_argument('title'); p.add_argument('source_dir')
    p = sub.add_parser('edit-product'); p.add_argument('name'); p.add_argument('product_id'); p.add_argument('--title'); p.add_argument('--source-dir')
    p = sub.add_parser('remove-product'); p.add_argument('name'); p.add_argument('product_id')
    p = sub.add_parser('move-product'); p.add_argument('name'); p.add_argument('product_id'); p.add_argument('position', type=int)
    args = parser.parse_args()
    try:
        run(args)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
