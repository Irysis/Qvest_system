# =============================================================================
# run_wt001_fm.R — WT-D20260803_001 MAX5 x alpha-rank FM 상호작용 (사전등록 primary)
#   사전등록: stage_artifacts/WT_D20260803_001/preregistration.json (측정 전 고정)
#
#   primary(Arm B) = FM: Ret_1m ~ zrank + zmax5 + zrank:zmax5
#                        + D35_RealVol_63d + D45_Downside_Dev + zsize + zliq
#     판정 = zrank:zmax5 계수 시계열 NW lag-3 t (>= +2.0 승자표지 / |t|<2 미확정 / <= -2.0 배제 지지)
#   Arm A(d1) = D35/D45 제외 (통제 전/후 병기 — Q-Lead 지시)
#   Arm C(d3) = + zrank:D35 + zrank:D45 (attribution gate)
#   Σ/weights 계산 없음 — 특성화만 (역할 경계)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_001/run_wt001_fm.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr); library(jsonlite)
  library(sandwich); library(lmtest); library(lubridate)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_001")
say <- function(fmt, ...) cat(sprintf(paste0("[wt001] ", fmt, "\n"), ...))

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
wz <- function(x) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s == 0) return(rep(NA_real_, length(x)))
  x <- pmin(pmax(x, m - 3 * s), m + 3 * s)
  s2 <- sd(x, na.rm = TRUE)
  if (!is.finite(s2) || s2 == 0) return(rep(NA_real_, length(x)))
  (x - mean(x, na.rm = TRUE)) / s2
}

# ── 0. 입력 로드 + vintage ───────────────────────────────────────────────────
IN_FILES <- c(
  max5  = "stage_artifacts/WT_D20260802_014/alpha_scores.parquet",
  alpha = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
  si    = "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
  ctrl  = "stage_artifacts/WT_D20260803_001/controls_panel_d35.parquet",
  raw   = ".cache/RAWDATA.parquet",
  regime = ".cache/unified_regime_signal.parquet"
)
vintage <- data.table(input = names(IN_FILES), path = IN_FILES,
                      mtime = sapply(IN_FILES, function(p) as.character(file.mtime(p))))
say("입력 vintage:"); print(vintage[, .(input, mtime)])

EX <- as.data.table(read_parquet(IN_FILES["max5"]))
EX[, Date := as.Date(Date)]
EX <- EX[is.finite(max5), .(Date, Ticker, max5)]

AS <- as.data.table(read_parquet(IN_FILES["alpha"]))
AS[, Date := as.Date(Date)]
AS <- AS[is.finite(score_eff), .(sig_label = Date, Ticker, score_eff)]
AS[, sig_ym := format(sig_label, "%Y-%m")]
n_sig_per_ym <- AS[, uniqueN(sig_label), by = sig_ym]
stopifnot(all(n_sig_per_ym$V1 == 1L))   # 월당 sig_label 유일 assert

SI <- readRDS(IN_FILES["si"])
fwd <- as.data.table(SI$fwd_ret); SIZE <- as.data.table(SI$SIZE); liqf <- as.data.table(SI$liqf)
for (dt in list(fwd, SIZE, liqf)) dt[, Date := as.Date(Date)]

CP <- as.data.table(read_parquet(IN_FILES["ctrl"]))
CP[, Date := as.Date(Date)]

ureg <- as.data.table(read_parquet(IN_FILES["regime"]))[, .(Date = as.Date(Date), Category)]
ureg[, hold_ym := format(Date, "%Y-%m")]

# d0 그리드: max5 가용 ∩ d0 <= 2026-03-31 (data_currency_flag)
d0_all <- sort(unique(EX$Date))
d0_all <- d0_all[d0_all <= as.Date("2026-03-31")]
say("d0 그리드: %d개월 (%s ~ %s)", length(d0_all),
    as.character(min(d0_all)), as.character(max(d0_all)))

