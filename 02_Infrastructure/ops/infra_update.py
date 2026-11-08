# -*- coding: utf-8 -*-
"""infra_update.py — 인프라 패키지 최신화(venv · 시스템 Python · R 사용자 라이브러리) · 2026-11-08 도훈
"부팅 시에 점검해서 R, 파이썬 버전, 각종 패키지 등 인프라 최신화 시킬 수 있도록 해줘".

기본 = 계획만. --apply 로 실행. 입력 = infra_currency.py 결과(.cache/machine/infra_currency_<HOST>.json · 오래됐거나 --refresh 면 다시 잰다).
규칙(바꾸는 것이 측정을 깨지 않게):
- 올릴 수 있는 것(upgradable — pip 모의 해석이 실제로 그 판을 깔려는 것)만. 의존 상한에 걸린 보류(held)는 손대지 않는다.
- 열린 라운드(사전등록 registered)가 판을 고정한 패키지는 건너뛴다 — --include-pinned 로만(그 뒤 라운드 재고정 필요).
- 메이저 판 변경은 건너뛴다 — --include-major 로만(코드 호환 확인 필요 · 예 pandas 2 → 3).
- venv 는 OneDrive 로 두 기계가 같이 쓴다 → 메인(machines.conf role main)에서만 바꾼다.
- 바꾸기 전 스냅샷(pip freeze · R 패키지 폴더 사본) → 바꾼 뒤 검증(pip check · import · R library) → 실패면 되돌린다.
- R · Python '판 자체'(예 4.6 → 4.7 · 3.15 → 3.16)는 하지 않는다 — 04_Research/01_reports/env_upgrade_20261109/PLAN.md 절차
  (관리자 설치 UAC · 경로 전환 · venv 재생성 · 회귀 시험 · 라운드 재고정).
★Claude 도구 세션 안에서는 %LOCALAPPDATA%(시스템 Python · R 사용자 라이브러리) 쓰기가 가상화돼 가짜 설치가 된다 —
  CLAUDECODE 환경이면 venv 밖 범위의 --apply 를 거부한다(일회용 예약 작업이나 보통 PowerShell 에서).

사용: python infra_update.py [--apply] [--scope venv,syspy,rpkgs] [--include-pinned] [--include-major] [--refresh]
종료 코드: 0 = 계획 출력 또는 모두 성공 · 1 = 일부 실패 → 되돌림 · 2 = 입력 · 환경 문제 · 3 = 되돌림도 실패(사람 조치).
"""
from __future__ import annotations

import argparse, datetime as dt, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import infra_currency as ic  # noqa: E402

CORE_IMPORTS = ["numpy", "pandas", "pyarrow", "scipy", "sklearn", "torch", "openpyxl"]
IMPORT_CHECK = ("import importlib, sys\nbad = []\nfor m in sys.argv[1:]:\n    try:\n        importlib.import_module(m)\n"
                "    except Exception as e:\n        bad.append(m + ': ' + str(e))\nprint('BAD', bad) if bad else print('IMPORT_OK')\n"
                "sys.exit(1 if bad else 0)\n")


def role_of(root, host):
    r = os.environ.get("QVEST_MACHINE_ROLE", "")
    if r:
        return r
    try:
        for ln in open(os.path.join(root, "02_Infrastructure/ops/machine/machines.conf"), encoding="utf-8"):
            p = ln.split()
            if len(p) == 3 and p[0] == "machine" and p[1].upper() == host:
                return p[2]
    except OSError:
        pass
    return "secondary"


def pinned_names(d):
    s = {"R": set(), "py": set()}
    for p in d.get("pins", []):
        s["R"] |= set(p.get("r_packages", {}))
        s["py"] |= {ic.norm(k) for k in p.get("python", {})}
    return s


