#!/usr/bin/env Rscript
#==============================================================================
# test_fw_d3_c11_label.R — D3 배포 생성기 §2d (PIT C11 표식 라벨) 위반 주입
#   대상: 02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R §2d  (+ generator_pins.json 핀 정합)
#   신설: 2026-09-24 (PIT C11 2단계 준비 · 판정서 V-03·V-04 · 결정 PIT-C11-BOOK0001 '표기 → 수리 뒤 재산출')
#
# ## 무엇을 재는가
#   게이트 두 입력(m4 · AE)의 C11 표식을 생성기가 **읽고**(라벨), 컷오프가 결정일 뒤면 **멈추고**(PIT),
#   그 밖에는 **비중을 한 줄도 바꾸지 않는가**(라벨 전용).
# ## 방법 — 배포 파일 §2d 블록을 잘라 fixture 위에서 eval (재구현 금지 · test_ae_consumer_freshness.R 과 같은 방식)
# ## 검출력 — MUT-1 컷오프 차단 제거판이 위반을 통과시킨다 · MUT-2 표식 무시판이 전부 UNRESOLVED 로 접힌다
#
# 실행: Rscript 08_Tests/portfolio/test_fw_d3_c11_label.R
#==============================================================================
suppressPackageStartupMessages({ library(arrow); library(data.table); library(jsonlite) })

.self <- tryCatch(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])),
                  error = function(e) NA_character_)
