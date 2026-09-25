#==============================================================================
# rf_sleeve.R — B7 구조적 방어 슬리브 (도훈 지시 2026-09-21)
#
# 왜 이 축인가 (실측):
#   · 분모(MDD)를 치는 유일한 축이던 B5 오버레이는 137칸을 태우고 적대검증 **pass 0**
#     (fail 11 · not_candidate 31). 노출 타이밍 주장은 노출-짝지은 플라시보(T3)를 못 넘었다.
#   · 방어 팩터를 B1 복합점수에 얹는 방식은 **67칸 이미 시험**됐고 MDD 0.53~0.67 로 불변,
#     최고 Calmar 0.419. 점수 혼합은 알파를 희석할 뿐 보유 구조를 안 바꾼다.
#   · 그런데 `module_catalog.json::defensive_score` 를 보면 **B등급 ∧ 심층 capture <0.80 인
#     모듈이 89개**(최고 0.392) 실재한다 — 위기에 덜 깨지는 보유 구성은 존재한다.
#   ⇒ 비어 있는 자리 = **선정 축의 구조적 방어**. 보유 종목의 일부를 방어 슬리브에 내준다.
#
# ★설계 불변식 (이걸 깨면 B5 의 재림이 된다):
#   ① **분할 비율 k 는 정적이다.** 시점마다 k 를 바꾸면 그 순간 총노출 타이밍 주장이 되고
#      T3 플라시보에 똑같이 죽는다. k 는 전 기간 고정이고 k 자체가 시험 축이다.
#   ② 총노출은 건드리지 않는다 — Sigma w = 1 유지, 현금 없음. 바뀌는 건 **누구를 보유하는가** 뿐.
#   ③ |SEL| 은 n_max 로 보존된다. 슬리브는 25종 **안에서의 분할**이다(PIT 2-슬리브 조항과 정합).
#
# ★팩터 id 를 박지 않는다 — 선택은 규칙이 한다(`rf_sl_resolve`).
#
# ★선정 규칙 = `ic_bad_rank_asof` (2026-09-24 · 플랜 P0-08 · 감사 D4-02·D4-05·D10-05 · pit.md C1 D-E 명문화).
#   구판 `ic_bad_rank` 는 factor_evidence.json 의 ic_bad(stage_gate_engine.R:889 sg_compute_conditional_ic 산출)를
#   내림차순으로 골랐다. 그 값에는 결함이 넷 있었다:
#     ① 전기간(2002~2025) 평균 — 2005~ 시그널일의 보유를 그 뒤 IC 로 골랐다(C1/C14 · 평가 창 결과를 소비하는 자동 선정).
#     ② 약세장 달을 보유 **종료**일(nxt)로 적어 IC[t](= corr(f[t], ret t→t+1))와 한 달 어긋났다.
#     ③ 기준 계열 STR_1375 부재 → STR_1469(레거시 5-sleeve) 로 대체된 전략 월수익이었다.
#     ④ 이미 소수인 Ret 을 /100 했다.
#   ⇒ B7 칸들은 설계가 말한 처치("약세장에서 잘 줄세우는 방어 팩터")를 시험하지 못했다
#     (원장 표식 treatment_misspecified — 재측정 없음: 규칙이 바뀌면 새 칸이다).
#   신판(`rf_sl_conditional_ic_asof`): as-of d 까지 **실현된** KOSPI200 월수익(공표 지수 포인트 BM_Close)으로
#   약세장 보유월을 **확장창 하위 q 분위**로 정하고, 그 달을 보유월로 갖는 IC 행(형성일 t = 보유월 직전 월말 ·
#   Usable_Date = 보유월 말 ≤ d)만 평균한다. q·최소 표본·후보 계열·경로 = reinforce_program.json B7.selection_asof.
#   ★정적 슬리브 불변식(①)을 지키려고 id 는 **워밍업 창 as-of(기본 = 셀 fixed_axes.start_date · 첫 시그널일 이전)로
#   1회 고정**한다 — 엔진 재구성 없음. 함수는 as-of 를 인자로 받으므로 시그널일마다 부를 수도 있다(그 경로는
#   엔진이 후보 팩터 전부를 적재해야 하고 불변식 재해석이 필요하다 — 미배선).
#   ★as-of 상한 가드 (2026-09-25 · P0-08 잔여 R3): .rf_sl_asof 가 인자·규칙 as-of 를 결정 시점(셀 스펙 fixed_axes.start_date ·
#     없으면 격자 fixed_axes.start_date) 이하로만 받는다 — 뒤·미래·NA·복수는 stop. 저수준 계산기(rf_sl_conditional_ic_asof ·
#     rf_sl_bench_months)는 d 를 받는 순수 함수라 결정 시점을 모른다 — 운영 호출은 rf_sl_resolve 경유 1곳뿐이다.
#
# 공개: rf_sl_parse / rf_sl_resolve / rf_sl_conditional_ic_asof / rf_sl_bench_months / rf_sl_select_config /
#       rf_sl_select / rf_sl_turnover_overlap / rf_sl_report
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.RF_SL_KINDS <- c("factor_topk", "antidefense", "random_beta_matched")
.RF_SL_SELECTS <- c("ic_bad_rank_asof")
# 퇴역 규칙 — 조용히 신판으로 바꿔 읽지 않고 멈춘다(바꿔 읽으면 구 칸과 새 칸이 같은 서명으로 섞인다).
#   과거 칸 재현은 factor_id 고정 경로로 한다(로그 log_B7_*.txt 의 해석 id).
.RF_SL_RETIRED_SELECTS <- c(
  ic_bad_rank = paste0("전표본 ic_bad(C1/C14) · 약세장 달 한 달 어긋남 · 레거시 전략(STR_1469) 대체 · Ret/100 ",
                       "(감사 D4-02·D4-05 · 2026-09-24 P0-08 퇴역) — select='ic_bad_rank_asof' 를 쓰거나 재현이면 factor_id 를 고정하라"))

