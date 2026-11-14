## test_cr_notch_size_beta.R — 등급 v3.5 위기 복원력 '강함' 가점의 크기 × β 짝 검사기(양성 · 음성 · 타이밍 · 돌연변이 · 단조성)
## 지키는 것: 도훈 결정 GRADE-CR-NOTCH-BETA-SELECTION-20261113 (가) · 헌장 §5 빈칸 14(선택 방어 = 크기 × β 동시 짝까지 넘을 때)
##   사전등록 04_Research/01_reports/grade_v35_cr_beta_selection_20261113/PREREG.md §5(N1 · P1 · P2 · T1 · M1~M4 · Z)
## 대상: contracts/matched_controls.R ⑥(크기 × β 플라시보) · contracts/grade_v3.R(gv3_notch_basis · gv3_cr_for_notch · .gv3_mc8)
##
## 합성 세계(결정론 · 시드 고정 · 2003~2014 평일 · 200종목):
##   초대형 20종(시가총액 1000 · β 1) + 중소형 180종(180..1). 시장 인자 f = 평상 +0.04%/일 + 0.6% 잡음 ·
##   위기 5번(63거래일 · 인자 누적 −40%) · 다음 63거래일 회복(누적 +66.7%). 종목 수익 = β_i(t) × f + 1.5% 고유 잡음.
##   중소형은 크기 분위마다 같은 비율로 유형을 섞는다(시가총액 순위 20 단위로 4·4·4·4·2·2):
##     LOWB β 0.4 대칭 · B07 β 0.7 · B10 β 1.0 · B13 β 1.3 · QUAL 평상 · 회복 β 1.0 / 위기 β 0.3(비대칭) · LQAS 평상 0.6 / 위기 0.2(저β + 비대칭)
##   벤치 = 전날 시가총액 가중. τ_D = 2009-12-31(위기 3번 보는 창 · 2번 시험 창).
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
cat("[root]", ROOT, "\n")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s %s\n", name, detail)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
throws <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
TD <- file.path(tempdir(), sprintf("cr_sb_%d", Sys.getpid())); dir.create(TD, showWarnings = FALSE, recursive = TRUE)

bcfg <- bc_cfg(ROOT)
bcfg$period_start <- "2000-01-01"; bcfg$tau_d <- "2009-12-31"; bcfg$dc_derive_window <- c("2003-01", "2014-12")
mcfg <- mc_cfg(ROOT)
gcfg <- gv3_cfg(ROOT)
MAJ <- bcfg$majority_share

## ── 합성 세계 ──
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

# 독립 엔진(test_matched_controls.R 와 같은 관례 — 창 (e_k, e_k+1] 매수후보유 · Return.portfolio · 레그 × GL)
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
mkH <- function(f) rbindlist(lapply(EX, function(d) { w <- f(d); data.table(date = d, ticker = names(w), target_weight = unname(w)) }))
ew <- function(tks, gl = 1) setNames(rep(gl / length(tks), length(tks)), tks)
run <- function(H, mc = mcfg, env = NULL) {
  S <- eng(H); B <- BM_ALL[date %in% S$date]
  card <- bc_card(S, B, cfg = bcfg)
  fc <- if (is.null(env)) mc_controls else env$mc_controls
  fa <- if (is.null(env)) mc_attribution else env$mc_attribution
  ctl <- fc(H, S, B, RAW, mc, "close_t1", "K200_KQ150")
  list(S = S, B = B, H = H, ctl = ctl, card = fa(card, ctl, B, bcfg))
}
att <- function(r, w = "overall") r$card$controls$attribution[[w]]
# 등급 계약이 MC8 에서 읽는 그 필드 묶음(.gv3_mc8 과 같은 추출)을 메모리판으로 — 노치 근거 함수에 넣는다
mc8_of <- function(r) { a <- att(r); k <- r$card$controls
  list(status = k$status, label = a$label, share_beats_size_exposure = a$share_beats_size_exposure,
       exposure_varies = k$exposure_profile$varies, share_beats_size_exposure_path = a$share_beats_size_exposure_path,
       majority_share = k$attribution$majority_share, label_size_beta = a$label_size_beta,
       share_beats_size_beta = a$share_beats_size_beta, share_beats_size_beta_path = a$share_beats_size_beta_path,
       size_beta_status = k$beta_match$status, beta_leg = k$beta_match$beta_leg) }
