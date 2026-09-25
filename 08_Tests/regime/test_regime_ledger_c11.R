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
for (p in c(LIB, FREDRG, SELFH, ROOTR, DRSH, GUARD, HELP, RULES, UTP, UTJ)) ok(file.exists(p), paste("존재", basename(p)))

mutant <- function(src, old, new, tag) {
  t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (lengths(regmatches(t, gregexpr(old, t, fixed = TRUE))) != 1L) return(NA_character_)
  f <- file.path(TD, paste0(tag, "_", basename(src))); writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE); f
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
  r$plan_epoch <- identical(pl$series$monthly$old_epoch, "legacy") && identical(pl$series$daily$candidate_epoch, K)
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
      identical(mt$c11_regime_key, K) && identical(mt$republished$archive_dir, ad)
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

report <- function(res, label) for (nm in names(res)) ok(isTRUE(res[[nm]]), sprintf("%s %s", label, nm))
red <- function(res, label) { bad <- names(res)[!vapply(res, isTRUE, logical(1))]
  ok(length(bad) > 0L, sprintf("%s ★red (깨진 검사: %s)", label, if (length(bad)) paste(bad, collapse = ",") else "없음 — 돌연변이를 못 잡는다")) }

# ═════════════════════════════════════════════════════════════════════════════
cat("\n── T1 legacy 병합 = 구판(git blob) 산출 ──\n")
OLDLIB <- git_blob(BLOB_OLD_APPEND, "old_append")
if (is.na(OLDLIB)) skip("T1", "git blob 부재(구판 regime_append_only.R)") else report(sc_T1(LIB, OLDLIB), "T1")
cat("\n── T2 같은 epoch 병합 — 표식 보존 · 소비자 가드 ──\n");      report(sc_T2(LIB), "T2")
cat("\n── T3 동결 구간 재서술 검출(양성 대조) ──\n");                report(sc_T3(LIB), "T3")
cat("\n── T4 epoch 불일치 = 무기록 ──\n");                           report(sc_T4(LIB), "T4")
cat("\n── T5 00:03 → 07:10 원문 경로 ──\n");                        report(sc_T5(LIB), "T5")
cat("\n── T6 재기준선 dry-run · 실행 · 복원 ──\n");                  report(sc_T6(LIB), "T6")
cat("\n── T7 동결 단조 ──\n");                                        report(sc_T7(LIB), "T7")

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

cat("\n── T9 돌연변이(같은 픽스처에서 red) ──\n")
MU <- list(
  M1 = list(old = "    out_attrs <- C$attrs\n", new = "    out_attrs <- list()\n", sc = "T2", why = "파일 속성 폐기"),
  M2 = list(old = "for (cl in c(REGIME_LEDGER_DECISION_COLS, REGIME_LEDGER_AVAIL_COLS))", new = "for (cl in REGIME_LEDGER_DECISION_COLS)", sc = "T3", why = "가용일 재서술 미검출"),
  M2b = list(old = "  status <- if (length(hard)) 1L else 0L\n", new = "  status <- 0L\n", sc = "T3", why = "재서술 검출 무력화"),
  M3 = list(old = "  same_epoch <- identical(ep$kind, ec$kind) && (ep$kind == \"legacy\" || identical(ep$key, ec$key))",
            new = "  same_epoch <- TRUE", sc = "T4", why = "epoch 대조 삭제(혼합 원장)"),
  M5 = list(old = "  if (!execute) {", new = "  if (FALSE) {", sc = "T6", why = "dry-run 이 기록"),
  M6 = list(old = "  if (isTRUE(fresh)) for (f in unlist(p))", new = "  if (FALSE) for (f in unlist(p))", sc = "T5", why = "잔재 후보 미삭제"),
  M7 = list(old = "  ft_write <- max(ft_prev, ft_new)", new = "  ft_write <- ft_new", sc = "T7", why = "동결 경계 후퇴"),
  M8 = list(old = "    else if (!identical(ec$key, rules_key)) prob(", new = "    else if (FALSE) prob(", sc = "T6", why = "재기준선 규칙 키 검사 삭제"),
  M10 = list(old = "    for (a in rev(done)) {", new = "    for (a in list()) {", sc = "T6", why = "보관 중간 실패 되돌림 삭제"),
  M11 = list(old = "  if (!is.null(expect_plan)) {", new = "  if (FALSE) {", sc = "T6", why = "검토 계획 대조 삭제"))
SC <- list(T2 = sc_T2, T3 = sc_T3, T4 = sc_T4, T5 = sc_T5, T6 = sc_T6, T7 = sc_T7)
for (nm in names(MU)) {
  m <- MU[[nm]]; f <- mutant(LIB, m$old, m$new, tolower(nm))
  if (is.na(f)) { ok(FALSE, sprintf("%s 대상 줄 부재(%s)", nm, m$why)); next }
  res <- tryCatch(SC[[m$sc]](f), error = function(e) { cat("    (시나리오 중단:", conditionMessage(e), ")\n"); list(crashed = FALSE) })
  red(res, sprintf("%s(%s → %s)", nm, m$why, m$sc))
}
## M4 — 구판 fred_regime.R(git blob): 07:10 이 원장 밖에서 라이브를 덮는다 → 00:03/07:10 교대
OLDFR <- git_blob(BLOB_OLD_FREDRG, "old_fred_regime")
if (is.na(OLDFR)) skip("M4", "git blob 부재(구판 fred_regime.R)") else {
  res <- tryCatch(sc_T5(LIB, fred_regime = OLDFR), error = function(e) { cat("    (시나리오 중단:", conditionMessage(e), ")\n"); list(crashed = FALSE) })
  red(res[c("daily_same", "monthly_hist_same", "build_fail_live_unchanged")], "M4(구판 fred_regime.R — 원장 밖 재빌드 → T5)")
}
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
