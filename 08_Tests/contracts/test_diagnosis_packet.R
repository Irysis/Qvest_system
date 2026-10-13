## test_diagnosis_packet.R — 처방 루프 진단 패킷 계약 검사기 (양방향: 불변 · 위반 주입 · 돌연변이)
## 대상: 02_Infrastructure/contracts/diagnosis_packet.R (v10.01 · 2026-10-13 · S1 최소판)
## 핵심 성질: 패킷은 τ_D 이후 데이터를 읽지 않는다 — τ_D 이후의 수익 · 시가총액 · 멤버십 · 보유 · 전략 수익 · 벤치를
##   통째로 바꿔도 패킷이 같아야 한다(R4 · D6). 그리고 같은 비교를 τ_D 를 늦춰 하면 달라져야 한다(비교가 공허하지 않다).
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(.qv_self_dir(), "..", ".."), mustWork = FALSE)
if (dir.exists(file.path(SELF, "02_Infrastructure/contracts"))) ROOT <- SELF
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
TAU <- as.Date("2008-12-31")

## ── 합성 세계(결정론 시드) — 60종목 · 2000~2012 평일 · 시장 요인 + 특이 잡음 · 위기 4번(τ_D 앞 2 · 뒤 2) ──
days <- seq(as.Date("2000-01-03"), as.Date("2012-12-31"), by = "day")
days <- days[!(as.POSIXlt(days)$wday %in% c(0L, 6L))]
NT <- 60L; TK <- sprintf("T%03d", seq_len(NT))
SECT <- rep(c("화학", "운송", "반도체", "자동차", "건설", "소프트웨어"), length.out = NT)
CR <- list(c("2004-03-01", "2004-05-31"), c("2006-06-01", "2006-08-31"), c("2009-06-01", "2009-08-31"), c("2011-06-01", "2011-08-31"))
mk_world <- function(seed, post_seed = NULL) {
  set.seed(seed)
  beta <- runif(NT, 0.6, 1.4); s0 <- exp(rnorm(NT)) * 1e11
  m <- rnorm(length(days), 0.0004, 0.009)
  for (c0 in CR) { ix <- which(days >= as.Date(c0[1]) & days <= as.Date(c0[2])); m[ix] <- m[ix] - 0.006
                   rx <- max(ix) + seq_len(90L); m[rx] <- m[rx] + 0.0055 }       # 위기 뒤 회복(위기끼리 이어지지 않게)
  E <- matrix(rnorm(length(days) * NT, 0, 0.012), length(days), NT)
  if (!is.null(post_seed)) {                      # τ_D 뒤만 다른 세계 — 다른 시드 · 큰 폭락 하나 더
    set.seed(post_seed); post <- days > TAU
    m[post] <- rnorm(sum(post), -0.001, 0.02); E[post, ] <- rnorm(sum(post) * NT, 0, 0.03)
  }
  R <- sweep(matrix(m, length(days), NT), 2, beta, `*`) + E
  R <- pmax(R, -0.29)
  SZ <- sweep(apply(1 + R, 2, cumprod), 2, s0, `*`)
  SZL <- rbind(s0, SZ[-nrow(SZ), ])
  list(R = R, SZ = SZ, BM = rowSums(SZL * R) / rowSums(SZL), CL = 1e4 * apply(1 + R, 2, cumprod))
}
EX <- days[!duplicated(format(days, "%Y-%m"))]; EX <- EX[EX >= as.Date("2003-02-01")]
# 전략 = 직전 60일 누적수익 상위 10종 동일가중(시그널 = 집행일 전 거래일까지) · 세계 B 는 τ_D 뒤 보유도 다르게(무작위 10종)
mk_hold <- function(W, post_random = FALSE, seed = 1L) {
  set.seed(seed)
  rbindlist(lapply(EX, function(e) {
    k <- match(e, days) - 1L
    if (post_random && e > TAU) pick <- sample(TK, 10L) else {
      mom <- colSums(log1p(W$R[max(1L, k - 59L):k, , drop = FALSE])); pick <- TK[order(-mom)][1:10]
    }
    data.table(date = e, ticker = pick, target_weight = 0.1, actual_weight = 0.1)
  }))
}
eng <- function(W, H) {                          # close_t1 창 (e_k, e_k+1] 매수후보유 · 결측 0
  e <- sort(unique(H$date)); out <- vector("list", length(e))
  for (k in seq_along(e)) {
    hi <- if (k < length(e)) e[k + 1L] else max(days)
    ii <- which(days > e[k] & days <= hi); if (!length(ii)) next
    h <- H[date == e[k]]; GL <- sum(h$target_weight); wn <- h$target_weight / GL
    Rm <- W$R[ii, match(h$ticker, TK), drop = FALSE]
    G <- apply(1 + Rm, 2, cumprod); if (!is.matrix(G)) G <- matrix(G, nrow = length(ii))
    V <- as.vector(G %*% wn); Vp <- c(1, V[-length(V)])
    out[[k]] <- data.table(date = days[ii], ret = GL * (V / Vp - 1))
  }
  rbindlist(out)
}
write_world <- function(W, H, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  S <- eng(W, H); B <- data.table(date = days, benchmark_ret = W$BM)[date %in% S$date]
  RAW <- data.table(Date = rep(days, times = NT), Ticker = rep(TK, each = length(days)), Ret = as.vector(W$R),
                    Size = as.vector(W$SZ), Close = as.vector(W$CL), Vol = 1e6, K200 = 1, KQ150 = 0, TradingHalt = 0,
                    Sector = rep(SECT, each = length(days)))
  arrow::write_parquet(RAW, file.path(dir, "RAWDATA.parquet"))
  arrow::write_parquet(data.table(Date = days, BM_Ret = W$BM), file.path(dir, "benchmark.parquet"))
  a <- file.path(dir, "art"); dir.create(a, showWarnings = FALSE)
  fwrite(S[, .(strategy_id = "SYN", date, frequency = "daily", ret_gross = ret, ret_net = ret, risk_free_ret = 0, leverage = 1)],
         file.path(a, "03_period_returns.csv"))
  fwrite(B[, .(date, benchmark_ret, benchmark_nav = cumprod(1 + benchmark_ret))], file.path(a, "05_benchmark_returns.csv"))
  fwrite(S[, .(date, nav_net = cumprod(1 + ret))], file.path(a, "02_nav.csv"))
  fwrite(H, file.path(a, "04_holdings.csv"))
  writeLines(toJSON(list(strategy_name = "SYN_MOM10", exec_price = "close_t1", universe = "K200_KQ150", construction = "top_n_long",
                         n_max = 10, weight_method = "ew", rebalance = "monthly", has_short = FALSE,
                         source_paper_url = "https://example.org/synthetic"), auto_unbox = TRUE), file.path(a, "01_strategy_spec.json"))
  writeLines(toJSON(list(strategy_id = "SYN", universe_id = "K200_KQ150", transaction_cost_bps = 15,
                         cost_model_version = "replication_weight_delta_v1/first_hold_day_multiplicative"), auto_unbox = TRUE),
             file.path(a, "00_manifest.json"))
  list(art = a, raw = file.path(dir, "RAWDATA.parquet"), bm = file.path(dir, "benchmark.parquet"))
}
build <- function(P, tau = TAU) dp_build(P$art, root = ROOT, tau_d = tau, raw_path = P$raw, bm_path = P$bm)
canon <- function(pk) { pk$created_at <- NULL; pk$provenance <- NULL
  as.character(toJSON(pk, auto_unbox = TRUE, digits = NA, null = "null", na = "null", Date = "ISO8601")) }

