#!/usr/bin/env Rscript
## test_pg2_coherence_check.R — PG2 정체성 정합 검사기의 위반 주입 테스트 (2026-08-08).
##
## 원 사고: Σ-A/B 배터리가 캐리어 2-1(구 PG2, overlay+Layer4)을 기준선으로 7주간 ΔIR 보고.
##   admitted_ids 는 이미 2-4(M4gAE, noLayer4)였고 Layer4 는 07-02 도훈 FINAL 제거.
##   근원 = book_state 안에서 정체성이 두 필드로 갈라짐(admitted_ids ↔ current_pg2_official_name).
##
## ★검사 설계: 축마다 **격리 주입**(1건당 1축)한다. 한 축이 다른 축을 가리면
##   "발화했다"가 "그 축을 쟀다"로 오독된다([[project-injection-fixture-confounding-20260802]]).
## ★clean 선확인 필수 — 모든 입력을 MISMATCH 로 만드는 검사기도 위반 주입은 다 통과한다.
## ★돌연변이: "admitted_ids 존재만 보는" 구판을 동반 실행 — C1/C2 를 **놓쳐야** 유효.

.root <- local({
  .marker <- file.path("02_Infrastructure", "portfolio", "pg2_coherence_check.R")
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
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
})
suppressPackageStartupMessages({ library(jsonlite) })
source(file.path(.root, "02_Infrastructure/portfolio/pg2_coherence_check.R"))
if (!exists("pg2_coherence_check")) { cat("FATAL: 검사기 로드 실패\n"); quit(status = 2) }

PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

CUR <- "STR_1715_on_M4gAE_R05_noLayer4_PG2"
OLD <- "STR_1715_AR_on_M4_R05_overlay_PG2"

## 픽스처 트리: book_state / carrier_meta / generator_pins / 실행코드 1개
mkfx <- function(official = CUR, carrier_strat = CUR,
                 carrier_at = "2026-07-19", book_at = "2026-07-19T05:12:00+09:00",
                 pins = CUR, code_hardcodes = FALSE, code_uses_resolver = TRUE) {
  d <- file.path(tempdir(), paste0("pg2fx_", as.integer(runif(1, 1e6, 9e6))))
  unlink(d, recursive = TRUE, force = TRUE)
  for (p in c("qepm/mailbox/governor", "06_Registry/book_carrier",
              "02_Infrastructure/ops", "02_Infrastructure/portfolio"))
    dir.create(file.path(d, p), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(list(admitted_ids = list(CUR), updated_at = book_at,
                    current_pg2_official_name = paste0(official, " (Layer 5 ...)"),
                    admitted_ids_prior_pre_d3_swapin = list(OLD)),   # ★형제 키 오염 함정 포함
                auto_unbox = TRUE, pretty = TRUE),
        file.path(d, "qepm/mailbox/governor/book_state.json"))
  write(toJSON(list(strategy = carrier_strat, book_state_updated_at = carrier_at, n_months = 269),
               auto_unbox = TRUE, pretty = TRUE),
        file.path(d, "06_Registry/book_carrier/carrier_meta.json"))
  gp <- list(`_readme` = "x"); gp[[pins]] <- list(mirror = "m", sha1 = "s")
  write(toJSON(gp, auto_unbox = TRUE, pretty = TRUE), file.path(d, "02_Infrastructure/ops/generator_pins.json"))
  body <- c("# fixture", if (code_hardcodes) sprintf('x <- "%s"', OLD) else 'x <- 1',
            if (code_uses_resolver) 'source("resolve_admitted_slot.R")' else '# none')
  writeLines(body, file.path(d, "02_Infrastructure/ops/fixture_consumer.R"))
  d
}
run <- function(d) { o <- NULL; utils::capture.output(o <- pg2_coherence_check(root = d, quiet = TRUE)); o }
codes <- function(r, sev = c("MISMATCH", "BLOCKED"))
  vapply(Filter(function(x) x$severity %in% sev, r$findings), function(x) x$code, character(1))

cat("== PG2 정합 검사기 위반 주입 테스트 ==\n\n")

