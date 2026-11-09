"""test_factor_direction_basis.py — 등록부 방향이 '저장값 기준'인지 지키는 상설 검사(2026-11-09 · FACTOR-DIRECTION-STORAGE-REPAIR-20261109).

왜: 소비자(정렬 대체 · registry 모드 · 결합용 뷰 · 추적 보고서 · 발굴 탐색기)는 등록부 direction 을 저장된 Raw_Value 에 곱는다.
  월간 빌더가 값을 음수로 뒤집어 저장하는데 등록부가 원래 양 기준으로 방향을 적으면 그 팩터가 거꾸로 정렬된다(P2R04 방어 틸트
  D03 · D04 · D07 이 2000~2002 에 정렬값 대 저장값 순위 상관 −1.000 이었다).
검사:
  B1 엔트리마다 direction_basis = stored_raw_value · stored_sign ∈ {1, −1} · direction_economic ∈ {higher_better, lower_better}
  B2 불변식 direction = direction_economic(stored_sign 1) | 반대(stored_sign −1)
  B3 빌더 부호 드리프트 — 월간 빌더(compute_*.R)의 Raw_Value 식이 음수화인지(변수 사슬 · 나눗셈 도우미 안까지 추적)를 지금 코드에서
     다시 읽어 감사 표(06_Registry/factor_direction_audit.json)의 code_negated_at_audit 와 대조한다. 빌더 부호를 바꾸고 감사 · 등록부를
     안 고치면 걸린다(뜻 판정은 감사 표 몫 — 파서는 '정의가 음수화를 말하나'를 판정하지 않는다).
  B5 등록부 ↔ 감사 표 — stored_sign · direction_economic · direction 이 감사 표와 같다.
  B4 두 등록부 사본(02_Infrastructure · .cache) 바이트 동일
  B6 방어 방향(2026-11-09 두 방향 분리 · FACTOR-DIRECTION-TWO-VIEWS-20261109) — 위험 · 유동성 범위 계열(defense · risk · regime ·
     liquidity · leverage · size) 엔트리는 direction_defensive(저장값 기준) · direction_defensive_definition · 이유를 갖고(감사 표가
     null 이라 이유와 함께 적은 것만 예외) 불변식 direction_defensive = f(definition, stored_sign) 을 지킨다
  B7 기대수익 방향 근거 — direction_economic_basis ∈ {literature · literature_mixed_defensive_tiebreak · code_and_definition ·
     registry_original} · 문헌 근거면 인용 필수 · 동률 규칙(문헌이 갈리거나 없음)이면 기대수익 = 방어(definition 기준)
  B8 같은 양 일관성 — 감사 표 two_views.groups 의 같은 양(또는 정확히 반대 부호) 팩터끼리 기대수익 · 방어 방향이 같다(부호 반영)
  M1 돌연변이 — 빌더 사본에서 D34 의 음수화를 지우면 B3 가 D34 를 잡는다(검사가 죽지 않았음을 실증)
  M2 · M3 · M4 돌연변이 — 등록부 사본에서 방어 방향 한 개 뒤집기(B6) · 같은 양 무리의 기대수익 방향 한 개 뒤집기(B8) ·
     문헌 근거 지우기(B7)가 각각 잡힌다
표준 라이브러리만 쓴다(배터리 해석기 = 시스템 파이썬).
"""
import copy
import glob
import json
import os
import re
import shutil
import sys
import tempfile
from datetime import date, timedelta

ROOT = os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "factor_db"))
from direction_code_parser import code_negation  # noqa: E402 — 야간 동기화(apply_direction_basis.py --sync)와 같은 판독기
REG = os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")
REG_CACHE = os.path.join(ROOT, ".cache", "factor_db", "factor_registry.json")
AUDIT = os.path.join(ROOT, "06_Registry", "factor_direction_audit.json")
CODE = os.path.join(ROOT, "02_Infrastructure", "factor_db")
DIRS = ("higher_better", "lower_better")
SCOPE = ("defense", "risk", "regime", "liquidity", "leverage", "size")
BASES = ("literature", "literature_mixed_defensive_tiebreak", "code_and_definition", "registry_original")
GRACE_DAYS = 2      # 새로 등재된 팩터는 야간 동기화(daily_refresh [6f])가 필드를 채울 때까지 이 날수만큼 WARN(실패 아님)
PASS = FAIL = 0


def flip(d):
    return "lower_better" if d == "higher_better" else "higher_better"


def stored_dir(d, s):
    return d if s == 1 else flip(d)


