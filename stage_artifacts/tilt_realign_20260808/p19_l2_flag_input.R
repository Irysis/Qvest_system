# p19_l2_flag_input.R — L2: β_R05 의 '입력 축' 탐색 (z 를 무엇으로 재는가)
# 근거: I1 에서 매핑 *형태*는 개선 여지 없음(연속화 열위), K2 에서 MDD 레버는 β_R05 단독.
#   남은 자유도 = flag 을 만드는 **입력 팩터**. R05_Tail_Risk 가 최적인지 그냥 선택됐던 것인지.
# ★E3 와의 차이: E3 는 각 팩터를 **단독 트리거**로 시험(전건 실패). 여기서는 실증된 구조
#   (라벨 × flag 2×2 표) **안의 수정자**로 넣는다 — 상호작용 항으로 평가.
# ★C15 정본 경로 · 비교 base = β_R05 단독(K2 최선, m4 제외해 축을 격리)
suppressMessages({ library(data.table); library(arrow); library(dplyr); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
BPS <- 0.0015
FACTORS <- c("R05_Tail_Risk","D01_IdioVol","L01_Amihud","Q07_Earnings_Stability","M08_Residual_Mom")

M <- fread("stage_artifacts/tilt_realign_20260808/p16_j1_close.csv"); M[, decision_date := as.Date(decision_date)]
R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
D <- merge(M[, .(decision_date, regime, beta_R05, m4)], R[, .(decision_date, eval_date, gross=gA, turn=tA)], by="decision_date")
setorder(D, decision_date)
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
hold <- car[, .(decision_date, Ticker)]
reg <- .load_registry()

Z <- rbindlist(lapply(seq_len(nrow(D)), function(i) {
  dd <- D$decision_date[i]
  f <- tryCatch(load_month_factors(dd, factor_names=FACTORS), error=function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  f <- as.data.table(f)
  if (!("Z_Score" %in% names(f)) && "Z_Score_Aligned" %in% names(f)) setnames(f,"Z_Score_Aligned","Z_Score")
  if (!("Z_Score" %in% names(f))) return(NULL)
  if ("Coverage" %in% names(f)) f <- f[Coverage == TRUE]
  f <- f[is.finite(Z_Score)]; if (!nrow(f)) return(NULL)
  fa <- as.data.table(tryCatch(align_factor_direction(copy(f)[, sig_date := dd], reg, sig_date=dd, min_ic_months=12L),
                               error=function(e) copy(f)))
  zc <- if ("Z_Score_Aligned" %in% names(fa)) "Z_Score_Aligned" else "Z_Score"
  hk <- hold[decision_date==dd, Ticker]
  fa[, .(z = mean(get(zc)[Ticker %in% hk], na.rm=TRUE)), by=Factor_Name][, decision_date := dd][]
}), fill=TRUE)
cat(sprintf("[z] %d행 | 팩터 %s\n", nrow(Z), paste(sort(unique(Z$Factor_Name)), collapse=",")))

mk <- function(inv, lbl) {
  net <- D$gross*inv - BPS*D$turn*inv
  x <- xts(net, order.by=D$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(입력=lbl, 발화=NA_integer_, SR=round(as.numeric(t[3,1]),3), CAGR=round(as.numeric(t[1,1])*100,2),
             MDD=round(as.numeric(maxDrawdown(x))*100,2),
             Calmar=round(as.numeric(t[1,1])/pmax(as.numeric(maxDrawdown(x)),1e-9),3))
}
base_beta <- fcase(D$regime=="CRISIS",0.50, D$regime=="CAUTION",0.70, default=1.00)
lower     <- fcase(D$regime=="CRISIS",0.30, D$regime=="CAUTION",0.50, default=0.85)
expq <- function(x,p=0.20,mn=36L) sapply(seq_along(x), function(i) if (i<=mn) NA_real_ else quantile(x[1:(i-1)],p,names=FALSE,na.rm=TRUE))

rows <- list(mk(D$beta_R05, "[기준] 현행 R05 flag (원장)"), mk(base_beta, "[대조] flag 없음 (라벨만)"))
rows[[1]]$발화 <- sum(D$beta_R05 < base_beta - 1e-9); rows[[2]]$발화 <- 0L
for (fn in sort(unique(Z$Factor_Name))) {
  zz <- merge(D[, .(decision_date)], Z[Factor_Name==fn, .(decision_date, z)], by="decision_date", all.x=TRUE)
  setorder(zz, decision_date)
  if (sum(is.finite(zz$z)) < 100) next
  q <- expq(zz$z); fl <- is.finite(q) & is.finite(zz$z) & zz$z < q; fl[is.na(fl)] <- FALSE
  r <- mk(ifelse(fl, lower, base_beta), sprintf("%s (보유종목 z)", fn)); r$발화 <- sum(fl)
  rows[[length(rows)+1L]] <- r
}
out <- rbindlist(rows); setorder(out, -Calmar)
cat("\n===== flag 입력 팩터 대조 (동일 2×2 매핑 · m4 제외) =====\n"); print(out)
cat(sprintf("\n[해석] 현행 R05 flag 를 Calmar 로 넘는 입력이 있으면 입력 축에 개선 여지.\n"))
cat(sprintf("       모두 못 넘으면 R05 선택이 사후적으로 정당 — 남은 자유도는 입력이 아니라 다른 층.\n"))
fwrite(out, "stage_artifacts/tilt_realign_20260808/p19_l2_flag_input.csv")
