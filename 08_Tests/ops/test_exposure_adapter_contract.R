#!/usr/bin/env Rscript
# test_exposure_adapter_contract.R — regime 레인 노출 어댑터 계약 위반 주입 (2026-08-09 신설).
#
# 왜 있나: regime 레인을 자동 배선하면서 **논문 유래 노출 스케줄**이 배터리에 합류할 수 있게 됐다.
#   노출 어댑터는 "얼마나 태울지"를 정하므로, 잘못되면 두 가지로 조용히 망가진다:
#     ① 미래참조 — 홀딩월 *말* 정보로 그 홀딩월 노출을 정하면 ~1개월 동월 look-ahead.
#        2026-07-06 BearProb 실사고가 정확히 이것이고, placebo·OOS·DSR·subperiod 를 **전부 통과**했다.
#        판별한 것은 lag1 스트레스와 strict-PIT A/B 뿐이었다. ⇒ 계약은 어댑터가 자기 컷오프를
#        **신고하게** 만들고, 신고 없으면 **로드를 거부**한다(부재를 '아마 괜찮음'으로 내려앉히지 않는다).
#     ② 제약 위반 — 노출 >1 은 레버리지, <0 은 숏. 둘 다 Production Constraints 밖이다.
#        ★clip 으로 조용히 살려내면 "무엇을 쟀나"가 흐려진다 → 살려내지 말고 제외 + 호명.
#
# ★검사 설계: 양성 + 위반 주입 8종 + 돌연변이(PIT 검사 없는 구판 래퍼).
#   돌연변이가 B·C 를 **통과시켜야** 이 검사가 실제로 무언가를 재는 것이다
#   (오탐 제거와 검사 사망은 겉보기가 같다 — [[feedback-verify-both-directions-always]]).

suppressMessages(library(data.table))

