# test_backtest_contract_audit_gate.R — 원장 integrity 게이트 훅의 **발화 실증**
#
# 대상: 02_Infrastructure/hooks/backtest_contract_audit.sh
#
# 왜 이 시험이 본체인가 (2026-08-24):
#   이 훅은 2026-08-23 플랜 D-d 로 **등록 해제**돼 있었다. 해제 사유는 원장 integrity
#   차단이 아니라 `.py` 자체합성 idiom 차단의 **오탐**(v8.4 ML 레인의 정상 .py Write 가
#   걸림)이었다. 오탐 가지만 잘라내고 재등록하는데, 그 재등록이 다음 둘을 동시에
#   만족해야 정당하다:
#     [양성] integrity == "FAIL" 인 bt_result 를 원장에 등재하려 하면 **실제로 막는가**
#     [음성] 해제 사유였던 .py 오탐이 **실제로 사라졌는가**
#   두 번째가 없으면 "고쳤다"는 주장이 근거를 못 갖고, 첫 번째가 없으면 살아있지도
#   않은 게이트를 헌법에 방어선으로 적는 상태가 반복된다(이번에 발견된 그 상태다).
#
# ★그리고 이 저장소에서 훅은 **두 번 조용히 죽었다** — selection_contamination_detector
#   (구조적 상시-allow) · lockbox_audit_trail(판정 기능 없음). 기전이 훅이라고 안전한 게
#   아니다. 양성 대조 없는 계기는 등재하지 않는다.

suppressPackageStartupMessages({ })

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
ok  <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng  <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }
sk  <- function(axis, reason, missing) {
  SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat("  SKIP ", axis, " — ", reason, "\n")
}
emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"backtest_contract_audit_gate","pass":%d,"fail":%d,"total":%d,"skipped":%d',
               PASS, FAIL, PASS + FAIL, SKIP)
  if (SKIP > 0L) {
    parts <- vapply(SKIPS, function(s)
      sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', s$axis, s$reason, s$missing), character(1))
    j <- paste0(j, ',"skips":[', paste(parts, collapse = ","), "]")
  }
  cat(paste0(j, "}\n"))
  quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

# ── 앵커: 자기 트리 우선 ([[feedback-code-root-is-not-data-root]]) ──────────
.self_dir <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self_dir, "..", ".."), winslash = "/", mustWork = FALSE)
HOOK <- file.path(ROOT, "02_Infrastructure", "hooks", "backtest_contract_audit.sh")

cat("=== backtest_contract_audit gate ===\n")
cat(sprintf("HOOK: %s\n\n", HOOK))

if (!file.exists(HOOK)) { sk("hook_present", "훅 파일 부재", HOOK); emit() }
BASH <- Sys.which("bash")
if (!nzchar(BASH)) { sk("bash_available", "bash 미탐지", "bash"); emit() }

HOOK_SRC <- readLines(HOOK, warn = FALSE)

