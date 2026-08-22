## WT-D20260822_011 — 반증 4축 (N1/N2/N3 승계 + N4 신설). 처치 백테스트 없음.
## N4 는 alpha_hypothesis.json 이 신설한 축이며 **성과 측정 없이 판정 가능**하도록 설계됐다.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_011")
say <- function(f, ...) cat(sprintf(paste0("[f] ", f, "\n"), ...))
Fx <- list(); Fx$falsification_source <- "qepm/mailbox/worktask/WT-D20260822_011/alpha_hypothesis.json$hypothesis$falsification"
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

O <- readRDS(file.path(OUT, "00_precheck_objects.rds"))
SEL <- as.data.table(O$SEL); RT <- as.data.table(O$RT); EPS <- O$EPS; Wb <- as.data.table(O$Wb)
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
kk <- function(d) paste(d$Date, d$Ticker)
Dt <- copy(SEL)[, sc_adj := sc - EPS * as.numeric(excluded)]
setorder(Dt, Date, -sc_adj); Dt[, rk := seq_len(.N), by = Date]
Wt <- Dt[rk <= 25L][, w := cap_norm(Size), by = Date][, .(Date, Ticker, w, sc)]
kb <- kk(Wb); kt <- kk(Wt)
disp <- merge(Wb[!(kb %chin% kt)], RT, by = c("Date","Ticker"), all.x = TRUE)
ins  <- merge(Wt[!(kt %chin% kb)], RT, by = c("Date","Ticker"), all.x = TRUE)
disp[, th := is.finite(Ret_1m) & Ret_1m <= -0.20]; ins[, th := is.finite(Ret_1m) & Ret_1m <= -0.20]

## ── N4 (신설) — ε-근접쌍 꼬리 판별력 ───────────────────────────────────────
m4 <- merge(disp[, .(td = mean(th), nd = .N), by = Date], ins[, .(ti = mean(th), ni = .N), by = Date], by = "Date")
m4[, spread := td - ti]
t4 <- nw_t(m4$spread)
Fx$N4 <- list(id = "N4_near_tie_tail_discrimination",
  epsilon = EPS, pairs_per_month = mean(m4$nd), n_months = nrow(m4),
  tail_flagged_pooled = disp[, mean(th)], tail_challenger_pooled = ins[, mean(th)],
  pooled_gap = disp[, mean(th)] - ins[, mean(th)],
  monthly_spread_mean = m4[, mean(spread)], monthly_spread_nw_t = t4,
  reject_rule = "n_months >= 30 에서 NW-t <= 0 → 기각",
  wt010_unconditional_reference = 0.00804952700257582,
  fired = (nrow(m4) >= 30L && is.finite(t4) && t4 <= 0),
  label = if (!is.finite(t4)) "산출불가" else if (t4 <= 0) "기각" else if (t4 < 2) "미결(검출 부족)" else "지지")
say("N4: 근접쌍 %.2f쌍/월 (n=%d월) | 꼬리 표식 %.4f%% vs 도전자 %.4f%% | 월별 스프레드 %+.6f NW t=%+.3f → %s",
    Fx$N4$pairs_per_month, Fx$N4$n_months, 100*Fx$N4$tail_flagged_pooled, 100*Fx$N4$tail_challenger_pooled,
    Fx$N4$monthly_spread_mean, t4, Fx$N4$label)
say("   [WT-010 비근접(무조건) top-25 조건부 격차 = %+.6f — 근접쌍 조건화로 %.0f%% 축소]",
    Fx$N4$wt010_unconditional_reference, 100*(1 - Fx$N4$pooled_gap/Fx$N4$wt010_unconditional_reference))

