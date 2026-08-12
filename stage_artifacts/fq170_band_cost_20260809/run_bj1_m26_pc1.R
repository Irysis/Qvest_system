## BJ1 — M26~PC1(MONOTONE) 미측정 수리
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BH2 에서 M26~PC1 이 NA(미측정)였다. 원인 = '13팩터 전부 non-NA' 엄격 교집합 x M26 좁은 커버리지.
##  수리 = 커버리지 상위 8종으로 축소한 PC1 + pairwise 상관. M01 도 같은 조건에서 재측정(대조).
##   BK1 지배: M26~PC1 >= 0.70 → '내 5재료 = 각 계열 대표' 가설 강화
##   BK2 비지배: < 0.50 → M26 은 MONOTONE 축의 부차 재료. 가설 약화
##   BK3 중간
##  ★성과 측정 없음. M01 재측정치가 BH2 의 0.886 과 크게 다르면 축소 자체가 결과를 바꾼 것이므로
##    그 사실을 먼저 보고한다(양성 대조 역할).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
MON <- S[shape == "MONOTONE_TOP"]$Factor_Name
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
liq <- as.data.table(P$liq)
ds <- sort(unique(B[!is.na(M26_Revenue_Mom)]$Date)); ds <- ds[seq(1,length(ds),by=6L)]
ds <- ds[ds >= as.Date("2008-01-01")]

# 1) 커버리지 census → 상위 8종 선정 (사전 규칙: 평균 non-NA 종목수 내림차순)
cov <- data.table(Factor_Name = MON, n = 0L)
for (dt in head(ds, 8L)) {
  z <- try(load_month_factors(as.Date(dt), factor_names = MON), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned), .N, by=Factor_Name]
  cov <- merge(cov, z, by="Factor_Name", all.x=TRUE); cov[is.na(N), N := 0L]
  cov[, n := n + N][, N := NULL]
}
TOP8 <- cov[order(-n)][1:8]$Factor_Name
cat("[커버리지 상위 8종]", paste(TOP8, collapse=", "), "\n")

r26 <- numeric(0); r01 <- numeric(0); nk <- numeric(0)
for (dt in ds) {
  z <- try(load_month_factors(as.Date(dt), factor_names = TOP8), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  L <- liq[Date == dt, .(Ticker, adv)]
  z <- merge(z, L, by="Ticker", all.x=TRUE)[is.na(adv) | adv >= 2e8]
  W <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  my <- B[Date == dt, .(Ticker, M26_Revenue_Mom, M01_PATHQ)]
  W <- merge(W, my, by="Ticker")
  fac <- intersect(TOP8, names(W))
  M <- as.matrix(W[, fac, with=FALSE])
  ok <- rowSums(is.na(M)) == 0L
  M <- M[ok,,drop=FALSE]; m26 <- W$M26_Revenue_Mom[ok]; m01 <- W$M01_PATHQ[ok]
  if (nrow(M) < 60L || ncol(M) < 4L) next
  nk <- c(nk, sum(!is.na(m26)))
  p1 <- prcomp(M, center=TRUE, scale.=TRUE)$x[,1]
  if (sum(!is.na(m26)) > 50L) r26 <- c(r26, suppressWarnings(cor(m26, p1, method="spearman", use="complete.obs")))
  if (sum(!is.na(m01)) > 50L) r01 <- c(r01, suppressWarnings(cor(m01, p1, method="spearman", use="complete.obs")))
}
cat(sprintf("\n유효 M26 관측 중앙값 = %.0f (문턱 50) · 측정 성공 월 %d/%d\n",
            median(nk), length(r26), length(ds)))
if (!length(r26)) { cat("★여전히 0 — 정지 신호. 커버리지 축소로도 해결 안 됨\n"); quit(status=0) }
cat(sprintf("M26 ~ PC1(TOP8) |rho| 중앙값 = **%.3f**\n", median(abs(r26))))
cat(sprintf("M01 ~ PC1(TOP8) |rho| 중앙값 = %.3f  (BH2 전체13 판: 0.886 — 대조)\n", median(abs(r01))))
m <- median(abs(r26))
verdict <- { if (m >= 0.70) "BK1_DOMINANT" else if (m < 0.50) "BK2_SECONDARY" else "BK3_MID" }
cat(sprintf("\n판정: %s\n★성과 측정 없음\n", verdict))
write_json(list(verdict=verdict, m26_pc1=m, m01_pc1=median(abs(r01)),
                m01_pc1_bh2_full13=0.886, n_months=length(r26), top8=TOP8),
           file.path(OUT,"bj1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
