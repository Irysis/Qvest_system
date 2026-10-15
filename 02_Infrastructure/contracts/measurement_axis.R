#==============================================================================
# measurement_axis.R — 측정 축 epoch 계약 (v10.01 · MC1 · MC3 · 2026-10-13)
#
# 왜: 결정 D11(유니버스 = 전 종목 + 위생) · D15(시작 2000-01-01)는 고정 축 변경이다. 같은 축 안에서만 비교해야
#   하므로(설계 l1_prescription_redesign_20261013 §9.5 '측정 축 epoch') 축을 설정 정본
#   constraint_defaults.json::measurement_axis 의 epoch 로 묶고, 이 계약이 측정에 주입한다.
# 유니버스는 엔진이 아니라 계약이 정한다: 충실구현 엔진 32/32 가 RAWDATA 의 K200/KQ150 플래그로 유니버스를 자르므로
#   (10-10 전 시장 파일럿 · 러너 인자만 바꾸면 처치가 안 간다) 적재 직후 두 플래그를 epoch 멤버십으로 바꿔 끼운다.
#   원 플래그는 K200_IDX / KQ150_IDX 로 보존한다(지수 멤버십이 필요한 소비자용 · 주입 표식).
# 위생 = QEPM 공통 헌장 §11 Variant A — factor_z_standard.R::corp_action_member(표준 필터의 판정식 정본 · 재구현 금지):
#   20일 평균 거래대금(t−1 · C10) ≥ 하한 ∧ 관리종목 · 거래정지 · 불성실공시 표식 아님.
#   표식은 퀀티와이즈 월말 스냅샷을 다음 스냅샷 전까지 이전 값으로 이월한 것이다(data/apply_universe_mapping.R roll join
#   — 그날까지 알려진 값만 · PIT). 행이 없는 날(상장 전 · 폐지 후)은 멤버가 아니다.
# 실효 시작(MC3 · 도훈 B안 10-13): epoch 에 effective_start 규칙이 있으면 신호 폭 ≥ 보유 × 배수 첫 신호일부터 성과를 센다(ma_effective_start)
#   · A 관문 창 이탈 기준 = 그 실효 시작(ma_window_anchor). 규칙이 없는 epoch(구 축)는 아무것도 바뀌지 않는다.
# 공개: ma_config · ma_epoch · ma_epoch_by_universe · ma_adv20_l1 · ma_membership · ma_inject_universe ·
#       ma_fidelity_universe · ma_record · ma_signal_coverage · ma_effective_start · ma_window_anchor
# 검사: 08_Tests/contracts/test_measurement_axis.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.ma_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

.ma_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "02_Infrastructure", "worktask", "constraint_defaults.json"))) return(p)
  }
  stop("[measurement_axis] 프로젝트 루트(constraint_defaults.json) 해석 실패")
}

#' 설정 — constraint_defaults.json 전체와 measurement_axis 블록(없으면 멈춘다 · 축을 지어내지 않는다)
ma_config <- function(root = NULL) {
  root <- .ma_root(root)
  f <- file.path(root, "02_Infrastructure", "worktask", "constraint_defaults.json")
  cd <- fromJSON(f, simplifyVector = FALSE)
  ma <- cd[["measurement_axis"]]
  if (!is.list(ma) || !is.list(ma[["epochs"]]) || !length(ma[["epochs"]]))
    stop("[measurement_axis] constraint_defaults.json::measurement_axis.epochs 없음 — fail-closed")
  act <- as.character(.ma_or(ma[["active"]], ""))
  if (!nzchar(act) || is.null(ma[["epochs"]][[act]])) stop("[measurement_axis] active epoch '", act, "' 가 epochs 에 없다")
  list(cd = cd, ma = ma, active = act, path = f, root = root)
}

.ma_get_key <- function(cd, dotted) {
  x <- cd
  for (k in strsplit(dotted, ".", fixed = TRUE)[[1]]) { if (!is.list(x)) return(NULL); x <- x[[k]] }
  x
}