## ── N1 — 노출 중립성 (size + win_vol, 교체 실현쌍 스코프) ──────────────────
NP <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/alpha_scores.parquet"))[, Date := as.Date(Date)]
CV <- NP[, .(Date, Ticker, win_vol, log_size)]
mk <- function(col) {
  X <- merge(rbind(disp[, .(Date, Ticker, g = "d")], ins[, .(Date, Ticker, g = "i")]),
             CV[, .(Date, Ticker, v = get(col))], by = c("Date","Ticker"))
  U <- merge(SEL[, .(Date, Ticker)], CV[, .(Date, Ticker, v = get(col))], by = c("Date","Ticker"))
  U[, pr := frank(v)/.N, by = Date]
  X <- merge(X, U[, .(Date, Ticker, pr)], by = c("Date","Ticker"))
  M <- X[, .(d = mean(pr[g=="d"]), i = mean(pr[g=="i"])), by = Date][is.finite(d) & is.finite(i)]
  list(gap = mean(M$d - M$i), abs = abs(mean(M$d - M$i)), nw_t = nw_t(M$d - M$i), n = nrow(M),
       lvl_d = mean(M$d), lvl_i = mean(M$i)) }
n1s <- mk("log_size"); n1v <- mk("win_vol")
Fx$N1 <- list(scope = "displaced(표식 밀림) vs inserted(비표식 편입) — 실현 교체쌍",
  threshold = 0.126, size = n1s, vol = n1v,
  fired = (n1s$abs >= 0.126 || n1v$abs >= 0.126),
  wt010_flagged_set = list(size_abs = 0.0815245766029775, vol_abs = 0.0597352879667346, fired = FALSE),
  note = "표식집합(low_orth) 자체는 WT-010 과 bit-동일(SMx verbatim 승계, md5 대조) — 표식-스코프 값은 WT-010 실측 그대로 유효. 본 표는 교체 실현쌍 재스코프.")
say("N1 size: disp %.4f vs ins %.4f (gap %+.4f, NW t %+.2f, n=%d) | vol: disp %.4f vs ins %.4f (gap %+.4f, NW t %+.2f) → %s",
    n1s$lvl_d, n1s$lvl_i, n1s$gap, n1s$nw_t, n1s$n, n1v$lvl_d, n1v$lvl_i, n1v$gap, n1v$nw_t,
    ifelse(Fx$N1$fired, "FIRED", "미발화"))

## ── N2 / N3 — 표식집합 성질이므로 WT-010 실측 승계 (재측정 불요) ───────────
W10 <- fromJSON("stage_artifacts/WT-D20260822_010/11_falsify.json")
Fx$N2 <- list(id = "N2_downday_individual_support_residual", inherited_from = "WT-D20260822_010/11_falsify.json",
  mean_spread = W10$N2$mean_spread, nw_t = W10$N2$nw_t, n_months = W10$N2$n_months,
  label = "지지(유의 음수)", fired = FALSE,
  inheritance_validity = "표식집합(score_orth 하위 20%) 은 SMx verbatim 승계로 WT-010 과 bit-동일하고, N2 는 표식집합의 성질이지 소비 형태(배제 vs tie-break)의 함수가 아니다 — 재측정이 같은 값을 낼 수밖에 없는 관측이므로 승계가 정본.")
Fx$N3 <- list(id = "N3_smart_money_followthrough", inherited_from = "WT-D20260822_010/11_falsify.json",
  mean_spread = W10$N3$mean_spread, nw_t = W10$N3$nw_t, n_months = W10$N3$n_months,
  reject_threshold = 2, label = "미결", fired = FALSE, inheritance_validity = Fx$N2$inheritance_validity)
say("N2 (승계): %+.6f NW t=%+.2f n=%d → 지지 | N3 (승계): %+.8f NW t=%+.2f → 미결",
    Fx$N2$mean_spread, Fx$N2$nw_t, Fx$N2$n_months, Fx$N3$mean_spread, Fx$N3$nw_t)

Fx$fired_count <- sum(c(Fx$N1$fired, Fx$N2$fired, Fx$N3$fired, Fx$N4$fired))
say("★ 발화 %d/4 (N1 %s / N2 %s / N3 %s / N4 %s)", Fx$fired_count,
    Fx$N1$fired, Fx$N2$fired, Fx$N3$fired, Fx$N4$fired)
write_json(Fx, file.path(OUT, "12_falsify.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
