#!/usr/bin/env python3
# ★RETIRED (v10 2026-09-03) — V7 mailbox 스테이지 라우터. v9(2026-08-23) 등록 해제(MANIFEST #26) 후
#   v10 에서 목적지(governor mailbox)마저 소멸해 배관 자체가 도달 불가. settings.json 재등록 금지 —
#   hook_integrity_check.sh REQUIRED_* 에도 넣지 말 것. 파일은 사료 존치(resurrection_verify.sh 가 경로 인용).
#   재열람 = git 태그 pre-v10-2layer.
"""role_router.py — DONE_S4 role 분기 (Phase C2)

stage_dispatch.s4_handler가 호출. role 결정은 R 함수 hook_determine_role 의존.
결과는 /tmp/role_cache_<strategy>_<hash>.json에 캐시 → Rscript 호출 횟수 감소.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path

ROLE_CACHE_DIR = Path("/tmp")
ROLE_CACHE_TTL = 24 * 3600  # 1일


def _log(msg: str) -> None:
    try:
        with Path("/tmp/pipeline_trigger.log").open("a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
    except Exception:
        pass


def _strategy_dir(project_root: Path, strategy: str) -> Path | None:
    base = project_root / "04_Research" / "strategies"
    if not base.exists():
        return None
    candidates = list(base.glob(f"*{strategy}*"))
    return candidates[0] if candidates else None


def _read_grade(src: Path) -> bool:
    try:
        d = json.loads(src.read_text())
        return bool(d.get("kospi_beat", False))
    except Exception:
        return False


def _hook_determine_role(project_root: Path, strategy_dir: Path, src: Path) -> str:
    """Rscript hook_determine_role 호출 + cache."""
    cache_key = f"role_cache_{strategy_dir.name}.json"
    cache_path = ROLE_CACHE_DIR / cache_key
    if cache_path.exists():
        age = time.time() - cache_path.stat().st_mtime
        if age < ROLE_CACHE_TTL:
            try:
                cached = json.loads(cache_path.read_text())
                return cached.get("role", "core_alpha")
            except Exception:
                pass
    # Rscript 호출
    cmd = [
        "Rscript", "--no-save", "-e",
        f"suppressMessages(source('02_Infrastructure/R/hook_batch_runner.R')); "
        f"cat(hook_determine_role('{strategy_dir}', '{src}'), '\\n')"
    ]
    try:
        out = subprocess.run(
            cmd, cwd=str(project_root), capture_output=True,
            timeout=30, text=True, check=False,
        )
        role = (out.stdout.strip().split("\n")[-1] if out.stdout else "").strip()
        if role:
            cache_path.write_text(json.dumps({"role": role, "ts": int(time.time())}))
            return role
    except Exception as e:
        _log(f"ROLE_RSCRIPT_FAIL: {strategy_dir.name} ({e})")
    return "core_alpha"


def _patch_done_with_role_meta(src: Path, role: str, extras: dict) -> None:
    try:
        d = json.loads(src.read_text())
        d["role_label"] = role
        d.update(extras)
        src.write_text(json.dumps(d, indent=2))
    except Exception as e:
        _log(f"PATCH_DONE_FAIL: {src.name} ({e})")


def _archive(src: Path) -> None:
    proc = src.parent.parent / "processed"
    proc.mkdir(parents=True, exist_ok=True)
    try:
        shutil.move(str(src), str(proc / src.name))
    except Exception:
        pass


def route_s4(src: Path, strategy: str, mailbox: Path, project_root: Path) -> bool:
    """DONE_S4 → role 결정 → 적합 target에 라우팅."""
    strat_dir = _strategy_dir(project_root, strategy)
    role = "core_alpha"
    if strat_dir is not None:
        role = _hook_determine_role(project_root, strat_dir, src)
    _log(f"ROLE: {strategy} → {role}")

    target: Path | None = None
    if role == "defense":
        target = mailbox / "forge" / "inbox" / f"TODO_S5_EXEC_{strategy}.json"
        _patch_done_with_role_meta(src, "defense", {})
    elif role == "cash_allocation":
        target = mailbox / "governor" / "inbox" / f"TODO_PG2_CASH_SLEEVE_{strategy}.json"
        _patch_done_with_role_meta(src, "cash_allocation", {
            "v55_trail": "standard",
            "admission_rule": "v3.5.2 §1.4",
        })
        _log(f"TRIGGER v55: {strategy} cash_allocation → TODO_PG2_CASH_SLEEVE (S5 skip)")
    elif role == "regime_adaptive":
        target = mailbox / "forge" / "inbox" / f"TODO_S5_EXEC_{strategy}.json"
        _patch_done_with_role_meta(src, "regime_adaptive", {
            "v55_gate_items": [
                "switching_alpha>0.10",
                "transition_cost<50bps",
                "stability_36M>=0.60",
            ],
        })
        _log(f"TRIGGER v55: {strategy} regime_adaptive → TODO_S5_EXEC")
    elif role == "ml_predictive":
        target = mailbox / "forge" / "inbox" / f"TODO_S5_EXEC_{strategy}.json"
        _patch_done_with_role_meta(src, "ml_predictive", {
            "v55_trail": "ml_empirical_first",
            "v55_gate_items": [
                "SR_OOS_IS>=0.70",
                "feature_concentration<0.4",
                "holdout_12M_strict",
            ],
        })
        _log(f"TRIGGER v55: {strategy} ml_predictive → TODO_S5_EXEC (empirical-first)")
    else:
        # core_alpha or diversifier: KOSPI beat 시 S6, 미달 시 S5 mutation
        kospi_beat = _read_grade(src)
        if kospi_beat:
            target = mailbox / "judge" / "inbox" / f"TODO_S6_{strategy}.json"
        else:
            target = mailbox / "forge" / "inbox" / f"TODO_S5_EXEC_{strategy}.json"

    if target is None or target.exists():
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copyfile(str(src), str(target))
    except Exception as e:
        _log(f"ROLE_ROUTE_COPY_FAIL: {target} ({e})")
        return False
    _log(f"TRIGGER: Forge DONE_S4 → {target.name} ({strategy}, role={role})")
    _archive(src)
    return True
