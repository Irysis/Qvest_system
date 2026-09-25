#!/usr/bin/env bash
#==============================================================================
# test_arm_gen_read_guard.sh — arm 생성·설계 세션 성과 열람 차단 계약 (v10.2 2026-09-03 · P0-M2 2026-09-25 확장)
#
# ★두 방향을 다 잰다: 생성·설계 세션에서 **막는가**, 평시·정당 경로에서 **안 막는가**.
#   상시 오탐 훅은 곧 해제되거나 무시된다 — 계기가 죽는 표준 경로다.
# 재는 것:
#   A. 평시(표식 없음) → 모든 사례 '{}' (측정 경로도 · 소음 0)
#   B. 위반 주입(설계 표식 QVEST_DESIGN_LANE=1) → block — 원장·복제 산출 0[2-9]·analysis·차트·권위재측정·기전지도·
#      hurdle·기억 카드·MEMORY.md · 경로 표기 7종(상대·역슬래시 절대·대소문자·..·/c/·~·junction)
#   C. 정당 경로(설계 표식) → pass — 엔진·arm·등록부·카탈로그·설계 캐시·01_spec·10_audit·memory_inbox·
#      02_Infrastructure/memory·qepm/memory/axioms·L-code
#   D. Grep 범위(R2 = find 판) — 원장 파일·06_Registry·루트 무필터·*.json·부정 글롭·전략 디렉터리·기억 조상·
#      junction 실경로·.cache/rf_parallel → block / *.R·type=r·02_Infrastructure·카탈로그·01_spec·qepm/memory/axioms·
#      설계 레인 자기 작업 디렉터리(.cache/rf_b1_design)·06_Registry/memory_inbox → pass (shallow 구역 — 드라이런 오차단 교정)
#   E. Glob 열거(R3) — 기억 카드 이름(요약) 열거 → block / 원장·산출물 이름 열거·코드·설계 캐시 → pass(이름은 성과가 아니다)
#   F. 셸 판(R4 · ★현재 등록 matcher 밖 = 판정만): 글롭 · 문자열 결합 · find/재귀 → block / 평범한 명령 → pass
#   G. 생성 표식(QVEST_ARM_GEN=1) 회귀 — 구판 검사 5종 그대로
#   H. 출력 JSON 유효성(역슬래시 경로 포함 · 구판 결함) · fail-closed(판정기 부재 → 측정 경로 Read·범위 도구 block)
#   I. 표본 자기일관성(AGRG_SELFTEST) — 구역 표본 전부가 R1 정규식에 걸리고 · junction 실경로가 구역에 든다
#   J. 레인 배선(정적) — 설계 레인 3종: rf_llm_agent_run 호출에 QVEST_DESIGN_LANE=1 · --disallowed-tools ⊇ {Bash,PowerShell} ·
#      --allowed-tools ∌ 둘 / 생성 레인(rf_overlay_propose.sh) 동일 / ops 전수: 표식을 싣는 호출은 모두 같은 조건 · export 금지
#   K. 레인 배선(동적) — 설계 레인 3종의 실제 호출 블록을 가짜 claude 로 재생: claude 프로세스에 표식 3종
#      (QVEST_DESIGN_LANE · QVEST_UNATTENDED_LANE · CLAUDE_CODE_DISABLE_AUTO_MEMORY)과 PowerShell 금지가 실리고 · 호출 뒤 셸에 표식이 안 남는다
#   L. 돌연변이 — 규칙을 하나씩 끈 훅·레인 사본에서 해당 사례가 뚫린다(판별력) · 오차단 교정 2종을 끄면 다시 막힌다
#   M. 등록 — settings.json 에 arm_gen_read_guard.sh 가 PreToolUse Read|Grep|Glob 로 걸려 있다(읽기만)
#   N. (P0-M2 수리 2026-09-25 · B-2) R2 순회 — 표본에 없는 이름의 측정 파일을 glob 으로 좁힌 Grep(D29~D36 block) ·
#      코드 면제(D37~D39 pass) · 예산 초과(항목·시간) → block · 설정 부재·불량 → 순회가 필요한 Grep 만 block · 돌연변이
#   (B-1) J·K 는 셸 통로 7종(CLI enablesCodeExecution = Bash·PowerShell·Monitor·REPL·Workflow·CronCreate·RemoteTrigger) 금지를 요구한다
#   O. (R2 2026-09-25 · pit.md C1 D-E) 전기간 성과·IC 통계 — 이름(STATS_RE: factor_evidence · IC 행렬·패널 · ast_structure_log ·
#      성과 원장 · L-code · 원장 사본 · 계열 evidence) · 구역(04_Research 전체 · outputs · qepm/memory) · 내용(R1_content: 구조 키 ≥ 문턱)
#      3층 block / 의미 정보(factor_registry · 카탈로그 · 격자 값 · 열린 경로의 설정·공리 · 단일 키 · 설계 캐시) pass ·
#      돌연변이(m18~m22) · 설정(N13~N17: content_guard 부재·불량 = 데이터 Read fail-closed · 문턱이 판정을 가른다 · R2 설정과 분리)
#      ★C12(L-code) 는 pass → block 으로 뒤집었다: 교차 entry 수치는 B1 재료가 가린 판을 준다 — 파일 직접 열람은 그 가림을 우회한다.
#   P. (R2 적대 검증 수리 2026-09-25) 운영 실경로로 통과가 실증된 우회 — ① 좁힌 glob 디렉터리 Grep 이 내용 층을 비껴감(순회가 이름만 봤다)
#      ② 백업 접미사·BOM·8.3 짧은 이름이 내용 층 확장자·머리 판정을 비껴감 ③ 구역 밖 디렉터리 Grep(순회 없음) ④ 같은 수치의 사본
#      (공리 distilled·candidates · 설계 캐시 재료·프롬프트 · 스케줄러 로그) → block / 열린 경로 active·좁힌 코드·설계 산출 되읽기 → pass ·
#      돌연변이 m23~m28 · N18 뒤집음(내용 설정 불량이면 순회도 데이터 파일에서 fail-closed) · D19·O21·O28 뒤집음(distilled 사본)
# 격리: 훅을 임시 루트로 복사 · 가짜 HOME(기억 디렉터리) · CLAUDE_PROJECT_DIR·QM_ROOT = 임시 루트 · 로그 = 임시 파일.
#   운영 원장·기억 디렉터리는 읽지도 쓰지도 않는다(판정 대상 경로는 전부 임시 루트 안이다).
# 대상 교체: QVEST_AGRG_HOOK(훅) · QVEST_AGRG_POLICY(R2 순회 설정 — 기본 = 훅 옆 policies/) · QVEST_AGRG_OPS(레인 셸·rf_llm_env.sh 디렉터리) ·
#   QVEST_AGRG_SETTINGS — 스테이징 판 검증용
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
SRC_HOOK="${QVEST_AGRG_HOOK:-$ROOT/02_Infrastructure/hooks/arm_gen_read_guard.sh}"
SRC_POL="${QVEST_AGRG_POLICY:-$(dirname "$SRC_HOOK")/policies/arm_gen_read_guard.json}"
# (B-1) 레인이 막아야 할 셸 통로 — CLI 2.1.261 이 enablesCodeExecution 으로 표시한 내장 도구(바이너리 판독 09-25). Monitor = 09-17 실측 통로.
export AGRG_SHELL_TOOLS="Bash,PowerShell,Monitor,REPL,Workflow,CronCreate,RemoteTrigger"
OPS="${QVEST_AGRG_OPS:-$ROOT/02_Infrastructure/ops}"
SETTINGS="${QVEST_AGRG_SETTINGS:-$ROOT/.claude/settings.json}"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
[ -x "$PY" ] || PY="$(command -v python3 2>/dev/null || command -v python)"
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); printf '  OK    %s\n' "$1"; }
ng(){ FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }
sk(){ SKIP=$((SKIP+1)); printf '  SKIP  %s — %s\n' "$1" "${2:-}"; }
wp(){ cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }

echo "=== test_arm_gen_read_guard ==="
[ -f "$SRC_HOOK" ] || { ng "훅 부재" "$SRC_HOOK"; printf '{"test":"arm_gen_read_guard","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SBX="$T/root"; HOMEF="$T/home"; CT="$T/qm_cache_target"
mkdir -p "$SBX/02_Infrastructure/hooks" "$T/cases" "$T/blocks" "$T/mut"
cp "$SRC_HOOK" "$SBX/02_Infrastructure/hooks/arm_gen_read_guard.sh"
HOOK="$SBX/02_Infrastructure/hooks/arm_gen_read_guard.sh"
if [ -f "$SRC_POL" ]; then mkdir -p "$SBX/02_Infrastructure/hooks/policies"; cp "$SRC_POL" "$SBX/02_Infrastructure/hooks/policies/arm_gen_read_guard.json"
else ng "R2 순회 설정 부재" "$SRC_POL"; fi

# ── 픽스처 트리 — 측정 구역 + 정당 경로 + 가짜 기억 디렉터리 ────────────────────────────────
mk(){ mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }
for f in 06_Registry/reinforce_ledger_l1.json 06_Registry/reinforce_ledger_l1.json.bak_x 06_Registry/overlay_mechanism_map.json \
         06_Registry/overlay_arm_ledger.jsonl 06_Registry/overlay_catalog.json 06_Registry/reinforce_program.json \
         06_Registry/memory_inbox/README.md \
         stage_artifacts/replication/r1/02_nav.csv stage_artifacts/replication/r1/04_holdings.csv \
         stage_artifacts/replication/r1/01_strategy_spec.json stage_artifacts/replication/r1/10_audit.csv \
         stage_artifacts/replication/r1/analysis_report.md stage_artifacts/replication/r1/equity_curve.png \
         stage_artifacts/replication/r1/authoritative_remeasure.json stage_artifacts/l_code/reinforcement/l_code_x.json \
         02_Infrastructure/reinforcement/overlay_arms/dbeta_tilt.R 02_Infrastructure/ops/x.R \
         02_Infrastructure/factor_db/factor_registry.json 02_Infrastructure/memory/notes.md \
         04_Research/strategies/S1/engine.R 04_Research/strategies/S1/hurdle_result.json \
         qepm/memory/axioms/ax1.md qepm/research/q1/hurdle_result.json \
         06_Registry/reinforce_ledger_l1.json.bak_20260904_174834 06_Registry/bt_result_format_census_x.csv \
         stage_artifacts/replication/r1/analysis_fmb.csv 04_Research/strategies/S1/bt_result_C_x.rds \
         04_Research/strategies/S1/build_bt_result_x.R; do mk "$SBX/$f"; done
# (B-2) 표본에 없는 이름의 측정 파일 — 적대 검증 우회 실례(원장 .bak_2* · rf_parallel/result_B1_* · analysis_fmb*.csv · pins/**/bt_result_*)
mkdir -p "$CT/rf_parallel" "$CT/rf_b1_design" "$CT/pins/p1"
mk "$CT/reinforce_auto_log.jsonl"; mk "$CT/rf_parallel/result_b5_1_1.json"; mk "$CT/rf_b1_design/design_x.json"
mk "$CT/rf_parallel/result_B1_7.json"; mk "$CT/essence_score_orig.R"; mk "$CT/pins/p1/bt_result_C.rds"
# (R2 · §O) 전기간 통계 픽스처 — 내용은 실제 산출물의 구조 키를 흉내 낸다(R1_content 가 이름 밖에서 잡는 것을 재려고)
mk "$SBX/06_Registry/factor_evidence.json" '{"factors":{"M01_Mom_12_1":{"ic_all":0.051,"ic_bad":0.02,"ic_good":0.06,"ic_screen_tier":"S1"}}}'
mk "$SBX/06_Registry/ast_structure_log.jsonl" '{"strategy_id":"WT_x_AC01_Total_Accruals_CF","port_t":-0.1899,"net_sr":-0.0406}'
mk "$SBX/06_Registry/hypothesis_index.json" '{"entries":[{"id":"H1","sharpe":1.1,"cagr":0.12,"mdd":0.3,"calmar":0.4}]}'
mk "$SBX/06_Registry/novel_stats_table.json" '{"rows":[{"id":"a","calmar":0.5,"sharpe":1.1}]}'
mk "$SBX/06_Registry/pit_quarantine.json" '{"factors":[{"id":"D32_Beta_VIX","ic_screen_tier":"S2"}]}'
mk "$SBX/06_Registry/weight_catalog.json" '{"arms":[{"id":"ew","label":"동일가중","family":"naive"}]}'
mk "$SBX/06_Registry/reinforce_program.json" '{"blocks":[{"id":"B1","select_winner_by":"port_t"},{"id":"B5","select_winner_by":"calmar","metric":"port_t"}]}'
mk "$SBX/04_Research/01_reports/p0/ledger_l1_post_epoch.json" '{"entries":[]}'
mk "$SBX/04_Research/factor_rotation/fof/_factor_ic.rds" 'RDX3'
mk "$SBX/04_Research/decision_framework/sb/k200_factor_returns_v3.parquet" 'PAR1'
mk "$SBX/04_Research/strategies/S1/output/perf_novel_name.csv" 'date,port_t,calmar,cagr'
mk "$SBX/qepm/memory/evidence_summary/fam.json" '{"family":"x","avg_ff5_t":1.47,"max_ff5_t":1.47}'
mk "$SBX/qepm/memory/axioms/distilled/DIST-x.json" '{"statement":"s","port_t":2.1,"calmar":0.5}'
mk "$SBX/outputs/ramp/latent_factor_returns.parquet" 'PAR1'
mk "$SBX/02_Infrastructure/worktask/constraint_defaults.json" '{"tier_graduation":{"calmar":0.64,"portfolio_alpha_t_nw_lag3":2.95,"oos_retention":0.5}}'
mk "$SBX/02_Infrastructure/factor_db/factor_registry.json" '{"S01_Size":{"category":"size","definition":"-log(MarketCap)","dedup":{"reason":"승인 게이트 통계 우위(port_t +0.194 vs -0.106)"}}}'
mkdir -p "$CT/factor_db" "$CT/rf_b5_design/b"
mk "$CT/conditional_ic_matrix.csv" 'Factor_Name,ic_all,ic_bad,ic_good,conditional_value,recent_3y_icir,n_months,used,category'
mk "$CT/factor_db/factor_ic_monthly.parquet" 'PAR1'
mk "$CT/rf_b5_design/b/design_r1.json" '{"schema":"rf_b5_design_v1","cells":[{"picks":["arm_a"],"label":"l","why":"w"}]}'
# (§P · 적대 검증 수리) 우회 실례 픽스처 — 이름은 STATS_RE 밖 · 내용은 실제 산출물의 구조를 흉내 낸다
mk "$SBX/04_Research/90_legacy/residual_x.csv" 'Factor_Name,ic_all,ic_bad,ic_good,recent_3y_icir'
mk "$SBX/qepm/registry/novel_perf.csv" 'strategy,cagr,calmar,sharpe'
mk "$SBX/qepm/registry/README.md" 'registry readme'
mk "$SBX/06_Registry/novel_stats_table.json.bak_1" '{"rows":[{"id":"a","calmar":0.5,"sharpe":1.1}]}'
mk "$SBX/04_Research/x/bom_perf.csv" "$(printf '\357\273\277port_t,calmar')"
mk "$SBX/qepm/memory/axioms/candidates/CAND-x.json" '{"statement":"IC 0.22 ICIR 1.88"}'
mk "$SBX/qepm/memory/axioms/active/AX-x.json" '{"statement":"s","calmar":0.5,"cagr":0.1}'
mk "$SBX/qepm/memory/axioms/sot_x.json" '{"a":{"calmar":0.5,"cagr":0.1}}'
mkdir -p "$CT/rf_lcode_mech" "$CT/scheduler_logs"
mk "$CT/rf_lcode_mech/RP_x_B1.materials.txt" 'code | grade | PORT_t | Calmar — B1_1 L19_Price_Delay 0.338'
mk "$CT/rf_lcode_mech/RP_x_B1.mechanism.json" '{"mechanism":"기전 문장"}'
mk "$CT/rf_b5_design/b/materials_r1.txt" '(3) arm 성과 이력 med_d_calmar 0.12'
mk "$CT/rf_b5_design/b/materials_r1.txt.sizes.json" '{"materials_bytes":1234}'
mk "$CT/scheduler_logs/reinforce_auto_x.log" '[rf_par] cell_done code=B5_31 grade=B port_t=2.32 calmar=0.491'
mk "$CT/rf_parallel/spec_B1_3__RP_x.json" '{"code":"B1_3","factors":[{"id":"V01_BM"}],"preflight":{"recent_attempts":["n=3 B1_3 Grade C · PORT_t 0.174"]}}'
JUNCTION=0
if cmd //c "mklink /J $(wp "$SBX/.cache") $(wp "$CT")" >/dev/null 2>&1 && [ -f "$SBX/.cache/rf_b1_design/design_x.json" ]; then JUNCTION=1
else rm -rf "$SBX/.cache" 2>/dev/null; mkdir -p "$SBX/.cache"; cp -r "$CT/." "$SBX/.cache/"; fi
SLUG="C--fake-proj"
mk "$HOMEF/.claude/projects/$SLUG/memory/MEMORY.md"; mk "$HOMEF/.claude/projects/$SLUG/memory/project-card-x.md"
mk "$HOMEF/.claude/projects/$SLUG/abc.jsonl"
SBXW="$(wp "$SBX")"; HOMEW="$(wp "$HOMEF")"; CTW="$(wp "$CT")"
# (§P) 8.3 짧은 이름 — 볼륨이 8.3 이름을 만들 때만(운영 C: 는 만든다: METHOD~1.JSO) · 없으면 P20 은 skip
SHORT83="$(cd "$SBX/06_Registry" 2>/dev/null && cmd //c "dir /x novel_stats_table.json" 2>/dev/null | tr -d '\r' | awk '/novel_stats_table\.json$/ { if (NF >= 5 && $(NF-1) ~ /~/) print $(NF-1) }' | head -1)"

fire(){ # $1 = 표식(0|design|arm|both) $2 = json 파일 [$3 = 훅 경로] [$4 = QVEST_PY_BIN]
  local h="${3:-$HOOK}" e=()
  case "$1" in design) e=(QVEST_DESIGN_LANE=1) ;; arm) e=(QVEST_ARM_GEN=1) ;; both) e=(QVEST_DESIGN_LANE=1 QVEST_ARM_GEN=1) ;; esac
  [ -n "${4:-}" ] && e+=(QVEST_PY_BIN="$4")
  (cd "$SBX" && env -u QVEST_DESIGN_LANE -u QVEST_ARM_GEN -u QVEST_PY_BIN -u QVEST_RF_ROOT -u CLAUDE_CONFIG_DIR \
     ${e[@]+"${e[@]}"} QVEST_PY="$PY" USERPROFILE="$HOMEW" HOME="$HOMEF" CLAUDE_PROJECT_DIR="$SBXW" QM_ROOT="$SBXW" \
     QVEST_ARM_GEN_GUARD_LOG="$T/guard.log" bash "$h" < "$2" 2>/dev/null)
}
verdict(){ case "$1" in *'"decision":"block"'*) echo block ;; '{}') echo pass ;; *) echo "odd:${1:0:120}" ;; esac; }

# ── 사례 — JSON 은 파이썬이 만든다(셸 이스케이프가 역슬래시를 먹는 사고 방지) ─────────────────────
"$PY" - "$(wp "$T/cases")" "$SBXW" "$HOMEW" "$CTW" "$SLUG" "$JUNCTION" "${SHORT83:-}" <<'PYEOF'
import io, json, os, sys
out, sbw, homew, ctw, slug, junction, short83 = sys.argv[1:8]
B = chr(92)
sbf = sbw.replace(B, '/')                                         # C:/.../root
sbg = '/' + sbf[0].lower() + sbf[2:]                              # /c/.../root
memw = homew + B + '.claude' + B + 'projects' + B + slug + B + 'memory'
rows = []
def put(cid, mode, want, tool, ti, desc):
    ti = dict(ti)
    obj = {'session_id': 't', 'hook_event_name': 'PreToolUse', 'cwd': sbw, 'tool_name': tool, 'tool_input': ti}
    io.open(os.path.join(out, cid + '.json'), 'w', encoding='utf-8', newline='').write(json.dumps(obj, ensure_ascii=False))
    rows.append('\t'.join([cid, mode, want, desc]))