def plan(d, scopes, include_pinned, include_major, role):
    pins = pinned_names(d)
    out = {}
    for sc, key, kind in (("venv", "venv_outdated", "py"), ("syspy", "syspy_outdated", "py"), ("rpkgs", "r_outdated", "R")):
        if sc not in scopes:
            continue
        rows = d.get(key) or []
        take, skip = [], []
        for i in rows:
            why = None
            if i.get("held_manual"):
                why = "수동 보류(%s)" % ic.HOLDS_FILE
            elif not i.get("upgradable", True):
                why = "보류(의존 상한)"
            elif not include_pinned and ((kind == "R" and i["name"] in pins["R"]) or (kind == "py" and ic.norm(i["name"]) in pins["py"])):
                why = "라운드 고정"
            elif not include_major and i.get("major"):
                why = "메이저"
            elif sc == "venv" and role != "main":
                why = "공유 venv — 메인에서만"
            (skip if why else take).append(dict(i, why=why))
        out[sc] = {"take": take, "skip": skip}
    return out


def py_apply(exe, items, snap, label, log):
    frz = os.path.join(snap, "%s_freeze.txt" % label)
    rc, txt = ic.run([exe, "-m", "pip", "freeze", "--disable-pip-version-check"], 300)
    if rc != 0:
        return 2, "freeze 실패"
    open(frz, "w", encoding="utf-8").write(txt)
    specs = ["%s==%s" % (i["name"], i.get("to") or i["latest"]) for i in items]
    rc, txt = ic.run([exe, "-m", "pip", "install", "--only-binary=:all:", "--disable-pip-version-check"] + specs, 1800)
    log.write(txt[-4000:])
    ok = rc == 0
    if ok:
        rc2, t2 = ic.run([exe, "-m", "pip", "check", "--disable-pip-version-check"], 300)
        mods = CORE_IMPORTS if label == "venv" else ["openpyxl", "numpy", "pypdf", "jsonschema"]
        rc3, t3 = ic.run([exe, "-c", IMPORT_CHECK] + mods, 600)
        ok = rc2 == 0 and rc3 == 0
        log.write("\n[check] pip check rc=%s · import rc=%s %s\n" % (rc2, rc3, t3.strip()[-300:]))
    if ok:
        return 0, "올림 %d: %s" % (len(items), ", ".join(specs))
    rc4, t4 = ic.run([exe, "-m", "pip", "install", "-r", frz, "--disable-pip-version-check"], 1800)
    log.write("\n[rollback] rc=%s %s\n" % (rc4, t4[-1500:]))
    return (1 if rc4 == 0 else 3), "실패 → 되돌림 rc=%s" % rc4


