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


# fn: bundle_path - Validate a bundle identifier and return its JSON config path.
def bundle_path(store, name):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', name) or name in ('.', '..'):
        raise ValueError('Bundle identifier must contain letters, digits, dots, underscores or hyphens')
    return store / (name + '.json')


# fn: load - Read and validate a saved documentation bundle from JSON.
def load(store, name):
    path = bundle_path(store, name)
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema') != 1 or data.get('id') != name:
        raise ValueError('Unsupported or mismatched bundle file: ' + str(path))
    return data


# fn: save - Write a bundle configuration atomically to the bundle store.
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


# fn: check_sources - Validate bundle source directories and their output-location constraints.
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
    for field in ('bundle_prefaces', 'bundle_epilogues', 'documents'):
        entries = data.get(field, [])
        if not isinstance(entries, list):
            raise ValueError(f'{field} must be a list')
        for entry in entries:
            selected = document_path(entry['path'])
            if selected.is_relative_to(Path(data['output_dir']).resolve()):
                raise ValueError('Documentation sources must not belong to this bundle output: ' + str(selected))
    for item in data['products']:
        source = Path(item['source_dir'])
        if not source.is_dir():
            raise ValueError(f"Missing source directory for {item['id']}: {source}")
        paths.append(source.resolve())
    out = Path(data['output_dir']).resolve()
    if any(out == src or src in out.parents for src in paths):
        raise ValueError('Output may not be inside a source directory')


# fn: document_path - Resolve a configured source file independently of generated output.
def document_path(value):
    path = Path(value).expanduser().resolve()
    if not path.is_file() or path.suffix.lower() not in ('.sh', '.py', '.md'):
        raise ValueError('Documentation source must be an existing .sh, .py or .md file: ' + str(path))
    return path


# fn: document_list - Validate the explicit bundle document list for the selected role.
def document_list(data, role):
    field = {'preface': 'bundle_prefaces', 'epilogue': 'bundle_epilogues', 'page': 'documents'}[role]
    values = data.get(field)
    if values is None:
        values = []
    if not isinstance(values, list):
        raise ValueError(f'{field} must be a list')
    return field, values


# fn: run - Execute the selected bundle-management subcommand.
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
        save(store, dict(schema=1, id=args.name, title=args.title, output_dir='', overwrite='replace', products=[]))
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
    elif args.command == 'add-document':
        field, documents = document_list(data, args.role)
        path = str(document_path(args.path))
        entry = {'path': path}
        if args.role == 'page':
            if not args.product or not any(item['id'] == args.product for item in data['products']):
                raise ValueError('Ordinary documents require an existing --product identifier')
            entry.update(product=args.product, group=args.group or '', subgroup=args.subgroup or '', placement=args.placement)
        if any(item.get('path') == path for item in documents):
            raise ValueError('Document already selected for this role: ' + path)
        documents.append(entry)
        data[field] = documents
        # Explicit selections replace old Chapter 0 choices, never augment them.
        if args.role == 'preface':
            data.pop('chapter0', None)
            data.pop('chapter0_origin', None)
    elif args.command == 'remove-document':
        field, documents = document_list(data, args.role)
        if field not in data:
            raise ValueError('No explicit list; switch the role to manual selection first')
        if not 1 <= args.position <= len(documents):
            raise ValueError('Document position out of range')
        documents.pop(args.position - 1)
        data[field] = documents
    elif args.command == 'move-document':
        field, documents = document_list(data, args.role)
        if field not in data:
            raise ValueError('No explicit list; switch the role to manual selection first')
        if not 1 <= args.position <= len(documents) or not 1 <= args.new_position <= len(documents):
            raise ValueError('Document position out of range')
        documents.insert(args.new_position - 1, documents.pop(args.position - 1))
        data[field] = documents
    elif args.command == 'document-mode':
        if args.role == 'page':
            raise ValueError('Only bundle prefaces and epilogues support auto-discovery')
        field, documents = document_list(data, args.role)
        if args.mode == 'auto':
            data.pop(field, None)
            if args.role == 'preface':
                data.pop('chapter0', None)
                data.pop('chapter0_origin', None)
        elif args.mode == 'none':
            data[field] = []
            if args.role == 'preface':
                data.pop('chapter0', None)
                data.pop('chapter0_origin', None)
        elif args.mode == 'manual':
            data[field] = documents
            if args.role == 'preface':
                data.pop('chapter0', None)
                data.pop('chapter0_origin', None)
    elif args.command == 'validate':
        check_sources(data)
        for field in ('bundle_prefaces', 'bundle_epilogues', 'documents'):
            for document in data.get(field, []):
                document_path(document['path'])
        print('Bundle valid: ' + data['title'])
        return
    save(store, data)
    print('Saved bundle: ' + data['id'])


# fn: main - Parse bundle CLI arguments and execute the requested command.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--store', default=str(DEFAULT_STORE))
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('list')
    sub.add_parser('list-json')
    p = sub.add_parser('create'); p.add_argument('name'); p.add_argument('title')
    for cmd in ('show', 'delete', 'validate'):
        p = sub.add_parser(cmd); p.add_argument('name')
    p = sub.add_parser('set'); p.add_argument('name'); p.add_argument('field', choices=['title','output_dir','overwrite']); p.add_argument('value')
    p = sub.add_parser('add-product'); p.add_argument('name'); p.add_argument('product_id'); p.add_argument('title'); p.add_argument('source_dir')
    p = sub.add_parser('edit-product'); p.add_argument('name'); p.add_argument('product_id'); p.add_argument('--title'); p.add_argument('--source-dir')
    p = sub.add_parser('remove-product'); p.add_argument('name'); p.add_argument('product_id')
    p = sub.add_parser('move-product'); p.add_argument('name'); p.add_argument('product_id'); p.add_argument('position', type=int)
    p = sub.add_parser('add-document'); p.add_argument('name'); p.add_argument('role', choices=['preface','epilogue','page']); p.add_argument('path'); p.add_argument('--product'); p.add_argument('--group', default=''); p.add_argument('--subgroup', default=''); p.add_argument('--placement', choices=['page','preface','epilogue'], default='page')
    p = sub.add_parser('remove-document'); p.add_argument('name'); p.add_argument('role', choices=['preface','epilogue','page']); p.add_argument('position', type=int)
    p = sub.add_parser('move-document'); p.add_argument('name'); p.add_argument('role', choices=['preface','epilogue','page']); p.add_argument('position', type=int); p.add_argument('new_position', type=int)
    p = sub.add_parser('document-mode'); p.add_argument('name'); p.add_argument('role', choices=['preface','epilogue']); p.add_argument('mode', choices=['auto','manual','none'])
    args = parser.parse_args()
    try:
        run(args)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
