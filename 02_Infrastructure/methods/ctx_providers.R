#==============================================================================
# ctx_providers.R — 어댑터 ctx **입력 확장 레지스트리** (2026-08-13 신설)
#   도훈 지시: "신규 논문이 들어오면 다양한 방법론을 실제 구현하기 위한 인프라가 매번 새롭게
#   필요할 거야. 그런 인프라가 필요하다고 판단되면 그냥 바로 구현할 수 있게 배선해."
#
#------------------------------------------------------------------------------
# 왜 레지스트리인가 — 오늘 같은 일이 반복될 것이기 때문이다
#------------------------------------------------------------------------------
# 2026-08-13 실측: CD-DFM(특성 기반)이 "구현 불가"로 기각됐는데, 사유는 데이터 부재가 아니라
# **ctx 에 특성이 안 실려 있음** 하나였다. 특성 패널은 이미 저장소에 있었다.
# 그때 나는 배터리(auto_sigma_weighting_ab.R:122)를 직접 패치해 thunk 하나를 박았다 —
# 그건 그 논문 하나를 여는 방식이지 **다음 논문을 여는 방식이 아니다.** 다음엔 거래량이,
# 그다음엔 일중·매크로·텍스트가 필요할 것이고, 매번 측정 경로(배터리)를 손대게 된다.
# 측정 경로를 자주 건드리는 것 자체가 회귀 위험이다.
#
# ⇒ 입력 추가를 **선언**으로 바꾼다. provider 를 등록하면 ctx 에 자동으로 실린다.
#   배터리는 두 번 다시 고치지 않는다.
#
#------------------------------------------------------------------------------
# 계약 (provider 를 추가하는 사람이 지킬 것)
#------------------------------------------------------------------------------
#   register_ctx_provider(
#     name        = "volume",                       # ctx$volume() 으로 노출됨
#     fn          = function(decision_date, assets) ...,   # 값 또는 NULL
#     pit_note    = "직전 월말까지만 …",            # ★필수 — 없으면 등록 거부
#     source_note = "load_month_factors 경유 (C15)")
#
# ★강제 3종 (등록 시점 거부):
#   ① `pit_note` 필수 — PIT 근거를 신고하지 않는 입력은 받지 않는다. 부재를 "아마 괜찮음"으로
#      내려앉히는 것이 이 저장소의 반복 결함이고, 오버레이 C5 사고가 정확히 그 형태였다.
#   ② fn 은 **(decision_date, assets) 2인자** — 그래야 PIT 컷오프를 provider 가 스스로 계산한다.
#      ★`decision_date` 는 **스칼라일 수도, 벡터일 수도** 있다. weight/sigma 레인은 월별 루프
#        안에서 부르므로 스칼라이고, exposure 레인은 periods 전체를 한 번에 넘기므로 벡터다
#        (스칼라만 가정하면 exposure 어댑터가 계열을 못 만든다). provider 는 길이에 맞춰
#        스냅샷 또는 계열을 반환한다.
#   ③ 반환은 값 또는 **NULL**. 실패를 예외로 던져 배터리를 죽이지 않는다(fail-soft).
#
# ★소비 측 규약: ctx$<name> 은 **함수(thunk)** 다. 지연 평가라
#   ①쓰지 않는 arm 은 I/O 비용 0 ②기존 arm 은 필드를 읽지 않으므로 결과가 바뀔 수 없다.
#   어댑터는 반드시 `NULL` 반환을 처리해야 한다(패널이 빈 달이 실재한다).
#==============================================================================

.CTX_PROVIDERS <- new.env(parent = emptyenv())

