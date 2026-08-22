## WT-D20260822_008 (FQ-246 NP2) P6 — 자기 적대검증(Self-Adversarial)이 요구한 추가 실측
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_008"
P1 <- readRDS(file.path(OUT,"p1_parity.rds")); G <- readRDS(file.path(OUT,"p3_gate.rds"))
B  <- readRDS(file.path(OUT,"p4_bounds.rds")); P5 <- readRDS(file.path(OUT,"p5_target_identity.rds"))
K <- P1$K; NM <- P1$NM; TOPN <- P1$TOPN; Zl <- P1$Zl; RBF <- P1$ret_by_factor
CRIT <- P1$CRIT; AM <- P1$AM; DIRS <- P1$DIRS; ALL <- G$ALL

cat("=== C1) [ACCEPT] 이항 MDE 의 정확 임계치 — qbinom 정의가 실제 기각역보다 1 낮다 ===\n")
xs <- 0:NM; pv <- vapply(xs, function(x) binom.test(x, NM, p=1/K, alternative="greater")$p.value, 0)
crit_x <- xs[which(pv < 0.05)[1]]
cat(sprintf("  사전등록 MDE(qbinom 판, WT-007 승계 컨벤션) = %d/%d = %.6f (p=%.4f — 기각 안 됨)\n",
            qbinom(0.95,NM,1/K), NM, qbinom(0.95,NM,1/K)/NM, pv[qbinom(0.95,NM,1/K)+1]))
cat(sprintf("  ★정확 기각 임계 count = %d/%d = %.6f (p=%.4f)\n", crit_x, NM, crit_x/NM, pv[crit_x+1]))
RETT <- ALL[key_id=="RET"]
cat(sprintf("  gross 정답지 최대 적중 = %d/%d = %.6f (%s) ⇒ 임계 미달 %s\n",
            round(max(RETT$hit)*NM), NM, max(RETT$hit), RETT$criterion[which.max(RETT$hit)],
            round(max(RETT$hit)*NM) < crit_x))
netmax <- B$NETT[which.max(hit_net)]
cat(sprintf("  net 정답지 최대 적중 = %d/%d = %.6f (%s, p=%.4f) ⇒ 임계 미달 %s\n",
            round(netmax$hit_net*NM), NM, netmax$hit_net, netmax$criterion, netmax$p_net,
            round(netmax$hit_net*NM) < crit_x))
cat("  ★라벨 정정: net 정답지 centrality_MIN 은 qbinom-MDE 와 동률이므로 POWERED_NULL 이 아니라\n")
cat("    UNRESOLVED_UNDERPOWERED 로 강등한다(문턱 완화 아님 — 라벨 강등).\n")

cat("\n=== C2) [ACCEPT] 잡음 사다리 검정력은 '단조 사본' 대안 전용 — 관측 기준은 그 궤적 밖 ===\n")
LAD <- B$LAD; obs <- RETT[criterion %in% names(DIRS)]
cat("  사다리 좌표 (hit, |rho|):\n")
print(LAD[, .(noise=noise_sd_mult, hit=round(hit,4), rho=round(rho,4), rho_t=round(rho_t,2), fire_rate)])
cat(sprintf("  관측 기준 최대: hit %.4f / |rho| %.4f  vs  같은 hit 의 사다리점 |rho| ≈ %.4f\n",
            max(obs$hit), max(abs(obs$rho)), LAD[which.min(abs(LAD$hit-max(obs$hit))), abs(rho)]))
cat("  ⇒ 관측 기준은 같은 적중률에서 사다리보다 |rho| 가 훨씬 낮다 = '전체 순위' 가 아니라\n")
cat("    '꼭짓점만' 안다는 대안 형태. 그 대안에 대한 구속 채널은 rho 가 아니라 **이항 적중률**이며,\n")
cat(sprintf("    그 채널의 정확 MDE 는 %.6f 다(사다리의 0.85 발화율을 인용하면 과대 주장).\n", crit_x/NM))

cat("\n=== C3) [PARTIAL] 8방향은 4 거울쌍 — Bonferroni 8 이 보수적인가 ===\n")
cat(sprintf("  raw 통과 %d/8 · Bonferroni(8) 통과 %d/8 · Sidak(4기준, 양측) alpha = %.5f\n",
            sum(obs$pass_raw), sum(obs$pass_adj), 1-(1-0.05)^(1/4)))
sid <- 1-(1-0.05)^(1/4)
cat(sprintf("  Sidak(4) 기준 통과 = %d/8 (hit_p < %.5f 또는 |rho_t| >= %.3f)\n",
            sum(obs$hit_p < sid | abs(obs$rho_t) >= qnorm(1-sid/2)), sid, qnorm(1-sid/2)))
cat("  ★어느 보정을 써도 통과 0 — raw 조차 0 이므로 다중검정 논쟁은 결론에 무영향.\n")

cat("\n=== C4) [ACCEPT] 분할표본 규격 불일치 — NHALF=12 대신 TOPN=25 로 재측정 ===\n")
ret_half <- function(m, idx, nsel) { Z <- Zl[[m]]$Z[idx,,drop=FALSE]; f <- Zl[[m]]$fwd[idx]
  vapply(seq_len(K), function(k){ v <- Z[,k]; ok <- is.finite(v)&is.finite(f)
    if (sum(ok) < nsel) return(NA_real_)
    mean(f[ok][order(v[ok], decreasing=TRUE)[seq_len(nsel)]]) }, 0) }
