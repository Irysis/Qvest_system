## WT-D20260822_008 (FQ-246 NP2) P8 — 고판별성 부분표본 후속 (★탐색적 · 사전등록 게이트 아님)
## 목적: P7 에서 raw 2/8 이 나온 부분표본이 '정보' 인지 '적중률만 오르고 가치는 없는 것' 인지 분리.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_008"
P1 <- readRDS(file.path(OUT,"p1_parity.rds")); P7 <- readRDS(file.path(OUT,"p7_falsification.rds"))
K<-P1$K; NM<-P1$NM; RBF<-P1$ret_by_factor; DIRS<-P1$DIRS; AM<-P1$AM; ret_best<-P1$ret_best
marg <- P7$marg; hi <- marg >= median(marg, na.rm=TRUE); idxhi <- which(hi)
cat(sprintf("고판별성 부분표본 n = %d (마진 중앙 이상)\n", length(idxhi)))

selval_sub <- function(am, idx) vapply(idx, function(m){
  if (is.na(am[m])) return(NA_real_); b <- RBF[m,]; ok <- is.finite(b)
  RBF[m, am[m]] - mean(b[ok]) }, 0)
set.seed(20260825L); NPERM <- 2000L
perm_hi <- vapply(seq_len(NPERM), function(i){ am <- sample.int(K, NM, replace=TRUE)
  v <- selval_sub(am, idxhi); mean(v[is.finite(v)])*12*100 }, 0)
SUB <- rbindlist(lapply(names(DIRS), function(nmd){ am <- AM[[nmd]]
  v <- selval_sub(am, idxhi); v <- v[is.finite(v)]; ann <- mean(v)*12*100
  ii <- idxhi[!is.na(am[idxhi])]
  data.table(criterion=nmd, n=length(ii), hit=mean(am[ii]==ret_best[ii]),
    hit_p=binom.test(sum(am[ii]==ret_best[ii]), length(ii), p=1/K, alternative="greater")$p.value,
    selval_ann_pct=ann, selval_t=.nw_t_mean(v,lag=3L),
    perm_z=(ann-mean(perm_hi))/sd(perm_hi)) }))
setorder(SUB, -hit)
print(SUB[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
cat(sprintf("\n순열 귀무(고판별성 부분표본): 평균 %+.4f · sd %.4f · 양측 MDE %.4f %%p/yr\n",
            mean(perm_hi), sd(perm_hi), 1.96*sd(perm_hi)))
cat(sprintf("★적중 raw-통과 %d/8 · 선택가치 순열-유의 %d/8 · **양쪽 동시 통과 %d/8**\n",
            sum(SUB$hit_p<0.05), sum(abs(SUB$perm_z)>=1.96),
            sum(SUB$hit_p<0.05 & SUB$perm_z>=1.96)))
top <- SUB[1]
cat(sprintf("★최고 적중 %s: hit %.5f (p %.4f) 인데 선택가치 %+.4f %%p/yr (perm z %.3f)\n",
            top$criterion, top$hit, top$hit_p, top$selval_ann_pct, top$perm_z))
cat("  ⇒ 적중률과 선택가치가 같은 부분표본에서도 어긋나면, 부분표본 적중은 '정보' 가 아니라\n")
cat("    분포 꼭짓점 근처의 라벨 우연으로 읽어야 한다(탐색적 관측 — 사전등록 게이트 아님).\n")

## 다중검정 기대치 대조 (부분표본 8검정)
cat(sprintf("\n[다중성] raw alpha=0.05 · 8검정 기대 통과 %.2f건 · 관측 %d건 · P(>=관측 | 귀무) = %.4f\n",
            8*0.05, sum(SUB$hit_p<0.05), 1-pbinom(sum(SUB$hit_p<0.05)-1, 8, 0.05)))
cat(sprintf("[다중성] Bonferroni(8) alpha=%.5f ⇒ 통과 %d/8\n", 0.05/8, sum(SUB$hit_p < 0.05/8)))

saveRDS(list(SUB=SUB, perm_hi=perm_hi, idxhi=idxhi), file.path(OUT,"p8_subsample_followup.rds"))
cat("\n[saved] p8_subsample_followup.rds\nOK\n")
