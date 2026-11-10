#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# test_scn_paper_query_sorts.py — 논문 수집 질의 재편 · 질의별 정렬(도훈 11-10 PAPER-QUERY-AND-ORDER-REDESIGN-20261110)
#
# 격리: 임시 루트에 paper_recharge_mcp.py · paper_id_norm.py · quant_sources.json 사본과 가짜 stdio MCP 서버(.mcp.json)를 둔다.
#   가짜 서버는 tools/call 인자를 기록하고 합성 논문을 돌려준다. 네트워크 · arXiv · uvx 호출 없음 · 운영 stage_artifacts 무접촉.
# 시나리오:
#   S1 질의 40개(고유 문자열) · 감사 §9 P-C1(a) 10개가 문자열 그대로 뒤에 붙음 · 테마 표지
#   S2 호출 50회 — 기존 30개 relevance 1회 · 표적 10개 relevance + date 각 1회(첫 시도 인자)
#   S3 범주 = 설정값 · date_from 없음(recency 0 유지)
#   S4 행에 sort_by · theme · 두 정렬에서 온 같은 논문은 1행(dedup 경로 그대로)
#   S5 질의 1개 실패 → 나머지 정상 · errors 에 {query, sort_by}
#   S6 한 질의 타임아웃(소스 치환으로 시한 단축 + 성사 단정)이 실행 전체를 죽이지 않는다
#   S7 전부 실패 → errors 키 집합 = calls 키 집합 · status mcp_ok_no_candidates(R 쪽이 강등)
#   S8 전송 사망(서버 종료) 2연속 → 남은 호출 skipped_after_transport_failure · calls 50 유지 · status mcp_partial_transport_failure(^mcp_ok 아님 → 경보)
#   S8b 전 호출 전송 실패 = mcp_error
#   S9 문자열 전용 옛 설정 = 종전 동작(전부 기본 정렬 1회) · S10 잘못된 sorts → query_spec_errors + 기본 정렬
import io, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MCP = os.path.join(ROOT, "02_Infrastructure", "tools", "paper_recharge_mcp.py")
NORM = os.path.join(ROOT, "02_Infrastructure", "ops", "paper_id_norm.py")
QS = os.path.join(ROOT, "02_Infrastructure", "docs", "quant_sources.json")
PY = sys.executable
RES = []
BASE = tempfile.mkdtemp(prefix="scn_paper_qs_")
_N = [0]

PC1A = ["defensive equity low beta betting against beta drawdown",
        "tail risk hedging equity crash protection portfolio",
        "downside beta asymmetric correlation cross-section",
        "time-series momentum trend following equity index crash",
        "managed volatility conditional exposure equity",
        "momentum crash dynamic momentum",
        "quantile regression distributional forecast stock returns",
        "conditional skewness left tail stock selection",
        "crisis alpha bear market stock performance",
        "Korean stock market foreign investor flow defensive"]

FAKE = r'''
import json, sys
log, mode, arg = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "")
n_call = 0
IDS = {}
def pid(s):
    # 문자열마다 고유 번호(충돌 없음 — 해시 충돌로 dedup 행 수가 흔들리지 않게)
    return "2698.%05d" % IDS.setdefault(s, len(IDS) + 1)
def paper(i):
    return {"id": i, "title": "paper " + i, "categories": ["q-fin.PM"], "published": "2026-11-01", "abstract": "equity factor"}
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        continue
    m = json.loads(line)
    if "id" not in m:
        continue
    meth = m.get("method")
    if meth == "initialize":
        res = {"protocolVersion": "2024-11-05", "capabilities": {}}
    elif meth == "tools/list":
        res = {"tools": [{"name": "search_papers"}]}
    elif meth == "tools/call":
        a = m["params"]["arguments"]
        n_call += 1
        with open(log, "a", encoding="utf-8") as f:
            f.write(json.dumps(a, ensure_ascii=False) + "\n")
        q = a.get("query", "")
        if mode == "die_after" and n_call > int(arg):
            sys.exit(0)
        if mode == "all_fail" or (mode == "fail_one" and q == arg):
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -1, "message": "rate limited"}}) + "\n"); sys.stdout.flush()
            continue
        if mode == "hang_one" and q == arg:
            continue
        sb = a.get("sort_by", "none")
        papers = [paper(pid(q)), paper(pid(q + "|" + sb))]
        res = {"content": [{"type": "text", "text": json.dumps({"papers": papers})}]}
    else:
        res = {}
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": res}) + "\n"); sys.stdout.flush()
'''


def check(name, ok, detail=""):
    RES.append((name, bool(ok)))
    print(("  [ok]   " if ok else "  [FAIL] ") + name + ("" if ok else "  " + str(detail)[:400]))