ic_half <- function(m, idx) { Z <- Zl[[m]]$Z[idx,,drop=FALSE]; f <- Zl[[m]]$fwd[idx]
  vapply(seq_len(K), function(k){ v <- Z[,k]; ok <- is.finite(v)&is.finite(f)
    if (sum(ok) < 30L || sd(v[ok])==0) return(NA_real_); cor(rank(v[ok]), rank(f[ok])) }, 0) }
set.seed(20260823L); R <- 20L
run_split <- function(nsel) { out <- vector("list", R)
  for (r in seq_len(R)) { vA <- vB <- iA <- matrix(NA_real_, NM, K)
    for (m in seq_len(NM)) { n <- length(Zl[[m]]$tick); s <- sample.int(n)
      hA <- s[seq_len(floor(n/2))]; hB <- s[(floor(n/2)+1):n]
      vA[m,] <- ret_half(m,hA,nsel); vB[m,] <- ret_half(m,hB,nsel); iA[m,] <- ic_half(m,hA) }
    ok <- apply(is.finite(vA)&is.finite(vB)&is.finite(iA), 1, all); mm <- which(ok)
    cen <- function(M,m,k) M[m,k] - mean(M[m,])
    pA <- vapply(mm, function(m) which.max(vA[m,]), 0L)
    pI <- vapply(mm, function(m) which.max(iA[m,]), 0L)
    tr <- vapply(seq_along(mm), function(j) cen(vB,mm[j],pA[j]), 0)
    ti <- vapply(seq_along(mm), function(j) cen(vB,mm[j],pI[j]), 0)
    orc<- vapply(mm, function(m) max(vB[m,])-mean(vB[m,]), 0)
    out[[r]] <- data.table(n_months=length(mm), transfer_ann=mean(tr)*12*100,
      transfer_t=.nw_t_mean(tr,lag=3L), transfer_ic_ann=mean(ti)*12*100,
      transfer_ic_t=.nw_t_mean(ti,lag=3L), oracle_ann=mean(orc)*12*100,
      agree=mean(vapply(seq_along(mm), function(j) pA[j]==which.max(vB[mm[j],]), TRUE))) }
  rbindlist(out)[, lapply(.SD, mean)] }
S25 <- run_split(TOPN); S12 <- P5$SUM
CMP <- rbind(
  data.table(spec="NHALF=12 (P5)", n_months=S12$n_months, transfer_ann=S12$transfer_ret_ann,
    transfer_t=S12$transfer_ret_t, transfer_ic_ann=S12$transfer_ic_ann, transfer_ic_t=S12$transfer_ic_t,
    oracle_ann=S12$oracle_B_ann, agree=S12$agree_AB),
  data.table(spec="NHALF=25 (=TOPN)", n_months=S25$n_months, transfer_ann=S25$transfer_ann,
    transfer_t=S25$transfer_t, transfer_ic_ann=S25$transfer_ic_ann, transfer_ic_t=S25$transfer_ic_t,
    oracle_ann=S25$oracle_ann, agree=S25$agree))
CMP[, transfer_ratio := transfer_ann/oracle_ann]
CMP[, ic_over_ret_transfer := transfer_ic_ann/transfer_ann]
print(CMP[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
cat("  ★두 규격에서 결론(전이 유의 · 전이비율 ~0.2 · IC/RET 전이 근접)이 재현되면 규격 의존 아님.\n")

cat("\n=== C5) [PARTIAL] 적중률-선택가치 괴리 상관은 8점 — 불확실 ===\n")
DIS <- B$DIS
ct <- cor.test(DIS$hit, DIS$selval_ann_pct)
cat(sprintf("  Pearson %+.4f · 95%% CI [%.4f, %.4f] · p %.4f (n=8)\n",
            ct$estimate, ct$conf.int[1], ct$conf.int[2], ct$p.value))
cat(sprintf("  ★8점 상관은 CI 가 부호를 넘나든다 ⇒ '괴리' 의 근거는 상관이 아니라 개별 관측:\n"))
cat(sprintf("    centrality_MIN = 적중 최고(%.5f, 우연 +%.2f pp)인데 선택가치 %+.4f %%p/yr (NW3 t %.3f)\n",
            DIS$hit[1], (DIS$hit[1]-0.2)*100, DIS$selval_ann_pct[1], DIS$selval_t[1]))
cat(sprintf("    (Bonferroni 8 문턱 |t| %.3f 미달 — raw 유의만. 라벨 = 진단 관측)\n", qnorm(1-0.05/16)))

cat("\n=== C6) [REBUTTAL] 승계 CRIT 를 재계산 없이 쓴 것이 결함인가 ===\n")
cat("  근거: (i) 패리티에서 8방향 IC-정답지 통계가 Δ=0.000e+00 비트-동일 재현 —\n")
cat("        CRIT 는 '같은 객체' 이며 이것이 정답지만 교체하는 paired 대조의 **전제**다.\n")
cat("  (ii) 게이트 자체의 결함 가능성은 양성 대조 4/4 발화 · 음성 대조 미발화로 배제.\n")
cat("  (iii) 단 CRIT 산식(4종 기준) 자체의 타당성은 본 라운드 범위 밖 — 새 기준 발굴은 next_probe.\n")

saveRDS(list(crit_x=crit_x, crit_hit=crit_x/NM, CMP=CMP, S25=S25, ct=ct, sidak=sid),
        file.path(OUT,"p6_adversarial.rds"))
cat("\n[saved] p6_adversarial.rds\nOK\n")
