# -*- coding: utf-8 -*-
"""FQ-004 Stage-1 무파서 취득 드라이버 (task #64, 도훈 승인 2026-07-13).

DART 구조화 API만 — document.xml 다운로드 0건.
  T1  감사의견 구조화: accnutAdtorNmNdAdtOpinion.json, 348 corps x FY2015-2025 (reprt_code 11011)  ~3,828콜
  T3  정정 이벤트 지도: per-corp A001 list [기재정정] 스캔 + F군(정정 보유 93 corps) 원행 재수집        ~460콜
  T2a 담보 최근 2년:   majorstock.json 348 corps, rows 본문 전량 보존 (census 카운트-only 버그 복원)   ~348콜

쿼터 규약 (절대):
  - 총 예산 5,000콜 hard cap (모든 HTTP 시도를 콜로 계상), 요청 간 딜레이 0.35s.
  - HTTP 429/503 → 5s*retry 백오프 최대 2회 (dart_insider_backfill.R 패턴 재사용).
  - DART status 020(사용한도) → 즉시 전체 중단 + resume manifest. 기타 오류 status(010/011/012/100/800/900/901) → fail-closed 중단.
  - status 013 = 정상 0건. phase별 실패율 > max(2, 2%) → phase partial 중단 (redo next run).
  - insider 백필 프로세스 간섭 없음 (list/구조화 API만, kill 없음).

범위 규율: 취득 + coverage census + 기술통계만. returns join 금지 (신호 실측은 별도 사전등록 라운드).

재개: 동일 명령 재실행 → state_stage1.json 위치에서 이어서 수집.
  실행: .venv_qvest_ml/Scripts/python.exe 02_Infrastructure/data/dart_pledge_audit_acquire.py
산출: 02_Infrastructure/data/dart_pledge_audit/{t1_audit_fyYYYY,t3_a001_annual_reports,t3_fgroup_rows,t2a_majorstock_snapshot}.parquet
      + acquisition_manifest.json (콜수·실패율·quota 이벤트·resume point·coverage 기술통계)
OneDrive 쓰기: temp + os.replace (JSONL append 제외 — plain text append는 mmap 1224 무관).
"""
import csv
import json
import os
import sys
import time
import collections

import requests
import pandas as pd

R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/02_Infrastructure/data/dart_pledge_audit"
os.makedirs(OUT, exist_ok=True)
STATE_PATH = OUT + "/state_stage1.json"
MANIFEST_PATH = OUT + "/acquisition_manifest.json"

HARD_CAP = 5000
DELAY = 0.35
TODAY = time.strftime("%Y%m%d")
FY_LIST = [str(y) for y in range(2015, 2026)]          # FY2015..FY2025
QUOTA_ST = {"020"}                                       # 사용한도 초과
FATAL_ST = {"010", "011", "012", "100", "800", "900", "901"}
CENSUS_EST = {"t1": 3828, "t3": 400, "t2a": 348}

env = dict(l.split("=", 1) for l in open(R + "/.env", encoding="utf-8", errors="ignore").read().splitlines()
           if "=" in l and not l.startswith("#"))
KEY = env["DART_API_KEY"].strip()

UNI = list(csv.DictReader(open(R + "/.cache/dart/universe_corpcodes.csv", encoding="utf-8")))
TICKER = {u["corp_code"]: u.get("ticker", "") for u in UNI}

# F군 정정 보유 corps (census_raw p4_audit.corps, n_corr>0 — 93 corps 예상)
_census = json.load(open(R + "/04_Research/dart_census/census_raw_20260713.json", encoding="utf-8"))
F_CORR_CORPS = [c["corp_code"] for c in _census["p4_audit"]["corps"] if c.get("n_corr", 0) > 0]


