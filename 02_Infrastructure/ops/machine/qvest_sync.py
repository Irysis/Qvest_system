#!/usr/bin/env python3
"""qvest_sync.py — 두 기계(OneDrive 로 공유하는 작업 트리) 동기화 도구 (2026-11-01 두 대 운용)

  write     <root> <out.tsv>
      작업 트리 · .git 의 크기 · 해시 대조표를 쓴다 — 정본 기계(노트북, 1_laptop.ps1 마지막 단계).
  compare   <root> <manifest.tsv> [--allow GLOB ..] [--report FILE] [--show N]
      OneDrive 로 받은 사본을 대조표와 맞춘다 — 메인 PC(2_main.ps1 이 보류 표식을 지우기 전 · 어떤 git 명령보다 먼저:
      git 은 .git/index 를 다시 쓴다).
  conflicts <root> --device NAME .. [--winner NAME ..] [--stash DIR] [--apply]
      OneDrive 충돌 사본('이름-기계명[.확장자]')을 찾아 정리한다. 기본은 계획만, --apply 가 실행.
  pin       <root> [--exclude REL ..] [--essential REL ..] [--files MANIFEST] [--no-all] [--margin-gb N] [--apply]
      '항상 이 장치에 유지'(attrib +P -U) — 내려받을 양 + 여유가 빈 공간을 넘으면 핵심 폴더만. --no-all = '전부' 계획 없이
      핵심 폴더부터(메인 — 결과물 폴더는 열 때 내려받기) · --files = 대조표의 T · U 파일 중 고른 폴더 밖의 것을 파일 단위로 더한다.
종료 코드: 0 = 정상 · 일치 · 1 = 불일치 · 2 = 사용법 · 입력 오류 · 3 = 사람이 봐야 할 것이 남음

대조표 대상: T = git 추적 파일 · U = 추적 안 됨이면서 무시 안 됨 · D = 작업 트리에서 지워진 추적 파일(메인에도 없어야 일치) ·
  G = .git 아래 전부(*.lock · tmp_* · fsmonitor--daemon 제외 · 메인에만 있는 .git 파일도 불일치 — 노트북에서 지운 ref 가
  아직 안 지워졌다는 뜻). 64 MB 넘는 파일은 앞뒤 1 MB 해시(p:) — pack 은 이름이 내용 해시라 크기 + 부분 해시로 충분하다.
  대조표를 쓴 뒤(머리말 epoch) 바뀐 파일은 '낡은 사본'이 아니라 '더 새 사본'이다 — 내용이 달라도 고친 시각이 대조표보다
  NEWER_SEC 넘게 뒤면 경고로만 센다(노트북이 대조표 뒤에 더 쓴 것 · 메인의 git 이 index 를 다시 쓴 것). 빠진 파일 ·
  대조표보다 오래된 다른 내용 = 아직 안 내려온 것 → 불일치.
--allow: 두 기계가 함께 덧붙이는 기록(qepm/observability/events.jsonl — 모든 도구 호출마다 safety_guard 가 한 줄)은
  차이를 보고만 하고 막지 않는다.
conflicts: 이긴 판 = --winner 기계의 사본(여럿이면 최신) · 없으면 원본 이름에 남은 판. *.jsonl 은 줄 합집합(이긴 판
  다음 나머지 판의 새 줄), 그 밖은 이긴 판만 남기고 나머지는 --stash 아래 같은 상대 경로 + '.<기계명>' 으로 옮긴다
  (지우지 않는다). 내용이 같은 사본은 지운다. .git 안의 사본은 건드리지 않는다(종료 3) · 원본이 없는 사본은 목록만.
긴 경로는 \\\\?\\ 접두로 연다(Windows MAX_PATH). 연결(junction · symlink)은 따라가지 않는다. 실측 절차 = README.md.
"""
import argparse
import ctypes
import datetime
import fnmatch
import hashlib
import os
import re
import shutil
import socket
import subprocess
import sys
import time

BIG = 64 * 1024 * 1024
PART = 1024 * 1024
NEWER_SEC = 60
G = 1024 ** 3
CLOUD_ATTR = 0x400000 | 0x40000 | 0x1000      # RECALL_ON_DATA_ACCESS | RECALL_ON_OPEN | OFFLINE — 아직 안 내려온 파일
PINNED, UNPINNED = 0x80000, 0x100000           # attrib +P(항상 유지) · +U(공간 확보)


