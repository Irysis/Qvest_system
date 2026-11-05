## P2R05 분위 DNN 엔진(04_Research/strategies/DT_2002_06975) 검사 — 단일 정의. register.R(--draft · --register) · precheck.R(--dry · --warm · 본 대조) ·
##   warm_engine.R 이 같은 함수를 쓴다(사전등록 평가 경로 핀 대상). 엔진 파일은 다른 구현 에이전트(A) 소관 — 이 파일은 읽고 대조만 한다(쓰기 없음).
##   (i)   템플릿 차분 대조 — template_diff_check.R 종료 코드 0(DESIGN §3.1 '차분은 지정 구역에만')
##   (ii)  생성 엔진 7개 md5 = engines_manifest.json 기록 = (있으면) 사전등록 핀
##   (iii) 정적 PIT — lookahead_detector::detect_lookahead(clean = TRUE 만 통과 · NA = 미스캔 = 실패 · 10-17 '비싼 실행 뒤 주석 오탐' 교훈으로 워밍 전에)
##   (iv)  엔진끼리 차이 = 규칙 상수 한 줄(.DT_RULE <- "<규칙>")뿐 · 그 값 = 파일 이름의 규칙 · 줄 위치 같음(DESIGN §7.1)
##   (v)   CODE_VERSION 7개 동일 = DESIGN §7.2 · §12 판본 식별자(평균 표적 rev3 키와 절대 충돌하지 않는 새 판본)
##   (vi)  규칙 상수(.DT_TAUS · .DT_VETO_SHARE · .DT_PERM_SEED · .DT_SIGMA_WIN · .DT_SIGMA_MIN) 판독 · 7개 동일 — 값은 기록(사전등록이 정본 · 이 파일에 숫자를 박지 않는다)
##   (vii) 양성 대조 · 뮤테이션 리허설 요약(positive_control_rehearsal.json · DESIGN §3.3) — pass ∧ 기록된 뮤테이션 전부 잡힘 ∧ template_md5 = 현 템플릿
##   (viii) 재시드 짝 엔진(engine_RX0S.R · 판단 T1 R-20261018-007 수용 · 조정자 10-18) — 원본 RX0 engine.R 과 줄 수 같음 · 다른 줄 = .SEED_BASE 대입 줄(정확히 1) +
##          식별자 줄(.TAG · .WD)만 · 다른 줄 번호 = 매니페스트 신고 줄 · CODE_VERSION 같음 · md5 = 매니페스트 = (있으면) 사전등록 핀 · 정적 PIT ·
##          경로 = 매니페스트의 engine_RX0S.R(없으면 DT_2002_06975/rx0s/engine_RX0S.R)
##   + 파이썬 판(venv torch · numpy · pandas · pyarrow — 기록 · 사전등록 뒤 바뀌면 precheck 가 멈춘다)
## 통합 계약(에이전트 A 산출물에 기대는 것 — 이름이 다르면 이 파일의 상수 한 곳만 고친다): 파일 이름(FILES · engine_<규칙>.R) · .DT_RULE 대입 줄 ·
##   파이썬 원문의 CODE_VERSION = "…" 줄 · 상수 대입 줄(.DT_TAUS <- c(…) 형식) · 매니페스트가 엔진 파일 이름과 md5(32자 16진)를 한 객체 또는 이름 키로 짝지음 ·
##   리허설 요약 필드 pass · mutations[{name, caught|failed|detected}] · template_md5
suppressPackageStartupMessages(library(jsonlite))
P2R05_DTC <- local({
  DT_DIR <- "04_Research/strategies/DT_2002_06975"
  RULES <- c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")
  FILES <- c(template = "engine_template.R", generator = "make_engines.R", diff_check = "template_diff_check.R",
             manifest = "engines_manifest.json", pc_rehearsal = "positive_control_rehearsal.json")
  CODE_VERSION <- "DT_2002_06975/dnn_quantile/rev1"                              # DESIGN §7.2 · §12 — 식별자(수치 결정 아님)
  CONST_NAMES <- c(".DT_TAUS", ".DT_VETO_SHARE", ".DT_PERM_SEED", ".DT_SIGMA_WIN", ".DT_SIGMA_MIN")   # DESIGN §12 상수 이름
  WORK <- paste0(DT_DIR, "/_work"); CACHE_DIR <- paste0(WORK, "/cache"); QPRED_DIR <- paste0(WORK, "/qpred")
  DETECTOR <- "02_Infrastructure/validation/lookahead_detector.R"
  ## 재시드 짝 엔진(판단 T1 R-20261018-007 · C-054 · 055 · 056 수용 · 조정자 10-18) — 원본 RX0 엔진과 .SEED_BASE 한 줄만 다른 사본. 경로 = 매니페스트(있으면) · 없으면 기본값
  RX0_SRC <- "04_Research/strategies/RP_AUTO_2002_06975/engine.R"
  RX0S_DEFAULT <- paste0(DT_DIR, "/rx0s/engine_RX0S.R")
  SEED_RX <- "^\\s*\\.SEED_BASE\\s*<-"
  ## DT 엔진 시험 증거(격리 점검 v1 권고 9 — 사전등록 tests_dt 에 md5 · 통과 수로 핀) · test_summary.json 은 마지막 --fast 판이라 느린 시험은 각 결과 파일로 핀한다
  ##   정적 PIT(engine_checks static_pit)는 .R 만 보므로 내장 파이썬 검사의 증거는 static_pit_results.json(추출 파이썬 포함)뿐이다(DT README §9 항목 13)
  RNG_FACTS <- paste0(DT_DIR, "/tests/_out/rng_stream_facts.json")
  TEST_EVIDENCE <- c(paste0(DT_DIR, "/tests/_out/", c("rule_smoke_results.json", "diff_check_mutation_results.json", "static_pit_results.json", "py_e2e_results.json",
                                                      "engine_dryrun_results.json", "pc_mutation_results.json", "rng_stream_facts.json", "template_diff_check.json")),
                     paste0(DT_DIR, "/README.md"))                              # README §7 = 공통 난수 사실 문장(reseed.note 근거)
  RULE_RX <- '^\\s*\\.DT_RULE\\s*<-\\s*"([A-Za-z0-9]+)"'
  CV_RX <- '^CODE_VERSION\\s*=\\s*"([^"]+)"'                                    # 줄 머리 고정 — 파이썬 최상위 대입 줄만(R 쪽 sub('^CODE_VERSION = "…') 정규식 문자열을 잡지 않게)
  .or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  md5f <- function(f) if (file.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_
  cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  rd_lines <- function(f) sub("\r$", "", readLines(f, warn = FALSE, encoding = "UTF-8"))
  rel_engine <- function(rule) sprintf("%s/engine_%s.R", DT_DIR, rule)
  rel_file <- function(key) paste0(DT_DIR, "/", FILES[[key]])
  ## 재시드 엔진 경로 — 매니페스트 안에서 engine_RX0S.R 로 끝나는 path 문자열(형식 가정 없이 걷는다) · 없으면 기본값
  rx0s_rel <- function(root) {
    man <- tryCatch(jsonlite::fromJSON(file.path(root, rel_file("manifest")), simplifyVector = FALSE), error = function(e) NULL)
    hit <- character(0)
    walk <- function(node) if (is.list(node)) for (v in node) {
      if (is.character(v) && length(v) == 1L && grepl("(^|/)engine_RX0S\\.R$", v, perl = TRUE)) hit <<- c(hit, v)
      if (is.list(v)) walk(v) }
    walk(man)
    hit <- unique(sub("^\\./", "", gsub("\\\\", "/", hit)))
    if (length(hit) == 1L) hit else RX0S_DEFAULT
  }
  all_rel <- function(root = NULL) c(unname(vapply(names(FILES), rel_file, "")), unname(vapply(RULES, rel_engine, "")), if (!is.null(root)) rx0s_rel(root) else RX0S_DEFAULT)
  ## 운영 경로 핀(사전등록 operational_pins$files 에 든다 — evaluate.R 의 핀 대조가 평가 시작부에서 재대조) · 리허설 요약은 engines 절에만(평가 경로 밖)
  ops_rel <- function(root = NULL) c(rel_file("template"), rel_file("generator"), rel_file("diff_check"), rel_file("manifest"), unname(vapply(RULES, rel_engine, "")),
                                     if (!is.null(root)) rx0s_rel(root) else RX0S_DEFAULT)
  inventory <- function(root) { f <- all_rel(root); ex <- file.exists(file.path(root, f)); list(present = f[ex], missing = f[!ex]) }
  ## 재시드 엔진 검사 — 원본 RX0 엔진과 줄 수 같음 · 다른 줄 = .SEED_BASE 대입 줄(필수 · 정확히 1) + 식별자 줄만(.TAG 로그 꼬리표 · .WD 작업 디렉터리 — 수치 경로 밖 ·
  ##   계산 결과 무관 · 캐시 키는 내용 주소) · 다른 줄 번호 = 매니페스트 rx0s.changes 신고 줄(있으면) · CODE_VERSION 같음(같은 평균 표적 캐시 판 · 시드가 키를 가른다)
  ##   ★조정자 계약 문장은 '시드 한 줄'이었고 구현(에이전트 A · 10-18 17:36)은 식별자 2줄을 더 바꿔 매니페스트에 신고했다 — 식별자 줄 밖의 차이는 하나라도 실패(통합 때 Q 확인 사항)
  ID_RX <- "^\\s*\\.(TAG|WD)\\s*<-"
  rx0s_check <- function(root) {
    rel <- rx0s_rel(root); f <- file.path(root, rel); o <- file.path(root, RX0_SRC)
    out <- list(path = rel, md5 = md5f(f), source = list(path = RX0_SRC, md5 = md5f(o)))
    if (!file.exists(f)) return(c(out, list(ok = FALSE, errors = paste("재시드 엔진 없음:", rel))))
    a <- rd_lines(o); b <- rd_lines(f); e <- character(0)
    if (length(a) != length(b)) e <- c(e, sprintf("engine_RX0S.R 줄 수 %d ≠ 원본 %d", length(b), length(a)))
    else {
      d <- which(a != b)
      sd <- d[grepl(SEED_RX, a[d], perl = TRUE) & grepl(SEED_RX, b[d], perl = TRUE)]
      idl <- d[grepl(ID_RX, a[d], perl = TRUE) & grepl(ID_RX, b[d], perl = TRUE)]
      other <- setdiff(d, c(sd, idl))
      if (length(sd) != 1L) e <- c(e, sprintf("engine_RX0S.R 과 원본의 .SEED_BASE 대입 줄 차이 %d개(정확히 1이어야 한다)", length(sd)))
      if (length(other)) e <- c(e, sprintf("engine_RX0S.R 과 원본이 시드 · 식별자(.TAG · .WD) 밖 %d줄에서 다르다(%s행)", length(other), paste(utils::head(other, 5L), collapse = ",")))
      man <- tryCatch(jsonlite::fromJSON(file.path(root, rel_file("manifest")), simplifyVector = FALSE), error = function(z) NULL)
      decl <- .find_rx0s_changes(man)
      if (!is.null(decl) && !identical(sort(as.integer(decl)), sort(as.integer(d)))) e <- c(e, sprintf("다른 줄 %s ≠ 매니페스트 신고 줄 %s", paste(d, collapse = ","), paste(sort(decl), collapse = ",")))
      out$seed_line <- if (length(sd) == 1L) list(line = sd, source = trimws(a[sd]), reseed = trimws(b[sd])) else NULL
      out$identifier_lines <- lapply(idl, function(i) list(line = i, source = trimws(a[i]), reseed = trimws(b[i])))
      out$n_diff_lines <- length(d)
    }
    cv <- code_version_of(f); cv0 <- code_version_of(o)
    if (!identical(cv, cv0)) e <- c(e, sprintf("engine_RX0S.R CODE_VERSION %s ≠ 원본 %s", cv, cv0))
    c(out, list(code_version = cv, ok = !length(e), errors = if (length(e)) e else NULL))
  }
  ## 파이썬 원문의 CODE_VERSION = "…" (엔진 R 파일 안 원시 문자열) — 서로 다른 값이 여럿이면 ' | ' 로 잇는다(= 불일치)
  code_version_of <- function(path) {
    L <- rd_lines(path); h <- grep(CV_RX, L, perl = TRUE, value = TRUE)
    v <- unique(sub(paste0(CV_RX, ".*$"), "\\1", h, perl = TRUE))
    if (length(v) == 1L) v else if (!length(v)) NA_character_ else paste(v, collapse = " | ")
  }
  rule_of <- function(L) { i <- grep(RULE_RX, L, perl = TRUE)
    list(n = length(i), line = if (length(i) == 1L) i else NA_integer_, value = if (length(i) == 1L) sub(paste0(RULE_RX, ".*$"), "\\1", L[i], perl = TRUE) else NA_character_) }
  ## 상수 대입 줄 판독 — 오른쪽이 숫자 · c(…) · L 접미 · 쉼표만일 때만 평가(c 외 함수 없는 환경) · 아니면 NA
  const_of <- function(path) {
    L <- rd_lines(path); out <- list()
    for (nm in CONST_NAMES) {
      rx <- paste0("^\\s*", gsub(".", "\\.", nm, fixed = TRUE), "\\s*<-\\s*(.+?)\\s*(#.*)?$")
      i <- grep(rx, L, perl = TRUE)
      if (length(i) != 1L) { out[[nm]] <- NA; next }
      rhs <- sub(rx, "\\1", L[i], perl = TRUE)
      if (!grepl("^(c\\()?[-+0-9.eEL, ]*\\)?$", rhs, perl = TRUE)) { out[[nm]] <- NA; next }
      v <- tryCatch(eval(parse(text = rhs), envir = list2env(list(c = base::c), parent = emptyenv())), error = function(e) NA)
      out[[nm]] <- suppressWarnings(as.numeric(v))
    }
    out
  }
  const_bad <- function(cs) names(cs)[vapply(cs, function(v) !length(v) || anyNA(v), logical(1))]
  ## (iv) 엔진끼리 차이 = .DT_RULE 한 줄뿐(줄 위치 같음 · 값 = 파일 이름 규칙)
  cross_diff <- function(root) {
    L <- lapply(RULES, function(r) rd_lines(file.path(root, rel_engine(r)))); names(L) <- RULES
    err <- character(0); rec <- list()
    for (r in RULES) {
      ro <- rule_of(L[[r]]); rec[[r]] <- list(rule_line = ro$line, rule_value = ro$value)
      if (ro$n != 1L) err <- c(err, sprintf("engine_%s.R: .DT_RULE 대입 줄 %d개(1개여야 한다)", r, ro$n))
      else if (!identical(ro$value, r)) err <- c(err, sprintf("engine_%s.R: .DT_RULE = \"%s\" ≠ 파일 이름의 규칙 %s", r, ro$value, r))
    }
    if (!length(err)) {
      r0 <- RULES[1]; b <- L[[r0]][-rec[[r0]]$rule_line]
      for (r in RULES[-1]) {
        x <- L[[r]][-rec[[r]]$rule_line]
        if (!identical(rec[[r]]$rule_line, rec[[r0]]$rule_line) || !identical(x, b))
          err <- c(err, sprintf("engine_%s.R: 규칙 상수 줄 밖에서 engine_%s.R 와 다르다(DESIGN §7.1 '파일끼리 규칙 상수 한 줄만 다르다')", r, r0))
      }
    }
    list(ok = !length(err), errors = err, rules = rec)
  }
  ## (ii) 매니페스트 → 규칙별 md5 — 형식을 가정하지 않고 걷는다: ① 이름 키가 규칙 또는 engine_<규칙>.R 이고 값이 md5(또는 md5 필드를 가진 객체)
  ##   ② 한 객체 안에 engine_<규칙>.R 로 끝나는 문자열 필드와 md5 모양(32자 16진) 필드가 하나씩. 한 규칙에 다른 md5 가 둘 이상이면 충돌(NA + 기록)
  manifest_md5 <- function(man) {
    is_md5 <- function(x) is.character(x) && length(x) == 1L && grepl("^[0-9a-f]{32}$", x, perl = TRUE)
    rule_in <- function(x) {
      if (!is.character(x) || length(x) != 1L) return(NA_character_)
      if (x %in% RULES) return(x)
      m <- regmatches(x, regexec("engine_(Q50|V1|V2|N1|N2|S1|S2)\\.R$", x, perl = TRUE))[[1]]
      if (length(m) == 2L) m[2] else NA_character_
    }
    hits <- list()
    put <- function(r, v) if (!is.na(r) && is_md5(v)) hits[[r]] <<- unique(c(hits[[r]], v))
    walk <- function(node) {
      if (!is.list(node)) return(invisible())
      nms <- names(node) %||% rep("", length(node))
      for (i in seq_along(node)) {
        k <- nms[i]; v <- node[[i]]
        if (nzchar(k)) {
          r <- rule_in(k)
          if (!is.na(r)) { if (is_md5(v)) put(r, v) else if (is.list(v)) for (z in Filter(is_md5, v)) put(r, z) }
        }
      }
      str_rules <- unique(stats::na.omit(vapply(Filter(function(v) is.character(v) && length(v) == 1L, node), rule_in, character(1))))
      md5s <- unique(unlist(Filter(is_md5, node)))
      if (length(str_rules) == 1L && length(md5s) == 1L) put(str_rules, md5s)
      for (v in node) if (is.list(v)) walk(v)
    }
    `%||%` <- function(a, b) if (is.null(a)) b else a
    walk(man)
    out <- setNames(rep(NA_character_, length(RULES)), RULES); conflict <- character(0)
    for (r in RULES) { h <- hits[[r]]; if (length(h) == 1L) out[[r]] <- h else if (length(h) > 1L) conflict <- c(conflict, r) }
    list(md5 = out, conflict = conflict)
  }
  ## (i) 템플릿 차분 대조 — 에이전트 A 의 검사기를 그대로 돌린다(인자 없음 · 종료 코드만 판정 · 꼬리 6줄 기록)
  diff_check <- function(root) {
    p <- file.path(root, rel_file("diff_check"))
    if (!file.exists(p)) return(list(ok = FALSE, rc = NA_integer_, tail = "template_diff_check.R 없음", path = rel_file("diff_check"), md5 = NA_character_))
    o <- suppressWarnings(system2("Rscript", c("--no-environ", shQuote(p)), stdout = TRUE, stderr = TRUE))   # QM_ROOT · CLAUDE_PROJECT_DIR = 호출자 Sys.setenv 상속
    st <- attr(o, "status"); st <- if (is.null(st)) 0L else as.integer(st)
    list(ok = identical(st, 0L), rc = st, tail = utils::tail(o, 6L), path = rel_file("diff_check"), md5 = md5f(p))
  }
  ## 매니페스트의 재시드 엔진 신고 줄 번호 — engine_RX0S.R path 를 가진 객체의 changes[].line(없으면 NULL = 대조 생략)
  .find_rx0s_changes <- function(man) {
    hit <- NULL
    walk <- function(node) if (is.list(node)) {
      s <- Filter(function(v) is.character(v) && length(v) == 1L, node)
      if (any(vapply(s, function(v) grepl("(^|/)engine_RX0S\\.R$", v, perl = TRUE), logical(1))) && is.list(node$changes))
        hit <<- vapply(node$changes, function(z) as.integer(.or(z$line, NA_integer_)), integer(1))
      for (v in node) if (is.list(v)) walk(v) }
    walk(man); hit
  }
  ## 매니페스트의 재시드 엔진 md5 — engine_RX0S.R 로 끝나는 path 문자열과 md5 모양 필드가 하나씩 든 객체
  rx0s_manifest_md5 <- function(man) {
    hit <- character(0)
    walk <- function(node) if (is.list(node)) {
      s <- Filter(function(v) is.character(v) && length(v) == 1L, node)
      if (any(vapply(s, function(v) grepl("(^|/)engine_RX0S\\.R$", v, perl = TRUE), logical(1)))) {
        m <- unique(unlist(Filter(function(v) grepl("^[0-9a-f]{32}$", v, perl = TRUE), s))); if (length(m) == 1L) hit <<- c(hit, m) }
      for (v in node) if (is.list(v)) walk(v) }
    walk(man); hit <- unique(hit)
    if (length(hit) == 1L) hit else NA_character_
  }
  ## (iii) 정적 PIT — 미스캔(NA)은 통과가 아니다 · 규칙 엔진 7 + 재시드 엔진
  static_pit <- function(root) {
    E <- new.env(parent = globalenv())
    invisible(utils::capture.output(sys.source(file.path(root, DETECTOR), envir = E, keep.source = FALSE)))
    targets <- c(setNames(vapply(RULES, rel_engine, ""), RULES), RX0S = rx0s_rel(root))
    targets <- targets[file.exists(file.path(root, targets))]                   # 없는 파일(대기 — 재시드 엔진)은 run_all 이 pending 으로 센다
    res <- lapply(names(targets), function(r) {
      x <- tryCatch(E$detect_lookahead(file.path(root, targets[[r]]), verbose = FALSE), error = function(e) list(clean = NA, scanned = FALSE, error = conditionMessage(e)))
      v1 <- if (length(x$violations)) paste(utils::head(as.character(unlist(x$violations[[1]])), 4L), collapse = " | ") else NA_character_
      list(rule = r, clean = if (is.null(x$clean)) NA else x$clean, scanned = isTRUE(x$scanned), n_violations = as.integer(.or(x$n_violations, NA_integer_)),
           first_violation = v1, error = .or(x$error, NA_character_))
    })
    list(detector = list(path = DETECTOR, md5 = md5f(file.path(root, DETECTOR))), engines = res,
         ok = all(vapply(res, function(z) isTRUE(z$clean), logical(1))))
  }
  ## (vii) 양성 대조 · 뮤테이션 리허설 요약
  pc_rehearsal <- function(root) {
    p <- file.path(root, rel_file("pc_rehearsal")); base <- list(path = rel_file("pc_rehearsal"), md5 = md5f(p))
    if (!file.exists(p)) return(c(base, list(ok = FALSE, why = "양성 대조 · 뮤테이션 리허설 요약 없음")))
    j <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(j)) return(c(base, list(ok = FALSE, why = "요약 JSON 판독 실패")))
    mu <- .or(j$mutations, list())
    nm <- vapply(mu, function(m) as.character(.or(m$name, .or(m$id, NA_character_)))[1], character(1))
    cg <- vapply(mu, function(m) isTRUE(.or(m$caught, .or(m$failed, .or(m$detected, m$pc_failed)))), logical(1))
    tmd <- as.character(.or(j$template_md5, NA_character_))[1]; cur <- md5f(file.path(root, rel_file("template")))
    why <- c(if (!isTRUE(j$pass)) "pass ≠ true",
             if (!length(mu)) "뮤테이션 기록 없음(양성 대조가 결함을 잡는다는 증거 없음)",
             if (length(mu) && !all(cg)) paste("양성 대조가 잡지 못한 뮤테이션:", paste(nm[!cg], collapse = ",")),
             if (is.na(tmd)) "template_md5 없음(어느 판의 리허설인지 모른다)" else if (!identical(tmd, cur)) "리허설 뒤 템플릿이 바뀌었다(template_md5 ≠ 현 템플릿)")
    c(base, list(ok = !length(why), why = if (length(why)) why else NULL, pass = isTRUE(j$pass), mutations = as.list(nm), caught = as.list(cg), template_md5 = tmd,
                 at = as.character(.or(j$at, NA_character_))[1]))
  }
  py_path <- function(root) { p <- file.path(root, ".venv_qvest_ml", "Scripts", "python.exe"); if (file.exists(p)) p else Sys.getenv("QVEST_PY", "") }
  ## 파이썬 판(엔진과 같은 해석 순서 · CUDA 초기화 없음 — 판 문자열만)
  python_versions <- function(root) {
    py <- py_path(root)
    if (!nzchar(py) || !file.exists(py)) return(list(ok = FALSE, why = "파이썬 실행기 없음(.venv_qvest_ml · QVEST_PY)"))
    code <- "import json, sys, numpy, pandas, pyarrow, torch; print(json.dumps({'python': sys.version.split()[0], 'torch': torch.__version__, 'torch_cuda': torch.version.cuda, 'numpy': numpy.__version__, 'pandas': pandas.__version__, 'pyarrow': pyarrow.__version__}))"
    o <- suppressWarnings(system2(py, c("-c", shQuote(code)), stdout = TRUE, stderr = FALSE))
    st <- attr(o, "status"); st <- if (is.null(st)) 0L else as.integer(st)
    j <- grep("^\\{", o, value = TRUE, perl = TRUE)
    if (st != 0L || !length(j)) return(list(ok = FALSE, why = sprintf("파이썬 판 조회 실패(rc %d)", st)))
    c(list(ok = TRUE, executable = sub(paste0("^", root, "/"), "", gsub("\\\\", "/", py))), jsonlite::fromJSON(j[length(j)]))
  }
  PY_KEYS <- c("python", "torch", "torch_cuda", "numpy", "pandas", "pyarrow")
  ## 전부 — pins = 사전등록 engines 절(있으면 그 값과 대조) · run_diff = 템플릿 차분 검사기 실행 여부. 반환 = list(ok, errors, pending, record)
  ## ok = 오류 0 ∧ 대기 0(초안 · 등록 · 워밍 · 본 대조) · 건식은 오류 0 만 본다(대기 = 다른 에이전트 산출 미비 — 목록만)
  run_all <- function(root, pins = NULL, run_diff = TRUE) {
    inv <- inventory(root)
    rec <- list(dir = DT_DIR, code_version_expected = CODE_VERSION, cache_dir = CACHE_DIR, qpred_dir = QPRED_DIR, inventory = inv)
    opt <- c(rel_file("pc_rehearsal"), rx0s_rel(root))                         # 리허설 요약 · 재시드 엔진은 없으면 '대기'로 세고 나머지 검사는 돈다
    core_miss <- setdiff(inv$missing, opt)                                      # 규칙 엔진 · 템플릿 · 생성기 · 검사기 · 매니페스트가 없으면 나머지 검사를 못 한다
    if (length(core_miss))
      return(list(ok = FALSE, pending = inv$missing, record = rec, errors = character(0),
                  why_pending = paste("DT 엔진 파일 없음(구현 에이전트 A 산출 대기):", paste(inv$missing, collapse = ", "))))
    pend <- intersect(inv$missing, opt)
    rx0s_pending <- rx0s_rel(root) %in% pend
    err <- character(0); add <- function(...) err <<- c(err, paste0(...))
    files <- lapply(names(FILES), function(k) list(key = k, path = rel_file(k), md5 = md5f(file.path(root, rel_file(k)))))
    gen <- lapply(RULES, function(r) { f <- file.path(root, rel_engine(r))
      list(rule = r, path = rel_engine(r), md5 = md5f(f), code_version = code_version_of(f), constants = const_of(f)) })
    cvs <- unique(vapply(gen, function(g) as.character(g$code_version), character(1)))
    if (length(cvs) != 1L || is.na(cvs)) add("CODE_VERSION 이 엔진마다 다르거나 없다: ", paste(cvs, collapse = " / "))
    else if (!identical(cvs, CODE_VERSION)) add("CODE_VERSION ", cvs, " ≠ DESIGN §7.2 ", CODE_VERSION)
    for (g in gen) { b <- const_bad(g$constants); if (length(b)) add("engine_", g$rule, ".R: 규칙 상수 판독 실패 — ", paste(b, collapse = ", ")) }
    if (length(unique(vapply(gen, function(g) cj(g$constants), character(1)))) != 1L) add("규칙 상수가 엔진마다 다르다(DESIGN §7.1 — 규칙 상수 한 줄 밖은 같아야 한다)")
    cd <- cross_diff(root); if (!isTRUE(cd$ok)) err <- c(err, cd$errors)
    man <- tryCatch(jsonlite::fromJSON(file.path(root, rel_file("manifest")), simplifyVector = FALSE), error = function(e) NULL)
    mm <- if (is.null(man)) list(md5 = setNames(rep(NA_character_, length(RULES)), RULES), conflict = character(0)) else manifest_md5(man)
    if (is.null(man)) add("engines_manifest.json 판독 실패")
    if (length(mm$conflict)) add("매니페스트에 한 규칙 md5 가 둘 이상: ", paste(mm$conflict, collapse = ","))
    for (g in gen) { m <- mm$md5[[g$rule]]
      if (is.na(m)) add("매니페스트에 engine_", g$rule, ".R md5 없음") else if (!identical(m, g$md5)) add("engine_", g$rule, ".R md5 ≠ 매니페스트(생성 뒤 손으로 고쳤거나 매니페스트가 낡았다)") }
    rs <- rx0s_check(root)                                                      # 재시드 짝 엔진(시드 한 줄 · CODE_VERSION 같음)
    rs$manifest_md5 <- if (is.null(man)) NA_character_ else rx0s_manifest_md5(man)
    if (!rx0s_pending) {
      if (!isTRUE(rs$ok)) err <- c(err, rs$errors)
      if (is.na(rs$manifest_md5)) add("매니페스트에 engine_RX0S.R md5 없음(재시드 엔진 — 구현 에이전트 A)") else if (!identical(rs$manifest_md5, rs$md5)) add("engine_RX0S.R md5 ≠ 매니페스트")
    }
    sp <- static_pit(root)
    for (z in sp$engines) if (!isTRUE(z$clean))
      add("engine_", z$rule, ".R 정적 PIT ", if (isTRUE(z$scanned)) sprintf("위반 %s건(첫 줄: %s)", format(z$n_violations), .or(z$first_violation, "?")) else paste("미스캔(통과 아님):", .or(z$error, "?")))
    dc <- if (isTRUE(run_diff)) diff_check(root) else NULL
    if (!is.null(dc) && !isTRUE(dc$ok)) add("템플릿 차분 대조 실패(rc ", format(dc$rc), "): ", paste(utils::tail(dc$tail, 2L), collapse = " | "))
    pc <- pc_rehearsal(root); if (!isTRUE(pc$ok) && !length(pend)) add("양성 대조 · 뮤테이션 리허설: ", paste(pc$why, collapse = " · "))
    if (!is.null(pins)) {                                                           # 사전등록 핀 대조(등록 뒤 · precheck --warm · 본 대조)
      pf <- .or(pins$files, list())
      for (f in files) { q <- Filter(function(z) identical(z$key, f$key), pf)
        if (!length(q) || !identical(q[[1]]$md5, f$md5)) add("DT 파일 md5 ≠ 사전등록 핀: ", f$path) }
      pg <- .or(pins$generated, list())
      for (g in gen) { q <- Filter(function(z) identical(z$rule, g$rule), pg)
        if (!length(q) || !identical(q[[1]]$md5, g$md5)) add("engine_", g$rule, ".R md5 ≠ 사전등록 핀") }
      if (!identical(as.character(.or(pins$code_version, NA_character_)), cvs)) add("CODE_VERSION ≠ 사전등록 핀")
      if (!identical(cj(.or(pins$constants, list())), cj(gen[[1]]$constants))) add("규칙 상수 ≠ 사전등록 핀")
      if (!identical(as.character(.or(pins$positive_control_rehearsal$md5, NA_character_)), as.character(pc$md5))) add("양성 대조 리허설 요약 md5 ≠ 사전등록 핀")
      if (!identical(as.character(.or(pins$rx0s$path, NA_character_)), rs$path) || !identical(as.character(.or(pins$rx0s$md5, NA_character_)), as.character(rs$md5)))
        add("engine_RX0S.R 경로 · md5 ≠ 사전등록 핀")
    }
    rec <- c(rec, list(code_version = cvs, files = files, generated = gen, constants = gen[[1]]$constants, cross_diff = cd,
                       manifest = list(md5 = as.list(mm$md5), conflict = as.list(mm$conflict)), static_pit = sp, diff_check = dc,
                       positive_control_rehearsal = pc, rx0s = rs))
    list(ok = !length(err) && !length(pend), errors = err, pending = pend, record = rec,
         why_pending = if (length(pend)) paste("구현 에이전트 A 산출 대기(양성 대조 리허설 요약 · 재시드 엔진):", paste(pend, collapse = ", ")) else NULL)
  }
  ## DT 시험 증거 — 파일마다 md5 · 통과 기록(ok · n · n_ok · 뮤테이션 정답 통과 · 뮤턴트 전부 실패 · 시각) · 형식을 가정하지 않고 있는 스칼라만 옮긴다(없는 파일 = md5 NA)
  ##   논리값 묶음(mutants_fail_all = 뮤턴트별 · positive_control = r_fired · py_fired)은 논리값만 모아 all() 1개로 옮긴다
  ##   pass = ok 가 있으면 ok(∧ 양성 대조 발화) · 없으면 correct_pass_all ∧ mutants_fail_all(pc_mutation) · 둘 다 없으면 NA(README — md5 핀만)
  test_evidence <- function(root) lapply(TEST_EVIDENCE, function(rel) {
    p <- file.path(root, rel); base <- list(path = rel, md5 = md5f(p))
    if (!file.exists(p)) return(c(base, list(pass = FALSE, why = "없음")))
    if (!grepl("\\.json$", rel)) return(c(base, list(pass = NA)))
    j <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.list(j)) return(c(base, list(read = FALSE, pass = FALSE, why = "JSON 판독 실패")))
    k <- intersect(c("ok", "n", "n_ok", "n_cases", "correct_pass_all", "fast", "device", "at", "generated_at"), names(j))
    out <- c(base, Filter(function(v) !is.list(v) && length(v) == 1L, j[k]))
    for (nm in intersect(c("mutants_fail_all", "positive_control"), names(j))) {
      v <- j[[nm]]
      lg <- if (is.list(v)) Filter(function(z) is.logical(z) && length(z) == 1L, v) else if (is.logical(v) && length(v) == 1L) list(v) else list()
      if (length(lg)) { out[[nm]] <- all(unlist(lg)); out[[paste0(nm, "_n")]] <- length(lg) }
    }
    out$pass <- if (!is.null(out$ok)) isTRUE(out$ok) && (is.null(out$positive_control) || isTRUE(out$positive_control)) &&
                                    (is.null(out$n) || is.null(out$n_ok) || identical(as.integer(out$n), as.integer(out$n_ok)))
                else if (!is.null(out$correct_pass_all)) isTRUE(out$correct_pass_all) && isTRUE(out$mutants_fail_all)
                else FALSE
    out
  })
  ## 시험 증거 대조 — 핀(사전등록 tests_dt)과 현재 md5 · 없거나 실패한 증거 · 반환 = list(errors, pending, record)
  test_evidence_check <- function(root, pins = NULL) {
    rec <- test_evidence(root); err <- character(0); pend <- character(0)
    for (z in rec) {
      if (is.na(z$md5)) pend <- c(pend, z$path)
      else if (identical(z$pass, FALSE)) err <- c(err, sprintf("DT 시험 증거 실패: %s%s", z$path, if (!is.null(z$why)) paste0("(", z$why, ")") else ""))
    }
    if (!is.null(pins)) {
      pp <- vapply(pins, function(z) as.character(.or(z$path, NA)), "")
      if (!setequal(pp, TEST_EVIDENCE)) err <- c(err, sprintf("DT 시험 증거 목록 ≠ 사전등록 핀(핀 %d · 현재 정의 %d)", length(pp), length(TEST_EVIDENCE)))
      for (z in pins) { cur <- md5f(file.path(root, z$path))
        if (!identical(cur, as.character(.or(z$md5, NA)))) err <- c(err, sprintf("DT 시험 증거 md5 ≠ 사전등록 핀: %s(핀 %s · 현재 %s) — 시험을 다시 돌렸거나 바뀌었다", z$path, .or(z$md5, "없음"), cur)) }
    }
    list(ok = !length(err) && !length(pend), errors = err, pending = pend, record = rec)
  }
  ## 엔진 종류(워밍 단정의 기준) — quantile = 규칙 엔진 7(분위 캐시 · 예측표 · cuda) · reseed = 재시드 엔진(새 시드 캐시 · cuda) · mean = 그 밖(RX0 평균 엔진 — 기존 캐시 공유)
  engine_kind <- function(rel, root) { rel <- gsub("\\\\", "/", rel)
    if (rel %in% vapply(RULES, rel_engine, "")) "quantile" else if (identical(rel, rx0s_rel(root))) "reseed" else "mean" }
  list(DT_DIR = DT_DIR, RULES = RULES, FILES = FILES, CODE_VERSION = CODE_VERSION, CONST_NAMES = CONST_NAMES, WORK = WORK, CACHE_DIR = CACHE_DIR,
       QPRED_DIR = QPRED_DIR, DETECTOR = DETECTOR, PY_KEYS = PY_KEYS, RX0_SRC = RX0_SRC, RX0S_DEFAULT = RX0S_DEFAULT,
       RNG_FACTS = RNG_FACTS, TEST_EVIDENCE = TEST_EVIDENCE, test_evidence = test_evidence, test_evidence_check = test_evidence_check,
       rel_engine = rel_engine, rel_file = rel_file, all_rel = all_rel, ops_rel = ops_rel, rx0s_rel = rx0s_rel, rx0s_check = rx0s_check,
       rx0s_manifest_md5 = rx0s_manifest_md5, engine_kind = engine_kind,
       inventory = inventory, code_version_of = code_version_of, const_of = const_of, cross_diff = cross_diff, manifest_md5 = manifest_md5,
       diff_check = diff_check, static_pit = static_pit, pc_rehearsal = pc_rehearsal, py_path = py_path, python_versions = python_versions,
       run_all = run_all, md5f = md5f)
})