# ---------------------------------------------------------------- state
def _fresh_state():
    return {
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
        "runs": [],
        "calls_total": 0,
        "fails_total": 0,
        "quota_events": [],
        "halt": None,                    # {"reason","phase","at"} — quota/fatal/cap
        "phases": {
            "t1":      {"status": "pending", "fy_idx": 0, "corp_idx": 0, "items_done": 0, "fails": 0, "n013": 0},
            "t3_a001": {"status": "pending", "corp_idx": 0, "items_done": 0, "fails": 0, "n013": 0, "truncated": []},
            "t3_f":    {"status": "pending", "corp_idx": 0, "items_done": 0, "fails": 0, "n013": 0},
            "t2a":     {"status": "pending", "corp_idx": 0, "items_done": 0, "fails": 0, "n013": 0},
        },
    }


def load_state():
    if os.path.exists(STATE_PATH):
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f)
    return _fresh_state()


def atomic_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1, default=str)
    os.replace(tmp, path)


state = load_state()
state["runs"].append({"started": time.strftime("%Y-%m-%d %H:%M:%S"), "calls_at_start": state["calls_total"]})
state["halt"] = None
RUN_CALLS0 = state["calls_total"]


def save_state():
    atomic_json(STATE_PATH, state)


class Halt(Exception):
    pass


def halt(reason, phase):
    state["halt"] = {"reason": reason, "phase": phase, "at": time.strftime("%Y-%m-%d %H:%M:%S")}
    if "quota" in reason or "020" in reason:
        state["quota_events"].append(state["halt"])
    print("[HALT] %s (phase=%s, calls=%d)" % (reason, phase, state["calls_total"]), flush=True)
    save_state()
    raise Halt(reason)


# ---------------------------------------------------------------- api
def api(url, params, tag, phase):
    """1 item = 성공 dict 반환 / 일시오류 소진 시 None(호출측이 fail 계상) / quota·fatal·cap 시 Halt."""
    retry = 0
    while True:
        if state["calls_total"] >= HARD_CAP:
            halt("hard cap %d reached" % HARD_CAP, phase)
        state["calls_total"] += 1
        if state["calls_total"] % 100 == 0:
            print("[quota] %d calls (%s)" % (state["calls_total"], tag), flush=True)
            save_state()
        try:
            resp = requests.get(url, params=dict(params, crtfc_key=KEY), timeout=25)
        except Exception as e:
            if retry >= 2:
                return None
            retry += 1
            time.sleep(5 * retry)
            continue
        if resp.status_code in (429, 503):
            if retry >= 2:
                return None
            retry += 1
            time.sleep(5 * retry)
            continue
        if resp.status_code != 200:
            if retry >= 2:
                return None
            retry += 1
            time.sleep(2 * retry)
            continue
        try:
            j = resp.json()
        except Exception:
            if retry >= 2:
                return None
            retry += 1
            time.sleep(2 * retry)
            continue
        st = j.get("status")
        time.sleep(DELAY)
        if st in ("000", "013"):
            return j
        if st in QUOTA_ST or "한도" in str(j.get("message", "")):
            halt("DART quota status %s (%s)" % (st, j.get("message")), phase)
        if st in FATAL_ST:
            halt("DART fatal status %s (%s) at %s" % (st, j.get("message"), tag), phase)
        # 미상 status — 일시오류 취급 후 소진 시 fail
        if retry >= 2:
            return None
        retry += 1
        time.sleep(2 * retry)


def check_fail_rate(phase, n_items):
    ph = state["phases"][phase]
    if ph["fails"] > max(2, int(0.02 * n_items)):
        ph["status"] = "partial_failrate"
        halt("fail rate exceeded: %d fails / %d items" % (ph["fails"], n_items), phase)


# ---------------------------------------------------------------- raw jsonl
def jsonl_append(name, obj):
    with open(OUT + "/" + name, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False, default=str) + "\n")


def jsonl_load(name):
    path = OUT + "/" + name
    if not os.path.exists(path):
        return []
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def write_parquet(df, fname):
    tmp = OUT + "/_tmp_" + fname
    df.to_parquet(tmp, index=False)
    os.replace(tmp, OUT + "/" + fname)


