#==============================================================================
# overlay_probe.R — 오버레이 arm 오프라인 검증 (v10.2 2026-09-03 · Phase 1)
#
# ★왜: 비중 arm 은 sync_catalog(probe=TRUE) 가 25종목 합성 픽스처로 실행 가능 여부를 미리 거른다.
#   오버레이는 그게 없어서, 나쁜 arm 하나가 백테를 다 차린 뒤 런타임 stop() 으로 죽으며
#   격자 칸 하나를 통째로 태웠다. 등재 전에 백테 예산 0 으로 거른다.
#
# 계약: 부작용 없음 — 카탈로그·원장에 쓰지 않는다. 판정만 돌려준다.
#   overlay_probe_arm(kind, root) -> list(ok, checks(data.table), reason)
# ★P0-09(2026-09-24): ④ 미래 참조 = 설정(06_Registry/overlay_probe_future.json) 12 시점 × 섭동 4종(NA·범위 밖 하·상·중앙값).
#   ⑤ 처치 전달은 엔진과 같이 t 행 fwd 를 NA 로 넘겨 돈다. 설정이 없으면 ④ FAIL — 샌드박스 루트에도 설정을 두어라.
# ★P0-09 보강(2026-09-25): ③c 호출자 스코프·엔진 원천 접근 스캔 — 마스크는 H 에만 걸린다. arm 이 dynGet('.M')·parent.frame()
#   으로 엔진 프레임에 가면 마스크 전 .M·미래 BM_DT 에 닿고, ④ 값 섭동(H 만 흔든다)은 그 통로를 못 본다(실증 = test_rf_overlay_pit_mask.R §B7).
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

#' ③c 호출자 스코프·엔진 원천 접근 스캔 (P0-09 보강 · 2026-09-25) — 주석 걷어낸 소스에서 H·ctx 밖으로 값을 가져오는 통로를 찾는다
#'   ★왜: 엔진은 arm 을 소스 평가 프레임(run_paper_replication 의 fe_env — .M·BM_DT·RAWDATA 가 사는 곳)에서 부른다.
#'     t 행 fwd 마스크는 H 사본에만 걸리므로 dynGet(".M") · get0("BM_DT", parent.frame()) 는 마스크 전 익월 수익·미래 BM 에 닿는다.
#'     ④ 는 H 만 흔들어 이 통로를 못 보고, probe 의 호출자 프레임엔 픽스처 M 이 있어 폴백을 둔 arm 은 통과한다.
#'   ★경계(오탐을 낮추는 쪽): 자기 env 를 만드는 new.env(parent = globalenv()) · get/assign/mget(envir = 자기 env) · <<- 는 통과
#'     (외부 패널 arm pg2_risk_overlay 의 로더 형태). 걸리는 것은 **프레임 탐색 함수**와 **엔진 내부 객체 이름**뿐이다.
#'     엔진 객체 이름은 흔한 지역 변수명(DT·.B 등)을 빼고 엔진 밖에서 쓸 일이 없는 것만 둔다.
#' @return data.table(rule, snippet) — 0행이면 통과
.OP_SCOPE_RULES <- c(
  frame_walk   = "\\b(parent\\.frame|sys\\.frames?|sys\\.function|sys\\.calls?|sys\\.parents?|sys\\.status|sys\\.on\\.exit|dynGet|parent\\.env|topenv)\\s*\\(",
  global_obj   = "\\.GlobalEnv\\b",
  engine_state = "(?<![A-Za-z0-9._$])(\\.M|BM_DT|RAWDATA|\\.HOLD|\\.HOLD_AV|PORTFOLIO|FACTORS)(?![A-Za-z0-9._])")
overlay_probe_scope_scan <- function(src) {
  if (!grepl("\n", src, fixed = TRUE) && file.exists(src)) src <- .op_src_nc(src)
  out <- data.table(rule = character(), snippet = character())
  for (nm in names(.OP_SCOPE_RULES)) {
    h <- regmatches(src, regexpr(.OP_SCOPE_RULES[[nm]], src, perl = TRUE))
    if (length(h)) out <- rbind(out, data.table(rule = nm, snippet = gsub("[[:space:]]+", " ", h)))
  }
  out
}