R = lambda cid, want, fp, d: put(cid, 'design', want, 'Read', {'file_path': fp}, d)
G = lambda cid, want, ti, d: put(cid, 'design', want, 'Grep', dict({'pattern': 'calmar'}, **ti), d)
L = lambda cid, want, ti, d: put(cid, 'design', want, 'Glob', ti, d)
S = lambda cid, want, tool, cmd, d: put(cid, 'design', want, tool, {'command': cmd, 'description': 't'}, d)
w = lambda *p: sbw + B + B.join(p)
# B. 위반 — 경로 표기 7종 + 측정 산출물 종류
R('B01', 'block', '06_Registry/reinforce_ledger_l1.json', '원장 상대경로')
R('B02', 'block', w('06_Registry', 'reinforce_ledger_l1.json'), '원장 역슬래시 절대경로(실레인 표기)')
R('B03', 'block', sbf + '/06_REGISTRY/Reinforce_Ledger_L1.JSON', '원장 대소문자 변형')
R('B04', 'block', '02_Infrastructure/../06_Registry/./reinforce_ledger_l1.json', '원장 ..·. 우회')
R('B05', 'block', sbg + '/06_Registry/reinforce_ledger_l1.json', '원장 Git Bash /c/ 표기')
R('B06', 'block', w('stage_artifacts', 'replication', 'r1', '04_holdings.csv'), '복제 04_holdings.csv(역슬래시)')
R('B07', 'block', 'stage_artifacts/replication/r1/02_nav.csv', '복제 02_nav.csv')
R('B08', 'block', 'stage_artifacts/replication/r1/analysis_report.md', '복제 analysis_report.md(Sharpe·IC)')
R('B09', 'block', memw + B + 'project-card-x.md', '기억 카드(역슬래시)')
R('B10', 'block', '~/.claude/projects/' + slug + '/memory/MEMORY.md', 'MEMORY.md(~ 표기)')
R('B11', 'block', 'stage_artifacts/replication/r1/authoritative_remeasure.json', '권위 재측정')
R('B12', 'block', '06_Registry/overlay_mechanism_map.json', '기전 지도')
R('B13', 'block', w('04_Research', 'strategies', 'S1', 'hurdle_result.json'), '전략 hurdle_result')
R('B14', 'block', w('.cache', 'rf_parallel', 'result_b5_1_1.json'), '병렬 결과(.cache junction 경유)')
R('B15', 'block', '06_Registry/reinforce_ledger_l1.json.bak_x', '원장 백업 사본')
R('B16', 'block', 'stage_artifacts/replication/r1/equity_curve.png', '성과 차트 png')
R('B17', 'block', '.cache/reinforce_auto_log.jsonl', '러너 로그')
R('B18', 'block', 'stage_artifacts/replication/r1/../r1/04_holdings.csv', '복제 산출 .. 우회')
# C. 정당 경로
R('C01', 'pass', w('02_Infrastructure', 'reinforcement', 'overlay_arms', 'dbeta_tilt.R'), 'arm 본보기')
R('C02', 'pass', '04_Research/strategies/S1/engine.R', '기저 엔진')
R('C03', 'pass', '02_Infrastructure/factor_db/factor_registry.json', '팩터 등록부')
R('C04', 'pass', w('06_Registry', 'overlay_catalog.json'), '오버레이 카탈로그')
R('C05', 'pass', '.cache/rf_b1_design/design_x.json', '설계 캐시')
R('C06', 'pass', 'stage_artifacts/replication/r1/01_strategy_spec.json', '복제 01_strategy_spec')
R('C07', 'pass', 'stage_artifacts/replication/r1/10_audit.csv', '복제 10_audit(무결성 검사)')
R('C08', 'pass', '06_Registry/memory_inbox/README.md', 'memory_inbox')
R('C09', 'pass', '02_Infrastructure/memory/notes.md', '02_Infrastructure/memory(좁게 — 기억 디렉터리 아님)')
R('C10', 'pass', 'qepm/memory/axioms/ax1.md', 'qepm/memory/axioms(공리 원천)')
R('C11', 'pass', '06_Registry/reinforce_program.json', '강화 격자')
R('C12', 'block', 'stage_artifacts/l_code/reinforcement/l_code_x.json', 'L-code(R2 — 교차 entry 전기간 수치 · 재료가 가린 판을 준다 · 구판 pass)')
R('C13', 'pass', '02_Infrastructure/ops/memory_md_parser.R', '이름에 memory_md 가 든 코드')
# D. Grep 범위(R2)
G('D01', 'block', {'path': w('06_Registry', 'reinforce_ledger_l1.json')}, 'Grep 원장 파일')
G('D02', 'block', {'path': '06_Registry'}, 'Grep 06_Registry 디렉터리(원장 포함)')
G('D03', 'block', {}, 'Grep 루트 무필터(path 없음)')
G('D04', 'block', {'path': sbw, 'glob': '*.json'}, 'Grep 루트 glob=*.json')
G('D05', 'pass', {'path': sbw, 'glob': '*.R'}, 'Grep 루트 glob=*.R')
G('D06', 'pass', {'path': sbw, 'type': 'r'}, 'Grep 루트 type=r')
G('D07', 'pass', {'path': '02_Infrastructure'}, 'Grep 02_Infrastructure')
G('D08', 'pass', {'path': '06_Registry/overlay_catalog.json'}, 'Grep 카탈로그 파일')
G('D09', 'block', {'path': 'stage_artifacts/replication', 'glob': '0?_*.csv'}, 'Grep 글롭 우회 0?_*.csv')
G('D10', 'pass', {'path': 'stage_artifacts/replication/r1', 'glob': '01_strategy_spec.json'}, 'Grep 복제 run 의 01_spec 만')
G('D11', 'block', {'path': sbw, 'glob': '!*.R'}, 'Grep 부정 글롭(!*.R = 나머지 전부)')
G('D12', 'block', {'path': '04_Research/strategies/S1'}, 'Grep 전략 디렉터리(구역 안 · 무필터)')
G('D13', 'pass', {'path': '04_Research/strategies/S1/engine.R'}, 'Grep 엔진 파일')
G('D14', 'block', {'path': homew + B + '.claude' + B + 'projects'}, 'Grep 기억 디렉터리 조상')
G('D15', 'block', {'path': memw, 'glob': '*.md'}, 'Grep 기억 디렉터리 *.md')
G('D16', 'pass', {'path': '06_Registry', 'glob': 'overlay_catalog.json'}, 'Grep 06_Registry 카탈로그만')
G('D17', 'block' if junction == '1' else 'skip', {'path': ctw}, 'Grep junction 실경로(C:/qm_cache 판) 직접')
G('D18', 'block', {'path': sbw, 'glob': '**/stage_artifacts/**/*.csv'}, 'Grep ** 글롭')
G('D19', 'block', {'path': 'qepm/memory/axioms'}, 'Grep qepm/memory/axioms(§P: 순회가 distilled 사본을 이름으로 잡는다 — 운영도 block · 구판 pass)')
G('D20', 'block', {'path': 'qepm'}, 'Grep qepm(구역 조상)')
G('D21', 'pass', {'path': sbw, 'glob': '*.{R,py}'}, 'Grep 중괄호 글롭 코드만')
G('D22', 'block', {'path': sbw, 'glob': '*.{R,json}'}, 'Grep 중괄호 글롭 json 포함')
G('D23', 'pass', {'path': sbw, 'type': 'py'}, 'Grep type=py')
G('D24', 'block', {'path': sbw, 'type': 'json'}, 'Grep type=json')
G('D25', 'block', {'path': sbg + '/stage_artifacts'}, 'Grep stage_artifacts(/c/ 표기)')
G('D26', 'pass', {'path': '.cache/rf_b1_design'}, 'Grep 설계 레인 자기 작업 디렉터리(.cache shallow 구역 — 오차단 교정)')
G('D27', 'block', {'path': '.cache/rf_parallel'}, 'Grep .cache/rf_parallel(병렬 결과)')
G('D28', 'pass', {'path': '06_Registry/memory_inbox'}, 'Grep 06_Registry/memory_inbox(06_Registry shallow)')
# (B-2) R2 순회 — 표본에 없는 이름의 실제 측정 파일을 glob 으로 좁힌 Grep(적대 검증 우회 실례) → block(R2_walk)
G('D29', 'block', {'path': '06_Registry', 'glob': '*.bak_2*', 'output_mode': 'content'}, 'Grep 06_Registry glob=*.bak_2*(원장 백업 — 적대 검증 재현)')
G('D30', 'block', {'path': w('.cache', 'rf_parallel'), 'glob': 'result_B1_*.json'}, 'Grep .cache/rf_parallel glob=result_B1_*.json(표본은 result_b5_*)')
G('D31', 'block', {'path': '.cache', 'glob': 'result_B1_*.json'}, 'Grep .cache glob=result_B1_*.json(하위 디렉터리 파일)')
G('D32', 'block', {'path': 'stage_artifacts/replication', 'glob': 'analysis_fmb*.csv'}, 'Grep 복제 glob=analysis_fmb*.csv(표본은 analysis_ic)')
G('D33', 'block', {'path': '04_Research/strategies', 'glob': 'bt_result_C*'}, 'Grep 전략 glob=bt_result_C*')
G('D34', 'block', {'path': sbw, 'glob': '*.bak_2*'}, 'Grep 루트 glob=*.bak_2*(구역 전부 순회)')
G('D35', 'block', {'path': '06_Registry', 'type': 'csv'}, 'Grep 06_Registry type=csv(표본 밖 bt_result_format_census)')
G('D36', 'block', {'path': '.cache', 'glob': 'pins'}, 'Grep .cache glob=pins(디렉터리 이름 glob → 그 아래 bt_result_*.rds)')
G('D37', 'pass', {'path': '.cache', 'glob': 'essence_score_orig.R'}, 'Grep .cache glob=essence_score_orig.R(코드 — 순회 생략 · Read 는 R1 이 막는다 = B19)')
G('D38', 'pass', {'path': '04_Research/strategies', 'glob': '*.R'}, 'Grep 전략 glob=*.R(코드만 — build_bt_result_x.R 이 있어도)')
G('D39', 'pass', {'path': '04_Research/strategies', 'glob': 'build_*'}, 'Grep 전략 glob=build_*(순회하되 코드 파일은 적중 아님)')
G('D40', 'pass', {'path': sbw, 'glob': 'zz_no_such_*'}, 'Grep 루트 glob=zz_no_such_*(구역 순회 — 적중 0 · 예산 안)')
R('B19', 'block', '.cache/essence_score_orig.R', 'Read .cache/essence_score_orig.R(R1 이름 차단은 그대로 — 코드 면제는 R2 순회만)')
# O. (R2 2026-09-25 · pit.md C1 D-E) 전기간 성과·IC 통계 — 이름·구역·내용 3층 block / 의미 정보 pass
R('O01', 'block', w('06_Registry', 'factor_evidence.json'), 'factor_evidence.json(전기간 ic_all·ic_bad·tier — 역슬래시 절대경로)')
R('O02', 'block', '.cache/conditional_ic_matrix.csv', 'conditional_ic_matrix.csv(IC 행렬 · junction 경유)')
R('O03', 'block', '.cache/factor_db/factor_ic_monthly.parquet', 'factor_ic_monthly.parquet(IC 패널 — 이진 · 이름이 유일한 수단)')
G('O04', 'block', {'path': '06_Registry', 'glob': 'factor_evidence.json'}, 'Grep 06_Registry glob=factor_evidence.json(좁힌 glob)')
G('O05', 'block', {'path': w('06_Registry', 'factor_evidence.json')}, 'Grep factor_evidence.json 파일')
G('O06', 'block', {'path': '.cache/factor_db'}, 'Grep .cache/factor_db(IC 패널 디렉터리)')
R('O07', 'block', '06_Registry/ast_structure_log.jsonl', 'ast_structure_log.jsonl(팩터별 canonical_screen port_t — 09-23 B1 설계 실수신)')
R('O08', 'block', '06_Registry/hypothesis_index.json', 'hypothesis_index.json(전략 전기간 성과 원장)')
R('O09', 'block', '04_Research/01_reports/p0/ledger_l1_post_epoch.json', '원장 사본(04_Research/01_reports — 구 정규식 밖 이름)')
R('O10', 'block', '04_Research/factor_rotation/fof/_factor_ic.rds', '팩터 IC rds(토큰 규칙 · 구 구역 밖)')
G('O11', 'block', {'path': '04_Research/factor_rotation'}, 'Grep 04_Research/factor_rotation(새 구역 04_Research — 구판 구역 밖)')
G('O12', 'block', {'path': '04_Research/decision_framework', 'glob': '*.parquet'}, 'Grep 04_Research/decision_framework glob=*.parquet(팩터 수익률)')
R('O13', 'block', 'qepm/memory/evidence_summary/fam.json', '계열 evidence_summary(ff5 t)')
G('O14', 'block', {'path': 'qepm/memory'}, 'Grep qepm/memory(evidence 포함 · 새 shallow 구역)')
R('O15', 'block', 'outputs/ramp/latent_factor_returns.parquet', 'outputs/ramp 팩터 수익률(새 구역 outputs)')
R('O16', 'block', '04_Research/strategies/S1/output/perf_novel_name.csv', '이름 목록 밖 성과 csv(머리 열 port_t·calmar·cagr → R1_content)')
R('O17', 'block', '06_Registry/novel_stats_table.json', '이름 목록 밖 성과 json(구조 키 calmar·sharpe → R1_content)')
G('O18', 'block', {'path': '06_Registry/novel_stats_table.json'}, 'Grep 이름 목록 밖 성과 json 파일(R1_content)')
R('O19', 'pass', '02_Infrastructure/factor_db/factor_registry.json', '팩터 등록부(이름·정의·계열 — 본문 속 port_t 는 키가 아니다)')
R('O20', 'pass', '02_Infrastructure/worktask/constraint_defaults.json', '등급 문턱 설정(구조 키 3종이지만 열린 경로 02_Infrastructure)')
R('O21', 'block', 'qepm/memory/axioms/distilled/DIST-x.json', '공리 distilled 사본(§P — L-code 수치 사본 · 열린 경로는 active/ 로 좁혔다 · 구판 pass)')
R('O22', 'pass', '06_Registry/pit_quarantine.json', '격리 목록(구조 키 1종 < 문턱 2)')
R('O23', 'pass', '.cache/rf_b5_design/b/design_r1.json', '설계 레인 자기 설계 캐시(구조 키 0)')
R('O24', 'pass', '06_Registry/weight_catalog.json', '비중 카탈로그')
R('O25', 'pass', '06_Registry/reinforce_program.json', '격자 — "select_winner_by": "port_t" 는 값이지 키가 아니다')
L('O26', 'block', {'pattern': '06_Registry/factor_evidence.json'}, 'Glob factor_evidence 리터럴(R1)')
L('O27', 'pass', {'pattern': '06_Registry/**/*factor*.json'}, 'Glob 06_Registry/**/*factor*.json(이름 열거만 — 09-23 B1 설계 실사용)')
G('O28', 'block', {'path': 'qepm/memory/axioms'}, 'Grep qepm/memory/axioms(§P — distilled 사본 포함 · 구판 pass)')
put('O29', 'arm', 'block', 'Read', {'file_path': '06_Registry/factor_evidence.json'}, '생성 표식: factor_evidence')
# P. (R2 적대 검증 수리 2026-09-25) 운영 실증 우회 — 좁힌 glob 순회 · 확장자 변형 · 구역 밖 디렉터리 · 수치 사본
G('P01', 'block', {'path': '04_Research/90_legacy', 'glob': 'residual_x.csv', 'output_mode': 'content'}, '좁힌 glob 디렉터리 Grep → 이름 밖 IC csv(순회가 내용으로 — 운영 residual_alpha_ranking.csv 재현)')
G('P02', 'block', {'path': '06_Registry', 'glob': 'novel_stats_table.json'}, '좁힌 glob 06_Registry → 이름 밖 성과 json(Read 는 O17 이 막는데 Grep 은 통과하던 것)')
G('P03', 'block', {'path': '04_Research/strategies', 'glob': 'perf_novel_name.csv'}, '좁힌 glob 전략 → 이름 밖 성과 csv(운영 s5_research_slate_*.json 재현)')
R('P04', 'block', '06_Registry/novel_stats_table.json.bak_1', '백업 접미사 .json.bak_1(확장자 끝 판정 우회 — 운영 governance_log.json.bak.* 재현)')
R('P05', 'block', '04_Research/x/bom_perf.csv', 'BOM 머리 csv(첫 열 port_t 가 BOM 에 붙어 빠지던 것)')
R('P06', 'block', '.cache/rf_lcode_mech/RP_x_B1.materials.txt', '설계 캐시 재료 사본(교차 entry 칸별 PORT_t 표 — 프롬프트 인라인이라 열 이유 없음)')
R('P07', 'block', '.cache/rf_b5_design/b/materials_r1.txt', 'B5 설계 재료 사본(arm 성과 이력)')
G('P08', 'block', {'path': '.cache/rf_lcode_mech'}, 'Grep 설계 캐시(재료 사본 포함) 무필터')
R('P09', 'block', '.cache/scheduler_logs/reinforce_auto_x.log', '스케줄러 로그(셀별 grade·port_t·calmar = reinforce_auto_log 사본)')
R('P09b', 'block', '.cache/rf_parallel/spec_B1_3__RP_x.json', '병렬 셀 사양(recent_attempts = 앞 칸 등급·PORT_t + 팩터 구성 — 구조 키 0 이라 내용 층 밖)')
G('P10', 'block', {'path': 'qepm/registry', 'glob': 'novel_perf.csv'}, '구역 밖 디렉터리 좁힌 Grep → 성과 csv(순회 없이 통과하던 것)')
G('P11', 'pass', {'path': 'qepm/registry', 'glob': 'README.md'}, '구역 밖 디렉터리 순회 — 비데이터 파일은 통과(양성 대조)')
R('P12', 'block', 'qepm/memory/axioms/candidates/CAND-x.json', '공리 후보 사본(IC 수치 서술)')
R('P13', 'pass', 'qepm/memory/axioms/active/AX-x.json', '활성 공리(열린 경로 active/ — 구조 키 2종이어도 면제)')
G('P14', 'pass', {'path': 'qepm/memory/axioms/active'}, 'Grep 활성 공리 디렉터리(열린 경로)')
R('P15', 'block', 'qepm/memory/axioms/sot_x.json', 'axioms 뿌리의 통계 json(열린 경로를 active/ 로 좁힌 효과)')
R('P16', 'pass', '.cache/rf_lcode_mech/RP_x_B1.mechanism.json', '설계 산출 되읽기(기전 json — 남은 위험: 교차 entry 사본이기도 하다)')
G('P17', 'pass', {'path': '.cache/rf_lcode_mech', 'glob': '*.mechanism.json'}, '설계 캐시 좁힌 glob(산출만) — 통과')
G('P18', 'pass', {'path': '04_Research/90_legacy', 'glob': '*.R'}, '좁힌 코드 glob — 순회 생략 유지')
G('P19', 'pass', {'path': '.cache/rf_b5_design', 'glob': '*.json'}, '설계 캐시 좁힌 glob=*.json — 재료 크기 메타(materials_r1.txt.sizes.json)는 재료 사본이 아니다(.txt 끝 고정)')
if short83:
    R('P20', 'block', w('06_Registry', short83), '8.3 짧은 이름(%s — 실경로 novel_stats_table.json · 입력 형태 확장자만 보던 판 우회)' % short83)