# ---------------------------------------------------------------- T1 감사의견
def t1_build_parquet(fy=None):
    """JSONL → parquet. fy 지정 시 해당 연도 체크포인트, None이면 전체 통합."""
    recs = jsonl_load("raw_t1.jsonl")
    rows = []
    seen = {}
    for r in recs:
        seen[(r["corp_code"], r["query_fy"])] = r      # dedupe: 마지막 수집 우선
    for (cc, qfy), r in sorted(seen.items()):
        for row in r["rows"]:
            d = dict(row)
            d["corp_code"] = cc
            d["query_fy"] = qfy
            d["ticker"] = TICKER.get(cc, "")
            d["api_status"] = r["status"]
            rows.append(d)
        if not r["rows"]:
            rows.append({"corp_code": cc, "query_fy": qfy, "ticker": TICKER.get(cc, ""),
                         "api_status": r["status"]})
    df = pd.DataFrame(rows).astype(str)
    if fy is not None:
        sub = df[df["query_fy"] == fy]
        write_parquet(sub, "t1_audit_fy%s.parquet" % fy)
    else:
        write_parquet(df, "t1_audit_opinion_fy2015_2025.parquet")
    return df


def run_t1():
    ph = state["phases"]["t1"]
    if ph["status"] == "done":
        return
    ph["status"] = "running"
    n_items = len(FY_LIST) * len(UNI)
    while ph["fy_idx"] < len(FY_LIST):
        fy = FY_LIST[ph["fy_idx"]]
        while ph["corp_idx"] < len(UNI):
            cc = UNI[ph["corp_idx"]]["corp_code"]
            tag = "t1:%s:FY%s" % (cc, fy)
            j = api("https://opendart.fss.or.kr/api/accnutAdtorNmNdAdtOpinion.json",
                    dict(corp_code=cc, bsns_year=fy, reprt_code="11011"), tag, "t1")
            if j is None:
                ph["fails"] += 1
                state["fails_total"] += 1
                jsonl_append("raw_t1.jsonl", {"corp_code": cc, "query_fy": fy,
                                              "status": "FETCH_FAIL", "rows": []})
                check_fail_rate("t1", n_items)
            else:
                if j.get("status") == "013":
                    ph["n013"] += 1
                jsonl_append("raw_t1.jsonl", {"corp_code": cc, "query_fy": fy,
                                              "status": j.get("status"), "rows": j.get("list") or []})
            ph["corp_idx"] += 1
            ph["items_done"] += 1
            if ph["items_done"] % 25 == 0:
                save_state()
        # FY 완료 → 연 체크포인트 parquet
        t1_build_parquet(fy=fy)
        print("[t1] FY%s done (%d/%d corps, calls=%d)" % (fy, len(UNI), len(UNI), state["calls_total"]), flush=True)
        ph["fy_idx"] += 1
        ph["corp_idx"] = 0
        save_state()
    t1_build_parquet(fy=None)
    ph["status"] = "done"
    save_state()
    print("[t1] DONE (calls=%d, 013=%d, fails=%d)" % (state["calls_total"], ph["n013"], ph["fails"]), flush=True)


# ---------------------------------------------------------------- T3 정정지도
LIST_COLS = ["corp_code", "corp_name", "stock_code", "corp_cls", "report_nm",
             "rcept_no", "flr_nm", "rcept_dt", "rm"]


def _list_rows_to_recs(rows, cc, source):
    out = []
    for r in rows:
        d = {k: r.get(k, "") for k in LIST_COLS}
        d["ticker"] = TICKER.get(cc, "")
        d["source"] = source
        d["is_jungjung"] = "정정" in str(r.get("report_nm", ""))
        out.append(d)
    return out