.root <- local({
  .marker <- file.path("02_Infrastructure", "methods", "method_registry.R")
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
.wd <- getwd(); setwd(.root)

PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

MR <- file.path(.root, "02_Infrastructure", "methods", "method_registry.R")
if (!file.exists(MR)) { cat("FATAL: method_registry.R 부재\n"); quit(status = 2) }
E <- new.env(parent = globalenv())
suppressMessages(sys.source(MR, envir = E))
for (sym in c("wrap_exposure_adapter", "load_exposure_adapters")) {
  if (!exists(sym, envir = E, inherits = FALSE)) {
    cat(sprintf("FATAL: `%s` 부재 — 계약이 없으면 이 검사는 아무것도 재지 않는다.\n", sym)); quit(status = 2)
  }
}
wrapf <- get("wrap_exposure_adapter", envir = E)

# ── 픽스처: 홀딩월 = month(decision_date) (실측 규약) ─────────────────────────
N <- 24L
dec  <- seq(as.Date("2024-01-01"), by = "month", length.out = N)
evl  <- seq(as.Date("2024-02-01"), by = "month", length.out = N)
CTX  <- list(periods = data.table(decision_date = dec, eval_date = evl),
             bare_gross = data.table(Date = evl, r = rep(0.01, N)))
HOLD <- as.Date(format(dec, "%Y-%m-01"))
CLEAN_CUT <- HOLD - 1           # 직전월 말 = clean
DIRTY_CUT <- HOLD + 20          # 홀딩월 '중' 정보 = 동월 look-ahead
EXP_OK <- data.table(Date = evl, exposure = rep(0.8, N))

mk <- function(exposure = EXP_OK, cutoff = CLEAN_CUT, drop_cut = FALSE, boom = FALSE) {
  force(exposure); force(cutoff); force(drop_cut); force(boom)
  function(ctx) {
    if (boom) stop("어댑터 내부 폭발")
    if (drop_cut) return(list(exposure = exposure))
    list(exposure = exposure, used_cutoff = cutoff)
  }
}
run <- function(fn, id = "T") {
  out <- NULL
  log <- utils::capture.output(out <- wrapf(fn, id)(CTX))
  list(out = out, log = paste(log, collapse = " | "))
}

cat("== regime 노출 어댑터 계약 위반 주입 테스트 ==\n")
cat(sprintf("   대상: %s\n\n", MR))

cat("[A] 양성 대조 — 정상 어댑터\n")
rA <- run(mk())
if (!is.null(rA$out) && nrow(rA$out) == N && all(abs(rA$out$exposure - 0.8) < 1e-12)) {
  ok(sprintf("통과 · %d개월 반환 (과잉차단 아님)", nrow(rA$out)))
} else { bad("A 양성", sprintf("out=%s log=%s", if (is.null(rA$out)) "NULL" else nrow(rA$out), rA$log)) }

cat("\n[B] ★위반 주입 — used_cutoff 미신고 (PIT 무신고)\n")
rB <- run(mk(drop_cut = TRUE))
if (is.null(rB$out) && grepl("계약 위반|PIT", rB$log)) {
  ok("로드 거부 + 호명 — 신고 없음을 '아마 괜찮음'으로 내려앉히지 않음")
} else { bad("B 무신고", sprintf("out=%s log=%s", if (is.null(rB$out)) "NULL" else "값", rB$log)) }

cat("\n[C] ★위반 주입 — 컷오프가 홀딩월 시작 이후 (2026-07-06 실사고 재현)\n")
rC <- run(mk(cutoff = DIRTY_CUT))
if (is.null(rC$out) && grepl("C5", rC$log)) {
  ok("거부 + C5 호명 (동월 look-ahead 차단)")
} else { bad("C 동월 누출", sprintf("out=%s log=%s", if (is.null(rC$out)) "NULL" else "값", rC$log)) }

cat("\n[C2] 경계 — 컷오프 == 홀딩월 시작일 (같은 날은 이미 홀딩월이다)\n")
rC2 <- run(mk(cutoff = HOLD))
if (is.null(rC2$out)) { ok("경계값도 거부 (>= 로 판정)") } else { bad("C2 경계", "통과함") }

cat("\n[D~G] 제약·형식 위반을 조용히 살려내지 않는가\n")
rD <- run(mk(exposure = data.table(Date = evl, exposure = c(1.4, rep(0.8, N - 1)))))
if (is.null(rD$out) && grepl("\\[0,1\\]|레버리지|무레버리지", rD$log)) {
  ok("D 노출>1 거부 (clip 으로 살려내지 않음)")
} else { bad("D 레버리지", rD$log) }
rE <- run(mk(exposure = data.table(Date = evl, exposure = c(-0.2, rep(0.8, N - 1)))))
if (is.null(rE$out)) { ok("E 노출<0 거부") } else { bad("E 음수 노출", rE$log) }
rF <- run(mk(exposure = data.table(Date = evl, exposure = c(NA_real_, rep(0.8, N - 1)))))
if (is.null(rF$out) && grepl("비유한", rF$log)) { ok("F 비유한 원소 거부") } else { bad("F 비유한", rF$log) }
rG <- run(mk(exposure = data.table(Date = evl, expo = rep(0.8, N))))
if (is.null(rG$out) && grepl("컬럼", rG$log)) { ok("G 컬럼 결손 거부") } else { bad("G 컬럼", rG$log) }

cat("\n[H] 어댑터 예외 — 조용한 성공으로 바뀌지 않는가\n")
rH <- run(mk(boom = TRUE))
if (is.null(rH$out) && grepl("예외", rH$log)) { ok("예외 → NULL + 호명") } else { bad("H 예외", rH$log) }

cat("\n[I] 스칼라 컷오프 신고 — 확장 허용(양성)\n")
rI <- run(mk(cutoff = as.Date("2023-12-31")))
if (!is.null(rI$out)) { ok("스칼라 1건 → 전 기간 확장 후 통과") } else { bad("I 스칼라", rI$log) }

cat("\n[J] 컷오프 길이 불일치 — 거부\n")
rJ <- run(mk(cutoff = CLEAN_CUT[1:3]))
if (is.null(rJ$out) && grepl("길이", rJ$log)) { ok("길이 불일치 거부") } else { bad("J 길이", rJ$log) }

cat("\n[K] ★돌연변이 — PIT/제약 검사를 뺀 구판 래퍼는 B·C·D 를 통과시켜야 한다\n")
legacy_wrap <- function(fn, id) function(ctx) {
  o <- tryCatch(fn(ctx), error = function(e) NULL)
  if (is.null(o)) return(NULL)
  e <- as.data.table(o$exposure); e[, Date := as.Date(Date)]; e[, .(Date, exposure = as.numeric(exposure))]
}
.leg <- function(fn) tryCatch(legacy_wrap(fn, "L")(CTX), error = function(e) NULL)
.missed <- sum(!is.null(.leg(mk(drop_cut = TRUE))),
               !is.null(.leg(mk(cutoff = DIRTY_CUT))),
               !is.null(.leg(mk(exposure = data.table(Date = evl, exposure = c(1.4, rep(0.8, N - 1)))))))
if (.missed == 3L) {
  ok("구판은 무신고·동월누출·레버리지 3종을 전부 통과시킴 — 이 검사의 판별력 실증")
} else { bad("K 돌연변이", sprintf("구판이 %d/3 만 통과 — 픽스처가 결함을 안 건드림", .missed)) }

cat("\n[L] 실물 레지스트리 — regime 노출 어댑터 등재 현황을 이름 붙여 보고하는가\n")
lg <- utils::capture.output(.ra <- get("load_exposure_adapters", envir = E)())
if (grepl("route=regime 노출 어댑터", paste(lg, collapse = " "))) {
  ok(sprintf("등재 %d건 — 로더가 건수를 호명(0 을 조용한 통과로 두지 않음)", length(.ra)))
} else { bad("L 실물 로더", paste(lg, collapse = " | ")) }

setwd(.wd)
cat(sprintf("\nFINAL: passed=%d failed=%d\n", PASS, FAIL))
quit(status = if (FAIL > 0) 1 else 0)