cat("[0] clean 선확인\n")
r <- run(mkfx())
if (isTRUE(r$ok) && length(codes(r)) == 0) {
  ok("전 축 일치 → ok=TRUE, MISMATCH 0")
} else {
  bad("clean", sprintf("ok=%s codes=%s", r$ok, paste(codes(r), collapse = ",")))
}
if (identical(r$admitted_ids, CUR)) {
  ok("권위를 admitted_ids 에서 읽음 (형제 키 _prior_ 오염 없음)")
} else {
  bad("권위", sprintf("admitted_ids=%s", paste(r$admitted_ids, collapse = ",")))
}

cat("\n[1] 축별 격리 주입\n")
INJ <- list(
  list(n = "C1 current_pg2_official_name stale", fx = function() mkfx(official = OLD),        exp = "C1"),
  list(n = "C2 캐리어가 구 PG2",                  fx = function() mkfx(carrier_strat = OLD),   exp = "C2"),
  list(n = "C3 캐리어 시점 낙후",                  fx = function() mkfx(carrier_at = "2026-06-02"), exp = "C3"),
  list(n = "C4 생성기 핀이 non-admitted",          fx = function() mkfx(pins = OLD),            exp = "C4")
)
for (t in INJ) {
  r <- run(t$fx()); cs <- codes(r)
  hit <- t$exp %in% cs
  clean_others <- setdiff(cs, t$exp)
  if (hit && length(clean_others) == 0) ok(sprintf("%s → %s 단독 검거 (교락 없음)", t$n, t$exp))
  else if (hit) bad(t$n, sprintf("%s 검거했으나 다른 축도 발화: %s — 픽스처 교락", t$exp, paste(clean_others, collapse = ",")))
  else bad(t$n, sprintf("검거 실패. codes=%s", paste(cs, collapse = ",")))
}

cat("\n[2] C5 우회 census — WARN 축(격리)\n")
r <- run(mkfx(code_hardcodes = TRUE, code_uses_resolver = FALSE))
c5 <- Filter(function(x) x$code == "C5", r$findings)
if (length(c5) == 1L) {
  ok("하드코딩 + resolver 미참조 → C5 발화")
} else {
  bad("C5", "발화 안 함")
}
r2 <- run(mkfx(code_hardcodes = TRUE, code_uses_resolver = TRUE))
if (length(Filter(function(x) x$code == "C5", r2$findings)) == 0L) {
  ok("하드코딩이어도 resolver 참조하면 C5 미발화 (정상 소비자를 벌하지 않음)")
} else {
  bad("C5 오탐", "resolver 사용자를 우회로 계상")
}

cat("\n[3] ★돌연변이 — admitted_ids 존재만 보는 구판은 C1/C2 를 놓쳐야 한다\n")
legacy <- function(d) {
  bs <- fromJSON(file.path(d, "qepm/mailbox/governor/book_state.json"), simplifyVector = FALSE)
  a <- unlist(bs[["admitted_ids"]]); list(ok = length(a) > 0 && nzchar(a[1]))
}
lr1 <- legacy(mkfx(official = OLD)); lr2 <- legacy(mkfx(carrier_strat = OLD))
if (isTRUE(lr1$ok) && isTRUE(lr2$ok)) {
  ok("구판: C1·C2 주입을 둘 다 통과시킴 = 이 검사기의 판별력 실증")
} else {
  bad("돌연변이", "구판이 잡았다 — 픽스처가 두 판을 구별 못 함")
}

cat("\n[4] 실물 회귀 — 현 저장소 상태\n")
rr <- run(.root)
cs <- codes(rr)
if (length(cs)) {
  ok(sprintf("실물: 불일치 %d건 검거 (%s) — 08-08 적발 상태와 정합",
             length(cs), paste(cs, collapse = ",")))
} else {
  ok("실물: 전 축 일치 (PG2 참조가 모두 갱신된 상태)")
}

cat(sprintf("\nFINAL: passed=%d failed=%d\n", PASS, FAIL))
quit(status = if (FAIL > 0) 1 else 0)
