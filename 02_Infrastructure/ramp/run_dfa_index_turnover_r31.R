## run_dfa_index_turnover_r31.R — R31: 지수 내부 회전율 실측 + 비용 부과 시 영향 (§34 결함 수리 1단계)
## 결함: ramp_shumulvey_indices.R 이 매 월말 top-tercile 멤버십을 재구성하는데 거래비용을 부과하지 않는다.
##       15bps 는 배분층(22개 지수 간 sum|Δw|)에만 붙는다.
## 본 스크립트는 지수 구성단계의 sum|Δw| 를 팩터별·월별로 실측하고, 15bps 부과 시 연율 drag 를 산출한다.
## ★비용 규약은 배분층과 동일: cost = (bps/1e4) * sum|Δw|  (v2.4_kr_retail_15bps delta-based)
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")

FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets", LowVol="D03_RealVol",
  LowBeta="D02_Beta", TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity",
  Accrual="AC18_Accrual_Quality", Consensus="C19_Composite_Earnings", SUE="C01_SUE",
  Crowding="CR07_Momentum_Crowding", ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
QCUT <- 0.6667   # 정본 SMV_TOPQ

rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[, Date := as.Date(Date)]; rd <- rd[is.finite(Size) & Size > 0]
rd[, inuniv := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
rd <- rd[inuniv == TRUE]; rd[, ym := format(Date, "%Y-%m")]
UNI <- rd[, .SD[which.max(Date)], by = .(Ticker, ym), .SDcols = "Size"]
MR  <- rd[is.finite(Ret), .(mret = prod(1 + Ret) - 1), by = .(Ticker, ym)]
alld  <- sort(unique(rd$Date))
rebal <- alld[!duplicated(format(alld, "%Y-%m"), fromLast = TRUE)]
rebal <- rebal[rebal >= as.Date("2005-12-01") & rebal <= as.Date("2026-07-31")]
cat("리밸 시점:", length(rebal), "(", as.character(min(rebal)), "~", as.character(max(rebal)), ")\n")

prevW <- setNames(vector("list", length(FAC)), names(FAC))
rows <- list()
for (i in seq_along(rebal)) {
  sd_ <- rebal[i]; ymd <- format(sd_, "%Y-%m")
  uni <- UNI[ym == ymd, .(Ticker, Size)]; if (nrow(uni) < 30) next
  f <- tryCatch(as.data.table(load_month_factors(sd_, factor_names = unname(FAC))),
                error = function(e) NULL)
  if (is.null(f) || nrow(f) == 0) next
  fm <- merge(f, uni, by = "Ticker")
  rt <- MR[ym == ymd]
  for (nmf in names(FAC)) {
    sub <- fm[Factor_Name == FAC[nmf]]; if (nrow(sub) < 15) next
    thr <- quantile(sub$Z_Score_Aligned, QCUT, na.rm = TRUE)
    sel <- sub[Z_Score_Aligned >= thr]
    w <- setNames(sel$Size / sum(sel$Size), sel$Ticker)
    pw <- prevW[[nmf]]
    if (!is.null(pw)) {
      r <- rt[match(names(pw), Ticker), mret]; r[!is.finite(r)] <- 0
      dr <- pw * (1 + r); dr <- dr / sum(dr)                 # 직전 보유의 당월 드리프트
      allt <- union(names(w), names(dr))
      a <- ifelse(is.na(w[allt]), 0, w[allt]); b <- ifelse(is.na(dr[allt]), 0, dr[allt])
      tov <- sum(abs(a - b))
      newn <- sum(!(names(w) %in% names(dr)))
      rows[[length(rows)+1]] <- data.table(ym = ymd, factor = nmf, n = length(w),
        turnover = tov, new_names = newn, new_frac = newn/length(w))
    }
    prevW[[nmf]] <- w
  }
  if (i %% 30 == 0) cat("  ", i, "/", length(rebal), ymd, "\n")
}
T <- rbindlist(rows)
fwrite(T, "outputs/ramp/dfa_index_turnover_r31_20260822.csv")

cat("\n=== [1] 팩터별 지수 내부 월 회전율 (sum|Δw|, 드리프트 반영) ===\n")
A <- T[, .(n_mo = .N, tov_med = median(turnover), tov_mean = mean(turnover),
           new_frac_med = median(new_frac),
           drag_15bps_yr = 12 * mean(turnover) * 15/1e4), by = factor][order(-tov_mean)]
print(A[, .(factor, n_mo, tov_med = round(tov_med,3), tov_mean = round(tov_mean,3),
            신규종목비율 = round(new_frac_med,3), 연율drag_15bps = round(drag_15bps_yr,4))])
cat(sprintf("\n  전 팩터 평균 월 회전율 = %.3f | 연율 %.2f | 15bps 부과 시 연율 drag = %.3f%%\n",
            mean(T$turnover), 12*mean(T$turnover), 100*12*mean(T$turnover)*15/1e4))

cat("\n=== [2] R20 채택팔이 실제로 고른 5개 팩터 기준 가중 drag ===\n")
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]; R[, ym := format(Date,"%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1)), by = ym,
         .SDcols = c("Market", fac)][ym <= "2026-07"]
NM <- nrow(mon); NF <- length(fac)
S <- matrix(NA_real_, NM, NF)
for (fi in 1:NF) for (m in 12:NM)
  S[m, fi] <- prod(1 + mon[[fac[fi]]][(m-11):m]) / prod(1 + mon$Market[(m-11):m]) - 1
tmap <- T[, .(tov = mean(turnover)), by = .(ym, factor)]
sel_drag <- c()
for (m in seq(13, NM, by = 3)) {
  d <- m - 1; s <- S[d, ]; pos <- which(is.finite(s) & s > 0); if (!length(pos)) next
  if (length(pos) > 5) pos <- pos[order(s[pos], decreasing = TRUE)][1:5]
  wf <- s[pos]/sum(s[pos]); nms <- fac[pos]
  tv <- tmap[ym == mon$ym[d]][match(nms, factor), tov]; tv[!is.finite(tv)] <- mean(T$turnover)
  sel_drag <- c(sel_drag, sum(wf * tv))
}
cat(sprintf("  선택 5팩터 가중 월 회전율 = %.3f (분기 리밸이나 지수는 **매월** 재구성되므로 월 12회 과금)\n",
            mean(sel_drag)))
cat(sprintf("  ⇒ 15bps 부과 시 연율 drag = **%.3f%%**\n", 100*12*mean(sel_drag)*15/1e4))
cat(sprintf("  현 CAGR 0.1403 대비 = %.1f%% 잠식 | 현 active(vs parent) 약 5.6%%/yr 대비 = %.1f%% 잠식\n",
            100*(12*mean(sel_drag)*15/1e4)/0.1403, 100*(12*mean(sel_drag)*15/1e4)/0.056))
cat("\nR31_DONE\n")
