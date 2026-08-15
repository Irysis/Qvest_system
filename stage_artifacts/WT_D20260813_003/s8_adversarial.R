## s8_adversarial.R — Self-Adversarial Challenge 수치 근거 (판정 확정 후)
## 제기 4건에 대한 실측: (A1) NW lag 민감도 (A2) 극단-국소 영역의 평균 부호
## (A3) 최근 국면 의존성 (A4) 검정력 — 이 판정을 해소하려면 표본이 얼마나 필요한가
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
BC <- new.env(parent = globalenv()); sys.source("02_Infrastructure/contracts/backtest_result_contract.R", envir = BC)
nw_t <- function(x, lag = 3L) BC$.nw_t_mean(x, lag = lag)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_003")
EV <- as.data.table(readRDS(file.path(OUT, "vt_panel.rds"))); setorder(EV, hold_start)
r <- EV$r; e <- EV$e; n <- nrow(EV); ebar <- mean(e); d <- (e - ebar) * r

## ── A1. NW lag 민감도 (겹치는 252d 창 -> lag-3 이 부족한가) ─────────────────
lags <- c(3L, 6L, 12L, 24L)
a1 <- data.table(lag = lags, t = vapply(lags, function(L) nw_t(d, L), numeric(1)))
cat("[A1] VT2b NW t — lag 민감도:\n"); print(a1)
cat(sprintf("[A1] d 계열 자기상관 ac1=%.4f ac3=%.4f ac12=%.4f (r 이 거의 무상관이라 d 도 낮음)\n",
            cor(d[-1], d[-n]), cor(d[-(1:3)], d[1:(n-3)]), cor(d[-(1:12)], d[1:(n-12)])))

## ── A2. 극단-국소 영역 — 문턱형이면 평균 부호가 다른가 ──────────────────────
## 승계 설계의 평균채널 근거는 TAIL 상위 20% 조작점(ON 34개월 mean -2.47%). 본 라운드 매핑은
## bind 41.8% 로 훨씬 넓다. 영역을 좁히면 평균 부호가 뒤집히는가?
pc <- frank(EV$sigma_d) / n
a2 <- rbindlist(lapply(c(0.50, 0.70, 0.80, 0.90, 0.95), function(q) {
  s <- pc > q
  data.table(top_frac = 1 - q, n_on = sum(s), mean_r_on_pct = 100*mean(r[s]),
             mean_r_off_pct = 100*mean(r[!s]), diff_pct = 100*(mean(r[s]) - mean(r[!s])),
             welch_t = as.numeric(t.test(r[s], r[!s])$statistic),
             welch_p = t.test(r[s], r[!s])$p.value)
}))
cat("\n[A2] sigma_hat 상위 X% 월의 벤치 평균수익 (음수여야 vol-target 이 평균채널을 번다):\n"); print(a2)
## 승계 TAIL 조작점 재현 — ★선별율을 맞춰 비교한다.
## 초판 결함: TAIL 은 expanding-pct>=0.80 (실제 발화율 9%) vs sigma_hat 은 전표본 rank>=0.80 (20%)
## 로 비교했다 — 선별율이 2배 달라 사과-오렌지. 두 예측기 모두 **동일 규칙**으로 재산출한다.
P2 <- as.data.table(arrow::read_parquet("stage_artifacts/WT_D20260813_002/alpha_scores.parquet"))
M <- merge(EV[, .(ym, r, sigma_d)], P2[, .(ym, TAIL, tail_pct)], by = "ym")
exp_pct <- function(v) { m <- length(v); o <- numeric(m); for (i in seq_len(m)) o[i] <- mean(v[1:i] <= v[i]); o }
M[, sig_pct := exp_pct(sigma_d)]
a2b <- rbindlist(lapply(list(
    list(rule = "expanding-pct >= 0.80", on_T = M$tail_pct >= 0.80,  on_S = M$sig_pct >= 0.80),
    list(rule = "전표본 rank 상위 20%",   on_T = frank(M$TAIL)/nrow(M) > 0.80, on_S = frank(M$sigma_d)/nrow(M) > 0.80),
    list(rule = "전표본 rank 상위 9%",    on_T = frank(M$TAIL)/nrow(M) > 0.91, on_S = frank(M$sigma_d)/nrow(M) > 0.91)
  ), function(z) data.table(rule = z$rule,
     n_TAIL = sum(z$on_T), mean_TAIL_on_pct = 100*mean(M$r[z$on_T]),
     n_SIGMA = sum(z$on_S), mean_SIGMA_on_pct = 100*mean(M$r[z$on_S]),
     overlap = sum(z$on_T & z$on_S))))
