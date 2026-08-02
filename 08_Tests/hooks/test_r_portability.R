#==============================================================================
# test_r_portability.R — R 측 Windows 이식성 계약 검사기
#
# 계약: 02_Infrastructure/docs/rules/r-portability.md (2026-07-25 승격)
#
# 라이브 존의 .R 을 스캔해 금칙 6종을 검출한다.
#   ① system2(..., env=)        — Windows에서 환경변수 아닌 인자 주입
#   ② 스크립트 최상위 on.exit() — 발화하지 않음(cleanup dead code)
#   ③ 선행 "/" 경로 하드코딩 / startsWith(p,"/") 절대경로 판정
#   ④ resolver 우선순위 QM_ROOT-before-CLAUDE_PROJECT_DIR
#   ⑤ system()/system2() 명령 문자열에 쉘 리다이렉션·연산자 주입 — Windows R 은 셸을
#      경유하지 않아 "2>/dev/null" · "&&" 가 프로그램의 리터럴 argv 로 전달된다
#   ⑥ regmatches × TRE 색인 — Windows TRE 는 매치 위치를 wchar_t(UTF-16 코드유닛)로
#      돌려주는데 regmatches/substr 은 코드포인트로 자른다. 매치 **앞**의 non-BMP
#      문자(이모지) 1개마다 추출 창이 1칸 밀린다. 길이는 맞으므로 오류가 아니라
#      **그럴듯한 쓰레기**가 나온다. perl/fixed/useBytes = TRUE 로 회피.
#
# 기수록 위반은 ALLOWLIST로 수용(원장 = rule 문서). 신규 위반만 FAIL —
# 원장을 줄이는 방향으로만 움직이게 한다.
#
# ★위반 주입 테스트 포함: 합성 위반 fixture를 실제로 잡는지 자체 검증.
#   검사기가 "잘못된 것을 재는" 실패가 이 리포지토리의 반복 부류라, 위반 주입 테스트
#   없는 검사기는 계약상 인정하지 않는다.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok   <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad  <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