#' 슬리브 규칙 파싱 — 미지원 종류/인자는 **조용히 무시하지 않고 멈춘다**
#'   (침묵 폴백은 '처치를 안 받은 칸'을 '처치를 받은 칸'으로 기록한다)
rf_sl_parse <- function(x) {
  if (is.null(x) || !length(x)) return(NULL)
  if (!is.list(x)) stop("[rf_sleeve] defense_sleeve 는 list 여야 한다")
  kind <- as.character(x$kind %||% "")
  if (!nzchar(kind)) return(NULL)
  if (!(kind %in% .RF_SL_KINDS))
    stop(sprintf("[rf_sleeve] 미지원 kind '%s' (지원: %s)", kind, paste(.RF_SL_KINDS, collapse = ", ")))
  k <- suppressWarnings(as.integer(x$k %||% NA_integer_))
  if (!is.finite(k) || k < 1L) stop("[rf_sleeve] k 는 1 이상 정수여야 한다")
  # ★factor_kind: 방어 팩터의 **원천**. 기본 "db"(팩터 DB · C15 경유). 엔진이 이미 지원하는
  #   다른 원천(예: 오프라인 price 팩터)도 그대로 쓸 수 있어야 한다 — 그래야 엔진 경유 검사가 선다.
  # ★asof: 선정 통계 창의 끝(선택). 없으면 rf_sl_resolve 가 셀 fixed_axes.start_date 로 해석한다.
  ok_args <- c("kind", "k", "select", "rank", "factor_id", "factor_kind", "beta_factor", "seed", "label", "basis", "asof")
  extra <- setdiff(names(x), ok_args)
  if (length(extra)) stop(sprintf("[rf_sleeve] 알 수 없는 인자: %s", paste(extra, collapse = ", ")))
  fid <- as.character(x$factor_id %||% "")
  sel <- as.character(x$select %||% "ic_bad_rank_asof")
  # 퇴역 select 는 파싱에서 멈춘다(엔진 계산 전) — 단 factor_id 고정이면 select 는 쓰이지 않으므로 통과(과거 칸 재현 경로)
  if (!nzchar(fid) && sel %in% names(.RF_SL_RETIRED_SELECTS))
    stop(sprintf("[rf_sleeve] 퇴역 select '%s' — %s", sel, .RF_SL_RETIRED_SELECTS[[sel]]))
  if (!nzchar(fid) && !(sel %in% .RF_SL_SELECTS))
    stop(sprintf("[rf_sleeve] 미지원 select '%s' (지원: %s)", sel, paste(.RF_SL_SELECTS, collapse = ", ")))
  list(kind = kind, k = k,
       select = sel,
       rank = suppressWarnings(as.integer(x$rank %||% 1L)),
       factor_id = fid,
       factor_kind = as.character(x$factor_kind %||% "db"),
       beta_factor = as.character(x$beta_factor %||% "D02_Beta"),
       seed = suppressWarnings(as.integer(x$seed %||% NA_integer_)),
       label = as.character(x$label %||% kind),
       asof = as.character(x$asof %||% ""))
}

