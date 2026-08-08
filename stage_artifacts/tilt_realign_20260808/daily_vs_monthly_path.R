# daily_vs_monthly_path.R — 일간 경로(_v2 트리오) vs 월간 경로(.tilt) vs 정본 실측 대조
# 질문: 결함이 "하나가 복제된 것"인가, "서로 다른 둘"인가?
#   월간 = 02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R 의 .tilt/.norm (실행체)
#   일간 = 04_Research/strategies/STR_1715_.../forward_weights.R 의 _v2 트리오
#          (daily_refresh.sh → forward_weights_orchestrator.R:32-37)
#   정본 = strategy_tilt_weights.R::linear_tilt_to_penalty_qd
# 동일 alpha 입력(2026-08-01)에 세 규칙을 적용해 비중 차이를 잰다.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
AS_OF <- as.Date("2026-08-01"); TOPN<-20L; MINN<-15L; LIQ<-2e8; LAM<-1.5; UB<-0.20; UBCR<-0.10; PHI<-3

## --- 일간 경로의 _v2 트리오를 실파일에서 추출 (재구현 금지 — 실제 코드를 쓴다) ---
denv <- new.env()
dsrc <- "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/forward_weights.R"
stopifnot(file.exists(dsrc))
suppressMessages(sys.source(dsrc, envir = denv))
for (f in c(".normalize_long_only_v2", ".linear_tilt_qd_v2", ".linear_tilt_to_penalty_qd_v2"))
  stopifnot(exists(f, envir = denv, inherits = FALSE))
cat("[daily] _v2 트리오 추출 완료 (실파일 sys.source)\n")

## --- 월간 실행체의 .tilt/.norm 을 실파일에서 추출 ---
menv <- new.env()
msrc <- "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R"
stopifnot(file.exists(msrc))
ml <- readLines(msrc, warn = FALSE)
ml_fn <- grep("^\\.(norm|tilt) <- function", ml)
stopifnot(length(ml_fn) == 2L)
menv$UB <- UB; menv$LAMBDA <- LAM
eval(parse(text = ml[ml_fn]), envir = menv)
cat(sprintf("[monthly] .norm/.tilt 추출 완료 (실행체 %s:%s)\n", basename(msrc), paste(ml_fn, collapse=",")))

## --- 동일 alpha 입력 구성 ---
ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[, Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]
panel <- ap[Date==AS_OF & !is.na(score_eff)]; REGIME <- panel$regime_state[1L]
setorder(panel, -score_eff)
N <- min(TOPN, nrow(panel)); if (N < MINN && nrow(panel) >= MINN) N <- MINN
a_can <- setNames(panel[seq_len(N)]$score_eff, panel[seq_len(N)]$Ticker)
sd_ <- min(raw[Date>=AS_OF]$Date)
liq <- raw[Date>=sd_-30L & Date<sd_, .(ADV=mean(TV,na.rm=TRUE)), by=Ticker][ADV>=LIQ, Ticker]
tk <- intersect(names(a_can), liq); if (length(tk)<5L) tk <- names(a_can)
a <- a_can[tk]
cat(sprintf("[input] AS_OF=%s regime=%s | 종목 %d\n", AS_OF, REGIME, length(a)))

## --- 세 규칙 적용 ---
w_daily <- denv$.linear_tilt_to_penalty_qd_v2(a, lambda=LAM, w_prev=NULL, phi=PHI, lb=0, ub=UB)  # 일간 호출부와 동일(w_prev=NULL 하드코딩, forward_weights.R:124-126)
names(w_daily) <- names(a)
w_month <- menv$.tilt(a)                                          # 월간 실행체
names(w_month) <- names(a)
ub_can <- if (identical(REGIME,"CRISIS")) min(UB,UBCR) else UB
w_canon <- normalize_long_only(linear_tilt_to_penalty_qd(a, lambda=LAM, w_prev=NULL, phi=PHI, lb=0, ub=ub_can), lb=0, ub=ub_can, target_sum=1)
names(w_canon) <- names(a)

cmp <- function(l1, w1, l2, w2) {
  u <- union(names(w1), names(w2))
  x <- setNames(rep(0,length(u)),u); x[names(w1)] <- w1
  y <- setNames(rep(0,length(u)),u); y[names(w2)] <- w2
  cat(sprintf("  %-28s vs %-28s : max|dw|=%.3e  괴리=%.4f (%.1f%%)  Σ %.6f / %.6f\n",
              l1, l2, max(abs(x-y)), 0.5*sum(abs(x-y)), 0.5*sum(abs(x-y))*100, sum(w1), sum(w2)))
  invisible(max(abs(x-y)))
}
cat("\n[대조]\n")
d_dm <- cmp("일간 _v2", w_daily, "월간 .tilt", w_month)
cmp("일간 _v2", w_daily, "정본", w_canon)
cmp("월간 .tilt", w_month, "정본", w_canon)

cat(sprintf("\n[판정] 일간 vs 월간 max|dw| = %.3e → %s\n", d_dm,
  if (d_dm < 1e-12) "동일 결함의 복제 (독립 변형 아님)" else "서로 다른 두 결함 — 각각 수리 필요"))
cat(sprintf("[Σw 보존] 일간 %.8f / 월간 %.8f / 정본 %.8f  (1 미만이면 캡 포화 시 합 미보장 결함 발현)\n",
            sum(w_daily), sum(w_month), sum(w_canon)))
cat(sprintf("[active 종목] 일간 %d / 월간 %d / 정본 %d\n", sum(w_daily>1e-9), sum(w_month>1e-9), sum(w_canon>1e-9)))
cat(sprintf("[max 비중] 일간 %.4f / 월간 %.4f / 정본 %.4f (CRISIS cap %.2f)\n",
            max(w_daily), max(w_month), max(w_canon), UBCR))
cat("\n[φ 실효성] 일간 호출부는 w_prev=NULL 하드코딩(forward_weights.R:124-126) → phi=3 을 넘겨도 블렌드 미실행.\n")
cat("           즉 '선언된 φ' 가 두 경로 모두에서 죽어 있다(월간=미사용 상수, 일간=w_prev NULL).\n")