else:
    put('P20', 'design', 'skip', 'Read', {'file_path': w('06_Registry', 'novel_stats_table.json')}, '8.3 짧은 이름 — 이 볼륨이 8.3 이름을 만들지 않는다')
# E. Glob 열거(R3)
L('E01', 'pass', {'pattern': '06_Registry/*.json'}, 'Glob 06_Registry/*.json — 이름 열거만(원장 내용은 R1 이 Read 에서)')
L('E02', 'pass', {'pattern': '**/*.R'}, 'Glob **/*.R')
L('E03', 'pass', {'pattern': 'stage_artifacts/replication/*/0?_*.csv'}, 'Glob 복제 0?_*.csv — 이름 열거만')
L('E04', 'pass', {'pattern': '.cache/rf_b1_design/*.json'}, 'Glob 설계 캐시')
L('E05', 'block', {'path': memw, 'pattern': '*'}, 'Glob 기억 디렉터리 *')
L('E06', 'pass', {'pattern': '06_Registry/rf_overlay*'}, 'Glob 06_Registry/rf_overlay*')
L('E07', 'pass', {'pattern': '**/*'}, 'Glob **/* (루트 — 기억 디렉터리 밖 = 이름 열거만)')
L('E08', 'block', {'pattern': '06_Registry/reinforce_ledger_l1.json'}, 'Glob 원장 리터럴')
L('E09', 'pass', {'pattern': '02_Infrastructure/reinforcement/overlay_arms/*'}, 'Glob arm 디렉터리')
L('E10', 'pass', {'path': sbw, 'pattern': '**/0[2-9]_*.csv'}, 'Glob **/0[2-9]_*.csv — 이름 열거만')
L('E11', 'block', {'path': homew + B + '.claude' + B + 'projects', 'pattern': '*/memory/*.md'}, 'Glob 기억 카드 이름(요약) 열거')
L('E12', 'block', {'path': homew + B + '.claude', 'pattern': '**/*.md'}, 'Glob ~/.claude/**/*.md(기억 포함)')
# F. 셸 판(R4) — 현재 matcher 밖(판정만)
S('F01', 'block', 'Bash', 'cat 06_Registry/reinforce_ledger_l*.json', '셸 글롭')
S('F02', 'block', 'PowerShell', 'Get-Content 06_Registry' + B + 'reinforce_*.json', 'PS 글롭(역슬래시)')
S('F03', 'block', 'Bash', 'python -c "print(open(\'06_Registry/reinforce_\'+\'ledger_l1.json\').read())"', '파이썬 문자열 결합')
S('F04', 'block', 'PowerShell', "Get-Content (('06_Registry/reinforce_','ledger_l1.json') -join '')", 'PS -join 결합')
S('F05', 'block', 'Bash', "find . -name '*.json'", 'find 루트')
S('F06', 'block', 'PowerShell', 'Get-ChildItem -Recurse -Filter *.csv stage_artifacts', 'PS 재귀 열거')
S('F07', 'block', 'PowerShell', 'findstr /s calmar *.json', 'findstr /s')
S('F08', 'block', 'Bash', 'rg calmar', 'rg 루트')
S('F09', 'block', 'Bash', 'cd 02_Infrastructure && cd .. && find . -name x', 'cd 추적 → 루트 find')
S('F10', 'block', 'PowerShell', 'findstr /N /C:"calmar" "' + w('06_Registry', 'reinforce_ledger_l1.json') + '"', '실측 우회(transcript) findstr 원장')
S('F11', 'block', 'Bash', 'cat ~/.claude/projects/' + slug + '/memory/MEMORY.md', '셸 기억')
S('F12', 'block', 'Bash', 'ls ~/.c*/p*/*/m*/', '셸 글롭 → 기억 디렉터리')
S('F13', 'pass', 'Bash', 'ls 02_Infrastructure/ops', '평범한 ls')
S('F14', 'pass', 'Bash', 'Rscript 02_Infrastructure/ops/x.R', 'Rscript 실행')
S('F15', 'pass', 'Bash', 'grep -n foo 02_Infrastructure/ops/x.R', '파일 grep')
S('F16', 'pass', 'Bash', 'cd 02_Infrastructure && find . -name "*.R"', 'cd 뒤 코드 find')
S('F17', 'pass', 'PowerShell', 'Get-ChildItem 02_Infrastructure/reinforcement/overlay_arms', 'PS arm 목록')
S('F18', 'pass', 'Bash', 'find .cache/rf_b1_design -name "*.json"', 'find 설계 작업 디렉터리(shallow)')
S('F19', 'block', 'Bash', 'ls -R .cache/rf_parallel', 'ls -R 병렬 결과')
S('F20', 'block', 'Bash', 'find 04_Research/factor_rotation -name x', '셸 find 04_Research(R2 새 구역 — m21 표적)')
# G. 생성 표식 회귀(구판 사례 그대로 — 상대경로)
put('G01', 'arm', 'block', 'Read', {'file_path': '06_Registry/reinforce_ledger_l1.json'}, '생성: 원장')
put('G02', 'arm', 'block', 'Read', {'file_path': '04_Research/x/stage_artifacts/authoritative_remeasure.json'}, '생성: 권위재측정')
put('G03', 'arm', 'block', 'Read', {'file_path': '06_Registry/overlay_mechanism_map.json'}, '생성: 기전지도')
put('G04', 'arm', 'pass', 'Read', {'file_path': '02_Infrastructure/reinforcement/overlay_arms/dbeta_tilt.R'}, '생성: arm 디렉터리 과잉 차단 없음')
put('G05', 'arm', 'block', 'Grep', {'pattern': 'grade', 'path': '06_Registry/reinforce_ledger_l1.json'}, '생성: Grep path 키')
put('G06', 'both', 'block', 'Read', {'file_path': w('06_Registry', 'reinforce_ledger_l1.json')}, '두 표식 동시')
io.open(os.path.join(out, 'expect.tsv'), 'w', encoding='utf-8', newline='').write('\n'.join(rows) + '\n')
PYEOF
[ -s "$T/cases/expect.tsv" ] || { ng "사례 생성 실패" "$PY"; printf '{"test":"arm_gen_read_guard","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"; exit 1; }

# ── A. 평시 무발화 ───────────────────────────────────────────────────────────────
echo "--- A. 평시(표식 없음) — 전 사례 '{}' ---"
bad=""; n=0
while IFS=$'\t' read -r id mode want desc; do
  n=$((n+1)); out="$(fire 0 "$T/cases/$id.json")"; [ "$out" = '{}' ] || bad="$bad $id"
done < "$T/cases/expect.tsv"
[ -z "$bad" ] && ok "A1 평시 무발화 — ${n}사례 전부 '{}'(측정 경로 포함)" || ng "A1 평시에 발화" "$bad"
out="$(cd "$SBX" && env -u QVEST_ARM_GEN QVEST_DESIGN_LANE=0 bash "$HOOK" < "$T/cases/B01.json" 2>/dev/null)"
[ "$out" = '{}' ] && ok "A2 QVEST_DESIGN_LANE=0 은 표식이 아니다" || ng "A2" "$out"

# ── B~G. 표식 사례 ───────────────────────────────────────────────────────────────
echo "--- B~G. 표식 사례 (B 위반 · C 정당 · D Grep 범위 · E Glob · F 셸 · G 생성 회귀) ---"
while IFS=$'\t' read -r id mode want desc; do
  if [ "$want" = skip ]; then sk "$id $desc" "환경 불가(junction·8.3 이름 생성 불가) — 미측정"; continue; fi
  out="$(fire "$mode" "$T/cases/$id.json")"; got="$(verdict "$out")"
  [ "$got" = block ] && printf '%s' "$out" > "$T/blocks/$id.out"
  if [ "$got" = "$want" ]; then ok "$id $desc → $want"; else ng "$id $desc" "기대 $want · 실제 $got"; fi
done < "$T/cases/expect.tsv"

# ── H. 출력 JSON · fail-closed ─────────────────────────────────────────────────────
echo "--- H. 출력 JSON 유효성 · fail-closed ---"
jv="$("$PY" - "$(wp "$T/blocks")" <<'PYEOF'
import io, json, os, sys
d = sys.argv[1]; n = 0; bad = []
for f in sorted(os.listdir(d)):
    s = io.open(os.path.join(d, f), encoding='utf-8').read()
    n += 1
    try:
        o = json.loads(s)
        if o.get('decision') != 'block' or 'ARM_GEN_READ_BLOCKED' not in o.get('reason', ''):
            bad.append(f)
    except Exception:
        bad.append(f)
print('%d %s' % (n, ','.join(bad) or '-'))
PYEOF
)"
jn="${jv%% *}"; jb="${jv#* }"; jb="${jb%$'\r'}"
[ "${jn:-0}" -ge 30 ] && [ "$jb" = "-" ] && ok "H1 block 출력 ${jn}건 전부 유효 JSON(역슬래시 절대경로 사례 포함 — 구판은 \\U 무효 이스케이프)" || ng "H1 JSON" "n=$jn bad=$jb"
NOPY="$T/no_such_python.exe"
out="$(fire design "$T/cases/B02.json" "" "$NOPY")"; [ "$(verdict "$out")" = block ] && ok "H2 fail-closed: 판정기 부재 + 원장 Read(역슬래시) → block" || ng "H2" "$out"
out="$(fire design "$T/cases/C02.json" "" "$NOPY")"; [ "$out" = '{}' ] && ok "H3 fail-closed: 판정기 부재 + 엔진 Read → pass" || ng "H3" "$out"
out="$(fire design "$T/cases/D07.json" "" "$NOPY")"; [ "$(verdict "$out")" = block ] && ok "H4 fail-closed: 판정기 부재 + Grep → block(범위 판정 불능)" || ng "H4" "$out"
out="$(fire 0 "$T/cases/B02.json" "" "$NOPY")"; [ "$out" = '{}' ] && ok "H5 평시는 판정기 부재여도 '{}'" || ng "H5" "$out"
printf 'not json at all reinforce_ledger_l1.json' > "$T/cases/X1.json"
out="$(fire design "$T/cases/X1.json")"; [ "$(verdict "$out")" = block ] && ok "H6 파싱 불능 + 측정 경로 흔적 → block" || ng "H6" "$out"
printf '{"tool_name":"Read","tool_input":' > "$T/cases/X2.json"
out="$(fire design "$T/cases/X2.json")"; [ "$out" = '{}' ] && ok "H7 파싱 불능 + 흔적 없음 → pass" || ng "H7" "$out"
[ -s "$T/guard.log" ] && grep -q 'BLOCK' "$T/guard.log" && ok "H8 차단 로그 = QVEST_ARM_GEN_GUARD_LOG(임시 파일)" || ng "H8 로그"

