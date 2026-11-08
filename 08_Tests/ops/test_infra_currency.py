# -*- coding: utf-8 -*-
"""test_infra_currency.py — 인프라 판 점검(infra_currency.py) · 최신화 계획(infra_update.py) 오프라인 시험 · 2026-11-08
네트워크 0 · 설치 0. 부팅 'Infra:' 줄 표시 규칙(최신 · 뒤처짐 · 보류 · 고정 · 오래됨 · 기록 없음)과 계획 분류(보류 · 라운드 고정 · 메이저 ·
공유 venv 는 메인에서만)를 양방향(발화해야 할 때 발화 · 하지 말아야 할 때 침묵)으로 잰다.
"""
import datetime as dt, json, os, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "ops"))
import infra_currency as ic  # noqa: E402
import infra_update as iu  # noqa: E402

P = F = 0


def ck(name, cond, info=""):
    global P, F
    if cond:
        P += 1; print("  PASS %s" % name)
    else:
        F += 1; print("  FAIL %s %s" % (name, info))


now = dt.datetime(2026, 11, 9, 6, 0, tzinfo=dt.timezone(dt.timedelta(hours=9)))
base = {"checked_at": "2026-11-09T05:40:00+09:00",
        "r": {"installed": "4.6.2", "latest": "4.6.2"}, "python": {"qvest_py": "3.15.2", "venv": "3.15.2", "latest": "3.15.2"},
        "venv_outdated": [], "syspy_outdated": [], "r_outdated": [], "rtools": {"status": "current"}, "pins": [], "pinned_outdated": []}


def D(**kw):
    d = json.loads(json.dumps(base)); d.update(kw); return d


# ① 기본 도우미
ck("vtuple 판 비교", ic.vtuple("4.6.2") > ic.vtuple("4.5.3") and ic.vtuple("2.15.0+cu132") == (2, 15, 0) and ic.vtuple("x") == ())
ck("norm PEP 503", ic.norm("Typing_Extensions") == ic.norm("typing-extensions") == ic.norm("typing.extensions"))
ck("major_jump", ic.major_jump("2.3.3", "3.1.1") and not ic.major_jump("1.9.0", "1.9.1"))
w = ic.parse_would_install("Collecting x\nWould install python-dateutil-4.0.0 torch-2.15.0+cu132 jsonschema-specifications-2025.9.1\n")
ck("parse_would_install 이름-판 분리", w == {"python-dateutil": "4.0.0", "torch": "2.15.0+cu132", "jsonschema-specifications": "2025.9.1"}, str(w))
ck("parse_would_install 없음 → 빈 사전", ic.parse_would_install("Requirement already satisfied") == {})
# user_env — 레지스트리에 없는 이름은 프로세스 환경으로 내려온다(레지스트리 쪽 우선은 HKCU 를 쓰지 않고는 잴 수 없어 제외)
_nm = "QVEST_INFRA_TEST_%d" % os.getpid()
os.environ[_nm] = "from-process"
ck("user_env 레지스트리 없음 → 프로세스 값", ic.user_env(_nm) == "from-process", ic.user_env(_nm))
del os.environ[_nm]
ck("user_env 둘 다 없음 → 빈 문자열", ic.user_env(_nm) == "")

# ② 부팅 줄 — 최신이면 ★ 없음 · 뒤처지면 ★(양방향)
l0 = ic.infra_line(D(), now=now)
ck("최신 → ★ 없음 · ✓ 표시", l0.startswith("Infra: R 4.6.2 ✓") and "★" not in l0, l0)
l1 = ic.infra_line(D(r={"installed": "4.5.2", "latest": "4.6.2"}), now=now)
ck("R 뒤처짐 → ★ · 'R 4.5.2→4.6.2'", "★최신화 필요" in l1 and "R 4.5.2→4.6.2" in l1, l1)
l2 = ic.infra_line(D(python={"qvest_py": "3.15.2", "venv": "3.12.10", "latest": "3.15.2"}), now=now)
ck("venv 기반 판 뒤처짐 → ★ · (venv 3.12.10)", "★최신화 필요" in l2 and "(venv 3.12.10)" in l2, l2)
held = [{"name": "lifelines", "installed": "0.30.0", "latest": "0.30.3", "upgradable": False, "major": False}]
l3 = ic.infra_line(D(venv_outdated=held), now=now)
ck("보류만 → ★ 없음 · 'venv 0(보류 1)'", "★" not in l3 and "venv 0(보류 1)" in l3, l3)
up = [{"name": "mpmath", "installed": "1.3.0", "latest": "1.4.1", "upgradable": True, "major": False},
      {"name": "pandas", "installed": "2.3.3", "latest": "3.1.1", "upgradable": True, "major": True}]