def lp(path):
    p = os.path.abspath(path)
    if os.name == 'nt' and not p.startswith('\\\\?\\'):
        p = '\\\\?\\' + p
    return p


def digest(path, size):
    h = hashlib.sha256()
    with open(lp(path), 'rb') as f:
        if size > BIG:
            h.update(f.read(PART))
            f.seek(size - PART)
            h.update(f.read(PART))
            return 'p:' + h.hexdigest()
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def git(root, *args):
    r = subprocess.run(['git', '-C', root, *args], capture_output=True)
    if r.returncode != 0:
        sys.exit('git %s 실패: %s' % (' '.join(args), r.stderr.decode('utf-8', 'replace').strip()))
    return r.stdout


def is_link(e):
    try:
        return e.is_symlink() or (hasattr(e, 'is_junction') and e.is_junction())
    except OSError:
        return True


def walk(top, prune=None):
    """(디렉터리, [파일 DirEntry]) — 연결은 따라가지 않는다 · prune(경로, 이름) 이 참이면 그 디렉터리로 내려가지 않는다"""
    stack = [lp(top)]
    while stack:
        d = stack.pop()
        try:
            it = os.scandir(d)
        except OSError:
            continue
        files = []
        with it:
            for e in it:
                try:
                    if is_link(e):
                        continue
                    if e.is_dir(follow_symlinks=False):
                        if not (prune and prune(e.path, e.name)):
                            stack.append(e.path)
                    else:
                        files.append(e)
                except OSError:
                    continue
        yield d, files


def git_skip(rel):
    name = rel.rsplit('/', 1)[-1]
    return name.endswith('.lock') or name.startswith('tmp_') or '/fsmonitor--daemon/' in rel


def git_files(root):
    """.git 아래 파일 — '/' 구분 상대 경로"""
    base = lp(root)
    for d, files in walk(os.path.join(root, '.git')):
        for e in files:
            rel = e.path[len(base) + 1:].replace('\\', '/')
            if not git_skip(rel):
                yield rel


def entries(root):
    for kind, args in (('T', ('ls-files', '-z')), ('U', ('ls-files', '-z', '--others', '--exclude-standard'))):
        for p in git(root, *args).decode('utf-8').split('\0'):
            if p:
                yield kind, p
    for p in git_files(root):
        yield 'G', p


def cmd_write(root, out):
    t0 = time.time()
    head = git(root, 'rev-parse', 'HEAD').decode().strip()
    branch = git(root, 'rev-parse', '--abbrev-ref', 'HEAD').decode().strip()
    n = dict.fromkeys('TUDG', 0)
    skipped = 0
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('# qvest_manifest v1 host=%s time=%s epoch=%d head=%s branch=%s root=%s\n' % (
            os.environ.get('COMPUTERNAME') or socket.gethostname(),
            datetime.datetime.now().isoformat(timespec='seconds'), int(t0), head, branch, root.replace('\\', '/')))
        for kind, rel in entries(root):
            if '\t' in rel or '\n' in rel:
                skipped += 1
                continue
            full = os.path.join(root, rel)
            try:
                size = os.stat(lp(full)).st_size
            except FileNotFoundError:
                if kind == 'T':
                    f.write('D\t-\t-\t%s\n' % rel)
                    n['D'] += 1
                continue
            f.write('%s\t%d\t%s\t%s\n' % (kind, size, digest(full, size), rel))
            n[kind] += 1
            if sum(n.values()) % 5000 == 0:
                print('  ... %d written, %.0fs' % (sum(n.values()), time.time() - t0), file=sys.stderr, flush=True)
    print('WROTE %s tracked=%d untracked=%d deleted=%d git=%d skipped=%d head=%s branch=%s %.0fs' % (
        out, n['T'], n['U'], n['D'], n['G'], skipped, head[:10], branch, time.time() - t0))
    return 0


