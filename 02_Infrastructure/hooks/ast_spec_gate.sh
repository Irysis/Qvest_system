#!/usr/bin/env bash
#==============================================================================
# ast_spec_gate.sh — AST v1.1 스펙 기계 게이트 (PreToolUse[Write] on alpha_package*.json)
#
# SOT: 02_Infrastructure/docs/qvest_ast_v1_1_sot.md §7 (기계 훅 ①~⑤) — Step 3 배선 (S2d 2026-07-25)
#
# 판정 (spec_version == "ast_v1.1" 패키지만 hard):
#  ① mechanism 3필드(agent/friction/path) 누락·공백           → block
#     falsification 사전 부재/빈 배열                          → block
#     falsification 이 field_dictionary 밖 필드 참조            → block
#     regime_scope.weakens_or_reverses_in 부재/빈 배열          → block
#  ② AST 연산자가 operator_library.json 𝒪 밖 (escape 리프 제외) → block
#     (허용 = 라이브러리 canonical + SOT §2 축약 표기 alias — ast_verify.py 와 동일 집합)
#  ③ ast_verify.py 정적검증 FAIL_LOOKAHEAD                      → block + 검증계층 경보
#     (경보 = stderr + 06_Registry/ast_gate_alerts.jsonl append — alpha 단계
#      정적검증이 잡았어야 할 위반이 Write 까지 도달 = 검증 계층 결손 신호)
#  ④ 구식 패키지(spec_version 부재/비-v1.1)                     → 통과 + advisory
#     ({"additionalContext": ...} — 라우터 context 채널 단일키, v1.1 전환 권고)
#  기타 non-block: FAIL_CONTRACT / WARN_RESTATEMENT / staleness → advisory
#
# field_dictionary = factor_registry.json 373 팩터명 ∪ ast_field_map_v0.json 58 group_id
#
# 작성 3의무 (harness.md 2026-07-24 정합 절):
#  1) content 는 소스 보간('''$CONTENT''') 금지 — 전체 payload 를 stdin bytes 로
#     python 에 전달(buffer.decode utf-8 — artifact_placement_guard 선례 패턴)
#  2) raw-INPUT 조기-exit — 'alpha_package' 미포함 payload 는 python 스폰 0
#  3) advisory 는 additionalContext 실전달 (라우터 dispatch context 채널)
#
# fail 정책: soft_fail true (dispatch) — 단 내부오류/실행기 부재 시 v1.1 패키지
#  형상(alpha_package ∧ ast_v1.1)이 raw payload 에 잡히면 fail-closed block
#  (discovery_graduation_gate 선례 — 게이트 침묵 통과 금지).
# 등록: policies/router_dispatch.json (Write, soft_fail true, /tmp/ast_spec_gate.log)
#==============================================================================
set -uo pipefail
export PYTHONUTF8=1

INPUT=$(cat)

_gate_fail_closed() {
  case "$INPUT" in
    *alpha_package*ast_v1.1*|*ast_v1.1*alpha_package*)
      echo '{"decision": "block", "reason": "ast_spec_gate: hook 내부 오류 — AST v1.1 스펙 검증 불가 (fail-closed)"}' ;;
    *) echo '{}' ;;
  esac
  exit 0
}
trap '_gate_fail_closed' ERR

# ── 3의무-2: raw-INPUT 조기-exit (superset 필터 — python 스폰 전) ──────────────
case "$INPUT" in
  *alpha_package*) : ;;
  *) echo '{}'; exit 0 ;;
esac

# ── python 해석 (bare python3 = Windows Store 스텁 회피) ──────────────────────
QVEST_PARSE_RESOLVE_ONLY=1; source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"; unset QVEST_PARSE_RESOLVE_ONLY
{ [ -n "${QVEST_PY_BIN:-}" ] && [ -x "$QVEST_PY_BIN" ]; } || _gate_fail_closed

ROOT_DIR="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
ROOT_DIR="${ROOT_DIR//\\//}"

