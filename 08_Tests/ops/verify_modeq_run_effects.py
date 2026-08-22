# -*- coding: utf-8 -*-
"""verify_modeq_run_effects.py — 무인 런의 **실제 부작용**을 사전 백업과 대조 (2026-08-22).

왜 있나: 러너의 `exit 0` 은 "돌았다"이지 "했다"가 아니고, `MODEQ_DONE` 개수조차
에이전트가 형식을 지켰을 때만 유효하다. 원장을 직접 대조해야 **무엇이 실제로 바뀌었는지**
알 수 있다. 특히 하드가드(자본 경로 금지)는 "안 바뀌었음"으로만 증명된다.

사용: python verify_modeq_run_effects.py <backup_dir>
"""
import hashlib
import io
import json
import os
import sys

ROOT = os.environ.get("QM_ROOT") or os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BAK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".cache",
                                                         "_prerun_backup_20260822")

P = F = 0


def ok(m):
    global P
    P += 1
    print("  PASS  %s" % m)


def ng(m, d):
    global F
    F += 1
    print("  FAIL  %s :: %s" % (m, d))


def sha(p):
    try:
        return hashlib.sha256(io.open(p, "rb").read()).hexdigest()
    except Exception:
        return None


def load(p):
    try:
        return json.load(io.open(p, encoding="utf-8"))
    except Exception:
        return None


def bak_of(rel):
    return os.path.join(BAK, rel.replace("/", "_"))


print("== 하드가드: 자본 경로가 **불변**인가 (안 바뀌었음으로만 증명된다) ==")
for rel in ("qepm/mailbox/governor/book_state.json",):
    a, b = sha(bak_of(rel)), sha(os.path.join(ROOT, rel))
    if a is None:
        ng("%s 백업" % rel, "사전 백업 없음 — 대조 불가")
    elif a == b:
        ok("%s 바이트 불변 (governor/자본 미접촉)" % rel)
    else:
        ng("%s 변경됨" % rel, "★자본 원장이 무인 런에 의해 변경 — 하드가드 위반")

print("== 산출: method_registry 에 실제로 무엇이 쓰였나 ==")
before = load(bak_of("06_Registry/method_registry.json"))
after = load(os.path.join(ROOT, "06_Registry", "method_registry.json"))
if not (isinstance(before, dict) and isinstance(after, dict)):
    ng("원장 로드", "before=%s after=%s" % (type(before).__name__, type(after).__name__))
else:
    bm = {str(m.get("method_id")): m for m in (before.get("methods") or [])}
    am = {str(m.get("method_id")): m for m in (after.get("methods") or [])}
    added = sorted(set(am) - set(bm))
    print("     methods: %d → %d (신규 %s)" % (len(bm), len(am), added or "없음"))

    def has_ms(m):
        return bool(str((m or {}).get("measurement_status") or "").strip())

    newly = [k for k in am if has_ms(am[k]) and not has_ms(bm.get(k))]
    if newly:
        ok("measurement_status 신규 기입 %d건: %s" % (len(newly), newly))
        for k in newly:
            v = str(am[k].get("measurement_status"))[:150]
            print("       %s → %s" % (k, v))
    else:
        ng("측정 칸 산출", "measurement_status 신규 기입 0건 — 등재→측정 배선이 실효 없음")

    print("== 라벨 계약: 자본 주장을 하지 않았는가 ==")
    bad = []
    for k in newly + added:
        m = am.get(k) or {}
        blob = json.dumps(m, ensure_ascii=False).lower()
        # 졸업/자본 자격을 주장하는 표현이 새로 들어왔는지
        for kw in ("graduation pass", "graduated", "admit", "book_state",
                   "자본 편입", "졸업 통과"):
            if kw in blob:
                bad.append((k, kw))
    ok("자본 자격 주장 표현 없음") if not bad else ng("자본 주장", str(bad))

    print("== 실측 계약: 손계산 흔적이 없는가 ==")
    smell = []
    for k in newly + added:
        blob = json.dumps(am.get(k) or {}, ensure_ascii=False)
        for kw in ("prod(1+", "cumprod", "손계산"):
            if kw in blob:
                smell.append((k, kw))
    ok("자체합성 흔적 없음") if not smell else ng("자체합성", str(smell))

print("== 부수 영향: 큐/환류 산출물이 예상 밖으로 바뀌지 않았는가 ==")
for rel, expect in (("06_Registry/factor_evidence.json", "unchanged"),):
    a, b = sha(bak_of(rel)), sha(os.path.join(ROOT, rel))
    if a is None:
        print("     %s 백업 없음 — skip" % rel)
    elif a == b:
        ok("%s 불변 (이 런의 소관 아님)" % rel)
    else:
        ng("%s 변경" % rel, "무인 런이 무관한 산출물을 건드림 — 범위 이탈")

print("== t_summary: PASS=%d FAIL=%d ==" % (P, F))
sys.exit(1 if F else 0)
