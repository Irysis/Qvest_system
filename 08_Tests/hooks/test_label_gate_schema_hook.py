## test_label_gate_schema_hook.py — FQ-119 관문의 스키마·훅 표면 위반 주입
##
## 왜 두 표면을 함께 거는가:
##   이 저장소에는 JSON-Schema **실행 엔진이 배선돼 있지 않다** (R jsonvalidate 미설치 ·
##   wt_validate_package 호출부 0). 그래서 schema.json 에 조건부 required 를 넣는 것만으로는
##   그것도 "정의만 있고 소비 없는" 계약이 된다. 실제로 발화하는 표면은
##   worktask_artifact_validator.sh (PostToolUse, warn level) 이다.
##   → 스키마(계약 문서)와 훅(실행)을 **같은 검사**에 묶어, 한쪽만 살아 있는 상태를 잡는다.
##
## 축:
##   A 비파괴 — 실물 alpha_package 전건에 대해 개정 전후 유효성이 바뀌지 않아야 한다
##             (opt-in 설계: 선언하지 않은 패키지는 종전대로 유효 → 진행 중 라운드 무영향)
##   B 스키마 위반 주입 — 라벨 소비를 선언하면 증거 제출이 실제로 강제되는가
##   C ★검출력 — 같은 위반을 **개정 전** 스키마는 하나도 못 잡았어야 한다(진짜 추가분인가)
##   D 훅 실발화 — 픽스처를 훅에 통과시켜 로그에 실제 경고가 찍히는가 (정적 grep 아님)
##
## 실행: python 08_Tests/hooks/test_label_gate_schema_hook.py

import io
import json
import os
import subprocess
import sys
import tempfile

def _pick(cands, probe):
    for c in cands:
        if c and os.path.exists(os.path.join(c, probe)):
            return c
    return ""