#' B7 선정 설정 — reinforce_program.json 의 B7.selection_asof (★하드코딩 금지 — 분위·최소 표본·후보 계열·경로는 격자가 진다).
#'   없거나 값이 범위 밖이면 stop(fail-closed): 기본값을 코드에 두면 격자와 코드가 다른 규칙을 말하게 된다.
rf_sl_select_config <- function(root = Sys.getenv("QM_ROOT", ".")) {
  p <- file.path(root, "06_Registry/reinforce_program.json")
  if (!file.exists(p)) stop("[rf_sleeve] reinforce_program.json 부재 — B7 선정 설정(selection_asof)을 읽을 곳이 없다: ", p)
  G <- fromJSON(p, simplifyVector = FALSE)
  b7 <- Filter(function(b) identical(as.character(b$id %||% ""), "B7"), G$blocks %||% list())
  cfg <- if (length(b7)) b7[[1]][["selection_asof"]] else NULL
  if (!is.list(cfg)) stop("[rf_sleeve] B7.selection_asof 설정 부재 — 분위·최소 표본을 코드에 박지 않는다: ", p)
  need <- c("bear_quantile", "min_bear_months", "candidate_categories", "rank_key", "ic_path", "bench_path", "bench_price_col")
  miss <- need[vapply(need, function(k) is.null(cfg[[k]]), logical(1))]
  if (length(miss)) stop(sprintf("[rf_sleeve] B7.selection_asof 필수 키 부재: %s", paste(miss, collapse = ", ")))
  q  <- suppressWarnings(as.numeric(cfg$bear_quantile))
  mn <- suppressWarnings(as.integer(cfg$min_bear_months))
  rk <- as.character(cfg$rank_key)
  cats <- as.character(unlist(cfg$candidate_categories))
  if (length(q) != 1L || !is.finite(q) || q <= 0 || q >= 1) stop("[rf_sleeve] bear_quantile 은 (0,1) 한 값이어야 한다")
  if (length(mn) != 1L || !is.finite(mn) || mn < 1L) stop("[rf_sleeve] min_bear_months 는 1 이상 정수여야 한다")
  if (length(rk) != 1L || !(rk %in% c("ic_bad", "conditional_value")))
    stop(sprintf("[rf_sleeve] rank_key '%s' 미지원 (ic_bad | conditional_value)", paste(rk, collapse = ",")))
  if (!length(cats)) stop("[rf_sleeve] candidate_categories 가 비었다")
  list(q = q, min_n = mn, rank_key = rk, cats = cats,
       ic_path = as.character(cfg$ic_path), bench_path = as.character(cfg$bench_path),
       bench_price_col = as.character(cfg$bench_price_col),
       fixed_axes_start = as.character((G$fixed_axes %||% list())$start_date %||% ""), source = p)
}

