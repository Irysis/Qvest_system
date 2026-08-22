## WT-D20260822_008 (FQ-246 NP2) P4 — 배제 구간 · 검출 바닥 · 정답지 3판 강건성 · 괴리 진단
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_008"
P1 <- readRDS(file.path(OUT,"p1_parity.rds")); G <- readRDS(file.path(OUT,"p3_gate.rds"))
PRE <- fromJSON(file.path(OUT,"PREREG.json"))
K <- P1$K; NM <- P1$NM; CRIT <- P1$CRIT; icm <- P1$icm; RBF <- P1$ret_by_factor
DIRS <- P1$DIRS; AM <- P1$AM; months <- P1$months; A4 <- P1$A4; Zl <- P1$Zl
ic_best <- P1$ic_best; ret_best <- P1$ret_best; TOPN <- P1$TOPN
ALL <- G$ALL; MDE_HIT <- G$MDE_HIT
a <- P1$agree; base_IC <- (1-a)/(K-1); slope <- a - base_IC

cat("################ (4-1) 정확 배제 구간 — 'null 이 무엇을 배제했나' ################\n")
CI <- ALL[key_id=="RET"][, {
  x <- round(hit*n); bt <- binom.test(x, n, p=1/K)
  .(criterion, n, hit, hits=x, ci_lo=bt$conf.int[1], ci_hi=bt$conf.int[2],
    ci_hi_1s=binom.test(x, n, p=1/K, alternative="less")$conf.int[2]) }, by=seq_len(nrow(ALL[key_id=="RET"]))]
CI[, `:=`(excess_hi_pp=(ci_hi-1/K)*100)]
setorder(CI, -hit)
print(CI[, .(criterion, hits, n, hit=round(hit,6), ci95=paste0("[",round(ci_lo,4),", ",round(ci_hi,4),"]"),
             ci_hi_1s=round(ci_hi_1s,4), excess_hi_pp=round(excess_hi_pp,2))])
cat(sprintf("\n★배제 서술: 어떤 기준도 h_RET > %.4f (최대 단측 95%% 상한) 를 지지하지 않는다.\n", max(CI$ci_hi_1s)))
cat(sprintf("  우연 = %.4f · 사전등록 MDE = %.6f · 관측 최대 적중 = %.6f (%s)\n",
            1/K, MDE_HIT, max(CI$hit), CI$criterion[which.max(CI$hit)]))

cat("\n################ (4-2) 검출 바닥 — 잡음 사다리로 게이트의 실효 하한 실측 ################\n")
set.seed(20260822L)
noise_add <- function(M, s) { S <- apply(M,1,function(x) sd(x[is.finite(x)]))
  M + matrix(rnorm(length(M)), nrow=nrow(M))*(S*s) }
amax <- function(M) apply(M,1,function(x){ x[!is.finite(x)] <- -Inf; which.max(x) })
LAD <- rbindlist(lapply(c(0,1,2,3,4,6,8,12,20,40), function(s) {
  reps <- rbindlist(lapply(1:20, function(r) { Mn <- if (s==0) RBF else noise_add(RBF,s)
    am <- amax(Mn); h <- mean(am==ret_best)
    rho <- vapply(seq_len(NM), function(m){ o <- is.finite(Mn[m,])&is.finite(RBF[m,])
      cor(rank(Mn[m,][o]), rank(RBF[m,][o])) },0)
    data.table(hit=h, p=binom.test(sum(am==ret_best),NM,p=1/K,alternative="greater")$p.value,
               rho=mean(rho), rho_t=.nw_t_mean(rho,lag=3L)) }))
  data.table(noise_sd_mult=s, hit=mean(reps$hit), p_median=median(reps$p),
             rho=mean(reps$rho), rho_t=mean(reps$rho_t),
             fire_rate=mean(reps$p < 0.05 | abs(reps$rho_t) >= 1.5)) }))
print(LAD[, lapply(.SD, function(x) if (is.numeric(x)) round(x,5) else x)])
floor_row <- LAD[fire_rate < 1][1]
cat(sprintf("\n★게이트 실효 검출 바닥: 잡음 %s 배까지 100%% 발화. 관측 기준의 적중 %.4f 는\n",
            if (nrow(LAD[fire_rate>=1])) max(LAD[fire_rate>=1, noise_sd_mult]) else NA, max(CI$hit)))
cat(sprintf("  잡음 %s 배 수준(적중 %.4f)보다 **낮다** ⇒ 게이트 무능이 아니라 기준 무정보.\n",
            LAD[which.min(abs(LAD$hit - max(CI$hit))), noise_sd_mult],
            LAD[which.min(abs(LAD$hit - max(CI$hit))), hit]))

cat("\n################ (4-3) 정답지 3판 — 비용-차감 소비면(RETNET) 강건성 ################\n")
## 소비면의 정직한 판 = net. 팩터별 월간 top-25 교체율로 15bps delta 과금 근사.
topset <- lapply(seq_len(NM), function(m) { Z <- Zl[[m]]$Z; tk <- Zl[[m]]$tick
  lapply(seq_len(K), function(k){ v <- Z[,k]; ok <- is.finite(v)
    if (sum(ok) < TOPN) return(character(0))
    tk[ok][order(v[ok], decreasing=TRUE)[seq_len(TOPN)]] }) })
turn <- matrix(NA_real_, NM, K)
for (m in 2:NM) for (k in seq_len(K)) { a1 <- topset[[m-1]][[k]]; a2 <- topset[[m]][[k]]
  if (length(a1)==0 || length(a2)==0) next
  turn[m,k] <- length(setdiff(a2,a1))/TOPN }
