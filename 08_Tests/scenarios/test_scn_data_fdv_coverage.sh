#!/usr/bin/env bash
# test_scn_data_fdv_coverage.sh — 팩터 DB 수리 요약 ↔ 판 표식 원장 누락 감지 시나리오 (감사 레인 A · 2026-11-10)
# 대상 = 02_Infrastructure/data/factor_db_vintage_coverage.py (모래상자 루트 · 합성 요약 · 합성 원장 — 운영 원장 무접촉)
#   V1 성공 요약 + 같은 decision 원장 항목 → OK(0)      V2 성공 요약인데 원장 항목 없음 → GAP(3) · 파일명 보고
#   V3 실패 요약 · .prev_ 판은 세지 않는다 → OK      V4 decision 없는 전체 재빌드 · scope all 항목이 stamp 뒤 완료 → OK
#   V5 당월 파일이 원장 최신 완료보다 앞 → GAP(old_code)   V6 원장 결정 id 가 decision_register 에 없음 → 보고(OK 유지)
#   V7 원장 없음 → ERROR(1 · OK 로 접지 않음)          V8 돌연변이(decision 일치 비교 무력화) → V1 이 GAP 로 뒤집힘
set -uo pipefail
T=scn_data_fdv_coverage
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
SRC="$PROJ/02_Infrastructure/data/factor_db_vintage_coverage.py"
PY="$PROJ/.venv_qvest_ml/Scripts/python.exe"; [ -x "$PY" ] || PY="${QVEST_PY:-python}"
[ -f "$SRC" ] || { echo "대상 없음"; fin 0 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
box() {  # $1=이름 → 빈 모래상자
  local b="$TMP/$1"; mkdir -p "$b/06_Registry" "$b/.cache/scheduler_logs" "$b/.cache/factor_db"; echo "$b"; }
led() { printf '{"schema":"factor_db_vintage_v1","entries":[%s]}' "$2" > "$1/06_Registry/factor_db_vintage.json"; }
dreg() { printf '{"schema":"decision_register_v1","items":[%s]}' "$2" > "$1/06_Registry/decision_register.json"; }
sub_() { printf '{"schema":"factor_subset_repair/v1","stamp":"%s","result":"%s","decision":"%s"}' "$3" "$4" "$5" > "$1/.cache/scheduler_logs/$2"; }
fdb() { : > "$1/.cache/factor_db/factor_db_202611.parquet"; touch -d "$2" "$1/.cache/factor_db/factor_db_202611.parquet"; }
run() { "$PY" -X utf8 "${3:-$SRC}" --root "$1" > "$TMP/out.txt" 2>&1; echo "$?"; }
field() { sed -n "s/.*$1=\([^	]*\).*/\1/p" "$TMP/out.txt" | head -1; }
E1='{"id":"REP-A-20261110","completed_at":"2026-11-10T11:26:00+09:00","scope":{"factors":["X"]},"decision":"REP-A-20261110(도훈)"}'

echo "== $T =="
B=$(box v1); led "$B" "$E1"; dreg "$B" '{"id":"REP-A-20261110"}'; sub_ "$B" factor_subset_repair_20261110_090109.json 20261110_090109 성공 REP-A-20261110; fdb "$B" "2026-11-10 11:30"
chk "V1 기록된 수리 → rc 0" 0 "$(run "$B")"; chk "V1 status OK" OK "$(field status)"
B=$(box v2); led "$B" "$E1"; dreg "$B" '{"id":"REP-A-20261110"}'; sub_ "$B" factor_subset_repair_20261110_150000.json 20261110_150000 성공 REP-B-20261110; fdb "$B" "2026-11-10 16:00"
chk "V2 미기록 수리 → rc 3" 3 "$(run "$B")"; chk "V2 미기록 파일명 보고" factor_subset_repair_20261110_150000.json "$(field unrecorded)"
B=$(box v3); led "$B" "$E1"; dreg "$B" '{"id":"REP-A-20261110"}'; sub_ "$B" factor_subset_repair_20261110_150000.json 20261110_150000 실패 REP-C-20261110
sub_ "$B" factor_subset_repair_20261110_160000.prev_x.json 20261110_160000 성공 REP-D-20261110; fdb "$B" "2026-11-10 16:00"
chk "V3 실패 요약 · .prev_ 판 제외 → OK" OK "$( run "$B" >/dev/null; field status)"
B=$(box v4); led "$B" '{"id":"FULL-20261109","completed_at":"2026-11-09T23:31:00","scope":"all","decision":"FULL-20261109"}'; dreg "$B" '{"id":"FULL-20261109"}'
printf '{"schema":"factor_db_full_rebuild/v1","stamp":"20261109_114145","result":"성공"}' > "$B/.cache/scheduler_logs/factor_db_full_rebuild_20261109_114145.json"; fdb "$B" "2026-11-10 01:00"
chk "V4 decision 없는 전체 재빌드 · all 항목이 덮음 → OK" OK "$( run "$B" >/dev/null; field status)"
B=$(box v5); led "$B" "$E1"; dreg "$B" '{"id":"REP-A-20261110"}'; sub_ "$B" factor_subset_repair_20261110_090109.json 20261110_090109 성공 REP-A-20261110; fdb "$B" "2026-11-10 09:00"
chk "V5 당월이 수리 완료보다 앞 → rc 3" 3 "$(run "$B")"; chk "V5 current_month old_code" "old_code(factor_db_202611.parquet)" "$(field current_month)"
B=$(box v6); led "$B" "$E1"; dreg "$B" '{"id":"OTHER-20261101"}'; sub_ "$B" factor_subset_repair_20261110_090109.json 20261110_090109 성공 REP-A-20261110; fdb "$B" "2026-11-10 11:30"
chk "V6 결정 기록 누락 보고 · 판정은 OK" "OK REP-A-20261110" "$( run "$B" >/dev/null; echo "$(field status) $(field decision_unregistered)")"
B=$(box v7)
chk "V7 원장 없음 → rc 1(ERROR)" 1 "$(run "$B")"
# V8 돌연변이 — decision 일치 비교 무력화(정확히 1곳 치환)
NEEDLE='if dec and (dec == e.get("id") or dec in str(e.get("decision") or "")):'
chk "V8 치환 대상 1곳" 1 "$(grep -cF "$NEEDLE" "$SRC")"
"$PY" -c "import sys;s=open(sys.argv[1],encoding='utf-8').read();open(sys.argv[2],'w',encoding='utf-8').write(s.replace(sys.argv[3],'if False:',1))" "$SRC" "$TMP/mut.py" "$NEEDLE"
chk "V8 치환 성사" YES "$(cmp -s "$SRC" "$TMP/mut.py" && echo NO || echo YES)"
B=$(box v8); led "$B" "$E1"; dreg "$B" '{"id":"REP-A-20261110"}'; sub_ "$B" factor_subset_repair_20261110_090109.json 20261110_090109 성공 REP-A-20261110; fdb "$B" "2026-11-10 11:30"
chk "V8 돌연변이는 V1 을 GAP 로 뒤집는다" 3 "$(run "$B" x "$TMP/mut.py")"
fin "$PASS" "$FAIL"
