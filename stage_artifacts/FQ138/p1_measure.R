## FQ-138 P1 — 사전등록(fq138_preregistration.json, 2026-08-08) **그대로** 실행
## ★이 라운드의 규율: 사전등록이 이미 pass/fail 불가를 선언했다(필요 연 27.71%).
##   ⇒ **구간추정**만 한다. delta 점추정 + 95% CI. 'CI 가 0 포함' 이라 쓰고 '효과 없음' 이라 쓰지 않는다.
##   CI 상한이 연 10% 미만일 때만 '실질적 효과 배제' 주장 가능.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ138")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

PRE <- fromJSON("stage_artifacts/fq141_precheck_20260808/fq138_preregistration.json", simplifyVector = FALSE)
say("사전등록 %s · registered_at %s · before_measurement %s",
    PRE$task_id, PRE$registered_at, PRE$registered_before_measurement)

## ---- ★data_pins MANDATORY (gridx_* 확장본. grid_* 파일럿 금지) ---------------
B <- "04_Research/method_frontier/fq002_contract_magnitude"
pin <- list(returns = file.path(B, "gridx_returns.parquet"),
            bench   = file.path(B, "gridx_bench.parquet"),
            usize   = file.path(B, "gridx_universe_size.parquet"),
            panel   = file.path(B, "panelx_A.parquet"))
say("=== 0. data pin 확인 (확장본 강제) ===")
for (k in names(pin)) say("  %-8s %s  존재=%s", k, basename(pin[[k]]), file.exists(pin[[k]]))
if (!all(vapply(pin, file.exists, logical(1)))) { say("★핀 파일 부재 — 중단(파일럿 대체 금지)"); quit(status=1) }

R  <- as.data.table(read_parquet(pin$returns))
BM <- as.data.table(read_parquet(pin$bench))
PA <- as.data.table(read_parquet(pin$panel))
for (D in list(R, BM, PA)) if ("Date" %in% names(D)) D[, Date := as.Date(Date)]
say("=== 1. 입력 실측 ===")
say("  returns %d행 · %d개월 · %s ~ %s · 컬럼 %s", nrow(R), uniqueN(R$Date), min(R$Date), max(R$Date),
    paste(names(R), collapse=","))
say("  bench   %d행 · 컬럼 %s", nrow(BM), paste(names(BM), collapse=","))
say("  panelx_A %d행 · %d개월 · 컬럼 %s", nrow(PA), uniqueN(PA$Date), paste(names(PA), collapse=","))
say("  ★사전등록 기재: gridx 80개월 · returns 191,980행 · bench 80행 — 대조 %s / %s / %s",
    uniqueN(R$Date) == 80L, nrow(R) == 191980L, nrow(BM) == 80L)

## ---- 2. 국면 정의 (FROZEN: t-1 mega_spread <= 0) ----------------------------
say("=== 2. 국면 (FROZEN — 동월·trailing3 사용 금지) ===")
rcol <- intersect(c("Ret_1m","ret","Ret"), names(R))[1]
scol <- intersect(c("Size","size","mktcap"), names(R))
say("  수익 컬럼=%s · size 컬럼=%s", rcol, if (length(scol)) scol[1] else "(없음 — usize 파일 사용)")
if (!length(scol)) {
  US <- as.data.table(read_parquet(pin$usize)); US[, Date := as.Date(Date)]
  say("  usize %d행 · 컬럼 %s", nrow(US), paste(names(US), collapse=","))
  sc <- intersect(c("Size","size","mktcap"), names(US))[1]
  R <- merge(R, US[, c("Date","Ticker", sc), with=FALSE], by = c("Date","Ticker"), all.x = TRUE)
  scol <- sc
}
setnames(R, rcol, "ret_1m"); setnames(R, scol[1], "sz")
MS <- R[!is.na(sz) & !is.na(ret_1m), {
  o <- order(-sz); top10 <- head(o, 10L)
  .(mega_spread = mean(ret_1m[top10]) - median(ret_1m))
}, by = Date][order(Date)]
MS[, regime := shift(mega_spread, 1L) <= 0]      # ★t-1
say("  mega_spread %d개월 · 국면 ON %d (%.1f%%) · NA %d",
    nrow(MS), sum(MS$regime, na.rm=TRUE), 100*mean(MS$regime, na.rm=TRUE), sum(is.na(MS$regime)))
