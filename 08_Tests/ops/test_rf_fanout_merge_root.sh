#!/usr/bin/env bash
#==============================================================================
# test_rf_fanout_merge_root.sh — 팬아웃 병합 단계: ROOT 슬래시 정규화 · 병합 실패 전파 (2026-09-06)
#
# 실사고: 세션 셸·스케줄러 셸의 QM_ROOT 는 역슬래시(C:\Users\…)다. rf_fidelity_fanout.sh 가 그 값을
#   `Rscript -e "source('$ROOT/…')"` 의 R 리터럴에 넣어 '\U' used without hex digits 로 병합기가 즉사했고
#   (09-04 16:19 · 09-06 17:58 · 18:08), 레인은 merge_done rc=1 을 적고도 exit 0 이라 verify 가 감사 없이
#   proceed 했다. verify(R)→system2 경로는 ~/.Renviron 의 슬래시 값이 물려져 살았다 — 같은 스크립트가
#   기동 부모에 따라 살고 죽는 형태.
# 양방향: ①역슬래시 QM_ROOT 로 병합만 돌려 fidelity_audit.json 이 나온다(양성)
#         ②정규화 줄을 뺀 사본은 실사고 지문('\U')으로 죽고 merge_failed + exit 3 (위반 주입)
#         ③축 파일 하나 파손은 설계대로 흡수(unverifiable 행 + 사유) — 병합은 산다(fanout 설계·C4 검사와 정합)
#         ④축 등록부 파손 = 진짜 병합 실패 → merge_failed + exit 3 + 감사 파일 없음
#         ⑤claude -p 는 한 번도 안 불린다(PATH 앞 감시 shim) · 운영 로그·저널은 1바이트도 안 자란다
# 부작용 없음: wdir·저널·로그 전부 임시 디렉터리(QVEST_RP_JLOG·QVEST_FA_LOG). 운영 원장·요청 파일 불가침.
# 실행: bash 08_Tests/ops/test_rf_fanout_merge_root.sh
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
# ★치환에 역슬래시 문자를 안 쓴다 — 셸·sed·awk·R 이 층마다 다르게 먹는다(test_reinforce_auto.sh 와 같은 사유)
ROOTF="$("$PY" -c "import sys;print(sys.argv[1].replace(chr(92),chr(47)))" "$ROOT")"
ROOTB="$("$PY" -c "import sys;print(sys.argv[1].replace(chr(47),chr(92)))" "$ROOTF")"   # 실사고 형태(역슬래시)
cd "$ROOTF" || exit 1
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

FAN="$ROOTF/02_Infrastructure/ops/rf_fidelity_fanout.sh"
AUDSH="$ROOTF/02_Infrastructure/ops/rf_fidelity_audit.sh"
AXES="$ROOTF/06_Registry/rf_fidelity_axes.json"
OPLOG="$ROOTF/.cache/scheduler_logs/fidelity_fanout_$(date +%Y%m%d).log"
OPJ="$ROOTF/.cache/reinforce_auto_log.jsonl"
fsize(){ "$PY" -c "import os,sys;print(os.path.getsize(sys.argv[1]) if os.path.exists(sys.argv[1]) else -1)" "$1"; }
OPLOG0=$(fsize "$OPLOG"); OPJ0=$(fsize "$OPJ")

TMP="$ROOTF/.cache/_test_fa_merge_root_$$"
rm -rf "$TMP"; mkdir -p "$TMP/bin"
trap 'rm -rf "$TMP"' EXIT
# claude 감시 shim — 불리면 표식을 남긴다(병합 단계만 돌아야 한다)
printf '#!/usr/bin/env bash\ntouch "%s/claude_was_called"\nexit 0\n' "$TMP" > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

mk_wdir(){  # $1 = wdir · 축 파일 전부 faithful (축 id 는 등록부에서 — 셸에 축을 박지 않는다)
  local w="$1"; rm -rf "$w"; mkdir -p "$w/art"
  printf '%s\n' 'FACTORS <- data.table::data.table(Date = as.Date("2020-01-31"), Ticker = "A", Score = 1)' > "$w/engine.R"
  "$PY" - "$AXES" "$w" <<'PYAX'
import io, json, sys
axes = json.load(io.open(sys.argv[1], encoding="utf-8"))["axes"]
for ax in axes:
    k = ax["key"]
    rec = {"axis": k, "verdict": "faithful", "undeclared_changes": [], "signal_mismatch": [],
           "evidence": "3절 대조 완료(%s)" % k, "confidence": "high", "checked": "전 항목", "note": ""}
    io.open("%s/fidelity_axis_%s.json" % (sys.argv[2], k), "w", encoding="utf-8", newline="").write(json.dumps(rec, ensure_ascii=False))
print(len(axes))
PYAX
}
run_merge(){  # $1 = 스크립트 · $2 = wdir · $3 = 저널 · $4 = 로그 · [$5 = 축 등록부 대체]
  #   QVEST_RF_ROOT 는 비우고 QM_ROOT 를 **역슬래시**로 준다 — 실사고의 기동 형태 그대로.
  if [ -n "${5:-}" ]; then
    env -u QVEST_RF_ROOT QM_ROOT="$ROOTB" QVEST_RP_JLOG="$3" QVEST_FA_LOG="$4" QVEST_FA_MERGE_ONLY=1 QVEST_RF_AXES="$5" \
      bash "$1" "$2" "$2/art" "https://arxiv.org/abs/0000.00000" "TEST_MERGE_ROOT" >/dev/null 2>&1
  else
    env -u QVEST_RF_ROOT QM_ROOT="$ROOTB" QVEST_RP_JLOG="$3" QVEST_FA_LOG="$4" QVEST_FA_MERGE_ONLY=1 \
      bash "$1" "$2" "$2/art" "https://arxiv.org/abs/0000.00000" "TEST_MERGE_ROOT" >/dev/null 2>&1
  fi
}
has_evt(){ grep -qE "\"event\": ?\"$2\"" "$1" 2>/dev/null; }   # 셸 jl 은 ": " · R jsonlite 는 ":" — 둘 다 잡는다

