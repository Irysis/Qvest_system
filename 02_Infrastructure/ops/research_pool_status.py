#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#==============================================================================
# research_pool_status.py — 페이퍼 적재 리서치풀 인지 리더 (Qvest v8.1.3)
#
# 목적: bootstrap.sh(/qvest)이 매 부팅 시 페이퍼 적재 파이프라인
#       (paper_recharge → router → dispatch)이 만든 *신규 리서치풀*을 인지하도록
#       stage_artifacts/paper_recharge/ 산출물을 요약한다.
#
#   - 라우팅 산출(alpha_search_route_<date>.json): route 분포 + 팩터 후보
#   - alpha 큐(alpha_search_queue_<date>.json): alpha-search 대기 testable 후보
#   - mode 큐(mode_queue_<date>.json): optimizer/risk/regime = QEPM 연료
#   - dispatch(research_status_<date>.json): 큐 소비 여부
#   - factor recheck(factor_recheck_queue/done): tier-2 잔여
#   - collection vs routing 날짜 비교: 수집은 됐으나 라우터 미반영 = "라우팅 대기"
#   - .cache/research_pool_last_seen.json 마커로 직전 부팅 이후 NEW 여부 판정
#
# 설계: fail-soft. 어떤 오류도 부팅을 중단시키지 않는다(항상 exit 0, 한 줄 SKIP).
#       날짜 파싱은 파일명 8자리(YYYYMMDD) 기준 — 가장 최신 stamp를 선택.
#
# Usage:
#   python3 research_pool_status.py [PROJECT_ROOT] [--json] [--mark]
#     PROJECT_ROOT  생략 시 env QM_ROOT / CLAUDE_PROJECT_DIR / cwd 순.
#     --json        기계 판독용 JSON 1개 출력(부팅 표시 대신).
#     --mark        표시 후 last_seen 마커를 최신 route 날짜로 갱신(부팅이 인지 처리).
#==============================================================================
import os
import re
import sys
import json
import glob
import datetime
import collections   # (2026-07-26 RPS-06) papers[].source 분해 파생용

#──────────────────────────────────────────────────────────────────────────────
# (2026-08-02 RPS-09/10/11) 술어 정본 import — 재구현 금지.
#   이 리더의 세 축(AlphaQueue testable · recheck잔여 · mode_queue)이 전부, 소비자 측에서
#   이미 수리된 술어를 **여기서 다시 얕게 구현**하고 있었다. 그래서 소비자는 맞고 리더만
#   틀린 상태가 됐다(08-02 실측: 리더 route 2 / 참값 1, 리더 recheck 3 / 참값 0).
#   → 정의를 research_pool_predicates.py 한 곳으로 모으고 여기선 호출만 한다.
#   sibling import — 이 파일과 같은 디렉터리(02_Infrastructure/ops/)에 있다.
_OPS_DIR = os.path.dirname(os.path.abspath(__file__))
if _OPS_DIR not in sys.path:
    sys.path.insert(0, _OPS_DIR)
try:
    import research_pool_predicates as RPP
except Exception:          # fail-soft: 부팅 중단 금지. render 가 사유를 세운다.
    RPP = None
#──────────────────────────────────────────────────────────────────────────────

STAGE_REL = os.path.join("stage_artifacts", "paper_recharge")
MARKER_REL = os.path.join(".cache", "research_pool_last_seen.json")
_DATE_RE = re.compile(r"(\d{8})")


def _resolve_root(argv):
    for a in argv:
        if not a.startswith("--"):
            if os.path.isdir(a):
                return a
    # (2026-07-26 RPS-07 수리) r-portability 금칙 ④ = resolver 는 CLAUDE_PROJECT_DIR 우선.
    #   구 순서(QM_ROOT 먼저)는 두 값이 다른 트리를 가리킬 때 **다른 저장소의 산출**을
    #   읽고도 정상 보고를 낸다. 또 존재검사만으론 정체를 못 보므로 표지로 확인한다
    #   ("있다"가 "그것이다"를 뜻하지 않는다).
    MARKER = os.path.join("02_Infrastructure", "ops", "research_pool_status.py")
    for env in ("CLAUDE_PROJECT_DIR", "QM_ROOT"):
        v = os.environ.get(env)
        if v and os.path.isfile(os.path.join(v, MARKER)):
            return v
    for env in ("CLAUDE_PROJECT_DIR", "QM_ROOT"):   # 표지 없으면 존재검사로 폴백(구 동작)
        v = os.environ.get(env)
        if v and os.path.isdir(v):
            return v
    return os.getcwd()


