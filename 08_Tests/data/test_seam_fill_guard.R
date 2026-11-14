#==============================================================================
# test_seam_fill_guard.R — 이음매 가드 '차단 대신 채움'(2026-11-14 · 도훈 결정 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114)
#
# 무엇을 재나(합성 픽스처 · 운영 .cache · 06_Registry 읽기/쓰기 0 — 수동 채움 등록부는 tempdir 모래상자 루트):
#   G1 날짜별 가격제한폭 — 2015-06-12 = 0.15 · 2015-06-15 = 0.30 · 1995 = 0.15 · 설정 경유(PRICE_LIMIT_SCHEDULE)
#   G2 결정 함수 seam_fill_resolve — 안 → fill_mc · 밖 → block_ret · 수동 등록부 우선 · 간격 세션 누적 · 채움 끔 = block_ret
#   G3 가드 실구동(seam_scan_report → seam_apply_actions) — 원천 전환 이음매에서
#        U1 비정수배(×1.37) · 시총 연속 → fill_mc(Ret = 시총 기준 실수익) · U2 같은 비율 · 시총 −33%(±30% 밖) → block_ret(NA)
#        U3 = U2 와 같은데 수동 등록부 값 → fill_manual · S5 ×5 분할 → rescale_ret(구 동작 그대로) · 단절 없는 종목 Ret 불변
#   G4 돌연변이 — seam_apply_actions 의 채움 적용을 지운 사본은 U1 이 시총 값이 아니어야 한다(검사가 채움을 잰다)
#
# 실행: R_ENVIRON_USER=<빈 파일> Rscript 08_Tests/data/test_seam_fill_guard.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
.t_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  cands <- character(0)
  if (length(f)) cands <- c(cands, normalizePath(file.path(dirname(f[1]), "..", ".."), mustWork = FALSE))
  cands <- c(cands, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/data/seam_scale_guard.R"))]
  if (!length(hit)) stop("project root 미발견")
  hit[1]
}
PROJ <- .t_root()
GUARD <- file.path(PROJ, "02_Infrastructure/data/seam_scale_guard.R")
PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
chk <- function(cond, n, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)
cat("=== seam guard fill (합성 픽스처) ===\n")