#' ④ 미래 섭동 설정 (P0-09 · 2026-09-24) — 정본 = 06_Registry/overlay_probe_future.json (근거는 그 파일에 적는다)
#'   시점 수·구성·섭동 종류를 코드에 박지 않는다. 부재·손상·어휘 밖 값 = ok=FALSE → ④ FAIL(미측정은 통과가 아니다).
#'   찾는 순서: root(호출자 루트) → .OP_ROOT()(QM_ROOT · 정본 저장소). 샌드박스 루트(등재 관문 검사 등)는 probe·admit
#'   사본만 두고 설정을 안 둔다 — 그때 정본 저장소 설정을 **읽기만** 한다(쓰기 0). 어느 쪽을 썼는지는 ④ 상세에 남긴다.
.OP_FUTURE_KEYS <- c("fwd_low", "fwd_high", "state_dd", "state_rv60", "spread")
.OP_PERTURB     <- c("na", "below_min", "above_max", "median")
overlay_probe_future_params <- function(root = .OP_ROOT()) {
  cands <- unique(file.path(c(root, .OP_ROOT()), "06_Registry/overlay_probe_future.json"))
  p <- cands[file.exists(cands)][1]
  no <- function(r) list(ok = FALSE, reason = r, path = p)
  if (is.na(p)) return(no(sprintf("설정 부재 — %s", paste(cands, collapse = " · "))))
  j <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) return(no(sprintf("설정 JSON 파손 — %s", p)))
  if (!identical(as.character(j$schema %||% ""), "overlay_probe_future_v1")) return(no("schema != overlay_probe_future_v1"))
  tf <- suppressWarnings(as.integer(j$t_floor %||% NA))
  if (length(tf) != 1L || is.na(tf) || tf < 1L) return(no("t_floor 는 1 이상 정수"))
  pt <- j$points
  if (!is.list(pt) || !setequal(names(pt), .OP_FUTURE_KEYS)) return(no(sprintf("points 키 = {%s} 여야 한다", paste(.OP_FUTURE_KEYS, collapse = ","))))
  k <- vapply(.OP_FUTURE_KEYS, function(z) { v <- suppressWarnings(as.integer(pt[[z]])); if (length(v) == 1L && !is.na(v)) v else -1L }, integer(1))
  if (any(k < 0L) || sum(k) < 1L) return(no("points 값은 0 이상 정수 · 합 1 이상"))
  pb <- as.character(unlist(j$perturb %||% list()))
  if (!length(pb) || !all(pb %in% .OP_PERTURB) || anyDuplicated(pb)) return(no(sprintf("perturb ⊆ {%s} · 중복 없음", paste(.OP_PERTURB, collapse = ","))))
  if (!"na" %in% pb) return(no("perturb 에 na 필수 — 엔진 실행 조건(t 행 fwd = NA)을 재지 않는 설정은 거부"))
  list(ok = TRUE, t_floor = tf, points = k, perturb = pb, path = p, fallback = !identical(p, cands[1]))
}

