## BN1 — BL1 재시행 (유니버스 선-제한 + 양성 대조 우선)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BL1 무효 원인 = 팩터 DB 전역에 점수를 줘 커버리지 60.1%. 수리 = **merged_panel 유니버스로 선-제한**.
##  ★판정 순서 고정: ①양성 대조 먼저 — m26 단독이 **1.292**(BN3 재확인 정본, 266개월)를 재현해야 한다.
##    미재현 시 대비 arm 을 **읽지 않고** 중단한다(BL1 에서 내가 저지른 실수의 직접 수리).
##   ②재현되면 MONOTONE 부차군(M0[12] 접두 제외) 합성 base 를 측정.
##   BP1 강화 유효: 부차군 base PORT_t - 1.292 >= +0.30
##   BP2 무효: 미달 → base 쪽 닫힘, 잔여는 비-return 하나
##   BP0 중단: 양성 대조 미재현(|차이| > 0.05)
##  ★커버리지를 산출물에 **명시 기록**(BO1 규약 후보의 첫 적용).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
MON <- S[shape == "MONOTONE_TOP"]$Factor_Name
SEC <- grep("^M0[12]", MON, value=TRUE, invert=TRUE)
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))

## ★유니버스 = AI1 과 동일 구성(merged_panel ∩ 수익 ∩ adv ∩ nmo>=125)
U <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
cat(sprintf("[유니버스] %d행 · %d개월 (AI1 과 동일 구성)\n", nrow(U), uniqueN(U$Date)))

run <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L,
        cost_bps_oneway=15, liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8,
        run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  data.table(arm=lab, n=r$n_months, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), IR=round(r$information_ratio,3),
             alpha_ann=round(r$alpha_annualized*100,3))
}
## ① 양성 대조
a <- run(U[, .(Date, Ticker, score = M26_Revenue_Mom)], "m26_solo")
print(a)
if (is.null(a) || abs(a$PORT_t - 1.292) > 0.05) {
  cat(sprintf("\n★BP0 중단 — 양성 대조 미재현 (%.3f vs 정본 1.292)\n", if(is.null(a)) NA else a$PORT_t))
  cat("  대비 arm 을 읽지 않는다(BL1 실수의 직접 수리)\n")
  write_json(list(verdict="BP0_POSITIVE_CONTROL_FAILED", m26=a),
             file.path(OUT,"bn1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(status=0)
}
cat(sprintf("\n★양성 대조 통과 (%.3f ≈ 1.292) — 대비 arm 진행\n\n", a$PORT_t))

## ② 부차군 합성 base
ds <- sort(unique(U$Date)); acc <- list()
for (i in seq_along(ds)) {
  dt <- ds[i]
  z <- try(load_month_factors(dt, factor_names = SEC), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned), .(zc = mean(Z_Score_Aligned)), by=Ticker]
  m <- merge(U[Date == dt, .(Ticker, m26 = M26_Revenue_Mom)], z, by="Ticker", all.x=TRUE)
  m[is.na(zc), zc := 0]
  m[, score := (scale(m26)[,1] + scale(zc)[,1])/2]
  acc[[length(acc)+1L]] <- m[, .(Date=dt, Ticker, score)]
}
b <- run(rbindlist(acc), "m26_plus_secondary")
print(b)
R <- rbindlist(list(a,b))
d <- b$PORT_t - a$PORT_t
cat(sprintf("\n기준 %.3f → 부차군 합성 %.3f · 개선 %+.3f (커버리지 %.4f / %.4f)\n",
            a$PORT_t, b$PORT_t, d, a$coverage, b$coverage))
verdict <- { if (b$coverage < 0.95) "BP_INVALID_COVERAGE"
             else if (d >= 0.30) "BP1_BASE_STRENGTHEN_WORKS" else "BP2_BASE_CLOSED" }
cat(sprintf("판정: %s\n★자본 자격 주장은 PORT_t>=2.95 시에만\n", verdict))
fwrite(R, file.path(OUT,"bn1_base_retry.csv"))
write_json(list(verdict=verdict, delta=d, results=R, n_sec=length(SEC)),
           file.path(OUT,"bn1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