cfg_old <- gcfg; cfg_old$cr_notch$selection_control <- "size_exposure"      # v3.2~v3.4 의미(같은 설정 · 짝만 다름)
nb <- function(m, ctl) gv3_notch_basis(m, NULL, gcfg$cr_notch[["timing_unit"]], ctl)
sh <- function(x) if (is.null(x) || !is.finite(x)) "NA" else sprintf("%.2f", x)

cat("=== 0. 합성 세계 · 설정 ===\n")
crs <- bc_crises_lt(BM_ALL[, .(date, r = benchmark_ret)], bcfg$crisis_lambda_down %||% 0.2, bcfg$crisis_lambda_up %||% 0.2)
chk("01 벤치 위기(LT 20/20) ≥ 4번 · 보는 창 · 시험 창 각 ≥ 2", nrow(crs) >= 4L && sum(crs$trough_date <= as.Date(bcfg$tau_d)) >= 2L &&
      sum(crs$peak_date > as.Date(bcfg$tau_d)) >= 2L, sprintf("(n=%d · depth=%s)", nrow(crs), paste(round(crs$depth, 2), collapse = ",")))
chk("02 정본 설정 = v3.5 · selection_control = size_beta · MC8 size_beta 블록 어휘", identical(gcfg$rules_version, "v3.5") &&
      identical(gv3_selection_control(gcfg), "size_beta") && identical(mcfg$size_beta$rule, "size_beta_placebo_v1") && isTRUE(mcfg$size_beta$cap == 1))

LOWB <- SM[TYP[SM] == "LOWB"]; QUAL <- SM[TYP[SM] == "QUAL"]; LQAS <- SM[TYP[SM] == "LQAS"]; B13 <- SM[TYP[SM] == "B13"]
rN1 <- run(mkH(function(d) ew(LOWB)))
rP1 <- run(mkH(function(d) ew(QUAL)))
rP2 <- run(mkH(function(d) ew(LQAS)))
tm <- vapply(seq_along(EX), function(k) { hi <- if (k < length(EX)) EX[k + 1L] else max(days); any(in_cr[days > EX[k] & days <= hi]) }, logical(1))
GLk <- setNames(ifelse(tm, 0.2, 1), as.character(EX))
rT1 <- run(mkH(function(d) ew(LOWB, GLk[[as.character(d)]])))
rH1 <- run(mkH(function(d) ew(B13)))

cat("\n=== N1. 음성 대조 — 분위 안 저β(0.4 대칭) 종목만 · 위기 비대칭 없음 ===\n")
a <- att(rN1); m <- mc8_of(rN1)
chk("N1a 구 짝(크기 × 노출)은 선택 방어로 센다 — 고친 결함의 재현", identical(a$label, "selection_defense"),
    sprintf("(label=%s · se=%s)", a$label, sh(a$share_beats_size_exposure)))
chk("N1b 크기 × β 짝은 못 넘는다 → label_size_beta = size_beta_unseparated", identical(a$label_size_beta, "size_beta_unseparated") &&
      isTRUE(a$share_beats_size_beta <= MAJ), sprintf("(sb=%s · β_leg=%s · ρ중앙=%s)", sh(a$share_beats_size_beta),
      sh(rN1$card$controls$beta_match$beta_leg), sh(rN1$card$controls$beta_match$rho_median)))