#' as-of 해석 — 인자 > 규칙 asof > 셀 스펙(RF_CELL_SPEC) fixed_axes.start_date > 격자 fixed_axes.start_date.
#'   ★전부 없으면 stop — 전기간으로 계산하지 않는다(C1).
#' ★상한 가드 (2026-09-25 · P0-08 잔여 R3) — 결정 시점 = 칸의 첫 시그널일 이전 워밍업 창 끝 =
#'   셀 스펙(RF_CELL_SPEC) fixed_axes.start_date(엔진 .START 와 같은 원천) · 없으면 격자 fixed_axes.start_date.
#'   슬리브 id 는 워밍업 창에서 1회 고정돼 그 칸의 전 시그널일에 쓰이므로(정적 슬리브 불변식 ①) as-of 가 결정 시점 뒤면
#'   첫 시그널일 뒤 실현 약세장 IC 로 방어 팩터를 고른 것이다(pit.md C1 D-E · C14).
#'   구판은 인자·규칙 as-of 에 상한이 없어 2020·2099·미래 날짜가 통과했고(엔진 경로 = 셀 시작 2005 + 규칙 asof 2015 도 통과),
#'   인자 NA 는 '없음' 으로 읽혀 조용히 기본값으로 갔다(실증 = R3 evidence red_b08).
#'   신판: 인자·규칙 as-of 가 NA·복수 → stop · 해석된 as-of 가 미래 또는 결정 시점 뒤 → stop · 결정 시점을 못 정하면 stop.
#'   결정 시점보다 이른 as-of 는 받는다(더 보수적인 창).
.rf_sl_asof <- function(asof = NULL, rule = NULL, cfg = NULL) {
  .s <- function(x) { x <- as.character(x %||% ""); if (length(x) != 1L || is.na(x)) "" else trimws(x) }
  .bad <- function(x) !is.null(x) && (length(x) != 1L || is.na(x))
  if (.bad(asof))
    stop(sprintf("[rf_sleeve] as-of 인자가 NA/복수(%s) — '없음'으로 읽지 않는다(C1 · 결정 시점 = 셀·격자 fixed_axes.start_date)",
                 paste(format(asof), collapse = ",")))
  if (.bad((rule %||% list())$asof))
    stop(sprintf("[rf_sleeve] 규칙 asof 가 NA/복수(%s) — 슬리브 스펙 결함", paste(format(rule$asof), collapse = ",")))
  # 결정 시점(상한) — 셀 스펙 시작일(엔진이 그 칸을 도는 첫 시그널일 이전) > 격자 시작일. 값을 코드에 두지 않는다.
  sp <- Sys.getenv("RF_CELL_SPEC", "")
  cell_sd <- if (nzchar(sp) && file.exists(sp))
    tryCatch(.s((fromJSON(sp, simplifyVector = FALSE)$fixed_axes %||% list())$start_date), error = function(e) "") else ""
  prog_sd <- .s((cfg %||% list())$fixed_axes_start)
  a <- .s(asof); src <- if (nzchar(a)) "arg" else ""
  if (!nzchar(a) && nzchar(.s((rule %||% list())$asof))) { a <- .s(rule$asof); src <- "rule$asof" }
  if (!nzchar(a) && nzchar(cell_sd)) { a <- cell_sd; src <- "cell fixed_axes.start_date" }
  if (!nzchar(a) && nzchar(prog_sd)) { a <- prog_sd; src <- "program fixed_axes.start_date" }
  if (!nzchar(a)) stop("[rf_sleeve] as-of 미해석(인자·규칙·셀 스펙·격자 모두 없음) — 선정 통계를 전기간으로 계산하지 않는다(C1)")
  d <- suppressWarnings(as.Date(a))
  if (is.na(d)) stop(sprintf("[rf_sleeve] as-of 날짜 해석 불가: '%s'", a))
  bsrc <- if (nzchar(cell_sd)) "cell fixed_axes.start_date" else if (nzchar(prog_sd)) "program fixed_axes.start_date" else ""
  if (!nzchar(bsrc))
    stop("[rf_sleeve] 결정 시점(셀·격자 fixed_axes.start_date) 부재 — as-of 상한을 대조할 수 없다(fail-closed · C1)")
  bound <- suppressWarnings(as.Date(if (nzchar(cell_sd)) cell_sd else prog_sd))
  if (is.na(bound)) stop(sprintf("[rf_sleeve] 결정 시점(%s) 날짜 해석 불가", bsrc))
  if (d > Sys.Date())
    stop(sprintf("[rf_sleeve] as-of %s(%s) 가 미래(오늘 %s) — 선정 통계 창 끝은 결정 시점 %s 이하여야 한다(C1/C14)",
                 format(d), src, format(Sys.Date()), format(bound)))
  if (d > bound)
    stop(sprintf(paste0("[rf_sleeve] as-of %s(%s) > 결정 시점 %s(%s = 칸의 첫 시그널일 이전 워밍업 창 끝) — ",
                        "첫 시그널일 뒤 실현 약세장 IC 로 방어 팩터를 고르게 된다(pit.md C1 D-E · C14)"),
                 format(d), src, format(bound), bsrc))
  list(date = d, source = src, bound = bound, bound_source = bsrc)
}

#' PIT 격리 팩터 id (06_Registry/pit_quarantine.json · 판독기 validation/pit_quarantine.R — rf_factor_arms 와 같은 규약)
#'   ★목록이 있는데 판독기가 없으면 stop — 격리를 조용히 건너뛰지 않는다.
.rf_sl_pitq_ids <- function(root) {
  rel <- "02_Infrastructure/validation/pit_quarantine.R"
  lib <- unique(c(file.path(root, rel), file.path(Sys.getenv("QM_ROOT", ""), rel)))
  lib <- lib[nzchar(lib) & file.exists(lib)]
  if (!length(lib)) {
    if (file.exists(file.path(root, "06_Registry/pit_quarantine.json")))
      stop("[rf_sleeve] pit_quarantine.json 은 있는데 판독기(pit_quarantine.R)가 없다 — 격리를 건너뛰지 않는다")
    return(character(0))
  }
  en <- new.env(parent = globalenv()); sys.source(lib[1], envir = en)
  en$pitq_factor_ids(root)
}

.rf_sl_read_parquet <- function(p, cols = NULL) {
  if (!file.exists(p)) stop("[rf_sleeve] 부재: ", p)
  suppressMessages(library(arrow))
  # ★mmap = FALSE — 판독 중 같은 경로 쓰기(야간 리프레시)를 막지 않는다(arrow mmap 잠금 전례 · 09-23)
  X <- as.data.table(arrow::read_parquet(p, mmap = FALSE))
  if (!is.null(cols)) {
    miss <- setdiff(cols, names(X)); if (length(miss)) stop(sprintf("[rf_sleeve] %s 에 열 부재: %s", p, paste(miss, collapse = ",")))
    X <- X[, ..cols]
  }
  X
}

