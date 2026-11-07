#!/usr/bin/env python3
# =============================================================================
# test_qv_lock.py — 쓰기 잠금 · GPU 임대 정본(02_Infrastructure/ops/qv_lock.py · 2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020) 양성 대조
#   위반을 일부러 일으켜 잡히는지 본다(양방향) + 뮤테이션(소스 텍스트 치환 사본 — 치환 성사 단정)으로 검사 자체의 검출력을 잰다.
#   L1 기본 · 재진입 / L2 두 프로세스 경합(시간 제한 · 대기 후 획득) / L3 죽은 소유자 즉시 회수 / L4 pid 재사용 판별 /
#   L5 소유자 표식 없는 잠금(유예 · 경과) / L6 매달린 소유자 회수 + 펜싱(잃은 쪽은 쓰지 않는다) / L7 회수 경합 — 판정 뒤 새 소유자를 지우지 않는다(+뮤테이션) /
#   L8 동시 8프로세스 상호 배제(구간 겹침 0) / G1~G8 GPU 임대(획득 · 거부 · 멱등 · 해제 · 상한 자르기 · 만료(+뮤테이션) · 보유자 사망 · 이력 · CLI)
#   운영 잠금 · 임대 · 설정 무접촉 — 전부 임시 디렉터리(QVEST_GPU_LEASE · QVEST_RF_CONFIG · 잠금 경로 직접 지정). GPU 를 쓰지 않는다.
# 실행: .venv_qvest_ml/Scripts/python.exe 08_Tests/ops/test_qv_lock.py
# =============================================================================
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "02_Infrastructure", "ops"))
from qv_bash import qv_bash  # bare "bash" 금지(금칙 ⑦ · 11-07) — WSL 있는 PC 에선 System32 bash 가 PATH 보다 먼저 잡힌다
import time

ROOT = os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OPS = os.path.join(ROOT, "02_Infrastructure", "ops")
SRC = os.path.join(OPS, "qv_lock.py")
PY = sys.executable
RESULTS = []
DEAD_PID = 999901


def check(name, cond, info=""):
    RESULTS.append((name, bool(cond)))
    print("%s %s%s" % ("PASS" if cond else "FAIL", name, ("  — " + str(info)[:300]) if (info and not cond) else ""))


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def mutant(tmp, old, new, name):
    """소스 텍스트 치환 사본 — 치환이 정확히 1곳 성사돼야 한다(빗나간 치환 = 가짜 양성 대조 · 10-15 교훈)."""
    s = io.open(SRC, encoding="utf-8").read()
    n = s.count(old)
    d = os.path.join(tmp, "mut_" + name)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "qv_lock.py")
    io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
    return p, n


def sleeper(sec=60):
    return subprocess.Popen([PY, "-c", "import time; time.sleep(%d)" % sec])


def holder_proc(lockdir, hold_s, flag, src=SRC, owner_extra=""):
    code = ("import sys,time,importlib.util as u\n"
            "s=u.spec_from_file_location('q',r'%s');q=u.module_from_spec(s);s.loader.exec_module(q)\n"
            "h=q.acquire(r'%s',wait_s=30)\n"
            "open(r'%s','w').write(str(time.time()))\n"
            "time.sleep(%f)\n"
            "q.release(h)\n") % (src, lockdir, flag, hold_s)
    return subprocess.Popen([PY, "-c", code])


def wait_file(p, timeout=20):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if os.path.exists(p):
            return True
        time.sleep(0.05)
    return False


