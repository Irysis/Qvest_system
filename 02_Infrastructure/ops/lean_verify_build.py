#!/usr/bin/env python3
# ★RETIRED (v10 2026-08-29 · 헤더 2026-09-03) — 무인 리서치 레인 퇴역: morning_run 에서 철거됐고
#   예약작업·bat 호출 0. 파일은 사료(08_Tests 가 경로로 직접 실행하므로 이동·삭제 금지).
#   재개 레시피 = git 태그 pre-v10-2layer 의 morning_run.sh [0.55]~[0.6] 구간.
# -*- coding: utf-8 -*-
#==============================================================================
# lean_verify_build.py — alpha-search 산출 디렉터리 → 최소 검증 JSON (v9 Lean Loop, 2026-08-23)
#
# 왜 있나:
#   구 체인은 검증 verdict 를 **프롬프트가 손으로 모았다**(L1~L3 수집 + L4 `claude -p`
#   충실성 검증자). 그 결과 판정 입력이 산문에서 만들어졌고, L4 는 31건 처리 동안
#   판정을 한 번도 바꾸지 않았다. v9 는 프롬프트에서 그 층을 떼고, 래퍼가 **산출물에서
#   기계로** 뽑는다. 이 파일이 그 추출기다.
#
# ★계약:
#   · 값은 전부 **산출물에서 읽은 것**이다. 없으면 필드를 **비운다**(추측·기본값 금지).
#     비어 있음은 auto_alpha_gate.R 에서 NA 로 읽히고, lean 모드에서는 "요구되지 않음"이다.
#   · `lean: true` 를 반드시 적는다 — 이 판정이 4층 전수가 아니라 축소 입력 위에서
#     나왔다는 사실이 판정과 함께 남아야 한다.
#
# 사용: lean_verify_build.py <stage_artifacts/alpha_search/<id> 디렉터리> [--out <path>]
# 출력: stdout 에 `KEY=VALUE` 줄들(래퍼가 파싱). 검증 JSON 은 디렉터리 안에 쓴다.
#==============================================================================
import csv
import io
import json
import os
import re
import sys

_ARXIV = re.compile(r'ar[xX]iv[:\s]*(\d{4}\.\d{4,5})', re.I)
_BARE = re.compile(r'(?<![\d.])(\d{4}\.\d{4,5})(?![\d.])')
_FQ = re.compile(r'\b(FQ-\d+[A-Za-z]?)\b')
_DOI = re.compile(r'\b(10\.\d{4,9}/[^\s"\'<>)\]]+)')


def _load(path):
    try:
        with io.open(path, 'r', encoding='utf-8-sig') as fh:
            return json.load(fh)
    except Exception:
        return None


def _num(x):
    try:
        v = float(x)
    except (TypeError, ValueError):
        return None
    return v if v == v else None      # NaN 제외


def _dig(o, *path):
    for k in path:
        if not isinstance(o, dict):
            return None
        o = o.get(k)
    return o


def port_t_from_compare(d):
    """`07_benchmark_compare.csv` 의 Portfolio_Alpha_t_NW_lag3 — forge/계약 정본 위치."""
    p = os.path.join(d, '07_benchmark_compare.csv')
    if not os.path.exists(p):
        return None
    try:
        with io.open(p, 'r', encoding='utf-8-sig', newline='') as fh:
            for row in csv.DictReader(fh):
                if (row.get('metric_name') or '').strip() == 'Portfolio_Alpha_t_NW_lag3':
                    return _num(row.get('strategy_value'))
    except Exception:
        return None
    return None


def derive_paper_id(man):
    """전략 산출물에서 논문 id 를 **역추출**한다.

    ★없는 것을 지어내지 않는다 — 못 찾으면 ('', 'not_found') 를 돌려주고, 호출자가
      `strategy_id` 폴백을 쓰되 그 사실을 `paper_id_source` 로 라벨한다.
    """
    hay = ' '.join(str(man.get(k) or '') for k in
                   ('strategy_idea', 'strategy_name', 'factor_engine_path', 'paper_id'))
    for rx, src in ((_ARXIV, 'arxiv_in_idea'), (_FQ, 'fq_in_idea'),
                    (_DOI, 'doi_in_idea'), (_BARE, 'bare_id_in_idea')):
        m = rx.search(hay)
        if m:
            return m.group(1), src
    return '', 'not_found'


