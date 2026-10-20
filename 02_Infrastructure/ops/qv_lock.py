# -*- coding: utf-8 -*-
"""qv_lock.py — 쓰기 잠금(mkdir + 소유자 pid + stale 판정 + 시간 제한)과 GPU 임대의 단일 정본 (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)

왜: 1계층 처리량 레버(레인 다중 슬롯 · 독립 라운드 동시 운영)는 같은 원장을 여러 프로세스가 동시에 읽고 고치는 상황을 만든다.
  원자적 교체(임시 파일 → os.replace)는 '찢어진 파일'만 막는다 — 두 writer 가 같은 판본을 읽고 각자 고쳐 쓰면 나중 쓴 쪽이
  앞 쪽 갱신을 조용히 지운다(읽기 · 수정 · 쓰기 경합의 갱신 유실 · 2026-08-08 FQ-122 실사고와 같은 형태). 그래서 임계구역을 잠근다.
  또 10-19 레인 정지 사고(GPU 를 넘겨받으려고 끈 레인 스위치를 되켜 줄 외부 감시 프로세스가 죽어 2.6일 정지)를 구조로 막으려고
  GPU 선점을 '스위치 + 감시 프로세스' 대신 **만료 시각을 품은 임대 파일**로 바꾼다 — 만료는 레인 틱이 파일만 보고 스스로 판정한다.

잠금 규약(파이썬 · R(qv_lock.R) · 셸(qv_lock.sh) 공통 — 형식이 같아 언어를 섞어도 서로를 본다):
  <잠금 디렉터리>            mkdir 원자성 = 획득(Git Bash 에 flock 이 없다 · cleaner_claim · shared_registry_io 와 같은 원리)
  <잠금 디렉터리>/owner.json  {"schema":"qv_lock_v1","pid":<Windows pid>,"proc_start":<프로세스 시작 epoch 초|null>,"token":<16진 16자>,
                              "host":..,"acquired_at":..,"acquired_epoch":..,"purpose":..,"lang":"py|R|sh"}
  판정(lock_state) — 먼저 걸리는 것이 이긴다:
    ① 디렉터리 없음 = free
    ② released.json 표식 = stale(released) — 지우기에 실패한 해제(rf_claim.R 선례)
    ③ owner.json 없음: 나이 ≤ NO_OWNER_GRACE_S(30초) = held(만드는 중) · 넘으면 stale(no_owner) — mkdir 과 기록 사이에 죽은 경우
    ④ 소유 pid 사망 = stale(dead_owner) · pid 는 살아 있는데 시작 시각이 기록과 START_TOL_S 넘게 다름 = stale(pid_reused)
       (2026-09-06 절전 뒤 pid 재사용 사고 — rf_claim.R 머리 주석)
    ⑤ 나이 > stale_s(기본 600초) = stale(too_old) — 살아 있지만 매달린 소유자. 원장 임계구역은 1초 미만이라 10분이면 매달림이다.
       빼앗긴 쪽은 쓰기 직전 펜싱(is_mine)에서 멈춘다(LockLost — 부분 쓰기 없음).
    ⑥ 그 밖 = held
  pid 를 판독할 수 없으면 살아 있다고 본다(살아 있는 소유자를 빼앗는 것이 반대 실수보다 나쁘다 — rf_claim.R 원칙).
  회수(reclaim)는 경합하지 않는다: <잠금>.reclaim 을 mkdir 로 잡은 쪽만, 판정 때 본 토큰이 그대로일 때만 <잠금>.dead.* 로 이름을 바꿔 치운다
    (둘이 동시에 stale 로 판정해도 한쪽이 새로 잡은 잠금을 다른 쪽이 지우지 못한다).
  같은 프로세스의 재진입은 깊이를 센다(원장 writer 안에서 저장 함수가 다시 잠금을 부르는 경로).

잠금 위치(lock_dir_for):
  · 이름 잠금(name=) → <QM_ROOT>/.cache/qv_locks/<name>.qvlock (QVEST_LOCK_DIR 가 있으면 그 아래)
  · 파일 잠금(target=) → 대상이 <X>/06_Registry/ 안이면 <X>/.cache/registry_locks/<파일명>.qvlock — 06_Registry 는 OneDrive 동기화
    폴더라 잠금 디렉터리를 두면 충돌 사본이 생길 수 있다(reinforce_ledger.R .dr_claim_path 주석) · 그 밖이면 <대상 폴더>/.qvlocks/<파일명>.qvlock
    (경로 문자열만으로 정한다 — 언어마다 같은 자리를 가리킨다).

GPU 임대(.cache/gpu_lease.json · QVEST_GPU_LEASE 로 덮기) — 서명 고정(원 세션 코어 실행기가 쓴다 · R/셸은 이 파일의 CLI 를 부른다 = 같은 의미):
  gpu_lease_acquire(holder, purpose, cap_hours=None, holder_pid=None) → {"ok", "reason", "lease"}
      reason: acquired | already_held(같은 보유자 · 연장 없음) | held_by_other(ok=False) · cap_hours 기본 = 설정 replication_lane.gpu_lease.default_cap_hours(12)
      · 상한 = max_cap_hours(12 — L1-SPEED-LEVERS-20261020 '상한 12h/라운드' · 근거 P2R05 GPU 추정 ≈8h + 50%) · 넘으면 상한으로 자르고 note 를 남긴다
      holder_pid(선택) = 보유 프로세스의 Windows pid — 주면 그 프로세스가 죽으면 만료 전이라도 풀린다(holder_dead). 짧게 사는 CLI 의 pid 를 넘기지 말 것.
  gpu_lease_release(holder) → {"ok", "reason"}  reason: released | not_held | held_by_other(ok=False)
  gpu_lease_status() → {"state": free|held|expired|holder_dead|unreadable, "holder", "purpose", "started_at", "cap_hours", "expires_at", "remaining_h", ...}
  임대는 레인 GPU 슬롯의 **새 claim** 만 보류시킨다 — 진행 중인 GPU 작업은 끝까지 간다 · CPU 슬롯은 선점하지 않는다.
  만료 판정 = 읽는 쪽(레인 틱)이 started_epoch + cap_hours 로 스스로 한다 · 외부 감시 프로세스 없음. 이력 = .cache/gpu_lease_history.jsonl.

CLI(표준 라이브러리만 — QVEST_PY 가 시스템 파이썬이어도 돈다):
  python qv_lock.py lease acquire --holder H --purpose P [--cap-hours 12] [--holder-pid N] [--json]
  python qv_lock.py lease release --holder H [--json]      |  lease status [--json]  |  lease expire-check [--json]
  python qv_lock.py lock acquire (--path P | --name N) [--owner-pid N] [--wait-s 60] [--stale-s 600] [--purpose ..]   → 토큰 출력
  python qv_lock.py lock release (--path P | --name N) --token T   |  lock state (--path P | --name N) [--stale-s 600]
  python qv_lock.py pid-alive N [--proc-start E]
  종료 코드: 0 = 성공 · 1 = 거부(다른 보유자 · 시간 초과) · 2 = 사용 오류
검사 = 08_Tests/ops/test_qv_lock.py · 08_Tests/ops/test_qv_lock_cross.R(R ↔ 파이썬 상호 판정)
"""
import contextlib
import datetime as dt
import io
import json
import os
import shutil
import socket
import sys
import time

