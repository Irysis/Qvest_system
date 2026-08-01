# =============================================================================
# run_fq073_r2.R — WT-D20260802_001 R2 / FQ-073 next_probe P1(materiality) + P2(회전율)
#
#   신호 계산 = ast_compile.R (컴파일러-소유 AS_OF 조인, 수기 merge 금지)
#   측정      = canonical_screen_bt (계약 실측, 손계산 금지)
#   역할 경계 = alpha only. 공분산/비중/사전최적화 없음.
#
#   R2 의 핵심 산출은 성과가 아니라 **판별**이다:
#     R1 보유 cap-tier(OTHER 88.9%)가 크로스워크 아티팩트인가, 수출 신호 자체의 성질인가.
#     → materiality 재척도 후 tier 분포가 이동하면 아티팩트, 이동 없으면 신호의 성질.
#     ★두 경우 모두 base rate 대비로 읽어야 한다 — K200uKQ150 에서 OTHER 는 정의상
#       (342-30)/342 ~ 91% 이므로 88.9% 는 '소형주 국소화'가 아니라 거의 중립이다.
#       본 러너는 유니버스/스코어풀 base rate 를 함께 실측해 비율(lift)로 보고한다.
#
# 실행: Rscript stage_artifacts/WT_D20260802_001/run_fq073_r2.R
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")

`%||%` <- function(a, b) if (is.null(a)) b else a
.die <- function(fmt, ...) stop(sprintf(paste0("[r2] ", fmt), ...), call. = FALSE)
say <- function(fmt, ...) cat(sprintf(paste0("[r2] ", fmt, "\n"), ...))

source("02_Infrastructure/ast/ast_compile.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")

# -----------------------------------------------------------------------------
# 1. 시장 패널 · 월말 그리드 · 유니버스 (R1 과 동일 경로)
# -----------------------------------------------------------------------------
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector")))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= as.Date("2014-11-01")]
RAW[, ym := format(Date, "%Y-%m")]
MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
say("rawdata %d행 · 월말 %d개 · %s~%s", nrow(RAW), length(MEND),
    as.character(min(MEND)), as.character(max(MEND)))

UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
EXPMIN <- as.data.table(read_parquet(file.path(OUT, "fq073_export_exposure_chapter.parquet")))[, min(as.Date(Date))]
EVAL <- sort(unique(UNIV$Date)); EVAL <- EVAL[EVAL >= EXPMIN + 700]
UNIV <- UNIV[Date %in% EVAL]
say("유니버스 %d월 · 월평균 %.0f종목 · %s~%s", uniqueN(UNIV$Date),
    UNIV[, .N, by = Date][, mean(N)], as.character(min(EVAL)), as.character(max(EVAL)))

# C5 PIT 감사 (R1 과 동일 규약 — 두 STORED_SCORE 리프 avail 규칙 동일)
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym,1,4)); m <- as.integer(substr(ym,6,7)) + k
  y <- y + (m-1L) %/% 12L; m <- (m-1L) %% 12L + 1L; sprintf("%04d-%02d", y, m)
}
SD <- data.table(score_date = EVAL)
SD[, data_ym := ym_add(format(score_date, "%Y-%m"), -1L)]
SD[, usable_date := as.Date(sprintf("%s-15", ym_add(data_ym, 1L)))]
SD[, holding_start := holdings_signal_cutoff(score_date)]
assert_overlay_pit(SD$usable_date, SD$holding_start, label = "FQ073_R2_customs_export_materiality")
say("C5 PASS — 버퍼 %d~%d일", min(as.integer(SD$holding_start - SD$usable_date)),
    max(as.integer(SD$holding_start - SD$usable_date)))

# -----------------------------------------------------------------------------
# 2. forward returns / bench / liq / size  (전부 계약 함수 경유)
# -----------------------------------------------------------------------------
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- RAWME[, .(Date, Ticker, Size)]

lbl <- merge(RAWME[, .(Date, Ticker, Close)], returns_dt, by = c("Date","Ticker"))
lbl <- merge(lbl, RAWME[, .(Date_next = Date, Ticker, Close_next = Close)], by = "Ticker",
             allow.cartesian = TRUE)
lbl <- lbl[Date_next > Date][order(Ticker, Date, Date_next)][, .SD[1], by = .(Ticker, Date)]
lbl[, ret_check := Close_next / Close - 1]
lab_corr <- lbl[is.finite(ret_check) & is.finite(Ret_1m), stats::cor(Ret_1m, ret_check)]
say("라벨 방향 감사 cor = %.6f (>0.99 기대)", lab_corr)
if (!is.finite(lab_corr) || lab_corr < 0.99) .die("라벨 방향 감사 실패")

