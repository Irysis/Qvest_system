# =============================================================================
# run_wt020_eval.R — WT-D20260802_020 MAX5 종목-레벨 crash 예측력 (FQ-112)
#   사전등록: stage_artifacts/WT_D20260802_020/preregistration.json (측정 전 고정)
#
#   primary = FM: crash_{i,t+1} ~ z(max5) + D01_IdioVol + D02_Beta + D03_RealVol
#             + D45_Downside_Dev  (월별 횡단면 LPM, b_max5 시계열 NW lag-3 t)
#   판정    = mean(b_max5)>0 AND t>=2.0 → 증분 실재 / t<2 → 변동성 재포장(정직 닫힘)
#   Σ/weights 계산 없음 — 예측력 특성화만 (역할 경계)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_020/run_wt020_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_020")
say <- function(fmt, ...) cat(sprintf(paste0("[wt020] ", fmt, "\n"), ...))
`%||%` <- function(a, b) if (is.null(a)) b else a

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

# ── 1. 입력 로드 ─────────────────────────────────────────────────────────────
EX <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_014/alpha_scores.parquet"))
EX[, Date := as.Date(Date)]
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
SIZE <- as.data.table(SI$SIZE); liqf <- as.data.table(SI$liqf)
for (dt in list(fwd, bench, SIZE, liqf)) dt[, Date := as.Date(Date)]
CP <- as.data.table(read_parquet(file.path(OUT, "controls_panel.parquet")))
CP[, Date := as.Date(Date)]
PAN <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_010/ot_panel.parquet"))
PAN[, Date := as.Date(Date)]
say("입력: EX %d행/%d월, controls %d행, fwd %d행", nrow(EX), uniqueN(EX$Date), nrow(CP), nrow(fwd))

# ── 2. Forward 라벨 방향 검증 (PIT) + 위반 주입 ──────────────────────────────
grid <- sort(unique(fwd$Date))
tk_need <- unique(EX$Ticker)
RD <- as.data.table(
  open_dataset(".cache/RAWDATA.parquet") %>%
    select(Date, Ticker, Ret) %>%
    filter(Date > as.Date("2004-12-01")) %>%
    collect())
RD <- RD[Ticker %chin% tk_need & is.finite(Ret)]
RD[, Date := as.Date(Date)]
RD[, iv := findInterval(as.numeric(Date) - 0.5, as.numeric(grid))]
RD <- RD[iv >= 1L & iv <= length(grid)]
RECON <- RD[, .(recon = prod(1 + Ret) - 1, nd = .N), by = .(Date = grid[iv], Ticker)]
say("recon: %d 종목-월 (일간 저장 Ret 복리 — 검증 전용, ret_firewall 준수)", nrow(RECON))

# 벤치 parity (in-sample 전월): 일간 BM_Ret 복리 재구성 vs screen_inputs bench
ex_dates <- sort(unique(EX$Date))
BMD <- as.data.table(
  open_dataset(".cache/RAWDATA.parquet") %>%
    select(Date, BM_Ret) %>%
    filter(Date > as.Date("2004-12-01")) %>%
    collect())
BMD <- unique(BMD[is.finite(BM_Ret), .(Date = as.Date(Date), BM_Ret)])
BMD[, iv := findInterval(as.numeric(Date) - 0.5, as.numeric(grid))]
BMD <- BMD[iv >= 1L & iv <= length(grid)]
BREC <- BMD[, .(brecon = prod(1 + BM_Ret) - 1), by = .(Date = grid[iv])]
bcmp <- merge(bench[Date %in% ex_dates], BREC, by = "Date")
bcmp[, adiff := abs(BM_Ret - brecon)]
setorder(bcmp, -adiff)
say("벤치 2소스 정합(진단 — 방향 게이트 아님): median|diff| %.6f / max|diff| %.6f / >1%% 월 %d개",
    median(bcmp$adiff), max(bcmp$adiff), bcmp[adiff > 0.01, .N])
