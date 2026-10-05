#!/usr/bin/env bash
#==============================================================================
# test_rf_clean_lane.sh — 무인 충실구현 레인 **청정 모드** 양방향 검사 (결정 FA-CLEAN-BASE-PATH · 도훈 2026-09-26)
#
# 재는 것 (막는가 · 안 막는가 · 기록이 재도출되는가 · 규칙을 끄면 붉어지는가)
#   S  동기화 — 가드 설정 clean_lane.target_regex·target_keys = 청정 규칙 설정 perf_path_regex·tool_target_keys(사후 검사와 같은 식) ·
#      가드 통과 표식(bash PASS_OUT) = 규칙 설정 guard_attestation.pass_stdout · 레인·감사 셸의 청정 --disallowed-tools 리터럴 = 레인 설정 ·
#      레인 설정의 지원 표식이 가드·주입 훅 본문에 실재 · 웹 금지 정규식이 레인 설정 web_forbidden 을 전부 잡는다 ·
#      (10-03) 청정 작업 디렉터리 접두(레인 설정·셸 기본값) ∈ 규칙 설정 engine_dir_regex(사후 검사의 새 엔진 경로 조건)
#   G  가드(arm_gen_read_guard.sh · 청정 표식 QVEST_CLEAN_LANE) — 위반 주입(원장·산출물·다른 전략 엔진·계획서·/tmp·contracts·docs·
#      config.R·경로 주입 규칙·작업 디렉터리의 감사 파일·.. 탈출·루트 Grep·패턴의 성과 토큰) → block + 표식 '[clean_lane' ·
#      양성 대조(작업 디렉터리·허용 목록·Glob 이름 열거·가린 사본) → 통과 출력 = {"continue":true}(증명 표식) · 평시 '{}' ·
#      설계 레인 출력은 구판 훅과 바이트 동일(차등 회귀) · fail-closed(판정기 부재·설정 부재) · R5 등록부 사본 안내
#   I  주입 훅(axiom_context_inject.sh) — 평시 = 성과 줄(최고 전략 PORT_t · 최근 교훈) 실림 / 청정 = 수치 0 · 청정 표식 줄 · 고정부 유지
#   M  모드 해석(rf_clean_lane.py mode) — 결합 · 지속 · 요청 on/off · 배포 전 진행 중 · 설정 기본 · 전제 미충족(halt/degraded) · 요청에 지속 기록
#   Z  피드백 가림(sanitize) — 산출물 참조 줄 제거 · 지표 수치·'필드=값'·화살표·등급 가림 · 논문 파라미터(12개월·10%·t-1) 보존 ·
#      사후 검사 정규식 잔존 0 · 가림 규칙을 비워도 사후 재검이 잡는다(fail-closed) · 규칙 판독 불능 = rc≠0
#   W  배선(정적) — 레인 청정 호출: 표식 2종 · 셸 7종+Agent+Skill 금지 · export 0 / normal 호출 구판 그대로 · 검증기 감사 스폰이 도우미를 거친다 ·
#      감사 셸 2종 청정 분기 · 레인 출처 기록 실행 전·후
#   D  레인(동적 · 가짜 claude·Rscript · 샌드박스 루트) — 청정 기본: RP_AUTO_CLEAN_ 작업 디렉터리 · claude 가 받은 표식·도구 · 프롬프트 열람 범위 절 ·
#      출처 기록 sha256 = 실제 파일 · 검증기에 RP_LANE_MODE 만(가드 표식 누수 0) · 요청 lane_mode 지속 / 결합 = normal 구판 호출 /
#      청정 재구현 피드백 가림 + 통계 / 비청정 감사 지적 제외 / 전제 미충족 요청 = halt(claude 0회 · 요청 보존)
#   A  감사 셸(동적 · 가짜 claude) — 청정: 산출물 경로 대신 비공개 줄 · 셸 금지 / 평시: 구판 그대로 (단일 · 팬아웃)
#   V  검증기 도우미(rf_clean_lane_lib.R) — 표식 임시 대입·원복 · 산출물 경로 비움 · 감사 원천 보존 매니페스트 · 출처 기록 덧붙임
#   L  돌연변이 — R6 호출 삭제 · 통과 표식 '{}' · 청정 R5 레인 삭제 · 작업 디렉터리 순회 예외 삭제 · 주입 훅 청정 분기 삭제 · 레인 표식 삭제 ·
#      레인 셸 금지 축소 · 가림 사후 재검 삭제 → 해당 사례 red
# 격리: 모든 쓰기 = mktemp 샌드박스(TMPDIR) · 가짜 HOME · 리프레시 배리어 잠금 = 샌드박스 경로 · R = 빈 Renviron. 운영 트리 읽기도 없다(코드 원천 = QM_ROOT).
# 대상 교체: QM_ROOT(코드 원천 루트 — 스테이징 미러) · QVEST_CL_PY(파이썬)
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
PY="${QVEST_CL_PY:-${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}}"
[ -x "$PY" ] || PY="C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"
export PYTHONDONTWRITEBYTECODE=1 PYTHONUTF8=1
RSCRIPT_REAL="${QVEST_CL_RSCRIPT:-$(command -v Rscript 2>/dev/null || echo "C:/Program Files/R/R-4.5.2/bin/Rscript.exe")}"
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); printf '  OK    %s\n' "$1"; }
ng(){ FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }
sk(){ SKIP=$((SKIP+1)); printf '  SKIP  %s — %s\n' "$1" "${2:-}"; }
wp(){ cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
summary(){ printf '\n합계: 통과 %d · 실패 %d · 생략 %d\n{"test":"rf_clean_lane","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n' "$PASS" "$FAIL" "$SKIP" "$PASS" "$FAIL" "$((PASS+FAIL))" "$SKIP"; }

echo "=== test_rf_clean_lane (FA-CLEAN-BASE-PATH) · 코드 원천 = $ROOT ==="
SRC_HOOK="$ROOT/02_Infrastructure/hooks/arm_gen_read_guard.sh"
SRC_POL="$ROOT/02_Infrastructure/hooks/policies/arm_gen_read_guard.json"
SRC_INJ="$ROOT/02_Infrastructure/hooks/axiom_context_inject.sh"
SRC_OPS="$ROOT/02_Infrastructure/ops"
SRC_LANECFG="$ROOT/06_Registry/replication_clean_lane.json"
SRC_RULECFG="$ROOT/06_Registry/prereg/clean_base_rule.config.json"
for f in "$SRC_HOOK" "$SRC_POL" "$SRC_INJ" "$SRC_OPS/rf_replication_auto.sh" "$SRC_OPS/rf_clean_lane.py" "$SRC_OPS/rf_clean_lane_lib.R" \
         "$SRC_OPS/rf_replication_verify.R" "$SRC_OPS/rf_fidelity_audit.sh" "$SRC_OPS/rf_fidelity_fanout.sh" "$SRC_OPS/rf_llm_env.sh" \
         "$SRC_OPS/rf_axiom_brief.sh" "$SRC_OPS/refresh_barrier.sh" "$SRC_OPS/rf_b1_design_lib.R" "$SRC_LANECFG" "$SRC_RULECFG"; do
  [ -f "$f" ] || { ng "원천 부재" "$f"; summary; exit 1; }
done
case "$(wp "${TMPDIR:-/tmp}")" in *Quant_Module_Moltbot*|*OneDrive*) ng "TMPDIR 가 운영 트리 안" "${TMPDIR:-}"; summary; exit 1;; esac
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
EMPTY_RENV="$T/empty.Renviron"; : > "$EMPTY_RENV"

# ═══ S 동기화 ═══
echo "--- S. 동기화(사본·리터럴 ↔ 정본) ---"
sres="$("$PY" - "$(wp "$SRC_POL")" "$(wp "$SRC_RULECFG")" "$(wp "$SRC_LANECFG")" "$(wp "$SRC_HOOK")" "$(wp "$SRC_INJ")" "$(wp "$SRC_OPS")" <<'PYEOF'
import io, json, re, sys, os
pol, rc, lc, hook, inj, ops = sys.argv[1:7]
P = json.load(io.open(pol, encoding='utf-8'))['clean_lane']; R = json.load(io.open(rc, encoding='utf-8')); L = json.load(io.open(lc, encoding='utf-8'))
T = R['exposure']['transcript']
out = []
out.append('S1 %d' % (P['target_regex'] == T['perf_path_regex'] and P['target_keys'] == T['tool_target_keys']))
h = io.open(hook, encoding='utf-8').read()
m = re.search(r"^\[ \"\$\{QVEST_CLEAN_LANE:-0\}\" = \"1\" \] && PASS_OUT='([^']*)'", h, re.M)
out.append('S2 %d' % (bool(m) and m.group(1) == T['guard_attestation']['pass_stdout']))
lane = io.open(os.path.join(ops, 'rf_replication_auto.sh'), encoding='utf-8').read()
blk = re.search(r'QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="\$WDIR" rf_llm_agent_run[^\n]*\\\n(?:[^\n]*\\\n)*[^\n]*', lane)
dt = re.search(r'--disallowed-tools "([^"]*)"', blk.group(0)).group(1) if blk else None
pre = re.search(r'--mode clean[\s\S]{0,400}?--disallowed "([^"]*)"', lane)
out.append('S3 %d' % (dt == L['disallowed_tools_clean'] and bool(pre) and pre.group(1) == L['disallowed_tools_clean']))
ok4 = True
for f in ('rf_fidelity_audit.sh', 'rf_fidelity_fanout.sh'):
    s = io.open(os.path.join(ops, f), encoding='utf-8').read()
    br = re.search(r'if \[ "\$\{QVEST_CLEAN_LANE:-0\}" = "1" \]; then\s*\n[\s\S]*?--disallowed-tools "([^"]*)"', s)
    ok4 = ok4 and bool(br) and br.group(1) == L['audit_disallowed_tools_clean']
out.append('S4 %d' % ok4)
out.append('S5 %d' % all(re.search(T['web']['forbidden_regex'], 'https://' + w + '/blob/main/06_Registry/x.json') for w in L['web_forbidden']))
out.append('S6 %d' % (L['guard_support_marker'] in h and L['inject_support_marker'] in io.open(inj, encoding='utf-8').read()))
out.append('S7 %d' % (L['provenance_file'] == R['exposure']['lane_provenance']['file'] and L['provenance_schema'] == R['exposure']['lane_provenance']['schema']))
# (10-03) 새 엔진 경로 — 레인 설정 wdir_prefix 로 만든 디렉터리 이름이 규칙 설정 engine_dir_regex 에 맞고, 옛 이름(RP_AUTO_<slug>)·결합 접두는 안 맞는다 ·
#   레인 셸 기본값(LANE_WDIR_PREFIX=…)도 같은 접두
edr = R['exposure']['lane_provenance'].get('engine_dir_regex') or ''
shp = re.search(r'LANE_WDIR_PREFIX=([A-Za-z0-9_]+)\s*$', lane, re.M)
out.append('S8 %d' % (bool(edr) and bool(re.search(edr, L['wdir_prefix'] + '1505_00328')) and not re.search(edr, 'RP_AUTO_1505_00328')
                       and not re.search(edr, 'RP_AUTO_COMBO_x') and bool(shp) and shp.group(1) == L['wdir_prefix']))
