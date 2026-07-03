#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#==============================================================================
# boot_status_smoke.py - Qvest v8.1.4 부팅 상태-라인 스모크 가드
#
# 목적: /qvest 부팅 하단 상태 라인을 산출하는 모든 리더를 실행해
#   (a) 예외 없음  (b) '?'/SKIP/placeholder 없음  을 단언한다.
#   새 상태 라인이 이 (Windows/OneDrive) 머신에서 검증 없이 출고돼
#   사용자가 부팅 때마다 깨짐을 발견하던 회귀 클래스를 *추가 시점*에 차단.
#
# 커버하는 회귀 2종(2026-06-21 실측 진단):
#   A) 백슬래시 $PROJECT x  python3 -c "...open('$PATH')..."  -> \U unicodeescape
#      SyntaxError -> 침묵 '?'  (Axioms/Cache_core 라인)
#      => 런타임 검사로는 못 잡음(boot 셸 따옴표 문제) -> [정적 린트]로 차단.
#   B) 생산자/소비자 JSON 스키마 드리프트(list vs dict) -> reader .get() AttributeError
#      -> fail-soft SKIP  (ResearchPool 라인)  => [런타임 검사]로 차단.
#
# 설계: 리더별 fail-soft(스모크 자체는 절대 부팅 중단 안 함).
#       exit code = FAIL 개수  => pre-commit / CI 게이트로도 사용 가능.
#       부팅에서는 advisory(loud) 한 줄로 surface.
#
# Usage: python3 boot_status_smoke.py [PROJECT_ROOT]
#   PROJECT_ROOT 생략 시 env QM_ROOT / CLAUDE_PROJECT_DIR / cwd 순.
#==============================================================================
import os
import re
import sys
import json
import glob
import importlib.util

RESULTS = []  # (name, ok: bool, detail: str)


def _root(argv):
    for a in argv:
        if not a.startswith("--") and os.path.isdir(a):
            return a
    for e in ("QM_ROOT", "CLAUDE_PROJECT_DIR"):
        v = os.environ.get(e)
        if v and os.path.isdir(v):
            return v
    return os.getcwd()


def _run(name, fn):
    try:
        ok, detail = fn()
    except Exception as e:
        ok, detail = False, "EXCEPTION %s: %s" % (type(e).__name__, e)
    RESULTS.append((name, bool(ok), str(detail)))


# ---- [런타임] ResearchPool 리더: collect/render 예외 없음 + 'reader 오류' 없음 -----------
def chk_research_pool(root):
    path = os.path.join(root, "02_Infrastructure", "ops", "research_pool_status.py")
    if not os.path.isfile(path):
        return True, "reader 부재(신규 클론 SKIP 정상)"
    spec = importlib.util.spec_from_file_location("rps_smoke", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    o = m.collect(root)          # 스키마 드리프트(class B) 발생 시 여기서 예외 -> _run이 잡음
    lines = m.render(o)
    if any("reader 오류" in l for l in lines):
        return False, "리더 예외: " + lines[0][:90]
    # available=False(데이터 없음)는 정상 SKIP; 그 외엔 첫 라인 요약
    return True, lines[0][:80]


# ---- [런타임] Axioms counts: documented_active 정수 산출 ----------------------------------
def chk_axioms(root):
    p = os.path.join(root, "qepm", "memory", "axioms", "axiom_sot_map.json")
    if not os.path.isfile(p):
        return False, "axiom_sot_map.json 부재"
    d = json.load(open(p, encoding="utf-8"))
    ax = [a for a in (d.get("axioms", []) or []) if a.get("documented_active")]
    n = len(ax)
    if n <= 0:
        return False, "documented_active 0 (산출 실패 의심)"
    by = {}
    for a in ax:
        by[a.get("enforcement_mode", "?")] = by.get(a.get("enforcement_mode", "?"), 0) + 1
    return True, "documented=%d (doc=%d/block=%d/adv=%d)" % (
        n, by.get("documented", 0), by.get("block", 0), by.get("advisory", 0))


# ---- [런타임] Cache_core: axiom_core.json 정수 -------------------------------------------
def chk_cache_core(root):
    p = os.path.join(root, ".cache", "axiom_core.json")
    if not os.path.isfile(p):
        return True, "axiom_core.json 부재(MISSING 정상)"
    d = json.load(open(p, encoding="utf-8"))
    n = len(d.get("axioms", []))
    return (n > 0), "count=%d" % n


# ---- [런타임] DataFresh: cache_freshness_latest.json parse + summary ----------------------
def chk_datafresh(root):
    p = os.path.join(root, "qepm", "observability", "cache_freshness_latest.json")
    if not os.path.isfile(p):
        return True, "freshness json 부재(SKIP 정상)"
    d = json.load(open(p, encoding="utf-8"))
    s = d.get("summary")
    return isinstance(s, dict), ("summary OK" if isinstance(s, dict) else "summary 부재/형식오류")


# ---- [정적 린트] boot 셸의 inline-path python -c 안티패턴(class A 차단) -------------------
#   python3 -c "...$PROJECT.../open('$PATH')..." 처럼 경로 $변수를 -c 문자열에 직접 박은 라인.
#   백슬래시 Windows 경로에서 \U unicodeescape로 침묵 실패. -> env-var 전달로 교체해야 함.
_INLINE_PC = re.compile(r"""python3?\s+-c\s+(['"])(.*?)\1""")
_PATHVAR = re.compile(r"\$\{?(PROJECT|[A-Z_]*(?:PATH|MAP|JSON|DIR))\b")


def chk_inline_path_lint(root):
    targets = [os.path.join(root, "02_Infrastructure", "ops", "bootstrap.sh")]
    offenders = []
    for f in targets:
        if not os.path.isfile(f):
            continue
        for i, line in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
            if line.lstrip().startswith("#"):
                continue  # 셸 주석(예시 텍스트 포함)은 실행 라인이 아니므로 제외
            for m in _INLINE_PC.finditer(line):
                code = m.group(2)
                if "os.environ" in code:
                    continue
                if _PATHVAR.search(code) or "open('$" in line or 'open("$' in line:
                    offenders.append("%s:%d" % (os.path.basename(f), i))
    if offenders:
        return False, "inline-path python -c 안티패턴: " + ", ".join(offenders[:6])
    return True, "boot 셸 inline-path 0건 (env-var 전달 규율 준수)"


def main():
    root = _root(sys.argv[1:])
    _run("ResearchPool", lambda: chk_research_pool(root))
    _run("Axioms", lambda: chk_axioms(root))
    _run("Cache_core", lambda: chk_cache_core(root))
    _run("DataFresh", lambda: chk_datafresh(root))
    _run("InlinePathLint", lambda: chk_inline_path_lint(root))

    fails = [r for r in RESULTS if not r[1]]
    for name, ok, detail in RESULTS:
        print("  [%s] %-15s %s" % ("OK  " if ok else "FAIL", name, detail))
    n = len(RESULTS)
    p = n - len(fails)
    if fails:
        print("[boot] status-line smoke: DEGRADED - %d/%d OK, broken: %s" % (
            p, n, ", ".join(f[0] for f in fails)))
    else:
        print("[boot] status-line smoke: %d/%d readers OK" % (p, n))
    return len(fails)


if __name__ == "__main__":
    sys.exit(main())
