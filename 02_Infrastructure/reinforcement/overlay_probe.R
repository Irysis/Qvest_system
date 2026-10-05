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
# ★R3R(2026-09-25 · P0-09 정적 probe 경화): ③c 정규식 열거는 eval.parent·rlang::caller_env·do.call("sys.frame")·별칭·백틱·계산된 FUN·
#   get/assign(envir =)·문자열 안 '#' 을 놓쳤다. ③d 허용 목록을 더했다 — 정본 arm 이 쓰는 이름 전수(getParseData·AST 추출)가 허용 집합이고
#   밖은 전부 거부(06_Registry/overlay_probe_allowlist.json · 동결 · 능력 계열은 sha 고정 개별 허가로만). 주석 걷기는 파서(COMMENT 토큰)로.
#   ③c 는 알려진 통로 열거(보조)로 남는다. 1차 방어는 여전히 엔진 런타임 마스크. 검사 = test_overlay_probe_allowlist.R
#==============================================================================
suppressPackageStartupMessages(library(data.table))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.OP_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# 주석을 걷어낸 소스 — 근거를 적은 주석이 스캔에 걸리면 안 되고,
# 반대로 주석 안에 숨긴 코드가 통과해서도 안 된다.
# ★R3R(2026-09-25 · P0-09 정적 probe 경화): 주석 = 파서가 COMMENT 토큰으로 판정한 것만 걷는다. 구판 sub("#.*$", "", ln) 은
#   문자열 안 '#' 뒤 같은 줄 전부를 지웠다 — `tag <- "#"; M <- dynGet(".M")` 이 ③·③b·③c 전부에서 사라졌다(실증 = test_overlay_probe_allowlist.R §C).
#   주석은 줄 끝까지 가므로 줄이 그 토큰 텍스트로 끝나는지 대조해 잘라낸다. 파싱 불가·좌표 불일치 = 구판 걷기 + parse_failed 표식
#   (③d 허용 목록이 같은 소스를 파서로 다시 읽어 unparseable 로 거부한다 — 걷기 실패가 통과로 새지 않는다).
.op_strip_comments <- function(ln) {
  ln <- sub("\r$", "", ln)
  bad <- function() structure(sub("#.*$", "", ln), parse_failed = TRUE)
  ex <- tryCatch(parse(text = ln, keep.source = TRUE), error = function(e) NULL)
  if (is.null(ex)) return(bad())
  pd <- utils::getParseData(ex, includeText = TRUE)
  if (is.null(pd)) return(if (length(ex)) bad() else ln)
  cm <- pd[pd$token == "COMMENT", c("line1", "text"), drop = FALSE]
  for (i in seq_len(nrow(cm))) {
    k <- cm$line1[i]; x <- ln[k]; tx <- cm$text[i]
    if (!endsWith(x, tx)) { x <- sub("[[:space:]]+$", "", x); tx <- sub("[[:space:]]+$", "", tx) }
    if (!endsWith(x, tx)) return(bad())
    ln[k] <- substr(x, 1L, nchar(x) - nchar(tx))
  }
  ln
}
.op_src_nc <- function(path) {
  ln <- readLines(path, warn = FALSE, encoding = "UTF-8")
  s <- .op_strip_comments(ln)
  out <- paste(s, collapse = "\n")
  if (isTRUE(attr(s, "parse_failed"))) attr(out, "parse_failed") <- TRUE
  out
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

#==============================================================================
# ③d 허용 목록(allowlist) — R3R 2026-09-25 · P0-09 정적 probe 경화
#
# ★왜 목록 방식을 뒤집었나: ③c 는 '막을 통로'를 열거했다(frame_walk 정규식). eval.parent · rlang::caller_env ·
#   do.call("sys.frame") · 별칭 f <- sys.frames · 계산된 FUN · get(…, envir =) — 통로는 열거보다 빨리 는다(R3 검증이 넷을 더 찾았다).
#   ③d 는 거꾸로 '쓸 수 있는 것'만 적는다: 정본 arm 이 실제로 쓰는 이름 전수(파서로 추출)가 허용 집합이고, 그 밖은 전부 거부다.
#   새 우회 형태는 목록에 없으므로 기본값이 거부다(fail-closed). 1차 방어는 여전히 엔진 런타임 마스크(rf_cell_engine.R H[t, fwd:=NA])다.
# ★허용 집합 = 06_Registry/overlay_probe_allowlist.json(동결). 후보 arm 파일이 overlay_arms/ 에 들어온 뒤 probe 가 도므로
#   디렉터리를 매번 다시 읽어 만들면 후보 자신이 허용 집합에 섞인다 — 그래서 빌드는 별도 행위(overlay_probe_allowlist_build)이고
#   probe 는 읽기만 한다. 부재·손상·스키마 불일치 = FAIL(미측정은 통과가 아니다).
# 판정 규칙(한 구현 — 빌더와 스캐너가 같은 추출기 .op_allow_extract 를 쓴다):
#   R0 파싱 불가 = 거부
#   R1 호출 머리(파서 토큰 SYMBOL_FUNCTION_CALL·SPECIAL·<<-·:=·치환함수 f<-) ∈ calls — 또는 이 파일이 묶은 이름이면서 참조 이름공간에 없는 것(지역 도우미)
#      ★파서 토큰 집합과 AST 머리 집합이 다르면 추출 불일치로 거부(두 추출기가 갈리면 하나는 소스를 안 재는 것이다)
#   R2 값 자리 기호: 참조 이름공간(레지스트리 ref_namespaces)에 있는 이름 ∈ values — 이 파일이 지역 변수로 묶은 이름이면
#      shadow 목록이거나 능력 계열·고차 함수가 아닐 것 · 참조 이름공간에 없는 이름은 이 파일이 묶었거나 픽스처 열 이름
#      (전역·엔진 객체 이름은 어느 쪽도 아니라 거부 — 어휘 스코프로 globalenv 에 닿는 통로)
#   R3 pkg::name — pkg ∈ pkgs · name 은 자리대로 R1/R2(지역 묶기로 면제 없음) · pkg:::name · 기호 아닌 피연산자 = 거부
#   R4 문자열이 능력 계열·고차 함수 이름이면 ∈ strings(이중 방어 — 변환 통로 자체는 R5 가 막는다)
#   R5 함수 자리 인자(참조 정의의 formals FUN·f·what… 를 match.call 로 찾는다 · do.call 은 what):
#      기호 ∈ fnargs 이면서 그 자신이 고차 함수가 아닐 것 · 함수 리터럴 · 이 파일이 함수 리터럴로만 묶은 이름 · pkg::name(fnargs) ·
#      문자열 ∈ fnstrs(do.call 은 문자열 전면 거부 — 도훈 결정 R3R) · 그 밖(계산된 값·지역 문자열 변수·형식 인자) = 거부 ·
#      `...` 가 섞였는데 함수 자리를 이름으로 안 줬으면 거부
#   R6 계산된 호출 머리 f(...)(...) 는 f ∈ headcalls 일 때만(정본: stats::ecdf(x)(v)) · x[[i]](…) 류 = 거부
#   R7 능력 계열(.OP_CAPABILITY) 이름은 공통 목록에 들어갈 수 없다 — 레지스트리 공통 목록에 있으면 레지스트리 무효(fail-closed).
#      그 이름이 필요한 정본 arm(외부 패널 로더 pg2_risk_overlay)은 파일 sha256 에 묶인 개별 허가(grants)로만 통과한다 —
#      한 바이트라도 바뀌면 허가가 풀리고 공통 목록으로만 잰다.
#==============================================================================
.OP_ALLOW_SCHEMA <- "overlay_probe_allowlist_v1"
# 능력 계열 — 프레임·호출 스택 · 환경 · 동적 코드 · 이름공간/패키지 · 입출력/시스템 · 훅.
#   ★탐지 기제가 아니다(탐지는 허용 목록 — 목록 밖은 전부 거부). 쓰임은 R7 두 곳뿐: 빌더의 공통/개별 분류 · 레지스트리 무결성.
#   빠진 이름이 있어도 그 이름은 정본 공통 arm 이 쓰지 않는 한 허용 집합에 없으므로 거부된다.
.OP_CAPABILITY <- c(
  "sys.call", "sys.calls", "sys.frame", "sys.frames", "sys.function", "sys.nframe", "sys.on.exit", "sys.parent",
  "sys.parents", "sys.status", "parent.frame", "dynGet", "eval.parent",
  "environment", "environment<-", "parent.env", "parent.env<-", "topenv", "globalenv", "emptyenv", "baseenv",
  "as.environment", "pos.to.env", "new.env", "list2env", "as.list.environment", "local", "attach", "detach", "get",
  "get0", "mget", "exists", "assign", "rm", "remove", "delayedAssign", "makeActiveBinding", "lockBinding",
  "unlockBinding", "lockEnvironment", "eapply", "ls", "objects", "is.environment", ".GlobalEnv", ".BaseNamespaceEnv",
  "eval", "evalq", "parse", "str2lang", "str2expression", "body", "body<-", "formals", "formals<-", "as.function",
  "as.call", "call", "match.fun", "forceAndCall", "quote", "bquote", "substitute", "alist", "as.name", "as.symbol",
  "getFunction", ".Internal", ".Primitive", ".Call", ".External", ".External2", ".C", ".Fortran", "trace", "untrace",
  "browser", "debug", "debugonce", "Recall",
  "library", "require", "requireNamespace", "loadNamespace", "attachNamespace", "asNamespace", "getNamespace",
  "getExportedValue", "getFromNamespace", "assignInNamespace", "assignInMyNamespace", "fixInNamespace", "getAnywhere",
  "sys.source", "source", "readRDS", "saveRDS", "load", "save", "file", "url", "gzfile", "readLines", "writeLines",
  "scan", "read.csv", "read.table", "write.csv", "write.table", "fread", "fwrite", "read_parquet", "write_parquet",
  "open_dataset", "read_json", "fromJSON", "toJSON", "write_json", "file.exists", "file.info", "file.rename",
  "file.remove", "file.copy", "unlink", "dir.create", "list.files", "dir.exists", "download.file", "system", "system2",
  "shell", "Sys.setenv", "Sys.getenv", "Sys.getpid", "Sys.setlocale", "setwd", "capture.output", "sink", "cat",
  "options", "setHook", "addTaskCallback", "reg.finalizer",
  "caller_env", "current_env", "env", "env_parent", "env_get", "env_get_list", "eval_bare", "eval_tidy", "inject",
  "exec", "sym", "syms", "parse_expr", "parse_exprs", "new_function", "as_function", "caller_fn", "caller_call",
  "frame_call", "frame_fn", "trace_back", "load_month_factors",
  # 참조 변경 — 엔진 소유 객체(H·ctx$hold)를 제자리에서 바꾸거나 둘러싼 환경(전역)에 쓴다
  "<<-", ":=", "set", "setattr", "setnames", "setorder", "setorderv", "setkey", "setkeyv", "setindex", "setindexv",
  "setDT", "setDF", "setcolorder", "setattr", "alloc.col", "truelength")
# R 문법 자체(파서가 만드는 머리) — 연산자·제어 구조. 백틱으로 불러도 문법과 같은 일만 한다. <<- 와 := 는 여기 없다(허용 목록 대상).
.OP_SYNTAX <- c("{", "(", "if", "for", "while", "repeat", "break", "next", "function", "return", "<-", "=", "[", "[[",
                "$", "@", "+", "-", "*", "/", "^", "%%", "%/%", "<", ">", "<=", ">=", "==", "!=", "!", "&", "&&",
                "|", "||", ":", "~", "?", "[<-", "[[<-", "$<-", "@<-")
# 함수 자리 formals — match.fun 을 거쳐 문자열·기호를 함수로 바꾸는 인자 이름(apply 계열·Reduce·Map·outer·sweep·ave·do.call).
.OP_FN_FORMALS <- c("FUN", "f", "what", "fn", "FN", "fun", ".f", ".fn")
# 함수 자리 문자열로 허용하는 문법 연산자 — 문법으로 이미 부를 수 있는 산술·비교·논리·추출·치환 연산자뿐(제어 구조·대입·function·? 제외).
#   능력을 더하지 않는다(match.fun("+") = 문법 +). do.call 의 문자열은 이것과 무관하게 전면 거부.
.OP_FN_SYNTAX_STR <- setdiff(.OP_SYNTAX, c("{", "(", "if", "for", "while", "repeat", "break", "next", "function", "return", "<-", "=", "?"))

.OP_REF_CACHE <- new.env(parent = emptyenv())
#' 참조 이름공간 색인 — 이름 전부(all) · 함수 이름(fun) · 고차 함수 정의(hof: 이름 → formals 에 FN 자리가 있는 closure)
.op_ref_index <- function(nss) {
  key <- paste(nss, collapse = "|")
  if (!is.null(.OP_REF_CACHE[[key]])) return(.OP_REF_CACHE[[key]])
  all <- character(0); fun <- character(0); defs <- list(); by_ns <- list(); missing_ns <- character(0)
  for (ns in nss) {
    if (identical(ns, "base")) {
      en <- baseenv(); nm <- ls(en, all.names = TRUE)
      getv <- function(n) get0(n, envir = en, inherits = FALSE)
    } else {
      if (!requireNamespace(ns, quietly = TRUE)) { missing_ns <- c(missing_ns, ns); next }
      en <- asNamespace(ns)
      lz <- tryCatch(ls(getNamespaceInfo(ns, "lazydata"), all.names = TRUE), error = function(e) character(0))
      nm <- unique(c(getNamespaceExports(ns), lz))
      getv <- function(n) if (n %in% lz) NULL else
        tryCatch(getExportedValue(ns, n), error = function(e) get0(n, envir = en, inherits = FALSE))
    }
    all <- c(all, nm); by_ns[[ns]] <- list()
    for (n in nm) {
      v <- getv(n)
      if (is.function(v)) {
        fun <- c(fun, n)
        if (!is.primitive(v) && (any(names(formals(v)) %in% .OP_FN_FORMALS) || identical(n, "do.call"))) {
          by_ns[[ns]][[n]] <- v
          if (is.null(defs[[n]])) defs[[n]] <- v
        }
      }
    }
  }
  out <- list(all = unique(all), fun = unique(fun), hof = defs, hof_by_ns = by_ns, missing = missing_ns, nss = nss)
  assign(key, out, envir = .OP_REF_CACHE)
  out
}

#' 추출기(빌더·스캐너 공용 — 한 구현) — 파일 하나의 이름 쓰임을 자리(role)별로 뽑는다.
#'   role: head(호출 머리) · head_computed(계산된 머리의 안쪽 함수) · value(값 자리 기호) · string(문자열) ·
#'         fn_sym/fn_str/fn_other(고차 함수의 함수 자리 인자) · hof_dots/hof_unmatched · internal(:::) · ns_bad
#' @return list(ok, err, occ = data.table(role, name, ns, hof, snip), bound, fnlit_only, tok_calls)
.op_allow_extract <- function(path_or_src, ref) {
  src <- if (length(path_or_src) == 1L && !grepl("\n", path_or_src, fixed = TRUE) && file.exists(path_or_src))
    paste(sub("\r$", "", readLines(path_or_src, warn = FALSE, encoding = "UTF-8")), collapse = "\n") else
    paste(as.character(path_or_src), collapse = "\n")
  ex <- tryCatch(parse(text = src, keep.source = TRUE), error = function(e) e)
  if (inherits(ex, "error")) return(list(ok = FALSE, err = conditionMessage(ex)))
  # ── 파서 토큰(getParseData) — 호출 머리 집합의 1차 원천. SYMBOL_FUNCTION_CALL($·@ 오른쪽 제외) · SPECIAL(%op%) · <<- · :=
  pd <- utils::getParseData(ex, includeText = TRUE)
  tok_calls <- character(0)
  if (!is.null(pd) && nrow(pd)) {
    tk <- pd[pd$terminal & pd$token != "COMMENT", c("line1", "col1", "token", "text")]
    tk <- tk[order(tk$line1, tk$col1), , drop = FALSE]
    prev <- c("", tk$token[-nrow(tk)])
    fc <- tk$token == "SYMBOL_FUNCTION_CALL" & !prev %in% c("'$'", "'@'")
    asg <- tk$text[tk$token %in% c("LEFT_ASSIGN", "RIGHT_ASSIGN")]
    tok_calls <- unique(c(gsub("^`|`$", "", tk$text[fc]), tk$text[tk$token == "SPECIAL"],
                          ifelse(asg == "->>", "<<-", asg)[asg %in% c("<<-", "->>", ":=")]))
    tok_calls <- setdiff(tok_calls, .OP_SYNTAX)
  }
  # ── AST 걷기 — 자리를 안다(토큰은 자리를 모른다: 함수 자리 인자·계산된 머리·대입 대상)
  st <- new.env(parent = emptyenv())
  st$rows <- list(); st$b <- character(0); st$lit <- character(0); st$nonlit <- character(0)
  dp <- function(v) substr(paste(deparse(v, width.cutoff = 60L)[1], collapse = ""), 1L, 70L)
  add <- function(role, name, ns = NA_character_, hof = NA_character_, snip = name)
    st$rows[[length(st$rows) + 1L]] <- list(role = role, name = name, ns = ns, hof = hof, snip = snip)
  bind <- function(n, lit = NA) {
    st$b <- c(st$b, n)
    if (isTRUE(lit)) st$lit <- c(st$lit, n) else if (identical(lit, FALSE)) st$nonlit <- c(st$nonlit, n)
  }
  # 빈 인자(x[, 1] 의 빈 자리)는 변수에 묶으면 평가 순간 missing 오류다 — 늘 색인식으로 quote(expr = ) 와 대조한다
  is_fn_lit <- function(v) is.call(v) && is.symbol(v[[1]]) && identical(as.character(v[[1]]), "function")
  unparen <- function(v) { while (is.call(v) && identical(v[[1]], as.name("(")) && length(v) == 2L) v <- v[[2]]; v }
  ns_parts <- function(v) {
    if (is.call(v) && is.symbol(v[[1]]) && as.character(v[[1]]) %in% c("::", ":::") && length(v) == 3L)
      return(list(op = as.character(v[[1]]), pkg = v[[2]], nm = v[[3]]))
    NULL
  }
  walk_args <- function(a) {
    nm <- names(a); if (is.null(nm)) nm <- rep("", length(a))
    for (i in seq_along(a)) {
      if (nzchar(nm[i])) bind(nm[i])                        # 이름 붙은 인자 = 열·원소 이름(data.table(Ticker = …) 등)
      if (!identical(a[[i]], quote(expr = ))) walk(a[[i]])
    }
  }
  target <- function(x) {                                   # 대입 대상 — 묶는 이름 · 치환 함수 f<- 머리
    x <- unparen(x)
    if (is.symbol(x)) { bind(as.character(x), lit = FALSE); return(invisible()) }
    if (is.character(x)) { for (z in x) bind(z, lit = FALSE); return(invisible()) }
    if (!is.call(x)) { walk(x); return(invisible()) }
    h <- x[[1]]
    if (is.symbol(h)) {
      hn <- as.character(h)
      if (hn %in% c("$", "@")) { target(x[[2]]); return(invisible()) }
      if (!hn %in% .OP_SYNTAX) { add("head", hn); add("head", paste0(hn, "<-")) }   # names(x) <- v = `names<-`(x, v) (중첩이면 getter 도 불린다)
    } else {
      np <- ns_parts(h)
      if (!is.null(np) && identical(np$op, "::") && is.symbol(np$pkg) && is.symbol(np$nm)) {
        add("head", as.character(np$nm), ns = as.character(np$pkg)); add("head", paste0(as.character(np$nm), "<-"), ns = as.character(np$pkg))
      } else add("head_computed", "?", snip = dp(x))
    }
    if (length(x) >= 2L) target(x[[2]])
    if (length(x) >= 3L) walk_args(as.list(x)[-(1:2)])
    invisible()
  }
  fn_arg <- function(v, hof) {                              # R5 — 함수 자리 인자
    v <- unparen(v)
    if (is.symbol(v)) { add("fn_sym", as.character(v), hof = hof); return(invisible()) }
    if (is.character(v) && length(v) == 1L) { add("fn_str", v, hof = hof); return(invisible()) }
    if (is_fn_lit(v)) { walk(v); return(invisible()) }
    np <- ns_parts(v)
    if (!is.null(np)) {
      if (identical(np$op, "::") && is.symbol(np$pkg) && is.symbol(np$nm))
        add("fn_sym", as.character(np$nm), ns = as.character(np$pkg), hof = hof)
      else add(if (identical(np$op, ":::")) "internal" else "ns_bad", dp(v), snip = dp(v))
      return(invisible())
    }
    add("fn_other", dp(v), hof = hof, snip = dp(v)); walk(v)
  }
  hof_check <- function(e, hn, ns) {                        # R5 — 참조 정의에 FN 자리가 있으면 match.call 로 찾는다
    def <- if (!is.na(ns)) ref$hof_by_ns[[ns]][[hn]] else ref$hof[[hn]]
    if (is.null(def)) return(FALSE)
    a <- as.list(e)[-1]; an <- names(a); if (is.null(an)) an <- rep("", length(a))
    fnf <- intersect(names(formals(def)), .OP_FN_FORMALS)
    dots <- vapply(seq_along(a), function(i) identical(a[[i]], as.name("...")), logical(1))
    if (any(dots) && !any(an %in% fnf)) { add("hof_dots", hn, hof = hn, snip = dp(e)); walk_args(a); return(TRUE) }
    m <- tryCatch(match.call(def, as.call(c(list(as.name(hn)), a[!dots])), expand.dots = FALSE), error = function(z) NULL)
    if (is.null(m)) { add("hof_unmatched", hn, hof = hn, snip = dp(e)); walk_args(a); return(TRUE) }
    ma <- as.list(m)[-1]
    for (k in names(ma)) {
      if (k %in% fnf) { fn_arg(ma[[k]], hn); next }
      if (identical(k, "...")) { walk_args(ma[[k]]); next }
      if (!identical(ma[[k]], quote(expr = ))) walk(ma[[k]])
    }
    TRUE
  }
  walk <- function(e) {
    if (is.symbol(e)) { n <- as.character(e); if (nzchar(n)) add("value", n); return(invisible()) }
    if (is.character(e)) { for (z in e) add("string", z); return(invisible()) }
    if (is.expression(e) || is.pairlist(e) || (is.list(e) && !is.call(e))) {
      for (i in seq_along(e)) if (!identical(e[[i]], quote(expr = ))) walk(e[[i]])
      return(invisible())
    }
    if (!is.call(e)) return(invisible())
    h <- e[[1]]; a <- as.list(e)[-1]
    np <- ns_parts(e)
    if (!is.null(np)) {                                     # pkg::name 을 값으로
      if (identical(np$op, "::") && is.symbol(np$pkg) && is.symbol(np$nm)) add("value", as.character(np$nm), ns = as.character(np$pkg))
      else add(if (identical(np$op, ":::")) "internal" else "ns_bad", dp(e), snip = dp(e))
      return(invisible())
    }
    if (is.symbol(h)) {
      hn <- as.character(h)
      if (identical(hn, "function")) {
        fm <- e[[2]]
        if (!is.null(fm)) { for (z in names(fm)) bind(z); for (i in seq_along(fm)) if (!identical(fm[[i]], quote(expr = ))) walk(fm[[i]]) }
        if (length(e) >= 3L) walk(e[[3]])
        return(invisible())
      }
      if (hn %in% c("<-", "=", "<<-")) {
        if (identical(hn, "<<-")) add("head", "<<-")
        rhs <- if (length(e) >= 3L) e[[3]] else NULL
        tg <- unparen(e[[2]])
        if (is.symbol(tg)) bind(as.character(tg), lit = is_fn_lit(unparen(rhs))) else target(tg)
        if (!is.null(rhs)) walk(rhs)
        return(invisible())
      }
      if (identical(hn, ":=")) {
        add("head", ":=")
        an <- names(a)
        if (length(a) == 2L && (is.null(an) || !any(nzchar(an)))) {
          l <- unparen(a[[1]])
          if (is.symbol(l)) bind(as.character(l), lit = FALSE)
          else if (is.character(l)) for (z in l) bind(z, lit = FALSE)
          else if (is.call(l) && identical(l[[1]], as.name("c")) && length(l) > 1L &&
                   all(vapply(as.list(l)[-1], is.character, logical(1)))) for (z in unlist(as.list(l)[-1])) bind(z, lit = FALSE)
          else walk(l)
          if (!identical(a[[2]], quote(expr = ))) walk(a[[2]])
        } else walk_args(a)
        return(invisible())
      }
      if (identical(hn, "for")) { bind(as.character(e[[2]]), lit = FALSE); walk(e[[3]]); walk(e[[4]]); return(invisible()) }
      if (hn %in% c("$", "@")) { walk(e[[2]]); return(invisible()) }    # 오른쪽 = 필드 이름(변수 조회 아님)
      if (hn %in% .OP_SYNTAX) { walk_args(a); return(invisible()) }
      add("head", hn)
      if (!hof_check(e, hn, NA_character_)) walk_args(a)
      return(invisible())
    }
    hnp <- ns_parts(h)
    if (!is.null(hnp)) {                                    # pkg::f(…)
      if (!identical(hnp$op, "::") || !is.symbol(hnp$pkg) || !is.symbol(hnp$nm)) {
        add(if (identical(hnp$op, ":::")) "internal" else "ns_bad", dp(h), snip = dp(h)); walk_args(a); return(invisible()) }
      hn <- as.character(hnp$nm); ns <- as.character(hnp$pkg)
      add("head", hn, ns = ns)
      if (!hof_check(e, hn, ns)) walk_args(a)
      return(invisible())
    }
    hu <- unparen(h)
    if (is.symbol(hu)) { walk(as.call(c(list(hu), a))); return(invisible()) }   # (f)(…) = f(…)
    if (is_fn_lit(hu)) { walk(hu); walk_args(a); return(invisible()) }          # 즉시 호출 함수 리터럴
    inner <- "?"                                            # 계산된 머리 — f(…)(…) 의 f · 추출 연산자면 그 이름([[ · $ …)
    if (is.call(hu)) {
      if (is.symbol(hu[[1]])) inner <- as.character(hu[[1]]) else {
        q <- ns_parts(hu[[1]]); if (!is.null(q) && is.symbol(q$nm)) inner <- as.character(q$nm) }
    }
    add("head_computed", inner, snip = dp(e))
    walk(hu); walk_args(a)
    invisible()
  }
  for (i in seq_along(ex)) walk(ex[[i]])
  occ <- if (length(st$rows)) rbindlist(st$rows) else
    data.table(role = character(), name = character(), ns = character(), hof = character(), snip = character())
  list(ok = TRUE, occ = occ, bound = unique(st$b), fnlit_only = setdiff(unique(st$lit), c(unique(st$nonlit))),
       tok_calls = tok_calls)
}

#' 레지스트리 적재·검증 — 찾는 순서 root → .OP_ROOT()(④ 설정과 같은 규약 · 샌드박스 루트는 정본을 읽기만 한다)
#' @return list(ok, reason, path, fallback, ref_ns, common = list(calls, values, strings, fnargs, fnstrs, headcalls, pkgs), grants)
overlay_probe_allowlist_params <- function(root = .OP_ROOT()) {
  cands <- unique(file.path(c(root, .OP_ROOT()), "06_Registry/overlay_probe_allowlist.json"))
  p <- cands[file.exists(cands)][1]
  no <- function(r) list(ok = FALSE, reason = r, path = p)
  if (is.na(p)) return(no(sprintf("허용 목록 부재 — %s", paste(cands, collapse = " · "))))
  j <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) return(no(sprintf("허용 목록 JSON 파손 — %s", p)))
  if (!identical(as.character(j$schema %||% ""), .OP_ALLOW_SCHEMA)) return(no(sprintf("schema != %s", .OP_ALLOW_SCHEMA)))
  vec <- function(x) as.character(unlist(x %||% list()))
  keys <- c("calls", "values", "shadow", "strings", "fnargs", "fnstrs", "headcalls", "pkgs")
  cm <- j$common
  if (!is.list(cm) || !all(keys %in% names(cm))) return(no(sprintf("common 키 = {%s} 여야 한다", paste(keys, collapse = ","))))
  common <- setNames(lapply(keys, function(k) vec(cm[[k]])), keys)
  # widened = 사람이 검토해 넓힌 이름(빌더 산출 common 과 분리 — 재빌드 대조가 손편집과 드리프트를 가를 수 있게). 능력 계열은 여기서도 거부.
  wd <- j$widened
  if (is.list(wd)) for (k in intersect(keys, names(wd))) common[[k]] <- union(common[[k]], vec(wd[[k]]))
  ref_ns <- vec(j$ref_namespaces)
  if (!"base" %in% ref_ns) return(no("ref_namespaces 에 base 필수"))
  cap <- intersect(unlist(common[setdiff(keys, "pkgs")]), .OP_CAPABILITY)
  if (length(cap)) return(no(sprintf("공통 목록에 능력 계열 이름 %s — 레지스트리 무효(능력은 sha 고정 개별 허가로만)", paste(cap, collapse = ","))))
  gr <- j$grants %||% list()
  grants <- lapply(gr, function(g) c(list(sha256 = as.character(g$sha256 %||% "")), setNames(lapply(keys, function(k) vec(g[[k]])), keys)))
  list(ok = TRUE, path = p, fallback = !identical(p, cands[1]), ref_ns = ref_ns, common = common, grants = grants,
       schema_cols = vec(j$schema_columns))
}