def r_apply(rs, items, snap, log):
    names = [i["name"] for i in items]
    code = """
lib <- .libPaths()[1]; snap <- %r; pk <- %s
dir.create(file.path(snap, "rlib"), recursive = TRUE, showWarnings = FALSE)
for (p in pk) if (dir.exists(file.path(lib, p))) file.copy(file.path(lib, p), file.path(snap, "rlib"), recursive = TRUE)
options(repos = c(CRAN = "%s"), install.packages.compile.from.source = "never")
ok <- tryCatch({ utils::install.packages(pk, lib = lib, type = "binary", quiet = TRUE); TRUE }, error = function(e) { cat("ERR", conditionMessage(e), "\\n"); FALSE })
bad <- character(0)
if (ok) for (p in pk) { r <- try(suppressPackageStartupMessages(library(p, character.only = TRUE, lib.loc = lib)), silent = TRUE); if (inherits(r, "try-error")) bad <- c(bad, p) }
if (!ok || length(bad)) {
  for (p in pk) { if (dir.exists(file.path(snap, "rlib", p))) { unlink(file.path(lib, p), recursive = TRUE); file.copy(file.path(snap, "rlib", p), lib, recursive = TRUE) } }
  cat("ROLLBACK", paste(bad, collapse = ","), "\\n"); quit(status = 1)
}
for (p in pk) cat("UPDATED", p, as.character(packageVersion(p, lib.loc = lib)), "\\n")
""" % (snap.replace("\\", "/"), "c(%s)" % ", ".join("'%s'" % n for n in names), ic.CRAN_REPO)
    f = tempfile.NamedTemporaryFile("w", suffix=".R", delete=False, encoding="utf-8")
    f.write(code); f.close()
    try:
        rc, txt = ic.run([rs, f.name], 3600)
    finally:
        os.unlink(f.name)
    log.write(txt[-4000:])
    if rc == 0:
        return 0, "올림 %d: %s" % (len(names), ", ".join(names))
    return 1, "실패 → 되돌림(%s)" % txt.strip()[-200:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("QM_ROOT", os.path.dirname(os.path.dirname(HERE))))
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--scope", default="venv,syspy,rpkgs")
    ap.add_argument("--include-pinned", action="store_true")
    ap.add_argument("--include-major", action="store_true")
    ap.add_argument("--refresh", action="store_true")
    a = ap.parse_args()
    root = a.root.replace("\\", "/")
    host = os.environ.get("COMPUTERNAME", "unknown").upper()
    jf = os.path.join(root, ".cache", "machine", "infra_currency_%s.json" % host)
    stale = True
    if os.path.exists(jf):
        try:
            d = json.load(open(jf, encoding="utf-8"))
            t = dt.datetime.fromisoformat(d["checked_at"])
            stale = (dt.datetime.now(t.tzinfo) - t).total_seconds() > 36 * 3600
        except Exception:  # noqa: BLE001
            stale = True
    if a.refresh or stale:
        rc, txt = ic.run([sys.executable, os.path.join(HERE, "infra_currency.py"), "--root", root], 1800)
        print(txt.strip()[-300:])
    try:
        d = json.load(open(jf, encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        print("infra_update: 점검 결과를 못 읽음 %s" % e)
        return 2
    ic.apply_holds(d, ic.load_holds(root))   # 점검 결과가 보류 파일보다 먼저 만들어졌어도 지금의 보류를 따른다
    scopes = {s.strip() for s in a.scope.split(",") if s.strip()}
    role = role_of(root, host)
    P = plan(d, scopes, a.include_pinned, a.include_major, role)
    for sc, v in P.items():
        print("[%s] 올릴 것 %d · 건너뜀 %d" % (sc, len(v["take"]), len(v["skip"])))
        for i in v["take"]:
            print("   + %s %s → %s" % (i["name"], i["installed"], i.get("to") or i["latest"]))
        for i in v["skip"]:
            print("   - %s %s → %s (%s)" % (i["name"], i["installed"], i["latest"], i["why"]))
    if not a.apply:
        print("(계획만 — --apply 로 실행)")
        return 0
    if os.environ.get("CLAUDECODE") and scopes & {"syspy", "rpkgs"} and any(P[s]["take"] for s in scopes & {"syspy", "rpkgs"} if s in P):
        print("infra_update: Claude 도구 세션에서는 시스템 Python · R 사용자 라이브러리를 바꾸지 않는다(가상화 — 가짜 설치). 일회용 예약 작업이나 보통 PowerShell 에서 다시.")
        return 2
    snap = os.path.join(root, ".cache", "machine", "infra_snapshots", "%s_%s" % (host, dt.datetime.now().strftime("%Y%m%d_%H%M%S")))
    os.makedirs(snap, exist_ok=True)
    logp = os.path.join(root, ".cache", "scheduler_logs", "infra_update_%s.log" % host)
    os.makedirs(os.path.dirname(logp), exist_ok=True)
    worst, notes = 0, []
    with open(logp, "a", encoding="utf-8") as log:
        log.write("\n===== %s infra_update apply scopes=%s snap=%s\n" % (dt.datetime.now().isoformat(timespec="seconds"), ",".join(sorted(scopes)), snap))
        if P.get("venv", {}).get("take"):
            rc, n = py_apply(os.path.join(root, ".venv_qvest_ml", "Scripts", "python.exe"), P["venv"]["take"], snap, "venv", log); worst = max(worst, rc); notes.append("venv " + n)
        if P.get("syspy", {}).get("take"):
            rc, n = py_apply(ic.user_env("QVEST_PY"), P["syspy"]["take"], snap, "syspy", log); worst = max(worst, rc); notes.append("syspy " + n)
        if P.get("rpkgs", {}).get("take"):
            rc, n = r_apply(ic.find_rscript(), P["rpkgs"]["take"], snap, log); worst = max(worst, rc); notes.append("rpkgs " + n)
        log.write("SUMMARY rc=%d · %s\n" % (worst, " | ".join(notes) or "할 일 없음"))
    print("SUMMARY rc=%d · %s" % (worst, " | ".join(notes) or "할 일 없음"))
    ic.run([sys.executable, os.path.join(HERE, "infra_currency.py"), "--root", root], 1800)   # 결과 다시 잼 — 부팅 줄 갱신
    return worst


if __name__ == "__main__":
    sys.exit(main())