turn[1,] <- colMeans(turn, na.rm=TRUE)
RBFNET <- RBF - turn*2*0.0015
ret_best_net <- apply(RBFNET,1,function(x){x[!is.finite(x)] <- -Inf; which.max(x)})
cat(sprintf("월평균 팩터 top-25 교체율 = %.4f (연 회전 %.2f) · net 정답지가 gross 와 일치 %.6f\n",
            mean(turn,na.rm=TRUE), mean(turn,na.rm=TRUE)*12*2, mean(ret_best_net==ret_best)))
NETT <- rbindlist(lapply(names(DIRS), function(nmd) {
  am <- AM[[nmd]]; ok <- !is.na(am); idx <- which(ok)
  h <- mean(am[idx]==ret_best_net[idx])
  cn <- DIRS[[nmd]][[1]]; dec <- DIRS[[nmd]][[2]]
  rho <- vapply(seq_len(NM), function(m){ x <- CRIT[m,,cn]; y <- RBFNET[m,]
    o <- is.finite(x)&is.finite(y); if (sum(o)<3L||sd(x[o])==0) return(NA_real_)
    cor(rank(x[o]),rank(y[o])) },0); rr <- rho[is.finite(rho)]; if(!dec) rr <- -rr
  data.table(criterion=nmd, hit_net=h,
    p_net=binom.test(sum(am[idx]==ret_best_net[idx]), sum(ok), p=1/K, alternative="greater")$p.value,
    rho_net=mean(rr), rho_t_net=.nw_t_mean(rr,lag=3L)) }))
NETT <- merge(NETT, ALL[key_id=="RET", .(criterion, hit_gross=hit, rho_t_gross=rho_t)], by="criterion")
NETT[, d_hit_net_vs_gross := hit_net - hit_gross]
setorder(NETT, -hit_net)
print(NETT[, .(criterion, hit_gross=round(hit_gross,5), hit_net=round(hit_net,5),
               d=round(d_hit_net_vs_gross,5), p_net=signif(p_net,3),
               rho_t_gross=round(rho_t_gross,3), rho_t_net=round(rho_t_net,3))])
cat(sprintf("★net 정답지에서도 최대 적중 %.6f < MDE %.6f ⇒ 결론 불변 = %s\n",
            max(NETT$hit_net), MDE_HIT, max(NETT$hit_net) < MDE_HIT))

cat("\n################ (4-4) ★괴리 진단 — 적중률과 선택가치가 어긋난다 ################\n")
DIS <- ALL[key_id=="RET" & criterion %in% names(DIRS), .(criterion, hit, selval_ann_pct, selval_t)]
setorder(DIS, -hit)
print(DIS[, .(criterion, hit=round(hit,5), selval_ann_pct=round(selval_ann_pct,4), selval_t=round(selval_t,3))])
cat(sprintf("  cor(적중률, 선택가치) across 8 방향 = %+.4f (Pearson) / %+.4f (Spearman)\n",
            cor(DIS$hit, DIS$selval_ann_pct), cor(rank(DIS$hit), rank(DIS$selval_ann_pct))))
cat(sprintf("  최고 적중 %s: hit %.5f (우연 초과 +%.2f pp) 인데 선택가치 %+.4f %%p/yr (t %.3f)\n",
            DIS$criterion[1], DIS$hit[1], (DIS$hit[1]-0.2)*100, DIS$selval_ann_pct[1], DIS$selval_t[1]))
cat("  ★argmax 적중은 분포의 **한 점**이고 선택가치는 분포 **전체**다 — 같은 기준이 두 축에서 반대로 간다.\n")
sv_bonf <- qnorm(1-0.05/16)
cat(sprintf("  Bonferroni(8방향, 양측) |t| 문턱 = %.3f ⇒ 선택가치 축 통과 = %d/8\n",
            sv_bonf, sum(abs(DIS$selval_t) >= sv_bonf)))

cat("\n################ (4-5) 가설 판정 계산 ################\n")
n_pass_adj <- ALL[key_id=="RET" & criterion %in% names(DIRS) & pass_adj, .N]
n_pass_raw <- ALL[key_id=="RET" & criterion %in% names(DIRS) & pass_raw, .N]
n_pair_mat <- G$PAIR[criterion %in% names(DIRS) & key_swap_material, .N]
cat(sprintf("  RET 정답지 게이트 통과 (adjusted) = %d/8 · (raw) = %d/8\n", n_pass_adj, n_pass_raw))
cat(sprintf("  정답지 교체 paired 유의 = %d/8 (Δhit 양측 MDE %.6f, 관측 최대 |Δhit| %.6f)\n",
            n_pair_mat, G$MDE_D2S, max(abs(G$PAIR[criterion %in% names(DIRS), d_hit]))))
cat(sprintf("  ⇒ 가설 '기준이 잘못된 표적을 맞혔다' 판정 = %s\n",
            if (n_pass_adj==0 && n_pair_mat==0) "REJECTED (powered)" else "SUPPORTED/PARTIAL"))

saveRDS(list(CI=CI, LAD=LAD, NETT=NETT, DIS=DIS, turn=turn, RBFNET=RBFNET,
             ret_best_net=ret_best_net, n_pass_adj=n_pass_adj, n_pass_raw=n_pass_raw,
             n_pair_mat=n_pair_mat, base_IC=base_IC, slope=slope),
        file.path(OUT,"p4_bounds.rds"))
cat("\n[saved] p4_bounds.rds\nOK\n")
