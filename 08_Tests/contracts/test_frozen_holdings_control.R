## test_frozen_holdings_control.R — 위기 전 보유 동결 대조 검사기(양성 · 음성 · 판정 불가 · 불변 · 원장 · 돌연변이)
## 지키는 것: 도훈 결정 CHARTER-GAP14-FOLLOWUPS-20261113 (나) '기록부터' — 보유 회전 β 타이밍 = A′ 의 타이밍(진단 기록만 · 등급 무접촉)
## 대상: contracts/frozen_holdings_control.R(fhc_frozen · fhc_dir · fhc_ledger_line · fhc_ledger_append · fhc_cfg)
##
## 합성 세계 = test_cr_notch_size_beta.R 와 같은 생성기(결정론 · 시드 고정 · 2003~2014 평일 · 200종목 · 위기 5번 · τ_D = 2009-12-31):
##   LOWB β 0.4 대칭 · B07 · B10 β 1.0 · B13 · QUAL 평상 1.0 / 위기 0.3(비대칭) · LQAS 평상 0.6 / 위기 0.2
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(.qv_self_dir(), "..", ".."), mustWork = FALSE)
if (dir.exists(file.path(SELF, "02_Infrastructure/contracts"))) ROOT <- SELF
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
source("02_Infrastructure/contracts/behavior_card.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/grade_v3.R")
source("02_Infrastructure/contracts/frozen_holdings_control.R")
cat("[root]", ROOT, "\n")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s %s\n", name, detail)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
throws <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
TD <- file.path(tempdir(), sprintf("fhc_%d", Sys.getpid())); dir.create(TD, showWarnings = FALSE, recursive = TRUE)

bcfg <- bc_cfg(ROOT)
bcfg$period_start <- "2000-01-01"; bcfg$tau_d <- "2009-12-31"; bcfg$dc_derive_window <- c("2003-01", "2014-12")
mcfg <- mc_cfg(ROOT); gcfg <- gv3_cfg(ROOT); fcfg <- fhc_cfg(ROOT)
MAJ <- bcfg$majority_share

## ── 합성 세계(test_cr_notch_size_beta.R 와 같은 생성기 · 같은 시드) ──
days <- seq(as.Date("2003-01-01"), as.Date("2014-12-31"), by = "day")
days <- days[!(as.POSIXlt(days)$wday %in% c(0L, 6L))]
nd <- length(days)
TK <- sprintf("T%03d", 1:200); MEGA <- TK[1:20]; SM <- TK[21:200]
size0 <- setNames(c(rep(1000, 20), 180:1), TK)
typ_of <- function(i) { k <- ((i - 1L) %% 20L) + 1L
  if (k <= 4L) "LOWB" else if (k <= 8L) "B07" else if (k <= 12L) "B10" else if (k <= 16L) "B13" else if (k <= 18L) "QUAL" else "LQAS" }
TYP <- setNames(c(rep("MEGA", 20), vapply(seq_along(SM), typ_of, "")), TK)
B_UP <- c(MEGA = 1.0, LOWB = 0.4, B07 = 0.7, B10 = 1.0, B13 = 1.3, QUAL = 1.0, LQAS = 0.6)
B_DN <- c(MEGA = 1.0, LOWB = 0.4, B07 = 0.7, B10 = 1.0, B13 = 1.3, QUAL = 0.3, LQAS = 0.2)
CR0 <- as.Date(c("2004-03-01", "2006-06-01", "2008-06-02", "2011-03-01", "2013-06-03"))
in_cr <- rep(FALSE, nd); in_rec <- rep(FALSE, nd)
for (c0 in CR0) { i0 <- which(days >= c0)[1]; in_cr[i0:(i0 + 62L)] <- TRUE; in_rec[(i0 + 63L):(i0 + 125L)] <- TRUE }
set.seed(20261113)
f <- ifelse(in_cr, 0.6^(1 / 63) - 1, ifelse(in_rec, (1 / 0.6)^(1 / 63) - 1, 0.0004)) + rnorm(nd, 0, 0.006)
EPS <- matrix(rnorm(nd * 200, 0, 0.015), nd, 200)
BU <- B_UP[TYP]; BD <- B_DN[TYP]
RM <- sapply(seq_along(TK), function(i) pmax(ifelse(in_cr, BD[i], BU[i]) * f + EPS[, i], -0.5))
colnames(RM) <- TK
SZM <- sweep(apply(1 + RM, 2, cumprod), 2, size0, `*`)
SZL <- rbind(size0, SZM[-nrow(SZM), ])
BMv <- rowSums(SZL * RM) / rowSums(SZL)
RAW <- data.table(Date = rep(days, times = length(TK)), Ticker = rep(TK, each = nd), K200 = 1, KQ150 = 0,
                  Size = as.vector(SZM), Ret = as.vector(RM), TradingHalt = 0)
