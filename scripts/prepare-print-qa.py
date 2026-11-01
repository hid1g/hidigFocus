#!/usr/bin/env python3
"""Prepare an isolated native review bundle. Never installs or launches it."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=pathlib.Path, default=pathlib.Path('dist/hidigFocus.app'))
parser.add_argument('--output', type=pathlib.Path, required=True)
parser.add_argument('--data-dir', type=pathlib.Path, required=True)
parser.add_argument('--evidence-dir', type=pathlib.Path, required=True)
parser.add_argument('--fixture-tasks', type=int, default=0)
parser.add_argument('--fixture-series', type=int)
parser.add_argument('--allow-profiling', action='store_true')
parser.add_argument('--bundle-id', default='com.hidig.focus.print.qa')
parser.add_argument('--name', default='hidigFocus Print QA')
parser.add_argument('--renderer', choices=['auto', 'canvas', 'legacy'], default='auto')
args = parser.parse_args()
source, output, data = args.app.resolve(), args.output.resolve(), args.data_dir.resolve()
if not args.bundle_id.startswith('com.hidig.focus.') or not args.bundle_id.endswith('.qa'):
    parser.error('Use a separate com.hidig.focus.*.qa bundle identifier')
if not (source / 'Contents/MacOS/hidigFocus').is_file():
    parser.error('Build dist/hidigFocus.app first')
if b'HidigQAEnvironment' not in (source / 'Contents/MacOS/hidigFocus').read_bytes():
    parser.error('This binary does not support embedded QA configuration; build current sources first')
live = pathlib.Path.home() / 'Library/Application Support/hidigFocus'
if data == live or live in data.parents:
    parser.error('QA data must be outside the live hidigFocus directory')
if output == source or 'qa' not in output.stem.lower() or output.parent in [pathlib.Path('/Applications'), pathlib.Path.home() / 'Applications']:
    parser.error('Choose a separate QA-named review bundle outside Applications')
if output.exists():
    info = plistlib.loads((output / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != args.bundle_id:
        parser.error('Refusing to replace an app with a different bundle identifier')
    processes = subprocess.check_output(['ps', '-axo', 'comm'], text=True)
    if any(line.startswith(str(output) + '/') for line in processes.splitlines()):
        parser.error('Close the existing QA app before preparing a replacement')
    shutil.rmtree(output)
shutil.copytree(source, output, symlinks=True)
info = plistlib.loads((output / 'Contents/Info.plist').read_bytes())
info.update(CFBundleIdentifier=args.bundle_id, CFBundleName=args.name, CFBundleDisplayName=args.name)
info.pop('NSDockTilePlugIn', None)
values = {'HIDIGFOCUS_QA': '1', 'HIDIGFOCUS_DATA_DIR': str(data),
          'HIDIGFOCUS_PREFS_SUITE': args.bundle_id,
          'HIDIGFOCUS_EVIDENCE_DIR': str(args.evidence_dir.resolve())}
if args.fixture_tasks:
    values['HIDIGFOCUS_QA_TASKS'] = str(max(0, args.fixture_tasks))
if args.fixture_series is not None:
    values['HIDIGFOCUS_QA_SERIES'] = str(max(0, args.fixture_series))
values['HIDIGFOCUS_CALENDAR_RENDERER'] = args.renderer
# Keep the original native executable. A shell/exec wrapper breaks process/window
# identity in accessibility and profiling tools on some macOS versions.
info['HidigQAEnvironment'] = values
(output / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
command = ['codesign', '--force', '--deep', '--sign', '-']
if args.allow_profiling:
    entitlement = output.parent / 'qa-debug-entitlements.plist'
    entitlement.write_bytes(plistlib.dumps({'com.apple.security.get-task-allow': True}))
    command += ['--entitlements', str(entitlement)]
subprocess.run(command + [str(output)], check=True)
print(output)
