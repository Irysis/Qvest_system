## =============================================================================
## template_diff_check.R — DT_2002_06975 템플릿 · 생성 엔진 차분 대조 (P2R05 · precheck 가 부른다 · 실패 = 종료 코드 1 + 위치 출력)
##
##   (i)  템플릿 대 원본 engine.R — 템플릿은 원본에서 표지 구역이 선언한 원본 행 범위만 바꾼 것이어야 한다.
##        표지: '## >>> DT_ZONE <이름> orig=a-b'(원본 a~b 행 대체) 또는 'orig=+a'(원본 a 행 뒤 삽입 · a = 0 이면 맨 앞) … '## <<< DT_ZONE <이름>'.
##        대조 = 원본 행을 순서대로 옮기며 각 구역 자리에 템플릿의 구역 블록(표지 포함)을 끼워 재구성한 결과가 템플릿과 바이트 동일한가.
##        → 구역 밖 차분 0 을 기계로 단정한다(구역은 겹치지 않고 원본 행 순서대로 · 이름 유일 · 중첩 없음 · 마지막 줄바꿈 여부 같음).
##        + 원본 md5 = 템플릿 머리말 'DT_SOURCE_MD5' (원본이 바뀌면 템플릿이 가리키는 판이 아니다)
##        + 보호 범위(아래 PROTECT — 특징 · 표적 · 창 · 일정 · 시드 · 유니버스 · 전처리 · PIT 단언 · 학습 수치 경로)의 원본 행을 대체하는 구역 0.
##          보호 범위 안 삽입 구역은 허용하되 목록에 '보호 범위 안 삽입'으로 표시한다(읽기 전용 계산인지 사람이 본다).
##   (ii) 생성 엔진 7개(engine_{Q50,V1,V2,N1,N2,S1,S2}.R) 대 템플릿 — 줄 수 같음 · 다른 줄 정확히 1줄 = 템플릿 '.DT_RULE <- "TEMPLATE"' →
##        '.DT_RULE <- "<파일 이름의 규칙>"' · 나머지 바이트 동일 · 디렉터리에 다른 engine_*.R 없음.
##   (iii) RX0S(rx0s/engine_RX0S.R — 원본 평균 엔진 rev3 재시드 · P2R05 시드 띠 · 판단 T1 C-20261018-054) 대 원본 engine.R —
##        줄 수 같음 · 다른 줄 = 아래 RX0S_SUBST 의 원본 행(48 꼬리표 · 72 시드 기저 · 101 작업 디렉터리)뿐 · 각 줄 = 원본 줄에서 그 부분 문자열만 치환.
##        101 행이 필요한 까닭: 원본 .WD 는 파일 위치가 아니라 루트 기준 고정 경로(…/RP_AUTO_2002_06975/_work)라, 바꾸지 않으면 원본 _work/cache 에 쓴다.
##   (iv) engines_manifest.json 의 md5(템플릿 · 생성기 · 생성 7개 · RX0S · 원본 engine.R) = 현재 파일 md5.
##
## 실행: Rscript template_diff_check.R [--json <출력 경로>] [--root <프로젝트 루트>]
##       source() 하면 함수만 정의된다(dt_template_diff_check(root) → list(ok, errors, zones, engines, ...)).
## =============================================================================
suppressPackageStartupMessages(library(jsonlite))

DT_RULES <- c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")
DT_RULE_LINE_TEMPLATE <- '.DT_RULE <- "TEMPLATE"'
## RX0S 정의(생성기 make_engines.R 도 이 정의를 쓴다) — 원본 engine.R 행 번호 · 그 줄 안에서 바꾸는 부분 문자열(정확히 1회)
RX0S_REL <- file.path("rx0s", "engine_RX0S.R")
RX0S_SEED_BASE <- 20261018L
RX0S_SUBST <- list(
  list(line = 48L,  what = "로그 꼬리표",   old = '"[RP_AUTO_2002_06975]"',          new = '"[DT_2002_06975:RX0S]"'),
  list(line = 72L,  what = "시드 기저",     old = ".SEED_BASE <- 20020697L",          new = sprintf(".SEED_BASE <- %dL", RX0S_SEED_BASE)),
  list(line = 101L, what = "작업 디렉터리", old = '"RP_AUTO_2002_06975", "_work")', new = '"DT_2002_06975", "rx0s", "_work")'))
