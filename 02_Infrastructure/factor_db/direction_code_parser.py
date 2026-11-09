"""direction_code_parser.py — 월간 빌더(compute_*.R)가 팩터 값을 음수로 뒤집어 저장하는지 코드에서 다시 읽는다.

왜(2026-11-09 · decision_register FACTOR-DIRECTION-STORAGE-REPAIR-20261109 · FACTOR-DIRECTION-TWO-VIEWS-20261109):
  등록부 방향은 '저장값 기준'이다(direction_basis = stored_raw_value). 빌더가 어떤 팩터를 −x 로 저장하는지가 바뀌면
  등록부 stored_sign · direction 도 같이 바뀌어야 한다. 이 판독기는 그 변화를 잡는 기준이다 — 상설 검사
  (08_Tests/factor_db/test_factor_direction_basis.py B3)와 야간 동기화(apply_direction_basis.py --sync)가 같은 판독기를 쓴다
  (두 곳이 따로 구현하면 갈라진다).
무엇을 읽나: `Factor_Name = "X", Raw_Value = <식>` 의 식이 '-' 로 시작하는지 · 나눗셈 도우미의 첫 인자가 '-' 로 시작하는지
  (.sdiv(-(ni - ocf), ta)) · 식이 변수면 같은 파일 안에서 직전 대입을 따라간다(최대 8단 · NA 초기화 건너뜀).
  판정 못 하면 None(경로마다 부호가 다르거나 식을 못 따라감). 뜻 판정('정의가 음수화를 말하나')은 하지 않는다 — NEG_DEF 는
  정의 문구가 음수화를 말하는지 보는 보조 정규식이다(자동 등재의 stored_sign 추정에만 쓴다 · 비소진적).
표준 라이브러리만 쓴다.
"""
import glob
import os
import re

NEG_DEF = re.compile(r"(?i)\bnegat|^\s*[-−]|\b(minus|negative of)\b")
_DIV_NEG = re.compile(r"^\.?[A-Za-z_]*div[A-Za-z0-9_]*\(\s*[-−]")
_BARE = re.compile(r"[A-Za-z_.][A-Za-z0-9_.]*")


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


def _is_neg(expr):
    """음수화 = 식이 '-' 로 시작 · 또는 나눗셈 도우미의 첫 인자가 '-' 로 시작(.sdiv(-(ni - ocf), ta) = −(ni − ocf)/ta)."""
    e = expr.strip().lstrip("(").strip()
    return e.startswith("-") or e.startswith("−") or bool(_DIV_NEG.match(e))


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
