#!/usr/bin/env bash
# run_l1_pilot_v2.sh — v10.2 사다리 루프 종단 파일럿 + A 경로 소방 훈련 실행기(코어 v2 · 도훈 L1-CHAIN-PILOT-FIRST-20261111 · 판단 J-20261111-010)
#   ① 거울 루트 M(저장소 밖 · PILOT_OUT 아래) = git archive HEAD(CLAUDE.md(계약의 루트 표식) · 02_Infrastructure · 04_Research/programs · 00_Lawbook · 06_Registry)
#      + 등급 계약 데이터 사본(.cache/benchmark.parquet · 요인 수익 3) + P1S01 판 확인용 엔진 사본 1 — 원본은 읽기만
#   ② 실제 원장 md5(전) → 시나리오 08_Tests/scenarios/test_scn_l1_pilot_v2.R(R_ENVIRON_USER = 빈 파일 · QM_ROOT = CLAUDE_PROJECT_DIR = RC_SA_ROOT = M ·
#      QVEST_TG_DRY_RUN=1 · 잠금 · GPU 임대 · 레인 상태 = 임시 경로) → 실행기 경로(round.sh 판 라우팅 · p4-pool · p4-status · 사슬 틱 드라이런 — 모두 M)
#      → 실제 원장 md5(후) · 발송 본문 보관 수(전 · 후) 대조 → 요약 pilot_summary.txt
#   사용: PILOT_OUT=<저장소 밖 빈 폴더> bash 08_Tests/scenarios/run_l1_pilot_v2.sh   (종료 0 = 시나리오 · 대조 전부 통과)
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
OUT=${PILOT_OUT:?PILOT_OUT 필요(저장소 밖 폴더)}
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd -P)
case "$OUT/" in "$REPO"/*) echo "[pilot] PILOT_OUT 이 저장소 안이다 — 중단"; exit 2 ;; esac
M=$OUT/mirror; rm -rf "$M" "$OUT/locks"; mkdir -p "$M/.cache" "$OUT/locks/qv" "$OUT/tick_state"   # 리프레시 · writer 잠금은 폴더 자체가 잠금 — 만들지 않는다(있으면 held)
MW=$(cygpath -m "$M"); RW=$(cygpath -m "$REPO"); OW=$(cygpath -m "$OUT")
echo "[pilot] 저장소 $RW · 거울 $MW · HEAD $(git -C "$REPO" rev-parse --short HEAD)"
git -C "$REPO" archive --format=tar HEAD CLAUDE.md 02_Infrastructure 04_Research/programs 00_Lawbook 06_Registry | tar -x -C "$M" || { echo "[pilot] 거울 만들기 실패"; exit 2; }
for f in benchmark.parquet kr_factor_returns_v2.parquet kr_factor_returns_meta.json kr_factor_returns_daily.parquet; do cp -p "$REPO/.cache/$f" "$M/.cache/" || exit 2; done
mkdir -p "$M/04_Research/strategies/RP_AUTO_2002_06975" && cp -p "$REPO/04_Research/strategies/RP_AUTO_2002_06975/engine.R" "$M/04_Research/strategies/RP_AUTO_2002_06975/"
mkdir -p "$M/stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification" && cp -p "$REPO/stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/"{prereg.json,standing_ledger.jsonl} "$M/stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/"
date '+%FT%T%z' > "$M/.pilot_mirror"
: > "$OUT/empty.Renviron"
REAL=(06_Registry/research_programs.json 06_Registry/q_judgment_ledger.json 06_Registry/decision_register.json 06_Registry/round_outcomes.jsonl
      06_Registry/factor_db_vintage.json 06_Registry/reinforce_ledger_l1.json 06_Registry/reinforce_ledger_l2.json 06_Registry/module_catalog.json
      06_Registry/rx_generator.json 06_Registry/timing_defense_evidence.json 06_Registry/book/book_registry.json 06_Registry/session_resume.json
      stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/standing_ledger.jsonl stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/prereg.json
      .cache/gpu_lease.json)
fp_real() { for f in "${REAL[@]}"; do if [ -f "$REPO/$f" ]; then printf '%s %s\n' "$(md5sum "$REPO/$f" | cut -c1-32)" "$f"; else printf 'absent %s\n' "$f"; fi; done; }
tg_n() { ls /c/tmp/qvest_tg_body_ARCHIVE 2>/dev/null | wc -l | tr -d ' '; }
fp_real > "$OUT/real_md5_before.txt"; TG0=$(tg_n)
export R_ENVIRON_USER="$OW/empty.Renviron" QM_ROOT="$MW" CLAUDE_PROJECT_DIR="$MW" RC_SA_ROOT="$MW" PILOT_REPO="$RW" QVEST_TG_DRY_RUN=1 QVEST_NO_ALERT=1 \
       QM_REFRESH_LOCKDIR="$OW/locks/refresh" QM_RAWDATA_WRITER_LOCKDIR="$OW/locks/writer" QVEST_LOCK_DIR="$OW/locks/qv" QVEST_GPU_LEASE="$OW/gpu_lease.json" \
       QVEST_RP_STATE_DIR="$MW/.cache" QVEST_RP_SLOT_DIR="$MW/06_Registry/replication_slots" CT_STATE_DIR="$OW/tick_state"
unset RC_CORE_DEFAULT
t0=$(date +%s)
Rscript "$REPO/08_Tests/scenarios/test_scn_l1_pilot_v2.R" > "$OUT/pilot_scenario.log" 2>&1; SRC=$?
echo "[pilot] 시나리오 rc=$SRC · $(( $(date +%s) - t0 ))초 · $(grep -c '\[ok\]' "$OUT/pilot_scenario.log") ok · $(grep -c '\[FAIL\]' "$OUT/pilot_scenario.log") FAIL"
## ── R 실행기 경로(거울 루트 · 읽기 전용 단계만 — 측정 단계는 배리어 대기가 있어 R 쪽에서 본다) ──────────────────────────────
RS="$M/04_Research/programs/_lib/round_core/round.sh"
LASTREL=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"v[0-9]+"' "$M/04_Research/programs/_lib/round_core/RELEASES.json" | tail -n 1 | sed -E 's/.*"(v[0-9]+)"$/\1/')
rs() { RC_ROOT_POSIX="$M" RC_ROOT_WIN="$MW" bash "$RS" "$@" 2>&1; }
{
  echo "== R1 상설 판 v2(P1S90_pilot) check — 코어 판 표기"; rs 04_Research/programs/P1_RETURN/P1S90_pilot check | grep -E '^\[check\]'
  echo "== R2 상설 판 v1(P1S01 사본) check — 코어 판 표기"; rs 04_Research/programs/P1_RETURN/P1S01_standing_qualification check | grep -E '^\[check\]'
  echo "== R3 '-' p4-pool(RC_CORE_DEFAULT=v1)"; RC_CORE_DEFAULT=v1 rs - p4-pool | grep -E '^\[p4-pool\]'
  echo "== R4 '-' p4-pool(RC_CORE_DEFAULT=v2)"; RC_CORE_DEFAULT=v2 rs - p4-pool | grep -E '^\[p4-pool\]'
  echo "== R4b '-' p4-pool(기본 = 거울 RELEASES 마지막 출시 판 $LASTREL)"; rs - p4-pool | grep -E '^\[p4-pool\]'
  echo "== R5 사슬 p4-status(사슬 사양 core_version)"; rs 04_Research/programs/P4_ASSEMBLY/P4C90_pilot p4-status | head -n 12
  echo "== R6 사슬 틱 드라이런(chain_tick.sh · 판 라우팅)"; RC_ROOT_POSIX="$M" RC_ROOT_WIN="$MW" bash "$M/02_Infrastructure/ops/chain_tick.sh" --dry-run 2>&1 | head -n 12
  echo "== R7 저장소 맨 위 '-' 폴더(만들지 않아야 한다)"; [ -e "$M/-" ] && echo "있음(결함)" || echo "없음"
} > "$OUT/pilot_runner.log"
cat "$OUT/pilot_runner.log"
## 실행기 경로 단정(로그에서 재도출) — 판 라우팅 · 기본 판 · 사슬 틱 계획 줄 · '-' 잔재 없음
RL="$OUT/pilot_runner.log"; RF=0
pmd5() { grep -A1 "^== $1 " "$RL" | tail -n 1 | sed 's/.*풀 md5 //'; }
r4b_ok() { case "$LASTREL" in v1) [ "$(pmd5 R4b)" = "$(pmd5 R3)" ] ;; v2) [ "$(pmd5 R4b)" = "$(pmd5 R4)" ] ;; *) return 1 ;; esac; }
r6_ok() { local S; S=$(sed -n '/^== R6/,/^== R7/p' "$RL")
  printf '%s\n' "$S" | grep -q '등록된 사슬 1 ' &&
  printf '%s\n' "$S" | awk -F'\t' '$1 ~ /P4C91_pilot_open$/ && $2 == "measure_base" {f=1} END {exit !f}' &&
  printf '%s\n' "$S" | awk -F'\t' '$1 ~ /P4C90_pilot$/ && $2 == "skip" && $4 == "closed" {f=1} END {exit !f}'; }
rchk() { if eval "$2"; then echo "  [ok] $1"; else echo "  [FAIL] $1"; RF=$((RF+1)); fi; }
{
  rchk "R1 상설 판 P1S90(사양 v2) → 코어 v2" "grep -A1 '^== R1' '$RL' | grep -q '코어 v2/'"
  rchk "R2 상설 판 P1S01 사본(사양 v1) → 코어 v1/e70ac0af(출시본 그대로)" "grep -A1 '^== R2' '$RL' | grep -q '코어 v1/e70ac0af'"
  rchk "R3·R4 사양 없는 호출 — RC_CORE_DEFAULT=v1 · v2 의 풀 md5 가 다르다(같은 거울 원장에서 두 판이 실제로 갈린다)" '[ "$(pmd5 R3)" != "$(pmd5 R4)" ]'
  rchk "R4b 사양 없는 호출의 기본 = 거울 RELEASES 마지막 출시 판($LASTREL — 그 판을 명시한 풀과 md5 같음)" "r4b_ok"
  rchk "R5 닫힌 사슬 p4-status(사슬 사양 v2) 판독 · 닫힘" "grep -A1 '^== R5' '$RL' | grep -q '닫힘'"
  rchk "R6 사슬 틱 드라이런 — 등록된 열린 사슬 1개 · P4C91_pilot_open 계획 = 기준 칸 측정(measure_base) · 닫힌 P4C90_pilot = skip closed" "r6_ok"
  rchk "R8 잠금 격리 — 거울 배리어 = free(열림) · 실제 배리어(총괄 세션 writer 잠금)와 무관" "sed -n '/^== R6/,/^== R7/p' '$RL' | grep -q '배리어 free(열림)'"
  rchk "R7 round.sh '-' 호출이 거울 맨 위에 '-' 폴더를 만들지 않았다" "grep -A1 '^== R7' '$RL' | grep -q '없음'"
} | tee "$OUT/pilot_runner_checks.txt"
RF=$(grep -c '\[FAIL\]' "$OUT/pilot_runner_checks.txt")
fp_real > "$OUT/real_md5_after.txt"; TG1=$(tg_n)
if diff -q "$OUT/real_md5_before.txt" "$OUT/real_md5_after.txt" >/dev/null; then RMD="불변"; else RMD="바뀜: $(diff "$OUT/real_md5_before.txt" "$OUT/real_md5_after.txt" | grep '^>' | cut -c3- | tr '\n' ' ')"; fi
{
  echo "pilot_at=$(date '+%FT%T%z') head=$(git -C "$REPO" rev-parse --short HEAD) mirror=$MW"
  echo "scenario_rc=$SRC ok=$(grep -c '\[ok\]' "$OUT/pilot_scenario.log") fail=$(grep -c '\[FAIL\]' "$OUT/pilot_scenario.log")"
  echo "runner_checks_fail=$RF"
  echo "real_ledgers=$RMD"
  echo "telegram_archive_before=$TG0 after=$TG1"
} | tee "$OUT/pilot_summary.txt"
[ "$SRC" = 0 ] && [ "$RF" = 0 ] && [ "$RMD" = "불변" ] && [ "$TG0" = "$TG1" ] && ! [ -e "$M/-" ]