# -----------------------------------------------------------------------------
# 3. cap-tier base rate — 판정 해석의 기준선 (R1 이 빠뜨린 축)
#    · universe : K200uKQ150 전체에서 tier 구성 (MEGA 10 / MID 20 은 정의상 고정)
#    · pool     : 크로스워크로 스코어가 부여되는 부분집합의 tier 구성
# -----------------------------------------------------------------------------
SZ <- copy(size_dt)[!is.na(Size)]
setorder(SZ, Date, -Size)
SZ[, cap_rank := seq_len(.N), by = Date]
SZ[, tier := fifelse(cap_rank <= 10L, "MEGA", fifelse(cap_rank <= 30L, "MID", "OTHER"))]
UT <- merge(UNIV, SZ[, .(Date, Ticker, tier)], by = c("Date","Ticker"), all.x = TRUE)
UT[is.na(tier), tier := "UNRANKED"]
base_univ <- UT[, .N, by = tier][, .(tier, share = N/sum(N))]
say("base rate (유니버스): %s", paste(sprintf("%s=%.3f", base_univ$tier, base_univ$share), collapse=" "))

# -----------------------------------------------------------------------------
# 4. AST 컴파일 -> canonical_screen_bt 실측
# -----------------------------------------------------------------------------
FIDS <- c("R2_G1_mat_surprise", "R2_G1c_matcred_surprise", "R2_G2_sue",
          "R2_G3_mat_sue", "R2_G4_mat_sue_sm3", "R2_G5_mat_sue_sm6")
PRIMARY <- "R2_G1_mat_surprise"

measure <- function(scores, top_n = 25L, feats = NULL, sid = "canonical_screen") {
  sc <- scores[is.finite(score), .(Date, Ticker, score)]
  if (!nrow(sc)) return(NULL)
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = top_n,
                      cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                      diag_dual_basis = TRUE, size_dt = size_dt,
                      ast_features = feats, strategy_id = sid,
                      run_id = paste0("WT_D20260802_001_R2/", sid))
}

results <- list(); manifests <- list(); panels <- list()
for (fid in c(FIDS)) {
  say("── compile %s", fid)
  cmp <- tryCatch(ast_compile(file.path(OUT, sprintf("ast_%s.json", fid)),
                              eval_dates = EVAL, universe = UNIV,
                              manifest_out = file.path(OUT, sprintf("ast_manifest_%s.json", fid))),
                  error = function(e) { say("  compile ERROR: %s", conditionMessage(e)); NULL })
  if (is.null(cmp)) next
  p <- as.data.table(cmp$panel); nn <- sum(!is.na(p$value))
  say("  panel %d cells · non-NA %d (%.1f%%) · nodes=%s depth=%s",
      nrow(p), nn, 100*nn/max(1,nrow(p)),
      cmp$manifest$ast_features$node_count %||% NA, cmp$manifest$ast_features$max_depth %||% NA)
  panels[[fid]] <- p; manifests[[fid]] <- cmp$manifest
  r <- measure(p[, .(Date, Ticker, score = value)], feats = cmp$manifest$ast_features,
               sid = paste0("FQ073_", fid))
  if (is.null(r)) { say("  측정 skip"); next }
  results[[fid]] <- r
  ct <- r$diag_cap_tier
  say("  PORT_t(cap-w)=%7.3f p=%.3f n=%3d IR=%6.3f TO=%6.1f%% | EW=%7.3f | tier MEGA/MID/OTHER=%.3f/%.3f/%.3f",
      r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue, r$n_months,
      r$information_ratio, 100*r$turnover_annual,
      r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_,
      ct$weight_share_avg$MEGA %||% NA_real_, ct$weight_share_avg$MID %||% NA_real_,
      ct$weight_share_avg$OTHER %||% NA_real_)
}

# -----------------------------------------------------------------------------
# 5. B0 = R1 baseline 재측정 (동일 코드경로에서 재현 + 공통창 비교 기준)
# -----------------------------------------------------------------------------
P1 <- as.data.table(read_parquet(file.path(OUT, "alpha_scores_F1_export_surprise.parquet")))
b0 <- measure(P1[!is.na(value), .(Date, Ticker, score = value)], sid = "FQ073_B0_R1_F1")
say("B0 (R1 F1 재현): PORT_t=%.4f n=%d TO=%.1f%%", b0$portfolio_alpha_t_nw_lag3,
    b0$n_months, 100*b0$turnover_annual)

# -----------------------------------------------------------------------------
# 6. 공통창 비교 — 변형마다 유효 개시월이 달라(SUE 는 TS_STD 12M 추가) 창을 맞춰야
#    귀속이 정직하다. 전 변형 교집합 월로 재측정.
# -----------------------------------------------------------------------------
valid_months <- lapply(panels, function(p) unique(as.Date(p[is.finite(value), Date])))
valid_months[["B0"]] <- unique(as.Date(P1[is.finite(value), Date]))
common <- Reduce(intersect, valid_months)
common <- as.Date(common, origin = "1970-01-01")
say("공통창: %d개월 %s~%s", length(common), as.character(min(common)), as.character(max(common)))