print('\n'.join(out))
PYEOF
)"
sv(){ printf '%s\n' "$sres" | tr -d '\r' | awk -v k="$1" '$1==k{print $2}'; }
[ "$(sv S1)" = 1 ] && ok "S1 가드 target_regex·target_keys = 규칙 설정 perf_path_regex·tool_target_keys(막는 식 = 사후 검사 식)" || ng "S1 동기화" "$sres"
[ "$(sv S2)" = 1 ] && ok "S2 가드 청정 통과 표식(PASS_OUT) = 규칙 설정 guard_attestation.pass_stdout" || ng "S2 통과 표식 동기화" "$sres"
[ "$(sv S3)" = 1 ] && ok "S3 레인 청정 호출·출처 기록의 --disallowed 리터럴 = 레인 설정 disallowed_tools_clean" || ng "S3 레인 금지 목록" "$sres"
[ "$(sv S4)" = 1 ] && ok "S4 감사 셸 2종 청정 분기 --disallowed-tools = 레인 설정 audit_disallowed_tools_clean" || ng "S4 감사 금지 목록" "$sres"
[ "$(sv S5)" = 1 ] && ok "S5 규칙 설정 web.forbidden_regex 가 레인 설정 web_forbidden 전부를 잡는다" || ng "S5 웹 금지" "$sres"
[ "$(sv S6)" = 1 ] && ok "S6 레인 설정 지원 표식이 가드·주입 훅 본문에 실재(구판 훅 위에서 청정 주장 불가)" || ng "S6 지원 표식" "$sres"
[ "$(sv S7)" = 1 ] && ok "S7 출처 기록 파일·스키마 = 규칙 설정 lane_provenance" || ng "S7 출처 기록 동기화" "$sres"
[ "$(sv S8)" = 1 ] && ok "S8 새 엔진 경로 — 레인 wdir_prefix(설정·셸 기본값) 디렉터리 ∈ 규칙 engine_dir_regex · 옛 이름·결합 접두 ∉" || ng "S8 새 엔진 경로 동기화" "$sres"

# ═══ G 가드 ═══
echo "--- G. 가드(청정 표식) ---"
SBX="$T/root"; HOMEF="$T/home"
mkdir -p "$SBX/02_Infrastructure/hooks/policies" "$SBX/02_Infrastructure/ops" "$T/cases" "$T/gb"
cp "$SRC_HOOK" "$SBX/02_Infrastructure/hooks/arm_gen_read_guard.sh"; cp "$SRC_POL" "$SBX/02_Infrastructure/hooks/policies/arm_gen_read_guard.json"
cp "$SRC_OPS/rf_b1_design_lib.R" "$SBX/02_Infrastructure/ops/rf_b1_design_lib.R"
HOOK="$SBX/02_Infrastructure/hooks/arm_gen_read_guard.sh"
mk(){ mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }
WD="$SBX/04_Research/strategies/RP_AUTO_CLEAN_9901_00050"
mk "$WD/engine.R" 'FACTORS <- data.table::data.table()'; mk "$WD/FIDELITY.json" '{"fidelity":"faithful","kept":"k","changed":"c"}'
mk "$WD/prompt.txt" 'prompt'; mk "$WD/fidelity_audit.json" '{"verdict":"faithful"}'; mk "$WD/sub/notes.txt" 'n'
mk "$SBX/04_Research/strategies/RP_AUTO_COMBO_x/engine.R" '# 1판 Grade C · PORT_t 0.691 · Calmar 0.235'
mk "$SBX/06_Registry/reinforce_ledger_l1.json" '{"entries":[]}'
mk "$SBX/stage_artifacts/replication/r1/06_metrics.csv" 'cagr,sharpe'
mk "$SBX/02_Infrastructure/backtest_harness.R" 'load_rawdata <- function() NULL'
mk "$SBX/02_Infrastructure/config.R" '# CAGR 11.1 SR 0.796'
mk "$SBX/02_Infrastructure/factor_db/factor_db_connector.R" 'load_month_factors <- function(d) NULL'
mk "$SBX/02_Infrastructure/factor_db/factor_registry.json" '{"S01_Size":{"category":"size","definition":"-log(MarketCap)","dedup":{"reason":"승인 게이트 통계 우위(port_t +0.194 vs -0.106)"}}}'
mk "$SBX/02_Infrastructure/data/loader_x.R" 'load_x <- function() NULL'
mk "$SBX/02_Infrastructure/contracts/essence_score.R" 'x'; mk "$SBX/02_Infrastructure/contracts/other.R" 'x'
mk "$SBX/02_Infrastructure/docs/CHANGELOG.md" 'Calmar 0.609'
mk "$SBX/.claude/rules/pit.md" '# PIT'; mk "$SBX/.claude/rules/measurement-graduation.md" 'PORT_t +1.065'
mk "$SBX/.claude/skills/factor-db-access.md" '# fdb'; mk "$SBX/CLAUDE.md" '# c'
mkdir -p "$SBX/.cache/design_view"; mk "$SBX/.cache/design_view/v.json" '{"a":"<stat>"}'
mk "$HOMEF/.claude/plans/plan.md" 'PORT_t 3.589'; mk "$HOMEF/.claude/projects/C--fake/memory/MEMORY.md" 'm'
mk "$T/outside/x.txt" 'x'
SBXW="$(wp "$SBX")"; HOMEW="$(wp "$HOMEF")"; WDW="$(wp "$WD")"
"$PY" - "$(wp "$T/cases")" "$SBXW" "$HOMEW" "$WDW" "$(wp "$T/outside/x.txt")" <<'PYEOF'
import io, json, os, sys
out, sb, home, wd, outside = sys.argv[1:6]
rows = []
def put(cid, want, tool, ti, desc):
    obj = {'session_id': 't', 'hook_event_name': 'PreToolUse', 'cwd': sb, 'tool_name': tool, 'tool_input': ti}
    io.open(os.path.join(out, cid + '.json'), 'w', encoding='utf-8', newline='').write(json.dumps(obj, ensure_ascii=False))
    rows.append('\t'.join([cid, want, desc]))
B = '\\'
R = lambda cid, want, fp, d: put(cid, want, 'Read', {'file_path': fp}, d)
G = lambda cid, want, ti, d: put(cid, want, 'Grep', dict({'pattern': 'load_'}, **ti), d)
L = lambda cid, want, ti, d: put(cid, want, 'Glob', ti, d)
# 위반 주입 — 청정 표식에서 block
R('CB01', 'block', '06_Registry/reinforce_ledger_l1.json', '원장(R6_target)')
R('CB02', 'block', sb + B + 'stage_artifacts' + B + 'replication' + B + 'r1' + B + '06_metrics.csv', '복제 산출물(역슬래시 절대)')
R('CB03', 'block', '04_Research/strategies/RP_AUTO_COMBO_x/engine.R', '다른 전략 엔진(주석 실측 PORT_t — R6_scope)')
R('CB04', 'block', '02_Infrastructure/config.R', 'config.R(허용 목록 밖 — 주석 CAGR·SR)')
R('CB05', 'block', '.claude/rules/measurement-graduation.md', '경로 주입 규칙 원문(실측 수치 19곳)')
R('CB06', 'block', home + '/.claude/plans/plan.md', '저장소 밖 계획서(R6_outside)')
R('CB07', 'block', outside, '저장소 밖 임의 파일(R6_outside)')
R('CB08', 'block', '02_Infrastructure/contracts/other.R', 'contracts/**(경로 주입 규칙 measurement-graduation 끌림)')
R('CB09', 'block', '02_Infrastructure/docs/CHANGELOG.md', 'docs(성과 이력)')
R('CB10', 'block', wd + '/fidelity_audit.json', '작업 디렉터리의 감사 파일(R6_target fidelity_audit)')
R('CB11', 'block', wd + '/../RP_AUTO_COMBO_x/engine.R', '작업 디렉터리 .. 탈출')
R('CB12', 'block', '02_Infrastructure/contracts/essence_score.R', 'essence 코드(R6_target)')
G('CB13', 'block', {}, 'Grep 무경로(루트 = 범위 넓음)')
G('CB14', 'block', {'path': '04_Research'}, 'Grep 04_Research(다른 전략 전부)')
G('CB15', 'block', {'path': '02_Infrastructure/data', 'pattern': 'essence'}, 'Grep 허용 디렉터리 + 패턴 성과 토큰(사후 검사 키)')
G('CB16', 'block', {'path': '02_Infrastructure'}, 'Grep 02_Infrastructure 전체(허용 디렉터리 밖 포함)')
L('CB17', 'block', {'pattern': home + '/.claude/plans/*.md'}, 'Glob 저장소 밖(계획서 이름)')
L('CB18', 'block', {'pattern': '**/stage_artifacts/**'}, 'Glob 패턴 성과 토큰(R6_target)')
R('CB19', 'block', '~/.claude/projects/C--fake/memory/MEMORY.md', '기억 MEMORY.md')
R('CB20', 'block', '02_Infrastructure/factor_db/factor_registry.json', '팩터 등록부(허용 · R5 가린 사본 안내)')
# 양성 대조 — 청정 표식에서 통과(출력 = {"continue":true})
R('CP01', 'pass', wd + '/engine.R', '작업 디렉터리 엔진')
R('CP02', 'pass', wd + B + 'FIDELITY.json', '작업 디렉터리 FIDELITY(역슬래시)')
R('CP03', 'pass', '04_Research/strategies/RP_AUTO_CLEAN_9901_00050/prompt.txt', '작업 디렉터리 프롬프트(상대)')
G('CP04', 'pass', {'path': wd}, 'Grep 작업 디렉터리(무필터 · 구역 표본 대조 예외)')
R('CP05', 'pass', '02_Infrastructure/factor_db/factor_db_connector.R', '허용: 팩터 DB 커넥터')
R('CP06', 'pass', '02_Infrastructure/backtest_harness.R', '허용: 하네스(로더)')
G('CP07', 'pass', {'path': '02_Infrastructure/data'}, 'Grep 허용 디렉터리(data)')
L('CP08', 'pass', {'pattern': '**/*.R'}, 'Glob 이름 열거(저장소 안)')
R('CP09', 'pass', 'CLAUDE.md', '허용: CLAUDE.md(자동 주입 · 알려진 경계)')
R('CP10', 'pass', '.claude/skills/factor-db-access.md', '허용: 팩터 DB 규약 문서')
R('CP11', 'pass', '.cache/design_view/v.json', '허용: 가린 사본')
R('CP12', 'pass', '02_Infrastructure/data/loader_x.R', '허용: 로더 코드')
L('CP13', 'pass', {'pattern': '*', 'path': wd}, 'Glob 작업 디렉터리')
io.open(os.path.join(out, 'expect.tsv'), 'w', encoding='utf-8', newline='').write('\n'.join(rows) + '\n')
PYEOF
gfire(){ # $1 = 표식(0|clean|design) $2 = json [$3 = 훅] [$4 = QVEST_PY_BIN]
  local h="${3:-$HOOK}" e=()
  case "$1" in clean) e=(QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$WDW") ;; design) e=(QVEST_DESIGN_LANE=1) ;; esac
  [ -n "${4:-}" ] && e+=(QVEST_PY_BIN="$4")
  (cd "$SBX" && env -u QVEST_DESIGN_LANE -u QVEST_ARM_GEN -u QVEST_CLEAN_LANE -u QVEST_CLEAN_WDIR -u QVEST_PY_BIN -u QVEST_RF_ROOT -u CLAUDE_CONFIG_DIR \
     ${e[@]+"${e[@]}"} QVEST_PY="$PY" USERPROFILE="$HOMEW" HOME="$HOMEF" CLAUDE_PROJECT_DIR="$SBXW" QM_ROOT="$SBXW" \
     QVEST_ARM_GEN_GUARD_LOG="$T/guard.log" bash "$h" < "$2" 2>/dev/null)
}
gv(){ case "$1" in *'"decision":"block"'*) echo block ;; '{"continue":true}') echo pass ;; '{}') echo quiet ;; *) echo "odd:${1:0:100}" ;; esac; }
while IFS=$'\t' read -r id want desc; do
  out="$(gfire clean "$T/cases/$id.json")"; got="$(gv "$out")"
  printf '%s' "$out" > "$T/gb/$id.out"
  if [ "$got" = "$want" ]; then
    if [ "$want" = block ]; then case "$out" in *'ARM_GEN_READ_BLOCKED[clean_lane'*) ok "$id $desc → block(표식 clean_lane)" ;; *) ng "$id $desc" "차단 사유에 clean_lane 표식 없음: ${out:0:160}" ;; esac
    else ok "$id $desc → 통과 출력 {\"continue\":true}(증명 표식)"; fi
  else ng "$id $desc" "기대 $want · 실제 $got · ${out:0:200}"; fi
