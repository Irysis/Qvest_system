#!/usr/bin/env python3
# =============================================================================
# test_rf_preaudit.py — 충실구현 측정 전 기계 사전검사(02_Infrastructure/ops/rf_preaudit.py) 양방향 검사
#
# 규율(memory: "검사기는 양방향으로 재라" · "양성 대조 없는 계기는 방어선으로 세지 않는다"):
#   N  음성 대조 — 규약을 지킨 합성 엔진·신고 → pass(경고 0 이 아니라 fail 0)
#   P  양성 대조 — 2026-10-05 2508.18592 1차 기각 엔진(감사 지적: DUPC-033 중복 · 매핑 불일치 · 단계 누락 · 창 종점)
#   M  돌연변이 — 음성 픽스처에 한 가지씩 주입 → 그 코드만 발화(다른 코드가 같이 뜨지 않는지도 본다)
#   G  관문 처분 — 격리 요청 파일: 보정 요청(exit 10 · pending · 카운터 분리) · 회차 소진 · 통과 · 비활성 · 결합 · 설정 파손 fail-open
#   S  청정 sanitize 통과 — 보정 피드백이 청정 재구현 절 가림(rf_clean_lane.py sanitize --kind failure)을 지나도 내용이 남는가
# 운영 상태를 빌리지 않는다: 픽스처·요청·설정 사본은 전부 임시 디렉터리(등록부·규칙 설정은 읽기만).
# 실행: .venv_qvest_ml/Scripts/python.exe 08_Tests/ops/test_rf_preaudit.py
# =============================================================================
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PA = os.path.join(ROOT, "02_Infrastructure", "ops", "rf_preaudit.py")
CFG = os.path.join(ROOT, "06_Registry", "rf_preaudit.json")
REG = os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")
CLPY = os.path.join(ROOT, "02_Infrastructure", "ops", "rf_clean_lane.py")
CLCFG = os.path.join(ROOT, "06_Registry", "replication_clean_lane.json")
# 양성 대조 픽스처 = 2026-10-05 2508.18592 1차 패스 실물(엔진 sha256 0cb8ea93… = 작업 디렉터리 engine.rejected1.R ·
#   FIDELITY = 1차 패스 자기신고 35항 — 2차 패스가 덮어쓰기 전 사본). 감사 지적: DUPC-033 중복 · 매핑 불일치 · 단계 누락 · 창 종점.
POS_DIR = os.path.join(ROOT, "08_Tests", "ops", "fixtures", "preaudit_2508_18592_pass1")
PY = sys.executable

RESULTS = []


def check(name, cond, info=""):
    RESULTS.append((name, bool(cond)))
    print("%s %s%s" % ("PASS" if cond else "FAIL", name, ("  — " + info) if (info and not cond) else ""))


def J(p):
    return json.loads(io.open(p, "rb").read().decode("utf-8-sig"))


def W(p, o):
    io.open(p, "w", encoding="utf-8").write(json.dumps(o, ensure_ascii=False, indent=1) if not isinstance(o, str) else o)


def run_pa(wdir, cfg=CFG, extra=None):
    cmd = [PY, PA, "--wdir", wdir, "--root", ROOT, "--cfg", cfg, "--out", os.path.join(wdir, "rep.json")]
    cmd += extra or []
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    rep = J(os.path.join(wdir, "rep.json")) if os.path.isfile(os.path.join(wdir, "rep.json")) else {}
    return p.returncode, rep


def codes(rep):
    return sorted({f["code"] for f in rep.get("findings") or [] if f["severity"] == "fail"})


REGD = J(REG)


def regdef(k):
    return (REGD.get(k) or {}).get("definition") or ""


GOOD_ENGINE = r'''# 합성 음성 픽스처 — 규약을 지킨 엔진
library(data.table)
F_USE <- c("V01_BM", "M04_Mom_1")
set.seed(7L)
X[, sig := frollmean(v, 12L)]
X[, sig := pmax(sig, 0)]
X <- X[is.finite(sig)]
fit <- tryCatch(lm(y ~ sig, data = X), error = function(e) NULL)
if (nrow(X) < 20L) stop("too few")
FACTORS <- X[, .(Date, Ticker, Score = sig)]
'''