def run(mode="ok", arg="", qs_obj=None, mcp_src=None):
    _N[0] += 1
    r = os.path.join(BASE, "r%02d" % _N[0])
    os.makedirs(os.path.join(r, "02_Infrastructure", "tools")); os.makedirs(os.path.join(r, "02_Infrastructure", "ops"))
    os.makedirs(os.path.join(r, "02_Infrastructure", "docs")); os.makedirs(os.path.join(r, "out"))
    mp = os.path.join(r, "02_Infrastructure", "tools", "paper_recharge_mcp.py")
    if mcp_src is None:
        shutil.copy(MCP, mp)
    else:
        io.open(mp, "w", encoding="utf-8").write(mcp_src)
    shutil.copy(NORM, os.path.join(r, "02_Infrastructure", "ops"))
    if qs_obj is None:
        shutil.copy(QS, os.path.join(r, "02_Infrastructure", "docs", "quant_sources.json"))
    else:
        io.open(os.path.join(r, "02_Infrastructure", "docs", "quant_sources.json"), "w", encoding="utf-8").write(json.dumps(qs_obj))
    fake = os.path.join(r, "fake_mcp.py"); io.open(fake, "w", encoding="utf-8").write(FAKE)
    log = os.path.join(r, "calls.jsonl")
    io.open(os.path.join(r, ".mcp.json"), "w", encoding="utf-8").write(json.dumps(
        {"mcpServers": {"arxiv": {"command": PY, "args": ["-X", "utf8", "-I", fake, log, mode, arg]}}}))
    out = os.path.join(r, "out", "mcp_discovery_20261110.json")
    p = subprocess.run([PY, "-X", "utf8", "-I", mp, "--project-root", r, "--out", out], capture_output=True, timeout=240)
    rep = json.load(io.open(out, encoding="utf-8")) if os.path.exists(out) else {}
    calls = [json.loads(l) for l in io.open(log, encoding="utf-8")] if os.path.exists(log) else []
    return rep, calls, p


def first_attempts(calls_log):
    """각 (query, sort_by) 의 첫 시도 인자 — 폴백 시도가 있어도 첫 인자만."""
    seen, out = set(), []
    for a in calls_log:
        k = (a.get("query"), a.get("sort_by"))
        if a.get("sort_by") is None or k in seen:
            continue
        seen.add(k); out.append(a)
    return out


def ekey(e, dflt):
    return (e.get("query"), e.get("sort_by") or dflt)


