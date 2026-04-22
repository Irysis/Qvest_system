#!/usr/bin/env python3
"""stage_dispatch.py — Pipeline DONE→TODO 라우터 (Phase C2)

호출 패턴 (pipeline_trigger.sh wrapper):
  python3 stage_dispatch.py <project_root> [<changed_file>]

  - changed_file 지정 시: 해당 파일이 DONE_ pattern과 매칭되면 단일 transition 처리 (O(1))
  - 미지정 시: 모든 mailbox inbox 스캔 (Bash event 등 file_path 없을 때 fallback)

선언적 transition table: stage_transitions.json
Special handlers: role_router.route_s4 + 로컬 함수들 (s5_to_s6_split, s6_codex_gate 등)

Dedup: SQLite (/tmp/pipeline_dedup.sqlite, TTL 30s) — 같은 (transition, strategy) 즉시 재처리 차단.
ERR safe: 모든 예외는 stderr로 기록만 하고 exit 0 (도구 차단 방지).
"""
from __future__ import annotations

import fnmatch
import glob
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
CHANGED_FILE = sys.argv[2] if len(sys.argv) > 2 else None
MAILBOX = PROJECT_ROOT / "qepm" / "mailbox"
LOG = Path("/tmp/pipeline_trigger.log")
DEDUP_DB = Path("/tmp/pipeline_dedup.sqlite")
HERE = Path(__file__).resolve().parent
TRANSITIONS_PATH = HERE / "stage_transitions.json"


def log(msg: str) -> None:
    ts = time.strftime("%H:%M:%S")
    try:
        with LOG.open("a") as f:
            f.write(f"{ts} {msg}\n")
    except Exception:
        pass


def init_dedup() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DEDUP_DB), timeout=2.0)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS seen "
        "(key TEXT PRIMARY KEY, ts INTEGER NOT NULL)"
    )
    # 30s 이전 항목 정리
    conn.execute("DELETE FROM seen WHERE ts < ?", (int(time.time()) - 30,))
    conn.commit()
    return conn


def is_seen(conn: sqlite3.Connection, key: str) -> bool:
    cur = conn.execute("SELECT 1 FROM seen WHERE key = ?", (key,))
    return cur.fetchone() is not None


def mark_seen(conn: sqlite3.Connection, key: str) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO seen (key, ts) VALUES (?, ?)",
        (key, int(time.time())),
    )
    conn.commit()


def archive_done(src: Path) -> None:
    """DONE_*.json → ../processed/ 이동."""
    proc = src.parent.parent / "processed"
    proc.mkdir(parents=True, exist_ok=True)
    try:
        shutil.move(str(src), str(proc / src.name))
    except Exception as e:
        log(f"ARCHIVE_FAIL: {src.name} ({e})")


def extract_strategy(done_path: Path, _src_glob: str) -> str:
    """DONE_S0_<strategy>.json → strategy."""
    name = done_path.name  # DONE_<stage>_<strategy>.json
    # remove .json
    stem = name[:-5] if name.endswith(".json") else name
    # remove DONE_<STAGE>_ prefix
    parts = stem.split("_", 2)
    if len(parts) >= 3 and parts[0] == "DONE":
        return parts[2]
    return stem


def cp(src: Path, dst: Path) -> bool:
    if dst.exists():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copyfile(str(src), str(dst))
        return True
    except Exception as e:
        log(f"COPY_FAIL: {src.name} → {dst} ({e})")
        return False


# ─── Special Handlers ────────────────────────────────────────────────


def s5_to_s6_split(src: Path, strategy: str, **_) -> bool:
    """S5 완료 → Judge + Codex 병렬 검증."""
    judge_target = MAILBOX / "judge" / "inbox" / f"TODO_S6_{strategy}.json"
    codex_target = MAILBOX / "codex" / "inbox" / f"TODO_S6_{strategy}.json"
    codex_target.parent.mkdir(parents=True, exist_ok=True)
    if judge_target.exists():
        return False
    # Mutation Tracker 갱신 (S2.7) — best effort
    tracker = PROJECT_ROOT / "02_Infrastructure" / "validation" / "mutation_tracker.py"
    if tracker.exists():
        try:
            env = os.environ.copy()
            env["QVEST_PROJECT_DIR"] = str(PROJECT_ROOT)
            subprocess.run(
                ["python3", str(tracker)],
                env=env, capture_output=True, timeout=30, check=False,
            )
        except Exception:
            pass
    cp(src, judge_target)
    cp(src, codex_target)
    log(f"TRIGGER: Forge DONE_S5 → Judge+Codex TODO_S6 ({strategy})")
    return True


