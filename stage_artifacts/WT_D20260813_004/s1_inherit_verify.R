# WT-D20260813_004 — Alpha Research (승계 전용 얇은 패스)
# 목적: 신호 패널 승계 parity 실측 + risk-research 소비 인터페이스 검증(축/결측/PIT/lag/조인키).
# ★금지 준수: 공분산 추정 0 · weight 결정 0 · 성과 측정(canonical_screen_bt/forge) 0 · 신규 팩터 소싱 0.
#   본 스크립트의 모든 상관/회귀는 '축 식별 + PIT 방향 진단' 용도이며 성과 통계량이 아니다.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260813_004")
P3   <- file.path(ROOT, "stage_artifacts/WT_D20260813_003/alpha_scores.parquet")
P2   <- file.path(ROOT, "stage_artifacts/WT_D20260813_002/alpha_scores.parquet")
BOOK <- file.path(ROOT, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")

d3 <- as.data.table(read_parquet(P3))
d2 <- as.data.table(read_parquet(P2))
R  <- list()

# ---------- S1. 축(Date 컨벤션) 무결성 ----------
first_day <- function(ym) as.Date(paste0(ym, "-01"))
axis_one <- function(d, tag) {
  ymv <- d$ym
  list(
    tag                    = tag,
    n_rows                 = nrow(d),
    ym_class               = class(d$ym)[1],
    ym_format_ok           = all(grepl("^[0-9]{4}-[0-9]{2}$", ymv)),
    ym_unique              = length(unique(ymv)) == nrow(d),
    ym_sorted_ascending    = !is.unsorted(ymv),
    ym_range               = c(min(ymv), max(ymv)),
    n_months_expected      = length(seq(first_day(min(ymv)), first_day(max(ymv)), by = "month")),
    calendar_gaps          = setdiff(format(seq(first_day(min(ymv)), first_day(max(ymv)), by = "month"), "%Y-%m"), ymv),
    hold_start_is_month1   = all(d$hold_start == first_day(ymv)),
    cutoff_equals_holdstart= all(d$signal_cutoff == d$hold_start),
    cutoff_minus_holdstart_days_range = range(as.integer(d$signal_cutoff - d$hold_start))
  )
}
R$axis <- list(wt003 = axis_one(d3, "WT_D20260813_003"), wt002 = axis_one(d2, "WT_D20260813_002"))

# ---------- S2. 결측 census ----------
na_census <- function(d) { x <- sapply(d, function(c) sum(is.na(c))); as.list(x[x > 0]) }
R$missing <- list(
  wt003_cols_with_na = na_census(d3), wt003_total_na = sum(sapply(d3, function(c) sum(is.na(c)))),
  wt002_cols_with_na = na_census(d2), wt002_total_na = sum(sapply(d2, function(c) sum(is.na(c))))
)

# ---------- S3. 승계 parity (재구축 아님 — 실측) ----------
mm <- merge(d3[, .(ym, sigma_hat_daily, sigma_hat_monthly, exposure_e, bm_ret_holding_month, realized_vol_in_month)],
            d2[, .(ym, VOL, TAIL, MSM, BEAR, bm_ret)], by = "ym", all = FALSE)
setorder(mm, ym)
n_theory_join <- length(intersect(d3$ym, d2$ym))
R$join_003_002 <- list(
  key = "ym (chr YYYY-MM)",
  n_wt003 = nrow(d3), n_wt002 = nrow(d2),
  n_joined = nrow(mm), n_theory = n_theory_join,
  join_matches_theory = nrow(mm) == n_theory_join,
  loss_vs_smaller_pct = round(100 * (1 - nrow(mm) / min(nrow(d3), nrow(d2))), 4),
  dropped_ym = sort(union(setdiff(d3$ym, d2$ym), setdiff(d2$ym, d3$ym)))
)

sh <- mm$sigma_hat_daily; vol <- mm$VOL
exp_z <- function(x) { n <- length(x); o <- rep(NA_real_, n)
  for (i in seq_len(n)) { s <- stats::sd(x[1:i]); if (is.finite(s) && s > 0) o[i] <- (x[i] - mean(x[1:i])) / s }
  o }
# ★ 정본 basis (코드에서 읽음, 추정 아님):
#   WT-002 f1b_diagnosis.R:30 `VOL := exp_z(vol)` · WT-003 s1_prereg.R:50-53 동일 exp_z.
#   ★★ 결정적: exp_z 는 anchored 변환이라 **격자 시점(warm-up)** 이 값을 정한다.
#   두 라운드의 격자 = RAWDATA 벤치 전구간에서 252d 충족 월 전부(427개월, 1991-02~2026-08).
#   emitted 패널(366/367행, 1996-02~) 은 그 격자의 **창(window)** 이라 warm-up 60개월이 빠져 있다.
#   따라서 emitted 패널만으로 exp_z 를 재현하면 값이 다르다 — 승계 불일치가 아니라 warm-up 결손.
RAW <- file.path(ROOT, ".cache/RAWDATA.parquet")
BDr <- unique(as.data.table(read_parquet(RAW, col_select = c("Date", "BM_Ret"))), by = "Date")
BDr <- BDr[order(Date)][is.finite(BM_Ret)][Date <= as.Date("2026-08-08")]   # 말단 0채움 배제 (WT-002/003 규약)
BDr[, ym := format(Date, "%Y-%m")]
MOr <- BDr[, .(n_days = .N), by = ym][order(ym)]
MOr[, hold_start := as.Date(paste0(ym, "-01"))]
LB <- 252L
MOr[, sigma_d := vapply(hold_start, function(cut) { r <- BDr[Date < cut, BM_Ret]
  if (length(r) < LB) return(NA_real_); stats::sd(tail(r, LB)) }, numeric(1))]
Sg <- MOr[is.finite(sigma_d)]
Sg[, VOL_rebuilt := exp_z(sigma_d)]

j_lvl <- merge(Sg[, .(ym, sigma_d)],     d3[, .(ym, sigma_hat_daily)], by = "ym")
j_z   <- merge(Sg[, .(ym, VOL_rebuilt)], d2[, .(ym, VOL)],             by = "ym")
# 대조군: emitted 창(366행)만으로 exp_z 재현 시도 = warm-up 결손판
naive_z <- exp_z(sh); okn <- is.finite(naive_z)

R$inheritance_parity <- list(
  declared_basis = "expanding z-score(exp_z) on anchored grid — 정의 WT-002/f1b_diagnosis.R:30, 재구축 WT-003/s1_prereg.R:50-53",
  reconstruction_grid = list(
    daily_source = ".cache/RAWDATA.parquet::BM_Ret (unique Date, finite, Date <= 2026-08-08)",
    daily_n = nrow(BDr), daily_range = c(format(min(BDr$Date)), format(max(BDr$Date))),
    anchored_grid_months = nrow(Sg), anchored_grid_range = c(Sg$ym[1], Sg$ym[nrow(Sg)]),
    warmup_months_before_panel_start = sum(Sg$ym < min(d2$ym)),
    note = "★emitted 패널(366/367)은 427개월 격자의 창 — anchored 변환(exp_z / expanding median sigma_star)은 패널만으로 재현 불가."
  ),
  level_parity_sigma_hat = list(
    pair = "reconstructed sigma_d (full grid) vs WT-003 alpha_scores.sigma_hat_daily",
    n = nrow(j_lvl), n_theory = nrow(d3), matches_theory = nrow(j_lvl) == nrow(d3),
    max_abs_diff = max(abs(j_lvl$sigma_d - j_lvl$sigma_hat_daily)),
    spearman = cor(j_lvl$sigma_d, j_lvl$sigma_hat_daily, method = "spearman")
  ),
  z_parity_VOL = list(
    pair = "reconstructed exp_z (full grid) vs WT-002 alpha_scores.VOL",
    n = nrow(j_z), n_theory = nrow(d2), matches_theory = nrow(j_z) == nrow(d2),
    max_abs_diff = max(abs(j_z$VOL_rebuilt - j_z$VOL)),
    spearman = cor(j_z$VOL_rebuilt, j_z$VOL, method = "spearman")
  ),
  warmup_truncation_control = list(
    pair = "exp_z(emitted 366행만) vs WT-002 VOL — warm-up 60개월 결손판",
    n = sum(okn),
    max_abs_diff = max(abs(naive_z[okn] - vol[okn])),
    spearman = cor(naive_z[okn], vol[okn], method = "spearman"),
    note = "정상 자료에 잘못된 격자를 적용하면 이 값이 나온다. 0 이 아닌 이 수치를 '승계 불일치'로 읽는 것이 본 인터페이스의 최대 오독 위험 — risk-research 는 anchored 변환을 재현할 때 반드시 427개월 격자에서 산출할 것."
  ),
  bm_ret_parity = list(
    max_abs_diff = max(abs(mm$bm_ret_holding_month - mm$bm_ret)),
    identical    = isTRUE(all.equal(mm$bm_ret_holding_month, mm$bm_ret, tolerance = 0))
  ),
  prereg_wt003_claim = list(spearman = 1, max_abs_diff = 0, n = 367,
    note = "WT-003 prereg_VT.json 기록치 — 본 라운드 독립 재실측으로 재현됨(z_parity_VOL).")
)

# ---------- S4. PIT / lag 구조 진단 ----------
setorder(d3, ym)
sig <- d3$sigma_hat_daily; rv <- d3$realized_vol_in_month; n <- nrow(d3)
ac1 <- function(x) cor(x[-1], x[-length(x)])
# PIT 방향 검사(위반 주입 없이 관측만): trailing 창이 홀딩월 '시작 전' 에서 끊기면
#  sigma_hat_{m+1}(= 월 m 전체를 포함) 이 sigma_hat_m 보다 realvol_m 과 더 강하게 붙어야 한다.
cor_same <- cor(sig, rv, method = "spearman")
cor_next <- cor(sig[-1], rv[-n], method = "spearman")
R$pit_lag <- list(
  cutoff_rule_declared = unique(d3$cutoff_rule),
  cutoff_semantics = "signal_cutoff 는 EXCLUSIVE upper bound — 일별 데이터는 Date < signal_cutoff 만 사용됨. signal_cutoff == hold_start == 홀딩월 1일.",
  ac1_sigma_hat = ac1(sig), ac1_realized_vol = ac1(rv),
  spearman_sigma_hat_m_vs_realvol_m      = cor_same,
  spearman_sigma_hat_mplus1_vs_realvol_m = cor_next,
  pit_direction_test = list(
    rule = "clean PIT 이면 cor(sigma_hat_{m+1}, realvol_m) > cor(sigma_hat_m, realvol_m) — 후자 창은 월 m 을 아직 못 봄",
    passed = cor_next > cor_same,
    margin = cor_next - cor_same
  ),
  outcome_columns_do_not_feed = c("bm_ret_holding_month", "realized_vol_in_month", "exposure_e(파생)"),
  outcome_note = "bm_ret_holding_month / realized_vol_in_month 는 홀딩월 '내' 실현값 = 검정 대상(target). 피처로 넣으면 C2 동월 순환참조."
)

# ---------- S5. 소비자 조인키 컨벤션 (book 축) ----------
bk <- fread(BOOK, colClasses = list(character = c("realized_ym", "return_ym")))
bk[, date := as.Date(date)]
key_census <- function(bkey, label) {
  j <- merge(d3[, .(ym, bm_ret_holding_month)], bk[, .(k = get(bkey), ret_orig)], by.x = "ym", by.y = "k", all = FALSE)
  list(book_key = label, n_joined = nrow(j),
       cor_bm_vs_book_unlevered = if (nrow(j) > 30) cor(j$bm_ret_holding_month, as.numeric(j$ret_orig), method = "pearson") else NA_real_)
}
R$consumer_join <- list(
  book_file = "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv",
  book_n_rows = nrow(bk),
  book_date_columns = list(
    date = "실제 결정일(거래일) — 월초 1일이 아님. 정확일치 merge 시 대량 손실(08-13 실사고: 271→142)",
    realized_ym = "결정월 라벨",
    return_ym = "수익이 실현된 홀딩월 라벨 — 본 패널 ym 과 동일 의미축"
  ),
  key_candidates = list(key_census("return_ym", "return_ym"), key_census("realized_ym", "realized_ym")),
  axis_identification_note = "cor 은 성과 통계량이 아니라 '어느 라벨이 같은 달을 가리키나' 의 축 식별 진단(metric_type=interface_diagnostic).",
  canonical_recipe = "merge(sigma_panel, book, by.x='ym', by.y='return_ym') — Date 형 정확일치 금지."
)

# ---------- S6. 승계 패널 emit ----------
outp <- copy(d3)
outp[, `:=`(
  inherited_from      = "stage_artifacts/WT_D20260813_003/alpha_scores.parquet",
  inheritance_type    = "verbatim_copy_no_rebuild",
  join_key            = "ym",
  join_key_semantics  = "holding month (수익 실현월) — book 축의 return_ym 과 동일 의미",
  cutoff_semantics    = "signal_cutoff EXCLUSIVE: 일별 데이터 Date < signal_cutoff",
  consumer            = "risk-research (Sigma 공통성분 분산 조건화 입력)"
)]
outp <- merge(outp, d2[, .(ym, VOL_wt002 = VOL, MSM_control = MSM, BEAR_control = BEAR)], by = "ym", all.x = TRUE)
setorder(outp, ym)
write_parquet(outp, file.path(OUT, "alpha_scores.parquet"))
R$emitted <- list(path = "stage_artifacts/WT_D20260813_004/alpha_scores.parquet",
                  n_rows = nrow(outp), n_cols = ncol(outp),
                  verbatim_parity_vs_wt003 = max(abs(outp$sigma_hat_daily - d3[order(ym)]$sigma_hat_daily)))

writeLines(toJSON(R, auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null"),
           file.path(OUT, "inherit_verify.json"))
cat(toJSON(R, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null"))
