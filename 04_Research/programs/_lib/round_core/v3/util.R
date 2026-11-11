## round_core v3 · util — 공용 도구(경로 · md5 · JSON · 과반 · 안전 호출 · τ_D 가림 · 실행 시간 기록)
##   라운드마다 다시 쓰이던 도우미의 단일 출처(P2R04 evaluate.R · round_kit.R 에서 이관 — 함수 본문은 같은 동작).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RC_VERSION <- "v3"
RC_REDACT  <- "[τ_D 이후 날짜 가림]"

## 프로젝트 루트 — 명시 > QM_ROOT > CLAUDE_PROJECT_DIR > 기본값(대소문자 · 구분자 정규화만)
rc_root <- function(root = NULL) {
  r <- root %||% Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  gsub("\\\\", "/", r)
}
rc_md5 <- function(f) unname(as.character(tools::md5sum(f)))
rc_rel <- function(p, root = rc_root()) {
  p <- gsub("\\\\", "/", p); r <- paste0(sub("/$", "", gsub("\\\\", "/", root)), "/")
  ifelse(startsWith(tolower(p), tolower(r)), substring(p, nchar(r) + 1L), p)
}
rc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
rc_abs <- function(p, root = rc_root()) ifelse(grepl("^([A-Za-z]:|/)", p), p, file.path(root, p))

## JSON — 읽기는 목록 그대로(simplifyVector = FALSE) · 쓰기는 원자적 교체 · 수치 손실 없음(digits = NA)
rc_json_read <- function(path) fromJSON(path, simplifyVector = FALSE)
rc_json_write <- function(x, path, pretty = TRUE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = pretty, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}

## 과반 — '비율이 이 값을 넘어야 과반'(엄격 >) · 비유한 = 거짓(P2R04 p2_maj 그대로)
rc_maj <- function(share, maj) {
  s <- suppressWarnings(as.numeric(share)); m <- suppressWarnings(as.numeric(maj))
  length(s) == 1L && length(m) == 1L && is.finite(s) && is.finite(m) && s > m
}

## 안전 호출 — 예기치 않은 오류는 그 단위만 미시험(평가 전체가 멈추지 않게 · 사전등록 체크리스트 5)
rc_safe <- function(f, ..., what = "") {
  tryCatch(list(ok = TRUE, value = f(...)),
           error = function(e) list(ok = FALSE, value = NULL, error = paste0(if (nzchar(what)) paste0(what, ": ") else "", conditionMessage(e))))
}

## τ_D 이후 날짜 가림(보는 창 파일 · P2R04 p2_redact_after_tau 와 같은 규칙) — 일(YYYY-MM-DD) · 월(YYYY-MM) 표기를 모두 본다
.rc_redact_chr <- function(s, tau) {
  tau <- as.Date(tau); ok <- !is.na(s)
  if (!any(ok)) return(s)
  tau_ym <- format(tau, "%Y-%m"); x <- s[ok]
  # ★perl = TRUE 필수(2026-11-10): 기본 엔진은 BMP 밖 문자 뒤에서 위치가 어긋나 그 뒤 날짜를 가리지 못한다(가림과 누출 검사가 같은 약점을 공유했다)
  m <- gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", x, perl = TRUE)
  regmatches(x, m) <- lapply(regmatches(x, m), function(v) { if (!length(v)) return(v); d <- suppressWarnings(as.Date(v))
                                                              ifelse(!is.na(d) & d > tau, RC_REDACT, v) })
  m2 <- gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", x, perl = TRUE)
  regmatches(x, m2) <- lapply(regmatches(x, m2), function(v) if (!length(v)) v else ifelse(v > tau_ym, RC_REDACT, v))
  for (i in seq_along(x)) for (h in .rc_tau_alt_hits(x[i], tau_ym)) x[i] <- gsub(h, RC_REDACT, x[i], fixed = TRUE)   # 표기 변형도 가린다(검사와 같은 규칙)
  s[ok] <- x; s
}
## 날짜 표기 변형(11-10 · 감사 K P4) — 한국어 연(월) · 슬래시 · 점 · 두 자리 연도(’23년) · 분기(2023Q1 · 1Q23 · 2023년 1분기).
##   반환 = 표기마다 (문자열 · 그 표기가 가리키는 가장 이른 연월 'YYYY-MM') — 연만 있는 표기 = 그 해 1월(τ_D 연도와 같으면 τ_D 뒤 아님 · 다음 해부터 누출).
##   ISO(YYYY-MM[-DD])는 아래 본 규칙이 맡는다(이 함수는 변형만).
RC_TAU_ALT_RX <- c(
  ko_ym  = "(?<![0-9])((?:19|20)[0-9]{2})\\s*년\\s*(?:(0?[1-9]|1[0-2])\\s*월)?",
  slash  = "(?<![0-9])((?:19|20)[0-9]{2})[/.](0?[1-9]|1[0-2])(?![0-9])",
  yy_ko  = "[’'`]([0-9]{2})\\s*년",
  q_a    = "(?<![0-9])((?:19|20)[0-9]{2})\\s*[Qq]([1-4])(?![0-9])",
  q_b    = "(?<![0-9A-Za-z])([1-4])[Qq]\\s*'?([0-9]{2})(?![0-9])",
  q_ko   = "(?<![0-9])((?:19|20)[0-9]{2})\\s*년\\s*([1-4])\\s*분기")