chk("N1c 노치: v3.4 의미 = selection(강함) · v3.5 = beta_not_separated(보통)",
    identical(nb(m, "size_exposure"), "selection") && identical(gv3_cr_for_notch("strong", m, cfg_old), "strong") &&
      identical(nb(m, "size_beta"), "beta_not_separated") && identical(gv3_cr_for_notch("strong", m, gcfg), "normal"))
chk("N1d β 맞춤 실측 — 전략 레그 β < 0.6(인자 β 0.4 · 벤치 대비) · 플라시보 β 중앙 > 레그 β · ρ 중앙 < 1",
    isTRUE(rN1$card$controls$beta_match$beta_leg < 0.6) &&
      isTRUE(rN1$card$controls$beta_match$placebo_beta$median > rN1$card$controls$beta_match$beta_leg) &&
      isTRUE(rN1$card$controls$beta_match$rho_median < 1), sprintf("(β_leg=%s · 플라시보 β 중앙=%s)",
      sh(rN1$card$controls$beta_match$beta_leg), sh(rN1$card$controls$beta_match$placebo_beta$median)))

cat("\n=== P1 · P2. 양성 대조 — 위기에만 덜 빠지는 종목(비대칭) ===\n")
a <- att(rP1); m <- mc8_of(rP1)
chk("P1a 평상 β 1 · 위기 β 0.3 종목 → 크기 × β 짝도 넘는다(selection_defense)", identical(a$label, "selection_defense") &&
      identical(a$label_size_beta, "selection_defense") && isTRUE(a$share_beats_size_beta > MAJ),
    sprintf("(se=%s · sb=%s · β_leg=%s)", sh(a$share_beats_size_exposure), sh(a$share_beats_size_beta), sh(rP1$card$controls$beta_match$beta_leg)))
chk("P1b 노치: v3.5 에서도 selection → 강함", identical(nb(m, "size_beta"), "selection") && identical(gv3_cr_for_notch("strong", m, gcfg), "strong"))
a <- att(rP2); m <- mc8_of(rP2)
chk("P2a 저β(평상 0.6) + 비대칭(위기 0.2) → β 가 낮아도 비대칭이면 선택(크기 × β 짝을 넘는다)", identical(a$label_size_beta, "selection_defense") &&
      isTRUE(a$share_beats_size_beta > MAJ), sprintf("(sb=%s · β_leg=%s)", sh(a$share_beats_size_beta), sh(rP2$card$controls$beta_match$beta_leg)))
chk("P2b 노치: v3.5 강함", identical(gv3_cr_for_notch("strong", m, gcfg), "strong"))

cat("\n=== T1. 저β + 노출 타이밍(위기 달 노출 0.2) — 경로판 크기 × β 짝 ===\n")
a <- att(rT1); m <- mc8_of(rT1)
chk("T1a 노출 경로가 변한다 · 경로판 두 짝이 있다", isTRUE(m$exposure_varies) && is.finite(a$share_beats_size_exposure_path) &&
      is.finite(a$share_beats_size_beta_path), sprintf("(sp=%s · spb=%s)", sh(a$share_beats_size_exposure_path), sh(a$share_beats_size_beta_path)))
chk("T1b 구 의미: 타이밍을 고정한 크기 × 노출 짝을 저β 로 이겨 selection(강함)", identical(nb(m, "size_exposure"), "selection") &&
      identical(gv3_cr_for_notch("strong", m, cfg_old), "strong"))
chk("T1c v3.5: 정적 크기 × β 짝은 넘지만(타이밍) 경로판 크기 × β 짝은 못 넘는다 → 타이밍 · 증거 없음 → 보통",
    isTRUE(a$share_beats_size_beta > MAJ) && isTRUE(a$share_beats_size_beta_path <= MAJ) &&
      identical(nb(m, "size_beta"), "timing_no_evidence") && identical(gv3_cr_for_notch("strong", m, gcfg), "normal"),
    sprintf("(sb=%s · spb=%s)", sh(a$share_beats_size_beta), sh(a$share_beats_size_beta_path)))