# ─── 라이브 존 (아카이브 제외) ───────────────────────────────────────────────
LIVE_DIRS <- c("02_Infrastructure", "08_Tests", "qepm/scripts")
live_files <- unlist(lapply(LIVE_DIRS, function(d)
  if (dir.exists(d)) list.files(d, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  else character(0)))
live_files <- normalizePath(live_files, winslash = "/", mustWork = FALSE)

# ─── Baseline 래칫 ───────────────────────────────────────────────────────────
# 기존 위반은 baseline 에 기록해 수용하고, **신규 위반만 FAIL** 한다.
# 원장은 줄어드는 방향으로만 움직인다 — baseline 에 있는데 실제로는 없어진 항목은
# "수리됨"으로 보고하고 baseline 을 줄이라고 요구한다(래칫 역행 방지).
# 재생성: Rscript 08_Tests/hooks/test_r_portability.R --write-baseline
BASELINE_PATH <- "08_Tests/hooks/_r_portability_baseline.json"
WRITE_BASELINE <- "--write-baseline" %in% commandArgs(trailingOnly = TRUE)

.bl <- if (file.exists(BASELINE_PATH)) fromJSON(BASELINE_PATH, simplifyVector = TRUE) else list()
baseline <- if (is.null(.bl$entries)) character(0) else as.character(.bl$entries)

# 금칙 ⑥ 전용 — **파일당 site 수**까지 고정한다.
# 이유: entries 키가 "파일:금칙코드" 라 이미 등재된 파일에 새 위반을 하나 더 넣어도
#   집합이 안 변해 래칫이 눈을 감는다. regmatches 를 많이 쓰는 파일이 바로 그 파일들이라,
#   가장 새 위반이 생기기 쉬운 자리에 정확히 사각이 생긴다. 줄 번호 대신 개수로 고정하면
#   위/아래 편집으로 줄이 밀려도 오탐이 안 난다.
baseline_sites6 <- if (is.null(.bl$code6_sites)) list() else as.list(.bl$code6_sites)

is_allowed <- function(key) key %in% baseline

rel_of <- function(p) sub(paste0("^", gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", PROJ), "/"), "", p)

# ─── 검출기 (파일 텍스트 → 위반 금칙코드 벡터) ──────────────────────────────
# 주석 줄은 제외 — 수리 노트가 자기 자신을 위반으로 잡는 것을 막는다.
strip_comments <- function(lines) lines[!grepl("^\\s*#", lines)]

# system2( ... ) / system( ... ) 호출 본문을 괄호 균형으로 추출.
# ★구 구현은 grepl("system2\\([^)]*env\\s*=") 였는데 [^)]* 가 인자 안의 첫 ')'
#   (예: args = c("-c", code))에서 멈춰 다중행 호출을 놓쳤다 — 위반 주입 테스트가 적발.
# ★gregexpr 은 반드시 perl=TRUE — 기본 TRE 는 Windows 에서 UTF-16 오프셋을 돌려주므로
#   검사기 자신이 금칙 ⑥ 에 걸린다(검사기가 자기가 잡는 결함을 앓는 부류).
.calls_pos <- function(txt, fname) {
  out <- list()
  # \\b 로 경계를 잡아 "system" 패턴이 "system2(" 를 삼키지 않게 한다.
  starts <- gregexpr(sprintf("\\b%s\\s*\\(", fname), txt, perl = TRUE)[[1]]
  if (starts[1] == -1) return(out)
  mlen  <- attr(starts, "match.length")
  chars <- strsplit(txt, "", fixed = TRUE)[[1]]
  n <- length(chars)
  for (k in seq_along(starts)) {
    open_at <- starts[k] + mlen[k] - 1L
    depth <- 0L; i <- open_at; endp <- NA_integer_; instr <- ""; esc <- FALSE
    while (i <= n) {
      ch <- chars[i]
      if (nzchar(instr)) {                       # 문자열 리터럴 안의 괄호는 세지 않는다
        if (esc) esc <- FALSE
        else if (ch == "\\") esc <- TRUE
        else if (ch == instr) instr <- ""
      } else if (ch == '"' || ch == "'") instr <- ch
      else if (ch == "(") depth <- depth + 1L
      else if (ch == ")") { depth <- depth - 1L; if (depth == 0L) { endp <- i; break } }
      i <- i + 1L
    }
    if (!is.na(endp))
      out[[length(out) + 1L]] <- list(start = starts[k], open = open_at, end = endp,
                                      body = paste(chars[open_at:endp], collapse = ""))
  }
  out
}
.calls_of <- function(txt, fname) vapply(.calls_pos(txt, fname), `[[`, character(1), "body")
.system2_calls <- function(txt) .calls_of(txt, "system2")

# 호출 본문("(...)")을 depth-1 콤마로 인자 분해. 문자열 리터럴·중첩 괄호 보호.
.split_args <- function(body) {
  chars <- strsplit(body, "", fixed = TRUE)[[1]]
  depth <- 0L; cur <- character(0); args <- character(0); instr <- ""; esc <- FALSE
  for (ch in chars) {
    if (nzchar(instr)) {
      cur <- c(cur, ch)
      if (esc) esc <- FALSE else if (ch == "\\") esc <- TRUE else if (ch == instr) instr <- ""
      next
    }
    if (ch == '"' || ch == "'") { instr <- ch; cur <- c(cur, ch); next }
    if (ch %in% c("(", "[", "{")) {
      depth <- depth + 1L
      if (!(depth == 1L && ch == "(")) cur <- c(cur, ch)
      next
    }
    if (ch %in% c(")", "]", "}")) {
      depth <- depth - 1L
      if (depth == 0L) { args <- c(args, paste(cur, collapse = "")); cur <- character(0); break }
      cur <- c(cur, ch); next
    }
    if (ch == "," && depth == 1L) { args <- c(args, paste(cur, collapse = "")); cur <- character(0); next }
    cur <- c(cur, ch)
  }
  trimws(args)
}

# ─── 금칙 ⑥ 검출기 ───────────────────────────────────────────────────────────
# regmatches(x, <색인>) 의 <색인> 이 TRE(기본 엔진)로 만들어졌는지 판정한다.
#   safe  = 색인 생성 호출에 perl/fixed/useBytes = TRUE 가 있음
#   TRE   = 없음  → 매치 앞의 non-BMP 문자 수만큼 추출 창이 밀린다
#
# ★기준 ① (surface 축소, 계약 문서와 동일): **count-only 는 무해**.
#   TRE 도 UTF-16 공간에서 같은 *개수* 를 찾는다 — 밀리는 것은 위치이지 개수가 아니다.
#   따라서 length()/lengths() 로만 소비되는 자리는 검출 대상이 아니다. 이걸 빼지 않으면
#   원장이 무해한 항목으로 부풀고, 시끄러운 래칫은 죽은 래칫과 겉보기가 같아진다.
# ★기준 ② (non-BMP 가 매치 *앞* 에 와야 함)는 **정적으로 판정 불가**하므로 빼지 않는다.
#   그래서 원장 등재 = "이 자리가 위험하다"가 아니라 "이 자리는 이 계통에 노출돼 있다"이다.
.IDX_FN   <- "gregexpr|regexpr|regexec|gregexec"
.SAFE_ARG <- "\\b(perl|fixed|useBytes)\\s*=\\s*TRUE"

# census=TRUE 면 c(total, safe, tre, count_only, bad) 를 돌려준다 — 문서에 적는 수치의 정본.
.regmatches_sites <- function(txt, census = FALSE) {
  n_bad <- 0L; n_tot <- 0L; n_safe <- 0L; n_cnt <- 0L
  for (cl in .calls_pos(txt, "regmatches")) {
    n_tot <- n_tot + 1L
    args <- .split_args(cl$body)
    a2 <- if (length(args) >= 2L) args[2] else ""
    tre <- NA
    if (grepl(sprintf("^(%s)\\s*\\(", .IDX_FN), a2, perl = TRUE)) {
      # 인라인: regmatches(x, gregexpr(...))
      fn <- sub("\\s*\\(.*$", "", a2)
      inner <- .calls_pos(a2, fn)
      bd <- if (length(inner)) inner[[1]]$body else a2
      tre <- !grepl(.SAFE_ARG, bd, perl = TRUE)
    } else if (grepl("^[A-Za-z._][A-Za-z0-9._]*$", a2, perl = TRUE)) {
      # 변수형: m <- regexpr(...); regmatches(x, m)  → 대입 우변을 추적
      pat <- sprintf("\\b%s\\s*(<-|=)\\s*(%s)\\s*\\(", gsub("\\.", "\\\\.", a2), .IDX_FN)
      hit <- regexpr(pat, txt, perl = TRUE)
      if (hit > 0) {
        rest <- substr(txt, hit, nchar(txt))
        fn <- sub(sprintf("^.*?(%s)\\s*\\($", .IDX_FN), "\\1",
                  substr(rest, 1, attr(hit, "match.length")))
        inner <- .calls_pos(rest, fn)
        tre <- if (length(inner)) !grepl(.SAFE_ARG, inner[[1]]$body, perl = TRUE) else TRUE
      } else tre <- TRUE          # 출처 불명 색인 = 안전 근거 없음 → 보수적으로 노출로 본다
    } else if (grepl(sprintf("\\b(%s)\\s*\\(", .IDX_FN), a2, perl = TRUE)) {
      tre <- !grepl(.SAFE_ARG, a2, perl = TRUE)
    } else tre <- TRUE
    if (!isTRUE(tre)) { n_safe <- n_safe + 1L; next }

    # ── 기준 ①: count-only 면 무해 ──
    pre <- substr(txt, max(1L, cl$start - 24L), cl$start - 1L)
    if (grepl("\\b(length|lengths)\\s*\\(\\s*$", pre, perl = TRUE)) { n_cnt <- n_cnt + 1L; next }
    # 대입변수의 *모든* 사용처가 length 류뿐이면 그것도 count-only
    asg <- regmatches(pre, regexpr("[A-Za-z._][A-Za-z0-9._]*\\s*(<-|=)\\s*$", pre, perl = TRUE))
    if (length(asg) == 1L) {
      v <- sub("\\s*(<-|=)\\s*$", "", asg)
      vpat <- sprintf("[^A-Za-z0-9._]%s[^A-Za-z0-9._]", gsub("\\.", "\\\\.", v))
      hits <- gregexpr(vpat, txt, perl = TRUE)[[1]]
      if (hits[1] > 0) {
        ctx <- vapply(seq_along(hits), function(i)
          substr(txt, max(1L, hits[i] - 12L), hits[i] + attr(hits, "match.length")[i] + 10L),
          character(1))
        is_len <- grepl(sprintf("(length|lengths)\\s*\\(\\s*%s", v), ctx, perl = TRUE)
        is_asg <- grepl(sprintf("%s\\s*(<-|=)[^=]", v), ctx, perl = TRUE)
        # ★any(is_len) 이 필수다. 이게 없으면 **한 번도 쓰이지 않는 변수**가
        #   "모든 사용처가 length 뿐"을 공허하게 만족해 무해로 빠진다(빈 집합 = 합격).
        #   2026-08-02 자체 위반 주입에서 적발: 등재 파일에 새 site 를 심었는데
        #   래칫이 침묵했다 — 검사기가 자기 사각을 만든 형태.
        only_len <- any(is_len) && all(is_len | is_asg)
        if (only_len) { n_cnt <- n_cnt + 1L; next }
      }
    }
    n_bad <- n_bad + 1L
  }
  if (census) c(total = n_tot, safe = n_safe, tre = n_tot - n_safe,
                count_only = n_cnt, extracting = n_bad) else n_bad
}

# 호출 본문에서 **문자열 리터럴만** 떼어낸다.
# 리터럴로 좁히는 이유: R 코드 자체의 `||`(예: args = if (a || b) x else y)나
# `stderr = FALSE` 같은 정본 인자를 쉘 문법으로 오검출하지 않기 위함.
.string_literals <- function(bodies) {
  if (!length(bodies)) return(character(0))
  out <- character(0)
  for (b in bodies) {
    for (pat in c('"(\\\\.|[^"\\\\])*"', "'(\\\\.|[^'\\\\])*'")) {
      m <- gregexpr(pat, b, perl = TRUE)[[1]]
      if (m[1] != -1) out <- c(out, regmatches(b, gregexpr(pat, b, perl = TRUE))[[1]])
    }
  }
  out
}

detect <- function(lines) {
  L <- strip_comments(lines)
  txt <- paste(L, collapse = "\n")
  hits <- integer(0)

  # ① system2(..., env = ...) — 괄호 균형으로 호출 본문만 떼어 검사
  if (any(grepl("\\benv\\s*=", .system2_calls(txt), perl = TRUE))) hits <- c(hits, 1L)

  # ② 최상위 on.exit — 들여쓰기 0 (함수 안이면 최소 2칸 들여쓰기된다는 관례 이용)
  if (any(grepl("^on\\.exit\\(", L))) hits <- c(hits, 2L)

  # ③ 선행 "/" 경로 하드코딩 + startsWith 절대경로 판정 + "/tmp/" 리터럴
  if (any(grepl('"/mnt/[a-z]/|"/tmp/', L)) ||
      any(grepl('startsWith\\([^,]+,\\s*"/"\\)', L))) hits <- c(hits, 3L)

  # ④ resolver 우선순위 역전 — QM_ROOT가 CLAUDE_PROJECT_DIR보다 먼저 등장
  qm  <- regexpr('Sys\\.getenv\\("QM_ROOT"', txt)
  cpd <- regexpr('Sys\\.getenv\\("CLAUDE_PROJECT_DIR"', txt)
  if (qm > 0 && cpd > 0 && qm < cpd) hits <- c(hits, 4L)

  # ⑤ system()/system2() 문자열에 쉘 리다이렉션·연쇄 연산자 주입.
  #   Windows R 의 system()/system2() 는 셸을 경유하지 않으므로 이 토큰들은 해석되지 않고
  #   대상 프로그램의 **리터럴 argv** 가 된다. 2026-08-02 실측:
  #     system("git rev-parse HEAD 2>/dev/null", intern=TRUE)
  #       → git 이 '2>/dev/null' 을 revision 으로 받아 status 128
  #     system("git status --porcelain 2>/dev/null", intern=TRUE)
  #       → 출력 0행 → 호출자의 length(out) > 0 이 **항상 FALSE** → "clean tree" 로 위장
  #   ★위험한 건 실패가 아니라 위장이다 — 빈 출력이 '변경 없음'이라는 정상값으로 읽힌다.
  #   대체: 리다이렉션은 stdout=/stderr= 인자로, 연쇄는 호출 분리로.
  #         셸이 정말 필요하면 shell() 을 쓰되 /dev/null 이 아니라 NUL 을 쓸 것.
  #   [2026-08-02 확장] 인라인 환경변수 접두 `VAR=값 cmd` 도 쉘 전용 문법이다.
  #     셸이 없으면 "VAR=값" 이 통째로 **프로그램 이름**이 되어 'not found' 로 죽는다.
  #     실측: test_contract_panel.R 작성 중 `system("CONTRACT_CKDIR=... Rscript ...")` 로 재현.
  #     정본 = Sys.setenv() + 복원 후 system2(cmd, args) (금칙 ① 대체 패턴과 동일).
  shell_meta <- "2>|1>|>>|>&|&&|\\|\\||/dev/null|\\s\\|\\s"
  bodies <- c(.calls_of(txt, "system2"), .calls_of(txt, "system"))
  strip <- function(v) sub('["\']$', "", sub('^["\']', "", v))
  if (any(grepl(shell_meta, strip(.string_literals(bodies)), perl = TRUE))) hits <- c(hits, 5L)

  #   [2026-08-02 확장] 인라인 환경변수 접두 `VAR=값 cmd` 도 쉘 전용 문법이다.
  #     셸이 없으면 "VAR=값" 이 통째로 **프로그램 이름**이 되어 'not found' 로 죽는다.
  #     실측: test_contract_panel.R 작성 중 system("CONTRACT_CKDIR=... Rscript ...") 로 재현.
  #     ★명령이 sprintf/paste 로 조립되면 리터럴이 system() **밖**에 있어 호출-본문 스캔으로는
  #      원리상 못 본다. 그래서 이 축만은 파일 전역 리터럴을 본다 — 단 system/system2 를
  #      실제로 쓰는 파일로 한정해 오검출을 묶는다.
  #     정본 = Sys.setenv() + 복원 후 system2(cmd, args) (금칙 ① 대체 패턴과 동일).
  #     ★1차 시도는 `^VAR=값\s+토큰` 이었는데 "vol_target=%.4f, lookback=%sd" 같은
  #      **로그 포맷 문자열**을 9건 오검출했다(실측). key=value 로 시작하는 진단문은 흔하다.
  #      → VAR= 대입 뒤에 **실행파일 호출**이 오는 형태만 남긴다.
  if (length(bodies)) {
    env_prefix <- paste0("^([A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)+",
                         "(Rscript|Rterm|python3?|bash|sh|git|node|npm|java)\\b")
    if (any(grepl(env_prefix, strip(.string_literals(txt)), perl = TRUE))) hits <- c(hits, 5L)
  }

  # ⑥ regmatches × TRE 색인 (기준 ① count-only 제외 후)
  if (.regmatches_sites(txt) > 0L) hits <- c(hits, 6L)

  unique(hits)
}

CODE_NAME <- c("1" = "system2(env=)", "2" = "top-level on.exit",
               "3" = "leading-slash path", "4" = "resolver precedence",
               "5" = "shell syntax in system() argv",
               "6" = "regmatches over TRE-indexed match (UTF-16 offset)")

# ─── 본 스캔 ─────────────────────────────────────────────────────────────────
cat("=== R portability contract scan ===\n")
cat(sprintf("  live zone: %s (%d files)\n", paste(LIVE_DIRS, collapse = ", "), length(live_files)))

found <- character(0)
sites6 <- list()
census6 <- c(total = 0L, safe = 0L, tre = 0L, count_only = 0L, extracting = 0L)
for (f in live_files) {
  rel <- rel_of(f)
  if (identical(rel, "08_Tests/hooks/test_r_portability.R")) next   # 검사기 자신의 fixture 문자열 제외
  lines <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  if (!length(lines)) next
  for (code in detect(lines)) found <- c(found, paste0(rel, ":", code))
  c6 <- .regmatches_sites(paste(strip_comments(lines), collapse = "\n"), census = TRUE)
  census6 <- census6 + c6
  if (c6[["extracting"]] > 0L) sites6[[rel]] <- as.integer(c6[["extracting"]])
}
found <- sort(unique(found))
sites6 <- sites6[order(names(sites6))]
n_sites6 <- sum(unlist(sites6))
cat(sprintf(paste0("  금칙 ⑥ census: regmatches site %d개 = safe(perl/fixed/useBytes) %d",
                   " + TRE %d [count-only %d(기준① 제외) / 값추출 %d(원장 seed)]\n"),
            census6[["total"]], census6[["safe"]], census6[["tre"]],
            census6[["count_only"]], census6[["extracting"]]))

if (WRITE_BASELINE) {
  write_json(list(
    contract = "02_Infrastructure/docs/rules/r-portability.md",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    note = "기존 위반 원장. 신규 위반만 FAIL. 항목은 수리 시 제거만 — 추가는 계약 위반.",
    codes = as.list(CODE_NAME),
    code6_note = paste("금칙 ⑥ 은 파일당 site 수까지 고정한다(기존 등재 파일에 새 위반이",
                       "추가되는 사각 차단). 값 = 기준 ① count-only 를 제외한 '값 추출' site 수만."),
    code6_sites = sites6,
    entries = found
  ), BASELINE_PATH, pretty = TRUE, auto_unbox = TRUE)
  cat(sprintf("  [baseline] %d entries (금칙 ⑥ site %d개 / %d 파일) → %s\n",
              length(found), n_sites6, length(sites6), BASELINE_PATH))
}

novel   <- setdiff(found, baseline)
retired <- setdiff(baseline, found)

if (length(novel) == 0L) {
  ok("no_novel_violation",
     sprintf("신규 위반 0건 (%d files 스캔 / baseline %d건 수용)",
             length(live_files), length(baseline)))
} else {
  for (k in novel) {
    parts <- strsplit(k, ":", fixed = TRUE)[[1]]
    bad("novel_violation",
        sprintf("%s — 금칙 %s (%s). rule: 02_Infrastructure/docs/rules/r-portability.md",
                parts[1], parts[2], CODE_NAME[[parts[2]]]))
  }
}

# 래칫 역행 방지: 고쳐진 항목은 baseline 에서 빼라고 요구한다.
if (length(retired) > 0L) {
  bad("baseline_not_shrunk",
      sprintf("%d건이 수리됐는데 baseline 에 남아 있음 (--write-baseline 으로 갱신): %s",
              length(retired), paste(utils::head(retired, 5), collapse = ", ")))
} else {
  ok("baseline_current", "baseline = 실제 위반 집합 일치")
}

# 금칙 ⑥ site-수 래칫 — 이미 등재된 파일 안에서 위반이 늘어나는 것도 신규 위반이다.
if (length(baseline_sites6) == 0L) {
  ok("code6_sites_baseline_absent", "code6_sites 미기록 — --write-baseline 으로 최초 생성")
} else {
  keys <- union(names(baseline_sites6), names(sites6))
  drift <- character(0)
  for (k in keys) {
    was <- as.integer(baseline_sites6[[k]] %||% 0L)
    now <- as.integer(sites6[[k]] %||% 0L)
    if (now != was) drift <- c(drift, sprintf("%s %d→%d", k, was, now))
  }
  if (length(drift) == 0L) {
    ok("code6_sites_current",
       sprintf("금칙 ⑥ site %d개 / %d 파일 = baseline 일치 (기준 ① count-only 제외분)",
               n_sites6, length(sites6)))
  } else {
    grew <- grepl("(\\d+)→(\\d+)$", drift) &
            vapply(strsplit(sub("^.*\\s", "", drift), "→"), function(p)
              as.integer(p[2]) > as.integer(p[1]), logical(1))
    bad(if (any(grew)) "code6_sites_grew" else "code6_sites_not_shrunk",
        sprintf("%s: %s (%s)",
                if (any(grew)) "금칙 ⑥ 신규 site" else "수리분이 baseline 에 남음",
                paste(utils::head(drift, 6), collapse = ", "),
                if (any(grew)) "rule: 02_Infrastructure/docs/rules/r-portability.md 금칙 ⑥"
                else "--write-baseline 으로 갱신"))
  }
}

# ─── 위반 주입 테스트 (위반 주입 테스트) ─────────────────────────────────────────────────
# 합성 위반을 실제로 잡는가? 못 잡으면 위 "0건"은 계측 사망이지 통과가 아니다.
fixtures <- list(
  list(code = 1L, name = "env_arg_injection",
       src = c('out <- system2(py, args = c("-c", code),',
               '               env = sprintf("X=%s", v),',
               '               stdout = TRUE)')),
  list(code = 2L, name = "toplevel_on_exit",
       src = c('d <- tempfile()', 'on.exit(unlink(d, recursive = TRUE), add = TRUE)')),
  list(code = 3L, name = "leading_slash_path",
       src = c('PROJ <- "/mnt/c/Users/User/OneDrive/Quant_Module_Moltbot"')),
  list(code = 4L, name = "resolver_precedence",
       src = c('cands <- c(Sys.getenv("QM_ROOT", ""),',
               '           Sys.getenv("CLAUDE_PROJECT_DIR", ""))')),
  # ⑤ 3형태: 실제로 발생했던 세 가지 shape 를 전부 주입한다.
  #   a) lineage_utils.R 구 구현 (2026-08-02 적발)  b) update_research_philosophy.R:104
  #   c) cert_backfill_audit.R 구 구현 (2026-07-26 CBA-06)
  list(code = 5L, name = "shell_redirect_in_system",
       src = c('sha <- system("git rev-parse HEAD 2>/dev/null", intern = TRUE)')),
  list(code = 5L, name = "shell_chain_in_system",
       src = c('system("git add -A && git commit --no-verify", intern = FALSE)')),
  list(code = 5L, name = "shell_pipe_in_system2",
       src = c('out <- system2("Rscript", args = c(f, "2>&1 | grep -E Tier"),',
               '               stdout = TRUE)')),
  # d) 인라인 환경변수 접두 — 2026-08-02 자체 위반으로 발견한 사각
  list(code = 5L, name = "shell_env_prefix",
       src = c('cmd <- sprintf("CONTRACT_CKDIR=%s WINDOW_M=%d Rscript %s", d, w, f)',
               'out <- system(cmd, intern = TRUE)')),
  list(code = 5L, name = "shell_env_prefix_literal",
       src = c('system("QM_ROOT=/x Rscript build.R", intern = TRUE)')),
  # ⑥ 3형태: 인라인 gregexpr · 변수형 regexpr · regexec(캡처그룹).
  #   실측 근거(2026-08-02, R 4.5.2 Korean_Korea.utf8 cp65001): 매치 앞 non-BMP 6개 →
  #   TRE 보고 위치 1670 vs 실제 1664, match.length 는 4로 정상 → 추출 '턱 1.'.
  list(code = 6L, name = "regmatches_tre_inline",
       src = c('risky <- regmatches(msg, gregexpr("&[a-zA-Z]+;", msg))[[1]]',
               'risky <- setdiff(risky, c("&lt;"))')),
  list(code = 6L, name = "regmatches_tre_var",
       src = c('m <- regexpr("WT-[0-9]{8}", title)',
               'wt <- regmatches(title, m)',
               'key <- sprintf("%s_%s", agent, wt[1])')),
  list(code = 6L, name = "regmatches_tre_regexec",
       src = c('mm <- regmatches(body, regexec("family[=:]\\\\s*([a-z_]+)", body))',
               'family <- mm[[1]][2]'))
)
for (fx in fixtures) {
  got <- detect(fx$src)
  if (fx$code %in% got) {
    ok(sprintf("violation_injection_%s", fx$name), sprintf("합성 위반 금칙 %d 검출됨", fx$code))
  } else {
    bad(sprintf("violation_injection_%s", fx$name),
        sprintf("합성 위반 금칙 %d를 검출하지 못함 — 검사기 무력(계측 사망)", fx$code))
  }
}

# 위양성 통제: 정본 패턴은 잡히면 안 된다
clean_src <- c(
  '.old <- Sys.getenv("NAME", unset = NA)',
  'Sys.setenv(NAME = value)',
  'invisible(reg.finalizer(globalenv(), function(e) cleanup(), onexit = TRUE))',
  'cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))',
  'p <- tempfile("fx_")',
  'system2(cmd, args = a, stdout = TRUE, stderr = TRUE)',
  # 금칙 ⑤ 위양성 통제 — 정본 호출과 "> 를 품었지만 쉘 문법이 아닌" 리터럴
  'sha <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)',
  'lg <- system2("git", c("log", "-1", "--pretty=format:%an <%ae>"), stdout = TRUE)',
  'r <- system2(cmd, args = if (a || b) x else y, stdout = TRUE)',
  'shell("dir 2>NUL")',
  # 금칙 ⑤ 확장(env-prefix) 위양성 통제 — 이들은 쉘 명령이 아니다
  'KEY <- sub("^DART_API_KEY=", "", env[grepl("^DART_API_KEY=", env)][1])',
  'writeLines(paste0("QM_ROOT=", root), ".env")',
  'out <- system2("Rscript", args = script, stdout = TRUE)',
  # 금칙 ⑥ 위양성 통제 — 색인이 코드포인트 기반이면 정본이다
  'pre <- regmatches(text, gregexpr(pat, text, perl = TRUE))[[1]]',
  'op <- lengths(regmatches(src, gregexpr("{", src, fixed = TRUE)))',
  'tok <- regmatches(s, gregexpr("[A-Z]+", s, useBytes = TRUE))[[1]]',
  'mv <- regexpr("L-[0-9]+", ll, perl = TRUE)',
  'lid <- regmatches(ll, mv)'
)
if (length(detect(clean_src)) == 0L) {
  ok("false_positive_control", "정본 패턴 오검출 0")
} else {
  bad("false_positive_control",
      sprintf("정본 패턴을 위반으로 오검출: %s", paste(detect(clean_src), collapse = ",")))
}

# ─── 금칙 ⑥ 기준 ① 판별력 (count-only 제외가 실제로 '구별' 하는가) ──────────────
# 통제를 한쪽만 두면 "제외 로직이 항상 켜져 있어" 아무것도 안 잡는 상태와 겉보기가 같다.
# 같은 호출을 count-only / 값-추출 두 형태로 넣어 **판정이 갈리는지** 본다.
crit1 <- list(
  list(name = "direct_length_wrapper", flag = FALSE,
       src = 'n <- length(regmatches(masked, gregexpr("[A-Za-z]", masked))[[1]])'),
  list(name = "value_extracted_same_call", flag = TRUE,
       src = 'hits <- regmatches(masked, gregexpr("[A-Za-z]", masked))[[1]]'),
  list(name = "var_used_only_by_length", flag = FALSE,
       src = c('matches <- regmatches(masked, gregexpr(abbrev_pattern, masked))[[1]]',
               'length(matches) >= 2')),
  list(name = "var_value_consumed", flag = TRUE,
       src = c('matches <- regmatches(masked, gregexpr(abbrev_pattern, masked))[[1]]',
               'paste(matches, collapse = ",")')),
  # 사용처가 **하나도 없는** 변수는 count-only 가 아니다 — 빈 집합이 all() 을 공허하게
  # 만족시켜 무해로 빠지던 사각(2026-08-02 위반 주입에서 적발, any(is_len) 로 폐쇄).
  list(name = "var_never_used_is_not_countonly", flag = TRUE,
       src = 'zz <- regmatches(s, gregexpr("[A-Z]+", s))[[1]]')
)
for (c1 in crit1) {
  got <- 6L %in% detect(c1$src)
  if (identical(got, c1$flag)) {
    ok(sprintf("criterion1_%s", c1$name),
       sprintf("기대 %s", if (c1$flag) "검출" else "무해(count-only)"))
  } else {
    bad(sprintf("criterion1_%s", c1$name),
        sprintf("기대 %s인데 %s — 기준 ① 판별력 상실",
                if (c1$flag) "검출" else "무해", if (got) "검출됨" else "무검출"))
  }
}

# ─── 금칙 ⑥ 함정 자체의 실재 확인 (계약 근거가 이 런타임에서 참인가) ──────────────
# 계약이 "R 4.5.2/Windows 에서 TRE 는 UTF-16 오프셋" 이라고 주장한다. 그 전제가 이 기계에서
# 거짓이면 금칙 ⑥ 은 근거 없는 규칙이 된다 — 그래서 규칙이 아니라 **현상** 을 직접 잰다.
.emo <- paste(rep("\U0001F4CC", 6L), collapse = "")
.sub <- paste0(.emo, " Gate D &lt; 2.95")
.tre <- regmatches(.sub, regexpr("&[a-zA-Z]+;", .sub))
.pcre <- regmatches(.sub, regexpr("&[a-zA-Z]+;", .sub, perl = TRUE))
if (!identical(.pcre, "&lt;")) {
  bad("trap_premise_pcre_correct", sprintf("perl=TRUE 추출이 '&lt;' 가 아님: [%s]", .pcre))
} else if (identical(.tre, .pcre)) {
  # 함정이 재현되지 않음 = 이 런타임에선 금칙 ⑥ 의 전제가 성립하지 않는다.
  ok("trap_premise_platform_note",
     "이 런타임에서 TRE 오프셋 밀림 미재현 — 금칙 ⑥ 은 Windows TRE 전제 규칙(계약 문서 참조)")
} else {
  ok("trap_premise_reproduced",
     sprintf("TRE 추출 [%s] ≠ PCRE [%s] — non-BMP %d개 선행 시 창 밀림 실재", .tre, .pcre, 6L))
}

# ─── 요약 ────────────────────────────────────────────────────────────────────
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "r_portability", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
