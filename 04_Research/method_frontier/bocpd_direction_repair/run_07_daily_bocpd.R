# run_07_daily_bocpd.R — 일별 해상도 BOCPD: 에피소드가 실제로 늘어나는가
#
# ── 왜 ───────────────────────────────────────────────────────────────────────
# 월간(271관측)에서 BOCPD 팔은 어느 문턱에서도 판별 불가였다. 구속한 것은 표본 길이가
# 아니라 **에피소드 수**다 — 신호가 있는 구간(mass>=0.60)은 4에피소드, 에피소드가 많은
# 구간(mass>=0.15)은 효과 0. 3.53%p 를 판별하려면 에피소드 30개가 필요한데 어느
# 문턱에서도 최대 22개였다(run_05 검정력 지도).
#
# 일별로 가면 관측이 271 -> 5,590 (20.6배)이 된다. 같은 선택성에서 변화점 사건이
# 비례해 늘어난다면 판별 가능 구간이 생긴다. 그것을 확인하는 라운드다.
#
# ── hazard 를 어떻게 정하는가 (스윕 금지) ───────────────────────────────────
# 월간 원본은 hazard = 1/24, 즉 **기대 국면 길이 2년**이다. 일별에 1/24 을 그대로 쓰면
# 기대 국면 길이가 24거래일(약 1개월)이 되어 **다른 모델**이 된다. 성과로 고르면 스윕이므로,
# 원칙에 따라 **같은 기대 국면 길이 2년**으로 환산해 hazard = 1/504 (거래일 기준) 하나만 쓴다.
# short-run 창도 같은 원칙: 월간 SHORT=6개월 -> 일별 SHORT=126거래일.
#
# ── 재현 검사 ────────────────────────────────────────────────────────────────
# 속도 때문에 재귀를 벡터화한다. 벡터화본이 **원본과 다른 값을 내면 다른 모델**이므로,
# 일별에 쓰기 전에 원본 월간 시계열에서 비트 단위 재현을 먼저 건다(양성 대조).
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_07_daily_bocpd.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(arrow) })

OUT <- "04_Research/method_frontier/bocpd_direction_repair"
SRC <- "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R"

# ── 벡터화 재귀 (원본과 동일 연산, 내부 for(r) 만 제거) ──────────────────────
bocpd_vec <- function(ret_vec, hazard, short_win, prior_mean = 0,
                      prior_var, prior_alpha = 1.0, prior_beta = prior_var * prior_alpha) {
  T_n <- length(ret_vec)
  Rcur <- numeric(T_n + 1L); Rcur[1L] <- 1.0     # R[, t] — 현재 열만 들고 간다(메모리)
  cp <- srm <- erl <- pmu <- psd <- numeric(T_n)
  av <- rep(prior_alpha, T_n + 1L); bv <- rep(prior_beta, T_n + 1L)
  mv <- rep(prior_mean, T_n + 1L); kv <- rep(1.0, T_n + 1L)
  for (t in seq_len(T_n)) {
    x <- ret_vec[t]
    i <- seq_len(t)
    a <- av[i]; b <- bv[i]; m <- mv[i]; k <- kv[i]
    sc <- sqrt(b * (k + 1) / (a * k))
    pred <- dt((x - m) / sc, df = 2 * a) / sc     # 벡터화 (원본은 스칼라 루프)
    growth <- Rcur[i] * pred * (1 - hazard)
    cpp <- sum(Rcur[i] * pred * hazard)
    Rnew <- numeric(T_n + 1L)
    Rnew[1L] <- cpp; Rnew[2:(t + 1L)] <- growth
    Z <- sum(Rnew); if (Z > 0) Rnew <- Rnew / Z else Rnew[1L] <- 1.0
    cp[t]  <- Rnew[1L]
    srm[t] <- sum(Rnew[1L:min(short_win + 1L, t + 1L)])
    erl[t] <- sum((0L:t) * Rnew[1L:(t + 1L)])
    na <- nb <- nm <- nk <- numeric(T_n + 1L)
    na[1] <- prior_alpha; nb[1] <- prior_beta; nm[1] <- prior_mean; nk[1] <- 1.0
    na[i + 1L] <- a + 0.5
    nk[i + 1L] <- k + 1
    nm[i + 1L] <- (k * m + x) / nk[i + 1L]
    nb[i + 1L] <- b + (k * (x - m)^2) / (2 * nk[i + 1L])
    w <- Rnew[1L:(t + 1L)]
    pmu[t] <- sum(w * nm[1:(t + 1L)])
    psd[t] <- sum(w * sqrt(nb[1:(t + 1L)] * (nk[1:(t + 1L)] + 1) /
                             (na[1:(t + 1L)] * nk[1:(t + 1L)])))
    av <- na; bv <- nb; mv <- nm; kv <- nk; Rcur <- Rnew
  }
  list(change_prob = cp, short_run_mass = srm, expected_runlen = erl,
       post_mean = pmu, post_sd = psd)
}