cat("\n[A2b] 선별율 일치 비교 — TAIL vs sigma_hat 이 고른 달의 평균수익 (spearman(TAIL,VOL)=0.838 인데도):\n")
print(a2b)
on_t <- M$tail_pct >= 0.80; on_s <- M$sig_pct >= 0.80
cat(sprintf("[A2b] 동일규칙(expanding-pct>=0.80): TAIL n=%d 평균 %+.3f%%/월 (Welch t=%+.3f p=%.4f) | sigma_hat n=%d 평균 %+.3f%%/월 (Welch t=%+.3f p=%.4f)\n",
            sum(on_t), 100*mean(M$r[on_t]), t.test(M$r[on_t], M$r[!on_t])$statistic, t.test(M$r[on_t], M$r[!on_t])$p.value,
            sum(on_s), 100*mean(M$r[on_s]), t.test(M$r[on_s], M$r[!on_s])$statistic, t.test(M$r[on_s], M$r[!on_s])$p.value))

## ── A3. 최근 국면 의존성 ────────────────────────────────────────────────────
a3 <- rbindlist(lapply(list(c(1, n), c(1, n - 12), c(1, n - 24), c(1, n - 60)), function(w) {
  i <- w[1]:w[2]; ee <- e[i]; rr <- r[i]; eb <- mean(ee)
  dd <- (ee - eb) * rr
  xx <- ee * rr; ccx <- eb * rr
  data.table(window = sprintf("%s ~ %s", EV$ym[w[1]], EV$ym[w[2]]), n = length(i),
             G = 1 - sd(xx)/sd(ccx), mean_d_ann_pct = 100*mean(dd)*12,
             net_ann_pct = 100*(mean(dd) + (var(ccx) - var(xx))/2)*12, t = nw_t(dd, 3L))
}))
cat("\n[A3] 말단 절단 감도:\n"); print(a3)

## ── A4. 검정력 — 이 판정을 통계적으로 해소하려면 ────────────────────────────
sd_d <- sd(d) * sqrt(12); mu_net <- (mean(d) + (var(ebar*r) - var(e*r))/2) * 12
sd_net_approx <- sd_d   # 순효과 분산은 사실상 d 가 지배(드래그항은 저분산)
n_req <- ceiling((1.96 * sd_net_approx / abs(mu_net))^2 * 12)
cat(sprintf("\n[A4] 순효과 점추정 %.3f%%/yr, 월별 sd(d) 연환산 %.3f%%. |t|=1.96 도달 필요 표본 ~= %d 개월 (%.1f 년)\n",
            100*mu_net, 100*sd_net_approx, n_req, n_req/12))
cat(sprintf("[A4] 현 표본 %d 개월 -> 현재 순효과 |t| 근사 = %.3f. 즉 '해롭다' 도 '이롭다' 도 이 표본으로는 미해소.\n",
            n, abs(mu_net)/(sd_net_approx/sqrt(n/12))))

write_json(list(
  wt_id = "WT-D20260813_003", stage = "self_adversarial_numbers",
  metric_type = "mechanism_observation_posthoc",
  A1_nw_lag_sensitivity = a1,
  A1_d_autocorr = list(ac1 = cor(d[-1], d[-n]), ac3 = cor(d[-(1:3)], d[1:(n-3)]),
                       ac12 = cor(d[-(1:12)], d[1:(n-12)])),
  A2_extreme_region = a2,
  A2b_rate_matched = a2b,
  A2b_note = "초판은 TAIL(expanding-pct, 발화율 9%) 과 sigma_hat(전표본 rank, 20%) 을 비교해 선별율이 2배 어긋났다 — 자기적발 후 동일 규칙으로 재산출.",
  A2_inherited_TAIL_opoint = list(n_on = sum(on_t), mean_on_pct = 100*mean(M$r[on_t]),
    mean_off_pct = 100*mean(M$r[!on_t]),
    welch_t = as.numeric(t.test(M$r[on_t], M$r[!on_t])$statistic),
    welch_p = t.test(M$r[on_t], M$r[!on_t])$p.value,
    sigma_same_rule_n = sum(on_s), sigma_same_rule_mean_pct = 100*mean(M$r[on_s])),
  A3_endpoint_sensitivity = a3,
  A4_power = list(net_annual_pct = 100*mu_net, sd_d_annualized_pct = 100*sd_net_approx,
    n_months_required_for_t196 = n_req, years_required = n_req/12, n_current = n)
), file.path(OUT, "adversarial_numbers.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("\n[done] adversarial_numbers.json\n")