## 원본 줄들 → RX0S 줄들(각 치환 대상이 그 줄에 정확히 1회 있어야 한다 · 없으면 stop)
dt_rx0s_lines <- function(orig_lines) {
  out <- orig_lines
  for (s in RX0S_SUBST) {
    ln <- orig_lines[s$line]
    n <- lengths(regmatches(ln, gregexpr(s$old, ln, fixed = TRUE, useBytes = TRUE)))
    if (is.na(ln) || n != 1L) stop(sprintf("[RX0S] 원본 %d행(%s)에 치환 대상 '%s' 가 %d회 — 1회여야 한다", s$line, s$what, s$old, n))
    out[s$line] <- sub(s$old, s$new, ln, fixed = TRUE, useBytes = TRUE)
  }
  out
}
## 보호 범위 — 원본 engine.R(md5 6b6a8e1a144b4b316c28628b0de7f95d) 행 번호. 어떤 구역도 이 행을 대체하지 않는다.
PROTECT <- list(
  c(42L, 47L),   c(49L, 53L),   c(58L, 82L),                     # 적재 · RAWDATA 단언 · 필수 열 · 상수(특징 창 · 표적 수평 · 학습 창 · 갱신 격자 · 5분위 · 시작 · 앵커 · 시드 기저 · 특징 목록)
  c(102L, 126L),                                                 # 실행 작업본 · 48시간 정리 · 파이썬 탐침
  c(131L, 183L),                                                 # 전처리 헬퍼(순위 재척도 · 결측 0.5) + R 양성 대조
  c(185L, 423L),                                                 # 격자 · 유니버스(MEM) · 가격/거래대금 특징 · 표적 · 컨센서스 · 일정 · 시드 · 회계 특징 · 순위 재척도 · 패널
  c(431L, 445L), c(447L, 469L), c(471L, 481L),                   # 파이썬: 가져오기 · 모델 상수(층 · dropout · epoch · 배치 · lr · BN) · 장치 · 몸통 · 초기화
  c(483L, 491L), c(493L, 508L), c(510L, 517L),                   # fit_predict: 시드 · 생성기 · 미니배치 순서 · 옵티마이저 · 학습 반복 · 예측(손실 2행 제외)
  c(520L, 568L),                                                 # 특징 이름 · 패널 적재 · 학습 집합 선택(창) · 캐시 키(명세 접미 삽입만 허용)
  c(592L, 604L),                                                 # run_task 앞부분: 선택 · PIT 단언(max_lab_i ≤ u_i) · 키 · 캐시 조회
  c(656L, 662L),                                                 # 처리 순서 회전 · 워커 수
  c(706L, 720L), c(722L, 730L), c(733L, 734L),                   # 스크립트 기록 · 실행 · 산출 적재 · diag 형 변환 · PIT/창 재단언 · 입력 차원
  c(736L, 775L), c(788L, 791L))                                  # 조립 · 검산 · 정리 · 산출 열

