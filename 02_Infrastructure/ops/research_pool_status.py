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

STAGE_REL = os.path.join("stage_artifacts", "paper_recharge")
MARKER_REL = os.path.join(".cache", "research_pool_last_seen.json")
_DATE_RE = re.compile(r"(\d{8})")


def _resolve_root(argv):
    for a in argv:
        if not a.startswith("--"):
            if os.path.isdir(a):
                return a
    for env in ("QM_ROOT", "CLAUDE_PROJECT_DIR"):
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
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


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
        "mode_queue": {"optimizer": 0, "risk": 0, "regime": 0},
        "dispatch_done": False,
        "recheck_pending": 0,
        "queue_done_n": 0,
        "gate_adopt": 0,
        "gate_quarantine": 0,
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
        out["counts_by_route"] = rj.get("counts_by_route", {}) or {}
        # (2026-07-26 probe① 수리) 생산자 route json에 n_papers 키가 없다(실키 = papers 리스트).
        # 구판은 없는 키 조회 → None → 부팅 라인 "papers ?" 영구 표시 (필드명 불일치 =
        # 조용한 빈 값 부류, search-index 907행 사건과 동형). 리스트 길이로 폴백.
        _np = rj.get("n_papers")
        if _np is None and isinstance(rj.get("papers"), list):
            _np = len(rj["papers"])
        out["n_papers"] = _np
        out["n_arxiv"] = rj.get("n_arxiv")
        out["n_curated"] = rj.get("n_curated")
        cands = rj.get("factor_candidates_all", []) or []
        testable = [c for c in cands if str(c.get("verdict", "")).lower() == "testable"]
        out["n_factor_testable"] = len(testable)
        out["factor_testable_names"] = [c.get("name", c.get("id", "?")) for c in testable]

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
        out["alpha_queue_autorun"] = aj.get("autorun")
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

    # 3b. (gap④) alpha 큐 자동백테 처리 결과 — alpha_search_queue_done + auto_verify gate
    dq = _load(os.path.join(stage, "alpha_search_queue_done.json"))
    out["queue_done_n"] = len(_processed_list(dq))
    for vf in glob.glob(os.path.join(stage, "auto_verify_*.json")):
        vj = _load(vf)
        dec = str(vj.get("gate_decision", "")).upper() if isinstance(vj, dict) else ""
        if dec == "ADOPT":
            out["gate_adopt"] += 1
        elif dec == "QUARANTINE":
            out["gate_quarantine"] += 1

    # 4. mode 큐(최신) — QEPM 연료
    mq_path, _ = _latest(stage, "mode_queue_*.json")
    if mq_path:
        mj = _load(mq_path) or {}
        for k in ("optimizer", "risk", "regime"):
            v = mj.get(k)
            out["mode_queue"][k] = len(v) if isinstance(v, list) else 0
        # dispatch 소비 여부 — route_date 기준 research_status 존재
        if route_d:
            rs = os.path.join(stage, "research_status_%s.json" % route_d)
            out["dispatch_done"] = os.path.isfile(rs)

    # 5. factor recheck(tier-2) 잔여 = 큐 - done
    fq_path, _ = _latest(stage, "factor_recheck_queue_*.json")
    queued_ids = set()
    if fq_path:
        fj = _load(fq_path) or {}
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
    ar_str = ("autorun=%s" % autorun) if autorun is not None else "autorun=?"
    stale = ""
    if o["alpha_queue_date"] and o["route_date"] and o["alpha_queue_date"] != o["route_date"]:
        stale = " [큐 stamp %s — route보다 과거, 재생성 대기]" % _fmt_date(o["alpha_queue_date"])
    # gap④ 자동백테 처리 결과 — 처리 N (ADOPT a / QUAR q)
    gate = ""
    if o["queue_done_n"] > 0 or o["gate_adopt"] > 0 or o["gate_quarantine"] > 0:
        gate = " · 처리 %d (ADOPT %d/QUAR %d)" % (
            o["queue_done_n"], o["gate_adopt"], o["gate_quarantine"])
    if o["n_factor_testable"] > 0 or o["alpha_queue_n"] > 0:
        names = ", ".join(o["factor_testable_names"][:3]) or aq_names or "?"
        lines.append("  AlphaQueue:  testable route %d / 소비큐 %d (%s) — %s%s%s" % (
            o["n_factor_testable"], o["alpha_queue_n"], ar_str, names, gate, stale))
    else:
        lines.append("  AlphaQueue:  0 testable 대기 (신선 KR 횡단면 알파 희귀)%s" % gate)

    # mode 큐 + dispatch
    mq = o["mode_queue"]
    disp = "DONE" if o["dispatch_done"] else "PENDING"
    lines.append("  ModeQueue:   opt%s/risk%s/regime%s (QEPM 연료) · dispatch=%s · recheck잔여 %d" % (
        mq["optimizer"], mq["risk"], mq["regime"], disp, o["recheck_pending"]))

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