# ── 1. Forward 라벨 방향 검증 (PIT) + 위반 주입 (WT-020 검증기 재사용) ───────
grid <- sort(unique(fwd$Date))
tk_need <- unique(AS$Ticker)
RD <- as.data.table(
  open_dataset(IN_FILES["raw"]) %>%
    select(Date, Ticker, Ret) %>%
    filter(Date > as.Date("2004-12-01")) %>%
    collect())
RD <- RD[Ticker %chin% tk_need & is.finite(Ret)]
RD[, Date := as.Date(Date)]
RD[, iv := findInterval(as.numeric(Date) - 0.5, as.numeric(grid))]
RD <- RD[iv >= 1L & iv <= length(grid)]
RECON <- RD[, .(recon = prod(1 + Ret) - 1, nd = .N), by = .(Date = grid[iv], Ticker)]
say("recon: %d 종목-월 (일간 저장 Ret 복리 — 검증 전용, ret_firewall 준수)", nrow(RECON))

validate_forward_label <- function(lab_dt, recon_dt, min_cor = 0.99, label_name = "Ret_1m") {
  m <- merge(lab_dt[, .(Date, Ticker, lab = get(label_name))],
             recon_dt[, .(Date, Ticker, recon)], by = c("Date", "Ticker"))
  m <- m[is.finite(lab) & is.finite(recon)]
  cc_all <- m[, cor(lab, recon)]
  cc_m <- m[, .(cc = if (.N >= 30) cor(lab, recon) else NA_real_), by = Date]
  med_cc <- median(cc_m$cc, na.rm = TRUE)
  say("  [validator %s] cor 전체 %.4f / 월중앙 %.4f", label_name, cc_all, med_cc)
  if (!is.finite(cc_all) || cc_all < min_cor || !is.finite(med_cc) || med_cc < min_cor)
    stop(sprintf("LABEL DIRECTION FAIL — cor %.4f/%.4f < %.2f (라벨이 익월 수익이 아님)",
                 cc_all, med_cc, min_cor))
  list(cor_all = cc_all, cor_monthly_median = med_cc, n_pairs = nrow(m))
}
v_pass <- validate_forward_label(fwd[Date %in% d0_all, .(Date, Ticker, Ret_1m)], RECON)
say("방향 검증 PASS — fwd Ret_1m = 익월 수익 실증 (n_pairs=%d)", v_pass$n_pairs)

# 위반 주입: 동월(직전구간) 수익을 라벨로 위장 — 검증기 stop() 발화해야 검사 실효
BAD <- copy(RECON)[, Date_next := {
  idx <- match(as.character(Date), as.character(grid)) + 1L
  as.Date(ifelse(idx <= length(grid), as.character(grid[idx]), NA))
}]
BAD <- BAD[!is.na(Date_next), .(Date = Date_next, Ticker, Ret_1m = recon)]
inj <- tryCatch({ validate_forward_label(BAD[Date %in% d0_all], RECON); list(fired = FALSE) },
                error = function(e) list(fired = TRUE, msg = conditionMessage(e)))
if (!inj$fired) stop("위반 주입 테스트 실패 — 검증기가 동월 라벨을 통과시킴 (검사 사망)")
say("위반 주입 FIRED — 동월 라벨 주입 시 stop() 발화 확인: %s", substr(inj$msg, 1, 70))

# ── 2. 패널 조립 (후보 프레임 = score_eff finite) ────────────────────────────
d0map <- data.table(d0 = d0_all)
d0map[, sig_ym := sapply(format(d0, "%Y-%m"), ym_add, k = 1L)]
CAND <- merge(AS, d0map, by = "sig_ym")          # 후보 프레임을 d0에 부착
say("후보 프레임: %d 종목-월 / %d개월 / 월평균 %.0f종",
    nrow(CAND), uniqueN(CAND$d0), nrow(CAND) / uniqueN(CAND$d0))

