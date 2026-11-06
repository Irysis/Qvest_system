#!/usr/bin/env bash
#==============================================================================
# test_gate_msm_asof.sh — Gate M 공통 관문(02_Infrastructure/ops/gate_msm_asof.sh) 양방향 검증 + 두 러너 배선
#
# 배경 (2026-11-06 · 결정 PIT-C1-MSM-PARAMS 안 A · MSM-ASOF-SWITCH-20261017 D4 B · 적대 검토 #4 · #15 · #16 · #19):
#   구 Gate M 은 수동 full 러너에만 있었고(예약 경로 noLayer4_Monthly_PaperTracking → run_nolayer4_monthly.sh 는 무검사),
#   표식(msm_estimator)만 봐서 밤 MSM 실패로 동결된 국면을 통과시켰다. 이제 공통 관문 한 벌이 표식 + 신선도를 보고,
#   예약 러너 [0b] 와 full 러너가 같은 스크립트를 부른다. 이 검사는 그 관문이 실제로 막는지 · 실제로 배선됐는지를 잰다.
#
# 계약:
#   P  정상 합성 캐시 → rc 0 · 'OK' · SIG_DATE = 벤치 마지막 거래일
#      (합성 휴장 11-30 · AS_OF 뒤 12-01/02 는 제외 → 11-27 — 달력 말일도 Date 라벨도 아님)
#   N  위반 주입 17종 → rc 1 · 'BAD' · **기대 태그만**(다른 태그가 잡으면 실패 — 엉뚱한 검사가 막는 것은 통과가 아니다)
#   A  인자 오류 · R  죽은 실행기(미실행 · 무출력 · rc/줄 불일치) → BAD [args] / [rscript] (성공으로 새지 않는다)
#   E  데이터 루트 해석(인자 > QM_ROOT · 역슬래시 형 · MSYS 형)
#   C  기대 추정기 상수: 관문 = regime_signal.R::MSM_ESTIMATOR_EXPECTED = msm_asof.R::MSMA_ESTIMATOR
#   W  배선(예약 러너: [0] 리프레시 뒤 · [1] 앞 · 삼키지 않음 · exit 23 유일 / full 러너: 공통 관문 · 인라인 판정 제거 ·
#      하위 rc 23 전파) + 검출기 돌연변이
#   M  돌연변이 — 검사 줄 하나를 no-op 로 바꾼 사본에서 그 위반이 OK 로 새는가(= 그 줄이 실제로 막는다).
#      ★사본은 deparse 가 아니라 소스 텍스트 치환으로 만들고, 치환 성사(태그 1→0 · 줄 수 동일 · 내용 다름)를 단정한 뒤 돌린다.
#   X  예약 러너 e2e(모래상자 루트 · 리프레시 스킵) — BAD 면 [1] 전에 exit 23 · 관문을 우회한 러너 사본은 23 이 아니다
#
# ★죽은 계측의 rc 가 기대값과 겹치지 않게: 성공(OK) 판정은 rc 0 ∧ 'OK ' 줄 · BAD 판정은 rc 1 ∧ 'BAD ' 줄 ∧ 기대 태그.
#   죽은 R 은 [rscript] 만 내므로 N 사례를 통과시키지 못한다. 케이스 전에 카나리아(합성 캐시 생성 + 정상 → OK)로
#   계측 생존을 확정하고, 실패하면 결과를 발행하지 않는다(preflight).
# 쓰기: mktemp -d 모래상자만(운영 .cache · 06_Registry · 05 계열 무접촉). 마지막 줄 = JSON 요약(run_all_hooks.sh 계약).
#==============================================================================
set -uo pipefail
TN="gate_msm_asof"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE="$(cd "$HERE/../.." && pwd)"                     # 코드 루트 = 이 시험 파일의 저장소(워크트리 포함)
if command -v cygpath >/dev/null 2>&1; then CODE="$(cygpath -m "$CODE")"; fi
GATE="$CODE/02_Infrastructure/ops/gate_msm_asof.sh"
NL4="$CODE/02_Infrastructure/monitoring/run_nolayer4_monthly.sh"
FULL="$CODE/02_Infrastructure/ops/run_pg2_rebalance_full.sh"
RSIG="$CODE/02_Infrastructure/regime/regime_signal.R"
MSMA="$CODE/02_Infrastructure/regime/msm_asof.R"
RS="${QVEST_RSCRIPT:-$(command -v Rscript 2>/dev/null || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')}"
AS="2026-12-01"                                        # 홀딩월 1일 → sig 월 2026-11
TAGS="marker bench sig_row avail daily read args tmp rscript internal"