done < "$T/cases/expect.tsv"
case "$(cat "$T/gb/CB20.out")" in *'design_view'*) ok "G1 등록부 차단은 R5 가린 사본 경로를 안내한다(청정 레인에도 R5)" ;; *) ng "G1 R5 사본 안내" "$(head -c 200 "$T/gb/CB20.out")" ;; esac
bad=""; while IFS=$'\t' read -r id want desc; do [ "$(gfire 0 "$T/cases/$id.json")" = '{}' ] || bad="$bad $id"; done < "$T/cases/expect.tsv"
[ -z "$bad" ] && ok "G2 평시(표식 없음) 전 사례 '{}' — 소음 0" || ng "G2 평시 발화" "$bad"
out="$(gfire clean "$T/cases/CP01.json" "" "$T/no_python.exe")"; [ "$(gv "$out")" = block ] && case "$out" in *clean_lane*) true ;; *) false ;; esac \
  && ok "G3 fail-closed: 판정기 부재 → 작업 디렉터리 Read 도 block(청정 표식 · clean_lane)" || ng "G3 fail-closed" "$out"
"$PY" - "$(wp "$SBX/02_Infrastructure/hooks/policies/arm_gen_read_guard.json")" "$(wp "$T/pol_noclean.json")" <<'PYEOF'
import io, json, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d.pop('clean_lane', None)
io.open(sys.argv[2], 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
PYEOF
mkdir -p "$T/hk2/02_Infrastructure/hooks/policies"; cp "$HOOK" "$T/hk2/02_Infrastructure/hooks/"; cp "$T/pol_noclean.json" "$T/hk2/02_Infrastructure/hooks/policies/arm_gen_read_guard.json"
out="$(gfire clean "$T/cases/CP05.json" "$T/hk2/02_Infrastructure/hooks/arm_gen_read_guard.sh")"
case "$out" in *'R6_policy'*) ok "G4 fail-closed: clean_lane 설정 부재 → 허용 목록 파일도 block(R6_policy)" ;; *) ng "G4 설정 부재" "${out:0:200}" ;; esac
# 차등 회귀 — 설계 표식 출력은 구판 훅(QVEST_CL_BASE_HOOK)과 바이트 동일
if [ -n "${QVEST_CL_BASE_HOOK:-}" ] && [ -f "$QVEST_CL_BASE_HOOK" ]; then
  mkdir -p "$T/hk0/02_Infrastructure/hooks/policies" "$T/hk0/02_Infrastructure/ops"
  cp "$QVEST_CL_BASE_HOOK" "$T/hk0/02_Infrastructure/hooks/arm_gen_read_guard.sh"
  cp "${QVEST_CL_BASE_POLICY:-$SRC_POL}" "$T/hk0/02_Infrastructure/hooks/policies/arm_gen_read_guard.json"
  cp "$SRC_OPS/rf_b1_design_lib.R" "$T/hk0/02_Infrastructure/ops/"
  diffs=""; n=0
  while IFS=$'\t' read -r id want desc; do
    n=$((n+1)); a="$(gfire design "$T/cases/$id.json" "$T/hk0/02_Infrastructure/hooks/arm_gen_read_guard.sh")"; b="$(gfire design "$T/cases/$id.json")"
    [ "$a" = "$b" ] || diffs="$diffs $id"
  done < "$T/cases/expect.tsv"
  [ -z "$diffs" ] && ok "G5 설계 레인 표식 출력 = 구판 훅과 바이트 동일(${n}사례 — 청정 변경이 설계 레인에 새지 않는다)" || ng "G5 설계 레인 차등" "$diffs"
else sk "G5 설계 레인 차등" "QVEST_CL_BASE_HOOK 미지정"; fi

# ═══ I 주입 훅 ═══
echo "--- I. 주입 훅(성과 문맥 제외) ---"
IR="$T/iroot"; mkdir -p "$IR/02_Infrastructure/hooks" "$IR/qepm/memory/axioms/active" "$IR/.cache"
cp "$SRC_INJ" "$IR/02_Infrastructure/hooks/axiom_context_inject.sh"; cp "$SRC_HOOK" "$IR/02_Infrastructure/hooks/" 2>/dev/null
[ -f "$ROOT/02_Infrastructure/hooks/_shared_parse.sh" ] && cp "$ROOT/02_Infrastructure/hooks/_shared_parse.sh" "$IR/02_Infrastructure/hooks/"
printf '%s\n' '{"axiom_id":"AX-000","statement":"한계는 대개 법칙이 아니라 방법의 한계다.","type":"IMMUTABLE","polarity":"axiom"}' > "$IR/qepm/memory/axioms/active/AX-000.json"
printf '%s\n' '# c' '<!-- FRONTIER_AXES_START -->' '> ★고정 축 완화를 레버로 제시 금지. 조건-안 레버만 프론티어 — 현행: ① 비대칭 표적.' '<!-- FRONTIER_AXES_END -->' > "$IR/CLAUDE.md"
"$PY" - "$(wp "$IR/.cache/positive_context.json")" <<'PYEOF'
import io, json, sys
io.open(sys.argv[1], 'w', encoding='utf-8').write(json.dumps({
  'positive_block': '- STR_AS_20260709_074129_30048 B s50.4 PORT_t 2.58 SR 0.87 CAGR 21% MDD 61% OOS -0.05 | Chen-Welch',
  'dist_block': '- DIST-QPM-014 IC 0.22 ICIR 1.88',
  'recent_block': '- L-RF-20260925_233320 C | [B7] 최고 B7_41 다중검정t 1.026 · 칼마 0.247',
  'dead_line': '[dead configs 597 — 착수 전 hypothesis_index.R lookup 1줄 확인]'}, ensure_ascii=False))
PYEOF
printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' > "$T/agent.json"
ifire(){ (cd "$IR" && env -u QVEST_CLEAN_LANE ${1:+QVEST_CLEAN_LANE=1} QVEST_PY_BIN="$PY" QVEST_PY="$PY" CLAUDE_PROJECT_DIR="$(wp "$IR")" QM_ROOT="$(wp "$IR")" \
          bash "${2:-$IR/02_Infrastructure/hooks/axiom_context_inject.sh}" < "$T/agent.json" 2>/dev/null); }
ictx(){ printf '%s' "$1" | "$PY" -c "import json,sys
try: print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])
except Exception as e: print('PARSE_FAIL', e)"; }
# ★자료는 파일로 넘긴다 — 파이프 + heredoc 은 둘 다 stdin 이라 스크립트가 자료를 못 읽는다(0 = 공허한 통과가 된다)
mhits(){ printf '%s' "$1" > "$T/mh_in.txt"; "$PY" - "$(wp "$SRC_RULECFG")" "$(wp "$T/mh_in.txt")" <<'PYEOF'
import io, json, re, sys
R = json.load(io.open(sys.argv[1], encoding='utf-8'))['exposure']['transcript']['auto_memory']['metric_regex']
s = io.open(sys.argv[2], encoding='utf-8').read(); print(sum(len(re.findall(x, s)) for x in R))
PYEOF
}
n0="$(ictx "$(ifire "")")"; n1="$(ictx "$(ifire 1)")"
h0="$(mhits "$n0" | tr -d '\r')"; h1="$(mhits "$n1" | tr -d '\r')"
case "$n0" in *'PORT_t 2.58'*'칼마 0.247'*) [ "${h0:-0}" -gt 0 ] && ok "I1 평시 = 성과 줄 실림(최고 전략 PORT_t · 최근 교훈 · 수치 ${h0}곳 — 양성 대조)" || ng "I1" "h0=$h0" ;; *) ng "I1 평시 성과 줄" "${n0:0:300}" ;; esac
case "$n1" in *'청정 레인 — 성과·교훈·dead 문맥 제외'*) [ "${h1:-x}" = 0 ] && ok "I2 청정 = 수치 0 · 청정 표식 줄(최고 전략·교훈·dead 줄 제외)" || ng "I2 청정 수치 잔존" "hits=$h1" ;; *) ng "I2 청정 표식 줄" "${n1:0:300}" ;; esac
case "$n1" in *'[AX 전제]'*'AX-000'*'고정 축'*) ok "I3 청정에도 고정부(공리·고정 축) 유지" ;; *) ng "I3 고정부" "${n1:0:200}" ;; esac
"$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if d.get('clean_lane') is True and d.get('pc_status')=='clean_lane_excluded' else 1)" "$(wp "$IR/.cache/axiom_inject_last.json")" \
  && ok "I4 계측 파일에 clean_lane=true · pc_status=clean_lane_excluded(샌드박스 .cache)" || ng "I4 계측" "$(head -c 300 "$IR/.cache/axiom_inject_last.json" 2>/dev/null)"