def check_defensive(facs, audit):
    """B6 — 범위 계열은 방어 방향을 갖는다(감사 표가 이유와 함께 null 로 적은 것만 예외) · 불변식 · 이유."""
    bad = []
    for k, e in facs.items():
        dd, ds = e.get("direction_defensive_definition"), e.get("direction_defensive")
        if dd is None:
            if ds is not None:
                bad.append(f"{k}(definition 없이 저장값 방어 방향만)")
            elif e.get("category") in SCOPE:
                a = audit.get(k, {})
                if not (a.get("defensive_definition") is None and (a.get("defensive_reason") or "").strip()):
                    bad.append(f"{k}(범위 계열인데 방어 방향 없음 · 감사 표 이유도 없음)")
            continue
        if dd not in DIRS or ds != stored_dir(dd, e.get("stored_sign")):
            bad.append(f"{k}(불변식 direction_defensive = f(definition, stored_sign))")
        elif not (e.get("direction_defensive_reason") or "").strip():
            bad.append(f"{k}(방어 방향 이유 없음)")
    return bad


def check_basis(facs):
    """B7 — 근거 종류 어휘 · 문헌 근거 인용 · 동률 규칙(기대수익 = 방어)."""
    bad = []
    for k, e in facs.items():
        b = e.get("direction_economic_basis")
        if b not in BASES:
            bad.append(f"{k}(basis {b})")
            continue
        if b in ("literature", "literature_mixed_defensive_tiebreak") and not (e.get("direction_economic_evidence") or "").strip():
            bad.append(f"{k}(문헌 근거인데 인용 없음)")
        if b == "literature_mixed_defensive_tiebreak" and e.get("direction_economic") != e.get("direction_defensive_definition"):
            bad.append(f"{k}(동률 규칙인데 기대수익 ≠ 방어)")
    return bad


def check_groups(facs, groups):
    """B8 — 같은 양 무리: 기준 양으로 옮긴 기대수익 · 방어 방향이 모두 같다."""
    bad = []
    for g in groups:
        ref_e, ref_d = set(), set()
        for m in g.get("members", []):
            e = facs.get(m.get("name"))
            s = m.get("sign_vs_ref")
            if e is None or s not in (1, -1):
                bad.append(f"{g.get('id')}({m.get('name')} 없음 · 부호 {s})")
                continue
            ref_e.add(stored_dir(e.get("direction_economic"), s))
            if e.get("direction_defensive_definition"):
                ref_d.add(stored_dir(e.get("direction_defensive_definition"), s))
        if len(ref_e) > 1:
            bad.append(f"{g.get('id')}(기대수익 방향 불일치)")
        if len(ref_d) > 1:
            bad.append(f"{g.get('id')}(방어 방향 불일치)")
    return bad


