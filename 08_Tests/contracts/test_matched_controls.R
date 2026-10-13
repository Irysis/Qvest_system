## test_matched_controls.R — MC8 크기 짝 · 노출 짝 무신호 대조 계약 검사기 (양방향: 양성 대조 + 위반 주입 + 돌연변이)
## 규약: "경고 0" 만으로는 검사기가 살아있는지 알 수 없다 — 일부러 틀린 입력을 넣어 발화를 확인한다.
## 대상: 02_Infrastructure/contracts/matched_controls.R (v10.01 · 2026-10-13) · 소비자 programs/program_report.R
##
## 합성 세계(결정론 · 100종목 · 2003~2012 평일): 초대형 10종(시가총액 1000) + 중소형 90종(90..1).
##   평상시 전 종목 +0.04%/일. 위기 4번(3개월) — 초대형 −50% · 중소형 −10% · '방어 종목'(분위마다 6번째) −2%,
##   다음 60일 회복으로 비율이 제자리. 벤치 = 시가총액 가중(초대형 비중 ≈ 71%) → 위기마다 ≈ −38%.
##   τ_D = 2008-12-31 로 두어 위기 2번은 보는 창 · 2번은 시험 창이다.
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
setwd(ROOT)
source("02_Infrastructure/contracts/behavior_card.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/programs/program_report.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}

bcfg <- bc_cfg(ROOT)
bcfg$period_start <- "2000-01-01"; bcfg$tau_d <- "2008-12-31"; bcfg$dc_derive_window <- c("2003-01", "2012-12")
mcfg <- mc_cfg(ROOT)

## ── 합성 세계 ──
days <- seq(as.Date("2003-01-01"), as.Date("2012-12-31"), by = "day")
days <- days[!(as.POSIXlt(days)$wday %in% c(0L, 6L))]
TK <- sprintf("T%03d", 1:100); MEGA <- TK[1:10]
PICK <- sprintf("T%03d", c(16, 26, 36, 46, 56, 66, 76, 86, 96))
size0 <- setNames(c(rep(1000, 10), 90:1), TK)
CRISES <- list(c("2004-03-01", "2004-05-31"), c("2006-06-01", "2006-08-31"),
               c("2009-06-01", "2009-08-31"), c("2011-06-01", "2011-08-31"))
in_cr <- rep(FALSE, length(days)); in_rec <- rep(FALSE, length(days)); n_cr <- integer(length(days)); n_rec <- integer(length(days))
for (c0 in CRISES) {
  ix <- which(days >= as.Date(c0[1]) & days <= as.Date(c0[2])); in_cr[ix] <- TRUE; n_cr[ix] <- length(ix)
  rx <- (max(ix) + 1L):(max(ix) + 60L); in_rec[rx] <- TRUE; n_rec[rx] <- 60L
}
grp <- ifelse(TK %in% MEGA, "mega", ifelse(TK %in% PICK, "pick", "small"))
drop <- c(mega = 0.5, pick = 0.98, small = 0.9)
RM <- sapply(seq_along(TK), function(i) {
  g <- drop[[grp[i]]]
  ifelse(in_cr, g^(1 / pmax(n_cr, 1L)) - 1, ifelse(in_rec, (1 / g)^(1 / pmax(n_rec, 1L)) - 1, 0.0004))
})
colnames(RM) <- TK
SZM <- sweep(apply(1 + RM, 2, cumprod), 2, size0, `*`)              # 그날 종가 시가총액
SZL <- rbind(size0, SZM[-nrow(SZM), ])                              # 전날 시가총액(벤치 가중)
BMv <- rowSums(SZL * RM) / rowSums(SZL)
RAW <- data.table(Date = rep(days, times = length(TK)), Ticker = rep(TK, each = length(days)),
                  K200 = 1, KQ150 = 0, Size = as.vector(SZM), Ret = as.vector(RM), TradingHalt = 0)
setkey(RAW, Ticker, Date)
BM_ALL <- data.table(date = days, benchmark_ret = BMv)
EX <- days[!duplicated(format(days, "%Y-%m"))]; EX <- EX[EX >= as.Date("2003-02-01")]   # 매월 첫 평일 = 집행일
szat <- function(d) SZM[match(d, days), ]

# 독립 엔진(집행 하네스와 같은 관례 — 창 (e_k, e_k+1] 매수후보유 · PerformanceAnalytics::Return.portfolio · 레그 × GL)
eng <- function(H) {
  e <- sort(unique(H$date)); out <- vector("list", length(e))
  for (k in seq_along(e)) {
    hi <- if (k < length(e)) e[k + 1L] else max(days)
    dd <- days[days > e[k] & days <= hi]
    if (!length(dd)) next
    h <- H[date == e[k]]; GL <- sum(h$target_weight)
    rx <- xts::xts(RM[match(dd, days), h$ticker, drop = FALSE], order.by = dd)
    pr <- suppressWarnings(PerformanceAnalytics::Return.portfolio(rx, weights = setNames(h$target_weight / GL, h$ticker),
                                                                  rebalance_on = NA))
    out[[k]] <- data.table(date = as.Date(zoo::index(pr)), ret_net = GL * as.numeric(pr[, 1]))
  }
  rbindlist(out)
}
mkH <- function(f) rbindlist(lapply(EX, function(d) { w <- f(d); data.table(date = d, ticker = names(w), target_weight = unname(w)) }))
run <- function(H) {
  S <- eng(H); B <- BM_ALL[date %in% S$date]
  card <- bc_card(S, B, cfg = bcfg)
  ctl <- mc_controls(H, S, B, RAW, mcfg, "close_t1", "K200_KQ150")
  list(S = S, B = B, ctl = ctl, card = mc_attribution(card, ctl, B, bcfg))
}
att <- function(r, w = "overall") r$card$controls$attribution[[w]]

cat("=== 0. 합성 세계 점검 ===\n")
crs <- bc_crises(BM_ALL[, .(date, r = benchmark_ret)], bcfg$crisis_depth)
chk("벤치 위기 4번(깊이 ≈ 38%)", nrow(crs) == 4L && all(abs(crs$depth - 0.3815) < 0.01),
    sprintf("(n=%d · depth=%s)", nrow(crs), paste(round(crs$depth, 3), collapse = ",")))

cat("\n=== A. 양성 대조 — 전략 = 크기 바스켓 그 자체(중소형 90종 동일가중 · 무선택) ===\n")
rB <- run(mkH(function(d) setNames(rep(1 / 90, 90), TK[11:100])))
J <- merge(rB$S, rB$ctl$series$size_matched, by = "date")
chk("A1 크기 단독 대조 수익 = 전략 수익(독립 엔진 · 최대 차 < 1e-12)", nrow(J) == nrow(rB$S) && max(abs(J$ret_net - J$ret)) < 1e-12,
    sprintf("(n=%d/%d · maxdiff=%.2e)", nrow(J), nrow(rB$S), max(abs(J$ret_net - J$ret))))
chk("A2 평균 노출 = 1 · 경로 불변 → 경로 진단 대조 없음", isTRUE(abs(rB$ctl$exposure$mean - 1) < 1e-12) &&
      !isTRUE(rB$ctl$exposure$varies) && is.null(rB$ctl$series$size_exposure_path))
chk("A3 바스켓 진단 — 모든 리밸 ok · 미배정 비중 0", rB$ctl$diag$n_rebalances_ok == length(EX) && rB$ctl$diag$unmapped_share_max == 0)

cat("\n=== B. 크기 방어 착시 — 중소형 무선택 보유는 시장보다 덜 빠지지만 실력이 아니다 ===\n")
chk("B1 행동 카드는 위기 방어로 본다(하락 포착 중앙 < 0.5)", isTRUE(rB$card$overall$crisis_dd_capture_median < 0.5),
    sprintf("(%.3f)", rB$card$overall$crisis_dd_capture_median %||% NA))
chk("B2 귀속 = size_defense(크기+노출 짝을 못 넘음 · 노출 짝은 넘음)", identical(att(rB)$label, "size_defense"),
    sprintf("(label=%s · se=%.2f · ex=%.2f)", att(rB)$label, att(rB)$share_beats_size_exposure, att(rB)$share_beats_exposure))
chk("B3 [돌연변이] 노출 짝만 쓰면 같은 전략이 'selection_defense' — 크기 짝이 없으면 착시가 실력으로 둔갑한다",
    identical(rB$card$controls$exposure_matched$label, "selection_defense"))
chk("B4 창별 귀속 — 보는 창 2번 · 시험 창 2번 모두 size_defense",
    identical(att(rB, "visible")$label, "size_defense") && identical(att(rB, "test")$label, "size_defense") &&
      att(rB, "visible")$n_crisis == 2L && att(rB, "test")$n_crisis == 2L,
    sprintf("(visible=%s/%d · test=%s/%d)", att(rB, "visible")$label, att(rB, "visible")$n_crisis,
            att(rB, "test")$label, att(rB, "test")$n_crisis))

cat("\n=== C. 선택 방어 — 분위 안에서 덜 빠지는 종목을 골랐다 ===\n")
rC <- run(mkH(function(d) setNames(rep(1 / 9, 9), PICK)))
chk("C1 귀속 = selection_defense", identical(att(rC)$label, "selection_defense"),
    sprintf("(label=%s · se=%.2f)", att(rC)$label, att(rC)$share_beats_size_exposure))
chk("C2 크기+노출 짝과의 하락 포착 차(중앙) > 0", isTRUE(att(rC)$median_gap_size_exposure > 0),
    sprintf("(gap=%.3f)", att(rC)$median_gap_size_exposure %||% NA))

cat("\n=== D. 노출 방어 — 같은 평균 노출의 시장보다 낫지 않다 ===\n")
rD1 <- run(mkH(function(d) setNames(rep(0.05, 10), MEGA)))           # 초대형만 · Σw = 0.5
chk("D1 초대형 절반 노출 → exposure_defense", identical(att(rD1)$label, "exposure_defense"),
    sprintf("(label=%s)", att(rD1)$label))
rD2 <- run(mkH(function(d) { s <- szat(d); 0.5 * s / sum(s) }))     # 전 종목 시가총액 가중 · Σw = 0.5 = 벤치 × 0.5
J2 <- merge(rD2$S, rD2$ctl$series$exposure_matched, by = "date")
chk("D2 [양성 대조] 노출 짝 대조 = 벤치 × 0.5 = 전략(최대 차 < 1e-12)", isTRUE(abs(rD2$ctl$exposure$mean - 0.5) < 1e-12) &&
      max(abs(J2$ret_net - J2$ret)) < 1e-12, sprintf("(Ē=%.6f · maxdiff=%.2e)", rD2$ctl$exposure$mean, max(abs(J2$ret_net - J2$ret))))
# 시가총액 가중은 리밸 사이 이긴 종목 비중을 그대로 들고 간다(표류) — 플라시보는 리밸마다 재배정한다.
#   이 세계는 분위 안 수익이 같아 플라시보 분산이 작으므로 위기 일부에서 꼬리에 들 수 있다(실측 4번 중 1번). 라벨은 과반으로만 낸다.
chk("D3 전략 = 노출 짝이면 노출 방어 — 시가총액 가중 표류는 과반 위기에서 플라시보를 넘지 못한다",
    isTRUE(att(rD2)$share_beats_exposure == 0) && isTRUE(att(rD2)$share_beats_size_exposure <= bcfg$majority_share) &&
      identical(att(rD2)$label, "exposure_defense"),
    sprintf("(ex=%.2f · se=%.2f · label=%s)", att(rD2)$share_beats_exposure, att(rD2)$share_beats_size_exposure, att(rD2)$label))

cat("\n=== E. 노출 타이밍 — 기전 방어로 세되 순수 선택과 구분한다 ===\n")
tm <- vapply(seq_along(EX), function(k) { hi <- if (k < length(EX)) EX[k + 1L] else max(days)
                                          any(in_cr[days > EX[k] & days <= hi]) }, logical(1))
GLk <- setNames(ifelse(tm, 0.2, 1), as.character(EX))
rE <- run(mkH(function(d) setNames(rep(GLk[[as.character(d)]] / 100, 100), TK)))
chk("E1 노출 경로가 변한다 → 경로 진단 대조 생성", isTRUE(rE$ctl$exposure$varies) && !is.null(rE$ctl$series$size_exposure_path))
chk("E2 귀속 = selection_defense(정적 평균 노출보다 덜 빠짐 = 기전 방어)", identical(att(rE)$label, "selection_defense"),
    sprintf("(label=%s)", att(rE)$label))
chk("E3 경로 진단 — 타이밍을 고정하면 넘은 위기 0(선택이 아니라 타이밍)", isTRUE(att(rE)$share_beats_size_exposure_path == 0),
    sprintf("(path=%.2f)", att(rE)$share_beats_size_exposure_path %||% NA))
nd <- vapply(seq_along(EX), function(k) { hi <- if (k < length(EX)) EX[k + 1L] else max(days)
                                          sum(days > EX[k] & days <= hi) }, integer(1))
chk("E4 평균 노출 = 보유 일수 가중 평균(손계산 대조)", isTRUE(abs(rE$ctl$exposure$mean - sum(GLk * nd) / sum(nd)) < 1e-12),
    sprintf("(%.6f vs %.6f)", rE$ctl$exposure$mean, sum(GLk * nd) / sum(nd)))

cat("\n=== P. 판정은 평균이 아니라 분위 — 분위 안 '운 좋은 한 종목'은 선택이 아니다 ===\n")
# 분위마다 1종(9종) 중 방어 종목은 1종뿐 — 무작위로 골라도 흔한 구성(Binomial(9, 0.1) 에서 1 이상 = 61%)
LUCKY <- c("T016", sprintf("T%03d", seq(21, 91, by = 10)))
rP <- run(mkH(function(d) setNames(rep(1 / 9, 9), LUCKY)))
chk("P1 [돌연변이] 기댓값(분위 바스켓)과 견주면 같은 전략이 'selection_defense' — 평균 비교는 운을 실력으로 센다",
    identical(rP$card$controls$size_exposure_matched$label, "selection_defense"),
    sprintf("(label=%s · share=%.2f)", rP$card$controls$size_exposure_matched$label %||% NA,
            rP$card$controls$size_exposure_matched$share_beats %||% NA))
chk("P2 플라시보 분위 판정은 선택이 아니다(size_defense)", identical(att(rP)$label, "size_defense"),
    sprintf("(label=%s · se=%.2f · p중앙=%.3f)", att(rP)$label, att(rP)$share_beats_size_exposure, att(rP)$median_placebo_p))
chk("P3 위기별 플라시보 p 중앙 > alpha", isTRUE(att(rP)$median_placebo_p > mcfg$placebo_alpha),
    sprintf("(p=%.3f)", att(rP)$median_placebo_p %||% NA))
chk("P4 진짜 선택(C)은 플라시보 p 중앙 ≤ 1/(n+1) 수준(무작위 200개가 한 번도 못 따라옴)",
    isTRUE(att(rC)$median_placebo_p <= 1 / (mcfg$placebo_n + 1) + 1e-12), sprintf("(p=%.4f)", att(rC)$median_placebo_p %||% NA))
cP2 <- mc_controls(mkH(function(d) setNames(rep(1 / 9, 9), LUCKY)), rP$S, rP$B, RAW, mcfg, "close_t1", "K200_KQ150")
chk("P5 재현성 — 같은 설정 · 같은 입력이면 플라시보 경로가 같다", identical(cP2$placebo$P, rP$ctl$placebo$P))
set.seed(7); x1 <- runif(1); set.seed(7)
invisible(mc_controls(mkH(function(d) setNames(rep(1 / 9, 9), LUCKY)), rP$S, rP$B, RAW, mcfg, "close_t1", "K200_KQ150"))
chk("P6 호출자의 난수 흐름을 바꾸지 않는다", identical(runif(1), x1))
pm <- rowMeans(rP$ctl$placebo$P); bk <- rP$ctl$series$size_matched$ret[match(rP$ctl$placebo$date, rP$ctl$series$size_matched$date)]
chk("P7 플라시보 평균 ≈ 분위 바스켓(기댓값) · 차원 = 수익일 × n — 분위 몫을 지킨 무작위 추출",
    nrow(rP$ctl$placebo$P) == nrow(rP$S) && ncol(rP$ctl$placebo$P) == mcfg$placebo_n && max(abs(pm - bk)) < 1e-4,
    sprintf("(dim=%dx%d · maxdiff=%.2e)", nrow(rP$ctl$placebo$P), ncol(rP$ctl$placebo$P), max(abs(pm - bk))))

cat("\n=== F. PIT — 크기는 집행일 전 거래일 값만 ===\n")
eF <- as.Date("2005-06-01"); aF <- max(days[days < eF])
HF <- data.table(date = eF, ticker = "T055", target_weight = 1)
R1 <- copy(RAW); R1[Ticker == "T055" & Date == eF, Size := 1e6]     # 위반 주입: 집행일 당일(미래) 시가총액 급변
m1 <- mc_size_basket(HF, R1, mcfg, "K200_KQ150")$members
chk("F1 집행일 당일 시가총액 급변은 분위를 못 바꾼다(as-of 분위 = 중형 · 초대형 0)",
    nrow(m1) == 10L && !any(m1$Ticker %in% MEGA) && "T055" %in% m1$Ticker, sprintf("(n=%d · mega=%d)", nrow(m1), sum(m1$Ticker %in% MEGA)))
R2 <- copy(RAW); R2[Ticker == "T055" & Date == aF, Size := 1e6]     # 돌연변이: 같은 급변을 하루 앞(as-of)으로
m2 <- mc_size_basket(HF, R2, mcfg, "K200_KQ150")$members
chk("F2 [돌연변이] 같은 급변이 as-of 날이면 최상위 분위로 간다 — 검사가 as-of 날을 실제로 읽는다",
    any(m2$Ticker %in% MEGA), sprintf("(mega=%d)", sum(m2$Ticker %in% MEGA)))
A0 <- mc_size_basket(mkH(function(d) setNames(1, "T050")), RAW, mcfg, "K200_KQ150")$asof
prevd <- vapply(A0$exec_date, function(x) as.numeric(max(days[days < x])), numeric(1))
chk("F3 모든 리밸의 as-of = 집행일 전 거래일(< 집행일)", all(A0$asof < A0$exec_date) && all(as.numeric(A0$asof) == prevd))
R3 <- copy(RAW); R3[Ticker == "T055" & Date == aF, TradingHalt := 1]
m3 <- mc_size_basket(data.table(date = eF, ticker = "T051", target_weight = 1), R3, mcfg, "K200_KQ150")$members
chk("F4 as-of 거래정지 종목은 바스켓에서 빠진다", !("T055" %in% m3$Ticker) && nrow(m3) >= 9L)
R4 <- copy(RAW); R4[Date == aF & Ticker %in% TK[51:100], K200 := 0]
m4 <- mc_size_basket(data.table(date = eF, ticker = "T070", target_weight = 1), R4, mcfg, "K200_KQ150")
chk("F5 비멤버 보유도 그날 시가총액으로 분위에 놓이고 바스켓은 멤버만 든다",
    nrow(m4$members) > 0L && all(m4$members$Ticker %in% TK[1:50]) && m4$diag$unmapped_share == 0)

cat("\n=== G. 롱숏 · 빈 입력은 닫힌다(침묵 통과 아님) ===\n")
HLS <- data.table(date = EX, ticker = "T001", target_weight = 0.5)
HLS <- rbind(HLS, data.table(date = EX, ticker = "T090", target_weight = -0.5))
cLS <- mc_controls(HLS, rB$S, rB$B, RAW, mcfg, "close_t1", "K200_KQ150")
chk("G1 음수 비중 → not_applicable_long_short", identical(cLS$status, "not_applicable_long_short"))
kLS <- mc_attribution(rB$card, cLS, rB$B, bcfg)
chk("G2 카드에도 상태가 실린다", identical(kLS$controls$status, "not_applicable_long_short"))
chk("G3 보고 줄은 사람 말(내부 코드 비노출)", grepl("롱숏 전략이라 대조 정의 밖", .prep_controls_line(kLS$controls, "overall")) &&
      !grepl("not_applicable", .prep_controls_line(kLS$controls, "overall")))
chk("G4 보유 기록이 비면 no_holdings", identical(mc_controls(HLS[0], rB$S, rB$B, RAW, mcfg, "close_t1", "K200_KQ150")$status, "no_holdings"))

cat("\n=== H. 설정 실패는 닫힌다 ===\n")
cj <- fromJSON(file.path(ROOT, "06_Registry/matched_controls.json"))
bad <- function(mut) { x <- cj; x <- mut(x); p <- tempfile(fileext = ".json"); writeLines(toJSON(x, auto_unbox = TRUE), p)
                       inherits(tryCatch(mc_cfg(path = p), error = function(e) e), "error") }
chk("H1 필수 키 누락 → 오류", bad(function(x) { x$size_buckets <- NULL; x }))
chk("H2 어휘 밖(within_bucket_weight = value) → 오류", bad(function(x) { x$within_bucket_weight <- "value"; x }))
chk("H3 size_buckets = 1 → 오류", bad(function(x) { x$size_buckets <- 1; x }))
chk("H4 size_buckets = 2.5 → 오류", bad(function(x) { x$size_buckets <- 2.5; x }))
chk("H5 정본 설정은 통과 · 분위 수는 출처 문장과 함께 있다", identical(mcfg$size_buckets, 10L) && nzchar(cj$size_buckets_source %||% ""))
chk("H6 placebo_alpha = 0.5 → 오류", bad(function(x) { x$placebo_alpha <- 0.5; x }))
chk("H7 placebo_n × alpha < 1(분위가 표본 밖) → 오류", bad(function(x) { x$placebo_n <- 10; x }))
chk("H8 판정 규칙 어휘 밖(평균 비교 nested_majority) → 오류", bad(function(x) { x$label_rule <- "nested_majority"; x }))

cat("\n=== I. 보유창 규약 ===\n")
d6 <- as.Date("2020-01-01") + 0:5
w1 <- .mc_windows(d6, d6[c(1, 4)], "close_t1")
chk("I1 close_t1 = (집행일, 다음 집행일] — 집행일 수익은 앞 창", identical(as.integer(w1$date - d6[1]), 1:5) &&
      identical(as.integer(w1$exec_date - d6[1]), c(0L, 0L, 0L, 3L, 3L)))
w2 <- .mc_windows(d6, d6[c(1, 4)], "close_d_legacy")
chk("I2 close_d_legacy = [집행일, 다음 집행일)", identical(as.integer(w2$exec_date - d6[1]), c(0L, 0L, 0L, 3L, 3L, 3L)))
chk("I3 명세 없으면 날짜로 판정(첫 수익일 > 첫 집행일 = close_t1)",
    identical(.mc_exec_price(list(), d6[2:6], d6[1])$value, "close_t1") &&
      identical(.mc_exec_price(list(), d6, d6[1])$value, "close_d_legacy") &&
      identical(.mc_exec_price(list(exec_price = "open_t1"), d6, d6[1])$source, "strategy_spec"))
chk("I4 집행 규약 어휘 밖 → 오류", inherits(tryCatch(.mc_exec_price(list(exec_price = "vwap"), d6, d6[1]), error = function(e) e), "error"))

cat("\n=== K. 보고 소비자(program_report.R) ===\n")
chk("K1 크기 방어 문장", grepl("크기 방어", prep_card_digest(rB$card)$controls))
chk("K2 선택 방어 문장", grepl("선택 방어", prep_card_digest(rC$card)$controls))
chk("K3 노출 방어 문장", grepl("노출 방어", prep_card_digest(rD1$card)$controls))
chk("K4 위기 줄에 크기+노출 짝 포착률이 붙는다", all(grepl("크기·노출 짝 [0-9]", prep_card_digest(rB$card)$lines)))
chk("K5 대조 미제공 카드 → '대조 없음'", grepl("대조 없음", prep_card_digest(bc_card(rB$S, rB$B, cfg = bcfg))$controls))
chk("K6 창 선택이 귀속 창을 따른다(시험 창 문장도 라벨을 낸다)", grepl("크기 방어", prep_card_digest(rB$card, "test")$controls))

cat("\n=== L. 산출물 디렉터리 경로(mc_card) — 파일 판독 · 명세 · 저장 왕복 ===\n")
od <- file.path(tempdir(), "mc_art"); dir.create(od, showWarnings = FALSE)
HB <- mkH(function(d) setNames(rep(1 / 90, 90), TK[11:100]))
fwrite(rB$S[, .(strategy_id = "SYN_B", date, ret_net)], file.path(od, "03_period_returns.csv"))
fwrite(rB$B, file.path(od, "05_benchmark_returns.csv"))
fwrite(HB, file.path(od, "04_holdings.csv"))
writeLines(toJSON(list(exec_price = "close_t1", universe = "K200_KQ150"), auto_unbox = TRUE), file.path(od, "01_strategy_spec.json"))
cL <- mc_card(od, root = ROOT, raw = RAW, bm_hist = BM_ALL, bcfg = bcfg)
chk("L1 디렉터리판 귀속 = 메모리판과 같다(size_defense)", identical(cL$controls$attribution$overall$label, "size_defense"))
chk("L2 명세 기록(집행 규약 · 유니버스 · 출처)", identical(cL$controls$spec$exec_price, "close_t1") &&
      identical(cL$controls$spec$exec_price_source, "strategy_spec") && identical(cL$controls$spec$universe, "K200_KQ150"))
p <- mc_write(cL, file.path(tempdir(), "mc_rt"), root = ROOT); rt <- fromJSON(p)
chk("L3 저장 왕복 — schema · 귀속 라벨 · 평균 노출 보존", identical(rt$schema, "behavior_card_v1") &&
      identical(rt$controls$attribution$overall$label, "size_defense") && isTRUE(abs(rt$controls$exposure_profile$mean - 1) < 1e-12))
writeLines(toJSON(list(exec_price = "close_t1"), auto_unbox = TRUE), file.path(od, "01_strategy_spec.json"))
chk("L4 유니버스 미상(명세 · 매니페스트 없음) → 오류(대조 유니버스를 지어내지 않는다)",
    inherits(tryCatch(mc_card(od, root = ROOT, raw = RAW, bm_hist = BM_ALL, bcfg = bcfg), error = function(e) e), "error"))

cat(sprintf("\n== matched_controls: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"matched_controls","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))   # 배터리 요약 계약(run_all_hooks.sh _last_summary_json)
if (FAIL > 0L) quit(status = 1L)
