## p2 — ★FQ-191 계약 신호에 직접 적용해 내 판독 오류를 확정 수치로 고정
## p1 결론: EW-basis = 상수 mean 불이익(-0.13t) + se 배율(x1.37). '핸디캡 제거' 아님.
## 확인 명제: FQ-191 의 EW 2.966 은 배율기 산물인가?
##   예측: 2.204 x (1/se비율) - 0.13 ≈ 2.966 이면 배율기로 전량 설명된다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/ladder_sweep")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")

nw <- function(a) { a <- a[is.finite(a)]; f <- lm(a ~ 1)
  s <- sqrt(NeweyWest(f, lag=3, prewhite=FALSE, adjust=TRUE)[1,1]); c(mean(a), s, mean(a)/s) }

B <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
S <- S[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]
M <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
M <- M[date < as.Date("2026-01-01")]
say("=== 입력 실측 === 신호 %d행 · 규칙 %d개월 · 국면 ON %d", nrow(S), nrow(M), sum(M$regime))

## 국면-조건부 규칙 계열 (FQ-191 정본 재현) — 두 벤치 각각
build <- function(cost) {
  r <- suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=cost,
        run_id="C", strategy_id="C", size_dt=US[,.(Date,Ticker,Size)]))
  PR <- as.data.table(r$period_returns)[, .(date, ret_net)]
  PR <- merge(PR, bd[, .(date=Date, bm_c=BM_Ret)], by="date")
  POOL <- merge(S[,.(Date,Ticker)], rt, by=c("Date","Ticker"))[, .(bm_e=mean(Ret_1m,na.rm=TRUE)), by=Date]
  PR <- merge(PR, POOL[,.(date=Date,bm_e)], by="date")
  X <- merge(PR, M[,.(date, regime)], by="date")
  X[, sw := c(0L, abs(diff(as.integer(regime))))]
  ## 규칙: ON 이면 전략, OFF 면 벤치 보유 — 벤치 basis 마다 '보유 대상' 도 함께 바뀐다
  X[, r_c := ifelse(regime, ret_net, bm_c) - sw*cost/1e4]
  X[, r_e := ifelse(regime, ret_net, bm_e) - sw*cost/1e4]
  X
}
X15 <- build(15); X0 <- build(0)
a_net <- nw(X15$r_c - X15$bm_c); a_gr <- nw(X0$r_c - X0$bm_c); a_ew <- nw(X0$r_e - X0$bm_e)
say("=== ★FQ-191 사다리 재현 + 분해 ===")
say("  net 15bps cap-w : mean %+.5f · se %.5f · t %+.3f", a_net[1], a_net[2], a_net[3])
say("  gross    cap-w  : mean %+.5f · se %.5f · t %+.3f", a_gr[1],  a_gr[2],  a_gr[3])
say("  gross    EW     : mean %+.5f · se %.5f · t %+.3f", a_ew[1],  a_ew[2],  a_ew[3])
say("  ---")
say("  ★se 비율 EW/capw = %.3f  → 배율 x%.3f", a_ew[2]/a_gr[2], a_gr[2]/a_ew[2])
say("  ★mean 이동       = %+.5f/월 (연 %+.2f%%) → t 기여 %+.3f",
    a_ew[1]-a_gr[1], (a_ew[1]-a_gr[1])*12*100, (a_ew[1]-a_gr[1])/a_gr[2])
say("  ★se 축소 기여    = %+.3f", a_ew[1]/a_ew[2] - a_ew[1]/a_gr[2])
say("  ⇒ 배율기만으로 예측한 값: %.3f x %.3f %+.3f = **%.3f** (실측 %.3f)",
    a_gr[3], a_gr[2]/a_ew[2], (a_ew[1]-a_gr[1])/a_gr[2],
    a_gr[3]*(a_gr[2]/a_ew[2]) + (a_ew[1]-a_gr[1])/a_gr[2]*(a_gr[2]/a_ew[2]), a_ew[3])

say("=== ★정정 판정 ===")
mag <- a_gr[2]/a_ew[2]
say("  내가 오늘 쓴 문장: '갭 0.746 중 0.762 를 비-신호 채널이 설명(102%%) — 제거하면 2.966 > 2.95 첫 통과'")
say("  실제: 벤치 채널의 정체는 **자 바꾸기**다.")
say("    - mean 채널: %+.3f t (%s — EW 벤치가 cap-w 보다 %s)",
    (a_ew[1]-a_gr[1])/a_gr[2],
    if ((a_ew[1]-a_gr[1]) < 0) "불리" else "유리",
    if ((a_ew[1]-a_gr[1]) < 0) "높다" else "낮다")
say("    - se 채널: x%.3f 배율 (부호 무관 확대 — 음수 재료 5종이 더 음수가 된 것이 증거)", mag)
say("  ⇒ ★**'제거하면 문턱을 넘는다' 는 성립하지 않는다.** 자본 자격에 대한 정보 0.")
say("  ⇒ H3(오버레이 라우팅) 판정 자체는 불변 — 애초에 cap-w 로 내렸다.")
say("     바뀌는 것은 **왜 미달인지의 설명**이다: 신호가 벤치 핸디캡에 가려진 게 아니라, 미달이 맞다.")

## 남는 진짜 채널 = 비용
say("=== ★남는 진짜 채널: 비용 ===")
say("  net %+.3f → gross %+.3f (Δ %+.3f) · mean 이동 %+.5f/월 (연 %+.2f%%)",
    a_net[3], a_gr[3], a_gr[3]-a_net[3], a_gr[1]-a_net[1], (a_gr[1]-a_net[1])*12*100)
say("  ⚠비용은 고정 축(15bps Production Constraints) — 반사실일 뿐 자본 주장 불가. 이건 원래 맞게 썼다.")
say("  ⇒ 갭 %.3f 중 비용이 설명하는 몫 = %.0f%% (나머지는 신호 부족)",
    2.95-a_net[3], 100*(a_gr[3]-a_net[3])/(2.95-a_net[3]))

saveRDS(list(net=a_net, gross=a_gr, ew=a_ew, mag=mag), file.path(OUT,"p2.rds"))
say("=== 완료 ===")
