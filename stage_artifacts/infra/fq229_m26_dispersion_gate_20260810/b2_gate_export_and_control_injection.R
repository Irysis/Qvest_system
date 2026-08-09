## =============================================================================
## FQ-229 (B2) — ①게이트 승수 tidy 내보내기(c1 이 소비) ②대조축 위반 주입(정규화)
## b1 의 자동 라벨 "대조축이 M26 보다 크게 개선" 은 **오독**이었다:
##   Δt 를 base t 가 제각각인 축들 사이에서 그대로 비교했다. C01 base t = -0.038 이라
##   깎일 것이 없어 Δt 가 0 에 가까울 뿐이다. 정본 비교 = 축별 무작위-게이트 귀무분포 대비 백분위.
## metric_type: canonical_screen_diag. 자본 주장 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[b2] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260812L)
NWLAG <- 3L; BURN <- 24L; B_INJ <- 2000L
FACS <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "M26_Revenue_Mom"); TARGET <- "M26_Revenue_Mom"
nw_t <- function(x, lag = NWLAG) { x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }
neutral <- function(m) { out <- m; run <- 0; cnt <- 0
  for (i in seq_along(m)) { out[i] <- if (cnt > 0 && run/cnt > 1e-9) m[i]/(run/cnt) else m[i]
    run <- run + m[i]; cnt <- cnt + 1 }; out }

A <- readRDS(file.path(OUT, "a1_results.rds")); DT <- as.data.table(A$DT); setorder(DT, signal_ym)
d1 <- DT$disp_lag1; n <- length(d1); gz <- DT$g_exp
expq <- function(p) { v <- rep(NA_real_, n)
  for (i in seq_len(n)) { h <- d1[1:i]; h <- h[is.finite(h)]
    if (length(h) >= BURN) v[i] <- quantile(h, p, names = FALSE) }; v }
q70 <- expq(0.70); q50 <- expq(0.50); q25 <- expq(0.25); q75 <- expq(0.75)
fixna <- function(v) { v[!is.finite(v)] <- 1; v }
g4v <- rep(NA_real_, n)
for (i in seq_len(n)) if (is.finite(q25[i])) g4v[i] <-
  if (d1[i] >= q75[i]) 1.50 else if (d1[i] >= q50[i]) 1.15 else if (d1[i] >= q25[i]) 0.85 else 0.50
G <- data.table(signal_ym = DT$signal_ym,
                G1 = fixna(ifelse(is.finite(q70) & d1 >= q70, 1, ifelse(is.finite(q70), 0, NA))),
                G2 = fixna(ifelse(is.finite(q50) & d1 >= q50, 1, ifelse(is.finite(q50), 0, NA))),
                G3 = fixna(pmin(pmax(1 + 1.0*gz, 0), 2)),
                G4 = fixna(g4v))
for (g in c("G1","G2","G3","G4")) G[, (paste0(g, "_n")) := neutral(get(g))]
fwrite(G, file.path(OUT, "b2_gate_multipliers.csv"))
say("게이트 승수 저장: %d개월 · 평균 중립화 승수 %s", nrow(G),
    paste(sprintf("%s %.3f", c("G1","G2","G3","G4"),
                  sapply(c("G1_n","G2_n","G3_n","G4_n"), function(cc) mean(G[[cc]]))), collapse=" · "))

## ---------------------------------------------------------------- 축별 주입
say("================ 축별 무작위-게이트 귀무분포 (B=%d) ================", B_INJ)
n_on <- sum(G$G1 > 0)
say("G1 발화 %d/%d — 무작위 게이트도 같은 발화수로 뽑는다", n_on, n)
dtof <- function(m, y) { mt <- neutral(m); nw_t(mt * y) - nw_t(y) }
INJ <- rbindlist(lapply(c(FACS, "M01"), function(f) {
  y <- DT[[f]]; obs <- dtof(G$G1, y)
  nulld <- vapply(seq_len(B_INJ), function(b) { mm <- rep(0, n); mm[sample.int(n, n_on)] <- 1; dtof(mm, y) }, 0)
  data.table(factor = f, base_t = nw_t(y), obs_dt = obs,
             null_med = median(nulld), null_q05 = quantile(nulld, .05, names = FALSE),
             null_q95 = quantile(nulld, .95, names = FALSE),
             pctile = mean(nulld <= obs), p_right = mean(nulld >= obs))
}))
for (i in seq_len(nrow(INJ))) with(INJ[i], say(
  "  %-18s base t %+.3f · 관측 Δt %+.4f · 귀무 중앙 %+.4f [%.4f, %+.4f] ⇒ 백분위 %.1f%% (p_우측 %.4f)",
  factor, base_t, obs_dt, null_med, null_q05, null_q95, pctile*100, p_right))
say("★정본 판정 (Δt 직접비교 아님 — 축별 귀무 대비 백분위): 유의(p<0.05) 축 = %s",
    { s <- INJ[p_right < 0.05, factor]; if (length(s)) paste(s, collapse=" / ") else "0건 — 어느 축도 무작위 게이트와 구별 안 됨" })
say("   ※ b1 의 '대조축이 M26 보다 크게 개선' 자동라벨은 폐기한다 — base t 가 제각각인 Δt 직접비교는 무의미하다.")
fwrite(INJ, file.path(OUT, "b2_control_injection.csv"))
saveRDS(list(G = G, INJ = INJ, n_on = n_on), file.path(OUT, "b2_results.rds"))
say("저장 완료 -> %s", OUT)