PASS=0; FAIL=0; SKIP=0; MK=0; MT=0; SKIPS=""
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
sk(){ echo "  [SKIP] $1 — $2"; SKIP=$((SKIP+1)); SKIPS="${SKIPS:+$SKIPS,}{\"axis\":\"$1\",\"reason\":\"$2\"}"; }
preflight_fail(){
  local r="${1//\\//}"; r="${r//\"/}"                 # JSON 안전(역슬래시 · 따옴표 제거)
  echo "XX 사전 점검 실패: $r — 케이스 결과를 발행하지 않는다(죽은 계측의 0/N 을 검거 실패로 읽지 않도록)"
  echo "{\"test\":\"$TN\",\"pass\":0,\"fail\":1,\"preflight\":\"$r\"}"
  exit 1
}

for f in "$GATE" "$NL4" "$FULL" "$RSIG" "$MSMA"; do [ -f "$f" ] || preflight_fail "파일 부재 $f"; done
SB_MSYS="$(mktemp -d)" || preflight_fail "mktemp -d 실패"
trap 'rm -rf "$SB_MSYS"' EXIT
SB="$SB_MSYS"
if command -v cygpath >/dev/null 2>&1; then SB="$(cygpath -m "$SB_MSYS")"; fi   # 네이티브 슬래시 형(R 인자용)
FX="$SB/fx"; mkdir -p "$SB/mut"

# ── 관문 실행 래퍼 ─────────────────────────────────────────────────────────────
OUT=""; RC=0
rung(){ local g="$1"; shift; OUT="$(bash "$g" "$@" </dev/null 2>"$SB/last.err")"; RC=$?; }   # stdin 차단 — 케이스 heredoc 을 자식이 먹지 않게
has_tag(){ case "$OUT" in *"[$1]"*) return 0 ;; esac; return 1; }
exp_ok(){ # exp_ok <라벨> [반드시 포함할 문자열]
  if [ "$RC" -eq 0 ] && [ "${OUT#OK }" != "$OUT" ] && { [ -z "${2:-}" ] || [[ "$OUT" == *"$2"* ]]; }; then ok "$1"
  else ng "$1 → rc=$RC out=${OUT:0:300}"; fi
}
exp_bad(){ # exp_bad <라벨> <기대 태그 csv> — rc 1 ∧ 'BAD ' ∧ 기대 태그 전부 ∧ 그 밖 태그 없음
  local lab="$1" want=",$2," t miss="" extra=""
  for t in $TAGS; do
    if [[ "$want" == *",$t,"* ]]; then has_tag "$t" || miss="$miss $t"
    else has_tag "$t" && extra="$extra $t"; fi
  done
  if [ "$RC" -eq 1 ] && [ "${OUT#BAD }" != "$OUT" ] && [ -z "$miss" ] && [ -z "$extra" ]; then ok "$lab"
  else ng "$lab → rc=$RC 누락[${miss# }] 여분[${extra# }] out=${OUT:0:300}"; fi
}

# ── 사전 점검 ①: 관문 문법 · 기대 추정기 상수(합성 캐시가 관문과 같은 값을 쓰도록) ──────────
bash -n "$GATE" 2>"$SB/bashn.err" || preflight_fail "관문 문법 오류 $(head -c 160 "$SB/bashn.err" | tr -d '\r\n')"
EXP_G="$(grep -E '^EXPECT <- "' "$GATE" | head -n 1 | sed -E 's/^EXPECT <- "([^"]+)".*/\1/')"
EXP_R="$(grep -E '^MSM_ESTIMATOR_EXPECTED <- "' "$RSIG" | head -n 1 | sed -E 's/^MSM_ESTIMATOR_EXPECTED <- "([^"]+)".*/\1/')"
EXP_M="$(grep -E '^MSMA_ESTIMATOR <- "' "$MSMA" | head -n 1 | sed -E 's/^MSMA_ESTIMATOR <- "([^"]+)".*/\1/')"
[ -n "$EXP_G" ] || preflight_fail "관문 EXPECT 상수 판독 실패"
EST="$EXP_G"

