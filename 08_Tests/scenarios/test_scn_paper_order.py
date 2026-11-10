#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# test_scn_paper_order.py — 다음 논문 순서 규칙(06_Registry/next_paper_order.json · 도훈 11-10 PAPER-QUERY-AND-ORDER-REDESIGN-20261110)
#
# 격리: 임시 루트에 ops 3종(research_pool_predicates · rf_next_paper_pick · paper_id_norm)을 복사하고 그 루트의 06_Registry
#   (순서 설정 사본 · 합성 L1 · 합성 건너뛰기 목록)와 stage 만 쓴다. 운영 등록부 · stage_artifacts · .cache 무접촉. 네트워크 없음.
# 시나리오:
#   O1 빈 엔진 우선(소비 건수 적은 엔진이 앞) · O2 construction 은 기저(return/defense) 소비 0 이면 뒤로 → 1편 소비 뒤 해제
#   O3 long_leg yes > unknown > no(불리언 · 대소문자 · long_only 정규화) · O4 crisis_evidence=reported 우선 · O5 모두 동률 = FIFO
#   O6 엔진 미상 = 뒤 · O7 마지막 비-prefilter 엔진을 쓴다 · O8 L1 건수(combo: 제외 · 키 정규화 · 중복 1편)
#   O9 설정 부재 · 깨짐 · disabled · 모르는 step · schema 불일치 · L1 깨짐 → FIFO + stderr + order_why
#   O10 step 하나를 끄면 그 키만 빠진다 · O11 결정론(CLI 2회 바이트 동일 · mtime 무관)
#   O12 정보 경계 — 등급 · 성과 · confidence 필드를 바꿔도 순서 · 키 불변 + 소스 정적 단정 + _order_view 화이트리스트
#   O13 선택기 기존 제약(건너뛰기 · revoked 재후보 · L1 소비 · 원문 링크 · --exclude · --only-key) 유지 · O14 order_why 가 키와 일치
#   O15 공급기(next_replication.R) E2E — 요청 · 로그에 order_why · 설정 삭제 → FIFO 상단 + 'fifo (next_paper_order missing)'
#   M1~M4 돌연변이: 각 단계 키를 상수로 치환(성사 단정)하면 해당 시나리오 순서가 바뀐다(검사가 규칙을 잡는다)
import io, json, os, re, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OPS = os.path.join(ROOT, "02_Infrastructure", "ops")
CFG = os.path.join(ROOT, "06_Registry", "next_paper_order.json")
PY = sys.executable
RES = []
BASE = tempfile.mkdtemp(prefix="scn_paper_order_")
_N = [0]


def check(name, ok, detail=""):
    RES.append((name, bool(ok)))
    print(("  [ok]   " if ok else "  [FAIL] ") + name + ("" if ok else "  " + str(detail)[:400]))


def P(pid, engine, verdict="testable", **kw):
    d = {"title": "t " + pid, "id": pid, "paper_key": "axv:" + pid, "source": "arxiv", "engine": engine,
         "verdict": verdict, "route": "replication" if verdict == "testable" else "skip", "factor_candidate": None, "reason": "r"}
    d.update(kw)
    return d


def wjson(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj, ensure_ascii=False))


def make_root(routes, l1_keys=(), cfg="copy", skip=None, pred_src=None, l1_raw=None):
    """routes = [(date, [papers], prefilter?)] · l1_keys = 소비 원장 paper_key 목록 · cfg = 'copy' | dict | str(raw) | None(부재)."""
    _N[0] += 1
    r = os.path.join(BASE, "r%02d" % _N[0])
    ops = os.path.join(r, "02_Infrastructure", "ops"); os.makedirs(ops)
    for f in ("rf_next_paper_pick.py", "paper_id_norm.py"):
        shutil.copy(os.path.join(OPS, f), ops)
    if pred_src is None:
        shutil.copy(os.path.join(OPS, "research_pool_predicates.py"), ops)
    else:
        wjson(os.path.join(ops, "research_pool_predicates.py"), pred_src)
    reg = os.path.join(r, "06_Registry"); os.makedirs(reg)
    if cfg == "copy":
        shutil.copy(CFG, reg)
    elif cfg is not None:
        wjson(os.path.join(reg, "next_paper_order.json"), cfg)
    if l1_raw is not None:
        wjson(os.path.join(reg, "reinforce_ledger_l1.json"), l1_raw)
    else:
        wjson(os.path.join(reg, "reinforce_ledger_l1.json"),
              {"entries": [{"paper_key": k, "status": "active", "base_grade": "C", "target_grade": "A"} for k in l1_keys]})
    wjson(os.path.join(reg, "replication_skiplist.json"), skip or {"entries": []})
    stage = os.path.join(r, "stage_artifacts", "paper_recharge"); os.makedirs(stage)
    for date, papers, *pf in routes:
        d = {"date": date, "schema_version": "paper_router_v5", "papers": papers}
        if pf and pf[0]:
            d["generated_by"] = "prefilter"
        wjson(os.path.join(stage, "alpha_search_route_%s.json" % date), d)
    return r