cat("\n=== H1. 고β(1.3 대칭) — 상한 1(차입 없음) ===\n")
a <- att(rH1)
chk("H1a 레그 β > 플라시보 β → ρ 는 모두 상한 1 · 크기 × β 짝 비율 = 크기 × 노출 짝 비율(같은 분포)",
    isTRUE(rH1$card$controls$beta_match$rho_median == 1) && isTRUE(a$share_beats_size_beta == a$share_beats_size_exposure),
    sprintf("(ρ중앙=%s · se=%s · sb=%s)", sh(rH1$card$controls$beta_match$rho_median), sh(a$share_beats_size_exposure), sh(a$share_beats_size_beta)))
cat("\n=== H2 · P3 · N2. 현금 혼합(평균 노출 0.7) — 노출 배율과 β 배율이 한 번씩만 곱해진다(판단 T4 C-20261113-076) ===\n")
rH2 <- run(mkH(function(d) ew(B13, 0.7)))
chk("H2 고β · 노출 0.7 → ρ 는 모두 1 · 크기 × β 플라시보의 위기 분위 = 크기 × 노출 플라시보의 위기 분위(같은 배율 Ē 한 번)",
    isTRUE(abs(rH2$ctl$exposure$mean - 0.7) < 1e-12) && isTRUE(rH2$card$controls$beta_match$rho_median == 1) &&
      isTRUE(all.equal(rH2$card$controls$placebo$per_crisis_size_beta$placebo_q, rH2$card$controls$placebo$per_crisis$placebo_q)),
    sprintf("(Ē=%.2f · ρ중앙=%s)", rH2$ctl$exposure$mean, sh(rH2$card$controls$beta_match$rho_median)))
rP3 <- run(mkH(function(d) ew(QUAL, 0.7))); rN2 <- run(mkH(function(d) ew(LOWB, 0.7)))
chk("P3 비대칭 종목 · 노출 0.7 → 크기 × β 짝도 넘는다 → 선택(강함)", identical(nb(mc8_of(rP3), "size_beta"), "selection") &&
      identical(gv3_cr_for_notch("strong", mc8_of(rP3), gcfg), "strong"), sprintf("(sb=%s)", sh(att(rP3)$share_beats_size_beta)))
chk("N2 저β 대칭 · 노출 0.7 → 구 짝은 선택 · 크기 × β 짝은 못 넘음 → beta_not_separated(보통)",
    identical(att(rN2)$label, "selection_defense") && identical(nb(mc8_of(rN2), "size_beta"), "beta_not_separated") &&
      identical(gv3_cr_for_notch("strong", mc8_of(rN2), gcfg), "normal"),
    sprintf("(se=%s · sb=%s)", sh(att(rN2)$share_beats_size_exposure), sh(att(rN2)$share_beats_size_beta)))
chk("H1b 구 라벨이 선택 방어가 아니면 label_size_beta 는 그 라벨 그대로", !identical(a$label, "selection_defense") && identical(a$label_size_beta, a$label),
    sprintf("(label=%s)", a$label))

cat("\n=== I. 통합 경로 — 등급 계약 .gv3_mc8(프로세스 RAWDATA) = 메모리판 ===\n")
assign("RAWDATA", RAW, envir = globalenv())
gx <- .gv3_mc8(list(H = rN1$H, pr = rN1$S, br = rN1$B, spec = list(exec_price = "close_t1", universe = "K200_KQ150")),
               bc_card(rN1$S, rN1$B, cfg = bcfg), list(bc_cfg = bcfg), ROOT, .gv3_deps(ROOT))