TD <- file.path(tempdir(), "dp_test"); unlink(TD, recursive = TRUE)
WA <- mk_world(11L); WB <- mk_world(11L, post_seed = 99L)
HA <- mk_hold(WA); HB <- mk_hold(WB, post_random = TRUE, seed = 5L)
PA <- write_world(WA, HA, file.path(TD, "A")); PB <- write_world(WB, HB, file.path(TD, "B"))

cat("=== 0. 세계 점검 — 두 세계는 τ_D 앞이 같고 뒤가 다르다 ===\n")
pre <- days <= TAU
chk("0a τ_D 앞 수익 · 시가총액 동일", identical(WA$R[pre, ], WB$R[pre, ]) && identical(WA$SZ[pre, ], WB$SZ[pre, ]))
chk("0b τ_D 뒤 수익 · 보유는 다르다", !identical(WA$R[!pre, ], WB$R[!pre, ]) &&
      !identical(HA[date > TAU], HB[date > TAU]) && identical(HA[date <= TAU], HB[date <= TAU]))

cat("\n=== A. τ_D 불변 — 적재 단계 절단 ===\n")
t0 <- Sys.time(); KA <- build(PA); KB <- build(PB)
cat(sprintf("  (패킷 2개 %.0fs)\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
chk("A1 τ_D 뒤 세계를 통째로 바꿔도 패킷이 바이트 동일(생성 시각 · 경로 제외)", identical(canon(KA), canon(KB)),
    sprintf("(nchar %d vs %d)", nchar(canon(KA)), nchar(canon(KB))))
chk("A2 패킷 날짜 전수 검사 = τ_D 초과 0", length(dp_scan_dates(KA[setdiff(names(KA), c("created_at", "tau_d"))], TAU)) == 0L)
chk("A3 보는 창 끝 ≤ τ_D · 위기는 τ_D 앞 2번(뒤 2번은 없다)", as.Date(KA$window[2]) <= TAU &&
      NROW(KA$behavior$crises) >= 2L && all(as.Date(KA$behavior$crises$trough_date) <= TAU))
KL <- build(PA, tau = as.Date("2010-12-31")); KLB <- build(PB, tau = as.Date("2010-12-31"))
chk("A4 [돌연변이] 같은 비교를 τ_D 를 늦춰(2010-12-31) 하면 달라진다 — A1 의 비교는 공허하지 않다",
    !identical(canon(KL), canon(KLB)))

cat("\n=== B. 날짜 검사기 — 위반 주입 ===\n")
bad1 <- KA; bad1$exposure$crises$peak_date[1] <- as.Date("2009-06-01")
chk("B1 Date 값 주입 → 검출", "2009-06-01" %in% dp_scan_dates(bad1, TAU))
bad2 <- KA; bad2$identity$idea <- "참고: 2011-08 급락 때 방어"
chk("B2 'YYYY-MM' 문자열 주입 → 검출", "2011-08" %in% dp_scan_dates(bad2, TAU))
bad3 <- KA; bad3$performance$annual <- rbind(as.data.table(KA$performance$annual), data.table(year = "2009-01-02", strategy = 0, bench = 0, active = 0, n_days = 1L), fill = TRUE)
chk("B3 표 안 'YYYY-MM-DD' 주입 → 검출", "2009-01-02" %in% dp_scan_dates(bad3, TAU))
chk("B4 파일명류 숫자(20090601)는 날짜로 보지 않는다(거짓 양성 없음)", !length(dp_scan_dates(list(x = "run_20090601_1234"), TAU)))

cat("\n=== C. 내용 — 항등식 · 귀속 합 · 성분 ===\n")
sx <- as.data.table(KA$exposure$summary)
chk("C1 노출 분해 몫의 합 = 1(항등식: 시장 + 크기 + 무신호 + 선택 + 비용 + 잔차 = 초과)",
    isTRUE(abs(sum(sx[component != "active"]$share_of_active) - 1) < 1e-9), sprintf("(%.12f)", sum(sx[component != "active"]$share_of_active)))
chk("C2 재구성 잔차 ≈ 0(보유 재구성 = 전략 수익)", isTRUE(abs(sx[component == "recon"]$ann_mean) < 1e-8),
    sprintf("(%.3g)", sx[component == "recon"]$ann_mean))
xc <- as.data.table(KA$exposure$crises); bs <- as.data.table(KA$exposure$by_sector)
gap <- bs[, .(s = sum(contrib)), by = peak_date][xc, on = "peak_date"][, abs(s - (strategy_sum - cost_sum))]
chk("C3 위기별 업종 기여 합 = 그 위기 전략 수익 합(비용 제외)", isTRUE(max(gap) < 1e-9), sprintf("(max gap %.3g)", max(gap)))
chk("C4 손실 상위 종목은 위기마다 최대 5종 · 업종 · 크기 분위가 붙는다",
    all(as.data.table(KA$exposure$top_losers)[, .N, by = peak_date]$N <= 5L) &&
      all(!is.na(as.data.table(KA$exposure$top_losers)$Sector)) && all(as.data.table(KA$exposure$top_losers)$size_decile %in% 1:10))
chk("C5 MC8 귀속 · 행동 카드 판정이 실린다", !is.null(KA$controls$attribution$label) && !is.null(KA$behavior$verdict))
chk("C6 종목명은 싣지 않는다(사전학습 서사 통로)", !("Name" %in% names(as.data.table(KA$exposure$top_losers))))
md <- dp_markdown(KA)
chk("C7 요약 문서 — 5절 · τ_D 표기", grepl("## 5. 구성 프로필", md, fixed = TRUE) && grepl(format(TAU), md, fixed = TRUE))

cat("\n=== D. 닫힘 ===\n")
HS <- copy(HA); HS[1, target_weight := -0.1]
PS <- write_world(WA, HS, file.path(TD, "S"))
chk("D1 음수 비중(숏) → 오류(처방 루프 = 롱온리)", inherits(tryCatch(build(PS), error = function(e) e), "error"))
chk("D2 τ_D 이전 보유가 없으면 오류", inherits(tryCatch(build(PA, tau = as.Date("2002-12-31")), error = function(e) e), "error"))
p <- dp_write(KA, file.path(TD, "out"))
rt <- fromJSON(p[["json"]])
chk("D3 저장 왕복 — schema · τ_D · 귀속 라벨 보존", identical(rt$schema, "diagnosis_packet_v1") && identical(rt$tau_d, format(TAU)) &&
      identical(rt$controls$attribution$label, KA$controls$attribution$label))

cat(sprintf("\n== diagnosis_packet: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"diagnosis_packet","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