setkey(RAW, Ticker, Date)
BM_ALL <- data.table(date = days, benchmark_ret = BMv)
EX <- days[!duplicated(format(days, "%Y-%m"))]; EX <- EX[EX >= as.Date("2003-02-01")]
eng <- function(H) {
  e <- sort(unique(H$date)); out <- vector("list", length(e))
  for (k in seq_along(e)) {
    hi <- if (k < length(e)) e[k + 1L] else max(days)
    dd <- days[days > e[k] & days <= hi]
    if (!length(dd)) next
    h <- H[date == e[k]]; GL <- sum(h$target_weight)
    rx <- xts::xts(RM[match(dd, days), h$ticker, drop = FALSE], order.by = dd)
    pr <- suppressWarnings(PerformanceAnalytics::Return.portfolio(rx, weights = setNames(h$target_weight / GL, h$ticker), rebalance_on = NA))
    out[[k]] <- data.table(date = as.Date(zoo::index(pr)), ret_net = GL * as.numeric(pr[, 1]))
  }
  rbindlist(out)
}
mkH <- function(f, ex = EX) rbindlist(lapply(ex, function(d) { w <- f(d); data.table(date = d, ticker = names(w), target_weight = unname(w)) }))
ew <- function(tks, gl = 1) setNames(rep(gl / length(tks), length(tks)), tks)
## 등급 v3.5 노치 근거(MC8 · 등급 계약) + 위기 전 보유 동결 대조(같은 입력 · 카드는 긴 벤치 이력으로 — fhc_dir 와 같은 규약)
run <- function(H, v35 = NULL, fenv = NULL) {
  S <- eng(H); B <- BM_ALL[date %in% S$date]; bmh <- BM_ALL[date <= max(S$date)]
  card <- bc_card(S, B, cfg = bcfg, bm_hist = bmh)
  ctl <- mc_controls(H, S, B, RAW, mcfg, "close_t1", "K200_KQ150")
  cm <- mc_attribution(card, ctl, B, bcfg)
  a <- cm$controls$attribution$overall; k <- cm$controls
  m <- list(status = k$status, label = a$label, share_beats_size_exposure = a$share_beats_size_exposure,
            exposure_varies = k$exposure_profile$varies, share_beats_size_exposure_path = a$share_beats_size_exposure_path,
            majority_share = k$attribution$majority_share, label_size_beta = a$label_size_beta,
            share_beats_size_beta = a$share_beats_size_beta, share_beats_size_beta_path = a$share_beats_size_beta_path,
            size_beta_status = k$beta_match$status, beta_leg = k$beta_match$beta_leg)
  basis <- v35 %||% gv3_notch_basis(m, NULL, gcfg$cr_notch[["timing_unit"]], "size_beta")
  ff <- if (is.null(fenv)) fhc_frozen else fenv$fhc_frozen
  fz <- ff(H, S, B, RAW, mcfg, "close_t1", "K200_KQ150", bcfg, card$crises, bmh, fcfg, v35_basis = basis, root = ROOT)
  list(S = S, B = B, H = H, card = card, basis = basis, cr = card$overall$cr, fz = fz)
}
sh <- function(x) if (is.null(x) || !length(x) || !is.finite(x)) "NA" else sprintf("%.2f", x)
fsum <- function(r) sprintf("(v3.5 %s · 동결 %s · 비율 %s · 시가총액만 %s · 위기 %d · 가상 %s)", r$basis, r$fz$label,
                           sh(r$fz$summary$overall$share_frozen_beats_size_beta), sh(r$fz$summary$overall$share_frozen_beats_size),
                           r$fz$summary$overall$n_crisis, r$fz$hypothetical_v36)