# ═══ M 모드 해석 ═══
echo "--- M. 모드 해석 ---"
MR="$T/mroot"; mkdir -p "$MR/02_Infrastructure/hooks/policies" "$MR/06_Registry/prereg"
cp "$SRC_HOOK" "$MR/02_Infrastructure/hooks/"; cp "$SRC_POL" "$MR/02_Infrastructure/hooks/policies/"; cp "$SRC_INJ" "$MR/02_Infrastructure/hooks/"
cp "$SRC_RULECFG" "$MR/06_Registry/prereg/"; cp "$SRC_LANECFG" "$MR/06_Registry/"
mcase(){ # $1 id $2 요청 json $3 combo $4 기대 모드 $5 기대 출처 [$6 lane cfg]
  local rq="$T/req_$1.json"; printf '%s' "$2" > "$rq"
  local o; o="$("$PY" "$(wp "$SRC_OPS/rf_clean_lane.py")" mode --req "$(wp "$rq")" --lane-cfg "$(wp "${6:-$MR/06_Registry/replication_clean_lane.json}")" --root "$(wp "$MR")" --combo "$3" 2>&1 | tr -d '\r')"
  local m s; m="$(printf '%s\n' "$o" | sed -n "s/^LANE_MODE=\(.*\)$/\1/p" | tr -d "'")"; s="$(printf '%s\n' "$o" | sed -n "s/^LANE_MODE_SOURCE=\(.*\)$/\1/p" | tr -d "'")"
  if [ "$m" = "$4" ] && [ "$s" = "$5" ]; then ok "M$1 → $m ($s)"; else ng "M$1" "기대 $4/$5 · 실제 $m/$s · $o"; fi
}
mcase 1 '{"paper":{"paper_key":"9901.1"},"status":"pending","combo":{"papers":[]}}' 1 normal combo_forced
mcase 2 '{"paper":{"paper_key":"9901.1"},"status":"pending"}' 0 clean config_default
mcase 3 '{"paper":{"paper_key":"9901.1"},"status":"pending","clean_mode":false}' 0 normal request_off
mcase 4 '{"paper":{"paper_key":"9901.1"},"status":"pending","clean_mode":true,"failure":"x"}' 0 clean request
mcase 5 '{"paper":{"paper_key":"9901.1"},"status":"pending","failure":"replication_error","auto_retries":1}' 0 normal legacy_in_flight
mcase 6 '{"paper":{"paper_key":"9901.1"},"status":"pending","lane_mode":"clean","failure":"x"}' 0 clean persisted
mcase 7 '{"paper":{"paper_key":"9901.1"},"status":"pending","lane_mode":"normal"}' 0 normal persisted
"$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if d.get('lane_mode')=='clean' and d.get('lane_mode_source')=='config_default' and d.get('lane_mode_at') else 1)" "$(wp "$T/req_2.json")" \
  && ok "M8 첫 해석을 요청 파일에 지속(lane_mode·source·at — 재시도·검증기 단독 재실행이 같은 작업 디렉터리)" || ng "M8 지속" "$(cat "$T/req_2.json")"
# 전제 미충족 — 구판 가드(표식 없음)로 바꾼 루트
MB="$T/mroot_old"; cp -r "$MR" "$MB"; sed -i "s/PASS_OUT='{\"continue\":true}'/PASS_OUT_REMOVED=1/" "$MB/02_Infrastructure/hooks/arm_gen_read_guard.sh"
mcase_b(){ local rq="$T/reqb_$1.json"; printf '%s' "$2" > "$rq"
  local o; o="$("$PY" "$(wp "$SRC_OPS/rf_clean_lane.py")" mode --req "$(wp "$rq")" --lane-cfg "$(wp "$MB/06_Registry/replication_clean_lane.json")" --root "$(wp "$MB")" --combo 0 2>&1 | tr -d '\r')"
  printf '%s\n' "$o"; }
o="$(mcase_b 9 '{"paper":{"paper_key":"9901.1"},"status":"pending","clean_mode":true}')"
case "$o" in *"LANE_MODE=halt"*guard_without_clean_support*) ok "M9 요청 청정 + 구판 가드 → halt(요청 보존 · 비청정으로 돌지 않는다)" ;; *) ng "M9 halt" "$o" ;; esac
"$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if 'lane_mode' not in d else 1)" "$(wp "$T/reqb_9.json")" && ok "M10 halt 는 요청에 모드를 지속하지 않는다" || ng "M10" "$(cat "$T/reqb_9.json")"
o="$(mcase_b 11 '{"paper":{"paper_key":"9901.1"},"status":"pending"}')"
case "$o" in *"LANE_MODE=normal"*"config_default_degraded"*guard_without_clean_support*) ok "M11 설정 기본 청정 + 구판 가드 → normal(degraded · 사유 기록)" ;; *) ng "M11 degraded" "$o" ;; esac
o="$("$PY" "$(wp "$SRC_OPS/rf_clean_lane.py")" mode --req "$(wp "$T/req_2.json")" --lane-cfg "$(wp "$T/no_cfg.json")" --root "$(wp "$MR")" --combo 0 2>&1 | tr -d '\r')"
printf '%s' '{"paper":{"paper_key":"9901.1"},"status":"pending","clean_mode":true}' > "$T/req_12.json"
o12="$("$PY" "$(wp "$SRC_OPS/rf_clean_lane.py")" mode --req "$(wp "$T/req_12.json")" --lane-cfg "$(wp "$T/no_cfg.json")" --root "$(wp "$MR")" --combo 0 2>&1 | tr -d '\r')"
case "$o12" in *"LANE_MODE=halt"*) ok "M12 레인 설정 부재 + 요청 청정 → halt" ;; *) ng "M12" "$o12" ;; esac
printf '%s' '{"paper":{"paper_key":"9901.1"},"status":"pending"}' > "$T/req_13.json"
o13="$("$PY" "$(wp "$SRC_OPS/rf_clean_lane.py")" mode --req "$(wp "$T/req_13.json")" --lane-cfg "$(wp "$T/no_cfg.json")" --root "$(wp "$MR")" --combo 0 2>&1 | tr -d '\r')"
case "$o13" in *"LANE_MODE=normal"*"lane_config_absent"*) ok "M13 레인 설정 부재 + 요청 무지정 → normal(lane_config_absent)" ;; *) ng "M13" "$o13" ;; esac

# ═══ Z 피드백 가림 ═══
echo "--- Z. 재구현 피드백 가림 ---"
cat > "$T/fb.txt" <<'EOF'
- 미신고 변경: [부호 반전] 논문 식 (3) 은 룩백 12개월 · 상위 10% · 종점 t-1 인데 구현은 부호가 반대다 — 측정 PORT_t -3.438 이 그 지문이다
- 신호 불일치: 측정 산출물 authoritative_remeasure.json::replication.paper_basis (cagr=0.119379, sharpe=0.380497)
- 원문 근거: §3.2 · Table 2 — Calmar 0.235 → 0.40 로 바뀌어야 한다 · 측정 등급 F · Sharpe=0.9
- 비용: 논문은 왕복 20bps · CAGR 21% 는 측정값
EOF
zrun(){ "$PY" "$(wp "$SRC_OPS/rf_clean_lane.py")" sanitize --lane-cfg "$(wp "${2:-$SRC_LANECFG}")" --root "$(wp "$MR")" --rule-cfg "$(wp "$SRC_RULECFG")" --kind audit --stats "$(wp "$1")" < "$T/fb.txt"; }
zo="$(zrun "$T/z_stats.json" | tr -d '\r')"
zchk(){ printf '%s' "$1" > "$T/zc_in.txt"; "$PY" - "$(wp "$SRC_RULECFG")" "$(wp "$T/zc_in.txt")" <<'PYEOF'
import io, json, re, sys
R = json.load(io.open(sys.argv[1], encoding='utf-8'))['exposure']
rx = R['prompt']['measured_ref_regex'] + R['transcript']['auto_memory']['metric_regex']
s = io.open(sys.argv[2], encoding='utf-8').read()
print(sum(1 for l in s.split('\n') if any(re.search(x, l) for x in rx)))
PYEOF
}
zr_in="$(zchk "$(cat "$T/fb.txt")" | tr -d '\r')"
[ "${zr_in:-0}" -ge 3 ] && ok "Z0 양성 대조 — 가림 전 입력은 사후 검사 정규식에 ${zr_in}줄 걸린다(계기가 실린다)" || ng "Z0 계기 적재" "$zr_in"
zr="$(zchk "$zo" | tr -d '\r')"
[ "$zr" = 0 ] && ok "Z1 가린 뒤 사후 검사 정규식(measured_ref 3 + metric 2) 잔존 줄 0" || ng "Z1 잔존" "$zr · $zo"
case "$zo" in *'룩백 12개월'*'상위 10%'*'t-1'*) ok "Z2 논문 파라미터 보존(12개월 · 10% · t-1 — 지표 이름 뒤가 아니다)" ;; *) ng "Z2 파라미터 보존" "$zo" ;; esac
case "$zo" in *'authoritative_remeasure'*|*'0.119379'*|*'-3.438'*|*'0.235'*|*'등급 F'*|*'21%'*) ng "Z3 성과 잔존" "$zo" ;; *) ok "Z3 측정 참조 줄 제거 + PORT_t·Calmar 화살표·등급·CAGR% 가림" ;; esac
case "$zo" in *'[부호 반전]'*'부호가 반대다'*) ok "Z4 충실도 사유 문장은 남는다(지적 요지 보존)" ;; *) ng "Z4 사유 보존" "$zo" ;; esac
"$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if d['dropped_ref']>=1 and d['masked']>=4 and d['lines_in']==d['lines_out'] and d['rules_sha256'] else 1)" "$(wp "$T/z_stats.json")" \
  && ok "Z5 가림 통계(제거 줄 ≥1 · 가림 ≥4 · 줄 수 보존 · 규칙 지문)" || ng "Z5 통계" "$(cat "$T/z_stats.json")"