say("  worst 5: %s", paste(sprintf("%s(%.4f)", as.character(bcmp$Date[1:5]), bcmp$adiff[1:5]), collapse=" "))
bench_coherence_flag <- list(
  known_family = "benchmark two-source divergence (08-02 사건 계보 — 독립 생성 + 정합 검사 부재)",
  median_abs_diff = median(bcmp$adiff), max_abs_diff = max(bcmp$adiff),
  worst_months = as.character(bcmp$Date[1:5]),
  load_bearing_here = FALSE,
  rationale = "본 라운드 crash 라벨 = 종목 횡단면(벤치 무관여). WT-014/016 paired Δactive는 bench 완전 상쇄. 포트 tail 진단(부수)만 ab 경유 간접 노출 — 해당 진단에 라벨 병기."
)

validate_forward_label <- function(lab_dt, recon_dt, min_cor = 0.99, label_name = "Ret_1m") {
  m <- merge(lab_dt[, .(Date, Ticker, lab = get(label_name))],
             recon_dt[, .(Date, Ticker, recon)], by = c("Date", "Ticker"))
  m <- m[is.finite(lab) & is.finite(recon)]
  cc_all <- m[, cor(lab, recon)]
  cc_m <- m[, .(cc = if (.N >= 30) cor(lab, recon) else NA_real_), by = Date]
  med_cc <- median(cc_m$cc, na.rm = TRUE)
  worst_cc <- min(cc_m$cc, na.rm = TRUE)
  say("  [validator %s] cor 전체 %.4f / 월중앙 %.4f / 월최악 %.4f", label_name, cc_all, med_cc, worst_cc)
  if (!is.finite(cc_all) || cc_all < min_cor || !is.finite(med_cc) || med_cc < min_cor)
    stop(sprintf("LABEL DIRECTION FAIL — 독립 재계산과 cor %.4f/%.4f < %.2f (라벨이 익월 수익이 아님)",
                 cc_all, med_cc, min_cor))
  list(cor_all = cc_all, cor_monthly_median = med_cc, cor_monthly_worst = worst_cc, n_pairs = nrow(m))
}

lab_true <- fwd[Date %in% ex_dates, .(Date, Ticker, Ret_1m)]
v_pass <- validate_forward_label(lab_true, RECON)
say("방향 검증 PASS — fwd Ret_1m = 익월 수익 실증 (n_pairs=%d)", v_pass$n_pairs)

# ★배관 결함 발견 기록 (사양 밖 — 본 표본 비오염): screen_inputs bench의 마지막 라벨월
# (d0=2026-06-30)은 패널 빌드일(07-14)까지의 부분월 복리(-0.2001 ≈ through 7/14 -0.2032)
# — 정본 7월 전월 -0.2363 아님. 본 표본은 d0<=2026-03-31이라 미소비. 소비 금지 플래그만 기록.
last_lab <- bench[Date == as.Date("2026-06-30"), BM_Ret]
full_july <- BREC[Date == as.Date("2026-06-30"), brecon]
data_currency_flag <- list(
  artifact = "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
  defect = sprintf("d0=2026-06-30 라벨월 = 부분월(빌드일 07-14 절단): bench %.4f vs 전월 정본 %.4f",
                   ifelse(length(last_lab), last_lab, NA), ifelse(length(full_july), full_july, NA)),
  contaminates_this_round = FALSE,
  rule = "이 패널의 d0 >= 2026-04-30 라벨(익월수익) 소비 금지 — 재빌드 후 소비"
)
say("★data_currency_flag: %s", data_currency_flag$defect)

# 위반 주입: 동월(t) 수익을 라벨로 위장 — 검증기가 FAIL을 발화해야 검사 실효 입증
g_prev <- setNames(c(NA, head(as.character(grid), -1)), as.character(grid))
BAD <- copy(RECON)[, Date_next := {
  idx <- match(as.character(Date), as.character(grid)) + 1L
  as.Date(ifelse(idx <= length(grid), as.character(grid[idx]), NA))
}]
BAD <- BAD[!is.na(Date_next), .(Date = Date_next, Ticker, Ret_1m = recon)]  # d0에 동월(직전구간) 수익 부착
inj <- tryCatch({ validate_forward_label(BAD[Date %in% ex_dates], RECON); list(fired = FALSE) },
                error = function(e) list(fired = TRUE, msg = conditionMessage(e)))
