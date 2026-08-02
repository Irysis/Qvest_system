# =============================================================================
# run_wt010_verify.R — WT-D20260802_010 구현 정확성 검증 (사전등록 의무 T1~T8)
#   원칙: 알려진 닫힌형 이론값 대조 + 위반 주입(고의 오구현이 잡히는지 확인).
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_010/run_wt010_verify.R")'
# =============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("stage_artifacts/WT_D20260802_010/ot_w1_lib.R")
suppressPackageStartupMessages(library(jsonlite))
say <- function(fmt, ...) cat(sprintf(paste0("[verify] ", fmt, "\n"), ...))
PASS <- list(); DETAIL <- list()
chk <- function(name, ok, detail = "") {
  PASS[[name]] <<- isTRUE(ok); DETAIL[[name]] <<- detail
  say("%-46s %s %s", name, ifelse(isTRUE(ok), "PASS", "FAIL"), detail)
}
set.seed(20260802)

# 고밀도 grid에서 이론분포 분위함수로 직접 대조 (구현 = w1_grid + 분위함수)
KH <- 200001L; UH <- ot_grid(KH)

# ── T1. Gaussian 위치: W1(N(0.3,1), N(-0.2,1)) = |Δμ| = 0.5 ─────────────────
qa <- 0.3 + stats::qnorm(UH); qb <- -0.2 + stats::qnorm(UH)
v1 <- w1_grid(qa, qb)
chk("T1 Gaussian location W1=|dmu|", abs(v1 - 0.5) < 1e-3, sprintf("W1=%.6f (이론 0.5)", v1))

# ── T2. Gaussian 스케일: W1(N(0,1),N(0,2)) = 1*sqrt(2/pi) ───────────────────
qa <- stats::qnorm(UH); qb <- 2 * stats::qnorm(UH)
v2 <- w1_grid(qa, qb); th2 <- sqrt(2 / pi)
chk("T2 Gaussian scale W1=|ds|*sqrt(2/pi)", abs(v2 - th2) / th2 < 2e-3,
    sprintf("W1=%.6f (이론 %.6f)", v2, th2))

# ── T3. Uniform: W1(U[0,1],U[0,2])=1/2, 평행이동 W1=|c| ─────────────────────
qa <- UH; qb <- 2 * UH
v3a <- w1_grid(qa, qb)
qa2 <- 3 + 4 * UH; qb2 <- 3.7 + 4 * UH          # U[3,7] vs U[3.7,7.7], c=0.7
v3b <- w1_grid(qa2, qb2)
chk("T3 Uniform pair + translation", abs(v3a - 0.5) < 1e-4 && abs(v3b - 0.7) < 1e-10,
    sprintf("W1=%.5f (0.5) / %.5f (0.7)", v3a, v3b))

# ── T4. barycenter 닫힌형: bary{N(1,1),N(3,2)} = N(2,1.5) 분위 (정확) ────────
Qm <- rbind(1 + 1 * stats::qnorm(OT_U), 3 + 2 * stats::qnorm(OT_U))
bar <- ot_cs_decompose(Qm)$qbar
th4 <- 2 + 1.5 * stats::qnorm(OT_U)
d4 <- max(abs(bar - th4))
chk("T4 1D barycenter = quantile mean (exact)", d4 < 1e-12, sprintf("max|diff|=%.2e", d4))

# ── T5. affine 불변: r -> a + b*r (b>0) 에서 정규화 파이프라인 정확 불변 ─────
r0 <- rt(63, df = 4) * 0.02 + rnorm(63, 0, 0.005)     # heavy-tail 표본
f0 <- ot_stock_quantiles(r0); f1 <- ot_stock_quantiles(0.013 + 3.7 * r0)
d5 <- max(abs(f0$q_norm - f1$q_norm))
chk("T5 affine invariance (norm quantiles exact)", d5 < 1e-12, sprintf("max|diff|=%.2e", d5))

