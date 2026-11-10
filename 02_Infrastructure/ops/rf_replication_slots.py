#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rf_replication_slots.py — 충실구현 레인 다중 슬롯 · GPU 임대 존중 · 논문 잠금 (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)

왜: 레인은 claim 1개(.cache/rf_replication.claim)라 논문을 1편씩 처리했다(레인 2.6일 정지 · GPU 0% 유휴가 같이 보였다).
  슬롯별 claim(CPU N + GPU 1)으로 처리량을 2~4배로 올리되, 과거 동시성 사고 영역(09-13 생존 회수 → 같은 논문 1·2·3판 동시 실행 ·
  09-01 고아 claim 13시간 정지)을 구조로 막는다:
    · 슬롯 claim = .cache/rf_replication.claim.<slot>/ (구판과 같은 owner · owner_win 형식 + owner_start · paper · slot)
      회수 · 생존 판정 · claim_live_long 은 슬롯마다 따로 한다(구판 규칙 그대로 — 소유자 사망 = 즉시 회수 · 생존 소유자는 나이로 회수하지 않는다(10-17)).
    · 같은 논문 중복 금지 = 논문 잠금(.cache/rf_replication.papers/<slug>.paper/ · mkdir 원자성) + 발행 잠금(qv_lock 이름 잠금 rf_replication.issue —
      논문 잠금의 모든 변경은 이 안에서만). 논문 잠금은 프로세스가 아니라 **슬롯 요청**이 쥔다 — 그 슬롯 요청이 그 논문을 바쁜 상태로 들고 있을 때만 산다.
    · torch/GPU 논문은 GPU 슬롯에만(rf_compute_class.py — 명시 > 구현 의존성 > 큐 메타 > cpu). CPU 슬롯이 측정 직전에 GPU 엔진을 발견하면
      GPU 인계함(06_Registry/replication_slots/_gpu_inbox/)으로 넘기고 GPU 슬롯이 검증기만 이어 돈다(failure=gpu_handoff).
    · GPU 임대(.cache/gpu_lease.json · qv_lock.py)가 살아 있으면 GPU 슬롯은 새 claim 을 보류한다 — 진행 중인 것은 끝까지 · CPU 슬롯은 선점하지 않는다.
      만료는 이 틱이 스스로 판정한다(외부 감시 프로세스 없음).
  디스패처(tick)는 빨리 끝난다 — 작업자는 셸(rf_replication_auto.sh)이 슬롯마다 분리 실행으로 띄운다(LAUNCH 줄). 예약 작업이 IgnoreNew 라
  틱이 작업자를 기다리면 다른 슬롯을 채울 수 없다.

경로(검사 격리용 환경변수 · 운영은 기본값):
  설정 QVEST_RF_CONFIG(06_Registry/reinforce_auto_config.json::replication_lane.slots = {"cpu":2,"gpu":1} — 없으면 구판 단일 슬롯 · 이 파일 미사용)
  상태 QVEST_RP_STATE_DIR(.cache) — 슬롯 claim · 논문 잠금 · 이름 잠금 · 임대(QVEST_GPU_LEASE 우선)
  요청 QVEST_RP_SLOT_DIR(06_Registry/replication_slots) — <slot>/replication_request.json(이름에 replication_request.json 이 들어가
       청정 레인 가드(arm_gen_read_guard 두 정규식)가 그대로 막는다) · _gpu_inbox/
  저널 QVEST_RP_JLOG(.cache/reinforce_auto_log.jsonl) · 구판 요청 QVEST_RP_REQUEST · 구판 claim QVEST_RP_CLAIM · 작업 디렉터리 QVEST_RP_WDIR_BASE
  검사 전용 이음매: QVEST_RP_CANDIDATES_JSON(후보 목록 대체) · QVEST_RP_ISSUE_CMD(next_replication.R 대체 실행 파일)

명령:
  tick [--no-launch]           디스패처 1회 — 회수 · 논문 잠금 청소 · 구판 요청 인수 · 인계함 → GPU 슬롯 · 빈 슬롯 발행 · 'LAUNCH <slot>' 출력
  issue --slot S               슬롯 S 에 다음 논문(인계함(GPU) → 재구현 대기열 → 큐 · 같은 등급만 · 논문 잠금 원자 획득 → next_replication.R --only-key)
  paper-lock --slot S          작업자 펜싱 — 이 슬롯이 요청의 논문을 쥐었는가(없으면 잡는다 · 다른 슬롯이 살아서 쥐었으면 요청을 duplicate_held_elsewhere 로 닫고 rc 3)
  classify --req P [--wdir W]  'gpu <근거>' | 'cpu <근거>'
  handoff --slot S --reason R [--verify-only]   CPU 슬롯 → GPU 인계함
  claim-stamp --claim D        슬롯 claim 에 소유자 시작 시각(owner_start) 기록 — pid 재사용 판별(09-06 사고)
  status [--line] [--json]     슬롯 상태
  burn [--days 7] [--json]     일 소진량(레인 저널 기반 — 구현 에이전트 수 · 분 · 감사 에이전트 수 · 한도 사건)
  config enable --cpu 2 --gpu 1 | config disable | config show     배포 · 되돌리기(설정 원자적 편집)
  config not-before <ISO-8601(시간대 필수)|clear>   시작 관문(레인이 그 시각 전에는 아무 일도 안 한다 · 11-10 REPLICATION-LANE-RESTART-SLOTS-20261110)
    ★1슬롯(동시 실행 1) = config enable --cpu 0 --gpu 1 — GPU 슬롯 하나가 모든 논문을 받는다(CPU 슬롯이 없으면 무엇이든 · 인계함 소비 · GPU 임대 존중).
      --cpu 1 --gpu 0 은 인계함(_gpu_inbox)을 영영 비우지 않고 torch 논문이 임대를 보지 않은 채 GPU 를 쓴다(쓰지 말 것).