SCHEMA_LOCK = "qv_lock_v1"
SCHEMA_LEASE = "gpu_lease_v1"
DEFAULT_WAIT_S = 60.0            # 원장 임계구역 대기 — 쓰기 1회는 1초 미만(실측 원장 크기 기준) · 60초는 매달린 경쟁자를 보고하는 시간
DEFAULT_STALE_S = 600.0          # 살아 있는 소유자의 상한 — ⑤ 참조
NO_OWNER_GRACE_S = 30.0          # mkdir 와 owner.json 기록 사이 창(밀리초)을 넉넉히 덮는다 — rf_claim.R 의 60초 유예와 같은 취지
RECLAIM_STALE_S = 60.0           # 회수 뮤텍스 자체가 남은 경우(회수 도중 사망)의 상한
START_TOL_S = 2.0                # 시작 시각 비교 허용 — 같은 커널 값(GetProcessTimes · ps::ps_create_time)이라 ms 단위로 같다
LEASE_DEFAULT_CAP_H = 12.0       # L1-SPEED-LEVERS-20261020 note '상한 12h/라운드'(근거 P2R05 GPU ≈8h · paused_note + 50%) — 설정이 없을 때의 값
LEASE_MAX_CAP_H = 12.0           # 같은 결정의 상한 — 설정 replication_lane.gpu_lease.max_cap_hours 가 정본


