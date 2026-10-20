#!/usr/bin/env python3
# =============================================================================
# test_replication_slots.py — 충실구현 레인 다중 슬롯 디스패처 · 발행기 · 논문 잠금 · GPU 인계 · GPU 임대 양성 대조
#   (02_Infrastructure/ops/rf_replication_slots.py · 2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)
#   과거 동시성 사고 영역을 일부러 일으켜 잡히는지 본다(양방향) + 뮤테이션(소스 텍스트 치환 사본 · 치환 성사 단정)으로 검출력을 잰다.
#   S1 발행 = 등급별 슬롯(GPU 논문 → gpu1 · CPU → cpu) · 논문 잠금 · LAUNCH 3줄 / S2 두 틱 경합 — 슬롯당 발행 1회(+뮤테이션: 잠금 제거 → 2회) /
#   S3 같은 논문 중복 — 다른 슬롯이 쥔 논문은 duplicate_held_elsewhere(+뮤테이션: 생존 판정 제거 → 빼앗음) /
#   S4 슬롯 소유자 사망 — 즉시 회수 · 재착수 · 그 논문은 다른 슬롯이 못 가져감 · 생존 소유자 유지 · claim_live_long 1회 · pid 재사용 /
#   S5 GPU 오배치 — 인계 → gpu1 · 구현 의존성 판별(torch 엔진 = gpu · 아니면 cpu · 큐 메타보다 우선 · +뮤테이션) /
#   S6 GPU 임대 — 유효 임대 = GPU 슬롯 보류(CPU 그대로) · 만료 = 틱이 풀고 재개(+뮤테이션: 만료 비교 제거 → 영영 보류) · 보유자 사망 /
#   S7 구판 요청 인수(살아 있는 구판 작업자 = 점유 · 죽으면 회수 후 등급 맞는 슬롯으로) / S8 용량(구판 CPU 점유 = CPU 1 감산) /
#   S9 환경 백오프 · 임대 중 GPU 인계함 대기 / S10 일 소진량(레인 저널) / S11 설정 켜기 · 끄기(구판 복귀 = LEGACY)
#   운영 요청 · claim · 잠금 · 임대 · 재구현 대기열 무접촉 — 전부 임시 경로(QVEST_RP_* · QVEST_GPU_LEASE · 후보 · 발행 대역).
# 실행: .venv_qvest_ml/Scripts/python.exe 08_Tests/ops/test_replication_slots.py
# =============================================================================
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OPS = os.path.join(ROOT, "02_Infrastructure", "ops")
SLOTS = os.path.join(OPS, "rf_replication_slots.py")
PY = sys.executable
RESULTS = []
DEAD_PID = 999901

STUB = r'''
import json, os, sys, time, io
a = sys.argv[1:]
g = lambda f: a[a.index(f) + 1] if f in a else ""
req, key, slot = g("--req"), g("--only-key"), g("--slot")
io.open(os.environ["STUB_LOG"], "a", encoding="utf-8").write("%s %s\n" % (slot, key))
time.sleep(float(os.environ.get("STUB_SLEEP") or 0))
c = json.load(io.open(os.environ["QVEST_RP_CANDIDATES_JSON"], encoding="utf-8"))
m = next((x for x in c if x["key"] == key), {})
os.makedirs(os.path.dirname(req), exist_ok=True)
d = {"status": "pending", "slot": slot, "lane_mode": "normal",
     "paper": {"paper_key": key, "paper_title": (m.get("meta") or {}).get("paper_title", key), "url": "http://127.0.0.1:9/" + key}}
io.open(req, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False))
'''


def check(name, cond, info=""):
    RESULTS.append((name, bool(cond)))
    print("%s %s%s" % ("PASS" if cond else "FAIL", name, ("  — " + str(info)[:400]) if (info and not cond) else ""))


def rj(p):
    try:
        return json.load(io.open(p, encoding="utf-8"))
    except Exception:
        return None


def wj(p, o):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    io.open(p, "w", encoding="utf-8").write(json.dumps(o, ensure_ascii=False))