#' epoch 하나 — id NULL 이면 active. 값은 설정에서만(하한은 liq_min_key 가 가리키는 정본 키에서 해석)
ma_epoch <- function(id = NULL, root = NULL) {
  C <- ma_config(root)
  id <- .ma_or(id, C$active)
  e <- C$ma[["epochs"]][[id]]
  if (is.null(e)) stop("[measurement_axis] epoch '", id, "' 없음")
  uni <- as.character(.ma_or(e[["universe"]], ""))
  if (!uni %in% c("K200_KQ150", "ALL_HYG")) stop("[measurement_axis] epoch '", id, "' universe '", uni, "' 미지원")
  st <- tryCatch(as.Date(as.character(e[["start_date"]])), error = function(z) as.Date(NA))
  if (length(st) != 1L || is.na(st)) stop("[measurement_axis] epoch '", id, "' start_date 판독 실패")
  liq <- NA_real_; flags <- character(0)
  if (isTRUE(e[["hygiene"]])) {
    key <- as.character(.ma_or(e[["liq_min_key"]], ""))
    liq <- suppressWarnings(as.numeric(.ma_get_key(C$cd, key)))
    if (length(liq) != 1L || !is.finite(liq) || liq <= 0)
      stop("[measurement_axis] epoch '", id, "' 유동성 하한(", key, ") 판독 실패 — 하한을 지어내지 않는다")
    flags <- as.character(unlist(e[["excluded_flags"]]))
    if (!length(flags)) stop("[measurement_axis] epoch '", id, "' excluded_flags 비었음")
  }
  list(id = id, universe = uni, start_date = st, hygiene = isTRUE(e[["hygiene"]]), liq_min = liq,
       excluded_flags = flags, active = identical(id, C$active), source = as.character(.ma_or(e[["source"]], "")),
       effective_start = .ma_eff_rule(e[["effective_start"]], id))
}

#' 실효 시작 규칙(MC3 · 도훈 B안 10-13) — epoch 설정에 없으면 NULL(구 축 = 규칙 없음 · 비트 동일). 있으면 형식을 엄격히 본다(fail-closed —
#'   배수를 지어내지 않는다). 규칙 = breadth_multiple(신호 폭 ≥ 보유 수 × breadth_mult) · window_anchor = effective_start(A 관문 창 이탈 기준).
.ma_eff_rule <- function(x, id) {
  if (is.null(x)) return(NULL)
  if (!is.list(x)) stop("[measurement_axis] epoch '", id, "' effective_start 형식 오류(객체 아님)")
  rule <- as.character(.ma_or(x[["rule"]], ""))
  if (!identical(rule, "breadth_multiple")) stop("[measurement_axis] epoch '", id, "' effective_start.rule 미지원: '", rule, "'")
  m <- suppressWarnings(as.numeric(x[["breadth_mult"]]))
  if (length(m) != 1L || !is.finite(m) || m <= 1) stop("[measurement_axis] epoch '", id, "' effective_start.breadth_mult 판독 실패(> 1 인 수 하나)")
  wa <- as.character(.ma_or(x[["window_anchor"]], ""))
  if (!wa %in% c("effective_start", "diagnostics")) stop("[measurement_axis] epoch '", id, "' effective_start.window_anchor 미지원: '", wa, "'")
  list(rule = rule, breadth_mult = m, window_anchor = wa)
}

#' 유니버스 이름 → epoch(active 가 그 유니버스면 active, 아니면 그 유니버스의 유일한 epoch)
ma_epoch_by_universe <- function(universe, root = NULL) {
  C <- ma_config(root)
  ids <- names(C$ma[["epochs"]])
  hit <- ids[vapply(ids, function(i) identical(as.character(.ma_or(C$ma[["epochs"]][[i]][["universe"]], "")), universe), logical(1))]
  if (!length(hit)) stop("[measurement_axis] universe '", universe, "' 를 쓰는 epoch 없음")
  if (C$active %in% hit) return(ma_epoch(C$active, C$root))
  if (length(hit) > 1L) stop("[measurement_axis] universe '", universe, "' epoch 가 여럿(", paste(hit, collapse = ","), ") — 지정 필요")
  ma_epoch(hit, C$root)
}