def cmd_compare(root, manifest, allow, report, show):
    t0 = time.time()
    bad, warn = [], []
    seen_git = set()
    total = 0
    with open(manifest, encoding='utf-8') as f:
        header = f.readline().strip()
        if not header.startswith('# qvest_manifest v1'):
            print('대조표 형식이 아님: %s' % manifest)
            return 2
        epoch = int(dict(re.findall(r'(\w+)=(\S*)', header)).get('epoch') or 0)
        for line in f:
            kind, size, hsh, rel = line.rstrip('\n').split('\t', 3)
            total += 1
            if kind == 'G':
                seen_git.add(rel.lower())
            full = os.path.join(root, rel)
            status, detail, mtime = None, '', 0
            try:
                st = os.stat(lp(full))
            except FileNotFoundError:
                if kind != 'D':
                    status = 'missing'
            else:
                mtime = st.st_mtime
                if kind == 'D':
                    status, detail = 'present', 'laptop deleted it'
                elif st.st_size != int(size):
                    status, detail = 'size', '%s != %d' % (size, st.st_size)
                else:
                    try:
                        if digest(full, st.st_size) != hsh:
                            status = 'hash'
                    except OSError as e:
                        status, detail = 'unreadable', str(e)
            if status in ('size', 'hash', 'present') and epoch and mtime > epoch + NEWER_SEC:
                warn.append(('newer', kind, rel, '%s · %s' % (status, time.strftime('%m-%d %H:%M', time.localtime(mtime)))))
            elif status:
                (warn if any(fnmatch.fnmatch(rel, g) for g in allow) else bad).append((status, kind, rel, detail))
            if total % 3000 == 0:
                print('  ... %d checked, %d mismatches, %.0fs' % (total, len(bad), time.time() - t0), file=sys.stderr, flush=True)
    for rel in git_files(root):
        if rel.lower() not in seen_git:
            try:
                mtime = os.stat(lp(os.path.join(root, rel))).st_mtime
            except OSError:
                continue
            if epoch and mtime > epoch + NEWER_SEC:
                warn.append(('newer', 'G', rel, 'only on this machine · written after the manifest'))
            else:
                bad.append(('extra', 'G', rel, 'only on this machine'))
    counts = {}
    for b in bad:
        counts[b[0]] = counts.get(b[0], 0) + 1
    lines = ['%-10s %s %s %s' % b for b in bad] + ['%-10s %s %s %s (allowed)' % w for w in warn]
    if report:
        with open(report, 'w', encoding='utf-8', newline='\n') as f:
            f.write('# compare %s vs %s at %s\n# %s\n' % (root, manifest, datetime.datetime.now().isoformat(timespec='seconds'), header))
            f.write('\n'.join(lines) + '\n')
    verdict = 'MATCH' if not bad else 'MISMATCH'
    print('%s total=%d mismatches=%d %s allowed_diffs=%d %.0fs | manifest: %s' % (
        verdict, total, len(bad), ' '.join('%s=%d' % kv for kv in sorted(counts.items())), len(warn), time.time() - t0, header[20:]))
    for ln in lines[:show]:
        print('  ' + ln)
    if len(lines) > show:
        print('  ... (%d more%s)' % (len(lines) - show, ', full list: ' + report if report else ''))
    return 0 if not bad else 1


def conflict_re(names):
    alt = '|'.join(re.escape(n) for n in sorted({n for n in names if n}, key=len, reverse=True))
    return re.compile(r'^(?P<stem>.+)-(?P<dev>%s)(?:-\d+)?(?P<ext>\.[^.]*)?$' % alt, re.I)


def _read(p):
    with open(lp(p), 'rb') as f:
        return f.read()


def union_lines(first, others):
    """이긴 판 그대로 + 나머지 판에서 처음 보는 줄(빈 줄 · CR 무시하고 비교)"""
    out = bytearray(first)
    if out and not out.endswith(b'\n'):
        out += b'\n'
    seen = {l.rstrip(b'\r') for l in first.split(b'\n')}
    added = 0
    for o in others:
        for l in o.split(b'\n'):
            k = l.rstrip(b'\r')
            if k and k not in seen:
                out += k + b'\n'
                seen.add(k)
                added += 1
    return bytes(out), added


def stash_move(p, stash, rel, label):
    dst = os.path.join(stash, *rel.split('/')) + '.' + re.sub(r'[^A-Za-z0-9_.-]', '_', label)
    os.makedirs(os.path.dirname(lp(dst)), exist_ok=True)
    d, i = dst, 1
    while os.path.exists(lp(d)):
        i += 1
        d = '%s.%d' % (dst, i)
    shutil.move(lp(p), lp(d))