# ── 합성 .cache 빌더(시나리오별 루트 = $FX/<시나리오>) — R 한 번에 전부 ───────────────
cat > "$SB/build_fx.R" <<'REOF'
## 합성 캐시 — 인자: BASE EST 시나리오... · 벤치/월간/일간 parquet(data.table + 속성 → arrow 'r' 메타로 왕복)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
a <- commandArgs(trailingOnly = TRUE); base <- a[1]; EST <- a[2]; scs <- a[-(1:2)]
KEY <- "c11_avail:TEST.b0:00000000"
days <- seq(as.Date("2026-08-03"), as.Date("2026-12-02"), by = "day")
days <- days[!(format(days, "%u") %in% c("6", "7"))]
days <- days[days != as.Date("2026-11-30")]            # 합성 휴장 — sig 월 마지막 거래일 = 11-27(금)
yms <- c("2026-08", "2026-09", "2026-10", "2026-11")
month_end <- function(y) seq(as.Date(paste0(y, "-01")), by = "month", length.out = 2L)[2L] - 1L
mk_month <- function(upto) {
  dd <- days[days <= upto]
  ys <- yms[yms %in% format(dd, "%Y-%m")]
  data.table(Date = do.call(c, lapply(ys, month_end)), YM = ys,
             MSM_Crisis_Prob = 0.1, Regime_Score = 30, Category = "NEUTRAL", Cash_Pct = 0,
             avail_date = do.call(c, lapply(ys, function(y) max(dd[format(dd, "%Y-%m") == y]))),
             c11_regime_key = KEY, msm_estimator = EST)
}
put <- function(dt, path, attrs) { for (n in names(attrs)) setattr(dt, n, attrs[[n]]); write_parquet(dt, path); invisible(TRUE) }
for (sc in scs) {
  cache <- file.path(base, sc, ".cache"); dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  if (sc == "empty") next
  b_upto <- m_upto <- d_upto <- as.Date("2026-12-02")
  if (sc == "bench_stale") b_upto <- as.Date("2026-10-30")
  if (sc == "all_stale_oct") b_upto <- m_upto <- d_upto <- as.Date("2026-10-30")
  if (sc == "daily_stale") d_upto <- as.Date("2026-11-19")
  bd <- days[days <= b_upto]
  write_parquet(data.table(Date = bd, BM_Close = 100 + seq_along(bd), BM_Ret = 0.001, BM_Src = "TEST"),
                file.path(cache, "benchmark.parquet"))
  m <- mk_month(m_upto)
  m_attrs <- list(c11_avail_regime_key = KEY, msm_estimator = EST)
  if (sc %in% c("no_marker", "attr_only")) m[, msm_estimator := NULL]
  if (sc %in% c("no_marker", "col_only")) m_attrs$msm_estimator <- NULL
  if (sc == "mixed") m[YM == "2026-08", msm_estimator := "legacy"]
  if (sc == "col_na") m[YM == "2026-09", msm_estimator := NA_character_]
  if (sc == "wrong_value") { m[, msm_estimator := paste0(EST, ":WRONG")]; m_attrs$msm_estimator <- paste0(EST, ":WRONG") }
  if (sc == "no_sig_row") m <- m[YM != "2026-11"]
  if (sc == "dup_sig_row") m <- rbind(m, m[YM == "2026-11"])
  if (sc == "avail_stale") m[YM == "2026-11", avail_date := as.Date("2026-11-19")]
  if (sc == "avail_ahead") m[YM == "2026-11", avail_date := as.Date("2026-11-30")]
  if (sc == "avail_not_date") m[, avail_date := as.character(avail_date)]
  mp <- file.path(cache, "unified_regime_signal.parquet")
  if (sc == "monthly_corrupt") writeBin(charToRaw("PAR1 this is not a parquet file"), mp) else put(m, mp, m_attrs)
  if (sc != "daily_absent") {
    dd <- days[days <= d_upto]
    dl <- data.table(Date = dd, YM = format(dd, "%Y-%m"), Category = "NEUTRAL", Cash_Pct = 0,
                     avail_date = dd, c11_regime_key = KEY, msm_estimator = EST)
    put(dl, file.path(cache, "unified_regime_signal_daily.parquet"), list(c11_avail_regime_key = KEY, msm_estimator = EST))
  }
}
cat("FIXTURES_OK", length(scs), "\n")
REOF
SCEN="ok no_marker col_only attr_only mixed col_na wrong_value no_sig_row dup_sig_row avail_stale avail_ahead avail_not_date daily_stale daily_absent bench_stale all_stale_oct monthly_corrupt empty"
# shellcheck disable=SC2086
_fx="$("$RS" --no-save "$SB/build_fx.R" "$FX" "$EST" $SCEN 2>"$SB/fx.err")"; _fxrc=$?
case "$_fx" in *FIXTURES_OK*) : ;; *) preflight_fail "합성 캐시 생성 실패(rc=$_fxrc · 실행기 $RS · R/arrow/data.table 확인) $(tail -n 1 "$SB/fx.err" | tr -d '\r\n"' | tail -c 120)" ;; esac
[ -f "$FX/ok/.cache/unified_regime_signal.parquet" ] || preflight_fail "합성 캐시 파일 부재"