LOWB <- SM[TYP[SM] == "LOWB"]; QUAL <- SM[TYP[SM] == "QUAL"]; LQAS <- SM[TYP[SM] == "LQAS"]; B10 <- SM[TYP[SM] == "B10"]
tm <- vapply(seq_along(EX), function(k) { hi <- if (k < length(EX)) EX[k + 1L] else max(days); any(in_cr[days > EX[k] & days <= hi]) }, logical(1))
rot <- function(to, lag) mkH(function(d) { k <- match(d, EX); kk <- k - lag; ew(if (kk >= 1L && tm[kk]) to else B10) })

cat("=== 0. 설정 · 계약 ===\n")
chk("01 설정 정본 — 계약 판 · β 창(최대 ≥ 최소 ≥ 6) · 근거 문장(Fama-French 1992 DOI) · 원장 경로",
    identical(fcfg$contract, "frozen_holdings_control_v1") && fcfg$beta_window_months >= fcfg$beta_min_months && fcfg$beta_min_months >= 6 &&
      grepl("10.1111/j.1540-6261.1992.tb04398.x", fcfg$beta_window_source, fixed = TRUE) && nzchar(fcfg$ledger))
fj <- fromJSON(file.path(ROOT, "06_Registry/frozen_holdings_control.json"))
bad_f <- function(mut) { x <- mut(fj); p <- tempfile(fileext = ".json"); writeLines(toJSON(x, auto_unbox = TRUE), p); throws(fhc_cfg(ROOT, path = p)) }
chk("02 [위반 주입] 근거 빈칸 · 최소 > 최대 · 최소 < 6 · 계약 판 다름 → 멈춘다 · 정본은 통과",
    bad_f(function(x) { x$beta_window_source <- ""; x }) && bad_f(function(x) { x$beta_min_months <- 80; x }) &&
      bad_f(function(x) { x$beta_min_months <- 3; x }) && bad_f(function(x) { x$contract <- "v0"; x }) && !bad_f(function(x) x))

rP1 <- run(mkH(function(d) ew(QUAL)))
rP2 <- run(mkH(function(d) ew(LQAS)))
rN0 <- run(rot(LOWB, 0L))
rN1 <- run(rot(LOWB, 1L))
rQ1 <- run(rot(QUAL, 1L))
rS  <- run(mkH(function(d) ew(LOWB)))

cat("\n=== P. 양성 — 위기 전부터 비대칭 종목을 들고 있던 전략 ===\n")
chk("P1 품질(평상 β 1 · 위기 0.3)을 계속 보유 → v3.5 selection · 동결해도 시가총액 · β 일치 대조를 넘는다 → selection_survives_freeze",
    identical(rP1$basis, "selection") && identical(rP1$fz$label, "frozen_separated") && identical(rP1$fz$hypothetical_v36, "selection_survives_freeze") &&
      isTRUE(rP1$fz$summary$overall$share_frozen_beats_size_beta > MAJ), fsum(rP1))
chk("P2 저β + 비대칭(평상 0.6 · 위기 0.2) → 동결해도 넘는다(저β 자체를 벌하지 않는다)",
    identical(rP2$fz$label, "frozen_separated"), fsum(rP2))
chk("P3 보는 창 · 시험 창이 따로 적힌다(각 ≥ 1 위기 · 전체 = 둘의 합 이상)",
    rP1$fz$summary$visible$n_crisis >= 1L && rP1$fz$summary$test$n_crisis >= 1L &&
      rP1$fz$summary$overall$n_crisis >= rP1$fz$summary$visible$n_crisis + rP1$fz$summary$test$n_crisis,
    sprintf("(전체 %d · 보는 창 %d · 시험 창 %d)", rP1$fz$summary$overall$n_crisis, rP1$fz$summary$visible$n_crisis, rP1$fz$summary$test$n_crisis))