def resolve(orig, copies, rel, win, stash, apply):
    labels = {orig: 'other'}
    labels.update({p: dv for p, dv in copies})
    wins = sorted((p for p, dv in copies if dv.lower() in win), key=lambda p: os.stat(lp(p)).st_mtime, reverse=True)
    winner = wins[0] if wins else orig
    losers = ([orig] if winner != orig else []) + [p for p, _ in copies if p != winner]
    data = {p: _read(p) for p in [winner] + losers}
    if len(set(data.values())) == 1:
        if apply:
            for p, _ in copies:
                os.remove(lp(p))
        return 'identical', '사본 %d개 삭제(내용 같음)' % len(copies)
    who = labels[winner] if winner != orig else '원본 이름'
    if rel.lower().endswith('.jsonl'):
        merged, added = union_lines(data[winner], [data[p] for p in losers])
        if apply:
            tmp = orig + '.qvest_tmp'
            with open(lp(tmp), 'wb') as f:
                f.write(merged)
            for p, dv in copies:
                stash_move(p, stash, rel, dv)
            os.replace(lp(tmp), lp(orig))
        return 'merged', '줄 합집합 = %s 판 + 새 줄 %d · 사본 → stash' % (who, added)
    if apply:
        for p in losers:
            stash_move(p, stash, rel, labels[p])
        if winner != orig:
            os.replace(lp(winner), lp(orig))
    return 'kept', '%s 판 유지 · 나머지 %d개 → stash' % (who, len(losers))


def cmd_conflicts(root, devices, winners, stash, apply):
    if apply and not stash:
        print('--apply 에는 --stash <폴더> 가 필요합니다')
        return 2
    t0 = time.time()
    pat = conflict_re(devices)
    win = {w.lower() for w in winners}
    base = lp(root)
    rel = lambda p: p[len(base) + 1:].replace('\\', '/')
    groups, orphans, nfiles, tick = {}, [], 0, time.time()
    for d, files in walk(root):
        nfiles += len(files)
        if time.time() - tick > 20:
            tick = time.time()
            print('  ... %d files scanned, %.0fs' % (nfiles, tick - t0), file=sys.stderr, flush=True)
        names = {e.name for e in files}
        for e in files:
            m = pat.match(e.name)
            if not m:
                continue
            orig = m.group('stem') + (m.group('ext') or '')
            if orig in names:
                groups.setdefault(os.path.join(d, orig), []).append((e.path, m.group('dev')))
            else:
                orphans.append(e.path)
    counts = dict.fromkeys(('merged', 'kept', 'identical', 'git', 'orphan', 'error'), 0)
    for orig, copies in sorted(groups.items()):
        r = rel(orig)
        devs = ','.join(sorted({dv for _, dv in copies}))
        if r.startswith('.git/'):
            counts['git'] += 1
            print('GIT       %s <- %s : .git 안 — 사람이 확인(건드리지 않음)' % (r, devs))
            continue
        try:
            kind, what = resolve(orig, copies, r, win, stash, apply)
            counts[kind] += 1
            print('%-9s %s <- %s : %s' % (kind.upper(), r, devs, what))
        except OSError as ex:
            counts['error'] += 1
            print('ERROR     %s : %s' % (r, ex))
    for o in orphans:
        if rel(o).startswith('.git/'):
            counts['git'] += 1
            print('GIT       %s : .git 안 · 원본 없음 — 사람이 확인(건드리지 않음)' % rel(o))
            continue
        counts['orphan'] += 1
        print('ORPHAN    %s : 원본 없음 — 남겨 둠(필요 없으면 지우기)' % rel(o))
    left = counts['git'] + counts['error']
    print('CONFLICTS files=%d groups=%d %s %.0fs%s' % (
        nfiles, len(groups), ' '.join('%s=%d' % kv for kv in counts.items()), time.time() - t0,
        '' if apply or not (groups or orphans) else ' (계획만 — --apply 로 실행)'))
    return 3 if left else 0


def manifest_files(manifest):
    """대조표의 T · U 파일 — [(상대 경로, 크기)] · 형식이 아니면 None"""
    with open(manifest, encoding='utf-8') as f:
        if not f.readline().startswith('# qvest_manifest v1'):
            return None
        return [(rel, int(size)) for kind, size, _, rel in (l.rstrip('\n').split('\t', 3) for l in f) if kind in ('T', 'U')]


_K32 = []


def pin_file(path):
    """파일 하나에 attrib +P -U — 0 = 됨, 아니면 Windows 오류 번호. 수만 개를 attrib 로 하나씩 띄우면 수십 분이라 속성을
    직접 쓴다(GetFileAttributesW → SetFileAttributesW · 11-03 메인 실측: attrib 와 같은 속성 · OneDrive 가 뒤에서 내려받음)"""
    if not _K32:
        from ctypes import wintypes
        k = ctypes.WinDLL('kernel32', use_last_error=True)
        k.GetFileAttributesW.argtypes = [wintypes.LPCWSTR]
        k.GetFileAttributesW.restype = wintypes.DWORD
        k.SetFileAttributesW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
        k.SetFileAttributesW.restype = wintypes.BOOL
        _K32.append(k)
    k, p = _K32[0], lp(path)
    a = k.GetFileAttributesW(p)
    if a == 0xFFFFFFFF:
        return ctypes.get_last_error() or 1
    if a & PINNED and not a & UNPINNED:
        return 0
    return 0 if k.SetFileAttributesW(p, (a | PINNED) & ~UNPINNED) else (ctypes.get_last_error() or 1)