#' ④ 섭동 시점 — 결정론(난수 없음 · 동률은 t 오름차순). 반환 data.table(t, why)
#'   fwd_low/fwd_high = fwd 하·상 꼬리(익월 폭락·급등 직전 달 — '극단일 때만 읽는' arm 이 켜지는 곳)
#'   state_dd/state_rv60 = 상태 극단(낙폭·변동성 상위 — 위기 국면에서만 켜지는 arm) · spread = 나머지 구간 균등.
overlay_probe_future_points <- function(M, fp) {
  N <- nrow(M)
  el <- if (N >= fp$t_floor) seq.int(fp$t_floor, N) else integer(0)
  ch <- integer(0); wy <- character(0)
  take <- function(ord, k, tag) {
    for (x in ord) { if (k <= 0L) break
      if (!(x %in% ch)) { ch <<- c(ch, x); wy <<- c(wy, tag); k <- k - 1L } }
  }
  rk <- function(v, dec) { ok <- is.finite(v); e <- el[ok]; v <- v[ok]; e[order(if (dec) -v else v, e)] }
  take(rk(M$fwd[el], FALSE), fp$points[["fwd_low"]],   "fwd_low")
  take(rk(M$fwd[el], TRUE),  fp$points[["fwd_high"]],  "fwd_high")
  take(rk(M$dd[el],  TRUE),  fp$points[["state_dd"]],  "state_dd")
  take(rk(M$rv60[el], TRUE), fp$points[["state_rv60"]], "state_rv60")
  rest <- setdiff(el, ch); ks <- fp$points[["spread"]]
  if (ks > 0L && length(rest)) take(rest[unique(round(seq(1, length(rest), length.out = min(ks, length(rest)))))], ks, "spread")
  o <- order(ch)
  data.table(t = ch[o], why = wy[o])
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

  # ── ③c 호출자 스코프·엔진 원천 접근 (P0-09 보강 · 2026-09-25) — 마스크(H 사본)를 돌아가는 통로. ④ 값 섭동으로는 안 보인다
  scope <- overlay_probe_scope_scan(src)
  if (nrow(scope)) { add("scope", "FAIL", paste(sprintf("%s: %s", scope$rule, scope$snippet), collapse = " | "))
                     return(bad(sprintf("호출자 스코프·엔진 원천 접근 — H·ctx 밖에서 값을 가져온다(마스크 전 .M·미래 BM 에 닿는 통로): %s",
                                        paste(unique(scope$rule), collapse = ",")))) }
  add("scope", "PASS", "프레임 탐색·엔진 원천 이름 0")

  fx <- overlay_probe_fixture()
  M <- fx$M; hold <- fx$hold; N <- nrow(M)
  mk_ctx <- function(t, H) list(t = t, date = M$Date[t], v_now = H$rv60[t],
                                tgt = stats::median(H$rv60, na.rm = TRUE), n_min = 24L, hold = hold)

  # ── ④ 미래 참조 — H$fwd 의 **t 행은 미실현**이다. 그 값을 흔들어 산출이 바뀌면 누출이다.
  #   ★P0-09 확장(2026-09-24 · 감사 D4-07): 구판은 한 시점(0.8N) · 한 방향(+0.5) 섭동이었다. fwd[t] 를 **극단일 때만**
  #     읽는 arm('익월 폭락이면 현금')은 그 한 점에서 분기가 안 켜져 통과했다(실증 = test_rf_overlay_pit_mask.R §B).
  #     현행: 설정(06_Registry/overlay_probe_future.json)이 정한 12 시점 — fwd 꼬리(하·상) · 상태 극단(dd·rv60 상위) ·
  #     균등 채움 — 마다 fwd[t] 를 NA · 표본 최솟값 아래 · 최댓값 위 · 중앙값으로 바꿔 산출 불변을 요구한다.
  #     섭동값은 전부 픽스처 fwd 분포에서 나온다(리터럴 없음). NA 섭동 = 엔진 실행 조건 그대로(엔진은 t 행 fwd 를 NA 로 넘긴다).
  #   설정 부재·손상 = 이 축 FAIL(미측정은 통과가 아니다).
  fp <- overlay_probe_future_params(root)
  if (!isTRUE(fp$ok)) { add("future", "FAIL", fp$reason)
                        return(bad(paste("미래 섭동 설정 불가:", fp$reason))) }
  tps <- overlay_probe_future_points(M, fp)
  .fw  <- M$fwd[is.finite(M$fwd)]
  .rng <- max(.fw) - min(.fw)
  pert <- c(na = NA_real_, below_min = min(.fw) - .rng, above_max = max(.fw) + .rng, median = stats::median(.fw))
  pert <- pert[fp$perturb]
  .same <- function(a, b) {
    if (is.data.frame(a) || is.data.frame(b)) {
      if (!(is.data.frame(a) && is.data.frame(b))) return(FALSE)
      return(isTRUE(all.equal(as.character(a$Ticker), as.character(b$Ticker))) &&
             isTRUE(all.equal(as.numeric(a$e), as.numeric(b$e))))
    }
    isTRUE(all.equal(as.numeric(a), as.numeric(b)))
  }
  for (tp in tps$t) {
    H0 <- M[seq_len(tp)]
    o0 <- tryCatch(FN(H0, tp, mk_ctx(tp, H0)), error = function(e) e)
    if (inherits(o0, "error")) { add("run", "FAIL", sprintf("t=%d %s", tp, conditionMessage(o0)))
                                 return(bad(paste("실행 오류:", conditionMessage(o0)))) }
    for (pn in names(pert)) {
      H1 <- copy(H0); H1[tp, fwd := pert[[pn]]]
      o1 <- tryCatch(FN(H1, tp, mk_ctx(tp, H1)), error = function(e) e)
      if (inherits(o1, "error") || !.same(o0, o1)) {
        why <- tps$why[match(tp, tps$t)]
        add("future", "FAIL", sprintf("t=%d(%s) fwd[t]→%s 에 산출이 %s", tp, why, pn,
                                      if (inherits(o1, "error")) paste("오류:", conditionMessage(o1)) else "반응"))
        return(bad(sprintf("미래 참조 — 신호일 t 의 fwd(익월 수익)를 읽었다 [t=%d · %s · 섭동 %s]", tp, why, pn))) }
    }
  }
  add("future", "PASS", sprintf("fwd[t] 섭동 불변 — %d시점(%s) × %d섭동(%s) · 설정 %s", nrow(tps),
                                paste(unique(tps$why), collapse = "·"), length(pert), paste(names(pert), collapse = "·"),
                                if (isTRUE(fp$fallback)) paste("QM_ROOT 폴백", fp$path) else "root"))

  # ── ⑤ 처치 전달 — 전 기간을 돌려 시간축 ∨ 횡단면 변동이 있는지
  #   ★P0-09: 엔진과 같은 조건으로 돈다 — t 행 fwd 를 NA 로 넘긴다(엔진 루프 머리의 마스크). fwd[t] 로만 켜지는 처치는 처치가 아니다.
  ex <- numeric(N); xs <- numeric(N); nvec <- 0L
  for (t in seq_len(N)) {
    if (t < 12L) { ex[t] <- 1; next }
    H <- M[seq_len(t)]; H[t, fwd := NA_real_]
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
