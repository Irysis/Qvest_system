#==============================================================================
# overlay_probe.R — 오버레이 arm 오프라인 검증 (v10.2 2026-09-03 · Phase 1)
#
# ★왜: 비중 arm 은 sync_catalog(probe=TRUE) 가 25종목 합성 픽스처로 실행 가능 여부를 미리 거른다.
#   오버레이는 그게 없어서, 나쁜 arm 하나가 백테를 다 차린 뒤 런타임 stop() 으로 죽으며
#   격자 칸 하나를 통째로 태웠다. 등재 전에 백테 예산 0 으로 거른다.
#
# 계약: 부작용 없음 — 카탈로그·원장에 쓰지 않는다. 판정만 돌려준다.
#   overlay_probe_arm(kind, root) -> list(ok, checks(data.table), reason)
#==============================================================================
suppressPackageStartupMessages(library(data.table))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.OP_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# 주석을 걷어낸 소스 — 근거를 적은 주석이 스캔에 걸리면 안 되고,
# 반대로 주석 안에 숨긴 코드가 통과해서도 안 된다.
.op_src_nc <- function(path) {
  ln <- readLines(path, warn = FALSE)
  paste(sub("#.*$", "", ln), collapse = "\n")
}

#' 결정론적 합성 픽스처 — 240개월 · 25종목 · 위기 구간 주입
#' ★위기를 넣는 이유: 낙폭 기반 arm 이 반응할 여지가 없으면 "상수 1" 이 arm 결함인지
#'   픽스처 결함인지 구분되지 않는다. 픽스처가 처치 기회를 보장해야 판정이 의미를 갖는다.
overlay_probe_fixture <- function(n_month = 240L, n_ticker = 25L, seed = 20260903L) {
  set.seed(seed)
  d <- seq(as.Date("2006-01-31"), by = "month", length.out = n_month)
  r <- stats::rnorm(n_month, 0.006, 0.05)
  r[70:78]  <- r[70:78]  - 0.11        # 위기 1
  r[150:156] <- r[150:156] - 0.08      # 위기 2
  nav <- cumprod(1 + r)
  dd  <- 1 - nav / cummax(nav)
  rv  <- as.numeric(stats::filter(abs(r), rep(1/6, 6), sides = 1)) * sqrt(12)
  rv[is.na(rv)] <- stats::sd(r) * sqrt(12)
  M <- data.table(
    Date = d, i = seq_len(n_month),
    rv20 = rv * 1.1, rv60 = rv, rv120 = rv * 0.9,
    dd = dd, r252 = c(rep(NA_real_, 12), nav[-seq_len(12)] / nav[seq_len(n_month - 12)] - 1),
    nav = nav, xs = abs(r) * 1.5 + 0.01)
  for (k in 1:10) M[, (paste0("ew", k)) := rv * (0.95 + k / 100)]
  M[, fwd := shift(nav, 1L, type = "lead") / nav - 1]
  tk <- sprintf("T%03d", seq_len(n_ticker))
  hold <- data.table(
    Ticker = tk,
    beta   = seq(0.5, 1.5, length.out = n_ticker),
    dbeta  = seq(0.3, 1.8, length.out = n_ticker),
    ovol   = seq(0.15, 0.55, length.out = n_ticker),
    bcorr  = seq(0.2, 0.9, length.out = n_ticker),
    n_obs  = 3000L)
  list(M = M, hold = hold)
}