#' 20일 평균 거래대금(t−1) — 종가 × 거래량의 20거래일 이동평균을 하루 늦춘다(C10). DT 행 순서대로 돌려준다(DT 불변).
ma_adv20_l1 <- function(DT) {
  need <- c("Date", "Ticker", "Close", "Vol")
  if (!all(need %in% names(DT))) stop("[measurement_axis] adv20 계산 열 부족: ", paste(setdiff(need, names(DT)), collapse = ","))
  K <- data.table(.i = seq_len(nrow(DT)), Ticker = DT$Ticker, Date = as.Date(DT$Date),
                  .tv = as.numeric(DT$Close) * as.numeric(DT$Vol))
  setorder(K, Ticker, Date)
  K[, .a := shift(frollmean(.tv, 20L, align = "right"), 1L), by = Ticker]
  setorder(K, .i)
  K$.a
}

#' 위생 멤버십(행 단위 논리) — epoch 의 하한 · 표식으로 표준 판정식(corp_action_member)을 부른다
ma_membership <- function(DT, ep) {
  if (!isTRUE(ep$hygiene)) stop("[measurement_axis] 위생 epoch 가 아니다: ", ep$id)
  miss <- setdiff(ep$excluded_flags, names(DT))
  if (length(miss)) stop("[measurement_axis] RAWDATA 에 위생 표식 열 없음: ", paste(miss, collapse = ","), " — 표식 없이 멤버십을 만들지 않는다")
  if (!exists("corp_action_member", mode = "function")) {
    f <- file.path(.ma_root(NULL), "02_Infrastructure", "factor_db", "factor_z_standard.R")
    invisible(utils::capture.output(suppressMessages(sys.source(f, envir = globalenv(), keep.source = FALSE))))
  }
  if (!identical(sort(ep$excluded_flags), sort(c("AdminStock", "TradingHalt", "UnfaithfulDisc"))))
    stop("[measurement_axis] 표준 판정식은 AdminStock · TradingHalt · UnfaithfulDisc 세 표식만 안다 — 설정과 다름")
  liq <- ma_adv20_l1(DT)
  corp_action_member(liq, DT$AdminStock, DT$TradingHalt, DT$UnfaithfulDisc, ep$liq_min)
}

#' RAWDATA 주입 — ALL_HYG 면 K200 := 멤버(1/0) · KQ150 := 0 (원 플래그 = K200_IDX/KQ150_IDX). K200_KQ150 이면 아무것도 안 한다.
#'   ★참조 수정(data.table `:=`) — 호출자의 RAWDATA 가 바뀐다(러너 안의 측정 전용 사본에만 쓴다).
#'   이미 주입됐으면(K200_IDX 존재) 원 플래그로 다시 계산한다(이중 주입이 원 플래그를 덮지 않는다).
ma_inject_universe <- function(RAWDATA, ep) {
  if (!data.table::is.data.table(RAWDATA)) stop("[measurement_axis] RAWDATA 는 data.table 이어야 한다")
  if (identical(ep$universe, "K200_KQ150")) return(list(RAWDATA = RAWDATA, diag = list(mode = "noop", epoch = ep$id)))
  if (!all(c("K200", "KQ150") %in% names(RAWDATA))) stop("[measurement_axis] RAWDATA K200/KQ150 열 없음")
  if (!"K200_IDX" %in% names(RAWDATA)) RAWDATA[, `:=`(K200_IDX = K200, KQ150_IDX = KQ150)]
  mem <- ma_membership(RAWDATA, ep)
  n_idx <- sum((RAWDATA$K200_IDX %in% c(1, TRUE)) | (RAWDATA$KQ150_IDX %in% c(1, TRUE)), na.rm = TRUE)
  RAWDATA[, K200 := as.numeric(mem)]
  RAWDATA[, KQ150 := 0]
  per_day <- RAWDATA[K200 == 1, .N, by = Date]
  idx_day <- RAWDATA[(K200_IDX %in% c(1, TRUE)) | (KQ150_IDX %in% c(1, TRUE)), .N, by = Date]
  list(RAWDATA = RAWDATA,
       diag = list(mode = "injected", epoch = ep$id, universe = ep$universe, liq_min = ep$liq_min,
                   excluded_flags = ep$excluded_flags, member_rows = sum(mem), index_member_rows = n_idx,
                   members_per_day_median = if (nrow(per_day)) as.numeric(stats::median(per_day$N)) else NA_real_,
                   index_members_per_day_median = if (nrow(idx_day)) as.numeric(stats::median(idx_day$N)) else NA_real_))
}

