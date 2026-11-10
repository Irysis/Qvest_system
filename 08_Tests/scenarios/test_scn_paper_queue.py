#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# test_scn_paper_queue.py — 감사 레인 C 시나리오: 라우팅 산출 → 충실구현 큐(alpha_pending · rf_next_paper_pick)
#
# 격리: 임시 stage 디렉터리에 합성 route/queue 파일만 둔다. 운영 stage_artifacts · 등록부에 쓰지 않는다
#   (rf_next_paper_pick 의 소비 기록 읽기는 운영 06_Registry 를 **읽기만** 한다 — 합성 id 2699.* 는 거기 없다).
# 시나리오:
#   Q1 라우터가 뒤 실행에서 testable → not_relevant/skip 으로 고치면 큐에서 빠진다(11-10 수리 · 수리 전 = 남음)
#   Q2 반대(skip → testable)는 큐에 들어온다
#   Q3 prefilter 스텁 · verdict=redundant 는 재판정이 아니다(빼지 않는다)
#   Q4 판 번호 · 접두 · URL 만 다른 중복은 한 편이다
#   Q5 깨진 route 파일 1개 — 나머지는 계속 읽힌다
#   Q6 두 슬롯 경합 — 한 슬롯이 쥔 논문(--exclude)은 다음 슬롯에 안 간다
#   Q7 alpha_pending() 반환 순서 = 처음 본 날짜 순(FIFO — 그 함수의 순서는 불변). 선택 순서는 11-10 도훈 결정
#      (PAPER-QUERY-AND-ORDER-REDESIGN-20261110)의 등록부 규칙이 따로 정한다(동률이면 FIFO 꼬리) — 규칙 시험 = test_scn_paper_order.py
#   M1 돌연변이: 수리(최신 판정 거부)를 소스 치환으로 끄면 Q1 이 깨진다(발화 실증)
import io, json, os, re, shutil, subprocess, sys, tempfile, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OPS = os.path.join(ROOT, "02_Infrastructure", "ops")
PY = sys.executable
RES = []


def check(name, ok, detail=""):
    RES.append((name, bool(ok)))
    print(("  [ok]   " if ok else "  [FAIL] ") + name + ("" if ok else "  " + str(detail)[:300]))


def load_mod(path, name):
    sys.path.insert(0, os.path.dirname(path))
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def paper(pid, engine, verdict, title=None):
    return {"title": title or ("t " + pid), "id": pid, "paper_key": "axv:" + re.sub(r"^arxiv:", "", pid),
            "source": "arxiv", "engine": engine, "verdict": verdict,
            "route": "replication" if verdict == "testable" else "skip", "factor_candidate": None, "reason": "r"}


def write(stage, name, obj):
    with io.open(os.path.join(stage, name), "w", encoding="utf-8") as f:
        if isinstance(obj, str):
            f.write(obj)
        else:
            json.dump(obj, f, ensure_ascii=False)


def route(date, papers, prefilter=False):
    d = {"date": date, "schema_version": "paper_router_v5", "papers": papers}
    if prefilter:
        d["generated_by"] = "prefilter"
    return d


def scenario(stage):
    write(stage, "alpha_search_route_20261015.json", route("20261015", [
        paper("2699.00001", "return", "testable"),        # Q1 → 뒤에서 not_relevant
        paper("2699.00002", "return", "skip"),            # Q2 → 뒤에서 testable
        paper("2699.00003", "defense", "testable"),       # Q3 → 뒤에서 redundant · prefilter 스텁만
        paper("2699.00004", "construction", "testable"),  # Q1b → 뒤에서 data_pipeline_required
        paper("2699.00006", "return", "testable"),        # Q7 순서 기준(먼저 본 것)
    ]))
    write(stage, "alpha_search_route_20261017.json", route("20261017", [
        paper("2699.00001", "not_relevant", "skip"),
        paper("2699.00002", "return", "testable"),
        paper("2699.00003", "defense", "redundant"),
        paper("2699.00004", "construction", "data_pipeline_required"),
        paper("arxiv:2699.00005v2", "return", "testable"),   # Q4 판 번호
        paper("2699.00007", "return", "testable"),
    ]))
    write(stage, "alpha_search_route_20261018.json", route("20261018", [
        paper("2699.00003", "defense", "redundant"),
        paper("2699.00005", "return", "redundant")], prefilter=True))
    write(stage, "alpha_search_route_20261019.json", route("20261019", [
        paper("https://arxiv.org/abs/2699.00005v1", "return", "testable")]))
    write(stage, "alpha_search_route_20261020.json", "{ broken json")   # Q5