# ── 사전 점검 ③ 카나리아: 정상 합성 캐시 → OK (계측 생존 확정 — 여기서 죽으면 케이스를 발행하지 않는다) ──
rung "$GATE" "$AS" "$FX/ok"
if [ "$RC" -ne 0 ] || [ "${OUT#OK }" = "$OUT" ]; then
  preflight_fail "카나리아 — 정상 합성 캐시에서 OK 가 안 나옴 rc=$RC $(printf '%s' "${OUT:0:160}" | tr -d '"')"
fi
P_OUT="$OUT"; P_RC="$RC"

# ── S: 문법 · 돌연변이 표적 태그 ─────────────────────────────────────────────
echo "=== S 문법 · 표적 태그 ==="
for f in "$GATE" "$NL4" "$FULL"; do
  if bash -n "$f" 2>"$SB/bashn.err"; then ok "S bash -n ${f##*/}"; else ng "S bash -n ${f##*/} → $(head -c 200 "$SB/bashn.err")"; fi
done
_tagbad=""
for t in @CHK_MARKER_COL @CHK_MARKER_ATTR @CHK_SIGROW @CHK_AVAIL @CHK_DAILY @CHK_WRAP_OK; do
  [ "$(grep -cF -- "$t" "$GATE")" = "1" ] || _tagbad="$_tagbad $t"
done
if [ -z "$_tagbad" ]; then ok "S 돌연변이 표적 태그 6종이 관문에 각 1회"; else ng "S 표적 태그 개수≠1:$_tagbad"; fi

# ── C: 기대 추정기 상수 3곳 일치 ─────────────────────────────────────────────
echo "=== C 기대 추정기 상수 ==="
if [ "$EXP_G" = "$EXP_R" ] && [ "$EXP_G" = "$EXP_M" ]; then ok "C 관문=$EXP_G = regime_signal.R = msm_asof.R"
else ng "C 상수 불일치 관문='$EXP_G' regime_signal.R='$EXP_R' msm_asof.R='$EXP_M' (어긋나면 관문은 막는 쪽으로 실패한다)"; fi

echo "=== P 정상(카나리아) ==="
OUT="$P_OUT"; RC="$P_RC"
exp_ok "P 정상 → OK · SIG_DATE=11-27(벤치 마지막 거래일 · 휴장 11-30 · AS_OF 뒤 제외)" "sig_date=2026-11-27"
case "$OUT" in *"sig_avail=2026-11-27"*"daily_max=2026-12-02"*) ok "P 진단 필드(sig_avail · daily_max) 실값" ;;
  *) ng "P 진단 필드 → ${OUT:0:300}" ;; esac

# ── N: 위반 주입 — 기대 태그만 ───────────────────────────────────────────────
echo "=== N 위반 주입 ==="
declare -A ORIG_RC
while read -r sc want lab; do
  [ -n "$sc" ] || continue
  rung "$GATE" "$AS" "$FX/$sc"; ORIG_RC[$sc]=$RC
  exp_bad "N $sc → BAD [$want] ($lab)" "$want"
done <<'CASES'
no_marker marker 표식 없음(현 라이브 구판 상태)
col_only marker 열만 있고 속성 없음
attr_only marker 속성만 있고 열 없음
mixed marker 열 혼합(legacy+asof)
col_na marker 열 일부 NA
wrong_value marker 다른 추정기 값
no_sig_row sig_row sig 월 행 없음(국면 동결)
dup_sig_row sig_row sig 월 행 중복
avail_stale avail sig 월 avail_date 11-19(부분 월 빌드)
avail_ahead avail avail_date 11-30 ≠ 벤치 11-27
avail_not_date avail avail_date 가 Date 형 아님
daily_stale daily 일간 max 11-19 < SIG_DATE
daily_absent read 일간 파일 없음
bench_stale bench 벤치가 sig 월에 닿지 않음
all_stale_oct bench,sig_row 벤치·월간·일간 모두 10월에 멈춤
monthly_corrupt read 월간 파일 파손
empty read 캐시 3종 전부 없음
CASES

# ── A: 인자 오류 ─────────────────────────────────────────────────────────────
echo "=== A 인자 ==="
rung "$GATE" "2026-12-15" "$FX/ok";  exp_bad "A AS_OF 1일 아님(2026-12-15) → BAD [args]" "args"
rung "$GATE" "2026-13-01" "$FX/ok";  exp_bad "A AS_OF 무효 달(2026-13-01 · R 판정) → BAD [args]" "args"
rung "$GATE" "2026-12-01x" "$FX/ok"; exp_bad "A AS_OF 꼬리 문자(2026-12-01x) → BAD [args]" "args"
rung "$GATE" "" "$FX/ok";            exp_bad "A AS_OF 빈 값 → BAD [args]" "args"
rung "$GATE" "$AS" "$SB/no_such_root"; exp_bad "A 데이터 루트 없음 → BAD [args]" "args"

