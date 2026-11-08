# -*- coding: utf-8 -*-
"""infra_currency.py — 인프라 판 점검(R · Rtools · Python · venv · 시스템 Python · R 패키지) · 2026-11-08 도훈
"부팅 시에 점검해서 R, 파이썬 버전, 각종 패키지 등 인프라 최신화 시킬 수 있도록 해줘".

무엇: 이 기계에 깔린 판과 공식 최신판(CRAN VERSION-INFO.dcf · python.org API)을 대조하고, venv · 시스템 Python(QVEST_PY) ·
R 사용자 라이브러리의 오래된 패키지를 센다. 열린(사전등록 registered) 라운드가 고정한 판(operational_pins · engines.python)을
읽어, 바꾸면 그 라운드가 '판 불일치'로 막히는 항목을 따로 표시한다.
결과 = .cache/machine/infra_currency_<HOST>.json (원자 쓰기). 부팅(boot_lean.sh `Infra:` 줄)은 이 파일만 읽는다 — 부팅에서 네트워크 0.

왜 매일 따로 도는가: 오래된 패키지 조회는 네트워크로 1~2분 걸린다 — 부팅(≈5초)에 넣지 않는다. 예약 작업 Qvest_InfraCurrency
(period local — 기계마다 자기 판을 잰다)가 매일 돈다. ★Claude 도구 세션 안에서 돌려도 읽기만 하므로 결과는 같다.

최신화 자체는 이 파일이 하지 않는다 — infra_update.py(패키지 · 고정 존중 · 스냅샷 · 검증 · 되돌림)와
R · Python 판 올리기 절차(04_Research/01_reports/env_upgrade_20261109/PLAN.md)가 한다.

사용: python infra_currency.py [--out PATH] [--no-network] [--skip-outdated] [--root ROOT]
종료 코드 0 = 기록함(뒤처짐이 있어도 0) · 2 = 기록 실패.
"""
from __future__ import annotations

import argparse, datetime as dt, glob, json, os, re, shutil, subprocess, sys, tempfile, urllib.request

CRAN_VERSION_INFO = "https://cran.r-project.org/src/base/VERSION-INFO.dcf"
CRAN_RTOOLS = "https://cran.r-project.org/bin/windows/Rtools/"
PY_RELEASES = "https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false"
CRAN_REPO = "https://cloud.r-project.org"


def vtuple(v):
    """'4.6.2' · '3.15.2' · '2.15.0+cu132' → 비교용 정수 튜플(앞의 숫자만)."""
    m = re.match(r"^\s*(\d+(?:\.\d+)*)", str(v or ""))
    return tuple(int(x) for x in m.group(1).split(".")) if m else ()


def norm(name):
    """PyPI 이름 정규화(PEP 503) — 'Jinja2' · 'typing_extensions' · 'python.dateutil' 비교용."""
    return re.sub(r"[-_.]+", "-", str(name)).lower()


def major_jump(a, b):
    ta, tb = vtuple(a), vtuple(b)
    return bool(ta and tb and ta[0] != tb[0])


def run(cmd, timeout=300):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as e:  # noqa: BLE001 — 점검기는 실패를 기록하고 계속한다
        return -1, "%s: %s" % (type(e).__name__, e)


MIRRORS = {"https://cran.r-project.org/": "https://cloud.r-project.org/"}   # CRAN 본 서버 시간 초과(11-08 실측 WinError 10060) → 클라우드 미러


def fetch(url, timeout=30):
    last = None
    for u in [url] + [url.replace(a, b) for a, b in MIRRORS.items() if url.startswith(a)]:
        try:
            with urllib.request.urlopen(u, timeout=timeout) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001 — 다음 출처로
            last = e
    raise last


