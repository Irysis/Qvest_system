#==============================================================================
# test_r_portability.R — R 측 Windows 이식성 계약 검사기
#
# 계약: 02_Infrastructure/docs/rules/r-portability.md (2026-07-25 승격)
#
# 라이브 존의 .R 을 스캔해 금칙 4종을 검출한다.
#   ① system2(..., env=)        — Windows에서 환경변수 아닌 인자 주입
#   ② 스크립트 최상위 on.exit() — 발화하지 않음(cleanup dead code)
#   ③ 선행 "/" 경로 하드코딩 / startsWith(p,"/") 절대경로 판정
#   ④ resolver 우선순위 QM_ROOT-before-CLAUDE_PROJECT_DIR
#
# 기수록 위반은 ALLOWLIST로 수용(원장 = rule 문서). 신규 위반만 FAIL —
# 원장을 줄이는 방향으로만 움직이게 한다.
#
# ★위반 주입 테스트 포함: 합성 위반 fixture를 실제로 잡는지 자체 검증.
#   검사기가 "잘못된 것을 재는" 실패가 이 리포지토리의 반복 부류라, 위반 주입 테스트
#   없는 검사기는 계약상 인정하지 않는다.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

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

baseline <- if (file.exists(BASELINE_PATH)) {
  b <- fromJSON(BASELINE_PATH, simplifyVector = TRUE)
  if (is.null(b$entries)) character(0) else as.character(b$entries)
} else character(0)

is_allowed <- function(key) key %in% baseline

rel_of <- function(p) sub(paste0("^", gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", PROJ), "/"), "", p)

# ─── 검출기 (파일 텍스트 → 위반 금칙코드 벡터) ──────────────────────────────
# 주석 줄은 제외 — 수리 노트가 자기 자신을 위반으로 잡는 것을 막는다.
strip_comments <- function(lines) lines[!grepl("^\\s*#", lines)]

# system2( ... ) 호출 본문을 괄호 균형으로 추출.
# ★구 구현은 grepl("system2\\([^)]*env\\s*=") 였는데 [^)]* 가 인자 안의 첫 ')'
#   (예: args = c("-c", code))에서 멈춰 다중행 호출을 놓쳤다 — 위반 주입 테스트가 적발.
.system2_calls <- function(txt) {
  out <- character(0)
  starts <- gregexpr("system2\\s*\\(", txt, perl = TRUE)[[1]]
  if (starts[1] == -1) return(out)
  chars <- strsplit(txt, "", fixed = TRUE)[[1]]
  for (s in starts) {
    open_at <- s + attr(starts, "match.length")[which(starts == s)][1] - 1L
    depth <- 0L; i <- open_at; n <- length(chars); endp <- NA_integer_
    while (i <= n) {
      if (chars[i] == "(") depth <- depth + 1L
      else if (chars[i] == ")") { depth <- depth - 1L; if (depth == 0L) { endp <- i; break } }
      i <- i + 1L
    }
    if (!is.na(endp)) out <- c(out, paste(chars[open_at:endp], collapse = ""))
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

  unique(hits)
}

CODE_NAME <- c("1" = "system2(env=)", "2" = "top-level on.exit",
               "3" = "leading-slash path", "4" = "resolver precedence")

# ─── 본 스캔 ─────────────────────────────────────────────────────────────────
cat("=== R portability contract scan ===\n")
cat(sprintf("  live zone: %s (%d files)\n", paste(LIVE_DIRS, collapse = ", "), length(live_files)))

found <- character(0)
for (f in live_files) {
  rel <- rel_of(f)
  if (identical(rel, "08_Tests/hooks/test_r_portability.R")) next   # 검사기 자신의 fixture 문자열 제외
  lines <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  if (!length(lines)) next
  for (code in detect(lines)) found <- c(found, paste0(rel, ":", code))
}
found <- sort(unique(found))

if (WRITE_BASELINE) {
  write_json(list(
    contract = "02_Infrastructure/docs/rules/r-portability.md",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    note = "기존 위반 원장. 신규 위반만 FAIL. 항목은 수리 시 제거만 — 추가는 계약 위반.",
    codes = as.list(CODE_NAME),
    entries = found
  ), BASELINE_PATH, pretty = TRUE, auto_unbox = TRUE)
  cat(sprintf("  [baseline] %d entries → %s\n", length(found), BASELINE_PATH))
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
               '           Sys.getenv("CLAUDE_PROJECT_DIR", ""))'))
)
for (fx in fixtures) {
  got <- detect(fx$src)
  if (fx$code %in% got) {
    ok(sprintf("negative_control_%s", fx$name), sprintf("합성 위반 금칙 %d 검출됨", fx$code))
  } else {
    bad(sprintf("negative_control_%s", fx$name),
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
  'system2(cmd, args = a, stdout = TRUE, stderr = TRUE)'
)
if (length(detect(clean_src)) == 0L) {
  ok("false_positive_control", "정본 패턴 오검출 0")
} else {
  bad("false_positive_control",
      sprintf("정본 패턴을 위반으로 오검출: %s", paste(detect(clean_src), collapse = ",")))
}

# ─── 요약 ────────────────────────────────────────────────────────────────────
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "r_portability", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
