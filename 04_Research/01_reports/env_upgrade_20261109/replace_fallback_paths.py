"""replace_fallback_paths.py — 살아 있는 코드의 대체 경로 문자열 R-4.5.2 → R-4.6.2 · Python312 → Python315 (2026-11-08 환경 최신화)
기본 = 계획만(바뀔 줄 출력). --apply 로 쓴다(원래 줄바꿈 · 인코딩 그대로 — 바이트 단위 치환).

뺀다: .claude/worktrees(에이전트 사본) · _archive · 05_Production(수정 금지) · 01_Literature · 99_Archive ·
      끝난 핀 라운드(P2R03 · P2R04 · P3R03 — 파일 지문 고정) · 다른 세션이 고치는 중인 파일(--skip 로 넘김).
경로 문맥만 바꾼다: 'R/R-4.5.2' · 'R\\R-4.5.2' · 'Python/Python312' · 'Python\\Python312' (산문 'Python312(pandas 없음)' 은 그대로).
"""
import os, re, subprocess, sys

root = sys.argv[1]
apply = "--apply" in sys.argv
skip = set()
if "--skip" in sys.argv:
    skip = {s.replace("\\", "/") for s in sys.argv[sys.argv.index("--skip") + 1].split(",") if s}

EXT = (".sh", ".R", ".py", ".bat", ".ps1", ".cmd", ".json")
ZONES = ("02_Infrastructure", "04_Research/programs", "08_Tests")
EXCLUDE = re.compile(r"(^|/)(\.claude/worktrees|_archive[^/]*|05_Production|01_Literature|99_Archive)(/|$)"
                     r"|04_Research/programs/(P2_DEFENSE/P2R03|P2_DEFENSE/P2R04|P3_CONSTRUCTION/P3R03)")
PATS = [(re.compile(rb"(R[/\\]{1,2})R-4\.5\.2"), rb"\1R-4.6.2"),
        (re.compile(rb"(Python[/\\]{1,2})Python312"), rb"\1Python315")]

changed_files, changed_lines = 0, 0
for z in ZONES:
    for d, _, files in os.walk(os.path.join(root, z)):
        for f in files:
            if not f.endswith(EXT):
                continue
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root).replace("\\", "/")
            if EXCLUDE.search(rel) or rel in skip:
                continue
            b = open(p, "rb").read()
            nb = b
            for pat, rep in PATS:
                nb = pat.sub(rep, nb)
            if nb == b:
                continue
            changed_files += 1
            old_lines, new_lines = b.split(b"\n"), nb.split(b"\n")
            for i, (o, n) in enumerate(zip(old_lines, new_lines)):
                if o != n:
                    changed_lines += 1
                    if not apply:
                        print("%s:%d: %s" % (rel, i + 1, n.decode("utf-8", "replace").strip()[:150]))
            if apply:
                open(p, "wb").write(nb)
print("files=%d lines=%d %s" % (changed_files, changed_lines, "APPLIED" if apply else "(plan only)"))