def user_env(name):
    """사용자 환경 변수 — 레지스트리(HKCU\\Environment) 값을 먼저 본다(예약 작업이 실제로 쓰는 값).
    Claude 앱 · 오래 켜 둔 셸은 시작 때 환경을 들고 있어 경로 전환(switch_env.ps1) 뒤에도 옛 판을 가리킨다
    (11-08 실측: 앱 세션 PATH 에 R 4.5.2 · Python312 가 먼저 · QVEST_RSCRIPT 없음) — 프로세스 값만 보면 거짓 '뒤처짐'이 난다."""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
            v = winreg.QueryValueEx(k, name)[0]
        if v:
            return os.path.expandvars(str(v))
    except Exception:  # noqa: BLE001 — 윈도가 아니거나 값이 없다 → 프로세스 환경
        pass
    return os.environ.get(name, "")


def find_rscript():
    c = [user_env("QVEST_RSCRIPT"), shutil.which("Rscript") or ""]
    c += sorted(glob.glob("C:/Program Files/R/R-*/bin/Rscript.exe"), key=lambda p: vtuple(p.split("R-")[-1]), reverse=True)
    for p in c:
        for q in ((p, p + ".exe") if p else ()):
            if os.path.isfile(q):
                return q
    return ""


def r_installed(rs):
    rc, out = run([rs, "--version"], 60) if rs else (-1, "")
    m = re.search(r"version (\d+\.\d+\.\d+)", out)
    return m.group(1) if m else None


def r_latest():
    t = fetch(CRAN_VERSION_INFO)
    rel = re.search(r"^Release:\s*(\S+)", t, re.M)
    date = re.search(r"^Date:\s*(\S+)", t, re.M)
    return (rel.group(1) if rel else None), (date.group(1) if date else None)


def rtools_state():
    have = sorted(os.path.basename(p) for p in glob.glob("C:/rtools4*") if os.path.isdir(p))
    try:
        listed = sorted(set(re.findall(r"rtools(4\d)", fetch(CRAN_RTOOLS))), key=int)
        latest = "rtools" + listed[-1] if listed else None
    except Exception:  # noqa: BLE001
        latest = None
    return {"installed": have, "latest": latest,
            "status": "unknown" if not latest else ("current" if latest in have else "behind")}


def py_version(exe):
    rc, out = run([exe, "--version"], 60) if exe and os.path.isfile(exe) else (-1, "")
    m = re.search(r"Python (\d+\.\d+\.\d+)", out)
    return m.group(1) if m else None


def py_latest():
    d = json.loads(fetch(PY_RELEASES, 60))
    vs = [re.match(r"Python (\d+\.\d+\.\d+)$", x.get("name", "")) for x in d]
    vs = [m.group(1) for m in vs if m and m.group(1).startswith("3.")]
    return max(vs, key=vtuple) if vs else None


def parse_would_install(text):
    """pip --dry-run 출력의 'Would install a-1.0 python-dateutil-4.0.0 torch-2.15.0+cu132' → {정규화 이름: 판}."""
    m = re.search(r"Would install (.*)", text or "")
    out = {}
    for tok in (m.group(1).split() if m else []):
        mm = re.match(r"^(.+)-(\d[^-]*)$", tok)
        if mm:
            out[norm(mm.group(1))] = mm.group(2)
    return out


