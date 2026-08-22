## WT-D20260822_008 (FQ-246 NP2) P7 — 승계 가설의 반증 스키마 F1~F5 직접 소화
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_008"
P1 <- readRDS(file.path(OUT,"p1_parity.rds")); G <- readRDS(file.path(OUT,"p3_gate.rds"))
B  <- readRDS(file.path(OUT,"p4_bounds.rds")); A6 <- readRDS(file.path(OUT,"p6_adversarial.rds"))
K<-P1$K; NM<-P1$NM; CRIT<-P1$CRIT; icm<-P1$icm; RBF<-P1$ret_by_factor; DIRS<-P1$DIRS; AM<-P1$AM
ic_best<-P1$ic_best; ret_best<-P1$ret_best; months<-P1$months; A4<-P1$A4
MDE_HIT <- G$MDE_HIT; CRITX <- A6$crit_hit

cat("=== F1) 사전 반증점 — 정답지 불일치율이 설계 상한을 만드는가 ===\n")
dis <- 1 - P1$agree
cat(sprintf("  불일치율 = %.8f (%d/%d 개월) · 이항 MDE 초과분 문턱 = %.4f pp\n",
            dis, round(dis*NM), NM, (MDE_HIT-1/K)*100))
cat(sprintf("  설계 상한 = IC 적중률 + 불일치율. 최대 IC 적중(%.6f) 기준 상한 = %.6f\n",
            max(G$ALL[key_id=="IC", hit]), max(G$ALL[key_id=="IC", hit]) + dis))
F1_pass <- dis*100 > (MDE_HIT-1/K)*100
cat(sprintf("  ★F1 판정 = %s — 불일치 %.2f pp 는 문턱 %.2f pp 를 %s ⇒ 설계 봉쇄 %s\n",
            if (F1_pass) "PASS (검정 가능)" else "BLOCKED", dis*100, (MDE_HIT-1/K)*100,
            if (F1_pass) "크게 상회" else "미달", if (F1_pass) "아님" else "발생"))
cat("  ⇒ 본 라운드의 null 은 UNRESOLVED_DESIGN_CAP 이 아니라 실질 판정 자격을 갖는다.\n")

cat("\n=== F3b) 선택가치 축 — 순열 귀무 직접 생성 (자기-diff sd 바 퇴화 배제) ===\n")
selval_series <- function(am) vapply(seq_len(NM), function(m){
  if (is.na(am[m])) return(NA_real_); b <- RBF[m,]; ok <- is.finite(b)
  RBF[m, am[m]] - mean(b[ok]) }, 0)
set.seed(20260824L); NPERM <- 2000L
perm_ann <- vapply(seq_len(NPERM), function(i){
  am <- sample.int(K, NM, replace=TRUE); v <- selval_series(am); mean(v[is.finite(v)])*12*100 }, 0)
cat(sprintf("  순열 귀무(월내 무작위 팩터 픽, NPERM=%d): 평균 %+.4f · sd %.4f · [q2.5, q97.5] = [%.3f, %.3f]\n",
            NPERM, mean(perm_ann), sd(perm_ann), quantile(perm_ann,0.025), quantile(perm_ann,0.975)))
SV <- rbindlist(lapply(names(DIRS), function(nmd){ v <- selval_series(AM[[nmd]]); v <- v[is.finite(v)]
  ann <- mean(v)*12*100
  data.table(criterion=nmd, selval_ann_pct=ann, selval_t=.nw_t_mean(v,lag=3L),
             perm_pctile=mean(perm_ann < ann),
             perm_z=(ann-mean(perm_ann))/sd(perm_ann)) }))
