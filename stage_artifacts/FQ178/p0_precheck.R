## FQ-178+179 P0 — ★연속 심도가 **실제로** 유효표본을 회복하는가 (착수 자격 판정)
## 혐의: 낙폭 d_t 는 자기상관이 매우 높다. "전 281개월이 변동에 기여" 는 자동이 아니다.
##       d_t 가 4개 에피소드에서만 크게 움직이면 연속화해도 유효 정보는 여전히 ~4 다.
## 이 precheck 가 미달이면 FQ-178 은 착수 전 폐기하고 그 사실이 FQ-180 의 답이 된다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ178")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

W <- readRDS(file.path(ROOT, "stage_artifacts/FQ176/panel_full.rds"))
W <- as.data.table(W)
say("=== 입력 실측 ===")
say("  panel %d행 · %d개월 · %s ~ %s · 관측단위 (월말 Date x Ticker)",
    nrow(W), uniqueN(W$Date), min(W$Date), max(W$Date))
if ("adv" %in% names(W)) { W <- W[is.na(adv) | adv >= 2e8]; say("  유동성필터 후 %d행", nrow(W)) }
say("  월별 종목수 중앙 %.0f", median(W[, .N, by=Date]$N))

P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
B <- as.data.table(P$bench)[!is.na(BM_Ret)][order(Date)]
## BM_Ret[t] 는 t->t+1 forward 이므로 월말 t 시점 **실현** 수익 = shift(BM_Ret,1)
B[, r_realized := shift(BM_Ret, 1L)]
nav <- cumprod(ifelse(is.na(B$r_realized), 0, B$r_realized) + 1)
n <- nrow(B); dd <- rep(NA_real_, n)
for (i in 12:n) dd[i] <- nav[i] / max(nav[(i-11):i]) - 1
B[, dd12 := dd]
say("=== 심도 계열 실측 ===")
say("  dd12 비결측 %d · 범위 %.3f ~ %.3f · 중앙 %.3f", sum(!is.na(B$dd12)),
    min(B$dd12,na.rm=TRUE), max(B$dd12,na.rm=TRUE), median(B$dd12,na.rm=TRUE))

## ★핵심 진단 1: d_t 의 자기상관 — 연속화가 독립 정보를 만드는가
d <- B$dd12[!is.na(B$dd12)]
ac <- acf(d, lag.max = 24, plot = FALSE)$acf[-1]
say("  자기상관: lag1 %.3f · lag3 %.3f · lag6 %.3f · lag12 %.3f · lag24 %.3f",
    ac[1], ac[3], ac[6], ac[12], ac[24])
## 유효표본 근사 (Bartlett): n_eff = n / (1 + 2*sum(rho_k))
pos <- ac[ac > 0]; infl <- 1 + 2*sum(head(pos, 24))
say("  ★유효표본 근사 n_eff = %d / %.2f = **%.1f**  (이분 설계의 에피소드 4개와 대조)",
    length(d), infl, length(d)/infl)

## ★핵심 진단 2: 심도 변동이 4 에피소드에 갇혀 있는가, 전 구간에 퍼져 있는가
B[, era := cut(Date, breaks = as.Date(c("1990-01-01","2003-01-01","2010-01-01","2018-01-01","2027-01-01")),
               labels = c("pre2003","2003-09","2010-17","2018+"))]
print(B[!is.na(dd12), .(n = .N, sd_dd = sd(dd12), min_dd = min(dd12),
                        frac_below_10 = mean(dd12 <= -0.10)), by = era])
say("  ★해석: sd_dd 가 특정 구간에만 크면 연속화해도 정보는 그 구간에 갇힌다.")

## ★핵심 진단 3: 회귀 프레임의 MDE — 이분 대비 실제 개선폭
## 판정량: spread_IC_{t+1} ~ d_t. slope 의 se 는 sd(IC)/ (sd(d)*sqrt(n_eff)) 근사.
FQ <- fread(file.path(ROOT, "stage_artifacts/FQ176/eligible.csv"))
say("=== 합성축 구성 (FQ-179 — family 21 -> 1) ===")
A_cols <- intersect(c("Q02_ROE","Q03_ROA","Q04_Piotroski_F","GR02_Earnings_Growth","GR04_GPA_Growth"), names(W))
V_cols <- intersect(c("V02_EP","V03_CFP","V04_fPER"), names(W))
say("  quality_growth 축: %s", paste(A_cols, collapse=", "))
say("  value 축        : %s", paste(V_cols, collapse=", "))
zs <- function(x) { s <- sd(x, na.rm=TRUE); if (!is.finite(s)||s==0) return(rep(NA_real_, length(x))); (x-mean(x,na.rm=TRUE))/s }
W[, zA := rowMeans(as.data.table(lapply(.SD, zs)), na.rm=TRUE), by = Date, .SDcols = A_cols]
W[, zV := rowMeans(as.data.table(lapply(.SD, zs)), na.rm=TRUE), by = Date, .SDcols = V_cols]
IC <- W[!is.na(Ret_1m), .(icA = suppressWarnings(cor(zA, Ret_1m, method="spearman", use="complete.obs")),
                          icV = suppressWarnings(cor(zV, Ret_1m, method="spearman", use="complete.obs"))), by = Date]
IC <- IC[is.finite(icA) & is.finite(icV)][order(Date)]
IC[, spread := icA - icV]
say("  IC 계열 %d개월 · icA mean %+.4f sd %.4f · icV mean %+.4f sd %.4f · spread mean %+.4f sd %.4f",
    nrow(IC), mean(IC$icA), sd(IC$icA), mean(IC$icV), sd(IC$icV), mean(IC$spread), sd(IC$spread))

M <- merge(IC, B[, .(Date, dd12)], by = "Date")
M[, d_lag := shift(dd12, 1L)]          # 신호 t → IC t+1  (M 은 IC 월 기준이므로 직전월 심도)
M <- M[!is.na(d_lag)]
say("=== MDE 대조 (사전 판정) ===")
n_eff <- nrow(M)/infl
se_slope_naive <- sd(M$spread) / (sd(M$d_lag) * sqrt(nrow(M)))
se_slope_eff   <- sd(M$spread) / (sd(M$d_lag) * sqrt(n_eff))
say("  회귀 n = %d · sd(spread) %.4f · sd(d_lag) %.4f", nrow(M), sd(M$spread), sd(M$d_lag))
say("  slope se: 순진 %.4f (MDE %.4f) · 자기상관 보정 %.4f (MDE %.4f)",
    se_slope_naive, 2*se_slope_naive, se_slope_eff, 2*se_slope_eff)
say("  ★심도 1sd(%.3f) 변화당 필요 spread 변화 = %.4f (보정 기준)", sd(M$d_lag), 2*se_slope_eff*sd(M$d_lag))
say("  ★대조: 이분 설계 MDE(에피소드-클러스터) = 0.168 = 무조건부 IC 4.6배")
say("  ★자격 규칙(사전 고정): 보정 MDE x sd(d_lag) 가 **0.168 보다 작아야** 연속화가 실제 개선이다.")
gain <- 0.168 / (2*se_slope_eff*sd(M$d_lag))
say("  ★개선 배수 = %.2fx  -> %s", gain,
    if (gain > 1.5) "착수 자격 있음" else if (gain > 1.0) "미미한 개선 — 설계 재고" else "★개선 없음 — 착수 전 폐기")

saveRDS(list(IC = IC, M = M, infl = infl, n_eff = n_eff), file.path(OUT, "p0.rds"))
say("=== P0 완료 ===")