#' 샌드박스 PROJECT 를 세우고 훅을 돌린다.
#' @param integrity  NULL 이면 bt_result.rds 를 만들지 않는다
#' @param hook_path  돌릴 훅(돌연변이 사본을 넘길 수 있다)
run_hook <- function(payload, integrity = NULL, hook_path = HOOK) {
  sb <- normalizePath(tempfile("qv_bca_"), winslash = "/", mustWork = FALSE)
  dir.create(file.path(sb, "04_Research", "strategies", "STR_FIXTURE"),
             recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(sb, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  if (!is.null(integrity)) {
    saveRDS(list(manifest = list(integrity_status = integrity)),
            file.path(sb, "04_Research", "strategies", "STR_FIXTURE", "bt_result.rds"))
  }
  inf <- tempfile("qv_bca_in_"); writeLines(payload, inf)
  outf <- tempfile("qv_bca_out_")
  old <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = NA)
  # ★Windows 에서 system2(env=) 는 무시된다 — Sys.setenv 로 넣고 복원한다
  #   ([[reference-r-portability]] 금칙 ①. 이 계통으로 오늘 다른 세션이 생산 원장을
  #    건드릴 뻔했다.)
  Sys.setenv(CLAUDE_PROJECT_DIR = sb)
  on.exit({ if (is.na(old)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = old) },
          add = TRUE)
  rc <- suppressWarnings(system2(BASH, c(hook_path), stdin = inf, stdout = outf, stderr = NULL))
  txt <- if (file.exists(outf)) paste(readLines(outf, warn = FALSE), collapse = "") else ""
  list(rc = rc, out = txt, blocked = grepl('"decision"\\s*:\\s*"block"', txt))
}

pl <- function(fp, extra = "") sprintf('{"tool_name":"Write","tool_input":{"file_path":"%s"%s}}',
                                       fp, extra)
REG <- "C:/x/qepm/registry/backtest_registry.csv"

# ── A. 양성 대조 — 게이트가 실제로 막는가 ───────────────────────────────────
cat("── A. 양성 대조 (integrity=FAIL → block) ───────────────────\n")
a1 <- run_hook(pl(REG), integrity = "FAIL")
if (a1$blocked) ok("integrity=FAIL 원장 등재 시도 → decision:block") else
  ng("★게이트가 안 막는다 — 살아있지 않은 방어선", substr(a1$out, 1, 160))

if (grepl("integrity=FAIL", a1$out, fixed = TRUE) || grepl("§20", a1$out, fixed = TRUE))
  ok("차단 사유에 계약 근거(§20 / integrity=FAIL) 명시") else
  ng("차단 사유가 조치 불가능", substr(a1$out, 1, 160))

# ── B. 음성 대조 — 정상 경로를 막지 않는가 ──────────────────────────────────
cat("\n── B. 음성 대조 ────────────────────────────────────────────\n")
b1 <- run_hook(pl(REG), integrity = "PASS")
if (!b1$blocked) ok("integrity=PASS → allow") else
  ng("★정상 산출물을 막는다", substr(b1$out, 1, 160))

b2 <- run_hook(pl(REG), integrity = NULL)
if (!b2$blocked) ok("최근 bt_result 부재 → allow (판정 불가는 차단 아님)") else
  ng("★근거 없이 막는다", substr(b2$out, 1, 160))

b3 <- run_hook(pl("C:/x/04_Research/notes/scratch.md"), integrity = "FAIL")
if (!b3$blocked) ok("비대상 경로는 integrity=FAIL 이어도 allow (대상 범위 준수)") else
  ng("★대상 범위 밖을 막는다", substr(b3$out, 1, 160))

# ── C. ★해제 사유가 실제로 제거됐는가 (.py 오탐) ────────────────────────────
cat("\n── C. ★해제 사유 제거 실증 (.py 자체합성 오탐) ─────────────\n")
PY_PAYLOAD <- ',"content":"import numpy as np\\nnav = np.prod(1 + r)\\ncum = (1 + r).cumprod()\\n"'
c1 <- run_hook(pl("C:/x/02_Infrastructure/ml/train_model.py", PY_PAYLOAD), integrity = NULL)
if (!c1$blocked)
  ok(".py + 자체합성 idiom → allow (2026-08-23 해제 사유가 사라졌다)") else
  ng("★오탐 잔존 — 이 상태로 재등록하면 v8.4 ML 레인이 다시 막힌다", substr(c1$out, 1, 160))

# C-2 돌연변이 통제: 구판 가지를 되살리면 같은 페이로드가 **실제로 막히는가**
#   이게 뒤집히지 않으면 축 C-1 은 아무것도 재고 있지 않다(페이로드가 애초에
#   idiom 을 안 담았을 수도 있으므로 반드시 확인한다).
mut <- tempfile("qv_bca_mut_", fileext = ".sh")
src <- HOOK_SRC
i <- grep("^TARGET_PATTERN=", src)
if (length(i) != 1L) {
  ng("★돌연변이 사본 생성 실패 — TARGET_PATTERN 앵커 이상", sprintf("%d회", length(i)))
} else {
  # ★정규식 이스케이프를 쓰지 않는다(fixed = TRUE) — 셸/R 왕복에서 백슬래시가 한 단계씩
  #   먹히면 치환이 조용히 실패하고, 그 실패가 "구판에서도 안 막힘"으로 오귀속된다.
  src[i] <- sub("metrics_official\\.csv$)", "metrics_official\\.csv$|\\.py$)",
                src[i], fixed = TRUE)
  old_branch <- c(
    'if echo "$FILE_PATH" | grep -qE \'\\.py$\'; then',
    "  PY_SYNTH_PATTERN='np\\.prod\\( *1 *\\+|\\( *1 *\\+ *[A-Za-z_][A-Za-z0-9_.]* *\\)\\.cumprod\\('",
    '  if echo "$INPUT" | grep -qE "$PY_SYNTH_PATTERN"; then',
    '    echo \'{"decision": "block", "reason": "python-policy.md §4 (mutant)"}\'',
    "    exit 0",
    "  fi",
    "  echo '{}'; exit 0",
    "fi")
  # 구판 가지는 TARGET_PATTERN **가드(if…fi) 뒤**에 와야 한다. 가드 안에 넣으면
  #   도달 자체를 못 해 "구판도 안 막는다"는 거짓 결론이 난다(첫 판이 그랬다).
  gi  <- grep("TARGET_PATTERN\"", src, fixed = TRUE)
  fi_ <- if (length(gi)) which(src == "fi" & seq_along(src) > gi[1])[1] else NA_integer_
  # ★조작 선행검증 — 사본이 실제로 "구판" 상태가 됐는지 **먼저** 확인한다.
  if (!grepl(".py$", src[i], fixed = TRUE)) {
    ng("★조작 선행검증 실패 — 사본 TARGET_PATTERN 에 .py 가 안 들어갔다", src[i])
  } else if (is.na(fi_)) {
    ng("★조작 선행검증 실패 — TARGET_PATTERN 가드 끝(fi)을 못 찾았다")
  } else {
    src <- append(src, old_branch, after = fi_)
    writeLines(src, mut)
    c2 <- run_hook(pl("C:/x/02_Infrastructure/ml/train_model.py", PY_PAYLOAD),
                   integrity = NULL, hook_path = mut)
    if (c2$blocked)
      ok("돌연변이 통제: 구판 가지를 되살리면 같은 페이로드가 block — 축 C-1 이 실제로 잰다") else
      ng("★돌연변이 통제 실패 — 구판에서도 안 막힌다. 축 C-1 은 무의미하다",
         substr(c2$out, 1, 160))
  }
}

# ── D. fail-closed 계약 (정적) ──────────────────────────────────────────────
cat("\n── D. fail-closed 계약 ─────────────────────────────────────\n")
j <- paste(HOOK_SRC, collapse = "\n")
if (grepl("trap '_gate_fail_closed' ERR", j, fixed = TRUE))
  ok("ERR trap 등록 — 내부 오류 시 fail-open 으로 새지 않는다") else
  ng("★fail-closed trap 부재")

fc <- grep("_gate_fail_closed\\(\\)", HOOK_SRC)
if (length(fc)) {
  body <- paste(HOOK_SRC[fc[1]:min(fc[1] + 12L, length(HOOK_SRC))], collapse = "\n")
  need <- c("backtest_registry", "methodology_", "metrics_official")
  miss <- need[!vapply(need, function(x) grepl(x, body, fixed = TRUE), logical(1))]
  if (!length(miss))
    ok("fail-closed 대상이 TARGET_PATTERN 3종을 모두 덮는다") else
    ng("★fail-closed 누락", paste(miss, collapse = ","))
} else ng("★_gate_fail_closed 정의 미발견")

if (!grepl("PY_SYNTH_PATTERN", j, fixed = TRUE))
  ok("구 .py 가지가 실행 위치에 없다(재도입 래칫)") else
  ng("★PY_SYNTH_PATTERN 잔존")

emit()