P <- CAND[, .(Date = d0, Ticker, score_eff)]
P <- merge(P, EX, by = c("Date", "Ticker"), all.x = TRUE)                  # max5 @ d0
# lag1 스트레스용: 전월 d0의 max5
d0idx <- data.table(Date = d0_all, prev = shift(d0_all, 1L))
EXlag <- merge(EX, d0idx[!is.na(prev)], by.x = "Date", by.y = "prev")
EXlag <- EXlag[, .(Date = Date.y, Ticker, max5_lag = max5)]
P <- merge(P, EXlag, by = c("Date", "Ticker"), all.x = TRUE)
P <- merge(P, fwd[, .(Date, Ticker, Ret_1m)], by = c("Date", "Ticker"), all.x = TRUE)
P <- merge(P, CP, by = c("Date", "Ticker"), all.x = TRUE)
P <- merge(P, SIZE, by = c("Date", "Ticker"), all.x = TRUE)
P <- merge(P, liqf, by = c("Date", "Ticker"), all.x = TRUE)

miss <- P[, .(max5 = mean(!is.finite(max5)), lab = mean(!is.finite(Ret_1m)),
              d35 = mean(!is.finite(D35_RealVol_63d)), d45 = mean(!is.finite(D45_Downside_Dev)),
              size = mean(!is.finite(Size)), adv = mean(!is.finite(adv)))]
say("결측률: max5 %.1f%% / 라벨 %.1f%% / D35 %.1f%% / D45 %.1f%% / Size %.1f%% / adv %.1f%%",
    100*miss$max5, 100*miss$lab, 100*miss$d35, 100*miss$d45, 100*miss$size, 100*miss$adv)

REG <- P[is.finite(max5) & is.finite(Ret_1m) & is.finite(D35_RealVol_63d) &
         is.finite(D45_Downside_Dev) & is.finite(Size) & is.finite(adv) & is.finite(score_eff)]
mn <- REG[, .N, by = Date]
keep_d <- mn[N >= 100, Date]
REG <- REG[Date %in% keep_d]
say("회귀 표본: %d행 / %d월 (n>=100 게이트 제외 %d월) / 월평균 n %.0f",
    nrow(REG), length(keep_d), length(d0_all) - length(keep_d), nrow(REG)/length(keep_d))

prep_z <- function(dt) {
  dt[, zrank := wz(frank(score_eff, ties.method = "average")), by = Date]
  dt[, zmax5 := wz(max5), by = Date]
  dt[, zsize := wz(log(pmax(Size, 1))), by = Date]
  dt[, zliq  := wz(log(pmax(adv, 1))), by = Date]
  dt
}
REG <- prep_z(REG)
REG[, zmax5_lag := wz(max5_lag), by = Date]

# 공선성 실측
ctab <- REG[, .(c_d35 = cor(zmax5, D35_RealVol_63d), c_d45 = cor(zmax5, D45_Downside_Dev),
                c_rank = cor(zmax5, zrank), c_size = cor(zmax5, zsize)), by = Date]
say("collinearity(월평균 cor): zmax5~D35 %+.3f / ~D45 %+.3f / ~zrank %+.3f / ~zsize %+.3f",
    ctab[, mean(c_d35)], ctab[, mean(c_d45)], ctab[, mean(c_rank)], ctab[, mean(c_size)])

