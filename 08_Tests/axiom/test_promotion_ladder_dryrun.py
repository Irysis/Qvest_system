#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""test_promotion_ladder_dryrun.py — v9 승격 사다리 dry-run 행동 검사 (2026-08-23).

무엇을 재는가
-------------
promote.R 의 v9 사다리(`.TIER$mode_local`)를 **실제 저장소 후보 전건**에 dry-run 으로
돌려, 판정이 셋 다 성립하는지 본다.

  [A] CLI  `--dry-run` 플래그가 verdict 토큰(`→ PASS|MAP|FAIL|SKIP_*`)을 실제로 찍는가
  [B] 판정  ① 통과(PASS) ≥1건 — 사다리가 **닫혀 있지 않다**(구 5축은 728회 0건이었다)
            ② 단일 L-code 후보는 **전부** SKIP_SINGLETON
            ③ polarity=unknown 후보는 **전부** SKIP_UNKNOWN
  [C] 무쓰기 dry-run 이 candidates / review_log / active 어디에도 쓰지 않는가
      (이름 + mtime + 크기 스냅샷 대조 — "안 썼다"를 개수로만 재면 덮어쓰기를 놓친다)

★검사 규율: [B]① 이 없으면 "전부 FAIL" 이라는 **구 상태와 겉보기가 같다**. 그래서
  이 검사의 본체는 개수가 아니라 **분포**다 — SKIP 이 0 이어도(사전 필터 사망) FAIL 이다.

실행: python 08_Tests/axiom/test_promotion_ladder_dryrun.py
      (Rscript 필요. 미탐지 시 SKIP 종료 — 검사 실패로 위장하지 않는다.)