# 모래상자 루트 — 표지 + 수동 채움 등록부(가드 설정 RET_FILL_REGISTRY 상대 경로)
SB <- gsub("\\\\", "/", file.path(tempdir(), paste0("sfg_", as.integer(Sys.time()))))
dir.create(file.path(SB, "02_Infrastructure/hooks"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(SB, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(PROJ, "02_Infrastructure/hooks/qvest_hook_router.py"), file.path(SB, "02_Infrastructure/hooks/"))
SEAM <- as.Date("2026-03-30")
writeLines(toJSON(list(schema = "ret_fill_registry_v1", entries = list(list(Date = as.character(SEAM), Ticker = "U3", Ret = -0.0777,
                                                                             method = "test", evidence = "test"))), auto_unbox = TRUE),
           file.path(SB, "06_Registry/ret_fill_registry.json"))
Sys.setenv(CLAUDE_PROJECT_DIR = PROJ, QM_ROOT = PROJ)
source(GUARD)
CFG <- seam_guard_config(file.path(PROJ, "02_Infrastructure/data/seam_guard_config.json"), reload = TRUE)
Sys.setenv(CLAUDE_PROJECT_DIR = SB, QM_ROOT = SB)        # 등록부 = 모래상자(운영 06_Registry 무접촉)
REG <- seam_fill_registry(CFG, SB)

# ── G1 ──────────────────────────────────────────────────────────────────────
lim <- seam_price_limit(as.Date(c("1995-05-02", "2015-06-12", "2015-06-15", "2026-03-30")), CFG)
chk(isTRUE(all.equal(lim, c(0.15, 0.15, 0.30, 0.30))), "g1_price_limit_schedule", "1995 · 2015-06-12 = 0.15 · 2015-06-15 · 2026 = 0.30")

# ── G2 ──────────────────────────────────────────────────────────────────────
r <- seam_fill_resolve(as.Date(c("2020-01-02", "2020-01-02", "2010-01-04", "2010-01-04", "2020-01-02")),
                       c("A", "B", "C", "D", "E"), c(-0.20, -0.33, -0.10, -0.20, -0.50), c(1L, 1L, 1L, 1L, 3L), CFG, REG)
chk(identical(r$action, c("fill_mc", "block_ret", "fill_mc", "block_ret", "fill_mc")) && isTRUE(all.equal(r$fill_ret[c(1, 3, 5)], c(-0.20, -0.10, -0.50))),
    "g2_resolve_limits", "2020 −20% 안 · −33% 밖 · 2010 −10% 안 · −20% 밖 · 3세션 −50% 안((1.3)^3−1)")
r2 <- seam_fill_resolve(SEAM, "U3", -0.40, 1L, CFG, REG)
chk(identical(r2$action, "fill_manual") && isTRUE(all.equal(r2$fill_ret, -0.0777)), "g2_manual_wins", "수동 등록부 값이 시총 값(밖)보다 우선")
CFG_OFF <- CFG; CFG_OFF$FILL_MC_ENABLED <- FALSE
r3 <- seam_fill_resolve(as.Date("2020-01-02"), "A", -0.20, 1L, CFG_OFF, REG)
chk(identical(r3$action, "block_ret"), "g2_fill_off", "채움 끔 = block_ret(구 동작)")

# ── G3 가드 실구동 ──────────────────────────────────────────────────────────────
days <- seq(SEAM - 20, SEAM + 10, by = "day"); days <- days[!as.POSIXlt(days)$wday %in% c(0L, 6L)]
mk <- function(tk, f_close, f_size, src_after = "quantiwise_update") {
  k <- seq_along(days); cl <- 1000 * (1 + 0.002 * sin(k + nchar(tk))); sz <- cl * 1e6
  aft <- days >= SEAM
  sz_seam <- sz[which(days == SEAM) - 1L] * f_size
  cl[aft] <- cl[aft] * f_close
  sz[aft] <- sz_seam * cl[aft] / cl[which(days == SEAM)]
  data.table(Date = days, Ticker = tk, Close = cl, Size = sz, source = ifelse(aft, src_after, "quantiwise"))
}
DT <- rbind(mk("U1", 1.37, 1.0), mk("U2", 1.37, 0.67), mk("U3", 1.37, 0.67), mk("S5", 5.0, 1.0), mk("NORM", 1.0, 1.0))
setorder(DT, Ticker, Date)
DT[, Ret := Close / shift(Close) - 1, by = Ticker]
rep <- seam_scan_report(DT, seam_scan_dates(DT, SEAM, CFG), CFG)
act <- function(tk) rep$tbl[Ticker == tk & Date == SEAM, action]
D2 <- seam_apply_actions(copy(DT), rep)
rg <- function(tk) D2[Ticker == tk & Date == SEAM, Ret]
mc <- function(tk) { y <- DT[Ticker == tk]; k <- which(y$Date == SEAM); y$Size[k] / y$Size[k - 1L] - 1 }
chk(identical(act("U1"), "fill_mc") && isTRUE(all.equal(rg("U1"), mc("U1"), tolerance = 1e-12)), "g3_unattributed_filled_mc",
    sprintf("U1 비정수배 ×1.37 · 시총 연속 → fill_mc · Ret %.5f = 시총 기준", rg("U1")))
chk(identical(act("U2"), "block_ret") && is.na(rg("U2")), "g3_outside_limit_blocked", "U2 시총 −33%(±30% 밖) → block_ret(NA)")
chk(identical(act("U3"), "fill_manual") && isTRUE(all.equal(rg("U3"), -0.0777)), "g3_manual_registry", "U3 = 수동 등록부 값")
chk(identical(act("S5"), "rescale_ret") && isTRUE(all.equal(rg("S5"), DT[Ticker == "S5" & Date == SEAM, Close] / DT[Ticker == "S5" & Date == SEAM - 3, Close] / 5 - 1, tolerance = 1e-9)),
    "g3_split_rescale_unchanged", "S5 ×5 → rescale_ret(구 동작)")
chk(isTRUE(all.equal(D2[Ticker == "NORM"]$Ret, DT[Ticker == "NORM"]$Ret)) &&
      isTRUE(all.equal(D2[Date != SEAM]$Ret, DT[Date != SEAM]$Ret)), "g3_others_untouched", "단절 없는 종목 · 다른 날 Ret 불변")

# ── G4 돌연변이 ──────────────────────────────────────────────────────────────
SRC <- readLines(GUARD, warn = FALSE, encoding = "UTF-8")
pat <- "    set(dt, i = pos[wf], j = \"Ret\", value = tbl$fill_ret[wf])"
hits <- which(SRC == pat)
if (length(hits) != 1L) bad("g4_mutation_setup", sprintf("치환 대상 %d곳(1 이어야 함)", length(hits))) else {
  MUT <- SRC; MUT[hits] <- "    invisible(NULL)"
  mp <- tempfile(fileext = ".R"); writeLines(MUT, mp, useBytes = TRUE)
  Sys.setenv(CLAUDE_PROJECT_DIR = PROJ, QM_ROOT = PROJ)
  E <- new.env(parent = globalenv()); invisible(capture.output(sys.source(mp, envir = E)))
  Sys.setenv(CLAUDE_PROJECT_DIR = SB, QM_ROOT = SB)
  Dm <- E$seam_apply_actions(copy(DT), rep)
  chk(!isTRUE(all.equal(Dm[Ticker == "U1" & Date == SEAM, Ret], mc("U1"), tolerance = 1e-12)), "g4_mutation_reddens",
      "채움 적용 줄을 지운 사본 = U1 이 시총 값이 아니다(검사가 채움을 재고 있다)")
}
cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL))
cat(sprintf('{"test":"seam_fill_guard","pass":%d,"fail":%d,"skipped":0,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
