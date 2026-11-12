# regime_catchup.R — 레짐 브리핑 직전 산출물 따라잡기 (2026-11-13 · 도훈 지시 "최신데이터로 계산되서 발송되게")
#
# 사고(11-13): 아침 [2/5]·[3/5] 생산자(07:16)는 그 시각 RAWDATA(11-11 까지)로 KTRI v3 · 국면 일간 원장을 만들었다.
#   RAWDATA 11-12 는 07:45 에 들어왔는데 mrs 자료 관문(regime_data_gate.R)은 산출물이 직전 거래일에 닿기를 30분 기다리기만 하고
#   생산자를 다시 부르지 않았다 → 07:49 에 11-11 자료로 본문 · 차트 3장이 나갔다(같은 아침 스타일 브리핑은 RAWDATA 를 직접 읽어 11-12).
# 동작: 입력의 마지막 날짜가 산출물보다 앞서 있으면 아침 체인과 **같은 함수**로 다시 만든다(새 계산 규칙 없음):
#   ① MSM as-of 경로 : 벤치 > msm_asof_daily               → msm_asof.R::msma_update            (self_heal.R · daily_refresh 와 같은 함수)
#   ② KTRI v3        : min(RAWDATA, 벤치) > KTRI v3         → ktri_v3_builder.R::build_ktri_v3_safe (morning [2/5] · daily_refresh 와 같은 함수)
#   ③ 국면 원장      : min(MSM, KTRI) > 국면 일간 원장       → regime_append_only.R::regime_ledger_rebuild_publish (라이브 = 원장 병합만)
#   FRED(L2)는 꼬리를 정하지 않는 층이라(as-of 로 붙는다 · regime_signal.R 꼬리 가드) 여기서 다시 받지 않는다.
# PIT: 새 날짜의 행은 생산자 규칙 그대로 만든다 — 꼬리 가드(L1 · L3 가 모두 닿은 날까지) · 입력 미도달 동결 보류 · FRED C11 가용 시점.
#   이 스크립트는 '언제 다시 부를지'만 정한다(판정 · 계산 규칙 무변경).
# 배리어(밤 리프레시 · RAWDATA writer 잠금)는 호출자 mrs_daily_briefing.sh 가 bash 로 판정한다 — held 면 이 스크립트를 부르지 않는다
#   (쓰는 중인 RAWDATA 를 읽지 않는다 · 진행 중인 리프레시는 같은 산출물을 스스로 다시 만든다).
# QVEST_REGIME_CATCHUP_PLAN=1 → 판정만 출력한다(생산자 호출 0 · 쓰기 0 · 시험용).
# stdout 마지막 줄: "CATCHUP ran <단계> | …" · "CATCHUP skip <사유> | …" · "CATCHUP plan <단계> | …"
source("02_Infrastructure/ops/morning_steps/_root.R")
suppressPackageStartupMessages({ library(data.table); library(arrow) })

PLAN <- identical(Sys.getenv("QVEST_REGIME_CATCHUP_PLAN", ""), "1")
.fin <- function(v) { v <- suppressWarnings(tryCatch(as.Date(v), error = function(e) as.Date(NA)))
  if (length(v) != 1L || is.na(v) || !is.finite(as.numeric(v))) as.Date(NA) else v }
.pq_last <- function(p) .fin(tryCatch(suppressWarnings(max(as.Date(read_parquet(p, col_select = "Date")$Date), na.rm = TRUE)),
                                      error = function(e) NA))
.csv_last <- function(p) .fin(tryCatch(suppressWarnings(max(as.Date(fread(p, select = "DATE")$DATE), na.rm = TRUE)),
                                       error = function(e) NA))
.gt <- function(a, b) !is.na(a) && (is.na(b) || a > b)                  # 입력 a 가 산출 b 보다 앞서는가(산출 판독 불가 = 앞섬)
.mn <- function(a, b) if (is.na(a) || is.na(b)) as.Date(NA) else min(a, b)
KTRI_CSV <- "04_Research/regime_comparison/output/ktri_v3_signals.csv"
U_DAILY  <- ".cache/unified_regime_signal_daily.parquet"
MSM_PQ   <- ".cache/msm_asof_daily.parquet"