def main():
    base = tempfile.mkdtemp(prefix="scn_paper_q_")
    try:
        stage = os.path.join(base, "stage"); os.makedirs(stage)
        scenario(stage)
        rpp = load_mod(os.path.join(OPS, "research_pool_predicates.py"), "research_pool_predicates")
        pend = rpp.alpha_pending(stage)
        ks = list(pend.keys())
        check("Q1 뒤 실행이 not_relevant 로 고친 논문은 큐에서 빠진다", "2699.00001" not in pend, ks)
        check("Q1b 뒤 실행이 data_pipeline_required 로 고친 논문도 빠진다", "2699.00004" not in pend, ks)
        check("Q2 skip → testable 로 고친 논문은 들어온다", "2699.00002" in pend, ks)
        check("Q3 redundant · prefilter 스텁은 재판정이 아니다(남는다)", "2699.00003" in pend, ks)
        check("Q4 판 번호 · 접두 · URL 만 다른 중복 = 1편", sum(1 for k in ks if k.startswith("2699.00005")) == 1, ks)
        check("Q5 깨진 route 파일이 있어도 나머지는 읽힌다", "2699.00007" in pend, ks)
        check("Q7 큐 순서 = 처음 본 날짜 순(FIFO)", ks.index("2699.00006") < ks.index("2699.00007"), ks)

        # Q6 슬롯 경합 — 발행기와 같은 CLI(--exclude · --list)로
        def pick(*extra):
            p = subprocess.run([PY, "-X", "utf8", os.path.join(OPS, "rf_next_paper_pick.py"), stage, *extra],
                               capture_output=True, text=True, encoding="utf-8", timeout=60)
            return p.stdout.strip()
        first = pick("--list", "1")
        head = re.findall(r"2699\.\d{5}", first)[:1]
        nxt = pick("--exclude", "axv:%s,%s" % (head[0], head[0]) if head else "", "--list", "1")
        nh = re.findall(r"2699\.\d{5}", nxt)[:1]
        check("Q6 한 슬롯이 쥔 논문(--exclude)은 다음 슬롯에 안 간다", bool(head) and bool(nh) and nh != head, (first[:200], nxt[:200]))

        # M1 돌연변이 — 최신 판정 거부 줄을 끈 사본
        src = io.open(os.path.join(OPS, "research_pool_predicates.py"), encoding="utf-8").read()
        mut = src.replace("        del pend[p]\n", "        pass\n")
        check("M1 치환 성사(1곳 이상)", mut != src)
        mdir = os.path.join(base, "mut"); os.makedirs(mdir)
        shutil.copy(os.path.join(OPS, "paper_id_norm.py"), mdir)
        io.open(os.path.join(mdir, "research_pool_predicates.py"), "w", encoding="utf-8").write(mut)
        code = ("import sys;sys.path.insert(0,%r);import research_pool_predicates as m;"
                "print('IN' if '2699.00001' in m.alpha_pending(%r) else 'OUT')") % (mdir, stage)
        r = subprocess.run([PY, "-X", "utf8", "-I", "-c", code], capture_output=True, text=True, timeout=60)
        check("M1 돌연변이 사본에선 Q1 논문이 큐에 남는다(검사가 수리를 잡는다)", r.stdout.strip() == "IN", (r.stdout, r.stderr[-300:]))
    finally:
        shutil.rmtree(base, ignore_errors=True)
    nf = sum(1 for _, ok in RES if not ok)
    print(json.dumps({"test": "scn_paper_queue", "pass": len(RES) - nf, "fail": nf, "total": len(RES)}))
    sys.exit(1 if nf else 0)


if __name__ == "__main__":
    main()