def main():
    q = load_module(SRC, "qv_lock_under_test")
    tmp = tempfile.mkdtemp(prefix="qvlock_test_")
    kids = []
    try:
        # ── L1 기본 · 재진입 ─────────────────────────────────────────────────
        ld = os.path.join(tmp, "a", "x.qvlock")
        h = q.acquire(ld, wait_s=1)
        st = q.lock_state(ld)
        check("L1 획득 → 상태 held(소유 pid = 이 프로세스 · 토큰 기록)", st["state"] == "held" and st["owner"]["pid"] == os.getpid()
              and st["owner"]["schema"] == "qv_lock_v1", st)
        h2 = q.acquire(ld, wait_s=0.2)
        check("L1 같은 프로세스 재진입 = 깊이 2(교착 없음)", h2 is h and h.depth == 2)
        r1, r2 = q.release(h2), q.release(h)
        check("L1 해제 = nested → released · 디렉터리 제거", r1 == "nested" and r2 == "released" and not os.path.isdir(ld), (r1, r2))

        # ── L2 두 프로세스 경합 ───────────────────────────────────────────────
        ld2 = os.path.join(tmp, "b", "y.qvlock")
        fl = os.path.join(tmp, "b_flag")
        p = holder_proc(ld2, 2.5, fl)
        kids.append(p)
        ok_hold = wait_file(fl)
        t0 = time.time()
        try:
            q.acquire(ld2, wait_s=0.4)
            timed_out = False
        except q.LockTimeout:
            timed_out = True
        check("L2 다른 프로세스가 쥔 잠금 — 시간 제한 안에 못 잡으면 LockTimeout(쓰지 않는다)", ok_hold and timed_out and time.time() - t0 < 3, (ok_hold, timed_out))
        t1 = time.time()
        h = q.acquire(ld2, wait_s=15)
        waited = time.time() - t1
        check("L2 보유자가 놓으면 대기자가 잡는다(대기 = 보유 시간 근처)", h is not None and 0.5 < waited < 10, waited)
        q.release(h)
        p.wait(10)

        # ── L3 죽은 소유자 즉시 회수 ─────────────────────────────────────────
        ld3 = os.path.join(tmp, "c", "z.qvlock")
        os.makedirs(ld3)
        q._atomic_json(os.path.join(ld3, "owner.json"), {"schema": "qv_lock_v1", "pid": DEAD_PID, "proc_start": None, "token": "deadbeefdeadbeef",
                                                         "acquired_epoch": time.time(), "purpose": "fixture"})
        st = q.lock_state(ld3)
        t0 = time.time()
        h = q.acquire(ld3, wait_s=2)
        check("L3 죽은 소유자(pid %d) = stale(dead_owner) → 나이 무관 즉시 회수" % DEAD_PID,
              st["state"] == "stale" and st["why"] == "dead_owner" and time.time() - t0 < 1.5 and q.lock_state(ld3)["owner"]["pid"] == os.getpid(), st)
        q.release(h)

        # ── L4 pid 재사용 판별(살아 있는 pid · 시작 시각 불일치) ────────────────
        sp = sleeper(60); kids.append(sp)
        time.sleep(0.3)
        ld4 = os.path.join(tmp, "d", "w.qvlock")
        os.makedirs(ld4)
        real_start = q.proc_start(sp.pid)
        q._atomic_json(os.path.join(ld4, "owner.json"), {"schema": "qv_lock_v1", "pid": sp.pid, "proc_start": (real_start or 0) - 3600,
                                                         "token": "1111222233334444", "acquired_epoch": time.time(), "purpose": "fixture"})
        st_reuse = q.lock_state(ld4)
        q._atomic_json(os.path.join(ld4, "owner.json"), {"schema": "qv_lock_v1", "pid": sp.pid, "proc_start": real_start,
                                                         "token": "1111222233334445", "acquired_epoch": time.time(), "purpose": "fixture"})
        st_live = q.lock_state(ld4)
        check("L4 살아 있는 pid 라도 시작 시각이 기록과 다르면 남의 프로세스(pid_reused) · 같으면 held(양방향)",
              real_start is not None and st_reuse["state"] == "stale" and st_reuse["why"] == "pid_reused" and st_live["state"] == "held",
              (real_start, st_reuse.get("why"), st_live.get("state")))
        shutil.rmtree(ld4, ignore_errors=True)

        # ── L5 소유자 표식 없는 잠금 ──────────────────────────────────────────
        ld5 = os.path.join(tmp, "e", "v.qvlock")
        os.makedirs(ld5)
        st_young = q.lock_state(ld5)
        old = time.time() - (q.NO_OWNER_GRACE_S + 5)
        os.utime(ld5, (old, old))
        st_old = q.lock_state(ld5)
        h = q.acquire(ld5, wait_s=1)
        check("L5 owner.json 없는 잠금 — 유예 안 = held(만드는 중) · 유예 지나면 stale(no_owner) → 회수",
              st_young["state"] == "held" and st_young["why"] == "no_owner_yet" and st_old["state"] == "stale" and st_old["why"] == "no_owner"
              and h is not None, (st_young, st_old))
        q.release(h)

        # ── L6 매달린 소유자(살아 있음 · 나이 > stale_s) 회수 + 펜싱 ─────────────
        ld6 = os.path.join(tmp, "f", "u.qvlock")
        h_old = q.acquire(ld6, wait_s=1)                      # 이 프로세스가 '매달린 소유자' 역 — 기록 나이를 과거로 돌린다
        o = q._read_owner(ld6); o["acquired_epoch"] = time.time() - 1000; q._atomic_json(os.path.join(ld6, "owner.json"), o)
        st6 = q.lock_state(ld6, stale_s=600)
        q._HELD.clear()                                      # 다른 프로세스 흉내(재진입 표 비움)
        h_new = q.acquire(ld6, wait_s=1, stale_s=600)
        target = os.path.join(tmp, "f", "ledger.json")
        io.open(target, "w").write('{"v": 0}')
        lost = False
        try:
            q.atomic_write_json(target, {"v": 1}, lock=h_old)
        except q.LockLost:
            lost = True
        check("L6 매달린 생존 소유자(나이 1000s > 600s) = stale(too_old) → 회수 · 빼앗긴 쪽은 펜싱에서 LockLost(쓰지 않는다)",
              st6["why"] == "too_old" and h_new is not None and lost and json.load(io.open(target))["v"] == 0, (st6, lost))
        q.atomic_write_json(target, {"v": 2}, lock=h_new)
        check("L6 새 소유자는 같은 펜싱을 통과해 쓴다(양방향)", json.load(io.open(target))["v"] == 2)
        q.release(h_new)

        # ── L7 회수 경합 — 판정 뒤 새 소유자가 생기면 옛 판정으로 지우지 않는다(+ 뮤테이션) ──────────────
        def l7(mod, sub):
            ld7 = os.path.join(tmp, sub, "t.qvlock")
            os.makedirs(ld7)
            mod._atomic_json(os.path.join(ld7, "owner.json"), {"schema": "qv_lock_v1", "pid": DEAD_PID, "proc_start": None,
                                                               "token": "aaaabbbbccccdddd", "acquired_epoch": time.time(), "purpose": "fixture"})
            judged = mod.lock_state(ld7)                       # B 가 stale 로 판정
            assert mod._reclaim(ld7, judged)                   # A 가 먼저 회수하고
            mod._HELD.clear()
            hA = mod.acquire(ld7, wait_s=1)                    # A 가 새로 잡는다
            mod._reclaim(ld7, judged)                          # B 가 옛 판정으로 회수를 시도
            return hA.is_mine()
        check("L7 회수 경합 — 판정 때 토큰이 바뀌었으면 회수하지 않는다(A 의 새 잠금 보존)", l7(q, "g") is True)
        mp, n = mutant(tmp, 'if (cur or {}).get("token") != jt:\n            return False', 'if False:\n            return False', "l7")
        qm = load_module(mp, "qv_lock_mut_l7")
        check("L7 뮤테이션(토큰 대조 제거)판은 A 의 잠금을 지운다 → 위 검사가 잡는 결함(검출력) · 치환 1곳", n == 1 and l7(qm, "g_mut") is False, n)

        # ── L8 동시 8프로세스 상호 배제 ───────────────────────────────────────
        ld8 = os.path.join(tmp, "h", "s.qvlock")
        log8 = os.path.join(tmp, "h_intervals.txt")
        code = ("import sys,time,importlib.util as u,os\n"
                "s=u.spec_from_file_location('q',r'%s');q=u.module_from_spec(s);s.loader.exec_module(q)\n"
                "for i in range(3):\n"
                "  h=q.acquire(r'%s',wait_s=60)\n"
                "  a=time.time(); time.sleep(0.08); b=time.time()\n"
                "  open(r'%s','a').write('%%d %%.6f %%.6f\\n'%%(os.getpid(),a,b))\n"
                "  q.release(h)\n") % (SRC, ld8, log8)
        ps = [subprocess.Popen([PY, "-c", code]) for _ in range(8)]
        rcs = [x.wait(120) for x in ps]
        iv = sorted(tuple(map(float, l.split()[1:])) for l in io.open(log8) if l.strip())
        overlap = sum(1 for i in range(1, len(iv)) if iv[i][0] < iv[i - 1][1])
        check("L8 8프로세스 × 3회 임계구역 — 구간 겹침 0 · 24구간 · 전부 정상 종료", rcs == [0] * 8 and len(iv) == 24 and overlap == 0,
              (rcs, len(iv), overlap))

        # ── G GPU 임대 ───────────────────────────────────────────────────────
        lease = os.path.join(tmp, "lease", "gpu_lease.json")
        cfg = os.path.join(tmp, "cfg.json")
        json.dump({"replication_lane": {"enabled": True, "gpu_lease": {"default_cap_hours": 12, "max_cap_hours": 12}}}, io.open(cfg, "w"))
        os.environ["QVEST_GPU_LEASE"] = lease
        os.environ["QVEST_RF_CONFIG"] = cfg
        r = q.gpu_lease_acquire("P2R05_measure", "분위 DNN 재학습")
        check("G1 빈 GPU 임대 획득 — cap 기본 12h(설정) · 만료 시각 기록", r["ok"] and r["reason"] == "acquired" and r["lease"]["cap_hours"] == 12
              and q.gpu_lease_status()["state"] == "held", r)
        r2 = q.gpu_lease_acquire("other_round", "x")
        r3 = q.gpu_lease_acquire("P2R05_measure", "분위 DNN 재학습", 5)
        check("G2 다른 보유자 = held_by_other(ok False) · 같은 보유자 = already_held(연장 없음 · 상한은 시작 기준)",
              (not r2["ok"]) and r2["reason"] == "held_by_other" and r3["ok"] and r3["reason"] == "already_held" and r3["lease"]["cap_hours"] == 12,
              (r2, r3))
        rr = q.gpu_lease_release("other_round")
        rr2 = q.gpu_lease_release("P2R05_measure")
        rr3 = q.gpu_lease_release("P2R05_measure")
        check("G3 해제 — 남의 임대는 못 놓는다 · 보유자는 놓는다 · 없는 임대 해제 = not_held(멱등)",
              (not rr["ok"]) and rr2["ok"] and rr2["reason"] == "released" and rr3["reason"] == "not_held" and q.gpu_lease_status()["state"] == "free",
              (rr, rr2, rr3))
        r4 = q.gpu_lease_acquire("big", "too long", 50)
        check("G4 상한 넘는 요청 → 상한(12h)으로 자르고 note 기록", r4["ok"] and r4["lease"]["cap_hours"] == 12 and "상한" in (r4.get("note") or ""), r4)
        # 만료 — 시작 시각을 13시간 전으로 돌린다
        L = json.load(io.open(lease, encoding="utf-8")); L["started_epoch"] = time.time() - 13 * 3600
        q._atomic_json(lease, L)
        st = q.gpu_lease_status()
        ex = q.gpu_lease_expire_check()
        check("G5 시작 + 12h 지나면 expired → 틱 판정(expire-check)이 파일을 치운다(외부 감시 없음)",
              st["state"] == "expired" and ex.get("cleared") and not os.path.exists(lease), (st.get("state"), ex.get("cleared")))
        q.gpu_lease_acquire("big", "too long", 12)
        L = json.load(io.open(lease, encoding="utf-8")); L["started_epoch"] = time.time() - 13 * 3600
        q._atomic_json(lease, L)
        mp, n = mutant(tmp, "    if now >= exp:\n        out[\"state\"] = \"expired\"", "    if False:\n        out[\"state\"] = \"expired\"", "g5")
        qm = load_module(mp, "qv_lock_mut_g5")
        check("G5 뮤테이션(만료 비교 제거)판은 13h 임대를 held 로 본다 → 위 검사가 잡는 결함 · 치환 1곳",
              n == 1 and qm.gpu_lease_status()["state"] == "held", n)
        os.remove(lease)
        dp = sleeper(60); kids.append(dp)
        time.sleep(0.3)
        r6 = q.gpu_lease_acquire("round_runner", "GPU stage", 8, holder_pid=dp.pid)
        st_alive = q.gpu_lease_status()["state"]
        dp.kill(); dp.wait(10)
        time.sleep(0.3)
        st_dead = q.gpu_lease_status()["state"]
        r7 = q.gpu_lease_acquire("next_round", "y")
        check("G6 holder_pid 를 주면 그 프로세스가 죽은 임대 = holder_dead → 다른 보유자가 잡는다(살아 있을 땐 held · 양방향)",
              r6["ok"] and st_alive == "held" and st_dead == "holder_dead" and r7["ok"] and r7["reason"] == "acquired", (st_alive, st_dead, r7))
        hist = [json.loads(l) for l in io.open(os.path.join(os.path.dirname(lease), "gpu_lease_history.jsonl"), encoding="utf-8")]
        evs = [h["event"] for h in hist]
        check("G7 임대 이력(gpu_lease_history.jsonl) — 획득 · 해제 · 만료 · 보유자 사망이 남는다",
              {"acquired", "released", "expired", "holder_dead"} <= set(evs), evs)
        q.gpu_lease_release("next_round")
        env = dict(os.environ)
        c1 = subprocess.run([PY, SRC, "lease", "acquire", "--holder", "cli_h", "--purpose", "cli test", "--cap-hours", "2", "--json"],
                            capture_output=True, text=True, env=env)
        c2 = subprocess.run([PY, SRC, "lease", "acquire", "--holder", "cli_x", "--purpose", "cli test", "--json"], capture_output=True, text=True, env=env)
        c3 = subprocess.run([PY, SRC, "lease", "status", "--json"], capture_output=True, text=True, env=env)
        c4 = subprocess.run([PY, SRC, "lease", "release", "--holder", "cli_h", "--json"], capture_output=True, text=True, env=env)
        s3 = json.loads(c3.stdout.strip().splitlines()[-1])
        check("G8 CLI — 획득 rc 0 · 다른 보유자 rc 1 · 상태 JSON(holder · cap 2h) · 해제 rc 0",
              c1.returncode == 0 and c2.returncode == 1 and s3.get("holder") == "cli_h" and s3.get("cap_hours") == 2 and c4.returncode == 0,
              (c1.returncode, c2.returncode, s3.get("holder"), c4.returncode, c1.stderr[-200:]))
        # 셸 대행 잠금 CLI — 소유자 = 넘긴 pid(오래 사는 셸) · 토큰으로만 해제
        sp2 = sleeper(60); kids.append(sp2)
        time.sleep(0.3)
        ldc = os.path.join(tmp, "cli_lock_target.json")
        a1 = subprocess.run([PY, SRC, "lock", "acquire", "--path", ldc, "--owner-pid", str(sp2.pid), "--wait-s", "1"], capture_output=True, text=True)
        tok = a1.stdout.strip()
        a2 = subprocess.run([PY, SRC, "lock", "acquire", "--path", ldc, "--owner-pid", str(os.getpid()), "--wait-s", "0.3"], capture_output=True, text=True)
        a0 = subprocess.run([PY, SRC, "lock", "acquire", "--path", ldc, "--wait-s", "0.3"], capture_output=True, text=True)
        a3 = subprocess.run([PY, SRC, "lock", "release", "--path", ldc, "--token", "wrongtoken"], capture_output=True, text=True)
        a4 = subprocess.run([PY, SRC, "lock", "release", "--path", ldc, "--token", tok], capture_output=True, text=True)
        check("G9 셸 대행 잠금 CLI — 소유자 pid 필수(없으면 rc 2) · 살아 있는 소유자면 남은 rc 1 · 틀린 토큰 해제 거부 · 맞는 토큰 해제",
              a1.returncode == 0 and len(tok) == 16 and a2.returncode == 1 and a0.returncode == 2 and a3.returncode == 1 and a4.returncode == 0,
              (a1.returncode, a2.returncode, a0.returncode, a3.returncode, a4.returncode))
        # 셸 API(qv_lock.sh) — 같은 의미 · 소유자 = 이 셸의 Windows pid
        sh = os.path.join(OPS, "qv_lock.sh").replace("\\", "/")
        script = ('. "%s"\n'
                  'gpu_lease_acquire sh_holder "sh test" 3 >/dev/null; echo "acq=$?"\n'
                  'gpu_lease_acquire other "x" >/dev/null; echo "other=$?"\n'
                  'gpu_lease_status\n'
                  'gpu_lease_release sh_holder >/dev/null; echo "rel=$?"\n'
                  'qv_lock_acquire name:sh_x 5 600 shtest; echo "lk=$? tok=${#QV_LOCK_TOKEN}"\n'
                  'ls "$QVEST_LOCK_DIR"\n'
                  'qv_lock_release name:sh_x; echo "unlk=$?"\n'
                  'ls "$QVEST_LOCK_DIR" | wc -l\n') % sh
        env_sh = dict(os.environ, QVEST_PY=PY.replace("\\", "/"), QVEST_LOCK_DIR=os.path.join(tmp, "sh_locks").replace("\\", "/"))
        rs = subprocess.run([qv_bash(), "-c", script], capture_output=True, text=True, encoding="utf-8", errors="replace", env=env_sh)
        out = rs.stdout.splitlines()
        st_line = next((l for l in out if l.startswith("{")), "{}")
        try:
            st_sh = json.loads(st_line)
        except Exception:
            st_sh = {}
        check("G10 셸 API(qv_lock.sh) — 임대 획득 rc 0 · 다른 보유자 rc 1 · 상태 JSON(held · cap 3h) · 해제 rc 0 · 이름 잠금 획득(토큰 16자) · 해제 뒤 비움",
              "acq=0" in out and "other=1" in out and st_sh.get("state") == "held" and st_sh.get("cap_hours") == 3 and "rel=0" in out
              and "lk=0 tok=16" in out and "sh_x.qvlock" in out and "unlk=0" in out and out[-1].strip() == "0", (out, rs.stderr[-300:]))
    finally:
        for k in kids:
            try:
                k.kill()
            except Exception:
                pass
        for k in ("QVEST_GPU_LEASE", "QVEST_RF_CONFIG"):
            os.environ.pop(k, None)
        shutil.rmtree(tmp, ignore_errors=True)
    n_fail = sum(1 for _, ok in RESULTS if not ok)
    print("== %d checks · %d failed" % (len(RESULTS), n_fail))
    print(json.dumps({"test": "qv_lock", "pass": len(RESULTS) - n_fail, "fail": n_fail, "total": len(RESULTS)}))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