.dtc_find_root <- function(arg_root = NULL) {
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[startsWith(ca, "--file=")])
  from_file <- if (length(f)) normalizePath(file.path(dirname(f[1]), "..", "..", ".."), winslash = "/", mustWork = FALSE) else ""
  cands <- c(arg_root %||% "", Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""), from_file,
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  for (p in cands) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, marker))) return(p)
  }
  stop("[template_diff_check] 프로젝트 루트를 찾지 못함(표지 ", marker, ")")
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## 바이트 그대로 읽기 — LF 로만 나눈다(CR 은 줄 내용에 남아 차분으로 드러난다). 두 파일을 같은 함수로 읽으므로 인코딩 표식이 같다.
.dtc_read <- function(p) {
  if (!file.exists(p)) stop("파일 없음: ", p)
  sz <- file.info(p)$size
  r <- if (sz > 0) readBin(p, "raw", sz) else raw(0)
  txt <- rawToChar(r)
  Encoding(txt) <- "bytes"
  list(lines = if (nchar(txt, type = "bytes") == 0L) character(0) else strsplit(txt, "\n", fixed = TRUE, useBytes = TRUE)[[1]],
       final_nl = length(r) > 0L && r[length(r)] == as.raw(10L), md5 = unname(as.character(tools::md5sum(p))))
}
.dtc_show <- function(x) { x <- iconv(x, from = "UTF-8", to = "UTF-8", sub = "?"); if (is.na(x)) "<비 UTF-8>" else substr(x, 1L, 160L) }

## 템플릿의 구역 파싱 — list(zones = data.frame, errors)
.dtc_parse_zones <- function(tl) {
  st_re <- "^## >>> DT_ZONE ([A-Za-z0-9_]+) orig=(\\+[0-9]+|[0-9]+-[0-9]+)$"
  en_re <- "^## <<< DT_ZONE ([A-Za-z0-9_]+)$"
  errs <- character(0); Z <- list(); open <- NULL
  for (i in seq_along(tl)) {
    ln <- tl[i]
    if (!grepl("DT_ZONE", ln, fixed = TRUE, useBytes = TRUE)) next
    if (!grepl("^\\s*#+\\s*(>>>|<<<)", ln, useBytes = TRUE)) next          # 표지 후보 = 주석 기호 뒤 바로 >>> / <<< (설명 문장 속 언급은 표지가 아니다)
    if (grepl("^\\s*## >>> DT_ZONE", ln, useBytes = TRUE)) {
      if (!grepl(st_re, ln, useBytes = TRUE)) { errs <- c(errs, sprintf("템플릿 %d행: 시작 표지 형식 위반: %s", i, .dtc_show(ln))); next }
      if (!is.null(open)) { errs <- c(errs, sprintf("템플릿 %d행: 구역 %s 가 닫히기 전에 새 구역 시작(중첩 금지)", i, open$name)); next }
      nm <- sub(st_re, "\\1", ln, useBytes = TRUE); sp <- sub(st_re, "\\2", ln, useBytes = TRUE)
      if (startsWith(sp, "+")) { a <- as.integer(substring(sp, 2L)); from <- a + 1L; to <- a; kind <- "insert" }
      else { ab <- as.integer(strsplit(sp, "-", fixed = TRUE)[[1]]); from <- ab[1]; to <- ab[2]; kind <- "replace" }
      open <- list(name = nm, spec = sp, kind = kind, from = from, to = to, start = i)
    } else if (grepl("^\\s*## <<< DT_ZONE", ln, useBytes = TRUE)) {
      if (!grepl(en_re, ln, useBytes = TRUE)) { errs <- c(errs, sprintf("템플릿 %d행: 끝 표지 형식 위반: %s", i, .dtc_show(ln))); next }
      nm <- sub(en_re, "\\1", ln, useBytes = TRUE)
      if (is.null(open)) { errs <- c(errs, sprintf("템플릿 %d행: 열리지 않은 구역 %s 의 끝 표지", i, nm)); next }
      if (!identical(nm, open$name)) { errs <- c(errs, sprintf("템플릿 %d행: 끝 표지 이름 %s ≠ 시작 %s", i, nm, open$name)); next }
      open$end <- i; Z[[length(Z) + 1L]] <- open; open <- NULL
    } else {
      errs <- c(errs, sprintf("템플릿 %d행: 표지 형식 위반(표지는 줄 맨 앞 '## >>> DT_ZONE' / '## <<< DT_ZONE' 만): %s", i, .dtc_show(ln)))
    }
  }
  if (!is.null(open)) errs <- c(errs, sprintf("구역 %s(템플릿 %d행)이 닫히지 않았다", open$name, open$start))
  zd <- if (length(Z)) do.call(rbind, lapply(Z, function(z) data.frame(name = z$name, spec = z$spec, kind = z$kind, from = z$from, to = z$to,
                                                                     start = z$start, end = z$end, stringsAsFactors = FALSE))) else
          data.frame(name = character(0), spec = character(0), kind = character(0), from = integer(0), to = integer(0), start = integer(0), end = integer(0))
  if (anyDuplicated(zd$name)) errs <- c(errs, paste("구역 이름 중복:", paste(unique(zd$name[duplicated(zd$name)]), collapse = ", ")))
  list(zones = zd, errors = errs)
}