def run_t3_a001():
    ph = state["phases"]["t3_a001"]
    if ph["status"] == "done":
        return
    ph["status"] = "running"
    while ph["corp_idx"] < len(UNI):
        cc = UNI[ph["corp_idx"]]["corp_code"]
        tag = "t3a:%s" % cc
        rows = []
        page = 1
        ok = True
        while True:
            j = api("https://opendart.fss.or.kr/api/list.json",
                    dict(corp_code=cc, pblntf_detail_ty="A001", bgn_de="20050101", end_de=TODAY,
                         last_reprt_at="N", page_no=page, page_count=100), tag, "t3_a001")
            if j is None:
                ok = False
                break
            if j.get("status") == "013":
                ph["n013"] += 1
                break
            rows += j.get("list") or []
            tp = int(j.get("total_page") or 1)
            if page >= tp:
                break
            if page >= 3:                                 # 안전 상한 (사업보고서 21y ≈ 1페이지)
                ph["truncated"].append(cc)
                break
            page += 1
        if not ok:
            ph["fails"] += 1
            state["fails_total"] += 1
            jsonl_append("raw_t3_a001.jsonl", {"corp_code": cc, "status": "FETCH_FAIL", "rows": []})
            check_fail_rate("t3_a001", len(UNI))
        else:
            jsonl_append("raw_t3_a001.jsonl", {"corp_code": cc, "status": "000", "rows": rows})
        ph["corp_idx"] += 1
        ph["items_done"] += 1
        if ph["items_done"] % 25 == 0:
            save_state()
    recs = jsonl_load("raw_t3_a001.jsonl")
    seen = {}
    for r in recs:
        seen[r["corp_code"]] = r
    all_rows = []
    for cc, r in sorted(seen.items()):
        all_rows += _list_rows_to_recs(r["rows"], cc, "A001")
    write_parquet(pd.DataFrame(all_rows).astype(str), "t3_a001_annual_reports.parquet")
    ph["status"] = "done"
    save_state()
    print("[t3_a001] DONE (%d corps, calls=%d)" % (len(seen), state["calls_total"]), flush=True)


def run_t3_f():
    ph = state["phases"]["t3_f"]
    if ph["status"] == "done":
        return
    ph["status"] = "running"
    while ph["corp_idx"] < len(F_CORR_CORPS):
        cc = F_CORR_CORPS[ph["corp_idx"]]
        tag = "t3f:%s" % cc
        rows = []
        page = 1
        ok = True
        while True:
            j = api("https://opendart.fss.or.kr/api/list.json",
                    dict(corp_code=cc, pblntf_ty="F", bgn_de="20050101", end_de=TODAY,
                         last_reprt_at="N", page_no=page, page_count=100), tag, "t3_f")
            if j is None:
                ok = False
                break
            if j.get("status") == "013":
                ph["n013"] += 1
                break
            rows += j.get("list") or []
            tp = int(j.get("total_page") or 1)
            if page >= tp or page >= 3:                   # census: >2페이지 corp 0 실측
                break
            page += 1
        if not ok:
            ph["fails"] += 1
            state["fails_total"] += 1
            jsonl_append("raw_t3_f.jsonl", {"corp_code": cc, "status": "FETCH_FAIL", "rows": []})
            check_fail_rate("t3_f", len(F_CORR_CORPS))
        else:
            jsonl_append("raw_t3_f.jsonl", {"corp_code": cc, "status": "000", "rows": rows})
        ph["corp_idx"] += 1
        ph["items_done"] += 1
        if ph["items_done"] % 25 == 0:
            save_state()
    recs = jsonl_load("raw_t3_f.jsonl")
    seen = {}
    for r in recs:
        seen[r["corp_code"]] = r
    all_rows = []
    for cc, r in sorted(seen.items()):
        all_rows += _list_rows_to_recs(r["rows"], cc, "F")
    write_parquet(pd.DataFrame(all_rows).astype(str), "t3_fgroup_rows.parquet")
    ph["status"] = "done"
    save_state()
    print("[t3_f] DONE (%d corps, calls=%d)" % (len(seen), state["calls_total"]), flush=True)


