#!/usr/bin/env bash
#==============================================================================
# gate_msm_asof.sh — Gate M 공통 관문: BOOK 월간 리밸이 읽는 통합 국면 신호가 as-of MSM 판이고 sig 월까지 전진했나
#   (2026-11-06 · 결정 PIT-C1-MSM-PARAMS 안 A · MSM-ASOF-SWITCH-20261017 D4 B · 적대 검토 #4 · #15 · #16 · #19)
#
# 왜: 동결 BOOK 엔진(factor_engine.R · m4)은 손대지 않는다(D4 B). 대신 엔진이 읽는 입력
#   .cache/unified_regime_signal.parquet 를 소비 직전에 본다.
#   ① 표식 — 구판 MSM 은 1990~2026-01 전 표본 MLE 모수(PIT C1)였다. 원장 재발행이 실패하거나 --restore 로
#      되돌아가 라이브가 구판으로 남으면 m4 의 Cash_Pct · MSM_Crisis_Prob 가 미래 자료로 정해진 값이 된다.
#   ② 신선도 — as-of 전환 뒤엔 밤 MSM 갱신이 실패하면 로더가 stop 하고 국면 빌드가 멈춘다(fail-closed 자체는 맞다).
#      그런데 그 실패는 리프레시 요약에 '실패 0'으로 남을 수 있고, 표식만 보는 관문은 그 동결본을 통과시킨다
#      (검토 #16 — 구 Gate M 이 찍던 max= 는 월말 라벨이라 내용이 언제까지인지 못 보여 준다).
#   ⇒ 두 러너(예약 경로 run_nolayer4_monthly.sh [0b] · 수동 full 러너 run_pg2_rebalance_full.sh Gate M)가
#      이 한 스크립트로 같은 판정을 한다. 판정 로직을 러너에 복붙하지 않는다(갈라지면 한쪽이 낡는다).
#
# 판정(전부 참이어야 OK — 실패 사유는 태그로 전부 적는다):
#   [marker]  월간 신호 행 열 msm_estimator 고유값 = asof_yearly:v1 ∧ 파일 속성 msm_estimator 같은 값
#             (열 없음 · 속성 없음 · 혼합 · NA · 다른 값 = BAD)
#   [bench]   SIG_DATE = 벤치(.cache/benchmark.parquet)에서 AS_OF 전 마지막 거래일. sig 월(= AS_OF 전날의 달) 안이어야
#             한다 — full 러너 [1b] 의 SIG_DATE(sig 월 벤치 최대일)와 같은 정의. 벤치가 sig 월에 닿지 않았으면 BAD.
#   [sig_row] 월간 신호에 sig 월(YM) 행이 정확히 1개
#   [avail]   그 행의 avail_date(Date 형) == SIG_DATE   (부분 월 빌드 · 국면 동결 = 불일치)
#   [daily]   일간 신호(.cache/unified_regime_signal_daily.parquet) max(Date) ≥ SIG_DATE
#   [read] · [args] · [tmp] · [rscript] · [internal] = 판독 실패 · 인자 오류 · R 미실행 — 전부 BAD(fail-closed)
#
# 사용:  bash gate_msm_asof.sh AS_OF [ROOT]
#   AS_OF = 홀딩월 1일(YYYY-MM-01). ROOT = 데이터 루트(인자 > $QM_ROOT > 운영 루트) — 시험은 모래상자 루트를 넘긴다.
#   R 실행기 = $QVEST_RSCRIPT > PATH 의 Rscript > R 4.5.2 기본 경로.
# 출력: stdout 정확히 1줄 'OK 진단…' | 'BAD [태그] 사유 ; … | 진단…'. 종료코드 0 = OK · 1 = BAD(판독 실패 포함).
#   ★성공은 양의 증거로만: R 종료코드 0 ∧ 'OK ' 줄일 때만 0 이다. 죽은 R(미실행 · 무출력 · rc/줄 불일치)은 1.
#   진단 문구(R 오류 꼬리)는 stderr 로만 낸다 — 호출 러너가 로그에 붙인다.
# 쓰기: 없음(읽기 전용 — R 임시 파일만 mktemp 후 삭제).
# 시험: 08_Tests/ops/test_gate_msm_asof.sh (모래상자 합성 .cache · 위반 주입 · 돌연변이 · 러너 배선)
#==============================================================================
set -uo pipefail

AS_OF="${1:-}"
ROOT="${2:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
# 슬래시 정규화 — 역슬래시 형(C:\Users\...)이 R 로 가면 '\U' 이스케이프 사고가 난다(run_pg2_rebalance_full.sh [1b] 선례).
# MSYS 형(/c/... · /tmp/...)은 cygpath 로 네이티브 슬래시 형(C:/...)으로 바꿔 R 에 넘긴다.
ROOT="${ROOT//\\//}"
if command -v cygpath >/dev/null 2>&1; then ROOT="$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT")"; fi
RSCRIPT="${QVEST_RSCRIPT:-$(command -v Rscript 2>/dev/null || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')}"

