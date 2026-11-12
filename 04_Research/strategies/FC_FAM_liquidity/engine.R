## FC_FAM_liquidity — 팩터 가족 합성 엔진 · 가족 liquidity (자체 사양 엔진 · 팩터 척추 1단계 F0)
## ★생성기 산출 — 손으로 고치지 않는다. 다시 만들기(저장소 루트): Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --write
##   생성기 md5 e31ad11fa6be218017e961c47b06bbdc · 사양 md5 634f512aa295e738e92b3734ee5fdfcc · 규칙 판 fce_rule_v0 · 사양 원문 = 같은 폴더 own_spec.json
##   결정 FACTOR-SPINE-STAGE1-20261112 · 팩터 척추 설계안 §3(문서 경로 = own_spec.json)
## 점수 = 종목마다 구성원 44개(등록부 category = liquidity)의 결합용 뷰 점수 가운데 값이 있는 것의 평균 · 하나도 없으면 결측
##   결합용 뷰 점수 = 매 시점 횡단면 순위 [−1, 1](동순위 평균) × 등록부 기대수익 방향
##     — Gu, Kelly & Xiu (2020) RFS 33(5) https://doi.org/10.1093/rfs/hhaa009
##   평균 규칙 = Asness, Frazzini & Pedersen (2019) RAS 24(1) https://doi.org/10.1007/s11142-018-9470-2
##     · Jensen, Kelly & Pedersen (2023) JF 78(5) https://doi.org/10.1111/jofi.13249
##   결측 종목은 그 날 패널에서 뺀다(0 으로 채우지 않는다 · 06_Registry/factor_combinable.json missing 선택지 na)
## 계약: 입력 = RAWDATA(거래일 달력 — Date 열만 쓴다) · .RP_START_DATE(없으면 측정 축 정본의 활성 epoch 시작일)
##   출력 = FACTORS(Date, Ticker, Score) 만 · 날짜 = 결합용 뷰의 그 달 as-of(월말 거래일 — 셀 경로 달 스냅에서 항등)
##   as-of 가 시작일 이후인 달만 · 패널 마지막 달을 뷰가 아직 못 따라왔으면 그 달만 뺀다(그 달은 뒤 수익이 없다)
## PIT: 팩터 값은 정본 접근자 fc_load_month 한 길로만 읽는다(C15) · 방향 인자 = 문자열 상수 registry(C13 · 수동 반전 없음)
##   · IC 를 읽지 않는다(C1 · C14) · 재무 시차는 팩터 DB 가 이미 적용한 값만 쓴다(C4)
##   · 구성원 · 부호(s_reg) · 가족 · 뷰 빌더 판은 선언 때 고정 — 실행 때 뷰 메타와 다르면 멈춘다(새 사양으로 다시 선언)
## 진단(판정 입력 아님): 날짜별 구성원 수 · 점수 범위 · 종목별 유효 수(값이 있는 구성원 수) 분포
##   → 이 폴더 fce_diag.csv(options(fce.diag_dir) 로 바꾼다 · 폴더가 없으면 쓰지 않는다)
.FCE_SPEC_ID <- "FC_FAM_liquidity"
.FCE_KIND <- "family"
.FCE_FAMILIES <- c("liquidity")
.FCE_RULE <- "fce_rule_v0"
.FCE_GEN_MD5 <- "e31ad11fa6be218017e961c47b06bbdc"
.FCE_SPEC_MD5 <- "634f512aa295e738e92b3734ee5fdfcc"
.FCE_VIEW_BUILDER <- "factor_combinable.R v1.1"
## 구성원(선언 때 고정) — id · 등록부 기대수익 부호 s_reg · 가족(등록부 category)
.FCE_M <- matrix(ncol = 3L, byrow = TRUE, data = c(
  "L01_Amihud", "-1", "liquidity",
  "L02_Turnover", "-1", "liquidity",
  "L03_Volume_Mom", "1", "liquidity",
  "L04_Bid_Ask_Proxy", "-1", "liquidity",
  "L05_Dollar_Volume", "-1", "liquidity",
  "L06_Zero_Trade_Days", "-1", "liquidity",
  "L07_Zero_Return_Days", "-1", "liquidity",
  "L08_Roll_Spread", "-1", "liquidity",
  "L09_Amihud_20d", "-1", "liquidity",
  "L10_Amihud_Ratio", "1", "liquidity",
  "L11_Kyle_Lambda", "-1", "liquidity",
  "L12_PS_Gamma", "1", "liquidity",
  "L13_Vol_Variance_Ratio", "1", "liquidity",
  "L14_Price_Impact", "-1", "liquidity",
  "L15_Turnover_252d", "-1", "liquidity",
  "L16_Turnover_Vol", "1", "liquidity",
  "L17_LOT_Measure", "-1", "liquidity",
  "L18_Eff_Spread_Proxy", "1", "liquidity",
  "L19_Price_Delay", "-1", "liquidity",
  "L20_Trade_Frequency", "-1", "liquidity",
  "L21_Market_Depth", "1", "liquidity",
  "L22_Ret_Autocorr", "1", "liquidity",
  "L23_Vol_Autocorr", "1", "liquidity",
  "L24_Range_per_Vol", "1", "liquidity",
  "L25_Amihud_Vol", "-1", "liquidity",
  "L26_Log_MktCap", "-1", "liquidity",
  "L27_Price_Level", "1", "liquidity",
  "L28_Vol_Mom_63d", "1", "liquidity",
  "L29_Illiq_Change", "1", "liquidity",
  "L31_Vol_Concentration", "1", "liquidity",
  "L32_Ret_Vol_Corr", "1", "liquidity",
  "L33_AbsRet_Vol_Corr", "1", "liquidity",
  "L34_Vol_Spike_Ratio", "1", "liquidity",
  "L35_Reversal_Intensity", "1", "liquidity",
  "L36_CLV_Stability", "1", "liquidity",
  "L37_Relative_Vol", "1", "liquidity",
  "L38_DolVol_Mom", "1", "liquidity",
  "L39_Overnight_Spread", "1", "liquidity",
  "L40_VWAP_Spread", "1", "liquidity",
  "L41_Intraday_Vol_Proxy", "1", "liquidity",
  "L42_Vol_Skewness", "-1", "liquidity",
  "L43_Turnover_Change", "1", "liquidity",
  "L44_Vol_Ret_Asymmetry", "1", "liquidity",
  "L45_Composite_Liquidity", "-1", "liquidity"
))
.FCE_MEMBERS <- data.frame(id = .FCE_M[, 1L], s_reg = as.integer(.FCE_M[, 2L]), family = .FCE_M[, 3L], stringsAsFactors = FALSE)
if (nrow(.FCE_MEMBERS) != 44L || anyDuplicated(.FCE_MEMBERS$id) > 0L || !all(.FCE_MEMBERS$s_reg %in% c(-1L, 1L)) ||
    !all(.FCE_MEMBERS$family %in% .FCE_FAMILIES))
  stop("[FC_FAM_liquidity] 구성원 표가 선언과 다르다 — 생성기로 다시 만들 것(손 편집 금지)")