"$PY" - "$(wp "$SRC_LANECFG")" "$(wp "$T/lane_nomask.json")" <<'PYEOF'
import io, json, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d['feedback_sanitize']['mask_regex'] = []; d['feedback_sanitize']['drop_line_regex'] = []
io.open(sys.argv[2], 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
PYEOF
zo2="$(zrun "$T/z2.json" "$T/lane_nomask.json" | tr -d '\r')"; zr2="$(zchk "$zo2" | tr -d '\r')"
"$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if d['dropped_residual']>=3 else 1)" "$(wp "$T/z2.json")" && [ "$zr2" = 0 ] \
  && ok "Z6 fail-closed: 가림 규칙을 비워도 사후 재검이 잔존 줄을 뺀다(dropped_residual ≥3 · 잔존 0)" || ng "Z6 사후 재검" "zr2=$zr2 $(cat "$T/z2.json")"
printf '{"feedback_sanitize":{"mask":"<stat>"}}' > "$T/lane_broken.json"
zrun "$T/z3.json" "$T/lane_broken.json" >/dev/null 2>&1; [ $? -ne 0 ] && ok "Z7 가림 규칙 판독 불능 → rc≠0(레인 halt 경로)" || ng "Z7 규칙 불능" "rc=0"

# ═══ W 배선(정적) ═══
echo "--- W. 배선(정적) ---"
wres="$("$PY" - "$(wp "$SRC_OPS")" <<'PYEOF'
import io, os, re, sys
ops = sys.argv[1]
SH = ['Bash', 'PowerShell', 'Monitor', 'REPL', 'Workflow', 'CronCreate', 'RemoteTrigger']
def blocks(lines, i):
    b = [lines[i]]; j = i
    while lines[j].rstrip().endswith('\\') and j + 1 < len(lines):
        j += 1; b.append(lines[j])
    return '\n'.join(b)
def tl(b, opt):
    m = re.search(opt + r'\s+"([^"]*)"', b); return None if not m else [t.strip() for t in m.group(1).split(',')]
L = io.open(os.path.join(ops, 'rf_replication_auto.sh'), encoding='utf-8').read().splitlines()
res = []
cl = [i for i, l in enumerate(L) if not l.strip().startswith('#') and re.search(r'(^|\s)QVEST_CLEAN_LANE=1\s.*rf_llm_agent_run', l)]
ok1 = len(cl) == 1
if ok1:
    b = blocks(L, cl[0]); dl, al = tl(b, '--disallowed-tools'), tl(b, '--allowed-tools')
    ok1 = 'QVEST_CLEAN_WDIR="$WDIR"' in b and dl is not None and all(t in dl for t in SH + ['Agent', 'Skill']) and al is not None and not any(t in al for t in SH + ['Agent', 'Skill'])
res.append('W1 %d' % ok1)
nm = [i for i, l in enumerate(L) if re.match(r'\s*rf_llm_agent_run "\$PF" "\$RUN_OUT" 3000', l)]
ok2 = len(nm) == 1 and tl(blocks(L, nm[0]), '--disallowed-tools') == ['Bash', 'Agent']
res.append('W2 %d' % ok2)
res.append('W3 %d' % (not any(re.search(r'\bexport\s+QVEST_CLEAN_(LANE|WDIR)\b', l) for l in L if not l.strip().startswith('#'))))
txt = '\n'.join(L)
res.append('W4 %d' % (txt.count('prov-pre') >= 2 and 'prov-post' in txt and 'RP_LANE_MODE="$LANE_MODE"' in txt))
V = io.open(os.path.join(ops, 'rf_replication_verify.R'), encoding='utf-8').read()
m = re.search(r'\.spawn_audit <- function\(\) \{([\s\S]*?)\n\}', V)
res.append('W5 %d' % (bool(m) and 'rcl_with_env(rcl_clean_env(WDIR)' in m.group(1) and 'rcl_audit_art(TRUE' in m.group(1)))
res.append('W6 %d' % ('audit_feedback_mode' in V and 'rcl_archive_audit_src' in V and 'rcl_prov_audit' in V))
print('\n'.join(res))
PYEOF
)"
wv(){ printf '%s\n' "$wres" | tr -d '\r' | awk -v k="$1" '$1==k{print $2}'; }
[ "$(wv W1)" = 1 ] && ok "W1 레인 청정 호출 1곳: 표식 2종(QVEST_CLEAN_LANE · QVEST_CLEAN_WDIR) · 셸 7종+Agent+Skill 금지 · 허용 목록에 없음" || ng "W1" "$wres"
[ "$(wv W2)" = 1 ] && ok "W2 normal 호출은 구판 그대로(--disallowed-tools Bash,Agent)" || ng "W2" "$wres"
[ "$(wv W3)" = 1 ] && ok "W3 청정 표식 export 0(호출 앞 임시 대입만 — 검증기·자식에 안 샌다)" || ng "W3" "$wres"
[ "$(wv W4)" = 1 ] && ok "W4 출처 기록 실행 전(청정·normal)·후 + 검증기에 RP_LANE_MODE" || ng "W4" "$wres"
[ "$(wv W5)" = 1 ] && ok "W5 검증기 감사 스폰 = 도우미 경유(표식 임시 대입 · 산출물 경로 비움)" || ng "W5" "$wres"
[ "$(wv W6)" = 1 ] && ok "W6 검증기: 감사 지적 출처 모드 · 원천 보존 · 출처 기록 덧붙임" || ng "W6" "$wres"

# ═══ D 레인(동적) ═══
echo "--- D. 레인(동적 · 가짜 claude·Rscript) ---"
LR="$T/lroot"; FB="$T/fakebin"; mkdir -p "$LR/02_Infrastructure/ops" "$LR/02_Infrastructure/hooks/policies" "$LR/06_Registry/prereg" "$LR/.cache" \
  "$LR/qepm/memory/axioms/active" "$LR/04_Research/strategies" "$LR/stage_artifacts" "$FB" "$T/rec"
for f in rf_replication_auto.sh rf_clean_lane.py rf_llm_env.sh rf_axiom_brief.sh refresh_barrier.sh; do cp "$SRC_OPS/$f" "$LR/02_Infrastructure/ops/"; done
printf '# stub verify — 실제 호출은 가짜 Rscript 가 기록한다\n' > "$LR/02_Infrastructure/ops/rf_replication_verify.R"
cp "$SRC_HOOK" "$SRC_INJ" "$LR/02_Infrastructure/hooks/"; cp "$SRC_POL" "$LR/02_Infrastructure/hooks/policies/"
cp "$SRC_RULECFG" "$LR/06_Registry/prereg/"; cp "$SRC_LANECFG" "$LR/06_Registry/"
cp "$MR/../iroot/qepm/memory/axioms/active/AX-000.json" "$LR/qepm/memory/axioms/active/" 2>/dev/null || true
printf '%s' '{"enabled":true,"claim_stale_hours":6,"llm":{"model":"opus","effort":"low","lanes":{"replication":{"model":"opus","effort":"low"}}}}' > "$LR/06_Registry/reinforce_auto_config.json"
printf '%s' '{"schema_version":1,"entries":[]}' > "$LR/06_Registry/reinforce_ledger_l1.json"
printf '# CLAUDE\n' > "$LR/CLAUDE.md"; mkdir -p "$LR/.claude/rules"; printf '# pit\n' > "$LR/.claude/rules/pit.md"
cat > "$FB/claude" <<'EOF'
#!/usr/bin/env bash
# 가짜 claude — 받은 표식·인자·프롬프트를 기록하고 엔진 1개를 쓴다(작업 디렉터리 = QVEST_CLEAN_WDIR 또는 --add-dir)
R="${FAKE_REC:?}"; n=$(ls "$R" 2>/dev/null | grep -c '^call_' ); n=$((n+1))
{ printf 'CLEAN=%s\nWDIRENV=%s\nUNA=%s\nAM=%s\n' "${QVEST_CLEAN_LANE:-}" "${QVEST_CLEAN_WDIR:-}" "${QVEST_UNATTENDED_LANE:-}" "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}"
  printf 'ARGS=%s\n' "$*"; } > "$R/call_$n.env"
cat > "$R/call_$n.prompt"
wd=""; prev=""; for a in "$@"; do [ "$prev" = "--add-dir" ] && wd="$a"; prev="$a"; done
[ -n "${QVEST_CLEAN_WDIR:-}" ] && wd="$QVEST_CLEAN_WDIR"
if [ -n "$wd" ] && [ "${FAKE_NO_ENGINE:-0}" != 1 ]; then
  printf '%s\n' 'suppressPackageStartupMessages(library(data.table))' 'DT <- as.data.table(RAWDATA)' 'setorder(DT, Ticker, Date)' \
    'DT[, r1 := data.table::shift(Close, 1L, type = "lag") / data.table::shift(Close, 2L, type = "lag") - 1, by = Ticker]' \
    'FACTORS <- DT[is.finite(r1), .(Date, Ticker, Score = -r1)]' > "$wd/engine.R"
  printf '%s' '{"fidelity":"faithful","kept":"k","changed":"유니버스만 K200 합집합 KQ150","paper_original_form":"f","portfolio_spec":{"construction":"top_n_long","weighting":"ew","rebalance":"monthly","top_n":25},"commission_paper":null}' > "$wd/FIDELITY.json"