def _date_of(path):
    m = _DATE_RE.search(os.path.basename(path))
    return m.group(1) if m else "00000000"


def _latest(stage, pattern):
    """패턴 매칭 파일 중 파일명 날짜가 가장 큰 것의 (path, date8) 반환. 없으면 (None, None)."""
    files = glob.glob(os.path.join(stage, pattern))
    if not files:
        return None, None
    best = max(files, key=_date_of)
    return best, _date_of(best)


def _load(path):
    # (2026-07-26 RPS-02 수리) 구현은 파일 부재와 파싱/IO 실패를 모두 None 으로 융합해,
    #   손상 산출물이 "데이터 없음"과 구분되지 않았다(계측 실패가 정상값 0 으로 위장).
    #   부재 = None / 실패 = 센티넬. 소비측이 라인에 사유를 인쇄한다.
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        return {"__load_error__": type(e).__name__}


def _processed_list(obj):
    """done/processed 산출이 list(ID들) 또는 {'processed': [...]} 양쪽 shape 허용.
    그 외(None/str 등)는 빈 리스트. — append형 파일 schema drift 방어."""
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        return obj.get("processed", []) or []
    return []


def _fmt_date(d8):
    if not d8 or len(d8) != 8:
        return str(d8)
    return "%s-%s-%s" % (d8[:4], d8[4:6], d8[6:8])


def _age_days(d8):
    try:
        dt = datetime.datetime.strptime(d8, "%Y%m%d").date()
        return (datetime.date.today() - dt).days
    except Exception:
        return None