if (!inj$fired) stop("위반 주입 테스트 실패 — 검증기가 동월 라벨을 통과시킴 (검사 사망)")
say("위반 주입 FIRED — 동월 라벨 주입 시 검증기 stop() 발화 확인: %s", substr(inj$msg, 1, 80))

# ── 3. 패널 조립 + 라벨 ─────────────────────────────────────────────────────
P <- merge(EX[, .(Date, Ticker, max5)], fwd, by = c("Date", "Ticker"), all.x = TRUE)
na_lab <- P[, mean(!is.finite(Ret_1m))]
say("라벨 결측(익월 수익 없음 — 상폐/정지 등): %.2f%% (생존편향 방향: crash 탐지 하향 — 한계 기록)", 100 * na_lab)
P <- P[is.finite(Ret_1m)]
P[, `:=`(crash = as.integer(Ret_1m <= quantile(Ret_1m, 0.10, type = 7)),
         boom  = as.integer(Ret_1m >= quantile(Ret_1m, 0.90, type = 7))), by = Date]
P[, crash_abs := as.integer(Ret_1m <= -0.20)]
P <- merge(P, CP, by = c("Date", "Ticker"), all.x = TRUE)
P <- merge(P, SIZE, by = c("Date", "Ticker"), all.x = TRUE)
P <- merge(P, PAN[, .(Date, Ticker, vol63, dsd63)], by = c("Date", "Ticker"), all.x = TRUE)

wz <- function(x) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s == 0) return(rep(NA_real_, length(x)))
  x <- pmin(pmax(x, m - 3 * s), m + 3 * s)
  (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
}
P[, zmax5 := wz(max5), by = Date]
P[, `:=`(zvol63 = wz(vol63), zdsd63 = wz(dsd63)), by = Date]

ctrl <- c("D01_IdioVol", "D02_Beta", "D03_RealVol", "D45_Downside_Dev")
REG <- P[is.finite(zmax5) & is.finite(D01_IdioVol) & is.finite(D02_Beta) &
         is.finite(D03_RealVol) & is.finite(D45_Downside_Dev)]
mn <- REG[, .N, by = Date]
keep_d <- mn[N >= 100, Date]
REG <- REG[Date %in% keep_d]
say("회귀 표본: %d행 / %d월 (n>=100 게이트로 제외 %d월) / 표본 내 crash base rate %.4f",
    nrow(REG), length(keep_d), uniqueN(P$Date) - length(keep_d), REG[, mean(crash)])

# 공선성 실측 (사전 posterior p1)
ctab <- REG[, .(c_D01 = cor(zmax5, D01_IdioVol), c_D02 = cor(zmax5, D02_Beta),
                c_D03 = cor(zmax5, D03_RealVol), c_D45 = cor(zmax5, D45_Downside_Dev),
                c_vol63 = cor(zmax5, zvol63, use = "pair"),
                c_dsd63 = cor(zmax5, zdsd63, use = "pair")), by = Date]
say("collinearity(월평균 cor): D01 %+.3f D02 %+.3f D03 %+.3f D45 %+.3f vol63 %+.3f dsd63 %+.3f",
    ctab[, mean(c_D01)], ctab[, mean(c_D02)], ctab[, mean(c_D03)],
    ctab[, mean(c_D45)], ctab[, mean(c_vol63, na.rm = TRUE)], ctab[, mean(c_dsd63, na.rm = TRUE)])