CODE_ROOT = _pick([os.getcwd(), os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")],
                  "02_Infrastructure/worktask/schema.json")
DATA_ROOT = _pick([os.environ.get("QM_ROOT", ""), os.getcwd(), os.environ.get("CLAUDE_PROJECT_DIR", "")],
                  "qepm/mailbox/worktask")
if not CODE_ROOT:
    print("[FATAL] 코드 루트를 찾지 못함 — schema.json 부재")
    sys.exit(1)
print("[root] CODE=%s" % CODE_ROOT)
print("[root] DATA=%s" % (DATA_ROOT or "(없음)"))

_p = [0]
_f = [0]

def ck(label, cond):
    if cond:
        _p[0] += 1
        print("  [PASS] %s" % label)
    else:
        _f[0] += 1
        print("  [FAIL] %s" % label)

try:
    from jsonschema import Draft202012Validator
except Exception as e:                                    # noqa: BLE001
    # ★엔진 부재를 '합격'으로 접지 않는다 — 스킵은 스킵으로 보고하고 훅 축은 계속 돈다.
    Draft202012Validator = None
    print("  [skip] jsonschema 미설치 (%s) — 스키마 축 미실행(합격으로 세지 않음)" % e)

SCHEMA_REL = "02_Infrastructure/worktask/schema.json"
schema_new = json.load(io.open(os.path.join(CODE_ROOT, SCHEMA_REL), encoding="utf-8"))

def alpha_validator(sch):
    # ★루트에는 9-way oneOf 가 있다. 루트를 그대로 쓰면 "alpha_package 인가"가 아니라
    #   "9종 중 정확히 하나인가"를 재게 된다 — 다른 축이 섞인 검사가 된다.
    return Draft202012Validator({"$schema": sch.get("$schema"),
                                 "definitions": sch["definitions"],
                                 "$ref": "#/definitions/alpha_package"})

EV = {
    "eligible": True, "verdict": "ELIGIBLE", "recall": 0.285, "base_rate": 0.171,
    "lift": 1.666, "fisher_p": 0.000116, "n_months": 439,
    "event_definition": "benchmark monthly return < -5.00%",
    "label_definition": "regime[daily_t1_monthstart] in {CRISIS,RISK_OFF,CAUTION}",
    "contract": "02_Infrastructure/contracts/label_eligibility_gate.R",
}
BASE = {
    "task_id": "WT-D20260808_999", "as_of_date": "2026-08-08", "forecast_horizon": "1m",
    "alpha_vector": {"005930": 0.012},
    "factor_specs": [{"factor_family": "Value", "proxy": "B/P", "economic_rationale": "risk_premium"}],
    "diagnostics": {"rank_ic": 0.02, "alpha_inheritance_cor": 0.10, "canonical_port_t_nw_lag3": 3.10},
}

def with_lc(**kw):
    d = dict(BASE)
    d["label_consumption"] = kw
    return d

CASES = [
    ("A 라벨 미선언 = 기존대로 유효(비파괴)", dict(BASE), True),
    ("B 소비 false 선언", with_lc(consumes_regime_label=False), True),
    ("C ★소비 true + 증거 전무 → 반려", with_lc(consumes_regime_label=True, consumption_surface="overlay"), False),
    ("D ★소비 true + 소비면 미기재 → 반려", with_lc(consumes_regime_label=True, label_eligibility=EV), False),
    ("E 소비 true + 완전 증거 → 통과",
     with_lc(consumes_regime_label=True, consumption_surface="overlay", label_eligibility=EV), True),
    ("F ★증거 event_definition 누락 → 반려",
     with_lc(consumes_regime_label=True, consumption_surface="overlay",
             label_eligibility={k: v for k, v in EV.items() if k != "event_definition"}), False),
    ("G ★증거 contract 누락(손계산 판정) → 반려",
     with_lc(consumes_regime_label=True, consumption_surface="overlay",
             label_eligibility={k: v for k, v in EV.items() if k != "contract"}), False),
    ("H ★verdict 자작('PASS') → 반려",
     with_lc(consumes_regime_label=True, consumption_surface="overlay",
             label_eligibility=dict(EV, verdict="PASS")), False),
    ("I UNMEASURABLE 은 제출 가능(합격 상태는 아님)",
     with_lc(consumes_regime_label=True, consumption_surface="overlay",
             label_eligibility=dict(EV, verdict="UNMEASURABLE_NO_DATA", eligible=None)), True),
    ("J ★소비면 enum 밖 → 반려",
     with_lc(consumes_regime_label=True, consumption_surface="vibes", label_eligibility=EV), False),
]

if Draft202012Validator is not None:
    print("\n── 스키마 무결 ──")
    try:
        Draft202012Validator.check_schema(schema_new)
        ck("개정 스키마 meta-schema 통과", True)
    except Exception as e:                                # noqa: BLE001
        ck("개정 스키마 meta-schema 통과 (%s)" % str(e)[:80], False)

    vn = alpha_validator(schema_new)

    # ── A. 비파괴 (실물 전건) ────────────────────────────────────────────────
    print("\n── A 비파괴 (실물 alpha_package 전건, 개정 전후 대조) ──")
    old_raw = subprocess.run(["git", "-C", CODE_ROOT, "show", "HEAD:" + SCHEMA_REL],
                             capture_output=True)
    vo = None
    if old_raw.returncode == 0 and old_raw.stdout:
        try:
            schema_old = json.loads(old_raw.stdout.decode("utf-8"))
            vo = alpha_validator(schema_old)
        except Exception:                                 # noqa: BLE001
            vo = None
    if vo is None:
        print("  [skip] HEAD 판 스키마를 얻지 못함 — 비파괴/검출력 축 미실행(합격으로 세지 않음)")
    else:
        n_pkg = 0
        changed = []
        if DATA_ROOT:
            wt_root = os.path.join(DATA_ROOT, "qepm", "mailbox", "worktask")
            for name in sorted(os.listdir(wt_root)):
                fp = os.path.join(wt_root, name, "alpha_package.json")
                if not os.path.exists(fp):
                    continue
                try:
                    d = json.load(io.open(fp, encoding="utf-8"))
                except Exception:                         # noqa: BLE001
                    continue
                if not isinstance(d, dict):
                    continue
                n_pkg += 1
                if vo.is_valid(d) != vn.is_valid(d):
                    changed.append(fp)
        print("   [실측] 실물 alpha_package %d건 · 유효성 변화 %d건" % (n_pkg, len(changed)))
        # ★0건을 결론으로 쓰기 전에 분모가 실재하는지 먼저 본다(빈 스캔이 '무결'로 읽히는 계통).
        ck("비파괴 분모 실재 (스캔 대상 > 50건)", n_pkg > 50)
        ck("★개정이 실물 패키지 유효성을 바꾸지 않음 (opt-in 설계)", len(changed) == 0)

        # ── C. 검출력 (구판 대조) ────────────────────────────────────────────
        print("\n── C 검출력 (같은 위반을 구판은 잡았는가) ──")
        viol = [(nm, doc) for nm, doc, exp in CASES if exp is False]
        old_catch = sum(1 for _, doc in viol if not vo.is_valid(doc))
        new_catch = sum(1 for _, doc in viol if not vn.is_valid(doc))
        print("   [실측] 위반 %d건 — 구판 검거 %d · 개정판 검거 %d" % (len(viol), old_catch, new_catch))
        ck("★구판은 이 위반들을 하나도 잡지 못했다 (검출력이 실제 추가분)", old_catch == 0)
        ck("★개정판이 위반 전건을 잡는다", new_catch == len(viol))

    # ── B. 스키마 위반 주입 ─────────────────────────────────────────────────
    print("\n── B 스키마 위반 주입 ──")
    ck("기준 픽스처가 개정판에서 유효 (이후 차이는 label 축 단독)", vn.is_valid(BASE))
    for name, doc, exp in CASES:
        ck(name, vn.is_valid(doc) == exp)

# ── D. 훅 실발화 ────────────────────────────────────────────────────────────
# ★정적 grep 이 아니라 훅을 **실행**해 로그에 경고가 실제로 찍히는지 본다.
#   (grep 은 코드가 존재함을 재고, 실행은 그 코드가 도달 가능함을 잰다 — 둘은 다르다)
print("\n── D 훅 실발화 (worktask_artifact_validator.sh 실행) ──")
HOOK = os.path.join(CODE_ROOT, "02_Infrastructure/hooks/worktask_artifact_validator.sh")
LOG = os.path.join(tempfile.gettempdir(), "worktask_artifact_validator.log")
if not os.path.exists(HOOK):
    ck("훅 파일 존재", False)
else:
    fixtures = {
        "clean":           dict(BASE),
        "declared_ok":     with_lc(consumes_regime_label=True, consumption_surface="overlay", label_eligibility=EV),
        "declared_noev":   with_lc(consumes_regime_label=True, consumption_surface="overlay"),
        "declared_inelig": with_lc(consumes_regime_label=True, consumption_surface="overlay",
                                   label_eligibility=dict(EV, verdict="INELIGIBLE_NO_DISCRIMINATION", eligible=False)),
        "undeclared":      dict(BASE, diagnostics=dict(BASE["diagnostics"], note="CRISIS 국면에서 신호 강화")),
    }
    tmpd = tempfile.mkdtemp(prefix="lblgate_")
    marker = os.path.basename(tmpd)
    for k, v in fixtures.items():
        os.makedirs(os.path.join(tmpd, k), exist_ok=True)
        io.open(os.path.join(tmpd, k, "alpha_package.json"), "w", encoding="utf-8").write(
            json.dumps(v, ensure_ascii=False, indent=1))
    bash = "bash"
    for k in fixtures:
        payload = json.dumps({"tool_input": {"file_path":
                                             os.path.join(tmpd, k, "alpha_package.json").replace("\\", "/")}})
        subprocess.run([bash, HOOK], input=payload.encode("utf-8"),
                       capture_output=True, cwd=CODE_ROOT)
    log = io.open(LOG, encoding="utf-8", errors="replace").read() if os.path.exists(LOG) else ""
    lines = [l for l in log.splitlines() if marker in l]
    # ★분모 가드: 훅이 아예 안 돌았는데 "경고 없음"을 통과로 읽지 않는다.
    ck("훅이 실제로 실행됨 (로그에 이번 실행 흔적)", len(lines) > 0)

    def fired(fixture, kind):
        return any(("/" + fixture + "/") in l and ("label_gate " + kind) in l for l in lines)

    ck("훅 D1 증거 결측 → evidence_missing 발화", fired("declared_noev", "evidence_missing"))
    ck("훅 D2 무자격 verdict → ineligible_label 발화", fired("declared_inelig", "ineligible_label"))
    ck("훅 D3 미선언 소비 흔적 → undeclared_consumption 발화", fired("undeclared", "undeclared_consumption"))
    ck("훅 D4 완전 증거 → 경고 없음 (항상경고 아님)",
       not any(("/declared_ok/" in l and "[WARN]" in l and "label_gate" in l) for l in lines))
    ck("훅 D5 라벨 무관 패키지 → label_gate 무발화 (오탐 아님)",
       not any(("/clean/" in l and "label_gate" in l) for l in lines))
    ck("★훅 발화 축이 실제로 갈린다 (미선언 발화 ≠ clean 무발화)",
       fired("undeclared", "undeclared_consumption") and
       not any(("/clean/" in l and "label_gate" in l) for l in lines))

print("\n[test_label_gate_schema_hook] PASS=%d FAIL=%d" % (_p[0], _f[0]))
print(json.dumps({"test": "label_gate_schema_hook", "pass": _p[0], "fail": _f[0],
                  "total": _p[0] + _f[0]}))
sys.exit(1 if _f[0] else 0)
