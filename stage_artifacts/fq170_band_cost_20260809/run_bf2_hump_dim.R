## BF2 — HUMP 67종의 독립 차원 + Q01 이 그 축을 지배하는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BD1: INVERTED 39종은 PC1 지배축 하나이고 내 D03 과 rho 0.959 → 결합 경로 폐쇄.
##  ⇒ 같은 진단을 HUMP 67종에 건다. 병렬 아크(HUMP 밴드 소비 확립, Q01_EB)의 일반화 여지가 갈린다.
##  측정: (i) 평균 |rho| · PC1 분산비 · 유효차원(80%/90%) · |rho|>=0.7 클러스터 수
##        (ii) rho(Q01_EB[내 패널], PC1(HUMP 67)) — 근친(Q01 계열 DB 팩터) 포함/제외 양판
##   BG1 다차원: PC1 분산비 < 0.50 ∧ Q01~PC1 |rho| < 0.50 → 병렬 아크 결합 경로 열림
##   BG2 지배축: PC1 >= 0.60 ∨ Q01~PC1 >= 0.70 → INVERTED 와 같은 구조, 결합 폐쇄
##   BG3 중간
##  ★성과 측정 없음. 구조 진단만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
HUM <- S[shape == "HUMP"]$Factor_Name
cat(sprintf("[HUMP] %d종 · Q 로 시작: %s\n", length(HUM),
            paste(head(grep("^Q", HUM, value=TRUE), 8), collapse=", ")))

B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
liq <- as.data.table(P$liq)
ds <- sort(unique(B[!is.na(Q01_EB)]$Date)); ds <- ds[seq(1, length(ds), by = 6L)]
ds <- ds[ds >= as.Date("2008-01-01")]
cat(sprintf("[표본] %d개월\n", length(ds)))

cors <- list(); rq <- numeric(0); rq2 <- numeric(0); shr <- numeric(0)
for (dt in ds) {
  z <- try(load_month_factors(as.Date(dt), factor_names = HUM), silent = TRUE)
  if (inherits(z, "try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  L <- liq[Date == dt, .(Ticker, adv)]
  z <- merge(z, L, by = "Ticker", all.x = TRUE)[is.na(adv) | adv >= 2e8]
  W <- dcast(z, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  my <- B[Date == dt & !is.na(Q01_EB), .(Ticker, Q01_EB)]
  W <- merge(W, my, by = "Ticker")
  fac <- intersect(HUM, names(W))
  M <- as.matrix(W[, fac, with = FALSE])
  ok <- !is.na(W$Q01_EB) & rowSums(is.na(M)) == 0L
  M <- M[ok, , drop = FALSE]; qv <- W$Q01_EB[ok]
  if (nrow(M) < 60L || ncol(M) < 5L) next
  C <- suppressWarnings(cor(M, method="spearman")); cors[[length(cors)+1L]] <- C
  pc <- prcomp(M, center=TRUE, scale.=TRUE); s <- pc$sdev^2
  shr <- c(shr, s[1]/sum(s))
  rq <- c(rq, suppressWarnings(cor(qv, pc$x[,1], method="spearman")))
  kin <- grep("^Q01", colnames(M), value=TRUE)
  M2 <- M[, setdiff(colnames(M), kin), drop=FALSE]
  if (ncol(M2) >= 5L) rq2 <- c(rq2, suppressWarnings(
    cor(qv, prcomp(M2, center=TRUE, scale.=TRUE)$x[,1], method="spearman")))
}
if (!length(cors)) { cat("★산출 0 — 정지 신호\n"); quit(status=0) }
nm <- Reduce(intersect, lapply(cors, colnames))
CB <- Reduce(`+`, lapply(cors, function(C) C[nm,nm]))/length(cors); diag(CB) <- 1
off <- CB[upper.tri(CB)]; CB[is.na(CB)] <- 0
ev <- pmax(eigen(CB, symmetric=TRUE)$values, 0); cum <- cumsum(ev)/sum(ev)
k7 <- length(unique(cutree(hclust(as.dist(1-abs(CB)), method="average"), h=0.3)))
cat(sprintf("\n[HUMP %d종 · 월 %d]\n평균 |rho| = %.3f · |rho|>=0.7 비율 %.3f\n",
            length(nm), length(cors), mean(abs(off), na.rm=TRUE), mean(abs(off)>=0.7, na.rm=TRUE)))
cat(sprintf("PC1 분산비 = **%.3f** · 유효차원 80%% = %d · 90%% = %d · 클러스터 %d\n",
            median(shr), which(cum>=0.80)[1], which(cum>=0.90)[1], k7))
cat(sprintf("Q01_EB ~ PC1(전체) |rho| 중앙값 = %.3f\n", median(abs(rq))))
if (length(rq2)) cat(sprintf("Q01_EB ~ PC1(Q01 계열 제외) |rho| 중앙값 = %.3f\n", median(abs(rq2))))
p1 <- median(shr); qr <- median(abs(if (length(rq2)) rq2 else rq))
verdict <- { if (p1 < 0.50 && qr < 0.50) "BG1_MULTIDIM_OPEN"
             else if (p1 >= 0.60 || qr >= 0.70) "BG2_DOMINATED_CLOSED" else "BG3_MID" }
cat(sprintf("\n판정: %s\n★성과 측정 없음\n", verdict))
write_json(list(verdict=verdict, n=length(nm), pc1_share=p1, eff80=which(cum>=0.80)[1],
                eff90=which(cum>=0.90)[1], clusters=k7,
                q01_pc1=median(abs(rq)), q01_pc1_exkin=if(length(rq2)) median(abs(rq2)) else NA),
           file.path(OUT,"bf2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