# ── 상수 (소스 재도출) ───────────────────────────────────────────────────────
txt <- paste(readLines(SRC, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
.grab <- function(pat) {
  m <- regmatches(txt, regexpr(pat, txt, perl = TRUE))
  if (!length(m)) stop(sprintf("상수 추출 실패: %s", pat))
  eval(parse(text = sub("^[A-Za-z_]+ *<- *", "", sub(" *#.*$", "", m))))
}
HZ_M <- .grab("BOCPD_HAZARD <- [^\n]+"); PV <- .grab("BOCPD_PRIOR_VAR <- [^\n]+")
SHORT_M <- 6L
cat(sprintf("[const] 월간 hazard=%.6f prior_var=%.6f short=%d (소스 재도출)\n",
            HZ_M, PV, SHORT_M))

# ── 재현 검사 — 벡터화본이 원본 월간 출력을 재현하는가 ──────────────────────
p <- as.data.table(read_parquet(
  "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
p[, Date := as.Date(Date)]; p <- unique(p, by = "Date")[order(Date)]
v <- !is.na(p$ret_net)
mv_out <- bocpd_vec(p$ret_net[v], hazard = HZ_M, short_win = SHORT_M, prior_var = PV)
lag1 <- function(z) c(NA_real_, z[-length(z)])
e_srm <- abs(lag1(mv_out$short_run_mass) - p$bocpd_short_run_mass_lag[v])
n_v <- sum(v); hn <- n_v - 2L                   # 꼬리 2행 = ret_net 갱신 구간(run_01 실측)
d_head <- max(e_srm[1:hn], na.rm = TRUE)
cat(sprintf("[재현검사] 벡터화본 vs 원본 월간 — 본문 1~%d max|delta| = %.3e\n", hn, d_head))
if (d_head > 1e-9)
  stop("[재현검사] 벡터화본이 원본과 다른 값을 낸다 — 일별에 쓸 수 없다. 중단")
cat("[재현검사] OK — 벡터화는 속도만 바꿨다\n")

# ── 일별 실행 ────────────────────────────────────────────────────────────────
D <- as.data.table(read_parquet(file.path(OUT, "daily_returns.parquet")))
D[, Date := as.Date(Date)]; setorder(D, Date)
HZ_D <- 1 / 504; SHORT_D <- 126L                # 월간과 **같은 기대 국면 길이 2년**
cat(sprintf("[daily] %d관측 · hazard=1/504 · short=%d거래일 (월간과 동일 시간척도)\n",
            nrow(D), SHORT_D))
t0 <- Sys.time()
dv <- bocpd_vec(D$ret_d, hazard = HZ_D, short_win = SHORT_D, prior_var = PV)
cat(sprintf("[daily] 재귀 완료 %.1f분\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

D[, `:=`(mass_d = dv$short_run_mass, erl_d = dv$expected_runlen,
         pmu_d = dv$post_mean, psd_d = dv$post_sd, cp_d = dv$change_prob)]
write_parquet(D, file.path(OUT, "daily_bocpd.parquet"))

# ── 월 결정으로 접기 (소비면은 여전히 월간 리밸) ────────────────────────────
#   결정일 t 의 신호 = 그 달 **시작 전** 마지막 거래일의 일별 사후. lag 는 그 구조로 이미 성립.
mon <- D[, .(mass = last(mass_d), erl = last(erl_d), pmu = last(pmu_d),
             psd = last(psd_d)), by = period_end][order(period_end)]
mon[, `:=`(mass_lag = shift(mass), erl_lag = shift(erl),
           pmu_lag = shift(pmu), psd_lag = shift(psd))]
m4 <- p[, .(period_end = Date, ret_net, cash = Cash_Pct_lag)]
J <- merge(mon, m4, by = "period_end")[!is.na(ret_net) & !is.na(mass_lag)]
J[, clean := is.na(cash) | cash == 0]
sub <- J[clean == TRUE][order(period_end)]
cat(sprintf("[join] 매크로 clean %d개월 · mass 분포 q25 %.3f 중앙 %.3f q75 %.3f max %.3f\n",
            nrow(sub), quantile(sub$mass_lag, .25), median(sub$mass_lag),
            quantile(sub$mass_lag, .75), max(sub$mass_lag)))

# ── 검정력 지도 (월간과 동일 형식 — 직접 비교 가능하게) ─────────────────────
y <- sub$ret_net; n <- length(y); sdv <- sd(y); ev <- y < -0.05; br <- mean(ev)
WARM <- 12L                                    # 관측 개월수 warm-up (bold-mayer 수리 정합)
sub[, obs := seq_len(.N)]
grid <- seq(0.15, 0.90, by = 0.05)
map <- rbindlist(lapply(grid, function(th) {
  x <- as.integer(sub$mass_lag >= th & sub$obs > WARM)
  k_m <- sum(x); k_e <- sum(rle(x == 1L)$values)
  if (k_m < 2L || k_m >= n - 2L)
    return(data.table(theta = th, n_fire = k_m, n_epi = k_e, effect = NA_real_,
                      lift = NA_real_, mde80 = NA_real_, resolvable = NA))
  eff <- mean(y[x == 1L]) - mean(y[x == 0L])
  se <- sdv * sqrt(1 / max(k_e, 1L) + 1 / (n - max(k_e, 1L)))
  data.table(theta = th, n_fire = k_m, n_epi = k_e, effect = eff,
             lift = mean(ev[x == 1L]) / br, mde80 = (1.645 + 0.84) * se,
             resolvable = abs(eff) >= (1.645 + 0.84) * se)
}))
cat("\n=== 일별 BOCPD 검정력 지도 (warm-up 12개월 적용) ===\n")
print(map[, .(theta, n_fire, n_epi, effect_pp = round(effect * 100, 2),
              lift = round(lift, 2), MDE80 = round(mde80 * 100, 2),
              판별가능 = ifelse(is.na(resolvable), "-", ifelse(resolvable, "O", "X")))])
fwrite(map, file.path(OUT, "daily_power_map.csv"))
cat(sprintf("\n[out] %s/{daily_bocpd.parquet,daily_power_map.csv}\n", OUT))