bad(){ echo "BAD $*"; exit 1; }
[[ "$AS_OF" =~ ^[0-9]{4}-[0-9]{2}-01$ ]] || bad "[args] AS_OF='$AS_OF' — 홀딩월 1일(YYYY-MM-01)이어야 한다"
[ -d "$ROOT" ] || bad "[args] 데이터 루트 없음 root=$ROOT"

_T="$(mktemp /tmp/qm_gatem_XXXX.R)" || bad "[tmp] mktemp 실패"
_E="$(mktemp /tmp/qm_gatem_XXXX.err)" || { rm -f "$_T"; bad "[tmp] mktemp 실패"; }
trap 'rm -f "$_T" "$_E"' EXIT
_TW="$_T"
if command -v cygpath >/dev/null 2>&1; then _TW="$(cygpath -m "$_T" 2>/dev/null || echo "$_T")"; fi

# 판정부(R) — 인용 heredoc 이라 셸 치환이 일어나지 않는다. 루트 · AS_OF 는 R 소스 문자열이 아니라 인자로 넘긴다.
# ★시험 돌연변이 표적: 끝에 '# @CHK_…' 꼬리표가 붙은 줄은 한 줄짜리 독립 문장이다 — 줄을 나누거나 else 사슬에 넣지 말 것
#   (08_Tests/ops/test_gate_msm_asof.sh 가 그 줄을 no-op 로 바꾼 사본으로 위반 사례가 OK 로 새는지 본다).
cat > "$_T" <<'REOF'
## gate_msm_asof 판정부 — 인자 ROOT AS_OF · 출력 = ASCII 1줄 · quit(status 0 = OK | 1 = BAD)
EXPECT <- "asof_yearly:v1"   # = regime_signal.R::MSM_ESTIMATOR_EXPECTED = msm_asof.R::MSMA_ESTIMATOR (어긋나면 막는 쪽으로 실패 · 시험이 셋을 대조)
a <- commandArgs(trailingOnly = TRUE)
why <- character(0); info <- character(0)
flag <- function(tag, msg) why <<- c(why, sprintf("[%s] %s", tag, msg))
note <- function(k, v) info <<- c(info, sprintf("%s=%s", k, v))
fmt <- function(v) if (!length(v)) "none" else paste(ifelse(is.na(v), "NA", as.character(v)), collapse = ",")
clean <- function(s) { s <- gsub("[\r\n\t]+", " ", paste(s, collapse = " ")); s2 <- iconv(s, "", "ASCII", sub = "?"); if (is.na(s2)) s2 <- "?"; substr(s2, 1L, 200L) }
finish <- function() {
  ok <- !length(why)
  line <- if (ok) paste("OK", paste(info, collapse = " ")) else paste("BAD", paste(why, collapse = " ; "), "|", paste(info, collapse = " "))
  cat(line, "\n", sep = "")
  quit(save = "no", status = if (ok) 0L else 1L)
}
main <- function() {
  if (length(a) < 2L) { flag("args", "need ROOT AS_OF"); return(invisible()) }
  root <- a[1]; as_of_s <- a[2]
  as_of <- suppressWarnings(as.Date(as_of_s, format = "%Y-%m-%d"))
  if (!grepl("^[0-9]{4}-[0-9]{2}-01$", as_of_s) || is.na(as_of)) { flag("args", sprintf("as_of=%s is not a valid YYYY-MM-01", clean(as_of_s))); return(invisible()) }
  sig_ym <- format(as_of - 1L, "%Y-%m")
  note("as_of", format(as_of)); note("sig_ym", sig_ym)
  rd <- function(tag, rel, ...) tryCatch({
    f <- file.path(root, ".cache", rel)
    if (!file.exists(f)) stop("absent: ", f)
    arrow::read_parquet(f, ...)
  }, error = function(e) { flag("read", sprintf("%s %s", tag, clean(conditionMessage(e)))); NULL })

  ## [bench] SIG_DATE = AS_OF 전 마지막 벤치 거래일 — sig 월 안이어야 한다(아니면 벤치가 sig 월에 닿지 않은 것)
  sig_date <- as.Date(NA)
  b <- rd("bench", "benchmark.parquet", col_select = "Date")
  if (!is.null(b)) {
    bd <- as.Date(b[["Date"]]); bd <- bd[!is.na(bd) & bd < as_of]
    last_b <- if (length(bd)) max(bd) else as.Date(NA)
    note("bench_last_before_as_of", fmt(last_b))
    if (!is.na(last_b) && format(last_b, "%Y-%m") == sig_ym) sig_date <- last_b
    if (is.na(sig_date)) flag("bench", sprintf("no bench trading day in sig_ym=%s before as_of (bench stale)", sig_ym))
  }
  note("sig_date", fmt(sig_date))

  ## [marker] [sig_row] [avail] — 월간 통합 신호(BOOK m4 엔진의 입력)
  x <- rd("monthly", "unified_regime_signal.parquet")
  if (!is.null(x)) {
    nm <- names(x)
    col <- if ("msm_estimator" %in% nm) unique(as.character(x[["msm_estimator"]])) else character(0)
    at <- attr(x, "msm_estimator", exact = TRUE); at <- if (is.null(at)) character(0) else as.character(at)
    note("col", fmt(col)); note("attr", fmt(at)); note("rows", nrow(x))
    if (!identical(col, EXPECT)) flag("marker", sprintf("column msm_estimator=%s (expect %s)", fmt(col), EXPECT))   # @CHK_MARKER_COL
    if (!identical(at, EXPECT)) flag("marker", sprintf("attr msm_estimator=%s (expect %s)", fmt(at), EXPECT))   # @CHK_MARKER_ATTR
    ym <- if ("YM" %in% nm) as.character(x[["YM"]]) else character(0)
    i <- which(ym == sig_ym)
    note("sig_rows", length(i))
    if (length(i) != 1L) flag("sig_row", sprintf("monthly rows with YM=%s: %d (expect 1)", sig_ym, length(i)))   # @CHK_SIGROW
    av <- if ("avail_date" %in% nm) x[["avail_date"]] else NULL
    sig_av <- if (length(i) == 1L && inherits(av, "Date")) av[i] else as.Date(NA)
    note("sig_avail", fmt(sig_av))
    if (length(i) == 1L && !inherits(av, "Date")) flag("avail", sprintf("avail_date column missing or not Date (%s)", if (is.null(av)) "absent" else class(av)[1]))
    if (length(i) == 1L && inherits(av, "Date") && !is.na(sig_date) && (is.na(sig_av) || sig_av != sig_date)) flag("avail", sprintf("sig row avail_date=%s != sig_date=%s (partial-month build or frozen regime)", fmt(sig_av), fmt(sig_date)))   # @CHK_AVAIL
  }

  ## [daily] 일간 통합 신호가 SIG_DATE 까지 왔나(내용 기준 신선도)
  d <- rd("daily", "unified_regime_signal_daily.parquet", col_select = "Date")
  if (!is.null(d)) {
    dd <- as.Date(d[["Date"]]); dd <- dd[!is.na(dd)]
    dmax <- if (length(dd)) max(dd) else as.Date(NA)
    note("daily_max", fmt(dmax))
    if (!is.na(sig_date) && (is.na(dmax) || dmax < sig_date)) flag("daily", sprintf("daily max(Date)=%s < sig_date=%s (daily regime not advanced)", fmt(dmax), fmt(sig_date)))   # @CHK_DAILY
  }
  invisible()
}
tryCatch(main(), error = function(e) flag("internal", clean(conditionMessage(e))))
finish()
REOF

