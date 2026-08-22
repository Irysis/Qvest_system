# -*- coding: utf-8 -*-
"""무인 런이 **알아낸 것**을 산출물에서 뽑는다 (2026-08-22, 도훈 지시).

왜 고쳤나:
  초판 완주 알림은 "정식 라운드 이어붙이기 한 건이 끝났습니다 / 다음 단계로 넘어갔습니다"
  처럼 **런 상태만** 날랐다. 도훈 지적 — "리서치에서 얻을 수 있는 인사이트는 없고,
  그저 완료했다는 얘기만 장황하게 온다."
  맞다. 완주 사실은 1줄이면 되고, 나머지는 **판정과 배운 것**이어야 한다.

★재료는 이미 있다:
  · `stage_artifacts/l_code/**/l_code_*.json` — `lesson_text`(배운 것) ·
    `mechanism_hypothesis`(왜) · `falsification_attempts`(어떻게 반증했나) · `grade`
  · `qepm/mailbox/worktask/<WT>/judge_package.json` — `verdict` · `hard_gate_summary` ·
    `beta_controlled_alpha` · `gate_results`
  · `alpha_package.json` — `hypothesis` · `research_verdict`
  L-code 가 **지식 적립 산출물**이므로 그것이 1순위다.

★범위 규약: **런 시작 시각 이후에 생성/수정된 것만** 본다.
  (오늘 하루 6번 틀린 그 실수 — 분모를 안 정하고 세면 남의 산출을 내 것으로 읽는다.)

사용:
  python research_insight_extract.py <root> <since_epoch> [--json out]
"""
import glob
import io
import json
import os
import re
import sys


def _load(p):
    try:
        with io.open(p, encoding='utf-8') as fh:
            return json.load(fh)
    except Exception:
        return None


def _s(x, n=400):
    """문자열 정리 — 길면 자르되 어디서 잘렸는지 표시."""
    if x is None:
        return ''
    t = re.sub(r'\s+', ' ', str(x)).strip()
    return t if len(t) <= n else t[:n - 1] + '…'


def collect(root, since):
    """since(epoch) 이후 생성·수정된 지식 산출물을 모은다."""
    out = {'lcodes': [], 'verdicts': [], 'since': since}

    # ── ① L-code (지식 적립 정본)
    for p in glob.glob(os.path.join(root, 'stage_artifacts', 'l_code', '*', 'l_code_*.json')):
        try:
            if os.path.getmtime(p) < since:
                continue
        except OSError:
            continue
        d = _load(p)
        if not isinstance(d, dict):
            continue
        out['lcodes'].append({
            'id': d.get('l_code') or os.path.basename(p),
            'strategy': d.get('strategy_id') or '',
            'family': d.get('family') or '',
            'grade': str(d.get('grade') or ''),
            'mode': d.get('research_mode') or '',
            'metric_type': d.get('metric_type') or '',
            'lesson': _s(d.get('lesson_text'), 460),
            'mechanism': _s(d.get('mechanism_hypothesis'), 300),
            'falsify': _s(d.get('falsification_attempts'), 260),
        })

    # ── ② judge 판정 (게이트 통과 여부와 그 이유)
    for p in glob.glob(os.path.join(root, 'qepm', 'mailbox', 'worktask', 'WT-*',
                                    'judge_package.json')):
        try:
            if os.path.getmtime(p) < since:
                continue
        except OSError:
            continue
        d = _load(p)
        if not isinstance(d, dict):
            continue
        hg = d.get('hard_gate_summary') or {}
        bca = d.get('beta_controlled_alpha') or {}
        gr = d.get('gate_results') or {}
        # 실패한 게이트의 사유 1개만
        fail_note = ''
        for k in sorted(gr):
            v = gr[k]
            if isinstance(v, dict) and str(v.get('result')).upper() == 'FAIL':
                fail_note = _s(v.get('note'), 300)
                break
        out['verdicts'].append({
            'wt': os.path.basename(os.path.dirname(p)),
            'verdict': d.get('verdict') or '',
            'grade': _s(d.get('grade_authoritative'), 40),
            'port_t': hg.get('port_t_hard'), 'oos': hg.get('oos_retention_hard'),
            'calmar': hg.get('calmar_hard'),
            't_alpha': bca.get('t_alpha_nw_lag3'), 'beta': bca.get('beta_to_bm'),
            'alpha_ann': bca.get('alpha_ann'),
            'fail_note': fail_note,
        })

    return out


def main(argv):
    if len(argv) < 2:
        sys.stderr.write('usage: research_insight_extract.py <root> <since_epoch> [--json out]\n')
        return 2
    root, since = argv[0], float(argv[1])
    res = collect(root, since)
    if '--json' in argv:
        try:
            io.open(argv[argv.index('--json') + 1], 'w', encoding='utf-8').write(
                json.dumps(res, ensure_ascii=False, indent=1))
        except Exception as e:
            sys.stderr.write('json 쓰기 실패: %s\n' % e)
    print(json.dumps(res, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