#' FIDELITY 의 유니버스 문구 — K200_KQ150 은 구판 문구 그대로(비트 동일 manifest)
ma_fidelity_universe <- function(universe) {
  if (is.null(universe) || identical(universe, "K200_KQ150") || identical(universe, "INDEX")) return("universe 치환(K200∪KQ150)")
  if (identical(universe, "ALL_HYG"))
    return("universe = 전 종목 + 위생(하우스 규칙 · 계약 주입 — 20일 거래대금(t−1) ≥ 하한 · 관리종목 · 거래정지 · 불성실공시 제외)")
  sprintf("universe = %s", universe)
}

#' 권위 기록용 축 블록
ma_record <- function(ep, diag = NULL) {
  list(epoch = ep$id, universe = ep$universe, start_date = format(ep$start_date), hygiene = ep$hygiene,
       liq_min = ep$liq_min, excluded_flags = ep$excluded_flags, active_epoch = isTRUE(ep$active),
       membership = diag, source = ep$source, effective_start_rule = ep$effective_start)
}

#' 신호 커버리지 기록(MC3 · 기록 전용 — 자르지 않는다) — 연도별 신호 폭(그날 신호가 있는 종목 수)과 멤버 수의 중앙값, 첫 신호일.
#'   ★폭은 **선정 전** 신호 패널(FACTORS · 유니버스 적용 뒤 · 점수 유한)에서 잰다(basis = "factors"). 선정 뒤 보유(WEIGHTS)로 재면
#'   폭이 보유 수(예: 25)로 눌려 커버리지를 말하지 못한다(10-13 첫 기록이 그랬다). PORTFOLIO 만 내는 엔진은 보유로만 잴 수 있다(basis = "holdings").
ma_signal_coverage <- function(dt, RAWDATA = NULL, basis = "holdings", breadth = NULL) {
  if (!is.null(breadth) && NROW(breadth)) {          # 엔진 보고 폭(선정 전 후보 수 · MC3 B) — FACTORS 가 미리 잘린 엔진(셀 엔진)용
    br <- data.table(Date = as.Date(breadth$Date), breadth = suppressWarnings(as.integer(breadth$breadth)))[!is.na(Date)]
    basis <- "engine_reported"
  } else {
    if (is.null(dt) || !nrow(dt)) return(list(status = "empty", basis = basis))
    d <- data.table(Date = as.Date(dt$Date), Ticker = dt$Ticker)
    if ("Score" %in% names(dt)) d <- d[is.finite(suppressWarnings(as.numeric(dt$Score)))]
    if (!nrow(d)) return(list(status = "empty", basis = basis))
    br <- d[, list(breadth = uniqueN(Ticker)), by = Date]
  }
  if (!nrow(br)) return(list(status = "empty", basis = basis))
  if (!is.null(RAWDATA) && all(c("K200", "KQ150") %in% names(RAWDATA))) {
    if (!inherits(RAWDATA$Date, "Date") || !inherits(br$Date, "Date")) stop("[measurement_axis] 날짜 열은 Date 여야 한다(정수 일 번호 비교)")
    un <- RAWDATA[as.integer(Date) %in% as.integer(br$Date) & (K200 %in% c(1, TRUE) | KQ150 %in% c(1, TRUE)), list(universe_n = .N), by = Date]   # 정수 일 번호(2026-10-15 속도 · 결과 동일 — Date %in% 은 전 행 문자열 서식화)
    br <- merge(br, un, by = "Date", all.x = TRUE)
  } else br[, universe_n := NA_integer_]
  br[, yr := format(Date, "%Y")]
  by_year <- br[, list(breadth_median = as.numeric(stats::median(breadth)),
                       universe_median = as.numeric(stats::median(universe_n, na.rm = TRUE)), n_dates = .N), by = yr]
  list(status = "ok", basis = basis, first_signal_date = format(min(br$Date)), last_signal_date = format(max(br$Date)),
       n_signal_dates = nrow(br), by_year = by_year)
}