검사 = 08_Tests/ops/test_replication_slots.py · 08_Tests/ops/test_replication_slots_lane.sh
"""
import argparse
import datetime as dt
import glob
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import qv_lock                     # noqa: E402
import rf_compute_class as cc      # noqa: E402

SCHEMA_PAPER_LOCK = "rf_paper_lock_v1"
BUSY = ("pending", "in_progress", "failed_needs_session")      # next_replication.R §1 과 같은 집합(이 상태면 덮어쓰지 않는다)
CHAIN_FRESH_S = 600            # 재구현 연쇄(exec) 창 표식의 유효 시간 — 연쇄 재진입은 수 초(관문 몇 개) · 넉넉히 10분
NO_OWNER_DEAD_S = 120          # 소유자 표식 없는 슬롯 claim — 작업자는 mkdir 직후 표식을 쓴다(밀리초) · 2분이면 그 사이 죽은 것
PAPER_LOCK_NO_OWNER_S = 30     # owner.json 없는 논문 잠금(발행 잠금 안에서만 만든다 — 30초면 만들다 죽은 것)
MAX_CPU_SLOTS = 8              # 24코어 · 31.7GB · 작업자 1개 = RAWDATA 적재 R 1개(실측 수 GB) — 설정 실수 방지선(배포 기본 2)
ISSUE_TRIES = 5                # 한 슬롯 발행 시도 상한(후보가 잠금 경합 · 발행 실패로 빠질 때) — 유한 재시도의 최소 표현


def _now():
    return time.time()


def _iso(t=None):
    return qv_lock._now_iso(t)


def _rd(p):
    return qv_lock._read_json(p)


def _rmtree_force(p):
    """폴더를 지운다 — 반환 = 지워졌는가.
    ★2026-11-06 실측: .cache 가 OneDrive 안 실제 폴더가 된 뒤(11-03) 동기화된 폴더는 수 초 안에 읽기 전용(R) 속성을 받는다.
      rmtree(ignore_errors=True) 는 안 파일만 지우고 R 폴더는 못 지운 채 조용히 끝난다 — 빈 claim 폴더가 '방금 만든 새 claim'
      (mtime 갱신)으로 남아 작업자가 in_progress 를 되살리지 않았다(11-01 cpu2 6시간 no_pending_request 와 같은 모양).
      R 을 풀고(os.chmod S_IWRITE) 한 번 더 지운다."""
    shutil.rmtree(p, ignore_errors=True)
    if not os.path.isdir(p):
        return True
    for dp, _dns, fns in os.walk(p, topdown=False):
        for n in fns:
            try:
                os.chmod(os.path.join(dp, n), stat.S_IWRITE)
            except OSError:
                pass
        try:
            os.chmod(dp, stat.S_IWRITE)
        except OSError:
            pass
    shutil.rmtree(p, ignore_errors=True)
    return not os.path.isdir(p)


class Lane(object):
    def __init__(self, root=None):
        e = os.environ.get
        self.root = (root or e("QM_ROOT") or os.path.dirname(os.path.dirname(HERE))).replace("\\", "/")
        r = self.root
        self.cfg_path = e("QVEST_RF_CONFIG") or os.path.join(r, "06_Registry", "reinforce_auto_config.json")
        self.variants_cfg = e("QVEST_RP_VARIANTS_CFG") or os.path.join(r, "06_Registry", "rf_replication_variants.json")
        self.state_dir = e("QVEST_RP_STATE_DIR") or os.path.join(r, ".cache")
        self.slot_dir = e("QVEST_RP_SLOT_DIR") or os.path.join(r, "06_Registry", "replication_slots")
        self.jlog_path = e("QVEST_RP_JLOG") or os.path.join(r, ".cache", "reinforce_auto_log.jsonl")
        self.legacy_req = e("QVEST_RP_REQUEST") or os.path.join(r, "06_Registry", "replication_request.json")
        self.legacy_claim = e("QVEST_RP_CLAIM") or os.path.join(r, ".cache", "rf_replication.claim")
        self.wdir_base = e("QVEST_RP_WDIR_BASE") or os.path.join(r, "04_Research", "strategies")
        self.cfg = _rd(self.cfg_path) or {}
        self.rl = (self.cfg.get("replication_lane") or {}) if isinstance(self.cfg, dict) else {}

    # ── 설정 ──────────────────────────────────────────────────────────────────
    def slot_counts(self):
        s = self.rl.get("slots")
        if not isinstance(s, dict):
            return None
        try:
            ncpu = int(s.get("cpu", 0) or 0)
            ngpu = int(s.get("gpu", 0) or 0)
        except (TypeError, ValueError):
            return None
        ncpu = max(0, min(ncpu, MAX_CPU_SLOTS))
        ngpu = 1 if ngpu >= 1 else 0           # GPU 1장(RTX 4080 Laptop) — 둘 이상은 같은 GPU 를 나눠 쓴다(VRAM 넘침)
        if ncpu + ngpu == 0:
            return None
        return ncpu, ngpu

    def slot_names(self):
        c = self.slot_counts()
        if not c:
            return []
        return ["cpu%d" % i for i in range(1, c[0] + 1)] + (["gpu1"] if c[1] else [])

    @staticmethod
    def slot_class(slot):
        return "gpu" if str(slot).startswith("gpu") else "cpu"

    def has_class(self, cls):
        return any(self.slot_class(s) == cls for s in self.slot_names())

    def accepts(self, slot, paper_cls):
        """GPU 슬롯 = GPU 논문(CPU 슬롯이 없으면 무엇이든) · CPU 슬롯 = CPU 논문(GPU 슬롯이 없으면 무엇이든)."""
        sc = self.slot_class(slot)
        if sc == paper_cls:
            return True
        return not self.has_class(paper_cls)

    def claim_stale_h(self):
        try:
            v = float(self.cfg.get("claim_stale_hours", 6))
            return v if v >= 1 else 6.0
        except (TypeError, ValueError):
            return 6.0

    def live_reclaim(self):
        v = _rd(self.variants_cfg) or {}
        return ((v.get("compute") or {}).get("live_claim_reclaim") is True) if isinstance(v, dict) else False

    # ── 경로 ──────────────────────────────────────────────────────────────────
    def req_path(self, slot):
        return os.path.join(self.slot_dir, slot, "replication_request.json")

    def claim_path(self, slot):
        return os.path.join(self.state_dir, "rf_replication.claim.%s" % slot)

    def chain_path(self, slot):
        return self.claim_path(slot) + ".chain"

    @property
    def papers_dir(self):
        return os.path.join(self.state_dir, "rf_replication.papers")

    @property
    def inbox_dir(self):
        return os.path.join(self.slot_dir, "_gpu_inbox")

    def name_lock(self, name):
        return os.path.join(self.state_dir, "qv_locks", name + ".qvlock")

    # ── 저널 ──────────────────────────────────────────────────────────────────
    def jl(self, event, **kw):
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "event": event, "src": "replication_slots"}
        rec.update({k: ("" if v is None else str(v)) for k, v in kw.items()})
        try:
            os.makedirs(os.path.dirname(self.jlog_path), exist_ok=True)
            with io.open(self.jlog_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        except Exception:
            pass
        try:
            sys.stderr.write("[rp_auto] %s %s\n" % (event, " ".join("%s=%s" % kv for kv in kw.items())))
        except Exception:
            pass

    # ── 요청 ──────────────────────────────────────────────────────────────────
    @staticmethod
    def req_key(d):
        return str(((d or {}).get("paper") or {}).get("paper_key") or "") if isinstance(d, dict) else ""

    @staticmethod
    def req_status(d):
        return str((d or {}).get("status") or "") if isinstance(d, dict) else ""

    def read_req(self, slot):
        return _rd(self.req_path(slot))

    def write_req(self, path, d):
        qv_lock._atomic_json(path, d)

    def ensure_slot_files(self):
        for s in self.slot_names():
            p = self.req_path(s)
            if not os.path.exists(p):
                self.write_req(p, {"status": "idle", "slot": s, "created_at": _iso(),
                                   "note": "슬롯 요청 자리 — 디스패처(rf_replication_slots.py tick)가 다음 논문을 발행한다"})

    def classify_req(self, d, wdir=None):
        return cc.classify_request(d or {}, self.wdir_base, self.cfg, wdir=wdir)

    # ── 슬롯 claim(구판 형식) ─────────────────────────────────────────────────
    def claim_info(self, cdir):
        if not os.path.isdir(cdir):
            return {"state": "free"}
        age_s = _now() - qv_lock._mtime(cdir)

        def _rdint(n):
            try:
                with io.open(os.path.join(cdir, n), "r", encoding="utf-8") as f:
                    return int(f.read().strip().split()[0])
            except Exception:
                return None

        def _rdtxt(n):
            try:
                with io.open(os.path.join(cdir, n), "r", encoding="utf-8") as f:
                    return f.read().strip()
            except Exception:
                return ""
        ow, om = _rdint("owner_win"), _rdint("owner")
        st = None
        try:
            st = float(_rdtxt("owner_start")) if _rdtxt("owner_start") else None
        except ValueError:
            st = None
        info = {"age_h": round(age_s / 3600.0, 3), "owner_win": ow, "owner": om, "paper": _rdtxt("paper"), "slot": _rdtxt("slot")}
        if ow:
            alive, why = qv_lock.owner_alive(ow, st)
            info.update({"state": "live" if alive else "dead", "why": why})
        elif om:
            info.update({"state": "unknown_owner", "why": "msys_pid_only"})     # 구판 claim — 나이 기준(구판 규칙)
        else:
            info.update({"state": "starting" if age_s <= NO_OWNER_DEAD_S else "dead", "why": "no_owner_marks"})
        return info

    def _reclaim_claim(self, cdir, slot, info, alive_flag):
        gone = _rmtree_force(cdir)
        try:
            os.remove(cdir + ".chain")
        except OSError:
            pass
        self.jl("claim_stale_reclaim", slot=slot, age_h=info.get("age_h"), dead=0 if alive_flag else 1,
                stale_h=self.claim_stale_h(), alive=1 if alive_flag else 0, why=info.get("why"), paper=info.get("paper"))
        if not gone:     # 회수했다고 적고 폴더가 남으면 작업자는 '새 claim' 으로 읽는다 — 실패를 따로 남긴다(감시기가 본다)
            self.jl("claim_reclaim_incomplete", slot=slot, path=cdir,
                    note="claim 폴더를 지우지 못했다 — 작업자가 in_progress 를 되살리지 못한다(no_pending_request 반복) · 세션 확인")

    def sweep_claim(self, slot, cdir):
        """슬롯 1개 claim 판정 · 회수 — 반환 = 판정 뒤 claim_info(free | live | starting)."""
        info = self.claim_info(cdir)
        st = info["state"]
        stale_h = self.claim_stale_h()
        if st == "dead":
            self._reclaim_claim(cdir, slot, info, False)
            return {"state": "free", "reclaimed": True}
        if st == "unknown_owner" and info["age_h"] >= stale_h:
            self._reclaim_claim(cdir, slot, info, False)
            return {"state": "free", "reclaimed": True}
        if st == "live" and info["age_h"] >= stale_h:
            if self.live_reclaim():
                self._reclaim_claim(cdir, slot, info, True)
                return {"state": "free", "reclaimed": True}
            mark = os.path.join(cdir, ".live_long_noted")
            if not os.path.exists(mark):
                self.jl("claim_live_long", slot=slot, age_h=info["age_h"], stale_h=stale_h, owner_win=info.get("owner_win"),
                        paper=info.get("paper"), note="생존 소유자 — 계산 시간 상한 없음(도훈 10-17)이라 회수하지 않는다 · 멈춘 실행이면 세션이 확인")
                try:
                    io.open(mark, "w").close()
                except Exception:
                    pass
        return info

    def chain_fresh(self, slot):
        p = self.chain_path(slot)
        return os.path.exists(p) and (_now() - qv_lock._mtime(p)) < CHAIN_FRESH_S

    # ── 논문 잠금 ─────────────────────────────────────────────────────────────
    @staticmethod
    def paper_slug(key):
        s = re.sub(r"[^A-Za-z0-9._-]+", "_", key or "").strip("_")[:60] or "key"
        return "%s_%s" % (s, hashlib.md5((key or "").encode("utf-8")).hexdigest()[:8])

    def paper_lock_dir(self, key):
        return os.path.join(self.papers_dir, self.paper_slug(key) + ".paper")

    def paper_lock_owner(self, key):
        o = _rd(os.path.join(self.paper_lock_dir(key), "owner.json"))
        return o if isinstance(o, dict) and o.get("key") else None

    def inbox_path(self, key):
        return os.path.join(self.inbox_dir, self.paper_slug(key) + ".json")

    def paper_lock_live(self, o):
        """논문 잠금이 살아 있는가 = 쥔 자리(슬롯 요청 · 인계함 · 구판 요청)가 그 논문을 바쁜 상태로 들고 있다."""
        k, slot = o.get("key"), o.get("slot")
        if slot == "gpu_inbox":
            return os.path.exists(self.inbox_path(k))
        p = self.legacy_req if slot == "legacy" else (o.get("req") or self.req_path(slot))
        d = _rd(p)
        return self.req_key(d) == k and self.req_status(d) in BUSY

    def paper_lock_acquire(self, key, slot, req):
        """발행 잠금 안에서만 부른다. 반환 = (True, slot) | (False, 쥔 슬롯)."""
        ld = self.paper_lock_dir(key)
        os.makedirs(self.papers_dir, exist_ok=True)
        for _ in range(3):
            try:
                os.mkdir(ld)
            except FileExistsError:
                o = self.paper_lock_owner(key)
                if o is None:
                    if _now() - qv_lock._mtime(ld) > PAPER_LOCK_NO_OWNER_S:
                        _rmtree_force(ld)
                        continue
                    return False, "?"
                if o.get("slot") == slot:
                    if o.get("req") != req:
                        o["req"] = req
                        qv_lock._atomic_json(os.path.join(ld, "owner.json"), o)
                    return True, slot
                if self.paper_lock_live(o):
                    return False, o.get("slot")
                _rmtree_force(ld)
                self.jl("paper_lock_stale_reclaim", paper=key, prev_slot=o.get("slot"), by=slot)
                continue
            qv_lock._atomic_json(os.path.join(ld, "owner.json"),
                                 {"schema": SCHEMA_PAPER_LOCK, "key": key, "slot": slot, "req": req, "at": _iso(), "by_pid": os.getpid()})
            return True, slot
        return False, "race"

    def paper_lock_release(self, key, slot):
        o = self.paper_lock_owner(key)
        if o and o.get("slot") == slot:
            _rmtree_force(self.paper_lock_dir(key))
            return True
        return False

    def paper_lock_transfer(self, key, to_slot, to_req):
        ld = self.paper_lock_dir(key)
        os.makedirs(ld, exist_ok=True)
        o = self.paper_lock_owner(key) or {"schema": SCHEMA_PAPER_LOCK, "key": key}
        o.update({"slot": to_slot, "req": to_req, "at": _iso(), "by_pid": os.getpid(), "prev_slot": o.get("slot")})
        qv_lock._atomic_json(os.path.join(ld, "owner.json"), o)

    def sweep_paper_locks(self):
        n = 0
        for ld in glob.glob(os.path.join(self.papers_dir, "*.paper")):
            o = _rd(os.path.join(ld, "owner.json"))
            if not isinstance(o, dict) or not o.get("key"):
                if _now() - qv_lock._mtime(ld) > PAPER_LOCK_NO_OWNER_S:
                    _rmtree_force(ld)
                    n += 1
                continue
            if not self.paper_lock_live(o):
                _rmtree_force(ld)
                n += 1
        return n

    def held_keys(self, except_slot=None):
        """다른 자리가 바쁘게 쥔 논문 키 — 슬롯 요청 · 인계함 · 구판 요청 · 살아 있는 논문 잠금."""
        ks = set()
        for s in self.slot_names():
            if s == except_slot:
                continue
            d = self.read_req(s)
            if self.req_status(d) in BUSY and self.req_key(d):
                ks.add(self.req_key(d))
        for f in glob.glob(os.path.join(self.inbox_dir, "*.json")):
            k = self.req_key(_rd(f))
            if k:
                ks.add(k)
        d = _rd(self.legacy_req)
        if self.req_status(d) in BUSY and self.req_key(d):
            ks.add(self.req_key(d))
        for ld in glob.glob(os.path.join(self.papers_dir, "*.paper")):
            o = _rd(os.path.join(ld, "owner.json"))
            if isinstance(o, dict) and o.get("key") and o.get("slot") != except_slot and self.paper_lock_live(o):
                ks.add(o["key"])
        return ks

    # ── 잠금 문맥 ─────────────────────────────────────────────────────────────
    def issue_lock(self, wait_s=120):
        return _LockCtx(self.name_lock("rf_replication.issue"), wait_s, "rf_replication.issue")

    def dispatch_lock(self, wait_s=5):
        return _LockCtx(self.name_lock("rf_replication.dispatch"), wait_s, "rf_replication.dispatch")

    # ── GPU 임대 ─────────────────────────────────────────────────────────────
    def lease(self):
        try:
            return qv_lock.gpu_lease_expire_check(self.root)
        except qv_lock.LockTimeout:
            return qv_lock.gpu_lease_status(self.root)

    @staticmethod
    def lease_blocks(st):
        return (st or {}).get("state") in ("held", "unreadable")

    # ── 후보 ─────────────────────────────────────────────────────────────────
    def candidates(self):
        """발행 후보(순서 = 재구현 대기열 reserved order 오름차순 → 큐 상단부터 · 재정렬 없음 — 등급 거르기는 순서를 바꾸지 않는다). 틱 안에서 1번만 잰다."""
        if getattr(self, "_cand_cache", None) is not None:
            return self._cand_cache
        self._cand_cache = self._candidates()
        return self._cand_cache

    def _candidates(self):
        tj = os.environ.get("QVEST_RP_CANDIDATES_JSON")
        if tj:
            c = _rd(tj) or []
            return [x for x in c if isinstance(x, dict) and x.get("key")]
        out = []
        qp = os.path.join(self.root, "06_Registry", "reimplement_queue.json")
        q = _rd(qp) or {}
        ents = [e for e in (q.get("entries") or []) if isinstance(e, dict) and e.get("status") == "reserved" and e.get("paper_key")]

        def _ord(e):
            try:
                v = float(e.get("order"))
                return v if v == v and abs(v) != float("inf") else float("inf")
            except (TypeError, ValueError):
                return float("inf")
        for i, e in sorted(enumerate(ents), key=lambda t: (_ord(t[1]), t[0])):
            w = e.get("wdir") or ""
            if w and not os.path.isabs(w):
                w = os.path.join(self.root, w)
            out.append({"key": str(e["paper_key"]), "source": "reimplement_queue", "wdir": w or None,
                        "meta": {"paper_title": e.get("paper_title") or "", "compute_class": e.get("compute_class"),
                                 "requires_gpu": e.get("requires_gpu")}})
        try:
            import rf_next_paper_pick as pick
            stage = os.path.join(self.root, "stage_artifacts", "paper_recharge")
            for c in pick.iter_candidates(stage):
                out.append({"key": str(c.get("paper_key") or ""), "source": "queue", "wdir": None, "meta": c})
        except Exception as ex:
            self.jl("candidates_queue_failed", err=str(ex)[:200])
        return [x for x in out if x["key"]]

    def run_issuer(self, slot, key):
        cmd_override = os.environ.get("QVEST_RP_ISSUE_CMD")
        args = ["--root", self.root, "--req", self.req_path(slot), "--only-key", key, "--slot", slot]
        if cmd_override:   # 검사 전용 대역 — .py 면 이 파이썬으로 돈다
            cmd = ([sys.executable, cmd_override] if cmd_override.endswith(".py") else [cmd_override]) + args
        else:
            cmd = ["Rscript", os.path.join(self.root, "02_Infrastructure", "programs", "next_replication.R")] + args
        env = dict(os.environ)
        env.pop("RP_SLOT", None)
        env["RP_SLOT_ISSUING"] = "1"
        try:
            r = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
            return r.returncode, (r.stdout or "")[-300:] + (r.stderr or "")[-300:]
        except Exception as ex:
            return 99, str(ex)[:300]

    # ── 인계함 ───────────────────────────────────────────────────────────────
    def handoff(self, slot, reason, verify_only=False):
        if not self.has_class("gpu"):
            return {"ok": False, "reason": "no_gpu_slot"}
        with self.issue_lock():
            p = self.req_path(slot)
            d = _rd(p)
            k = self.req_key(d)
            if not k:
                return {"ok": False, "reason": "no_request_key"}
            cls = self.classify_req(d)
            d2 = dict(d)
            d2["handoff"] = {"from_slot": slot, "at": _iso(), "reason": reason, "verify_only": bool(verify_only),
                             "basis": cls.get("basis"), "detail": cls.get("detail")}
            if verify_only:
                d2["failure"] = "gpu_handoff"
            if d2.get("status") == "in_progress":
                d2["status"] = "pending"
            ip = self.inbox_path(k)
            qv_lock._atomic_json(ip, d2)
            self.paper_lock_transfer(k, "gpu_inbox", ip)
            self.write_req(p, {"status": "handed_off_gpu", "slot": slot, "paper": d.get("paper"), "handed_off_at": _iso(),
                               "handoff_to": "gpu_inbox", "reason": reason, "verify_only": bool(verify_only)})
            self.jl("gpu_handoff", slot=slot, paper=k, reason=reason, verify_only=int(bool(verify_only)),
                    basis=cls.get("basis"), detail=cls.get("detail"))
            return {"ok": True, "paper": k, "inbox": ip}

    def inbox_take(self, gslot):
        """발행 잠금 안. 가장 먼저 넘어온 인계 1건 → GPU 슬롯 요청."""
        fs = []
        for f in glob.glob(os.path.join(self.inbox_dir, "*.json")):
            d = _rd(f)
            if isinstance(d, dict) and self.req_key(d):
                fs.append((((d.get("handoff") or {}).get("at") or ""), f, d))
        if not fs:
            return None
        fs.sort(key=lambda t: (t[0], t[1]))
        _, f, d = fs[0]
        k = self.req_key(d)
        d = dict(d)
        d["slot"] = gslot
        if d.get("status") not in BUSY:
            d["status"] = "pending"
        self.write_req(self.req_path(gslot), d)
        self.paper_lock_transfer(k, gslot, self.req_path(gslot))
        try:
            os.remove(f)
        except OSError:
            pass
        self.jl("gpu_inbox_taken", slot=gslot, paper=k, verify_only=int(bool((d.get("handoff") or {}).get("verify_only"))))
        return k

    # ── 구판 요청 인수 ────────────────────────────────────────────────────────
    def legacy_scan(self, occ):
        """구판 claim · 요청. 반환 = 점유자 정보(살아 있는 구판 작업자) 또는 None. 발행 잠금 안에서 부른다."""
        info = self.claim_info(self.legacy_claim)
        d = _rd(self.legacy_req)
        k, st = self.req_key(d), self.req_status(d)
        if info["state"] in ("live", "starting") or (info["state"] == "unknown_owner" and info["age_h"] < self.claim_stale_h()):
            cls = self.classify_req(d)["class"] if k else "cpu"
            return {"state": "live", "paper": k, "class": cls, "status": st, "age_h": info.get("age_h")}
        if info["state"] != "free":
            _rmtree_force(self.legacy_claim)
            self.jl("legacy_claim_reclaim", why=info.get("why"), age_h=info.get("age_h"), paper=k)
        if st not in BUSY or not k:
            return None
        cls = self.classify_req(d)
        for s in self.slot_names():
            if not self.accepts(s, cls["class"]):
                continue
            o = occ.get(s) or {}
            if o.get("claim") != "free" or o.get("chaining") or self.req_status(self.read_req(s)) in BUSY:
                continue
            ok, holder = self.paper_lock_acquire(k, s, self.req_path(s))
            if not ok:
                self.jl("legacy_adopt_blocked", paper=k, holder=holder)
                return None
            d2 = dict(d)
            d2["slot"] = s
            d2["adopted_from"] = "legacy"
            d2["adopted_at"] = _iso()
            self.write_req(self.req_path(s), d2)
            self.write_req(self.legacy_req, {"status": "adopted_by_slot", "slot": s, "paper": d.get("paper"), "adopted_at": _iso(),
                                             "prev_status": st, "note": "다중 슬롯 전환 — 이 요청은 슬롯 요청(06_Registry/replication_slots/%s/)으로 옮겼다" % s})
            self.jl("legacy_request_adopted", slot=s, paper=k, prev_status=st, cls=cls["class"], basis=cls["basis"])
            occ.setdefault(s, {})["status"] = d2.get("status")
            return None
        self.jl("legacy_adopt_waiting", paper=k, cls=cls["class"], note="받을 빈 슬롯 없음 — 다음 틱")
        return {"state": "waiting", "paper": k, "class": cls["class"], "status": st}

    # ── 발행 ─────────────────────────────────────────────────────────────────
    def issue(self, slot, lease_st=None, locked=False):
        if not locked:
            with self.issue_lock():
                return self.issue(slot, lease_st, locked=True)
        self.sweep_paper_locks()
        d = self.read_req(slot)
        if self.req_status(d) in BUSY:
            return {"issued": False, "reason": "busy"}
        if self.slot_class(slot) == "gpu":
            ls = lease_st if lease_st is not None else self.lease()
            if self.lease_blocks(ls):
                return {"issued": False, "reason": "gpu_leased", "holder": ls.get("holder")}
            k = self.inbox_take(slot)
            if k:
                return {"issued": True, "reason": "gpu_inbox", "paper": k}
        excl = self.held_keys(except_slot=slot)
        tries = 0
        for c in self.candidates():
            k = c["key"]
            if k in excl:
                continue
            cls = cc.classify(c.get("meta") or {}, c.get("wdir"), self.cfg)     # 작업 디렉터리에 엔진이 없으면 큐 메타로 떨어진다
            if not self.accepts(slot, cls["class"]):
                continue
            ok, holder = self.paper_lock_acquire(k, slot, self.req_path(slot))
            if not ok:
                excl.add(k)
                continue
            tries += 1
            rc, tail = self.run_issuer(slot, k)
            d2 = self.read_req(slot)
            if self.req_key(d2) == k and self.req_status(d2) == "pending":
                self.jl("slot_issued", slot=slot, paper=k, source=c.get("source"), cls=cls["class"], basis=cls["basis"])
                return {"issued": True, "reason": c.get("source"), "paper": k}
            self.paper_lock_release(k, slot)
            self.jl("slot_issue_miss", slot=slot, paper=k, rc=rc, tail=tail.replace("\n", " ")[-200:])
            if tries >= ISSUE_TRIES:
                break
        return {"issued": False, "reason": "nothing"}

    # ── 작업자 펜싱 ───────────────────────────────────────────────────────────
    def ensure_paper(self, slot):
        try:
            with self.issue_lock():
                return self._ensure_paper(slot)
        except qv_lock.LockTimeout:
            self.jl("paper_lock_wait_timeout", slot=slot, note="발행 잠금 대기 초과 — 요청을 건드리지 않고 물러난다(다음 틱)")
            return 4, "lock_timeout"

    def _ensure_paper(self, slot):
        p = self.req_path(slot)
        d = _rd(p)
        k = self.req_key(d)
        if not k:
            return 0, "no_key"
        ok, holder = self.paper_lock_acquire(k, slot, p)
        if ok:
            return 0, "ok"
        d2 = dict(d)
        d2["status"] = "duplicate_held_elsewhere"
        d2["duplicate_of"] = holder
        d2["duplicate_at"] = _iso()
        self.write_req(p, d2)
        self.jl("paper_locked_elsewhere", slot=slot, paper=k, holder=holder,
                note="같은 논문을 다른 자리가 쥐고 있다 — 이 슬롯 요청을 닫는다(중복 실행 금지)")
        return 3, holder

    # ── 디스패처 ─────────────────────────────────────────────────────────────
    def tick(self, launch=True):
        slots = self.slot_names()
        if not slots:
            print("LEGACY")
            return 0
        self._cand_cache = None
        try:
            ctx = self.dispatch_lock()
            ctx.__enter__()
        except qv_lock.LockTimeout:
            self.jl("halt_dispatch_busy", note="다른 디스패처가 도는 중 — 이번 틱은 물러난다")
            return 0
        try:
            return self._tick(slots, launch)
        except qv_lock.LockTimeout as ex:
            self.jl("halt_issue_lock_busy", err=str(ex)[:200], note="발행 잠금 대기 초과 — 이번 틱은 물러난다")
            return 0
        finally:
            ctx.__exit__(None, None, None)

    def _tick(self, slots, launch):
        self.ensure_slot_files()
        ls = self.lease()
        if ls.get("cleared"):
            self.jl("gpu_lease_expired", state=ls.get("state"), holder=ls.get("holder"), purpose=ls.get("purpose"),
                    started_at=ls.get("started_at"), cap_hours=ls.get("cap_hours"),
                    note="임대 만료(또는 보유 프로세스 사망) — 틱이 스스로 풀었다 · GPU 슬롯 재개")
            ls = {"state": "free"}
        occ = {}
        for s in slots:
            ci = self.sweep_claim(s, self.claim_path(s))
            occ[s] = {"claim": "free" if ci["state"] == "free" else ci["state"], "chaining": self.chain_fresh(s),
                      "paper": ci.get("paper") or "", "age_h": ci.get("age_h")}
        with self.issue_lock():
            self.sweep_paper_locks()
            legacy = self.legacy_scan(occ)
            gslot = next((s for s in slots if self.slot_class(s) == "gpu"), None)
            legacy_gpu = bool(legacy and legacy.get("state") == "live" and legacy.get("class") == "gpu")
            for s in sorted(slots, key=lambda x: (self.slot_class(x) != "gpu", x)):
                o = occ[s]
                if o["claim"] != "free" or o["chaining"]:
                    continue
                if self.req_status(self.read_req(s)) in BUSY:
                    continue
                if self.slot_class(s) == "gpu" and (self.lease_blocks(ls) or legacy_gpu):
                    continue
                r = self.issue(s, lease_st=ls, locked=True)
                o["issue"] = r.get("reason")
        ncpu, ngpu = self.slot_counts()
        run_cpu = sum(1 for s in slots if self.slot_class(s) == "cpu" and (occ[s]["claim"] != "free" or occ[s]["chaining"]))
        run_gpu = sum(1 for s in slots if self.slot_class(s) == "gpu" and (occ[s]["claim"] != "free" or occ[s]["chaining"]))
        if legacy and legacy.get("state") == "live":
            if legacy.get("class") == "gpu":
                run_gpu += 1
            else:
                run_cpu += 1
        cap = {"cpu": ncpu - run_cpu, "gpu": ngpu - run_gpu}
        out = []
        now = _now()
        for s in slots:
            o = occ[s]
            d = self.read_req(s)
            o["status"] = self.req_status(d)
            o["req_paper"] = self.req_key(d)
            if o["claim"] != "free" or o["chaining"] or o["status"] not in BUSY:
                continue
            sc = self.slot_class(s)
            if sc == "gpu" and self.lease_blocks(ls):
                o["hold"] = "gpu_lease"
                continue
            try:
                ew = float((d or {}).get("env_retry_after_epoch") or 0)
            except (TypeError, ValueError):
                ew = 0
            if ew > now:
                o["hold"] = "env_cooldown"
                continue
            if cap[sc] <= 0:
                o["hold"] = "capacity"
                continue
            cap[sc] -= 1
            out.append(s)
        self.write_status(slots, occ, ls, legacy, out)
        self.jl("slots_tick", slots=",".join(slots), launch=",".join(out) or "-",
                occupancy=" ".join("%s:%s/%s%s" % (s, occ[s]["claim"], occ[s].get("status") or "?",
                                                   ("@" + occ[s]["req_paper"]) if occ[s].get("req_paper") else "") for s in slots),
                lease=ls.get("state"), lease_holder=ls.get("holder") or "",
                legacy=(legacy or {}).get("state") or "none")
        if launch:
            for s in out:
                print("LAUNCH %s" % s)
        return 0

    # ── 상태 · 소진량 ─────────────────────────────────────────────────────────
    ATTENTION = ("failed_needs_session", "held_audit_conflict", "exhausted_retries", "duplicate_held_elsewhere")

    def write_status(self, slots, occ, ls, legacy, launched):
        """틱 요약 = 06_Registry/replication_slots/_status.json — 부팅 줄(boot_lean.sh PEND) · Superfan 감시(json_field worst_status)가 읽는다."""
        rows, att = [], []
        for s in slots:
            o = occ.get(s) or {}
            st = o.get("status") or ""
            rows.append({"slot": s, "claim": o.get("claim"), "status": st, "paper": o.get("req_paper") or "", "hold": o.get("hold") or ""})
            if st in self.ATTENTION:
                att.append("%s:%s" % (s, st))
        worst = "failed_needs_session" if any(a.endswith(":failed_needs_session") for a in att) else ("attention" if att else "ok")
        d = {"schema": "replication_slots_status_v1", "at": _iso(), "slots": rows, "launched": launched,
             "inbox": len(glob.glob(os.path.join(self.inbox_dir, "*.json"))), "lease": (ls or {}).get("state"),
             "lease_holder": (ls or {}).get("holder"), "legacy": (legacy or {}).get("state") or "none", "attention": att, "worst_status": worst}
        try:
            qv_lock._atomic_json(os.path.join(self.slot_dir, "_status.json"), d)
        except Exception as ex:
            self.jl("slots_status_write_failed", err=str(ex)[:200])

    def status(self):
        rows = []
        for s in self.slot_names():
            ci = self.claim_info(self.claim_path(s))
            d = self.read_req(s)
            rows.append({"slot": s, "claim": ci["state"], "age_h": ci.get("age_h"), "status": self.req_status(d),
                         "paper": self.req_key(d), "title": str(((d or {}).get("paper") or {}).get("paper_title") or "")[:40]})
        inbox = [self.req_key(_rd(f)) for f in sorted(glob.glob(os.path.join(self.inbox_dir, "*.json")))]
        return {"slots": rows, "inbox": inbox, "lease": qv_lock.gpu_lease_status(self.root),
                "legacy": {"claim": self.claim_info(self.legacy_claim)["state"], "status": self.req_status(_rd(self.legacy_req))}}

    def burn(self, days=7):
        cut = dt.date.today() - dt.timedelta(days=max(1, int(days)) - 1)
        agg = {}
        paper_slot, t0 = {}, {}
        try:
            fh = io.open(self.jlog_path, "r", encoding="utf-8", errors="replace")
        except OSError:
            return {"days": [], "note": "저널 없음: %s" % self.jlog_path}
        last_paper_for_fanout = None
        with fh:
            for line in fh:
                if '"src"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                ts = str(r.get("ts") or "")
                try:
                    day = dt.date.fromisoformat(ts[:10])
                except ValueError:
                    continue
                if day < cut:
                    continue
                src, ev = r.get("src"), r.get("event")
                slot = r.get("slot") or "legacy"
                if src == "replication_auto":
                    a = agg.setdefault((ts[:10], slot), {"papers": 0, "impl_agents": 0, "agent_min": 0.0, "audit_agents": 0, "quota_hits": 0, "verifies": 0})
                    if ev == "start":
                        a["papers"] += 1
                        paper_slot[str(r.get("paper") or "")] = slot
                    elif ev == "model_selected":
                        t0[slot] = ts
                    elif ev == "agent_done":
                        a["impl_agents"] += 1 + (1 if str(r.get("fell_back")) == "1" else 0)
                        if slot in t0:
                            try:
                                a["agent_min"] += (dt.datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S") -
                                                   dt.datetime.strptime(t0.pop(slot)[:19], "%Y-%m-%dT%H:%M:%S")).total_seconds() / 60.0
                            except ValueError:
                                pass
                    elif ev == "halt_env_failure" and r.get("kind") == "model_quota_exhausted":
                        a["quota_hits"] += 1
                    elif ev == "verify_done":
                        a["verifies"] += 1
                elif src == "fidelity_audit" and ev == "delegate_fanout":
                    last_paper_for_fanout = str(r.get("paper") or "")
                elif src == "fidelity_fanout" and ev == "agents_done":
                    s2 = r.get("slot") or paper_slot.get(last_paper_for_fanout or "", "legacy")
                    a = agg.setdefault((ts[:10], s2), {"papers": 0, "impl_agents": 0, "agent_min": 0.0, "audit_agents": 0, "quota_hits": 0, "verifies": 0})
                    try:
                        a["audit_agents"] += int(r.get("axes") or 0)
                    except ValueError:
                        pass
        rows = [dict(day=k[0], slot=k[1], **{kk: (round(vv, 1) if isinstance(vv, float) else vv) for kk, vv in v.items()})
                for k, v in sorted(agg.items())]
        by_day = {}
        for x in rows:
            t = by_day.setdefault(x["day"], {"papers": 0, "llm_sessions": 0, "agent_min": 0.0, "quota_hits": 0})
            t["papers"] += x["papers"]
            t["llm_sessions"] += x["impl_agents"] + x["audit_agents"]
            t["agent_min"] += x["agent_min"]
            t["quota_hits"] += x["quota_hits"]
        return {"rows": rows, "by_day": by_day, "slots": self.slot_names() or ["legacy"],
                "note": "레인 저널 기반 대리 지표 — LLM 세션 수(구현 + 감사) · 구현 에이전트 벽시계 분. 논문당 비용은 같고 슬롯 수만큼 소진 속도가 빨라진다 · 한도 사건(quota_hits)이 생기면 슬롯 수를 줄이고 도훈께 보고"}

    # ── 설정(배포 · 되돌리기) ─────────────────────────────────────────────────
    def config_edit(self, enable, ncpu=2, ngpu=1):
        with qv_lock.write_lock(target=self.cfg_path, wait_s=30, purpose="replication_lane.slots"):
            c = _rd(self.cfg_path)
            if not isinstance(c, dict):
                raise SystemExit("[rp_slots] 설정 판독 불가: %s" % self.cfg_path)
            rl = c.setdefault("replication_lane", {})
            if enable:
                rl["slots"] = {"cpu": int(ncpu), "gpu": int(ngpu)}
                rl.setdefault("gpu_lease", {"default_cap_hours": qv_lock.LEASE_DEFAULT_CAP_H, "max_cap_hours": qv_lock.LEASE_MAX_CAP_H,
                                            "basis": "L1-SPEED-LEVERS-20261020 note '상한 12h/라운드' — P2R05 GPU 추정 ≈8h(paused_note) + 50% · 운영 매개변수(조정 가능)"})
                rl["slots_enabled_at"] = _iso()
                rl["slots_note"] = ("WP3 다중 슬롯(rf_replication_slots.py) — 슬롯 = cpu1..cpuN + gpu1 · torch 논문 = GPU 슬롯만 · GPU 임대 존중 · "
                                    "되돌리기 = rf_replication_slots.py config disable(slots 키 제거 → 구판 단일 슬롯)")
            else:
                rl.pop("slots", None)
                rl["slots_disabled_at"] = _iso()
            tmp = self.cfg_path + ".slots.tmp"
            with io.open(tmp, "w", encoding="utf-8", newline="\n") as f:
                json.dump(c, f, ensure_ascii=False, indent=2)
                f.write("\n")
            os.replace(tmp, self.cfg_path)
            return rl

    @staticmethod
    def parse_not_before(v):
        """시작 관문 값 검사 — rf_replication_auto.sh 관문 판정과 같은 규칙(ISO-8601 · 시간대 필수 · 'Z' 허용). 반환 = 정규화 문자열 · 실패 = ValueError."""
        s = str(v or "").strip()
        if not s:
            raise ValueError("빈 값")
        t = dt.datetime.fromisoformat(s[:-1] + "+00:00" if s[-1:] in ("Z", "z") else s)
        if t.tzinfo is None or t.utcoffset() is None:
            raise ValueError("시간대 없음: %s" % s)
        return t.isoformat()

    def config_not_before(self, value):
        """replication_lane.not_before 설정 · 해제(clear) — 값 검사가 실패하면 설정을 쓰지 않는다(REPLICATION-LANE-RESTART-SLOTS-20261110)."""
        clear = str(value or "").strip().lower() == "clear"
        nb = None if clear else self.parse_not_before(value)
        with qv_lock.write_lock(target=self.cfg_path, wait_s=30, purpose="replication_lane.not_before"):
            c = _rd(self.cfg_path)
            if not isinstance(c, dict):
                raise SystemExit("[rp_slots] 설정 판독 불가: %s" % self.cfg_path)
            rl = c.setdefault("replication_lane", {})
            if clear:
                rl.pop("not_before", None)
                rl["not_before_cleared_at"] = _iso()
            else:
                rl["not_before"] = nb
                rl["not_before_set_at"] = _iso()
                rl["not_before_note"] = ("시작 관문 — 이 시각 전에는 레인이 아무 일도 하지 않는다(rf_replication_auto.sh · 스위치 바로 뒤) · "
                                         "해제 = rf_replication_slots.py config not-before clear")
            tmp = self.cfg_path + ".nb.tmp"
            with io.open(tmp, "w", encoding="utf-8", newline="\n") as f:
                json.dump(c, f, ensure_ascii=False, indent=2)
                f.write("\n")
            os.replace(tmp, self.cfg_path)
            return rl


class _LockCtx(object):
    def __init__(self, lockdir, wait_s, purpose):
        self.lockdir, self.wait_s, self.purpose, self.h = lockdir, wait_s, purpose, None

    def __enter__(self):
        self.h = qv_lock.acquire(self.lockdir, wait_s=self.wait_s, stale_s=3600, purpose=self.purpose)
        return self.h

    def __exit__(self, *a):
        qv_lock.release(self.h)
        return False


def _status_line(L):
    st = L.status()
    parts = []
    for r in st["slots"]:
        if r["claim"] == "live":
            parts.append("%s %s %s(%.1fh)" % (r["slot"], r["paper"] or "?", r["status"] or "?", r["age_h"] or 0))
        elif r["status"] in BUSY:
            parts.append("%s %s 대기(%s)" % (r["slot"], r["paper"] or "?", r["status"]))
        else:
            parts.append("%s 비어 있음" % r["slot"])
    ls = st["lease"]
    if ls.get("state") == "held":
        parts.append("GPU 임대 %s %.1f/%.0fh" % (ls.get("holder"), ls.get("elapsed_h") or 0, ls.get("cap_hours") or 0))
    if st["inbox"]:
        parts.append("GPU 인계 대기 %d" % len(st["inbox"]))
    return "Lane: " + " · ".join(parts) if parts else "Lane: 슬롯 미설정(구판 단일 슬롯)"


def main(argv=None):
    for _s in (sys.stdout, sys.stderr):   # 레인 셸은 -X utf8 없이 부른다 — 콘솔 코드 페이지에 없는 글자(논문 제목)로 죽지 않게
        try:
            _s.reconfigure(errors="replace")
        except Exception:
            pass
    ap = argparse.ArgumentParser(prog="rf_replication_slots")
    ap.add_argument("--root")
    sp = ap.add_subparsers(dest="cmd", required=True)
    t = sp.add_parser("tick"); t.add_argument("--no-launch", action="store_true")
    i = sp.add_parser("issue"); i.add_argument("--slot", required=True)
    pl = sp.add_parser("paper-lock"); pl.add_argument("--slot", required=True)
    c = sp.add_parser("classify"); c.add_argument("--req", required=True); c.add_argument("--wdir")
    h = sp.add_parser("handoff"); h.add_argument("--slot", required=True); h.add_argument("--reason", required=True)
    h.add_argument("--verify-only", action="store_true")
    cs = sp.add_parser("claim-stamp"); cs.add_argument("--claim", required=True)
    s = sp.add_parser("status"); s.add_argument("--line", action="store_true"); s.add_argument("--json", action="store_true")
    b = sp.add_parser("burn"); b.add_argument("--days", type=int, default=7); b.add_argument("--json", action="store_true")
    cf = sp.add_parser("config"); cf.add_argument("op", choices=["enable", "disable", "show", "not-before"])
    cf.add_argument("value", nargs="?", default=None)      # not-before 전용: ISO-8601(시간대 필수) | clear
    cf.add_argument("--cpu", type=int, default=2); cf.add_argument("--gpu", type=int, default=1)
    a = ap.parse_args(argv)
    L = Lane(a.root)
    if a.cmd == "tick":
        return L.tick(launch=not a.no_launch)
    if a.cmd == "issue":
        if a.slot not in L.slot_names():
            print("unknown_slot")
            return 2
        r = L.issue(a.slot)
        print(json.dumps(r, ensure_ascii=False))
        return 0
    if a.cmd == "paper-lock":
        rc, why = L.ensure_paper(a.slot)
        print("%s %s" % ({0: "ok", 3: "held_elsewhere", 4: "lock_timeout"}.get(rc, "error"), why))
        return rc
    if a.cmd == "classify":
        r = L.classify_req(_rd(a.req) or {}, wdir=a.wdir)
        print("%s %s %s" % (r["class"], r["basis"], (r.get("detail") or "").replace(" ", "_")[:80]))
        return 0
    if a.cmd == "handoff":
        r = L.handoff(a.slot, a.reason, a.verify_only)
        print(json.dumps(r, ensure_ascii=False))
        return 0 if r.get("ok") else 1
    if a.cmd == "claim-stamp":
        try:
            with io.open(os.path.join(a.claim, "owner_win"), encoding="utf-8") as f:
                pid = int(f.read().strip().split()[0])
            ps = qv_lock.proc_start(pid)
            if ps is not None:
                with io.open(os.path.join(a.claim, "owner_start"), "w", encoding="utf-8") as f:
                    f.write("%.3f\n" % ps)
            return 0
        except Exception:
            return 1
    if a.cmd == "status":
        if a.line:
            print(_status_line(L))
        else:
            print(json.dumps(L.status(), ensure_ascii=False, indent=1 if not a.json else None))
        return 0
    if a.cmd == "burn":
        r = L.burn(a.days)
        if a.json:
            print(json.dumps(r, ensure_ascii=False))
        else:
            print("일 소진량(최근 %d일 · 슬롯 %s) — %s" % (a.days, ",".join(r.get("slots") or []), r.get("note")))
            print("%-10s %-7s %6s %8s %9s %8s %6s" % ("day", "slot", "papers", "impl_ag", "agent_min", "audit_ag", "quota"))
            for x in r.get("rows") or []:
                print("%-10s %-7s %6d %8d %9.1f %8d %6d" % (x["day"], x["slot"], x["papers"], x["impl_agents"], x["agent_min"],
                                                          x["audit_agents"], x["quota_hits"]))
            for d, v in sorted((r.get("by_day") or {}).items()):
                print("합계 %s — 논문 %d · LLM 세션 %d · 구현 에이전트 %.0f분 · 한도 사건 %d" % (d, v["papers"], v["llm_sessions"], v["agent_min"], v["quota_hits"]))
        return 0
    if a.cmd == "config":
        if a.op == "show":
            print(json.dumps({k: L.rl.get(k) for k in ("enabled", "slots", "gpu_lease", "not_before")}, ensure_ascii=False))
            return 0
        if a.op == "not-before":
            if a.value is None:
                print("[rp_slots] config not-before <ISO-8601(시간대 필수)|clear>", file=sys.stderr)
                return 2
            try:
                rl = L.config_not_before(a.value)
            except ValueError as ex:
                print("[rp_slots] not_before 거부(설정 무변경): %s" % ex, file=sys.stderr)
                return 2
            print(json.dumps({k: rl.get(k) for k in ("enabled", "slots", "not_before")}, ensure_ascii=False))
            return 0
        if a.value is not None:
            print("[rp_slots] %s 는 값 인자를 받지 않는다: %s" % (a.op, a.value), file=sys.stderr)
            return 2
        rl = L.config_edit(a.op == "enable", a.cpu, a.gpu)
        print(json.dumps({k: rl.get(k) for k in ("enabled", "slots", "gpu_lease")}, ensure_ascii=False))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
