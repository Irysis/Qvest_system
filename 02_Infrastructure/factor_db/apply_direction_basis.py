"""apply_direction_basis.py — factor_registry.json 의 방향(direction)을 '저장값 기준'으로 바로잡는 writer.

왜(2026-11-09 · decision_register FACTOR-DIRECTION-STORAGE-REPAIR-20261109):
  등록부 direction 은 소비자 전부(정렬 대체 경로 · registry 모드 · 결합용 뷰 · FF5 · 스마트베타 추적 · 발굴 탐색기)가
  저장된 Raw_Value 에 곱한다. 그런데 월간 빌더는 일부 팩터를 음수로 뒤집어 저장하고(예: D34 = −sd · D03 = −sd · D04 = −하방β),
  등록부는 그 팩터들의 방향을 원래 양(변동성 · β) 기준으로 적었다 → 그 팩터들이 거꾸로 정렬됐다. 실측: P2R04 방어 틸트
  D03 · D04 · D07 이 2000-06 ~ 2002-06 에 정렬값 대 저장값 순위 상관 −1.000(IC 36개월 미만 구간의 등록부 대체).
무엇을 쓰나(엔트리마다 · direction 바로 뒤에):
  direction_economic          = definition 이 말하는 양의 기대수익 방향(문헌 · 사람이 쓰는 값)
  direction_economic_basis    = 그 방향의 근거 종류(literature · literature_mixed_defensive_tiebreak · code_and_definition ·
                                registry_original — 2026-11-09 두 방향 분리 · decision_register FACTOR-DIRECTION-TWO-VIEWS-20261109)
  direction_economic_evidence = 근거 인용(있을 때만)
  stored_sign                 = 저장 Raw_Value = stored_sign × (definition 이 말하는 양) — 코드 감사로 확정(+1 / −1)
  direction_basis             = "stored_raw_value"
  direction                   = direction_economic(stored_sign = +1) 또는 그 반대(stored_sign = −1) — 소비자가 쓰는 값
  direction_defensive         = 방어 방향(저장값 기준 · 위험 · 유동성 계열만 · 위기 하락 노출↓ · 상승 참여↑ 쪽 = higher)
  direction_defensive_definition / direction_defensive_reason = 그 방향의 definition 기준 값 · 이유
  direction_history · direction_defensive_history = 바뀐 엔트리만 [{date, from, to, reason, evidence, decision}] 덧붙임
입력: 감사 표 06_Registry/factor_direction_audit.json(schema factor_direction_audit_v1 | v2 · factors[name] = {stored_sign,
  direction_economic, monthly_src, stored_expr, reason, [economic_basis, economic_evidence, defensive_definition, defensive_reason,
  change_decision, change_reason]}).
쓰기: 등록부 사본 둘(02_Infrastructure/factor_db/ · .cache/factor_db/) — apply_factor_dedup.R 과 같은 규약. 이 파일은 파이썬
  json.dumps(indent=2, ensure_ascii=False) + 끝 줄바꿈으로 바이트 왕복이 같다(2026-11-09 실측) → 바뀐 엔트리만 차이로 남는다.
  원자적 교체 · 재파싱 검사(엔트리 수 · 순서) · 두 사본 바이트 동일 단정. 멱등(두 번 돌려도 변화 없음).
사용: python -I apply_direction_basis.py [--audit PATH] [--dry-run] [--registry PATH ...]

★야간 동기화(--sync · 2026-11-09 · 도훈 'C안으로 수정된 정책도 추후 팩터 DB 업데이트에 자동으로 반영되게끔') —
  일일 체인 daily_refresh.sh [6f] 가 매일 부른다. 새 팩터는 등록부에 여러 길로 들어온다(add_factor.R 줄 단위 덧붙임 · 세션이 고친
  compute_*.R · 등록부를 통째로 다시 쓰는 R 도구). 이 모드가 그 길 전부를 같은 규칙으로 맞춘다:
  ① 감사 표에 없는 새 엔트리 → 감사 표에 자동 등재(stored_sign = 엔트리가 이미 적은 값 · 없으면 코드 판독기 + 정의 문구 · 판독 못 하면 +1
     '정의 = 저장값' 가정) · 기대수익 방향은 등재자가 쓴 direction(저장값 기준)을 그대로 둔다(소비자 동작 불변) · 근거 = registry_original ·
     위험 · 유동성 범위 계열이면 방어 방향 '판정 대기'(방어 보기에서는 빠진다 = 안전한 기본값) → 판정 대기 목록
  ② 등록부 direction 이 감사 표와 다르면(누가 손으로 바꿨거나 R 도구가 덮음) 고치지 않고 '충돌'로 경보(감사 표가 정본 — 바꾸려면 감사 표로)
  ③ 빌더 부호 드리프트(코드 판독기 재도출 ≠ 감사 시점) → 경보(뜻 판정이 필요해 자동 수리하지 않는다)
  ④ 두 사본이 다르면 엔트리 합집합으로 맞춘다(같은 이름 다른 값 = 충돌 경보 · 쓰지 않음)
  ⑤ 서식이 왕복과 다르면(R 도구가 다시 씀) 같은 뜻으로 정규화해 쓴다 · 읽은 뒤 파일이 바뀌면 쓰지 않는다(낙관적 동시성)
  출력: .cache/factor_direction_pending.json(added · pending_defensive · conflicts · drift · copies) · 종료 0 정상 · 3 경보 · 4 동시 변경(다음 밤)
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
DECISION_TWO = "FACTOR-DIRECTION-TWO-VIEWS-20261109"
DIRS = ("higher_better", "lower_better")
SCOPE = ("defense", "risk", "regime", "liquidity", "leverage", "size")   # 방어 방향을 두는 위험 · 유동성 계열(TWO-VIEWS)
PENDING = os.path.join(ROOT, ".cache", "factor_direction_pending.json")
BASES = ("literature", "literature_mixed_defensive_tiebreak", "code_and_definition", "registry_original")
SCHEMAS = ("factor_direction_audit_v1", "factor_direction_audit_v2")
NEW_KEYS = ("direction_economic", "direction_economic_basis", "direction_economic_evidence", "stored_sign", "direction_basis",
            "direction_defensive", "direction_defensive_definition", "direction_defensive_reason")


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
        basis = a.get("economic_basis", "registry_original")
        if basis not in BASES:
            raise SystemExit(f"[direction_basis] 감사 economic_basis 어휘 밖: {name} {basis}")
        ev = a.get("economic_evidence") or ""
        if basis in ("literature", "literature_mixed_defensive_tiebreak") and not ev.strip():
            raise SystemExit(f"[direction_basis] 문헌 근거 방향인데 economic_evidence 가 비었다: {name}")
        dd = a.get("defensive_definition")
        if dd is not None and dd not in DIRS:
            raise SystemExit(f"[direction_basis] 감사 defensive_definition 불량: {name} {dd}")
        want = stored_direction(de, s)
        want_def = stored_direction(dd, s) if dd else None
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
                ne["direction_economic_basis"] = basis
                if ev.strip():
                    ne["direction_economic_evidence"] = ev
                ne["stored_sign"] = s
                ne["direction_basis"] = "stored_raw_value"
                if dd:
                    ne["direction_defensive"] = want_def
                    ne["direction_defensive_definition"] = dd
                    ne["direction_defensive_reason"] = a.get("defensive_reason", "")
                continue
            ne[k] = v
        if "direction" not in e:
            raise SystemExit(f"[direction_basis] direction 키 없음: {name}")
        if e["direction"] != want:
            hist = list(e.get("direction_history") or [])
            hist.append({"date": today, "from": e["direction"], "to": want, "decision": a.get("change_decision", DECISION),
                         "reason": a.get("change_reason") or a.get("reason", ""), "evidence": ev or a.get("monthly_src", ""),
                         "stored_expr": a.get("stored_expr", "")})
            ne["direction_history"] = hist
            changes.append((name, e["direction"], want, a.get("change_reason") or a.get("reason", "")))
        if e.get("direction_defensive") is not None and e.get("direction_defensive") != want_def:
            dh = list(e.get("direction_defensive_history") or [])
            dh.append({"date": today, "from": e.get("direction_defensive"), "to": want_def, "decision": DECISION_TWO,
                       "reason": a.get("defensive_reason", "")})
            ne["direction_defensive_history"] = dh
            changes.append((name + "[방어]", e.get("direction_defensive"), want_def, a.get("defensive_reason", "")))
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


def auto_audit_entry(name, e, code_neg, today, neg_def):
    """감사 표에 없는 새 엔트리의 감사 항목. 소비자가 쓰는 direction(저장값 기준)은 바꾸지 않는다."""
    d = e.get("direction")
    if d not in DIRS:
        return None, f"direction 어휘 밖({d})"
    if e.get("direction_basis") == "stored_raw_value" and e.get("stored_sign") in (1, -1) and e.get("direction_economic") in DIRS:
        s, de, sb = e["stored_sign"], e["direction_economic"], "entry_declared"
        if stored_direction(de, s) != d:
            return None, "엔트리가 적은 stored_sign · direction_economic 이 direction 과 맞지 않음"
    else:
        if code_neg is None:
            s, sb = 1, "assumed_definition_is_stored"      # add_factor 템플릿 · 엔진 패널 = 정의 그대로 저장
        else:
            s, sb = (1 if bool(code_neg) == bool(neg_def.search(e.get("definition") or "")) else -1), "auto_parser"
        de = stored_direction(d, s)
    a = {"stored_sign": s, "direction_economic": de, "direction_stored": d,
         "economic_basis": e.get("direction_economic_basis") if e.get("direction_economic_basis") in BASES else "registry_original",
         "stored_sign_basis": sb, "code_negated_at_audit": code_neg, "monthly_src": "", "stored_expr": "",
         "reason": f"자동 등재 {today}(야간 동기화) — direction 은 등재자가 쓴 저장값 기준 값 그대로 · stored_sign = {sb}",
         "auto_added": today}
    if e.get("category") in SCOPE:
        a["defensive_definition"] = None
        a["defensive_reason"] = f"자동 등재 {today} — 방어 방향 판정 대기(판정 전에는 방어 보기에서 빠진다)"
        a["pending_defensive"] = True
    return a, None


def sync(regs, audit_path, code_dir, pending_out, dry=False, today=None, _before_replace=None):
    """야간 동기화(모듈 머리 주석 ①~⑤). 반환 = (rc, 보고 dict). rc 0 정상 · 3 경보 · 4 동시 변경 · 2 오류."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:                                    # python -I 는 스크립트 폴더를 sys.path 에 넣지 않는다
        sys.path.insert(0, here)
    from direction_code_parser import NEG_DEF, code_negation
    today = today or date.today().isoformat()
    rep = {"at": today, "added": [], "pending_defensive": [], "conflicts": [], "drift": [], "copies": "same",
           "normalized": False, "wrote": False, "errors": []}
    present = [p for p in regs if os.path.exists(p)]
    if not present:
        rep["errors"].append("등록부 없음")
        _write_pending(pending_out, rep)                        # 지난 밤 결과가 남아 정상처럼 읽히지 않게
        return 2, rep
    raws = [open(p, "rb").read() for p in present]
    try:
        parsed = [json.loads(r.decode("utf-8")) for r in raws]
    except Exception as ex:                                     # 깨진 JSON 은 고치지 않는다(사람 몫)
        rep["errors"].append(f"등록부 파싱 실패: {ex}")
        _write_pending(pending_out, rep)
        return 2, rep
    reg = parsed[0]
    if len(set(raws)) > 1:
        clash = sorted(k for p in parsed[1:] for k in (set(reg) & set(p)) if reg[k] != p[k])
        if clash:
            rep["copies"] = "conflict"
            rep["errors"].append("두 사본의 같은 이름 엔트리 값이 다르다: " + ", ".join(clash[:12]))
            _write_pending(pending_out, rep)
            return 3, rep
        merged = dict(reg)
        for p in parsed[1:]:
            for k, v in p.items():
                if k not in merged:
                    merged[k] = v
        reg = merged
        rep["copies"] = "union"
    rep["normalized"] = serialize(parsed[0]) != raws[0]
    A = json.load(open(audit_path, encoding="utf-8"))
    if A.get("schema") not in SCHEMAS:
        rep["errors"].append(f"감사 표 schema 불일치: {A.get('schema')}")
        _write_pending(pending_out, rep)
        return 2, rep
    audit = A["factors"]
    neg = code_negation(code_dir)
    conflict_names = set()
    for name, e in reg.items():
        if not isinstance(e, dict):
            continue
        a = audit.get(name)
        if a is None:
            a, why = auto_audit_entry(name, e, neg.get(name), today, NEG_DEF)
            if a is None:
                rep["conflicts"].append({"name": name, "why": why})
                conflict_names.add(name)
                continue
            audit[name] = a
            rep["added"].append(name)
        else:
            if e.get("direction") != a.get("direction_stored"):
                rep["conflicts"].append({"name": name, "registry": e.get("direction"), "audit": a.get("direction_stored"),
                                         "why": "등록부 direction ≠ 감사 표(손 편집 · 다른 도구) — 감사 표로 바꿀 것"})
                conflict_names.add(name)
            was, now = a.get("code_negated_at_audit"), neg.get(name)
            if was is not None and now is not None and bool(was) != bool(now):
                rep["drift"].append({"name": name, "audit": was, "now": now})
        if e.get("category") in SCOPE and not a.get("defensive_definition"):
            rep["pending_defensive"].append(name)
    sub = {k: v for k, v in audit.items() if k not in conflict_names}
    try:
        new, changes, _missing, _defc = apply(reg, sub, today)
    except SystemExit as ex:
        rep["errors"].append(str(ex))
        _write_pending(pending_out, rep)
        return 2, rep
    rep["direction_changes"] = [{"name": n, "from": f, "to": t} for n, f, t, _ in changes]
    data = serialize(new)
    alert = bool(rep["conflicts"] or rep["drift"])
    if dry or all(r == data for r in raws) and not rep["added"]:
        _write_pending(pending_out, rep)
        return (3 if alert else 0), rep
    if rep["added"]:
        A["factors"] = audit
        hist = list(A.get("history") or [])
        hist.append({"date": today, "what": f"야간 동기화 자동 등재 {len(rep['added'])}개", "names": rep["added"][:50]})
        A["history"] = hist
        adata = (json.dumps(A, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        fd, atmp = tempfile.mkstemp(prefix=".aud_", suffix=".json", dir=os.path.dirname(os.path.abspath(audit_path)))
        with os.fdopen(fd, "wb") as fh:
            fh.write(adata)
        os.replace(atmp, audit_path)                            # 감사 표 먼저 — 등록부 쓰기가 실패해도 다음 밤이 이어받는다(멱등)
    staged = []
    for p in present:
        tmp, chk = atomic_write(p, data)
        if list(chk.keys()) != list(new.keys()):
            os.unlink(tmp)
            rep["errors"].append(f"재파싱 엔트리 순서 · 집합 변화: {p}")
            _write_pending(pending_out, rep)
            return 2, rep
        staged.append((tmp, p))
    if _before_replace:
        _before_replace()                                       # 시험용 — 쓰기 직전 동시 변경 주입
    if any(open(p, "rb").read() != r for p, r in zip(present, raws)):
        for tmp, _ in staged:
            os.unlink(tmp)
        rep["errors"].append("읽은 뒤 등록부가 바뀌었다(동시 쓰기) — 쓰지 않음 · 다음 밤에 다시")
        _write_pending(pending_out, rep)
        return 4, rep
    for tmp, p in staged:
        os.replace(tmp, p)
    rep["wrote"] = True
    _write_pending(pending_out, rep)
    return (3 if alert else 0), rep


def _write_pending(path, rep):
    if not path:
        return
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".pend_", suffix=".json", dir=d)
    with os.fdopen(fd, "wb") as fh:
        fh.write((json.dumps(rep, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    os.replace(tmp, path)


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
    if "--sync" in args:
        pend = args[args.index("--pending-out") + 1] if "--pending-out" in args else PENDING
        rc, rep = sync(regs, audit_path, os.path.join(ROOT, "02_Infrastructure", "factor_db"), pend, dry=dry)
        print(f"[direction_sync] rc={rc} · 사본 {rep['copies']} · 정규화 {rep['normalized']} · 자동 등재 {len(rep['added'])} · "
              f"방어 판정 대기 {len(rep['pending_defensive'])} · 충돌 {len(rep['conflicts'])} · 부호 드리프트 {len(rep['drift'])} · "
              f"방향 변경 {len(rep.get('direction_changes', []))} · 썼다 {rep['wrote']}")
        for x in rep["added"][:20]:
            print(f"  [자동 등재] {x}")
        for x in rep["conflicts"][:20]:
            print(f"  [충돌] {x}")
        for x in rep["drift"][:20]:
            print(f"  [부호 드리프트] {x}")
        for x in rep["errors"]:
            print(f"  [오류] {x}")
        if rep["pending_defensive"]:
            print(f"  [방어 판정 대기] {', '.join(rep['pending_defensive'][:20])}{' …' if len(rep['pending_defensive']) > 20 else ''}")
        sys.exit(rc)
    A = json.load(open(audit_path, encoding="utf-8"))
    if A.get("schema") not in SCHEMAS:
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
    n_def = sum(1 for v in new.values() if isinstance(v, dict) and v.get("direction_defensive"))
    print(f"[direction_basis] 엔트리 {len(reg)} · 감사 {len(audit)} · 방향 바뀜 {len(changes)} · 정의 문구 수리 {len(def_changes)} · "
          f"방어 방향 {n_def} · 감사 밖(필드 없음) {len(missing)}")
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
