#==============================================================================
# test_daily_refresh_r_blocks.R — 무인 일일 체인에 내장된 R 블록 구문 사전검사
#
# 왜 (2026-08-02 실사고):
#   daily_refresh.sh 의 r18(완료/부분실패 텔레그램 통보) 블록이 **최상위 if/else 를
#   두 줄로 쪼갠** 형태였다:
#       .hdr <- if (cond) "완료"
#               else sprintf("★부분실패 — %s", .fails)
#   R 은 줄바꿈에서 if 문을 닫으므로 다음 줄의 else 가 고아가 된다
#   ("unexpected 'else'"). 결과: 그 스텝이 파싱 단계에서 죽어 DailyRefresh 가
#   rc=1 로 끝났고, **무엇보다 그 블록이 바로 일일 성공/실패를 알리는 통보 스텝**이라
#   실패 요약이 텔레그램에 영영 도달하지 않았다. 실패를 보이게 하려고 넣은 코드가
#   자기 자신 때문에 안 보이게 된 셈이다.
#
#   이 저장소에는 이 블록들을 **실행 전에** 검사하는 장치가 0건이었다. 구문 오류는
#   해당 스텝이 실제로 도는 새벽에만, 로그 안에서만 드러난다.
#
# 무엇을 재는가:
#   run_r '<R 코드>' 로 내장된 모든 블록을 추출해 parse() 한다. 실행하지 않는다
#   (부작용 없음) — 구문만 본다.
#
# ★계측 사망 방지 = 독립 교차계수:
#   추출기가 조용히 0건/소수만 집으면 "전부 통과"로 위장된다. 그래서 추출 블록 수를
#   **독립적으로 센 opener 수**와 대조한다. 둘이 어긋나면 그 자체가 FAIL 이다.
#   (이 저장소의 반복 실패부류 = "검사기가 잘못된 것을 잼".)
#
# ★위반 주입 테스트 + 음성 통제 내장.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""))
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

# ─── 대상 (라이브 무인 체인만. _old_ 아카이브 사본 제외) ─────────────────────
TARGETS <- c("02_Infrastructure/data/daily_refresh.sh")

# opener/closer 형태 (실측 2026-08-02):
#   opener : "run_r '"  · "  run_r '"  · "cd \"$INFRA\" && run_r '"
#   closer : "'"  · "  '"  · "' 2>&1"  · "  ' 2>&1"
RE_OPEN  <- "run_r[[:space:]]+'[[:space:]]*$"
RE_CLOSE <- "^[[:space:]]*'([[:space:]].*)?$"

extract_blocks <- function(lines) {
  out <- list(); i <- 1L; n <- length(lines)
  while (i <= n) {
    if (grepl(RE_OPEN, lines[i])) {
      start <- i + 1L; j <- start
      while (j <= n && !grepl(RE_CLOSE, lines[j])) j <- j + 1L
      if (j <= n) {
        out[[length(out) + 1L]] <- list(start = start, end = j - 1L,
                                        src = if (j > start) lines[start:(j - 1L)] else character(0))
        i <- j + 1L; next
      }
    }
    i <- i + 1L
  }
  out
}

# 셸 인용부호 스플라이스 복원 (실측 6곳: setwd("'"$BASE"'") )
#   bash 는 '...' 안에서 '"$VAR"' 를 만나면 따옴표를 닫고 $VAR 를 확장한 뒤 다시 연다.
#   즉 R 이 실제로 받는 텍스트는 setwd("C:/...") 다. 구문검사 시점에는 확장값을 알 수
#   없으므로 **그 자리만** 안전한 리터럴 토큰으로 치환한다.
#   ★치환 범위를 이 관용구로 한정하는 이유: 넓게 지우면 진짜 구문 오류까지 덮어
#   검사기가 무력해진다. 아래 injection_splice_with_dangling_else 가 그 경계를 지킨다.
SPLICE_TOKEN <- "__SHELL_SUBST__"
splice_shell <- function(src) {
  src <- gsub("'\"\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}\"'", SPLICE_TOKEN, src)
  src <- gsub("'\"\\$[A-Za-z_][A-Za-z0-9_]*\"'",       SPLICE_TOKEN, src)
  src <- gsub("'\"\\$\\([^)]*\\)\"'",                  SPLICE_TOKEN, src)
  src
}

parse_ok <- function(src) {
  if (!length(src)) return("빈 블록")
  tryCatch({ parse(text = splice_shell(src)); NA_character_ },
           error = function(e) conditionMessage(e))
}

cat("=== daily_refresh 내장 R 블록 구문 검사 ===\n")