chk("P4 첫 위기(자료 시작 14개월 뒤)는 β 창 부족(최소 24개월)으로 판정에서 빠진다", "beta_window_short" %in% rP1$fz$per_crisis$status,
    sprintf("(상태 %s)", paste(names(rP1$fz$status_counts), unlist(rP1$fz$status_counts), sep = "=", collapse = " · ")))

cat("\n=== N. 음성 — 보유 회전(노출 1 · 평상 B10 → 위기 무렵 저β) ===\n")
chk("N0 고점 앞 회전(신호 지연 0) → v3.5 는 selection(알려진 빈틈) · 동결 보유 = 이미 저β → 위기 전 β 에 맞춘 대조를 못 넘는다 → rotation_timing",
    identical(rN0$basis, "selection") && identical(rN0$fz$label, "frozen_not_separated") && identical(rN0$fz$hypothetical_v36, "rotation_timing"), fsum(rN0))
chk("N1 한 달 늦은 회전 → v3.5 selection · 동결 보유 = 평상 B10 → 못 넘는다 → rotation_timing",
    identical(rN1$basis, "selection") && identical(rN1$fz$label, "frozen_not_separated") && identical(rN1$fz$hypothetical_v36, "rotation_timing"), fsum(rN1))
chk("N2 위기 무렵 품질로 회전(한 달 늦게) → 동결 보유 = 평상 B10 → 못 넘는다 → rotation_timing(회전 기여 = 동결 포착 − 실제 포착 > 0)",
    identical(rQ1$basis, "selection") && identical(rQ1$fz$label, "frozen_not_separated") && identical(rQ1$fz$hypothetical_v36, "rotation_timing") &&
      isTRUE(rQ1$fz$summary$overall$median_rotation_gap > 0), sprintf("%s · 회전 기여 중앙 %s", fsum(rQ1), sh(rQ1$fz$summary$overall$median_rotation_gap)))
chk("N3 정적 저β(0.4 대칭) → v3.5 부터 선택 아님 · 동결도 못 넘음 · 시가총액만 맞춘 대조는 넘는다(β 맞춤이 가르는 것)",
    identical(rS$basis, "beta_not_separated") && identical(rS$fz$hypothetical_v36, "not_selection_v35") && identical(rS$fz$label, "frozen_not_separated") &&
      isTRUE(rS$fz$summary$overall$share_frozen_beats_size > MAJ), fsum(rS))
chk("N4 동결 보유의 위기 전 β — 저β 보유 < 0.6 · 품질 보유는 저β 보다 0.25 이상 높다(위기 전 60개월 창은 앞선 위기 달도 섞어 잰다)",
    isTRUE(rS$fz$summary$overall$median_beta_frozen < 0.6) &&
      isTRUE(rP1$fz$summary$overall$median_beta_frozen > rS$fz$summary$overall$median_beta_frozen + 0.25),
    sprintf("(저β %s · 품질 %s)", sh(rS$fz$summary$overall$median_beta_frozen), sh(rP1$fz$summary$overall$median_beta_frozen)))

cat("\n=== U. 판정 불가 · 근거 ===\n")
rU <- run(mkH(function(d) ew(QUAL), ex = EX[EX >= as.Date("2012-06-01")]), v35 = "selection")
chk("U1 위기 2번 미만(전략 시작 2012-06) → insufficient · 근거 selection 이면 freeze_unresolved",
    identical(rU$fz$label, "insufficient") && identical(rU$fz$hypothetical_v36, "freeze_unresolved"), fsum(rU))
chk("U2 근거 없음(NA) → v35_basis_unknown · 근거가 timing_evidence 면 not_selection_v35(가상 판정은 selection 만 가른다)",
    identical(fhc_frozen(rP1$H, rP1$S, rP1$B, RAW, mcfg, "close_t1", "K200_KQ150", bcfg, rP1$card$crises, BM_ALL[date <= max(rP1$S$date)], fcfg,
                         v35_basis = NA_character_, root = ROOT)$hypothetical_v36, "v35_basis_unknown") &&
      identical(fhc_frozen(rP1$H, rP1$S, rP1$B, RAW, mcfg, "close_t1", "K200_KQ150", bcfg, rP1$card$crises, BM_ALL[date <= max(rP1$S$date)], fcfg,
                           v35_basis = "timing_evidence", root = ROOT)$hypothetical_v36, "not_selection_v35"))