OUT="$("$RSCRIPT" --no-save "$_TW" "$ROOT" "$AS_OF" 2>"$_E")"
RC=$?
LINE="$(printf '%s\n' "$OUT" | tr -d '\r' | grep -E '^(OK|BAD) ' | tail -n 1)"
# 성공 = R rc 0 ∧ 'OK ' 줄(양의 증거). BAD = R rc 1 ∧ 'BAD ' 줄. 그 밖(미실행 · 무출력 · 불일치)은 판독 실패로 막는다.
if [ "$RC" -eq 0 ] && [ "${LINE#OK }" != "$LINE" ]; then echo "$LINE"; exit 0; fi   # @CHK_WRAP_OK
if [ "$RC" -eq 1 ] && [ "${LINE#BAD }" != "$LINE" ]; then echo "$LINE"; exit 1; fi
{ echo "[gate_msm_asof] R 판독 실패 rc=$RC rscript=$RSCRIPT 판정 줄=${LINE:-없음}"; tail -n 5 "$_E" 2>/dev/null; } >&2
# stdout 사유에는 판정 줄 머리말(OK/BAD)만 싣는다 — 줄 전체를 실으면 그 안의 [태그]가 실패 사유로 오독된다.
_HEAD="${LINE%% *}"
bad "[rscript] R 판독 실패(rc=$RC · 판정 줄 머리말=${_HEAD:-없음}) — 실행기 $RSCRIPT"