class LockTimeout(RuntimeError):
    pass


class LockLost(RuntimeError):
    pass


# ── 공용 ──────────────────────────────────────────────────────────────────────
def _root():
    for k in ("QM_ROOT", "CLAUDE_PROJECT_DIR"):
        v = os.environ.get(k, "")
        if v and os.path.isdir(v):
            return v
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _now_iso(t=None):
    return dt.datetime.fromtimestamp(time.time() if t is None else t).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def _token():
    return os.urandom(8).hex()          # 난수 상태(random 모듈)를 건드리지 않는다


def _read_json(p):
    try:
        with io.open(p, "rb") as f:
            return json.loads(f.read().decode("utf-8-sig"))
    except Exception:
        return None


def atomic_write_json(path, obj, lock=None, indent=1):
    """원자적 교체(임시 파일 → os.replace) + (잠금을 주면) 교체 직전 펜싱 — 잠금을 잃었으면 쓰지 않고 LockLost.
    Windows 일시 점유(백신 · 동기화)는 짧게 재시도한다. 실패하면 임시 파일을 남기지 않는다."""
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, ".%s.%d.%s.tmp" % (os.path.basename(path), os.getpid(), _token()[:6]))
    with io.open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=indent)
        f.write("\n")
    try:
        if lock is not None:
            lock.assert_mine("원자적 교체")
        for k in range(5):
            try:
                os.replace(tmp, path)
                return
            except PermissionError:
                time.sleep(0.05 * (k + 1))
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def _atomic_json(p, obj):
    atomic_write_json(p, obj)


def _mtime(p):
    try:
        return os.path.getmtime(p)
    except OSError:
        return time.time()


# ── 프로세스 생존 · 시작 시각 ─────────────────────────────────────────────────
if os.name == "nt":
    import ctypes
    from ctypes import wintypes

    _k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    _k32.OpenProcess.restype = wintypes.HANDLE
    _k32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    _k32.GetExitCodeProcess.restype = wintypes.BOOL
    _k32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(ctypes.c_ulonglong)] * 4
    _k32.GetProcessTimes.restype = wintypes.BOOL
    _k32.CloseHandle.argtypes = [wintypes.HANDLE]
    _k32.CloseHandle.restype = wintypes.BOOL
    _QUERY = 0x1000                      # PROCESS_QUERY_LIMITED_INFORMATION
    _STILL_ACTIVE = 259

    def _open(pid):
        return _k32.OpenProcess(_QUERY, False, int(pid))

    def pid_alive(pid):
        """Windows pid 생존 — 판독 불가(권한 거부 등)는 살아 있다로 본다."""
        try:
            pid = int(pid)
        except (TypeError, ValueError):
            return True
        if pid <= 0:
            return True
        h = _open(pid)
        if not h:
            err = ctypes.get_last_error()
            return err == 5              # ERROR_ACCESS_DENIED = 있다 · ERROR_INVALID_PARAMETER(87) = 없다
        try:
            code = wintypes.DWORD()
            if _k32.GetExitCodeProcess(h, ctypes.byref(code)):
                return code.value == _STILL_ACTIVE
            return True
        finally:
            _k32.CloseHandle(h)

    def proc_start(pid):
        """프로세스 시작 시각(epoch 초) — 모르면 None."""
        try:
            pid = int(pid)
        except (TypeError, ValueError):
            return None
        if pid <= 0:
            return None
        h = _open(pid)
        if not h:
            return None
        try:
            c, e, k, u = (ctypes.c_ulonglong() for _ in range(4))
            if not _k32.GetProcessTimes(h, ctypes.byref(c), ctypes.byref(e), ctypes.byref(k), ctypes.byref(u)):
                return None
            return (c.value - 116444736000000000) / 1e7
        finally:
            _k32.CloseHandle(h)