echo "=== 0. 픽스처 — 실사고 형태인가 ==="
HB=$("$PY" -c "import sys;print(1 if chr(92) in sys.argv[1] else 0)" "$ROOTB")
[ "$HB" = "1" ] && ok "0a QM_ROOT 픽스처에 역슬래시가 있다 ($ROOTB)" || ng "0a 픽스처가 역슬래시 형태가 아니다" "$ROOTB"
[ -s "$AXES" ] && ok "0b 축 등록부 존재" || ng "0b 축 등록부 부재" "$AXES"

echo "=== 1. 양성 — 역슬래시 QM_ROOT 로 병합만 돌려 감사 파일이 나온다 ==="
W1="$TMP/w1"; J1="$TMP/j1.jsonl"; L1="$TMP/l1.log"
NAX=$(mk_wdir "$W1")
run_merge "$FAN" "$W1" "$J1" "$L1"; RC=$?
[ "$RC" = "0" ] && ok "1a 레인 exit 0" || ng "1a 레인 exit≠0" "rc=$RC · $(tail -2 "$L1" 2>/dev/null | tr '\n' ' ')"
[ -s "$W1/fidelity_audit.json" ] && ok "1b fidelity_audit.json 생성" || ng "1b 감사 파일 없음" "$(tail -3 "$L1" 2>/dev/null | tr '\n' ' ')"
V=$("$PY" -c "import io,json,sys;print(json.load(io.open(sys.argv[1],encoding='utf-8')).get('verdict'))" "$W1/fidelity_audit.json" 2>/dev/null)
[ "$V" = "faithful" ] && ok "1c verdict=faithful (축 $NAX 전부 faithful)" || ng "1c verdict" "$V"
has_evt "$J1" merge_done && ok "1d 저널 merge_done" || ng "1d merge_done 없음"
has_evt "$J1" audit_verified && ok "1e 저널 audit_verified — 스키마 검증이 병합 뒤에 돈다(단일 레인과 같게)" || ng "1e audit_verified 없음"
! has_evt "$J1" merge_failed && ok "1f merge_failed 없음" || ng "1f 정상 병합에 merge_failed"
! grep -q "used without hex digits" "$L1" 2>/dev/null && ok "1g 로그에 실사고 지문 없음" || ng "1g 실사고 지문('\\U')이 남아 있다"

echo "=== 2. 위반 주입 — 정규화 줄을 뺀 사본은 실사고 그대로 죽는다 (merge_failed + exit 3) ==="
NONORM="$TMP/fanout_nonorm.sh"
NREM=$("$PY" - "$FAN" "$NONORM" <<'PYMUT'
import io, sys
src = io.open(sys.argv[1], "rb").read().decode("utf-8").split("\n")
keep = [l for l in src if not l.startswith('ROOT="${ROOT//')]
io.open(sys.argv[2], "wb").write("\n".join(keep).encode("utf-8"))
print(len(src) - len(keep))
PYMUT
)
[ "$NREM" = "1" ] && ok "2a 정규화 줄 1개 제거(변이가 살아 있다)" || ng "2a 정규화 줄 제거 수" "$NREM (0 이면 죽은 변이 — 정규화 줄 자체가 없다)"
W2="$TMP/w2"; J2="$TMP/j2.jsonl"; L2="$TMP/l2.log"
mk_wdir "$W2" >/dev/null
run_merge "$NONORM" "$W2" "$J2" "$L2"; RC=$?
[ "$RC" = "3" ] && ok "2b 레인 exit 3" || ng "2b 레인 exit" "rc=$RC (구판은 0 이었다)"
[ ! -e "$W2/fidelity_audit.json" ] && ok "2c 감사 파일 없음" || ng "2c 역슬래시 ROOT 인데 감사 파일이 나왔다"
has_evt "$J2" merge_failed && ok "2d 저널 merge_failed" || ng "2d merge_failed 없음"
! has_evt "$J2" merge_done && ok "2e merge_done 없음(실패를 성공으로 안 적는다)" || ng "2e 실패인데 merge_done"
grep -q "used without hex digits" "$L2" 2>/dev/null && ok "2f 실사고 지문 재현('\\U' used without hex digits)" || ng "2f 지문 불일치" "$(tail -2 "$L2" 2>/dev/null | tr '\n' ' ')"