## dt_dir · source_engine = 시험용(tests/diff_check_mutation_test.R 가 사본 디렉터리로 양방향 검사) — 기본 = 정본 위치
dt_template_diff_check <- function(root = NULL, dt_dir = NULL, source_engine = NULL) {
  root <- .dtc_find_root(root)
  dd <- dt_dir %||% file.path(root, "04_Research", "strategies", "DT_2002_06975")
  orig_p <- source_engine %||% file.path(root, "04_Research", "strategies", "RP_AUTO_2002_06975", "engine.R")
  tmpl_p <- file.path(dd, "engine_template.R")
  errs <- character(0); notes <- character(0)
  O <- .dtc_read(orig_p); Tm <- .dtc_read(tmpl_p)
  N <- length(O$lines)
  ## ── (i) 템플릿 대 원본 ──
  src <- grep("^# DT_SOURCE_MD5 [0-9a-f]{32}$", Tm$lines, value = TRUE, useBytes = TRUE)
  if (length(src) != 1L) errs <- c(errs, sprintf("템플릿 머리말 DT_SOURCE_MD5 줄이 %d개 — 1개여야 한다", length(src)))
  else if (!identical(sub("^# DT_SOURCE_MD5 ", "", src), O$md5))
    errs <- c(errs, sprintf("원본 engine.R md5 %s ≠ 템플릿 DT_SOURCE_MD5 %s — 원본이 바뀌었거나 다른 판의 사본", O$md5, sub("^# DT_SOURCE_MD5 ", "", src)))
  pz <- .dtc_parse_zones(Tm$lines); errs <- c(errs, pz$errors); Z <- pz$zones
  rec <- character(0); ptr <- 1L; zrep <- list()
  for (j in seq_len(nrow(Z))) {
    z <- Z[j, ]
    bad_rng <- (z$kind == "replace" && !(z$from >= 1L && z$to >= z$from && z$to <= N)) || (z$kind == "insert" && !(z$to >= 0L && z$to <= N))
    if (bad_rng) { errs <- c(errs, sprintf("구역 %s: 원본 행 범위 orig=%s 가 원본(1~%d행) 밖", z$name, z$spec, N)); next }
    if (z$from < ptr) { errs <- c(errs, sprintf("구역 %s: orig=%s 가 앞 구역과 겹치거나 순서가 거꾸로다(원본 %d행부터여야 한다)", z$name, z$spec, ptr)); next }
    if (z$from > ptr) rec <- c(rec, O$lines[ptr:(z$from - 1L)])
    rec <- c(rec, Tm$lines[z$start:z$end])
    hit <- character(0)
    if (z$kind == "replace") for (pr in PROTECT) if (z$from <= pr[2] && z$to >= pr[1]) hit <- c(hit, sprintf("%d-%d", pr[1], pr[2]))
    ins_in <- z$kind == "insert" && any(vapply(PROTECT, function(pr) z$to >= pr[1] && z$to < pr[2], logical(1)))
    if (length(hit)) errs <- c(errs, sprintf("구역 %s: 보호 범위 %s 의 원본 행을 대체한다(orig=%s)", z$name, paste(hit, collapse = ","), z$spec))
    zrep[[length(zrep) + 1L]] <- list(name = z$name, orig = z$spec, kind = z$kind, template_lines = sprintf("%d-%d", z$start, z$end),
                                      n_orig_replaced = if (z$kind == "replace") z$to - z$from + 1L else 0L,
                                      n_zone_lines = z$end - z$start - 1L, insert_inside_protected = ins_in,
                                      replaced = if (z$kind == "replace") vapply(O$lines[z$from:z$to], .dtc_show, "", USE.NAMES = FALSE) else character(0))
    if (ins_in) notes <- c(notes, sprintf("구역 %s(orig=%s): 보호 범위 안 삽입 — 읽기 전용 계산인지 확인 대상", z$name, z$spec))
    ptr <- z$to + 1L
  }
  if (ptr <= N) rec <- c(rec, O$lines[ptr:N])
  same_len <- length(rec) == length(Tm$lines)
  k <- which(rec[seq_len(min(length(rec), length(Tm$lines)))] != Tm$lines[seq_len(min(length(rec), length(Tm$lines)))])
  if (length(k) || !same_len) {
    i <- if (length(k)) k[1] else min(length(rec), length(Tm$lines)) + 1L
    errs <- c(errs, sprintf("구역 밖 차분 — 템플릿 %d행(재구성 %d행 · 템플릿 %d행): 기대 '%s' · 실제 '%s'", i, length(rec), length(Tm$lines),
                            if (i <= length(rec)) .dtc_show(rec[i]) else "<끝>", if (i <= length(Tm$lines)) .dtc_show(Tm$lines[i]) else "<끝>"))
  }
  if (!identical(O$final_nl, Tm$final_nl)) errs <- c(errs, "마지막 줄바꿈 여부가 원본과 다르다")
  ## ── (ii) 생성 엔진 대 템플릿 ──
  rl <- which(Tm$lines == DT_RULE_LINE_TEMPLATE)
  if (length(rl) != 1L) errs <- c(errs, sprintf("템플릿의 규칙 줄 '%s' 가 %d개 — 1개여야 한다", DT_RULE_LINE_TEMPLATE, length(rl)))
  else if (!any(Z$start < rl & Z$end > rl & Z$name == "ident")) errs <- c(errs, "템플릿의 규칙 줄이 구역 ident 안에 없다")
  ex <- list.files(dd, pattern = "^engine_.*\\.R$")
  extra <- setdiff(ex, c("engine_template.R", sprintf("engine_%s.R", DT_RULES)))
  if (length(extra)) errs <- c(errs, paste("예정에 없는 엔진 파일:", paste(extra, collapse = ", ")))
  eng <- list()
  for (r in DT_RULES) {
    p <- file.path(dd, sprintf("engine_%s.R", r))
    if (!file.exists(p)) { errs <- c(errs, sprintf("생성 엔진 없음: engine_%s.R", r)); next }
    E <- .dtc_read(p)
    if (length(E$lines) != length(Tm$lines)) { errs <- c(errs, sprintf("engine_%s.R: 줄 수 %d ≠ 템플릿 %d", r, length(E$lines), length(Tm$lines))); next }
    dk <- which(E$lines != Tm$lines)
    want <- sprintf('.DT_RULE <- "%s"', r)
    ok <- length(rl) == 1L && identical(dk, rl) && identical(E$lines[rl], want) && identical(E$final_nl, Tm$final_nl)
    if (!ok) errs <- c(errs, sprintf("engine_%s.R: 템플릿과 다른 줄 %d개(%s) — 규칙 줄(템플릿 %s행) 하나만 '%s' 로 달라야 한다%s", r, length(dk),
                                     paste(utils::head(dk, 5L), collapse = ","), if (length(rl) == 1L) rl else "?", want,
                                     if (length(dk)) sprintf(" · 첫 차이 %d행: '%s'", dk[1], .dtc_show(E$lines[dk[1]])) else ""))
    eng[[r]] <- list(file = basename(p), md5 = E$md5, n_diff_lines = length(dk), rule_line = if (length(rl) == 1L) rl else NA_integer_, ok = ok)
  }
  ## ── (iii) RX0S 대 원본 ──
  rx_p <- file.path(dd, RX0S_REL); rx <- NULL
  rx_extra <- setdiff(list.files(dirname(rx_p), pattern = "^engine_.*\\.R$"), basename(rx_p))
  if (length(rx_extra)) errs <- c(errs, paste("rx0s/ 에 예정에 없는 엔진 파일:", paste(rx_extra, collapse = ", ")))
  if (!file.exists(rx_p)) errs <- c(errs, sprintf("RX0S 엔진 없음: %s", RX0S_REL))
  else {
    X <- .dtc_read(rx_p)
    want <- tryCatch(dt_rx0s_lines(O$lines), error = function(e) { errs <<- c(errs, conditionMessage(e)); NULL })
    if (!is.null(want)) {
      if (length(X$lines) != length(O$lines)) errs <- c(errs, sprintf("RX0S: 줄 수 %d ≠ 원본 %d", length(X$lines), N))
      else {
        dk <- which(X$lines != O$lines)
        exp_k <- vapply(RX0S_SUBST, function(s) s$line, integer(1))
        if (!identical(dk, exp_k)) errs <- c(errs, sprintf("RX0S: 원본과 다른 줄 %s — %s 행(%s)뿐이어야 한다%s", paste(utils::head(dk, 8L), collapse = ","),
                                                         paste(exp_k, collapse = ","), paste(vapply(RX0S_SUBST, function(s) s$what, ""), collapse = " · "),
                                                         if (length(setdiff(dk, exp_k))) sprintf(" · 예정 밖 첫 차이 %d행: '%s'", setdiff(dk, exp_k)[1], .dtc_show(X$lines[setdiff(dk, exp_k)[1]])) else ""))
        bad_k <- exp_k[X$lines[exp_k] != want[exp_k]]
        if (length(bad_k)) errs <- c(errs, sprintf("RX0S: %s 행이 '원본 줄의 부분 문자열만 치환' 과 다르다(첫 %d행: '%s')", paste(bad_k, collapse = ","), bad_k[1], .dtc_show(X$lines[bad_k[1]])))
      }
      if (!identical(X$final_nl, O$final_nl)) errs <- c(errs, "RX0S: 마지막 줄바꿈 여부가 원본과 다르다")
    }
    rx <- list(file = RX0S_REL, md5 = X$md5, n_diff_lines = if (length(X$lines) == N) length(which(X$lines != O$lines)) else NA_integer_,
               diff_lines = vapply(RX0S_SUBST, function(s) s$line, integer(1)), seed_base = RX0S_SEED_BASE,
               changes = lapply(RX0S_SUBST, function(s) list(line = s$line, what = s$what, old = s$old, new = s$new)))
  }
  ## ── (iv) 매니페스트 ──
  mf <- file.path(dd, "engines_manifest.json"); man <- NULL
  if (!file.exists(mf)) errs <- c(errs, "engines_manifest.json 없음 — make_engines.R 을 실행하지 않았다")
  else {
    man <- tryCatch(fromJSON(mf, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(man)) errs <- c(errs, "engines_manifest.json 판독 실패")
    else {
      chk <- c(list(list(path = man$template$path, md5 = man$template$md5), list(path = man$generator$path, md5 = man$generator$md5),
                    list(path = man$source_engine$path, md5 = man$source_engine$md5), list(path = man$rx0s$path, md5 = man$rx0s$md5)),
               lapply(man$engines %||% list(), function(e) list(path = e$path, md5 = e$md5)))
      if (length(man$engines %||% list()) != length(DT_RULES)) errs <- c(errs, sprintf("매니페스트 엔진 수 %d ≠ %d", length(man$engines %||% list()), length(DT_RULES)))
      for (c0 in chk) {
        p <- file.path(root, c0$path %||% "")
        cur <- if (nzchar(c0$path %||% "") && file.exists(p)) unname(as.character(tools::md5sum(p))) else NA_character_
        if (!identical(cur, c0$md5 %||% "")) errs <- c(errs, sprintf("매니페스트 md5 불일치: %s (기록 %s · 현재 %s)", c0$path %||% "?", c0$md5 %||% "?", cur))
      }
    }
  }
  list(ok = !length(errs), errors = errs, notes = notes, root = root,
       source_engine = list(path = "04_Research/strategies/RP_AUTO_2002_06975/engine.R", md5 = O$md5, n_lines = N),
       template = list(path = "04_Research/strategies/DT_2002_06975/engine_template.R", md5 = Tm$md5, n_lines = length(Tm$lines)),
       n_zones = nrow(Z), zones = zrep, engines = eng, rx0s = rx,
       manifest = if (is.null(man)) NULL else list(generated_at = man$generated_at %||% NA))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  jout <- if ("--json" %in% args) args[which(args == "--json") + 1L] else NA_character_
  aroot <- if ("--root" %in% args) args[which(args == "--root") + 1L] else NULL
  res <- tryCatch(dt_template_diff_check(aroot), error = function(e) list(ok = FALSE, errors = paste("실행 오류:", conditionMessage(e)), zones = list(), engines = list(), notes = character(0)))
  for (z in res$zones) cat(sprintf("[template_diff_check] 구역 %-18s orig=%-8s 템플릿 %-9s 원본 대체 %3d행 · 구역 내용 %3d행%s\n", z$name, z$orig, z$template_lines,
                                   as.integer(z$n_orig_replaced), as.integer(z$n_zone_lines), if (isTRUE(z$insert_inside_protected)) " · 보호 범위 안 삽입" else ""))
  for (e in res$engines) cat(sprintf("[template_diff_check] %-14s md5 %s · 템플릿과 다른 줄 %d(규칙 줄 %s행) · %s\n", e$file, e$md5, as.integer(e$n_diff_lines),
                                     as.character(e$rule_line), if (isTRUE(e$ok)) "일치" else "불일치"))
  if (!is.null(res$rx0s)) cat(sprintf("[template_diff_check] %-14s md5 %s · 원본 engine.R 과 다른 줄 %s(%s — 꼬리표 · 시드 기저 %d · 작업 디렉터리)\n",
                                      basename(res$rx0s$file), res$rx0s$md5, as.character(res$rx0s$n_diff_lines),
                                      paste(res$rx0s$diff_lines, collapse = "·"), as.integer(res$rx0s$seed_base)))
  for (n0 in res$notes) cat("[template_diff_check] 참고 — ", n0, "\n", sep = "")
  if (!is.na(jout)) writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), jout, useBytes = TRUE)
  if (isTRUE(res$ok)) {
    cat(sprintf("[template_diff_check] 통과 — 구역 %d개 밖 원본과 바이트 동일(원본 md5 %s) · 보호 범위 대체 0 · 생성 엔진 %d개 = 템플릿 + 규칙 줄 1줄 · RX0S = 원본 + %d줄(꼬리표 · 시드 · 작업 디렉터리) · 매니페스트 md5 일치\n",
                as.integer(res$n_zones), res$source_engine$md5, length(res$engines), as.integer(res$rx0s$n_diff_lines %||% NA)))
    quit(status = 0L)
  }
  cat("[template_diff_check] 실패:\n", paste0("  · ", res$errors, collapse = "\n"), "\n", sep = "")
  quit(status = 1L)
}
