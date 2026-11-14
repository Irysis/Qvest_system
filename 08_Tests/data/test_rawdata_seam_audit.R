#==============================================================================
# test_rawdata_seam_audit.R — RAWDATA 원천 이음매 감사기 (합성 픽스처 · 2026-11-13 · 원천 이음매 결함 수리)
#
# 무엇을 재나(운영 .cache · 06_Registry 읽기/쓰기 0 — 설정 · 등록부 · 사이드카는 tempdir 모래상자 루트):
#   A1 양성 대조 — ×5 분할 기준 단절(주식수 ÷5 · 시총 연속 · Ret 생비율) = 새 단절 · 등록부 항목 = 알려진 것(경보 없음)
#   A2 음성 대조 — 상한가 +30% · 정리매매 −90%(주식수 그대로 = 진짜 사건) · 유상증자(주식수 · 시총 같이) · 가드가 고친 행
#        (rescale · NA) = 단절 아님
#   A3 날짜 지문 — 한 날 30/100 종목 집단 단절 = 경보일 · 평상일 = 없음
#   A4 차단 — rsa_block_new 뒤 재감사 = 새 단절 0 · 경보일 0(알려진 것 그대로) · 다른 행 Ret 불변 · 행 순서 바뀐 표 = stop
#   A5 문턱 = 설정 경유 — DAY_FRAC_OFF_ALARM · BASIS_SHARES_TOL 을 바꾸면 판정이 따라 움직인다 · 설정 부재 = stop
#   A6 돌연변이(소스 텍스트 치환 · 정확히 1곳) — 생비율 조건 · 주식수 조건을 지운 사본은 음성 대조를 단절로 오검거해야 한다
#   A7 CLI — 오염 픽스처 rc 3 + RSA 줄 status=alarm · 깨끗한 픽스처 rc 0 · 없는 파일 rc 1
#
# 실행: R_ENVIRON_USER=<빈 파일> Rscript 08_Tests/data/test_rawdata_seam_audit.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })

.t_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  cands <- character(0)
  if (length(f)) cands <- c(cands, normalizePath(file.path(dirname(f[1]), "..", ".."), mustWork = FALSE))
  cands <- c(cands, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견")
  hit[1]
}
PROJ <- .t_root(); setwd(PROJ)
PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
chk <- function(cond, n, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)
cat("=== rawdata seam audit (합성 픽스처) ===\n")

DATA <- file.path(PROJ, "02_Infrastructure/data")
AUD <- file.path(DATA, "rawdata_seam_audit.R")
TMPD <- gsub("\\\\", "/", file.path(tempdir(), paste0("rsatest_", as.integer(Sys.time()))))