def pip_outdated(exe):
    if not exe or not os.path.isfile(exe):
        return None, "python 없음"
    rc, out = run([exe, "-m", "pip", "list", "--outdated", "--format=json", "--disable-pip-version-check"], 600)
    i = out.find("[")
    if rc != 0 or i < 0:
        return None, out.strip()[-200:]
    try:
        items = json.loads(out[i:out.rfind("]") + 1])
    except ValueError as e:
        return None, "json %s" % e
    rows = [{"name": x["name"], "installed": x["version"], "latest": x["latest_version"],
             "major": major_jump(x["version"], x["latest_version"])} for x in items]
    if rows:
        # 실제로 올릴 수 있는가 = pip 모의 해석이 그 판(또는 더 새 판)을 설치하려는가. 의존 상한에 걸린 것은 held(보류) —
        #   예 11-08: lifelines 0.30.3 은 pandas<3 · mpmath 1.4 는 sympy 상한 → 부팅마다 '★최신화 필요'가 거짓으로 뜨지 않게 가른다.
        rc2, out2 = run([exe, "-m", "pip", "install", "--dry-run", "--upgrade", "--only-binary=:all:", "--disable-pip-version-check"]
                        + [r["name"] for r in rows], 600)
        would = parse_would_install(out2)
        for r in rows:
            w = would.get(norm(r["name"]))
            r["upgradable"] = bool(w) and vtuple(w) > vtuple(r["installed"])
            r["to"] = w if r["upgradable"] else None
        # pip 모의 해석은 '요청한 패키지 + 그 의존'만 풀고 이미 깔린 다른 패키지(역의존)의 상한은 보지 않는다 —
        #   11-08 실측: mpmath 1.4.1 = 'Would install' 인데 sympy 1.14.0 이 mpmath<1.4 를 요구(올리면 torch 가 쓰는 sympy 요구가 깨진다).
        #   → 대상 해석기 안에서 깔린 배포판의 활성 요구 조건을 모아 새 판을 허용하지 않는 역의존이 있으면 보류로 돌린다.
        blocked = reverse_dep_blocks(exe, {norm(r["name"]): r["to"] for r in rows if r.get("upgradable")})
        for r in rows:
            b = blocked.get(norm(r["name"]))
            if b:
                r["upgradable"], r["to"], r["held_by"] = False, None, b
    return rows, None


_REVDEP_CODE = r'''
import json, sys, importlib.metadata as m
from pip._vendor.packaging.requirements import Requirement
from pip._vendor.packaging.utils import canonicalize_name
cand = json.loads(sys.argv[1]); out = {}
for d in m.distributions():
    for rs in (d.requires or []):
        try:
            q = Requirement(rs)
        except Exception:
            continue
        if q.marker is not None and not q.marker.evaluate({"extra": ""}):
            continue                                   # extra 전용 요구(예: scipy 의 test) · 이 환경에 해당 없는 요구는 제외
        n = canonicalize_name(q.name)
        if n in cand and str(q.specifier) and not q.specifier.contains(cand[n], prereleases=True):
            out.setdefault(n, []).append("%s %s requires %s" % (d.metadata["Name"], d.version, rs))
print("REVDEP" + json.dumps(out))
'''


def reverse_dep_blocks(exe, cand):
    """{정규화 이름: 새 판} 중 이미 깔린 배포판의 요구 조건이 그 판을 허용하지 않는 것 → {이름: [막는 요구 …]}. 조회 실패 = 빈 사전(막지 않음)."""
    if not cand or not exe or not os.path.isfile(exe):
        return {}
    rc, out = run([exe, "-c", _REVDEP_CODE, json.dumps(cand)], 300)
    i = out.find("REVDEP")
    if rc != 0 or i < 0:
        return {}
    try:
        return json.loads(out[i + 6:].strip().splitlines()[0])
    except ValueError:
        return {}


def r_outdated(rs):
    if not rs:
        return None, "Rscript 없음"
    # type = 'binary' — 새 판이 소스로만 나와 아직 Windows 바이너리가 없는 것(11-08 실측 otel · permute)은 '올릴 것'으로 세지 않는다
    code = ("op <- tryCatch(old.packages(lib.loc = .libPaths()[1], repos = '%s', type = 'binary'), error = function(e) {cat('ERR', conditionMessage(e)); NULL});"
            "if (!is.null(op)) for (i in seq_len(nrow(op))) cat('OLD', op[i, 'Package'], op[i, 'Installed'], op[i, 'ReposVer'], '\\n');"
            "cat('NLIB', nrow(installed.packages(lib.loc = .libPaths()[1])), '\\n')") % CRAN_REPO
    f = tempfile.NamedTemporaryFile("w", suffix=".R", delete=False, encoding="utf-8")
    f.write(code); f.close()
    try:
        rc, out = run([rs, f.name], 600)
    finally:
        os.unlink(f.name)
    if "ERR" in out and "OLD" not in out:
        return None, out.strip()[-200:]
    items = [{"name": a, "installed": b, "latest": c, "major": major_jump(b, c)}
             for a, b, c in re.findall(r"^OLD (\S+) (\S+) (\S+)", out, re.M)]
    n = re.search(r"NLIB (\d+)", out)
    return {"items": items, "n_lib": int(n.group(1)) if n else None}, None