class Fx(object):
    """격리 고정물 — 설정 · 상태 · 슬롯 요청 · 저널 · 구판 요청/claim · 작업 디렉터리 · 임대 · 후보 · 발행 대역."""

    def __init__(self, base, name, slots=None, cands=None):
        self.d = os.path.join(base, name)
        os.makedirs(self.d)
        self.cfg = os.path.join(self.d, "cfg.json")
        c = {"enabled": False, "claim_stale_hours": 6,
             "replication_lane": {"enabled": True, "gpu_lease": {"default_cap_hours": 12, "max_cap_hours": 12}}}
        if slots is not False:
            c["replication_lane"]["slots"] = slots or {"cpu": 2, "gpu": 1}
        wj(self.cfg, c)
        self.variants = os.path.join(self.d, "variants.json")
        wj(self.variants, {"compute": {"live_claim_reclaim": False}})
        self.state = os.path.join(self.d, "state")
        self.slotdir = os.path.join(self.d, "slots")
        self.jlog = os.path.join(self.d, "j.jsonl")
        self.legacy_req = os.path.join(self.d, "legacy_req.json")
        self.legacy_claim = os.path.join(self.state, "rf_replication.claim")
        self.wbase = os.path.join(self.d, "strategies")
        self.lease = os.path.join(self.state, "gpu_lease.json")
        self.cands = os.path.join(self.d, "cands.json")
        self.stub = os.path.join(self.d, "issue_stub.py")
        self.stublog = os.path.join(self.d, "issue_log.txt")
        io.open(self.stub, "w", encoding="utf-8").write(STUB)
        os.makedirs(self.state, exist_ok=True)
        wj(self.cands, cands if cands is not None else [
            {"key": "A.cpu", "source": "queue", "meta": {"paper_title": "Momentum crash factor in Korea"}},
            {"key": "B.gpu", "source": "queue", "meta": {"paper_title": "LSTM forecasting of stock returns"}},
            {"key": "C.cpu", "source": "queue", "meta": {"paper_title": "Value and profitability spreads"}},
            {"key": "D.cpu", "source": "queue", "meta": {"paper_title": "Low volatility anomaly"}},
            {"key": "E.gpu", "source": "queue", "meta": {"paper_title": "Graph neural network lead-lag"}}])

    def env(self, **kw):
        e = dict(os.environ)
        e.update({"QM_ROOT": ROOT, "QVEST_RF_CONFIG": self.cfg, "QVEST_RP_VARIANTS_CFG": self.variants, "QVEST_RP_STATE_DIR": self.state,
                  "QVEST_RP_SLOT_DIR": self.slotdir, "QVEST_RP_JLOG": self.jlog, "QVEST_RP_REQUEST": self.legacy_req,
                  "QVEST_RP_CLAIM": self.legacy_claim, "QVEST_RP_WDIR_BASE": self.wbase, "QVEST_GPU_LEASE": self.lease,
                  "QVEST_RP_CANDIDATES_JSON": self.cands, "QVEST_RP_ISSUE_CMD": self.stub, "STUB_LOG": self.stublog,
                  "PYTHONIOENCODING": "utf-8"})
        e.pop("RP_SLOT", None)
        e.update({k: str(v) for k, v in kw.items()})
        return e

    def run(self, args, slots_py=SLOTS, wait=True, **kw):
        cmd = [PY, "-X", "utf8", slots_py, "--root", ROOT] + args
        if not wait:
            return subprocess.Popen(cmd, env=self.env(**kw), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
        return subprocess.run(cmd, env=self.env(**kw), capture_output=True, text=True, encoding="utf-8", timeout=300)

    def tick(self, slots_py=SLOTS, **kw):
        r = self.run(["tick"], slots_py=slots_py, **kw)
        return sorted(l.split()[1] for l in r.stdout.splitlines() if l.startswith("LAUNCH ")), r

    def req(self, slot):
        return rj(os.path.join(self.slotdir, slot, "replication_request.json")) or {}

    def key(self, slot):
        return ((self.req(slot).get("paper") or {}).get("paper_key")) or ""

    def put_req(self, slot, key, status="pending", title=None, **extra):
        d = {"status": status, "slot": slot, "lane_mode": "normal",
             "paper": {"paper_key": key, "paper_title": title or key, "url": "http://127.0.0.1:9/" + key}}
        d.update(extra)
        wj(os.path.join(self.slotdir, slot, "replication_request.json"), d)

    def events(self, name=None):
        out = []
        if os.path.exists(self.jlog):
            for l in io.open(self.jlog, encoding="utf-8"):
                try:
                    r = json.loads(l)
                except Exception:
                    continue
                if name is None or r.get("event") == name:
                    out.append(r)
        return out

    def issued(self):
        if not os.path.exists(self.stublog):
            return []
        return [tuple(l.split()) for l in io.open(self.stublog, encoding="utf-8") if l.strip()]

    def paper_owner(self, key):
        sys.path.insert(0, OPS)
        import rf_replication_slots as rs
        p = os.path.join(self.state, "rf_replication.papers", rs.Lane.paper_slug(key) + ".paper", "owner.json")
        return (rj(p) or {}).get("slot")

    def claim(self, slot, owner_win=None, owner=4242, age_h=0.0, owner_start=None, paper=""):
        c = os.path.join(self.state, "rf_replication.claim." + slot)
        os.makedirs(c, exist_ok=True)
        io.open(os.path.join(c, "owner"), "w").write("%d\n" % owner)
        if owner_win is not None:
            io.open(os.path.join(c, "owner_win"), "w").write("%d\n" % owner_win)
        if owner_start is not None:
            io.open(os.path.join(c, "owner_start"), "w").write("%.3f\n" % owner_start)
        if paper:
            io.open(os.path.join(c, "paper"), "w").write(paper + "\n")
        if age_h:
            t = time.time() - age_h * 3600
            os.utime(c, (t, t))
        return c


def mutant_dir(base, name, edits):
    """rf_replication_slots.py · qv_lock.py · rf_compute_class.py 를 사본 디렉터리에 두고 치환을 건다 — 반환 (slots 사본 경로, 치환 성사 수 목록)."""
    d = os.path.join(base, "mut_" + name)
    os.makedirs(d)
    ns = []
    for f in ("rf_replication_slots.py", "qv_lock.py", "rf_compute_class.py"):
        s = io.open(os.path.join(OPS, f), encoding="utf-8").read()
        for (tf, old, new) in edits:
            if tf == f:
                ns.append(s.count(old))
                s = s.replace(old, new)
        io.open(os.path.join(d, f), "w", encoding="utf-8").write(s)
    return os.path.join(d, "rf_replication_slots.py"), ns


def sleeper(sec=120):
    return subprocess.Popen([PY, "-c", "import time; time.sleep(%d)" % sec])


def main():
    base = tempfile.mkdtemp(prefix="rpslots_test_")
    kids = []
    sys.path.insert(0, OPS)
    import qv_lock
    try:
        # ── S1 발행 = 등급별 슬롯 ─────────────────────────────────────────────
        f = Fx(base, "s1")
        launch, r = f.tick()
        check("S1 빈 슬롯 3개 발행 — gpu1 = GPU 논문(B · 큐 메타 LSTM) · cpu1/cpu2 = CPU 논문(A · C · 큐 순서) · LAUNCH 3줄",
              f.key("gpu1") == "B.gpu" and f.key("cpu1") == "A.cpu" and f.key("cpu2") == "C.cpu" and launch == ["cpu1", "cpu2", "gpu1"],
              (f.key("cpu1"), f.key("cpu2"), f.key("gpu1"), launch, r.stderr[-300:]))
        check("S1 논문 잠금 = 쥔 슬롯(A→cpu1 · C→cpu2 · B→gpu1)",
              f.paper_owner("A.cpu") == "cpu1" and f.paper_owner("C.cpu") == "cpu2" and f.paper_owner("B.gpu") == "gpu1")
        launch2, _ = f.tick()
        check("S1 다음 틱 — 바쁜 슬롯(pending · claim 없음)은 다시 발행하지 않고 다시 띄운다(발행 3회 그대로)",
              len(f.issued()) == 3 and launch2 == ["cpu1", "cpu2", "gpu1"], (f.issued(), launch2))

        # ── S2 두 틱 경합 ───────────────────────────────────────────────────
        def race(slots_py, name):
            g = Fx(base, name)
            ps = [g.run(["tick"], slots_py=slots_py, wait=False, STUB_SLEEP=1.5) for _ in range(2)]
            for p in ps:
                p.communicate(timeout=300)
            per = {}
            for s, k in g.issued():
                per[s] = per.get(s, 0) + 1
            keys = [g.key(s) for s in ("cpu1", "cpu2", "gpu1")]
            return per, keys, g
        per, keys, g2 = race(SLOTS, "s2")
        check("S2 두 틱 동시 — 슬롯당 발행 1회 · 슬롯 간 같은 논문 0(디스패처 잠금 + 발행 잠금 + 논문 잠금)",
              per == {"cpu1": 1, "cpu2": 1, "gpu1": 1} and len(set(keys)) == 3 and all(keys), (per, keys))
        mp, ns = mutant_dir(base, "s2", [
            ("rf_replication_slots.py", 'return _LockCtx(self.name_lock("rf_replication.issue"), wait_s, "rf_replication.issue")', "return _NoLock()"),
            ("rf_replication_slots.py", 'return _LockCtx(self.name_lock("rf_replication.dispatch"), wait_s, "rf_replication.dispatch")', "return _NoLock()"),
            ("rf_replication_slots.py", "class _LockCtx(object):", "class _NoLock(object):\n    def __enter__(self):\n        return None\n\n    def __exit__(self, *a):\n        return False\n\n\nclass _LockCtx(object):")])
        per_m, keys_m, _ = race(mp, "s2_mut")
        check("S2 뮤테이션(디스패처 · 발행 잠금 제거)판은 같은 슬롯을 두 번 발행한다 → 위 검사가 잡는 결함 · 치환 3곳",
              ns == [1, 1, 1] and max(per_m.values() or [0]) >= 2, (ns, per_m))

        # ── S3 같은 논문 중복 ───────────────────────────────────────────────
        f = Fx(base, "s3")
        f.tick()                                      # cpu1 = A (잠금 cpu1)
        f.put_req("cpu2", "A.cpu")                    # 세션이 손으로 같은 논문을 cpu2 에 썼다(위반 주입)
        r3 = f.run(["paper-lock", "--slot", "cpu2"])
        r3b = f.run(["paper-lock", "--slot", "cpu1"])
        check("S3 다른 슬롯이 바쁘게 쥔 논문 — cpu2 펜싱 rc 3 · cpu2 요청 = duplicate_held_elsewhere(cpu1) · cpu1 은 그대로 rc 0",
              r3.returncode == 3 and f.req("cpu2").get("status") == "duplicate_held_elsewhere" and f.req("cpu2").get("duplicate_of") == "cpu1"
              and r3b.returncode == 0 and f.req("cpu1").get("status") == "pending" and f.paper_owner("A.cpu") == "cpu1",
              (r3.returncode, f.req("cpu2").get("status"), r3b.returncode))
        f.put_req("cpu1", "A.cpu", status="done")     # cpu1 이 끝냈다 → 잠금은 죽은 잠금
        f.put_req("cpu2", "A.cpu")
        r3c = f.run(["paper-lock", "--slot", "cpu2"])
        check("S3 쥔 슬롯이 끝낸 논문(요청 done) = 죽은 잠금 → 회수 후 cpu2 가 잡는다(양방향)", r3c.returncode == 0 and f.paper_owner("A.cpu") == "cpu2",
              (r3c.returncode, r3c.stdout))
        fm = Fx(base, "s3_mut")
        mp, ns = mutant_dir(base, "s3", [("rf_replication_slots.py", "                if self.paper_lock_live(o):\n                    return False, o.get(\"slot\")",
                                          "                if False:\n                    return False, o.get(\"slot\")")])
        fm.tick(slots_py=mp)
        fm.put_req("cpu2", "A.cpu")
        r3m = fm.run(["paper-lock", "--slot", "cpu2"], slots_py=mp)
        check("S3 뮤테이션(생존 판정 제거)판은 살아 있는 cpu1 의 논문을 cpu2 가 빼앗는다(rc 0) → 위 검사가 잡는 결함 · 치환 1곳",
              ns == [1] and r3m.returncode == 0 and fm.paper_owner("A.cpu") == "cpu2", (ns, r3m.returncode))

        # ── S4 슬롯 소유자 사망 · 생존 · claim_live_long · pid 재사용 ─────────────
        f = Fx(base, "s4")
        f.put_req("cpu1", "A.cpu", status="in_progress")
        f.run(["paper-lock", "--slot", "cpu1"])
        f.claim("cpu1", owner_win=DEAD_PID, paper="A.cpu")
        launch, _ = f.tick()
        rec = [e for e in f.events("claim_stale_reclaim") if e.get("slot") == "cpu1"]
        check("S4 죽은 소유자 claim — 나이 무관 즉시 회수(claim_stale_reclaim dead=1) · 재착수(LAUNCH cpu1) · 요청 in_progress 보존(작업자가 되살린다)",
              rec and rec[0].get("dead") == "1" and "cpu1" in launch and not os.path.isdir(os.path.join(f.state, "rf_replication.claim.cpu1"))
              and f.req("cpu1").get("status") == "in_progress", (rec, launch))
        check("S4 죽은 작업자의 논문(A)은 다른 슬롯이 못 가져간다 — cpu2 는 다음 후보(C) · 잠금 cpu1",
              f.key("cpu2") == "C.cpu" and f.paper_owner("A.cpu") == "cpu1", (f.key("cpu2"), f.paper_owner("A.cpu")))
        sp = sleeper(); kids.append(sp)
        time.sleep(0.3)
        g = Fx(base, "s4b")
        g.put_req("cpu1", "A.cpu", status="in_progress")
        g.run(["paper-lock", "--slot", "cpu1"])
        g.claim("cpu1", owner_win=sp.pid, age_h=7, paper="A.cpu")
        l1, _ = g.tick()
        l2, _ = g.tick()
        ll = [e for e in g.events("claim_live_long") if e.get("slot") == "cpu1"]
        check("S4 살아 있는 소유자 — 7h ≥ 6h 라도 회수하지 않는다(계산 시간 상한 없음) · claim_live_long 은 claim 당 1번 · 그 슬롯은 띄우지 않는다",
              os.path.isdir(os.path.join(g.state, "rf_replication.claim.cpu1")) and len(ll) == 1 and "cpu1" not in l1 + l2
              and not [e for e in g.events("claim_stale_reclaim") if e.get("slot") == "cpu1"], (len(ll), l1, l2))
        h = Fx(base, "s4c")
        h.put_req("cpu1", "A.cpu", status="in_progress")
        h.claim("cpu1", owner_win=sp.pid, owner_start=(qv_lock.proc_start(sp.pid) or 0) - 3600, paper="A.cpu")
        l3, _ = h.tick()
        check("S4 pid 재사용(살아 있는 pid · 시작 시각 불일치) = 죽은 소유자 → 회수 · 재착수", "cpu1" in l3 and
              [e for e in h.events("claim_stale_reclaim") if e.get("slot") == "cpu1" and e.get("why") == "pid_reused"], l3)

        # ── S5 GPU 오배치 ───────────────────────────────────────────────────
        f = Fx(base, "s5", cands=[{"key": "A.cpu", "source": "queue", "meta": {"paper_title": "Momentum"}}])
        f.put_req("cpu1", "B.gpu", title="LSTM forecasting of stock returns")
        f.run(["paper-lock", "--slot", "cpu1"])
        cls = f.run(["classify", "--req", os.path.join(f.slotdir, "cpu1", "replication_request.json")]).stdout.strip()
        ho = f.run(["handoff", "--slot", "cpu1", "--reason", "test_misplacement"])
        inbox = [x for x in os.listdir(os.path.join(f.slotdir, "_gpu_inbox"))] if os.path.isdir(os.path.join(f.slotdir, "_gpu_inbox")) else []
        check("S5 CPU 슬롯의 GPU 논문 — 판별 gpu(큐 메타 LSTM) · 인계 → 인계함 1건 · cpu1 요청 = handed_off_gpu · 논문 잠금 = gpu_inbox",
              cls.startswith("gpu queue_keywords") and ho.returncode == 0 and len(inbox) == 1 and f.req("cpu1").get("status") == "handed_off_gpu"
              and f.paper_owner("B.gpu") == "gpu_inbox", (cls, ho.stdout, inbox, f.req("cpu1").get("status")))
        launch, _ = f.tick()
        check("S5 다음 틱 — gpu1 이 인계함에서 B 를 받는다(pending) · LAUNCH gpu1 · 인계함 비움 · cpu1 은 새 CPU 논문(A)",
              f.key("gpu1") == "B.gpu" and f.req("gpu1").get("status") == "pending" and "gpu1" in launch and not os.listdir(os.path.join(f.slotdir, "_gpu_inbox"))
              and f.key("cpu1") == "A.cpu" and f.paper_owner("B.gpu") == "gpu1", (f.key("gpu1"), launch, f.key("cpu1")))
        # 구현 의존성(engine.R → _work/model.py import torch) — 큐 메타가 CPU 여도 gpu · torch 없는 엔진은 메타가 LSTM 이어도 cpu
        w = os.path.join(base, "wd_torch"); os.makedirs(os.path.join(w, "_work"))
        io.open(os.path.join(w, "engine.R"), "w").write('py <- file.path(WDIR, "_work", "model.py")\nsystem2(PY, py)\n')
        io.open(os.path.join(w, "_work", "model.py"), "w").write("import numpy as np\nimport torch\nnet = torch.nn.LSTM(4, 8)\n")
        w2 = os.path.join(base, "wd_cpu"); os.makedirs(w2)
        io.open(os.path.join(w2, "engine.R"), "w").write("# import torch  (주석은 의존이 아니다)\nFACTORS <- data.frame()\n")
        rq = os.path.join(base, "rq.json"); wj(rq, {"paper": {"paper_key": "X", "paper_title": "Value factor"}})
        rq2 = os.path.join(base, "rq2.json"); wj(rq2, {"paper": {"paper_key": "Y", "paper_title": "Deep learning LSTM returns"}})
        c1 = f.run(["classify", "--req", rq, "--wdir", w]).stdout.strip()
        c2 = f.run(["classify", "--req", rq2, "--wdir", w2]).stdout.strip()
        check("S5 구현 의존성이 큐 메타보다 우선 — torch 를 부르는 엔진 = gpu · 주석의 torch 는 의존 아님 = cpu(양방향)",
              c1.startswith("gpu engine_dependency") and c2.startswith("cpu engine_dependency"), (c1, c2))
        mp, ns = mutant_dir(base, "s5", [("rf_compute_class.py", 'ENGINE_DEP_RE = re.compile(r"(?m)^(?![ \\t]*#).*?(', 'ENGINE_DEP_RE = re.compile(r"(?m)^(?![ \\t]*#).*?(?!)(')])
        c1m = f.run(["classify", "--req", rq, "--wdir", w], slots_py=mp).stdout.strip()
        check("S5 뮤테이션(의존 정규식 무력화)판은 torch 엔진을 cpu 로 본다 → 위 검사가 잡는 결함 · 치환 1곳",
              ns == [1] and c1m.startswith("cpu"), (ns, c1m))

        # ── S6 GPU 임대 ─────────────────────────────────────────────────────
        def lease_case(name, started_ago_h, slots_py=SLOTS, holder_pid=None):
            g = Fx(base, name)
            for s, k in (("cpu1", "A.cpu"), ("cpu2", "C.cpu"), ("gpu1", "B.gpu")):
                g.put_req(s, k)
            wj(g.lease, {"schema": "gpu_lease_v1", "holder": "P2R05_measure", "purpose": "분위 DNN", "started_epoch": time.time() - started_ago_h * 3600,
                         "started_at": "x", "cap_hours": 12, "holder_pid": holder_pid, "holder_proc_start": None})
            l, _ = g.tick(slots_py=slots_py)
            return g, l
        g, l = lease_case("s6a", 1)
        check("S6 유효 임대(1h/12h) — GPU 슬롯 보류(LAUNCH 없음 · 요청 보존) · CPU 슬롯은 그대로 · 임대 파일 유지",
              l == ["cpu1", "cpu2"] and g.req("gpu1").get("status") == "pending" and os.path.exists(g.lease), l)
        g, l = lease_case("s6b", 13)
        ex = g.events("gpu_lease_expired")
        check("S6 만료 임대(13h > 12h) — 틱이 스스로 풀고(gpu_lease_expired · 파일 제거) GPU 슬롯 재개(LAUNCH gpu1)",
              "gpu1" in l and ex and not os.path.exists(g.lease), (l, len(ex)))
        mp, ns = mutant_dir(base, "s6", [("qv_lock.py", "    if now >= exp:\n        out[\"state\"] = \"expired\"", "    if False:\n        out[\"state\"] = \"expired\"")])
        g, l = lease_case("s6m", 13, slots_py=mp)
        check("S6 뮤테이션(만료 비교 제거)판은 만료 임대에 GPU 슬롯을 영영 보류한다 → 위 검사가 잡는 결함 · 치환 1곳",
              ns == [1] and "gpu1" not in l, (ns, l))
        dpp = sleeper(); kids.append(dpp); time.sleep(0.3)
        dpid = dpp.pid
        dpp.kill(); dpp.wait(10)
        g, l = lease_case("s6c", 1, holder_pid=dpid)
        check("S6 보유 프로세스가 죽은 임대(holder_dead) — 만료 전이라도 틱이 풀고 GPU 슬롯 재개", "gpu1" in l and g.events("gpu_lease_expired"), l)
        g = Fx(base, "s6d")
        wj(g.lease, {"schema": "gpu_lease_v1", "holder": "P2R05_measure", "purpose": "x", "started_epoch": time.time(), "started_at": "x", "cap_hours": 12})
        l, _ = g.tick()
        check("S6 임대 중 빈 GPU 슬롯은 발행도 하지 않는다(GPU 논문은 큐에 남는다) · CPU 슬롯은 발행",
              g.req("gpu1").get("status") == "idle" and g.key("cpu1") and g.key("cpu2") and "gpu1" not in l, (g.req("gpu1").get("status"), l))

        # ── S7 구판 요청 인수 ───────────────────────────────────────────────
        sp2 = sleeper(); kids.append(sp2); time.sleep(0.3)
        f = Fx(base, "s7")
        wj(f.legacy_req, {"status": "in_progress", "lane_mode": "normal",
                          "paper": {"paper_key": "2601.04602", "paper_title": "Hybrid Transformer Graph Neural Network", "url": "http://127.0.0.1:9/x"}})
        os.makedirs(f.legacy_claim)
        io.open(os.path.join(f.legacy_claim, "owner"), "w").write("1\n")
        io.open(os.path.join(f.legacy_claim, "owner_win"), "w").write("%d\n" % sp2.pid)
        for s, k in (("gpu1", "E.gpu"),):
            f.put_req(s, k)
        l, _ = f.tick()
        check("S7 살아 있는 구판 작업자(GPU 논문) = 점유 — 인수 안 함 · GPU 슬롯 띄우지 않음(GPU 두 작업 겹침 방지) · 그 논문은 발행 제외",
              f.req("gpu1").get("status") == "pending" and "gpu1" not in l and (rj(f.legacy_req) or {}).get("status") == "in_progress"
              and "2601.04602" not in [f.key("cpu1"), f.key("cpu2")], l)
        shutil.rmtree(f.legacy_claim)
        os.makedirs(f.legacy_claim)
        io.open(os.path.join(f.legacy_claim, "owner_win"), "w").write("%d\n" % DEAD_PID)
        f.put_req("gpu1", "E.gpu", status="done")
        l, _ = f.tick()
        check("S7 구판 작업자 사망 — 구판 claim 회수 · 요청을 등급 맞는 슬롯(gpu1)으로 인수 · 구판 자리 = adopted_by_slot · LAUNCH gpu1",
              f.key("gpu1") == "2601.04602" and f.req("gpu1").get("adopted_from") == "legacy" and (rj(f.legacy_req) or {}).get("status") == "adopted_by_slot"
              and not os.path.isdir(f.legacy_claim) and "gpu1" in l and f.paper_owner("2601.04602") == "gpu1", (f.key("gpu1"), l))

        # ── S8 용량 · S9 백오프 ──────────────────────────────────────────────
        f = Fx(base, "s8")
        wj(f.legacy_req, {"status": "in_progress", "paper": {"paper_key": "Z.legacy", "paper_title": "Value spread", "url": "u"}})
        os.makedirs(f.legacy_claim)
        io.open(os.path.join(f.legacy_claim, "owner_win"), "w").write("%d\n" % sp2.pid)
        f.put_req("cpu1", "A.cpu"); f.put_req("cpu2", "C.cpu")
        l, _ = f.tick()
        check("S8 살아 있는 구판 CPU 작업자 = CPU 용량 1 감산 — CPU 2슬롯 중 1개만 띄운다", sum(1 for s in l if s.startswith("cpu")) == 1, l)
        f = Fx(base, "s9")
        f.put_req("cpu1", "A.cpu", env_retry_after_epoch=int(time.time()) + 600)
        f.put_req("cpu2", "C.cpu")
        l, _ = f.tick()
        check("S9 환경 백오프(한도 소진 · 600초) 요청은 띄우지 않는다 · 다른 슬롯은 띄운다", "cpu1" not in l and "cpu2" in l, l)

        # ── S10 일 소진량 ───────────────────────────────────────────────────
        f = Fx(base, "s10")
        day = time.strftime("%Y-%m-%d")
        ev = [("replication_auto", "start", "cpu1", {"paper": "A"}), ("replication_auto", "model_selected", "cpu1", {}),
              ("replication_auto", "start", "gpu1", {"paper": "B"}), ("replication_auto", "model_selected", "gpu1", {}),
              ("replication_auto", "agent_done", "cpu1", {"fell_back": "0"}), ("replication_auto", "agent_done", "gpu1", {"fell_back": "1"}),
              ("fidelity_audit", "delegate_fanout", None, {"paper": "A"}), ("fidelity_fanout", "agents_done", None, {"axes": "6"}),
              ("replication_auto", "halt_env_failure", "cpu2", {"kind": "model_quota_exhausted"})]
        with io.open(f.jlog, "w", encoding="utf-8") as fh:
            for i, (src, e, s, kv) in enumerate(ev):
                r = {"ts": "%sT10:%02d:00+0900" % (day, i * 5), "event": e, "src": src}
                if s:
                    r["slot"] = s
                r.update(kv)
                fh.write(json.dumps(r) + "\n")
        b = json.loads(f.run(["burn", "--days", "1", "--json"]).stdout)
        rows = {x["slot"]: x for x in b["rows"]}
        tot = b["by_day"].get(day, {})
        check("S10 일 소진량 — 슬롯별 논문 · 구현 에이전트(폴백 = 2회) · 분 · 감사 에이전트(논문→슬롯 귀속) · 한도 사건 · 일 합계 LLM 세션",
              rows["cpu1"]["papers"] == 1 and rows["cpu1"]["impl_agents"] == 1 and rows["cpu1"]["agent_min"] == 15.0 and rows["cpu1"]["audit_agents"] == 6
              and rows["gpu1"]["impl_agents"] == 2 and rows["cpu2"]["quota_hits"] == 1 and tot.get("llm_sessions") == 9 and tot.get("papers") == 2,
              (b["rows"], tot))

        # ── S11 설정 켜기 · 끄기 ─────────────────────────────────────────────
        f = Fx(base, "s11", slots=False)
        l0 = f.run(["tick"]).stdout.strip()
        e1 = f.run(["config", "enable", "--cpu", "3", "--gpu", "1"])
        c1 = rj(f.cfg)["replication_lane"]
        l1, _ = f.tick()
        e2 = f.run(["config", "disable"])
        c2 = rj(f.cfg)["replication_lane"]
        l2 = f.run(["tick"]).stdout.strip()
        check("S11 설정 — slots 없음 = LEGACY(구판 단일 슬롯) · enable = slots{cpu 3, gpu 1} + 임대 기본 12h · 슬롯 4개 동작 · disable = slots 제거 → LEGACY",
              l0 == "LEGACY" and e1.returncode == 0 and c1.get("slots") == {"cpu": 3, "gpu": 1} and c1["gpu_lease"]["default_cap_hours"] == 12
              and len(l1) == 4 and e2.returncode == 0 and "slots" not in c2 and c2.get("enabled") is True and l2 == "LEGACY", (l0, c1.get("slots"), l1, l2))

        # ── S12 틱 요약(_status.json) → 부팅 줄(boot_lean.sh PEND) · Superfan worst_status ─────────────────────
        import re
        f = Fx(base, "s12")
        f.tick()
        f.put_req("cpu2", "C.cpu", status="failed_needs_session")
        f.tick()
        st = rj(os.path.join(f.slotdir, "_status.json")) or {}
        check("S12 틱 요약 — 슬롯 3행 · 확인 대상(cpu2 failed_needs_session) · worst_status = failed_needs_session(Superfan json_field 가 읽는 값)",
              st.get("schema") == "replication_slots_status_v1" and len(st.get("slots") or []) == 3 and "cpu2:failed_needs_session" in (st.get("attention") or [])
              and st.get("worst_status") == "failed_needs_session", st)
        src = io.open(os.path.join(ROOT, "02_Infrastructure", "ops", "boot_lean.sh"), encoding="utf-8").read()
        m = re.search(r"^def PEND\(\):\n(?:[ \t].*\n|\n)+", src, re.M)
        out_on = out_off = None
        if m:
            import glob as _glob
            def run_pend(root):
                ns = {"glob": _glob, "os": os, "time": time, "json": json,
                      "R": lambda *a: os.path.join(root, *a),
                      "J": lambda p: rj(os.path.join(root, p))}
                exec(m.group(0), ns)
                return ns["PEND"]()
            broot = os.path.join(base, "bootroot")
            os.makedirs(os.path.join(broot, "06_Registry", "replication_slots"))
            out_off = run_pend(broot)
            shutil.copy(os.path.join(f.slotdir, "_status.json"), os.path.join(broot, "06_Registry", "replication_slots", "_status.json"))
            out_on = run_pend(broot)
        check("S12 부팅 줄 — 요약이 있으면 '레인 슬롯 바쁨/전체 · ★확인 n' · 없으면(구판) 표기 없음(양방향)",
              m is not None and "레인 슬롯 3/3" in (out_on or "") and "★확인 1" in (out_on or "") and "레인 슬롯" not in (out_off or "x"),
              (out_on, out_off))
    finally:
        for k in kids:
            try:
                k.kill()
            except Exception:
                pass
        shutil.rmtree(base, ignore_errors=True)
    n_fail = sum(1 for _, ok in RESULTS if not ok)
    print("== %d checks · %d failed" % (len(RESULTS), n_fail))
    print(json.dumps({"test": "replication_slots", "pass": len(RESULTS) - n_fail, "fail": n_fail, "total": len(RESULTS)}))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