# ── 3의무-1: payload 는 stdin bytes 로 전달 (소스 보간 없음, 스크립트는 '-c' 단일인용) ──
printf '%s' "$INPUT" | ASG_ROOT="$ROOT_DIR" "$QVEST_PY_BIN" -c '
import datetime, json, os, re, sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

def scrub(s):
    return "".join("?" if 0xD800 <= ord(ch) <= 0xDFFF else ch for ch in str(s))

def emit(obj):
    print(scrub(json.dumps(obj, ensure_ascii=False)))
    sys.exit(0)

def allow():
    print("{}"); sys.exit(0)

def block(reason):
    emit({"decision": "block", "reason": "ast_spec_gate: " + reason})

def advisory(msg):
    emit({"additionalContext": "[ast_spec_gate advisory — 차단 아님] " + msg})

ROOT = (os.environ.get("ASG_ROOT") or "").replace("\\", "/") or "."

try:
    payload = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
except Exception:
    allow()
if payload.get("tool_name") != "Write":
    allow()
ti = payload.get("tool_input") or {}
fp = (ti.get("file_path") or "").replace("\\", "/")
base = fp.rsplit("/", 1)[-1]
if not re.match(r"^alpha_package.*\.json$", base):
    allow()
content = ti.get("content") or ""

try:
    pkg = json.loads(content)
    if not isinstance(pkg, dict):
        raise ValueError("root not object")
except Exception as e:
    advisory("alpha_package JSON 파싱 실패(%s) — v1.1 스펙 판정 불가. 유효 JSON + "
             "spec_version=ast_v1.1 3층 구조(가설 mechanism/falsification/regime_scope + AST) 권장 "
             "(SOT qvest_ast_v1_1_sot.md par.1)." % type(e).__name__)

spec_version = pkg.get("spec_version")

# ── ④ 구식 패키지 lane: 통과 + advisory (v1.1 전환 권고) ─────────────────────
if spec_version != "ast_v1.1":
    tag = "spec_version 부재" if spec_version is None else ("spec_version=%r 미인식" % spec_version)
    advisory(tag + " — 구식 alpha_package 로 통과. AST v1.1 전환 권고: spec_version=\"ast_v1.1\" + "
             "mechanism{agent,friction,path} + falsification(field_dictionary 필드) + "
             "regime_scope.weakens_or_reverses_in + ast(𝒪 연산자·escape 리프 4종). "
             "SOT: 02_Infrastructure/docs/qvest_ast_v1_1_sot.md par.1/par.7.")

# ── v1.1 hard lane ────────────────────────────────────────────────────────────
hyp = pkg.get("hypothesis") if isinstance(pkg.get("hypothesis"), dict) else {}

def pick(key):
    v = pkg.get(key)
    return v if v is not None else hyp.get(key)

# ① mechanism 3필드
mech = pick("mechanism")
if not isinstance(mech, dict):
    block("mechanism 부재 — {agent, friction, path} 3필드 필수 (SOT par.1: 주체·마찰 무명명 가설 기계 반려)")
missing = [k for k in ("agent", "friction", "path")
           if not (isinstance(mech.get(k), str) and mech.get(k).strip())]
if missing:
    block("mechanism 필드 누락/공백: {%s} — 3필드(agent/friction/path) 전부 비어있지 않은 서술 필수 (SOT par.1)" % ", ".join(missing))

# field_dictionary 로드 (registry 373 + ast_field_map 58 group)
def load_field_dictionary():
    names = set()
    with open(os.path.join(ROOT, "02_Infrastructure/factor_db/factor_registry.json"), encoding="utf-8") as f:
        names |= set(json.load(f).keys())
    with open(os.path.join(ROOT, "06_Registry/ast_field_map_v0.json"), encoding="utf-8") as f:
        fmap = json.load(f)
    for dom in fmap.get("domains", {}).values():
        for g in dom.get("leaf_groups", []):
            names.add(g.get("group_id"))
    names.discard(None)
    return names

