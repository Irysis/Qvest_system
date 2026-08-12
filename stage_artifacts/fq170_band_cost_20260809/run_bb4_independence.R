## BB4 — INVERTED 39종의 **실질 독립 차원** (결합 EV 의 전제)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AZ1 이 INVERTED 39종을 찾았으나 상위가 전부 vol/tail 계열이다 → 한 재료군의 여러 표현일 수 있다.
##  ★선례: 오늘 폐지 풀 라운드가 '명목 195 → 유효 독립 85'(최대 그룹 49개 동일벡터)를 실측했다.
##  측정: 39종의 월별 횡단면 Z 벡터 상관 → 평균 |rho| · PCA 유효차원(분산 90% 도달 성분수) ·
##        상관 0.7 이상 클러스터 수.
##   BC1 다차원: 유효차원 >= 5 → 결합 EV 유지, BB1 착수
##   BC2 저차원: 유효차원 <= 2 → 39종은 실질 1~2 재료. 결합 경로 좁아짐, D03 단독과 큰 차이 없음
##   BC3 중간: 3~4
##  ★성과 측정 없음. 구조 진단만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
INV <- S[shape == "INVERTED"][order(-ic)]$Factor_Name
cat(sprintf("[INVERTED] %d종\n", length(INV)))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
liq <- as.data.table(P$liq); ret <- as.data.table(P$ret)
ds_all <- sort(unique(ret$Date)); ds <- ds_all[seq(1, length(ds_all), by = 12L)]
ds <- ds[ds >= as.Date("2008-01-01")]
cat(sprintf("[표본] %d개월 (12개월 간격)\n", length(ds)))

cors <- list()
for (dt in ds) {
  z <- try(load_month_factors(as.Date(dt), factor_names = INV), silent = TRUE)
  if (inherits(z, "try-error")) next
  z <- as.data.table(z)[Factor_Name %in% INV & !is.na(Z_Score_Aligned)]
  L <- liq[Date == dt, .(Ticker, adv)]
  z <- merge(z, L, by = "Ticker", all.x = TRUE)[is.na(adv) | adv >= 2e8]
  W <- dcast(z, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  M <- as.matrix(W[, -1, with = FALSE])
  keep <- colSums(!is.na(M)) >= 60L
  M <- M[, keep, drop = FALSE]
  if (ncol(M) < 3L) next
  C <- suppressWarnings(cor(M, use = "pairwise.complete.obs", method = "spearman"))
  cors[[length(cors)+1L]] <- C
}
if (!length(cors)) { cat("★상관 산출 0 — 정지 신호. 로더 factor_names 인자 확인 필요\n"); quit(status=0) }
nm <- Reduce(intersect, lapply(cors, colnames))
cat(sprintf("[공통 팩터] %d종 · 월 %d\n", length(nm), length(cors)))
CB <- Reduce(`+`, lapply(cors, function(C) C[nm, nm])) / length(cors)
diag(CB) <- 1
off <- CB[upper.tri(CB)]
cat(sprintf("\n평균 |rho| = %.3f · 중앙값 %.3f · |rho|>=0.7 쌍 비율 %.3f\n",
            mean(abs(off), na.rm=TRUE), median(abs(off), na.rm=TRUE), mean(abs(off) >= 0.7, na.rm=TRUE)))
CB[is.na(CB)] <- 0
ev <- eigen(CB, symmetric = TRUE)$values; ev <- pmax(ev, 0)
cum <- cumsum(ev)/sum(ev)
eff90 <- which(cum >= 0.90)[1]; eff80 <- which(cum >= 0.80)[1]
cat(sprintf("PCA 유효차원: 80%% = %d · 90%% = %d (n=%d)\n", eff80, eff90, length(nm)))
cat(sprintf("PC1 분산비 = %.3f · PC1-3 누적 = %.3f\n", ev[1]/sum(ev), cum[3]))
hc <- hclust(as.dist(1 - abs(CB)), method = "average")
k7 <- length(unique(cutree(hc, h = 0.3)))   # |rho|>=0.7 군집
cat(sprintf("|rho|>=0.7 클러스터 수 = %d\n", k7))

verdict <- { if (eff90 >= 5L) "BC1_MULTIDIM" else if (eff90 <= 2L) "BC2_LOW_DIM" else "BC3_MID" }
cat(sprintf("\n판정: %s\n★성과 측정 없음 — 구조 진단만\n", verdict))
write_json(list(verdict=verdict, n=length(nm), mean_abs_rho=mean(abs(off), na.rm=TRUE),
                eff_dim_80=eff80, eff_dim_90=eff90, pc1_share=ev[1]/sum(ev), n_clusters=k7),
           file.path(OUT,"bb4_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