# ── I. 표본 자기일관성 ───────────────────────────────────────────────────────────────
echo "--- I. 구역 표본 자기일관성 ---"
printf '{"tool_name":"AgrgSelftest","tool_input":{},"cwd":"%s"}' "$(printf '%s' "$SBXW" | sed 's/\\/\\\\/g')" > "$T/cases/X3.json"
selftest(){ (cd "$SBX" && env -u QVEST_ARM_GEN QVEST_DESIGN_LANE=1 AGRG_SELFTEST=1 QVEST_PY="$PY" USERPROFILE="$HOMEW" HOME="$HOMEF" \
      CLAUDE_PROJECT_DIR="$SBXW" QM_ROOT="$SBXW" QVEST_ARM_GEN_GUARD_LOG="$T/guard.log" bash "$HOOK" < "$1" 2>/dev/null); }
st="$(selftest "$T/cases/X3.json")"
out="$(selftest "$T/cases/B02.json")"; [ "$(verdict "$out")" = block ] && ok "I0 자기진단 표식이 켜져도 실제 원장 Read 는 block(구멍 아님)" || ng "I0 자기진단이 판정을 바꿨다" "$out"
iv="$(printf '%s' "$st" | "$PY" -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print('parse_fail'); sys.exit(0)
rg=d.get('regions') or []
need=['/06_registry','/stage_artifacts','/04_research/strategies','/qepm/research','/.cache','/.claude/projects/c--fake-proj/memory']
miss=[n for n in need if not any(r.endswith(n) for r in rg)]
jt=any(r.endswith('/qm_cache_target') for r in rg)
print('%d %d %s %s' % (len(rg), len(d.get('unmatched_samples') or []), ','.join(miss) or '-', 'J' if jt else 'noJ'))" 2>/dev/null | tr -d '\r')"
set -- $iv
[ "${1:-0}" -ge 5 ] 2>/dev/null && [ "${2:-x}" = 0 ] && ok "I1 구역 표본 전부가 R1 정규식에 걸린다(구역 ${1:-?}개)" || ng "I1 자기일관성(구역 ≥5 · 불일치 0)" "$iv"
[ "${3:-x}" = "-" ] && ok "I2 기대 구역 6종 존재(06_Registry·stage_artifacts·04_Research/strategies·qepm/research·.cache·기억)" || ng "I2 구역 누락" "$iv"
if [ "$JUNCTION" = 1 ]; then [ "${4:-}" = J ] && ok "I3 junction 실경로(.cache → 대상)가 구역에 든다" || ng "I3 실경로 해소" "$iv"
else sk "I3 junction" "mklink /J 불가"; fi