.fce_root <- local({
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[FC_FAM_liquidity] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
})
.fce_fc <- new.env(parent = globalenv())
sys.source(file.path(.fce_root, "02_Infrastructure", "factor_db", "factor_combinable.R"), envir = .fce_fc, keep.source = FALSE)
.fce_start <- if (exists(".RP_START_DATE")) as.Date(.RP_START_DATE) else local({
  e <- new.env(parent = globalenv())
  sys.source(file.path(.fce_root, "02_Infrastructure", "contracts", "measurement_axis.R"), envir = e, keep.source = FALSE)
  as.Date(e$ma_epoch(root = .fce_root)$start_date)
})
if (length(.fce_start) != 1L || is.na(.fce_start)) stop("[FC_FAM_liquidity] 측정 시작일을 읽지 못했다")
if (!exists("RAWDATA")) stop("[FC_FAM_liquidity] RAWDATA 없음 — 셀 경로 · 러너가 넘기는 패널(거래일 달력)이 필요하다")
.fce_cal <- sort(unique(as.Date(RAWDATA[["Date"]])))
.fce_me <- .fce_cal[!duplicated(format(.fce_cal, "%Y%m"), fromLast = TRUE)]
.fce_me <- .fce_me[.fce_me >= .fce_start]
if (!length(.fce_me)) stop(sprintf("[%s] 시작일 %s 뒤 월말 거래일이 패널에 없다", .FCE_SPEC_ID, format(.fce_start)))
.fce_rows <- list(); .fce_dg <- list()
for (.fce_i in seq_along(.fce_me)) {
  .fce_d <- .fce_me[.fce_i]
  .fce_r <- NULL
  invisible(utils::capture.output(.fce_r <- tryCatch(
    .fce_fc$fc_load_month(.fce_d, direction = "registry", factors = .FCE_MEMBERS$id, missing = "na", dedup = FALSE, family = TRUE),
    error = function(e) e)))
  if (inherits(.fce_r, "error")) {
    .fce_em <- conditionMessage(.fce_r)
    if (.fce_i == length(.fce_me) && (grepl("결합용 뷰에 그 달이 없다", .fce_em, fixed = TRUE) || grepl("보다 이르다", .fce_em, fixed = TRUE))) {
      cat(sprintf("[%s] 패널 마지막 달 %s 은 뺀다 — 결합용 뷰가 패널 끝을 아직 못 따라왔다(그 달은 뒤 수익이 없다): %s\n",
                  .FCE_SPEC_ID, format(.fce_d, "%Y-%m"), .fce_em))
      next
    }
    stop(.fce_r)
  }
  .fce_in <- .fce_r$info
  if (!identical(.fce_in$builder, .FCE_VIEW_BUILDER) || !identical(.fce_in$direction, "registry") || !identical(.fce_in$missing, "na") ||
      !identical(.fce_in$dedup, FALSE) || !identical(.fce_in$rerank_within_tickers, FALSE))
    stop(sprintf("[%s] 결합용 뷰 판 · 읽기 인자가 선언과 다르다(뷰 %s · 선언 %s) — 사양을 다시 선언할 것", .FCE_SPEC_ID,
                 as.character(.fce_in$builder)[1], .FCE_VIEW_BUILDER))
  .fce_asof <- as.Date(.fce_in$asof)
  if (.fce_asof < .fce_start) next
  .fce_m <- .fce_r$meta
  .fce_k <- match(.fce_m$Factor_Name, .FCE_MEMBERS$id)
  .fce_ok <- !is.na(.fce_k) & !is.na(.fce_m$s_reg) & !is.na(.fce_m$category)
  .fce_ok[.fce_ok] <- .fce_m$s_reg[.fce_ok] == .FCE_MEMBERS$s_reg[.fce_k[.fce_ok]] &
    .fce_m$category[.fce_ok] == .FCE_MEMBERS$family[.fce_k[.fce_ok]]
  if (!all(.fce_ok))
    stop(sprintf("[%s] 방향 · 가족 고정 위반 — 뷰 메타의 s_reg · category 가 선언과 다르다(%s): %s — 사양을 다시 선언할 것", .FCE_SPEC_ID,
                 format(.fce_d, "%Y-%m"), paste(utils::head(.fce_m$Factor_Name[!.fce_ok], 8L), collapse = ", ")))
  .fce_f <- .fce_r$families
  ## 가족 점수 = 결합용 뷰가 낸 가족 평균(구성원 중 값이 있는 것의 평균 · 하나도 없으면 결측 · 열이 없으면 그 달 구성원 0)
  .fce_s <- if (.FCE_FAMILIES %in% names(.fce_f)) .fce_f[[.FCE_FAMILIES]] else rep(NA_real_, nrow(.fce_f))
  .fce_v <- is.finite(.fce_s)
  .fce_nv <- if (nrow(.fce_r$n_avail) == nrow(.fce_f)) .fce_r$n_avail$n_avail[.fce_v] else integer(0)
  .fce_np <- as.integer(.FCE_FAMILIES %in% names(.fce_f))
  .fce_rows[[length(.fce_rows) + 1L]] <- data.frame(Date = rep(.fce_asof, sum(.fce_v)), Ticker = .fce_f$Ticker[.fce_v],
                                                    Score = .fce_s[.fce_v], stringsAsFactors = FALSE)
  .fce_dg[[length(.fce_dg) + 1L]] <- data.frame(Date = .fce_asof, n_members_present = nrow(.fce_m), n_families_present = .fce_np,
    n_scored = sum(.fce_v), score_min = if (any(.fce_v)) min(.fce_s[.fce_v]) else NA_real_,
    score_max = if (any(.fce_v)) max(.fce_s[.fce_v]) else NA_real_, n_valid_min = if (length(.fce_nv)) min(.fce_nv) else NA_real_,
    n_valid_median = if (length(.fce_nv)) stats::median(.fce_nv) else NA_real_, n_valid_max = if (length(.fce_nv)) max(.fce_nv) else NA_real_)
}
if (!length(.fce_rows)) stop(sprintf("[%s] 산출이 비었다 — 시작일 %s 뒤 점수가 있는 달이 없다", .FCE_SPEC_ID, format(.fce_start)))
FACTORS <- data.table::rbindlist(.fce_rows)
if (!nrow(FACTORS)) stop(sprintf("[%s] 산출이 비었다 — 점수가 있는 종목이 없다", .FCE_SPEC_ID))
.fce_dgt <- do.call(rbind, .fce_dg)
.fce_dgt$start <- format(.fce_start)
.fce_dgt$spec_md5 <- .FCE_SPEC_MD5
cat(sprintf("[%s] FACTORS %d행 · 달 %d(%s ~ %s) · 시작 %s · 구성원 선언 %d · 달마다 있는 구성원 %d ~ %d\n", .FCE_SPEC_ID, nrow(FACTORS),
            nrow(.fce_dgt), format(min(.fce_dgt$Date)), format(max(.fce_dgt$Date)), format(.fce_start), nrow(.FCE_MEMBERS),
            min(.fce_dgt$n_members_present), max(.fce_dgt$n_members_present)))