def cli_ordered(r, raw=False):
    """임시 루트의 술어 CLI(alpha-pending-ordered) → [(key, why, order_key)] · stderr."""
    p = subprocess.run([PY, "-X", "utf8", "-I", os.path.join(r, "02_Infrastructure", "ops", "research_pool_predicates.py"),
                        "alpha-pending-ordered", os.path.join(r, "stage_artifacts", "paper_recharge"), os.path.join(r, "06_Registry")],
                       capture_output=True, timeout=120)
    out = p.stdout.decode("utf-8", "replace"); err = p.stderr.decode("utf-8", "replace")
    if raw:
        return p.stdout, err
    rows = []
    for ln in out.splitlines():
        ln = ln.strip()
        if ln.startswith("{"):
            try:
                o = json.loads(ln)
                rows.append((o.get("key"), o.get("why"), o.get("order_key")))
            except Exception:
                pass
    return rows, err


def keys(r):
    rows, _ = cli_ordered(r)
    return [k for k, _, _ in rows]


def pick(r, *extra):
    p = subprocess.run([PY, "-X", "utf8", "-I", os.path.join(r, "02_Infrastructure", "ops", "rf_next_paper_pick.py"),
                        os.path.join(r, "stage_artifacts", "paper_recharge"), *extra],
                       capture_output=True, timeout=120)
    out = []
    for ln in p.stdout.decode("utf-8", "replace").splitlines():
        ln = ln.strip()
        if ln.startswith("{"):
            try:
                out.append(json.loads(ln))
            except Exception:
                pass
    return out, p.stderr.decode("utf-8", "replace")


def short(ks):
    return [str(k)[-2:] for k in ks]


# ── 시나리오 정의 (순수 정의 — 돌연변이 시험이 재사용) ──
def sc_o1(**kw):   # return 2편 소비 · defense 0 → defense 가 앞
    return make_root([("20261001", [P("2699.90001", "return", "skip"), P("2699.90002", "return", "skip")]),
                      ("20261002", [P("2699.10001", "return"), P("2699.10002", "defense")])],
                     l1_keys=["2699.90001", "axv:2699.90002"], **kw)


def sc_o2(base_consumed=False, **kw):
    rts = [("20261002", [P("2699.20001", "construction"), P("2699.20002", "return")])]
    l1 = []
    if base_consumed:
        rts.insert(0, ("20261001", [P("2699.90011", "defense", "skip")]))
        l1 = ["2699.90011"]
    return make_root(rts, l1_keys=l1, **kw)


def sc_o3(**kw):
    return make_root([("20261002", [
        P("2699.30001", "return", long_leg="no"),
        P("2699.30002", "return"),                                   # 결측 = unknown
        P("2699.30003", "return", long_leg="yes"),
        P("2699.30004", "return", long_leg=True),
        P("2699.30005", "return", long_leg="False"),
        P("2699.30006", "return", long_leg="unknown", long_only="YES")])], **kw)


def sc_o4(**kw):
    return make_root([("20261002", [
        P("2699.40001", "return", crisis_evidence="not_reported"),
        P("2699.40002", "return", crisis_evidence="reported"),
        P("2699.40003", "return")])], **kw)