.rc_tau_alt_hits <- function(v, tau_ym) {
  out <- character(0)
  for (nm in names(RC_TAU_ALT_RX)) {
    mm <- regmatches(v, gregexpr(RC_TAU_ALT_RX[[nm]], v, perl = TRUE))
    for (s in unlist(mm)) {
      g <- regmatches(s, regexec(RC_TAU_ALT_RX[[nm]], s, perl = TRUE))[[1]]
      ym <- switch(nm,
        ko_ym = sprintf("%s-%02d", g[2], if (nzchar(g[3])) as.integer(g[3]) else 1L),
        slash = sprintf("%s-%02d", g[2], as.integer(g[3])),
        yy_ko = sprintf("20%s-01", g[2]),
        q_a = sprintf("%s-%02d", g[2], 3L * as.integer(g[3]) - 2L),
        q_b = sprintf("20%s-%02d", g[3], 3L * as.integer(g[2]) - 2L),
        q_ko = sprintf("%s-%02d", g[2], 3L * as.integer(g[3]) - 2L))
      if (!is.na(ym) && ym > tau_ym) out <- c(out, s)
    }
  }
  unique(out)
}
rc_redact_after_tau <- function(x, tau) {
  tau <- as.Date(tau)
  if (is.character(x)) return(.rc_redact_chr(x, tau))
  if (is.data.table(x)) { x <- copy(x); for (cc in names(x)) if (is.character(x[[cc]])) set(x, j = cc, value = .rc_redact_chr(x[[cc]], tau)); return(x) }
  if (is.data.frame(x)) { for (cc in names(x)) if (is.character(x[[cc]])) x[[cc]] <- .rc_redact_chr(x[[cc]], tau); return(x) }
  if (is.list(x) && length(x)) { x[] <- lapply(x, rc_redact_after_tau, tau = tau); return(x) }
  x
}
## 보는 창 파일에 τ_D 이후 날짜가 남았는지 전수 검사(쓰기 전 단정 — 남으면 그 목록)
rc_after_tau_leaks <- function(x, tau) {
  tau <- as.Date(tau); tau_ym <- format(tau, "%Y-%m"); out <- character(0)
  walk <- function(v) {
    if (is.character(v)) {
      d <- unlist(regmatches(v, gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", v, perl = TRUE)))
      dd <- suppressWarnings(as.Date(d)); out <<- c(out, d[!is.na(dd) & dd > tau])
      ym <- unlist(regmatches(v, gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", v, perl = TRUE)))
      out <<- c(out, ym[ym > tau_ym])
      out <<- c(out, .rc_tau_alt_hits(v[!is.na(v)], tau_ym))      # 표기 변형(한국어 연월 · 슬래시 · 점 · ’yy년 · 분기)
    } else if (is.list(v)) for (e in v) walk(e)
    else if (inherits(v, "Date")) out <<- c(out, format(v[!is.na(v) & v > tau]))
  }
  walk(x); unique(out)
}

## 처방 입력 글 검사(11-10 · 감사 K P1) — 쓰기(결과 원장 rc_outcome_record)와 읽기(설계 입력 · 생성기 검토 .rcp4_assert_clean)가 같은 함수를 쓴다:
##   받아들인 줄은 반드시 읽힌다(전에는 쓰기가 등급 표기를 안 봐 '등급 C' 교훈 한 줄이 설계 입력을 영구 정지시켰다).
## 11-10(2) 정보 경계 검사 확장(감사 U11 · fail-closed — 모르면 막는다) — 전에는 '등급 X' 어순과 ISO · 몇 변형 날짜만 봐서
##   'A등급' · 'B→A' · '2023~2025' · '23년' · 'Mar 2023' · '20230315' · '2023H1' · 'FY2024' · '시험 창 Calmar 0.41' 이 통과했다.
##   이 함수 하나를 결과 원장 쓰기(rc_outcome_record) · 원장 읽기(rc_outcomes_read(tau_clean =)) · 설계 입력 · 생성기 검토(p4.R .rcp4_assert_clean) ·
##   처방 레인 문서(rx_round.R .rx_assert_clean)가 함께 쓴다(한 구현). 이 검사는 rc_after_tau_leaks(보는 창 기계 파일 검사 · 날짜만)보다 넓다 —
##   글(처방 에이전트가 읽는 자리)에만 건다.
##   ① 등급 표기 — 어순 · 표기 전부: '등급 A' · '등급: A' · '등급은 B' · 'A등급' · 'A 등급' · 'A급' · 'Grade B' · 'graded A' · 'A grade' · 'B→A' ·
##      필드(essence_grade: "B") · 등급 상태어('A 자격' · 'A 후보' · 'A 달성' · 'A 승격' · 'A 띠'). 칸 · 블록 라벨('칸 A' · 'B1 블록' · 'C1~C15')과
##      '등급 산식' · 'A 하한'(문턱 이름)은 통과.
##   ② τ_D 뒤 연도 — 구분자 무관: 네 자리 연도 단독(범위 2023~2025 · Mar 2023 · 2023H1) · FY2024 · YYYYMMDD · YYYYMM · 두 자리('23년 · ’23 · 23H1 · 24Q3 · 24.3Q).
##      두 자리 연도는 기간 표현(10년 보유)과 겹쳐 '오늘 연도 이하'만 연도로 읽는다(미래 연도에는 성과가 있을 수 없다) · '…년간' · '…년 동안'은 기간.
##   ③ 시험 창 성과 수치 — 시험 창 · 강건성 구간 · τ_D 이후 · OOS · holdout · 전기간 · 전체 기간 · 검증 구간 · full sample 같은 말과 같은 문단 안의 수치
##      (11-10(3) — 전에는 같은 줄 24자 안만 봐서 줄바꿈 · 긴 수식어로 우회됐다 · 단위 = 칸 안 문단)
##      (소수 · 백분율 · 분수 · 지표 이름 + 수 · 건수). 날짜 · 연도는 숫자로 세지 않는다(②가 맡는다 · '2015~2016 위기' 같은 교훈은 통과).
##   allow = 코드가 생성한 고정 문장(규범 · 지시문)의 정확한 부분 문자열 — 검사 전에 그 문자열만 지운다(데이터에서 오지 않는 것만 · 호출부가 상수로 준다).
##   11-10(3) 재수리(독립 검증) — 'Grade-A'(하이픈 · 대시) · 한국어 서술형 이동 · 판정('B에서 A로 올라갔다' · 'A로 승급' · 'A 판정' · '판정 A') ·
##      '전체 기간' · '전 구간' · '전체 표본' · '검증 구간' · 시험 창 수치를 줄바꿈 · 24자 밖으로 떼어 놓는 우회를 막는다.
##      ③은 같은 줄 24자 근접이 아니라 '문단'(한 칸 = 원장 필드 원소 하나 · 그 안의 빈 줄 · 마크다운 구조 줄(- * + > # | 1.)로 나뉜 덩어리) 안의
##      공존으로 본다 — 한 문단 안에 시험 창 · OOS · 강건성 · 전기간 낱말과 수치가 함께 있으면 막는다(거리 무관).
RC_GRADE_MARK_RX <- c(
  word_letter = "(?<![A-Za-z])(?:등급|[Gg]rade[ds]?|GRADE)\\s*(?:[:：=\\-–—]|은|는|이|가|을|를|으로|로|도)?\\s*[\"'“”‘’(\\[]?\\s*[ABCF][+]?(?![A-Za-z0-9_])",
  field       = "(?i)grade[a-z0-9_]*[\"']?\\s*[:=]\\s*[\"']?[ABCF](?![A-Za-z0-9_])",
  letter_word = "(?<![A-Za-z0-9_])[ABCF][+]?\\s*-?\\s*(?:등급|[Gg]rade|GRADE)",
  letter_geup = "(?<![A-Za-z0-9_])[ABCF][+]?\\s*급(?!락|등|증|감|변|반|격|매|히|속)",
  transition  = "(?<![A-Za-z0-9_])[ABCF][+]?\\s*(?:→|->|=>|⇒|➜|➔|⟶|－>)\\s*[ABCF](?![A-Za-z0-9_])",
  status_word = "(?<![A-Za-z0-9_])[ABCF][+]?\\s*(?:자격|후보|달성|승격|강등|도달|등극|띠)")
## 서술형 이동 · 판정(11-10(3)) — 칸 · 블록 라벨('칸 A 로 옮겨' · '칸 B 에서 칸 C 로')과 'A/B' 비교 표기를 먼저 가린 사본에만 건다(오탐 방지 ·
##   가린 사본은 이 두 규칙에만 쓰고 위 규칙은 원문에 건다 — 라벨 가림이 'A등급' 같은 표기를 숨기지 않게).
RC_GRADE_LABEL_MASK_RX <- paste0("(?:칸|블록|변형|사본|슬리브|팔|[Aa]rm|안|군|그룹|모형|모델|사양|시나리오|경로|방법)\\s*[ABCF](?![A-Za-z0-9_+])|",
                                 "(?<![A-Za-z0-9_])[ABCF]\\s*/\\s*[ABCF](?![A-Za-z0-9_])")
RC_GRADE_NARR_RX <- c(
  ko_move   = "(?<![A-Za-z0-9_/])[ABCF][+]?\\s*(?:에서|으로|로)\\s*(?:[ABCF][+]?(?![A-Za-z0-9_])|승급|승격|상향|하향|강등|올라|올랐|올려|오르|오른|내려|내렸|떨어|상승|하락)",
  verdict_a = "(?<![A-Za-z0-9_/])[ABCF][+]?\\s*(?:판정|판결)",
  verdict_b = "판정\\s*(?:[:：=]|은|는|이|가|결과\\s*(?:는|가|=)?)?\\s*[\"'“”‘’(\\[]?\\s*[ABCF][+]?(?![A-Za-z0-9_/])")
.rc_grade_hits <- function(txt) {
  a <- unlist(lapply(RC_GRADE_MARK_RX, function(rx) regmatches(txt, gregexpr(rx, txt, perl = TRUE))[[1]]))
  m <- gsub(RC_GRADE_LABEL_MASK_RX, "§L", txt, perl = TRUE)
  b <- unlist(lapply(RC_GRADE_NARR_RX, function(rx) regmatches(m, gregexpr(rx, m, perl = TRUE))[[1]]))
  unique(c(a, b))
}
RC_MON_RX <- "(?:[Jj]an|[Ff]eb|[Mm]ar|[Aa]pr|[Mm]ay|[Jj]un|[Jj]ul|[Aa]ug|[Ss]ep|[Oo]ct|[Nn]ov|[Dd]ec)[a-z]*\\.?,?\\s*"
RC_YEAR_RX <- c(
  y4       = "(?<![0-9A-Za-z_.])((?:19|20)[0-9]{2})(?![0-9_])",
  fy       = "(?:FY|Fy|fy|CY)\\s*'?((?:19|20)?[0-9]{2})(?![0-9])",
  mon4     = paste0(RC_MON_RX, "((?:19|20)[0-9]{2})(?![0-9])"),
  compact8 = "(?<![0-9A-Za-z_])((?:19|20)[0-9]{2})(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])(?![0-9_])",
  compact6 = "(?<![0-9A-Za-z_])((?:19|20)[0-9]{2})(0[1-9]|1[0-2])(?![0-9_])",
  yy_ko    = "(?<![0-9.])([0-9]{2})\\s*년(?!\\s*(?:간|동안|치|이상|이내|넘게|째|물|만에))",
  yy_apos  = "[’'`‘]\\s*([0-9]{2})(?![0-9])",
  yy_half  = "(?<![0-9A-Za-z.])([0-9]{2})\\s*[Hh]([12])(?![0-9A-Za-z])",
  yy_q     = "(?<![0-9A-Za-z.])([0-9]{2})\\s*[Qq]([1-4])(?![0-9])",
  yy_dotq  = "(?<![0-9.])([0-9]{2})\\.\\s*([1-4])\\s*[Qq](?![A-Za-z])")
.rc_year_hits <- function(v, tau) {
  ty <- as.integer(format(tau, "%Y")); tym <- format(tau, "%Y-%m"); now_y <- as.integer(format(Sys.Date(), "%Y")); out <- character(0)
  for (nm in names(RC_YEAR_RX)) for (s in unlist(regmatches(v, gregexpr(RC_YEAR_RX[[nm]], v, perl = TRUE)))) {
    g <- regmatches(s, regexec(RC_YEAR_RX[[nm]], s, perl = TRUE))[[1]]; y <- g[2]
    two <- nchar(y) == 2L; yi <- suppressWarnings(as.integer(if (two) paste0("20", y) else y))
    if (is.na(yi)) { out <- c(out, s); next }                                  # 판독 불가 = 막는다
    leak <- if (nm == "compact8") { d <- suppressWarnings(as.Date(sprintf("%s-%s-%s", g[2], g[3], g[4]))); is.na(d) || d > tau }
            else if (nm == "compact6") sprintf("%s-%s", g[2], g[3]) > tym
            else if (two) yi > ty && yi <= now_y                               # 두 자리 = 오늘 연도 이하만 연도로 읽는다
            else yi > ty
    if (isTRUE(leak)) out <- c(out, s)
  }
  unique(out)
}
RC_TESTWIN_KW_RX <- paste0("(?:시험\\s*(?:창|구간|기간)|강건성\\s*(?:시험|구간|창|기간)|(?:τ|tau)_?D\\s*(?:이후|뒤|다음|after)|정보\\s*경계\\s*(?:이후|뒤)|",
                           "(?<![A-Za-z])(?:OOS|oos)(?![A-Za-z])|(?i:out[- ]of[- ]sample)|(?i:hold[- ]?out)|홀드아웃|(?i:test\\s*(?:window|period))|",
                           "(?<![가-힣])전\\s*(?:기간|구간)|전체\\s*(?:기간|구간|표본|샘플)|검증\\s*(?:창|구간|기간)|(?i:full[- ]?(?:sample|period))|사후\\s*구간)")
## '보는 창'의 전 구간(τ_D 이전 창 전체)은 시험 창 · 전기간이 아니다 — 그 문맥만 키워드에서 뺀다(시험으로 고정)
RC_TESTWIN_VIS_RX <- "보는\\s*창(?:\\s*의)?\\s*(?:전체\\s*(?:기간|구간|표본|샘플)|전\\s*(?:기간|구간))"
## 문단 경계 — 빈 줄 · 마크다운 구조 줄의 시작(목록 · 인용 · 제목 · 표 · 번호 목록). 그 밖의 줄바꿈은 같은 문단(공백으로 본다)
RC_PARA_SPLIT_RX <- "\\n[ \\t]*\\n|\\n(?=[ \\t]*(?:[-*+>#|]|[0-9]+[.)][ \\t]))"
RC_TESTWIN_NUM_RX <- paste0("(?:(?<![A-Za-z0-9_.])[-+−]?[0-9]*\\.[0-9]+|(?<![A-Za-z0-9_.])[0-9]+(?:\\.[0-9]+)?\\s*%p?|(?<![A-Za-z0-9_.])[0-9]+\\s*/\\s*[0-9]+|",
                            "(?<![A-Za-z0-9_.])[0-9]+\\s*(?:건|회|번|차례|승|패|개(?!월)|위기|종목|종)|",
                            "(?<![A-Za-z])(?i:calmar|sharpe|sortino|cagr|mdd|port_t|dsr|pbo|sr|ic|t|s)\\s*[:=]?\\s*[-+−]?[0-9])")
## ③ 시험 창 수치 — 검사 단위 = 칸(cells 원소 하나) 안의 문단. 문단 안에 키워드와 수치가 함께 있으면 막는다(거리 · 줄바꿈 무관 · 11-10(3)).
##   반환 = 걸린 문단마다 '키워드 … 수치' 한 줄(사유 표시용).
.rc_testwin_hits <- function(cells) {
  out <- character(0)
  for (cell in as.character(cells)) {
    if (is.na(cell) || !nzchar(cell)) next
    ## 날짜 · 연도는 수치로 세지 않는다(그 판정은 ②) · '보는 창 전 구간'은 키워드가 아니다
    s <- gsub("(?<![0-9])(19|20)[0-9]{2}(-(0[1-9]|1[0-2])(-(0[1-9]|[12][0-9]|3[01]))?)?(?![0-9])", "§", cell, perl = TRUE)
    s <- gsub(RC_TESTWIN_VIS_RX, "보는 창", s, perl = TRUE)
    for (p in strsplit(s, RC_PARA_SPLIT_RX, perl = TRUE)[[1]]) {
      p <- gsub("[\r\n]+", " ", p)
      kw <- regmatches(p, regexpr(RC_TESTWIN_KW_RX, p, perl = TRUE))
      if (!length(kw)) next
      nm <- regmatches(p, regexpr(RC_TESTWIN_NUM_RX, p, perl = TRUE))
      if (length(nm)) out <- c(out, paste(kw, "…", nm))
    }
  }
  unique(out)
}
rc_input_issues <- function(x, tau, allow = character(0)) {
  tau <- tryCatch(as.Date(tau), error = function(e) as.Date(NA))
  if (length(tau) != 1L || is.na(tau)) return(list(ok = FALSE, leaks = character(0), grades = character(0), windows = character(0), why = "τ_D 판독 불가"))
  cells <- iconv(as.character(unlist(x)), from = "UTF-8", to = "UTF-8", sub = "")
  if (anyNA(cells[!is.na(as.character(unlist(x)))])) return(list(ok = FALSE, leaks = character(0), grades = character(0), windows = character(0), why = "인코딩 판독 불가"))
  cells <- cells[!is.na(cells)]
  for (a in as.character(allow)) if (!is.na(a) && nzchar(a)) cells <- gsub(a, " ", cells, fixed = TRUE)
  txt <- paste(cells, collapse = "\n")
  lk <- unique(c(rc_after_tau_leaks(txt, tau), .rc_year_hits(txt, tau)))
  gr <- .rc_grade_hits(txt)
  tw <- .rc_testwin_hits(cells)
  list(ok = !length(lk) && !length(gr) && !length(tw), leaks = c(lk, if (length(tw)) paste0("시험 창 수치: ", tw)), grades = gr, windows = tw,
       why = paste(c(if (length(lk)) paste("τ_D 뒤 날짜 · 연도", paste(head(lk, 5), collapse = ",")),
                     if (length(gr)) paste("등급 표기", paste(head(gr, 5), collapse = ",")),
                     if (length(tw)) paste("시험 창 · 전기간 수치", paste(head(tw, 5), collapse = ","))), collapse = " · "))
}

## 실행 시간 기록(속도 계획 5-1) — .cache/round_core/perf/<round>.jsonl 한 줄씩(동기화 밖 로컬 정션)
rc_perf_log <- function(round_id, stage, seconds, extra = list(), root = rc_root()) {
  d <- file.path(root, ".cache", "round_core", "perf"); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  rec <- c(list(at = rc_now(), round = round_id, stage = stage, seconds = round(as.numeric(seconds), 3), core = RC_VERSION), extra)
  cat(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = NA), "\n", sep = "", file = file.path(d, paste0(round_id, ".jsonl")), append = TRUE)
  invisible(rec)
}
rc_timed <- function(round_id, stage, expr, root = rc_root()) {
  t0 <- Sys.time(); v <- force(expr)
  rc_perf_log(round_id, stage, difftime(Sys.time(), t0, units = "secs"), root = root)
  v
}

## JSON 경로 참조 해석 — "<파일>::<a.b.c>" (수치 근거를 정본 설정에서 읽는다 · 하드코딩 금지)
rc_ref_value <- function(ref, root = rc_root()) {
  parts <- strsplit(ref, "::", fixed = TRUE)[[1]]
  if (length(parts) != 2L) stop("[round_core] 참조 형식은 '<파일>::<키 경로>': ", ref)
  x <- rc_json_read(rc_abs(parts[1], root))
  for (k in strsplit(parts[2], ".", fixed = TRUE)[[1]]) {
    if (is.null(x[[k]])) stop("[round_core] 참조 키 없음: ", ref)
    x <- x[[k]]
  }
  x
}