# ── 4. FM 월별 횡단면 회귀 ───────────────────────────────────────────────────
fm_run <- function(dt, form, coef_name = "zmax5") {
  dd <- sort(unique(dt$Date))
  out <- lapply(dd, function(d) {
    sub <- dt[Date == d]
    fit <- tryCatch(lm(form, data = sub), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    co <- coef(fit)
    data.table(Date = d, b = unname(co[coef_name]), r2 = summary(fit)$r.squared, n = nrow(sub))
  })
  rbindlist(Filter(Negate(is.null), out))
}
f_full <- crash ~ zmax5 + D01_IdioVol + D02_Beta + D03_RealVol + D45_Downside_Dev
f_uni  <- crash ~ zmax5
f_ctrl <- crash ~ D01_IdioVol + D02_Beta + D03_RealVol + D45_Downside_Dev
f_sw   <- crash ~ zmax5 + zvol63 + zdsd63
f_abs  <- crash_abs ~ zmax5 + D01_IdioVol + D02_Beta + D03_RealVol + D45_Downside_Dev
f_boom <- boom ~ zmax5 + D01_IdioVol + D02_Beta + D03_RealVol + D45_Downside_Dev

FM_full <- fm_run(REG, f_full)
FM_uni  <- fm_run(REG, f_uni)
FM_ctrl <- fm_run(REG, f_ctrl, coef_name = "D01_IdioVol")  # b는 비소비 — r2만 사용
FM_sw   <- fm_run(REG[is.finite(zvol63) & is.finite(zdsd63)], f_sw)
FM_abs  <- fm_run(REG, f_abs)
FM_boom <- fm_run(REG, f_boom)

t_full <- nw_t(FM_full$b); t_uni <- nw_t(FM_uni$b)
t_sw <- nw_t(FM_sw$b); t_abs <- nw_t(FM_abs$b); t_boom <- nw_t(FM_boom$b)
r2_inc <- merge(FM_full[, .(Date, r2f = r2)], FM_ctrl[, .(Date, r2c = r2)], by = "Date")
say("★ PRIMARY FM full: mean(b_max5)=%+.5f NW t=%+.3f (판정 기준 t>=2.0, n=%d월)",
    FM_full[, mean(b)], t_full, nrow(FM_full))
say("  univariate:      mean b=%+.5f t=%+.3f", FM_uni[, mean(b)], t_uni)
say("  same-window ctrl: mean b=%+.5f t=%+.3f (n=%d월)", FM_sw[, mean(b)], t_sw, nrow(FM_sw))
say("  abs(-20%%) label:  mean b=%+.5f t=%+.3f", FM_abs[, mean(b)], t_abs)
say("  boom(상방) label: mean b=%+.5f t=%+.3f", FM_boom[, mean(b)], t_boom)
say("  R2: ctrl-only %.4f → full %.4f (증분 %.4f)",
    r2_inc[, mean(r2c)], r2_inc[, mean(r2f)], r2_inc[, mean(r2f - r2c)])

# 잔차 신호 (risk_package 이식 후보 형태 — 통제 4축 직교화 잔차)
REG[, resid_zmax5 := {
  fit <- lm(zmax5 ~ D01_IdioVol + D02_Beta + D03_RealVol + D45_Downside_Dev)
  as.numeric(residuals(fit))
}, by = Date]

# ── 5. 발생률 lift (top-decile max5) ────────────────────────────────────────
REG[, top_max5 := zmax5 >= quantile(zmax5, 0.90, type = 7), by = Date]
INC <- REG[, .(p_top = mean(crash[top_max5]), p_base = mean(crash),
               b_top = mean(boom[top_max5]), b_base = mean(boom),
               ret_spread = mean(Ret_1m[top_max5]) - mean(Ret_1m[!top_max5]),
               n_top = sum(top_max5)), by = Date]
say("발생률: crash P(top)=%.4f vs base %.4f (lift %+.4f, NW t=%+.2f) | boom P(top)=%.4f vs %.4f (lift %+.4f, t=%+.2f)",
    INC[, mean(p_top)], INC[, mean(p_base)], INC[, mean(p_top - p_base)], nw_t(INC[, p_top - p_base]),
    INC[, mean(b_top)], INC[, mean(b_base)], INC[, mean(b_top - b_base)], nw_t(INC[, b_top - b_base]))
say("  익월 수익 스프레드(top−rest): %+.5f/월 (NW t=%+.2f)",
    INC[, mean(ret_spread)], nw_t(INC$ret_spread))

# ── 6. 국면 조건부 (hold_ym = d0월+1) — CRISIS 긴장 해소 ────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
FM_full[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
INC[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
FMr <- merge(FM_full, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
INCr <- merge(INC, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_fm <- FMr[!is.na(Category), .(n = .N, mean_b = mean(b), t_nw = nw_t(b)), by = Category]
reg_inc <- INCr[!is.na(Category),
                .(crash_lift = mean(p_top - p_base), t_crash = nw_t(p_top - p_base),
                  boom_lift = mean(b_top - b_base), t_boom = nw_t(b_top - b_base),
                  ret_spread = mean(ret_spread), t_spread = nw_t(ret_spread), n = .N),
                by = Category]
say("--- 국면별 b_max5 (full model) ---")
for (i in seq_len(nrow(reg_fm)))
  say("  %-8s n=%3d mean_b=%+.5f t=%+.2f", reg_fm$Category[i], reg_fm$n[i], reg_fm$mean_b[i], reg_fm$t_nw[i])
say("--- 국면별 양측 꼬리 (top-decile max5) ---")
for (i in seq_len(nrow(reg_inc)))
  say("  %-8s n=%3d crash_lift=%+.4f(t%+.2f) boom_lift=%+.4f(t%+.2f) ret_spread=%+.5f(t%+.2f)",
      reg_inc$Category[i], reg_inc$n[i], reg_inc$crash_lift[i], reg_inc$t_crash[i],
      reg_inc$boom_lift[i], reg_inc$t_boom[i], reg_inc$ret_spread[i], reg_inc$t_spread[i])

# ── 7. cap-tier 분해 ─────────────────────────────────────────────────────────
REG[, size_rank := frank(-Size, ties.method = "first"), by = Date]
REG[, tier := fifelse(size_rank <= 10, "MEGA", fifelse(size_rank <= 30, "MID", "OTHER"))]
REG[, top_tier := zmax5 >= quantile(zmax5, 0.90, type = 7), by = .(Date, tier)]
TIER <- REG[, .(p_top = mean(crash[top_tier]), p_base = mean(crash),
                n_top = sum(top_tier), n = .N), by = .(Date, tier)]
tier_tab <- TIER[is.finite(p_top),
                 .(crash_lift = mean(p_top - p_base), t_nw = nw_t(p_top - p_base),
                   mean_base = mean(p_base), n_months = .N, mean_n_top = mean(n_top)), by = tier]
FM_oth <- fm_run(REG[tier == "OTHER"], f_full)
t_oth <- nw_t(FM_oth$b)
say("--- cap-tier (tier 내 상대 top-decile) ---")
for (i in seq_len(nrow(tier_tab)))
  say("  %-6s crash_lift=%+.4f (t=%+.2f) base=%.4f n_top/월=%.1f",
      tier_tab$tier[i], tier_tab$crash_lift[i], tier_tab$t_nw[i],
      tier_tab$mean_base[i], tier_tab$mean_n_top[i])
say("  OTHER 내 FM full: mean_b=%+.5f t=%+.3f (n=%d월)", FM_oth[, mean(b)], t_oth, nrow(FM_oth))

# ── 8. 포트폴리오-레벨 tail 진단 (부수, 저검정력 라벨) ───────────────────────
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
CLEAN <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
CLEAN[, Date := as.Date(Date)]
stopifnot(CLEAN$vintage_verified[1] == "production_parity_verified")
d0map <- data.table(d0 = grid); d0map[, ym := format(d0, "%Y-%m")]
CL <- copy(CLEAN); CL[, map_ym := format(Date - 1, "%Y-%m")]
CLd <- merge(CL, d0map, by.x = "map_ym", by.y = "ym")
S0 <- merge(CLd[is.finite(score_eff), .(Date = d0, Ticker, sc = score_eff)], SIZE, by = c("Date", "Ticker"))
S0 <- merge(S0, liqf, by = c("Date", "Ticker"), all.x = TRUE)
S0 <- S0[is.na(adv) | adv >= 2e8]
Wb <- rbindlist(lapply(sort(unique(S0$Date)), function(d) {
  sub <- S0[Date == d]; if (nrow(sub) < 25) return(NULL)
  setorder(sub, -sc); hd <- head(sub, 25)
  data.table(Date = d, Ticker = hd$Ticker, w = cap_norm(hd$Size))
}))
EXPO <- merge(Wb, REG[, .(Date, Ticker, zmax5)], by = c("Date", "Ticker"), all.x = TRUE)
expo_m <- EXPO[, .(expo = sum(w * fifelse(is.finite(zmax5), zmax5, 0)),
                   cov_w = sum(w[is.finite(zmax5)])), by = Date]
R14 <- readRDS("stage_artifacts/WT_D20260802_014/wt014_eval_results.rds")
PD <- as.data.table(R14$paired_series)[, .(Date = as.Date(date), ab)]
PT <- merge(expo_m, PD, by = "Date")
fit_p <- lm(ab ~ expo, data = PT)
t_expo <- tryCatch(as.numeric(lmtest::coeftest(fit_p,
    vcov. = sandwich::NeweyWest(fit_p, lag = 3, prewhite = FALSE))["expo", 3]), error = function(e) NA_real_)
thr_tail <- quantile(PT$ab, 0.05, type = 7)
PT[, tail5 := ab <= thr_tail]
wt <- tryCatch(wilcox.test(PT[tail5 == TRUE, expo], PT[tail5 == FALSE, expo]), error = function(e) NULL)
say("포트 tail(부수): expo→active OLS b=%+.5f NW t=%+.2f | tail월(n=%d) 사전 expo %+.4f vs 비tail %+.4f (Wilcoxon p=%.3f) | expo 커버리지(w) %.2f",
    coef(fit_p)["expo"], t_expo, PT[, sum(tail5)], PT[tail5 == TRUE, mean(expo)],
    PT[tail5 == FALSE, mean(expo)], ifelse(is.null(wt), NA, wt$p.value), expo_m[, mean(cov_w)])
say("  (라벨: ab는 SI bench 경유 — bench 2소스 정합 worst월 %s의 tail 분류 여부 = %s)",
    as.character(bcmp$Date[1]), as.character(PT[Date == bcmp$Date[1], tail5]))

# ── 9. 저장 ──────────────────────────────────────────────────────────────────
saveRDS(list(
  validator = v_pass, injection = inj, na_label_share = na_lab,
  data_currency_flag = data_currency_flag, bench_coherence_flag = bench_coherence_flag,
  bench_cmp = bcmp,
  collinearity = ctab, r2 = list(ctrl_only = r2_inc[, mean(r2c)], full = r2_inc[, mean(r2f)]),
  fm = list(full = list(mean_b = FM_full[, mean(b)], t = t_full, n = nrow(FM_full), series = FM_full),
            uni = list(mean_b = FM_uni[, mean(b)], t = t_uni),
            sw = list(mean_b = FM_sw[, mean(b)], t = t_sw, n = nrow(FM_sw)),
            abs = list(mean_b = FM_abs[, mean(b)], t = t_abs),
            boom = list(mean_b = FM_boom[, mean(b)], t = t_boom)),
  incidence = list(summary = INC, crash_lift = INC[, mean(p_top - p_base)],
                   t_crash = nw_t(INC[, p_top - p_base]),
                   boom_lift = INC[, mean(b_top - b_base)],
                   t_boom = nw_t(INC[, b_top - b_base]),
                   ret_spread = INC[, mean(ret_spread)], t_spread = nw_t(INC$ret_spread)),
  regime = list(fm = reg_fm, inc = reg_inc),
  tier = list(inc = tier_tab, fm_other = list(mean_b = FM_oth[, mean(b)], t = t_oth, n = nrow(FM_oth))),
  portfolio = list(b_expo = coef(fit_p)["expo"], t_expo = t_expo,
                   tail_expo = PT[tail5 == TRUE, mean(expo)],
                   nontail_expo = PT[tail5 == FALSE, mean(expo)],
                   wilcox_p = ifelse(is.null(wt), NA, wt$p.value),
                   n_tail = PT[, sum(tail5)], series = PT)
), file.path(OUT, "wt020_eval_results.rds"))

SIG <- REG[, .(Date, Ticker, max5, zmax5, resid_zmax5)]
write_parquet(SIG, file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt020_eval_results.rds + alpha_scores.parquet (%d행 신호 패널, 라벨 미포함)", nrow(SIG))