"""
from __future__ import annotations

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if not os.path.isdir(os.path.join(ROOT, "02_Infrastructure")):
    ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") or ROOT

CAND_DIR = os.path.join(ROOT, "qepm", "memory", "axioms", "candidates")
RL_DIR = os.path.join(ROOT, "qepm", "memory", "axioms", "review_log")
ACTIVE_DIR = os.path.join(ROOT, "qepm", "memory", "axioms", "active")
PROMOTE_R = os.path.join(ROOT, "02_Infrastructure", "axiom", "promote.R")

PASS = FAIL = SKIP = 0


def ok(name, msg=""):
    global PASS
    PASS += 1
    print(f"  PASS: {name}" + (f" — {msg}" if msg else ""))


def bad(name, msg=""):
    global FAIL
    FAIL += 1
    print(f"  FAIL: {name}" + (f" — {msg}" if msg else ""))


def skip(name, msg=""):
    global SKIP
    SKIP += 1
    print(f"  SKIP: {name}" + (f" — {msg}" if msg else ""))


def chk(name, cond, msg=""):
    ok(name, msg) if cond else bad(name, msg)


def _rscript() -> str | None:
    p = shutil.which("Rscript")
    if p:
        return p
    for base in (r"C:\Program Files\R",):
        if os.path.isdir(base):
            for d in sorted(os.listdir(base), reverse=True):
                c = os.path.join(base, d, "bin", "Rscript.exe")
                if os.path.exists(c):
                    return c
    return None


def _snapshot(*dirs) -> dict:
    """이름 -> (mtime_ns, size). '개수 불변'만 보면 덮어쓰기를 못 잡는다."""
    out = {}
    for d in dirs:
        for f in glob.glob(os.path.join(d, "**", "*.json"), recursive=True):
            try:
                st = os.stat(f)
                out[os.path.relpath(f, ROOT)] = (st.st_mtime_ns, st.st_size)
            except OSError:
                pass
    return out


def main() -> int:
    rs = _rscript()
    if rs is None:
        skip("T0_rscript", "Rscript 미탐지 — 환경 문제이지 검사 실패가 아님")
        print(f"\nTOTAL: {PASS} pass / {FAIL} fail / {SKIP} skip")
        print(json.dumps({"test": "promotion_ladder_dryrun", "pass": PASS, "fail": FAIL,
                          "skip": SKIP, "total": PASS + FAIL}, ensure_ascii=False))
        return 0
    cands = sorted(glob.glob(os.path.join(CAND_DIR, "CAND_*.json")))
    if not os.path.exists(PROMOTE_R) or not cands:
        skip("T0_inputs", f"promote.R={os.path.exists(PROMOTE_R)} candidates={len(cands)}")
        print(f"\nTOTAL: {PASS} pass / {FAIL} fail / {SKIP} skip")
        return 0
    ok("T0_inputs", f"promote.R + candidate {len(cands)}건")

    # ── 기대 라벨을 후보 파일에서 **독립적으로** 산출 (promote.R 출력에 의존하지 않음) ──
    expect_singleton, expect_unknown = set(), set()
    for f in cands:
        try:
            with open(f, "r", encoding="utf-8-sig") as fh:
                d = json.load(fh)
        except Exception:
            continue
        b = os.path.basename(f)
        if (d.get("polarity") or "unknown") == "unknown":
            expect_unknown.add(b)
        elif len(d.get("supporting_l_codes") or []) < 2:
            expect_singleton.add(b)

    before = _snapshot(CAND_DIR, RL_DIR, ACTIVE_DIR)

    # ── [A] CLI 경로: 대표 후보 1건에 `--dry-run` 을 붙여 토큰이 찍히는지 ──
    print("\n[A] CLI --dry-run 토큰")
    env = dict(os.environ, CLAUDE_PROJECT_DIR=ROOT, R_LIBS_USER=os.environ.get("R_LIBS_USER", ""))
    r = subprocess.run([rs, PROMOTE_R, "--dry-run", cands[0]], cwd=ROOT, env=env,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    tok = re.findall(r"→ (PASS|MAP|FAIL|SKIP_[A-Z]+)", (r.stdout or "") + (r.stderr or ""))
    chk("A1_cli_emits_token", len(tok) >= 1, f"exit={r.returncode} tokens={tok[:3]}")

    # ── [B] 전건 dry-run (프로세스 1회 — 후보마다 Rscript 를 띄우면 검사가 분 단위가 된다) ──
    print("\n[B] 후보 전건 dry-run 판정 분포")
    drv = tempfile.NamedTemporaryFile("w", suffix=".R", delete=False, encoding="utf-8")
    drv.write(
        'Sys.setenv(PROMOTE_SOURCED = "1")\n'
        f'root <- {json.dumps(ROOT)}\n'
        'Sys.setenv(CLAUDE_PROJECT_DIR = root)\n'
        'e <- new.env(parent = globalenv())\n'
        'invisible(capture.output(suppressWarnings(suppressMessages(\n'
        '  sys.source(file.path(root, "02_Infrastructure/axiom/promote.R"), envir = e)))))\n'
        'fs <- list.files(file.path(root, "qepm/memory/axioms/candidates"),\n'
        '                 pattern = "^CAND_.*\\\\.json$", full.names = TRUE)\n'
        'for (f in fs) {\n'
        '  v <- tryCatch({ r <- NULL\n'
        '    invisible(capture.output(r <- e$promote_to_axiom(f, dry_run = TRUE)))\n'
        '    as.character(r$verdict %||% "NA") }, error = function(err) paste0("ERROR:", conditionMessage(err)))\n'
        '  cat(sprintf("VERDICT\\t%s\\t%s\\n", basename(f), v[1]))\n'
        '}\n')
    drv.close()
    r2 = subprocess.run([rs, drv.name], cwd=ROOT, env=env, capture_output=True,
                        text=True, encoding="utf-8", errors="replace")
    os.unlink(drv.name)
    verdicts = {}
    for line in (r2.stdout or "").splitlines():
        if line.startswith("VERDICT\t"):
            _, base, v = line.split("\t", 2)
            verdicts[base] = v.strip()
    chk("B0_all_candidates_judged", len(verdicts) == len(cands),
        f"판정 {len(verdicts)}/{len(cands)} (미판정은 crash 이지 '결과 없음' 이 아니다)")
    if len(verdicts) != len(cands):
        print((r2.stderr or "")[-1500:])

    dist = {}
    for v in verdicts.values():
        dist[v] = dist.get(v, 0) + 1
    print(f"      분포: {dist}")
    errs = [b for b, v in verdicts.items() if v.startswith("ERROR:")]
    chk("B1_no_error", not errs, f"판정 중 예외 {len(errs)}건" + (f" 예: {errs[:2]}" if errs else ""))
    chk("B2_at_least_one_pass", dist.get("PASS", 0) >= 1,
        f"PASS={dist.get('PASS', 0)} (0 이면 사다리가 닫힌 것 — 구 5축 상태와 동일)")
    miss_s = sorted(b for b in expect_singleton if verdicts.get(b) != "SKIP_SINGLETON")
    chk("B3_singletons_skipped", not miss_s,
        f"단일 L-code {len(expect_singleton)}건 중 미SKIP {len(miss_s)}건" + (f" 예: {miss_s[:2]}" if miss_s else ""))
    miss_u = sorted(b for b in expect_unknown if verdicts.get(b) != "SKIP_UNKNOWN")
    chk("B4_unknown_skipped", not miss_u,
        f"polarity=unknown {len(expect_unknown)}건 중 미SKIP {len(miss_u)}건" + (f" 예: {miss_u[:2]}" if miss_u else ""))
    # 사전 필터가 죽으면(전부 판정) 위 두 축은 '기대 0건' 으로 조용히 통과할 수 있다 — 양성 대조.
    chk("B5_skip_filter_alive", (len(expect_singleton) + len(expect_unknown)) == 0 or
        (dist.get("SKIP_SINGLETON", 0) + dist.get("SKIP_UNKNOWN", 0)) >= 1,
        f"SKIP 발화 {dist.get('SKIP_SINGLETON', 0)}+{dist.get('SKIP_UNKNOWN', 0)} "
        f"(기대 대상 {len(expect_singleton)}+{len(expect_unknown)})")

    # ── [C] dry-run 무쓰기 ──
    print("\n[C] dry-run 부작용 0")
    after = _snapshot(CAND_DIR, RL_DIR, ACTIVE_DIR)
    added = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    touched = sorted(k for k in set(before) & set(after) if before[k] != after[k])
    chk("C1_no_new_file", not added, f"신규 {len(added)}건" + (f" 예: {added[:2]}" if added else ""))
    chk("C2_no_removed_file", not removed, f"소실 {len(removed)}건" + (f" 예: {removed[:2]}" if removed else ""))
    chk("C3_no_modified_file", not touched,
        f"변경 {len(touched)}건" + (f" 예: {touched[:2]}" if touched else ""))

    print(f"\nTOTAL: {PASS} pass / {FAIL} fail / {SKIP} skip")
    print(json.dumps({"test": "promotion_ladder_dryrun", "pass": PASS, "fail": FAIL,
                      "skip": SKIP, "total": PASS + FAIL,
                      "verdict_distribution": dist}, ensure_ascii=False))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