#' 벤치 월수익 (as-of 절단 후 집계 — 절단이 먼저다) — **완결된 달만** 돌려준다
#' @param BM 일간 data.table(Date, <price_col> 또는 BM_Ret) — 또는 월간 주입 data.table(hm "YYYY-MM", ret(소수), hend Date)
#' @return data.table(hm, ret, hend) — hend = 그 달 마지막 관측일(≤ d).
#'   완결 = 일간이면 달력상 월말 ≤ d ∧ 그 달 모든 일수익이 정의됨(첫 달은 전월 종가가 없어 빠진다) · 월간 주입이면 hend ≤ d.
#'   ★Ret/100 금지: 공표 지수 포인트(price_col)가 있으면 그 비율로만 수익을 만든다(단위 모호성 없음). 없어서 BM_Ret 을
#'     쓰는데 |r| ≥ 1(일간 100%) 이 있으면 퍼센트 단위로 보고 멈춘다 — 나눠서 고치지 않는다.
rf_sl_bench_months <- function(BM, d, price_col = "BM_Close") {
  d <- as.Date(d)
  B <- as.data.table(BM)
  if ("hm" %in% names(B)) {
    if (!all(c("ret", "hend") %in% names(B))) stop("[rf_sleeve] 월간 벤치 주입은 hm·ret·hend 열이 필요하다")
    M <- B[, .(hm = as.character(hm), ret = as.numeric(ret), hend = as.Date(hend))][!is.na(hend) & hend <= d & is.finite(ret)]
    if (anyDuplicated(M$hm)) stop("[rf_sleeve] 월간 벤치 주입에 같은 hm 이 둘 이상")
    return(M[])
  }
  if (!("Date" %in% names(B))) stop("[rf_sleeve] 벤치에 Date 열이 없다")
  B[, Date := as.Date(Date)]
  B <- B[!is.na(Date) & Date <= d]                                         # ★as-of 절단(집계 전)
  setorder(B, Date)
  if (price_col %in% names(B)) {
    px <- as.numeric(B[[price_col]])
    B[, .r := px / shift(px) - 1]
  } else if ("BM_Ret" %in% names(B)) {
    r <- as.numeric(B$BM_Ret)
    if (any(abs(r) >= 1, na.rm = TRUE))
      stop("[rf_sleeve] BM_Ret 에 |r| >= 1 — 퍼센트 단위 의심(Ret/100 로 고치지 않고 멈춘다)")
    B[, .r := r]
  } else stop(sprintf("[rf_sleeve] 벤치에 %s·BM_Ret 둘 다 없다", price_col))
  B[, hm := format(Date, "%Y-%m")]
  M <- B[, .(ret = if (all(is.finite(.r))) prod(1 + .r) - 1 else NA_real_, hend = max(Date)), by = hm]
  cal_end <- as.Date(paste0(M$hm, "-01")) + 32L
  cal_end <- as.Date(format(cal_end, "%Y-%m-01")) - 1L                       # 그 달 달력상 마지막 날
  M[is.finite(ret) & cal_end <= d][]
}

