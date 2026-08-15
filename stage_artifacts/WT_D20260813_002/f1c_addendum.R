## f1c_addendum.R — F1 진단 보완 3건 (판정 변경 불가)
##  (A1) D3 의 recall 0.000 이 정보인가 표본 부족인가 — n_on 실측
##  (A2) D1 부산물 정량화 — 인과 VOL 이 전표본-적합 MSM 을 이기는가 (부트스트랩)
##  (A3) VOL 의 MSM 대비 증분 + 부기간
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_002")
LG <- new.env(parent = globalenv())
sys.source("02_Infrastructure/contracts/label_eligibility_gate.R", envir = LG)
D <- as.data.table(readRDS(file.path(OUT, "f1_panel.rds")))
auc <- function(s, y) { y <- as.logical(y); ok <- is.finite(s); s <- s[ok]; y <- y[ok]
  if (sum(y) < 2 || sum(!y) < 2) return(NA_real_)
  r <- rank(s, ties.method="average"); (sum(r[y]) - sum(y)*(sum(y)+1)/2)/(sum(y)*sum(!y)) }

## A1 — calm 부분집합에서 TAIL top20% 가 실제 몇 달이나 켜졌나
S <- D[msm_pct < 0.80]
g <- LG$label_eligibility(S$tail_pct >= 0.80, S$evt_A)
cat(sprintf("[A1] calm n=%d  TAIL top20%% 발화 n_on=%d  그중 사건 %d  base_rate=%.4f\n",
            g$n, g$n_on, round(g$recall * g$n_on), g$base_rate))
## 발화가 희소하면 recall 0 은 정보가 아니라 표본 — 관대한 문턱(상위 35%)도 병기
g35 <- LG$label_eligibility(S$tail_pct >= 0.65, S$evt_A)
cat(sprintf("[A1] 관대 문턱(top35%%): n_on=%d recall=%.3f base=%.3f lift=%.2fx p=%.4f %s\n",
            g35$n_on, g35$recall, g35$base_rate, g35$lift, g35$fisher_p, g35$verdict))

## A2 — VOL vs MSM 부트스트랩
set.seed(20260813L)
bboot <- function(pa, pb, y, B=2000L, bl=6L) { n <- length(y); nb <- ceiling(n/bl); st <- seq_len(max(1L,n-bl+1L))
  v <- vapply(seq_len(B), function(b) { idx <- unlist(lapply(sample(st, nb, TRUE), function(s) s:(s+bl-1L)))[seq_len(n)]
    idx <- idx[idx <= n & !is.na(idx)]; yy <- y[idx]
    if (sum(yy) < 3 || sum(!yy) < 3) return(NA_real_); auc(pa[idx], yy) - auc(pb[idx], yy) }, numeric(1))
  v[is.finite(v)] }
bb <- bboot(D$VOL, D$MSM, D$evt_A)
cat(sprintf("[A2] VOL - MSM dAUC = %.4f  P(d>0)=%.3f  CI90=[%.4f, %.4f]\n",
            auc(D$VOL,D$evt_A)-auc(D$MSM,D$evt_A), mean(bb>0), quantile(bb,0.05), quantile(bb,0.95)))
bt <- bboot(D$VOL, D$TAIL, D$evt_A)
cat(sprintf("[A2] VOL - TAIL dAUC = %.4f  P(d>0)=%.3f  CI90=[%.4f, %.4f]\n",
            auc(D$VOL,D$evt_A)-auc(D$TAIL,D$evt_A), mean(bt>0), quantile(bt,0.05), quantile(bt,0.95)))

## A3 — VOL 의 MSM 대비 증분 (expanding OLS 잔차, 인과)
rv <- rep(NA_real_, nrow(D))
for (i in 30:nrow(D)) { f <- stats::lm(VOL ~ MSM, data=D[1:i]); rv[i] <- D$VOL[i] - stats::predict(f, newdata=D[i]) }
cat(sprintf("[A3] VOL_resid_MSM AUC = %.4f  (0.5 = 증분 없음)\n", auc(rv, D$evt_A)))
subv <- D[, .(n=.N, n_evt=sum(evt_A), auc_VOL=auc(VOL,evt_A), auc_MSM=auc(MSM,evt_A),
              auc_TAIL=auc(TAIL,evt_A)), by=sub]
cat("[A3] 부기간 (기술통계):\n"); print(subv)

write_json(list(
  wt_id="WT-D20260813_002", stage="F1c_addendum", metric_type="mechanism_observation_posthoc",
  A1_calm_operating_point=list(n=g$n, n_on_top20=g$n_on, recall_top20=g$recall,
     base_rate=g$base_rate, verdict_top20=g$verdict,
     n_on_top35=g35$n_on, recall_top35=g35$recall, lift_top35=g35$lift,
     p_top35=g35$fisher_p, verdict_top35=g35$verdict),
  A2_vol_vs_state=list(
     d_auc_vol_msm=auc(D$VOL,D$evt_A)-auc(D$MSM,D$evt_A), p_gt0_vol_msm=mean(bb>0),
     ci90_vol_msm=as.numeric(quantile(bb,c(0.05,0.95))),
     d_auc_vol_tail=auc(D$VOL,D$evt_A)-auc(D$TAIL,D$evt_A), p_gt0_vol_tail=mean(bt>0),
     ci90_vol_tail=as.numeric(quantile(bt,c(0.05,0.95)))),
  A3_incremental=list(vol_resid_msm_auc=auc(rv,D$evt_A), subperiod=subv)
), file.path(OUT,"f1c_addendum.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("\n[done] f1c_addendum.json written\n")