def open_round_pins(root):
    """사전등록(registered)인데 아직 결과가 없는 라운드의 판 고정 — 바꾸면 그 라운드 사전 점검이 막힌다."""
    out = []
    try:
        reg = json.load(open(os.path.join(root, "06_Registry/research_programs.json"), encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return out
    for p in reg.get("programs", []):
        for r in p.get("rounds", []) or []:
            if str(r.get("status", "")).lower() != "registered" or not r.get("prereg"):
                continue
            try:
                pre = json.load(open(os.path.join(root, r["prereg"]), encoding="utf-8"))
            except Exception:  # noqa: BLE001
                continue
            op = pre.get("operational_pins", {}) or {}
            py = (pre.get("engines", {}) or {}).get("python", {}) or {}
            out.append({"round": r.get("round_id") or r.get("id"), "prereg": r["prereg"],
                        "r_version": op.get("r_version"), "r_packages": op.get("packages", {}) or {},
                        "python": {k: v for k, v in py.items() if k not in ("ok", "executable")}})
    return out


HOLDS_FILE = "06_Registry/infra_holds.json"
HOLD_KEYS = {"R": "r_outdated", "venv": "venv_outdated", "syspy": "syspy_outdated"}


def load_holds(root):
    """수동 판 보류(06_Registry/infra_holds.json) — 사람이 확인한 사유(예: 판을 올리면 측정 정의가 조용히 바뀜)로 묶은 판. 파일 없음 · 깨짐 = 보류 없음."""
    try:
        d = json.load(open(os.path.join(root, HOLDS_FILE), encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return []
    return [h for h in (d.get("holds") or []) if isinstance(h, dict) and h.get("kind") in HOLD_KEYS and h.get("name")]


def apply_holds(d, holds):
    """보류 항목을 '올릴 수 없음'으로 표시(upgradable=False · held_manual=사유) — 부팅 줄은 (보류 n)으로 세고 infra_update 는 건너뛴다."""
    for h in holds:
        for i in d.get(HOLD_KEYS[h["kind"]]) or []:
            if (i["name"] == h["name"]) if h["kind"] == "R" else (norm(i["name"]) == norm(h["name"])):
                i["upgradable"], i["to"], i["held_manual"] = False, None, h.get("reason") or "수동 보류"
    return d


def infra_line(d, now=None, stale_h=36):
    """부팅 한 줄 — boot_lean.sh 와 시험이 같은 함수를 쓴다(표시 규칙 단일 출처)."""
    if not isinstance(d, dict) or "checked_at" not in d:
        return "Infra: ?(점검 기록 없음 — Qvest_InfraCurrency)"
    try:
        t = dt.datetime.fromisoformat(d["checked_at"])
        now = now or dt.datetime.now(t.tzinfo)
        age_h = (now - t).total_seconds() / 3600.0
    except Exception:  # noqa: BLE001
        age_h = None
    R, P = d.get("r", {}), d.get("python", {})
    parts, need = [], False
    if R.get("installed") and R.get("latest"):
        ok = vtuple(R["installed"]) >= vtuple(R["latest"]); need |= not ok
        parts.append("R %s%s" % (R["installed"], " ✓" if ok else "→%s" % R["latest"]))
    else:
        parts.append("R ?")
    qp, vp, lp = P.get("qvest_py"), P.get("venv"), P.get("latest")
    if qp and lp:
        ok = vtuple(qp) >= vtuple(lp) and (not vp or vtuple(vp) >= vtuple(lp)); need |= not ok
        parts.append("Python %s%s" % (qp, " ✓" if ok else "→%s" % lp) + ("" if vp == qp else "(venv %s)" % vp))
    else:
        parts.append("Python ?")
    for key, label in (("venv_outdated", "venv"), ("syspy_outdated", "시스템Py"), ("r_outdated", "R패키지")):
        x = d.get(key)
        if x is None:
            parts.append("%s ?" % label)
            continue
        up = [i for i in x if i.get("upgradable", True)]          # R 은 바이너리 있는 것만 들어오므로 전부 올릴 수 있음
        held, mj = len(x) - len(up), sum(1 for i in up if i.get("major"))
        need |= len(up) > 0
        parts.append("%s %d%s%s" % (label, len(up), "(메이저 %d)" % mj if mj else "", "(보류 %d)" % held if held else ""))
    rt = d.get("rtools", {})
    if rt.get("status") == "behind":
        need = True; parts.append("Rtools→%s" % rt.get("latest"))
    pins = d.get("pins", [])
    pinned = d.get("pinned_outdated", [])
    tail = []
    if pins:
        tail.append("고정 %s%s" % ("·".join(str(p["round"]).split("_")[0] for p in pins), "(걸림 %d)" % len(pinned) if pinned else ""))
    if age_h is not None:
        tail.append("점검 %s%s" % (d["checked_at"][5:16].replace("T", " "), " ★오래됨" if age_h > stale_h else ""))
    head = "Infra: ★최신화 필요 — " if need else "Infra: "
    return head + " · ".join(parts) + (" | " + " · ".join(tail) if tail else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("QM_ROOT", os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
    ap.add_argument("--out")
    ap.add_argument("--no-network", action="store_true")
    ap.add_argument("--skip-outdated", action="store_true")
    a = ap.parse_args()
    root = a.root.replace("\\", "/")
    host = os.environ.get("COMPUTERNAME", "unknown").upper()
    out = a.out or os.path.join(root, ".cache", "machine", "infra_currency_%s.json" % host)
    d = {"schema": "infra_currency_v1", "host": host, "checked_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"), "errors": []}
    rs = find_rscript()
    d["r"] = {"rscript": rs, "installed": r_installed(rs),
              "all_installed": sorted((os.path.basename(os.path.dirname(os.path.dirname(p))) for p in glob.glob("C:/Program Files/R/R-*/bin/Rscript.exe")), key=lambda s: vtuple(s[2:]))}
    venv = os.path.join(root, ".venv_qvest_ml", "Scripts", "python.exe")
    qpy = user_env("QVEST_PY")
    d["python"] = {"qvest_py_path": qpy, "qvest_py": py_version(qpy), "venv": py_version(venv)}
    if not a.no_network:
        for k, fn in (("r", r_latest), ("python", py_latest)):
            try:
                if k == "r":
                    d["r"]["latest"], d["r"]["latest_date"] = fn()
                else:
                    d["python"]["latest"] = fn()
            except Exception as e:  # noqa: BLE001
                d["errors"].append("%s latest: %s" % (k, e))
        d["rtools"] = rtools_state()
    if not a.skip_outdated and not a.no_network:
        d["venv_outdated"], e1 = pip_outdated(venv)
        d["syspy_outdated"], e2 = pip_outdated(qpy)
        ro, e3 = r_outdated(rs)
        d["r_outdated"] = ro["items"] if ro else None
        d["r"]["n_user_lib"] = ro.get("n_lib") if ro else None
        d["errors"] += [e for e in (e1, e2, e3) if e]
    d["pins"] = open_round_pins(root)
    pinned = []
    for p in d["pins"]:
        for i in d.get("r_outdated") or []:
            if i["name"] in p["r_packages"]:
                pinned.append({"round": p["round"], "kind": "R", "name": i["name"]})
        for i in d.get("venv_outdated") or []:
            if norm(i["name"]) in {norm(k) for k in p["python"]}:
                pinned.append({"round": p["round"], "kind": "venv", "name": i["name"]})
    d["pinned_outdated"] = pinned
    d["holds"] = load_holds(root)
    apply_holds(d, d["holds"])
    d["line"] = infra_line(d)
    try:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=1)
        os.replace(tmp, out)
    except OSError as e:
        print("infra_currency: 기록 실패 %s" % e, file=sys.stderr)
        return 2
    print(d["line"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