# ── T6. 분해 항등식: location-scale family에서 delta(u)=dmu+ds*z(u) ──────────
#   비정규화 rtail = dmu + ds*mean(z(u), u in right band) — 닫힌형 재현.
#   (비정규화 버전이 모멘텀(위치)+vol(스케일) 재조합임을 정리 수준으로 입증)
mus <- c(0.5, -0.5); sds <- c(1.3, 0.7)
Qraw <- rbind(mus[1] + sds[1] * stats::qnorm(OT_U), mus[2] + sds[2] * stats::qnorm(OT_U))
dec <- ot_cs_decompose(Qraw)
zR <- mean(stats::qnorm(OT_U)[OT_RIGHT_IDX]); zL <- mean(stats::qnorm(OT_U)[OT_LEFT_IDX])
th_rt <- (mus - mean(mus)) + (sds - mean(sds)) * zR
th_lt <- (mus - mean(mus)) + (sds - mean(sds)) * zL
d6 <- max(abs(dec$rtail - th_rt), abs(dec$ltail - th_lt))
chk("T6 decomposition identity (loc-scale)", d6 < 1e-12,
    sprintf("max|diff|=%.2e (rtail=dmu+ds*zbar_R 재현)", d6))

# ── T7. grid 수렴/노이즈 바닥 문서화 ─────────────────────────────────────────
# (a) K=31 vs K=2001: N(0,1) vs N(0.2,1.3) W1 편향
w31 <- w1_grid(0 + 1 * stats::qnorm(OT_U), 0.2 + 1.3 * stats::qnorm(OT_U))
w2001 <- w1_grid(stats::qnorm(ot_grid(2001)), 0.2 + 1.3 * stats::qnorm(ot_grid(2001)))
bias31 <- (w31 - w2001) / w2001
# (b) 동일분포 n=63 표본쌍 W1 노이즈 바닥 (500회)
noise <- replicate(500, {
  za <- ot_stock_quantiles(rnorm(63))$q_norm
  zb <- ot_stock_quantiles(rnorm(63))$q_norm
  w1_grid(za, zb)
})
chk("T7 grid bias + sampling noise floor (문서화)", abs(bias31) < 0.05,
    sprintf("K31 vs K2001 bias=%.3f%% | n=63 동일분포 W1 노이즈 med=%.3f p90=%.3f",
            100 * bias31, median(noise), quantile(noise, 0.9)))

# ── T8. 위반 주입 — 오구현이 검사에서 잡히는가 (검사기 실효 확인) ────────────
# (a) L2(Cramér) 오구현: T2 이론값과 불일치해야 정상 검출
v8a <- w1_grid_l2_BROKEN(stats::qnorm(UH), 2 * stats::qnorm(UH))
det_a <- abs(v8a - th2) / th2 > 0.05           # L2는 1.0 근방 — 0.798과 뚜렷 분리
chk("T8a injection: L2-instead-of-L1 caught", det_a,
    sprintf("BROKEN=%.4f vs 이론 %.4f (불일치 검출=%s)", v8a, th2, det_a))
# (b) 정렬 누락 분위 오구현: 단조성 위반 + T1 불일치로 검출
xs <- rnorm(200, 0.3)
qbrk <- emp_q_unsorted_BROKEN(xs, OT_U)
mono_viol <- any(diff(qbrk) < 0)
chk("T8b injection: unsorted-quantile caught", mono_viol,
    sprintf("분위 단조성 위반 검출=%s", mono_viol))

# ── 저장 ─────────────────────────────────────────────────────────────────────
n_pass <- sum(unlist(PASS)); n_total <- length(PASS)
say("=== %d / %d PASS ===", n_pass, n_total)
write_json(list(task_id = "WT-D20260802_010", generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                n_pass = n_pass, n_total = n_total,
                results = lapply(names(PASS), function(k) list(test = k, pass = PASS[[k]], detail = DETAIL[[k]]))),
           "stage_artifacts/WT_D20260802_010/verify_results.json",
           auto_unbox = TRUE, pretty = TRUE)
say("verify_results.json 저장")