else:                                    # pragma: no cover — 운영은 Windows
    def pid_alive(pid):
        try:
            pid = int(pid)
        except (TypeError, ValueError):
            return True
        if pid <= 0:
            return True
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def proc_start(pid):
        try:
            with open("/proc/%d/stat" % int(pid)) as f:
                st = f.read()
            ticks = float(st.rsplit(")", 1)[1].split()[19])
            with open("/proc/stat") as f:
                bt = next(float(l.split()[1]) for l in f if l.startswith("btime "))
            return bt + ticks / os.sysconf("SC_CLK_TCK")
        except Exception:
            return None


def owner_alive(pid, recorded_start=None):
    """pid 생존 + (둘 다 알면) 시작 시각 일치 — 다르면 재사용된 pid 다."""
    if not pid_alive(pid):
        return False, "dead_owner"
    if recorded_start is None:
        return True, "alive"
    cur = proc_start(pid)
    try:
        if cur is not None and abs(float(cur) - float(recorded_start)) > START_TOL_S:
            return False, "pid_reused"
    except (TypeError, ValueError):
        pass
    return True, "alive"


# ── 잠금 위치 ─────────────────────────────────────────────────────────────────
def lock_dir_for(target=None, name=None, root=None):
    base_env = os.environ.get("QVEST_LOCK_DIR", "")
    if name:
        base = base_env or os.path.join(root or _root(), ".cache", "qv_locks")
        return os.path.join(base, name + ".qvlock")
    if not target:
        raise ValueError("lock_dir_for: target 또는 name 필요")
    t = os.path.abspath(target)
    if base_env:
        return os.path.join(base_env, os.path.basename(t) + ".qvlock")
    d = os.path.dirname(t)
    if os.path.basename(d).lower() == "06_registry":
        return os.path.join(os.path.dirname(d), ".cache", "registry_locks", os.path.basename(t) + ".qvlock")
    return os.path.join(d, ".qvlocks", os.path.basename(t) + ".qvlock")


# ── 잠금 판정 · 획득 · 해제 ───────────────────────────────────────────────────
def _read_owner(lockdir):
    o = _read_json(os.path.join(lockdir, "owner.json"))
    return o if isinstance(o, dict) and o.get("token") else None


def lock_state(lockdir, stale_s=DEFAULT_STALE_S, now=None):
    now = time.time() if now is None else now
    if not os.path.isdir(lockdir):
        return {"state": "free", "why": "absent"}
    if os.path.exists(os.path.join(lockdir, "released.json")):
        return {"state": "stale", "why": "released", "owner": _read_owner(lockdir)}
    o = _read_owner(lockdir)
    if o is None:
        age = now - _mtime(lockdir)
        if age > NO_OWNER_GRACE_S:
            return {"state": "stale", "why": "no_owner", "age_s": age, "owner": None}
        return {"state": "held", "why": "no_owner_yet", "age_s": age, "owner": None}
    try:
        age = now - float(o.get("acquired_epoch"))
    except (TypeError, ValueError):
        age = now - _mtime(lockdir)
    alive, why = owner_alive(o.get("pid"), o.get("proc_start"))
    if not alive:
        return {"state": "stale", "why": why, "age_s": age, "owner": o}
    if stale_s and stale_s > 0 and age > stale_s:
        return {"state": "stale", "why": "too_old", "age_s": age, "owner": o}
    return {"state": "held", "why": "alive", "age_s": age, "owner": o}


def _rmtree_quiet(p):
    shutil.rmtree(p, ignore_errors=True)