# ── 모래상자 루트: 표지 + 두 설정 사본 + 가짜 등록부 ─────────────────────────────
mk_root <- function(name, guard_patch = NULL, audit_patch = NULL, registry = NULL) {
  r <- file.path(TMPD, name)
  dir.create(file.path(r, "02_Infrastructure/hooks"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "02_Infrastructure/data"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(PROJ, "02_Infrastructure/hooks/qvest_hook_router.py"), file.path(r, "02_Infrastructure/hooks/"))
  g <- fromJSON(file.path(DATA, "seam_guard_config.json")); for (k in names(guard_patch)) g[[k]] <- guard_patch[[k]]
  a <- fromJSON(file.path(DATA, "rawdata_seam_audit_config.json")); for (k in names(audit_patch)) a[[k]] <- audit_patch[[k]]
  writeLines(toJSON(g, auto_unbox = TRUE, digits = NA), file.path(r, "02_Infrastructure/data/seam_guard_config.json"))
  writeLines(toJSON(a, auto_unbox = TRUE, digits = NA), file.path(r, "02_Infrastructure/data/rawdata_seam_audit_config.json"))
  if (!is.null(registry)) writeLines(toJSON(registry, auto_unbox = TRUE), file.path(r, "06_Registry/basis_break_registry.json"))
  # 수동 채움 등록부(2026-11-14 · 차단 대신 채움) — 가드 설정 RET_FILL_REGISTRY 가 가리키는 파일. 기본 = 빈 등록부
  writeLines(toJSON(list(schema = "ret_fill_registry_v1", entries = list()), auto_unbox = TRUE),
             file.path(r, "06_Registry/ret_fill_registry.json"))
  r
}
REG <- list(schema = "basis_break_registry_v1", generated_at = "2026-09-07T00:00:00+0900",
            scope = list(source_transition_seams = list("2026-03-30")),
            entries = list(list(Date = "2026-02-10", Ticker = "KNOWN", verdict = "adjustment_basis_break", action = "none"),
                           list(Date = "2026-03-30", Ticker = "SPLIT5", verdict = "adjustment_basis_break", action = "none")))
R0 <- mk_root("r0", registry = REG)
Sys.setenv(CLAUDE_PROJECT_DIR = R0, QM_ROOT = R0)
DATA_DIR <- DATA       # 감사기가 가드 정본을 검사 대상 트리에서 싣는다(모래상자 루트에는 코드가 없다)
source(AUD)            # 가드 정본도 함께 실린다(같은 트리의 seam_scale_guard.R)
CFG0 <- rsa_config(R0, reload = TRUE)

# ── 합성 픽스처 ────────────────────────────────────────────────────────────────
#   종목 100개 × 40거래일. 주식수 1e6 고정 · 가격 = 결정적 소폭 등락. 특수 종목만 사건을 심는다.
days <- seq(as.Date("2026-02-02"), by = "day", length.out = 60); days <- days[!as.POSIXlt(days)$wday %in% c(0L, 6L)][1:40]   # 로캘 무관(weekdays() 는 한국어 로캘에서 "토요일")
mk_fx <- function() {
  tk <- sprintf("T%03d", 1:100)
  X <- CJ(Ticker = tk, Date = days)
  X[, k := seq_len(.N), by = Ticker]
  X[, Close := 1000 * (1 + 0.003 * sin(k + as.integer(substr(Ticker, 2, 4))))]
  X[, shares := 1e6]
  ev <- function(tkr, d) X$Ticker == tkr & X$Date >= d
  dS <- days[10]; dK <- days[7]; dM <- days[30]; dR <- days[15]; dL <- days[20]; dD <- days[25]
  # SPLIT5: dS 부터 가격 ×5 · 주식수 ÷5 (시총 연속) → 기준 단절(새)
  X[Ticker == "T001", Ticker := "SPLIT5"]; X[ev("SPLIT5", dS), `:=`(Close = Close * 5, shares = shares / 5)]
  # KNOWN: dK 부터 ×2 · ÷2 — 등록부에 실린 원천 내부 단절(알려진 것)
  X[Ticker == "T002", Ticker := "KNOWN"]; X[ev("KNOWN", dK), `:=`(Close = Close * 2, shares = shares / 2)]
  # REPAIRED · BLOCKED: SPLIT5 와 같은 단절인데 가드가 고친 행(아래 Ret 단계에서 덮는다)
  X[Ticker == "T003", Ticker := "REPAIRED"]; X[ev("REPAIRED", dS), `:=`(Close = Close * 5, shares = shares / 5)]
  X[Ticker == "T004", Ticker := "BLOCKED"]; X[ev("BLOCKED", dS), `:=`(Close = Close * 5, shares = shares / 5)]
  # MEASURED: 같은 ×5 단절인데 저장 Ret 이 다른 계기로 잰 값(0.40 · 생비율 아님) — 생비율 조건이 일하는지 재는 자리
  X[Ticker == "T008", Ticker := "MEASURED"]; X[ev("MEASURED", dS), `:=`(Close = Close * 5, shares = shares / 5)]
  # LIMIT: dL 하루 +30% (주식수 그대로) · DELIST: dD 하루 −90% 정리매매(주식수 그대로)
  X[Ticker == "T005", Ticker := "LIMIT"]; X[ev("LIMIT", dL), Close := Close * 1.30]
  X[Ticker == "T006", Ticker := "DELIST"]; X[ev("DELIST", dD), Close := Close * 0.10]
  # RIGHTS: dR 유상증자 상장 — 주식수 +40% · 가격 그대로(시총 +40%) → |Ret| 작음 = 단절 아님
  X[Ticker == "T007", Ticker := "RIGHTS"]; X[ev("RIGHTS", dR), shares := shares * 1.4]
  # 집단 단절일 dM: T050~T079 30종목 ×5 · ÷5
  mass <- sprintf("T%03d", 50:79); X[Ticker %in% mass & Date >= dM, `:=`(Close = Close * 5, shares = shares / 5)]
  X[, Size := Close * shares]
  setorder(X, Ticker, Date)
  X[, Ret := Close / shift(Close) - 1, by = Ticker]
  pc <- X[Ticker == "REPAIRED" & Date == days[9], Close]; sc <- X[Ticker == "REPAIRED" & Date == dS, Close]
  X[Ticker == "REPAIRED" & Date == dS, Ret := sc / pc / 5 - 1]        # 가드 rescale_ret 과 같은 값
  X[Ticker == "BLOCKED" & Date == dS, Ret := NA_real_]                 # 가드 block_ret
  X[Ticker == "MEASURED" & Date == dS, Ret := 0.40]                     # 생비율(≈ +400%)이 아닌 저장값
  list(X = X[, .(Date, Ticker, Close, Size, Ret)], dS = dS, dK = dK, dM = dM, mass = mass)
}
FX <- mk_fx(); X <- FX$X

# ── A1 · A2 · A3 ───────────────────────────────────────────────────────────────
a <- rsa_audit(X, CFG0)
newk <- paste(a$hits_new$Ticker, a$hits_new$Date)
exp_new <- c(paste("SPLIT5", FX$dS), paste(FX$mass, FX$dM))
chk(setequal(newk, exp_new), "a1_new_breaks_exact", sprintf("새 단절 %d행 = SPLIT5 1 + 집단 30", length(newk)))
chk(identical(paste(a$hits_known$Ticker, a$hits_known$Date), paste("KNOWN", FX$dK)), "a1_known_from_registry",
    "등록부 원천 내부 단절 = 알려진 것(세기만)")
chk(!any(c("LIMIT", "DELIST", "RIGHTS", "REPAIRED", "BLOCKED", "MEASURED") %in% a$hits_new$Ticker), "a2_negatives_clean",
    "상한가 · 정리매매 · 유상증자 · 가드가 고친 행(rescale · NA) · 다른 계기 저장값 = 단절 아님")
chk(identical(as.character(a$days_alarm$Date), as.character(FX$dM)) && a$days_alarm$n_off == 30L, "a3_day_signature",
    sprintf("집단 단절일 %s = 경보(30/%d)", FX$dM, a$days_alarm$n))
chk(identical(a$status, "alarm"), "a3_status_alarm", "새 단절 · 경보일 있으면 alarm")
# ★원천 전환 이음매 날짜(03-30)에 등록된 항목은 알려진 것으로 세지 않는다(가드 소관 — 안 고쳐져 있으면 결함)
k <- rsa_known(CFG0)
chk(nrow(k) == 1L && identical(k$Ticker, "KNOWN"), "a1_transition_seam_not_known", "등록부 03-30 항목 = known 제외")

# ── A4 채움(2026-11-14 · 차단 대신 채움 — 도훈 결정 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114) ─────────────
#   시총이 이어지는 ×5 · ×2 단절 = 시총 기준 실수익(그날 시총 ÷ 전날 시총 − 1)이 제한폭 안 → 새 · 알려진 · 비어 있던(BLOCKED) 단절 모두 그 값으로 채운다.
X2 <- copy(X); X2 <- rsa_block_new(X2, a)
a2 <- rsa_audit(X2, CFG0)
fill_keys <- c(exp_new, paste("KNOWN", FX$dK), paste("BLOCKED", FX$dS))
X[, mc := Size / shift(Size) - 1, by = Ticker]
want <- X[paste(Ticker, Date) %in% fill_keys, .(Ticker, Date, mc)]
got <- merge(want, X2[, .(Ticker, Date, Ret)], by = c("Ticker", "Date"))
same_other <- isTRUE(all.equal(X[!paste(Ticker, Date) %in% fill_keys]$Ret, X2[!paste(Ticker, Date) %in% fill_keys]$Ret))
X[, mc := NULL]
chk(nrow(a2$hits_new) == 0L && nrow(a2$days_alarm) == 0L && nrow(a2$hits_known) == 0L && nrow(a2$hits_blocked) == 0L &&
      identical(a2$status, "ok") && same_other && nrow(got) == length(fill_keys) && isTRUE(all.equal(got$Ret, got$mc, tolerance = 1e-12)),
    "a4_fill_then_clean", "채움 뒤 재감사 ok · 새 31 + 알려진 1 + 비어 있던 1 = 시총 기준 실수익 · 다른 행 Ret 불변")
chk(attr(X2, "seam_audit_filled") == length(fill_keys) && attr(X2, "seam_audit_blocked") == 0L, "a4_fill_count",
    sprintf("채움 %d행 · 차단 %d행", attr(X2, "seam_audit_filled"), attr(X2, "seam_audit_blocked")))
chk(identical(a$status, "alarm") && a$counts$fill_new == length(exp_new) && a$counts$unresolved_new == 0L,
    "a4_status_counts", "집단 극단 수익일이 있으면 채워도 경보 · 새 단절 전부 채움 가능(못 채움 0)")
X3 <- copy(X); setorder(X3, Date, Ticker)
e4 <- tryCatch({ rsa_block_new(X3, a); "no_error" }, error = function(e) "stopped")
chk(identical(e4, "stopped"), "a4_reordered_table_stops", "감사 뒤 행 순서가 바뀐 표 = 엉뚱한 행을 지우지 않고 stop")

# ── A8 제한폭 밖 · 수동 등록부 · 날짜별 제한폭 ─────────────────────────────────────────
#   OUT30: 2026 새 단절인데 시총이 하루 −33%(±30% 밖 · 감사 단절 대역 ±35% 안) → 차단(NA) + 경보 · OLD15: 2014 알려진 단절 시총 −20%(±15% 밖) → 손대지 않음(목록)
#   OLD15b: 2014 알려진 단절 시총 −10%(안) → 채움 · MANUAL: 비어 있던 단절 시총 −33% 인데 수동 등록부 값(−0.123) → 등록부 값
mk8 <- function() {
  d1 <- seq(as.Date("2014-03-03"), by = "day", length.out = 20); d1 <- d1[!as.POSIXlt(d1)$wday %in% c(0L, 6L)][1:10]
  d2 <- seq(as.Date("2026-04-01"), by = "day", length.out = 20); d2 <- d2[!as.POSIXlt(d2)$wday %in% c(0L, 6L)][1:10]
  one <- function(tk, dd, f_close, f_size) { k <- seq_along(dd); cl <- 1000 + k; sh <- rep(1e6, length(dd))
    cl[6:length(dd)] <- cl[6:length(dd)] * f_close; sz <- cl * sh; sz[6:length(dd)] <- sz[5] * f_size * (1 + 0.001 * (0:(length(dd) - 6)))
    data.table(Ticker = tk, Date = dd, Close = cl, Size = sz) }
  Y <- rbind(one("OUT30", d2, 5, 0.67), one("OLD15", d1, 5, 0.80), one("OLD15b", d1, 5, 0.90), one("MANUAL", d2, 5, 0.67))
  setorder(Y, Ticker, Date); Y[, Ret := Close / shift(Close) - 1, by = Ticker]
  Y[Ticker == "MANUAL" & Date == d2[6], Ret := NA_real_]
  list(Y = Y, d1 = d1, d2 = d2)
}
F8 <- mk8()
REG8 <- list(schema = "basis_break_registry_v1", generated_at = "2026-11-14T00:00:00+0900", scope = list(source_transition_seams = list()),
             entries = list(list(Date = as.character(F8$d1[6]), Ticker = "OLD15", verdict = "adjustment_basis_break", action = "none"),
                            list(Date = as.character(F8$d1[6]), Ticker = "OLD15b", verdict = "adjustment_basis_break", action = "none")))
R8 <- mk_root("r8", registry = REG8)
writeLines(toJSON(list(schema = "ret_fill_registry_v1", entries = list(list(Date = as.character(F8$d2[6]), Ticker = "MANUAL", Ret = -0.123,
                                                                             method = "test", evidence = "test"))), auto_unbox = TRUE),
           file.path(R8, "06_Registry/ret_fill_registry.json"))
Sys.setenv(CLAUDE_PROJECT_DIR = R8, QM_ROOT = R8)
CFG8 <- rsa_config(R8, reload = TRUE)
a8 <- rsa_audit(F8$Y, CFG8)
Y2 <- rsa_block_new(copy(F8$Y), a8)
rget <- function(tk, d) Y2[Ticker == tk & Date == d, Ret]
mc_of <- function(tk, d) { y <- F8$Y[Ticker == tk]; k <- which(y$Date == d); y$Size[k] / y$Size[k - 1L] - 1 }
chk(is.na(rget("OUT30", F8$d2[6])) && identical(a8$status, "alarm") && a8$counts$unresolved_new == 1L, "a8_outside_limit_blocks",
    "2026 새 단절 시총 −33% = ±30% 밖 → 차단(NA) · 경보")
chk(isTRUE(all.equal(rget("OLD15", F8$d1[6]), F8$Y[Ticker == "OLD15" & Date == F8$d1[6], Ret])) && a8$counts$unresolved_known == 1L,
    "a8_old_limit_15_untouched", "2014 알려진 단절 시총 −20% = ±15% 밖 → 손대지 않음(목록 1)")
chk(isTRUE(all.equal(rget("OLD15b", F8$d1[6]), mc_of("OLD15b", F8$d1[6]))), "a8_old_inside_filled", "2014 알려진 단절 시총 −10% = 안 → 시총 기준 실수익")
chk(isTRUE(all.equal(rget("MANUAL", F8$d2[6]), -0.123)), "a8_manual_registry_wins", "비어 있던 단절 · 시총 −33% 인데 수동 등록부 값(−0.123) 채택")

# ── A9 채움 끔(FILL_MC_ENABLED = false) = 구 동작(새 단절 차단 · 알려진 것 무처치) · 수동 등록부는 그대로 ─────────────
R9 <- mk_root("r9", guard_patch = list(FILL_MC_ENABLED = FALSE), registry = REG)
Sys.setenv(CLAUDE_PROJECT_DIR = R9, QM_ROOT = R9)
a9 <- rsa_audit(X, rsa_config(R9, reload = TRUE)); X9 <- rsa_block_new(copy(X), a9)
chk(all(is.na(X9[paste(Ticker, Date) %in% exp_new]$Ret)) && isTRUE(all.equal(X9[Ticker == "KNOWN" & Date == FX$dK]$Ret, X[Ticker == "KNOWN" & Date == FX$dK]$Ret)),
    "a9_fill_off_is_old_behavior", "채움 끔 = 새 단절 31행 차단 · 알려진 것 그대로")

# ── A10 돌연변이 — rsa_block_new 의 채움 적용을 지운 사본은 A4 채움 단정이 빨개져야 한다 ─────────────
SRC <- readLines(AUD, warn = FALSE, encoding = "UTF-8")
pat <- "      set(dt, i = h$i[wf], j = \"Ret\", value = h$fill_ret[wf]); n_fill <- n_fill + length(wf)"
hits <- which(SRC == pat)
if (length(hits) != 1L) bad("a10_mutation_setup", sprintf("치환 대상 %d곳(1 이어야 함)", length(hits))) else {
  MUT <- SRC; MUT[hits] <- "      n_fill <- n_fill + length(wf)"
  mp <- tempfile(fileext = ".R"); writeLines(MUT, mp, useBytes = TRUE)
  E <- new.env(parent = globalenv()); sys.source(mp, envir = E)
  Sys.setenv(CLAUDE_PROJECT_DIR = R0, QM_ROOT = R0)
  am <- E$rsa_audit(X, E$rsa_config(R0, reload = TRUE)); Xm <- E$rsa_block_new(copy(X), am)
  still_raw <- isTRUE(all.equal(Xm[paste(Ticker, Date) %in% paste("SPLIT5", FX$dS)]$Ret, X[paste(Ticker, Date) %in% paste("SPLIT5", FX$dS)]$Ret))
  chk(still_raw, "a10_mutation_reddens", "채움 적용 줄을 지운 사본 = SPLIT5 가 생비율 그대로(검사가 채움을 재고 있다)")
}

# ── A11 수동 등록부 강제(2026-11-14) — 단절 지문 밖 행도 등록부 값으로 · 같은 값 = 손대지 않음 · 없는 종목 = 무시 · 멱등 ─────────────
#   Y2 = A8 처분 뒤 표(OLD15b 는 시총 기준 −10% 로 채워져 단절 지문 밖 — 지난 처분이 이전상장 첫날을 시총 기준으로 채운 자리와 같은 모양).
Sys.setenv(CLAUDE_PROJECT_DIR = R8, QM_ROOT = R8)
writeLines(toJSON(list(schema = "ret_fill_registry_v1", entries = list(
  list(Date = as.character(F8$d2[6]), Ticker = "MANUAL", Ret = -0.123, method = "test", evidence = "test"),
  list(Date = as.character(F8$d1[6]), Ticker = "OLD15b", Ret = -0.077, method = "test", evidence = "test"),
  list(Date = as.character(F8$d1[6]), Ticker = "GHOST", Ret = 0.5, method = "test", evidence = "test"))), auto_unbox = TRUE),
  file.path(R8, "06_Registry/ret_fill_registry.json"))
a11 <- rsa_audit(Y2, CFG8)
Y3 <- rsa_block_new(copy(Y2), a11)
k11 <- Y3$Ticker == "OLD15b" & Y3$Date == F8$d1[6]
chk(a11$counts$registry_fix == 1L && identical(a11$registry_fix$Ticker, "OLD15b") && isTRUE(all.equal(Y3$Ret[k11], -0.077)) &&
      identical(attr(Y3, "seam_audit_registry_fixed"), 1L), "a11_registry_enforced_outside_hits",
    "시총 기준으로 채워진 행(단절 지문 밖)도 등록부 값(−0.077)으로 · 1행")
chk(isTRUE(all.equal(Y3$Ret[!k11], Y2$Ret[!k11])) && a11$counts$registry_n == 3L && a11$counts$registry_missing == 1L &&
      identical(a11$registry_missing$Ticker, "GHOST"), "a11_registry_same_and_absent_untouched",
    "같은 값(MANUAL) · 없는 종목(GHOST) = 손대지 않음 · GHOST 는 '표에 없음' 목록 1행 · 다른 행 불변")
chk(rsa_audit(Y3, CFG8)$counts$registry_fix == 0L, "a11_registry_idempotent", "강제 뒤 재감사 = 강제 0(멱등)")
Y4 <- copy(Y2); setorder(Y4, Date, Ticker)
e11 <- tryCatch({ rsa_block_new(Y4, a11); "no_error" }, error = function(e) "stopped")
chk(identical(e11, "stopped"), "a11_reordered_table_stops", "감사 뒤 행 순서가 바뀐 표 = 등록부 강제도 쓰지 않고 stop")

# ── A12 돌연변이 — 등록부 강제 줄을 지운 사본은 A11 이 빨개져야 한다 ─────────────
pat12 <- "    set(dt, i = rf$i, j = \"Ret\", value = rf$Ret_reg); n_reg <- nrow(rf)"
h12 <- which(SRC == pat12)
if (length(h12) != 1L) bad("a12_mutation_setup", sprintf("치환 대상 %d곳(1 이어야 함)", length(h12))) else {
  MUT <- SRC; MUT[h12] <- "    n_reg <- nrow(rf)"
  mp <- tempfile(fileext = ".R"); writeLines(MUT, mp, useBytes = TRUE)
  E <- new.env(parent = globalenv()); sys.source(mp, envir = E)
  am <- E$rsa_audit(Y2, E$rsa_config(R8, reload = TRUE)); Ym <- E$rsa_block_new(copy(Y2), am)
  chk(isTRUE(all.equal(Ym$Ret[k11], Y2$Ret[k11])) && !isTRUE(all.equal(Ym$Ret[k11], -0.077)), "a12_mutation_reddens",
      "강제 줄을 지운 사본 = OLD15b 가 시총 기준 값 그대로(검사가 강제를 재고 있다)")
}
Sys.setenv(CLAUDE_PROJECT_DIR = R0, QM_ROOT = R0)

# ── A5 설정 경유 ───────────────────────────────────────────────────────────────
R1 <- mk_root("r1", audit_patch = list(DAY_FRAC_OFF_ALARM = 0.5), registry = REG)
a5 <- rsa_audit(X, rsa_config(R1, reload = TRUE))
R2 <- mk_root("r2", guard_patch = list(BASIS_SHARES_TOL = 10), registry = REG)
a6 <- rsa_audit(X, rsa_config(R2, reload = TRUE))
chk(nrow(a5$days_alarm) == 0L && nrow(a5$hits_new) == 31L && nrow(a6$hits_new) == 0L && nrow(a6$days_alarm) == 1L,
    "a5_thresholds_from_config", "날짜 문턱 0.5 → 경보일 0 · 주식수 문턱 10 → 종목 단절 0(하드코딩 부재)")
R3 <- mk_root("r3", registry = REG); file.remove(file.path(R3, "02_Infrastructure/data/rawdata_seam_audit_config.json"))
e5 <- tryCatch({ rsa_config(R3, reload = TRUE); "no_error" }, error = function(e) "stopped")
chk(identical(e5, "stopped"), "a5_missing_config_stops", "감사 설정 부재 = 기본값 낙하 없이 stop")
R4 <- mk_root("r4", registry = NULL)
a7 <- rsa_audit(X, rsa_config(R4, reload = TRUE))
chk(identical(a7$counts$known_status, "registry_absent") && nrow(a7$hits_known) == 0L && nrow(a7$hits_new) == 32L,
    "a5_registry_absent_marked", "등록부 부재 = 알려진 것 0 + 표지(지어내지 않는다 · KNOWN 도 새 단절)")

# ── A6 돌연변이 ────────────────────────────────────────────────────────────────
src <- paste(readLines(AUD, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
mut_run <- function(old, new) {
  n <- lengths(regmatches(src, gregexpr(old, src, fixed = TRUE)))
  if (n != 1L) return(sprintf("치환 대상 %d곳", n))
  p <- file.path(TMPD, "rsa_mut.R"); writeLines(sub(old, new, src, fixed = TRUE), p, useBytes = TRUE)
  e <- new.env(parent = globalenv())
  tryCatch({ sys.source(p, envir = e); e$rsa_audit(X, e$rsa_config(R0, reload = TRUE)) }, error = function(z) conditionMessage(z))
}
m1 <- mut_run("C[, unrepaired := is.finite(raw_ret) & abs(Ret - raw_ret) <= cfg$RET_MATCH_TOL * pmax(1, abs(Ret))]",
              "C[, unrepaired := TRUE]")
chk(is.list(m1) && "MEASURED" %in% m1$hits_new$Ticker, "a6_mutation_unrepaired_reddens",
    if (is.list(m1)) "생비율 조건 삭제 사본 = 다른 계기로 잰 저장값을 단절로 오검거(조건이 실제로 일한다)" else m1)
m2 <- mut_run("abs(r_shares - 1) > cfg$BASIS_SHARES_TOL & abs(rs - 1) <= mx]", "TRUE]")
chk(is.list(m2) && "DELIST" %in% m2$hits_new$Ticker, "a6_mutation_basis_reddens",
    if (is.list(m2)) "주식수 · 시총 조건 삭제 사본 = 정리매매 −90%(주식수 그대로)를 단절로 오검거" else m2)

# ── A7 CLI ─────────────────────────────────────────────────────────────────────
rscript <- file.path(R.home("bin"), "Rscript")
envf <- file.path(TMPD, "empty.Renviron"); writeLines("", envf)
run_cli <- function(pq) {
  old <- Sys.getenv(c("CLAUDE_PROJECT_DIR", "QM_ROOT", "R_ENVIRON_USER"), names = TRUE)
  on.exit(do.call(Sys.setenv, as.list(old)), add = TRUE)
  Sys.setenv(CLAUDE_PROJECT_DIR = R0, QM_ROOT = R0, R_ENVIRON_USER = envf)
  o <- suppressWarnings(system2(rscript, c(shQuote(AUD), "--rawdata", shQuote(pq), "--label", "t", "--no-sidecar"), stdout = TRUE, stderr = TRUE))
  list(rc = attr(o, "status") %||% 0L, line = tail(grep("^RSA\t", o, value = TRUE), 1))
}
p_bad <- file.path(TMPD, "bad.parquet"); write_parquet(X, p_bad)
p_ok <- file.path(TMPD, "ok.parquet"); write_parquet(X2, p_ok)
c1 <- run_cli(p_bad); c2 <- run_cli(p_ok); c3 <- run_cli(file.path(TMPD, "none.parquet"))
chk(identical(as.integer(c1$rc), 3L) && grepl("status=alarm\tnew=31", c1$line), "a7_cli_alarm_rc3", c1$line)
chk(identical(as.integer(c2$rc), 0L) && grepl("status=ok\tnew=0", c2$line), "a7_cli_ok_rc0", c2$line)
chk(identical(as.integer(c3$rc), 1L) && grepl("status=unreadable", c3$line), "a7_cli_missing_rc1", c3$line)

unlink(TMPD, recursive = TRUE)
cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL))
cat(jsonlite::toJSON(list(test = "rawdata_seam_audit", pass = PASS, fail = FAIL, skipped = 0L, total = PASS + FAIL, skips = list()),
                     auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