def cmd_pin(root, excludes, essentials, margin_gb, apply, manifest=None, no_all=False):
    """이 기계에 '항상 유지' — 제외 폴더 밑으로는 attrib /S 를 걸지 않게 폴더 단위로 나눠 건다 · --files 의 대조표 파일은
    고른 폴더 밖이면 파일 단위로 건다"""
    t0 = time.time()
    root = os.path.abspath(root)
    base = lp(root)
    ex_rel = {e.strip('/').lower() for e in excludes if '/' in e.strip('/')}
    ex_name = {e.strip('/').lower() for e in excludes if '/' not in e.strip('/')}
    rel = lambda p: p[len(base) + 1:].replace('\\', '/')
    excluded = {}                                  # 제외 폴더 → (파일 수, 크기)

    def prune(path, name):
        r = rel(path)
        if name.lower() in ex_name or r.lower() in ex_rel:
            excluded[r] = None
            return True
        return False

    cloud, size, nfile = {}, {}, {}                # 상대 디렉터리('' = 루트) → 자기 바로 아래 파일 합
    dirs, nseen, tick = set(), 0, time.time()
    for d, files in walk(root, prune):
        r = rel(d) if d != base else ''
        dirs.add(r)
        nseen += len(files)
        if time.time() - tick > 20:
            tick = time.time()
            print('  ... %d files scanned, %.0fs' % (nseen, tick - t0), file=sys.stderr, flush=True)
        c = s = 0
        for e in files:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            s += st.st_size
            if getattr(st, 'st_file_attributes', 0) & CLOUD_ATTR:
                c += st.st_size
        cloud[r], size[r], nfile[r] = c, s, len(files)
    has_ex = {d: False for d in dirs}
    for x in excluded:
        p = x.rsplit('/', 1)[0] if '/' in x else ''
        while True:
            has_ex[p] = True
            if not p:
                break
            p = p.rsplit('/', 1)[0] if '/' in p else ''

    def under(r, tops):
        return any(r == t or r.startswith(t + '/') for t in tops)

    listed = []                                    # 대조표 파일 (상대 경로, 폴더('' = 루트), 크기, 클라우드 전용 크기)
    if manifest:
        mf = manifest_files(manifest)
        if mf is None:
            print('대조표 형식이 아님: %s' % manifest)
            return 2
        for r, n in mf:
            d = r.rsplit('/', 1)[0] if '/' in r else ''
            if d and (any(x in ex_name for x in d.lower().split('/')) or under(d.lower(), ex_rel)):
                continue
            try:
                st = os.stat(lp(os.path.join(root, r)))
            except OSError:
                continue
            listed.append((r, d, n, st.st_size if getattr(st, 'st_file_attributes', 0) & CLOUD_ATTR else 0))

    def outside(tops):                             # 고른 폴더가 덮지 않는 대조표 파일
        return [x for x in listed if not (under(x[1], tops) if x[1] else '' in tops)]

    def need(tops):
        return (sum(cloud[r] for r in dirs if r and under(r, tops)) + (cloud[''] if '' in tops else 0)
                + sum(x[3] for x in outside(tops)))

    top_all = sorted(r for r in dirs if r and '/' not in r)
    free = shutil.disk_usage(root).free
    margin = margin_gb * G
    core = [t for t in ('.git', '.venv_qvest_ml') if t in dirs]
    plans = [('essential', sorted(set(e for e in essentials if e in dirs) | set(core)) + ['']), ('core', core)]
    if not no_all:
        plans.insert(0, ('all', top_all + ['']))
    choice = None
    for label, tops in plans:
        if need(tops) + margin <= free:
            choice = (label, tops)
            break
    print('PIN root=%s free=%.1fGB margin=%dGB scan=%.0fs' % (root, free / G, margin_gb, time.time() - t0))
    for label, tops in plans:
        o = outside(tops)
        print('  plan %-9s download=%.1fGB%s%s' % (label, need(tops) / G,
              ' (대조표 파일 %d개 · %.2fGB 는 파일 단위)' % (len(o), sum(x[2] for x in o) / G) if manifest else '',
              '  <= 선택' if choice and choice[0] == label else ''))
    tot_cloud = sum(cloud.values())
    print('  total size=%.1fGB not-yet-local=%.1fGB · excluded=%s' % (sum(size.values()) / G, tot_cloud / G, ', '.join(sorted(excluded)) or '-'))
    if not choice:
        print('PIN SKIP — 빈 공간이 핵심(.git · venv)조차 담지 못함: 디스크를 비운 뒤 다시')
        return 3
    if not apply:
        print('(계획만 — --apply 로 실행)')
        return 0
    kids = {}
    for x in dirs:
        if x:
            kids.setdefault(x.rsplit('/', 1)[0] if '/' in x else '', []).append(x)
    cmds = []

    def pin_dir(r):
        p = os.path.join(root, *r.split('/')) if r else root
        if r:
            cmds.append([p])
        if not has_ex.get(r):
            if nfile.get(r) or kids.get(r):
                cmds.append([os.path.join(p, '*'), '/S', '/D'])
            return
        if nfile.get(r):
            cmds.append([os.path.join(p, '*')])    # 바로 아래 파일만 — 제외 폴더가 밑에 있다
        for c in sorted(kids.get(r, [])):
            pin_dir(c)

    for t in choice[1]:
        if t:
            pin_dir(t)
        elif nfile.get(''):
            cmds.append([os.path.join(root, '*')])  # 루트 바로 아래 파일
    fails = 0
    for a in cmds:
        r = subprocess.run(['attrib', '+P', '-U'] + a, capture_output=True)
        if r.returncode != 0:
            fails += 1
            if fails <= 10:
                msg = (r.stdout + r.stderr).decode('oem' if os.name == 'nt' else 'utf-8', 'replace').strip()
                print('  attrib %s : rc=%d %s' % (' '.join(a), r.returncode, msg[:160]))
    one = outside(choice[1])
    for x in one:
        e = pin_file(os.path.join(root, *x[0].split('/')))
        if e:
            fails += 1
            if fails <= 10:
                print('  pin %s : err=%d' % (x[0], e))
    print('PIN %s units=%d files=%d fails=%d %.0fs — OneDrive 가 뒤에서 내려받는다(작업 표시줄 아이콘)' % (
        choice[0], len(cmds), len(one), fails, time.time() - t0))
    return 0 if fails == 0 else 3


