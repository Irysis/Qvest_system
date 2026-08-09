#!/usr/bin/env Rscript
# test_sigma_ab_freshness_gate.R — Σ-가중 A/B 배터리 신선도 게이트 위반 주입 테스트.
#
# 원 결함 (2026-08-08 실측):
#   paper_research_dispatch.R 의 게이트가 `ov_csv$mtime >= carrier$mtime` 단독이었다.
#   캐리어는 PG2 재구성 때만 갱신되므로 배터리를 한 번 돌린 뒤엔 **영구 참**이 된다.
#     carrier 2026-06-18 14:15  /  h1b_sigma_ab_overlay.csv 2026-06-18 16:46
#   → 07-01·07-26·08-02·08-04·08-06 research_status 가 전부 동일값
#     (book_ir 1.209 / EW 1.106 / ΔIR −0.103, n_months 269 — 당시 북은 271개월).
#   **7주간 캐시 1벌을 "오늘의 optimizer 판정"으로 텔레그램까지 재발송**했다.
#   ★"재계산 회피"로 쓴 게이트가 실제로는 **재계산 영구 정지**였다.
#   ★research_status_<D>.json 이 매일 새로 *쓰이므로* 파이프가 도는 것처럼 보인 게 은폐 기전
#     ("소비 흔적 = 소비" 계통. [[project-mode-queue-dispatch-drop-20260802]] 와 같은 파일).
#
# ★검사 설계 — 양방향 + 돌연변이:
#   (A) 진짜 최신이면 fresh 로 읽는가        — 재사용을 없애버리지 않았는지(매일 재실행 방지 목적 보존)
#   (B) 입력이 더 새로우면 stale 인가        — **원 결함 축**
#   (C) 입력이 안 움직여도 나이 초과면 stale  — 백스톱 축
#   (D) 입력 전무 = fresh 아님               — "부재를 정상값으로 내려앉히지 않기"
#   (E) 결과 파일 부재 = fresh 아님
#   돌연변이: 수리 전 carrier-단독 게이트를 동반 실행 — B·C 를 **놓쳐야** 한다.
#     전부 통과하면 이 검사는 아무것도 재지 않는 것이다(오탐 제거와 검사 사망은 겉보기가 같다).
#
# ★검사 대상 = 사본이 아니라 원본 .R 의 마커 구간 추출.
#   >>> SIGMA_AB_FRESHNESS_GATE … <<< SIGMA_AB_FRESHNESS_GATE