snap <- function() list(raw = .pq_last(RAWDATA_CACHE), bm = .pq_last(".cache/benchmark.parquet"),
                        msm = .pq_last(MSM_PQ), ktri = .csv_last(KTRI_CSV), reg = .pq_last(U_DAILY))
s0 <- snap()
fmt <- function(d) if (is.na(d)) "NA" else format(d)
cat(sprintf("[regime_catchup] 입력 RAWDATA %s · 벤치 %s | 산출 MSM %s · KTRI v3 %s · 국면 일간 %s\n",
            fmt(s0$raw), fmt(s0$bm), fmt(s0$msm), fmt(s0$ktri), fmt(s0$reg)))

do_msm  <- .gt(s0$bm, s0$msm)
do_ktri <- .gt(.mn(s0$raw, s0$bm), s0$ktri)
## 국면 원장은 위 둘을 돌린 뒤 다시 잰다(계획 모드는 돌렸다고 가정한 날짜로 잰다)
msm_p  <- if (do_msm) s0$bm else s0$msm
ktri_p <- if (do_ktri) .mn(s0$raw, s0$bm) else s0$ktri
tail_line <- function(s) sprintf("KTRI v3 %s→%s · 국면 일간 %s→%s", fmt(s0$ktri), fmt(s$ktri), fmt(s0$reg), fmt(s$reg))

if (PLAN) {
  steps <- c(if (do_msm) "msm", if (do_ktri) "ktri", if (.gt(.mn(msm_p, ktri_p), s0$reg)) "regime")
  cat(sprintf("CATCHUP plan %s | 입력 RAWDATA %s · 벤치 %s\n", if (length(steps)) paste(steps, collapse = "+") else "없음",
              fmt(s0$raw), fmt(s0$bm)))
  quit(save = "no", status = 0)
}

ran <- character(0)
if (do_msm) {
  tryCatch({
    source("02_Infrastructure/regime/msm_asof.R")
    msma_update(getwd())
    ran <- c(ran, "msm")
  }, error = function(e) cat(sprintf("[regime_catchup] MSM(as-of) FAIL: %s\n", conditionMessage(e))))
}
if (do_ktri) {
  tryCatch({
    source("02_Infrastructure/regime/ktri_v3_builder.R")
    if (is.null(build_ktri_v3_safe())) stop("build_ktri_v3_safe 가 NULL(빌드 실패 · 로그 위)")
    ran <- c(ran, "ktri")
  }, error = function(e) cat(sprintf("[regime_catchup] KTRI v3 FAIL: %s\n", conditionMessage(e))))
}
s1 <- snap()
if (.gt(.mn(s1$msm, s1$ktri), s1$reg)) {
  tryCatch({
    source("02_Infrastructure/regime/regime_signal.R")
    source("02_Infrastructure/regime/regime_append_only.R")
    res <- regime_ledger_rebuild_publish(root = getwd())
    ok <- vapply(res, function(r) isTRUE(r$status %in% c(0L, 1L)), logical(1))
    ran <- c(ran, if (all(ok)) "regime" else sprintf("regime(rc %s)", paste(vapply(res, function(r) as.character(r$status), ""), collapse = "/")))
  }, error = function(e) cat(sprintf("[regime_catchup] 국면 원장 FAIL: %s\n", conditionMessage(e))))
}
s2 <- snap()
if (length(ran)) {
  cat(sprintf("CATCHUP ran %s | %s\n", paste(ran, collapse = "+"), tail_line(s2)))
} else {
  why <- if (!do_msm && !do_ktri && !.gt(.mn(s1$msm, s1$ktri), s1$reg)) "입력이 산출물보다 앞서지 않음" else "생산자 실패(위 로그)"
  cat(sprintf("CATCHUP skip %s | 입력 RAWDATA %s · 벤치 %s · %s\n", why, fmt(s0$raw), fmt(s0$bm), tail_line(s2)))
}