chk("I1 등급 계약 추출 = 메모리판(라벨 · β 짝 비율 · 레그 β) · 원천 = 프로세스 RAWDATA",
    identical(gx$label, att(rN1)$label) && identical(gx$label_size_beta, att(rN1)$label_size_beta) &&
      isTRUE(all.equal(gx$share_beats_size_beta, att(rN1)$share_beats_size_beta)) && identical(gx$raw_source, "process_RAWDATA") &&
      isTRUE(all.equal(gx$beta_leg, rN1$card$controls$beta_match$beta_leg)), sprintf("(gx label=%s · sb=%s)", gx$label_size_beta, sh(gx$share_beats_size_beta)))
chk("I2 통합 경로로도 v3.5 노치 = 보통(beta_not_separated)", identical(gv3_cr_for_notch("strong", gx, gcfg), "normal") &&
      identical(nb(gx, "size_beta"), "beta_not_separated"))
rm("RAWDATA", envir = globalenv())

cat("\n=== E. 카드 안 라벨 하나 — 보고용 기댓값 계열은 판정이 아니다(철학 C-20261113-064) ===\n")
chk("E1 크기 × β 결정론 사본(보고용)의 대조 라벨 = report_only_expected_value · 판정 라벨은 attribution 의 label_size_beta 하나",
    identical(rN1$card$controls$size_beta_matched$label, "report_only_expected_value") &&
      identical(rT1$card$controls$size_beta_path$label, "report_only_expected_value") &&
      identical(att(rN1)$label_size_beta, "size_beta_unseparated"),
    sprintf("(N1 사본 라벨=%s · T1 경로 사본=%s)", rN1$card$controls$size_beta_matched$label %||% "NULL", rT1$card$controls$size_beta_path$label %||% "NULL"))

cat("\n=== R. 기록 — 보유 회전 β 타이밍(알려진 빈틈 · 판정 아님 · 철학 C-20261113-063 · 헌장 빈칸 상신) ===\n")
## v3.5 가 닫는 것 = 정적 β 축소로 산 가점. 노출 1 고정에서 보유를 위기 달에 저β 로 돌리는 전략은 노출 경로가 고정이라
##   노출 고정 분기를 지나 'selection' 이 된다(같은 β 낮춤을 현금으로 하면 타이밍 → 증거 필요). 규칙화는 도훈 결정 뒤 새 판.
B10 <- SM[TYP[SM] == "B10"]
rot <- function(lag) mkH(function(d) { k <- match(d, EX); kk <- k - lag; ew(if (kk >= 1L && tm[kk]) LOWB else B10) })
for (lg_ in c(0L, 1L)) { rr <- run(rot(lg_)); a_ <- att(rr)
  cat(sprintf("  [기록] 보유 회전(평상 β 1.0 → 위기 달 β 0.4 · 노출 1 · 신호 지연 %d달): 구 라벨 %s · 크기 × β 짝 %s · v3.5 근거 %s → %s\n",
              lg_, a_$label, sh(a_$share_beats_size_beta), nb(mc8_of(rr), "size_beta"), gv3_cr_for_notch("strong", mc8_of(rr), gcfg))) }

cat("\n=== F. fail-closed · 설정 ===\n")
mcfg0 <- mcfg; mcfg0$size_beta <- NULL
r0 <- run(mkH(function(d) ew(LOWB)), mc = mcfg0)
chk("F1 size_beta 블록 없는 설정(구 사본) → β 블록 not_configured · 비율 NA · v3.5 노치 = beta_unresolved(보통)",
    identical(r0$card$controls$beta_match$status, "not_configured") && is.na(att(r0)$share_beats_size_beta) &&
      identical(att(r0)$label_size_beta, "size_beta_unmeasured") && identical(gv3_cr_for_notch("strong", mc8_of(r0), gcfg), "normal") &&
      identical(nb(mc8_of(r0), "size_beta"), "beta_unresolved"))
chk("F2 구 라벨 블록은 β 블록과 무관하게 같다(label · 크기 × 노출 비율 identical)", identical(att(r0)$label, att(rN1)$label) &&
      identical(att(r0)$share_beats_size_exposure, att(rN1)$share_beats_size_exposure))
