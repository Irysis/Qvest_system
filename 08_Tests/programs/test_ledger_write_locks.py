#!/usr/bin/env python3
# =============================================================================
# test_ledger_write_locks.py — 원장 writer 4종 쓰기 잠금 양성 대조 (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020 — 독립 라운드 동시 운영의 전제)
#   '동시 writer 2개가 서로의 갱신을 잃지 않는다'를 일부러 경합을 일으켜 잰다: 두 프로세스가 같은 원장에 각자 N건을 쓰는데,
#   저장 직전에 0.3초를 쉬게 만들어(읽기 → 고치기 → [쉼] → 쓰기) 잠금이 없으면 거의 확실히 한쪽 갱신이 덮이게 한다.
#   대상: ①판단 원장 q_judgment_ledger.py ②재개 저널 session_resume.py ③프로그램 등록부 program_registry.R(pr_enqueue)
#        ④결정 기록부 reinforce_ledger.R(dr_open — 09-25 O0a 부터 claim + CAS 를 이미 갖는다 · 여기서 실측 확인)
#   각 대상마다 양성 대조(잠금 = 2N건 · id 중복 0) + 뮤테이션(잠금 제거판 = 유실이 실제로 생긴다 → 이 검사가 그 결함을 잡는다)을 함께 단다.
#   운영 원장 무접촉 — 전부 임시 사본(QVEST_JUDGMENT_LEDGER_PATH · QVEST_SESSION_RESUME_PATH · 등록부 path= · 결정 기록부 root= · QVEST_DR_CLAIM).
# 실행: .venv_qvest_ml/Scripts/python.exe 08_Tests/programs/test_ledger_write_locks.py
# =============================================================================
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROG = os.path.join(ROOT, "02_Infrastructure", "programs")
PY = sys.executable
N = 5
RESULTS = []


def check(name, cond, info=""):
    RESULTS.append((name, bool(cond)))
    print("%s %s%s" % ("PASS" if cond else "FAIL", name, ("  — " + str(info)[:400]) if (info and not cond) else ""))


PY_DRIVER = r'''
import contextlib, importlib.util, sys, time
mod_path, mod_name, mode, prefix, n = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
s = importlib.util.spec_from_file_location(mod_name, mod_path); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
orig = m.save
def slow_save(path, d, lock=None):
    time.sleep(0.3)                  # 읽기 → 고치기 → [쉼] → 쓰기: 경합 창을 넓힌다
    return orig(path, d, lock=lock)
m.save = slow_save
if mode == "nolock":                 # 뮤테이션 — 잠금 제거
    for nm in ("_ledger_lock", "_state_lock"):
        if hasattr(m, nm):
            setattr(m, nm, lambda p: contextlib.nullcontext())
for i in range(n):
    if mod_name == "qjl":
        m.main(["record", "--kind", "ops", "--summary", "%s-%02d" % (prefix, i), "--rationale", "lock test"])
    else:
        m.main(["note", "--id", "OP-LOCKTEST", "--text", "%s-%02d" % (prefix, i)])
'''

R_PR_DRIVER = r'''
a <- commandArgs(trailingOnly = TRUE); reg <- a[1]; mode <- a[2]; prefix <- a[3]; n <- as.integer(a[4]); src <- a[5]
## 검사 대상 파일은 경로로 받는다 — R 은 ~/.Renviron 의 QM_ROOT(운영 체크아웃)로 환경을 덮어 worktree 사본 대신 운영 코드를 읽는다(10-20 실측)
suppressMessages(source(src))
.orig_save <- pr_save
pr_save <- function(reg, root = NULL, path = NULL) { Sys.sleep(0.3); .orig_save(reg, root, path) }   # 경합 창
if (identical(mode, "nolock")) .pr_lock <- function(p) NULL                                       # 뮤테이션 — 잠금 제거
for (i in seq_len(n)) pr_enqueue("P1_RETURN", list(key = sprintf("%s-%02d", prefix, i), note = "lock test"), path = reg)
'''