fi
echo "fake claude done"
EOF
cat > "$FB/Rscript" <<'EOF'
#!/usr/bin/env bash
# 가짜 Rscript — 검증기 호출의 환경을 기록(측정 0)
R="${FAKE_REC:?}"; n=$(ls "$R" 2>/dev/null | grep -c '^rscript_'); n=$((n+1))
{ printf 'ARGS=%s\nRP_LANE_MODE=%s\nRP_WDIR=%s\nQVEST_CLEAN_LANE=%s\nQVEST_CLEAN_WDIR=%s\n' "$*" "${RP_LANE_MODE:-}" "${RP_WDIR:-}" "${QVEST_CLEAN_LANE:-}" "${QVEST_CLEAN_WDIR:-}"; } > "$R/rscript_$n.env"
exit 0
EOF
chmod +x "$FB/claude" "$FB/Rscript"
LRW="$(wp "$LR")"
lrun(){ # $1 = 요청 json · 나머지 = 추가 env (레인 사본 = $LANE_SH)
  local rq="$1"; shift
  printf '%s' "$rq" > "$LR/06_Registry/replication_request.json"
  rm -rf "$T/rec"; mkdir -p "$T/rec"; rm -rf "$LR/.cache/rf_replication.claim"
  (cd "$LR" && env -u QVEST_CLEAN_LANE -u QVEST_CLEAN_WDIR -u QVEST_DESIGN_LANE -u QVEST_ARM_GEN PATH="$FB:$PATH" FAKE_REC="$T/rec" \
     QM_ROOT="$LRW" CLAUDE_PROJECT_DIR="$LRW" QVEST_PY="$PY" RF_CLAUDE_BIN="$FB/claude" R_ENVIRON_USER="$EMPTY_RENV" \
     QVEST_RP_REQUEST="$LRW/06_Registry/replication_request.json" QVEST_RF_CONFIG="$LRW/06_Registry/reinforce_auto_config.json" \
     QVEST_RP_JLOG="$LRW/.cache/jlog.jsonl" QVEST_RP_CLAIM="$LRW/.cache/rf_replication.claim" \
     QM_REFRESH_LOCKDIR="$T/no_refresh.lock" QM_RAWDATA_WRITER_LOCKDIR="$T/no_writer.lock" RB_VERIFY_WAIT_S=1 "$@" \
     bash "${LANE_SH:-$LR/02_Infrastructure/ops/rf_replication_auto.sh}" > "$T/lane_out.txt" 2>&1); echo $?
}
recv(){ grep -h "^$2=" "$T/rec/$1" 2>/dev/null | head -1 | cut -d= -f2-; }
REQ_BASE='{"status":"pending","paper":{"paper_key":"9901.00050","url":"https://arxiv.org/abs/9901.00050","paper_title":"T","factor_name":"f","factor_def":"d"}}'
rc="$(lrun "$REQ_BASE")"
CWD1="$LR/04_Research/strategies/RP_AUTO_CLEAN_9901_00050"
if [ -f "$T/rec/call_1.env" ]; then
  [ -d "$CWD1" ] && [ ! -d "$LR/04_Research/strategies/RP_AUTO_9901_00050" ] && ok "D1 청정 기본 → 작업 디렉터리 RP_AUTO_CLEAN_9901_00050(구판 디렉터리 미생성)" || ng "D1 작업 디렉터리" "$(ls "$LR/04_Research/strategies")"
  [ "$(recv call_1.env CLEAN)" = 1 ] && [ "$(recv call_1.env UNA)" = 1 ] && [ "$(recv call_1.env AM)" = 1 ] && case "$(recv call_1.env WDIRENV)" in *RP_AUTO_CLEAN_9901_00050) true ;; *) false ;; esac \
    && ok "D2 claude 가 받은 표식 = 청정·작업 디렉터리·무인·자동 기억 차단" || ng "D2 표식" "$(cat "$T/rec/call_1.env")"
  a="$(recv call_1.env ARGS)"; miss=""; for t in Bash PowerShell Monitor REPL Workflow CronCreate RemoteTrigger Agent Skill; do case "$a" in *"--disallowed-tools "*"$t"*) ;; *) miss="$miss $t" ;; esac; done
  [ -z "$miss" ] && ok "D3 claude 인자 --disallowed-tools ⊇ 셸 7종 + Agent + Skill" || ng "D3 금지 누락" "$miss · $a"
  grep -q '^## 청정 모드 — 열람 범위' "$T/rec/call_1.prompt" && grep -q 'factor_db_connector' "$T/rec/call_1.prompt" && head -1 "$T/rec/call_1.prompt" | grep -q '^논문 1편의 \*\*충실구현\*\*' \
    && ok "D4 프롬프트: 첫 줄 불변(전사 색인 규약) + 열람 범위 절(허용 목록 생성)" || ng "D4 프롬프트" "$(head -3 "$T/rec/call_1.prompt")"
  pv="$("$PY" - "$(wp "$CWD1")" <<'PYEOF'
import hashlib, io, json, os, sys
wd = sys.argv[1]; P = json.load(io.open(os.path.join(wd, 'lane_provenance.json'), encoding='utf-8'))
sh = lambda p: hashlib.sha256(open(os.path.join(wd, p), 'rb').read()).hexdigest()
m5 = lambda p: hashlib.md5(open(os.path.join(wd, p), 'rb').read()).hexdigest()
src = P['pre']['injected_context_sources']
fp = hashlib.sha256(json.dumps(src, ensure_ascii=False, sort_keys=True).encode('utf-8')).hexdigest()
ok = (P['schema'] == 'lane_provenance_v1' and P['mode'] == 'clean' and P['clean'] is True and P['pre']['guard']['applied'] is True
      and P['pre']['prompt']['sha256'] == sh('prompt.txt') and P['post']['engine_sha256'] == sh('engine.R') and P['post']['engine_md5'] == m5('engine.R')
      and P['engine_rel'] == '04_Research/strategies/RP_AUTO_CLEAN_9901_00050/engine.R'
      and P['pre']['injected_context_fingerprint'] == fp and src['prompt'] == sh('prompt.txt') and src['mode'] == 'clean'
      and P['pre']['cli']['disallowed_tools'].endswith('Agent,Skill')
      and any(f['path'] == 'CLAUDE.md' for f in P['pre']['known_boundary']['instruction_files']) and P['pre']['guard']['env']['QVEST_CLEAN_LANE'] == '1')
print('1' if ok else json.dumps(P, ensure_ascii=False)[:600])
PYEOF
)"
  [ "$(printf '%s' "$pv" | tr -d '\r')" = 1 ] && ok "D5 출처 기록: mode clean · 가드 적용 · 프롬프트·엔진 sha256/md5 = 실제 파일 · 주입 문맥 지문 재계산 일치 · 새 엔진 경로 · 규칙 파일 지문" || ng "D5 출처 기록" "$pv"
  # (10-03) 검증기 호출 기록을 ARGS 로 고른다 — 레인에 다른 Rscript 호출(HUMAN 키트의 차단 active 계수 Rscript -e …)이 앞서 붙어도
  #   '첫 Rscript = 검증기' 가정이 깨지지 않게(HUMAN 3-way 병합판에서 rscript_1 = 계수 호출이라 D6 이 거짓 실패했다 · 순서 무관 배포)
  RVF="$(grep -l '^ARGS=.*rf_replication_verify\.R' "$T"/rec/rscript_*.env 2>/dev/null | head -1)"; RVF="${RVF##*/}"
  [ -n "$RVF" ] && [ "$(recv "$RVF" RP_LANE_MODE)" = clean ] && [ -z "$(recv "$RVF" QVEST_CLEAN_LANE)" ] && [ -z "$(recv "$RVF" QVEST_CLEAN_WDIR)" ] \
    && ok "D6 검증기에는 RP_LANE_MODE=clean 만 — 가드 표식 누수 0(측정·원장 쓰기는 평소 조건)" || ng "D6 검증기 환경" "${RVF:-검증기 호출 기록 없음} $(cat "$T/rec/${RVF:-none}" 2>/dev/null)"
  "$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if d.get('lane_mode')=='clean' and d.get('status')=='in_progress' else 1)" "$(wp "$LR/06_Registry/replication_request.json")" \
    && ok "D7 요청 파일 lane_mode=clean 지속(다음 tick·검증기 단독 재실행이 같은 디렉터리)" || ng "D7 지속" "$(head -c 400 "$LR/06_Registry/replication_request.json")"
else ng "D1~D7 청정 실행" "claude 미호출 rc=$rc · $(tail -5 "$T/lane_out.txt")"; fi
# 결합 = normal 구판 호출
rc="$(lrun '{"status":"pending","paper":{"paper_key":"combo:9901.1+9901.2","url":"https://arxiv.org/abs/9901.1","paper_title":"C"},"combo":{"papers":[{"key":"9901.1","title":"a","url":"u"}],"item_engines":[{"key":"9901.1","engine":"e","t":1.2}],"best_parent_t":1.2,"tries_before":0}}')"
if [ -f "$T/rec/call_1.env" ]; then
  a="$(recv call_1.env ARGS)"
  [ -z "$(recv call_1.env CLEAN)" ] && case "$a" in *'--disallowed-tools Bash,Agent '*) true ;; *) false ;; esac && ls -d "$LR/04_Research/strategies/RP_AUTO_COMBO_"* >/dev/null 2>&1 \
    && ok "D8 결합 요청 = normal(표식 없음 · 구판 금지 목록 · RP_AUTO_COMBO_ 디렉터리)" || ng "D8 결합" "$(cat "$T/rec/call_1.env")"
  "$PY" -c "import json,sys,glob,os; p=glob.glob(os.path.join(sys.argv[1],'RP_AUTO_COMBO_*','lane_provenance.json')); d=json.load(open(p[0],encoding='utf-8')); sys.exit(0 if d['mode']=='normal' and d['mode_source']=='combo_forced' and d['pre']['guard']['applied'] is False else 1)" "$(wp "$LR/04_Research/strategies")" \
    && ok "D9 normal 실행도 출처 기록(mode normal · combo_forced · 가드 미적용)" || ng "D9 normal 출처 기록" ""
else ng "D8 결합 실행" "claude 미호출 · $(tail -5 "$T/lane_out.txt")"; fi
# 청정 재구현 — 감사 지적(청정 감사) 가림 + 측정 실패 사유 가림
FBJ="$("$PY" -c "import json; print(json.dumps(open(r'$(wp "$T/fb.txt")',encoding='utf-8').read()))")"
REQ_RE="{\"status\":\"pending\",\"lane_mode\":\"clean\",\"lane_mode_source\":\"config_default\",\"paper\":{\"paper_key\":\"9901.00050\",\"url\":\"https://arxiv.org/abs/9901.00050\",\"paper_title\":\"T\"},\"audit_retries\":1,\"audit_feedback\":$FBJ,\"audit_feedback_mode\":\"clean\",\"audit_feedback_src\":\".clean_audit_src/r1\",\"failure\":\"replication_error\",\"failure_detail\":\"Error: PORT_t 1.234 · stage_artifacts/replication/x/06_metrics.csv 판독 실패\"}"
rc="$(lrun "$REQ_RE")"
if [ -f "$T/rec/call_1.prompt" ]; then
  sec="$("$PY" - "$(wp "$T/rec/call_1.prompt")" "$(wp "$SRC_RULECFG")" <<'PYEOF'