l4 = ic.infra_line(D(venv_outdated=up), now=now)
ck("올릴 것 있음 → ★ · 메이저 수", "★최신화 필요" in l4 and "venv 2(메이저 1)" in l4, l4)
l5 = ic.infra_line(D(r_outdated=[{"name": "otel", "installed": "0.2.0", "latest": "0.3.0", "major": False}]), now=now)
ck("R 패키지 바이너리 갱신 → ★ · 'R패키지 1'", "★최신화 필요" in l5 and "R패키지 1" in l5, l5)
l6 = ic.infra_line(D(checked_at="2026-11-07T05:40:00+09:00"), now=now)
ck("36시간 넘음 → ★오래됨", "★오래됨" in l6, l6)
ck("36시간 안 → 오래됨 없음", "오래됨" not in l0, l0)
ck("기록 없음 → '?(점검 기록 없음'", ic.infra_line(None).startswith("Infra: ?(점검 기록 없음"))
ck("조회 실패(None) → '?' 표시 · ★ 안 냄", "venv ?" in ic.infra_line(D(venv_outdated=None), now=now) and "★" not in ic.infra_line(D(venv_outdated=None), now=now))
l7 = ic.infra_line(D(pins=[{"round": "P2R05_distribution_target"}], pinned_outdated=[{"round": "P2R05", "kind": "R", "name": "arrow"}]), now=now)
ck("고정 라운드 · 걸림 수 표시", "고정 P2R05(걸림 1)" in l7, l7)

# ③ 열린 라운드 판 고정 읽기(가짜 루트)
with tempfile.TemporaryDirectory() as td:
    os.makedirs(os.path.join(td, "06_Registry")); os.makedirs(os.path.join(td, "r"))
    json.dump({"operational_pins": {"r_version": "R version 4.6.2", "packages": {"arrow": "26.0.0"}},
               "engines": {"python": {"ok": True, "python": "3.15.2", "torch": "2.15.0+cu132", "executable": "x"}}},
              open(os.path.join(td, "r", "prereg.json"), "w", encoding="utf-8"))
    json.dump({"programs": [{"rounds": [{"round_id": "RA", "status": "registered", "prereg": "r/prereg.json"},
                                        {"round_id": "RB", "status": "evaluated", "prereg": "r/prereg.json"}]}]},
              open(os.path.join(td, "06_Registry", "research_programs.json"), "w", encoding="utf-8"))
    pins = ic.open_round_pins(td)
    ck("registered 만 고정으로 읽음(evaluated 제외)", [p["round"] for p in pins] == ["RA"], str(pins))
    ck("고정 내용 = R 판 · R 패키지 · Python(ok · executable 제외)",
       pins and pins[0]["r_packages"] == {"arrow": "26.0.0"} and set(pins[0]["python"]) == {"python", "torch"}, str(pins))

# ④ 최신화 계획 분류(infra_update.plan)
d = D(venv_outdated=up + held + [{"name": "torch", "installed": "2.15.0", "latest": "2.16.0", "upgradable": True, "major": False}],
      r_outdated=[{"name": "arrow", "installed": "26.0.0", "latest": "26.1.0", "major": False},
                  {"name": "zoo", "installed": "1.9-1", "latest": "1.9-2", "major": False}],
      pins=[{"round": "RA", "r_packages": {"arrow": "26.0.0"}, "python": {"torch": "2.15.0"}}])
pl = iu.plan(d, {"venv", "rpkgs"}, include_pinned=False, include_major=False, role="main")
take_v = {i["name"] for i in pl["venv"]["take"]}; why_v = {i["name"]: i["why"] for i in pl["venv"]["skip"]}
ck("venv: 올릴 것 = mpmath 만", take_v == {"mpmath"}, str(take_v))
ck("venv: pandas = 메이저 · lifelines = 보류 · torch = 라운드 고정",
   why_v.get("pandas") == "메이저" and why_v.get("lifelines", "").startswith("보류") and why_v.get("torch") == "라운드 고정", str(why_v))
ck("rpkgs: arrow = 라운드 고정 · zoo = 올림",
   {i["name"] for i in pl["rpkgs"]["take"]} == {"zoo"} and pl["rpkgs"]["skip"][0]["why"] == "라운드 고정")
pl2 = iu.plan(d, {"venv"}, include_pinned=True, include_major=True, role="main")
ck("--include-pinned --include-major → pandas · torch 도 올림(보류는 여전히 제외)",
   {i["name"] for i in pl2["venv"]["take"]} == {"mpmath", "pandas", "torch"}, str([i["name"] for i in pl2["venv"]["take"]]))
pl3 = iu.plan(d, {"venv"}, include_pinned=False, include_major=False, role="secondary")
ck("노트북(secondary) → 공유 venv 안 바꿈", not pl3["venv"]["take"] and any(i["why"] == "공유 venv — 메인에서만" for i in pl3["venv"]["skip"]))

print("[test_infra_currency] PASS=%d FAIL=%d" % (P, F))
print(json.dumps({"test": "infra_currency", "pass": P, "fail": F, "total": P + F}))
sys.exit(1 if F else 0)