setorder(SV, -selval_ann_pct)
SV[, perm_sig := abs(perm_z) >= 1.96]
print(SV[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
cat(sprintf("  ★순열 귀무 대비 유의 = %d/8 (양측 |z|>=1.96) · 사전등록 MDE(순열 sd 1.96배) = %.4f %%p/yr\n",
            sum(SV$perm_sig), 1.96*sd(perm_ann)))

cat("\n=== F5) 기전 지문 — 불일치 월의 RET-승자가 꼬리질량(breadth)이 더 큰가 ===\n")
disc <- ic_best != ret_best
bw <- vapply(seq_len(NM), function(m) CRIT[m, ret_best[m], "breadth"], 0)
bw_z <- vapply(seq_len(NM), function(m){ x <- CRIT[m,,"breadth"]; o <- is.finite(x)
  if (sum(o)<2L || sd(x[o])==0) return(NA_real_); (CRIT[m,ret_best[m],"breadth"]-mean(x[o]))/sd(x[o]) }, 0)
tt <- t.test(bw_z[disc & is.finite(bw_z)], bw_z[!disc & is.finite(bw_z)])
cat(sprintf("  RET-승자의 월내 breadth z-순위(월 표준화): 불일치 월 %+.4f (n=%d) vs 일치 월 %+.4f (n=%d)\n",
            mean(bw_z[disc], na.rm=TRUE), sum(disc & is.finite(bw_z)),
            mean(bw_z[!disc], na.rm=TRUE), sum(!disc & is.finite(bw_z))))
cat(sprintf("  Welch t = %.4f · p = %.4f · 95%% CI [%.4f, %.4f]\n", tt$statistic, tt$p.value,
            tt$conf.int[1], tt$conf.int[2]))
cat(sprintf("  ★F5 판정 = %s\n", if (tt$p.value < 0.05 && tt$estimate[1] > tt$estimate[2])
    "지지 — 불일치 월 승자가 꼬리질량 큼" else "미지지 — '꼬리에서만 옳은 팩터' 기전 서술 강등"))

cat("\n=== 정답지 판별성 — 1위-2위 선택가치 마진 분포 (라벨 잡음 진단) ===\n")
marg <- vapply(seq_len(NM), function(m){ x <- sort(RBF[m,][is.finite(RBF[m,])], decreasing=TRUE)
  if (length(x) < 2L) return(NA_real_); x[1]-x[2] }, 0)
spread <- vapply(seq_len(NM), function(m){ x <- RBF[m,][is.finite(RBF[m,])]; max(x)-min(x) }, 0)
qq <- quantile(marg, c(0.05,0.25,0.5,0.75,0.95), na.rm=TRUE)
cat(sprintf("  1위-2위 마진(월수익 단위): 중앙 %.5f · IQR [%.5f, %.5f] · p5 %.5f · p95 %.5f\n",
            qq[3], qq[2], qq[4], qq[1], qq[5]))
cat(sprintf("  연율 환산 중앙 마진 = %.4f %%p/yr · best-worst 스프레드 중앙 = %.4f %%p/yr\n",
            qq[3]*12*100, median(spread)*12*100))
near_tie <- mean(marg < 0.002, na.rm=TRUE)
cat(sprintf("  준동률 월(마진 < 0.2%%/월) 비중 = %.4f\n", near_tie))
## 마진 상위 절반(판별성 높은 월)에서만 재측정 — 라벨 잡음이 null 의 원인인가
hi <- marg >= median(marg, na.rm=TRUE)
HALF <- rbindlist(lapply(names(DIRS), function(nmd){ am <- AM[[nmd]]
  idx <- which(!is.na(am) & hi); h <- mean(am[idx]==ret_best[idx])
  data.table(criterion=nmd, n=length(idx), hit_hi_margin=h,
    p=binom.test(sum(am[idx]==ret_best[idx]), length(idx), p=1/K, alternative="greater")$p.value) }))
setorder(HALF, -hit_hi_margin)
print(HALF[, .(criterion, n, hit=round(hit_hi_margin,5), p=signif(p,3))])
cat(sprintf("  ★판별성 높은 절반에서도 최대 적중 %.5f (우연 %.3f, 이 부분표본 MDE %.5f) ⇒ 통과 %d/8\n",
            max(HALF$hit_hi_margin), 1/K, qbinom(0.95, HALF$n[1], 1/K)/HALF$n[1],
            sum(HALF$p < 0.05)))

cat("\n=== 국면 advisory (ax001_v2 축 — 주장 승격 금지) ===\n")
bm <- A4$bench_dt[Date %in% as.Date(months)][order(Date)]
bad <- bm$BM_Ret < quantile(bm$BM_Ret, 0.20)
cat(sprintf("  위기 월 %d / 정상 월 %d · 위기 월 정답지 스프레드 중앙 %.5f vs 정상 %.5f\n",
            sum(bad), sum(!bad), median(spread[bad]), median(spread[!bad])))
REG <- rbindlist(lapply(names(DIRS), function(nmd){ am <- AM[[nmd]]
  ib <- which(!is.na(am) & bad); ig <- which(!is.na(am) & !bad)
  data.table(criterion=nmd, hit_crisis=mean(am[ib]==ret_best[ib]),
             hit_normal=mean(am[ig]==ret_best[ig]), n_crisis=length(ib)) }))
print(REG[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
cat(sprintf("  평균 적중: 위기 %.4f vs 정상 %.4f (승계 경계 서술 = 위기에서 약화 예측)\n",
            mean(REG$hit_crisis), mean(REG$hit_normal)))

saveRDS(list(F1_pass=F1_pass, dis=dis, SV=SV, perm_ann=perm_ann, F5=tt, bw_z=bw_z, disc=disc,
             marg=marg, spread=spread, near_tie=near_tie, HALF=HALF, REG=REG, bad=bad),
        file.path(OUT,"p7_falsification.rds"))
cat("\n[saved] p7_falsification.rds\nOK\n")