#' 달력 리터럴 스캔 (v10.4 2026-09-17) — 주석 걷어낸 소스에서 특정 연·월·날짜·인덱스 창에 매인 논리를 찾는다
#'
#' ★규칙의 경계 (오탐을 낮추는 쪽으로 그었다 — 포맷 문자열 "%Y-%m" · "%Y-%m-01" · paste0(ym, "-01") 은 통과):
#'   ① 연-월(-일) 문자열 리터럴          "2018-01" · '2020-03-31' · "201801" · "2018/01"
#'   ② 날짜 생성자에 문자열 리터럴          as.Date("...") · as.IDate("...") · as.POSIXct("...") · ymd("...")
#'   ③ 숫자 인자 날짜 생성자               ISOdate(2008, ...) · make_date(2008, ...)
#'   ④ format(..., "%Y") 을 연도와 비교     format(d, "%Y") == "2008" · as.integer(format(d, "%Y")) >= 2008 · %in% c("2008", …)
#'   ⑤ year() 을 연도와 비교               year(ctx$date) >= 2018
#'   ⑥ 날짜 객체를 리터럴과 직접 비교        ctx$date >= 17532 · H$Date[t] > "2018-01-01" · Date == 17532
#'   ⑦ 맨 연도 문자열 비교·접두 검사          x == "2008" · startsWith(x, "2008") · grepl("^2008", x)
#'   ⑧ 월 인덱스 창                        t == 150 · t %in% 146:153 · t >= 146 & t <= 153 · t > 100 · between(t, …) · H$i[t] == 150
#'      (워밍업 가드 `t < 24L` 한 방향·두 자리는 통과 — 세 자리 이상은 8년+ 라 워밍업이 아니다. 표본 하한은 n_min 에서 온다)
#'   ⑨ 오염 변수 — year()/format(%Y)/as.Date/ctx$date/H$Date 에서 대입된 이름을 연도 리터럴과 비교하면 같은 위반
#' @return data.table(rule, snippet) — 0행이면 통과
.OP_CAL_RULES <- c(
  ym_string          = "[\"'](19|20)[0-9]{2}([-/.]?(0[1-9]|1[0-2])([-/.]?(0[1-9]|[12][0-9]|3[01]))?)[\"']",
  date_ctor_literal  = "\\b(as\\.I?Date|as\\.POSIX[cl]t|strptime|ymd|ydm|mdy|dmy|as_date)\\(\\s*[\"'][^\"'\\n]*[0-9]{4}[^\"'\\n]*[\"']",
  date_ctor_numeric  = "\\b(ISOdate|ISOdatetime|make_date|make_datetime)\\(\\s*(19|20)[0-9]{2}L?\\b",
  format_year_cmp    = "format\\((?:[^()]|\\([^()]*\\))*%Y(?:[^()]|\\([^()]*\\))*\\)\\s*\\)?\\s*(==|!=|>=|<=|>|<|%in%)\\s*c?\\(?\\s*[\"']?(19|20)[0-9]{2}L?\\b",
  format_year_cmp_rev= "[\"']?(19|20)[0-9]{2}[\"']?\\s*(==|!=|>=|<=|>|<)\\s*(as\\.(integer|numeric)\\()?\\s*format\\((?:[^()]|\\([^()]*\\))*%Y",
  year_fn_cmp        = "\\b(year|isoyear)\\((?:[^()]|\\([^()]*\\))*\\)\\s*\\)?\\s*(==|!=|>=|<=|>|<|%in%)\\s*c?\\(?\\s*[\"']?(19|20)[0-9]{2}L?\\b",
  year_fn_cmp_rev    = "[\"']?(19|20)[0-9]{2}[\"']?\\s*(==|!=|>=|<=|>|<)\\s*(as\\.(integer|numeric)\\()?\\s*(year|isoyear)\\(",
  date_obj_cmp       = "(ctx\\$date|H\\$Date|\\$Date|\\bDate|Sys\\.Date\\(\\))(\\[[^]]*\\])?\\s*\\)?\\s*(==|!=|>=|<=|>|<|%in%)\\s*c?\\(?\\s*([\"'][0-9]|[0-9]{4,})",
  date_obj_cmp_rev   = "([\"'][0-9][^\"'\\n]*[\"']|\\b[0-9]{4,}L?)\\s*(==|!=|>=|<=|>|<)\\s*(as\\.(integer|numeric)\\()?\\s*(ctx\\$date|H\\$Date|Sys\\.Date\\(\\))",
  bare_year_str_cmp  = "(==|!=|>=|<=|>|<|%in%)\\s*c?\\(?\\s*[\"'](19|20)[0-9]{2}[\"']",
  bare_year_prefix   = "\\b(startsWith|endsWith|grepl|grep|regexpr|str_detect|substr|substring)\\([^)\\n]*[\"']\\^?(19|20)[0-9]{2}L?\\b",
  t_index_eq         = "\\bt\\s*(==|!=|%in%)\\s*c?\\(?\\s*[0-9]",
  t_index_window     = "\\bt\\s*[<>]=?\\s*[0-9]+L?\\s*\\)?\\s*(&&?|\\|\\|?)\\s*\\(?\\s*\\bt\\s*[<>]=?\\s*[0-9]",
  t_index_large      = "\\bt\\s*[<>]=?\\s*[0-9]{3,}L?\\b",
  t_index_large_rev  = "\\b[0-9]{3,}L?\\s*[<>]=?\\s*t\\b",
  t_between          = "\\bbetween\\(\\s*t\\s*,\\s*[0-9]",
  H_i_cmp            = "H\\$i(\\[[^]]*\\])?\\s*(==|!=|>=|<=|>|<|%in%)\\s*c?\\(?\\s*[0-9]")