def good_fidelity():
    return {
        "fidelity": "adapted",
        "kept": "기전 유지",
        "changed": ("유니버스 K200∪KQ150 · 결측·비유한값은 제외(is.finite) · 음수는 0 으로 clip(pmax) · seed 7 고정 · "
                    "lm 실패 시 폴백 NULL(tryCatch) · 최소 20종 하한"),
        "paper_original_form": "횡단면 점수",
        "portfolio_spec": {"construction": "top_n_long", "weighting": "ew", "rebalance": "monthly", "top_n": 25},
        "commission_paper": None,
        "paper_steps": [
            {"step": "신호", "paper_quote": "§2 'signal is the 12-month mean'", "status": "implemented", "note": "frollmean 12"},
            {"step": "가중", "paper_quote": "§3 'equal weight'", "status": "implemented", "note": ""},
            {"step": "표본", "paper_quote": "§1 'all stocks'", "status": "changed", "note": "K200∪KQ150"},
            {"step": "리밸", "paper_quote": "§3 'monthly'", "status": "implemented", "note": ""},
            {"step": "비용", "paper_quote": "§4 'no costs'", "status": "implemented", "note": ""},
        ],
        "windows": [{"name": "신호 창", "paper": "s∈[t-11, t]", "impl": "frollmean 12 — [t-11, t] 당월 포함"}],
        "factor_mapping": [
            {"factor_id": "V01_BM", "paper_item": "B/M", "registry_definition": regdef("V01_BM"), "deviation": "none"},
            {"factor_id": "M04_Mom_1", "paper_item": "1M return", "registry_definition": regdef("M04_Mom_1"), "deviation": "none"},
        ],
    }


def make_fx(base, name, engine=GOOD_ENGINE, fid=None):
    d = os.path.join(base, name)
    os.makedirs(d, exist_ok=True)
    W(os.path.join(d, "engine.R"), engine)
    W(os.path.join(d, "FIDELITY.json"), fid if fid is not None else good_fidelity())
    return d


