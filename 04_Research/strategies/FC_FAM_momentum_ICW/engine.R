## FC_FAM_momentum_ICW — 결합기 T1 · 가족 momentum(as-of IC 가중) (자체 사양 엔진 · 팩터 척추 결합기 T1 · as-of IC 가중)
## ★생성기 산출 — 손으로 고치지 않는다. 다시 만들기(저장소 루트): Rscript 02_Infrastructure/factor_db/fc_combiner_gen.R --write
##   생성기 md5 6b2a6e45e33abb59be8609df1886b209 · 사양 md5 9689f6791f238f152779d779b277ad05 · 규칙 판 fcc_rule_t1_v0 · 사양 원문 = 같은 폴더 own_spec.json
##   팩터 척추 설계안 §4-2 T1 · 구성원 = P1R03 선언 T0 사양(FC_FAM_momentum)과 같다 — 가중만 다르다
## 점수 = 종목마다 구성원 30개(등록부 category = momentum)의 결합용 뷰 점수를 as-of IC 가중으로 평균(값 있는 구성원만)
##   그 달 구성원 가중이 모두 0 이면 등가중(T0 FC_FAM_momentum 와 같은 값) — 진단 fallback_t0
##   팩터 가중 w = max(s_reg × ICIR, 0) · ICIR = 정본 접근자 compute_rolling_ic_all(그 달 as-of, 36, 120)
##     (IC 원장 Usable_Date ≤ as-of 를 접근자가 강제 · 최근 120개월 · 36개월 미만 = 없음 → 가중 0 · 반대 부호 IC = 가중 0 · 뒤집지 않는다)
##   근거: IC 기반 결합 — Qian, Hua & Sorensen (2007) QEPM https://doi.org/10.1201/9781420010794
##     · 양의 지난 성과 팩터만 — Ehsani & Linnainmaa (2022) JF 77(3) https://doi.org/10.1111/jofi.13131
##     · 순위 변환 — Gu, Kelly & Xiu (2020) RFS 33(5) https://doi.org/10.1093/rfs/hhaa009 · 가족 단위 — JKP (2023) https://doi.org/10.1111/jofi.13249
##   ICIR 이 모두 같으면 T0 와 같은 점수(T1 은 T0 를 품는다)
## 계약: 입력 = RAWDATA(거래일 달력 — Date 열만 쓴다) · .RP_START_DATE(없으면 측정 축 정본의 활성 epoch 시작일)
##   출력 = FACTORS(Date, Ticker, Score) 만 · 날짜 = 결합용 뷰의 그 달 as-of(월말 거래일 — 셀 경로 달 스냅에서 항등)
##   as-of 가 시작일 이후인 달만 · 패널 마지막 달을 뷰가 아직 못 따라왔으면 그 달만 뺀다(그 달은 뒤 수익이 없다)
## PIT: 팩터 값 = fc_load_month 한 길(C15) · 방향 인자 = 문자열 상수 registry(C13 · 부호 = 등록부 고정 · 가중 ≥ 0 단정)
##   · IC = compute_rolling_ic_all 한 길(C14 — Usable_Date ≤ as-of) · 재무 시차는 팩터 DB 가 이미 적용한 값만(C4)
##   · 구성원 · 부호 · 가족 · 뷰 빌더 판 · IC 창은 선언 때 고정 — 실행 때 다르면 멈춘다(새 사양으로 다시 선언)
## 진단(판정 입력 아님): 날짜별 구성원 수 · 양의 가중 수 · 대체 여부 · 점수 범위 · 유효 수 → 이 폴더 fce_diag.csv
##   IC 에서 나온 값이라 정보 경계(06_Registry/behavior_card.json tau_d) 이전 행만 쓴다 · options(fce.diag_dir) 로 바꾼다 · 폴더가 없으면 쓰지 않는다
.FCE_SPEC_ID <- "FC_FAM_momentum_ICW"
.FCE_KIND <- "family_icw"
.FCE_FAMILIES <- c("momentum")
.FCE_RULE <- "fcc_rule_t1_v0"
.FCE_GEN_MD5 <- "6b2a6e45e33abb59be8609df1886b209"
.FCE_SPEC_MD5 <- "9689f6791f238f152779d779b277ad05"
.FCE_VIEW_BUILDER <- "factor_combinable.R v1.1"
.FCE_IC_MIN <- 36L
.FCE_IC_MAX <- 120L
## 구성원(선언 때 고정) — id · 등록부 기대수익 부호 s_reg · 가족(등록부 category)
.FCE_M <- matrix(ncol = 3L, byrow = TRUE, data = c(
  "M01_Mom_12_1", "1", "momentum",
  "M02_Mom_6_1", "1", "momentum",
  "M03_Mom_3_1", "1", "momentum",
  "M04_Mom_1", "-1", "momentum",
  "M05_Trended_Mom", "1", "momentum",
  "M06_High_52w", "1", "momentum",
  "M07_IndMom", "1", "momentum",
  "M08_Residual_Mom", "1", "momentum",
  "M09_Composite_Mom", "1", "momentum",
  "M10_Intermediate_Mom", "1", "momentum",
  "M11_ST_Reversal", "-1", "momentum",
  "M12_LR_Reversal", "-1", "momentum",
  "M13_VolAdj_Mom", "1", "momentum",
  "M14_RiskAdj_Mom", "1", "momentum",
  "M15_Mom_3", "1", "momentum",
  "M16_Trend_Factor", "1", "momentum",
  "M17_Low_52w", "1", "momentum",
  "M18_RSI", "-1", "momentum",
  "M19_MACD", "1", "momentum",
  "M20_Keller_Mom", "1", "momentum",
  "M21_Seasonality", "1", "momentum",
  "M22_Max_Return", "-1", "momentum",
  "M23_Acceleration", "1", "momentum",
  "M24_Sector_Rel_Mom", "1", "momentum",
  "M25_Earnings_Mom_Streak", "1", "momentum",
  "M26_Revenue_Mom", "1", "momentum",
  "M27_Analyst_Rev_Mom", "1", "momentum",
  "M28_OP_Rev_Mom", "1", "momentum",
  "M30_Mom_10d", "-1", "momentum",
  "M32_Composite_Mom_v2", "1", "momentum"
))
.FCE_MEMBERS <- data.frame(id = .FCE_M[, 1L], s_reg = as.integer(.FCE_M[, 2L]), family = .FCE_M[, 3L], stringsAsFactors = FALSE)
if (nrow(.FCE_MEMBERS) != 30L || anyDuplicated(.FCE_MEMBERS$id) > 0L || !all(.FCE_MEMBERS$s_reg %in% c(-1L, 1L)) ||
    !all(.FCE_MEMBERS$family %in% .FCE_FAMILIES))
  stop("[FC_FAM_momentum_ICW] 구성원 표가 선언과 다르다 — 생성기로 다시 만들 것(손 편집 금지)")