def s6_codex_gate(src: Path, strategy: str, **_) -> bool:
    """Judge DONE_S6 + Codex DONE_S6 양쪽 완료 시 → S7."""
    target = MAILBOX / "judge" / "inbox" / f"TODO_S7_{strategy}.json"
    codex_done = MAILBOX / "codex" / "inbox" / f"DONE_S6_{strategy}.json"
    if target.exists():
        return False
    if not codex_done.exists():
        log(f"WAIT: Judge DONE_S6 but Codex pending ({strategy})")
        return False
    cp(src, target)
    log(f"TRIGGER: Judge+Codex DONE_S6 → Judge TODO_S7 ({strategy})")
    try:
        archive_done(codex_done)
    except Exception:
        pass
    return True


def s7_grade_gate(src: Path, strategy: str, **_) -> bool:
    """Grade A/A_NOVEL/A_CONDITIONAL/B만 PG0 진입."""
    target = MAILBOX / "q_lead" / "inbox" / f"TODO_PG0_{strategy}.json"
    if target.exists():
        return False
    grade = "F"
    strat_dirs = list((PROJECT_ROOT / "04_Research" / "strategies").glob(f"*{strategy}*"))
    if strat_dirs:
        for hr in strat_dirs[0].glob("output*/hurdle_result.json"):
            try:
                d = json.loads(hr.read_text())
                v = d.get("verdict", d)
                grade = v.get("grade", d.get("grade", "F"))
                break
            except Exception:
                continue
    if grade in ("A", "A_NOVEL", "A_CONDITIONAL", "B"):
        cp(src, target)
        log(f"TRIGGER: Judge DONE_S7 → Governor TODO_PG0 ({strategy}, Grade={grade})")
    else:
        proc = src.parent.parent / "processed"
        proc.mkdir(parents=True, exist_ok=True)
        try:
            shutil.move(str(src), str(proc / f"ARCHIVED_S7_{strategy}.json"))
        except Exception:
            pass
        log(f"BLOCKED: {strategy} Grade={grade} → ARCHIVE (PG 진입 거부)")
        return True  # processed
    return True


def _spawn_distill_async(strategy: str, fn_name: str, trigger_flag: Path) -> None:
    if trigger_flag.exists():
        return
    trigger_flag.touch()
    cmd = (
        f"cd '{PROJECT_ROOT}' && Rscript --no-save -e \""
        f"suppressMessages(source('02_Infrastructure/R/hook_batch_runner.R')); "
        f"{fn_name}('{strategy}')\""
    )
    log_file = f"/tmp/pipeline_trigger_{fn_name}_{os.getpid()}.log"
    try:
        subprocess.Popen(
            ["nohup", "bash", "-c", cmd],
            stdout=open(log_file, "w"), stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL, start_new_session=True,
        )
    except Exception as e:
        log(f"DISTILL_SPAWN_FAIL: {strategy} {fn_name} ({e})")


def pg2_distill_async(src: Path, strategy: str, **_) -> bool:
    flag = Path(f"/tmp/axiom_partial_trigger_{strategy}")
    _spawn_distill_async(strategy, "hook_pg2_distill_and_gap", flag)
    log(f"TRIGGER: PG2 완료 — Axiom distill + gap→Scout ({strategy})")
    return True


def pg3_full_distill_async(src: Path, strategy: str, **_) -> bool:
    flag = Path(f"/tmp/axiom_distill_trigger_{strategy}")
    if flag.exists():
        return False
    # L-code 존재 체크 (없으면 다음 사이클로 미룸)
    strat_dirs = list((PROJECT_ROOT / "04_Research" / "strategies").glob(f"*{strategy}*"))
    if strat_dirs:
        l_codes = list(strat_dirs[0].glob("l_code_*.json"))
        if not l_codes:
            log(f"AXIOM DEFER: {strategy} — l_code 미존재, 다음 사이클 대기")
            return False
    _spawn_distill_async(strategy, "hook_pg3_full_distill", flag)
    log(f"TRIGGER: Axiom 전체 증류 — PG3 ({strategy})")
    return True


