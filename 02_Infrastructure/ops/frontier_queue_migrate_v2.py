#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#==============================================================================
# frontier_queue_migrate_v2.py — alpha_frontier_queue v1.0 → v2.0 (v9 Lean Loop §3.4(f))
#
# 무엇을 고치나:
#   `status` 가 **자유서술**이라 251건에 서로 다른 값이 **137종** 들어 있다. 그래서
#   "지금 착수 가능한 항목이 몇 개인가" 를 **기계가 답할 수 없다** — 소비자는 문자열을
#   눈으로 읽어야 하고, 읽는 사람마다 답이 다르다. 큐가 있는데 큐 역할을 못 한다.
#
# 어떻게:
#   ① `status` 를 enum {open, claimed, done, parked} 로 **접고**, 원문은 `status_raw` 에
#      **전부 보존**한다(정보 손실 0 — 접는 것이지 버리는 것이 아니다).
#   ② 알파 가설과 **인프라 항목**을 분리한다(`infra_backlog.json`). 섞여 있으면
#      "다음 알파 라운드가 무엇인가" 를 물었을 때 배선 태스크가 함께 나온다.
#   ③ 종결(done)분은 `_archive/` 로 옮겨 살아 있는 큐를 100건 이하로 만든다.
#
# ★접기 규칙은 **토큰 매칭**이고, 규칙이 애매한 자리는 전부 리포트로 노출한다:
#   · `conflicts` — done 토큰과 open 토큰이 **한 status 에 공존**(`..._negative_frontier_open`).
#     이 저장소의 INV-7 관용구다: "측정은 음성인데 방향은 열려 있다". done 으로 접으면
#     열린 프론티어 15건이 통째로 묻히므로 **open 이 이긴다** — 그 사실을 세어서 보고한다.
#   · `residual_open` — done/parked/open 어느 토큰도 없어 **기본값 open** 으로 떨어진 원문.
#     기본값은 판정이 아니라 미판정이므로, 사람이 눈으로 확인할 목록으로 따로 낸다.
#
# 사용:
#   frontier_queue_migrate_v2.py --dry-run     # 표만 출력, 파일 무변경
#   frontier_queue_migrate_v2.py               # 실제 마이그레이션
#   frontier_queue_migrate_v2.py --root <path> # 저장소 루트 지정(검사용)
#==============================================================================
import io
import json
import os
import re
import sys
from collections import Counter, OrderedDict

STATUS_ENUM = ('open', 'claimed', 'done', 'parked')

# ── 토큰 사전 (v9 Lean Loop 확정) ─────────────────────────────────────────────
DONE_TOKENS = ('done', 'measured', 'settled', 'negative', 'closed', 'consumed',
               'established', 'characterized', 'explored', 'quarantine',
               'reversed', 'exhausted', 'superseded', 'kill')
PARKED_TOKENS = ('blocked', 'deprioritized', 'capacity_wait', 'dohoon', 'data_gate',
                 'awaiting', 'needs', 'parked', 'deferred', 'inconclusive',
                 'key_gated', 'hold')
# open 토큰 — done 과 공존하면 **이쪽이 이긴다**(INV-7 관용구 보존, 위 서문 참조).
OPEN_TOKENS = ('open',)

# ── 인프라 분리 축 ───────────────────────────────────────────────────────────
INFRA_LANES = {'pipeline', 'paper_lane', 'infra_guard', 'infra_measurement_integrity',
               'measurement_integrity', 'methodology_repair', 'consume_surface',
               'reclassify', 'recovery'}
# ★`감사` 는 부정 전방탐색을 단다 — `감사의견`/`감사보고서` 는 **DART 공시 필드**(auditor's
#   opinion)이고 알파 재료다. 실측: 전방탐색 없이 돌리면 FQ-004("DART 담보/질권 + 감사의견/
#   going-concern") · FQ-022("담보/질권·감사의견 metadata census") 두 건이 인프라로 잘못
#   빠졌다 — 둘 다 `lane=non_return` 즉 v8.4 가 명시한 알파 원천이다. 인프라 축의 '감사' 는
#   하네스 감사를 뜻하므로, 회계 감사어를 제외해야 그 뜻이 유지된다.
INFRA_TITLE_RX = re.compile(r'(배선|하네스|훅|스키마|원장|인덱스|큐 소비|파이프라인|감사(?!의견|보고서)|어댑터)')