.fce_root <- local({
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[FC_FAM_momentum_ICW] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
})
.fce_fc <- new.env(parent = globalenv())
sys.source(file.path(.fce_root, "02_Infrastructure", "factor_db", "factor_combinable.R"), envir = .fce_fc, keep.source = FALSE)
## IC 접근자 — 정본 커넥터(결합용 뷰 .fc_env 와 같은 적재 순서: config.R → factor_db_connector.R · 작업 폴더 = 02_Infrastructure)
.fce_ic <- new.env(parent = globalenv())
local({
  .fce_owd <- setwd(file.path(.fce_root, "02_Infrastructure")); on.exit(setwd(.fce_owd), add = TRUE)
  invisible(utils::capture.output(suppressMessages({
    sys.source(file.path(.fce_root, "02_Infrastructure", "config.R"), envir = .fce_ic, keep.source = FALSE)
    sys.source(file.path(.fce_root, "02_Infrastructure", "factor_db", "factor_db_connector.R"), envir = .fce_ic, keep.source = FALSE)
  })))
})
if (!is.function(.fce_ic$compute_rolling_ic_all)) stop("[FC_FAM_momentum_ICW] IC 접근자 compute_rolling_ic_all 을 싣지 못했다")
.fce_start <- if (exists(".RP_START_DATE")) as.Date(.RP_START_DATE) else local({
  e <- new.env(parent = globalenv())
  sys.source(file.path(.fce_root, "02_Infrastructure", "contracts", "measurement_axis.R"), envir = e, keep.source = FALSE)
  as.Date(e$ma_epoch(root = .fce_root)$start_date)
})
if (length(.fce_start) != 1L || is.na(.fce_start)) stop("[FC_FAM_momentum_ICW] 측정 시작일을 읽지 못했다")
.fce_tau <- tryCatch(as.Date(jsonlite::fromJSON(file.path(.fce_root, "06_Registry", "behavior_card.json"))$tau_d), error = function(e) as.Date(NA))
if (!exists("RAWDATA")) stop("[FC_FAM_momentum_ICW] RAWDATA 없음 — 셀 경로 · 러너가 넘기는 패널(거래일 달력)이 필요하다")
.fce_cal <- sort(unique(as.Date(RAWDATA[["Date"]])))
.fce_me <- .fce_cal[!duplicated(format(.fce_cal, "%Y%m"), fromLast = TRUE)]
.fce_me <- .fce_me[.fce_me >= .fce_start]
if (!length(.fce_me)) stop(sprintf("[%s] 시작일 %s 뒤 월말 거래일이 패널에 없다", .FCE_SPEC_ID, format(.fce_start)))
## 가중 합성 — 열 j 의 가중 w 로 종목마다 (값 있는 구성원 가중 합)으로 나눈다(분모 0 = 결측)
.fce_wavg <- function(Z0, A, j, w) {
  num <- drop(Z0[, j, drop = FALSE] %*% w); den <- drop(A[, j, drop = FALSE] %*% w)
  ifelse(den > 0, num / den, NA_real_)
}
.fce_rows <- list(); .fce_dg <- list()
for (.fce_i in seq_along(.fce_me)) {
  .fce_d <- .fce_me[.fce_i]
  .fce_r <- NULL
  invisible(utils::capture.output(.fce_r <- tryCatch(
    .fce_fc$fc_load_month(.fce_d, direction = "registry", factors = .FCE_MEMBERS$id, missing = "na", dedup = FALSE, family = FALSE),
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
  ## as-of IC → 구성원 가중(부호 = 등록부 고정 · 음수 · 없음 = 0)
  .fce_icr <- NULL
  invisible(utils::capture.output(.fce_icr <- .fce_ic$compute_rolling_ic_all(.fce_asof, .FCE_IC_MIN, .FCE_IC_MAX)))
  .fce_a <- .FCE_MEMBERS$s_reg * .fce_icr$ICIR[match(.FCE_MEMBERS$id, .fce_icr$Factor_Name)]
  .fce_w <- ifelse(is.finite(.fce_a) & .fce_a > 0, .fce_a, 0)
  if (length(.fce_w) != nrow(.FCE_MEMBERS) || any(!is.finite(.fce_w)) || any(.fce_w < 0))
    stop(sprintf("[%s] 가중 단정 위반(유한 · 비음수 · 구성원 수) — %s", .FCE_SPEC_ID, format(.fce_d, "%Y-%m")))
  .fce_P <- as.data.frame(.fce_r$panel)
  .fce_cols <- intersect(.FCE_MEMBERS$id, names(.fce_P))
  .fce_kc <- match(.fce_cols, .FCE_MEMBERS$id)
  .fce_wc <- .fce_w[.fce_kc]; .fce_fm <- .FCE_MEMBERS$family[.fce_kc]
  .fce_Z0 <- as.matrix(.fce_P[, .fce_cols, drop = FALSE]); storage.mode(.fce_Z0) <- "double"
  .fce_A <- !is.na(.fce_Z0); .fce_Z0[!.fce_A] <- 0
  ## 가족 T1 점수 = 구성원 가중 평균(값 있는 구성원) · 가중이 모두 0 이면 등가중(T0)
  .fce_j <- which(.fce_fm == .FCE_FAMILIES)
  .fce_npos <- sum(.fce_wc[.fce_j] > 0)
  .fce_fb <- length(.fce_j) > 0L && .fce_npos == 0L
  .fce_s <- if (!length(.fce_j)) rep(NA_real_, nrow(.fce_Z0)) else
    .fce_wavg(.fce_Z0, .fce_A, .fce_j, if (.fce_fb) rep(1, length(.fce_j)) else .fce_wc[.fce_j])
  .fce_v <- is.finite(.fce_s)
  .fce_nv <- if (length(.fce_j)) rowSums(.fce_A[, .fce_j, drop = FALSE][, (.fce_wc[.fce_j] > 0) | .fce_fb, drop = FALSE])[.fce_v] else numeric(0)
  .fce_np <- as.integer(.fce_npos > 0L)
  .fce_rows[[length(.fce_rows) + 1L]] <- data.frame(Date = rep(.fce_asof, sum(.fce_v)), Ticker = .fce_P$Ticker[.fce_v],
                                                    Score = .fce_s[.fce_v], stringsAsFactors = FALSE)
  .fce_dg[[length(.fce_dg) + 1L]] <- data.frame(Date = .fce_asof, n_members_present = length(.fce_cols), n_pos_weight = .fce_npos,
    n_families_weighted = .fce_np, fallback_t0 = .fce_fb, n_scored = sum(.fce_v),
    score_min = if (any(.fce_v)) min(.fce_s[.fce_v]) else NA_real_, score_max = if (any(.fce_v)) max(.fce_s[.fce_v]) else NA_real_,
    n_valid_min = if (length(.fce_nv)) min(.fce_nv) else NA_real_, n_valid_median = if (length(.fce_nv)) stats::median(.fce_nv) else NA_real_,
    n_valid_max = if (length(.fce_nv)) max(.fce_nv) else NA_real_)
}
if (!length(.fce_rows)) stop(sprintf("[%s] 산출이 비었다 — 시작일 %s 뒤 점수가 있는 달이 없다", .FCE_SPEC_ID, format(.fce_start)))
FACTORS <- data.table::rbindlist(.fce_rows)
if (!nrow(FACTORS)) stop(sprintf("[%s] 산출이 비었다 — 점수가 있는 종목이 없다", .FCE_SPEC_ID))
.fce_dgt <- do.call(rbind, .fce_dg)
cat(sprintf("[%s] FACTORS %d행 · 달 %d(%s ~ %s) · 시작 %s · 구성원 선언 %d · 달마다 있는 구성원 %d ~ %d\n", .FCE_SPEC_ID, nrow(FACTORS),
            nrow(.fce_dgt), format(min(.fce_dgt$Date)), format(max(.fce_dgt$Date)), format(.fce_start), nrow(.FCE_MEMBERS),
            min(.fce_dgt$n_members_present), max(.fce_dgt$n_members_present)))
.fce_dd <- getOption("fce.diag_dir", file.path(.fce_root, "04_Research", "strategies", .FCE_SPEC_ID))
if (dir.exists(.fce_dd) && !is.na(.fce_tau)) {
  .fce_dgt <- .fce_dgt[.fce_dgt$Date <= .fce_tau, , drop = FALSE]
  .fce_dgt$start <- rep(format(.fce_start), nrow(.fce_dgt)); .fce_dgt$spec_md5 <- rep(.FCE_SPEC_MD5, nrow(.fce_dgt))
  .fce_tmp <- file.path(.fce_dd, sprintf(".fce_diag_%d.tmp", Sys.getpid()))
  .fce_to <- file.path(.fce_dd, "fce_diag.csv")
  .fce_wr <- tryCatch({
    utils::write.csv(.fce_dgt, .fce_tmp, row.names = FALSE)
    if (file.exists(.fce_to)) file.remove(.fce_to)
    file.rename(.fce_tmp, .fce_to)
  }, error = function(e) FALSE)
  if (!isTRUE(.fce_wr)) { unlink(.fce_tmp); warning(sprintf("[%s] 진단 파일을 쓰지 못했다(판정 무관): %s", .FCE_SPEC_ID, .fce_dd)) }
}
suppressWarnings(rm(list = c(".fce_rows", ".fce_dg", ".fce_dgt", ".fce_r", ".fce_m", ".fce_in", ".fce_k", ".fce_ok", ".fce_s", ".fce_v",
                             ".fce_nv", ".fce_np", ".fce_npos", ".fce_fb", ".fce_icr", ".fce_a", ".fce_w", ".fce_P", ".fce_cols", ".fce_kc",
                             ".fce_wc", ".fce_fm", ".fce_Z0", ".fce_A", ".fce_j", ".fce_S", ".fce_W", ".fce_g", ".fce_Wm", ".fce_den",
                             ".fce_cal", ".fce_me", ".fce_d", ".fce_i", ".fce_asof", ".fce_em", ".fce_dd", ".fce_tmp", ".fce_wr", ".fce_to",
                             ".fce_fc", ".fce_ic", ".fce_start", ".fce_tau", ".fce_wavg", ".FCE_M")))
invisible(gc(verbose = FALSE))