register_ctx_provider <- function(name, fn, pit_note, source_note = NA_character_,
                                  fixture_fn = NULL, overwrite = FALSE) {
  if (!is.character(name) || !nzchar(name)) stop("[ctx_provider] name 필수")
  if (!is.function(fn) || length(formals(fn)) < 2L)
    stop("[ctx_provider] fn 은 function(decision_date, assets) 여야 한다 — ",
         "provider 가 자기 PIT 컷오프를 스스로 계산해야 하기 때문이다.")
  if (missing(pit_note) || !nzchar(paste(pit_note, collapse = "")))
    stop("[ctx_provider] `", name, "`: pit_note 필수 — PIT 근거 미신고 입력은 받지 않는다. ",
         "(부재를 '아마 괜찮음'으로 내려앉히는 것이 반복 결함이고, C5 오버레이 사고가 그 형태였다.)")
  if (exists(name, envir = .CTX_PROVIDERS, inherits = FALSE) && !overwrite)
    stop("[ctx_provider] `", name, "` 이미 등록됨 — 교체하려면 overwrite=TRUE")
  if (!is.null(fixture_fn) && !is.function(fixture_fn))
    stop("[ctx_provider] `", name, "`: fixture_fn 은 function(decision_date, assets) 여야 한다")
  assign(name, list(fn = fn, pit_note = pit_note, source_note = source_note,
                    fixture_fn = fixture_fn),
         envir = .CTX_PROVIDERS)
  invisible(TRUE)
}

list_ctx_providers <- function() {
  ns <- sort(ls(.CTX_PROVIDERS))
  if (!length(ns)) return(data.frame(name = character(0), pit_note = character(0)))
  data.frame(name = ns,
             pit_note    = vapply(ns, function(n) get(n, envir = .CTX_PROVIDERS)$pit_note, character(1)),
             source_note = vapply(ns, function(n) as.character(get(n, envir = .CTX_PROVIDERS)$source_note %||% NA), character(1)),
             row.names = NULL, stringsAsFactors = FALSE)
}

