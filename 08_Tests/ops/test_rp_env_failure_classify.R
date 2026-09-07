#!/usr/bin/env Rscript
# test_rp_env_failure_classify.R — 환경 실패는 논문의 증거가 아니다 (2026-09-07 실사고)
#
# 실사고: 충실구현 레인이 Fable 모델 한도에 걸렸다.
#   로그에 "You've reached your Fable limit. Switch to another model, or manage usage
#   credits at claude.ai/settings/usage..." 가 찍혔는데, 환경/리서치 실패를 가르는 분기가
#   OAuth·401 만 보고 한도 문구는 안 봤다. 그래서 `no_engine`(리서치 실패)로 떨어졌고
#   재시도 3회를 태운 뒤 **3편 결합 논문이 replication_skiplist.json 에 'unreproducible'
#   로 영구 등재**될 참이었다. 모델이 안 떴다는 사실은 그 논문에 대한 증거가 아니다.
#
# 같은 블록에서 두 번째 결함: 인증만료 알림이 **한 번도 나간 적이 없다**. 구판 PYX 는
#   따옴표 헤레독이라 $ROOT 가 안 풀려 리터럴 경로였고, 파이썬 문자열 안에 생짜 개행이
#   있어 파싱에서 죽었다 — `2>/dev/null || true` 가 그 죽음을 통째로 삼켰다.
#   (계기가 잴 것을 안 재고 재기 쉬운 것을 잰다 · 조용한 실패의 전형)
#
# 세 번째: 백오프가 없어 한도 소진 중에도 매 tick(≈4분) 빈 CLI 호출이 쌓인다.
#
# 양방향: 양성(실제 문구가 잡힌다 · 알림이 실제로 써진다 · 예산 미소모) +
#         위반 주입(한도 문구를 목록에서 빼면 미분류로 떨어진다 = 검출력 실증) +
#         과잉 차단 금지(평범한 리서치 실패 로그는 환경 실패로 안 잡힌다).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY   <- Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"))
SH   <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh")
SBX  <- file.path(tempdir(), sprintf("rpenv_%d", Sys.getpid()))
dir.create(SBX, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(SH)) { ng("표적 스크립트 부재", SH); quit(status = 1L) }
SRC <- readLines(SH, encoding = "UTF-8", warn = FALSE)

## ── 도구: 분류 블록을 소스에서 재도출한다 (행번호 못박지 않는다 — 리팩터가 옮긴다) ──
extract_classifier <- function(ln) {
  st <- which(trimws(ln) == 'ENV_FAIL=""')
  if (!length(st)) return(NULL)
  st <- st[1]
  fi <- which(trimws(ln) == "fi")
  fi <- fi[fi > st]
  if (!length(fi)) return(NULL)
  ln[st:fi[1]]
}
## 따옴표 헤레독 본문을 이름으로 뽑는다 (주석 줄 제외 — 주석 안 토큰을 코드로 읽으면 오탐한다)
extract_heredoc <- function(ln, name) {
  code <- ifelse(grepl("^\\s*#", ln), "", ln)
  op <- grep(paste0("<<'", name, "'"), code, fixed = TRUE)
  cl <- which(trimws(code) == name)
  if (!length(op)) return(NULL)
  cl <- cl[cl > op[1]]
  if (!length(cl)) return(NULL)
  if (cl[1] - op[1] < 2L) return(character(0))
  ln[(op[1] + 1L):(cl[1] - 1L)]
}

cat("=== A. 양성 — 실제 한도 문구가 환경 실패로 분류된다 ===\n")
CLS <- extract_classifier(SRC)
if (!is.null(CLS) && length(CLS) >= 4L) ok(sprintf("A0 분류 블록 추출 %d줄", length(CLS))) else {
  ng("A0 분류 블록을 못 찾았다 — 검사가 표적을 잃었다"); CLS <- NULL }

run_classifier <- function(body, log_text, tag) {
  lf <- file.path(SBX, sprintf("log_%s.txt", tag))
  writeLines(log_text, lf, useBytes = TRUE)
  sf <- file.path(SBX, sprintf("cls_%s.sh", tag))
  writeLines(c("#!/usr/bin/env bash", "LOG=\"$1\"", body, 'printf %s "$ENV_FAIL"'), sf, useBytes = TRUE)
  out <- suppressWarnings(system2("bash", c(shQuote(sf), shQuote(lf)), stdout = TRUE, stderr = TRUE))
  paste(out %||% "", collapse = "")
}