import io, json, re, sys
p = io.open(sys.argv[1], encoding='utf-8').read(); R = json.load(io.open(sys.argv[2], encoding='utf-8'))['exposure']
rx = R['prompt']['measured_ref_regex'] + R['transcript']['auto_memory']['metric_regex']
segs = re.split(r'(?m)^## ', p)
fb = [s for s in segs if s.startswith('★재구현')]
hits = sum(1 for s in fb for l in s.split('\n') if any(re.search(x, l) for x in rx))
print('%d %d %d' % (len(fb), hits, int('부호 반전' in p and '룩백 12개월' in p)))
PYEOF
)"
  set -- $(printf '%s' "$sec" | tr -d '\r')
  [ "${1:-0}" = 2 ] && [ "${2:-x}" = 0 ] && [ "${3:-0}" = 1 ] && ok "D10 청정 재구현 프롬프트: 재구현 절 2개(측정 실패·감사) · 성과 잔존 0 · 충실도 사유 보존" || ng "D10 피드백 가림" "$sec"
  [ -f "$CWD1/.clean_fb_audit.json" ] && [ -f "$CWD1/.clean_fb_failure.json" ] && ok "D11 가림 통계 2종(.clean_fb_*) — 출처 기록이 싣는다" || ng "D11 통계" "$(ls -a "$CWD1")"
  "$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); f=d['pre']['feedback']; sys.exit(0 if f['audit_source_mode']=='clean' and f['audit_source_dir']=='.clean_audit_src/r1' and f['audit']['dropped_ref']>=1 else 1)" "$(wp "$CWD1/lane_provenance.json")" \
    && ok "D12 출처 기록: 감사 지적 출처 모드·사본 위치·가림 통계" || ng "D12" "$(head -c 500 "$CWD1/lane_provenance.json")"
else ng "D10~D12 청정 재구현" "claude 미호출 · $(tail -5 "$T/lane_out.txt")"; fi
# 비청정 감사 지적 → 청정 프롬프트에서 제외
rc="$(lrun "$(printf '%s' "$REQ_RE" | sed 's/"audit_feedback_mode":"clean"/"audit_feedback_mode":"normal"/')")"
if [ -f "$T/rec/call_1.prompt" ]; then
  ! grep -q '적대적 충실도 감사에서 기각됐다' "$T/rec/call_1.prompt" && grep -q 'clean_audit_feedback_dropped' "$LR/.cache/jlog.jsonl" \
    && ok "D13 비청정 감사의 지적은 청정 재구현 프롬프트에서 제외 + 저널 clean_audit_feedback_dropped" || ng "D13" "$(grep -c '감사에서 기각' "$T/rec/call_1.prompt")"
else ng "D13" "claude 미호출"; fi
# 전제 미충족(구판 가드) + 요청 청정 → halt · claude 0회 · 요청 보존
cp "$LR/02_Infrastructure/hooks/arm_gen_read_guard.sh" "$T/guard_keep.sh"
sed -i "s/PASS_OUT='{\"continue\":true}'/PASS_OUT_REMOVED=1/" "$LR/02_Infrastructure/hooks/arm_gen_read_guard.sh"
rc="$(lrun '{"status":"pending","clean_mode":true,"paper":{"paper_key":"9901.00051","url":"https://arxiv.org/abs/9901.00051","paper_title":"T"}}')"
cp "$T/guard_keep.sh" "$LR/02_Infrastructure/hooks/arm_gen_read_guard.sh"
[ ! -f "$T/rec/call_1.env" ] && grep -q 'halt_clean_unavailable' "$LR/.cache/jlog.jsonl" && "$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if d['status']=='pending' and 'lane_mode' not in d else 1)" "$(wp "$LR/06_Registry/replication_request.json")" \
  && ok "D14 요청 청정 + 구판 가드 → halt_clean_unavailable · claude 0회 · 요청 pending 보존" || ng "D14 halt" "rc=$rc $(tail -3 "$T/lane_out.txt")"

# ═══ A 감사 셸(동적) ═══
echo "--- A. 감사 셸(동적 · 가짜 claude) ---"
AR="$T/aroot"; mkdir -p "$AR/02_Infrastructure/ops" "$AR/06_Registry" "$AR/.cache" "$AR/qepm/memory/axioms/active" "$AR/wd"
for f in rf_fidelity_audit.sh rf_fidelity_fanout.sh rf_llm_env.sh rf_axiom_brief.sh rf_fidelity_audit_lib.R; do cp "$SRC_OPS/$f" "$AR/02_Infrastructure/ops/" 2>/dev/null; done
printf 'x <- 1\n%.0s' {1..40} > "$AR/wd/engine.R"; printf '{"fidelity":"faithful"}' > "$AR/wd/FIDELITY.json"
printf '%s' '{"axes":[{"key":"signal","title":"신호","tier":"t","focus":"f","counterexample":"c","model":"opus","effort":"low","required":true}]}' > "$AR/06_Registry/rf_fidelity_axes.json"
arun(){ # $1 fanout(0|1) $2 ART $3 clean(0|1)
  printf '{"fidelity_audit":{"enabled":true,"fanout":{"enabled":%s}}}' "$([ "$1" = 1 ] && echo true || echo false)" > "$AR/06_Registry/reinforce_auto_config.json"
  rm -rf "$T/rec"; mkdir -p "$T/rec"; rm -f "$AR/wd/"*prompt* "$AR/wd/.audit_prompt_"*
  (cd "$AR" && env -u QVEST_CLEAN_LANE -u QVEST_CLEAN_WDIR PATH="$FB:$PATH" FAKE_REC="$T/rec" FAKE_NO_ENGINE=1 QM_ROOT="$(wp "$AR")" QVEST_RF_ROOT="$(wp "$AR")" \
     QVEST_PY="$PY" RF_CLAUDE_BIN="$FB/claude" R_ENVIRON_USER="$EMPTY_RENV" QVEST_RP_JLOG="$(wp "$AR")/.cache/j.jsonl" QVEST_FA_LOG="$(wp "$AR")/.cache/fa.log" \
     QVEST_RF_AXES="$(wp "$AR")/06_Registry/rf_fidelity_axes.json" ${3:+$([ "$3" = 1 ] && echo QVEST_CLEAN_LANE=1)} \
     bash "$AR/02_Infrastructure/ops/rf_fidelity_audit.sh" "$(wp "$AR")/wd" "$2" "https://arxiv.org/abs/9901.00050" "9901.00050" > "$T/aud_out.txt" 2>&1)
}
arun 0 "" 1
if [ -f "$T/rec/call_1.env" ]; then
  grep -q '측정 산출물: (청정 모드 — 비공개' "$T/rec/call_1.prompt" && ! grep -q 'stage_artifacts' "$T/rec/call_1.prompt" && case "$(recv call_1.env ARGS)" in *PowerShell*Skill*) true ;; *) false ;; esac \
    && ok "A1 단일 감사 청정: 산출물 비공개 줄 · 경로 없음 · 셸·Skill 금지" || ng "A1" "$(grep '측정 산출물' "$T/rec/call_1.prompt") · $(recv call_1.env ARGS)"
else ng "A1 단일 감사 청정" "claude 미호출 · $(tail -3 "$T/aud_out.txt")"; fi
arun 0 "C:/x/stage_artifacts/replication/r1" 0
if [ -f "$T/rec/call_1.env" ]; then
  grep -q '측정 산출물: C:/x/stage_artifacts/replication/r1' "$T/rec/call_1.prompt" && case "$(recv call_1.env ARGS)" in *'--disallowed-tools Bash,Agent,Edit '*) true ;; *) false ;; esac \
    && ok "A2 단일 감사 평시: 구판 그대로(산출물 경로 · Bash,Agent,Edit)" || ng "A2" "$(recv call_1.env ARGS)"
else ng "A2 단일 감사 평시" "claude 미호출"; fi
arun 1 "" 1
fp="$(ls "$AR/wd/.audit_prompt_signal.txt" 2>/dev/null)"
if [ -n "$fp" ] && [ -f "$T/rec/call_1.env" ]; then
  grep -q '측정 산출물: (청정 모드 — 비공개' "$fp" && case "$(recv call_1.env ARGS)" in *PowerShell*Skill*) true ;; *) false ;; esac \
    && ok "A3 팬아웃 청정: 축 프롬프트 비공개 줄 · 축 레인 셸·Skill 금지" || ng "A3" "$(grep '측정 산출물' "$fp") · $(recv call_1.env ARGS)"
else ng "A3 팬아웃 청정" "축 프롬프트/호출 없음 · $(tail -3 "$T/aud_out.txt")"; fi
arun 1 "C:/x/stage_artifacts/replication/r1" 0
fp="$(ls "$AR/wd/.audit_prompt_signal.txt" 2>/dev/null)"
if [ -n "$fp" ] && [ -f "$T/rec/call_1.env" ]; then
  grep -q '측정 산출물: C:/x/stage_artifacts/replication/r1' "$fp" && case "$(recv call_1.env ARGS)" in *'--disallowed-tools Bash,Agent,Edit '*) true ;; *) false ;; esac \
    && ok "A4 팬아웃 평시: 구판 그대로" || ng "A4" "$(recv call_1.env ARGS)"
else ng "A4 팬아웃 평시" "축 프롬프트/호출 없음"; fi

# ═══ V 검증기 도우미(R) ═══
echo "--- V. 검증기 도우미(rf_clean_lane_lib.R) ---"
VR="$T/vroot"; mkdir -p "$VR/wd"; printf 'p1 측정 산출물: (청정 모드 — 비공개)\n' > "$VR/wd/.audit_prompt_signal.txt"; printf '{"verdict":"misdeclared"}' > "$VR/wd/fidelity_audit.json"
printf '{"schema":"lane_provenance_v1","mode":"clean","audits":[]}' > "$VR/wd/lane_provenance.json"
cat > "$T/v.R" <<'EOF'
source(Sys.getenv("CL_LIB"))
wd <- Sys.getenv("CL_WD"); res <- character(0)
Sys.unsetenv(c("QVEST_CLEAN_LANE", "QVEST_CLEAN_WDIR")); Sys.setenv(QVEST_CLEAN_WDIR = "keep_me")
inside <- rcl_with_env(rcl_clean_env("C:\\a\\b"), c(Sys.getenv("QVEST_CLEAN_LANE"), Sys.getenv("QVEST_CLEAN_WDIR")))
res <- c(res, sprintf("V1 %d", as.integer(identical(inside, c("1", "C:/a/b")) && identical(Sys.getenv("QVEST_CLEAN_LANE", NA), NA_character_) && identical(Sys.getenv("QVEST_CLEAN_WDIR"), "keep_me"))))
res <- c(res, sprintf("V2 %d", as.integer(identical(rcl_audit_art(TRUE, "x/y"), "") && identical(rcl_audit_art(FALSE, "x/y"), "x/y"))))
a <- rcl_archive_audit_src(wd, 1L)
m <- jsonlite::fromJSON(file.path(wd, ".clean_audit_src/r1/manifest.json"), simplifyVector = FALSE)
res <- c(res, sprintf("V3 %d", as.integer(identical(a$rel, ".clean_audit_src/r1") && all(c(".audit_prompt_signal.txt", "fidelity_audit.json") %in% names(m$files)) &&
                                          identical(m$files[[".audit_prompt_signal.txt"]], digest::digest(file.path(wd, ".audit_prompt_signal.txt"), algo = "sha256", file = TRUE)))))
