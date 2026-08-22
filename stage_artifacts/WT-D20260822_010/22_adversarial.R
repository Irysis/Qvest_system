## WT-D20260822_010 — Self-Adversarial 검증 실행분
##  A1) "NP2 가 측정한 그 객체를 소비했다" 를 **수치로** 증명 (재구성 축이 NP2 t 를 재현하는가)
##  A2) 컷 모집단 차이(NP2 표본 분위 vs base 후보 분위)가 배제집합을 얼마나 바꾸는가
##  A3) P1 단독(WT-009 정확 함수형)으로도 관문이 통과하는가 = 관문 판정의 P1/P2 선택 민감도
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
say <- function(f, ...) cat(sprintf(paste0("[adv] ", f, "\n"), ...))
source("02_Infrastructure/contracts/distribution_target_screen.R")
A <- list()

NP <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/alpha_scores.parquet"))[, Date := as.Date(Date)]
fwdNP <- readRDS("stage_artifacts/WT-D20260813_006/fwd.rds")
RETNP <- as.data.table(fwdNP$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
LIQNP <- as.data.table(fwdNP$liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]
setattr(LIQNP, "liq_ruler", attr(fwdNP$liq_dt, "liq_ruler", exact = TRUE))
SCORES  <- NP[is.finite(absorb_raw), .(Date, Ticker, score = absorb_raw)]
CONTROL <- NP[, .(Date, Ticker, win_vol, log_size)]
WIN2 <- list(early = as.Date(c("2000-01-01","2015-12-01")), late = as.Date(c("2015-12-01","2026-06-01")))

## ── A1. NP2 verbatim 재현 ──────────────────────────────────────────────────
r1 <- canonical_distribution_screen(
  scores_dt = SCORES, returns_dt = RETNP, control_dt = CONTROL,
  control_cols = c("win_vol","log_size"), control_transform = "rank",
  n_quantiles = 5L, q_hi = 5L, q_lo = 1L, quantile_probs = c(0.10, 0.90),
  tail_threshold_mode = "fixed", tail_fixed_up = 0.20, tail_fixed_dn = -0.20,
  winsorize_probs = c(0.01, 0.99), liq_dt = LIQNP, liq_min = 2e8,
  windows = WIN2, nw_lag = 3L, t_min_survive = 2.0,
  run_id = "WT010_adv_np2_reproduce", spec_id = "FQ234_absorb_w3_corr",
  prereg_ref = "stage_artifacts/WT-D20260822_003/PREREG_NP2.json")
got <- c(early = r1$windows$early$orthogonalized$axes$tail_dn_prob_diff$nw_t,
         late  = r1$windows$late$orthogonalized$axes$tail_dn_prob_diff$nw_t)
ref <- c(early = -4.323, late = -3.100)
say("A1 NP2 재현: tail_dn_prob_diff orth NW-t early %.4f (기준 %.3f) / late %.4f (기준 %.3f)",
    got["early"], ref["early"], got["late"], ref["late"])
A$A1_np2_reproduction <- list(measured = as.list(round(got, 6)), reference = as.list(ref),
  max_abs_diff = max(abs(got - ref)), matched = all(abs(got - ref) < 0.01),
  reading = "본 라운드가 쓴 직교화 축이 NP2 가 보고한 그 축과 같은 객체임을 수치로 증명 — '같은 객체를 소비했다'가 서술이 아니라 실측.")

## ── A2. 컷 모집단 차이 ─────────────────────────────────────────────────────
O <- readRDS(file.path(OUT, "00_precheck_objects.rds")); SMx <- O$SMx
NP2CUT <- copy(SMx)
orthall <- O$ORTH
np2thr <- orthall[, .(thr_np2 = quantile(score_orth, 0.20, type = 7, names = FALSE)), by = Date]
NP2CUT <- merge(NP2CUT, np2thr, by = "Date", all.x = TRUE)
NP2CUT[, excl_np2 := is.finite(score_orth) & score_orth <= thr_np2]
tab <- NP2CUT[!is.na(excluded), .(n = .N,
  both = sum(excluded & excl_np2), only_base = sum(excluded & !excl_np2),
  only_np2 = sum(!excluded & excl_np2), neither = sum(!excluded & !excl_np2))]
jacc <- tab$both / (tab$both + tab$only_base + tab$only_np2)
say("A2 컷 모집단: 교집합 %d / base컷 전용 %d / NP2컷 전용 %d / Jaccard %.4f (전체 %d행)",
    tab$both, tab$only_base, tab$only_np2, jacc, tab$n)
A$A2_cut_population <- list(counts = as.list(tab), jaccard = jacc,
  base_cut_rate = NP2CUT[!is.na(excluded), mean(excluded)],
  np2_cut_rate = NP2CUT[!is.na(excluded), mean(excl_np2)],
  reading = paste0("base 후보집합 내 20% 컷(WT-009 관례, 본 라운드 사용)과 NP2 표본 20% 컷은 ",
    "완전히 같지 않다 — Jaccard ", round(jacc,4), ". 두 컷이 크게 다르면 '같은 객체' 주장에서 ",
    "축은 같아도 집합이 달라진다는 뜻이므로 수치를 기록한다."))

## ── A3. 관문의 P1/P2 선택 민감도 ───────────────────────────────────────────
PC <- fromJSON(file.path(OUT, "00_precheck.json"))
A$A3_gate_sensitivity <- list(
  ratio_max_P1P2 = PC$gate$ratio,
  ratio_P1_only = PC$gate$P1_annual_pp / PC$gate$mde80_annual_pp,
  ratio_P2_only = PC$gate$P2_annual_pp / PC$gate$mde80_annual_pp,
  threshold = 0.10,
  both_above_threshold = (PC$gate$P1_annual_pp / PC$gate$mde80_annual_pp >= 0.10),
  reading = "관문 통과가 P2(관대한 상한) 도입 덕분이었는지 확인. P1 단독으로도 문턱을 넘으면 관문 판정은 그 선택에 종속되지 않는다.")
say("A3 관문 민감도: max(P1,P2) %.4f / P1 단독 %.4f / P2 단독 %.4f (문턱 0.10) → P1 단독 통과 = %s",
    A$A3_gate_sensitivity$ratio_max_P1P2, A$A3_gate_sensitivity$ratio_P1_only,
    A$A3_gate_sensitivity$ratio_P2_only, A$A3_gate_sensitivity$both_above_threshold)

write_json(A, file.path(OUT, "22_adversarial.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
