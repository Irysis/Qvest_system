# =============================================================================
# build_pool_panel.R — WT-D20260803_005 (FQ-131) Step A: 대규모 factor 풀 top-K 패널
#   사전등록: stage_artifacts/WT_D20260803_005/preregistration.json
#
#   ★ 설계: 전체 z 패널(325 factor x 350 ticker x 295월 ≈ 33M행)을 물리지 않고,
#     월별 load_month_factors(d) (C15) 1회 순회에서 factor별 상위 K=80만 남긴다.
#     canonical_screen_bt는 이 top-80 위에서 자체 유동성필터 + top-25를 수행 —
#     전체 패널을 먹였을 때와 동일한 선택이 되는지는 Step B parity로 실증한다.
#
#   PIT: load_month_factors(sig_date) 경유(C15) → align_factor_direction PIT-safe
#     (Usable_Date <= sig_date, C14). Z_Score_Aligned 그대로 사용(C13 NEGATE/FLIP 없음).
#     유동성/멤버십은 canonical_screen_bt의 liq_dt(t-1 ADV, C10)가 담당.
#
#   출력: pool_panel.parquet (Date, Ticker, Factor_Name, score, rank_in_factor)
#         pool_meta.rds (factor별 커버리지 / 월별 IC-direction 부호 / eval grid)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/build_pool_panel.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) cat(sprintf(paste0("[wt005A] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

TOP_K       <- 80L        # 저장 상위 (canonical top-25 대비 3.2x 여유)
COV_MIN     <- 0.05
MIN_TICKERS <- 100L       # 창 유효 최소 종목
MIN_MONTHS  <- 216L       # 사전등록 가용성 규칙 (18년)

# ── 1. eval 그리드 + 유니버스 (WT-004와 동일 vintage 재현) ───────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(FALSE)
stopifnot(length(MEND) == uniqueN(format(MEND, "%Y-%m")))   # ★ distinct-YM assert
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
setkey(UNIV, Date, Ticker)

# factor DB 가용 월 (재무 의존 factor 시작 이후)
FDB_MIN <- as.Date("2002-08-01")
sig_all <- MEND[MEND >= FDB_MIN]
say("eval grid: %d월 (%s ~ %s) | 유니버스-월 행 %d",
    length(sig_all), min(sig_all), max(sig_all), nrow(UNIV[Date %in% sig_all]))

# ── 2. 단 1회 월별 순회 — factor별 top-K 추출 ────────────────────────────────
t0 <- Sys.time()
panel_list <- vector("list", length(sig_all))
dir_list   <- vector("list", length(sig_all))
cov_list   <- vector("list", length(sig_all))
build_hash <- "unknown"
sink(file.path(OUT, "build_pool_panel_connector.log"))   # 연결자 로그 격리(월 295회)
for (i in seq_along(sig_all)) {
  d <- sig_all[i]
  uni_tk <- UNIV[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = COV_MIN), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0L) { rm(fdt); next }
  if (identical(build_hash, "unknown")) {
    bh <- attr(fdt, "factor_db_build_hash"); if (!is.null(bh)) build_hash <- bh
  }
  S <- fdt[Ticker %in% uni_tk & is.finite(Z_Score_Aligned)]
  rm(fdt)
  # 커버리지 (top-K 절단 *전*에 factor별 유효 종목 수 확정)
  cv <- S[, .(n_tk = .N), by = Factor_Name]; cv[, Date := d]
  cov_list[[i]] <- cv
  keep_f <- cv[n_tk >= MIN_TICKERS, Factor_Name]
  S <- S[Factor_Name %in% keep_f]
  if (!nrow(S)) next
  setorder(S, Factor_Name, -Z_Score_Aligned)
  S[, rk := seq_len(.N), by = Factor_Name]
  P <- S[rk <= TOP_K, .(Date = d, Ticker, Factor_Name, score = Z_Score_Aligned, rank_in_factor = rk)]
  panel_list[[i]] <- P
  # IC-direction 부호 기록 (연결자 내부 캐시 그대로 — 진단 전용)
  idr <- tryCatch(.load_ic_direction_cached(d, 36L), error = function(e) NULL)
  if (!is.null(idr) && nrow(idr)) dir_list[[i]] <- data.table(Date = d,
      Factor_Name = idr$Factor_Name, ic_sign = idr$ic_sign)
  rm(S, P); if (i %% 24L == 0L) gc(FALSE)
}
sink()
PANEL <- rbindlist(Filter(Negate(is.null), panel_list), use.names = TRUE)
COV   <- rbindlist(Filter(Negate(is.null), cov_list),   use.names = TRUE)
DIR   <- rbindlist(Filter(Negate(is.null), dir_list),   use.names = TRUE)
rm(panel_list, cov_list, dir_list); gc(FALSE)
say("월 순회 완료 %.0fs | PANEL 행 %d | factor %d | 월 %d",
    as.numeric(difftime(Sys.time(), t0, units = "secs")), nrow(PANEL),
    uniqueN(PANEL$Factor_Name), uniqueN(PANEL$Date))

# ── 3. 사전등록 가용성 규칙 적용 ─────────────────────────────────────────────
ELIG <- COV[n_tk >= MIN_TICKERS, .(months = uniqueN(Date),
            first = min(Date), last = max(Date)), by = Factor_Name]
POOL <- ELIG[months >= MIN_MONTHS, Factor_Name]
say("가용성 규칙 통과 factor: %d / %d (>= %d월, >= %d종목)",
    length(POOL), nrow(ELIG), MIN_MONTHS, MIN_TICKERS)
PANEL <- PANEL[Factor_Name %in% POOL]
setkey(PANEL, Factor_Name, Date, Ticker)

# ── 4. IC-direction 부호 안정성 (진단 — 정렬 절차 자체의 시변성) ─────────────
DIRSTAT <- if (nrow(DIR)) {
  D2 <- DIR[Factor_Name %in% POOL]
  setorder(D2, Factor_Name, Date)
  D2[, .(n_dir_flips = sum(diff(ic_sign) != 0L), n_obs = .N,
         share_pos = mean(ic_sign > 0)), by = Factor_Name]
} else data.table()
if (nrow(DIRSTAT)) say("IC-direction 부호전환: 0회 %d factor / >=1회 %d factor (중앙값 %.0f)",
    DIRSTAT[n_dir_flips == 0L, .N], DIRSTAT[n_dir_flips > 0L, .N],
    as.numeric(median(DIRSTAT$n_dir_flips)))

# ── 5. 저장 ─────────────────────────────────────────────────────────────────
write_parquet(PANEL, file.path(OUT, "pool_panel.parquet"))
saveRDS(list(sig_all = sig_all, pool = POOL, elig = ELIG, coverage = COV,
             dir_stat = DIRSTAT, top_k = TOP_K, min_months = MIN_MONTHS,
             min_tickers = MIN_TICKERS, build_hash = build_hash,
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "pool_meta.rds"))
say("저장 완료 — pool_panel.parquet (%.1f MB) + pool_meta.rds | build_hash=%s",
    file.info(file.path(OUT, "pool_panel.parquet"))$size / 1e6, build_hash)