say("  ★사전등록 기재 base rate 35.0%% (28/80) — 대조 %.1f%%", 100*mean(MS$regime, na.rm=TRUE))

## ---- 3. SIG / NEU 포트 월수익 ------------------------------------------------
say("=== 3. SIG(계약 신호 top-25) vs NEU(중립 대조) ===")
## ★신호 정의는 **정체 검사로 확정**(p0b): 원 스크립트 diag_fq125_stage1_controls.R:44
##   S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
##   필터 = score > 0 ∧ adv >= 2e8 ∧ member (동상 47행)
##   ⚠내 초판은 수치 컬럼 첫 번째(n_contracts)를 집었는데 **원 스크립트 참조 0회** = 오답이었다.
US <- as.data.table(read_parquet(pin$usize)); US[, Date := as.Date(Date)]
me <- data.table(Date = sort(unique(R$Date)))
me[, ym := as.integer(format(Date, "%Y%m"))]
PA[, ym := as.integer(ym)]
S <- merge(me, PA[, .(ym, Ticker, w_amt)], by = "ym", allow.cartesian = TRUE)
S <- merge(S, US[, .(Date, Ticker, Size)], by = c("Date","Ticker"))
S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
S <- S[is.finite(score) & score > 0, .(Date, Ticker, score)]
say("  ★신호 = w_amt / Size (원 스크립트 정본) · %d행 · %d개월 · 월중앙 %d종목",
    nrow(S), uniqueN(S$Date), as.integer(median(S[, .N, by=Date]$N)))

rt <- R[!is.na(ret_1m), .(Date, Ticker, Ret_1m = ret_1m)]
bd <- BM[, .(Date, BM_Ret = get(setdiff(names(BM), "Date")[1]))]
say("  포트 구성 입력: scores %d행 · ret %d행 · bench %d행", nrow(S), nrow(rt), nrow(bd))

run_port <- function(sc, tag) {
  r <- canonical_screen_bt(sc, rt, bd, top_n = 25L, cost_bps_oneway = 15,
                           run_id = paste0("FQ138_", tag), strategy_id = paste0("FQ138_", tag),
                           diag_dual_basis = FALSE)
  list(pr = as.data.table(r$period_returns), port_t = r$portfolio_alpha_t_nw_lag3,
       n = r$n_months, ir = r$information_ratio)
}
SIG <- run_port(S, "SIG")
set.seed(20260808)
NEU_s <- copy(S)[, score := runif(.N), by = Date]     # 신호 없는 무작위 25종 (사전등록: POOL_EW 또는 무작위)
NEU <- run_port(NEU_s, "NEU")
say("  SIG: %d개월 · PORT_t %+.3f · IR %+.3f", SIG$n, SIG$port_t, SIG$ir)
say("  NEU: %d개월 · PORT_t %+.3f · IR %+.3f", NEU$n, NEU$port_t, NEU$ir)

M <- merge(SIG$pr[, .(date, sig = ret_net - benchmark_ret)],
           NEU$pr[, .(date, neu = ret_net - benchmark_ret)], by = "date")
M[, s := sig - neu]
M <- merge(M, MS[, .(date = Date, regime)], by = "date")
M <- M[!is.na(regime)]
say("  스프레드 계열 %d개월 · 국면 ON %d · s sd %.4f", nrow(M), sum(M$regime), sd(M$s))

