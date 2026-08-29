# -*- coding: utf-8 -*-
"""paper_registry.json paper_key 백필 (v10 2026-08-29 신설 — 도훈 지시 "중복 수집 방지 규칙").

무엇을 하나:
  registry 전건(619+)에 `arxiv_id` / `doi` / `title_hash` / `paper_key` 4필드를 채운다.
  키 규약 정본은 `02_Infrastructure/ops/paper_id_norm.py::paper_key()` — 여기서 재구현하지 않는다.

  · arxiv_id 역산 순서: source URL → path 파일명(`MCP_2608_25223.pdf` → `2608.25223`).
  · 기존 중복(같은 paper_key 2건 이상)은 **삭제하지 않고** 뒤 항목에 `duplicate_of` 를
    표기한다(첫 항목 id). 리포트 = `stage_artifacts/paper_recharge/registry_dedup_report.json`.
  · 멱등: 이미 채워진 필드는 보존한다. 재실행해도 diff 0.
  · 원자 쓰기(tmp + os.replace) + 쓰기 직전 재파싱 검증 (paper_id_norm append 계약 미러).

실행:
  "$QVEST_PY" 02_Infrastructure/tools/paper_registry_backfill.py [--dry-run]
"""
import io
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(os.path.dirname(_HERE))
sys.path.insert(0, os.path.join(_ROOT, '02_Infrastructure', 'ops'))

from paper_id_norm import (paper_key, arxiv_id_from, norm_doi, title_hash,
                           _atomic_write)  # noqa: E402

_REG = os.path.join(_ROOT, '06_Registry', 'paper_registry.json')
_REPORT = os.path.join(_ROOT, 'stage_artifacts', 'paper_recharge',
                       'registry_dedup_report.json')
# 파일명 arXiv id: MCP_2608_25223.pdf / MCP_2202_03012v2.pdf
_PATH_ID = re.compile(r'MCP_(\d{4})_(\d{4,5})(v\d+)?\.pdf$', re.I)


def _arxiv_from_path(path):
    m = _PATH_ID.search(str(path or ''))
    if not m:
        return ''
    return '%s.%s' % (m.group(1), m.group(2))  # 버전 접미는 버린다(정본 규약 3조)


def backfill(entries):
    """엔트리 목록을 제자리 갱신하고 (n_filled, dupes) 반환."""
    n_filled = 0
    seen = {}    # paper_key → 첫 등장 항목 id
    dupes = []   # [{key, first_id, dup_id, dup_title}]
    for e in entries:
        if not isinstance(e, dict):
            continue
        changed = False
        if not str(e.get('arxiv_id') or '').strip():
            ax = arxiv_id_from(e.get('source')) or _arxiv_from_path(e.get('path'))
            if ax:
                e['arxiv_id'] = ax
                changed = True
        if not str(e.get('doi') or '').strip():
            d = norm_doi(e.get('source'))
            if d:
                e['doi'] = d
                changed = True
        if not str(e.get('title_hash') or '').strip():
            th = title_hash(e.get('title'))
            if th:
                e['title_hash'] = th
                changed = True
        if not str(e.get('paper_key') or '').strip():
            pk = paper_key(arxiv_id=e.get('arxiv_id'), doi=e.get('doi'),
                           title=e.get('title'), source_url=e.get('source'))
            if pk:
                e['paper_key'] = pk
                changed = True
        if changed:
            n_filled += 1
        pk = str(e.get('paper_key') or '').strip()
        if pk:
            if pk in seen:
                if not str(e.get('duplicate_of') or '').strip():
                    e['duplicate_of'] = seen[pk]
                dupes.append({'key': pk, 'first_id': seen[pk],
                              'dup_id': e.get('id'),
                              'dup_title': e.get('title')})
            else:
                seen[pk] = e.get('id')
    return n_filled, dupes


def main(argv):
    dry = '--dry-run' in argv
    with io.open(_REG, 'r', encoding='utf-8-sig') as fh:
        entries = json.load(fh)
    if not isinstance(entries, list):
        raise SystemExit('paper_registry.json 최상위가 배열이 아닙니다')

    n_before = len(entries)
    n_filled, dupes = backfill(entries)
    n_keyed = sum(1 for e in entries
                  if isinstance(e, dict) and str(e.get('paper_key') or '').strip())

    print('[backfill] entries=%d · 갱신 %d건 · paper_key 보유 %d건 · 중복 %d쌍%s'
          % (n_before, n_filled, n_keyed, len(dupes),
             ' (dry-run — 쓰기 없음)' if dry else ''))
    for d in dupes[:20]:
        print('  dup %s : %s ← %s (%s)' % (d['key'], d['first_id'],
                                           d['dup_id'],
                                           str(d['dup_title'])[:60]))
    if len(dupes) > 20:
        print('  … 외 %d쌍 (리포트 참조)' % (len(dupes) - 20))

    if dry:
        return 0

    # 재파싱 검증 후 원자 쓰기 (registry + 리포트)
    checked = json.loads(json.dumps(entries, ensure_ascii=False))
    if len(checked) != n_before:
        raise SystemExit('검증 실패: 항목 수가 변했다 (%d → %d)'
                         % (n_before, len(checked)))
    _atomic_write(_REG, json.dumps(checked, ensure_ascii=False, indent=2) + '\n')

    os.makedirs(os.path.dirname(_REPORT), exist_ok=True)
    import datetime
    _atomic_write(_REPORT, json.dumps({
        'generated_at': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'n_entries': n_before, 'n_filled': n_filled, 'n_keyed': n_keyed,
        'n_dupes': len(dupes), 'dupes': dupes,
        'note': '중복은 삭제하지 않고 duplicate_of 로만 표기 (도훈 열람용)',
    }, ensure_ascii=False, indent=2) + '\n')
    print('[backfill] 완료 — 리포트: %s' % os.path.relpath(_REPORT, _ROOT))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
