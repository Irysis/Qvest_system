## BD1 — D03_EWMA 가 INVERTED 39종의 PC1 과 얼마나 겹치는가 (BB1 착수 게이트)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BB4: 39종의 PC1 이 분산 66.8% 지배. D03 이 PC1 과 겹치면 결합은 D03 단독의 재탕이다.
##  측정: 월별로 39종 Z 행렬의 PC1 점수를 구하고 D03 Z 와의 spearman |rho| 를 낸다(월 중앙값).
##   ★D03_EWMA 가 39종 목록에 있으면 **제외한 38종으로 PC1 을 만든다**(자기 자신 포함 시 순환).
##   BE1 독립: |rho| 중앙값 < 0.50 → D03 은 부차 축, 결합 EV 실재 → BB1 착수
##   BE2 중복: |rho| >= 0.70 → 결합은 재탕, 경로 닫힘
##   BE3 중간: 0.50~0.70
##  ★성과 측정 없음. 구조 진단만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
INV <- S[shape == "INVERTED"]$Factor_Name
cat(sprintf("[INVERTED] %d종 · D03_EWMA 포함? %s\n", length(INV), "D03_EWMA" %in% INV))
OTH <- setdiff(INV, "D03_EWMA")
NEED <- unique(c(OTH, "D03_EWMA"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
liq <- as.data.table(P$liq); ret <- as.data.table(P$ret)
ds_all <- sort(unique(ret$Date)); ds <- ds_all[seq(1, length(ds_all), by = 6L)]
ds <- ds[ds >= as.Date("2008-01-01")]
cat(sprintf("[표본] %d개월\n", length(ds)))

rho <- numeric(0); shr <- numeric(0)
for (dt in ds) {
  z <- try(load_month_factors(as.Date(dt), factor_names = NEED), silent = TRUE)
  if (inherits(z, "try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  L <- liq[Date == dt, .(Ticker, adv)]
  z <- merge(z, L, by = "Ticker", all.x = TRUE)[is.na(adv) | adv >= 2e8]
  W <- dcast(z, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  if (!("D03_EWMA" %in% names(W))) next
  d03 <- W$D03_EWMA
  M <- as.matrix(W[, intersect(OTH, names(W)), with = FALSE])
  ok <- !is.na(d03) & rowSums(is.na(M)) == 0L
  M <- M[ok, , drop = FALSE]; d03 <- d03[ok]
  if (nrow(M) < 60L || ncol(M) < 5L) next
  pc <- prcomp(M, center = TRUE, scale. = TRUE)
  s <- pc$sdev^2; shr <- c(shr, s[1]/sum(s))
  rho <- c(rho, suppressWarnings(cor(d03, pc$x[,1], method = "spearman")))
}
if (!length(rho)) { cat("★산출 0 — 정지 신호\n"); quit(status=0) }
ar <- abs(rho)
cat(sprintf("\n월 %d · |rho(D03, PC1)| 중앙값 = **%.3f** · 평균 %.3f · 5~95%% %.3f~%.3f\n",
            length(ar), median(ar), mean(ar), quantile(ar,0.05), quantile(ar,0.95)))
cat(sprintf("PC1 분산비(38종) 중앙값 = %.3f\n", median(shr)))
m <- median(ar)
verdict <- { if (m < 0.50) "BE1_INDEPENDENT" else if (m >= 0.70) "BE2_REDUNDANT" else "BE3_MID" }
cat(sprintf("\n판정: %s\n★성과 측정 없음\n", verdict))
write_json(list(verdict=verdict, n_months=length(ar), rho_median=median(ar),
                rho_mean=mean(ar), pc1_share_median=median(shr)),
           file.path(OUT,"bd1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
