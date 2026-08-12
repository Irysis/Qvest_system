## BD1b — 수리판. DB 팩터는 D03_RealVol 이고 내 패널의 D03_EWMA 는 **WT-003 파생 변형**이다.
## 사전등록(측정 전 고정, 이 주석이 정본):
##  세 량을 함께 낸다(월별 spearman, 중앙값 보고):
##   (a) rho(D03_EWMA[내 패널], D03_RealVol[DB])  — 내 재료가 DB 재료와 같은 것인가
##   (b) rho(D03_EWMA, PC1(INVERTED 39 전체))     — 내 재료가 PC1 과 겹치는가
##   (c) rho(D03_EWMA, PC1(INVERTED 38, D03_RealVol 제외)) — 근친 제거 후에도 겹치는가
##   BE1 독립: (c) 중앙값 < 0.50 → 결합 EV 실재, BB1 착수
##   BE2 중복: (c) >= 0.70 → 결합은 재탕, 경로 닫힘
##   BE3 중간: 0.50~0.70
##  ★성과 측정 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
INV <- S[shape == "INVERTED"]$Factor_Name
cat(sprintf("[INVERTED] %d종 · D03_RealVol 포함 %s\n", length(INV), "D03_RealVol" %in% INV))

B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
liq <- as.data.table(P$liq)
ds <- sort(unique(B[!is.na(D03_EWMA)]$Date)); ds <- ds[seq(1, length(ds), by = 6L)]
ds <- ds[ds >= as.Date("2008-01-01")]
cat(sprintf("[표본] %d개월\n", length(ds)))

ra <- rb <- rc <- numeric(0)
for (dt in ds) {
  z <- try(load_month_factors(as.Date(dt), factor_names = INV), silent = TRUE)
  if (inherits(z, "try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  L <- liq[Date == dt, .(Ticker, adv)]
  z <- merge(z, L, by = "Ticker", all.x = TRUE)[is.na(adv) | adv >= 2e8]
  W <- dcast(z, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  my <- B[Date == dt & !is.na(D03_EWMA), .(Ticker, D03_EWMA)]
  W <- merge(W, my, by = "Ticker")
  fac <- intersect(INV, names(W))
  M <- as.matrix(W[, fac, with = FALSE])
  ok <- !is.na(W$D03_EWMA) & rowSums(is.na(M)) == 0L
  M <- M[ok, , drop = FALSE]; d <- W$D03_EWMA[ok]
  if (nrow(M) < 60L || ncol(M) < 5L) next
  if ("D03_RealVol" %in% colnames(M))
    ra <- c(ra, suppressWarnings(cor(d, M[, "D03_RealVol"], method="spearman")))
  p1 <- prcomp(M, center=TRUE, scale.=TRUE)$x[,1]
  rb <- c(rb, suppressWarnings(cor(d, p1, method="spearman")))
  M2 <- M[, setdiff(colnames(M), "D03_RealVol"), drop=FALSE]
  if (ncol(M2) >= 5L) {
    p2 <- prcomp(M2, center=TRUE, scale.=TRUE)$x[,1]
    rc <- c(rc, suppressWarnings(cor(d, p2, method="spearman")))
  }
}
if (!length(rc)) { cat("★산출 0 — 정지 신호\n"); quit(status=0) }
f <- function(v, lab) cat(sprintf("  %-46s 중앙값 %.3f · 평균 %.3f (월 %d)\n", lab, median(abs(v)), mean(abs(v)), length(v)))
cat("\n=== |spearman| (월별, 중앙값) ===\n")
f(ra, "(a) D03_EWMA[내] ~ D03_RealVol[DB]")
f(rb, "(b) D03_EWMA ~ PC1(INVERTED 39)")
f(rc, "(c) D03_EWMA ~ PC1(38, D03_RealVol 제외)")
m <- median(abs(rc))
verdict <- { if (m < 0.50) "BE1_INDEPENDENT" else if (m >= 0.70) "BE2_REDUNDANT" else "BE3_MID" }
cat(sprintf("\n판정: %s\n★성과 측정 없음\n", verdict))
write_json(list(verdict=verdict, rho_a=median(abs(ra)), rho_b=median(abs(rb)), rho_c=m,
                n_months=length(rc)), file.path(OUT,"bd1_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
