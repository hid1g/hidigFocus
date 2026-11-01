#!/usr/bin/env python3
"""Compare exported before/after snapshots without printing private task contents."""
import argparse
import json
from pathlib import Path

SET_FIELDS = {'weekdays', 'checkInDayKeys', 'requiredTaskIDs', 'selectedCalendarIDs'}
MAINTENANCE = {'disciplineStreak', 'disciplineLastCountedDayKey'}


def normalize(value, key=''):
    if isinstance(value, dict):
        return {k: normalize(v, k) for k, v in value.items()}
    if isinstance(value, list):
        if key == 'pendingGroupRules' and len(value) % 2 == 0:
            return {str(value[i]): normalize(value[i + 1]) for i in range(0, len(value), 2)}
        values = [normalize(v) for v in value]
        if key in SET_FIELDS:
            values.sort(key=lambda v: json.dumps(v, sort_keys=True))
        return values
    return value


def compare(before, after, path='$'):
    differences = []
    if isinstance(before, dict) and isinstance(after, dict):
        for key in before:
            if path == '$' and key in MAINTENANCE:
                continue
            child = path + '.' + key
            if key not in after:
                differences.append(child)
            else:
                differences.extend(compare(before[key], after[key], child))
    elif isinstance(before, list) and isinstance(after, list):
        if len(before) != len(after):
            differences.append(path + '.length')
        for i, (old, new) in enumerate(zip(before, after)):
            differences.extend(compare(old, new, path + '[' + str(i) + ']'))
    elif type(before) is not type(after) or before != after:
        differences.append(path)
    return differences


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    before = json.loads(args.before.read_text())
    after = json.loads(args.after.read_text())
    paths = compare(normalize(before), normalize(after))
    report = {
        'everyExistingRawJSONFieldPreserved': not paths,
        'differentOrMissingFieldPaths': paths,
        'allowedRootChanges': sorted(MAINTENANCE),
        'tasksBefore': len(before.get('managedTasks', [])),
        'tasksAfter': len(after.get('managedTasks', [])),
        'scope': 'Existing raw fields; full typed equality and file hashes are checked separately by PrintDesignTests.'
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Preservation audit: ' + ('PASS' if not paths else 'FAIL') + '; changed/missing paths: ' + str(len(paths)))
    raise SystemExit(1 if paths else 0)