cw <- list()
for (fid in names(panels)) {
  r <- measure(panels[[fid]][Date %in% common, .(Date, Ticker, score = value)],
               sid = paste0("FQ073_cw_", fid))
  if (!is.null(r)) cw[[fid]] <- r
}
cw[["B0"]] <- measure(P1[Date %in% common & !is.na(value), .(Date, Ticker, score = value)],
                      sid = "FQ073_cw_B0")

# -----------------------------------------------------------------------------
# 7. 스코어풀 base rate (PRIMARY 기준) + tier lift
# -----------------------------------------------------------------------------
POOL <- merge(panels[[PRIMARY]][is.finite(value), .(Date, Ticker)],
              SZ[, .(Date, Ticker, tier)], by = c("Date","Ticker"), all.x = TRUE)
POOL[is.na(tier), tier := "UNRANKED"]
base_pool <- POOL[, .N, by = tier][, .(tier, share = N/sum(N))]
say("base rate (스코어풀): %s", paste(sprintf("%s=%.3f", base_pool$tier, base_pool$share), collapse=" "))

tier_row <- function(r, tag) {
  ct <- r$diag_cap_tier
  if (is.null(ct) || !isTRUE(ct$available)) return(NULL)
  data.table(variant = tag,
             MEGA = ct$weight_share_avg$MEGA %||% 0, MID = ct$weight_share_avg$MID %||% 0,
             OTHER = ct$weight_share_avg$OTHER %||% 0, UNRANKED = ct$weight_share_avg$UNRANKED %||% 0)
}
TIER <- rbindlist(c(list(tier_row(b0, "B0_R1_F1")),
                    lapply(names(results), function(f) tier_row(results[[f]], f))), fill = TRUE)
bp <- setNames(base_pool$share, base_pool$tier)
bu <- setNames(base_univ$share, base_univ$tier)
for (tt in c("MEGA","MID","OTHER")) {
  TIER[[paste0("lift_pool_", tt)]] <- round(TIER[[tt]] / (bp[[tt]] %||% NA_real_), 3)
  TIER[[paste0("lift_univ_", tt)]] <- round(TIER[[tt]] / (bu[[tt]] %||% NA_real_), 3)
}
print(TIER)

# -----------------------------------------------------------------------------
# 8. 저장
# -----------------------------------------------------------------------------
pack <- function(r) if (is.null(r)) NULL else list(
  metric_type = "canonical_screen",
  portfolio_alpha_t_nw_lag3 = round(r$portfolio_alpha_t_nw_lag3, 4),
  p = round(r$portfolio_alpha_t_pvalue, 4), n_months = r$n_months,
  information_ratio = round(r$information_ratio, 4),
  net_sr = round(r$net_sr %||% NA_real_, 4),
  turnover_annual = round(r$turnover_annual, 4),
  ew_universe_port_t = round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_, 4),
  ew_post2017_t = round(r$diag_ew_universe$post2017_t_nw_lag3 %||% NA_real_, 4),
  cap_tier_weight_share = r$diag_cap_tier$weight_share_avg,
  cap_tier_contrib_annualized = r$diag_cap_tier$contrib_gross_annualized)

RES <- list(
  round = "R2",
  base_rate = list(universe = as.list(setNames(round(base_univ$share,4), base_univ$tier)),
                   score_pool_primary = as.list(setNames(round(base_pool$share,4), base_pool$tier)),
                   note = "K200uKQ150 에서 MEGA=10 / MID=20 종목은 정의상 고정이므로 OTHER base ~0.91. 보유 tier 비중은 이 base 대비 lift 로 읽어야 한다."),
  full_window = c(list(B0_R1_F1 = pack(b0)), lapply(results, pack)),
  common_window = list(months = length(common),
                       from = as.character(min(common)), to = as.character(max(common)),
                       results = lapply(cw, pack)),
  tier_table = TIER,
  ast_features = lapply(manifests, function(m) m$ast_features))
write_json(RES, file.path(OUT, "fq073_r2_results.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", digits = 6)
saveRDS(list(results = results, cw = cw, b0 = b0, manifests = manifests, common = common,
             base_univ = base_univ, base_pool = base_pool, TIER = TIER),
        file.path(OUT, "fq073_r2_results.rds"))
for (fid in names(panels))
  write_parquet(panels[[fid]], file.path(OUT, sprintf("alpha_scores_%s.parquet", fid)))
say("→ fq073_r2_results.json · 패널 %d개 저장", length(panels))