# ── 3. FM 헬퍼 ───────────────────────────────────────────────────────────────
fm_run <- function(dt, form, coefs) {
  dd <- sort(unique(dt$Date))
  out <- lapply(dd, function(d) {
    sub <- dt[Date == d]
    fit <- tryCatch(lm(form, data = sub), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    co <- coef(fit)
    if (any(!coefs %in% names(co)) || any(!is.finite(co[coefs]))) return(NULL)
    cbind(data.table(Date = d, n = nrow(sub), r2 = summary(fit)$r.squared),
          as.data.table(as.list(co[coefs])))
  })
  rbindlist(Filter(Negate(is.null), out))
}
fm_summ <- function(FM, cn) {
  sapply(cn, function(v) c(mean = FM[, mean(get(v))], t = nw_t(FM[[v]])))
}

f_A <- Ret_1m ~ zrank + zmax5 + zrank:zmax5 + zsize + zliq
f_B <- Ret_1m ~ zrank + zmax5 + zrank:zmax5 + D35_RealVol_63d + D45_Downside_Dev + zsize + zliq
f_C <- Ret_1m ~ zrank + zmax5 + zrank:zmax5 + zrank:D35_RealVol_63d + zrank:D45_Downside_Dev +
                D35_RealVol_63d + D45_Downside_Dev + zsize + zliq
f_L <- Ret_1m ~ zrank + zmax5_lag + zrank:zmax5_lag + D35_RealVol_63d + D45_Downside_Dev + zsize + zliq

cn_int <- "zrank:zmax5"
FM_B <- fm_run(REG, f_B, c("zrank", "zmax5", cn_int))
FM_A <- fm_run(REG, f_A, c("zrank", "zmax5", cn_int))
FM_C <- fm_run(REG, f_C, c("zrank", "zmax5", cn_int, "zrank:D35_RealVol_63d"))
FM_L <- fm_run(REG[is.finite(zmax5_lag)], f_L, c("zrank:zmax5_lag"))

t_B <- nw_t(FM_B[[cn_int]]); t_A <- nw_t(FM_A[[cn_int]]); t_C <- nw_t(FM_C[[cn_int]])
t_L <- nw_t(FM_L[["zrank:zmax5_lag"]])
say("★ PRIMARY Arm B (D35+D45 통제): b_int=%+.5f NW t=%+.3f (n=%d월)",
    FM_B[, mean(get(cn_int))], t_B, nrow(FM_B))
say("  Arm A (통제 전):             b_int=%+.5f NW t=%+.3f", FM_A[, mean(get(cn_int))], t_A)
say("  Arm C (rank×D35/D45 병렬):   b_int=%+.5f NW t=%+.3f | b(rank×D35)=%+.5f",
    FM_C[, mean(get(cn_int))], t_C, FM_C[, mean(`zrank:D35_RealVol_63d`)])
say("  d2 lag1:                     b_int=%+.5f NW t=%+.3f", FM_L[, mean(`zrank:zmax5_lag`)], t_L)
say("  주효과(Arm B): zrank %+.5f (t %+.2f) / zmax5 %+.5f (t %+.2f)",
    FM_B[, mean(zrank)], nw_t(FM_B$zrank), FM_B[, mean(zmax5)], nw_t(FM_B$zmax5))

# 고랭크 국소 한계효과: b_zmax5 + q90(zrank)*b_int (월별)
q90 <- REG[, .(q90 = quantile(zrank, 0.90, type = 7)), by = Date]
FMq <- merge(FM_B, q90, by = "Date")
FMq[, eff_top := zmax5 + q90 * get(cn_int)]
say("  고랭크(q90) MAX5 한계효과: %+.5f (NW t %+.3f)", FMq[, mean(eff_top)], nw_t(FMq$eff_top))

# ── 4. d4 placebo (월내 max5 순열 × 5 seeds) ─────────────────────────────────
plac <- sapply(1:5, function(sd_i) {
  set.seed(2026080300 + sd_i)
  RP <- copy(REG)
  RP[, zmax5 := sample(zmax5), by = Date]
  FMp <- fm_run(RP, f_B, cn_int)
  nw_t(FMp[[cn_int]])
})
say("d4 placebo t (5 seeds): %s (전부 |t|<2 기대)", paste(sprintf("%+.2f", plac), collapse = " "))

# ── 5. d5 top-rank 40 국소 검정 ──────────────────────────────────────────────
TOP <- REG[, .SD[frank(-score_eff, ties.method = "first") <= 40], by = Date]
TOP[, zmax5_s := wz(max5), by = Date]
TOP[, zsize_s := wz(log(pmax(Size, 1))), by = Date]
f_T <- Ret_1m ~ zmax5_s + D35_RealVol_63d + D45_Downside_Dev + zsize_s
FM_T <- fm_run(TOP, f_T, "zmax5_s")
t_T <- nw_t(FM_T$zmax5_s)
say("d5 top-40 국소: b_zmax5=%+.5f NW t=%+.3f (n=%d월)", FM_T[, mean(zmax5_s)], t_T, nrow(FM_T))
# 통제 전 판 병기
f_T0 <- Ret_1m ~ zmax5_s + zsize_s
FM_T0 <- fm_run(TOP, f_T0, "zmax5_s")
say("d5 top-40 (통제 전): b=%+.5f t=%+.3f", FM_T0[, mean(zmax5_s)], nw_t(FM_T0$zmax5_s))

# ── 6. d6 부기간 + d7 국면 ───────────────────────────────────────────────────
sub_def <- list(p1 = c("2004-01-01", "2011-12-31"), p2 = c("2012-01-01", "2018-12-31"),
                p3 = c("2019-01-01", "2026-12-31"),
                pre2017 = c("2004-01-01", "2016-12-31"), post2017 = c("2017-01-01", "2026-12-31"))
sub_tab <- rbindlist(lapply(names(sub_def), function(nm) {
  w <- sub_def[[nm]]
  s <- FM_B[Date >= as.Date(w[1]) & Date <= as.Date(w[2])]
  data.table(window = nm, n = nrow(s), mean_b = s[, mean(get(cn_int))], t_nw = nw_t(s[[cn_int]]))
}))
say("d6 부기간 (Arm B 상호작용):"); print(sub_tab)

FM_B[, hold_ym := sapply(format(Date, "%Y-%m"), ym_add, k = 1L)]
FMr <- merge(FM_B, ureg[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_tab <- FMr[!is.na(Category), .(n = .N, mean_b = mean(get(cn_int)), t_nw = nw_t(get(cn_int))),
               by = Category]
say("d7 국면별 (홀딩월 unified Category):"); print(reg_tab)
ax001 <- reg_tab[Category == "CRISIS"]

# ── 7. d8 cap-tier ───────────────────────────────────────────────────────────
REG[, size_rank := frank(-Size, ties.method = "first"), by = Date]
REG[, tier := fifelse(size_rank <= 10, "MEGA", fifelse(size_rank <= 30, "MID", "OTHER"))]
f_red <- Ret_1m ~ zrank + zmax5 + zrank:zmax5     # 소형 셀 축약 스펙 (저검정력 라벨)
tier_tab <- rbindlist(lapply(c("MEGA", "MID", "OTHER"), function(tt) {
  sub <- REG[tier == tt]
  form <- if (tt == "OTHER") f_B else f_red
  FMt <- fm_run(sub, form, cn_int)
  data.table(tier = tt, spec = if (tt == "OTHER") "full" else "reduced_low_power",
             n_months = nrow(FMt), mean_b = FMt[, mean(get(cn_int))], t_nw = nw_t(FMt[[cn_int]]))
}))
# TOP30 결합 셀 (MEGA+MID, 축약 스펙)
FM_t30 <- fm_run(REG[tier %in% c("MEGA", "MID")], f_red, cn_int)
tier_tab <- rbind(tier_tab, data.table(tier = "TOP30_combined", spec = "reduced_low_power",
             n_months = nrow(FM_t30), mean_b = FM_t30[, mean(get(cn_int))],
             t_nw = nw_t(FM_t30[[cn_int]])))
say("d8 cap-tier:"); print(tier_tab)

# ── 8. d9 이중 정렬 5×5 (기술 서술) ─────────────────────────────────────────
REG[, q_rank := pmin(5L, 1L + as.integer(5 * (frank(zrank, ties.method = "first") - 1) / .N)), by = Date]
REG[, q_max5 := pmin(5L, 1L + as.integer(5 * (frank(zmax5, ties.method = "first") - 1) / .N)), by = Date]
DS <- REG[, .(mret = mean(Ret_1m)), by = .(Date, q_rank, q_max5)]
grid55 <- DS[, .(mret = mean(mret)), by = .(q_rank, q_max5)][order(q_rank, q_max5)]
spread_by_rank <- rbindlist(lapply(1:5, function(qr) {
  s <- dcast(DS[q_rank == qr], Date ~ q_max5, value.var = "mret")
  if (!all(c("1", "5") %in% names(s))) return(NULL)
  sp <- s[["5"]] - s[["1"]]
  data.table(q_rank = qr, mean_spread = mean(sp, na.rm = TRUE), t_nw = nw_t(sp))
}))
say("d9 rank분위별 max5 Q5-Q1 스프레드:"); print(spread_by_rank)

# ── 9. 문턱 근방 섭동 (조건부 — |t_B| ∈ [1.5, 2.5]) ──────────────────────────
perturb <- NULL
if (is.finite(t_B) && abs(t_B) >= 1.5 && abs(t_B) <= 2.5) {
  say("★ 문턱 근방 (t=%.3f) — 멤버십 섭동 5 seeds 실행 (FQ-109)", t_B)
  pt <- sapply(1:5, function(sd_i) {
    set.seed(2026080310 + sd_i)
    RS <- REG[, .SD[sample(.N, size = floor(.N * 0.95))], by = Date]
    RS <- prep_z(RS)
    FMs <- fm_run(RS, f_B, cn_int)
    nw_t(FMs[[cn_int]])
  })
  perturb <- list(seeds_t = pt, q05 = quantile(pt, 0.05, type = 7), q95 = quantile(pt, 0.95, type = 7))
  say("섭동 t 분포: %s | q05=%.3f q95=%.3f", paste(sprintf("%+.3f", pt), collapse = " "),
      perturb$q05, perturb$q95)
} else say("문턱 근방 아님 (t=%.3f) — 섭동 생략 (사전등록 조건 미충족)", t_B)

# ── 10. 사전등록 판정 ────────────────────────────────────────────────────────
verdict <- if (is.finite(t_B) && t_B >= 2.0) "WINNER_MARKER_CONFIRMED" else
           if (is.finite(t_B) && t_B <= -2.0) "EXCLUSION_FRAME_SUPPORTED" else "INCONCLUSIVE"
attribution <- if (verdict == "WINNER_MARKER_CONFIRMED" && is.finite(t_C) && t_C >= 2.0)
  "MAX5_SPECIFIC" else if (verdict == "WINNER_MARKER_CONFIRMED")
  "SHORT_VOL_INTERACTION_REEXPRESSION" else NA_character_
say("★ 사전등록 판정: %s (t_B=%+.3f) | attribution: %s", verdict, t_B, attribution)

# ── 11. 저장 ─────────────────────────────────────────────────────────────────
saveRDS(list(
  vintage = vintage, validator = v_pass, injection = inj,
  missingness = miss, collinearity = ctab,
  arms = list(
    B = list(series = FM_B, summ = fm_summ(FM_B, c("zrank", "zmax5", cn_int)), t_int = t_B),
    A = list(series = FM_A, t_int = t_A),
    C = list(series = FM_C, t_int = t_C, mean_rank_d35 = FM_C[, mean(`zrank:D35_RealVol_63d`)]),
    lag1 = list(t_int = t_L, mean_b = FM_L[, mean(`zrank:zmax5_lag`)])),
  eff_top_q90 = list(mean = FMq[, mean(eff_top)], t = nw_t(FMq$eff_top)),
  placebo = plac,
  top40 = list(ctrl = list(mean_b = FM_T[, mean(zmax5_s)], t = t_T, n = nrow(FM_T)),
               noctrl = list(mean_b = FM_T0[, mean(zmax5_s)], t = nw_t(FM_T0$zmax5_s))),
  subperiod = sub_tab, regime = reg_tab, ax001_crisis = ax001,
  tier = tier_tab, double_sort = list(grid = grid55, spread_by_rank = spread_by_rank),
  perturbation = perturb,
  verdict = list(primary = verdict, attribution = attribution, t_B = t_B, t_A = t_A,
                 t_C = t_C, t_lag1 = t_L)
), file.path(OUT, "wt001_fm_results.rds"))

SIG <- REG[, .(Date, Ticker, score_eff, zrank, zmax5, interaction = zrank * zmax5)]
write_parquet(SIG, file.path(OUT, "alpha_scores.parquet"))
say("저장 완료 — wt001_fm_results.rds + alpha_scores.parquet (%d행)", nrow(SIG))
say("DONE")