#' as-of 조건부 IC — 약세장 보유월의 횡단면 IC 평균 (B7 선정 통계 · P0-08)
#' @param d   as-of 날짜(이 날짜까지 알 수 있었던 것만 쓴다)
#' @param IC  data.table(Factor_Name, Date = 형성일 t, Usable_Date = 보유월 말(=IC 가용일), IC)
#'            — IC[t] = corr(factor[t], ret t→t+1) (factor_db_connector.R:669-670). Usable_Date 가 없으면 stop(C14).
#' @param BM  rf_sl_bench_months 입력(일간 KOSPI200 또는 월간 주입)
#' @param q   약세장 분위(확장창 — d 까지 실현된 보유월 전부의 q 분위) · min_n = 평균을 낼 최소 월수(미만 = NA)
#' @return data.table(Factor_Name, ic_bad, n_bad, ic_good, n_good, conditional_value) + attr(meta)
#'   정렬: 보유월 = Usable_Date 의 달. 그 달이 형성일 다음 달이 아닌 행이 있으면 stop(정렬을 추정하지 않는다).
#'   PIT: IC 는 Usable_Date ≤ d 만 · 벤치는 d 에서 절단 후 월 집계 · 분위는 두 조건을 통과한 보유월 집합에서만.
rf_sl_conditional_ic_asof <- function(d, IC, BM, q, min_n, price_col = "BM_Close") {
  d <- as.Date(d); if (length(d) != 1L || is.na(d)) stop("[rf_sleeve] as-of d 가 날짜 한 개여야 한다")
  X <- as.data.table(IC)
  need <- c("Factor_Name", "Date", "Usable_Date", "IC")
  if (!all(need %in% names(X)))
    stop(sprintf("[rf_sleeve] IC 열 부재(%s) — Usable_Date 없이는 as-of 판정 불가(C14)", paste(setdiff(need, names(X)), collapse = ",")))
  X <- X[, .(Factor_Name = as.character(Factor_Name), Date = as.Date(Date), Usable_Date = as.Date(Usable_Date),
             IC = as.numeric(IC))]
  X <- X[!is.na(Usable_Date) & Usable_Date <= d & is.finite(IC)]                          # C14
  if (!nrow(X)) stop(sprintf("[rf_sleeve] as-of %s 에 가용 IC 0행", format(d)))
  X[, hm := format(Usable_Date, "%Y-%m")]
  nx <- format(as.Date(format(X$Date, "%Y-%m-01")) + 32L, "%Y-%m")                     # 형성일 다음 달
  if (any(X$hm != nx))
    stop(sprintf("[rf_sleeve] IC 형성일→가용일이 한 달이 아닌 행 %d개 — 보유월 정렬 불가(추정하지 않는다)", sum(X$hm != nx)))
  M <- rf_sl_bench_months(BM, d, price_col)                                              # d 까지 완결된 벤치 달 전부
  if (!nrow(M)) stop(sprintf("[rf_sleeve] as-of %s — 완결된 벤치 달 0개", format(d)))
  # ★약세장 문턱 = 시장(벤치) 자신의 실현 이력 분위(확장창). 모집단은 d 까지 완결된 벤치 달 전부 — IC 쪽 행 구성
  #   (팩터별 이력 길이·결측)이 문턱을 움직이지 않게 한다(구 산출기도 기준 계열 전 월의 분위였다 · stage_gate_engine.R:962).
  thr <- as.numeric(stats::quantile(M$ret, probs = q, na.rm = TRUE, names = FALSE))
  X <- merge(X, M, by = "hm")                                                             # ★달(보유월)로 잇는다 — 날짜 일치 조인 금지
  if (!nrow(X)) stop(sprintf("[rf_sleeve] as-of %s — IC 보유월과 벤치 월이 겹치지 않는다", format(d)))
  mon <- M
  X[, bear := ret <= thr]
  out <- X[, .(ic_bad = if (sum(bear) >= min_n) mean(IC[bear]) else NA_real_, n_bad = sum(bear),
               ic_good = if (sum(!bear) >= min_n) mean(IC[!bear]) else NA_real_, n_good = sum(!bear)),
           by = Factor_Name]
  out[, conditional_value := ic_bad - ic_good]
  setattr(out, "meta", list(asof = format(d), q = q, min_n = as.integer(min_n), threshold = thr,
                            n_months = nrow(mon), n_bear_months = sum(mon$ret <= thr),
                            first_hm = min(mon$hm), last_hm = max(mon$hm), ic_max_usable = format(max(X$Usable_Date))))
  out[]
}