for (tgt in TARGETS) {
  if (!file.exists(tgt)) {
    bad(sprintf("target_missing[%s]", tgt), "대상 스크립트 부재 — 경로 드리프트 의심")
    next
  }
  L <- readLines(tgt, warn = FALSE, encoding = "UTF-8")
  blocks <- extract_blocks(L)

  # (교차계수) 추출 수 vs 독립 opener 수 — 어긋나면 추출기가 사망한 것이다
  n_open <- sum(grepl(RE_OPEN, L))
  if (length(blocks) == n_open && n_open > 0L) {
    ok(sprintf("block_extraction[%s]", basename(tgt)),
       sprintf("블록 %d개 추출 = opener %d개 (교차계수 일치)", length(blocks), n_open))
  } else {
    bad(sprintf("block_extraction[%s]", basename(tgt)),
        sprintf("추출 %d != opener %d — 추출기 사망/형태 드리프트 (0건 통과 위장 차단)",
                length(blocks), n_open))
  }

  for (b in blocks) {
    err <- parse_ok(b$src)
    nm <- sprintf("parse[%s:%d]", basename(tgt), b$start)
    if (is.na(err)) ok(nm) else bad(nm, sprintf("구문 오류 — %s", gsub("[\r\n]+", " ", err)))
  }
}

# ─── 위반 주입 테스트 ────────────────────────────────────────────────────────
# 합성 위반을 실제로 잡는가? 못 잡으면 위 통과는 계측 사망이지 통과가 아니다.
inject <- list(
  list(name = "toplevel_dangling_else",
       src = c('.fails <- "x"',
               '.hdr <- if (identical(.fails, "none")) "[OK]"',
               '        else sprintf("[FAIL %s]", .fails)')),
  list(name = "unbalanced_brace",
       src = c('f <- function(x) {', '  x + 1')),
  list(name = "unclosed_string",
       src = c('msg <- "abc')),
  # 스플라이스 복원이 진짜 구문 오류를 덮지 않는지 — 치환 경계의 파수꾼
  list(name = "splice_with_dangling_else",
       src = c('setwd("\'"$BASE"\'")',
               '.hdr <- if (TRUE) "[OK]"',
               '        else "[FAIL]"'))
)
for (fx in inject) {
  if (!is.na(parse_ok(fx$src))) {
    ok(sprintf("injection_%s", fx$name), "합성 구문 위반 검출됨")
  } else {
    bad(sprintf("injection_%s", fx$name), "합성 위반을 통과시킴 — 검사기 무력(계측 사망)")
  }
}

# ─── 음성 통제: 정상 블록을 오검출하면 안 된다 ───────────────────────────────
clean <- c('library(data.table)',
           '.fails <- Sys.getenv("DR_FAILED_SO_FAR", "none")',
           '.hdr <- if (identical(.fails, "none")) {',
           '  "[OK]"',
           '} else {',
           '  sprintf("[FAIL %s]", .fails)',
           '}',
           'if (nzchar(.hdr)) cat(.hdr, "\\n")')
if (is.na(parse_ok(clean))) {
  ok("false_positive_control", "정상 블록 오검출 0")
} else {
  bad("false_positive_control", sprintf("정상 블록을 위반으로 오검출: %s", parse_ok(clean)))
}

# 스플라이스 복원 자체의 양성 대조 — 관용구가 실제로 복원되는지(치환기 미발화 방지)
splice_fx <- c('setwd("\'"$BASE"\'")', 'x <- 1')
if (any(grepl(SPLICE_TOKEN, splice_shell(splice_fx), fixed = TRUE)) && is.na(parse_ok(splice_fx))) {
  ok("splice_restore_control", "셸 스플라이스 관용구 복원 후 정상 파싱")
} else {
  bad("splice_restore_control", "스플라이스 치환기 미발화 — 관용구가 오검출로 돌아옴")
}

# ─── 위반 주입 (실파일 사본) ────────────────────────────────────────────────
# 위 주입들은 합성 조각이다. 여기서는 **실제 대상 파일을 복사해** 첫 블록에 고아 else 를
# 심고, 추출→스플라이스 복원→파싱 전 경로가 그것을 잡는지 본다. 원본은 건드리지 않는다.
# (합성 fixture 만으로는 "추출기가 실파일에서 그 줄에 도달하는가"를 증명하지 못한다.)
local({
  tgt <- TARGETS[1]
  if (!file.exists(tgt)) return(invisible(NULL))
  L2 <- readLines(tgt, warn = FALSE, encoding = "UTF-8")
  opens <- which(grepl(RE_OPEN, L2))
  if (!length(opens)) {
    bad("injection_real_file_copy", "opener 0건 — 주입 대상 없음")
    return(invisible(NULL))
  }
  L2 <- append(L2, c('.probe <- if (TRUE) "a"', '        else "b"'), after = opens[1])
  tmp <- tempfile(fileext = ".sh")
  on.exit(unlink(tmp), add = TRUE)   # 함수 프레임 내부 — r-portability 금칙 ② 대상 아님
  writeLines(L2, tmp, useBytes = TRUE)
  b2 <- extract_blocks(readLines(tmp, warn = FALSE, encoding = "UTF-8"))
  nfail <- sum(vapply(b2, function(b) !is.na(parse_ok(b$src)), logical(1)))
  if (nfail >= 1L) {
    ok("injection_real_file_copy", sprintf("실파일 사본에 심은 고아 else → parse 실패 %d건 검거", nfail))
  } else {
    bad("injection_real_file_copy", "실파일에 심은 고아 else 를 놓침 — 추출→파싱 전 경로 무력")
  }
})

# ─── 요약 ────────────────────────────────────────────────────────────────────
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "daily_refresh_r_blocks", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