SPECIAL_HANDLERS = {
    "stage_dispatch.s5_to_s6_split": s5_to_s6_split,
    "stage_dispatch.s6_codex_gate": s6_codex_gate,
    "stage_dispatch.s7_grade_gate": s7_grade_gate,
    "stage_dispatch.pg2_distill_async": pg2_distill_async,
    "stage_dispatch.pg3_full_distill_async": pg3_full_distill_async,
}


def _load_role_router():
    """role_router.route_s4 — 지연 로드 (Rscript hook_determine_role 호출)."""
    sys.path.insert(0, str(HERE))
    try:
        import role_router  # type: ignore
        return role_router.route_s4
    except Exception as e:
        log(f"ROLE_ROUTER_LOAD_FAIL: {e}")
        return None


# ─── Main Dispatch ───────────────────────────────────────────────────


def process_match(transition: dict, src: Path, conn: sqlite3.Connection) -> bool:
    strategy = extract_strategy(src, transition["src_glob"])
    dedup_key = f"{transition['name']}::{strategy}"
    if is_seen(conn, dedup_key):
        return False
    method = transition.get("method", "copy")
    triggered = False
    if method == "copy":
        dst_template = transition["dst_template"]
        dst = MAILBOX / dst_template.format(strategy=strategy)
        if cp(src, dst):
            log(f"TRIGGER: {transition['name']} → {dst.relative_to(MAILBOX)} ({strategy})")
            triggered = True
            archive_done(src)
    elif method == "special":
        handler_name = transition["special_handler"]
        handler = SPECIAL_HANDLERS.get(handler_name)
        if handler is None and handler_name == "role_router.route_s4":
            handler = _load_role_router()
            if handler is not None:
                SPECIAL_HANDLERS[handler_name] = handler
        if handler is None:
            log(f"HANDLER_MISSING: {handler_name}")
            return False
        try:
            triggered = handler(src=src, strategy=strategy, mailbox=MAILBOX, project_root=PROJECT_ROOT)
            if triggered:
                # special handler가 자체적으로 archive 안 한 경우 보조
                if src.exists():
                    archive_done(src)
        except Exception as e:
            log(f"HANDLER_ERROR: {handler_name} {strategy} ({e})")
    if triggered:
        mark_seen(conn, dedup_key)
    return triggered


def file_matches(src_glob: str, file_path: str) -> bool:
    """src_glob (e.g., 'scout/inbox/DONE_S0_*.json') ↔ file_path 매칭."""
    try:
        rel_to_mb = Path(file_path).resolve().relative_to(MAILBOX.resolve())
    except ValueError:
        return False
    return fnmatch.fnmatch(str(rel_to_mb), src_glob)


def main() -> int:
    if not MAILBOX.exists():
        return 0
    transitions = json.loads(TRANSITIONS_PATH.read_text())["transitions"]

    # processed/ 자동 생성 + DONE 정리
    for agent_dir in MAILBOX.glob("*/"):
        (agent_dir / "processed").mkdir(exist_ok=True)
    for f in (MAILBOX / "q_lead" / "inbox").glob("DONE_*.json"):
        try:
            shutil.move(str(f), str(MAILBOX / "q_lead" / "processed" / f.name))
        except Exception:
            pass

    conn = init_dedup()

    # CHANGED_FILE 단일 파일 모드 (PostToolUse[Write])
    if CHANGED_FILE and Path(CHANGED_FILE).exists():
        for t in transitions:
            if file_matches(t["src_glob"], CHANGED_FILE):
                process_match(t, Path(CHANGED_FILE).resolve(), conn)
                break  # 한 파일은 하나의 transition만
        return 0

    # Full scan fallback (Bash event 등)
    for t in transitions:
        for src_str in glob.glob(str(MAILBOX / t["src_glob"])):
            src = Path(src_str)
            if not src.is_file():
                continue
            process_match(t, src, conn)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        log(f"DISPATCH_FATAL: {e}")
        sys.exit(0)