#' 규칙 → 방어 팩터 id. ★리터럴 금지: as-of 측정값으로 고른다.
#'   자격: 계열 ∈ selection_asof.candidate_categories ∧ lifecycle active ∧ PIT 격리 아님 ∧ as-of ic_bad(≥min_n 개월) 측정됨.
#'   정렬: rank_key(기본 ic_bad) 내림차순 · 동률은 id 순(결정론). rank 번째를 고른다.
#'   ⚠한계 명시: ic_bad 는 "약세장에서 종목을 잘 줄세운다" 이지 "상위 k종 슬리브가 덜 깨진다" 가
#'     아니다. 그 간극은 이 축의 **칸들이 직접 측정**한다(대조군 B7_40/41 이 귀속을 가른다).
#' @param asof NULL 이면 규칙 asof → 셀 스펙 → 격자 fixed_axes.start_date 순으로 해석(워밍업 창 1회 고정)
#'   ★상한 가드(R3 · 2026-09-25): 인자·규칙 as-of 가 결정 시점(셀 스펙 > 격자 fixed_axes.start_date) 뒤·미래·NA 면 stop.
#' @param IC,BM 주입(검사·시그널일별 호출용). NULL 이면 설정 경로에서 읽는다.
rf_sl_resolve <- function(rule, root = Sys.getenv("QM_ROOT", "."), asof = NULL, IC = NULL, BM = NULL) {
  if (nzchar(rule$factor_id %||% "")) return(list(id = rule$factor_id, basis = "spec 고정", asof = NA_character_))
  sel <- as.character(rule$select %||% "")
  if (sel %in% names(.RF_SL_RETIRED_SELECTS))
    stop(sprintf("[rf_sleeve] 퇴역 select '%s' — %s", sel, .RF_SL_RETIRED_SELECTS[[sel]]))
  if (!(sel %in% .RF_SL_SELECTS)) stop(sprintf("[rf_sleeve] 미지원 select '%s'", sel))
  cfg <- rf_sl_select_config(root)
  A <- .rf_sl_asof(asof, rule, cfg)
  ev_p <- file.path(root, "06_Registry/factor_evidence.json")
  if (!file.exists(ev_p)) stop("[rf_sleeve] factor_evidence.json 부재 — 후보 계열·lifecycle 을 읽을 등록부가 없다")
  EV <- fromJSON(ev_p, simplifyVector = FALSE)$factors
  # ★자격은 성과가 아니라 **분류**만 본다(계열·lifecycle). 전기간 ic_bad 는 여기서 읽지 않는다.
  cand <- data.table(
    id  = names(EV),
    cat = vapply(EV, function(e) as.character(e$category %||% ""), character(1)),
    lc  = vapply(EV, function(e) as.character(e$lifecycle_status %||% "active"), character(1)))
  pitq <- .rf_sl_pitq_ids(root)
  n_q <- sum(cand$cat %in% cfg$cats & cand$lc == "active" & cand$id %in% pitq)
  cand <- cand[cat %in% cfg$cats & lc == "active" & !(id %in% pitq)]
  if (!nrow(cand)) stop("[rf_sleeve] 자격 팩터 0종 — 등록부 계열 확인")
  IC <- IC %||% .rf_sl_read_parquet(file.path(root, cfg$ic_path), c("Factor_Name", "Date", "Usable_Date", "IC"))
  BM <- BM %||% .rf_sl_read_parquet(file.path(root, cfg$bench_path))
  IC <- as.data.table(IC)[as.character(Factor_Name) %in% cand$id]
  if (!nrow(IC)) stop("[rf_sleeve] 자격 팩터의 IC 이력 0행")
  C <- rf_sl_conditional_ic_asof(A$date, IC, BM, cfg$q, cfg$min_n, cfg$bench_price_col)
  meta <- attr(C, "meta")
  C <- C[is.finite(get(cfg$rank_key))]
  if (!nrow(C)) stop(sprintf("[rf_sleeve] as-of %s 에 약세장 IC(≥%d개월)가 측정된 자격 팩터 0종", format(A$date), cfg$min_n))
  setorderv(C, c(cfg$rank_key, "Factor_Name"), c(-1L, 1L))
  r <- max(1L, as.integer(rule$rank %||% 1L))
  if (r > nrow(C)) stop(sprintf("[rf_sleeve] rank %d > 자격 팩터 %d종", r, nrow(C)))
  basis <- sprintf(paste0("ic_bad_rank_asof %d/%d · as-of %s(%s) · 약세장 = KOSPI200 실현 보유월 확장창 하위 %.0f%% ",
                          "(%s~%s %d개월 · 문턱 %.4f · 약세 %d개월) · %s 정렬 · ic_bad %.4f(n=%d) · ic_good %.4f · 격리 제외 %d"),
                   r, nrow(C), format(A$date), A$source, 100 * cfg$q, meta$first_hm, meta$last_hm, meta$n_months,
                   meta$threshold, meta$n_bear_months, cfg$rank_key, C$ic_bad[r], C$n_bad[r], C$ic_good[r],
                   n_q)
  list(id = C$Factor_Name[r], basis = basis, asof = format(A$date), asof_source = A$source,
       asof_bound = format(A$bound), asof_bound_source = A$bound_source,
       table = C, meta = meta)
}