echo "=== 3. 축 파일 하나 파손 — 설계대로 흡수(병합은 산다 · 안 본 축이 남는다) ==="
W3="$TMP/w3"; J3="$TMP/j3.jsonl"; L3="$TMP/l3.log"
mk_wdir "$W3" >/dev/null
K1=$("$PY" -c "import io,json,sys;a=json.load(io.open(sys.argv[1],encoding='utf-8'))['axes'];print([x['key'] for x in a if x.get('required')][0])" "$AXES")
printf '{not json' > "$W3/fidelity_axis_$K1.json"
run_merge "$FAN" "$W3" "$J3" "$L3"; RC=$?
[ "$RC" = "0" ] && ok "3a 레인 exit 0 — 한 축 파손은 병합 실패가 아니다(fanout 설계)" || ng "3a 레인 exit" "rc=$RC"
R3=$("$PY" -c "
import io,json,sys
try: a=json.load(io.open(sys.argv[1],encoding='utf-8'))
except Exception as e: print('NOFILE'); raise SystemExit
row=[r for r in a.get('axis_verdicts',[]) if r.get('axis')==sys.argv[2]]
rs=(row[0].get('reason') or '') if row else ''
print('OK' if (a.get('verdict')=='unverifiable' and '파손' in rs) else 'verdict=%s reason=%s' % (a.get('verdict'), rs))" "$W3/fidelity_audit.json" "$K1" 2>/dev/null)
[ "$R3" = "OK" ] && ok "3b required 축($K1) 파손 → verdict unverifiable + 행 사유 '파손'(안 본 축이 남는다)" || ng "3b 파손 축 처리" "$R3"

echo "=== 4. 축 등록부 파손 — 진짜 병합 실패는 크게 (merge_failed + exit 3 + 감사 파일 없음) ==="
W4="$TMP/w4"; J4="$TMP/j4.jsonl"; L4="$TMP/l4.log"
mk_wdir "$W4" >/dev/null
printf '{broken' > "$TMP/axes_broken.json"
run_merge "$FAN" "$W4" "$J4" "$L4" "$TMP/axes_broken.json"; RC=$?
[ "$RC" = "3" ] && ok "4a 레인 exit 3" || ng "4a 레인 exit" "rc=$RC"
has_evt "$J4" merge_failed && ok "4b 저널 merge_failed" || ng "4b merge_failed 없음"
[ ! -e "$W4/fidelity_audit.json" ] && ok "4c 감사 파일 없음 — verify 의 rf_audit_gate 가 미실행으로 잡는 입력" || ng "4c 파손 등록부인데 감사 파일"
! has_evt "$J4" merge_done && ok "4d merge_done 없음" || ng "4d 실패인데 merge_done"

echo "=== 5. 격리 — claude 미호출 · 운영 로그/저널 불변 · 호출자 전파 배선 ==="
[ ! -e "$TMP/claude_was_called" ] && ok "5a claude -p 미호출(감시 shim 표식 없음)" || ng "5a 병합 단계가 claude 를 불렀다"
OPLOG1=$(fsize "$OPLOG"); OPJ1=$(fsize "$OPJ")
[ "$OPLOG0" = "$OPLOG1" ] && ok "5b 운영 스케줄러 로그 불변(QVEST_FA_LOG 격리)" || ng "5b 운영 로그가 자랐다" "$OPLOG0 → $OPLOG1"
[ "$OPJ0" = "$OPJ1" ] && ok "5c 운영 저널 불변(QVEST_RP_JLOG 격리)" || ng "5c 운영 저널이 자랐다" "$OPJ0 → $OPJ1"
grep -qF 'exec bash "$ROOT/02_Infrastructure/ops/rf_fidelity_fanout.sh"' "$AUDSH" \
  && ok "5d audit.sh 는 exec 로 위임 — fanout 의 exit 3 이 그대로 verify 에 닿는다" || ng "5d audit.sh 위임이 exec 가 아니다"
grep -q '^ROOT="${ROOT//' "$AUDSH" && ok "5e audit.sh 도 슬래시 정규화" || ng "5e audit.sh 정규화 없음"
grep -qF 'jl merge_failed' "$FAN" && grep -qF 'return 3' "$FAN" && ok "5f fanout: merge_failed 저널 + exit 3 배선" || ng "5f 병합 실패 배선 부재"

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"rf_fanout_merge_root","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
