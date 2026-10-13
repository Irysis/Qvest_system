#!/usr/bin/env bash
# test_paper_atlas_run.sh — 메커니즘 지도 추출 레인 검사 (샌드박스 · claude 미호출)
#   ① 게이트 꺼짐 → 아무것도 안 함 ② 일감 0 → 작업 폴더를 남기지 않음 ③ 일감 있음 + DRYRUN → 일감 파일이 생기고 claude 는 안 부름
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$(mktemp -d)"; command -v cygpath >/dev/null 2>&1 && SB="$(cygpath -m "$SB")"
mkdir -p "$SB/02_Infrastructure/programs" "$SB/02_Infrastructure/ops" "$SB/06_Registry" "$SB/.cache/scheduler_logs"
cp "$REPO"/02_Infrastructure/programs/*.R "$SB/02_Infrastructure/programs/"
cp "$REPO/02_Infrastructure/ops/paper_atlas_run.sh" "$REPO/02_Infrastructure/ops/paper_atlas_prompt.md" "$SB/02_Infrastructure/ops/"
cp "$REPO/06_Registry/research_programs.json" "$SB/06_Registry/"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  [ok]   $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }

QM_ROOT="$SB" QVEST_PAPER_ATLAS_ENABLE=0 bash "$SB/02_Infrastructure/ops/paper_atlas_run.sh" >/dev/null 2>&1
[ ! -d "$SB/stage_artifacts/paper_atlas" ] && ok "게이트 꺼짐 → 작업 폴더 없음" || ng "게이트 꺼짐인데 작업 폴더가 생겼다"

QM_ROOT="$SB" QVEST_PAPER_ATLAS_ENABLE=1 QVEST_PAPER_ATLAS_DRYRUN=1 bash "$SB/02_Infrastructure/ops/paper_atlas_run.sh" >/dev/null 2>&1
_left=$(ls "$SB/stage_artifacts/paper_atlas" 2>/dev/null | wc -l | tr -d ' ')
[ "${_left:-0}" = "0" ] && ok "일감 0 → 작업 폴더를 남기지 않음" || ng "일감 0인데 작업 폴더 ${_left}개 남음"

(cd "$SB" && QM_ROOT="$SB" Rscript -e 'source("02_Infrastructure/programs/program_registry.R"); pr_enqueue("P2_DEFENSE", list(key="axv:2401.77777", kind="paper", title="test", engine="defense"), path=file.path(getwd(), "06_Registry/research_programs.json"))' >/dev/null 2>&1)
QM_ROOT="$SB" QVEST_PAPER_ATLAS_ENABLE=1 QVEST_PAPER_ATLAS_DRYRUN=1 bash "$SB/02_Infrastructure/ops/paper_atlas_run.sh" >/dev/null 2>&1
_job=$(ls "$SB"/stage_artifacts/paper_atlas/*/job.json 2>/dev/null | head -1)
if [ -n "$_job" ] && grep -q "axv:2401.77777" "$_job"; then ok "일감 있음 + DRYRUN → 일감 파일에 논문이 실린다"; else ng "일감 파일이 없거나 논문이 빠졌다"; fi
[ ! -f "$(dirname "${_job:-/nonexistent}")/staging.json" ] && ok "DRYRUN 은 스테이징(LLM 산출)을 만들지 않는다" || ng "DRYRUN 인데 스테이징이 생겼다"
[ ! -f "$SB/06_Registry/mechanism_atlas.jsonl" ] && ok "DRYRUN 은 지도를 쓰지 않는다" || ng "DRYRUN 인데 지도가 생겼다"

rm -rf "$SB"
echo "== paper_atlas_run: PASS $PASS · FAIL $FAIL =="
printf '{"test":"paper_atlas_run","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"   # 배터리 요약 계약
[ "$FAIL" -eq 0 ]