rP1b <- run(mkH(function(d) ew(QUAL)))
chk("U3 결정성 — 같은 입력 두 번 = 위기별 표 동일(시드 = MC8 시드 + 고점 날짜)", isTRUE(all.equal(rP1$fz$per_crisis, rP1b$fz$per_crisis)))

cat("\n=== I. 디렉터리 경로 · 불변 · 원장 ===\n")
RD <- file.path(TD, "rec_P1"); dir.create(RD, showWarnings = FALSE)
fwrite(rP1$S[, .(date, ret_net, strategy_id = "SYN_QUAL")], file.path(RD, "03_period_returns.csv"))
fwrite(rP1$B, file.path(RD, "05_benchmark_returns.csv")); fwrite(rP1$H, file.path(RD, "04_holdings.csv"))
writeLines(toJSON(list(universe = "K200_KQ150", exec_price = "close_t1"), auto_unbox = TRUE), file.path(RD, "01_strategy_spec.json"))
writeLines(toJSON(list(strategy_name = "SYN_QUAL", essence_grade = "B", grade_v3 = list(rules_version = "v3.5", notch_basis = "selection",
                       cr_notch_basis = "strong", cr = list(overall = "strong"))), auto_unbox = TRUE), file.path(RD, "authoritative_remeasure.json"))
md5_0 <- tools::md5sum(list.files(RD, full.names = TRUE))
rd <- fhc_dir(RD, ROOT, raw = RAW, bm_hist = BM_ALL, fcfg = fcfg, cfg = mcfg, bcfg = bcfg)
md5_1 <- tools::md5sum(list.files(RD, full.names = TRUE))
chk("I1 디렉터리 경로 = 메모리 경로(라벨 · 비율 · 위기별 표) · 근거는 저장 권위 기록에서 읽는다",
    identical(rd$label, rP1$fz$label) && identical(rd$v35_basis, "selection") && isTRUE(all.equal(rd$per_crisis, rP1$fz$per_crisis)) &&
      identical(rd$source$strategy_name, "SYN_QUAL"), sprintf("(라벨 %s · 가상 %s)", rd$label, rd$hypothetical_v36))
chk("I2 불변 — 디렉터리의 파일 · md5 가 그대로(권위 기록 · 산출물 무접촉)", identical(md5_0, md5_1) && length(md5_0) == 5L)
LP <- file.path(TD, "ledger.jsonl")
l1 <- fhc_ledger_line(rd, RD, ROOT)
w1 <- fhc_ledger_append(list(l1), LP); w2 <- fhc_ledger_append(list(l1), LP)
l3 <- l1; l3$key <- paste0(l1$key, "|다른 시점")
w3 <- fhc_ledger_append(list(l3), LP)
back <- lapply(readLines(LP, encoding = "UTF-8"), fromJSON)
chk("I3 원장 — 첫 줄은 쓰고 같은 키는 건너뛰고 다른 키는 쓴다 · 줄마다 JSON · 위기별 날짜는 문자열",
    w1$written == 1L && w2$written == 0L && w2$skipped == 1L && w3$written == 1L && length(back) == 2L &&
      identical(back[[1]]$hypothetical_v36, rd$hypothetical_v36) && is.character(back[[1]]$per_crisis$peak_date))
chk("I4 원장 키 = 기록 · 권위 기록 md5 · 계약 판 · 데이터 시점(RAWDATA · 벤치 — 이 시험 루트의 .cache 판)",
    grepl("frozen_holdings_control_v1", l1$key, fixed = TRUE) && grepl(unname(md5_0[grepl("authoritative", names(md5_0))]), l1$key, fixed = TRUE))