# ── J. 레인 배선(정적) ──────────────────────────────────────────────────────────────
echo "--- J. 레인 배선(정적) ---"
lane_scan(){ "$PY" - "$(wp "$1")" <<'PYEOF'
import io, os, re, sys
ops = sys.argv[1]
REQ = {'rf_b1_design.sh': 'QVEST_DESIGN_LANE', 'rf_b5_design.sh': 'QVEST_DESIGN_LANE',
       'rf_lcode_mechanism.sh': 'QVEST_DESIGN_LANE', 'rf_overlay_propose.sh': 'QVEST_ARM_GEN'}
def blocks(lines, i):
    b = [lines[i]]; j = i
    while lines[j].rstrip().endswith('\\') and j + 1 < len(lines):
        j += 1; b.append(lines[j])
    return '\n'.join(b)
def tools(b, opt):
    m = re.search(opt + r'\s+"([^"]*)"', b)
    return None if not m else [t.strip() for t in m.group(1).split(',')]
SH = [t for t in os.environ.get('AGRG_SHELL_TOOLS', 'Bash,PowerShell').split(',') if t]   # (B-1) 셸 통로 7종
problems = []; found = {k: 0 for k in REQ}; n_marked = 0
for fn in sorted(os.listdir(ops)):
    if not fn.endswith('.sh'):
        continue
    lines = io.open(os.path.join(ops, fn), encoding='utf-8', errors='replace').read().splitlines()
    for i, l in enumerate(lines):
        s = l.strip()
        if s.startswith('#'):
            continue
        if re.search(r'\bexport\s+(QVEST_DESIGN_LANE|QVEST_ARM_GEN)\b', l):
            problems.append('%s:%d export 표식(자식 전체로 샌다)' % (fn, i + 1))
        m = re.search(r'(^|[\s;&|(])(QVEST_DESIGN_LANE|QVEST_ARM_GEN)=1\s', l)
        if not m:
            continue
        n_marked += 1
        b = blocks(lines, i)
        if not re.search(r'\b(rf_llm_agent_run|claude)\b', b):
            problems.append('%s:%d 표식이 claude 호출이 아닌 곳에 있다' % (fn, i + 1)); continue
        al, dl = tools(b, '--allowed-tools'), tools(b, '--disallowed-tools')
        miss = [t for t in SH if dl is None or t not in dl]
        if miss:
            problems.append('%s:%d --disallowed-tools 에 셸 통로 누락 %s (현재 %s)' % (fn, i + 1, ','.join(miss), dl))
        if al is None or any(t in al for t in SH):
            problems.append('%s:%d --allowed-tools 가 없거나 셸 도구를 허용(%s)' % (fn, i + 1, al))
        if fn in REQ and m.group(2) == REQ[fn] and 'rf_llm_agent_run' in b:
            found[fn] += 1
for fn, k in REQ.items():
    if found[fn] < 1:
        problems.append('%s: %s=1 을 실은 rf_llm_agent_run 호출이 없다' % (fn, k))
print('MARKED %d' % n_marked)
for p in problems:
    print('PROBLEM ' + p)
PYEOF
}
js="$(lane_scan "$OPS" | tr -d '\r')"
jp="$(printf '%s\n' "$js" | grep -c '^PROBLEM' || true)"
[ "$jp" = 0 ] && ok "J1 설계 레인 3종·생성 레인 1종 — 표식 호출 $(printf '%s' "$js" | sed -n 's/^MARKED //p')곳 전부 셸 통로 7종($AGRG_SHELL_TOOLS) 금지 · export 0" \
  || ng "J1 레인 배선" "$(printf '%s\n' "$js" | grep '^PROBLEM' | head -4 | tr '\n' ' ')"
mkdir -p "$T/jm1" "$T/jm2" "$T/jm3" "$T/jm4" "$T/jm5"
for f in rf_b1_design.sh rf_b5_design.sh rf_lcode_mechanism.sh rf_overlay_propose.sh; do for k in 1 2 3 4 5; do cp "$OPS/$f" "$T/jm$k/"; done; done
sed -i 's/"Bash,PowerShell,Monitor,/"Bash,Monitor,/' "$T/jm1/rf_b5_design.sh"
sed -i 's/^QVEST_DESIGN_LANE=1 LLM_FALLBACK_MODEL="" rf_llm_agent_run/LLM_FALLBACK_MODEL="" rf_llm_agent_run/' "$T/jm2/rf_lcode_mechanism.sh"
printf '\nexport QVEST_DESIGN_LANE=1\n' >> "$T/jm3/rf_b1_design.sh"
sed -i 's/"Bash,PowerShell,Monitor,/"Bash,PowerShell,/' "$T/jm4/rf_b1_design.sh"             # (B-1) Monitor 금지 삭제 = 09-17 실측 통로
sed -i 's/"Bash,PowerShell,Monitor,/"Bash,PowerShell,/' "$T/jm5/rf_overlay_propose.sh"       # (B-1) 생성 레인도 같은 조건
if cmp -s "$T/jm1/rf_b5_design.sh" "$OPS/rf_b5_design.sh" || cmp -s "$T/jm2/rf_lcode_mechanism.sh" "$OPS/rf_lcode_mechanism.sh" \
   || cmp -s "$T/jm4/rf_b1_design.sh" "$OPS/rf_b1_design.sh" || cmp -s "$T/jm5/rf_overlay_propose.sh" "$OPS/rf_overlay_propose.sh"; then
  ng "J2 돌연변이" "sed 무변화(좌표 낡음)"
else
  m1="$(lane_scan "$T/jm1" | grep -c 'rf_b5_design.sh.*누락 PowerShell' || true)"
  m2="$(lane_scan "$T/jm2" | grep -c 'rf_lcode_mechanism.sh: QVEST_DESIGN_LANE=1' || true)"
  m3="$(lane_scan "$T/jm3" | grep -c 'rf_b1_design.sh.*export' || true)"
  m4="$(lane_scan "$T/jm4" | grep -c 'rf_b1_design.sh.*누락 Monitor' || true)"
  m5="$(lane_scan "$T/jm5" | grep -c 'rf_overlay_propose.sh.*누락 Monitor' || true)"
  [ "$m1" -ge 1 ] && [ "$m2" -ge 1 ] && [ "$m3" -ge 1 ] && [ "$m4" -ge 1 ] && [ "$m5" -ge 1 ] \
    && ok "J2 돌연변이 5종 검출 — PowerShell 금지 삭제 · 설계 표식 삭제 · export 누출 · Monitor 금지 삭제(설계·생성)" || ng "J2 판별력" "m1=$m1 m2=$m2 m3=$m3 m4=$m4 m5=$m5"
fi

# ── K. 레인 배선(동적) — 실제 호출 블록을 가짜 claude 로 재생 ─────────────────────────────
echo "--- K. 레인 배선(동적) ---"
cat > "$T/fake_claude.sh" <<'EOF'
#!/usr/bin/env bash
printf 'DES=%s UNA=%s AM=%s ARGS=%s\n' "${QVEST_DESIGN_LANE:-}" "${QVEST_UNATTENDED_LANE:-}" "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" "$*"
EOF
chmod +x "$T/fake_claude.sh"; printf 'prompt\n' > "$T/pf.txt"
if [ ! -f "$OPS/rf_llm_env.sh" ] || ! grep -q '^rf_llm_agent_run()' "$OPS/rf_llm_env.sh"; then
  sk "K 동적 재생" "rf_llm_env.sh::rf_llm_agent_run 부재"
else
  for lane in rf_b1_design.sh rf_b5_design.sh rf_lcode_mechanism.sh; do
    blk="$("$PY" - "$(wp "$OPS/$lane")" <<'PYEOF'
import io, re, sys
lines = io.open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
for i, l in enumerate(lines):
    if not l.strip().startswith('#') and re.search(r'(^|\s)QVEST_DESIGN_LANE=1\s.*rf_llm_agent_run', l):
        b = [l]; j = i
        while lines[j].rstrip().endswith('\\') and j + 1 < len(lines):
            j += 1; b.append(lines[j])
        print('\n'.join(b)); break