# ── R: 죽은 실행기 — 성공으로 새지 않는다 ───────────────────────────────────────
echo "=== R 죽은 실행기 ==="
FRB="$SB_MSYS/fakebin_r"; mkdir -p "$FRB"
mkfake(){ printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FRB/$1"; chmod +x "$FRB/$1"; }
mkfake r_silent_rc0 'exit 0'
mkfake r_ok_rc1 'echo "OK fake as_of=x"; exit 1'
mkfake r_bad_rc0 'echo "BAD [marker] fake"; exit 0'
QVEST_RSCRIPT="$SB/no_such_dir/Rscript.exe" rung "$GATE" "$AS" "$FX/ok"; exp_bad "R 실행기 없음 → BAD [rscript]" "rscript"
QVEST_RSCRIPT="$FRB/r_silent_rc0" rung "$GATE" "$AS" "$FX/ok"; exp_bad "R 무출력 rc 0 → BAD [rscript]" "rscript"
QVEST_RSCRIPT="$FRB/r_ok_rc1" rung "$GATE" "$AS" "$FX/ok";     exp_bad "R 'OK' 줄 + rc 1(불일치) → BAD [rscript]" "rscript"
QVEST_RSCRIPT="$FRB/r_bad_rc0" rung "$GATE" "$AS" "$FX/ok";    exp_bad "R 'BAD' 줄 + rc 0(불일치) → BAD [rscript]" "rscript"

# ── E: 데이터 루트 해석 ────────────────────────────────────────────────────────
echo "=== E 루트 해석 ==="
QM_ROOT="$FX/ok" rung "$GATE" "$AS";                       exp_ok "E 인자 없음 · QM_ROOT=정상 → OK"
QM_ROOT="$FX/no_marker" rung "$GATE" "$AS";                exp_bad "E 인자 없음 · QM_ROOT=표식 없음 → BAD(QM_ROOT 를 실제로 읽는다)" "marker"
QM_ROOT="$FX/no_marker" rung "$GATE" "$AS" "$FX/ok";       exp_ok "E 인자(정상) > QM_ROOT(표식 없음) → OK"
rung "$GATE" "$AS" "${FX//\//\\}\\ok";                     exp_ok "E 역슬래시 형 루트 → OK(슬래시 정규화)"
rung "$GATE" "$AS" "$SB_MSYS/fx/ok";                       exp_ok "E MSYS 형 루트(/tmp/…) → OK"

# ── W: 배선(정적 · 주석 제외 줄) ───────────────────────────────────────────────
echo "=== W 러너 배선 ==="
cl(){ grep -nvE '^[[:space:]]*#' "$1"; }                     # "줄번호:내용" — 주석은 구판 패턴을 인용하므로 뺀다
firstln(){ cl "$1" | grep -F -- "$2" | head -n 1 | cut -d: -f1; }
w1(){ # w1 <러너> — 관문 호출이 [1](run_pg2_forward) 앞에 있는가(출력 = 판정 문구).
      #   구 조건 '[0] 리프레시 뒤'는 2026-11-06 러너 리프레시 제거(도훈 지시 "daily_refresh 돌리는 프로세스는 빼버려")로
      #   없어졌다 — 리프레시 부재 자체는 test_ae_monthly_plumbing.py WIRE-3 이 잰다.
  local g f; g="$(firstln "$1" "gate_msm_asof.sh")"; f="$(firstln "$1" "run_pg2_forward_noLayer4.sh")"
  if [ -z "$g" ]; then echo "ABSENT"; return 1; fi
  if [ -n "$f" ] && [ "$g" -lt "$f" ]; then echo "ORDER_OK gate=$g forward=$f"; return 0; fi
  echo "ORDER_BAD gate=$g forward=${f:-?}"; return 1
}
_w="$(w1 "$NL4")" && ok "W1 예약 러너: 관문이 [1] 앞 ($_w)" || ng "W1 예약 러너 관문 위치 → $_w"
_g="$(firstln "$NL4" "gate_msm_asof.sh")"
if cl "$NL4" | grep -F "gate_msm_asof.sh" | grep -qE '\|\|[[:space:]]*(echo|say|true|:)'; then ng "W2 예약 러너: 관문 실패를 || 로 삼킨다"
elif [ -n "$_g" ] && awk -v s="$_g" 'NR>s && NR<=s+8 && /^[[:space:]]*exit 23([[:space:]]|$)/{f=1} END{exit !f}' "$NL4"; then ok "W2 예약 러너: 관문 실패 = exit 23(삼키지 않음)"
else ng "W2 예약 러너: 관문 뒤 8줄 안에 exit 23 없음"; fi
_n23="$(cl "$NL4" | grep -cE '(^|[^0-9])exit 23([^0-9]|$)')"
[ "$_n23" = "1" ] && ok "W3 예약 러너: exit 23 은 Gate M 하나(기존 12~22 와 겹치지 않음)" || ng "W3 예약 러너: exit 23 ${_n23}건"
_gf="$(firstln "$FULL" "gate_msm_asof.sh")"; _sf="$(firstln "$FULL" 'bash "02_Infrastructure/monitoring/run_nolayer4_monthly.sh"')"
if [ -n "$_gf" ] && [ -n "$_sf" ] && [ "$_gf" -lt "$_sf" ] \
   && awk -v s="$_gf" 'NR>s && NR<=s+6 && /abort "GateM-msm"/ && / 23$/{f=1} END{exit !f}' "$FULL"; then
  ok "W4 full 러너: 공통 관문(조기 경보)이 [2] 앞 · 실패 = abort 23 (gate=$_gf sub=$_sf)"
else ng "W4 full 러너: 공통 관문 호출/abort 23 배선 이상 (gate=${_gf:-없음} sub=${_sf:-없음})"; fi
_inl="$(cl "$FULL" | grep -cE 'msm_estimator|qm_gatem_')"
[ "$_inl" = "0" ] && ok "W5 full 러너: 인라인 MSM 판정 제거(판정 정본 한 벌)" || ng "W5 full 러너: 인라인 판정 잔존 ${_inl}줄"
_nx="$(cl "$FULL" | awk -F: -v s="${_sf:-999999}" '$1>s' | head -n 1)"
if [ -n "$_sf" ] && [[ "$_nx" == *'_NL4_RC=$?'* ]] \
   && cl "$FULL" | awk -F: -v s="$_sf" '$1>s' | grep -qF '"$_NL4_RC" -eq 23' \
   && cl "$FULL" | awk -F: -v s="$_sf" '$1>s' | grep -qE 'abort "GateM-msm-sub".* 23$'; then
  ok "W6 full 러너: 하위 러너 rc 를 받아 23 이면 중단(이전 홀딩 CSV 로 Gate C 오통과 방지)"
else ng "W6 full 러너: 하위 rc 23 전파 없음 (다음 줄=${_nx:-없음})"; fi
# WM 검출기 돌연변이 — 관문 호출 줄을 지운 러너 사본에서 W1 이 ABSENT 를 내는가(검출기 생존)
MT=$((MT+1))
grep -vF "gate_msm_asof.sh" "$NL4" > "$SB/mut/nl4_nogate.sh"
_wm="$(w1 "$SB/mut/nl4_nogate.sh")"
if [ "$(grep -cF "gate_msm_asof.sh" "$SB/mut/nl4_nogate.sh")" = "0" ] && [ "$_wm" = "ABSENT" ] && w1 "$NL4" >/dev/null; then
  MK=$((MK+1)); ok "WM 검출기: 관문 줄 제거 사본 → ABSENT · 원본 → 위치 OK"
else ng "WM 검출기 사망: 제거 사본 판정=$_wm"; fi

# ── M: 돌연변이 — 검사 줄 하나를 no-op 로 바꾼 사본에서 그 위반이 OK 로 새는가 ─────────
echo "=== M 돌연변이 ==="
mutate(){ # mutate <src> <dst> <태그> <대체 줄> — 태그 줄 1개 치환 + 성사 단정(1→0 · 줄 수 동일 · 내용 다름 · 대체 줄 존재)
  local src="$1" dst="$2" tag="$3" rep="$4" n0 n1
  n0="$(grep -cF -- "$tag" "$src")"; [ "$n0" = "1" ] || { echo "    mutate: 원본 $tag ${n0}건(≠1)"; return 1; }
  T="$tag" REP="$rep" awk 'index($0, ENVIRON["T"]) { print ENVIRON["REP"]; next } { print }' "$src" > "$dst" || return 1
  n1="$(grep -cF -- "$tag" "$dst")"; [ "$n1" = "0" ] || { echo "    mutate: 사본에 $tag ${n1}건 잔존"; return 1; }
  [ "$(wc -l < "$src")" = "$(wc -l < "$dst")" ] || { echo "    mutate: 줄 수 변화"; return 1; }
  ! cmp -s "$src" "$dst" || { echo "    mutate: 사본 = 원본"; return 1; }
  grep -qF -- "MUTANT" "$dst" || { echo "    mutate: 대체 줄 부재"; return 1; }
  bash -n "$dst" || { echo "    mutate: 사본 문법 오류"; return 1; }
  return 0
}
mut(){ # mut <id> <태그> <시나리오> — R 검사 줄 → no-op
  local id="$1" tag="$2" sc="$3" dst="$SB/mut/gate_$1.sh"; MT=$((MT+1))
  if ! mutate "$GATE" "$dst" "$tag" "invisible(NULL)   # MUTANT-REMOVED"; then ng "$id 돌연변이 치환 실패($tag) — 검사 불능"; return; fi
  rung "$dst" "$AS" "$FX/$sc"
  if [ "${ORIG_RC[$sc]:-x}" = "1" ] && [ "$RC" -eq 0 ] && [ "${OUT#OK }" != "$OUT" ]; then
    MK=$((MK+1)); ok "$id 검거: $tag 줄을 지운 사본에서 '$sc' 가 OK 로 샌다(원본 BAD) — 그 줄이 실제로 막는다"
  else ng "$id 생존: $tag 제거 사본 rc=$RC (원본 rc=${ORIG_RC[$sc]:-?}) out=${OUT:0:200}"; fi
}
mut M1 "@CHK_AVAIL" avail_stale          # 신선도 ① sig 월 avail_date == SIG_DATE
mut M2 "@CHK_DAILY" daily_stale          # 신선도 ② 일간 max ≥ SIG_DATE
mut M3 "@CHK_MARKER_ATTR" col_only       # 표식 — 파일 속성
mut M4 "@CHK_MARKER_COL" attr_only       # 표식 — 행 열
mut M5 "@CHK_SIGROW" no_sig_row          # sig 월 행 존재
# M6 래퍼 — 성공 조건에서 'R rc 0' 을 뺀 사본: 'OK' 를 찍고 rc 1 로 죽는 실행기가 OK 로 새는가
MT=$((MT+1))
if mutate "$GATE" "$SB/mut/gate_M6.sh" "@CHK_WRAP_OK" 'if [ "${LINE#OK }" != "$LINE" ]; then echo "$LINE"; exit 0; fi   # MUTANT-WRAP'; then
  QVEST_RSCRIPT="$FRB/r_ok_rc1" rung "$SB/mut/gate_M6.sh" "$AS" "$FX/ok"
  if [ "$RC" -eq 0 ] && [ "${OUT#OK }" != "$OUT" ]; then MK=$((MK+1)); ok "M6 검거: rc 조건을 뺀 래퍼에서 죽은 실행기가 OK 로 샌다(원본 = R3 [rscript])"
  else ng "M6 생존: rc 조건 제거 사본 rc=$RC out=${OUT:0:200}"; fi
else ng "M6 돌연변이 치환 실패 — 검사 불능"; fi

# ── X: 예약 러너 e2e(모래상자) ────────────────────────────────────────────────
#   안전망: ① (구 PG2_REFRESH_DONE=1 리프레시 스킵 — 2026-11-06 러너 리프레시 제거로 무의미 · 무해해 남김) ② 가짜 taskkill 을 PATH 맨 앞에(command -v 로 확인 — 아니면 SKIP)
#   ③ QM_ROOT = 모래상자 — 관문이 못 막으면 [1] 이하가 모래상자 안에서 실패할 뿐 운영 자료에 닿지 않는다.
echo "=== X 예약 러너 e2e ==="
FAKEBIN="$SB_MSYS/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit 0\n' "$SB_MSYS/taskkill_called" > "$FAKEBIN/taskkill"; chmod +x "$FAKEBIN/taskkill"
_tk="$(export PATH="$FAKEBIN:$PATH"; hash -r; command -v taskkill)"
XR="$SB/xroot"; XRC=0; XLOG=""
xsetup(){ # 실행마다 새 루트 + taskkill 호출 표식 초기화(앞 실행의 표식이 다음 판정에 새지 않게 — 메타 시험에서 실측된 누수)
  rm -rf "$XR"; rm -f "$SB_MSYS/taskkill_called"
  mkdir -p "$XR/02_Infrastructure/ops" && cp -r "$FX/$1/.cache" "$XR/" && cp "$GATE" "$XR/02_Infrastructure/ops/gate_msm_asof.sh" && cmp -s "$GATE" "$XR/02_Infrastructure/ops/gate_msm_asof.sh"; }
xrun(){ ( export PATH="$FAKEBIN:$PATH" QM_ROOT="$XR" PG2_AS_OF="$AS" PG2_REFRESH_DONE=1; hash -r; timeout 240 bash "$1" ) > "$SB/xrun.out" 2>&1
        XRC=$?; XLOG="$(cat "$XR/.cache/nolayer4_track_logs/"track_*.log 2>/dev/null)"; }
xstopped(){ # 러너가 [0b] 에서 23 으로 멈췄고 [1] 이하가 돌지 않았나
  [ "$XRC" -eq 23 ] && [[ "$XLOG" == *"[0b] Gate M: BAD"* ]] && [[ "$XLOG" == *"XX [0b]"* ]] \
    && [[ "$XLOG" != *"[1a]"* ]] && [[ "$XLOG" != *"run_pg2_forward_noLayer4"* ]] && [ ! -e "$SB_MSYS/taskkill_called" ]
}
if [ "$_tk" != "$FAKEBIN/taskkill" ]; then
  sk "X_e2e" "가짜 taskkill 이 PATH 에서 먼저 잡히지 않음(command -v=$_tk) — 실 러너 실행 생략"
  sk "X_e2e" "같은 사유"; sk "X_e2e_mutant" "같은 사유"
else
  for xs in "no_marker:marker" "avail_stale:avail"; do
    sc="${xs%%:*}"; tg="${xs##*:}"
    if ! xsetup "$sc"; then ng "X $sc 모래상자 준비 실패"; continue; fi
    xrun "$NL4"
    _gl="$(printf '%s\n' "$XLOG" | grep -F "[0b] Gate M:" | head -n 1)"   # 태그는 관문 판정 줄에서만 본다(안내 줄은 태그 이름을 늘 담는다)
    if xstopped && [[ "$_gl" == *"[$tg]"* ]]; then ok "X 예약 러너($sc): [0b] Gate M BAD [$tg] → exit 23 · [1] 미실행 · taskkill 미호출"
    else ng "X 예약 러너($sc): rc=$XRC [1]실행=$([[ "$XLOG" == *"[1a]"* ]] && echo y || echo n) log=$(printf '%s' "$XLOG" | tr '\n' ' ' | head -c 300)"; fi
  done
  # X 돌연변이 — 관문 호출을 'OK' 고정으로 바꾼(우회) 러너 사본은 23 으로 멈추지 않아야 한다(= e2e 판정이 배선을 본다).
  #   사본은 kill_stray 의 taskkill 도 true 로 무력화한다(치환 성사 단정 — 사본에 taskkill 0건).
  MT=$((MT+1))
  XM="$SB/mut/run_nolayer4_bypass.sh"
  if mutate "$NL4" "$XM.tmp" '_GM="$(bash "$QM_ROOT/02_Infrastructure/ops/gate_msm_asof.sh"' '_GM="OK mutant-bypass"   # MUTANT-BYPASS'; then
    sed 's#taskkill //F //IM Rscript\.exe#true#g' "$XM.tmp" > "$XM"
    if [ "$(grep -c taskkill "$XM")" = "0" ] && [ "$(grep -c taskkill "$NL4")" -ge 1 ] && bash -n "$XM" && xsetup no_marker; then
      xrun "$XM"
      if [ "$XRC" -ne 23 ] && [[ "$XLOG" == *"[0b] Gate M: OK mutant-bypass"* ]] && [[ "$XLOG" != *"XX [0b]"* ]] && [ ! -e "$SB_MSYS/taskkill_called" ]; then
        MK=$((MK+1)); ok "XM 검거: 관문 우회 사본은 표식 없는 캐시로 [0b] 를 지나 rc=$XRC(≠23) — e2e 판정이 배선을 실제로 본다"
      else ng "XM 생존/이상: 우회 사본 rc=$XRC log=$(printf '%s' "$XLOG" | tr '\n' ' ' | head -c 300)"; fi
    else ng "XM 사본 준비 실패(taskkill 무력화 · 문법 · 모래상자)"; fi
  else ng "XM 돌연변이 치환 실패 — 검사 불능"; fi
fi

echo "결과: PASS=$PASS FAIL=$FAIL SKIP=$SKIP · 돌연변이 검거 $MK/$MT"
echo "{\"test\":\"$TN\",\"pass\":$PASS,\"fail\":$FAIL,\"skipped\":$SKIP,\"total\":$((PASS+FAIL)),\"mut_killed\":$MK,\"mut_total\":$MT,\"skips\":[${SKIPS}]}"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