cat("\n=== R. 기록 — 알려진 경계(판정 아님) ===\n")
rQ0 <- run(rot(QUAL, 0L))
cat(sprintf("  [기록] 고점 앞 품질 회전(완전 예지 · 신호 지연 0): %s — 동결 보유가 이미 품질이라 이 대조로는 '위기 직전에 고른 품질'과 '늘 품질'을 가르지 못한다(보유 이력 대조는 후속)\n", fsum(rQ0)))

cat("\n=== M. 돌연변이(소스 텍스트 치환 사본 — 치환 성사를 먼저 단정) ===\n")
mut <- function(from, to) {                                          # 치환 쌍 여러 개 — 쌍마다 정확히 1줄이 맞아야 한다
  src <- readLines(file.path(ROOT, "02_Infrastructure/contracts/frozen_holdings_control.R"), encoding = "UTF-8", warn = FALSE)
  for (q in seq_along(from)) {
    hit <- grepl(from[q], src, fixed = TRUE)
    if (sum(hit) != 1L) return(list(applied = FALSE, n = sum(hit)))
    src[hit] <- gsub(from[q], to[q], src[hit], fixed = TRUE)
  }
  p <- file.path(TD, "mut_fhc.R"); writeLines(src, p, useBytes = TRUE)
  en <- new.env(parent = globalenv()); sys.source(p, envir = en, keep.source = FALSE)
  list(applied = TRUE, env = en)
}
M1 <- mut("rho <- ifelse(is.finite(bj) & bj > 0, pmin(bF / bj, 1), NA_real_)", "rho <- ifelse(is.finite(bj) & bj > 0, 1, NA_real_)")
if (isTRUE(M1$applied)) { rM1 <- run(rot(LOWB, 0L), fenv = M1$env)
  chk("M1 [돌연변이] β 맞춤을 지우면(ρ = 1) 고점 앞 저β 회전이 동결 대조를 넘어 selection_survives_freeze — N0 가 잡는다",
      identical(rM1$fz$hypothetical_v36, "selection_survives_freeze") && identical(rN0$fz$hypothetical_v36, "rotation_timing"), fsum(rM1))
} else chk("M1 치환 대상 문장 1개", FALSE, sprintf("(n=%s)", M1$n))
M2 <- mut(c("e0 <- dd$exec_date[which.min(dd$date)]", "if (e0 > p0) { rows[[i]] <- st(\"held_after_peak\"); next }"),
          c("e0 <- dd$exec_date[which.max(dd$date)]", "if (FALSE) { rows[[i]] <- st(\"held_after_peak\"); next }"))
if (isTRUE(M2$applied)) { rM2 <- run(rot(QUAL, 1L), fenv = M2$env)
  chk("M2 [돌연변이] 동결 보유를 위기 끝(저점) 보유로 바꾸고 고점 뒤 보유 가드를 지우면 품질 회전이 selection_survives_freeze — N2 가 잡는다",
      identical(rM2$fz$hypothetical_v36, "selection_survives_freeze") && identical(rQ1$fz$hypothetical_v36, "rotation_timing"), fsum(rM2))
} else chk("M2 치환 대상 문장 1개", FALSE, sprintf("(n=%s)", M2$n))
M3 <- mut("e0 <- dd$exec_date[which.min(dd$date)]", "e0 <- dd$exec_date[which.max(dd$date)]")
if (isTRUE(M3$applied)) { rM3 <- run(rot(QUAL, 1L), fenv = M3$env)
  chk("M3 [돌연변이] 위기 끝 보유로만 바꾸면 고점 뒤 보유 가드가 모든 위기를 빼 판정 불가가 된다 — N2(rotation_timing)가 잡는다",
      !identical(rM3$fz$hypothetical_v36, "rotation_timing") && all(rM3$fz$per_crisis[status != "beta_window_short"]$status == "held_after_peak"), fsum(rM3))
} else chk("M3 치환 대상 문장 1개", FALSE, sprintf("(n=%s)", M3$n))

unlink(TD, recursive = TRUE)
cat(sprintf("\n== frozen_holdings_control: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"frozen_holdings_control","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