def main():
    try:
        cfg = json.load(io.open(QS, encoding="utf-8"))["arxiv_queries"]
        rep, log, p = run()
        qs = rep.get("queries") or []
        check("S1a 질의 40개 · 고유 문자열", len(qs) == 40 and len(set(qs)) == 40, (len(qs), p.stderr[-300:]))
        check("S1b 감사 P-C1(a) 10개가 문자열 그대로 · 기존 30개 뒤", qs[30:] == PC1A, qs[30:])
        specs = rep.get("query_specs") or []
        th = [s.get("theme") for s in specs]
        check("S1c 테마 표지 — 표적 10개 = defense 8 · distribution 2 · 기존 30개도 표지",
              th[30:].count("defense") == 8 and th[30:].count("distribution") == 2 and all(th[:30]), th)
        fa = first_attempts(log)
        rel = [a["query"] for a in fa if a["sort_by"] == "relevance"]; dat = [a["query"] for a in fa if a["sort_by"] == "date"]
        check("S2a 호출 50회(calls · n_calls · 서버 기록)", len(rep.get("calls") or []) == 50 and rep.get("n_calls") == 50 and len(fa) == 50,
              (len(rep.get("calls") or []), rep.get("n_calls"), len(fa)))
        check("S2b 기존 30개 = relevance 1회 · 표적 10개 = relevance + date 각 1회",
              rel == qs and dat == PC1A, (len(rel), len(dat)))
        check("S3 범주 = 설정값 · date_from 없음 · max_results 설정값",
              all(a.get("categories") == cfg["categories"] and "date_from" not in a and a.get("max_results") == cfg["max_results_per_query"] for a in fa))
        cands = rep.get("candidates") or []
        ids = [c.get("arxiv_id") for c in cands]
        check("S4a 행에 sort_by · theme", cands and all(c.get("sort_by") in ("relevance", "date") and c.get("theme") for c in cands))
        # 질의 q 의 공통 논문 pid(q) 는 두 정렬 모두에서 오지만 1행
        check("S4b 두 정렬에서 온 같은 논문 = 1행(dedup 그대로) · 행 수 = 40 + 50",
              len(ids) == len(set(ids)) == 90, (len(ids), len(set(ids))))
        check("S4c status mcp_ok · schema v2", rep.get("status") == "mcp_ok" and rep.get("schema_version") == "paper_recharge_mcp_v2", rep.get("status"))

        rep5, _, _ = run("fail_one", PC1A[0])
        e5 = [e for e in rep5.get("errors") or [] if isinstance(e, dict)]
        ek5 = {ekey(e, "relevance") for e in e5}
        check("S5 질의 1개 실패 → 그 질의 두 정렬만 errors{query, sort_by} · 나머지 정상(mcp_ok)",
              ek5 == {(PC1A[0], "relevance"), (PC1A[0], "date")} and rep5.get("status") == "mcp_ok"
              and sum(1 for c in rep5.get("calls") or [] if c.get("ok")) == 48, (ek5, rep5.get("status")))

        src = io.open(MCP, encoding="utf-8").read()
        old = "timeout_sec: int = 60"
        mut = src.replace(old, "timeout_sec: int = 3")
        check("S6a 시한 단축 치환 성사(1곳)", mut != src and src.count(old) == 1)
        rep6, _, _ = run("hang_one", qs[3], mcp_src=mut)
        c6 = rep6.get("calls") or []
        bad6 = [c for c in c6 if not c.get("ok")]
        check("S6b 한 질의 타임아웃 → 그 호출만 실패 · 나머지 49 정상 · status mcp_ok",
              len(c6) == 50 and len(bad6) == 1 and bad6[0].get("query") == qs[3] and rep6.get("status") == "mcp_ok",
              (len(c6), [(c.get("query"), c.get("exception")) for c in bad6], rep6.get("status")))

        rep7, _, _ = run("all_fail")
        dflt = rep7.get("sort_by") or "relevance"
        ck7 = {(c.get("query"), c.get("sort_by")) for c in rep7.get("calls") or []}
        ek7 = {ekey(e, dflt) for e in rep7.get("errors") or [] if isinstance(e, dict)}
        check("S7 전부 실패 → errors 키 집합 = calls 키 집합(50) · status mcp_ok_no_candidates",
              len(ck7) == 50 and ck7 == ek7 and rep7.get("status") == "mcp_ok_no_candidates", (len(ck7), len(ek7), rep7.get("status")))

        rep8, log8, _ = run("die_after", "5")
        c8 = rep8.get("calls") or []
        sk8 = [c for c in c8 if c.get("skipped") == "skipped_after_transport_failure"]
        check("S8 서버 사망 → 2연속 전송 실패 뒤 나머지 skipped · calls 50 유지 · 성공분 보존",
              len(c8) == 50 and len(sk8) == 50 - 5 - 2 and sum(1 for c in c8 if c.get("ok")) == 5 and len(rep8.get("candidates") or []) > 0,
              (len(c8), len(sk8), rep8.get("status")))
        st8 = str(rep8.get("status") or "")
        # 일일 R 마커 조건 = grepl("^mcp_ok", status) 가 거짓이어야 경보가 선다(침묵 실패 회귀 방지 · 재수리 11-10)
        check("S8c 도중 사망 = mcp_partial_transport_failure(skipped=43/50) · ^mcp_ok 아님(경보 마커 조건 성립)",
              st8 == "mcp_partial_transport_failure(skipped=43/50)" and not st8.startswith("mcp_ok")
              and rep8.get("n_calls_skipped") == 43, st8)
        rep8b, _, _ = run("die_after", "0")
        check("S8b 전 호출 전송 실패 = mcp_error(종전 '실행 전체 실패' 의미 보존)", rep8b.get("status") == "mcp_error", rep8b.get("status"))

        old_cfg = {"arxiv_queries": {"queries": ["q one", "q two", "q three"], "categories": ["q-fin.PM"],
                                     "max_results_per_query": 10, "recency_days": 0, "sort_by": "relevance", "max_queries": 40}}
        rep9, log9, _ = run(qs_obj=old_cfg)
        fa9 = first_attempts(log9)
        check("S9 문자열 전용 옛 설정 = 종전 동작(3질의 · relevance 1회씩 · queries 그대로)",
              rep9.get("queries") == ["q one", "q two", "q three"] and [(a["query"], a["sort_by"]) for a in fa9] ==
              [("q one", "relevance"), ("q two", "relevance"), ("q three", "relevance")] and rep9.get("status") == "mcp_ok", (rep9.get("queries"), fa9))
        bad_cfg = json.loads(json.dumps(old_cfg))
        bad_cfg["arxiv_queries"]["queries"] = [{"q": "q bad", "theme": "defense", "sorts": ["bogus"]}, {"q": "q mix", "sorts": ["date", "nope"]}, 7]
        rep10, log10, _ = run(qs_obj=bad_cfg)
        fa10 = first_attempts(log10)
        se = rep10.get("query_spec_errors") or []
        check("S10 잘못된 sorts · 형식 → query_spec_errors 기록 · 유효분만(기본 정렬 폴백)",
              len(se) == 3 and [(a["query"], a["sort_by"]) for a in fa10] == [("q bad", "relevance"), ("q mix", "date")], (se, fa10))
    finally:
        shutil.rmtree(BASE, ignore_errors=True)
    nf = sum(1 for _, ok in RES if not ok)
    print(json.dumps({"test": "scn_paper_query_sorts", "pass": len(RES) - nf, "fail": nf, "total": len(RES)}))
    sys.exit(1 if nf else 0)


if __name__ == "__main__":
    main()