CONSUME_RULE_V2 = (
    "착수 전: hypothesis_index lookup → 본 큐 확인 → status/owner 갱신. "
    "★status 는 enum 4종만 쓴다 — open(착수 가능) / claimed(다른 세션이 잡음, 착수 금지) / "
    "done(종결, 살아 있는 큐에는 남지 않음 — 06_Registry/_archive/ 로 이동) / "
    "parked(착수 불가, 사유는 parked_reason). 원문 서술은 status_raw 에 보존되며 "
    "**판정에 쓰지 않는다**(자유서술 137종이 큐를 기계가 못 읽게 만든 것이 v2 의 사유다). "
    "★parked_reason=dohoon_decision / dohoon_data_work 는 **세션 임의 착수 금지** — "
    "구 규약의 '도훈 결정 항목' 이 enum 으로 보존된 자리다. "
    "★claim 규약: open 인 항목만 집을 수 있고, 집으면 status=claimed + owner 를 자기 세션으로 "
    "갱신한 뒤 시작한다. 신규 ID 는 하드코딩 금지 — 최대 번호+1 계산 후 재읽기로 존재 확인. "
    "★인프라 항목은 이 파일에 없다 — 06_Registry/infra_backlog.json 을 볼 것."
)


def _load(path):
    with io.open(path, 'r', encoding='utf-8-sig') as fh:
        return json.load(fh, object_pairs_hook=OrderedDict)


def _detect_eol(path):
    try:
        with io.open(path, 'rb') as fh:
            return '\r\n' if b'\r\n' in fh.read(4096) else '\n'
    except Exception:
        return '\n'


def _write(path, obj, eol='\r\n'):
    """정본 형식 = indent 2 · ensure_ascii False · 기존 줄끝 유지.

    무수정 왕복이 **바이트 동일**임을 2026-08-23 실측으로 확인했다
    (917,818B 원본 ↔ indent=2 재직렬화 912,340B + CRLF 5,478 = 동일).
    """
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    tmp = path + '.tmp'
    with io.open(tmp, 'w', encoding='utf-8', newline=eol) as fh:
        fh.write(json.dumps(obj, ensure_ascii=False, indent=2))
    os.replace(tmp, path)


def _txt(e, *keys):
    return ' '.join(str(e.get(k) or '') for k in keys)


def _match(hay, tokens):
    low = hay.lower()
    for t in tokens:
        if t in low:
            return t
    return None


def classify(e):
    """엔트리 1건 → (status, parked_reason|None, note).

    note ∈ {'', 'conflict_open_over_done', 'residual_default_open'} — 애매한 자리의 라벨.
    """
    raw = str(e.get('status') or '')
    owner = str(e.get('owner') or '') if not isinstance(e.get('owner'), (dict, list)) \
        else json.dumps(e.get('owner'), ensure_ascii=False)

    done_tok = _match(raw, DONE_TOKENS)
    open_tok = _match(raw, OPEN_TOKENS)
    parked_tok = _match(raw, PARKED_TOKENS) or _match(owner, PARKED_TOKENS)

    # ① done ∧ open 공존 = INV-7 관용구("음성이지만 방향은 열려 있다") → open 이 이긴다.
    if done_tok and open_tok:
        return 'open', None, 'conflict_open_over_done'
    if done_tok:
        return 'done', None, ''
    if parked_tok:
        reason = parked_tok
        if parked_tok == 'dohoon':
            blob = (raw + ' ' + owner).lower()
            reason = 'dohoon_data_work' if 'data_work' in blob else 'dohoon_decision'
        return 'parked', reason, ''
    if 'CLAIMED' in owner and 'UNCLAIMED' not in owner:
        return 'claimed', None, ''
    if 'CLAIMED' in raw and 'UNCLAIMED' not in raw:
        return 'claimed', None, ''
    if open_tok:
        return 'open', None, ''
    return 'open', None, 'residual_default_open'


def is_infra(e):
    lane = str(e.get('lane') or '').strip()
    kind = str(e.get('kind') or '').strip()
    if lane in INFRA_LANES:
        return True, 'lane=%s' % lane
    if kind.startswith('infra_'):
        return True, 'kind=%s' % kind
    if INFRA_TITLE_RX.search(str(e.get('title') or '')):
        return True, 'title_rx=%s' % INFRA_TITLE_RX.search(str(e.get('title') or '')).group(1)
    return False, ''