chk("F3 라벨 문자열만(구 호출) → v3.5 는 β 를 확인할 수 없어 보통 · 구 의미 v3.1 형식은 강함 그대로",
    identical(gv3_cr_for_notch("strong", "selection_defense", gcfg), "normal") &&
      { c1 <- cfg_old; c1$cr_notch$strong_requires <- "mc8_selection_defense"; identical(gv3_cr_for_notch("strong", "selection_defense", c1), "strong") } &&
      { c2 <- gcfg; c2$cr_notch$strong_requires <- "mc8_selection_defense"
        identical(gv3_cr_for_notch("strong", mc8_of(rN1), c2), "normal") && identical(gv3_cr_for_notch("strong", mc8_of(rP1), c2), "strong") })
chk("F4 강함이 아니면 β 짝과 무관(약함 · 보통 · 판정 불가 그대로)", identical(gv3_cr_for_notch("weak", mc8_of(rN1), gcfg), "weak") &&
      identical(gv3_cr_for_notch("normal", mc8_of(rP1), gcfg), "normal") && identical(gv3_cr_for_notch("insufficient", mc8_of(rP1), gcfg), "insufficient"))
gj <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
bad_g <- function(mut) { x <- mut(gj); p <- tempfile(fileext = ".json"); writeLines(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA), p); throws(gv3_cfg(ROOT, path = p)) }
chk("F5 [위반 주입] selection_control 어휘 밖(size_only) → gv3_cfg 가 멈춘다", bad_g(function(x) { x$cr_notch$selection_control <- "size_only"; x }))
chk("F8 [위반 주입] 판 v3.5 인데 selection_control 이 빠지거나 size_exposure 면 gv3_cfg 가 멈춘다(구 의미로 조용히 돌아가지 않는다 · T4 C-077) · 정본은 통과",
    bad_g(function(x) { x$cr_notch$selection_control <- NULL; x }) && bad_g(function(x) { x$cr_notch$selection_control <- "size_exposure"; x }) &&
      !bad_g(function(x) x) && !bad_g(function(x) { x$rules_version <- "v3.4"; x$cr_notch$selection_control <- NULL; x }))
mj <- fromJSON(file.path(ROOT, "06_Registry/matched_controls.json"))
bad_m <- function(mut) { x <- mut(mj); p <- tempfile(fileext = ".json"); writeLines(toJSON(x, auto_unbox = TRUE), p); throws(mc_cfg(path = p)) }
chk("F6 [위반 주입] size_beta.cap = 1.5(차입 사본) · rule 어휘 밖 · β 추정기 어휘 밖 → mc_cfg 가 멈춘다",
    bad_m(function(x) { x$size_beta$cap <- 1.5; x }) && bad_m(function(x) { x$size_beta$rule <- "size_beta_mean"; x }) &&
      bad_m(function(x) { x$size_beta$beta_estimator <- "daily_ols"; x }))
chk("F7 정본 설정은 통과하고 근거 문장이 있다", is.list(mc_cfg(ROOT)$size_beta) && nzchar(mj$size_beta_source %||% "") &&
      grepl("GRADE-CR-NOTCH-BETA-SELECTION-20261113", gj$cr_notch_source, fixed = TRUE))

cat("\n=== M. 돌연변이(소스 텍스트 치환 사본 — 치환 성사를 먼저 단정) ===\n")
mut_env <- function(file, from, to, deps = NULL) {
  src <- readLines(file.path(ROOT, file), encoding = "UTF-8", warn = FALSE)
  hit <- grepl(from, src, fixed = TRUE)
  if (sum(hit) != 1L) return(list(applied = FALSE, n = sum(hit)))
  src[hit] <- gsub(from, to, src[hit], fixed = TRUE)
  p <- file.path(TD, paste0("mut_", basename(file))); writeLines(src, p, useBytes = TRUE)
  en <- new.env(parent = globalenv())
  for (d in deps) sys.source(file.path(ROOT, d), envir = en, keep.source = FALSE)
  sys.source(p, envir = en, keep.source = FALSE)
  list(applied = TRUE, env = en)
}
M1 <- mut_env("02_Infrastructure/contracts/matched_controls.R", "if (!is.null(col_scale)) Mx <- sweep(Mx, 2L, col_scale[cols], `*`)",
              "if (FALSE) Mx <- sweep(Mx, 2L, col_scale[cols], `*`)", deps = "02_Infrastructure/contracts/behavior_card.R")