#' 방어 슬리브 적용 — 알파 상위 (n_max-k) 종 + 방어 k 종.
#' @param PANEL 후보 패널 (Date,Ticker,Score + defcol[, betacol])
#' @param SEL   알파 선정 결과 (Date,Ticker,...) — |SEL| = n_max/Date
#' @param defcol 방어 팩터 값 컬럼명 · betacol 베타 컬럼명(대조군용)
#' ★핵심: 방어 k종은 **알파가 안 고른 이름 중에서** 고른다. 이미 고른 이름을 다시 세면
#'   보유가 그대로라 처치가 전달되지 않는다(그 경우는 아래 가드가 멈춘다).
rf_sl_select <- function(PANEL, SEL, rule, n_max, defcol, betacol = NULL) {
  if (is.null(rule)) return(SEL)
  stopifnot(is.data.table(PANEL), is.data.table(SEL))
  n_max <- as.integer(n_max); k <- as.integer(rule$k)
  if (k >= n_max) stop(sprintf("[rf_sleeve] k %d >= n_max %d — 알파 슬리브가 사라진다", k, n_max))
  if (!(defcol %in% names(PANEL))) stop("[rf_sleeve] 방어 팩터 컬럼 부재: ", defcol)

  n_alpha <- n_max - k
  A <- SEL[order(Date, -Score)][, head(.SD, n_alpha), by = Date]        # 알파 슬리브

  P <- PANEL[is.finite(get(defcol))]
  if (!nrow(P)) stop("[rf_sleeve] 방어 팩터가 전 시점 결측 — 처치 불가")
  P <- P[!A[, .(Date, Ticker)], on = c("Date", "Ticker")]               # 알파가 안 고른 이름만

  D <- switch(rule$kind,
    "factor_topk"  = P[order(Date, -get(defcol))][, head(.SD, k), by = Date],
    # ★부호 반전 대조. 알려진 퇴화: 방어 팩터가 알파 점수와 **강하게 역상관**이면
    #   "비선정 이름 중 방어 하위 k종" = "알파 n_alpha+1..n_max 위" 가 되어 기저 선정과 같아진다.
    #   그 경우 아래 처치 전달 가드가 멈춘다 — 통과시키면 '대조군을 쟀다'는 거짓 기록이 남는다.
    "antidefense"  = P[order(Date,  get(defcol))][, head(.SD, k), by = Date],
    "random_beta_matched" = {
      if (is.null(betacol) || !(betacol %in% names(P)))
        stop("[rf_sleeve] 베타매칭 대조에는 베타 컬럼이 필요하다: ", betacol %||% "NULL")
      # ★무신호 대조 — 방어 팩터가 고를 이름들과 **같은 베타 분포**에서 무작위로 뽑는다.
      #   "방어가 한 일" 과 "베타를 낮춘 일" 을 가르는 유일한 장치다.
      ref <- P[order(Date, -get(defcol))][, head(.SD, k), by = Date][
        , .(bmin = min(get(betacol), na.rm = TRUE), bmax = max(get(betacol), na.rm = TRUE)), by = Date]
      M <- merge(P, ref, by = "Date")
      M <- M[is.finite(get(betacol)) & get(betacol) >= bmin & get(betacol) <= bmax]
      sd <- rule$seed; if (!is.finite(sd)) sd <- 20260921L
      set.seed(sd)
      M[, .SD[sample(.N, min(k, .N))], by = Date]
    },
    stop("[rf_sleeve] kind 미지원: ", rule$kind))

  cols <- intersect(names(A), names(D))
  OUT <- rbind(A[, ..cols], D[, ..cols])
  setorder(OUT, Date, -Score)

  # ── 처치 전달 가드 — 보유가 알파 단독과 같으면 이 칸은 아무것도 재지 않는다 ──
  .key <- function(X) X[, .(s = paste(sort(as.character(Ticker)), collapse = "|")), by = Date]
  same <- merge(.key(SEL), .key(OUT), by = "Date")[, mean(s.x == s.y)]
  if (is.finite(same) && same > 0.99)
    stop(sprintf("[rf_sleeve] 처치 미전달 — 보유가 알파 단독과 %.1f%% 동일(방어 k종이 이미 알파 안에 있다)",
                 100 * same))
  OUT
}

#' 두 선정의 보유 겹침(진단) — 슬리브가 실제로 몇 %를 갈아끼웠나
rf_sl_turnover_overlap <- function(before, after) {
  if (!is.data.table(before) || !is.data.table(after)) return(NA_real_)
  B <- before[, .(t = list(as.character(Ticker))), by = Date]
  A <- after[,  .(t = list(as.character(Ticker))), by = Date]
  M <- merge(B, A, by = "Date")
  if (!nrow(M)) return(NA_real_)
  mean(vapply(seq_len(nrow(M)), function(i) {
    b <- M$t.x[[i]]; a <- M$t.y[[i]]
    length(intersect(b, a)) / max(1L, length(union(b, a)))
  }, numeric(1)))
}

rf_sl_report <- function(before, after, rule, fid, basis) {
  sprintf("defense_sleeve=%s | k=%d · 팩터 %s (%s) · 보유 겹침 %.1f%% · 종목수 %d→%d",
          rule$label %||% rule$kind, rule$k, fid, basis,
          100 * (rf_sl_turnover_overlap(before, after) %||% NA_real_),
          round(mean(before[, .N, by = Date]$N)), round(mean(after[, .N, by = Date]$N)))
}

cat("[rf_sleeve.R] Loaded — rf_sl_parse / rf_sl_resolve(as-of) / rf_sl_conditional_ic_asof / rf_sl_bench_months / rf_sl_select_config / rf_sl_select / rf_sl_turnover_overlap / rf_sl_report\n")
