#!/usr/bin/env Rscript
# =============================================================================
# p2_power_adversarial.R — p1 바에 대한 자가 적대검증 3렌즈
#
# p1 결과가 "필요/기대 = 0.19~0.21 (여유 5배)" 로 너무 쉽게 나왔다. 쉬운 답을 그대로
# 제출하지 않는다(answer-principles 자가체크). 바를 무너뜨릴 수 있는 3가지를 실측한다:
#
#  L1. sd 대체오류 — p1 은 **무작위** K=12 arm 의 diff sd 를 썼다. 실제 arm 은 상태성과로
#      *선택*된 로스터라 base 와 더 멀다 ⇒ diff sd 가 더 크고 바가 올라간다.
#  L2. ★PIT — P0 의 상태별 지속성(DOWN +0.462 등)은 **동월 bm** 로 상태를 정의했다.
#      실제 arm 은 결정시점에 그 달 bm 을 모른다. 상태라벨을 t-1 로 지연시키면
#      버킷 구성원이 바뀌고 천장이 무너진다. (국면 라벨 = 기지 병목, 2026-08-02)
#  L3. 다중검정 — arm 이 여럿인 sweep 이면 |t|>=2.0 자체가 틀린 문턱이다.
#
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p2_adv.log"), split = TRUE)
set.seed(20260809)
T_THR <- 2.0

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
M0 <- as.matrix(sub[, ..scrap_ok]); cov_m <- colSums(is.finite(M0)); keep <- which(cov_m >= 253)
rows <- complete.cases(M0[, keep, drop = FALSE])
M <- M0[rows, keep, drop = FALSE]; ids <- scrap_ok[keep]
bmv <- sub$bm[rows]; ymv <- sub$ym[rows]; n_all <- nrow(M)
C <- cor(M); diag(C) <- 0
hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[,1] < hi[,2], , drop = FALSE]
comp <- local({ par <- seq_len(ncol(M)); fnd <- function(x){ while(par[x]!=x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) { a<-fnd(hi[r,1]); b<-fnd(hi[r,2]); if(a!=b) par[b]<-a }
  vapply(seq_len(ncol(M)), fnd, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; idu <- ids[reps]; NU <- ncol(Mu)
dts <- as.Date(paste0(substr(ymv,1,4),"-",substr(ymv,5,6),"-01"))
Xu <- xts(Mu, order.by = dts)
pf <- function(x,w) as.numeric(Return.portfolio(x, weights=w, rebalance_on="months"))
base85 <- pf(Xu, rep(1/NU, NU))
A <- Mu - matrix(base85, n_all, NU)

st  <- ifelse(bmv <= -0.05, "DOWN", ifelse(bmv >= 0.05, "SURGE", "FLAT"))
stL <- c(NA, st[-n_all])                       # t-1 지연 라벨 (PIT)
cat(sprintf("=== [0] %d months  dedup=%d ===\n", n_all, NU))

## ---------------------------------------- 사전확인: elite 컬럼 NA 원인 (p1 미출력)
eu <- intersect(elite_ok, colnames(PAN))
E  <- as.matrix(sub[rows, ..eu]); nabad <- colSums(!is.finite(E))
cat(sprintf("[chk] ELITE %d개 중 결측보유 컬럼=%d (%s) → p1 에서 ELITE 행 미출력된 이유\n",
            length(eu), sum(nabad>0), paste(sprintf("%s:%d", eu[nabad>0], nabad[nabad>0]), collapse=", ")))

## ================================================== L1. 선택된 arm 의 diff sd
cat("\n=== [L1] 무작위 arm sd vs **선택된** arm sd (바의 sd 대체오류 점검) ===\n")
sel_roster <- function(mask, K=12L) order(colMeans(A[mask,,drop=FALSE]), decreasing=TRUE)[1:K]
l1 <- list()
for (s in c("DOWN","SURGE","FLAT")) {
  mask <- st == s
  selv <- sel_roster(mask); r <- pf(Xu[, selv, drop=FALSE], rep(1/12,12)); d <- r - base85
  sd_sel <- sd(d[mask]); mu_sel <- mean(d[mask]); nb_ <- sum(mask)
  l1[[s]] <- list(state=s, n=nb_, sd_selected_pct=100*sd_sel, mean_IS_pct=100*mu_sel,
                  required_pct_per_month=100*T_THR*sd_sel/sqrt(nb_),
                  t_IS=mu_sel/(sd_sel/sqrt(nb_)))
  cat(sprintf("  %-6s n=%3d  선택arm sd=%.3f%%/m  IS평균=%+.3f%%/m  IS t=%+.2f  필요=%.4f%%/m\n",
              s, nb_, 100*sd_sel, 100*mu_sel, mu_sel/(sd_sel/sqrt(nb_)), 100*T_THR*sd_sel/sqrt(nb_)))
}

## ================================================== L2. PIT: t-1 상태라벨
cat("\n=== [L2] ★PIT — 상태라벨 t-1 지연 시 버킷이 무엇이 되는가 ===\n")
tm <- table(prev = stL[-1], now = st[-1])
cat("  전이표 (행=st(t-1), 열=st(t)):\n"); print(tm)
for (s in c("DOWN","SURGE","FLAT")) {
  pr <- tm[s, ] / sum(tm[s, ])
  cat(sprintf("  P(st(t)=%-5s | st(t-1)=%-5s) = %.3f   ← 라벨 지속성\n", s, s, pr[[s]]))
}
persist <- vapply(c("DOWN","SURGE","FLAT"), function(s) tm[s,s]/sum(tm[s,]), numeric(1))

# 지연라벨 버킷에서의 IS 천장 + 그 버킷의 split-half 순위 지속성
sh_rho <- function(mask) {
  idxm <- which(mask); if (length(idxm) < 8) return(NA_real_)
  h <- idxm[1:floor(length(idxm)/2)]; g <- setdiff(idxm, h)
  suppressWarnings(cor(colMeans(A[h,,drop=FALSE]), colMeans(A[g,,drop=FALSE]), method="spearman"))
}
cat("\n  [재현 확인] 동월 라벨 split-half spearman (P0 §5 대조: DOWN+0.462 SURGE+0.498 FLAT-0.436)\n")
for (s in c("DOWN","SURGE","FLAT"))
  cat(sprintf("    %-6s rho=%+.3f (n=%d)\n", s, sh_rho(st==s), sum(st==s)))

cat("\n  [PIT 판본] t-1 지연 라벨 버킷\n")
l2 <- list()
for (s in c("DOWN","SURGE","FLAT")) {
  mask <- !is.na(stL) & stL == s
  nb_ <- sum(mask); rho <- sh_rho(mask)
  selv <- sel_roster(mask); r <- pf(Xu[, selv, drop=FALSE], rep(1/12,12)); d <- r - base85
  ceil <- mean(d[mask]); sdd <- sd(d[mask])
  req  <- T_THR*sdd/sqrt(nb_)
  exp_oos <- ceil * max(rho, 0, na.rm=TRUE)
  l2[[s]] <- list(state=paste0("lag1_", s), n=nb_, sd_pct=100*sdd, rho_splithalf=rho,
                  is_ceiling_pct=100*ceil, required_pct=100*req,
                  expected_oos_pct=100*exp_oos,
                  required_over_expected = if (is.finite(exp_oos) && exp_oos>0) req/exp_oos else Inf)
  cat(sprintf("    lag1_%-6s n=%3d  sd=%.3f%%/m  split-half rho=%+.3f  IS천장=%+.3f%%/m  필요=%.3f%%/m  기대OOS=%+.3f%%/m  필요/기대=%.2f\n",
              s, nb_, 100*sdd, rho, 100*ceil, 100*req, 100*exp_oos,
              l2[[s]]$required_over_expected))
}

## L2b. 실제로 PIT 규칙을 굴렸을 때의 상한 — 지연라벨로 상태별 IS로스터 스위칭 (전표본 지식)
cat("\n  [L2b] 지연라벨 상태-스위칭 전략의 **전표본-지식 상한** (OOS 아님, 상한임)\n")
W <- matrix(0, n_all, NU)
for (s in c("DOWN","SURGE","FLAT")) {
  m_now <- st == s                      # 로스터는 동월 상태로 최적화(=관대한 상한)
  selv  <- sel_roster(m_now)
  m_use <- !is.na(stL) & stL == s
  W[m_use, selv] <- 1/12
}
W[is.na(stL), ] <- 1/NU
Wx <- xts(W, order.by = dts)
rsw <- as.numeric(Return.portfolio(Xu, weights = Wx))
nsw <- min(length(rsw), length(base85))
dsw <- tail(rsw, nsw) - tail(base85, nsw)
cat(sprintf("    지연라벨 스위칭 상한: 평균 %+.4f%%/m  sd=%.3f%%/m  t=%+.2f  (n=%d)\n",
            100*mean(dsw), 100*sd(dsw), mean(dsw)/(sd(dsw)/sqrt(nsw)), nsw))
cat(sprintf("    (비교) 동월(오라클) 라벨 스위칭이 아니라 **지연** 라벨임. 이 값이 상한이고 OOS 는 이보다 낮다.\n"))

## ================================================== L3. 다중검정 문턱
cat("\n=== [L3] 다중검정 — arm 이 여럿이면 |t|>=2.0 은 틀린 문턱 ===\n")
for (ntr in c(1, 6, 20, 100, 400, 4000)) {
  tcrit <- qnorm(1 - 0.05/(2*ntr))
  emax  <- qnorm(1 - 1/(2*ntr+2))
  cat(sprintf("    n_trials=%4d → Bonferroni t=%.2f · 순수잡음 max|t| 기대=%.2f\n", ntr, tcrit, emax))
}
cat("    ⇒ p1 의 MDD '달성가능 t=+2.59' 는 400 draw IS-argmax 산물 → 잡음 기대 max 2.89 미만. 무의미.\n")

write_json(list(
  meta = list(stage="prereg_power_adversarial", n_months=n_all, dedup=NU,
              metric_type="diagnostic_precheck"),
  L1_selected_arm_sd = unname(l1),
  L2_pit_lagged_label = list(label_persistence = as.list(persist),
                             buckets = unname(l2),
                             lagged_switch_upper_bound = list(
                               mean_pct_per_month = 100*mean(dsw), sd_pct = 100*sd(dsw),
                               t = mean(dsw)/(sd(dsw)/sqrt(nsw)), n = nsw)),
  L3_multiple_testing = lapply(c(1,6,20,100,400,4000), function(k)
    list(n_trials=k, bonferroni_t=qnorm(1-0.05/(2*k)), expected_noise_max_t=qnorm(1-1/(2*k+2))))
), file.path(OUT, "prereg_power_adversarial.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[saved]\n"); sink()