# ---------------------------------------------------------------- T2a 담보 majorstock
def run_t2a():
    ph = state["phases"]["t2a"]
    if ph["status"] == "done":
        return
    ph["status"] = "running"
    while ph["corp_idx"] < len(UNI):
        cc = UNI[ph["corp_idx"]]["corp_code"]
        j = api("https://opendart.fss.or.kr/api/majorstock.json", dict(corp_code=cc), "t2a:%s" % cc, "t2a")
        if j is None:
            ph["fails"] += 1
            state["fails_total"] += 1
            jsonl_append("raw_t2a.jsonl", {"corp_code": cc, "status": "FETCH_FAIL", "rows": []})
            check_fail_rate("t2a", len(UNI))
        else:
            if j.get("status") == "013":
                ph["n013"] += 1
            jsonl_append("raw_t2a.jsonl", {"corp_code": cc, "status": j.get("status"),
                                           "rows": j.get("list") or []})
        ph["corp_idx"] += 1
        ph["items_done"] += 1
        if ph["items_done"] % 25 == 0:
            save_state()
    recs = jsonl_load("raw_t2a.jsonl")
    seen = {}
    for r in recs:
        seen[r["corp_code"]] = r
    all_rows = []
    for cc, r in sorted(seen.items()):
        for row in r["rows"]:
            d = dict(row)
            d["ticker"] = TICKER.get(cc, "")
            d["snapshot_date"] = TODAY
            all_rows.append(d)
    write_parquet(pd.DataFrame(all_rows).astype(str), "t2a_majorstock_snapshot.parquet")
    ph["status"] = "done"
    save_state()
    print("[t2a] DONE (%d corps, calls=%d)" % (len(seen), state["calls_total"]), flush=True)


# ---------------------------------------------------------------- coverage 기술통계 (returns join 금지)
def _norm_opinion(v):
    v = str(v or "").strip()
    if v in ("", "-", "nan", "None"):
        return "missing"
    if "의견거절" in v:
        return "의견거절"
    if "부적정" in v:
        return "부적정"
    if "한정" in v:
        return "한정"
    if "적정" in v:
        return "적정"
    return "other"


_TRIVIAL = {"", "-", "nan", "None", "없음", "해당사항 없음", "해당사항없음", "해당 사항 없음", "해당사항 없음."}


def _nontrivial(v):
    return str(v or "").strip() not in _TRIVIAL