## ★실사고 그대로의 문구 (2026-09-07 replication_auto 로그에서 발췌)
QUOTA_MSG <- "You've reached your Fable limit. Switch to another model, or manage usage credits at claude.ai/settings/usage?from=cc_cli_limit_message, to continue."
AUTH_MSG  <- "API Error: 401 OAuth access token has expired"
BENIGN    <- c("[replication] 권위 등급 = F (15bps 판 · OK)",
               "[rp_vfy] base_below_threshold",
               "경고메시지(들): 1: table.Drawdowns(ret_xts, top = 100)에서: Only 15 available in the data.",
               "engine.R 산출 실패 — 논문 신호 정의가 모호해 구현을 접었다")

if (!is.null(CLS)) {
  r <- run_classifier(CLS, QUOTA_MSG, "quota")
  if (identical(r, "model_quota_exhausted"))
    ok("A1 한도 문구 → model_quota_exhausted") else
    ng("A1 한도 문구가 환경 실패로 안 잡힌다 — 실사고 재발", sprintf("얻은 값 '%s'", r))

  r <- run_classifier(CLS, AUTH_MSG, "auth")
  if (identical(r, "claude_auth_expired"))
    ok("A2 인증만료 문구 → claude_auth_expired (회귀 없음)") else
    ng("A2 인증만료 분류가 깨졌다", sprintf("얻은 값 '%s'", r))

  ## 429 · usage limit 변형도 잡아야 한다 (문구는 CLI 판마다 바뀐다)
  r <- run_classifier(CLS, "API Error: 429 rate_limit_error", "429")
  if (identical(r, "model_quota_exhausted")) ok("A3 429/rate_limit 변형도 잡는다") else
    ng("A3 429 변형 미검출", sprintf("얻은 값 '%s'", r))

  cat("=== B. 과잉 차단 금지 — 평범한 리서치 실패는 환경 실패가 아니다 ===\n")
  r <- run_classifier(CLS, BENIGN, "benign")
  if (identical(r, ""))
    ok("B1 리서치 실패 로그는 미분류(no_engine 경로 유지)") else
    ng("B1 평범한 실패를 환경 실패로 오분류 — 진짜 실패가 영원히 재시도된다", sprintf("얻은 값 '%s'", r))

  cat("=== C. 위반 주입 — 한도 문구를 목록에서 빼면 잡히는가 ===\n")
  ## 구판 재현: elif 분기(한도)를 통째로 지운다 → 한도 문구가 미분류로 떨어져야 한다
  bad <- CLS[!grepl("model_quota_exhausted", CLS, fixed = TRUE)]
  bad <- bad[!grepl("manage usage credits", bad, fixed = TRUE)]
  rb <- run_classifier(bad, QUOTA_MSG, "inject")
  if (!identical(rb, "model_quota_exhausted"))
    ok("C1 한도 분기를 빼면 미분류 — 이 검사가 실사고를 실제로 잡는다") else
    ng("C1 분기를 빼도 통과 — 검출력 없음")
}

cat("=== D. 알림 블록이 실제로 실행된다 (구판은 파싱에서 죽었다) ===\n")
PYX <- extract_heredoc(SRC, "PYX")
if (!is.null(PYX) && length(PYX) >= 3L) ok(sprintf("D0 알림 블록 추출 %d줄", length(PYX))) else
  ng("D0 알림 블록을 못 찾았다")