if (isTRUE(M1$applied)) { rM1 <- run(mkH(function(d) ew(LOWB)), env = M1$env)
  chk("M1 [돌연변이] 플라시보에 ρ 를 곱하지 않으면 저β 가 크기 × β 짝을 넘어 강함이 된다 — N1b · N1c 가 잡는다",
      identical(att(rM1)$label_size_beta, "selection_defense") && identical(gv3_cr_for_notch("strong", mc8_of(rM1), gcfg), "strong") &&
        identical(att(rN1)$label_size_beta, "size_beta_unseparated"), sprintf("(돌연변이 sb=%s)", sh(att(rM1)$share_beats_size_beta)))
} else chk("M1 치환 대상 문장 1개", FALSE, sprintf("(n=%s)", M1$n))
M2 <- mut_env("02_Infrastructure/contracts/grade_v3.R", "if (!(sb > maj)) return(\"beta_not_separated\")", "if (FALSE) return(\"beta_not_separated\")")
chk("M2 [돌연변이] 노치 근거에서 크기 × β 조건을 빼면 N1 이 selection(강함) — N1c 가 잡는다",
    isTRUE(M2$applied) && identical(M2$env$gv3_cr_for_notch("strong", mc8_of(rN1), gcfg), "strong") &&
      identical(gv3_cr_for_notch("strong", mc8_of(rN1), gcfg), "normal"), sprintf("(치환 %s)", isTRUE(M2$applied)))
M3 <- mut_env("02_Infrastructure/contracts/matched_controls.R", "pmin(b_leg / b_j, out$cap)", "(b_leg / b_j)",
              deps = "02_Infrastructure/contracts/behavior_card.R")
if (isTRUE(M3$applied)) { rM3 <- run(mkH(function(d) ew(B13)), env = M3$env)
  chk("M3 [돌연변이] 상한 1 을 지우면 고β 전략의 짝이 차입 사본(ρ > 1)이 된다 — H1a(ρ = 1)가 잡는다",
      isTRUE(rM3$card$controls$beta_match$rho_median > 1) && isTRUE(rH1$card$controls$beta_match$rho_median == 1),
      sprintf("(돌연변이 ρ중앙=%s · se=%s · sb=%s)", sh(rM3$card$controls$beta_match$rho_median), sh(att(rM3)$share_beats_size_exposure),
              sh(att(rM3)$share_beats_size_beta)))
} else chk("M3 치환 대상 문장 1개", FALSE, sprintf("(n=%s)", M3$n))
M4 <- mut_env("02_Infrastructure/contracts/grade_v3.R", "if (sp > maj && spb > maj) return(\"selection\")", "if (sp > maj) return(\"selection\")")
chk("M4 [돌연변이] 경로판 크기 × β 조건을 빼면 T1(저β 타이밍)이 selection(강함) — T1c 가 잡는다",
    isTRUE(M4$applied) && identical(M4$env$gv3_cr_for_notch("strong", mc8_of(rT1), gcfg), "strong") &&
      identical(gv3_cr_for_notch("strong", mc8_of(rT1), gcfg), "normal"), sprintf("(치환 %s)", isTRUE(M4$applied)))