.op_sha256 <- function(p) {             # 없으면 "" — 개별 허가가 안 맞아 공통 목록으로만 잰다(fail-closed)
  if (requireNamespace("digest", quietly = TRUE)) return(digest::digest(file = p, algo = "sha256"))
  if (requireNamespace("openssl", quietly = TRUE)) { con <- file(p, "rb"); on.exit(close(con)); return(as.character(openssl::sha256(con))) }
  ""
}

#' R1~R6 판정 — 추출 결과 × 허용 집합. 0행 = 통과
.op_allow_decide <- function(x, al, ref, schema) {
  if (!isTRUE(x$ok)) return(data.table(rule = "unparseable", snippet = substr(as.character(x$err %||% ""), 1L, 70L)))
  o <- x$occ; B <- x$bound; A <- al
  inref <- function(n) n %in% ref$all
  out <- list(); hit <- function(rule, s) out[[length(out) + 1L]] <<- data.table(rule = rule, snippet = s)
  # 추출 일치 — 토큰이 본 호출 머리를 AST 가 못 봤으면 걷기 결함(검사 안 된 호출)이다
  miss <- setdiff(x$tok_calls, o[role == "head", name])
  if (length(miss)) hit("extract_mismatch", paste(miss, collapse = ","))
  for (i in seq_len(nrow(o))) {
    r <- o$role[i]; n <- o$name[i]; ns <- o$ns[i]; q <- !is.na(ns)
    if (q && !ns %in% A$pkgs) { hit("pkg_not_allowed", paste0(ns, "::", n)); next }
    if (r == "head") {
      if (n %in% A$calls) next
      if (!q && n %in% B && !inref(n)) next                  # 지역 도우미(이 파일이 묶은 이름 · 참조 이름공간에 없음)
      hit("call_not_allowed", if (q) paste0(ns, "::", n) else n)
    } else if (r == "value") {
      if (n %in% A$values || n %in% c("...", sprintf("..%d", 1:9))) next
      # 지역 변수 이름이 참조 이름과 겹친다(q·t·cut·col·nobs…) — 이 파일이 그 이름을 묶었을 때만. 정본 shadow 목록이 아니면
      #   능력 계열·고차 함수 이름은 안 된다(if (FALSE) sys.frame <- 1; f <- sys.frame 처럼 '묶인 척' 해 참조 이름공간 객체를 끌어오는 별칭 차단)
      if (!q && inref(n) && n %in% B && (n %in% A$shadow || (!n %in% .OP_CAPABILITY && is.null(ref$hof[[n]])))) next
      if (!q && !inref(n) && (n %in% B || n %in% schema)) next
      hit(if (inref(n)) "value_not_allowed" else "free_name", if (q) paste0(ns, "::", n) else n)
    } else if (r == "string") {
      # 문자열 → 함수 변환 통로는 R5(함수 자리)·do.call 이 막는다. 여기는 이중 방어 — 능력 계열·고차 함수 이름 문자열만 거부
      #   ("sys.frame"·"sapply" 를 어딘가에 들고 있는 것 자체). "list"·"mean" 같은 흔한 낱말은 통과(정본 LOO 오탐 원인이었다).
      if (n %in% ref$fun && !n %in% A$strings && (n %in% .OP_CAPABILITY || !is.null(ref$hof[[n]]))) hit("string_ref", sprintf('"%s"', n))
    } else if (r == "fn_sym") {
      if (!q && n %in% x$fnlit_only && !inref(n)) next       # 이 파일이 함수 리터럴로만 묶은 이름
      if (n %in% A$fnargs && is.null(ref$hof[[n]])) next     # 허용된 함수이면서 그 자신은 고차 함수가 아님
      hit("fn_not_allowed", sprintf("%s(… %s …)", o$hof[i], if (q) paste0(ns, "::", n) else n))
    } else if (r == "fn_str") {
      if (identical(o$hof[i], "do.call")) { hit("docall_string", sprintf('do.call("%s", …)', n)); next }
      if (n %in% A$fnstrs && is.null(ref$hof[[n]])) next
      if (n %in% .OP_FN_SYNTAX_STR) next                   # 연산자 문자열(sweep(…, "*") · vapply(l, "[[", …)) — 문법으로 이미 쓸 수 있는 것
      hit("fn_not_allowed", sprintf('%s(… "%s" …)', o$hof[i], n))
    } else if (r == "fn_other") {
      hit("computed_fn", sprintf("%s(… %s …)", o$hof[i], o$snip[i]))
    } else if (r == "head_computed") {
      if (n %in% A$headcalls) next
      hit("computed_head", o$snip[i])
    } else if (r %in% c("hof_dots", "hof_unmatched", "internal", "ns_bad")) {
      hit(r, o$snip[i])
    }
  }
  if (!length(out)) return(data.table(rule = character(), snippet = character()))
  unique(rbindlist(out))
}