GEN_REL <- "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R"
.pick_root <- function() {
  for (c in c(if (!is.na(.self)) file.path(.self, "..", ".."), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (!nzchar(c)) next
    c <- gsub("\\\\", "/", c)
    if (file.exists(file.path(c, GEN_REL))) return(c)
  }
  NULL
}
ROOT_REPO <- .pick_root()
if (is.null(ROOT_REPO)) { cat("PROJECT_ROOT 해석 실패 — 표지", GEN_REL, "없음\n"); quit(status = 2) }
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
pick_src <- function(rel) Filter(file.exists, c(file.path(ROOT_REPO, rel), file.path(DATA_ROOT, rel)))[1]
FA_SRC <- pick_src("02_Infrastructure/data/fred_availability.R")
RULES_SRC <- pick_src("06_Registry/fred_availability_rules.json")
if (is.na(FA_SRC) || is.na(RULES_SRC)) { cat("가용시점 층 부재\n"); quit(status = 2) }

PASS <- 0L; FAILS <- character(0)
ok  <- function(n, note = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n          %s\n", n, note)) }
bad <- function(n, m) { FAILS <<- c(FAILS, n); cat(sprintf("  ★FAIL %s\n          %s\n", n, m)) }
chk <- function(n, expr) {
  r <- tryCatch(expr, error = function(e) structure(conditionMessage(e), class = "terr"))
  if (inherits(r, "terr")) bad(n, r) else ok(n, r)
}

GEN_LINES <- readLines(file.path(ROOT_REPO, GEN_REL), warn = FALSE, encoding = "UTF-8")
i0 <- grep("^## --- 2d\\.", GEN_LINES); i1 <- grep("^## --- 3\\.", GEN_LINES)
if (length(i0) != 1L || length(i1) != 1L || i1 <= i0) { cat("§2d 블록 경계 해석 실패\n"); quit(status = 2) }
BLOCK <- GEN_LINES[i0:(i1 - 1L)]
EXPR <- parse(text = paste(BLOCK, collapse = "\n"))

TD <- file.path(tempdir(), paste0("fwc11_", Sys.getpid()))
FX <- file.path(TD, "root"); dir.create(file.path(FX, "02_Infrastructure/data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(FX, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(FA_SRC, file.path(FX, "02_Infrastructure/data/fred_availability.R"))
file.copy(RULES_SRC, file.path(FX, "06_Registry/fred_availability_rules.json"))
KEY <- local({ e <- new.env(); suppressMessages(sys.source(FA_SRC, envir = e)); e$fred_avail_rules_meta(RULES_SRC)$regime_key })
AS_OF <- as.Date("2026-10-01")

## AE 행은 **실제 생산 경로 형식**으로 만든다 — pandas datetime64[ns](tz 없음) = arrow timestamp[ns] → R POSIXct.
##   (tz 변환으로 하루 앞당겨지는 함정을 이 경로로 같이 잰다)
mk_aer <- function(cut = "2026-09-30", key = KEY, stamped = TRUE) {
  cols <- list(decision_date = Array$create(as.POSIXct("2026-10-01", tz = "UTC"))$cast(timestamp("ns")),
               fire_seq = Array$create(1L), last_feat_date = Array$create(as.POSIXct("2026-09-30", tz = "UTC"))$cast(timestamp("ns")))
  if (stamped) {
    cols$c11_feat_join <- Array$create("c11_avail_decision_close")
    cols$c11_regime_key <- Array$create(key)
    cols$c11_info_cutoff <- Array$create(as.POSIXct(cut, tz = "UTC"))$cast(timestamp("ns"))
    cols$c11_vintage_unresolved <- Array$create("Chi_Fin_Cond,StL_Fin_Stress")
  }
  p <- tempfile(tmpdir = TD, fileext = ".parquet")
  write_parquet(do.call(arrow_table, cols), p)
  x <- as.data.table(read_parquet(p)); x[, decision_date := as.Date(decision_date)]; x
}
mk_m4r <- function(status = "verified", cut = "2026-10-01", key = KEY, stamped = TRUE) {
  x <- data.table(Date = as.Date("2026-10-01"), weight_str1715 = 0.92)
  if (stamped) x[, `:=`(c11_info_cutoff = as.Date(cut), c11_regime_key = key, c11_status = status)]
  x
}
run_block <- function(expr, aer, m4r) {
  env <- new.env(parent = globalenv())
  assign("ROOT", FX, envir = env); assign("AS_OF", AS_OF, envir = env)
  assign("aer", aer, envir = env); assign("m4r", m4r, envir = env)
  assign("gate", 0.70, envir = env); assign("m4_scalar", 0.92, envir = env); assign("ae_fire", 1L, envir = env)
  utils::capture.output(eval(expr, envir = env))
  list(gate_c11 = get("GATE_C11", envir = env), ae = get("AE_C11", envir = env), m4 = get("M4_C11", envir = env),
       gate = get("gate", envir = env), m4_scalar = get("m4_scalar", envir = env), ae_fire = get("ae_fire", envir = env))
}
expect_stop <- function(expr, aer, m4r, pat) {
  e <- tryCatch({ run_block(expr, aer, m4r); NULL }, error = function(e) conditionMessage(e))
  if (is.null(e)) stop("위반이 통과됨 — C11 차단 사망")
  if (!grepl(pat, e)) stop(sprintf("다른 사유로 실패: %s", substr(e, 1, 120)))
  sprintf("차단: %s", substr(e, 1, 90))
}

cat(strrep("=", 78), "\n", "test_fw_d3_c11_label — D3 생성기 §2d C11 표식 (epoch ", KEY, ")\n", strrep("=", 78), "\n", sep = "")

chk("V1  ★m4·AE 모두 현행 epoch 표식 → gate C11_VERIFIED · AE 컷오프 날짜 보존(timestamp[ns] 경로)", {
  r <- run_block(EXPR, mk_aer(), mk_m4r())
  if (!identical(r$gate_c11, "C11_VERIFIED")) stop(sprintf("gate=%s ae=%s m4=%s", r$gate_c11, r$ae$status, r$m4$status))
  if (!identical(r$ae$info_cutoff, "2026-09-30")) stop(sprintf("AE 컷오프 %s (하루 밀림 = tz 함정)", r$ae$info_cutoff))
  sprintf("gate %s · AE cut %s · m4 %s", r$gate_c11, r$ae$info_cutoff, r$m4$status)
})
chk("V2  AE 표식 없음(수리 전 판) → 비중 무개입 · gate C11_UNRESOLVED 표기", {
  r <- run_block(EXPR, mk_aer(stamped = FALSE), mk_m4r())
  if (!identical(r$ae$status, "C11_UNRESOLVED") || !identical(r$gate_c11, "C11_UNRESOLVED")) stop(r$ae$status)
  "AE C11_UNRESOLVED → gate UNRESOLVED (중단 아님)"
})
chk("V3  ★AE 컷오프 = 결정일 → 차단(stop)", expect_stop(EXPR, mk_aer(cut = "2026-10-01"), mk_m4r(), "C11 위반"))
chk("V4  ★m4 verified 인데 컷오프 > 결정일 → 차단(stop)", expect_stop(EXPR, mk_aer(), mk_m4r(cut = "2026-10-02"), "C11 위반"))
chk("V5  AE 옛 epoch → C11_STALE_EPOCH · gate UNRESOLVED", {
  r <- run_block(EXPR, mk_aer(key = "c11_avail:OLD"), mk_m4r())
  if (!identical(r$ae$status, "C11_STALE_EPOCH") || !identical(r$gate_c11, "C11_UNRESOLVED")) stop(r$ae$status)
  "STALE_EPOCH → UNRESOLVED"
})
chk("V6  m4 표식 열 없음(구 원장) → unresolved 표기 · m4 unresolved 행 → gate UNRESOLVED", {
  r1 <- run_block(EXPR, mk_aer(), mk_m4r(stamped = FALSE))
  r2 <- run_block(EXPR, mk_aer(), mk_m4r(status = "unresolved", cut = NA))
  if (!grepl("unresolved", r1$m4$status) || !identical(r1$gate_c11, "C11_UNRESOLVED") || !identical(r2$gate_c11, "C11_UNRESOLVED"))
    stop(paste(r1$m4$status, r1$gate_c11, r2$gate_c11))
  "열 없음·unresolved 둘 다 UNRESOLVED (중단 아님)"
})
chk("V7  m4 no_regime(워밍업) · m4 옛 epoch", {
  r1 <- run_block(EXPR, mk_aer(), mk_m4r(status = "no_regime", cut = NA, key = NA_character_))
  r2 <- run_block(EXPR, mk_aer(), mk_m4r(key = "c11_avail:OLD"))
  if (!identical(r1$gate_c11, "C11_VERIFIED") || !identical(r2$m4$status, "verified_stale_epoch") || !identical(r2$gate_c11, "C11_UNRESOLVED"))
    stop(paste(r1$gate_c11, r2$m4$status, r2$gate_c11))
  "no_regime = 해외 정보 없음 → VERIFIED · 옛 epoch → UNRESOLVED"
})
chk("W1  ★라벨 전용 — 블록이 gate·m4_scalar·ae_fire 를 바꾸지 않는다", {
  for (a in list(mk_aer(), mk_aer(stamped = FALSE))) {
    r <- run_block(EXPR, a, mk_m4r())
    if (!identical(r$gate, 0.70) || !identical(r$m4_scalar, 0.92) || !identical(r$ae_fire, 1L)) stop("블록이 게이트 입력을 바꿨다")
  }
  code <- sub("#.*$", "", BLOCK[!grepl("^\\s*#", BLOCK)])
  if (any(grepl("^\\s*(gate|w_fin|w_base|beta_R05|invested|m4_scalar|ae_fire)\\s*(<-|=)", code))) stop("비중 변수 대입이 블록에 있다")
  "gate 0.70 · m4 0.92 · ae_fire 1 불변 · 비중 변수 대입 0"
})
chk("W2  manifest 에 pit$c11(gate·ae·m4·rules_key) 기록", {
  if (!any(grepl("c11=list(gate=GATE_C11, ae=AE_C11, m4=M4_C11, rules_key=C11_KEY_NOW", GEN_LINES, fixed = TRUE))) stop("manifest 기록 부재")
  "pit$c11 기록 줄 실재"
})
chk("W3  §2b(신선도 검사 블록)에 C11 코드가 끼어들지 않음 — test_ae_consumer_freshness 추출 경계 보존", {
  j0 <- grep("^## --- 2b\\.", GEN_LINES); j1 <- grep("^## --- 2c\\.", GEN_LINES)
  b2 <- GEN_LINES[j0:(j1 - 1L)]
  if (any(grepl("C11_|m4r\\$c11", b2))) stop("§2b 에 C11 코드 — 그 블록만 eval 하는 기존 검사가 m4r 부재로 죽는다")
  "§2b 무변경 경계"
})
chk("P1  생성기 핀 정합 — 미러 sha1 == generator_pins.json (러너 [1b] exit 12 방지)", {
  pj <- file.path(ROOT_REPO, "02_Infrastructure/ops/generator_pins.json")
  if (!file.exists(pj)) stop("generator_pins.json 부재")
  e <- fromJSON(pj, simplifyVector = FALSE)[["STR_1715_on_M4gAE_R05_noLayer4_PG2"]]
  dg <- digest::digest(file = file.path(ROOT_REPO, e$mirror), algo = "sha1")
  if (!identical(dg, e$sha1)) stop(sprintf("핀 %s vs 실측 %s", substr(e$sha1, 1, 12), substr(dg, 1, 12)))
  sprintf("sha1 %s 일치", substr(dg, 1, 12))
})

## ── 검출력 ─────────────────────────────────────────────────────────────────
mut1 <- BLOCK; k <- grep("if (.cut >= AS_OF) stop(", mut1, fixed = TRUE)
chk("MUT-1  ★AE 컷오프 차단을 걷어낸 판은 V3 입력을 통과시킨다", {
  if (length(k) != 1L) stop("표지 줄 부재 — 돌연변이 무효")
  mut1[k] <- sub("if (.cut >= AS_OF) stop(", "if (FALSE) stop(", mut1[k], fixed = TRUE)
  r <- run_block(parse(text = paste(mut1, collapse = "\n")), mk_aer(cut = "2026-10-01"), mk_m4r())
  sprintf("돌연변이 통과(status %s) → 신판 V3 차단", r$ae$status)
})
mut2 <- BLOCK; k2 <- grep("AE_C11 <- if (all(c(\"c11_feat_join\"", mut2, fixed = TRUE)
chk("MUT-2  ★AE 표식을 안 읽는 판(구판 = 표기 없음)은 V1 입력도 UNRESOLVED 로 접는다", {
  if (length(k2) != 1L) stop("표지 줄 부재 — 돌연변이 무효")
  mut2[k2] <- sub("AE_C11 <- if (all(", "AE_C11 <- if (FALSE && all(", mut2[k2], fixed = TRUE)
  r <- run_block(parse(text = paste(mut2, collapse = "\n")), mk_aer(), mk_m4r())
  if (!identical(r$gate_c11, "C11_UNRESOLVED")) stop("돌연변이가 VERIFIED — 검사 무효")
  "돌연변이 UNRESOLVED → 신판 V1 VERIFIED"
})

unlink(TD, recursive = TRUE, force = TRUE)
cat(strrep("-", 78), "\n")
NT <- PASS + length(FAILS)
cat(sprintf("  %d/%d PASS\n", PASS, NT))
if (length(FAILS)) cat("  ★실패:", paste(FAILS, collapse = ", "), "\n")
cat(sprintf('{"test":"fw_d3_c11_label","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, length(FAILS), NT))
quit(status = if (length(FAILS)) 1L else 0L)
