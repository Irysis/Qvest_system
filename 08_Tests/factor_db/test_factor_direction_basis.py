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
  M1 돌연변이 — 빌더 사본에서 D34 의 음수화를 지우면 B3 가 D34 를 잡는다(검사가 죽지 않았음을 실증)
표준 라이브러리만 쓴다(배터리 해석기 = 시스템 파이썬).
"""
import glob
import json
import os
import re
import shutil
import sys
import tempfile

ROOT = os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot")
REG = os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")
REG_CACHE = os.path.join(ROOT, ".cache", "factor_db", "factor_registry.json")
AUDIT = os.path.join(ROOT, "06_Registry", "factor_direction_audit.json")
CODE = os.path.join(ROOT, "02_Infrastructure", "factor_db")
DIRS = ("higher_better", "lower_better")
NEG_DEF = re.compile(r"(?i)\bnegat|^\s*[-−]|\b(minus|negative of)\b")
PASS = FAIL = 0


def chk(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1; print(f"  [ok]   {name}")
    else:
        FAIL += 1; print(f"  [FAIL] {name} {detail}")


def _expr_after(s, i):
    depth, j = 0, i
    while j < len(s):
        c = s[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif c == "," and depth == 0:
            break
        j += 1
    return " ".join(s[i:j].split())


_DIV_NEG = re.compile(r"^\.?[A-Za-z_]*div[A-Za-z0-9_]*\(\s*[-−]")


def _is_neg(expr):
    """음수화 = 식이 '-' 로 시작 · 또는 나눗셈 도우미의 첫 인자가 '-' 로 시작(.sdiv(-(ni - ocf), ta) = −(ni − ocf)/ta)."""
    e = expr.strip().lstrip("(").strip()
    return e.startswith("-") or e.startswith("−") or bool(_DIV_NEG.match(e))


_BARE = re.compile(r"[A-Za-z_.][A-Za-z0-9_.]*")


def _resolve(s, expr, pos, depth=0):
    """식이 변수 이름이면 같은 파일에서 pos 직전 대입(:= · <- · = · list(X = y) 의 X = y)을 따라간다(최대 8단).
    음수화 = 마지막으로 닿은 식이 '-' 로 시작. NA 초기화(d01 <- d02 <- NA_real_)는 건너뛰고 그 앞 대입을 본다."""
    e = expr.strip().lstrip("(").strip()
    if not _BARE.fullmatch(e):
        return _is_neg(e)
    if depth >= 8:
        return None
    pat = re.compile(r"(?<![A-Za-z0-9_.$])" + re.escape(e) + r"\s*(?::=|<-|=)(?!=)\s*")
    cands = list(pat.finditer(s[:pos]))
    for a in reversed(cands):
        rhs = _expr_after(s, a.end())
        r = rhs.strip()
        if not r or r.startswith("NA") or _BARE.fullmatch(r.split("<-")[0].strip()) and "<-" in r:
            continue                                   # NA 초기화 · 사슬 대입의 가운데
        return _resolve(s, rhs, a.start(), depth + 1)
    return None


def code_negation(code_dir):
    """팩터 → True(음수화) | False | None(해결 못함). 직접 식 + 같은 파일 안 변수 추적(직전 대입)."""
    out = {}
    for fp in sorted(glob.glob(os.path.join(code_dir, "compute_*.R"))):
        s = open(fp, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'Factor_Name\s*=\s*"([A-Za-z0-9_]+)"\s*,\s*Raw_Value\s*=\s*', s):
            name, expr = m.group(1), _expr_after(s, m.end())
            if expr.startswith("NA_real_") or expr == "NA":
                continue
            res = _resolve(s, expr, m.start())
            old = out.get(name, "unset")
            out[name] = res if old in ("unset", res) else None   # 경로마다 부호가 다르면 해결 못함
    return out


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
    bad1 = [k for k, e in facs.items() if e.get("direction_basis") != "stored_raw_value" or e.get("stored_sign") not in (1, -1)
            or e.get("direction_economic") not in DIRS or e.get("direction") not in DIRS]
    chk(f"B1 엔트리 {len(facs)}개 모두 저장값 기준 필드(direction_basis · stored_sign · direction_economic)", not bad1, ", ".join(bad1[:10]))
    def want_dir(e):
        de = e.get("direction_economic")
        return de if e.get("stored_sign") == 1 else ("lower_better" if de == "higher_better" else "higher_better")
    bad2 = [k for k, e in facs.items() if k not in bad1 and e.get("direction") != want_dir(e)]
    chk("B2 불변식 direction = f(direction_economic, stored_sign)", not bad2, ", ".join(bad2[:10]))
    audit = json.load(open(AUDIT, encoding="utf-8"))["factors"]
    neg = code_negation(CODE)
    both = sum(1 for k, a in audit.items() if a.get("code_negated_at_audit") is not None and neg.get(k) is not None)
    bad3 = b3_drift(audit, neg)
    chk(f"B3 빌더 부호 드리프트 없음(감사 · 지금 둘 다 판정된 {both}개)", not bad3, "; ".join(bad3[:8]))
    bad5 = [k for k, e in facs.items() if k in audit and (e.get("stored_sign") != audit[k]["stored_sign"] or
            e.get("direction_economic") != audit[k]["direction_economic"] or e.get("direction") != audit[k]["direction_stored"])]
    miss5 = [k for k in facs if k not in audit]
    chk(f"B5 등록부 ↔ 감사 표 일치(엔트리 {len(facs)} · 감사 밖 {len(miss5)})", not bad5 and not miss5, ", ".join((bad5 + miss5)[:10]))
    same = os.path.exists(REG_CACHE) and open(REG, "rb").read() == open(REG_CACHE, "rb").read()
    chk("B4 등록부 사본 둘 바이트 동일", same)
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