try:
    FIELD_DICT = load_field_dictionary()
except Exception as e:
    block("field_dictionary 로드 실패(%s: %s) — falsification 검증 불가 (fail-closed)" % (type(e).__name__, e))

# ① falsification 사전 — field_dictionary 내 필드 참조 의무
fals = pick("falsification")
if not isinstance(fals, list) or not fals:
    block("falsification 사전 부재/빈 배열 — field_dictionary 필드로 확인 가능한 부수 관측 >=1 필수 "
          "(성과 동어반복 금지, SOT par.1)")

def fals_fields(entry):
    if isinstance(entry, str):
        return [entry]
    if isinstance(entry, dict):
        out = []
        for k in ("field", "fields", "field_ref", "leaf", "group_id", "factor"):
            v = entry.get(k)
            if isinstance(v, str):
                out.append(v)
            elif isinstance(v, list):
                out += [x for x in v if isinstance(x, str)]
        return out
    return []

bad_entries = []
for i, entry in enumerate(fals):
    refs = fals_fields(entry)
    if not refs:
        bad_entries.append("[%d] 필드 참조 없음(field/fields/group_id/factor 키 필요)" % i)
    else:
        unknown = [r for r in refs if r not in FIELD_DICT]
        if unknown:
            bad_entries.append("[%d] field_dictionary 밖: %s" % (i, ", ".join(unknown[:5])))
if bad_entries:
    block("falsification 검증 실패 — " + " | ".join(bad_entries[:6])
          + " (field_dictionary = factor_registry 373 팩터명 + ast_field_map_v0 group_id 58)")

# ① regime_scope.weakens_or_reverses_in 빈 배열 금지
rs = pick("regime_scope")
worin = rs.get("weakens_or_reverses_in") if isinstance(rs, dict) else None
if not isinstance(worin, list) or not worin:
    block("regime_scope.weakens_or_reverses_in 부재/빈 배열 — 약화·역전 국면 명시 필수 (SOT par.1)")

# ── ② AST 연산자 in-library 검사 (escape 리프 제외) ───────────────────────────
def extract_ast(p):
    for holder in (p, p.get("factor_definition") or {}, p.get("spec") or {}):
        if isinstance(holder, dict) and isinstance(holder.get("ast"), dict):
            return holder["ast"]
    return None

ast_root = extract_ast(pkg)
if ast_root is None:
    block("ast 노드 부재 (top-level/factor_definition/spec) — v1.1 팩터 정의는 AST 의무 "
          "(formulaic lane + escape 리프 4종, SOT par.1/par.2)")

try:
    with open(os.path.join(ROOT, "02_Infrastructure/ast/operator_library.json"), encoding="utf-8") as f:
        LIB_OPS = set(json.load(f).get("operators", {}).keys())
except Exception as e:
    block("operator_library.json 로드 실패(%s) — 𝒪 검사 불가 (fail-closed)" % type(e).__name__)
# SOT par.2 축약 표기 alias (ast_verify.py 수용 집합과 동일 — dialect 갭 봉합, S2d)
ALIAS_OPS = {"ZSCORE", "WINSORIZE", "NEUTRALIZE", "DEMEAN", "DELTA"}
ALLOWED_OPS = LIB_OPS | ALIAS_OPS

def collect_ops(node, acc):
    if not isinstance(node, dict):
        return
    if "leaf" in node or node.get("type") == "leaf" or node.get("type") == "const":
        return  # 리프(escape 포함)/상수 — 연산자 검사 대상 아님
    op = node.get("op")
    if isinstance(op, str):
        acc.append(op.upper())
    for key in ("children", "args"):
        ch = node.get(key)
        if isinstance(ch, list):
            for c in ch:
                collect_ops(c, acc)