#' 실효 시작(MC3 · 도훈 B안 10-13 · decision_register MC3-EFFECTIVE-START-B)
#'   실효 시작 = 신호 폭(그 신호일 FACTORS 에서 점수가 유한한 종목 수 · 유니버스 적용 뒤) ≥ 보유 수(그 신호일 WEIGHTS 비중 ≠ 0 종목 수)
#'   × breadth_mult 를 **처음** 만족한 신호일. 그 전 신호일은 성과에서 뺀다 — 폭이 보유의 몇 배가 안 되면 상위 N 선정은 '있는 것 다 사기'다.
#'   ★PIT: 첫 통과 시각이다 — 각 신호일의 판정은 그날의 폭 · 보유만 쓴다(뒷날 값으로 기준을 잡지 않는다 · C안과의 차이).
#'   시작 뒤 문턱 아래로 내려간 신호일은 자르지 않고 수만 기록한다(구간을 구멍 내지 않는다).
#'   PORTFOLIO 만 내는 엔진(FACTORS 없음)은 후보 수를 알 수 없다 → 자르지 않고 status = "breadth_unmeasurable"(실효 시작 = 첫 신호일 · 표식).
#' @param FACTORS 측정에 들어간 신호 패널(Date, Ticker, Score) 또는 NULL
#' @param WEIGHTS 측정 비중(Date = 신호일, Ticker, Weight)
#' @param rule    ma_epoch()$effective_start (NULL 이면 status "no_rule")
#' @param breadth 엔진이 보고한 선정 전 후보 폭 data.table(Date, breadth) — 있으면 FACTORS 보다 우선(basis "engine_reported").
#'   셀 엔진(rf_cell_engine.R)은 상위 n_max 만 FACTORS 로 내므로 FACTORS 폭 = n_max 다(그대로 재면 규칙이 영영 안 선다 · 10-13 실측 전 발견).
#'   보고가 없고 FACTORS 폭이 모든 신호일에 보유 수 이하면(미리 잘린 패널) 폭을 잴 수 없다 → breadth_unmeasurable(factors_pretruncated · 자르지 않음).
#' @return list(status = ok | never_met | breadth_unmeasurable | no_rule, date, first_signal_date, n_dates_cut, ...)
ma_effective_start <- function(FACTORS, WEIGHTS, rule, breadth = NULL) {
  if (is.null(rule)) return(list(status = "no_rule"))
  if (is.null(WEIGHTS) || !nrow(WEIGHTS)) stop("[measurement_axis] 실효 시작 — WEIGHTS 가 비었다")
  W <- data.table(Date = as.Date(WEIGHTS$Date), Ticker = WEIGHTS$Ticker, Weight = suppressWarnings(as.numeric(WEIGHTS$Weight)))
  hd <- W[is.finite(Weight) & Weight != 0, list(holdings = uniqueN(Ticker)), by = Date]
  if (!nrow(hd)) stop("[measurement_axis] 실효 시작 — 비중 ≠ 0 인 보유가 없다")
  setorder(hd, Date)
  base <- list(rule = rule$rule, breadth_mult = rule$breadth_mult, window_anchor = rule$window_anchor,
               first_signal_date = format(min(hd$Date)), n_signal_dates = nrow(hd))
  unmeas <- function(basis, note) c(base, list(status = "breadth_unmeasurable", basis = basis, date = format(min(hd$Date)),
                                               n_dates_cut = 0L, note = note))
  if (!is.null(breadth) && NROW(breadth)) {
    if (!all(c("Date", "breadth") %in% names(breadth))) stop("[measurement_axis] 엔진 보고 폭은 (Date, breadth) 표여야 한다")
    br <- data.table(Date = as.Date(breadth$Date), breadth = suppressWarnings(as.integer(breadth$breadth)))[!is.na(Date)]
    basis <- "engine_reported"
  } else {
    if (is.null(FACTORS) || !nrow(FACTORS) || !all(c("Date", "Ticker", "Score") %in% names(FACTORS)))
      return(unmeas("portfolio_only", "엔진이 PORTFOLIO 만 내 신호 폭(후보 수)을 잴 수 없다 — 자르지 않음(실효 시작 = 첫 신호일) · 폭 미측정 표식"))
    Fx <- data.table(Date = as.Date(FACTORS$Date), Ticker = FACTORS$Ticker, Score = suppressWarnings(as.numeric(FACTORS$Score)))
    br <- Fx[is.finite(Score), list(breadth = uniqueN(Ticker)), by = Date]
    basis <- "factors"
    chk <- merge(hd, br, by = "Date", all.x = TRUE)
    if (nrow(chk) && all(!is.na(chk$breadth) & chk$breadth <= chk$holdings))
      return(unmeas("factors_pretruncated", "FACTORS 가 모든 신호일에 보유 수 이하 — 엔진이 미리 자른 패널로 보인다(후보 폭 미보고) · 자르지 않음 · 폭 미측정 표식"))
  }
  X <- merge(hd, br, by = "Date", all.x = TRUE)
  X[is.na(breadth), breadth := 0L]
  X[, ok := breadth >= rule$breadth_mult * holdings]
  setorder(X, Date)
  if (!any(X$ok))
    return(c(base, list(status = "never_met", basis = basis, date = NA_character_, n_dates_cut = nrow(X),
                        breadth_max = max(X$breadth), holdings_median = as.numeric(stats::median(X$holdings)),
                        note = "신호 폭이 보유 수 × 배수에 한 번도 못 미쳤다 — 선정이 성립한 신호일이 없다(측정 무효)")))
  d0 <- X[ok == TRUE][1]$Date
  aft <- X[Date >= d0]
  c(base, list(status = "ok", basis = basis, date = format(d0), n_dates_cut = sum(X$Date < d0),
               breadth_at_start = X[Date == d0]$breadth, holdings_at_start = X[Date == d0]$holdings,
               n_dates_below_after = sum(!aft$ok)))
}

#' A 관문 창 이탈 기준일(MC3 B · window_anchor = effective_start) — 권위 기록의 measurement_axis 블록에서 읽는다.
#'   규칙이 실효 시작 기준이고 실효 시작일이 기록돼 있으면 그 날짜, 아니면 NA(호출자가 전역 diagnostics.window_anchor_date 로 떨어진다).
ma_window_anchor <- function(mx) {
  if (!is.list(mx)) return(as.Date(NA))
  es <- mx[["effective_start"]]; rl <- mx[["effective_start_rule"]]
  if (!is.list(es) || !is.list(rl) || !identical(as.character(.ma_or(rl[["window_anchor"]], "")), "effective_start")) return(as.Date(NA))
  d <- tryCatch(as.Date(as.character(.ma_or(es[["date"]], NA))), error = function(e) as.Date(NA))
  if (length(d) == 1L) d else as.Date(NA)
}