def _reclaim(lockdir, judged):
    """판정 때 본 토큰(없으면 '소유자 없음')이 그대로일 때만 치운다. 성공 = True."""
    rc = lockdir + ".reclaim"
    try:
        os.mkdir(rc)
    except FileExistsError:
        if time.time() - _mtime(rc) > RECLAIM_STALE_S:
            _rmtree_quiet(rc)
        return False
    except OSError:
        return False
    try:
        if not os.path.isdir(lockdir):
            return True
        cur = _read_owner(lockdir)
        jt = ((judged or {}).get("owner") or {}).get("token")
        if (cur or {}).get("token") != jt:
            return False                 # 판정 뒤 바뀌었다(새 소유자) — 건드리지 않는다
        # 토큰이 같으면 판정 대상과 같은 소유자다 — 죽은 pid 는 되살아나지 않고(재사용은 시작 시각이 가른다) 나이 · 해제 표식도 그대로다
        tomb = "%s.dead.%d.%s" % (lockdir, os.getpid(), _token()[:8])
        for k in range(5):
            try:
                os.rename(lockdir, tomb)
                break
            except FileNotFoundError:
                return True
            except OSError:
                time.sleep(0.05 * (k + 1))
        else:
            return False
        _rmtree_quiet(tomb)
        return True
    finally:
        try:
            os.rmdir(rc)
        except OSError:
            pass


class LockHandle(object):
    __slots__ = ("lockdir", "token", "depth", "owner_pid", "purpose")

    def __init__(self, lockdir, token, owner_pid, purpose):
        self.lockdir, self.token, self.depth, self.owner_pid, self.purpose = lockdir, token, 1, owner_pid, purpose

    def is_mine(self):
        o = _read_owner(self.lockdir)
        return bool(o) and o.get("token") == self.token and not os.path.exists(os.path.join(self.lockdir, "released.json"))

    def assert_mine(self, what="쓰기"):
        if not self.is_mine():
            raise LockLost("[qv_lock] 잠금을 잃었다(%s) — %s 를 하지 않는다: %s" % (self.purpose or "?", what, self.lockdir))

    def __repr__(self):
        return "LockHandle(%r, depth=%d)" % (self.lockdir, self.depth)


_HELD = {}


def _key(lockdir):
    return os.path.normcase(os.path.abspath(lockdir))


def acquire(lockdir, wait_s=DEFAULT_WAIT_S, stale_s=DEFAULT_STALE_S, purpose="", owner_pid=None, lang="py"):
    """잠금 획득 — 시간 안에 못 잡으면 LockTimeout. owner_pid 를 주면 그 pid 를 소유자로 적는다(셸 대행 · 재진입 표 미사용)."""
    k = _key(lockdir)
    if owner_pid is None and k in _HELD:
        h = _HELD[k]
        if h.is_mine():
            h.depth += 1
            return h
        _HELD.pop(k, None)
    parent = os.path.dirname(lockdir)
    if parent:
        os.makedirs(parent, exist_ok=True)
    deadline = time.time() + max(0.0, float(wait_s))
    delay = 0.05
    last = None
    while True:
        try:
            os.mkdir(lockdir)
        except (FileExistsError, PermissionError):
            st = lock_state(lockdir, stale_s)
            last = st
            if st["state"] == "free":
                continue
            if st["state"] == "stale" and _reclaim(lockdir, st):
                continue
            if time.time() >= deadline:
                o = st.get("owner") or {}
                raise LockTimeout("[qv_lock] 잠금 획득 실패(%.0f초 대기): %s · 상태 %s/%s · 소유 pid %s · 용도 %s" % (
                    float(wait_s), lockdir, st.get("state"), st.get("why"), o.get("pid"), o.get("purpose")))
            time.sleep(delay)
            delay = min(delay * 1.6, 0.5)
            continue
        pid = int(owner_pid) if owner_pid is not None else os.getpid()
        rec = {"schema": SCHEMA_LOCK, "pid": pid, "proc_start": proc_start(pid), "token": _token(),
               "host": socket.gethostname(), "acquired_at": _now_iso(), "acquired_epoch": time.time(),
               "purpose": purpose or "", "lang": lang}
        try:
            _atomic_json(os.path.join(lockdir, "owner.json"), rec)
        except Exception:
            _rmtree_quiet(lockdir)
            raise
        h = LockHandle(lockdir, rec["token"], pid, purpose)
        if owner_pid is None:
            _HELD[k] = h
        return h