## ---- 4. ★1급 = DiD 회귀 (구간추정) ------------------------------------------
hac <- function(y, x, lag = 3L) {
  n <- length(y); X <- cbind(1, as.numeric(x)); b <- solve(crossprod(X), crossprod(X, y))
  e <- as.numeric(y - X %*% b); Xi <- solve(crossprod(X)); Sm <- crossprod(X * e)
  for (l in seq_len(lag)) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE]); Sm <- Sm + w*(G+t(G)) }
  V <- Xi %*% Sm %*% Xi; list(b = as.numeric(b), se = sqrt(diag(V)))
}
f <- hac(M$s, M$regime, 3L)
delta <- f$b[2]; se <- f$se[2]; tt <- delta/se
ci <- delta + c(-1.96, 1.96) * se
say("=== 4. ★1급 판정량 — DiD delta (구간추정) ===")
say("  s_t = a + delta*1{t-1 mega_spread<=0}")
say("  a     = %+.5f/월 (연 %+.2f%%)", f$b[1], f$b[1]*12*100)
say("  ★delta = %+.5f/월 (연 **%+.2f%%**) · NW3 se %.5f · t %+.3f", delta, delta*12*100, se, tt)
say("  ★95%% CI = [%+.5f, %+.5f]/월 = 연 **[%+.2f%%, %+.2f%%]**", ci[1], ci[2], ci[1]*12*100, ci[2]*12*100)
say("  사전등록 required_effect(interaction, 유효 n 18.2) = 연 **27.71%%**")
say("  ⇒ 보고 규칙(사전등록): CI 가 0 포함이면 '구간이 0을 포함' 으로만 서술. '효과 없음' 금지.")
say("     CI 상한 < 연 10%% 일 때만 '실질적 효과 배제' 주장 가능 — 현재 상한 %+.2f%%", ci[2]*12*100)

## ---- 5. 2급 (결과 무관 보고) -------------------------------------------------
say("=== 5. 2급 — 사전등록이 결과 무관 보고를 명시한 항목 ===")
on <- M$regime
say("  SIG_ON 단독 조건부 평균 활성 %+.5f/월 (연 %+.2f%%) · n=%d [원 보고 PORT_t 2.198 재현 확인용]",
    mean(M$sig[on]), mean(M$sig[on])*12*100, sum(on))
say("  ★NEU_ON 단독 조건부 평균 활성 %+.5f/월 (연 %+.2f%%) [순풍 크기 직접 계량]",
    mean(M$neu[on]), mean(M$neu[on])*12*100)
say("  SIG_OFF %+.5f · NEU_OFF %+.5f", mean(M$sig[!on]), mean(M$neu[!on]))
say("  ⇒ NEU_ON 이 SIG_ON 에 근접하면 원 결과는 **순풍**이다(사전등록 명시)")

## ---- 6. ★위반 주입 (위약 셔플) ----------------------------------------------
say("=== 6. ★위반 주입 — 계약 score 월내 셔플 위약 ===")
set.seed(99); pl <- numeric(0)
for (b in 1:20) {
  PS <- copy(S)[, score := sample(score), by = Date]
  P <- run_port(PS, sprintf("PLA%02d", b))
  MM <- merge(P$pr[, .(date, sig = ret_net - benchmark_ret)],
              NEU$pr[, .(date, neu = ret_net - benchmark_ret)], by = "date")
  MM[, s := sig - neu]; MM <- merge(MM, MS[, .(date = Date, regime)], by="date")[!is.na(regime)]
  ff <- hac(MM$s, MM$regime, 3L); pl <- c(pl, ff$b[2]/ff$se[2])
}
say("  위약 20회 DiD t: 중앙 %+.3f · |t|>=2 비율 %.2f · 최대 %+.3f",
    median(pl), mean(abs(pl) >= 2), max(abs(pl)))
say("  ⇒ 위약이 문턱을 넘으면 **파이프라인 결함**(사전등록 명시)")

saveRDS(list(M = M, delta = delta, se = se, t = tt, ci = ci, SIG = SIG, NEU = NEU, placebo = pl),
        file.path(OUT, "p1.rds"))
fwrite(M, file.path(OUT, "p1_spread.csv"))
say("=== P1 완료 ===")