PYEOF
)"
    if [ -z "$blk" ]; then ng "K $lane" "설계 표식 호출 블록 없음"; continue; fi
    printf '%s\n' "$blk" > "$T/k_block.sh"
    res="$(env -u QVEST_DESIGN_LANE -u QVEST_UNATTENDED_LANE -u CLAUDE_CODE_DISABLE_AUTO_MEMORY bash -c '
      . "$1"; LLM_MODEL=m; LLM_EFFORT=e; LLM_FALLBACK_MODEL=""; RF_CLAUDE_BIN="$2"
      PF="$3"; RUN_OUT="$4"; DDIR="$5"; ADIR="$5"; GDIR="$5"; WDIR="$5"; QVEST_B5_TIMEOUT=30
      . "$6"
      echo "RC=$LLM_RC AFTER=${QVEST_DESIGN_LANE:-unset} CHILD=$(bash -c "echo \${QVEST_DESIGN_LANE:-unset}")"
    ' _ "$OPS/rf_llm_env.sh" "$T/fake_claude.sh" "$T/pf.txt" "$T/k_out.txt" "$T" "$T/k_block.sh" 2>&1 | tr -d '\r' | tail -1)"
    ko="$(tr -d '\r' < "$T/k_out.txt" 2>/dev/null | head -1)"
    # (B-1) claude 가 실제로 받은 --disallowed-tools 값에 셸 통로 7종이 전부 있는가
    dtv="$(printf '%s' "$ko" | sed -n 's/.*--disallowed-tools \([^ ]*\).*/\1/p')"; kmiss=""
    for t in ${AGRG_SHELL_TOOLS//,/ }; do case ",$dtv," in *",$t,"*) ;; *) kmiss="$kmiss $t" ;; esac; done
    case "$ko" in
      "DES=1 UNA=1 AM=1 "*--disallowed-tools*)
        if [ -n "$kmiss" ]; then ng "K $lane 셸 통로 미금지" "누락:$kmiss · 받은 값=[$dtv]"
        else case "$res" in *"AFTER=unset CHILD=unset"*) ok "K $lane — claude 에 표식 3종 + 셸 통로 7종 금지(Monitor 포함) · 호출 뒤 셸·자식에 표식 없음" ;;
                            *) ng "K $lane 표식 누출" "$res" ;; esac; fi ;;
      *) ng "K $lane" "claude 가 받은 것=[$ko] res=[$res]" ;;
    esac
  done
fi

# ── L. 돌연변이 — 규칙을 끈 훅 사본에서 해당 사례가 뚫린다 ─────────────────────────────────
echo "--- L. 돌연변이(훅) ---"
mut(){ # $1 이름 $2 사례 id $3 표식 $4 파이썬 치환(old) $5 (new) [$6 QVEST_PY_BIN] [$7 돌연변이 기대 판정 — 기본 pass(뚫림) · block(오차단 부활)]
  local h="$T/mut/$1.sh" out got want="${7:-pass}"
  "$PY" - "$(wp "$HOOK")" "$(wp "$h")" "$4" "$5" <<'PYEOF'
import io, sys
src, dst, old, new = sys.argv[1:5]
s = io.open(src, encoding='utf-8', newline='').read()
io.open(dst, 'w', encoding='utf-8', newline='').write(s.replace(old, new, 1) if s.count(old) == 1 else s)
PYEOF
  if cmp -s "$h" "$HOOK"; then ng "L $1" "치환 대상이 1곳이 아니다(좌표 낡음)"; return; fi
  cp "$h" "$SBX/02_Infrastructure/hooks/_mut_$1.sh"
  out="$(fire "$3" "$T/cases/$2.json" "$SBX/02_Infrastructure/hooks/_mut_$1.sh" "${6:-}")"; got="$(verdict "$out")"
  if [ "$want" = block ]; then
    [ "$got" = block ] && ok "L $1 — 교정을 끄면 사례 $2 가 다시 막힌다(오차단 부활)" || ng "L $1 판별력" "사례 $2 = $got"
    return
  fi
  if [ "$got" = block ]; then
    if [ "$1" = m06_json_concat ]; then
      printf '%s' "$out" | "$PY" -c "import json,sys; json.loads(sys.stdin.read())" >/dev/null 2>&1 \
        && ng "L $1 판별력" "무효 JSON 이 나와야 한다" || ok "L $1 — 사례 $2 출력이 무효 JSON(H1 이 잡는다)"
    else ng "L $1 판별력" "사례 $2 가 여전히 block — 이 규칙 없이도 막히면 검사가 규칙을 안 잰다"; fi
  else ok "L $1 — 규칙을 끄면 사례 $2 가 뚫린다($got)"; fi
}
mut m01_gate_design B02 design 'if [ "${QVEST_ARM_GEN:-0}" != "1" ] && [ "${QVEST_DESIGN_LANE:-0}" != "1" ]; then' 'if [ "${QVEST_ARM_GEN:-0}" != "1" ]; then'
mut m02_memory_re B09 design '|\.claud(e|~[0-9])/projects/[^/]+/memory(/|"|$)|memory\.md' ''
mut m03_replication_re B06 design '|stage_artifacts/replication/[^/]+/(0[2-9]_[a-z_]+\.csv|analysis_[a-z_]+\.(csv|md)|(equity_curve|drawdown|annual_returns)\.png)' ''
mut m04_no_slash_norm B06 design "    s = s.replace('\\\\', '/')
    m = re.match(r'^/cygdrive" "    m = re.match(r'^/cygdrive"
mut m05_no_scope D02 design "        h = scope_hit(fs, TI.get('glob') or '', TI.get('type') or '')" "        h = None"
mut m06_json_concat B01 design "    sys.stdout.buffer.write(json.dumps({'decision': 'block', 'reason': msg}, ensure_ascii=True, separators=(',', ':')).encode('ascii'))" "    sys.stdout.buffer.write(('{\"decision\":\"block\",\"reason\":\"' + msg + '\"}').encode('utf-8'))"
mut m07_failclosed_scope D07 design '  if printf '"'"'%s'"'"' "$hay" | grep -qE '"'"'"tool_name" *: *"(grep|glob|bash|powershell)"'"'"'; then _deny_const "scope"; fi' '' "$T/no_such_python.exe"
if [ "$JUNCTION" = 1 ]; then
  mut m08_no_realpath D17 design "def real(n):
    try:" "def real(n):
    return None
    try:"
else sk "L m08_no_realpath" "junction 없음"; fi
mut m09_no_glob_enum E11 design "            h = glob_hit(full, mem_only=True)
            if h:
                block('R3_glob', h)" "            h = None"
mut m10_no_concat_strip F03 design "    joined = re.sub(r'''(['\"])\s*[+.,]?\s*(['\"])''', '', raw)" "    joined = raw"
mut m11_no_dir_glob F12 design "                hit = glob_hit(f, dirs=True) if f else None" "                hit = glob_hit(f) if f else None"
mut m12_cache_deep D26 design "    '.cache': (['reinforce_auto_log.jsonl', 'rf_parallel/result_b5_1_1.json', 'overlay_ab_results.csv'], False)," "    '.cache': (['reinforce_auto_log.jsonl', 'rf_parallel/result_b5_1_1.json', 'overlay_ab_results.csv'], True)," '' block
mut m13_glob_all_regions E01 design "        if mem_only and not mem:
            continue
" "" '' block
# (B-2) R2 순회 돌연변이 — 순회를 끄면 표본 밖 측정 파일이 뚫린다 · 코드 면제를 끄면 오차단 부활 · 디렉터리 glob 을 끄면 뚫린다
mut m14_no_walk D29 design "            h = _walk(root, pre, glob, typ, pol, st, seen)" "            h = None"
mut m15_no_code_skip D39 design "                if nm.endswith(cx):
                    continue
" "" '' block
mut m17_no_dir_whitelist D36 design "stack.append((full, rel, inc or _dir_whitelisted(rel, glob)))" "stack.append((full, rel, inc))"
# (R2 · §O) 돌연변이 — 이름 층(이진 패널은 내용으로 못 잡는다) · 내용 층 · 열린 경로 · 새 구역 · 키 대 값
mut m18_no_stats_re O03 design 'MEASURE_RE="${MEASURE_RE}|${STATS_RE}"' 'MEASURE_RE="${MEASURE_RE}"'
mut m19_no_content O16 design "        h = content_hit(fsr)                                    # (R2) 이름 밖 통계 산출물 — 내용 재도출" "        h = None"
mut m20_no_open O20 design "        if rel is not None and rel.startswith(cp['open']):
            return None
" "" '' block
mut m21_no_new_region F20 design "    '04_research': (['x/analysis_ic.csv', 'x/factor_returns.parquet', 'x/ledger_l1_post_epoch.json', 'x/analysis_fmb.csv'], True),
" ""
mut m22_values_counted O25 design "krx=re.compile(r'\"(' + '|'.join(keys) + r')\"\\s*:', re.I)," "krx=re.compile(r'\"(' + '|'.join(keys) + r')\"', re.I)," '' block
# (§P · 적대 검증 수리) 돌연변이 — 순회 내용 판정 · 확장자 변형 · BOM · 구역 밖 순회 · 수치 사본 이름
mut m23_no_walk_content P01 design "                    ch = content_hit([full])                     # scandir 이름 = 긴 이름(8.3 아님) — 실경로 해소 불요" "                    ch = None"
mut m24_ext_endswith P04 design "        de = _dext(f, cp['ext'])" "        de = next((e for e in cp['ext'] if f.endswith(e)), None)"
mut m25_no_nonregion_walk P10 design "        if rel is not None and cpo and not (rel + '/').startswith(cpo['open']):" "        if False:"
mut m26_no_copies_re P06 design "|qepm/memory/axioms/(distilled|candidates|review_log|deprecated)/|rf_(b1_design|b5_design|lcode_mech|block_design)/([^/\" ]*/)*[^/\" ]*(materials|prompt)[^/\" ]*\.txt([^a-z0-9_.]|$)|scheduler_logs/|rf_parallel/spec_|backtest_registry\.csv" ""
mut m28_no_bom P05 design "s.lstrip('\ufeff').split('\n', 1)[0]" "s.split('\n', 1)[0]"
if [ -n "${SHORT83:-}" ]; then
  mut m29_first_form_only P20 design "    for f in fs:
        de = _dext(f, cp['ext'])" "    for f in fs[:1]:
        de = _dext(f, cp['ext'])"
else sk "L m29_first_form_only" "8.3 이름 없음"; fi

# ── N. (B-2) R2 순회 예산·설정 — 설정은 훅 옆 policies/ 에서 읽으므로 대체 설정은 훅 사본 디렉터리로 준다 ─────────
echo "--- N. R2 순회 예산·설정 ---"
POLSRC="$SBX/02_Infrastructure/hooks/policies/arm_gen_read_guard.json"
alt(){ # $1 이름 $2 max_entries(빈 = 설정 파일 없음 · bad = 불량 값) $3 max_seconds [$4 훅 원본 — 기본 $HOOK] → 훅 사본 경로
  local d="$T/alt_$1"; mkdir -p "$d"; cp "${4:-$HOOK}" "$d/arm_gen_read_guard.sh"
  if [ -n "$2" ]; then mkdir -p "$d/policies"
    "$PY" - "$(wp "$POLSRC")" "$(wp "$d/policies/arm_gen_read_guard.json")" "$2" "$3" <<'PYEOF'
import io, json, sys
src, dst, ne, ns = sys.argv[1:5]
d = json.load(io.open(src, encoding='utf-8'))
d['r2_walk']['max_entries'] = 0 if ne == 'bad' else int(ne)
d['r2_walk']['max_seconds'] = float(ns)
io.open(dst, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False))
PYEOF
  fi
  printf '%s' "$d/arm_gen_read_guard.sh"; }
