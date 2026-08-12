## P7a — 밴드 Δ 가 base 성격에 어떻게 달렸는가: 겹침률로 설명되는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  실측 Δ: mine +0.845 · PG2 +0.264 · core4 **-0.293**. base 강도로는 단조 설명 안 됨(P6c 정정).
##  가설: base top-25 와 **D03 밴드(D3~D4) 후보의 겹침률**이 Δ 를 설명한다.
##    겹침이 높으면 밴드가 base 가 이미 고른 종목을 재확인 → 무해/소폭 개선
##    겹침이 낮으면 밴드가 base 의 좋은 종목을 **밀어냄** → 해로움
##  측정: 각 base 의 top-25 중 D03 q∈{3,4} 인 비율(월 중앙값) + 교체된 12종의 base 순위 손실.
##   Y1 겹침이 설명: 겹침률 순서가 Δ 순서와 일치(mine > PG2 > core4) → 사전 판정 가능
##   Y2 불일치: 순서가 안 맞음 → 다른 기전(P7b 성격 축)
##  ★성과 측정 없음. 기전 진단만.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
B[, ym := format(Date, "%Y-%m")]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, ym := format(as.Date(Date), "%Y-%m")]
ds <- sort(unique(B$Date))
acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=CORE4), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
C4 <- rbindlist(acc, fill=TRUE)

U <- merge(B, ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, C4, by=c("Date","Ticker"), all.x=TRUE)
U <- merge(U, A[!is.na(score_eff), .(ym, Ticker, pg2=score_eff)], by=c("ym","Ticker"), all.x=TRUE)
have4 <- intersect(CORE4, names(U))
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
U[complete.cases(U[, have4, with=FALSE]),
  core4 := rowMeans(scale(as.matrix(.SD)), na.rm=TRUE), by=Date, .SDcols=have4]

diag_base <- function(col, lab) {
  D <- U[!is.na(get(col)) & !is.na(q)]
  D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  s <- D[, {
    o <- order(-get(col)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
    top <- seq_len(min(25L, .N))
    in_band <- mean(qq[top] %in% 3:4)                 # top-25 중 밴드 구역 비율
    # 교체 손실: 밴드로 채울 12종의 base 순위 (낮을수록 base 상 열등)
    keep <- tk[seq_len(min(13L, .N))]
    pool_rk <- which(qq %in% 3:4 & !(tk %in% keep))[seq_len(12L)]
    .(in_band = in_band, pool_rank_med = median(pool_rk, na.rm=TRUE))
  }, by=Date]
  data.table(base = lab, n_months = nrow(s),
             overlap = round(median(s$in_band, na.rm=TRUE), 4),
             pool_rank_med = round(median(s$pool_rank_med, na.rm=TRUE), 1))
}
R <- rbindlist(list(diag_base("M26_Revenue_Mom","mine(M26)"),
                    diag_base("pg2","PG2 score_eff"),
                    diag_base("core4","core4-EW")))
R[, delta := c(0.845, 0.264, -0.293)]
print(R[])
rho <- suppressWarnings(cor(R$overlap, R$delta, method="spearman"))
rho2 <- suppressWarnings(cor(R$pool_rank_med, R$delta, method="spearman"))
cat(sprintf("\nspearman(겹침률, Δ) = %.3f · spearman(교체풀 순위, Δ) = %.3f  (n=3)\n", rho, rho2))
verdict <- if (is.finite(rho) && rho >= 0.99) "Y1_OVERLAP_EXPLAINS" else "Y2_NOT_EXPLAINED"
cat(sprintf("판정: %s\n⚠n=3 이라 상관은 순서 일치 여부만 본다(통계량 아님)\n", verdict))
write_json(list(verdict=verdict, rho_overlap=rho, rho_poolrank=rho2, results=R),
           file.path(OUT,"p7a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