def release(h):
    """해제 — 내 토큰일 때만 치운다. 반환 = 'released' | 'nested' | 'lost'(남이 회수함) | 'marker_left'."""
    if h is None:
        return "lost"
    if h.depth > 1:
        h.depth -= 1
        return "nested"
    _HELD.pop(_key(h.lockdir), None)
    o = _read_owner(h.lockdir)
    if not o or o.get("token") != h.token:
        return "lost"
    tomb = "%s.dead.%d.%s" % (h.lockdir, os.getpid(), _token()[:8])
    for k in range(5):
        try:
            os.rename(h.lockdir, tomb)
            _rmtree_quiet(tomb)
            return "released"
        except FileNotFoundError:
            return "lost"
        except OSError:
            time.sleep(0.05 * (k + 1))
    try:                                 # 지우지 못하면 해제 표식(다음 획득자가 즉시 회수 — rf_claim.R 선례)
        _atomic_json(os.path.join(h.lockdir, "released.json"), {"released_at": _now_iso(), "by_pid": os.getpid(), "token": h.token})
        return "marker_left"
    except Exception:
        return "lost"


def release_by_token(lockdir, token):
    o = _read_owner(lockdir)
    if not o or o.get("token") != token:
        return "lost"
    h = LockHandle(lockdir, token, o.get("pid"), o.get("purpose"))
    return release(h)


@contextlib.contextmanager
def write_lock(target=None, name=None, wait_s=DEFAULT_WAIT_S, stale_s=DEFAULT_STALE_S, purpose="", root=None):
    """with write_lock(path) as h: 읽기 → 고치기 → atomic_write_json(path, obj, lock=h)"""
    h = acquire(lock_dir_for(target=target, name=name, root=root), wait_s=wait_s, stale_s=stale_s,
                purpose=purpose or (os.path.basename(target) if target else name))
    try:
        yield h
    finally:
        release(h)


# ── GPU 임대─────────────────────────────────────────────────────────────────
def gpu_lease_path(root=None):
    return os.environ.get("QVEST_GPU_LEASE") or os.path.join(root or _root(), ".cache", "gpu_lease.json")


def _lease_history_path(lease_p):
    return os.path.join(os.path.dirname(lease_p) or ".", "gpu_lease_history.jsonl")


def _lease_cfg(root=None):
    cp = os.environ.get("QVEST_RF_CONFIG") or os.path.join(root or _root(), "06_Registry", "reinforce_auto_config.json")
    c = _read_json(cp) or {}
    g = ((c.get("replication_lane") or {}).get("gpu_lease") or {}) if isinstance(c, dict) else {}
    def num(v, d):
        try:
            v = float(v)
            return v if v > 0 else d
        except (TypeError, ValueError):
            return d
    mx = num(g.get("max_cap_hours"), LEASE_MAX_CAP_H)
    df = min(num(g.get("default_cap_hours"), LEASE_DEFAULT_CAP_H), mx)
    return {"default_cap_hours": df, "max_cap_hours": mx}


