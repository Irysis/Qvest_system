#!/usr/bin/env Rscript
# =============================================================================
# test_regime_ledger_c11.R — 국면 발행 원장(regime_append_only.R) C11 원장 경로 (양방향 · 돌연변이)
# =============================================================================
# 막는 결함(2026-09-24 실측 · 판정서 pit_c11_20260924 · 결정 PIT-C11-REMEDIATION 안 B):
#   A  병합 `.SDcols = names(pub)` 가 발행본(구 스키마) 열 목록으로 잘라 생산자 표식(avail_date · c11_regime_key ·
#      파일 속성 c11_avail_regime_key)을 매일 00:03 에 삭제 → 소비자 C11 가드가 legacy 로 보고 per_regime 보류.
#   B  아침 fred_regime.R(07:10)이 원장을 거치지 않고 전 이력을 재빌드해 라이브를 덮음 → 00:03 / 07:10 교대.
#      같은 병: self_heal.R 재빌드(월요일마다 stale 판정).
#   C  C11 이전 epoch 발행본과 C11 epoch 재생성본을 말없이 이어 붙임(혼합 원장).
#   D  재기준선(republish) 수단 부재 — 구 원장 보관 후 현행 epoch 로 재초기화(dry-run 기본).
# 축: T1 legacy 병합 = 구판(git blob 고정) 산출 동일 · T2 같은 epoch 병합 표식 보존(소비자 가드 판정 포함) ·
#     T3 동결 구간 재서술 검출(양성 대조 — 결정값 3열 + 가용일 · CLI 종료 1) · T4 epoch 불일치 무기록(종료 3)·반쪽 표식(2) ·
#     T5 00:03(daily_refresh 블록 원문 실행) → 07:10(fred_regime.R 원문 실행) 두 라이브 동일 · 빌드 실패 = 라이브 불변 ·
#     T6 재기준선 dry-run 무기록·계획 = 실행 결과 · 보관 해시 · 거부 조건 · 복원 · T7 동결 단조 · T8 배선 정적 검사 ·
#     T9 돌연변이 M1~M11(같은 픽스처에서 red).
# ── 2026-11-06 MSM 추정기 에폭 축(결정 PIT-C1-MSM-PARAMS 안 A · MSM-ASOF-SWITCH-20261017 · 적대 검토 #2·#7·#9·#14·#18) ──
#   설치본 regime_append_only.R 은 에폭을 합성 키 '<c11 키>|msm:<추정기>' 로 가른다(표식 = 행 열 msm_estimator ∪ 같은 이름
#   파일 속성 · 없음 = msm:legacy = 전 표본 C1 MSM · 값이 여럿/NA = 반쪽 표식). 그래서 T6 계획의 candidate_epoch 는 'K|msm:legacy'
#   (순수 C11 키 = candidate_c11)이고, M8 대상 줄은 `ec$c11, rk$c11` 판으로 옮겼다. 표식 값 = 생산자 regime_signal.R::
#   MSM_ESTIMATOR_EXPECTED 재도출(검사 쪽 리터럴 없음 · 규칙 키도 실행 시 규칙 파일에서 — 특정 키 문자열에 기대지 않는다). 새 축:
#     T11a 병합 — (a) 같은 C11 · legacy 원장 ↔ as-of 후보(양방향) 종료 3 · 무기록 · 에폭 문자열 = 합성 키
#          (b) 반쪽 MSM 표식 후보 4꼴(열 NA 혼재 · 열 전부 NA · 열 ≠ 속성 · 열 두 값) + 발행본 변조 → 종료 2 · 무기록
#          (c) meta msm_estimator ≠ parquet 표식 → 종료 2 · 무기록(대조: meta 필드 없음 = 전환 전 판 모양 → 병합 0 · 필드 채움)
#              + 이웃 축 meta c11_regime_key ≠ parquet(설치본이 ep$key → ep$c11 로 바꾼 줄) → 종료 2 · 무기록
#          (f) as-of 원장 + as-of 후보 → 0 · meta = 접두 없는 값 · 표식(열 + 속성) · C11 키 보존 · 드리프트 로그 에폭
#          (g) 병합 후 MSM 혼합(후보가 열을 잃고 속성만) → 종료 2 · 무기록
#     T11r 재발행(실행 플래그를 켠 채) — (d) 지정 '<K>|msm:<추정기>' + legacy 후보 = 거부 · 무기록(대조: as-of 후보 = 문제 0)
#          (e) 구 원장 as-of → legacy 후보 · 기본 규칙 키 = 'MSM 후퇴' 거부 · 무기록(대조: as-of 후보 = 문제 0)
#          (f) 전환 재발행(옛 C11 키 K2 · legacy · meta 필드 없음 → K · as-of): dry-run 계획 → --expect-plan 실행 → 첫 밤 병합 0
#     T11c CLI — 밤 루프 호출(--series daily --root --from-candidate) 종료 3 · 무기록 · 3단계 명령 모양(--rules-key · --reason ·
#          --plan-out 종료 0 → legacy 후보 거부 종료 2 + 거부 문구 → --expect-plan --execute 종료 0). ★종료 2 는 죽은 프로세스
#          (.rl_main 의 tryCatch)와 겹치므로 거부 문구 출력까지 단정한다.
#     T12 돌연변이 MA·MA3·MA2·MB·MC·MC2·MF·MG(→T11a) · MD·ME(→T11r) · MK·MR(→T11c) — 지킨 줄을 소스 텍스트 치환으로 지운 사본
#          (대상 정확히 1회 · 치환 성사 · 사본 ≠ 원본 · 사본 구문 해석 단정)에서 표적 검사가 전부 뒤집혀야 red.
#          치환 도구 mutant() 자체도 T9 첫머리에서 양성 대조한다(대상 부재 · 중복 · 구문 파손 = 거부 · 정상 치환 = 성사).
#   ★red 판정은 기준선 대비(적대 검토 #18 · T9 에도 적용): 같은 시나리오를 원본으로 돌려 TRUE 였던 검사가 FALSE 로 바뀌어야 red 다
#     (기준선이 이미 FALSE 인 검사는 어느 사본에서도 red 로 보인다). 시나리오 중단은 red 로 세지 않는다(FAIL).
# 쓰기: tempdir() 만. 운영 파일은 읽기만(대상 소스·규칙 파일·git blob).
# 실행: Rscript 08_Tests/regime/test_regime_ledger_c11.R   (자식은 이 검사가 빈 Renviron 으로 격리한다 — 2026-09-25 LEDGER B1 수리 · T10)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
GITDIR <- if (dir.exists(file.path(ROOT, ".git"))) ROOT else
  gsub("\\\\", "/", Sys.getenv("QVEST_TEST_GIT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
LIB    <- file.path(ROOT, "02_Infrastructure/regime/regime_append_only.R")
FREDRG <- file.path(ROOT, "02_Infrastructure/ops/morning_steps/fred_regime.R")
SELFH  <- file.path(ROOT, "02_Infrastructure/ops/morning_steps/self_heal.R")
ROOTR  <- file.path(ROOT, "02_Infrastructure/ops/morning_steps/_root.R")
DRSH   <- file.path(ROOT, "02_Infrastructure/data/daily_refresh.sh")
GUARD  <- file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R")
HELP   <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
RULES  <- file.path(ROOT, "06_Registry/fred_availability_rules.json")
UTP    <- file.path(ROOT, "02_Infrastructure/utils/atomic_parquet.R")
UTJ    <- file.path(ROOT, "02_Infrastructure/utils/atomic_json.R")
SIGNAL <- file.path(ROOT, "02_Infrastructure/regime/regime_signal.R")   # MSM 표식 생산자 — 표식 값 재도출용(읽기만)
## 구판 고정(git blob) — 배포 후 HEAD 가 신판이 돼도 비교 기준이 움직이지 않게 해시로 못박는다
BLOB_OLD_APPEND <- "eaf34c35a2c76ea155396b293323a26d142aec0a"   # regime_append_only.R (2026-08-13 판)
BLOB_OLD_FREDRG <- "5816076acb000226fedc95a44fe0d70535ff3c4f"   # ops/morning_steps/fred_regime.R (2026-06-19 판)
RS <- file.path(R.home("bin"), "Rscript")

P <- 0L; FL <- 0L; SKIPS <- list()
ok <- function(c, m) { if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") } }
skip <- function(axis, reason) { SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason); cat("  SKIP ", axis, "—", reason, "\n") }
TD <- normalizePath(file.path(tempdir(), paste0("rlc11_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
## ★자식 프로세스 격리(2026-09-25 통합 수리 · 적대 검증 LEDGER B1): R 은 시작 때 ~/.Renviron 을 적용해 **이미 세운 QM_ROOT 를 덮는다**
##   (Windows system2(env=) 는 무시되고, Sys.setenv 로 물려준 값도 자식의 Renviron 처리에서 운영 경로로 바뀐다 — 실측).
##   그러면 T5 의 00:03 블록이 운영 .cache/_regime_candidate/ 를 지우고 픽스처를 쓴다(스위트 러너·야간 수집은 R_ENVIRON_USER 를
##   비우지 않는다). 이 프로세스의 모든 자식에게 빈 Renviron 을 물려주고, 끝(T10)에서 Renviron 이 가리키는 루트의 후보 디렉터리 무접촉을 단정한다.
.renv_orig <- Sys.getenv("R_ENVIRON_USER", unset = "")
.renv_root <- local({   # 이 프로세스가 시작 때 읽은 Renviron 의 QM_ROOT(= 격리가 깨지면 자식이 쓰게 될 루트)
  f <- if (nzchar(.renv_orig)) .renv_orig else file.path(Sys.getenv("HOME", path.expand("~")), ".Renviron")
  l <- if (file.exists(f)) grep("^\\s*QM_ROOT\\s*=", readLines(f, warn = FALSE), value = TRUE) else character(0)
  if (length(l)) gsub("\\\\", "/", trimws(gsub("^[\"']|[\"']$", "", trimws(sub("^[^=]*=", "", l[length(l)]))))) else NA_character_
})
.EMPTY_RENV <- file.path(TD, "empty.Renviron"); file.create(.EMPTY_RENV)
Sys.setenv(R_ENVIRON_USER = .EMPTY_RENV)
.guard_roots <- unique(na.omit(c(ROOT, .renv_root, gsub("\\\\", "/", Sys.getenv("QM_ROOT", unset = NA)))))
.cand_snap <- function() { d <- file.path(.guard_roots, ".cache/_regime_candidate")
  f <- unlist(lapply(d[dir.exists(d)], list.files, all.files = TRUE, no.. = TRUE, full.names = TRUE))
  if (!length(f)) return(character(0))
  i <- file.info(f); sort(paste(f, i$size, format(i$mtime, "%Y%m%d%H%M%OS3"))) }
.CAND0 <- .cand_snap()
for (p in c(LIB, FREDRG, SELFH, ROOTR, DRSH, GUARD, HELP, RULES, UTP, UTJ, SIGNAL)) ok(file.exists(p), paste("존재", basename(p)))

## 돌연변이 사본 — 소스 텍스트 치환(deparse 아님 · 줄바꿈으로 조용히 빗나간 전례). old/new 는 같은 길이 벡터(여러 줄 동시 삭제 = MA2).
##   치환마다 대상이 정확히 1회 · 치환 뒤 대상 소멸 · 사본 ≠ 원본 · 사본 구문 해석 성공을 단정한다 — 하나라도 어긋나면 NA(+사유 속성)이고
##   호출부가 FAIL 로 센다(구문이 깨진 사본은 시나리오를 '중단'시켜 red 처럼 보이게 만든다 — 그 길을 막는다).
mutant <- function(src, old, new, tag) {
  t0 <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n"); t <- t0
  bad <- function(why) structure(NA_character_, why = why)
  if (length(old) != length(new) || !length(old)) return(bad("치환 쌍 길이 불일치"))
  for (i in seq_along(old)) {
    n <- lengths(regmatches(t, gregexpr(old[i], t, fixed = TRUE)))
    if (n != 1L) return(bad(sprintf("대상 %d회(1회여야 함): %s", n, substr(old[i], 1L, 70L))))
    t <- sub(old[i], new[i], t, fixed = TRUE)
    if (grepl(old[i], t, fixed = TRUE)) return(bad(sprintf("치환 뒤에도 대상 잔존(치환 미성사): %s", substr(old[i], 1L, 70L))))
  }
  if (identical(t, t0)) return(bad("사본 = 원본(치환 미성사)"))
  f <- file.path(TD, paste0(tag, "_", basename(src))); writeLines(t, f, useBytes = TRUE)
  pe <- tryCatch({ parse(f, keep.source = FALSE, encoding = "UTF-8"); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(pe)) return(bad(paste("사본 구문 오류:", pe)))
  f
}
git_blob <- function(sha, tag) {
  f <- file.path(TD, paste0(tag, ".R"))
  o <- suppressWarnings(system2("git", c("-C", shQuote(GITDIR), "cat-file", "-p", sha), stdout = TRUE, stderr = FALSE))
  if (!length(o) || !is.null(attr(o, "status"))) return(NA_character_)
  writeLines(o, f, useBytes = TRUE); f
}
sha <- function(p) if (file.exists(p)) unname(as.character(tools::md5sum(p))) else NA_character_
run_rs <- function(args, wd = NULL, env = character(0)) {
  ## ★Windows: system2(env=) 는 무시된다 — Sys.setenv 로 자식에게 물려준다(끝나면 복원)
  old <- Sys.getenv(names(env), unset = NA); if (length(env)) do.call(Sys.setenv, as.list(env))
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) }, add = TRUE)
  if (!is.null(wd)) { ow <- setwd(wd); on.exit(setwd(ow), add = TRUE) }
  out <- suppressWarnings(system2(RS, c("--no-save", args), stdout = TRUE, stderr = TRUE))
  list(rc = as.integer(attr(out, "status") %||% 0L), out = out)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

## ── 규칙 키 · 픽스처 ─────────────────────────────────────────────────────────
.fa <- new.env(parent = globalenv()); sys.source(HELP, envir = .fa)
K  <- .fa$fred_avail_rules_meta(RULES)$regime_key
K2 <- "c11_avail:2099-01-01.bX:deadbeef"
cat("규칙 키:", K, "\n")
TODAY <- Sys.Date()
kr_dec <- function(d) { w <- as.integer(format(d, "%u")); d - ifelse(w == 7L, 2L, ifelse(w == 6L, 1L, 0L)) }
stamp <- function(dt, key) {
  if (is.null(key)) return(dt)
  dt[, c11_regime_key := key]; setattr(dt, "c11_avail_regime_key", key); dt
}
## MSM 추정기 표식 — 값은 생산자 정본(regime_signal.R::MSM_ESTIMATOR_EXPECTED)에서 재도출한다(검사 쪽 리터럴 금지).
##   재도출 실패 = FAIL 로 세고, 시나리오는 자리표시 값으로 계속 돈다(원장 논리는 값 내용과 무관 — 결과가 사라지지 않게).
MSMV <- local({
  x <- readLines(SIGNAL, encoding = "UTF-8", warn = FALSE)
  v <- sub('^MSM_ESTIMATOR_EXPECTED\\s*<-\\s*"([^"]+)".*$', "\\1", grep('^MSM_ESTIMATOR_EXPECTED\\s*<-\\s*"', x, value = TRUE))
  if (length(v) == 1L && nzchar(v)) v else NA_character_
})
ok(!is.na(MSMV), sprintf("MSM 표식 값 재도출 regime_signal.R::MSM_ESTIMATOR_EXPECTED = %s", MSMV))
if (is.na(MSMV)) MSMV <- "msm_value_unresolved"
## mode = both(생산자 .msm_stamp 꼴: 행 열 + 같은 이름 파일 속성) · col · attr
mstamp <- function(dt, val = MSMV, mode = "both") {
  if (mode %in% c("both", "col")) dt[, msm_estimator := val]
  if (mode %in% c("both", "attr")) setattr(dt, "msm_estimator", val)
  dt
}
msmA  <- function(x, mode = "both", key = K) mstamp(stamp(copy(x), key), MSMV, mode)   # as-of 판(C11 키 + MSM 표식)
msmL  <- function(x, key = K) stamp(copy(x), key)                                     # legacy 판(MSM 표식 없음)
msm_key <- function(c11 = K, est = NULL) paste0(c11, "|msm:", if (is.null(est)) "legacy" else est)   # 설치본 .rl_epoch 의 합성 키 꼴
mk_monthly <- function(last_me, n = 33L, key = K, seed = 1L) {
  set.seed(seed)
  fm <- seq(as.Date(format(last_me, "%Y-%m-01")), by = "-1 month", length.out = n)
  d <- sort(as.Date(sapply(fm, function(x) seq(x, by = "month", length.out = 2)[2] - 1), origin = "1970-01-01"))
  dt <- data.table(Date = d, YM = format(d, "%Y%m"), MSM_Crisis_Prob = round(runif(n), 6), FRED_MRS = round(rnorm(n), 6),
                   KTRI_Score = round(runif(n, 20, 80), 4), VEA_Score = round(runif(n, 20, 80), 4),
                   Layer1_Alert = runif(n) > 0.8, Regime_Score = round(runif(n, 0, 60), 6),
                   Category = sample(c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS"), n, TRUE), Cash_Pct = round(runif(n, 0, .4), 6),
                   fw_Mom = round(runif(n), 4))
  if (!is.null(key)) dt[, avail_date := kr_dec(Date)]
  stamp(dt, key)
}
mk_daily <- function(last_d, n = 80L, key = K, seed = 2L) {
  set.seed(seed)
  d <- seq(last_d - 200L, last_d, by = "day"); d <- tail(d[as.integer(format(d, "%u")) <= 5L], n)
  dt <- data.table(Date = d, YM = format(d, "%Y%m"), MSM_Crisis_Prob = round(runif(n), 6), FRED_MRS = round(rnorm(n), 6),
                   KTRI_Score = round(runif(n, 20, 80), 4), VEA_Score = round(runif(n, 20, 80), 4),
                   Regime_Score = round(runif(n, 0, 60), 6), Regime_Score_smooth = round(runif(n, 0, 60), 6),
                   Category = sample(c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS"), n, TRUE), Cash_Pct = round(runif(n, 0, .4), 6),
                   Active_Layers = 3L, Is_Month_End = FALSE, last_updated = "2026-01-01 00:00:00")
  if (!is.null(key)) dt[, avail_date := as.Date(Date)]
  stamp(dt, key)
}
wparq <- function(dt, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); write_parquet(dt, p); p }
rdp <- function(p) { x <- read_parquet(p, mmap = FALSE); dt <- as.data.table(x); dt[, Date := as.Date(Date)]
                     setorder(dt, Date); list(dt = dt, key = attr(x, "c11_avail_regime_key", exact = TRUE)) }
same_dt <- function(a, b) isTRUE(all.equal(as.data.frame(a), as.data.frame(b), check.attributes = FALSE))
.RC <- 0L   # 루트 일련번호 — 픽스처가 set.seed 를 부르므로 runif 이름은 실행 간 충돌한다(실측: 돌연변이 실행이 본 실행 디렉터리를 재사용)
mkroot <- function(tag, lib = LIB) {
  .RC <<- .RC + 1L
  r <- file.path(TD, sprintf("%s_%03d", tag, .RC))
  if (dir.exists(r)) stop("[test] 루트 재사용 금지: ", r)
  for (d in c("02_Infrastructure/regime", "02_Infrastructure/utils", "02_Infrastructure/data", "02_Infrastructure/validation",
              "02_Infrastructure/ops/morning_steps", "06_Registry/regime_published", ".cache"))
    dir.create(file.path(r, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(lib, file.path(r, "02_Infrastructure/regime/regime_append_only.R"))
  file.copy(UTP, file.path(r, "02_Infrastructure/utils/atomic_parquet.R")); file.copy(UTJ, file.path(r, "02_Infrastructure/utils/atomic_json.R"))
  file.copy(HELP, file.path(r, "02_Infrastructure/data/fred_availability.R")); file.copy(RULES, file.path(r, "06_Registry/fred_availability_rules.json"))
  file.copy(GUARD, file.path(r, "02_Infrastructure/validation/overlay_pit_guard.R"))
  r
}
L <- function(lib) { e <- new.env(parent = globalenv()); suppressMessages(sys.source(lib, envir = e)); e }
paths <- function(r, s) list(live = file.path(r, ".cache", if (s == "monthly") "unified_regime_signal.parquet" else "unified_regime_signal_daily.parquet"),
                              pub = file.path(r, "06_Registry/regime_published", sprintf("regime_signal_%s_published.parquet", s)),
                              meta = file.path(r, "06_Registry/regime_published", sprintf("regime_signal_%s_meta.json", s)),
                              side = file.path(r, "06_Registry/regime_published", sprintf("regime_signal_%s_ledger.jsonl", s)),
                              dlog = file.path(r, "06_Registry/regime_published/regime_drift_log.jsonl"),
                              cand = file.path(r, ".cache/_regime_candidate", if (s == "monthly") "unified_regime_signal.parquet" else "unified_regime_signal_daily.parquet"))
guard_status <- function(r, dt_path) {
  old <- Sys.getenv("QM_ROOT"); Sys.setenv(QM_ROOT = r); on.exit(Sys.setenv(QM_ROOT = old))
  g <- new.env(parent = globalenv()); suppressMessages(sys.source(file.path(r, "02_Infrastructure/validation/overlay_pit_guard.R"), envir = g))
  x <- as.data.table(read_parquet(dt_path, mmap = FALSE)); x <- x[!is.na(Category)]
  g$c11_panel_status(x, "Category")
}
D0 <- as.Date("2026-09-25")          # 합성 시나리오 기준일(in-process · --as-of 명시)

## ── MSM 축 공용 도구 ───────────────────────────────────────────────────────────
## 루트 지문 = 발행 원장 디렉터리 전량(하위 보관 디렉터리 포함) + 두 라이브 + 재생성 증거(.regen_) — 무기록 단정의 기준
snap_root <- function(R) {
  pd <- file.path(R, "06_Registry/regime_published")
  f <- c(list.files(pd, all.files = TRUE, no.. = TRUE, full.names = TRUE, recursive = TRUE),
         paths(R, "monthly")$live, paths(R, "daily")$live, list.files(file.path(R, ".cache"), pattern = "\\.regen_", full.names = TRUE))
  setNames(vapply(f, sha, ""), f)
}
## meta 필드 덮어쓰기 — value = NULL 이면 필드 삭제. null = "null": 다른 null 필드가 '{}' 로 바뀌지 않게
meta_set <- function(p, field, value) {
  mt <- fromJSON(p, simplifyVector = FALSE); mt[[field]] <- value
  write_json(mt, p, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}
## 발행 원장 init(+ 라이브 동기) — pubs = list(<계열> = 기준선 픽스처). strip = TRUE 면 meta 에서 msm_estimator 필드를 지운다
##   (전환 전 운영 meta 모사 — 2026-10-20 판엔 필드가 없다)
msm_ledger <- function(E, lib, tag, pubs, strip = FALSE) {
  R <- mkroot(tag, lib)
  for (s in names(pubs)) {
    Pp <- paths(R, s); x <- pubs[[s]]
    wparq(x, Pp$cand); i <- E$regime_ledger_append(s, root = R, as_of = D0, candidate = Pp$cand, init = TRUE, verbose = FALSE)
    if (!identical(i$status, 0L)) stop(sprintf("[test] %s init 실패(rc=%s): %s", s, i$status, i$msg %||% ""))
    wparq(x, Pp$live); file.remove(Pp$cand)
    if (isTRUE(strip)) meta_set(Pp$meta, "msm_estimator", NULL)
  }
  R
}
msm_cands <- function(R, tag, mc, dc) list(monthly = wparq(mc, file.path(R, tag, "unified_regime_signal.parquet")),
                                           daily   = wparq(dc, file.path(R, tag, "unified_regime_signal_daily.parquet")))
## 발행 parquet 의 표식 판독(C11 열 · 속성 + MSM 열 고유값 · 속성) — rdp 는 C11 속성만 본다
rdm <- function(p) {
  x <- read_parquet(p, mmap = FALSE); dt <- as.data.table(x)
  list(key = attr(x, "c11_avail_regime_key", exact = TRUE), msm_attr = attr(x, "msm_estimator", exact = TRUE),
       keycol  = if ("c11_regime_key" %in% names(dt)) unique(as.character(dt$c11_regime_key)) else NULL,
       msm_col = if ("msm_estimator" %in% names(dt)) unique(as.character(dt$msm_estimator)) else NULL)
}
## as-of 표식 온전(생산자 .msm_stamp 꼴 = 열 단일값 + 속성 · C11 열 + 속성 = 규칙 키)
msm_marked <- function(p, val = MSMV, key = K) {
  z <- rdm(p)
  identical(z$msm_col, val) && identical(z$msm_attr, val) && identical(z$keycol, key) && identical(z$key, key)
}

# ═════════════════════════════════════════════════════════════════════════════
# 시나리오 함수 — lib 경로를 받아 명명 논리 벡터(전부 TRUE = 정상)를 낸다. 돌연변이는 같은 함수로 red 를 잰다.
# ═════════════════════════════════════════════════════════════════════════════
sc_T2 <- function(lib) {
  r <- list(); R <- mkroot("t2", lib); E <- L(lib)
  for (s in c("monthly", "daily")) {
    Pp <- paths(R, s)
    c0 <- if (s == "monthly") mk_monthly(as.Date("2026-09-30")) else mk_daily(D0 - 1L)
    wparq(c0, Pp$cand)
    i0 <- E$regime_ledger_append(s, root = R, as_of = D0, candidate = Pp$cand, init = TRUE, verbose = FALSE)
    wparq(c0, Pp$live)
    nxt <- if (s == "monthly") as.Date("2026-10-02") else D0 + 3L       # 월: 9월 완료 · 일: 09-25(금)·09-28(월) 추가
    c1 <- if (s == "monthly") mk_monthly(as.Date("2026-10-31"), n = 34L) else mk_daily(D0 + 2L, n = 82L)
    ## 동결분(≤ 발행 원장 frozen_through)은 c0 와 같게 — 이번 비교는 표식 보존만 잰다
    ft0 <- as.Date(fromJSON(Pp$meta)$frozen_through)
    c1 <- rbind(c0[Date <= ft0], c1[Date > ft0]); stamp(c1, K); setattr(c1, "c11_avail_regime_key", K)
    wparq(c1, Pp$cand)
    a1 <- E$regime_ledger_append(s, root = R, as_of = nxt, candidate = Pp$cand, verbose = FALSE)
    pb <- rdp(Pp$pub); lv <- rdp(Pp$live); mt <- fromJSON(Pp$meta)
    r[[paste0(s, "_init")]] <- identical(i0$status, 0L)
    r[[paste0(s, "_rc0")]] <- identical(a1$status, 0L) && isTRUE(a1$written)
    r[[paste0(s, "_avail_Date")]] <- inherits(pb$dt$avail_date, "Date") && inherits(lv$dt$avail_date, "Date") && !anyNA(pb$dt$avail_date)
    r[[paste0(s, "_keycol")]] <- identical(unique(pb$dt$c11_regime_key), K) && identical(unique(lv$dt$c11_regime_key), K)
    r[[paste0(s, "_attr")]] <- identical(pb$key, K) && identical(lv$key, K)
    r[[paste0(s, "_live_eq_pub")]] <- same_dt(pb$dt, lv$dt)
    r[[paste0(s, "_rows")]] <- nrow(pb$dt) == nrow(c1) && same_dt(pb$dt[Date <= ft0], c0[Date <= ft0]) && same_dt(pb$dt[Date > ft0], c1[Date > ft0])
    r[[paste0(s, "_colorder")]] <- identical(names(pb$dt), names(c1))
    r[[paste0(s, "_meta_key")]] <- identical(mt$c11_regime_key, K)
    r[[paste0(s, "_meta_msm")]] <- identical(mt$msm_estimator, "legacy")   # MSM 표식 없는 픽스처 = meta 'legacy'(접두 없는 꼴 · 2026-11-06)
    r[[paste0(s, "_guard")]] <- identical(guard_status(R, Pp$live), "avail_annotated")
    sl <- readLines(Pp$side, encoding = "UTF-8"); j <- fromJSON(sl[length(sl)])
    r[[paste0(s, "_sidecar_avail")]] <- !is.null(j$avail_date) && identical(as.Date(j$avail_date), max(pb$dt$avail_date))
  }
  r
}

sc_T3 <- function(lib) {
  r <- list(); E <- L(lib)
  base <- mk_monthly(as.Date("2026-09-30"))
  setup <- function() { R <- mkroot("t3", lib); Pp <- paths(R, "monthly"); wparq(base, Pp$cand)
    E$regime_ledger_append("monthly", root = R, as_of = D0, candidate = Pp$cand, init = TRUE, verbose = FALSE); list(R = R, Pp = Pp) }
  tgt <- as.Date("2025-03-31")
  inj <- list(Regime_Score = function(x) x[Date == tgt, Regime_Score := Regime_Score + 1],
              Category     = function(x) x[Date == tgt, Category := ifelse(Category == "CRISIS", "RISK_ON", "CRISIS")],
              Cash_Pct     = function(x) x[Date == tgt, Cash_Pct := Cash_Pct + 0.01],
              avail_date   = function(x) x[Date == tgt, avail_date := avail_date + 1L])
  for (nm in names(inj)) {
    S <- setup(); cc <- copy(base); inj[[nm]](cc); stamp(cc, K); wparq(cc, S$Pp$cand)
    a <- E$regime_ledger_append("monthly", root = S$R, as_of = D0, candidate = S$Pp$cand, verbose = FALSE)
    pb <- rdp(S$Pp$pub)$dt; lv <- rdp(S$Pp$live)$dt
    r[[paste0("hard_", nm)]] <- identical(a$status, 1L) && nm %in% names(a$hard) &&
      same_dt(pb[Date == tgt], base[Date == tgt]) && same_dt(lv[Date == tgt], base[Date == tgt])
  }
  ## 입력 드리프트 = 통과(로그) · 문턱 아래(1e-12) = 통과
  S <- setup(); cc <- copy(base); cc[Date == tgt, FRED_MRS := FRED_MRS + 0.5]; cc[Date == tgt - 31L, Regime_Score := Regime_Score + 1e-12]
  stamp(cc, K); wparq(cc, S$Pp$cand)
  a <- E$regime_ledger_append("monthly", root = S$R, as_of = D0, candidate = S$Pp$cand, verbose = FALSE)
  dl <- readLines(S$Pp$dlog); j <- fromJSON(dl[length(dl)])
  r$soft_pass <- identical(a$status, 0L) && !is.null(j$drift_soft$FRED_MRS) && length(j$drift_hard) == 0L
  ## CLI 종료 코드 = 1 (프로세스 수준 양성 대조 — daily_refresh 의 case 가 읽는 값)
  S <- setup(); cc <- copy(base); cc[Date == tgt, Regime_Score := Regime_Score + 1]; stamp(cc, K); wparq(cc, S$Pp$cand)
  x <- run_rs(c(file.path(S$R, "02_Infrastructure/regime/regime_append_only.R"), "--series", "monthly", "--root", S$R,
                "--as-of", as.character(D0), "--from-candidate"))
  r$cli_rc1 <- identical(x$rc, 1L)
  r
}

sc_T4 <- function(lib) {
  r <- list(); E <- L(lib)
  cases <- list(
    legacy_pub_keyed_cand = list(pub = mk_monthly(as.Date("2026-09-30"), key = NULL), cand = mk_monthly(as.Date("2026-09-30")), rc = 3L),
    keyed_pub_other_key   = list(pub = mk_monthly(as.Date("2026-09-30")), cand = mk_monthly(as.Date("2026-09-30"), key = K2), rc = 3L),
    keyed_pub_legacy_cand = list(pub = mk_monthly(as.Date("2026-09-30")), cand = mk_monthly(as.Date("2026-09-30"), key = NULL), rc = 3L),
    malformed_cand        = list(pub = mk_monthly(as.Date("2026-09-30")),
                                 cand = { x <- mk_monthly(as.Date("2026-09-30")); x[, avail_date := NULL]; x }, rc = 2L))
  for (nm in names(cases)) {
    R <- mkroot("t4", lib); Pp <- paths(R, "monthly"); cs <- cases[[nm]]
    wparq(cs$pub, Pp$cand); E$regime_ledger_append("monthly", root = R, as_of = D0, candidate = Pp$cand, init = TRUE, verbose = FALSE)
    wparq(cs$pub, Pp$live); writeLines('{"seed":1}', Pp$dlog); writeLines("x", Pp$side)
    before <- vapply(Pp[c("pub", "meta", "side", "dlog", "live")], sha, "")
    wparq(cs$cand, Pp$cand)
    a <- E$regime_ledger_append("monthly", root = R, as_of = D0, candidate = Pp$cand, verbose = FALSE)
    after <- vapply(Pp[c("pub", "meta", "side", "dlog", "live")], sha, "")
    r[[nm]] <- identical(a$status, cs$rc) && identical(before, after) &&
      !length(list.files(dirname(Pp$pub), pattern = "\\.bak_")) && !length(list.files(dirname(Pp$live), pattern = "\\.regen_"))
  }
  r
}

## T5 — 00:03(daily_refresh 원문 블록) → 07:10(fred_regime.R 원문) 을 합성 루트에서 순서대로
.write_stubs <- function(R) {
  ## ★루트 = 이 픽스처 루트 리터럴(환경변수 불신 — 자식의 Renviron 이 QM_ROOT 를 운영으로 덮는다 · LEDGER B1 수리 2026-09-25).
  writeLines(c(sprintf('PROJECT_ROOT <- "%s"; Sys.setenv(QM_ROOT = PROJECT_ROOT, CLAUDE_PROJECT_DIR = PROJECT_ROOT)', R),
               'FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure"); CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")',
               'REGIME_SIGNAL_CACHE <- file.path(CACHE_DIR, "unified_regime_signal.parquet"); RESEARCH_OUTPUT <- file.path(PROJECT_ROOT, "04_Research")'),
             file.path(R, "02_Infrastructure/config.R"))
  writeLines(c('build_regime_signal_table <- function(save_path = NULL, daily = FALSE, ...) {',
               '  if (identical(Sys.getenv("RL_FAIL_BUILD"), "1")) stop("stub build failure")',
               '  x <- readRDS(Sys.getenv(if (daily) "RL_FIX_DAILY" else "RL_FIX_MONTHLY"))',
               '  if (is.null(save_path)) save_path <- file.path(CACHE_DIR, if (daily) "unified_regime_signal_daily.parquet" else "unified_regime_signal.parquet")',
               '  dir.create(dirname(save_path), recursive = TRUE, showWarnings = FALSE); arrow::write_parquet(x, save_path); invisible(x) }'),
             file.path(R, "02_Infrastructure/regime/regime_signal.R"))
}
.extract_dr <- function(dr) {
  x <- readLines(dr, encoding = "UTF-8", warn = FALSE)
  h <- grep("^# build_regime_signal_table — MSM 갱신 후 호출", x)[1]
  s <- h + grep("^run_r '$", x[(h + 1):length(x)])[1]; e <- s + grep("^'$", x[(s + 1):length(x)])[1]
  lp <- grep("^for _series in monthly daily; do$", x)[1]; le <- lp + grep("^done$", x[(lp + 1):length(x)])[1]
  list(r_block = x[(s + 1):(e - 1)], loop = x[lp:le], ok = !anyNA(c(h, s, e, lp, le)))
}
sc_T5 <- function(lib, fred_regime = FREDRG, dr = DRSH) {
  r <- list(); R <- mkroot("t5", lib); .write_stubs(R); E <- L(lib)
  file.copy(ROOTR, file.path(R, "02_Infrastructure/ops/morning_steps/_root.R"))
  file.copy(fred_regime, file.path(R, "02_Infrastructure/ops/morning_steps/fred_regime.R"))
  X <- .extract_dr(dr); r$dr_extract <- X$ok
  if (!X$ok) return(r)
  bd <- seq(TODAY - 200L, TODAY - 1L, by = "day"); bd <- bd[as.integer(format(bd, "%u")) <= 5L]
  L1 <- max(bd); L2 <- max(bd[bd < L1]); me <- seq(as.Date(format(TODAY, "%Y-%m-01")), by = "month", length.out = 2)[2] - 1L
  cur_m <- as.Date(format(TODAY, "%Y-%m-01"))
  ## 초기 원장(어제 07:10 상태): 일간 ≤ L2 동결 · 월간 < 당월 동결
  d0 <- mk_daily(L1, n = 90L); m0 <- mk_monthly(me)
  for (s in c("monthly", "daily")) {
    Pp <- paths(R, s); c0 <- if (s == "monthly") m0 else d0[Date <= L2]
    wparq(c0, Pp$cand); E$regime_ledger_append(s, root = R, as_of = if (s == "monthly") TODAY else L1, candidate = Pp$cand, init = TRUE, verbose = FALSE)
    wparq(c0, Pp$live); file.remove(Pp$cand)
  }
  ## 00:03 후보: 동결 이력에 입력 드리프트(FRED 소급 개정) + 새 행 L1 · 월간 진행중 행 갱신
  dN <- copy(d0); dN[Date < L2 - 20L, FRED_MRS := FRED_MRS + 0.3]; stamp(dN, K)
  mN <- copy(m0); mN[Date == me, Regime_Score := Regime_Score + 3]; stamp(mN, K)
  ## 07:10 후보: 동결 이력의 결정값 재서술(Regime_Score) + L1 행 변경 · 월간 진행중 행 재갱신
  dM <- copy(dN); dM[Date < L2 - 10L, Regime_Score := Regime_Score + 2]; dM[Date == L1, Regime_Score := Regime_Score + 5]; stamp(dM, K)
  mM <- copy(mN); mM[Date < cur_m - 60L, Regime_Score := Regime_Score + 2]; mM[Date == me, Regime_Score := Regime_Score + 1]; stamp(mM, K)
  fx <- function(x, nm) { f <- file.path(R, paste0(nm, ".rds")); saveRDS(x, f); f }
  env_n <- c(QM_ROOT = R, CLAUDE_PROJECT_DIR = R, RL_FIX_DAILY = fx(dN, "dN"), RL_FIX_MONTHLY = fx(mN, "mN"), RL_FAIL_BUILD = "0")
  env_m <- c(QM_ROOT = R, CLAUDE_PROJECT_DIR = R, RL_FIX_DAILY = fx(dM, "dM"), RL_FIX_MONTHLY = fx(mM, "mM"), RL_FAIL_BUILD = "0")
  ## ── 00:03: daily_refresh.sh 원문 블록(재생성 run_r 본문 + 원장 루프) ──
  rb <- file.path(R, "night_block.R"); writeLines(X$r_block, rb, useBytes = TRUE)
  x1 <- run_rs(rb, wd = file.path(R, "02_Infrastructure"), env = env_n)
  sh <- file.path(R, "night_loop.sh")
  writeLines(c(sprintf('RSCRIPT="%s"; QM_ROOT="%s"; BASE="%s"; INFRA="%s/02_Infrastructure"', RS, R, R, R), X$loop), sh, useBytes = TRUE)
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR")); Sys.setenv(QM_ROOT = R, CLAUDE_PROJECT_DIR = R)
  x2 <- suppressWarnings(system2("bash", shQuote(sh), stdout = TRUE, stderr = TRUE)); do.call(Sys.setenv, as.list(old))
  r$night_rc <- identical(x1$rc, 0L) && sum(grepl("\\[regime-append/(monthly|daily)\\] OK", x2)) == 2L
  if (!isTRUE(r$night_rc)) cat(tail(c(x1$out, x2), 15), sep = "\n")
  N <- lapply(c(monthly = "monthly", daily = "daily"), function(s) rdp(paths(R, s)$live))
  ## ── 07:10: fred_regime.R 원문 ──
  x3 <- run_rs(c("-e", shQuote('source("02_Infrastructure/ops/morning_steps/fred_regime.R")')), wd = R, env = env_m)
  M <- lapply(c(monthly = "monthly", daily = "daily"), function(s) rdp(paths(R, s)$live))
  r$morning_ran <- identical(x3$rc, 0L)
  r$daily_same <- same_dt(N$daily$dt, M$daily$dt) && identical(N$daily$key, K) && identical(M$daily$key, K)
  r$monthly_hist_same <- same_dt(N$monthly$dt[Date < cur_m], M$monthly$dt[Date < cur_m]) && identical(N$monthly$key, K) && identical(M$monthly$key, K)
  r$monthly_open_updated <- isTRUE(all.equal(M$monthly$dt[Date == me]$Regime_Score, mM[Date == me]$Regime_Score))
  r$markers_both <- all(vapply(c(N, M), function(z) inherits(z$dt$avail_date, "Date") && identical(unique(z$dt$c11_regime_key), K), logical(1)))
  r$guard_after_morning <- identical(guard_status(R, paths(R, "daily")$live), "avail_annotated")
  r$morning_detected_restatement <- any(grepl("동결 구간 재서술 시도 검출", x3$out))
  ## ── 00:03 빌드 실패 = 후보 부재(잔재 후보 삭제) = 라이브 불변 — daily_refresh 원문 블록 + 루프 ──
  wparq(dM, paths(R, "daily")$cand); wparq(mM, paths(R, "monthly")$cand)        # 어제 후보가 남아 있는 상황
  bl0 <- vapply(c("monthly", "daily"), function(s) sha(paths(R, s)$live), "")
  ng0 <- length(list.files(file.path(R, ".cache"), pattern = "\\.regen_"))
  x5 <- run_rs(rb, wd = file.path(R, "02_Infrastructure"), env = c(env_n[-5], RL_FAIL_BUILD = "1"))
  Sys.setenv(QM_ROOT = R, CLAUDE_PROJECT_DIR = R)
  x6 <- suppressWarnings(system2("bash", shQuote(sh), stdout = TRUE, stderr = TRUE)); do.call(Sys.setenv, as.list(old))
  r$night_build_fail_live_unchanged <- identical(x5$rc, 0L) && sum(grepl("\\(rc=2\\)", x6)) == 2L &&
    identical(bl0, vapply(c("monthly", "daily"), function(s) sha(paths(R, s)$live), "")) &&
    length(list.files(file.path(R, ".cache"), pattern = "\\.regen_")) == ng0
  ## ── 07:10 빌드 실패 = 후보 부재 = 라이브 불변 (잔재 후보가 병합되면 안 된다) ──
  wparq(dM, paths(R, "daily")$cand); wparq(mM, paths(R, "monthly")$cand)        # 어제 후보가 남아 있는 상황
  bl <- vapply(c("monthly", "daily"), function(s) sha(paths(R, s)$live), "")
  nregen <- length(list.files(file.path(R, ".cache"), pattern = "\\.regen_"))
  x4 <- run_rs(c("-e", shQuote('source("02_Infrastructure/ops/morning_steps/fred_regime.R")')), wd = R, env = c(env_m[-5], RL_FAIL_BUILD = "1"))
  r$build_fail_live_unchanged <- identical(bl, vapply(c("monthly", "daily"), function(s) sha(paths(R, s)$live), "")) &&
    length(list.files(file.path(R, ".cache"), pattern = "\\.regen_")) == nregen && sum(grepl("원장 경로 실패\\(rc=2\\)", x4$out)) == 2L
  r
}

sc_T6 <- function(lib) {
  r <- list(); R <- mkroot("t6", lib); E <- L(lib)
  pd <- file.path(R, "06_Registry/regime_published")
  ## 구 원장 = C11 이전(legacy) · .bak 2개 · 사이드카 · 드리프트 로그 · .gitignore
  mL <- mk_monthly(as.Date("2026-09-30"), key = NULL); dL <- mk_daily(D0 - 1L, key = NULL)
  for (s in c("monthly", "daily")) { Pp <- paths(R, s); x <- if (s == "monthly") mL else dL
    wparq(x, Pp$cand); E$regime_ledger_append(s, root = R, as_of = D0, candidate = Pp$cand, init = TRUE, verbose = FALSE); wparq(x, Pp$live)
    writeLines(c('{"Date":"x"}'), Pp$side); file.copy(Pp$pub, paste0(Pp$pub, ".bak_20260801_000000")) }
  writeLines('{"ts":"old"}', file.path(pd, "regime_drift_log.jsonl")); writeLines("*.bak_*", file.path(pd, ".gitignore"))
  ## 후보 = 현행 epoch 판(값도 다르다 — 재서술 수 비교용)
  mC <- mk_monthly(as.Date("2026-09-30"), seed = 11L); dC <- mk_daily(D0 - 1L, seed = 12L)
  cm <- wparq(mC, file.path(R, "cands/unified_regime_signal.parquet")); cd <- wparq(dC, file.path(R, "cands/unified_regime_signal_daily.parquet"))
  snap <- function() { f <- c(list.files(pd, all.files = TRUE, no.. = TRUE, full.names = TRUE, recursive = TRUE), paths(R, "monthly")$live, paths(R, "daily")$live)
                       setNames(vapply(f, sha, ""), f) }
  s0 <- snap(); pre_hash <- s0
  pf <- file.path(R, "plan.json")
  dr <- E$regime_ledger_republish(root = R, as_of = D0, candidates = list(monthly = cm, daily = cd), plan_out = pf, verbose = FALSE)
  r$dry_rc0 <- identical(dr$status, 0L)
  r$dry_no_write <- identical(snap(), s0) && !dir.exists(dr$archive_dir)
  pl <- fromJSON(pf, simplifyVector = FALSE)
  ## 계획의 재서술 수 = 독립 재도출(공통 날짜 · Regime_Score |Δ|>1e-9)
  indep <- function(a, b) { m <- merge(a[, .(Date, x = Regime_Score)], b[, .(Date, y = Regime_Score)], by = "Date"); sum(abs(m$x - m$y) > 1e-9) }
  r$plan_diff <- identical(as.integer(pl$series$monthly$diff_vs_old$per_col$Regime_Score$n), indep(mL, mC)) &&
    identical(as.integer(pl$series$daily$diff_vs_old$per_col$Regime_Score$n), indep(dL, dC))
  r$plan_files <- setequal(vapply(pl$archive, function(a) a$file, ""), basename(list.files(pd, all.files = TRUE, no.. = TRUE))) &&
    all(vapply(pl$archive, function(a) (a$action == "move") == grepl("\\.bak_", a$file), logical(1)))
  ## ★2026-11-06: candidate_epoch = 합성 키 '<c11>|msm:<추정기>'(설치본 .rl_epoch) — 순수 C11 키는 candidate_c11. 픽스처는 MSM 표식 없음 = msm:legacy
  r$plan_epoch <- identical(pl$series$monthly$old_epoch, "legacy") &&
    all(vapply(c("monthly", "daily"), function(s) identical(pl$series[[s]]$candidate_c11, K) &&
                 identical(pl$series[[s]]$candidate_epoch, msm_key(K)) &&
                 identical(pl$series[[s]]$candidate_msm, "msm:legacy"), logical(1)))
  ## 거부 조건: 후보 키 ≠ 규칙 키 · 보관 디렉터리 존재
  cbad <- wparq(mk_monthly(as.Date("2026-09-30"), key = K2), file.path(R, "cands_bad/unified_regime_signal.parquet"))
  b1 <- E$regime_ledger_republish("monthly", root = R, as_of = D0, candidates = list(monthly = cbad), execute = TRUE, verbose = FALSE)
  r$refuse_key <- identical(b1$status, 2L) && identical(snap(), s0) && !dir.exists(b1$archive_dir)
  dir.create(file.path(pd, "_archive_exists_probe"))
  b2 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = list(monthly = cm, daily = cd), execute = TRUE,
                                  archive_dir = file.path(pd, "_archive_exists_probe"), verbose = FALSE)
  r$refuse_archive_exists <- identical(b2$status, 2L) && identical(snap()[names(s0)], s0)
  unlink(file.path(pd, "_archive_exists_probe"), recursive = TRUE)
  ## 보관 경로가 Windows MAX_PATH 를 넘으면 실행 전 거부(중간 실패 원천 차단)
  b3 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = list(monthly = cm, daily = cd), execute = TRUE,
                                  archive_dir = file.path(pd, strrep("x", 230)), verbose = FALSE)
  r$refuse_long_path <- if (identical(.Platform$OS.type, "windows")) identical(b3$status, 2L) && identical(snap(), s0) else TRUE
  ## 보관 중간 실패(두 번째 .bak 이 잠김) → 이동분 되돌림·복사분 삭제·보관 디렉터리 제거 · 원장 미교체
  con <- tryCatch(file(paste0(paths(R, "monthly")$pub, ".bak_20260801_000000"), "rb"), error = function(e) NULL)
  e1 <- if (is.null(con)) "잠글 .bak 부재(앞 단계가 이미 옮김)" else
    tryCatch({ E$regime_ledger_republish(root = R, as_of = D0, candidates = list(monthly = cm, daily = cd), execute = TRUE, verbose = FALSE)
               "no-error" }, error = function(e) conditionMessage(e))
  if (!is.null(con)) close(con)
  r$rollback_on_failure <- if (identical(.Platform$OS.type, "windows"))
    grepl("되돌림", e1) && identical(snap(), s0) && !dir.exists(file.path(pd, sprintf("_archive_pre_c11_%s", format(D0, "%Y%m%d")))) else TRUE
  ## 검토 계획과 다른 후보(dry-run 이후 재빌드) → 거부 · 무기록
  ctam <- copy(mC); ctam[1, Regime_Score := Regime_Score + 1]; stamp(ctam, K)
  ctp <- wparq(ctam, file.path(R, "cands_tam/unified_regime_signal.parquet"))
  b4 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = list(monthly = ctp, daily = cd), execute = TRUE,
                                  expect_plan = pf, verbose = FALSE)
  r$refuse_plan_mismatch <- identical(b4$status, 2L) && identical(snap(), s0) && any(grepl("검토 계획", b4$problems))
  ## 실행 — 검토한 dry-run 계획과 같은 후보·같은 원장 디렉터리일 때만
  ex <- E$regime_ledger_republish(root = R, as_of = D0, candidates = list(monthly = cm, daily = cd), execute = TRUE,
                                  expect_plan = pf, verbose = FALSE)
  ad <- ex$archive_dir
  r$exec_rc0 <- identical(ex$status, 0L) && dir.exists(ad) && basename(ad) == sprintf("_archive_pre_c11_%s", format(D0, "%Y%m%d"))
  arch_ok <- all(vapply(names(pre_hash)[startsWith(names(pre_hash), pd)], function(f) identical(sha(file.path(ad, basename(f))), pre_hash[[f]]), logical(1)))
  r$archive_hash <- arch_ok && !length(list.files(pd, pattern = "\\.bak_20260801"))
  for (s in c("monthly", "daily")) {
    Pp <- paths(R, s); pb <- rdp(Pp$pub); lv <- rdp(Pp$live); mt <- fromJSON(Pp$meta); S <- pl$series[[s]]
    cc <- if (s == "monthly") mC else dC
    r[[paste0(s, "_pub_is_cand")]] <- same_dt(pb$dt, cc) && identical(pb$key, K) && same_dt(lv$dt, cc) && identical(lv$key, K)
    r[[paste0(s, "_plan_eq_exec")]] <- identical(mt$frozen_through, S$frozen_through) && identical(as.integer(mt$n), as.integer(S$n)) &&
      identical(mt$c11_regime_key, K) && identical(mt$msm_estimator, "legacy") && identical(mt$republished$archive_dir, ad)
  }
  dl <- readLines(file.path(pd, "regime_drift_log.jsonl"))
  r$dlog_event <- identical(dl[1], '{"ts":"old"}') && sum(grepl('"event":"republish"', dl)) == 2L
  r$manifest <- file.exists(file.path(ad, "MANIFEST.json"))
  ## 재기준선 뒤 다음 날 병합 = 같은 epoch → 0 · 표식 유지
  d2 <- mk_daily(D0 + 2L, n = 82L, seed = 12L); ft <- as.Date(fromJSON(paths(R, "daily")$meta)$frozen_through)
  d2 <- rbind(dC[Date <= ft], d2[Date > ft]); stamp(d2, K); wparq(d2, paths(R, "daily")$cand)
  a2 <- E$regime_ledger_append("daily", root = R, as_of = D0 + 3L, candidate = paths(R, "daily")$cand, verbose = FALSE)
  r$post_append <- identical(a2$status, 0L) && identical(rdp(paths(R, "daily")$live)$key, K)
  ## 복원: dry-run 무변화 → 실행 시 구 발행본 바이트 복귀 · .bak 되돌림 · 라이브 = 구 발행본
  s1 <- snap(); rd <- tryCatch(E$regime_ledger_restore(ad, root = R, verbose = FALSE), error = function(e) list(status = NA_integer_))
  r$restore_dry <- identical(rd$status, 0L) && identical(snap(), s1)
  tryCatch(E$regime_ledger_restore(ad, root = R, execute = TRUE, verbose = FALSE), error = function(e) NULL)
  r$restore_exec <- identical(sha(paths(R, "monthly")$pub), pre_hash[[paths(R, "monthly")$pub]]) &&
    identical(sha(paths(R, "daily")$meta), pre_hash[[paths(R, "daily")$meta]]) &&
    file.exists(paste0(paths(R, "monthly")$pub, ".bak_20260801_000000")) &&
    same_dt(rdp(paths(R, "monthly")$live)$dt, mL)
  r
}

sc_T7 <- function(lib) {
  E <- L(lib); R <- mkroot("t7", lib); Pp <- paths(R, "daily")
  d <- mk_daily(D0 - 1L); wparq(d, Pp$cand)
  E$regime_ledger_append("daily", root = R, as_of = D0, candidate = Pp$cand, init = TRUE, verbose = FALSE)
  ft0 <- fromJSON(Pp$meta)$frozen_through
  a <- E$regime_ledger_append("daily", root = R, as_of = D0 - 10L, candidate = Pp$cand, verbose = FALSE)
  list(monotonic = identical(fromJSON(Pp$meta)$frozen_through, ft0) && identical(a$status, 0L))
}

## ── T11 MSM 추정기 에폭 축 (2026-11-06 · 적대 검토 #2·#7·#9·#14·#18) ─────────────────────────────────
## T11a — 병합(append). 모든 사례가 같은 C11 키 K · 같은 동결 이력이다 → 판정을 가르는 축은 MSM 표식뿐.
sc_T11a <- function(lib) {
  r <- list(); E <- L(lib)
  c0 <- mk_monthly(as.Date("2026-09-30"))
  msg <- function(a) if (is.null(a$msg)) "" else a$msg
  ## 후보를 놓고 병합 → 결과 + (종료 코드 일치 ∧ 무기록: 발행 원장 디렉터리 전량 · 두 라이브 · .regen_ 불변)
  try_append <- function(R, cand, rc) {
    Pp <- paths(R, "monthly"); wparq(cand, Pp$cand); s0 <- snap_root(R)
    a <- E$regime_ledger_append("monthly", root = R, as_of = D0, candidate = Pp$cand, verbose = FALSE)
    list(a = a, ok = identical(a$status, rc) && identical(snap_root(R), s0))
  }
  ## (a) MSM 만 다른 에폭(양방향) → 종료 3 · 무기록 · 보고 에폭 = 합성 키
  A <- list(a_legacy_pub_asof_cand = list(pub = msmL(c0), cand = msmA(c0), pe = msm_key(K), ce = msm_key(K, MSMV)),
            a_asof_pub_legacy_cand = list(pub = msmA(c0), cand = msmL(c0), pe = msm_key(K, MSMV), ce = msm_key(K)))
  for (nm in names(A)) {
    x <- try_append(msm_ledger(E, lib, "t11a", list(monthly = A[[nm]]$pub)), A[[nm]]$cand, 3L)
    r[[nm]] <- x$ok && identical(x$a$pub_epoch, A[[nm]]$pe) && identical(x$a$cand_epoch, A[[nm]]$ce)
  }
  ## (b) 반쪽 MSM 표식 후보 4꼴 → 종료 2 · 무기록 (발행 원장 = 정상 as-of)
  OTHER <- paste0(MSMV, "_other")
  B <- list(
    b_cand_col_na_mix    = function(x) { x <- msmA(x); set(x, i = seq(1L, nrow(x), by = 3L), j = "msm_estimator", value = NA_character_); x },
    b_cand_col_all_na    = function(x) { x <- msmL(x); x[, msm_estimator := NA_character_]; x },
    b_cand_attr_conflict = function(x) { x <- msmA(x); setattr(x, "msm_estimator", OTHER); x },
    b_cand_col_two       = function(x) { x <- msmA(x, mode = "col"); set(x, i = 1L, j = "msm_estimator", value = OTHER); x })
  for (nm in names(B)) {
    x <- try_append(msm_ledger(E, lib, "t11b", list(monthly = msmA(c0))), B[[nm]](c0), 2L)
    r[[nm]] <- x$ok && grepl("후보 표식 계약 위반", msg(x$a), fixed = TRUE) && grepl("MSM 추정기 표식이 단일하지 않다", msg(x$a), fixed = TRUE)
  }
  ## (b) 발행본 변조 — parquet MSM 열 한 칸 NA(meta 그대로) + 정상 as-of 후보 → 종료 2 · 무기록
  R <- msm_ledger(E, lib, "t11b", list(monthly = msmA(c0)))
  ## ★Windows: 원자적 쓰기 정본이 검증용으로 read_parquet(mmap 기본 TRUE)을 해 둔 매핑이 GC 전까지 남아 같은 경로 덮어쓰기가
  ##   error 1224 로 거부된다(실측) — 변조 쓰기 전에 매핑을 거둔다
  invisible(gc())
  tp <- msmA(c0); set(tp, i = 2L, j = "msm_estimator", value = NA_character_); wparq(tp, paths(R, "monthly")$pub)
  x <- try_append(R, msmA(c0), 2L)
  r$b_pub_tampered <- x$ok && grepl("발행 원장 표식 계약 위반", msg(x$a), fixed = TRUE) &&
    grepl("MSM 추정기 표식이 단일하지 않다", msg(x$a), fixed = TRUE)
  ## (c) meta msm_estimator ≠ parquet 표식(발행본 as-of · meta 'legacy') + 같은 에폭 후보 → 종료 2 · 무기록
  R <- msm_ledger(E, lib, "t11c", list(monthly = msmA(c0))); meta_set(paths(R, "monthly")$meta, "msm_estimator", "legacy")
  x <- try_append(R, msmA(c0), 2L)
  r$c_meta_ne_parquet <- x$ok && grepl("parquet MSM 표식", msg(x$a), fixed = TRUE)
  ## (c) 이웃 축: meta c11_regime_key ≠ parquet C11 키 → 종료 2 · 무기록 (설치본이 합성 키 도입으로 ep$key → ep$c11 로 바꾼 줄 —
  ##   그 전엔 이 검사의 위반 주입이 스위트에 없었다)
  R <- msm_ledger(E, lib, "t11c", list(monthly = msmA(c0))); meta_set(paths(R, "monthly")$meta, "c11_regime_key", K2)
  x <- try_append(R, msmA(c0), 2L)
  r$c_meta_c11_ne_parquet <- x$ok && grepl("parquet epoch", msg(x$a), fixed = TRUE)
  ## (c) 대조: meta 에 필드가 없으면(전환 전 판 모양) 이 검사를 건너뛰고 병합한다 → 0 · 병합이 필드를 접두 없는 값으로 채운다
  R <- msm_ledger(E, lib, "t11c", list(monthly = msmA(c0)), strip = TRUE); Pp <- paths(R, "monthly")
  wparq(msmA(c0), Pp$cand)
  a <- E$regime_ledger_append("monthly", root = R, as_of = D0, candidate = Pp$cand, verbose = FALSE)
  r$c_meta_absent_merges <- identical(a$status, 0L) && isTRUE(a$written) && identical(fromJSON(Pp$meta)$msm_estimator, MSMV)
  ## (f) 정상 — as-of 원장 + as-of 후보(다음 달 · 9월 완료) → 0 · meta 접두 없는 값 · 표식 보존 · 에폭 기록
  R <- msm_ledger(E, lib, "t11f", list(monthly = msmA(c0))); Pp <- paths(R, "monthly"); mt0 <- fromJSON(Pp$meta)
  r$f_init_meta <- identical(mt0$msm_estimator, MSMV) && identical(mt0$c11_regime_key, K) && msm_marked(Pp$pub)
  ft0 <- as.Date(mt0$frozen_through)
  c1 <- mk_monthly(as.Date("2026-10-31"), n = 34L); c1 <- msmA(rbind(c0[Date <= ft0], c1[Date > ft0])); wparq(c1, Pp$cand)
  a <- E$regime_ledger_append("monthly", root = R, as_of = as.Date("2026-10-02"), candidate = Pp$cand, verbose = FALSE)
  mt <- fromJSON(Pp$meta); dl <- readLines(Pp$dlog, encoding = "UTF-8"); j <- fromJSON(dl[length(dl)])
  r$f_merge_rc0 <- identical(a$status, 0L) && isTRUE(a$written) && identical(a$epoch, msm_key(K, MSMV)) &&
    identical(j$epoch, msm_key(K, MSMV)) && identical(nrow(rdp(Pp$pub)$dt), nrow(c1)) && identical(mt$frozen_through, "2026-09-30")
  r$f_meta_unprefixed <- identical(mt$msm_estimator, MSMV) && identical(mt$c11_regime_key, K)
  r$f_markers_kept <- msm_marked(Pp$pub) && msm_marked(Pp$live)
  ## (g) 병합 후 MSM 혼합 — 후보가 열을 잃고 속성만(에폭은 같다) → 병합 결과 열 = as-of + NA → 종료 2 · 무기록
  x <- try_append(msm_ledger(E, lib, "t11g", list(monthly = msmA(c0))), msmA(c0, mode = "attr"), 2L)
  r$g_postmerge_mixed <- x$ok && grepl("병합 후 MSM 표식", msg(x$a), fixed = TRUE)
  r
}

## T11r — 재발행(republish). 거부 사례는 실행 플래그(execute = TRUE)를 켠 채 거부·무기록·보관 디렉터리 부재를 본다.
sc_T11r <- function(lib) {
  r <- list(); E <- L(lib)
  mA <- mk_monthly(as.Date("2026-09-30"), seed = 21L); dA <- mk_daily(D0 - 1L, seed = 22L)   # 재기준선 후보 값(구 원장과 다르다)
  old_k2 <- list(monthly = mk_monthly(as.Date("2026-09-30"), key = K2), daily = mk_daily(D0 - 1L, key = K2))   # 전환 전 모양(옛 C11 키 · legacy MSM)
  old_as <- list(monthly = msmA(mk_monthly(as.Date("2026-09-30"))), daily = msmA(mk_daily(D0 - 1L)))          # 전환 뒤 원장(as-of)
  RK <- msm_key(K, MSMV)
  ## (d) 지정 '<K>|msm:<추정기>' + legacy 후보 → 두 계열 모두 '후보 MSM 추정기 ≠ 지정' · 종료 2 · 무기록 (구 원장 legacy = 후퇴 검사와 분리)
  R <- msm_ledger(E, lib, "t11d", old_k2, strip = TRUE)
  cl <- msm_cands(R, "cands_legacy", msmL(mA), msmL(dA)); ca <- msm_cands(R, "cands_asof", msmA(mA), msmA(dA)); s0 <- snap_root(R)
  d1 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = cl, rules_key = RK, execute = TRUE, verbose = FALSE)
  r$d_refuse_legacy_cand <- identical(d1$status, 2L) && identical(snap_root(R), s0) && !dir.exists(d1$archive_dir) &&
    sum(grepl("후보 MSM 추정기(msm:legacy) ≠ 지정(msm:", d1$problems, fixed = TRUE)) == 2L && !any(grepl("MSM 후퇴", d1$problems, fixed = TRUE))
  d2 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = ca, rules_key = RK, verbose = FALSE)
  r$d_ctrl_asof_cand_ok <- identical(d2$status, 0L) && !length(d2$problems) && identical(snap_root(R), s0)
  ## (e) 구 원장 as-of → legacy 후보 · 기본 규칙 키(MSM 부분 없음) → 'MSM 후퇴' 두 계열 · 종료 2 · 무기록
  R <- msm_ledger(E, lib, "t11e", old_as)
  cl <- msm_cands(R, "cands_legacy", msmL(mA), msmL(dA)); ca <- msm_cands(R, "cands_asof", msmA(mA), msmA(dA)); s0 <- snap_root(R)
  e1 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = cl, execute = TRUE, verbose = FALSE)
  r$e_refuse_msm_retreat <- identical(e1$status, 2L) && identical(e1$rules_key, K) && identical(snap_root(R), s0) && !dir.exists(e1$archive_dir) &&
    sum(grepl("MSM 후퇴", e1$problems, fixed = TRUE)) == 2L && !any(grepl("지정(", e1$problems, fixed = TRUE))
  e2 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = ca, verbose = FALSE)
  r$e_ctrl_asof_cand_ok <- identical(e2$status, 0L) && !length(e2$problems) && identical(snap_root(R), s0)
  ## (f) 전환 재발행 = 운영 3단계 모양: 구 원장(K2 · legacy · meta 필드 없음) → dry-run 계획 → --expect-plan 실행 → 첫 밤 병합
  R <- msm_ledger(E, lib, "t11s", old_k2, strip = TRUE)
  ca <- msm_cands(R, "cands_asof", msmA(mA), msmA(dA)); pf <- file.path(R, "plan_switch.json"); RSN <- "test-msm-switch"
  p1 <- E$regime_ledger_republish(root = R, as_of = D0, candidates = ca, rules_key = RK, reason = RSN, plan_out = pf, verbose = FALSE)
  pl <- fromJSON(pf, simplifyVector = FALSE)
  r$f_switch_plan <- identical(p1$status, 0L) && identical(pl$rules_key, RK) && identical(pl$reason, RSN) &&
    all(vapply(c("monthly", "daily"), function(s) identical(pl$series[[s]]$candidate_epoch, RK) && identical(pl$series[[s]]$candidate_c11, K) &&
                 identical(pl$series[[s]]$old_epoch, msm_key(K2)), logical(1)))
  ex <- E$regime_ledger_republish(root = R, as_of = D0, candidates = ca, rules_key = RK, reason = RSN, execute = TRUE,
                                  expect_plan = pf, verbose = FALSE)
  mfp <- file.path(ex$archive_dir %||% "", "MANIFEST.json")
  mf <- if (length(mfp) == 1L && file.exists(mfp)) fromJSON(mfp, simplifyVector = FALSE) else list()
  r$f_switch_exec <- identical(ex$status, 0L) && identical(mf$rules_key, RK) && identical(mf$reason, RSN) &&
    all(vapply(c("monthly", "daily"), function(s) {
      Pp <- paths(R, s); mt <- fromJSON(Pp$meta)
      identical(mt$c11_regime_key, K) && identical(mt$msm_estimator, MSMV) && identical(mt$rules_key_at_write, K) &&
        identical(mt$republished$reason, RSN) && identical(mt$republished$old_epoch, msm_key(K2)) && msm_marked(Pp$pub) && msm_marked(Pp$live)
    }, logical(1)))
  Pp <- paths(R, "daily"); ft <- as.Date(fromJSON(Pp$meta)$frozen_through)
  d3 <- mk_daily(D0 + 2L, n = 82L, seed = 22L); d3 <- msmA(rbind(dA[Date <= ft], d3[Date > ft])); wparq(d3, Pp$cand)
  a3 <- E$regime_ledger_append("daily", root = R, as_of = D0 + 3L, candidate = Pp$cand, verbose = FALSE); mt <- fromJSON(Pp$meta)
  r$f_switch_then_nightly <- identical(a3$status, 0L) && isTRUE(a3$written) && identical(a3$epoch, RK) && msm_marked(Pp$pub) &&
    msm_marked(Pp$live) && identical(mt$msm_estimator, MSMV) && identical(mt$republished$reason, RSN)
  r
}

## T11c — CLI(프로세스 수준). ★종료 2 는 .rl_main 의 tryCatch(죽은 실행)와 겹친다 → 거부 문구 출력까지 함께 단정한다.
sc_T11c <- function(lib) {
  r <- list(); E <- L(lib)
  LR <- function(R) file.path(R, "02_Infrastructure/regime/regime_append_only.R")   # 루트 사본(돌연변이면 그 사본이 돈다)
  ## 밤 루프 호출 모양(daily_refresh: --series <s> --root <BASE> --from-candidate) — legacy 원장 + as-of 후보 → 종료 3 · 무기록
  dd <- mk_daily(D0 - 1L)
  R <- msm_ledger(E, lib, "t11n", list(daily = msmL(dd))); Pp <- paths(R, "daily")
  wparq(msmA(dd), Pp$cand); s0 <- snap_root(R)
  x <- run_rs(c(LR(R), "--series", "daily", "--root", R, "--as-of", as.character(D0), "--from-candidate"))
  r$cli_night_rc3 <- identical(x$rc, 3L) && identical(snap_root(R), s0) && any(grepl(msm_key(K, MSMV), x$out, fixed = TRUE))
  ## 3단계 명령 모양: --rules-key '<K>|msm:<추정기>' · --reason · --plan-out(dry-run) → legacy 후보 거부 → --expect-plan --execute
  mA <- mk_monthly(as.Date("2026-09-30"), seed = 21L); dA <- mk_daily(D0 - 1L, seed = 22L)
  R <- msm_ledger(E, lib, "t11k", list(monthly = mk_monthly(as.Date("2026-09-30"), key = K2), daily = mk_daily(D0 - 1L, key = K2)), strip = TRUE)
  ca <- msm_cands(R, "ca", msmA(mA), msmA(dA)); cl <- msm_cands(R, "cl", msmL(mA), msmL(dA))
  RK <- msm_key(K, MSMV); RSN <- "cli-msm-switch-test"; pf <- file.path(R, "plan_cli.json")
  rp <- function(cc, ...) run_rs(c(LR(R), "--republish", "--root", R, "--as-of", as.character(D0), "--candidate-monthly", cc$monthly,
                                   "--candidate-daily", cc$daily, "--rules-key", shQuote(RK), "--reason", RSN, ...))
  s0 <- snap_root(R)
  y1 <- rp(ca, "--plan-out", pf)
  pl <- if (file.exists(pf)) fromJSON(pf, simplifyVector = FALSE) else list()
  r$cli_plan_shape <- identical(y1$rc, 0L) && identical(snap_root(R), s0) && identical(pl$mode, "dry-run") && identical(pl$rules_key, RK) &&
    identical(pl$reason, RSN) && identical(pl$series$monthly$candidate_epoch, RK) && identical(pl$series$daily$candidate_epoch, RK)
  y2 <- rp(cl)
  r$cli_refuse_legacy <- identical(y2$rc, 2L) && identical(snap_root(R), s0) &&
    sum(grepl("후보 MSM 추정기(msm:legacy) ≠ 지정(", y2$out, fixed = TRUE)) == 2L
  y3 <- rp(ca, "--expect-plan", pf, "--execute")
  r$cli_exec <- identical(y3$rc, 0L) && all(vapply(c("monthly", "daily"), function(s) {
    Pp <- paths(R, s); mt <- fromJSON(Pp$meta)
    identical(mt$c11_regime_key, K) && identical(mt$msm_estimator, MSMV) && identical(mt$republished$reason, RSN) &&
      msm_marked(Pp$pub) && msm_marked(Pp$live)
  }, logical(1)))
  if (!identical(y1$rc, 0L) || !identical(y3$rc, 0L)) cat(tail(c(y1$out, y3$out), 12), sep = "\n")   # 실행 자체가 죽었을 때만 진단 출력
  r
}

## T1 — legacy 원장 병합 = 구판(blob) 산출과 동일(배포 직후~재기준선 전 · 표식 없는 계열에 대한 비트 동일 규약)
sc_T1 <- function(lib, old_lib) {
  r <- list()
  for (s in c("monthly", "daily")) for (drift in c(FALSE, TRUE)) {
    tag <- sprintf("%s_%s", s, if (drift) "drift" else "clean")
    c0 <- if (s == "monthly") mk_monthly(as.Date("2026-09-30"), key = NULL) else mk_daily(D0 - 1L, key = NULL)
    c1 <- if (s == "monthly") mk_monthly(as.Date("2026-10-31"), n = 34L, key = NULL, seed = 5L) else mk_daily(D0 + 2L, n = 82L, key = NULL, seed = 5L)
    if (!drift) { ft <- if (s == "monthly") as.Date("2026-08-31") else D0 - 1L; c1 <- rbind(c0[Date <= ft], c1[Date > ft]) }
    out <- list()
    for (w in c("old", "new")) {
      R <- mkroot(paste0("t1", w), if (w == "old") old_lib else lib); Pp <- paths(R, s)
      wparq(c0, Pp$live)
      i <- run_rs(c(file.path(R, "02_Infrastructure/regime/regime_append_only.R"), "--series", s, "--as-of", as.character(D0), "--init"),
                  env = c(CLAUDE_PROJECT_DIR = R, QM_ROOT = R))
      wparq(c1, Pp$live)
      a <- run_rs(c(file.path(R, "02_Infrastructure/regime/regime_append_only.R"), "--series", s,
                    "--as-of", as.character(if (s == "monthly") as.Date("2026-10-02") else D0 + 3L)),
                  env = c(CLAUDE_PROJECT_DIR = R, QM_ROOT = R))
      out[[w]] <- list(rc = c(i$rc, a$rc), pub = rdp(Pp$pub)$dt, live = rdp(Pp$live)$dt,
                       side = readLines(Pp$side, encoding = "UTF-8"), meta = fromJSON(Pp$meta))
    }
    r[[tag]] <- identical(out$old$rc, out$new$rc) && same_dt(out$old$pub, out$new$pub) && same_dt(out$old$live, out$new$live) &&
      identical(names(out$old$pub), names(out$new$pub)) && identical(out$old$side, out$new$side) &&
      identical(out$old$meta$frozen_through, out$new$meta$frozen_through) && identical(out$old$meta$n, out$new$meta$n) &&
      identical(out$new$rc[2], if (drift) 1L else 0L)
  }
  r
}

## 시나리오 실행 — 중단(오류)은 결과 대신 crashed 속성을 단 빈 목록(보고 = FAIL · red 아님). 요약 JSON 이 끊기지 않게 계속 간다.
run_sc <- function(fn, ...) tryCatch(fn(...), error = function(e) {
  cat("    (시나리오 중단:", conditionMessage(e), ")\n"); structure(list(), crashed = conditionMessage(e)) })
report <- function(res, label) {
  if (!is.null(attr(res, "crashed"))) return(invisible(ok(FALSE, sprintf("%s 시나리오 중단: %s", label, attr(res, "crashed")))))
  for (nm in names(res)) ok(isTRUE(res[[nm]]), sprintf("%s %s", label, nm))
}
## ★red = 기준선(원본 라이브러리 · 같은 시나리오) 대비 TRUE → FALSE 로 뒤집힌 검사(적대 검토 #18 — 기준선이 이미 FALSE 인 검사는
##   어느 사본에서도 'red' 로 보이므로 판별력이 없다). 시나리오 중단 = red 아님(FAIL). targets 를 주면 그 검사가 뒤집혀야 한다
##   (need = "all" 전부 · "any" 하나 이상). 표적이 기준선에서 TRUE 가 아니면 판별 불가 = FAIL.
red <- function(res, label, base, targets = NULL, need = "all") {
  if (!is.null(attr(res, "crashed")))
    return(invisible(ok(FALSE, sprintf("%s 시나리오 중단 — red 로 세지 않는다(%s)", label, attr(res, "crashed")))))
  bt <- names(base)[vapply(base, isTRUE, logical(1))]
  fl <- bt[!vapply(bt, function(n) isTRUE(res[[n]]), logical(1))]
  fls <- if (length(fl)) paste(fl, collapse = ",") else "없음"
  if (is.null(targets))
    return(invisible(ok(length(fl) > 0L, sprintf("%s ★red (기준선 TRUE→FALSE: %s)", label,
                                                 if (length(fl)) fls else "없음 — 돌연변이를 못 잡는다"))))
  nb <- setdiff(targets, bt); hit <- intersect(targets, fl); miss <- setdiff(targets, hit)
  pass <- !length(nb) && (if (identical(need, "any")) length(hit) > 0L else !length(miss))
  ok(pass, sprintf("%s ★red 표적(%s) %s%s%s · 뒤집힌 전체: %s", label, need, paste(targets, collapse = ","),
                   if (length(nb)) sprintf(" · 기준선 TRUE 아님(판별 불가): %s", paste(nb, collapse = ",")) else "",
                   if (!identical(need, "any") && length(miss)) sprintf(" · 안 뒤집힘: %s", paste(miss, collapse = ",")) else "", fls))
}

# ═════════════════════════════════════════════════════════════════════════════
BASE <- list()   # 기준선 = 원본 라이브러리 결과(돌연변이 red 판정의 비교 기준)
cat("\n── T1 legacy 병합 = 구판(git blob) 산출 ──\n")
OLDLIB <- git_blob(BLOB_OLD_APPEND, "old_append")
if (is.na(OLDLIB)) skip("T1", "git blob 부재(구판 regime_append_only.R)") else report(run_sc(sc_T1, LIB, OLDLIB), "T1")
cat("\n── T2 같은 epoch 병합 — 표식 보존 · 소비자 가드 ──\n");      BASE$T2 <- run_sc(sc_T2, LIB); report(BASE$T2, "T2")
cat("\n── T3 동결 구간 재서술 검출(양성 대조) ──\n");                BASE$T3 <- run_sc(sc_T3, LIB); report(BASE$T3, "T3")
cat("\n── T4 epoch 불일치 = 무기록 ──\n");                           BASE$T4 <- run_sc(sc_T4, LIB); report(BASE$T4, "T4")
cat("\n── T5 00:03 → 07:10 원문 경로 ──\n");                        BASE$T5 <- run_sc(sc_T5, LIB); report(BASE$T5, "T5")
cat("\n── T6 재기준선 dry-run · 실행 · 복원 ──\n");                  BASE$T6 <- run_sc(sc_T6, LIB); report(BASE$T6, "T6")
cat("\n── T7 동결 단조 ──\n");                                        BASE$T7 <- run_sc(sc_T7, LIB); report(BASE$T7, "T7")
cat("\n── T11a MSM 에폭 — 병합(같은 C11 · MSM 축만 다름) ──\n");      BASE$T11a <- run_sc(sc_T11a, LIB); report(BASE$T11a, "T11a")
cat("\n── T11r MSM 에폭 — 재발행(지정 추정기 · 후퇴 차단 · 전환) ──\n"); BASE$T11r <- run_sc(sc_T11r, LIB); report(BASE$T11r, "T11r")
cat("\n── T11c MSM 에폭 — CLI(밤 루프 · 3단계 명령 모양) ──\n");      BASE$T11c <- run_sc(sc_T11c, LIB); report(BASE$T11c, "T11c")

cat("\n── T8 배선 정적 검사(라이브를 원장 밖에서 쓰는 재생성 호출 0) ──\n")
## 문자열 리터럴을 비운 뒤 주석을 지운다 — cat("-> build_regime_signal_table() …") 같은 로그 문자열은 호출이 아니다
strip_comments <- function(x) sub("#.*$", "", gsub("'[^']*'", "''", gsub("\"[^\"]*\"", "\"\"", x)))
fr_raw <- readLines(FREDRG, encoding = "UTF-8", warn = FALSE); fr <- strip_comments(fr_raw)
ok(!any(grepl("build_regime_signal_table\\(", fr)) && any(grepl("regime_ledger_rebuild_publish\\(", fr)) &&
     any(grepl("^\\s*source\\(\"02_Infrastructure/regime/regime_append_only\\.R\"\\)", fr_raw)), "T8 fred_regime.R: 직접 재빌드 0 · 원장 경로 호출")
shl <- strip_comments(readLines(SELFH, encoding = "UTF-8", warn = FALSE))
ok(!any(grepl("build_regime_signal_table\\(", shl)) && any(grepl("regime_ledger_rebuild_publish\\(", shl)), "T8 self_heal.R: 직접 재빌드 0 · 원장 경로 호출")
X <- .extract_dr(DRSH)
bl <- X$r_block[grepl("build_regime_signal_table\\(", X$r_block)]
ok(X$ok && length(bl) == 2L && all(grepl("save_path = \\.cand\\$(monthly|daily)", bl)) && any(grepl("fresh = TRUE", X$r_block)),
   "T8 daily_refresh.sh 재생성 블록: 두 빌드 모두 후보 경로 · 잔재 후보 삭제")
ok(any(grepl("--from-candidate", X$loop)) && any(grepl("^\\s*3\\)", X$loop)), "T8 daily_refresh.sh 원장 루프: --from-candidate · 종료 3 분기")
drx <- readLines(DRSH, encoding = "UTF-8", warn = FALSE)
ok(!any(grepl("build_module_performance\\.R\" >/dev/null", drx)) && any(grepl("per_regime_pit_c11", drx)),
   "T8 daily_refresh.sh [8.2]: 모듈 성능 출력 비폐기 · per_regime C11 상태 표면")
dr_all <- strip_comments(drx)
ok(sum(grepl("build_regime_signal_table\\(", dr_all)) == 2L, "T8 daily_refresh.sh: 재생성 호출은 그 블록의 2건뿐")

cat("\n── T9 돌연변이(같은 픽스처에서 기준선 대비 red) ──\n")
## 계기 자기 검사(양성 대조) — mutant() 가 빗나간 치환을 사본으로 내보내지 않는가: 대상 부재 · 대상 2회 이상 · 구문을 깨는
##   치환은 NA(+사유), 정상 치환은 대상이 사라지고 새 줄이 든 사본(원본 무변경)
.mt_src0 <- sha(LIB)
.mt <- list(absent = mutant(LIB, "__no_such_target_text__", "x", "mt_absent"),
            dup    = mutant(LIB, "regime_ledger_paths(", "x(", "mt_dup"),
            syntax = mutant(LIB, 'return(list(kind = "keyed", key = paste(k, m, sep = "|"), c11 = k, msm = m))', 'return(list(kind = "keyed"', "mt_syntax"),
            good   = mutant(LIB, "  ft_write <- max(ft_prev, ft_new)", "  ft_write <- ft_new", "mt_good"))
ok(is.na(.mt$absent) && grepl("대상 0회", attr(.mt$absent, "why") %||% "", fixed = TRUE) &&
     is.na(.mt$dup) && grepl("1회여야 함", attr(.mt$dup, "why") %||% "", fixed = TRUE) &&
     is.na(.mt$syntax) && grepl("구문 오류", attr(.mt$syntax, "why") %||% "", fixed = TRUE),
   "T9 계기 자기 검사: mutant() 가 대상 부재 · 중복 · 구문 파손 치환을 거부(NA + 사유)")
.gl <- if (!is.na(.mt$good)) readLines(.mt$good, encoding = "UTF-8", warn = FALSE) else character(0)
ok(!is.na(.mt$good) && any(grepl("^  ft_write <- ft_new(\\s|$)", .gl)) && !any(grepl("ft_write <- max(ft_prev, ft_new)", .gl, fixed = TRUE)) &&
     identical(sha(LIB), .mt_src0), "T9 계기 자기 검사: 정상 치환 = 대상 소멸 · 새 줄 존재(뒤 주석 유지) · 원본 무변경")
MU <- list(
  M1 = list(old = "    out_attrs <- C$attrs\n", new = "    out_attrs <- list()\n", sc = "T2", why = "파일 속성 폐기"),
  M2 = list(old = "for (cl in c(REGIME_LEDGER_DECISION_COLS, REGIME_LEDGER_AVAIL_COLS))", new = "for (cl in REGIME_LEDGER_DECISION_COLS)", sc = "T3", why = "가용일 재서술 미검출"),
  M2b = list(old = "  status <- if (length(hard)) 1L else 0L\n", new = "  status <- 0L\n", sc = "T3", why = "재서술 검출 무력화"),
  M3 = list(old = "  same_epoch <- identical(ep$kind, ec$kind) && (ep$kind == \"legacy\" || identical(ep$key, ec$key))",
            new = "  same_epoch <- TRUE", sc = "T4", why = "epoch 대조 삭제(혼합 원장)"),
  M5 = list(old = "  if (!execute) {", new = "  if (FALSE) {", sc = "T6", why = "dry-run 이 기록"),
  M6 = list(old = "  if (isTRUE(fresh)) for (f in unlist(p))", new = "  if (FALSE) for (f in unlist(p))", sc = "T5", why = "잔재 후보 미삭제"),
  M7 = list(old = "  ft_write <- max(ft_prev, ft_new)", new = "  ft_write <- ft_new", sc = "T7", why = "동결 경계 후퇴"),
  ## ★2026-11-06: 설치본은 규칙 키를 합성 키로 분해해 C11 부분끼리 대조한다(rk = .rl_split_key(rules_key)) — 대상 줄도 그 판으로
  M8 = list(old = "    else if (!identical(ec$c11, rk$c11)) prob(", new = "    else if (FALSE) prob(", sc = "T6", why = "재기준선 규칙 키 검사 삭제"),
  M10 = list(old = "    for (a in rev(done)) {", new = "    for (a in list()) {", sc = "T6", why = "보관 중간 실패 되돌림 삭제"),
  M11 = list(old = "  if (!is.null(expect_plan)) {", new = "  if (FALSE) {", sc = "T6", why = "검토 계획 대조 삭제"))
SC <- list(T2 = sc_T2, T3 = sc_T3, T4 = sc_T4, T5 = sc_T5, T6 = sc_T6, T7 = sc_T7, T11a = sc_T11a, T11r = sc_T11r, T11c = sc_T11c)
for (nm in names(MU)) {
  m <- MU[[nm]]; f <- mutant(LIB, m$old, m$new, tolower(nm))
  if (is.na(f)) { ok(FALSE, sprintf("%s 대상 줄 부재·치환 실패(%s) — %s", nm, m$why, attr(f, "why") %||% "")); next }
  red(run_sc(SC[[m$sc]], f), sprintf("%s(%s → %s)", nm, m$why, m$sc), BASE[[m$sc]])
}
## M4 — 구판 fred_regime.R(git blob): 07:10 이 원장 밖에서 라이브를 덮는다 → 00:03/07:10 교대
OLDFR <- git_blob(BLOB_OLD_FREDRG, "old_fred_regime")
if (is.na(OLDFR)) skip("M4", "git blob 부재(구판 fred_regime.R)") else
  red(run_sc(sc_T5, LIB, fred_regime = OLDFR), "M4(구판 fred_regime.R — 원장 밖 재빌드 → T5)", BASE$T5,
      targets = c("daily_same", "monthly_hist_same", "build_fail_live_unchanged"), need = "any")
## M9 — 구판 병합(git blob)이 오늘 운영 상태(legacy 원장 + C11 후보)에서 표식을 지운다(수리판 = 종료 3·무기록)
if (!is.na(OLDLIB)) {
  R <- mkroot("m9", OLDLIB); Pp <- paths(R, "daily")
  wparq(mk_daily(D0 - 2L, key = NULL), Pp$live)
  run_rs(c(file.path(R, "02_Infrastructure/regime/regime_append_only.R"), "--series", "daily", "--as-of", as.character(D0 - 1L), "--init"),
         env = c(CLAUDE_PROJECT_DIR = R, QM_ROOT = R))
  wparq(mk_daily(D0 - 1L), Pp$live)
  run_rs(c(file.path(R, "02_Infrastructure/regime/regime_append_only.R"), "--series", "daily", "--as-of", as.character(D0)),
         env = c(CLAUDE_PROJECT_DIR = R, QM_ROOT = R))
  ok(!identical(guard_status(R, Pp$live), "avail_annotated"), "M9 구판 병합 ★red: legacy 원장 + C11 후보 → 라이브 표식 삭제(가드 = legacy)")
}

cat("\n── T12 돌연변이 — MSM 에폭 가드(지킨 줄을 지운 사본 · 표적 검사가 기준선 대비 전부 red) ──\n")
## 대상 문자열은 설치본 원문 그대로(소스 텍스트 치환 — deparse 아님). old/new 가 벡터면 여러 줄 동시 치환(MA2).
MU2 <- list(
  MA  = list(old = 'return(list(kind = "keyed", key = paste(k, m, sep = "|"), c11 = k, msm = m))',
             new = 'return(list(kind = "keyed", key = k, c11 = k, msm = m))', sc = "T11a",
             tg = c("a_legacy_pub_asof_cand", "a_asof_pub_legacy_cand"), why = "합성 에폭 키에서 MSM 부분 삭제(C11 키만 대조) — (a)"),
  ## MA3 = 에폭 대조 자체(M3 와 같은 줄)를 지운 사본을 MSM 축에 — (a) 는 병합 후 혼합 검사가 종료 2 로 받아내므로 '종료 3' 기대가 깨진다
  MA3 = list(old = '  same_epoch <- identical(ep$kind, ec$kind) && (ep$kind == "legacy" || identical(ep$key, ec$key))',
             new = '  same_epoch <- TRUE', sc = "T11a",
             tg = c("a_legacy_pub_asof_cand", "a_asof_pub_legacy_cand"), why = "에폭 대조 삭제(MSM 축) — (a)"),
  MA2 = list(old = c('  if (REGIME_LEDGER_MSM_COL %in% names(obj$dt)) v <- unique(as.character(obj$dt[[REGIME_LEDGER_MSM_COL]]))\n',
                     '  if (!is.null(a)) v <- c(v, as.character(a))\n'),
             new = c("", ""), sc = "T11a",
             tg = c("a_legacy_pub_asof_cand", "a_asof_pub_legacy_cand", "b_cand_col_na_mix", "b_pub_tampered", "f_init_meta"),
             why = "MSM 표식 판독 삭제(.rl_msm 이 늘 legacy) — (a)(b)(f)"),
  MB  = list(old = '    if (is.na(m)) return(list(kind = "malformed"', new = '    if (FALSE) return(list(kind = "malformed"', sc = "T11a",
             tg = c("b_cand_col_na_mix", "b_cand_col_all_na", "b_cand_attr_conflict", "b_cand_col_two", "b_pub_tampered"),
             why = "반쪽 MSM 표식 malformed 분기 삭제 — (b)"),
  MC  = list(old = '  if (ep$kind == "keyed" && !is.null(mt$msm_estimator)', new = '  if (FALSE && !is.null(mt$msm_estimator)', sc = "T11a",
             tg = "c_meta_ne_parquet", why = "meta MSM ≠ parquet 검사 삭제 — (c)"),
  MC2 = list(old = '  if (ep$kind == "keyed" && !is.null(mt$c11_regime_key)', new = '  if (FALSE && !is.null(mt$c11_regime_key)', sc = "T11a",
             tg = "c_meta_c11_ne_parquet", why = "meta C11 키 ≠ parquet 검사 삭제 — (c) 이웃"),
  MF  = list(old = 'NA_character_ else sub("^msm:", "", m)', new = 'NA_character_ else m', sc = "T11a",
             tg = c("f_init_meta", "f_meta_unprefixed"), why = "meta 접두 제거 삭제('msm:' 붙은 값 기록) — (f)"),
  MG  = list(old = '    if (!identical(.rl_msm(list(dt = final, attrs = out_attrs)), ec$msm))', new = '    if (FALSE)', sc = "T11a",
             tg = "g_postmerge_mixed", why = "병합 후 MSM 혼합 검사 삭제 — (g)"),
  MD  = list(old = '    else if (!is.na(rk$msm) && !identical(ec$msm, rk$msm)) prob(', new = '    else if (FALSE) prob(', sc = "T11r",
             tg = "d_refuse_legacy_cand", why = "재발행 지정 추정기 ≠ 후보 검사 삭제 — (d)"),
  ME  = list(old = 'if (identical(ec$kind, "keyed") && !is.na(epb$msm)', new = 'if (FALSE && !is.na(epb$msm)', sc = "T11r",
             tg = "e_refuse_msm_retreat", why = "MSM 후퇴 차단 삭제 — (e)"),
  MK  = list(old = 'rules_key = getarg("--rules-key", NULL)', new = 'rules_key = NULL', sc = "T11c",
             tg = c("cli_plan_shape", "cli_refuse_legacy"), why = "CLI --rules-key 판독 삭제"),
  MR  = list(old = '    rsn <- getarg("--reason", NULL)', new = '    rsn <- NULL', sc = "T11c",
             tg = c("cli_plan_shape", "cli_exec"), why = "CLI --reason 판독 삭제"))
for (nm in names(MU2)) {
  m <- MU2[[nm]]; f <- mutant(LIB, m$old, m$new, tolower(nm))
  if (is.na(f)) { ok(FALSE, sprintf("%s 대상 줄 부재·치환 실패(%s) — %s", nm, m$why, attr(f, "why") %||% "")); next }
  red(run_sc(SC[[m$sc]], f), sprintf("%s(%s → %s)", nm, m$why, m$sc), BASE[[m$sc]], targets = m$tg)
}

cat("\n── T10 격리: Renviron 이 가리키는 루트(= 운영)의 후보 디렉터리 무접촉 ──\n")
ok(identical(.cand_snap(), .CAND0), sprintf("T10 ★%s 의 .cache/_regime_candidate 무접촉(자식이 ~/.Renviron QM_ROOT 로 새지 않았다 · 감시 루트 %d개)",
                                        paste(.guard_roots, collapse = " · "), length(.guard_roots)))
Sys.setenv(R_ENVIRON_USER = .renv_orig)
cat(sprintf("\n=== 최종: %d PASS / %d FAIL / %d SKIP ===\n", P, FL, length(SKIPS)))
cat(as.character(toJSON(list(test = "test_regime_ledger_c11", pass = P, fail = FL, total = P + FL,
                             skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
## 성공 시 quit 하지 않는다 — 08_Tests/regime/run_all.R 가 이 파일을 같은 프로세스에서 sys.source 하므로
##   quit(0) 은 러너를 죽인다(수렴 규약: test_m4_append_candidate_filter.R). 실패·SKIP 만 종료 1.
if (FL > 0L || length(SKIPS) > 0L) quit(status = 1L, save = "no")
unlink(TD, recursive = TRUE)