if (!is.null(PYX) && length(PYX)) {
  pf <- file.path(SBX, "alert.py")
  writeLines(PYX, pf, useBytes = TRUE)
  aroot <- file.path(SBX, "alert_root"); dir.create(aroot, showWarnings = FALSE)
  out <- suppressWarnings(system2(PY, c(shQuote(pf), shQuote(aroot), "model_quota_exhausted"),
                                  stdout = TRUE, stderr = TRUE))
  rc <- attr(out, "status") %||% 0L
  if (identical(as.integer(rc), 0L)) ok("D1 알림 블록 rc=0 (파싱·실행 성공)") else
    ng("D1 알림 블록이 죽는다 — 구판 병 재발", paste(utils::head(out, 3), collapse = " "))
  ad <- file.path(aroot, ".cache", "scheduler_alerts")
  fs <- list.files(ad, pattern = "alert$", full.names = TRUE)
  if (length(fs)) ok(sprintf("D2 알림 파일이 실제로 써진다 (%s)", basename(fs[1]))) else
    ng("D2 알림 파일 0건 — 경보가 나가지 않는다")
  if (length(fs) && file.info(fs[1])$size > 0) ok("D3 알림 내용 비지 않음") else
    ng("D3 알림 파일이 비었다")
  ## ★리터럴 $ROOT 디렉터리가 생기면 구판 병(따옴표 헤레독 미전개)이 살아 있는 것이다
  if (!dir.exists(file.path(getwd(), "$ROOT")) && !dir.exists(file.path(SBX, "$ROOT")))
    ok("D4 리터럴 '$ROOT' 디렉터리 미생성 — 셸변수가 실제로 전개된다") else
    ng("D4 리터럴 $ROOT 경로가 생겼다 — 따옴표 헤레독 미전개")
}

cat("=== E. 재시도 예산 미소모 + 백오프 기록 ===\n")
PYENV <- extract_heredoc(SRC, "PYENV")
if (!is.null(PYENV) && length(PYENV) >= 3L) ok(sprintf("E0 상태 갱신 블록 추출 %d줄", length(PYENV))) else
  ng("E0 상태 갱신 블록을 못 찾았다")
if (!is.null(PYENV) && length(PYENV)) {
  ef <- file.path(SBX, "envstate.py")
  writeLines(PYENV, ef, useBytes = TRUE)
  rq <- file.path(SBX, "req.json")
  ## 픽스처는 합성한다 — 운영 replication_request.json 을 빌리면 그 파일을 고칠 때 검사가 깨진다
  writeLines(paste0('{"status":"in_progress","auto_retries":2,"failure":"no_engine",',
                    '"paper":{"paper_key":"combo:aaa+bbb"}}'), rq, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, c(shQuote(ef), shQuote(rq), "model_quota_exhausted", "1800"),
                                  stdout = TRUE, stderr = TRUE))
  rc <- attr(out, "status") %||% 0L
  if (identical(as.integer(rc), 0L)) ok("E1 상태 갱신 rc=0") else
    ng("E1 상태 갱신이 죽는다", paste(utils::head(out, 3), collapse = " "))
  txt <- paste(readLines(rq, encoding = "UTF-8", warn = FALSE), collapse = "")
  gv <- function(k) {
    m <- regexpr(paste0('"', k, '"\\s*:\\s*"?([^",}]*)'), txt, perl = TRUE)  # perl=TRUE — 금칙 6
    if (m[1] < 0) return(NA_character_)
    sub(paste0('.*"', k, '"\\s*:\\s*"?'), "", regmatches(txt, m)[[1]], perl = TRUE)
  }
  if (identical(gv("auto_retries"), "2"))
    ok("E2 재시도 예산 불변(2) — 환경 실패가 논문 예산을 안 태운다") else
    ng("E2 재시도 예산이 소모됐다 — skiplist 로 가는 경로가 살아 있다", sprintf("auto_retries=%s", gv("auto_retries")))
  if (identical(gv("status"), "pending"))
    ok("E3 status=pending 복원 — 환경 풀리면 자동 재개") else
    ng("E3 status 복원 실패", sprintf("status=%s", gv("status")))
  if (identical(gv("last_env_failure"), "model_quota_exhausted"))
    ok("E4 사유가 환경 실패로 기록된다") else ng("E4 사유 미기록", gv("last_env_failure"))
  ra <- suppressWarnings(as.numeric(gv("env_retry_after_epoch")))
  if (is.finite(ra) && ra > as.numeric(Sys.time()) + 1000)
    ok("E5 백오프 시각이 미래로 기록된다(≈30분)") else
    ng("E5 백오프 미기록 — 한도 중에도 매 tick 빈 호출", sprintf("epoch=%s", gv("env_retry_after_epoch")))
  ## 인증만료는 백오프를 걸지 않는다 — 사람이 고치면 즉시 재개돼야 한다
  writeLines('{"status":"in_progress","auto_retries":0}', rq, useBytes = TRUE)
  invisible(suppressWarnings(system2(PY, c(shQuote(ef), shQuote(rq), "claude_auth_expired", "1800"),
                                     stdout = TRUE, stderr = TRUE)))
  txt <- paste(readLines(rq, encoding = "UTF-8", warn = FALSE), collapse = "")
  if (!grepl("env_retry_after_epoch", txt, fixed = TRUE))
    ok("E6 인증만료엔 백오프 없음 — 재인증 즉시 재개") else
    ng("E6 인증만료에도 30분 대기가 걸린다")
}