.op_cal_tainted <- function(src) {
  ln <- strsplit(src, "\n", fixed = TRUE)[[1]]
  m  <- regmatches(ln, regexec("^\\s*([A-Za-z._][A-Za-z0-9._]*)\\s*(<-|=)\\s*(.+)$", ln, perl = TRUE))
  nm <- character(0)
  for (x in m) if (length(x) == 4L &&
                   grepl("\\b(year|isoyear)\\(|%Y|as\\.I?Date\\(|as\\.POSIX|ctx\\$date|\\$Date\\b|Sys\\.Date\\(", x[4], perl = TRUE))
    nm <- c(nm, x[2])
  unique(nm)
}

overlay_probe_calendar_scan <- function(src) {
  if (!grepl("\n", src, fixed = TRUE) && file.exists(src)) src <- .op_src_nc(src)   # 경로를 주면 주석을 걷어 읽는다
  .snip <- function(rx) {
    h <- regmatches(src, regexpr(rx, src, perl = TRUE))
    h <- gsub("[[:space:]]+", " ", h); if (nchar(h) > 70L) h <- paste0(substr(h, 1, 67), "...")
    h
  }
  out <- data.table(rule = character(), snippet = character())
  for (nm in names(.OP_CAL_RULES)) {
    rx <- .OP_CAL_RULES[[nm]]
    if (grepl(rx, src, perl = TRUE)) out <- rbind(out, data.table(rule = nm, snippet = .snip(rx)))
  }
  # ⑨ 오염 변수 — 날짜에서 파생된 이름을 연도 리터럴과 비교
  for (v in .op_cal_tainted(src)) {
    ve <- gsub(".", "\\.", v, fixed = TRUE)          # R 식별자는 . 만 정규식 특수문자다
    rxs <- c(sprintf("(?<![A-Za-z0-9._$])%s\\s*(==|!=|>=|<=|>|<|%%in%%)\\s*c?\\(?\\s*[\"']?(19|20)[0-9]{2}L?\\b", ve),
             sprintf("[\"']?(19|20)[0-9]{2}[\"']?\\s*(==|!=|>=|<=|>|<)\\s*(?<![A-Za-z0-9._$])%s\\b", ve))
    for (rx in rxs) if (grepl(rx, src, perl = TRUE)) {
      out <- rbind(out, data.table(rule = sprintf("tainted_var(%s)", v), snippet = .snip(rx))); break }
  }
  out
}

