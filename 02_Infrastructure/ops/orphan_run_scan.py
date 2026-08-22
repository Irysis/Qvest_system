# -*- coding: utf-8 -*-
"""무음 사망 런 탐지 — start 는 있는데 종료 기록이 없는 구간을 찾는다 (2026-08-22 신설).

왜 있나 (실사고 2026-08-22 18:30 런):
  qepm_dossier 런이 WT-D20260813_001 을 9일 만에 ALPHA_DONE 으로 올린 뒤(19:11~19:15)
  **19:29 이후 흔적 없이 사라졌다** — `claude -p exit=` 기록 0건, 완주 알림 미발화,
  락은 trap 이 정상 해제. 다음 런은 아무 이상을 못 느끼고 시작했다.
  ⇒ **런 하나가 통째로 증발한 사실이 어디에도 남지 않는다.**
  (원인은 실행 중 스크립트 편집으로 추정 — bash 는 바이트 오프셋으로 재개한다.)

★왜 정체 경보로는 못 잡나: 그 장치는 **살아서 매달린** 홀더를 겨눈다. 죽은 런은
  락을 반납하므로 다음 트리거가 경합을 만나지 않고, 따라서 검사 자체가 실행되지 않는다.
  '살아 매달림' 과 '죽어 증발' 은 **다른 축**이고 둘 다 필요하다.

★탐지 원리: 러너 로그는 하루치가 한 파일이다. `[tag] start` 와 그 뒤의 종료 기록
  (`claude -p exit=` / `skip` / `disabled`)을 짝짓고, **짝 없는 start** 를 센다.
  ⇒ 범위를 먼저 자른다(오늘 하루 4회 틀린 그 실수를 피한다): 각 start 부터
    다음 start 직전까지가 한 구간이고, 그 구간 안에서만 종료를 찾는다.

사용:
  python orphan_run_scan.py <root> [--days N] [--json out] [--status-line]
"""
import glob
import io
import json
import os
import re
import sys

START = re.compile(r'^(\S+)\s+\[([A-Za-z_]+)\]\s+start\b')
# 종료로 인정하는 신호 — 러너가 '끝났다' 고 말한 모든 형태
END = re.compile(r'\[([A-Za-z_]+)\]\s+(?:claude -p exit=|fallback\(opus\) exit=|'
                 r'DRYRUN|처리 결과:|해소:|alert marker)')


def scan_file(path):
    """한 로그 파일에서 (구간 start ts, tag, 종료여부, 마지막줄시각) 목록."""
    try:
        lines = io.open(path, encoding='utf-8', errors='replace').read().split('\n')
    except Exception:
        return []
    starts = []
    for i, ln in enumerate(lines):
        m = START.match(ln)
        if m:
            starts.append((i, m.group(1), m.group(2)))
    out = []
    for k, (i, ts, tag) in enumerate(starts):
        j = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        seg = lines[i:j]
        ended = any(END.search(x) for x in seg[1:])
        # 구간의 마지막 타임스탬프 (정체 판단용)
        last = ts
        for x in seg:
            mm = re.match(r'^(\d{4}-\d{2}-\d{2}T\S+)', x)
            if mm:
                last = mm.group(1)
        out.append({'ts': ts, 'tag': tag, 'ended': ended, 'last': last,
                    'lines': len(seg), 'file': os.path.basename(path)})
    return out


def main(argv):
    root = argv[0] if argv else '.'
    days = 14
    if '--days' in argv:
        days = int(argv[argv.index('--days') + 1])
    pat = os.path.join(root, '.cache', 'scheduler_logs', '*.log')
    files = sorted(glob.glob(pat))[-max(days * 6, 20):]

    runs = []
    for f in files:
        runs.extend(scan_file(f))

    # ★진행 중인 런을 무음 사망으로 세지 않는다 — 분모에 무엇이 들어가는지 먼저 정한다.
    #   (오늘 반복한 실수: 범위를 선언하지 않고 세면 수치가 답처럼 보인다.)
    #   판정: 구간 마지막 기록이 grace 분 이내면 '진행 중'으로 보류한다.
    import datetime
    grace = 90
    if '--grace' in argv:
        grace = int(argv[argv.index('--grace') + 1])
    now = datetime.datetime.now()

    def _age_min(ts):
        try:
            t = datetime.datetime.strptime(ts[:19], '%Y-%m-%dT%H:%M:%S')
            return (now - t).total_seconds() / 60.0
        except Exception:
            return 1e9

    inflight = [r for r in runs if not r['ended'] and _age_min(r['last']) < grace]
    orph = [r for r in runs if not r['ended'] and _age_min(r['last']) >= grace]
    for r in inflight:
        r['inflight'] = True
    by_tag = {}
    for r in orph:
        by_tag.setdefault(r['tag'], []).append(r)

    if '--status-line' in argv:
        if not orph:
            print("OrphanRuns: 무음 사망 0건%s"
                  % (" (진행 중 %d건 보류)" % len(inflight) if inflight else ""))
        else:
            top = sorted(by_tag.items(), key=lambda kv: -len(kv[1]))[:3]
            seg = " · ".join("%s %d" % (k, len(v)) for k, v in top)
            print("OrphanRuns: ★start 후 종료기록 없는 런 %d건 (%s) — 최근 %s"
                  % (len(orph), seg, max(r['ts'] for r in orph)[:16]))
        return 0

    print("스캔 로그 %d개 · 런 구간 %d개 (진행 중 %d건 보류, grace %d분)"
          % (len(files), len(runs), len(inflight), grace))
    print("★종료 기록 없는 런(무음 사망 의심): %d건" % len(orph))
    print()
    if orph:
        print("%-22s %-14s %-6s %s" % ("시작", "러너", "줄수", "구간 마지막 기록"))
        print("-" * 78)
        for r in sorted(orph, key=lambda x: x['ts'])[-25:]:
            print("%-22s %-14s %-6d %s" % (r['ts'][:19], r['tag'], r['lines'], r['last'][:19]))
        print()
        print("러너별:", ", ".join("%s %d" % (k, len(v)) for k, v in
                                   sorted(by_tag.items(), key=lambda kv: -len(kv[1]))))
    print()
    print("정상 종료: %d건" % (len(runs) - len(orph)))

    if '--json' in argv:
        out = argv[argv.index('--json') + 1]
        try:
            io.open(out, 'w', encoding='utf-8').write(
                json.dumps({'total': len(runs), 'orphan': len(orph), 'items': orph},
                           ensure_ascii=False, indent=1))
            print("→ %s" % out)
        except Exception as e:
            sys.stderr.write("json 쓰기 실패: %s\n" % e)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
