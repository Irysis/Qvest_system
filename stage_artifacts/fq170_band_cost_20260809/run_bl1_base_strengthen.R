## BL1 — base 쪽 강화: M26 이 MONOTONE 부차(0.157)라면 계열 내 결합 여지가 실재한다
## 사전등록(측정 전 고정, 이 주석이 정본):
##  이 아크는 20+ 라운드 내내 **신호 쪽(필터/밴드)만** 팠고 base(M26 top-25)는 고정으로 뒀다.
##  BJ1: M26~MONOTONE PC1 = 0.157(부차) · M01 = 0.958(지배축).
##  ⇒ MONOTONE 계열의 **부차군**(지배축 M01 및 그와 |rho|>=0.7 인 것 제외)을 M26 과 등가중 합성해
##     base 를 만들고, 절대 basis(canonical_screen_bt) PORT_t 가 M26 단독 1.292 를 넘는지 본다.
##  arm: (1) M26 단독(기준) (2) M26 + 부차군 EW-Z 합성 (3) MONOTONE 전체 EW-Z 합성(참고, 지배축 포함)
##   BM1 base 강화 유효: (2) 가 (1) 보다 PORT_t 유의 개선(>= +0.3) → 새 레버
##   BM2 무효: 개선 < 0.3 → base 쪽도 닫힘, 잔여는 비-return 하나
##  ★합성은 Z 평균(자체합성 금지 대상 아님 — 신호 합성이지 수익률 합성 아님). 판정은 계약 경로.
##  BM3 자본 자격 주장은 PORT_t>=2.95 시에만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
MON <- S[shape == "MONOTONE_TOP"]$Factor_Name
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
ds <- sort(unique(B[!is.na(M26_Revenue_Mom)]$Date))
cat(sprintf("[표본] %d개월\n", length(ds)))

# 부차군 = MONOTONE 중 M01_PATHQ 계열(지배축) 제외. 지배축 대리 = census 상 M01 과 가장 닮은 DB 팩터를
# 찾는 대신, 보수적으로 **M01/M02 접두 모멘텀 계열**을 제외한다(사전 규칙).
SEC <- grep("^M0[12]", MON, value=TRUE, invert=TRUE)
cat(sprintf("[MONOTONE %d종] 부차군 %d종: %s\n", length(MON), length(SEC), paste(head(SEC,10), collapse=", ")))

## ★R 함정: for (dt in ds) 는 **Date 클래스를 벗겨** 숫자를 준다.
##  as.character(dt) 가 "17532" 가 되어 as.Date() 가 실패한다. 인덱스 순회로 고정.
Z <- list(); Zd <- as.Date(character(0))
for (i in seq_along(ds)) {
  dt <- ds[i]
  z <- try(load_month_factors(dt, factor_names = MON), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  Z[[format(dt, "%Y-%m-%d")]] <- z; Zd <- c(Zd, dt)
}
cat(sprintf("[팩터 로드] %d개월\n", length(Z)))

mk <- function(mode) {
  out <- list()
  for (k in names(Z)) {
    dt <- as.Date(k)
    z <- Z[[k]]
    my <- B[Date == dt & !is.na(M26_Revenue_Mom), .(Ticker, m26 = M26_Revenue_Mom)]
    if (mode == "m26") { out[[k]] <- my[, .(Date=dt, Ticker, score=m26)]; next }
    fs <- if (mode == "sec") SEC else MON
    a <- z[Factor_Name %in% fs, .(zc = mean(Z_Score_Aligned)), by = Ticker]
    m <- merge(my, a, by="Ticker", all = TRUE)
    m[is.na(m26), m26 := 0]; m[is.na(zc), zc := 0]
    # Z 평균 합성 (신호 합성 — 수익률 자체합성 아님)
    m[, sc := (scale(m26)[,1] + scale(zc)[,1]) / 2]
    out[[k]] <- m[, .(Date=dt, Ticker, score=sc)]
  }
  rbindlist(out)
}
rows <- list()
for (mode in c("m26","sec","all")) {
  Sc <- mk(mode)
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench,
        top_n=25L, cost_bps_oneway=15, liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8,
        run_id=paste0("BL1_",mode), strategy_id=paste0("BL1_",mode)), silent=TRUE)
  if (inherits(r,"try-error")) { cat(sprintf("%s 실패: %s\n", mode, conditionMessage(attr(r,"condition")))); next }
  rows[[length(rows)+1L]] <- data.table(arm=mode, n=r$n_months,
    PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), IR=round(r$information_ratio,3),
    alpha_ann=round(r$alpha_annualized*100,3), turn=round(r$turnover_annual,2))
}
R <- rbindlist(rows); print(R[])
b <- R[arm=="m26", PORT_t]; s <- R[arm=="sec", PORT_t]
cat(sprintf("\n기준(M26 단독) %.3f → 부차군 합성 %.3f · 개선 %+.3f\n", b, s, s-b))
verdict <- { if (is.na(s)) "BM_UNDEF" else if (s >= 2.95) "BM1_CAPITAL_CANDIDATE"
             else if (s - b >= 0.30) "BM1_BASE_STRENGTHEN_WORKS" else "BM2_BASE_CLOSED" }
cat(sprintf("판정: %s\n★BM3: 자본 자격 주장은 PORT_t>=2.95 시에만\n", verdict))
fwrite(R, file.path(OUT,"bl1_base.csv"))
write_json(list(verdict=verdict, base_t=b, sec_t=s, results=R, n_sec=length(SEC)),
           file.path(OUT,"bl1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