def build(d, out=None):
    man = _load(os.path.join(d, 'strategy_manifest.json')) or {}
    hur = _load(os.path.join(d, 'hurdle_result.json')) or {}
    # ★v9.21 §1-c — 권위 등급(essence)의 산출물. run_alpha_search 의
    #   .authoritative_remeasure() 가 쓴다. 없으면 이 런은 계약을 안 거친 것이고,
    #   그 사실을 grade_basis 로 라벨한다(추측·기본값 금지 — 이 파일의 계약).
    aut = _load(os.path.join(d, 'authoritative_remeasure.json')) or {}
    if not man and not hur:
        return None

    v = {}
    v['lean'] = True
    v['lean_note'] = ('v9 Lean Loop — 검증 입력은 hurdle_result.json + strategy_manifest.json '
                      '실측만. L4 충실성 검증자(claude -p)는 폐지됐고, 값이 없는 층은 '
                      '"요구되지 않음"(NA)이지 "실패"가 아니다.')
    v['builder'] = 'lean_verify_build.py'
    v['source_dir'] = d.replace('\\', '/')

    pid, src = derive_paper_id(man)
    sid = man.get('strategy_id') or os.path.basename(os.path.normpath(d))
    v['strategy_id'] = sid
    v['paper_id'] = pid or sid
    v['paper_id_source'] = src if pid else 'strategy_id_fallback'

    # ── L1 pit — detect_lookahead 정적 스캔 결과. CLEAN 이 아니면 FALSE(관용 금지).
    pit_status = _dig(man, 'pit', 'status')
    if pit_status is not None:
        v['pit_pass'] = (str(pit_status).strip().upper() == 'CLEAN')
        v['pit_status'] = pit_status

    # ── L2 contract — bt_result 계약 audit. integrity FAIL 또는 audit_fail>0 이면 FALSE.
    bc = man.get('backtest_contract') or {}
    integ = bc.get('integrity_status')
    afail = bc.get('audit_fail')
    if integ is not None or afail is not None:
        ok = str(integ or '').strip().upper() != 'FAIL'
        if afail is not None:
            try:
                ok = ok and int(afail) == 0
            except (TypeError, ValueError):
                pass
        if str(bc.get('status') or '').strip().upper() not in ('', 'OK'):
            ok = False
        v['contract_pass'] = bool(ok)
        v['contract_integrity_status'] = integ
        v['contract_audit_fail'] = afail

    # ── L3 robustness — **산출물에 있을 때만** 적는다.
    #   hurdle_gate 의 oos 축(D062)이 essence 의 oos_retention 과 같은 양이다.
    #   구 L3 규칙(oos_retention >= 0.5, 자본 0.7 아님 — 오염 sanity)을 그대로 쓴다.
    #   ★권위 우선(v9.21 §1-c): essence.oos_retention 은 anchored 3분할 중앙값(v2)이고
    #     hurdle 의 oos 축은 그 proxy 다. 같은 양이므로 문턱 0.5 는 그대로 쓴다.
    oos = _num(_dig(aut, 'essence', 'oos_retention'))
    oos_src = 'authoritative_remeasure.essence.oos_retention (essence v2 median)'
    if oos is None:
        oos = _num(_dig(hur, 'score_breakdown', 'oos', 'value'))
        oos_src = 'hurdle_result.score_breakdown.oos.value (proxy)'
    if oos is not None:
        v['oos_retention'] = oos
        v['robustness_pass'] = bool(oos >= 0.5)
        v['robustness_basis'] = oos_src + ' >= 0.5 (screening sanity)'
    # (없으면 robustness_pass 를 **적지 않는다** → 게이트에서 NA → lean 상 요구되지 않음)

    # ── L4 fidelity — v9 에서 폐지. 필드를 만들지 않는다(그 자체가 "요구되지 않음").

    # ── 구조 탈락 + 지표
    if 'hard_fail' in hur:
        v['hard_fail'] = bool(hur.get('hard_fail'))
    fr = hur.get('fail_reasons')
    if isinstance(fr, list):
        fr = '; '.join(str(x) for x in fr)
    if fr:
        v['hard_fail_reason'] = fr
    # ── 등급: ★권위(essence) 우선, hurdle 은 진단 축으로 병기 (v9.21 §1-c)
    #   hurdle_gate 는 2026-05-31 에 이미 DEMOTED(authoritative=FALSE ·
    #   grade_basis='proxy_diagnostic_18component') 됐다. 그런데 이 추출기는 그 강등된
    #   등급을 `grade` 로 내보내 auto_alpha_gate 의 등급 바닥이 proxy 위에서 돌았다.
    #   ⇒ 축을 이름으로 가른다: grade=권위 · grade_proxy=진단. grade_basis 가 출처를 못박는다.
    if hur.get('total_score') is not None:
        v['score'] = hur.get('total_score')
    if hur.get('grade') is not None:
        v['grade_proxy'] = hur.get('grade')          # hurdle 18-component (진단)
    if aut.get('essence_grade') is not None:
        v['grade'] = aut.get('essence_grade')
        v['grade_basis'] = 'essence_score(authoritative_remeasure.json)'
        if aut.get('metric_type') is not None:
            v['grade_metric_type'] = aut.get('metric_type')
    elif hur.get('grade') is not None:
        # 권위 등급이 없다 = 계약 미경유(구 산출물 또는 백테 실패). **비우지 않고 라벨한다** —
        # 비우면 게이트에서 '요구되지 않음'이 되어 등급 바닥이 조용히 사라진다.
        v['grade'] = hur.get('grade')
        v['grade_basis'] = 'hurdle_gate(proxy — 권위 등급 부재)'
    elif _dig(man, 'verdict', 'grade') is not None:
        v['grade'] = _dig(man, 'verdict', 'grade')
        v['grade_basis'] = 'strategy_manifest.verdict(proxy)'

    # ── ★구조 낙폭 라벨을 게이트까지 옮긴다 (2026-08-24 도훈 지시의 필수 짝)
    #   MDD 는 등급을 접지 않게 됐다. 그러면 구조 후보가 등급으로는 안 걸리는데,
    #   **어디로 보낼지**를 정할 근거도 같이 사라지면 안 된다. essence 가 남긴
    #   structural_drawdown 라벨을 여기서 옮겨 적어 auto_alpha_gate 가 SCREEN_TIER 로
    #   라우팅할 수 있게 한다(hurdle 의 structural_dd 와 **독립 근거**, OR 가산).
    if aut.get('structural_drawdown') is not None:
        v['essence_structural_drawdown'] = bool(aut.get('structural_drawdown'))
    if aut.get('hard_fail_source') is not None:
        v['essence_hard_fail_source'] = aut.get('hard_fail_source')

    met = hur.get('metrics') or man.get('metrics') or {}
    for src_k, dst_k in (('MDD', 'mdd'), ('Calmar', 'calmar'),
                         ('Turnover_Ann', 'turnover'), ('Sharpe', 'sharpe'),
                         ('CAGR', 'cagr'), ('IR', 'ir')):
        val = _num(met.get(src_k))
        if val is not None:
            v[dst_k] = val

    pt = port_t_from_compare(d)
    if pt is None:
        pt = _num(_dig(man, 'authoritative', 'portfolio_alpha_t_nw_lag3'))
    if pt is not None:
        v['port_t'] = pt

    sr = _dig(hur, 'screening', 'screen_route')
    if sr and str(sr).strip().upper() != 'NONE':
        v['screen_route_hint'] = sr
    if _dig(hur, 'screening', 'screen_pass') is not None:
        v['screen_pass'] = bool(_dig(hur, 'screening', 'screen_pass'))
    # [2026-08-23 v9.1 / S2b] `hard_fail=false` 인데 `hard_fail_reason` 에 구조 낙폭 문장이
    #   남는 **새 상태**를 게이트 원장에서 구분 가능하게 병기한다. ★`hard_fail_reason` 키
    #   이름은 바꾸지 않는다 — 검사기 6개가 그 이름을 읽는다.
    if _dig(hur, 'screening', 'structural_dd') is not None:
        v['structural_dd'] = bool(_dig(hur, 'screening', 'structural_dd'))

    path = out or os.path.join(d, 'auto_verify_lean.json')
    tmp = path + '.tmp'
    with io.open(tmp, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(json.dumps(v, ensure_ascii=False, indent=2) + '\n')
    os.replace(tmp, path)
    v['_path'] = path
    return v


def main(argv):
    if not argv:
        sys.stderr.write('usage: lean_verify_build.py <alpha_search dir> [--out <path>]\n')
        return 2
    d = argv[0]
    out = None
    if '--out' in argv:
        i = argv.index('--out')
        if i + 1 < len(argv):
            out = argv[i + 1]
    if not os.path.isdir(d):
        print('STATUS=no_dir')
        return 1
    v = build(d, out)
    if v is None:
        # 산출물이 없다 = 그 런은 백테까지 못 갔다. 판정 대상이 아니다(0 으로 삼키지 않고 라벨).
        print('STATUS=no_artifacts')
        return 1
    print('STATUS=ok')
    print('VERIFY_PATH=%s' % v['_path'].replace('\\', '/'))
    print('PAPER_ID=%s' % v['paper_id'])
    print('PAPER_ID_SOURCE=%s' % v['paper_id_source'])
    print('STRATEGY_ID=%s' % v['strategy_id'])
    print('GRADE=%s' % (v.get('grade') if v.get('grade') is not None else ''))
    print('PORT_T=%s' % (v.get('port_t') if v.get('port_t') is not None else ''))
    print('SCREEN_ROUTE_HINT=%s' % (v.get('screen_route_hint') or ''))
    print('GRADE_BASIS=%s' % (v.get('grade_basis') or ''))
    print('GRADE_PROXY=%s' % (v.get('grade_proxy') if v.get('grade_proxy') is not None else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