ops = []
collect_ops(ast_root, ops)
outside = sorted({o for o in ops if o not in ALLOWED_OPS})
if outside:
    block("𝒪 밖 연산자 {%s} — operator_library.json 미등재 (escape 리프 4종만 예외). "
          "확장은 06_Registry/ast_operator_backlog.json blocked_by_capability 적립 경유 (SOT par.2 확장 규율)"
          % ", ".join(outside))

# ── ③ ast_verify.py 정적검증 (in-process) ─────────────────────────────────────
try:
    sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure/ast"))
    import ast_verify as av
    with open(av.DEFAULT_REGISTRY, encoding="utf-8") as f:
        registry = json.load(f)
    with open(av.DEFAULT_FIELD_MAP, encoding="utf-8") as f:
        field_map = json.load(f)
    sig_d, td = av.extract_pit_dates(pkg, None, None)
    verifier = av.AstVerifier(registry, field_map, td)
    verdict, _max_avail = verifier.run(ast_root, sig_d)
except Exception as e:
    block("ast_verify 실행 실패(%s: %s) — PIT 정적검증 불가 (fail-closed). "
          "pit.sig_date/decision_ts 및 AST 리프 형상 확인" % (type(e).__name__, scrub(e)))

if verdict == "FAIL_LOOKAHEAD":
    v3 = verifier.violations[:3]
    detail = "; ".join("%s(%s: avail %s > t_d %s)" % (v.get("leaf"), v.get("path"),
                       v.get("avail_ts"), v.get("decision_ts")) for v in v3)
    # 검증계층 경보 — alpha 단계 정적검증이 잡았어야 할 위반이 Write 도달
    alert = {"ts": datetime.datetime.now().isoformat(timespec="seconds"),
             "kind": "verification_layer_breach",
             "strategy_id": pkg.get("strategy_id"), "file_path": fp,
             "verdict": verdict, "violations_head": v3,
             "note": "ast_spec_gate 도달 전 alpha 단계 ast_verify 미실행/무시 — 검증 계층 결손 신호 (SOT par.7-5)"}
    # 배터리 실행은 registry 경보 append 만 억제 (판정 block 은 동일 — 로그 오염 방지 전용)
    if os.environ.get("QVEST_AST_GATE_BATTERY") != "1":
        try:
            with open(os.path.join(ROOT, "06_Registry/ast_gate_alerts.jsonl"), "a", encoding="utf-8") as f:
                f.write(scrub(json.dumps(alert, ensure_ascii=False)) + "\n")
        except Exception:
            pass
    print("[ast_spec_gate] ALERT verification_layer_breach: FAIL_LOOKAHEAD 이 Write 까지 도달 — "
          "06_Registry/ast_gate_alerts.jsonl 적립", file=sys.stderr)
    block("PIT 정적검증 FAIL_LOOKAHEAD — %s. alpha 반려(forge 사이클 0 소비, SOT par.4). "
          "검증계층 경보 적립됨" % detail)

warns = []
if verdict == "FAIL_CONTRACT":
    heads = ["%s: %s" % (c.get("leaf_type"), c.get("detail", "")[:120])
             for c in verifier.contract_failures[:3]]
    warns.append("ast_verify FAIL_CONTRACT (non-block — 게이트 hard 대상은 FAIL_LOOKAHEAD): "
                 + " | ".join(heads))
elif verdict == "WARN_RESTATEMENT":
    warns.append("WARN_RESTATEMENT — restatement-prone + vintage 무 리프 %d개 (judge/governor 입력 플래그, SOT par.4)"
                 % len(verifier.restatement_leaves))
if verifier.staleness_flags:
    warns.append("staleness 플래그 %d건 (수동 export 리프 — 라이브 스테일 위험)" % len(verifier.staleness_flags))

if warns:
    advisory("v1.1 스펙 hard 게이트 통과(verdict=%s). " % verdict + " / ".join(warns))
allow()
' 2>>/tmp/ast_spec_gate_inner.log || _gate_fail_closed
exit 0