def migrate(root, dry_run=True, stamp='20260823'):
    qpath = os.path.join(root, '06_Registry', 'alpha_frontier_queue.json')
    Q = _load(qpath)
    eol = _detect_eol(qpath)
    entries = Q.get('entries') or []

    rep = {
        'generated_at': stamp,
        'source': '06_Registry/alpha_frontier_queue.json',
        'source_entries': len(entries),
        'source_distinct_raw_status': len({str(e.get('status') or '') for e in entries}),
        'mapping': {'done_tokens': list(DONE_TOKENS), 'parked_tokens': list(PARKED_TOKENS),
                    'open_tokens': list(OPEN_TOKENS), 'enum': list(STATUS_ENUM)},
        'infra_split': {'lanes': sorted(INFRA_LANES), 'title_regex': INFRA_TITLE_RX.pattern,
                        'kind_prefix': 'infra_'},
    }
    by_status = Counter()
    by_lane = Counter()
    by_parked_reason = Counter()
    infra_by_reason = Counter()
    conflicts, residual, title_rx_hits = [], [], []
    alpha_live, alpha_done, infra = [], [], []

    for e in entries:
        st, reason, note = classify(e)
        inf, why = is_infra(e)
        new = OrderedDict()
        for k, v in e.items():
            new[k] = v
            if k == 'status':
                new['status'] = st
                new['status_raw'] = str(v or '')
                if reason:
                    new['parked_reason'] = reason
        if 'status' not in new:                      # status 키가 없던 항목 방어
            new['status'] = st
            new['status_raw'] = ''
            if reason:
                new['parked_reason'] = reason

        by_status[st] += 1
        by_lane[str(e.get('lane') or '(none)')] += 1
        if reason:
            by_parked_reason[reason] += 1
        if note == 'conflict_open_over_done':
            conflicts.append({'id': e.get('id'), 'status_raw': str(e.get('status') or '')})
        elif note == 'residual_default_open':
            residual.append({'id': e.get('id'), 'status_raw': str(e.get('status') or ''),
                             'lane': e.get('lane')})

        if inf:
            infra_by_reason[why.split('=')[0]] += 1
            new['infra_reason'] = why
            if why.startswith('title_rx'):
                # ★제목 정규식은 인프라 판정의 **가장 약한 축**이다(lane 선언과 달리 저자의
                #   의도가 아니라 어휘를 본다). 전건을 리포트에 실어 사람이 되돌릴 수 있게 한다 —
                #   `infra_reason` 한 필드로 필터되므로 되돌리기는 한 줄이다.
                title_rx_hits.append({'id': e.get('id'), 'lane': e.get('lane'),
                                      'matched': why.split('=', 1)[1],
                                      'title': str(e.get('title') or '')[:100]})
            infra.append(new)
        elif st == 'done':
            alpha_done.append(new)
        else:
            alpha_live.append(new)

    rep['by_status'] = dict(by_status)
    rep['by_lane'] = dict(by_lane.most_common())
    rep['by_parked_reason'] = dict(by_parked_reason)
    rep['infra_split_counts'] = {'total': len(infra), 'by_axis': dict(infra_by_reason)}
    rep['conflicts_open_over_done'] = conflicts
    rep['residual_default_open'] = residual
    rep['infra_by_title_regex'] = title_rx_hits
    rep['outputs'] = {'alpha_live': len(alpha_live), 'alpha_done_archived': len(alpha_done),
                      'infra_backlog': len(infra)}
    assert len(alpha_live) + len(alpha_done) + len(infra) == len(entries), '항목 소실'

    if dry_run:
        return rep, None

    # ── 실제 쓰기 ────────────────────────────────────────────────────────────
    arch_dir = os.path.join(root, '06_Registry', '_archive')

    newQ = OrderedDict()
    for k, v in Q.items():
        if k == 'schema_version':
            newQ[k] = '2.0'
        elif k == 'consume_rule':
            newQ[k] = CONSUME_RULE_V2
        elif k == 'updated':
            newQ[k] = '2026-08-23'
        elif k == 'entries':
            newQ[k] = alpha_live
        else:
            newQ[k] = v
    newQ['migrated_from'] = 'schema 1.0 (자유서술 status %d종) — %s' % (
        rep['source_distinct_raw_status'], 'frontier_queue_migrate_v2.py')
    newQ['archive_refs'] = {
        'done': '06_Registry/_archive/alpha_frontier_queue_done_%s.json' % stamp,
        'infra': '06_Registry/infra_backlog.json',
        'report': '06_Registry/_archive/frontier_migration_report_%s.json' % stamp,
    }
    _write(qpath, newQ, eol)

    _write(os.path.join(root, '06_Registry', 'infra_backlog.json'), OrderedDict([
        ('schema_version', '2.0'),
        ('sot', '02_Infrastructure/docs/qvest_v8_3_alpha_discovery_sot.md §4 (인프라 분리는 v9 Lean Loop §3.4(f))'),
        ('updated', '2026-08-23'),
        ('purpose', '알파 큐에서 분리한 **인프라·하네스·배선** 항목. 알파 라운드 자원 배분의 '
                    '기본값은 알파 전진이고(CLAUDE.md 존재의의), 인프라는 ①알파 라운드를 실제로 '
                    '막는 결함 ②측정 신뢰를 훼손하는 결함에 한정해 즉시 수리한다. 그 외는 여기서 대기.'),
        ('consume_rule', CONSUME_RULE_V2),
        ('split_axis', rep['infra_split']),
        ('entries', infra),
    ]), eol)

    _write(os.path.join(arch_dir, 'alpha_frontier_queue_done_%s.json' % stamp), OrderedDict([
        ('schema_version', '2.0'),
        ('archived_at', '2026-08-23'),
        ('note', '살아 있는 큐(alpha_frontier_queue.json)에서 옮긴 **종결(done)** 알파 항목. '
                 '삭제가 아니라 이동이다 — 원문 서술은 status_raw 에 그대로 있고, INV-7 상 '
                 '부활 조건이 발화하면 여기서 되살린다.'),
        ('source', '06_Registry/alpha_frontier_queue.json (schema 1.0)'),
        ('entries', alpha_done),
    ]), eol)

    _write(os.path.join(arch_dir, 'frontier_migration_report_%s.json' % stamp), rep, eol)
    return rep, newQ


