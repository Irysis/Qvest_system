"""apply_direction_basis.py — factor_registry.json 의 방향(direction)을 '저장값 기준'으로 바로잡는 writer.

왜(2026-11-09 · decision_register FACTOR-DIRECTION-STORAGE-REPAIR-20261109):
  등록부 direction 은 소비자 전부(정렬 대체 경로 · registry 모드 · 결합용 뷰 · FF5 · 스마트베타 추적 · 발굴 탐색기)가
  저장된 Raw_Value 에 곱한다. 그런데 월간 빌더는 일부 팩터를 음수로 뒤집어 저장하고(예: D34 = −sd · D03 = −sd · D04 = −하방β),
  등록부는 그 팩터들의 방향을 원래 양(변동성 · β) 기준으로 적었다 → 그 팩터들이 거꾸로 정렬됐다. 실측: P2R04 방어 틸트
  D03 · D04 · D07 이 2000-06 ~ 2002-06 에 정렬값 대 저장값 순위 상관 −1.000(IC 36개월 미만 구간의 등록부 대체).
무엇을 쓰나(엔트리마다 · direction 바로 뒤에):
  direction_economic = definition 이 말하는 양의 이론 방향(사람이 쓰는 값)
  stored_sign        = 저장 Raw_Value = stored_sign × (definition 이 말하는 양) — 코드 감사로 확정(+1 / −1)
  direction_basis    = "stored_raw_value"
  direction          = direction_economic(stored_sign = +1) 또는 그 반대(stored_sign = −1) — 소비자가 쓰는 값
  direction_history  = 바뀐 엔트리만 [{date, from, to, reason, evidence, decision}] 덧붙임
입력: 감사 표 06_Registry/factor_direction_audit.json(schema factor_direction_audit_v1 · factors[name] = {stored_sign,
  direction_economic, monthly_src, stored_expr, reason}).
쓰기: 등록부 사본 둘(02_Infrastructure/factor_db/ · .cache/factor_db/) — apply_factor_dedup.R 과 같은 규약. 이 파일은 파이썬
  json.dumps(indent=2, ensure_ascii=False) + 끝 줄바꿈으로 바이트 왕복이 같다(2026-11-09 실측) → 바뀐 엔트리만 차이로 남는다.
  원자적 교체 · 재파싱 검사(엔트리 수 · 순서) · 두 사본 바이트 동일 단정. 멱등(두 번 돌려도 변화 없음).
사용: python -I apply_direction_basis.py [--audit PATH] [--dry-run] [--registry PATH ...]
"""
import json
import os
import sys
import tempfile
from datetime import date

ROOT = os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot")
AUDIT = os.path.join(ROOT, "06_Registry", "factor_direction_audit.json")
REGS = [os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json"),
        os.path.join(ROOT, ".cache", "factor_db", "factor_registry.json")]
DECISION = "FACTOR-DIRECTION-STORAGE-REPAIR-20261109"
DIRS = ("higher_better", "lower_better")
NEW_KEYS = ("direction_economic", "stored_sign", "direction_basis")


def flip(d):
    return "lower_better" if d == "higher_better" else "higher_better"


def stored_direction(d_econ, s):
    return d_econ if s == 1 else flip(d_econ)