mkmut(){ # $1 원본 훅 $2 사본 $3 old $4 new — old 가 정확히 1곳일 때만 바꾼다(아니면 사본 = 원본 → 호출자가 무변화로 잡는다)
  "$PY" - "$(wp "$1")" "$(wp "$2")" "$3" "$4" <<'PYEOF'
import io, sys
src, dst, old, new = sys.argv[1:5]
s = io.open(src, encoding='utf-8', newline='').read()
io.open(dst, 'w', encoding='utf-8', newline='').write(s.replace(old, new, 1) if s.count(old) == 1 else s)
PYEOF
}
nchk(){ # $1 id $2 기대(pass|block) $3 훅 $4 사례 [$5 사유 문자열(block 일 때 포함돼야)]
  local out got; out="$(fire design "$T/cases/$4.json" "$3")"; got="$(verdict "$out")"
  if [ "$got" != "$2" ]; then ng "$1" "기대 $2 · 실제 $got · ${out:0:160}"; return; fi
  if [ -n "${5:-}" ] && ! printf '%s' "$out" | grep -q "$5"; then ng "$1" "사유에 $5 없음 · ${out:0:160}"; return; fi
  ok "$1 → $2${5:+ ($5)}"; }
H_TINY="$(alt tiny 3 20)"; H_SLOW="$(alt slow 100000000 0.000000001)"; H_NOPOL="$(alt nopol '' '')"; H_BAD="$(alt bad bad 20)"
nchk "N1 항목 예산 3 + 루트 좁힌 glob(D40) → block — 넘치면 막는다" block "$H_TINY" D40 R2_scope_budget
nchk "N2 항목 예산 3 + 02_Infrastructure(D07) → pass — 구역과 안 겹치면 순회 안 함" pass "$H_TINY" D07
nchk "N3 항목 예산 3 + 루트 *.R(D05) → pass — 코드만 필터는 순회 생략(생성 레인 실사용)" pass "$H_TINY" D05
nchk "N4 시간 예산 1ns + 루트 좁힌 glob(D40) → block — 시간 축도 막는다" block "$H_SLOW" D40 R2_scope_budget
nchk "N5 설정 부재 + 06_Registry 카탈로그(D16) → block(fail-closed)" block "$H_NOPOL" D16 R2_policy
nchk "N6 설정 부재 + 02_Infrastructure(D07) → pass — 순회가 필요 없는 Grep 은 영향 없음" pass "$H_NOPOL" D07
nchk "N7 설정 불량(max_entries 0) + D16 → block(fail-closed)" block "$H_BAD" D16 R2_policy
nchk "N8 설정 부재 + 원장 Read(B02) → block — R1 은 설정과 무관" block "$H_NOPOL" B02 R1_path
if [ -f "$T/blocks/D29.out" ] && grep -q 'R2_walk' "$T/blocks/D29.out"; then ok "N9 D29 차단 사유 = R2_walk(표본 대조가 아니라 실제 순회가 잡았다)"
else ng "N9 D29 사유" "$(head -c 200 "$T/blocks/D29.out" 2>/dev/null)"; fi
# 돌연변이(설정 축) — 예산 검사를 끄면 N1 이 뚫리고 · 코드 생략을 끄면 N3 이 예산에 걸리고 · 설정 부재를 통과로 바꾸면 D29 가 뚫린다
mkdir -p "$T/nm"
mkmut "$HOOK" "$T/nm/nobudget.sh" "                    raise _Budget()" "                    pass"
mkmut "$HOOK" "$T/nm/noprune.sh" "    if _code_only(glob, typ, pol['code_ext']):
        return None
" ""
mkmut "$HOOK" "$T/nm/polopen.sh" "    if not pol:
        return ('R2_policy'," "    if not pol:
        return None
    if not pol:
        return ('R2_policy',"
if cmp -s "$T/nm/nobudget.sh" "$HOOK" || cmp -s "$T/nm/noprune.sh" "$HOOK" || cmp -s "$T/nm/polopen.sh" "$HOOK"; then ng "N 돌연변이" "치환 대상이 1곳이 아니다(좌표 낡음)"
else
  nchk "N10 돌연변이 예산 검사 삭제 + 항목 예산 3 → D40 pass(검사가 예산을 잰다)" pass "$(alt m_nobudget 3 20 "$T/nm/nobudget.sh")" D40
  nchk "N11 돌연변이 코드 생략 삭제 + 항목 예산 3 → D05 block(생략이 루트 *.R 을 살린다)" block "$(alt m_noprune 3 20 "$T/nm/noprune.sh")" D05 R2_scope_budget
  nchk "N12 돌연변이 설정 부재=통과 → D29 pass(fail-closed 가 표본 밖 측정 파일을 지킨다)" pass "$(alt m_polopen '' '' "$T/nm/polopen.sh")" D29
fi

# (R2 · §O) content_guard 설정 축 — 부재·불량 = 데이터 Read fail-closed · 문턱이 판정을 가른다 · R2 순회 설정과 분리
altc(){ # $1 이름 $2 수정식(nopol = 설정 파일 없음 · drop_keys = keys 삭제 · k=<json> = content_guard[k] 교체) → 훅 사본 경로
  local d="$T/altc_$1"; mkdir -p "$d"; cp "$HOOK" "$d/arm_gen_read_guard.sh"
  if [ "$2" != nopol ]; then mkdir -p "$d/policies"
    "$PY" - "$(wp "$POLSRC")" "$(wp "$d/policies/arm_gen_read_guard.json")" "$2" <<'PYEOF'
import io, json, sys
src, dst, expr = sys.argv[1:4]
d = json.load(io.open(src, encoding='utf-8'))
c = d['content_guard']
if expr == 'drop_keys':
    del c['keys']
else:
    k, v = expr.split('=', 1)
    c[k] = json.loads(v)
io.open(dst, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False))
PYEOF
  fi
  printf '%s' "$d/arm_gen_read_guard.sh"; }
HC_NOPOL="$(altc nopol nopol)"; HC_HI="$(altc hi 'min_distinct_keys=99')"; HC_LO="$(altc lo 'min_distinct_keys=1')"; HC_BAD="$(altc bad drop_keys)"
nchk "N13 content_guard 부재(설정 파일 없음) + 카탈로그 Read(C04) → block(fail-closed)" block "$HC_NOPOL" C04 R1_content_policy
nchk "N14 설정 부재 + 엔진 .R Read(C02) → pass — 데이터 파일만 fail-closed" pass "$HC_NOPOL" C02
nchk "N15 [돌연변이] 문턱 99 → 이름 밖 성과 csv(O16) pass — 문턱이 판정을 가른다" pass "$HC_HI" O16
nchk "N16 [돌연변이] 문턱 1 → 단일 키 격리 목록(O22) block — 문턱 2 가 막는 오차단" block "$HC_LO" O22 R1_content
nchk "N17 content_guard 불량(keys 삭제) + 등록부 Read(O19) → block(fail-closed)" block "$HC_BAD" O19 R1_content_policy
# (§P) N18 뒤집음 — 순회가 내용 판정을 쓰므로 content_guard 불량이면 순회도 **데이터 파일에서** fail-closed(구판: pass = 두 설정 분리)
nchk "N18 content_guard 불량 + 좁힌 glob 데이터 파일 Grep(D16) → block(순회 내용 판정 fail-closed)" block "$HC_BAD" D16 R2_walk_content_policy
nchk "N18b content_guard 불량 + 비데이터 디렉터리 Grep(D28 memory_inbox README) → pass — 데이터 파일만 fail-closed" pass "$HC_BAD" D28
HC_WIDE="$(altc wide 'open_prefixes=["02_infrastructure/","qepm/memory/axioms/"]')"
nchk "N20 [돌연변이] 열린 경로를 qepm/memory/axioms/ 로 되돌림 → axioms 뿌리 통계 json(P15) pass — active/ 로 좁힌 것이 판정을 가른다" pass "$HC_WIDE" P15
for id in P01 P02 P03 P10; do
  if [ -f "$T/blocks/$id.out" ] && grep -q 'R2_walk_content' "$T/blocks/$id.out"; then ok "N21 $id 차단 사유 = R2_walk_content(순회가 이름이 아니라 내용으로 잡았다)"
  else ng "N21 $id 사유" "$(head -c 200 "$T/blocks/$id.out" 2>/dev/null)"; fi
done
for id in O16 O17 O18; do
  if [ -f "$T/blocks/$id.out" ] && grep -q 'R1_content' "$T/blocks/$id.out"; then ok "N19 $id 차단 사유 = R1_content(이름이 아니라 내용이 잡았다)"
  else ng "N19 $id 사유" "$(head -c 200 "$T/blocks/$id.out" 2>/dev/null)"; fi
done

# ── M. 등록 — 훅이 settings.json 에 실제로 걸려 있는가(파일만 있고 안 도는 계기 금지) ──────────────
echo "--- M. 등록 ---"
if [ -f "$SETTINGS" ]; then
  REG="$("$PY" - "$(wp "$SETTINGS")" <<'PYEOF' 2>/dev/null | tr -d '\r'
import io, json, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8'))
ms = [g.get('matcher', '') for g in d.get('hooks', {}).get('PreToolUse', []) if 'arm_gen_read_guard.sh' in json.dumps(g)]
print('%d %s' % (len(ms), '|'.join(ms)))
PYEOF
)"
  case "$REG" in
    1\ *Read*) case "$REG" in *Grep*Glob*|*Glob*Grep*) ok "M1 settings.json 에 등록됨 — matcher=${REG#* }" ;; *) ng "M1 matcher 에 Grep·Glob 없음" "$REG" ;; esac ;;
    *) ng "M1 미등록 또는 중복 — 존재하지만 발화하지 않는 계기" "$REG" ;;
  esac
else sk "M1 등록" "settings.json 없음: $SETTINGS"; fi

echo
printf '합계: 통과 %d · 실패 %d · 건너뜀 %d\n' "$PASS" "$FAIL" "$SKIP"
printf '{"test":"arm_gen_read_guard","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