#' 등록된 provider 를 **지연 thunk** 로 감싼 named list 반환. 배터리가 ctx 에 splice 한다.
#' @param fixture TRUE 면 provider 가 선언한 `fixture_fn` 을 쓴다.
#'   ★등재 게이트는 **데이터 vintage 에 묶이면 안 된다** — 실패측정: fixture 가 실 factor DB
#'   (821,373행)를 물어오자 합성 자산(A00001…)과 티커가 안 맞아 정상 probe 가 EW 로 붕괴,
#'   "배선 실효" 축이 거짓 FAIL 을 냈다. 같은 어댑터가 날마다 다른 판정을 받게 된다.
#'   ⇒ 새 입력을 추가하는 사람은 **fixture_fn 도 같이 선언**한다(선언 하나에 둘 다).
build_ctx_extras <- function(decision_date, assets, fixture = FALSE) {
  ns <- ls(.CTX_PROVIDERS)
  out <- list()
  for (n in ns) {
    p <- get(n, envir = .CTX_PROVIDERS)
    if (isTRUE(fixture)) {
      if (is.null(p$fixture_fn)) next          # fixture 미선언 provider 는 게이트에서 제외
      p <- list(fn = p$fixture_fn)
    }
    out[[n]] <- local({
      .p <- p; .d <- decision_date; .a <- assets; .cache <- NULL; .done <- FALSE
      function() {
        if (.done) return(.cache)
        .done <<- TRUE
        .cache <<- tryCatch(.p$fn(.d, .a), error = function(e) {
          cat(sprintf("[ctx_provider:%s] 실패(%s) — NULL 반환. 어댑터가 NULL 을 처리해야 한다\n",
                      n, conditionMessage(e))); NULL })
        .cache
      }
    })
  }
  out
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# ══ 기본 provider ═════════════════════════════════════════════════════════════
# characteristics — 펀더멘털/특성 패널 (CD-DFM 계열이 요구하는 입력)
register_ctx_provider(
  name = "characteristics",
  pit_note = paste("sig_date = **직전 월말**(홀딩월 시작 전). 수익률의 `Date < start_d` 와 같은 규약이며",
                   "C5 오버레이 타이밍과 동형. 당월 패널을 쓰면 동월 look-ahead 가 된다."),
  source_note = "load_month_factors() 경유 — factor DB parquet 직독 금지(C15).",
  # 게이트용 합성 패널 — 실데이터를 쓰면 판정이 vintage 에 묶인다(위 build_ctx_extras 주석).
  fixture_fn = function(decision_date, assets) list(
    sig_date = as.Date(format(as.Date(decision_date[1]), "%Y-%m-01")) - 1L,
    panel = data.frame(Ticker = assets,
                       char_value = seq(-1, 1, length.out = length(assets)),
                       char_size  = seq(1, 2, length.out = length(assets)),
                       stringsAsFactors = FALSE)),
  fn = function(decision_date, assets) {
    # 특성 패널은 월별 스냅샷이 정본이다 — 벡터가 오면 **가장 이른** 홀딩월 기준으로 잡는다
    # (exposure 레인이 전 구간을 넘기는 경우. 계열이 필요하면 별도 provider 를 등록할 것).
    sig <- as.Date(format(min(as.Date(decision_date)), "%Y-%m-01")) - 1L
    if (!exists("load_month_factors"))
      suppressWarnings(source(file.path(Sys.getenv("QM_ROOT", getwd()),
                                        "02_Infrastructure/factor_db/factor_db_connector.R")))
    panel <- load_month_factors(sig)
    if (is.null(panel)) return(NULL)
    list(sig_date = sig, panel = panel)
  })

# ── macro — VIX·크레딧·금리·금융스트레스 일별 계열 (cash-overlay 계열 논문이 요구하는 입력)
#   2026-08-13 신설. 도훈 standing policy 로 "필요하면 바로 배선" 의 첫 적용 사례다.
MACRO_PUB_LAG_DAYS <- 5L   # 보수적 균일 발표시차. 아래 pit_note 참조 — 사전고정, sweep 아님
register_ctx_provider(
  name = "macro",
  pit_note = paste(
    "컷오프 = **홀딩월 시작 −", MACRO_PUB_LAG_DAYS, "일**. 두 겹으로 막는다.",
    "①월별 스탬프(`macro_regime.parquet`)를 쓰지 않는다 — 그 파일의 마지막 YM 은",
    "**진행 중인 달**이라(실측 2026-08-13 기준 YM=2026-08) 월중 조회가 곧 동월 look-ahead 다.",
    "대신 일별 `fred_macro_wide.parquet` 을 날짜로 자른다.",
    "②C11 발표시차 — FRED 의 Date 는 **관측 기준일**이지 공표일이 아니다. 계열별 시차가 다르고",
    "가장 느린 계열은 ~73일이므로, 균일 5일은 **빠른 계열(VIX·금리·크레딧 = 일별 시장가)에만",
    "충분**하다. 느린 거시계열(CPI·고용·산업생산 등)을 쓰려면 어댑터가 자기 시차를 추가로",
    "적용해야 한다 — 이 provider 는 그것을 대신해주지 않는다."),
  source_note = ".cache/fred_macro_wide.parquet (일별 24계열). 월별 스탬프 사용 금지.",
  fixture_fn = function(decision_date, assets) {
    # ★fixture 도 **production 과 같은 컷오프 규칙**을 따라야 한다. 초판은 계열을 max(d) 까지
    #   생성해 마지막 날짜가 홀딩월 시작과 같아졌고(=침범), 계약검사 T3h 가 그것을 잡았다.
    #   게이트용 합성값이 규칙을 어기면 그 게이트는 자기가 강제하는 규칙을 스스로 위반한다.
    d <- sort(unique(as.Date(decision_date)))
    cut <- as.Date(format(min(d), "%Y-%m-01")) - MACRO_PUB_LAG_DAYS
    n <- max(400L, 30L * length(d))
    g <- seq(cut - n, cut, by = "day")
    set.seed(20260813)
    list(cutoff = cut,
         series = data.frame(Date = g,
                             VIX        = 15 + 10 * abs(sin(seq_along(g) / 90)),
                             HY_Spread  = 3  +  2 * abs(cos(seq_along(g) / 120)),
                             Fed_Funds_Rate = 2 + sin(seq_along(g) / 300),
                             StL_Fin_Stress = sin(seq_along(g) / 150)))
  },
  fn = function(decision_date, assets) {
    fp <- file.path(Sys.getenv("QM_ROOT", getwd()), ".cache/fred_macro_wide.parquet")
    if (!file.exists(fp)) return(NULL)
    suppressWarnings(suppressMessages(library(arrow)))
    df <- as.data.frame(arrow::read_parquet(fp))
    if (!("Date" %in% names(df))) return(NULL)
    df$Date <- as.Date(df$Date)
    # ★컷오프 = 가장 이른 홀딩월 시작 − 발표시차. **홀딩월 안의 관측은 한 줄도 쓰지 않는다.**
    cut <- as.Date(format(min(as.Date(decision_date)), "%Y-%m-01")) - MACRO_PUB_LAG_DAYS
    out <- df[df$Date <= cut, , drop = FALSE]
    if (!nrow(out)) return(NULL)
    list(cutoff = cut, series = out)
  })