def render(rep):
    out = []
    a = out.append
    a('== frontier_queue_migrate_v2 — dry run ==')
    a('원본: %s  entries=%d  자유서술 status %d종'
      % (rep['source'], rep['source_entries'], rep['source_distinct_raw_status']))
    a('')
    a('-- 접힌 status (enum) --')
    for k in STATUS_ENUM:
        a('  %-8s %4d' % (k, rep['by_status'].get(k, 0)))
    a('  %-8s %4d' % ('TOTAL', sum(rep['by_status'].values())))
    a('')
    a('-- parked 사유 --')
    for k, v in sorted(rep['by_parked_reason'].items(), key=lambda x: -x[1]):
        a('  %-18s %4d' % (k, v))
    a('')
    a('-- lane 별 (상위 20) --')
    for i, (k, v) in enumerate(rep['by_lane'].items()):
        if i >= 20:
            a('  ... (%d lanes 더)' % (len(rep['by_lane']) - 20))
            break
        a('  %-34s %4d' % (k[:34], v))
    a('')
    a('-- 인프라 분리 --')
    a('  총 %d건  축별: %s' % (rep['infra_split_counts']['total'],
                              rep['infra_split_counts']['by_axis']))
    a('  ★제목 정규식으로만 편입된 항목 (판정의 가장 약한 축 — 사람 확인 대상, %d건):'
      % len(rep['infra_by_title_regex']))
    for h in rep['infra_by_title_regex']:
        a('    %-8s [%s] %-24s %s' % (h['id'], h['matched'], str(h['lane'])[:24], h['title'][:62]))
    a('')
    a('-- ★conflict: done 토큰 ∧ open 토큰 공존 → open 이 이긴다 (%d건) --'
      % len(rep['conflicts_open_over_done']))
    for c in rep['conflicts_open_over_done'][:20]:
        a('  %-9s %s' % (c['id'], c['status_raw'][:82]))
    if len(rep['conflicts_open_over_done']) > 20:
        a('  ... (%d건 더)' % (len(rep['conflicts_open_over_done']) - 20))
    a('')
    a('-- ★residual: open 토큰 없이 기본값 open 으로 떨어진 원문 (%d건) — 사람 확인 대상 --'
      % len(rep['residual_default_open']))
    for c in rep['residual_default_open']:
        a('  %-9s %-26s %s' % (c['id'], str(c.get('lane'))[:26], c['status_raw'][:60]))
    a('')
    a('-- 산출 예정 --')
    a('  06_Registry/alpha_frontier_queue.json                    alpha live  %4d'
      % rep['outputs']['alpha_live'])
    a('  06_Registry/infra_backlog.json                           infra       %4d'
      % rep['outputs']['infra_backlog'])
    a('  06_Registry/_archive/alpha_frontier_queue_done_*.json    alpha done  %4d'
      % rep['outputs']['alpha_done_archived'])
    a('  06_Registry/_archive/frontier_migration_report_*.json    (본 리포트)')
    return '\n'.join(out)


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if '--root' in argv:
        root = argv[argv.index('--root') + 1]
    dry = '--dry-run' in argv
    rep, _ = migrate(root, dry_run=dry)
    print(render(rep))
    if not dry:
        print('')
        print('== 실행 완료 — 위 표는 실제 적용된 분류다 ==')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