## 과반 경계(판단 T4 C-20261113-076) — 크기 × β 짝 비율이 정확히 과반이면 '넘음'이 아니다(MC8 라벨 규칙과 같은 초과 비교)
mB <- mc8_of(rN1); mB$share_beats_size_beta <- MAJ
chk("Z2 경계 — 크기 × β 짝 비율 = 과반(majority_share) 이면 beta_not_separated(초과만 넘음)", identical(nb(mB, "size_beta"), "beta_not_separated"))
M5 <- mut_env("02_Infrastructure/contracts/grade_v3.R", "if (!(sb > maj)) return(\"beta_not_separated\")", "if (!(sb >= maj)) return(\"beta_not_separated\")")
chk("M5 [돌연변이] 과반 비교를 '≥' 로 느슨하게 하면 경계 기록이 selection — Z2 가 잡는다",
    isTRUE(M5$applied) && identical(M5$env$gv3_notch_basis(mB, NULL, "lt", "size_beta"), "selection"), sprintf("(치환 %s)", isTRUE(M5$applied)))
M6 <- mut_env("02_Infrastructure/contracts/matched_controls.R",
              "pstb <- if (sbok) .mc_placebo_crises(CR, pl, rep(ctl$exposure$mean, length(pl$date))",
              "pstb <- if (sbok) .mc_placebo_crises(CR, pl, rep(ctl$exposure$mean^2, length(pl$date))", deps = "02_Infrastructure/contracts/behavior_card.R")
if (isTRUE(M6$applied)) { rM6 <- run(mkH(function(d) ew(B13, 0.7)), env = M6$env)
  chk("M6 [돌연변이] 정적 크기 × β 플라시보에 노출을 두 번 곱하면(Ē² · 노출 0.7) 위기 분위가 크기 × 노출 플라시보와 갈린다 — H2 가 잡는다",
      !isTRUE(all.equal(rM6$card$controls$placebo$per_crisis_size_beta$placebo_q, rM6$card$controls$placebo$per_crisis$placebo_q)))
} else chk("M6 치환 대상 문장 1개", FALSE, sprintf("(n=%s)", M6$n))

cat("\n=== Z. 단조성 — 같은 입력이면 v3.5 등급 ≤ v3.4 등급(v3.5 는 강함을 보통으로만 바꾼다) ===\n")
rank_g <- c(F = 0L, C = 1L, B = 2L, A = 3L)
viol <- 0L; n_case <- 0L; n_down <- 0L
for (S in c(0, 0.3, 0.6, 0.9, 1.2)) for (fl_ok in c(TRUE, FALSE)) for (oos_ok in c(TRUE, FALSE)) for (gt in c(TRUE, FALSE))
  for (fe in c(TRUE, FALSE)) for (tm_ in c(1.0, 2.5, 3.5)) {
    fl <- c(port_t = TRUE, calmar = fl_ok, cagr = TRUE, sharpe = TRUE); op <- c(a = oos_ok, b = TRUE)
    fa <- list(eligible = fe, t_min = tm_, th_b = 2.0, th_a = 2.95); gates <- c(g = gt)
    old <- gv3_decide(S, 0.45, fl, op, "strong", gcfg, gates = gates, fa = fa)$grade
    new <- gv3_decide(S, 0.45, fl, op, "normal", gcfg, gates = gates, fa = fa)$grade
    n_case <- n_case + 1L
    if (!is.na(old) && !is.na(new)) { if (rank_g[[new]] > rank_g[[old]]) viol <- viol + 1L; if (rank_g[[new]] < rank_g[[old]]) n_down <- n_down + 1L }
  }
chk("Z1 노치 경우 전수(S 띠 5 × 하한 × OOS × 관문 × 팩터 알파 자격 × t 3) — 등급이 오르는 경우 0", viol == 0L && n_down > 0L,
    sprintf("(경우 %d · 내림 %d · 오름 %d)", n_case, n_down, viol))

unlink(TD, recursive = TRUE)
cat(sprintf("\n== cr_notch_size_beta: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"cr_notch_size_beta","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