.root <- local({
  # ★앵커 1순위 = 이 스크립트 자신의 위치 (self-first).
  #   env 를 먼저 믿으면 worktree 에서 돌린 검사가 조용히 main 트리를 검사한다.
  #   [[project-test-runner-anchor-selffirst-20260802]]
  .marker <- file.path("02_Infrastructure", "ops", "paper_research_dispatch.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (dir.exists(cand)) cand else getwd()
})
TARGET <- Sys.getenv("QVEST_DISPATCH_R",
                     file.path(.root, "02_Infrastructure", "ops", "paper_research_dispatch.R"))

PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

# ── 원본에서 게이트 추출 ──────────────────────────────────────────────────────
extract_gate <- function(path) {
  if (!file.exists(path)) { cat("FATAL: 대상 부재:", path, "\n"); quit(status = 2) }
  ln <- readLines(path, warn = FALSE)
  b <- grep(">>> SIGMA_AB_FRESHNESS_GATE", ln, fixed = TRUE)
  e <- grep("<<< SIGMA_AB_FRESHNESS_GATE", ln, fixed = TRUE)
  if (length(b) != 1L || length(e) != 1L || e <= b) {
    cat("FATAL: 게이트 마커를 찾지 못했다 (b=", length(b), " e=", length(e), ") — ",
        "마커가 바뀌었으면 이 추출기부터 고칠 것. 조용히 0건 검사하는 것을 막기 위해 중단.\n", sep = "")
    quit(status = 2)
  }
  blk <- paste(ln[(b + 1):(e - 1)], collapse = "\n")
  # ★추출 범위 오류를 초록으로 넘기지 않는다 — 핵심 심볼 3종이 다 있어야 한다.
  for (sym in c("sigma_ab_inputs", "SIGMA_AB_MAX_AGE_DAYS", "fresh")) {
    if (!grepl(sym, blk, fixed = TRUE)) {
      cat(sprintf("FATAL: 추출 구간에 `%s` 가 없다 — 추출 범위 오류.\n", sym)); quit(status = 2)
    }
  }
  blk
}

GATE   <- extract_gate(TARGET)
# 돌연변이(수리 전 판): 캐리어 하나만 본다.
LEGACY <- 'fresh <- file.exists(ov_csv) && file.exists(carrier) &&
           file.info(ov_csv)$mtime >= file.info(carrier)$mtime
           .stale_why <- "(legacy)"'

OV      <- "06_Registry/book_carrier/h1b_sigma_ab_overlay.csv"
CARRIER <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
OTHERS  <- c(".cache/rawdata.parquet", ".cache/benchmark.parquet",
             paste0("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/",
                    "04_backtest_results/period_returns_layer5.csv"))

# 픽스처: 파일별 나이(일). NA = 그 파일 없음.
build_fixture <- function(dir, age_out, age_carrier, age_raw, age_bench, age_layer5) {
  unlink(dir, recursive = TRUE, force = TRUE)
  now <- Sys.time()
  put <- function(rel, age) {
    if (is.na(age)) return(invisible(NULL))
    p <- file.path(dir, rel)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines("x", p)
    Sys.setFileTime(p, now - age * 86400)
  }
  put(OV, age_out); put(CARRIER, age_carrier)
  put(OTHERS[1], age_raw); put(OTHERS[2], age_bench); put(OTHERS[3], age_layer5)
  invisible(dir)
}

# 게이트 블록을 픽스처 위에서 평가해 fresh / 사유를 돌려준다.
run_gate <- function(src, dir) {
  wd <- getwd(); on.exit(setwd(wd), add = TRUE)   # ★함수 안이라 on.exit 발화함(top-level 금칙 회피)
  setwd(dir)
  env <- new.env(parent = globalenv())
  assign("ov_csv", OV, envir = env); assign("carrier", CARRIER, envir = env)
  out <- utils::capture.output(eval(parse(text = src), envir = env))
  list(fresh = isTRUE(get0("fresh", envir = env, ifnotfound = NA)),
       why   = as.character(get0(".stale_why", envir = env, ifnotfound = "")),
       log   = paste(out, collapse = " | "))
}

TMP <- file.path(tempdir(), "sigma_ab_fresh_fx")

# name, 기대 fresh(수리판), 기대 fresh(legacy), 픽스처 나이(일)
CASES <- list(
  list(n = "A 정본 재사용 — 결과가 전 입력보다 새로움",           new = TRUE,  leg = TRUE,
       age = c(out =  1, car =  20, raw =  3, bench =  4, l5 =  5)),
  list(n = "B ★원 결함 — 입력(rawdata)이 결과보다 새로움",        new = FALSE, leg = TRUE,
       age = c(out = 10, car =  20, raw =  5, bench = 30, l5 = 40)),
  list(n = "C 백스톱 — 입력 정지 상태에서 결과만 노화",           new = FALSE, leg = TRUE,
       age = c(out = 40, car =  45, raw = 46, bench = 47, l5 = 48)),
  list(n = "D 입력 전무 — 판정 불가(fresh 아님)",                 new = FALSE, leg = FALSE,
       age = c(out =  1, car =  NA, raw = NA, bench = NA, l5 = NA)),
  list(n = "E 결과 부재",                                          new = FALSE, leg = FALSE,
       age = c(out = NA, car =  20, raw =  3, bench =  4, l5 =  5))
)

cat("== Σ-A/B 신선도 게이트 위반 주입 테스트 ==\n")
cat(sprintf("   대상: %s\n\n", TARGET))

cat("[1] 수리판 게이트 — 5 케이스\n")
for (cs in CASES) {
  build_fixture(TMP, cs$age[["out"]], cs$age[["car"]], cs$age[["raw"]],
                cs$age[["bench"]], cs$age[["l5"]])
  r <- run_gate(GATE, TMP)
  if (identical(r$fresh, cs$new)) ok(sprintf("%s → fresh=%s", cs$n, r$fresh))
  else bad(cs$n, sprintf("fresh=%s (기대 %s) why=%s", r$fresh, cs$new, r$why))
}

cat("\n[2] 돌연변이(수리 전 carrier-단독) — B·C 를 놓쳐야 검사가 유효\n")
missed <- 0
for (cs in CASES) {
  build_fixture(TMP, cs$age[["out"]], cs$age[["car"]], cs$age[["raw"]],
                cs$age[["bench"]], cs$age[["l5"]])
  r <- run_gate(LEGACY, TMP)
  if (identical(r$fresh, cs$leg)) ok(sprintf("legacy %s → fresh=%s (기대대로)", cs$n, r$fresh))
  else bad(sprintf("legacy %s", cs$n), sprintf("fresh=%s (기대 %s)", r$fresh, cs$leg))
  if (!identical(cs$new, cs$leg)) missed <- missed + 1
}
# ★R 최상위에서는 `if (..) x` 다음 줄 `else` 가 파스 에러다(블록 안에서만 허용). 반드시 중괄호로.
if (missed >= 2) {
  ok(sprintf("돌연변이 판별력: 수리판과 legacy 가 %d 케이스에서 갈림", missed))
} else {
  bad("돌연변이 판별력", sprintf("갈리는 케이스 %d건 (<2) — 검사가 결함을 구별 못 함", missed))
}

cat("\n[3] 실물 상태 회귀 — 현 저장소에서 stale 로 읽히는가\n")
# ★고정 기대값이 아니라 **현 실측 상태**에 대한 확인. 배터리가 재실행돼 결과가
#   진짜 최신이 되면 fresh=TRUE 가 정상이므로, 그 경우는 이유를 출력하고 통과시킨다.
if (dir.exists(.root)) {
  r <- run_gate(GATE, .root)
  if (isTRUE(r$fresh)) {
    ok("실물: fresh=TRUE — 배터리 결과가 전 입력보다 최신(재실행 완료 상태)")
  } else {
    ok(sprintf("실물: fresh=FALSE — 재계산 예정. 사유=%s", r$why))
  }
} else {
  bad("실물 상태", "프로젝트 루트 부재")
}

unlink(TMP, recursive = TRUE, force = TRUE)
cat(sprintf("\nFINAL: passed=%d failed=%d\n", PASS, FAIL))
## ★러너 집계용 요약 JSON — 이 줄이 없으면 run_all_hooks.sh 가 이 suite 를
##   UNREPORTED(=1 fail)로 계상하고 **통과 건수는 통째로 사라진다**.
##   위 FINAL 줄은 사람용이라 유지한다(둘 다 남긴다). 2026-08-09 추가.
cat(sprintf("{\"test\":\"sigma_ab_freshness_gate\",\"pass\":%d,\"fail\":%d,\"total\":%d}\n",
            PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0) 1 else 0)