def _history(lease_p, event, lease, **kw):
    rec = {"ts": _now_iso(), "event": event, "holder": (lease or {}).get("holder"), "purpose": (lease or {}).get("purpose"),
           "started_at": (lease or {}).get("started_at"), "cap_hours": (lease or {}).get("cap_hours")}
    rec.update(kw)
    try:
        with io.open(_lease_history_path(lease_p), "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass


def _lease_eval(lease, now, path):
    """임대 파일 내용 → 상태. 파일이 없으면 free · 못 읽으면 unreadable(GPU 슬롯은 보류 쪽 · 상한 경과면 expired)."""
    if lease is None:
        return {"state": "free", "path": path}
    if not isinstance(lease, dict) or lease.get("schema") != SCHEMA_LEASE:
        age_h = (now - _mtime(path)) / 3600.0
        st = "expired" if age_h > LEASE_MAX_CAP_H else "unreadable"
        return {"state": st, "path": path, "age_h": round(age_h, 3), "why": "schema_or_parse"}
    try:
        started = float(lease.get("started_epoch"))
        cap = float(lease.get("cap_hours"))
    except (TypeError, ValueError):
        age_h = (now - _mtime(path)) / 3600.0
        return {"state": "expired" if age_h > LEASE_MAX_CAP_H else "unreadable", "path": path, "why": "fields"}
    exp = started + cap * 3600.0
    out = dict(lease)
    out.update({"path": path, "expires_epoch": exp, "expires_at": _now_iso(exp),
                "remaining_h": round((exp - now) / 3600.0, 3), "elapsed_h": round((now - started) / 3600.0, 3)})
    if now >= exp:
        out["state"] = "expired"
        return out
    hp = lease.get("holder_pid")
    if hp not in (None, "", 0):
        alive, why = owner_alive(hp, lease.get("holder_proc_start"))
        if not alive:
            out["state"] = "holder_dead"
            out["why"] = why
            return out
    out["state"] = "held"
    return out


def gpu_lease_status(root=None, now=None):
    p = gpu_lease_path(root)
    now = time.time() if now is None else now
    if not os.path.exists(p):
        return {"state": "free", "path": p}
    raw = _read_json(p)
    if raw is None:
        return _lease_eval("<unparsable>", now, p)
    return _lease_eval(raw, now, p)


def gpu_lease_acquire(holder, purpose, cap_hours=None, holder_pid=None, root=None):
    holder = (holder or "").strip()
    purpose = (purpose or "").strip()
    if not holder or not purpose:
        raise ValueError("gpu_lease_acquire: holder · purpose 필수")
    cfg = _lease_cfg(root)
    note = ""
    cap = cfg["default_cap_hours"] if cap_hours in (None, "") else float(cap_hours)
    if not (cap > 0):
        raise ValueError("gpu_lease_acquire: cap_hours > 0")
    if cap > cfg["max_cap_hours"]:
        note = "cap_hours %.3g → 상한 %.3g 로 자름(설정 replication_lane.gpu_lease.max_cap_hours · L1-SPEED-LEVERS-20261020)" % (cap, cfg["max_cap_hours"])
        cap = cfg["max_cap_hours"]
    p = gpu_lease_path(root)
    with write_lock(target=p, wait_s=30, stale_s=120, purpose="gpu_lease"):
        st = gpu_lease_status(root)
        if st["state"] == "held":
            if st.get("holder") == holder:
                return {"ok": True, "reason": "already_held", "lease": st, "note": "같은 보유자 — 연장하지 않는다(상한은 시작 시각 기준)"}
            return {"ok": False, "reason": "held_by_other", "lease": st}
        if st["state"] == "unreadable":
            return {"ok": False, "reason": "lease_unreadable", "lease": st}
        if st["state"] in ("expired", "holder_dead"):
            _history(p, st["state"], st, by=holder)
        now = time.time()
        hp = None
        if holder_pid not in (None, "", 0, "0"):
            hp = int(holder_pid)
        lease = {"schema": SCHEMA_LEASE, "holder": holder, "purpose": purpose, "started_at": _now_iso(now), "started_epoch": now,
                 "cap_hours": cap, "cap_basis": "L1-SPEED-LEVERS-20261020 — 상한 12h/라운드(P2R05 GPU 추정 ≈8h + 50%) · 설정 replication_lane.gpu_lease",
                 "holder_pid": hp, "holder_proc_start": proc_start(hp) if hp else None, "host": socket.gethostname()}
        if note:
            lease["note"] = note
        _atomic_json(p, lease)
        _history(p, "acquired", lease)
        out = _lease_eval(lease, time.time(), p)
        return {"ok": True, "reason": "acquired", "lease": out, "note": note}


def gpu_lease_release(holder, root=None):
    holder = (holder or "").strip()
    p = gpu_lease_path(root)
    with write_lock(target=p, wait_s=30, stale_s=120, purpose="gpu_lease"):
        if not os.path.exists(p):
            return {"ok": True, "reason": "not_held"}
        raw = _read_json(p)
        if isinstance(raw, dict) and raw.get("holder") not in (None, holder):
            return {"ok": False, "reason": "held_by_other", "lease": gpu_lease_status(root)}
        _history(p, "released", raw if isinstance(raw, dict) else None, by=holder)
        os.remove(p)
        return {"ok": True, "reason": "released"}


def gpu_lease_expire_check(root=None):
    """레인 틱 전용 — 만료 · 보유자 사망이면 이력에 남기고 파일을 치운다(외부 감시 없음). 반환 = 판정 뒤 상태."""
    p = gpu_lease_path(root)
    st = gpu_lease_status(root)
    if st["state"] not in ("expired", "holder_dead"):
        return st
    with write_lock(target=p, wait_s=30, stale_s=120, purpose="gpu_lease"):
        st2 = gpu_lease_status(root)
        if st2["state"] in ("expired", "holder_dead"):
            _history(p, st2["state"], st2, by="lane_tick")
            try:
                os.remove(p)
            except OSError:
                pass
            st2 = dict(st2)
            st2["cleared"] = True
        return st2


# ── CLI ──────────────────────────────────────────────────────────────────────
def _cli(argv):
    import argparse
    for _s in (sys.stdout, sys.stderr):   # 셸 · R 이 -X utf8 없이 부른다 — 콘솔 코드 페이지에 없는 글자로 죽지 않게
        try:
            _s.reconfigure(errors="replace")
        except Exception:
            pass
    ap = argparse.ArgumentParser(prog="qv_lock")
    sp = ap.add_subparsers(dest="cmd", required=True)
    le = sp.add_parser("lease")
    le.add_argument("op", choices=["acquire", "release", "status", "expire-check"])
    le.add_argument("--holder"); le.add_argument("--purpose"); le.add_argument("--cap-hours", type=float)
    le.add_argument("--holder-pid", type=int); le.add_argument("--json", action="store_true")
    lk = sp.add_parser("lock")
    lk.add_argument("op", choices=["acquire", "release", "state"])
    lk.add_argument("--path"); lk.add_argument("--name"); lk.add_argument("--token"); lk.add_argument("--owner-pid", type=int)
    lk.add_argument("--wait-s", type=float, default=DEFAULT_WAIT_S); lk.add_argument("--stale-s", type=float, default=DEFAULT_STALE_S)
    lk.add_argument("--purpose", default="")
    pa = sp.add_parser("pid-alive"); pa.add_argument("pid", type=int); pa.add_argument("--proc-start", type=float)
    a = ap.parse_args(argv)
    if a.cmd == "pid-alive":
        alive, why = owner_alive(a.pid, a.proc_start)
        print("%s %s" % ("alive" if alive else "dead", why))
        return 0 if alive else 1
    if a.cmd == "lease":
        try:
            if a.op == "acquire":
                r = gpu_lease_acquire(a.holder, a.purpose, a.cap_hours, a.holder_pid)
            elif a.op == "release":
                if not a.holder:
                    print("holder 필수", file=sys.stderr)
                    return 2
                r = gpu_lease_release(a.holder)
            elif a.op == "status":
                r = gpu_lease_status()
            else:
                r = gpu_lease_expire_check()
        except (ValueError, LockTimeout) as e:
            print(json.dumps({"ok": False, "reason": "error", "error": str(e)}, ensure_ascii=False) if a.json else str(e))
            return 2 if isinstance(e, ValueError) else 1
        if a.json:
            print(json.dumps(r, ensure_ascii=False))
        else:
            print(" ".join("%s=%s" % (k, v) for k, v in r.items() if k != "lease"))
        if a.op in ("acquire", "release"):
            return 0 if r.get("ok") else 1
        return 0
    if not (a.path or a.name):
        print("--path 또는 --name 필요", file=sys.stderr)
        return 2
    ld = lock_dir_for(target=a.path, name=a.name)
    if a.op == "state":
        st = lock_state(ld, a.stale_s)
        print(json.dumps({k: v for k, v in st.items()}, ensure_ascii=False))
        return 0
    if a.op == "acquire":
        # 소유자는 오래 사는 호출자(셸 스크립트)의 Windows pid 여야 한다 — 이 CLI 는 곧 끝나고, 명령 치환의 부모는 곧 끝나는 서브셸이다
        if not a.owner_pid:
            print("--owner-pid 필요(셸: $(cat /proc/$$/winpid))", file=sys.stderr)
            return 2
        try:
            h = acquire(ld, wait_s=a.wait_s, stale_s=a.stale_s, purpose=a.purpose, owner_pid=a.owner_pid, lang="sh")
        except LockTimeout as e:
            print(str(e), file=sys.stderr)
            return 1
        print(h.token)
        return 0
    if not a.token:
        print("--token 필요", file=sys.stderr)
        return 2
    r = release_by_token(ld, a.token)
    print(r)
    return 0 if r in ("released", "marker_left") else 1


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