def chk(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1; print(f"  [ok]   {name}")
    else:
        FAIL += 1; print(f"  [FAIL] {name} {detail}")


def b3_drift(audit, neg):
    """감사 시점 코드 음수화(code_negated_at_audit)와 지금 코드 재도출이 다른 팩터 — 둘 다 판정된 것만 본다."""
    bad = []
    for name, a in audit.items():
        was, now = a.get("code_negated_at_audit"), neg.get(name)
        if was is None or now is None:
            continue
        if bool(was) != bool(now):
            bad.append(f"{name}(감사 {was} → 지금 {now})")
    return bad


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # 배터리 해석기 기본 출력 = cp949
    except Exception:
        pass
    reg = json.load(open(REG, encoding="utf-8"))
    facs = {k: v for k, v in reg.items() if isinstance(v, dict)}
    cutoff = (date.today() - timedelta(days=GRACE_DAYS)).isoformat()
    def young(k):           # 등재 GRACE_DAYS 안 — 야간 동기화가 아직 안 돌았을 수 있다(경고만)
        ad = str(((facs.get(k) or {}).get("lifecycle") or {}).get("added_date") or "")
        return ad >= cutoff
    bad1 = [k for k, e in facs.items() if e.get("direction_basis") != "stored_raw_value" or e.get("stored_sign") not in (1, -1)
            or e.get("direction_economic") not in DIRS or e.get("direction") not in DIRS]
    warn1 = [k for k in bad1 if young(k)]
    if warn1:
        print(f"  [WARN] 새 등재 {len(warn1)}개가 아직 방향 필드 없음(야간 동기화 대기 · {GRACE_DAYS}일 넘으면 실패): {', '.join(warn1[:8])}")
    bad1 = [k for k in bad1 if k not in warn1]
    chk(f"B1 엔트리 {len(facs)}개 모두 저장값 기준 필드(direction_basis · stored_sign · direction_economic)", not bad1, ", ".join(bad1[:10]))
    bad1 = bad1 + warn1
    def want_dir(e):
        de = e.get("direction_economic")
        return de if e.get("stored_sign") == 1 else ("lower_better" if de == "higher_better" else "higher_better")
    bad2 = [k for k, e in facs.items() if k not in bad1 and e.get("direction") != want_dir(e)]
    chk("B2 불변식 direction = f(direction_economic, stored_sign)", not bad2, ", ".join(bad2[:10]))
    A = json.load(open(AUDIT, encoding="utf-8"))
    audit = A["factors"]
    groups = (A.get("two_views") or {}).get("groups") or []
    neg = code_negation(CODE)
    both = sum(1 for k, a in audit.items() if a.get("code_negated_at_audit") is not None and neg.get(k) is not None)
    bad3 = b3_drift(audit, neg)
    chk(f"B3 빌더 부호 드리프트 없음(감사 · 지금 둘 다 판정된 {both}개)", not bad3, "; ".join(bad3[:8]))
    bad5 = [k for k, e in facs.items() if k in audit and (e.get("stored_sign") != audit[k]["stored_sign"] or
            e.get("direction_economic") != audit[k]["direction_economic"] or e.get("direction") != audit[k]["direction_stored"] or
            e.get("direction_economic_basis") != audit[k].get("economic_basis", "registry_original") or
            e.get("direction_defensive_definition") != audit[k].get("defensive_definition"))]
    miss5 = [k for k in facs if k not in audit]
    warn5 = [k for k in miss5 if young(k)]
    if warn5:
        print(f"  [WARN] 새 등재 {len(warn5)}개가 아직 감사 표 밖(야간 동기화 대기): {', '.join(warn5[:8])}")
    miss5 = [k for k in miss5 if k not in warn5]
    chk(f"B5 등록부 ↔ 감사 표 일치(엔트리 {len(facs)} · 감사 밖 {len(miss5)})", not bad5 and not miss5, ", ".join((bad5 + miss5)[:10]))
    same = os.path.exists(REG_CACHE) and open(REG, "rb").read() == open(REG_CACHE, "rb").read()
    chk("B4 등록부 사본 둘 바이트 동일", same)
    n_def = sum(1 for e in facs.values() if e.get("direction_defensive"))
    bad6 = check_defensive(facs, audit)
    chk(f"B6 방어 방향 — 범위 계열 보유 · 불변식 · 이유(방어 방향 {n_def}개)", not bad6 and n_def > 0, ", ".join(bad6[:10]))
    bad7 = check_basis(facs)
    chk("B7 기대수익 방향 근거 — 어휘 · 인용 · 동률 규칙", not bad7, ", ".join(bad7[:10]))
    bad8 = check_groups(facs, groups)
    chk(f"B8 같은 양 일관성(무리 {len(groups)}개)", not bad8 and len(groups) > 0, ", ".join(bad8[:10]))
    # 돌연변이 — 등록부 사본(메모리)에서 하나씩 어긋나게 해 각 검사가 잡는지
    m2 = copy.deepcopy(facs)
    k2 = next((k for k, e in m2.items() if e.get("direction_defensive")), None)
    if k2:
        m2[k2]["direction_defensive"] = flip(m2[k2]["direction_defensive"])
    chk("M2 돌연변이(방어 방향 한 개 뒤집기) — B6 가 잡는다", k2 is not None and any(x.startswith(k2 + "(") for x in check_defensive(m2, audit)))
    m3 = copy.deepcopy(facs)
    g3 = next((g for g in groups if len(g.get("members", [])) >= 2 and all(m.get("name") in m3 for m in g["members"])), None)
    if g3:
        k3 = g3["members"][0]["name"]
        m3[k3]["direction_economic"] = flip(m3[k3]["direction_economic"])
    chk("M3 돌연변이(같은 양 무리의 기대수익 방향 한 개 뒤집기) — B8 이 잡는다",
        g3 is not None and any(x.startswith(g3["id"] + "(기대수익") for x in check_groups(m3, groups)))
    m4 = copy.deepcopy(facs)
    k4 = next((k for k, e in m4.items() if e.get("direction_economic_basis") == "literature"), None)
    if k4:
        m4[k4]["direction_economic_evidence"] = ""
    chk("M4 돌연변이(문헌 근거 지우기) — B7 이 잡는다", k4 is not None and any(x.startswith(k4 + "(") for x in check_basis(m4)))
    tmp = tempfile.mkdtemp(prefix="dirbasis_")
    try:
        for fp in glob.glob(os.path.join(CODE, "compute_*.R")):
            shutil.copy(fp, tmp)
        p = os.path.join(tmp, "compute_defense.R")
        s = open(p, encoding="utf-8", errors="replace").read()
        old = 'Factor_Name = "D34_RealVol_21d",\n                                Raw_Value = -sd_ret)'
        hit = s.count(old) == 1
        if hit:
            open(p, "w", encoding="utf-8").write(s.replace(old, old.replace("-sd_ret", "sd_ret")))
        mut = b3_drift(audit, code_negation(tmp))
        chk("M1 돌연변이(D34 음수화 제거) — 치환 성사 ∧ B3 가 D34 를 잡는다", hit and any(x.startswith("D34_RealVol_21d(") for x in mut),
            f"hit={hit} · {mut[:3]}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n[test_factor_direction_basis] {PASS} passed, {FAIL} failed")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