def collect(root):
    """리서치풀 상태를 dict로 수집(표시/JSON 공용)."""
    stage = os.path.join(root, STAGE_REL)
    out = {
        "stage": stage,
        "available": os.path.isdir(stage),
        "route_date": None,
        "collect_date": None,
        "routing_pending": False,
        "counts_by_route": {},
        "n_papers": None,
        "n_arxiv": None,
        "n_curated": None,
        "n_factor_testable": 0,
        "factor_testable_names": [],
        "alpha_queue_n": 0,
        "alpha_queue_date": None,
        "alpha_queue_autorun": None,
        "alpha_queue_names": [],
        # (RPS-09) 전 파일 − done 미소비분 = 실제 착수 가능분. route-최신 testable 과 별개 축.
        "alpha_pending_n": None,
        "alpha_pending_names": [],
        "mode_queue": {"optimizer": 0, "risk": 0, "regime": 0},
        "mode_queue_unresolved": [],     # (RPS-11) 3라우트 0 + 미해석 키 = 드롭 지문
        "dispatch_done": False,
        "recheck_pending": 0,
        "recheck_drift": None,           # (RPS-10) 큐파일 잔여 vs route 재파생 불일치
        "predicates_missing": (RPP is None),
        "queue_done_n": 0,
        "gate_adopt": 0,
        "gate_quarantine": 0,
        "gate_src": None,       # 집계 권위 출처: ledger / auto_verify
        "gate_drift": None,     # 원장 vs 파생 glob 불일치 표식 (숨기지 않고 surface)
        "alpha_queue_autorun_src": None,
        "is_new": False,
        "age_days": None,
    }
    if not out["available"]:
        return out

    # 1. 라우팅 산출(최신)
    route_path, route_d = _latest(stage, "alpha_search_route_*.json")
    if route_path:
        out["route_date"] = route_d
        out["age_days"] = _age_days(route_d)
        rj = _load(route_path) or {}
        if isinstance(rj, dict) and rj.get("__load_error__"):
            # (RPS-02) 손상 산출물 — 아래 파생 숫자는 전부 0/None 이 되므로
            #   "데이터 없음"으로 오독된다. 사유를 세워 render 가 숫자 대신 사유를 찍게.
            out["route_parse_error"] = rj["__load_error__"]
            rj = {}
        out["counts_by_route"] = rj.get("counts_by_route", {}) or {}
        # (2026-07-26 probe① 수리) 생산자 route json에 n_papers 키가 없다(실키 = papers 리스트).
        # 구판은 없는 키 조회 → None → 부팅 라인 "papers ?" 영구 표시 (필드명 불일치 =
        # 조용한 빈 값 부류, search-index 907행 사건과 동형). 리스트 길이로 폴백.
        _np = rj.get("n_papers")
        if _np is None and isinstance(rj.get("papers"), list):
            _np = len(rj["papers"])
        out["n_papers"] = _np
        #──────────────────────────────────────────────────────────────────────
        # (2026-07-26 RPS-01/RPS-06 수리) ★위 n_papers 수리가 **한 필드에서 멈춰 있었다**.
        #   같은 계약 위반이 세 곳 더 있었다 — 생산자 계약(paper_router_prompt.md:40)이
        #   선언한 키는 {date, counts_by_route, n_factor_candidates, papers:[{source,
        #   factor_candidate:{name,verdict,...}}]} 뿐이고 n_arxiv/n_curated/
        #   factor_candidates_all 은 **계약에 없다**(route 13건 중 06-19/20/26 3건만 보유,
        #   07-01 이후 10건 전부 부재).
        #   증상: src 분해가 경고 없이 사라지고(부팅 `papers 30` 뒤 `= arxiv 30` 소실),
        #   testable 카운트가 0으로 읽혔다(실제 papers[] 기준 4건).
        #   → 계약 위치에서 파생하고, 구 top-level 키는 폴백으로만 둔다.
        #   ★교훈: 필드명 불일치 수리는 **같은 파일의 형제 필드를 전수 확인**해야 한다
        #     (CBA-01 = 형제 파일 미전파, 이건 형제 필드 미전파 — 같은 부류).
        #──────────────────────────────────────────────────────────────────────
        _papers = rj.get("papers") if isinstance(rj.get("papers"), list) else []
        out["n_arxiv"] = rj.get("n_arxiv")
        out["n_curated"] = rj.get("n_curated")
        if (out["n_arxiv"] is None and out["n_curated"] is None) and _papers:
            _srcs = collections.Counter(
                str(p.get("source", "")).split(":")[0] for p in _papers)
            out["n_arxiv"] = _srcs.get("arxiv")
            out["n_curated"] = _srcs.get("curated")

        cands = rj.get("factor_candidates_all") or None
        if cands is None:
            cands = [(p.get("factor_candidate") or {}) for p in _papers]
        testable = [c for c in cands if str(c.get("verdict", "")).lower() == "testable"]
        out["n_factor_testable"] = len(testable)
        out["factor_testable_names"] = [
            c.get("name") or c.get("factor_name") or c.get("id") or "(무명)"
            for c in testable]
        # 교차검증축: 생산자 top-level n_testable 과 파생 카운트가 어긋나면 숫자를 믿지 말고
        #   불일치 자체를 노출한다(조용히 한쪽을 채택하면 어느 쪽이 틀렸는지 영구 미상).
        _nt_declared = rj.get("n_testable")
        if isinstance(_nt_declared, int) and _nt_declared != out["n_factor_testable"]:
            out["testable_mismatch"] = "declared=%d derived=%d" % (
                _nt_declared, out["n_factor_testable"])

    # 2. 수집 산출(최신) — 라우터 미반영 신규 감지
    coll_path, coll_d = _latest(stage, "mcp_discovery_*.json")
    if coll_d is None:
        coll_path, coll_d = _latest(stage, "paper_recharge_*.done")
    out["collect_date"] = coll_d
    if coll_d and route_d and coll_d > route_d:
        out["routing_pending"] = True

    # 3. alpha 큐(최신) — alpha-search 대기 testable 후보
    aq_path, aq_d = _latest(stage, "alpha_search_queue_*.json")
    if aq_path:
        aj = _load(aq_path) or {}
        cands = aj.get("candidates", []) or []
        out["alpha_queue_n"] = len(cands)
        out["alpha_queue_date"] = aq_d
        # (2026-08-02 RPS-06 수리) 생산자 스키마 드리프트 — 2026-07-27 산출부터 최상위
        #   `autorun` 키가 사라지고 실행 파라미터가 `runtime_vars`(TODAY/MAX_ALPHA)로 옮겨졌다.
        #   구판 리더는 top-level `autorun` 만 봐서 전건 None → 부팅 라인이 "autorun=?" 를
        #   상시 표시했고, boot_status_smoke 의 placeholder 단언이 이를 정확히 FAIL 로
        #   보고하고 있었다(= 스모크가 깨진 게 아니라 **진짜 결손을 가리키고 있었다**).
        #   autorun 의 의미 = 이번 라운드에 자동 spawn 된 후보 수. 권위 생산자는 라우터의
        #   `autorun_candidates` 리스트이므로, 구 키 → 큐 리스트 → 라우터 리스트 순으로 해석한다.
        #   (factor_name/created_at 사건과 동형 — 필드명 불일치는 예외 없이 조용한 빈 값이 된다.)
        _ar = aj.get("autorun")
        if _ar is None and isinstance(aj.get("autorun_candidates"), list):
            _ar = len(aj["autorun_candidates"])
        if _ar is None and route_path:
            _rj = _load(route_path)
            if isinstance(_rj, dict) and isinstance(_rj.get("autorun_candidates"), list):
                _ar = len(_rj["autorun_candidates"])
                out["alpha_queue_autorun_src"] = "route"
        out["alpha_queue_autorun"] = _ar
        # (2026-07-26 probe① 수리) 생산자 스키마는 후보 최상위 factor_name/factor_title 이다
        #   (실측 alpha_search_queue_20260726.json). 구판은 factor_candidate.name → id 만 봐서
        #   두 키 모두 부재 → 전건 "?" → 부팅 AlphaQueue 라인이 이름 대신 "?"를 상시 표시했다.
        #   (search-index created_at/logged_at 907행 사건과 동형 — 필드명 불일치는 예외 없이
        #    조용한 빈 값이 된다.) 구 스키마도 폴백으로 계속 지원.
        names = []
        for c in cands:
            fc = c.get("factor_candidate") or {}
            nm = (c.get("factor_name") or c.get("factor_title")
                  or fc.get("name") or c.get("id"))
            names.append(nm if nm else "(무명 후보 — 생산자 스키마 확인 필요)")
        out["alpha_queue_names"] = names

    # 3a. (2026-08-02 RPS-09 수리) ★미소비 pending — 이 리더의 헤드라인 결함.
    #   구판 `n_factor_testable` 은 ① done 을 **차감하지 않고** ② `_latest` 로 최신 route
    #   파일 **하나만** 봤다. 두 결함이 반대 방향으로 작용해 숫자가 그럴듯했다:
    #     실측 08-02 — 라인은 "testable route 2 — VolRankStability, T_RetAutoCorr_12M" 를
    #     찍었는데 두 건 다 그날 실행·QUARANTINE 완료(done 차감 시 0)이고, 진짜 미소비분은
    #     **과거 파일**에 있어 이 라인엔 아예 안 잡혔다(정본 술어 기준 참값 1).
    #   → 소비자(alpha_search_queue_run.sh)가 실제로 착수하는 집합과 같은 술어를 쓴다.
    #     route-최신 testable 은 "오늘 라우터가 뭘 봤나"의 진단축으로 남긴다(다른 질문).
    if RPP is not None:
        try:
            _pend = RPP.alpha_pending(stage)
            out["alpha_pending_n"] = len(_pend)
            out["alpha_pending_names"] = [
                (RPP.display_name(o) or pid) for pid, o in _pend.items()]
        except Exception as e:
            out["alpha_pending_error"] = type(e).__name__

    # 3b. (gap④) alpha 큐 자동백테 처리 결과 — alpha_search_queue_done + auto_verify gate
    dq = _load(os.path.join(stage, "alpha_search_queue_done.json"))
    out["queue_done_n"] = len(_processed_list(dq))
    # (2026-08-02 RPS-07 수리) 구현은 판정 집계를 **원장이 아니라 파생 산출**
    #   (auto_verify_*.json glob)에서 셌다. 두 계열은 어긋난다 — 실측 2026-08-02:
    #     원장 alpha_search_queue_done.json::records = 6건 전부 QUARANTINE
    #     auto_verify glob = 7파일이나 gate_decision 키 보유분은 5건
    #       · auto_verify_2607.14174.json  = 스키마 상이(gate_decision 없이 L1_pit_pass 등)
    #       · auto_verify_resid_info_vol_20260727.json = 미게이트(진행 중)
    #       · 2607.19497 은 파일명이 paper_id 아닌 factor 명(auto_verify_spec_mass_lowfreq_*)
    #   → 화면은 "QUAR 5" 를 표시했으나 실제 격리는 6건. 스키마·명명 드리프트가
    #     조용한 **누락 집계**로 나타나던 자리다(집계 대상 오인 계통).
    #   원장(gate_decision 을 전건 보유)을 1차 권위로 세우고, 파생 glob 은 교차검증으로만
    #   쓴다. 둘이 어긋나면 숨기지 말고 드리프트 표식을 올린다.
    _led = dq.get("records", []) if isinstance(dq, dict) else []
    _led_adopt = _led_quar = 0
    for r in _led:
        if not isinstance(r, dict):
            continue
        d = str(r.get("gate_decision", "")).upper()
        if d == "ADOPT":
            _led_adopt += 1
        elif d == "QUARANTINE":
            _led_quar += 1
    _vf_adopt = _vf_quar = 0
    for vf in glob.glob(os.path.join(stage, "auto_verify_*.json")):
        vj = _load(vf)
        dec = str(vj.get("gate_decision", "")).upper() if isinstance(vj, dict) else ""
        if dec == "ADOPT":
            _vf_adopt += 1
        elif dec == "QUARANTINE":
            _vf_quar += 1
    if _led:
        out["gate_adopt"], out["gate_quarantine"] = _led_adopt, _led_quar
        out["gate_src"] = "ledger"
        if (_vf_adopt, _vf_quar) != (_led_adopt, _led_quar):
            out["gate_drift"] = "auto_verify %d/%d vs 원장 %d/%d" % (
                _vf_adopt, _vf_quar, _led_adopt, _led_quar)
    else:
        out["gate_adopt"], out["gate_quarantine"] = _vf_adopt, _vf_quar
        out["gate_src"] = "auto_verify"

    # 4. mode 큐(최신) — QEPM 연료
    # (2026-07-26 RPS-04 수리) 구현은 날짜를 버려(`_`) mode 큐가 route 보다 과거여도
    #   현재 연료처럼 보였다. alpha 큐와 동일하게 stamp 를 살려 stale 태그를 붙인다.
    mq_path, mq_d = _latest(stage, "mode_queue_*.json")
    out["mode_queue_date"] = mq_d
    if mq_path:
        mj = _load(mq_path) or {}
        # (2026-08-02 RPS-11 수리) 구판은 3키를 **최상위에서만** 읽었다. mode_queue_20260727.json
        #   은 3키를 `queue`{} 안에 넣었으므로 그 판을 재생하면 opt0/risk0/regime0 으로 표시된다
        #   — 소비자(paper_research_dispatch.R)가 정확히 이 미해석으로 14편을 전량 드롭했고,
        #   그쪽은 이미 두 형태 관용으로 수리됐다. 리더만 구판에 남아 있었다.
        #   ★schema_version 으로 분기 불가(생산자 이름이 들어가 있다) → 형태를 직접 본다.
        if RPP is not None:
            _routes = RPP.mode_queue_routes(mj)
            for k in ("optimizer", "risk", "regime"):
                out["mode_queue"][k] = len(_routes[k])
            # "0편"과 "못 읽음"은 겉보기가 같다 — 미해석 키가 드롭의 유일한 지문이다.
            out["mode_queue_unresolved"] = RPP.mode_queue_unresolved(mj)
        else:
            for k in ("optimizer", "risk", "regime"):
                v = mj.get(k)
                out["mode_queue"][k] = len(v) if isinstance(v, list) else 0
        # dispatch 소비 여부 — route_date 기준 research_status
        # (2026-08-02 RPS-08 수리) 구판은 `os.path.isfile()` 만 봤다 = **존재 검사로 소비 검사를
        #   대체**. 실사고 07-27: mode_queue 가 3키를 queue{} 안에 넣어 dispatch 가 0/0/0 으로
        #   읽고 `research_status_20260727.json::actions = []` 를 썼는데(14편 전량 드롭),
        #   파일은 존재하므로 부팅 라인이 **dispatch=DONE** 을 찍었다 — 유실이 정상 종료로 위장.
        #   ([[project-completion-check-pattern-scan-20260726]] "시간 경과=완결" 대리판정과 동형:
        #    여기선 "파일 존재=소비 완료".) 내용을 열어 액션이 실재하는지로 판정한다.
        if route_d:
            rs = os.path.join(stage, "research_status_%s.json" % route_d)
            if not os.path.isfile(rs):
                out["dispatch_done"] = False
            else:
                rj = _load(rs)
                acts = rj.get("actions") if isinstance(rj, dict) else None
                # actions 는 07-27 이전엔 dict{route: {...}}, 이후 산출엔 list — 둘 다 관용.
                n_act = len(acts) if isinstance(acts, (dict, list)) else 0
                out["dispatch_done"] = n_act > 0
                if n_act == 0:
                    # 빈 소비를 조용히 넘기지 않는다 — 이것이 드롭의 유일한 지문이다.
                    out["dispatch_empty"] = "research_status_%s.json actions 비어 있음 (소비 0 — 스키마 드리프트/드롭 의심)" % route_d

    # 5. factor recheck(tier-2) 잔여 = 큐 - done
    # (2026-08-02 RPS-10 수리) 구판은 큐의 `paper_id` 를 done 과 **raw 문자열 비교**했다.
    #   큐 0802 의 id 는 'arxiv:' 접두(route 0727 판에서 물려받음)이고 done 은 bare 라
    #   `pid not in done` 이 항상 참 → 실측 "recheck잔여 3" 인데 참값 0(3/3 전량 처리분).
    #   소비자(factor_deep_recheck_run.sh)는 이미 정규화로 수리돼 N=0 을 내고 있었다 —
    #   즉 **리더만 어긋나** 있었고, 부팅 라인이 매일 없는 잔여를 광고했다.
    fq_path, _ = _latest(stage, "factor_recheck_queue_*.json")
    fj = (_load(fq_path) or {}) if fq_path else {}
    if RPP is not None:
        out["recheck_pending"] = len(RPP.recheck_residual(stage, fj))
        # 교차검증축: 물질화된 큐파일 잔여 ↔ route 재파생(소비자가 다음 런에 만들 집합).
        #   어긋나면 큐파일이 stale 이라는 뜻 — 숨기지 말고 드러낸다(RPS-07 원장↔파생 선례).
        try:
            _canon = len(RPP.recheck_uncertain(stage))
            if _canon != out["recheck_pending"]:
                out["recheck_drift"] = "큐파일 %d vs route 재파생 %d" % (
                    out["recheck_pending"], _canon)
        except Exception:
            pass
    else:
        queued_ids = set()
        for it in (fj.get("items", []) or []):
            pid = it.get("paper_id")
            if pid:
                queued_ids.add(pid)
        done_ids = set()
        dj = _load(os.path.join(stage, "factor_recheck_done.json"))
        for it in _processed_list(dj):
            pid = it.get("paper_id") if isinstance(it, dict) else it
            if pid:
                done_ids.add(pid)
        out["recheck_pending"] = len(queued_ids - done_ids)

    # 6. NEW 판정 — 직전 부팅 인지 마커와 비교
    marker = _load(os.path.join(root, MARKER_REL)) or {}
    last_seen = marker.get("route_date")
    if out["route_date"] and out["route_date"] != last_seen:
        out["is_new"] = True

    return out