cat("=== F. 백오프 게이트가 레인에 실재한다 ===\n")
if (any(grepl("env_retry_after_epoch", SRC, fixed = TRUE)) &&
    any(grepl("halt_env_cooldown", SRC, fixed = TRUE)))
  ok("F1 쿨다운 게이트가 소스에 있다") else
  ng("F1 백오프를 기록만 하고 읽는 자가 없다 — 쓰는 자만 있는 이음매")
## 게이트가 pending 게이트 뒤(= 모델 호출 앞)에 있어야 한다
gi <- which(grepl("halt_env_cooldown", SRC, fixed = TRUE))[1]
pi <- which(grepl("no_pending_request", SRC, fixed = TRUE))
pi <- pi[pi > 100L][1]
ci <- which(grepl("timeout 3000 claude -p", SRC, fixed = TRUE))[1]
if (all(is.finite(c(gi, pi, ci))) && gi > pi && gi < ci)
  ok("F2 게이트가 pending 판정 뒤·모델 호출 앞에 있다") else
  ng("F2 게이트 위치가 어긋난다 — 도달 불가하거나 예산을 이미 쓴 뒤",
     sprintf("gate=%s pending=%s call=%s", gi, pi, ci))

cat("=== G. 따옴표 헤레독 전수 — 파싱 + 셸변수 미전개 0건 ===\n")
## ★구판 결함이 안 보였던 이유: 스캐너가 <<'X' 뒤에 리다이렉션이 붙은 블록을 놓쳤다.
##   여기서는 주석을 지우고, 여는 줄 뒤 임의 텍스트를 허용해 전수를 잡는다.
code <- ifelse(grepl("^\\s*#", SRC), "", SRC)
ops <- grep("<<'PY", code, fixed = TRUE)
nms <- character(0)
for (i in ops) {
  m <- regexpr("<<'(PY[A-Z]*)'", code[i], perl = TRUE)     # perl=TRUE — 금칙 6
  if (m[1] > 0) nms <- c(nms, gsub("[<']", "", regmatches(code[i], m)[[1]]))
}
nms <- unique(nms)
if (length(nms) >= 4L) ok(sprintf("G0 헤레독 %d종 발견: %s", length(nms), paste(nms, collapse = ", "))) else
  ng("G0 헤레독을 거의 못 찾았다 — 스캔이 표적을 잃었다", paste(nms, collapse = ","))
gbad <- 0L
for (nm in nms) {
  body <- extract_heredoc(SRC, nm)
  if (is.null(body) || !length(body)) { ng(sprintf("G:%s 본문 추출 실패", nm)); gbad <- gbad + 1L; next }
  bf <- file.path(SBX, paste0("hd_", nm, ".py"))
  writeLines(body, bf, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, c("-m", "py_compile", shQuote(bf)), stdout = TRUE, stderr = TRUE))
  if (identical(as.integer(attr(out, "status") %||% 0L), 0L)) ok(sprintf("G:%s 파싱 OK", nm)) else {
    ng(sprintf("G:%s 파싱 실패 — 조용히 죽는 블록", nm), paste(utils::head(out, 2), collapse = " ")); gbad <- gbad + 1L }
  hit <- grep('"\\$[A-Z_]', body, perl = TRUE, value = TRUE)   # perl=TRUE — 금칙 6
  if (length(hit)) {
    ng(sprintf("G:%s 따옴표 헤레독 안 미전개 셸변수", nm), trimws(substr(hit[1], 1, 70))); gbad <- gbad + 1L }
}
if (gbad == 0L) ok("G1 전 헤레독 파싱·전개 정상")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rp_env_failure_classify","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