def main():
    tmp = tempfile.mkdtemp(prefix="test_rf_preaudit_")
    try:
        # ── N 음성 대조 ───────────────────────────────────────────────
        d = make_fx(tmp, "N")
        rc, rep = run_pa(d)
        check("N1 compliant fixture → pass(rc 0)", rc == 0 and rep.get("verdict") == "pass", "rc=%s codes=%s" % (rc, codes(rep)))
        check("N2 compliant fixture → registry factors counted 2", (rep.get("stats") or {}).get("registry_factors_used") == 2,
              str(rep.get("stats")))

        # ── P 양성 대조(실데이터) ─────────────────────────────────────────
        if os.path.isfile(os.path.join(POS_DIR, "engine.R")) and os.path.isfile(os.path.join(POS_DIR, "FIDELITY.json")):
            d = os.path.join(tmp, "P")
            shutil.copytree(POS_DIR, d)
            rc, rep = run_pa(d)
            c = codes(rep)
            check("P1 2508 pass-1 engine + real self-declaration → findings(rc 1)", rc == 1, "rc=%s" % rc)
            dup = [f for f in rep.get("findings") or [] if f["code"] == "P3_duplicate_cluster"]
            check("P2 DUPC-033(M11/M29) caught — the auditor's mismatch", any("DUPC-033" in f["title"] for f in dup), str([f["title"] for f in dup]))
            check("P3 factor_mapping missing caught", "P2_factor_mapping_missing" in c, str(c))
            check("P4 paper_steps / windows missing caught", "P4_paper_steps_missing" in c and "P5_windows_missing" in c, str(c))
            check("P5 top-level constants table missing caught (GUARD)", "P7_constants_missing" in c, str(c))
            check("P6 thoroughly declared defensive code → no P6 false positive", not [x for x in c if x.startswith("P6_")], str(c))
        else:
            check("P0 positive-control fixture present", False, POS_DIR)

        # ── M 돌연변이 ───────────────────────────────────────────────
        def mut(name, engine=GOOD_ENGINE, fid_fn=None, expect=None, only=True):
            f = good_fidelity()
            if fid_fn:
                fid_fn(f)
            dd = make_fx(tmp, name, engine=engine, fid=f)
            rc_, rep_ = run_pa(dd)
            c_ = codes(rep_)
            ok = (rc_ == 1) and (expect in c_) and ((c_ == [expect]) if only else True)
            check("%s → %s%s" % (name, expect, " only" if only else ""), ok, "rc=%s codes=%s" % (rc_, c_))

        mut("M1 undeclared clip", engine=GOOD_ENGINE + "Z <- pmin(Z, 3)\n",
            fid_fn=lambda f: f.update(changed=f["changed"].replace("clip(pmax)", "").replace("음수는 0 으로", "")),
            expect="P6_clip_winsor")
        mut("M2 unmapped registry factor", engine=GOOD_ENGINE.replace('"M04_Mom_1")', '"M04_Mom_1", "V02_EP")'),
            expect="P2_factor_unmapped")
        mut("M3 duplicate cluster", engine=GOOD_ENGINE.replace('"M04_Mom_1")', '"M04_Mom_1", "M11_ST_Reversal", "M29_Mom_5d")'),
            fid_fn=lambda f: f["factor_mapping"].extend([
                {"factor_id": "M11_ST_Reversal", "paper_item": "5d rev", "registry_definition": regdef("M11_ST_Reversal"), "deviation": "none"},
                {"factor_id": "M29_Mom_5d", "paper_item": "5d mom", "registry_definition": regdef("M29_Mom_5d"), "deviation": "none"}]),
            expect="P3_duplicate_cluster")
        mut("M4 windows removed", fid_fn=lambda f: f.pop("windows"), expect="P5_windows_missing")
        mut("M5 changed step without note",
            fid_fn=lambda f: f["paper_steps"].append({"step": "중성화", "paper_quote": "§2.1 'regressed on industry'", "status": "omitted", "note": ""}),
            expect="P4_paper_steps_malformed")
        mut("M6 undeclared seed", fid_fn=lambda f: f.update(changed=f["changed"].replace("seed 7 고정 · ", "")),
            expect="P6_seed")
        mut("M7 window impl without endpoint",
            fid_fn=lambda f: f["windows"][0].update(impl="12개월 평균"), expect="P5_windows_malformed")
        # M8 — 중복 군집을 군집 id 로 신고하면 통과(논문도 같은 변환을 별개 지표로 둔 경우의 출구)
        f8 = good_fidelity()
        f8["factor_mapping"] += [
            {"factor_id": "M11_ST_Reversal", "paper_item": "5d rev", "registry_definition": regdef("M11_ST_Reversal"), "deviation": "none"},
            {"factor_id": "M29_Mom_5d", "paper_item": "5d mom", "registry_definition": regdef("M29_Mom_5d"), "deviation": "none"}]
        f8["changed"] += " · DUPC-033 두 지표를 논문의 별개 지표 둘에 대응(의도)"
        d8 = make_fx(tmp, "M8", engine=GOOD_ENGINE.replace('"M04_Mom_1")', '"M04_Mom_1", "M11_ST_Reversal", "M29_Mom_5d")'), fid=f8)
        rc8, rep8 = run_pa(d8)
        check("M8 duplicate cluster declared by id → pass", rc8 == 0, "codes=%s" % codes(rep8))
        d9 =make_fx(tmp, "M9", engine=GOOD_ENGINE + "# Z <- pmin(Z, 3)  set.seed(1) tryCatch(\n")
        rc9, rep9 = run_pa(d9)
        check("M9 constructs inside comments do not fire", rc9 == 0, "codes=%s" % codes(rep9))
        # ── P7 상수표 · 새 범주(month_skip · zscore_disclosure) ─────────────────────
        ENG_K = GOOD_ENGINE.replace("set.seed(7L)", "set.seed(7L)\nPAP_L <- 12L\nAX_MIN <- 20L")

        def with_consts(f):
            f["constants"] = [{"name": "PAP_L", "value": "12", "source": "paper", "note": "§2 12개월"},
                              {"name": "AX_MIN", "value": "20L", "source": "supplement", "note": "최소 20종 하한(논문 무명시)"}]
        mut("M11 top-level constants without constants table", engine=ENG_K, expect="P7_constants_missing")
        mut("M12 constant value mismatch", engine=ENG_K,
            fid_fn=lambda f: (with_consts(f), f["constants"][0].update(value="24")), expect="P7_constants_value_mismatch")
        mut("M13 constant with bad source label", engine=ENG_K,
            fid_fn=lambda f: (with_consts(f), f["constants"][1].update(source="assumed")), expect="P7_constants_source")
        f14 = good_fidelity()
        with_consts(f14)
        d14 = make_fx(tmp, "N3", engine=ENG_K, fid=f14)
        rc14, rep14 = run_pa(d14)
        check("N3 constants table complete (int literal 12L vs declared 12) → pass", rc14 == 0, "codes=%s" % codes(rep14))
        ENG_S = GOOD_ENGINE.replace("FACTORS <-", "for (k in 1:3) { if (k == 2) next }\nFACTORS <-")
        mut("M14 undeclared month skip (next)", engine=ENG_S, expect="P6_month_skip")
        f15 = good_fidelity()
        f15["changed"] += " · 표본 부족 달은 건너뛰고(next) 하네스가 직전 보유를 이월"
        rc15, rep15 = run_pa(make_fx(tmp, "M15", engine=ENG_S, fid=f15))
        check("M15 month skip declared → pass", rc15 == 0, "codes=%s" % codes(rep15))
        ENG_Z = GOOD_ENGINE.replace("X[, sig :=", "Z <- load_month_factors(d)[, .(Ticker, Z_Score_Aligned)]\nX[, sig :=", 1)
        mut("M16 Z_Score_Aligned consumed without transform disclosure", engine=ENG_Z, expect="P6_zscore_disclosure")
        # ── H 하네스 공시 블록 생성기 · P8(블록이 prompt.txt 에 실렸을 때만 강제) ─────────────
        ph = subprocess.run([PY, PA, "--harness-block", "--root", ROOT, "--cfg", CFG], capture_output=True, text=True, encoding="utf-8")
        hb = ph.stdout
        mk = (J(CFG).get("harness") or {}).get("marker") or "[HARNESS-DISCLOSURE v1]"
        ep_now = ((J(os.path.join(ROOT, "02_Infrastructure", "worktask", "constraint_defaults.json")).get("execution") or {}).get("exec_price"))
        check("H1 harness block renders with marker + live exec_price from harness config",
              ph.returncode == 0 and mk in hb and ("exec=%s" % ep_now) in hb, "rc=%s ep=%s head=%s" % (ph.returncode, ep_now, hb[:80]))
        cdir = os.path.join(tmp, "cd")
        os.makedirs(cdir)
        for ep_try, expect_rc in (("open_t1", 0), ("weird_rule", 3)):
            W(os.path.join(cdir, "cd_%s.json" % ep_try), {"execution": {"exec_price": ep_try}})
            ch = J(CFG)
            ch["harness"]["exec_config"] = os.path.join(cdir, "cd_%s.json" % ep_try)
            W(os.path.join(cdir, "cfg_%s.json" % ep_try), ch)
            p2 = subprocess.run([PY, PA, "--harness-block", "--root", ROOT, "--cfg", os.path.join(cdir, "cfg_%s.json" % ep_try)],
                                capture_output=True, text=True, encoding="utf-8")
            if expect_rc == 0:
                check("H2 exec rule follows the harness config (open_t1 → open_t1 statement)",
                      p2.returncode == 0 and "exec=open_t1" in p2.stdout and "시가" in p2.stdout, p2.stdout[:120])
            else:
                check("H3 unknown exec rule → rc 3 · no fabricated block", p2.returncode == 3 and not p2.stdout.strip(), "rc=%s out=%r" % (p2.returncode, p2.stdout[:80]))
        f8a = good_fidelity()
        d8a = make_fx(tmp, "P8a", fid=f8a)
        W(os.path.join(d8a, "prompt.txt"), "프롬프트 본문\n\n" + hb)
        rc8a, rep8a = run_pa(d8a)
        check("P8a block in prompt.txt but not copied → P8_harness_disclosure_missing only",
              rc8a == 1 and codes(rep8a) == ["P8_harness_disclosure_missing"], str(codes(rep8a)))
        f8b = good_fidelity()
        f8b["harness_disclosure"] = hb[hb.index(mk):]
        d8b = make_fx(tmp, "P8b", fid=f8b)
        W(os.path.join(d8b, "prompt.txt"), "프롬프트 본문\n\n" + hb)
        rc8b, rep8b = run_pa(d8b)
        check("P8b block copied into harness_disclosure → pass", rc8b == 0, str(codes(rep8b)))
        d10 = make_fx(tmp, "M10", fid="{ not json")
        rc10, rep10 = run_pa(d10)
        check("M10 unparsable FIDELITY → P1_fidelity_unparsable", rc10 == 1 and "P1_fidelity_unparsable" in codes(rep10), str(codes(rep10)))

        # ── G 관문 처분 ──────────────────────────────────────────────
        def gate_run(wdir, req, cfg=CFG, combo="0"):
            rp = os.path.join(tmp, "req_%s.json" % os.path.basename(wdir))
            W(rp, req)
            p = subprocess.run([PY, PA, "--gate", "--req", rp, "--wdir", wdir, "--root", ROOT, "--cfg", cfg, "--is-combo", combo],
                               capture_output=True, text=True, encoding="utf-8")
            return p.returncode, p.stdout.strip().split("\n")[-1] if p.stdout.strip() else "", J(rp)

        base_req = {"status": "in_progress", "paper": {"paper_key": "TEST"}, "audit_retries": 1, "auto_retries": 2,
                    "audit_feedback": "앞 감사 지적(유지되어야 함)"}
        bad = make_fx(tmp, "Gbad", fid={k: v for k, v in good_fidelity().items() if k != "paper_steps"})
        rc, out, rq = gate_run(bad, dict(base_req))
        check("G1 findings round 0 → exit 10 · action=reimplement", rc == 10 and out.startswith("action=reimplement"), "rc=%s out=%s" % (rc, out))
        check("G2 request → pending · failure=declaration_gate · preaudit_rounds=1",
              rq.get("status") == "pending" and rq.get("failure") == "declaration_gate" and rq.get("preaudit_rounds") == 1, str({k: rq.get(k) for k in ("status", "failure", "preaudit_rounds")}))
        check("G3 counters untouched (audit_retries 1 · auto_retries 2 · audit_feedback kept)",
              rq.get("audit_retries") == 1 and rq.get("auto_retries") == 2 and rq.get("audit_feedback") == base_req["audit_feedback"], str({k: rq.get(k) for k in ("audit_retries", "auto_retries")}))
        check("G4 failure_detail carries the finding text", "P4_paper_steps_missing" in (rq.get("failure_detail") or ""), (rq.get("failure_detail") or "")[:120])
        check("G5 prior engine preserved as engine.rejected_preaudit1.R (engine.R left in place)",
              os.path.isfile(os.path.join(bad, "engine.rejected_preaudit1.R")) and os.path.isfile(os.path.join(bad, "engine.R")))
        # G12 — 관문이 작업 디렉터리에 남긴 파일이 전부 청정 규칙의 레인 파일 정규식(사전등록 핀) 안인가 — 규칙 파일에서 재도출.
        import re as _re
        crule = J(os.path.join(ROOT, "06_Registry", "prereg", "clean_base_rule.config.json"))
        lrx = [_re.compile(r) for r in ((crule.get("exposure") or {}).get("wdir") or {}).get("lane_file_regex") or []]
        fixture_files = {"engine.R", "FIDELITY.json", "rep.json"}   # rep.json = 이 검사의 --out(관문 산출 아님)
        gate_files = [f for f in os.listdir(bad) if f not in fixture_files]
        outside = [f for f in gate_files if not any(rx.search(f) for rx in lrx)]
        check("G12 gate-written WDIR files all inside the pinned clean lane_file_regex",
              bool(lrx) and bool(gate_files) and not outside, "files=%s outside=%s" % (gate_files, outside))
        r2 = dict(rq)
        r2["status"] = "in_progress"
        rc, out, rq2 = gate_run(bad, r2)
        check("G6 findings at max rounds → proceed (exit 0) + failure cleared + residual recorded",
              rc == 0 and out.startswith("action=proceed") and rq2.get("failure") == "" and (rq2.get("preaudit_residual") or {}).get("codes"),
              "rc=%s out=%s failure=%r" % (rc, out, rq2.get("failure")))
        good = make_fx(tmp, "Ggood")
        r3 = dict(base_req)
        r3.update(failure="declaration_gate", failure_detail="낡은 사유", preaudit_rounds=1)
        rc, out, rq3 = gate_run(good, r3)
        check("G7 pass → proceed + stale declaration_gate cleared", rc == 0 and "verdict=pass" in out and rq3.get("failure") == "", "out=%s" % out)
        r4 = dict(base_req)
        r4.update(failure="replication_error", failure_detail="다른 사유")
        rc, out, rq4 = gate_run(good, r4)
        check("G8 pass leaves a non-gate failure untouched", rq4.get("failure") == "replication_error", str(rq4.get("failure")))
        cfg_off = os.path.join(tmp, "cfg_off.json")
        c = J(CFG)
        c["enabled"] = False
        W(cfg_off, c)
        rc, out, rq5 = gate_run(bad, dict(base_req), cfg=cfg_off)
        check("G9 disabled → proceed · request untouched", rc == 0 and "why=disabled" in out and rq5 == base_req, out)
        rc, out, rq6 = gate_run(bad, dict(base_req), combo="1")
        check("G10 combo request → skip (apply_to_combo false)", rc == 0 and "why=combo" in out and rq6 == base_req, out)
        cfg_bad = os.path.join(tmp, "cfg_bad.json")
        W(cfg_bad, "{ broken")
        rc, out, rq7 = gate_run(bad, dict(base_req), cfg=cfg_bad)
        check("G11 broken config → fail-open proceed", rc == 0 and "verdict=error" in out, out)

        # ── S 청정 sanitize 통과 ──────────────────────────────────────
        fb = rq.get("failure_detail") or ""
        if os.path.isfile(CLPY) and os.path.isfile(CLCFG):
            p = subprocess.run([PY, CLPY, "sanitize", "--lane-cfg", CLCFG, "--root", ROOT, "--kind", "failure",
                                "--stats", os.path.join(tmp, "san_stats.json")],
                               input=fb, capture_output=True, text=True, encoding="utf-8")
            out_s = p.stdout
            check("S1 sanitize(kind=failure) succeeds on gate feedback", p.returncode == 0, "rc=%s err=%s" % (p.returncode, p.stderr[:200]))
            check("S2 sanitized feedback keeps the finding codes", "P4_paper_steps_missing" in out_s, out_s[:200])
        else:
            check("S0 clean-lane sanitizer present", False, CLPY)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    n_fail = sum(1 for _, ok in RESULTS if not ok)
    print("== %d checks · %d failed" % (len(RESULTS), n_fail))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