def main():
    for s in (sys.stdout, sys.stderr):              # 파이프로 받으면 cp949 — 한글 · 기호를 UTF-8 로 고정(호출 쪽도 UTF-8 로 읽는다)
        try:
            s.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description='Qvest two-machine OneDrive sync tool')
    sub = ap.add_subparsers(dest='cmd', required=True)
    w = sub.add_parser('write')
    w.add_argument('root')
    w.add_argument('out')
    c = sub.add_parser('compare')
    c.add_argument('root')
    c.add_argument('manifest')
    c.add_argument('--allow', action='append', default=[])
    c.add_argument('--report')
    c.add_argument('--show', type=int, default=40)
    k = sub.add_parser('conflicts')
    k.add_argument('root')
    k.add_argument('--device', action='append', default=[], required=True)
    k.add_argument('--winner', action='append', default=[])
    k.add_argument('--stash')
    k.add_argument('--apply', action='store_true')
    p = sub.add_parser('pin')
    p.add_argument('root')
    p.add_argument('--exclude', action='append', default=[])
    p.add_argument('--essential', action='append', default=[])
    p.add_argument('--files')
    p.add_argument('--no-all', action='store_true')
    p.add_argument('--margin-gb', type=int, default=25)
    p.add_argument('--apply', action='store_true')
    a = ap.parse_args()
    if not os.path.isdir(os.path.join(a.root, '.git')):
        print('.git 없음: %s' % a.root)
        return 2
    if a.cmd == 'write':
        return cmd_write(a.root, a.out)
    if a.cmd == 'compare':
        return cmd_compare(a.root, a.manifest, a.allow, a.report, a.show)
    if a.cmd == 'conflicts':
        return cmd_conflicts(a.root, a.device, a.winner, a.stash, a.apply)
    return cmd_pin(a.root, a.exclude, a.essential, a.margin_gb, a.apply, a.files, a.no_all)


if __name__ == '__main__':
    sys.exit(main())