#' ③d 공개 진입 — 파일(또는 소스 문자열) 하나를 허용 목록으로 판정한다
#' @param kind  개별 허가(grants) 조회 키. NULL 이면 공통 목록만
#' @return list(ok, reason, hits = data.table(rule, snippet), grant, al_path)
overlay_probe_allowlist_scan <- function(path_or_src, kind = NULL, root = .OP_ROOT(), al = NULL) {
  if (is.null(al)) al <- overlay_probe_allowlist_params(root)
  if (!isTRUE(al$ok)) return(list(ok = FALSE, reason = al$reason, hits = data.table(rule = "registry", snippet = al$reason)))
  ref <- .op_ref_index(al$ref_ns)
  if (length(ref$missing)) return(list(ok = FALSE, reason = sprintf("참조 이름공간 미설치 %s — 판정 불가(fail-closed)", paste(ref$missing, collapse = ",")),
                                       hits = data.table(rule = "ref_missing", snippet = paste(ref$missing, collapse = ","))))
  A <- al$common; gnote <- "공통 목록"
  g <- if (!is.null(kind)) al$grants[[kind]] else NULL
  if (!is.null(g)) {
    is_file <- length(path_or_src) == 1L && !grepl("\n", path_or_src, fixed = TRUE) && file.exists(path_or_src)
    sh <- if (is_file) .op_sha256(path_or_src) else ""
    if (nzchar(g$sha256) && identical(tolower(sh), tolower(g$sha256))) {
      for (k in names(A)) A[[k]] <- union(A[[k]], g[[k]])
      gnote <- sprintf("공통 + 개별 허가 %s(sha %s)", kind, substr(sh, 1L, 12L))
    } else gnote <- sprintf("개별 허가 %s 무효 — sha 불일치(%s ≠ %s) · 공통 목록만", kind, substr(sh, 1L, 12L), substr(g$sha256, 1L, 12L))
  }
  fx <- overlay_probe_fixture()
  schema <- unique(c(names(fx$M), names(fx$hold), "Date", al$schema_cols))
  x <- .op_allow_extract(path_or_src, ref)
  h <- .op_allow_decide(x, A, ref, schema)
  list(ok = !nrow(h), hits = h, grant = gnote, al_path = al$path, fallback = isTRUE(al$fallback),
       reason = if (nrow(h)) sprintf("허용 목록 밖 %d건 — %s", nrow(h),
                                     paste(utils::head(sprintf("%s: %s", h$rule, h$snippet), 6L), collapse = " | ")) else NA_character_)
}