overlay_probe_arm <- function(kind, root = .OP_ROOT()) {
  chk <- data.table(check = character(), status = character(), detail = character())
  add <- function(c_, s_, d_ = "") chk <<- rbind(chk, data.table(check = c_, status = s_, detail = d_))
  bad <- function(reason) list(ok = FALSE, checks = chk, reason = reason)

  # ── ① 파일·함수 계약
  p <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".R"))
  if (!file.exists(p)) { add("file", "FAIL", p); return(bad("arm 파일 부재")) }
  env <- new.env(parent = globalenv())
  e1 <- tryCatch({ source(p, local = env); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(e1)) { add("file", "FAIL", e1); return(bad(paste("source 실패:", e1))) }
  fn_name <- paste0("overlay_expo_", kind)
  if (!exists(fn_name, envir = env, inherits = FALSE)) {
    add("file", "FAIL", fn_name); return(bad(sprintf("%s() 부재 — arm 계약 위반", fn_name))) }
  FN <- get(fn_name, envir = env)
  if (!is.function(FN)) { add("file", "FAIL", "not a function"); return(bad("함수가 아니다")) }
  add("file", "PASS", basename(p))

  # ── ② 측정 누출 — 소스가 성과 필드를 참조하면 '성과를 보지 않는다' 가 거짓 주장이 된다.
  #   ★스캐너를 재구현하지 않는다 — 정본(weight_catalog.R)을 불러 쓴다. 두 구현이 갈리면
  #     갈린 순간 둘 중 하나는 실제 소스를 안 재는 것이 된다(이 저장소의 반복 결함).
  wc <- file.path(root, "02_Infrastructure/portfolio/weight_catalog.R")
  lk_fn <- NULL
  if (file.exists(wc)) {
    wenv <- new.env(parent = globalenv())
    tryCatch(suppressMessages(source(wc, local = wenv)), error = function(e) NULL)
    if (exists("wc_scan_measurement_leak", envir = wenv, inherits = FALSE))
      lk_fn <- get("wc_scan_measurement_leak", envir = wenv)
  }
  if (is.null(lk_fn)) {
    add("leak", "SKIP", "wc_scan_measurement_leak 미가용 — 이 축은 미측정(통과 아님)")
  } else {
    s <- lk_fn(p)
    if (!isTRUE(s$ok)) { add("leak", "FAIL", as.character(s$reason))
                         return(bad(paste("측정 누출:", s$reason))) }
    add("leak", "PASS", "측정 토큰 0")
  }

  # ── ③ 임의 상수 — 시장/종목 특징을 숫자 리터럴과 직접 비교하지 않을 것
  src <- .op_src_nc(p)
  # ★인덱스 허용 — 가장 흔한 형태가 H$dd[t] > 0.2 다. 대괄호를 안 넣으면 이 구멍으로 다 샌다.
  lit <- c("H\\$[A-Za-z0-9_.]+(\\[[^]]*\\])?\\s*[<>]=?\\s*-?[0-9]",
           "(ctx\\$)?hold\\$[A-Za-z0-9_.]+(\\[[^]]*\\])?\\s*[<>]=?\\s*-?[0-9]",
           "-?[0-9.]+\\s*[<>]=?\\s*H\\$[A-Za-z0-9_.]+")
  hit <- lit[vapply(lit, function(rx) grepl(rx, src, perl = TRUE), logical(1))]
  if (length(hit)) { add("literal", "FAIL", paste(hit, collapse = " | "))
                     return(bad("임의 상수 문턱 — 특징을 리터럴과 직접 비교했다")) }
  add("literal", "PASS", "리터럴 문턱 0")

  # ── ③b 달력 리터럴 (v10.4 2026-09-17 · 6번째 검사) — 특정 연·월·인덱스 창에 매인 논리
  #   ★왜 별도 검사인가: 합성 픽스처(2006-01 기점 240개월)는 실제 달력과 어긋나므로
  #     "2008년 이후만" · "t가 146~153이면" 같은 논리는 픽스처에서 **안 켜지고** ④⑤를 통과한 뒤
  #     실데이터에서만 켜진다 — probe 를 비껴가는 형태다. 특정 날짜를 아는 것 자체가 사후 지식이다.
  cal <- overlay_probe_calendar_scan(src)
  if (nrow(cal)) { add("calendar", "FAIL", paste(sprintf("%s: %s", cal$rule, cal$snippet), collapse = " | "))
                   return(bad("달력 리터럴 — 특정 연·월·인덱스 창에 매인 논리(합성 날짜에선 안 켜지고 실데이터에서만 켜진다)")) }
  add("calendar", "PASS", "달력 리터럴 0")

  fx <- overlay_probe_fixture()
  M <- fx$M; hold <- fx$hold; N <- nrow(M)
  mk_ctx <- function(t, H) list(t = t, date = M$Date[t], v_now = H$rv60[t],
                                tgt = stats::median(H$rv60, na.rm = TRUE), n_min = 24L, hold = hold)

  # ── ④ 미래 참조 — H$fwd 의 **t 행은 미실현**이다. 그 값을 흔들어 산출이 바뀌면 누출이다.
  tp <- as.integer(N * 0.8)
  H0 <- M[seq_len(tp)]
  o0 <- tryCatch(FN(H0, tp, mk_ctx(tp, H0)), error = function(e) e)
  if (inherits(o0, "error")) { add("run", "FAIL", conditionMessage(o0))
                               return(bad(paste("실행 오류:", conditionMessage(o0)))) }
  H1 <- copy(H0); H1[tp, fwd := (fwd %||% 0) + 0.5]
  o1 <- tryCatch(FN(H1, tp, mk_ctx(tp, H1)), error = function(e) e)
  .flat <- function(z) if (is.data.frame(z)) as.numeric(z$e) else as.numeric(z)
  if (inherits(o1, "error") || !isTRUE(all.equal(.flat(o0), .flat(o1)))) {
    add("future", "FAIL", "H$fwd[t] 섭동에 산출이 반응")
    return(bad("미래 참조 — 신호일 t 의 fwd(익월 수익)를 읽었다")) }
  add("future", "PASS", "fwd[t] 섭동 불변")

  # ── ⑤ 처치 전달 — 전 기간을 돌려 시간축 ∨ 횡단면 변동이 있는지
  ex <- numeric(N); xs <- numeric(N); nvec <- 0L
  for (t in seq_len(N)) {
    if (t < 12L) { ex[t] <- 1; next }
    H <- M[seq_len(t)]
    o <- tryCatch(FN(H, t, mk_ctx(t, H)), error = function(e) e)
    if (inherits(o, "error")) { add("run", "FAIL", sprintf("t=%d %s", t, conditionMessage(o)))
                                return(bad(paste("실행 오류 t=", t, ": ", conditionMessage(o), sep = ""))) }
    if (is.data.frame(o)) {
      v <- as.numeric(o$e); nvec <- nvec + 1L
      ex[t] <- mean(v, na.rm = TRUE); xs[t] <- if (length(v) > 1L) stats::sd(v, na.rm = TRUE) else 0
    } else { ex[t] <- as.numeric(o)[1]; xs[t] <- 0 }
  }
  add("run", "PASS", sprintf("%d개월 무오류 · 벡터 반환 %d개월", N, nvec))
  t_var <- stats::sd(ex, na.rm = TRUE); x_var <- max(xs, na.rm = TRUE)
  if ((!is.finite(t_var) || t_var < 1e-12) && x_var < 1e-12) {
    add("treatment", "FAIL", "시간축·횡단면 모두 상수")
    return(bad("처치 미전달 — 노출이 상수다(격자에서도 측정 무효로 죽는다)")) }
  if (mean(ex, na.rm = TRUE) >= 1 - 1e-12 && x_var < 1e-12) {
    add("treatment", "FAIL", "노출 상시 1")
    return(bad("처치 미전달 — 노출이 상시 1")) }
  add("treatment", "PASS", sprintf("시간 sd %.4f · 횡단면 sd 최대 %.4f · 평균노출 %.3f",
                                   t_var, x_var, mean(ex, na.rm = TRUE)))
  add("axis", "INFO", if (nvec > 0L) "cross_sectional" else "scalar_exposure")
  list(ok = TRUE, checks = chk, reason = NA_character_,
       axis = if (nvec > 0L) "cross_sectional" else "scalar_exposure",
       mean_exposure = mean(ex, na.rm = TRUE), t_var = t_var, x_var = x_var)
}

cat("[overlay_probe.R] Loaded — overlay_probe_arm(kind) / overlay_probe_fixture()\n")