def main():
    try:
        sys.path.insert(0, OPS)
        import research_pool_predicates as rpp  # noqa: E402

        check("O0 설정 파일 존재 · schema next_paper_order_v1", os.path.exists(CFG) and
              json.load(io.open(CFG, encoding="utf-8")).get("schema") == "next_paper_order_v1")

        r1 = sc_o1()
        k1 = keys(r1)
        check("O1 빈 엔진 우선 — defense(소비 0)가 return(소비 2)보다 앞", k1[:2] == ["2699.10002", "2699.10001"], k1)

        k2a = keys(sc_o2())
        check("O2a construction 은 기저(return/defense) 소비 0 이면 뒤로", k2a == ["2699.20002", "2699.20001"], k2a)
        k2b = keys(sc_o2(base_consumed=True))
        check("O2b 기저 1편 소비 뒤 해제 — 둘 다 소비 0 동률 → FIFO", k2b[:2] == ["2699.20001", "2699.20002"], k2b)

        k3 = keys(sc_o3())
        check("O3 long_leg yes > unknown > no (True · 'False' · long_only=YES 정규화)",
              short(k3) == ["03", "04", "06", "02", "01", "05"], short(k3))

        k4 = keys(sc_o4())
        check("O4 crisis_evidence=reported 우선 · 나머지 FIFO", short(k4) == ["02", "01", "03"], short(k4))

        r5 = make_root([("20261001", [P("2699.50002", "return"), P("2699.50001", "return")]),
                        ("20261003", [P("2699.50003", "return")])])
        k5 = keys(r5)
        check("O5 모두 동률 = 처음 본 순서(FIFO · 키 이름순 아님)", short(k5) == ["02", "01", "03"], short(k5))

        r6 = make_root([("20261001", [P("2699.90061", "return", "skip"), P("2699.90062", "return", "skip"), P("2699.90063", "return", "skip")]),
                        ("20261002", [P("2699.60001", None), P("2699.60002", "return")])],
                       l1_keys=["2699.90061", "2699.90062", "2699.90063"])
        k6 = keys(r6)
        check("O6 엔진 미상은 소비 많은 엔진보다도 뒤", k6[:2] == ["2699.60002", "2699.60001"], k6)

        r7 = make_root([("20261001", [P("2699.90071", "return", "skip"), P("2699.70002", "return"), P("2699.70001", "return")]),
                        ("20261002", [P("2699.70001", "defense")]),
                        ("20261003", [P("2699.70001", None, "redundant")], True)],
                       l1_keys=["2699.90071"])
        rows7, _ = cli_ordered(r7)
        check("O7 마지막 비-prefilter 엔진(defense)을 쓴다 — prefilter 스텁(engine null)은 무시",
              [k for k, _, _ in rows7][:2] == ["2699.70001", "2699.70002"] and "engine=defense" in (rows7[0][1] or ""), rows7[:2])

        # O8 L1 건수 — 순수 함수
        led = os.path.join(BASE, "o8_l1.json")
        wjson(led, {"entries": [{"paper_key": "axv:2699.80001"}, {"paper_key": "2699.80001v2"}, {"paper_key": "arxiv:2699.80001"},
                                {"paper_key": "combo:2699.80001+2699.80002"}, {"paper_key": "2699.80003"}, {"paper_key": "mystery_x"},
                                {"paper_key": ""}, {"status": "active"}]})
        meta8 = {"2699.80001": {"engine": "return"}, "2699.80002": {"engine": "defense"}, "2699.80003": {"engine": "Construction"}}
        c8 = rpp.l1_engine_counts(led, meta8)
        check("O8 L1 건수 — combo: 제외 · axv:/arxiv:/판 번호 = 1편 · 미매핑 따로",
              c8[0] == {"return": 1, "defense": 0, "construction": 1} and c8[1] == 1 and c8[2] == 3, c8)

        # O9 안전한 폴백 — 같은 O1 시나리오(규칙이면 비-FIFO)
        fifo1 = ["2699.10001", "2699.10002"]
        good = json.load(io.open(CFG, encoding="utf-8"))
        bad_step = json.loads(json.dumps(good)); bad_step["steps"].append({"name": "grade_bonus"})
        bad_schema = dict(good, schema="next_paper_order_v0")
        cases = [("missing", dict(cfg=None)), ("unreadable", dict(cfg="{ broken")), ("disabled", dict(cfg=dict(good, enabled=False))),
                 ("unknown_step", dict(cfg=bad_step)), ("schema", dict(cfg=bad_schema)), ("l1_unreadable", dict(l1_raw="[ broken"))]
        for reason, kw in cases:
            r = sc_o1(**kw)
            rows, err = cli_ordered(r)
            ks = [k for k, _, _ in rows]
            why0 = rows[0][1] if rows else ""
            check("O9 %s → FIFO + stderr + order_why" % reason,
                  ks[:2] == fifo1 and ("fallback=fifo reason=%s" % reason) in err and
                  str(why0).startswith("fifo (next_paper_order %s)" % reason), (ks, err[-200:], why0))

        # O9b 형이 틀린 단계 매개변수 → 평가 예외가 선택을 멈추지 않고 FIFO(재수리 11-10)
        def _mut(name, field, val):
            c = json.loads(json.dumps(good))
            hit = [s for s in c["steps"] if s.get("name") == name]
            assert hit, name
            hit[0][field] = val
            return c
        bad_types = [("rule_eval_error:ValueError", _mut("construction_needs_base", "min_base_consumed", "one")),
                     ("rule_eval_error:AttributeError", _mut("long_leg", "rank", ["yes", "no"])),
                     ("rule_eval_error:TypeError", _mut("construction_needs_base", "base_engines", 5))]
        for reason, cfgx in bad_types:
            rows, err = cli_ordered(sc_o1(cfg=cfgx))
            ks = [k for k, _, _ in rows]
            why0 = rows[0][1] if rows else ""
            check("O9b %s → FIFO + stderr + order_why(선택 정지 없음)" % reason,
                  ks[:2] == fifo1 and ("fallback=fifo reason=%s" % reason) in err and
                  str(why0).startswith("fifo (next_paper_order %s)" % reason), (ks, err[-300:], why0))
        p9, _ = pick(sc_o1(cfg=bad_types[0][1]))
        check("O9c 형 오류 설정에서도 선택기는 논문을 낸다(alpha_pending_failed 아님)",
              p9 and p9[0].get("paper_key") == "2699.10001" and not p9[0].get("error"), p9)

        # O10 step 하나 끄기
        off = json.loads(json.dumps(good))
        for s in off["steps"]:
            if s.get("name") == "long_leg":
                s["enabled"] = False
        rows10, _ = cli_ordered(sc_o3(cfg=off))
        rows3, _ = cli_ordered(sc_o3())
        check("O10 long_leg 만 끄면 그 키만 빠진다(순서 = FIFO · 키 길이 1 감소)",
              short([k for k, _, _ in rows10]) == ["01", "02", "03", "04", "05", "06"] and
              len(rows10[0][2]) == len(rows3[0][2]) - 1, (rows10[:2], rows3[:1]))

        # O11 결정론
        r11 = sc_o3()
        b1, _ = cli_ordered(r11, raw=True)
        for f in os.listdir(os.path.join(r11, "stage_artifacts", "paper_recharge")):
            os.utime(os.path.join(r11, "stage_artifacts", "paper_recharge", f), (time.time() + 3600, time.time() + 3600))
        b2, _ = cli_ordered(r11, raw=True)
        check("O11 결정론 — CLI 2회 바이트 동일(mtime 바꿔도)", b1 == b2 and len(b1) > 0)

        # O12 정보 경계 — 등급 · 성과 · confidence 를 바꿔도 순서 · 키 불변
        def o12(perturb):
            ex = {} if not perturb else {"essence_grade": "A", "calmar": 9.9, "port_t": 9.9, "sharpe": 3.0, "cagr": 0.5}
            fc = {"name": "f", "def": "d", "verdict": "testable", "confidence": 0.99 if perturb else 0.1}
            rts = [("20261001", [P("2699.91201", "return", "skip"), P("2699.91202", "defense", "skip")]),
                   ("20261002", [P("2699.12001", "return", long_leg="yes", factor_candidate=fc, **ex),
                                 P("2699.12002", "construction", crisis_evidence="reported", factor_candidate=fc),
                                 P("2699.12003", "defense", **ex)])]
            r = make_root(rts, l1_keys=[])
            lp = os.path.join(r, "06_Registry", "reinforce_ledger_l1.json")
            ents = [{"paper_key": "2699.91201", "status": "exhausted" if perturb else "active",
                     "base_grade": "A" if perturb else "F", "target_grade": "A", "base_essence_history": [{"grade": "A"}] if perturb else []},
                    {"paper_key": "2699.91202", "status": "parked" if perturb else "active", "base_grade": "B" if perturb else "C"}]
            wjson(lp, {"entries": ents})
            return cli_ordered(r)[0]
        a12, b12 = o12(False), o12(True)
        check("O12a 등급 · 성과 · confidence · L1 status 를 바꿔도 순서 · 순서 키 불변", a12 == b12 and len(a12) == 3, (a12, b12))
        src = io.open(os.path.join(OPS, "research_pool_predicates.py"), encoding="utf-8").read()
        m = re.search(r"# ── 다음 논문 순서.*?# ── 다음 논문 순서 끝", src, re.S)
        sec = m.group(0) if m else ""
        code = "\n".join(ln.split("#", 1)[0] for ln in sec.splitlines())
        bad = [t for t in ("grade", "calmar", "port_t", "sharpe", "cagr", "confidence", "essence", "mdd", "pool", "factor_candidate")
               if t in code.lower()]
        check("O12b 순서 절 소스(주석 제외)에 등급 · 성과 · 기저 풀 토큰 0", bool(sec) and not bad, bad)
        check("O12c _order_view 출력 키 ⊆ ORDER_FIELDS(화이트리스트)",
              set(rpp._order_view({"engine": "x", "essence_grade": "A", "calmar": 1, "long_leg": "yes", "zz": 1}).keys()) <= set(rpp.ORDER_FIELDS)
              and "calmar" not in rpp.ORDER_FIELDS and "essence_grade" not in rpp.ORDER_FIELDS)

        # O13 선택기 기존 제약 유지
        skip = {"entries": [{"paper_key": "2699.13002", "status": "active"}, {"paper_key": "2699.13003", "status": "revoked"}]}
        r13 = make_root([("20261001", [P("2699.13001", "defense"), P("2699.13002", "defense"), P("2699.13003", "defense"),
                                       P("2699.13004", "defense"), dict(P("2699.13005", "defense"), source="curated"),
                                       P("2699.13006", "defense")])],
                        l1_keys=["2699.13004"], skip=skip)
        outs, _ = pick(r13, "--list", "20")
        got = [o.get("paper_key") for o in outs]
        check("O13a 건너뛰기(active) 제외 · revoked 재후보 · L1 소비 제외 · 원문 링크 없음 제외",
              got == ["2699.13001", "2699.13003", "2699.13006"], got)
        o_ex, _ = pick(r13, "--exclude", "2699.13001", "--list", "1")
        o_only, _ = pick(r13, "--only-key", "2699.13006")
        o_only_bad, _ = pick(r13, "--only-key", "2699.13002")
        check("O13b --exclude · --only-key 유지",
              [o.get("paper_key") for o in o_ex] == ["2699.13003"] and [o.get("paper_key") for o in o_only] == ["2699.13006"]
              and (o_only_bad and o_only_bad[0].get("error") == "only_key_not_available"), (o_ex, o_only, o_only_bad))
        p1, _ = pick(r1)
        check("O13c 인자 없는 선택기(구판 main)도 규칙 상단을 낸다", p1 and p1[0].get("paper_key") == "2699.10002", p1)

        # O14 order_why ↔ 키
        o14, _ = pick(r1, "--list", "2")
        w0 = (o14[0].get("order_why") if o14 else "") or ""
        check("O14 order_why = 순서 키 값(engine · 소비 · long_leg · crisis · fifo#) · order_key 동봉",
              w0.startswith("next_paper_order v1") and "fifo#2/2" in w0
              and "engine=defense(소비 0" in w0 and isinstance(o14[0].get("order_key"), list), (w0, o14[:1]))

        # O15 공급기 E2E(next_replication.R)
        rs = shutil.which("Rscript")
        if rs:
            r15 = sc_o1()
            os.makedirs(os.path.join(r15, "02_Infrastructure", "programs"))
            shutil.copy(os.path.join(ROOT, "02_Infrastructure", "programs", "next_replication.R"), os.path.join(r15, "02_Infrastructure", "programs"))
            shutil.copy(os.path.join(OPS, "rf_reimplement_queue.R"), os.path.join(r15, "02_Infrastructure", "ops"))
            os.makedirs(os.path.join(r15, ".cache"))
            renv = os.path.join(BASE, "empty.Renviron"); io.open(renv, "w").close()
            env = dict(os.environ, R_ENVIRON_USER=renv, QVEST_PY=PY, QM_ROOT=r15)
            for k in ("RP_SLOT", "RP_SLOT_ISSUING", "QVEST_RP_REQUEST"):
                env.pop(k, None)

            def run15():
                subprocess.run([rs, os.path.join(r15, "02_Infrastructure", "programs", "next_replication.R"), "--root", r15],
                               capture_output=True, timeout=300, env=env)
                rq = json.load(io.open(os.path.join(r15, "06_Registry", "replication_request.json"), encoding="utf-8"))
                lg = [json.loads(l) for l in io.open(os.path.join(r15, ".cache", "programs_log.jsonl"), encoding="utf-8") if l.strip()]
                return rq, [x for x in lg if x.get("event") == "replication_requested"]
            rq, lg = run15()
            check("O15a 공급기 요청 = 규칙 상단 · paper.order_why · 로그 replication_requested.order_why",
                  rq.get("paper", {}).get("paper_key") == "2699.10002" and "next_paper_order v1" in (rq["paper"].get("order_why") or "")
                  and lg and "next_paper_order v1" in (lg[-1].get("order_why") or ""), (rq.get("paper"), lg[-1:]))
            os.remove(os.path.join(r15, "06_Registry", "replication_request.json"))
            os.remove(os.path.join(r15, "06_Registry", "next_paper_order.json"))
            rq2, lg2 = run15()
            check("O15b 설정 삭제 → FIFO 상단 + 'fifo (next_paper_order missing)'",
                  rq2.get("paper", {}).get("paper_key") == "2699.10001" and
                  str(rq2["paper"].get("order_why") or "").startswith("fifo (next_paper_order missing)"), rq2.get("paper"))
        else:
            check("O15 Rscript 확보", False, "Rscript 없음")

        # M1~M4 돌연변이 — 각 단계 키를 상수로
        muts = [("M1 construction_needs_base", "1 if (eng == \"construction\" and base_n < need) else 0", "0",
                 lambda s: keys(sc_o2(pred_src=s)), ["2699.20002", "2699.20001"]),
                ("M2 engine_gap", "(0, counts.get(eng, 0)) if eng else (1, 0)", "(0, 0)",
                 lambda s: keys(sc_o1(pred_src=s))[:2], ["2699.10002", "2699.10001"]),
                ("M3 long_leg", "ll_rank.get(ll, ll_unknown)", "0",
                 lambda s: short(keys(sc_o3(pred_src=s))), ["03", "04", "06", "02", "01", "05"]),
                ("M4 crisis_evidence", "ce_rank.get(ce, ce_default)", "0",
                 lambda s: short(keys(sc_o4(pred_src=s))), ["02", "01", "03"])]
        for name, old, new, runner, expect in muts:
            ms = src.replace(old, new)
            check("%s 치환 성사(1곳)" % name, ms != src and src.count(old) == 1, src.count(old))
            got = runner(ms)
            check("%s 돌연변이 사본에선 순서가 바뀐다(검사가 규칙을 잡는다)" % name, got != expect and len(got) == len(expect), got)
    finally:
        shutil.rmtree(BASE, ignore_errors=True)
    nf = sum(1 for _, ok in RES if not ok)
    print(json.dumps({"test": "scn_paper_order", "pass": len(RES) - nf, "fail": nf, "total": len(RES)}))
    sys.exit(1 if nf else 0)


if __name__ == "__main__":
    main()
