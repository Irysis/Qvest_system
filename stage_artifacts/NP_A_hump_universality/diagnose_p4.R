# =============================================================================
# diagnose_p4.R — 측정 중 드러난 결함 2건 진단 (수리 전 정체 확인)
#   결함 1: A_raw_post2015 에서 C02_EPS_Chg_1m · M26_Revenue_Mom 의 분위 프로파일 NaN
#           → 빈 분위(empty quintile). 원인 = raw z 의 동점(tie) 로 frank(z)/.N 밴드가 빈다.
#           ★ NaN 은 결론이 아니라 정지 신호. 어느 월·어느 분위·몇 건인지 실측한다.
#   결함 2: 앵커 post2015 에서 블록 부트스트랩 p(0.017) 와 NW t(-1.74) 불일치
#           → 부트스트랩 분포의 비대칭 여부를 실측하고 보수적 인용 근거를 만든다.
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/diagnose_p4.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
IN3 <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p4] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R"); set.seed(20260809L)
SPN <- readRDS(file.path(OUT, "signal_panel_neutral.rds"))
P1p <- readRDS(file.path(IN3, "prereg_p1.rds")); P0 <- readRDS(file.path(IN3, "p0_panels.rds"))
DG <- list()

ACT_A <- P1p$D[, .(Date, Ticker, act)]
ACT_B <- merge(P0$E[, .(Date, Ticker)], P0$returns_dt, by = c("Date","Ticker"))
ACT_B <- merge(ACT_B, P0$bench_dt, by = "Date")[, .(Date, Ticker, act = Ret_1m - BM_Ret)]

say("=== 결함 1: 빈 분위 실측 (전 신호 × 두 프레임 × 두 arm) ===")
emp <- rbindlist(lapply(sort(unique(SPN$Factor_Name)), function(fn) {
  rbindlist(lapply(c("A","B"), function(fr) {
    ACT <- if (fr == "A") ACT_A else ACT_B
    rbindlist(lapply(c("z","zn"), function(zc) {
      X <- merge(SPN[Factor_Name == fn, .(Date, Ticker, z, zn)], ACT, by = c("Date","Ticker"))
      X <- X[is.finite(get(zc)) & is.finite(act)]
      s <- X[, { qr <- frank(get(zc))/.N
        .(n1 = sum(qr <= 0.2), n2 = sum(qr > 0.2 & qr <= 0.4), n3 = sum(qr > 0.4 & qr <= 0.6),
          n4 = sum(qr > 0.6 & qr <= 0.8), n5 = sum(qr > 0.8), nn = .N) }, by = Date]
      s[, empty := (n1 == 0) | (n2 == 0) | (n3 == 0) | (n4 == 0) | (n5 == 0)]
      data.table(signal = fn, frame = fr, arm = zc, n_month = nrow(s),
                 n_empty_full = sum(s$empty), n_empty_post2015 = sum(s$empty & s$Date >= as.Date("2015-01-01")),
                 min_q1 = min(s$n1), min_q3 = min(s$n3), min_q5 = min(s$n5),
                 worst_month = if (any(s$empty)) as.character(s[empty == TRUE][1]$Date) else NA_character_) })) })) }))
print(emp[n_empty_full > 0])
say("빈 분위 발생 셀 %d / %d (전체 신호×프레임×arm)", nrow(emp[n_empty_full > 0]), nrow(emp))
say("★ 발생 arm: %s", paste(unique(emp[n_empty_full > 0]$arm), collapse = ", "))
DG$empty_quintiles <- emp

# 원인 확인: 동점 비율
say("=== 결함 1 원인 — raw z 동점 비율 (최빈값 점유율) ===")
tie <- SPN[, { tb <- table(z); .(top_tie_frac = max(tb)/.N, n = .N) }, by = .(Factor_Name, Date)][
  , .(median_top_tie_frac = median(top_tie_frac), max_top_tie_frac = max(top_tie_frac)), by = Factor_Name][order(-max_top_tie_frac)]
print(tie)
DG$tie_fraction_raw <- tie

say("=== 결함 2: 부트스트랩 분포 비대칭 실측 (앵커 post2015) ===")
D <- P1p$D[Date >= as.Date("2015-01-01")]
s <- D[, { qr <- frank(q01_n)/.N
  .(q3 = mean(act[qr > 0.4 & qr <= 0.6]), q5 = mean(act[qr > 0.8])) }, by = Date]
g <- s$q5 - s$q3
mbb_draws <- function(x, block = 12L, B = 5000L) { n <- length(x); nb <- ceiling(n/block); sm <- n - block + 1L
  replicate(B, { st <- sample.int(sm, nb, replace = TRUE)
    idx <- as.vector(outer(0:(block-1L), st, function(a,b) b + a)); mean(x[idx[seq_len(n)]]) }) }
m <- mbb_draws(g)
f <- lm(g ~ 1); nwse <- sqrt(sandwich::NeweyWest(f, lag = 3, prewhite = FALSE)[1,1])
say("  표본평균 월 %+.5f (연 %+.2f%%) · NW(lag3) SE 월 %.5f → t %+.2f (양측 p %.3f)",
    mean(g), 100*12*mean(g), nwse, mean(g)/nwse, 2*(1-pnorm(abs(mean(g)/nwse))))
say("  부트스트랩(block=12,B=5000): 재표본평균 sd %.5f · 왜도 %+.2f · P(m>=0) %.4f",
    sd(m), mean((m-mean(m))^3)/sd(m)^3, mean(m >= 0))
say("  → 백분위 p %.3f vs 정규근사 부트 p %.3f vs NW p %.3f",
    2*min(mean(m<=0), mean(m>=0)), 2*(1-pnorm(abs(mean(g))/sd(m))), 2*(1-pnorm(abs(mean(g)/nwse))))
say("  ★ 세 값이 갈리면 **가장 보수적인 값**(NW)을 인용한다 — 사전등록 부트 CI 는 병기하되 단독 인용 금지")
DG$bootstrap_asymmetry <- list(mean_monthly = mean(g), ann_pct = 100*12*mean(g),
  nw_se = nwse, nw_t = mean(g)/nwse, nw_p2 = 2*(1-pnorm(abs(mean(g)/nwse))),
  boot_sd = sd(m), boot_skew = mean((m-mean(m))^3)/sd(m)^3,
  boot_p_percentile = 2*min(mean(m<=0), mean(m>=0)),
  boot_p_normal = 2*(1-pnorm(abs(mean(g))/sd(m))),
  citation_rule = "세 추론이 갈리면 가장 보수적(NW)을 인용. 부트 백분위 p 단독 인용 금지")

write_json(DG, file.path(OUT, "diagnosis_p4.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== 진단 완료 → diagnosis_p4.json ===")
