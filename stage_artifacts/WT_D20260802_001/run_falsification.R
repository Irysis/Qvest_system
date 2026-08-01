# =============================================================================
# run_falsification.R — WT-D20260802_001 / FQ-073
#   AST v1.1 §1 이 의무화한 hypothesis.falsification 의 실제 집행.
#
#   선언한 반증 조건 (성과 동어반복 아님 — field_dictionary C-CONSENSUS-QW 리프로 확인):
#     "수출 서프라이즈 상위 종목의 후속 컨센서스 영업이익(op_profit_fy1) 추정치가
#      상향되지 않으면 '수출→실적' 경로가 끊어진 것 = 기전 기각"
#
#   이 검정은 가격을 보지 않는다. 따라서 '신호가 가격에 없다'와
#   '기전 자체가 없다'를 분리한다 — 음수 PORT_t 만으로는 구분 불가한 축.
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
say <- function(fmt, ...) cat(sprintf(paste0("[falsify] ", fmt, "\n"), ...))

CP <- ".cache/consensus/op_profit_fy1.parquet"
if (!file.exists(CP)) stop("[falsify] consensus op_profit_fy1 부재: ", CP)
CO <- as.data.table(read_parquet(CP))
say("consensus 원본 컬럼: %s", paste(names(CO), collapse = ", "))
setnames(CO, names(CO), sub("^security_id$", "Ticker", names(CO)))
vcol <- setdiff(names(CO), c("Date", "Ticker"))[1]
CO[, Date := as.Date(Date)]
setnames(CO, vcol, "op_fy1")
CO <- CO[is.finite(op_fy1) & op_fy1 != 0]
say("consensus: %d행 · %d종목 · %s~%s", nrow(CO), uniqueN(CO$Ticker),
    as.character(min(CO$Date)), as.character(max(CO$Date)))

P1 <- as.data.table(read_parquet(file.path(OUT, "alpha_scores_F1_export_surprise.parquet")))
P1 <- P1[!is.na(value)]
setkey(CO, Ticker, Date)

# 각 score_date d 에 대해: 컨센 수준 as-of(d)  vs  as-of(d + H)  의 로그변화
asof_val <- function(dates, tickers) {
  q <- data.table(Ticker = tickers, Date = dates); setkey(q, Ticker, Date)
  CO[q, roll = TRUE, on = .(Ticker, Date)]$op_fy1        # d 이하 최신 관측 (PIT 방향)
}

H_DAYS <- c(63L, 126L)   # 약 3M / 6M
res <- list()
for (H in H_DAYS) {
  X <- copy(P1)
  X[, v0 := asof_val(Date, Ticker)]
  X[, v1 := asof_val(Date + H, Ticker)]
  X <- X[is.finite(v0) & is.finite(v1) & v0 > 0 & v1 > 0]
  X[, rev_log := log(v1 / v0)]
  # 극단 클립 (컨센 원장 튐 방어 — 판정 아닌 위생)
  X <- X[abs(rev_log) < log(10)]
  # 월별 횡단면 5분위
  X[, q := cut(frank(value, ties.method = "average") / .N, breaks = seq(0, 1, 0.2),
               labels = 1:5, include.lowest = TRUE), by = Date]
  bym <- X[!is.na(q), .(rev = mean(rev_log), n = .N), by = .(Date, q)]
  spread <- dcast(bym, Date ~ q, value.var = "rev")
  setnames(spread, c("Date", paste0("Q", 1:5)))
  spread <- spread[is.finite(Q1) & is.finite(Q5)]
  spread[, q5_minus_q1 := Q5 - Q1]
  mu <- spread[, mean(q5_minus_q1)]; se <- spread[, sd(q5_minus_q1) / sqrt(.N)]
  tt <- mu / se
  say("H=%dd: Q5-Q1 컨센 영업이익 개정 = %+.4f (log) t=%.3f n_months=%d | Q5=%+.4f Q1=%+.4f",
      H, mu, tt, nrow(spread), spread[, mean(Q5)], spread[, mean(Q1)])
  res[[paste0("H", H, "d")]] <- list(
    horizon_days = H, q5_minus_q1_logrev = round(mu, 5), t_stat = round(tt, 3),
    n_months = nrow(spread), q5_mean = round(spread[, mean(Q5)], 5),
    q1_mean = round(spread[, mean(Q1)], 5), n_obs = nrow(X),
    metric_type = "diagnostic_falsification")
}

verdict <- {
  t3 <- res$H63d$t_stat; t6 <- res$H126d$t_stat
  if (is.finite(t3) && t3 >= 2 && res$H63d$q5_minus_q1_logrev > 0)
    "MECHANISM_SUPPORTED — 수출 서프라이즈 상위군의 후속 컨센 상향이 유의. 가격 미반영은 전이/구현 문제."
  else if (is.finite(t3) && t3 <= -2)
    "MECHANISM_REVERSED — 상위군 컨센이 오히려 하향. 신호 정의(부호/스케일) 재검토 필요."
  else
    "MECHANISM_NOT_SUPPORTED — 선언한 부수 관측(컨센 상향)이 유의하지 않다. 가격 이전 단계에서 기전이 끊긴다 = 반증 조건 충족."
}
say("판정: %s", verdict)

write_json(list(falsification_declared =
   "수출 서프라이즈 상위 종목의 후속 컨센서스 영업이익(op_profit_fy1) 추정치가 상향되지 않으면 기전 기각",
   field_dictionary_ref = "C-CONSENSUS-QW (ast_field_map_v0.json / fundamentals)",
   results = res, verdict = verdict),
   file.path(OUT, "fq073_falsification.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
say("→ fq073_falsification.json")