def build_coverage():
    cov = {}
    # T1
    p = OUT + "/t1_audit_opinion_fy2015_2025.parquet"
    if os.path.exists(p):
        df = pd.read_parquet(p)
        cur = df[df.get("bsns_year", pd.Series(dtype=str)).astype(str).str.contains("당기", na=False)].copy()
        by = {}
        for fy, g in df.groupby("query_fy"):
            gc = cur[cur["query_fy"] == fy]
            ops = gc["adt_opinion"].map(_norm_opinion) if "adt_opinion" in gc.columns else pd.Series(dtype=str)
            by[fy] = {
                "corps_queried": int(g["corp_code"].nunique()),
                "corps_with_data": int(g[g["api_status"] == "000"]["corp_code"].nunique()),
                "corps_013_empty": int(g[g["api_status"] == "013"]["corp_code"].nunique()),
                "rows_current_term": int(len(gc)),
                "opinion_dist": {k: int(v) for k, v in ops.value_counts().items()},
                "non_clean_opinion": int(ops.isin(["한정", "부적정", "의견거절"]).sum()),
                "emphs_nontrivial": int(gc["emphs_matter"].map(_nontrivial).sum()) if "emphs_matter" in gc.columns else None,
                "going_concern_kw": int(gc["emphs_matter"].astype(str).str.contains("계속기업", na=False).sum()) if "emphs_matter" in gc.columns else None,
            }
        cov["t1_audit_opinion"] = by
    # T3
    p = OUT + "/t3_a001_annual_reports.parquet"
    if os.path.exists(p):
        df = pd.read_parquet(p)
        df["year"] = df["rcept_dt"].astype(str).str.replace("-", "").str[:4]
        corr = df[df["report_nm"].astype(str).str.contains("기재정정", na=False)]
        cov["t3_a001"] = {
            "total_rows": int(len(df)),
            "corps": int(df["corp_code"].nunique()),
            "correction_rows": int(len(corr)),
            "corps_with_correction": int(corr["corp_code"].nunique()),
            "corrections_by_year": {k: int(v) for k, v in corr["year"].value_counts().sort_index().items()},
        }
    p = OUT + "/t3_fgroup_rows.parquet"
    if os.path.exists(p):
        df = pd.read_parquet(p)
        corr = df[df["report_nm"].astype(str).str.contains("정정", na=False)]
        cov["t3_fgroup"] = {
            "total_rows": int(len(df)),
            "corps": int(df["corp_code"].nunique()),
            "correction_rows": int(len(corr)),
            "census_expected_corr": 165,
        }
    # T2a
    p = OUT + "/t2a_majorstock_snapshot.parquet"
    if os.path.exists(p):
        df = pd.read_parquet(p)
        df["year"] = df["rcept_dt"].astype(str).str.replace("-", "").str[:4]

        def _num(x):
            try:
                return float(str(x).replace(",", "").strip())
            except Exception:
                return 0.0
        df["ctr_pos"] = df["ctr_stkqy"].map(_num) > 0
        df["resn_pledge"] = df["report_resn"].astype(str).str.contains("담보|질권", na=False)
        by = {}
        for y, g in df.groupby("year"):
            by[y] = {"reports": int(len(g)), "ctr_pos": int(g["ctr_pos"].sum()),
                     "resn_pledge": int(g["resn_pledge"].sum())}
        resn_top = df["report_resn"].astype(str).str.strip().str[:60].value_counts().head(20)
        cov["t2a_majorstock"] = {
            "total_rows": int(len(df)),
            "corps_covered": int(df["corp_code"].nunique()),
            "corps_with_pledge_resn": int(df[df["resn_pledge"]]["corp_code"].nunique()),
            "by_year": by,
            "resn_top20": {k: int(v) for k, v in resn_top.items()},
        }
    return cov


def write_manifest(final):
    run_calls = state["calls_total"] - RUN_CALLS0
    man = {
        "task": "FQ-004 stage1 no-parser acquisition (T1 audit opinion / T3 correction map / T2a pledge majorstock)",
        "date": time.strftime("%Y-%m-%d %H:%M:%S"),
        "hard_cap": HARD_CAP,
        "delay_s": DELAY,
        "calls_total": state["calls_total"],
        "calls_this_run": run_calls,
        "fails_total": state["fails_total"],
        "quota_events": state["quota_events"],
        "phases": state["phases"],
        "census_estimate_calls": CENSUS_EST,
        "resume_needed": not final,
        "resume_point": state["halt"],
        "resume_cmd": ".venv_qvest_ml/Scripts/python.exe 02_Infrastructure/data/dart_pledge_audit_acquire.py",
        "resume_note": "insider wave(02:00) 이후 재실행 — state_stage1.json 위치에서 이어서 수집" if not final else None,
        "coverage": build_coverage(),
        "no_returns_join": True,
        "universe_n": len(UNI),
    }
    atomic_json(MANIFEST_PATH, man)
    return man


def main():
    print("[stage1] start: universe=%d, F_corr_corps=%d, calls_so_far=%d, cap=%d"
          % (len(UNI), len(F_CORR_CORPS), state["calls_total"], HARD_CAP), flush=True)
    final = False
    try:
        run_t1()
        run_t3_a001()
        run_t3_f()
        run_t2a()
        final = True
    except Halt:
        pass
    state["runs"][-1]["finished"] = time.strftime("%Y-%m-%d %H:%M:%S")
    state["runs"][-1]["calls_at_end"] = state["calls_total"]
    save_state()
    man = write_manifest(final)
    print("[stage1] %s. calls_total=%d (this run %d), fails=%d, resume_needed=%s"
          % ("COMPLETE" if final else "PARTIAL", state["calls_total"],
             man["calls_this_run"], state["fails_total"], man["resume_needed"]), flush=True)


if __name__ == "__main__":
    main()
