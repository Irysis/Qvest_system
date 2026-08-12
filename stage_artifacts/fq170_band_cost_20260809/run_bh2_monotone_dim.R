## BH2 — MONOTONE_TOP 14종 구조 (3형태 x 독립차원 표 완성)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BB4/BD1: INVERTED 39 = PC1 0.668 지배 1축(내 D03 과 rho 0.959)
##  BF2:     HUMP 65 = PC1 0.253, 유효차원 22, 클러스터 41 (내 Q01 비지배 0.276)
##  ⇒ MONOTONE_TOP 14 를 같은 방식으로 재 3형태 표를 닫는다. 내 재료 M26/M01 의 지배 여부도 함께.
##   BI1 다차원: PC1 < 0.50 → '다차원은 HUMP 고유' 가 아니라 'INVERTED 만 특이'
##   BI2 지배축: PC1 >= 0.60 → 'INVERTED·MONOTONE 은 1축, HUMP 만 다차원'
##   BI3 중간
##  ★성과 측정 없음. 구조 진단만. n=14 로 작아 PCA 안정성 한계를 병기한다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
MON <- S[shape == "MONOTONE_TOP"]$Factor_Name
cat(sprintf("[MONOTONE_TOP] %d종: %s\n", length(MON), paste(head(MON, 14), collapse=", ")))

B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
liq <- as.data.table(P$liq)
ds <- sort(unique(B[!is.na(M26_Revenue_Mom)]$Date)); ds <- ds[seq(1, length(ds), by = 6L)]
ds <- ds[ds >= as.Date("2008-01-01")]

cors <- list(); shr <- numeric(0); r26 <- numeric(0); r01 <- numeric(0)
for (dt in ds) {
  z <- try(load_month_factors(as.Date(dt), factor_names = MON), silent = TRUE)
  if (inherits(z, "try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  L <- liq[Date == dt, .(Ticker, adv)]
  z <- merge(z, L, by="Ticker", all.x=TRUE)[is.na(adv) | adv >= 2e8]
  W <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  my <- B[Date == dt, .(Ticker, M26_Revenue_Mom, M01_PATHQ)]
  W <- merge(W, my, by="Ticker")
  fac <- intersect(MON, names(W))
  M <- as.matrix(W[, fac, with=FALSE])
  ok <- rowSums(is.na(M)) == 0L
  M <- M[ok,,drop=FALSE]; m26 <- W$M26_Revenue_Mom[ok]; m01 <- W$M01_PATHQ[ok]
  if (nrow(M) < 60L || ncol(M) < 4L) next
  cors[[length(cors)+1L]] <- suppressWarnings(cor(M, method="spearman"))
  pc <- prcomp(M, center=TRUE, scale.=TRUE); s <- pc$sdev^2
  shr <- c(shr, s[1]/sum(s))
  if (sum(!is.na(m26)) > 50L) r26 <- c(r26, suppressWarnings(cor(m26, pc$x[,1], method="spearman", use="complete.obs")))
  if (sum(!is.na(m01)) > 50L) r01 <- c(r01, suppressWarnings(cor(m01, pc$x[,1], method="spearman", use="complete.obs")))
}
if (!length(cors)) { cat("★산출 0 — 정지 신호\n"); quit(status=0) }
nm <- Reduce(intersect, lapply(cors, colnames))
CB <- Reduce(`+`, lapply(cors, function(C) C[nm,nm]))/length(cors); diag(CB) <- 1
off <- CB[upper.tri(CB)]; CB[is.na(CB)] <- 0
ev <- pmax(eigen(CB, symmetric=TRUE)$values, 0); cum <- cumsum(ev)/sum(ev)
k7 <- length(unique(cutree(hclust(as.dist(1-abs(CB)), method="average"), h=0.3)))
p1 <- median(shr)
cat(sprintf("\n[MONOTONE_TOP %d종 · 월 %d]\n평균 |rho| = %.3f · |rho|>=0.7 비율 %.3f\n",
            length(nm), length(cors), mean(abs(off), na.rm=TRUE), mean(abs(off)>=0.7, na.rm=TRUE)))
cat(sprintf("PC1 분산비 = **%.3f** · 유효차원 80%% = %d · 90%% = %d · 클러스터 %d\n",
            p1, which(cum>=0.80)[1], which(cum>=0.90)[1], k7))
cat(sprintf("M26 ~ PC1 |rho| = %.3f · M01_PATHQ ~ PC1 |rho| = %.3f\n",
            median(abs(r26)), median(abs(r01))))
verdict <- { if (p1 < 0.50) "BI1_MULTIDIM" else if (p1 >= 0.60) "BI2_DOMINATED" else "BI3_MID" }
cat(sprintf("\n판정: %s\n⚠n=%d 로 작아 PCA 안정성 한계 병기\n★성과 측정 없음\n", verdict, length(nm)))

cat("\n=== 3형태 x 구조 표 ===\n")
cat("  형태           n    평균|rho|  PC1분산비  유효차원80%  클러스터  내재료~PC1\n")
cat(sprintf("  INVERTED      39     0.594      0.668         4          10      0.959 (D03)\n"))
cat(sprintf("  HUMP          65     0.151      0.253        22          41      0.276 (Q01)\n"))
cat(sprintf("  MONOTONE_TOP  %2d     %.3f      %.3f        %2d          %2d      %.3f (M26)\n",
            length(nm), mean(abs(off), na.rm=TRUE), p1, which(cum>=0.80)[1], k7, median(abs(r26))))
write_json(list(verdict=verdict, n=length(nm), pc1_share=p1, eff80=which(cum>=0.80)[1],
                clusters=k7, m26_pc1=median(abs(r26)), m01_pc1=median(abs(r01))),
           file.path(OUT,"bh2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