def _mark(root, route_date):
    if not route_date:
        return
    try:
        path = os.path.join(root, MARKER_REL)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"route_date": route_date,
                       "marked_at": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")},
                      f, ensure_ascii=False)
    except Exception:
        pass


def render(o):
    """부팅 표시용 라인 리스트 반환(BMP-only, 장식 글리프 회피)."""
    if not o["available"]:
        return ["ResearchPool: SKIP (paper_recharge 산출 부재 — paper_recharge_daily 미실행/신규 클론)"]
    if not o["route_date"]:
        cd = _fmt_date(o["collect_date"]) if o["collect_date"] else "?"
        return ["ResearchPool: 수집만 collect=%s, 라우팅 산출 부재 (router 미실행 — paper_router_run.sh)" % cd]

    if o.get("route_parse_error"):
        # (RPS-02) 손상 산출물 — 아래 파생 숫자는 전부 0 이므로 "데이터 없음"으로 오독된다.
        return ["ResearchPool: route=%s ★route json 판독 실패 (%s) — 아래 숫자 산출 불가. "
                "숫자 0 은 '없음'이 아니라 '미측정'" % (
                    _fmt_date(o["route_date"]), o["route_parse_error"])]

    cr = o["counts_by_route"]
    route_str = "a%s/o%s/r%s/rg%s/skip%s" % (
        cr.get("alpha", 0), cr.get("optimizer", 0), cr.get("risk", 0),
        cr.get("regime", 0), cr.get("skip", 0))
    new_tag = "NEW" if o["is_new"] else "seen"
    age = o["age_days"]
    age_str = ("%dd" % age) if age is not None else "?"
    src = []
    if o["n_arxiv"] is not None:
        src.append("arxiv %s" % o["n_arxiv"])
    if o["n_curated"] is not None:
        src.append("curated %s" % o["n_curated"])
    src_str = (" = " + " + ".join(src)) if src else ""
    lines = []
    lines.append("ResearchPool: route=%s [%s · %s] papers %s%s · route %s" % (
        _fmt_date(o["route_date"]), new_tag, age_str,
        o["n_papers"] if o["n_papers"] is not None else "?", src_str, route_str))

    # alpha 큐 — route-level testable(최신·authoritative) 헤드라인 + 소비 큐(staleness 명시)
    aq_names = ", ".join(o["alpha_queue_names"][:3])
    if o["alpha_queue_n"] > 3:
        aq_names += ", ..."
    autorun = o["alpha_queue_autorun"]
    # (2026-08-02) 구판 폴백은 리터럴 '?' 였다 — boot_status_smoke 의 placeholder 단언이
    #   정확히 이걸 잡는다(그 단언은 "약속만 있고 구현이 없던" 결손을 07-26에 실장한 것).
    #   '?' 는 아무것도 말하지 않는다. 미상이면 미상이라고, 사유가 짐작되면 사유를 쓴다.
    ar_str = ("autorun=%s" % autorun) if autorun is not None else "autorun=미상(생산자 키 부재)"
    stale = ""
    if o["alpha_queue_date"] and o["route_date"] and o["alpha_queue_date"] != o["route_date"]:
        stale = " [큐 stamp %s — route보다 과거, 재생성 대기]" % _fmt_date(o["alpha_queue_date"])
    # gap④ 자동백테 처리 결과 — 처리 N (ADOPT a / QUAR q)
    gate = ""
    if o["queue_done_n"] > 0 or o["gate_adopt"] > 0 or o["gate_quarantine"] > 0:
        # (2026-07-26 RPS-05 수리) 이 수치는 auto_verify_*.json 전량 glob = **누적**인데
        #   라벨이 없어 '이번 런 실적'으로 읽혔다. 범위를 이름으로 밝힌다.
        gate = " · 처리 누적 %d (ADOPT %d/QUAR %d)" % (
            o["queue_done_n"], o["gate_adopt"], o["gate_quarantine"])
        # (2026-08-02 RPS-07) 원장↔파생 불일치는 조용히 넘기지 않는다 — 명명/스키마
        #   드리프트로 판정이 누락 집계되던 자리이므로 한 줄로 드러낸다.
        if o.get("gate_drift"):
            gate += " ⚠드리프트(%s)" % o["gate_drift"]
    # (2026-08-02 RPS-09) 헤드라인 = **미소비 pending**(소비자가 실제 착수하는 집합).
    #   route-최신 testable 은 "오늘 라우터가 뭘 봤나"라는 다른 질문이므로 진단축으로 병기한다.
    #   구판은 후자만 찍으면서 전자인 척했다 — 그래서 그날 이미 QUARANTINE 된 2건이
    #   "대기 중"으로 광고되고, 과거 파일의 진짜 미소비분은 보이지 않았다.
    pend_n = o.get("alpha_pending_n")
    pend_names = o.get("alpha_pending_names") or []
    if o.get("alpha_pending_error"):
        pend_str = "미소비 산정실패(%s)" % o["alpha_pending_error"]
    elif pend_n is None:
        pend_str = "미소비 미측정(술어 모듈 부재)"
    else:
        pend_str = "미소비 %d" % pend_n
    if pend_names:
        names = ", ".join(pend_names[:3]) + (", ..." if len(pend_names) > 3 else "")
    else:
        # pending 0 이면 최신 route testable 을 맥락으로 보인다(무엇이 처리됐는지).
        names = (", ".join(o["factor_testable_names"][:3]) or aq_names
                 or "(표시할 후보명 없음)")
    if pend_n or o["n_factor_testable"] > 0 or o["alpha_queue_n"] > 0:
        lines.append("  AlphaQueue:  %s (전파일−done) · route최신 testable %d · 소비큐 %d (%s) — %s%s%s" % (
            pend_str, o["n_factor_testable"], o["alpha_queue_n"], ar_str, names, gate, stale))
    else:
        # (2026-07-26 RPS-03 수리) 구현은 0 에 **연구 결론**("신선 KR 횡단면 알파 희귀")을
        #   하드코딩했다 — 필드명 불일치로 파생이 0 이 됐던 실제 상황(testable 4건 존재)에서
        #   그 문구가 그대로 나갔다. 해설은 측정이 건건할 때만, 근거를 함께 붙인다.
        if o.get("testable_mismatch"):
            lines.append("  AlphaQueue:  0 testable — ★측정 불일치(%s): 스키마 드리프트 의심%s"
                         % (o["testable_mismatch"], gate))
        else:
            lines.append("  AlphaQueue:  0 testable 대기 (route n_testable=%s 확인)%s"
                         % (o.get("n_factor_testable", 0), gate))

    # mode 큐 + dispatch
    mq = o["mode_queue"]
    # (2026-08-02 RPS-08) 빈 소비를 PENDING 으로 뭉개지 않는다 — "아직 안 돌았다"와
    #   "돌았는데 0편 소비했다"는 다른 사건이고, 후자가 07-27 14편 드롭의 실제 모습이었다.
    if o.get("dispatch_empty"):
        disp = "★EMPTY(소비 0 — 드롭 의심)"
    else:
        disp = "DONE" if o["dispatch_done"] else "PENDING"
    mq_stale = ""
    if o.get("mode_queue_date") and o["route_date"] and o["mode_queue_date"] != o["route_date"]:
        # (RPS-04) 큐 stamp 가 route 보다 과거 = 현재 연료가 아니다(구판은 무표기)
        mq_stale = " [큐 stamp %s — route보다 과거]" % _fmt_date(o["mode_queue_date"])
    # (2026-08-02 RPS-11) 3라우트 0 + 미해석 키 = 스키마 드리프트 지문. 0 으로 뭉개지 않는다.
    mq_unres = ""
    if o.get("mode_queue_unresolved"):
        mq_unres = " ★미해석 키(%s) — 스키마 드리프트 의심" % ", ".join(
            o["mode_queue_unresolved"][:4])
    # (2026-08-02 RPS-10) 큐파일 잔여 ↔ route 재파생 불일치 = 큐파일 stale 지문.
    rc_drift = " ⚠드리프트(%s)" % o["recheck_drift"] if o.get("recheck_drift") else ""
    lines.append("  ModeQueue:   opt%s/risk%s/regime%s (QEPM 연료) · dispatch=%s · recheck잔여 %d%s%s%s" % (
        mq["optimizer"], mq["risk"], mq["regime"], disp, o["recheck_pending"],
        rc_drift, mq_unres, mq_stale))

    # 라우팅 대기(수집 > 라우팅)
    if o["routing_pending"]:
        lines.append("  Routing:     PENDING — collect=%s > route=%s (신규 적재 라우터 미반영, paper_router_run.sh _FORCE=1)" % (
            _fmt_date(o["collect_date"]), _fmt_date(o["route_date"])))
    return lines


def main():
    argv = sys.argv[1:]
    want_json = "--json" in argv
    want_mark = "--mark" in argv
    try:
        root = _resolve_root(argv)
        o = collect(root)
        if want_json:
            print(json.dumps(o, ensure_ascii=False))
        else:
            for ln in render(o):
                print(ln)
        if want_mark and o.get("available") and o.get("route_date"):
            _mark(root, o["route_date"])
    except Exception as e:
        # fail-soft: 부팅 중단 절대 금지
        if want_json:
            print(json.dumps({"available": False, "error": "%s" % type(e).__name__}))
        else:
            print("ResearchPool: SKIP (reader 오류 %s)" % type(e).__name__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