.fce_dd <- getOption("fce.diag_dir", file.path(.fce_root, "04_Research", "strategies", .FCE_SPEC_ID))
if (dir.exists(.fce_dd)) {
  .fce_tmp <- file.path(.fce_dd, sprintf(".fce_diag_%d.tmp", Sys.getpid()))
  .fce_to <- file.path(.fce_dd, "fce_diag.csv")
  .fce_wr <- tryCatch({
    utils::write.csv(.fce_dgt, .fce_tmp, row.names = FALSE)
    if (file.exists(.fce_to)) file.remove(.fce_to)
    file.rename(.fce_tmp, .fce_to)
  }, error = function(e) FALSE)
  if (!isTRUE(.fce_wr)) { unlink(.fce_tmp); warning(sprintf("[%s] 진단 파일을 쓰지 못했다(판정 무관): %s", .FCE_SPEC_ID, .fce_dd)) }
}
suppressWarnings(rm(list = c(".fce_rows", ".fce_dg", ".fce_dgt", ".fce_r", ".fce_f", ".fce_m", ".fce_in", ".fce_k", ".fce_ok", ".fce_s",
                             ".fce_v", ".fce_nv", ".fce_np", ".fce_x", ".fce_nf", ".fce_fcol", ".fce_cal", ".fce_me", ".fce_d", ".fce_i",
                             ".fce_asof", ".fce_em", ".fce_dd", ".fce_tmp", ".fce_wr", ".fce_to", ".fce_fc", ".fce_start", ".FCE_M")))
invisible(gc(verbose = FALSE))