R_DR_DRIVER = r'''
a <- commandArgs(trailingOnly = TRUE); root <- a[1]; src <- a[2]; mode <- a[3]; prefix <- a[4]; n <- as.integer(a[5])
invisible(capture.output(source(src)))
if (identical(mode, "nolock"))     # 뮤테이션 — claim 제거(사본 src 는 CAS 재대조도 지웠다)
  .rf_ledger_claim <- function(root, claim, wait_s, poll_s, what) list(claim = claim, mode = "none", release = function() invisible(NULL))
for (i in seq_len(n)) tryCatch(
  dr_open(sprintf("%s_%02d", prefix, i), title = "lock test", options = c("a"), recommendation = "a", default_until_decided = "a",
          blocks = character(0), source = "test_ledger_write_locks", root = root, .pre_write_hook = function(p) Sys.sleep(0.3)),
  error = function(e) cat("ERR", conditionMessage(e), "\n"))
'''


def run_pair(cmds, env):
    ps = [subprocess.Popen(c, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace") for c in cmds]
    outs = [p.communicate(timeout=900)[0] for p in ps]
    return [p.returncode for p in ps], outs


def main():
    base = tempfile.mkdtemp(prefix="ledgerlock_test_")
    env0 = dict(os.environ, QM_ROOT=ROOT, CLAUDE_PROJECT_DIR=ROOT, QVEST_CODE_ROOT=ROOT, PYTHONIOENCODING="utf-8")
    env0.pop("QVEST_UNATTENDED_LANE", None); env0.pop("QVEST_ORGANIC_CTX", None)
    try:
        drv = os.path.join(base, "py_driver.py")
        io.open(drv, "w", encoding="utf-8").write(PY_DRIVER)

        # ── ① 판단 원장 ─────────────────────────────────────────────────────
        def qjl(mode, tag):
            p = os.path.join(base, tag, "q_judgment_ledger.json")
            os.makedirs(os.path.dirname(p))
            env = dict(env0, QVEST_JUDGMENT_LEDGER_PATH=p)
            rcs, outs = run_pair([[PY, drv, os.path.join(PROG, "q_judgment_ledger.py"), "qjl", mode, "W%d" % k, str(N)] for k in (1, 2)], env)
            d = json.load(io.open(p, encoding="utf-8"))
            js = d.get("judgments") or []
            return rcs, len(js), len({j["id"] for j in js}), outs
        rcs, n_j, n_id, outs = qjl("lock", "qjl_lock")
        check("① 판단 원장 — 동시 writer 2개 × %d건 = %d건 모두 남는다 · id 중복 0(잠금 안에서 id 부여)" % (N, 2 * N),
              rcs == [0, 0] and n_j == 2 * N and n_id == 2 * N, (rcs, n_j, n_id, [o[-300:] for o in outs]))
        rcs, n_j, n_id, _ = qjl("nolock", "qjl_mut")
        check("① 뮤테이션(잠금 제거)판은 갱신을 잃는다(%d건 < %d) → 위 검사가 잡는 결함" % (n_j, 2 * N), n_j < 2 * N, (rcs, n_j))

        # ── ② 재개 저널 ─────────────────────────────────────────────────────
        def sres(mode, tag):
            p = os.path.join(base, tag, "session_resume.json")
            os.makedirs(os.path.dirname(p))
            env = dict(env0, QVEST_SESSION_RESUME_PATH=p)
            subprocess.run([PY, os.path.join(PROG, "session_resume.py"), "begin", "--id", "OP-LOCKTEST", "--title", "t", "--step", "S1=x"],
                           env=env, capture_output=True, text=True)
            rcs, outs = run_pair([[PY, drv, os.path.join(PROG, "session_resume.py"), "sres", mode, "W%d" % k, str(N)] for k in (1, 2)], env)
            d = json.load(io.open(p, encoding="utf-8"))
            op = next(o for o in d["operations"] if o["id"] == "OP-LOCKTEST")
            notes = [x["text"] for x in op.get("log") or [] if x["text"][:1] == "W"]
            return rcs, len(notes), outs
        rcs, n_n, outs = sres("lock", "sres_lock")
        check("② 재개 저널 — 동시 writer 2개 × %d 기록 = %d 모두 남는다" % (N, 2 * N), rcs == [0, 0] and n_n == 2 * N, (rcs, n_n, [o[-300:] for o in outs]))
        rcs, n_n, _ = sres("nolock", "sres_mut")
        check("② 뮤테이션(잠금 제거)판은 기록을 잃는다(%d < %d) → 위 검사가 잡는 결함" % (n_n, 2 * N), n_n < 2 * N, (rcs, n_n))

        # ── ③ 프로그램 등록부 ───────────────────────────────────────────────
        rdrv = os.path.join(base, "pr_driver.R")
        io.open(rdrv, "w", encoding="utf-8").write(R_PR_DRIVER)

        def preg(mode, tag):
            d = os.path.join(base, tag, "06_Registry")
            os.makedirs(d)
            p = os.path.join(d, "research_programs.json").replace("\\", "/")
            shutil.copy(os.path.join(ROOT, "06_Registry", "research_programs.json"), p)
            prsrc = os.path.join(PROG, "program_registry.R").replace("\\", "/")
            rcs, outs = run_pair([["Rscript", rdrv, p, mode, "LOCKTEST-W%d" % k, str(N), prsrc] for k in (1, 2)], env0)
            reg = json.load(io.open(p, encoding="utf-8"))
            q = next(x for x in reg["programs"] if x["id"] == "P1_RETURN").get("queue") or []
            keys = [x.get("key") for x in q if str(x.get("key", "")).startswith("LOCKTEST-")]
            lockdir = os.path.join(base, tag, ".cache", "registry_locks")
            return rcs, len(keys), outs, lockdir
        rcs, n_k, outs, lockdir = preg("lock", "pr_lock")
        check("③ 프로그램 등록부(pr_enqueue) — 동시 writer 2개 × %d건 = %d건 모두 큐에 남는다" % (N, 2 * N), rcs == [0, 0] and n_k == 2 * N,
              (rcs, n_k, [o[-300:] for o in outs]))
        check("③ 잠금 자리 = <루트>/.cache/registry_locks(06_Registry 안에 잠금 디렉터리를 두지 않는다 · 끝나면 비어 있다)",
              os.path.isdir(lockdir) and not [x for x in os.listdir(lockdir) if x.endswith(".qvlock")]
              and not [x for x in os.listdir(os.path.join(base, "pr_lock", "06_Registry")) if "lock" in x], os.listdir(lockdir) if os.path.isdir(lockdir) else "-")
        rcs, n_k, _, _ = preg("nolock", "pr_mut")
        check("③ 뮤테이션(잠금 제거)판은 큐 항목을 잃는다(%d < %d) → 위 검사가 잡는 결함" % (n_k, 2 * N), n_k < 2 * N, (rcs, n_k))

        # ── ④ 결정 기록부(dr_open) ───────────────────────────────────────────
        ddrv = os.path.join(base, "dr_driver.R")
        io.open(ddrv, "w", encoding="utf-8").write(R_DR_DRIVER)
        src = os.path.join(ROOT, "02_Infrastructure", "reinforcement", "reinforce_ledger.R").replace("\\", "/")
        s = io.open(src, encoding="utf-8").read()
        n_cas = s.count("    if (!identical(md5_a, md5_b)) {")
        msrc = os.path.join(base, "reinforce_ledger_mut.R").replace("\\", "/")
        io.open(msrc, "w", encoding="utf-8").write(s.replace("    if (!identical(md5_a, md5_b)) {", "    if (FALSE) {"))

        def dreg(mode, tag, source_file, n=3):
            root = os.path.join(base, tag).replace("\\", "/")
            os.makedirs(os.path.join(root, "06_Registry"))
            json.dump({"schema": "decision_register_v1", "note": "test", "items": [], "last_updated": ""},
                      io.open(os.path.join(root, "06_Registry", "decision_register.json"), "w", encoding="utf-8"))
            env = dict(env0, QVEST_DR_CLAIM=os.path.join(root, ".cache", "decision_register.claim").replace("\\", "/"))
            rcs, outs = run_pair([["Rscript", ddrv, root, source_file, mode, "LOCK_W%d" % k, str(n)] for k in (1, 2)], env)
            d = json.load(io.open(os.path.join(root, "06_Registry", "decision_register.json"), encoding="utf-8"))
            ids = [x["id"] for x in d.get("items") or []]
            return rcs, len(ids), len(set(ids)), outs
        rcs, n_i, n_u, outs = dreg("lock", "dr_lock", src)
        check("④ 결정 기록부(dr_open · 09-25 claim + CAS) — 동시 writer 2개 × 3건 = 6건 모두 남는다 · 오류 0",
              rcs == [0, 0] and n_i == 6 and n_u == 6 and not any("ERR" in o for o in outs), (rcs, n_i, [o[-400:] for o in outs]))
        rcs, n_i, _, outs = dreg("nolock", "dr_mut", msrc)
        check("④ 뮤테이션(claim 제거 + CAS 재대조 제거)판은 항목을 잃는다(%d < 6) → 위 검사가 잡는 결함 · 치환 1곳" % n_i,
              n_cas == 1 and n_i < 6, (n_cas, n_i, [o[-200:] for o in outs]))

        # ── ⑤ 검증기 공유 기록 구간(슬롯 작업자 · rf_replication.book) — 슬롯 검증기 둘이 겹치지 않는다 · 끝나면 놓는다 · 구판은 무동작 ──
        import re
        vsrc = io.open(os.path.join(ROOT, "02_Infrastructure", "ops", "rf_replication_verify.R"), encoding="utf-8").read()
        m = re.search(r"^\.SBL <- new\.env\(.*?^\}\n", vsrc, re.S | re.M)
        if not m:
            check("⑤ 검증기 기록 잠금 정의 추출", False, "패턴 없음")
        else:
            blk = os.path.join(base, "sbl_block.R")
            io.open(blk, "w", encoding="utf-8").write(m.group(0))
            st = os.path.join(base, "sbl_state").replace("\\", "/")
            ivl = os.path.join(base, "sbl_intervals.txt").replace("\\", "/")
            drv5 = os.path.join(base, "sbl_driver.R")
            io.open(drv5, "w", encoding="utf-8").write(r'''
a <- commandArgs(trailingOnly = TRUE); blk <- a[1]; ivl <- a[2]
ROOT <- Sys.getenv("QVEST_CODE_ROOT"); .RP_SLOT <- Sys.getenv("RP_SLOT", "")
jlog <- function(event, ...) cat("JL", event, "\n")
eval(parse(blk, encoding = "UTF-8"))
h <- .slot_book_lock()
t1 <- as.numeric(Sys.time()); Sys.sleep(1.0); t2 <- as.numeric(Sys.time())
cat(sprintf("%s %.4f %.4f %s\n", Sys.getpid(), t1, t2, if (is.null(h)) "nolock" else "lock"), file = ivl, append = TRUE)
quit(status = 0)          # 종료 해제(reg.finalizer onexit) — 놓지 않고 죽어도 다음 대기자가 죽은 소유자로 회수한다
''')
            env5 = dict(env0, QVEST_RP_STATE_DIR=st, RP_SLOT="cpu1")
            ps = [subprocess.Popen(["Rscript", drv5, blk, ivl], env=env5, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   encoding="utf-8", errors="replace") for _ in range(3)]
            outs5 = [p.communicate(timeout=600)[0] for p in ps]
            iv = sorted(tuple(float(x) for x in l.split()[1:3]) for l in io.open(ivl) if l.strip())
            kinds = {l.split()[3] for l in io.open(ivl) if l.strip()}
            ov = sum(1 for i in range(1, len(iv)) if iv[i][0] < iv[i - 1][1])
            left = os.path.join(st, "qv_locks", "rf_replication.book.qvlock")
            check("⑤ 슬롯 검증기 3개의 공유 기록 구간 — 겹침 0 · 셋 다 잠금 경유 · 끝나면 잠금이 남지 않는다(종료 해제)",
                  len(iv) == 3 and ov == 0 and kinds == {"lock"} and not os.path.isdir(left), (iv, kinds, os.path.isdir(left), [o[-200:] for o in outs5]))
            ivl2 = ivl + ".legacy"
            env6 = dict(env0, QVEST_RP_STATE_DIR=st)
            env6.pop("RP_SLOT", None)
            subprocess.run(["Rscript", drv5, blk, ivl2], env=env6, capture_output=True, text=True, timeout=300)
            k2 = [l.split()[3] for l in io.open(ivl2) if l.strip()] if os.path.exists(ivl2) else []
            check("⑤ 구판(RP_SLOT 없음) — 기록 잠금 무동작(구판 동작 그대로)", k2 == ["nolock"], k2)
    finally:
        shutil.rmtree(base, ignore_errors=True)
    n_fail = sum(1 for _, ok in RESULTS if not ok)
    print("== %d checks · %d failed" % (len(RESULTS), n_fail))
    print(json.dumps({"test": "ledger_write_locks", "pass": len(RESULTS) - n_fail, "fail": n_fail, "total": len(RESULTS)}))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