rcl_prov_audit(wd, list(mode = "clean", art_hidden = TRUE, src = a$rel)); rcl_prov_audit(wd, list(mode = "clean", art_hidden = TRUE))
P <- jsonlite::fromJSON(file.path(wd, "lane_provenance.json"), simplifyVector = FALSE)
res <- c(res, sprintf("V4 %d", as.integer(length(P$audits) == 2L && identical(P$audits[[1]]$src, ".clean_audit_src/r1") && identical(P$mode, "clean"))))
Sys.setenv(RP_LANE_MODE = "clean"); m1 <- rcl_lane_mode(); Sys.setenv(RP_LANE_MODE = "weird"); m2 <- rcl_lane_mode()
res <- c(res, sprintf("V5 %d", as.integer(identical(m1, "clean") && identical(m2, "normal"))))
cat(res, sep = "\n")
EOF
vres="$(cd "$VR" && env CL_LIB="$(wp "$SRC_OPS/rf_clean_lane_lib.R")" CL_WD="$(wp "$VR/wd")" R_ENVIRON_USER="$EMPTY_RENV" QM_ROOT="$(wp "$VR")" CLAUDE_PROJECT_DIR="$(wp "$VR")" "$RSCRIPT_REAL" "$(wp "$T/v.R")" 2>&1 | tr -d '\r')"
vv(){ printf '%s\n' "$vres" | awk -v k="$1" '$1==k{print $2}'; }
[ "$(vv V1)" = 1 ] && ok "V1 가드 표식 임시 대입 → 원복(없던 변수 삭제 · 있던 값 복원 · 역슬래시 → 슬래시)" || ng "V1" "$vres"
[ "$(vv V2)" = 1 ] && ok "V2 청정 = 산출물 경로 비움 / 평시 = 그대로" || ng "V2" "$vres"
[ "$(vv V3)" = 1 ] && ok "V3 감사 원천 보존(.clean_audit_src/r1 · 매니페스트 sha256 = 사본)" || ng "V3" "$vres"
[ "$(vv V4)" = 1 ] && ok "V4 출처 기록 audits 덧붙임(기존 필드 보존)" || ng "V4" "$vres"
[ "$(vv V5)" = 1 ] && ok "V5 레인 모드 = clean 만 clean(그 밖 = normal)" || ng "V5" "$vres"

# ═══ L 돌연변이 ═══
echo "--- L. 돌연변이 ---"
mut_hook(){ # $1 이름 $2 python 치환(구 → 신) 파일
  local d="$T/mh_$1"; mkdir -p "$d/02_Infrastructure/hooks/policies" "$d/02_Infrastructure/ops"
  cp "$HOOK" "$d/02_Infrastructure/hooks/arm_gen_read_guard.sh"; cp "$SBX/02_Infrastructure/hooks/policies/arm_gen_read_guard.json" "$d/02_Infrastructure/hooks/policies/"
  cp "$SBX/02_Infrastructure/ops/rf_b1_design_lib.R" "$d/02_Infrastructure/ops/"
  echo "$d/02_Infrastructure/hooks/arm_gen_read_guard.sh"
}
sub_file(){ "$PY" - "$(wp "$1")" "$2" "$3" <<'PYEOF'
import io, sys
p, a, b = sys.argv[1:4]
s = io.open(p, encoding='utf-8').read()
if a not in s: print('NOCHANGE'); sys.exit(0)
io.open(p, 'w', encoding='utf-8', newline='').write(s.replace(a, b, 1)); print('CHANGED')
PYEOF
}
h1="$(mut_hook m1)"; r="$(sub_file "$h1" "        h = clean_hit()                                         # (FA-CLEAN-BASE-PATH) R6 — 기존 규칙보다 먼저" "        h = None")"
if [ "$r" = CHANGED ]; then o3="$(gv "$(gfire clean "$T/cases/CB03.json" "$h1")")"; o6="$(gv "$(gfire clean "$T/cases/CB06.json" "$h1")")"
  [ "$o3" != block ] && [ "$o6" != block ] && ok "L1 R6 호출 삭제 → 다른 전략 엔진·계획서 열람이 뚫린다(CB03·CB06 red)" || ng "L1 판별력" "$o3 $o6"
else ng "L1 돌연변이 좌표 낡음" "$r"; fi
h2="$(mut_hook m2)"; r="$(sub_file "$h2" "PASS_OUT='{\"continue\":true}'" "PASS_OUT='{}'")"
if [ "$r" = CHANGED ]; then o="$(gfire clean "$T/cases/CP01.json" "$h2")"; [ "$o" = '{}' ] && ok "L2 통과 표식 '{}' 로 → 증명 표식 소실(CP01 이 {\"continue\":true} 아님 = red)" || ng "L2" "$o"
else ng "L2 좌표 낡음" "$r"; fi
h3="$(mut_hook m3)"; "$PY" - "$(wp "$(dirname "$h3")/policies/arm_gen_read_guard.json")" <<'PYEOF'
import io, json, sys
p = sys.argv[1]; d = json.load(io.open(p, encoding='utf-8')); d['catalog_view']['lanes'] = [x for x in d['catalog_view']['lanes'] if x != 'clean_lane']
io.open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
PYEOF
o="$(gv "$(gfire clean "$T/cases/CB20.json" "$h3")")"; [ "$o" = pass ] && ok "L3 R5 레인에서 clean_lane 삭제 → 등록부(dedup.reason port_t) 원문 열람이 뚫린다(CB20 red)" || ng "L3" "$o"
h4="$(mut_hook m4)"; r="$(sub_file "$h4" "            h = _own_walk(fs, TI.get('glob') or '', TI.get('type') or '')   # (FA-CLEAN-BASE-PATH) 작업 디렉터리 = 순회만" "            h = scope_hit(fs, TI.get('glob') or '', TI.get('type') or '')")"
if [ "$r" = CHANGED ]; then o="$(gv "$(gfire clean "$T/cases/CP04.json" "$h4")")"; [ "$o" = block ] && ok "L4 작업 디렉터리 순회 예외 삭제 → 자기 디렉터리 Grep 오차단(CP04 red — 예외가 실제로 쓰인다)" || ng "L4" "$o"
else ng "L4 좌표 낡음" "$r"; fi
cp "$IR/02_Infrastructure/hooks/axiom_context_inject.sh" "$T/inj_m5.sh"
r="$(sub_file "$T/inj_m5.sh" "if CLEAN:" "if False:")"
if [ "$r" = CHANGED ]; then cp "$T/inj_m5.sh" "$IR/02_Infrastructure/hooks/axiom_context_inject_m5.sh"; nm="$(ictx "$(ifire 1 "$IR/02_Infrastructure/hooks/axiom_context_inject_m5.sh")")"; hm="$(mhits "$nm" | tr -d '\r')"
  [ "${hm:-0}" -gt 0 ] && ok "L5 주입 훅 청정 분기 삭제 → 청정 표식에서도 성과 수치 ${hm}곳(I2 red)" || ng "L5" "hits=$hm"
else ng "L5 좌표 낡음" "$r"; fi
cp "$LR/02_Infrastructure/ops/rf_replication_auto.sh" "$T/lane_m6.sh"
r="$(sub_file "$T/lane_m6.sh" "  QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR=\"\$WDIR\" rf_llm_agent_run" "  rf_llm_agent_run")"
if [ "$r" = CHANGED ]; then cp "$T/lane_m6.sh" "$LR/02_Infrastructure/ops/rf_replication_auto_m6.sh"
  LANE_SH="$LR/02_Infrastructure/ops/rf_replication_auto_m6.sh" lrun "$REQ_BASE" >/dev/null
  [ -f "$T/rec/call_1.env" ] && [ -z "$(recv call_1.env CLEAN)" ] && ok "L6 레인 청정 표식 삭제 → claude 가 표식 없이 뜬다(D2 red)" || ng "L6" "$(cat "$T/rec/call_1.env" 2>/dev/null)"
else ng "L6 좌표 낡음" "$r"; fi
cp "$LR/02_Infrastructure/ops/rf_replication_auto.sh" "$T/lane_m7.sh"
r="$(sub_file "$T/lane_m7.sh" "    --disallowed-tools \"Bash,PowerShell,Monitor,REPL,Workflow,CronCreate,RemoteTrigger,Agent,Skill\" \\" "    --disallowed-tools \"Bash,Agent\" \\")"
if [ "$r" = CHANGED ]; then cp "$T/lane_m7.sh" "$T/m7dir_lane.sh"
  m7="$("$PY" - "$(wp "$T/lane_m7.sh")" <<'PYEOF'
import io, re, sys
L = io.open(sys.argv[1], encoding='utf-8').read().splitlines()
i = [k for k, l in enumerate(L) if re.search(r'(^|\s)QVEST_CLEAN_LANE=1\s.*rf_llm_agent_run', l)][0]
b = [L[i]]; j = i
while L[j].rstrip().endswith('\\'): j += 1; b.append(L[j])
m = re.search(r'--disallowed-tools\s+"([^"]*)"', '\n'.join(b)); print('RED' if 'PowerShell' not in m.group(1) else 'GREEN')
PYEOF
)"
  [ "$(printf '%s' "$m7" | tr -d '\r')" = RED ] && ok "L7 레인 청정 금지 목록 축소 → W1 판정식이 잡는다(셸 통로 누락)" || ng "L7" "$m7"
else ng "L7 좌표 낡음" "$r"; fi
cp "$SRC_OPS/rf_clean_lane.py" "$T/rcl_m8.py"
r="$(sub_file "$T/rcl_m8.py" "        if any(r.search(ln) for r in R['post']):" "        if False:")"
if [ "$r" = CHANGED ]; then
  zo8="$("$PY" "$(wp "$T/rcl_m8.py")" sanitize --lane-cfg "$(wp "$T/lane_nomask.json")" --root "$(wp "$MR")" --rule-cfg "$(wp "$SRC_RULECFG")" --kind audit < "$T/fb.txt" | tr -d '\r')"
  zr8="$(zchk "$zo8" | tr -d '\r')"; [ "${zr8:-0}" -gt 0 ] && ok "L8 가림 사후 재검 삭제 + 규칙 비움 → 성과 잔존 ${zr8}줄(Z6 red — 재검이 실제 방어선)" || ng "L8" "$zr8"
else ng "L8 좌표 낡음" "$r"; fi

summary
[ "$FAIL" -eq 0 ]