#' 빌더 — 정본 arm 디렉터리에서 허용 집합을 만든다(쓰기는 호출자 몫 · 이 함수는 목록만 돌려준다)
#'   ★규칙(도훈 지시 R3R — "정본 arm 이 쓰는 함수 호출 전수가 허용 집합, 환경 조작은 거부"):
#'   공통(common) = 정본 arm **전부**의 쓰임 합집합 − 능력 계열(.OP_CAPABILITY). 참조 이름공간에 있는 이름만(지역 도우미 이름은 넣지 않는다).
#'     values = 이 파일이 묶지 않은 채 값으로 부른 참조 이름(진짜 참조) · shadow = 이 파일이 지역 변수로 묶은 참조 이름(q·t·cut 류 —
#'     지역 변수 이름으로만 허용하고 묶지 않은 파일에서는 거부한다)
#'   개별 허가(grants) = 능력 계열을 쓰거나 자유 이름(전역 조회)이 있는 정본 arm — 공통 밖에 필요한 것 전부 · 파일 sha256 고정
#' @return list(json = <레지스트리 본문>, cls = 분류, per = arm 별 추출)
overlay_probe_allowlist_build <- function(arm_dir, ref_ns, exclude = character(0), reasons = list()) {
  ref <- .op_ref_index(ref_ns)
  if (length(ref$missing)) stop("[overlay_probe] 참조 이름공간 미설치: ", paste(ref$missing, collapse = ","))
  fs <- list.files(arm_dir, pattern = "^[A-Za-z].*[.]R$", full.names = TRUE)
  fs <- fs[!sub("[.]R$", "", basename(fs)) %in% exclude]
  fx <- overlay_probe_fixture(); schema <- unique(c(names(fx$M), names(fx$hold), "Date"))
  keys <- c("calls", "values", "shadow", "strings", "fnargs", "fnstrs", "headcalls", "pkgs")
  use_of <- function(x) {
    o <- x$occ; B <- x$bound; inr <- function(n) n %in% ref$all
    hv <- o[role == "value"]
    list(calls     = unique(c(o[role == "head" & (!is.na(ns) | !(name %in% B) | inr(name)), name],
                              x$tok_calls[!x$tok_calls %in% B | inr(x$tok_calls)])),
         values    = unique(hv[(!is.na(ns) & inr(name)) | (is.na(ns) & inr(name) & !(name %in% B)), name]),
         shadow    = unique(hv[is.na(ns) & inr(name) & name %in% B, name]),
         strings   = unique(o[role == "string" & name %in% ref$fun, name]),
         fnargs    = unique(o[role == "fn_sym" & (!is.na(ns) | !(name %in% x$fnlit_only) | inr(name)), name]),
         fnstrs    = unique(o[role == "fn_str", name]),
         headcalls = unique(o[role == "head_computed", name]),
         pkgs      = unique(stats::na.omit(o$ns)),
         free      = unique(hv[is.na(ns) & !inr(name) & !(name %in% B) & !(name %in% schema), name]))
  }
  per <- list(); cls <- character(0)
  for (f in fs) {
    k <- sub("[.]R$", "", basename(f))
    x <- .op_allow_extract(f, ref)
    if (!isTRUE(x$ok)) stop("[overlay_probe] 정본 arm 파싱 불가: ", basename(f), " — ", x$err)
    u <- use_of(x)
    capu <- intersect(unlist(u[setdiff(keys, "pkgs")]), .OP_CAPABILITY)
    per[[k]] <- list(u = u, x = x, sha = .op_sha256(f), cap = capu)
    cls[k] <- if (length(capu) || length(u$free)) "grant" else "common"
  }
  common <- setNames(lapply(keys, function(z) sort(setdiff(unique(unlist(lapply(per, function(p) p$u[[z]]))), .OP_CAPABILITY))), keys)
  grants <- list()
  for (k in names(cls)[cls == "grant"]) {
    u <- per[[k]]$u; u$values <- unique(c(u$values, u$free))
    g <- setNames(lapply(keys, function(z) sort(setdiff(u[[z]], common[[z]]))), keys)
    grants[[k]] <- c(list(sha256 = per[[k]]$sha, capability = sort(per[[k]]$cap), free_names = sort(per[[k]]$u$free),
                          reason = as.character(reasons[[k]] %||% "능력 계열 사용 정본 arm — 파일 sha 고정 개별 허가")), g)
  }
  js <- list(schema = .OP_ALLOW_SCHEMA, ref_namespaces = ref_ns, schema_columns = character(0),
             source_arms = unname(lapply(names(per), function(k) list(kind = k, sha256 = per[[k]]$sha, class = unname(cls[k])))),
             common = common, grants = grants)
  list(json = js, cls = cls, per = per)
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

  # ── ③d 허용 목록 (R3R 2026-09-25 · P0-09 정적 probe 경화) — 목록 밖 호출·값·함수 자리 인자·환경 조작·do.call 문자열 = 거부.
  #   ③c 는 알려진 통로 열거(보조)로 남는다. 레지스트리(06_Registry/overlay_probe_allowlist.json) 부재·손상·능력 계열 오염 = FAIL.
  al_s <- overlay_probe_allowlist_scan(p, kind = kind, root = root)
  if (!isTRUE(al_s$ok)) { add("allowlist", "FAIL", as.character(al_s$reason))
                          return(bad(sprintf("허용 목록 밖 — 정본 arm 이 쓰지 않는 호출·환경 조작·계산된 함수 자리(fail-closed): %s",
                                             as.character(al_s$reason)))) }
  add("allowlist", "PASS", sprintf("허용 목록 안 — %s · 레지스트리 %s%s", al_s$grant, basename(al_s$al_path),
                                   if (isTRUE(al_s$fallback)) " (QM_ROOT 폴백)" else ""))

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

cat("[overlay_probe.R] Loaded — overlay_probe_arm(kind) / overlay_probe_fixture() / overlay_probe_allowlist_scan(path, kind) (+ ③d 허용 목록 · R3R)\n")