def serialize(obj):
    return (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def apply(reg, audit, today):
    out, changes, missing, def_changes = {}, [], [], []
    for name, e in reg.items():
        a = audit.get(name)
        if a is None or not isinstance(e, dict):
            out[name] = e
            if isinstance(e, dict) and e.get("direction_basis") != "stored_raw_value":
                missing.append(name)
            continue
        s, de = a["stored_sign"], a["direction_economic"]
        if s not in (1, -1) or de not in DIRS:
            raise SystemExit(f"[direction_basis] 감사 값 불량: {name} stored_sign={s} direction_economic={de}")
        want = stored_direction(de, s)
        ne = {}
        newdef = a.get("definition_new")
        for k, v in e.items():
            if k in NEW_KEYS:
                continue
            if k == "definition" and newdef and v != newdef:
                ne["definition"] = newdef
                continue
            if k == "direction":
                ne["direction"] = want
                ne["direction_economic"] = de
                ne["stored_sign"] = s
                ne["direction_basis"] = "stored_raw_value"
                continue
            ne[k] = v
        if "direction" not in e:
            raise SystemExit(f"[direction_basis] direction 키 없음: {name}")
        if e["direction"] != want:
            hist = list(e.get("direction_history") or [])
            hist.append({"date": today, "from": e["direction"], "to": want, "decision": DECISION,
                         "reason": a.get("reason", ""), "evidence": a.get("monthly_src", ""),
                         "stored_expr": a.get("stored_expr", "")})
            ne["direction_history"] = hist
            changes.append((name, e["direction"], want, a.get("reason", "")))
        if newdef and e.get("definition") != newdef:
            dh = list(e.get("definition_history") or [])
            dh.append({"date": today, "from": e.get("definition"), "to": newdef, "decision": DECISION,
                       "reason": a.get("reason", "")})
            ne["definition_history"] = dh
            def_changes.append(name)
        out[name] = ne
    return out, changes, missing, def_changes


def atomic_write(path, data):
    d = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix=".reg_", suffix=".json", dir=d)
    with os.fdopen(fd, "wb") as fh:
        fh.write(data)
    chk = json.loads(open(tmp, encoding="utf-8").read())
    return tmp, chk


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # 시스템 파이썬 기본 출력 = cp949
    except Exception:
        pass
    args = sys.argv[1:]
    dry = "--dry-run" in args
    audit_path = args[args.index("--audit") + 1] if "--audit" in args else AUDIT
    regs = REGS
    if "--registry" in args:
        i = args.index("--registry") + 1
        regs = []
        while i < len(args) and not args[i].startswith("--"):
            regs.append(args[i]); i += 1
    A = json.load(open(audit_path, encoding="utf-8"))
    if A.get("schema") != "factor_direction_audit_v1":
        raise SystemExit(f"[direction_basis] 감사 표 schema 불일치: {A.get('schema')}")
    audit = A["factors"]
    present = [p for p in regs if os.path.exists(p)]
    if not present:
        raise SystemExit("[direction_basis] 등록부 없음")
    raws = [open(p, "rb").read() for p in present]
    if len(set(raws)) != 1:
        raise SystemExit("[direction_basis] 등록부 사본이 서로 다르다 — 먼저 맞춘 뒤 돌린다: " + ", ".join(present))
    reg = json.loads(raws[0].decode("utf-8"))
    if serialize(reg) != raws[0]:
        raise SystemExit("[direction_basis] 등록부가 json.dumps(indent=2) 왕복과 다르다 — 이 writer 로 쓰면 무관한 줄이 바뀐다")
    today = date.today().isoformat()
    new, changes, missing, def_changes = apply(reg, audit, today)
    print(f"[direction_basis] 엔트리 {len(reg)} · 감사 {len(audit)} · 방향 바뀜 {len(changes)} · 정의 문구 수리 {len(def_changes)} · 감사 밖(필드 없음) {len(missing)}")
    for n, a, b, why in changes:
        print(f"  {n}: {a} → {b} · {why[:90]}")
    if missing:
        print("  감사 밖:", ", ".join(missing[:20]), "…" if len(missing) > 20 else "")
    data = serialize(new)
    if data == raws[0]:
        print("[direction_basis] 변화 없음(멱등)")
        return
    if dry:
        print("[direction_basis] --dry-run — 쓰지 않음")
        return
    staged = []
    for p in present:
        tmp, chk = atomic_write(p, data)
        if list(chk.keys()) != list(reg.keys()):
            os.unlink(tmp)
            raise SystemExit(f"[direction_basis] 재파싱 엔트리 순서 · 집합 변화: {p}")
        staged.append((tmp, p))
    for tmp, p in staged:
        os.replace(tmp, p)
    after = [open(p, "rb").read() for p in present]
    if len(set(after)) != 1:
        raise SystemExit("[direction_basis] 쓴 뒤 사본이 서로 다르다")
    print(f"[direction_basis] 썼다: {len(present)}개 사본 · {len(changes)}개 방향 변경")


if __name__ == "__main__":
    main()
