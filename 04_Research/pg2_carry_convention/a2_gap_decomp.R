## A2 목표-갭 구조 분해 — 진단용 (read-only, 산출물 미등록)
## book = STR_1715_on_M4_R05_noLayer4_PG2 recon (WT-D20260702_002 정의 재현)
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
COST <- 0.0015

p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
dR05 <- abs(p$beta_R05 - shift(p$beta_R05,1,fill=1.0))
p[, ret_noL4 := beta_R05*m4*ret_orig - dR05*COST]
p[, invested := beta_R05*m4]
p[, cashfrac := 1 - invested]

## ---- ① invested fraction 분포 ----
cat("== [1] invested fraction (beta_R05*m4), 269m ==\n")
q <- quantile(p$invested, c(0,.05,.25,.5,.75,.95,1))
cat(sprintf("mean=%.4f | q0=%.3f q5=%.3f q25=%.3f med=%.3f q75=%.3f q95=%.3f max=%.3f\n",
    mean(p$invested), q[1],q[2],q[3],q[4],q[5],q[6],q[7]))
cat(sprintf("full-invested(=1) months: %d (%.1f%%) | invested<0.5: %d (%.1f%%) | <0.25: %d\n",
    sum(p$invested==1), 100*mean(p$invested==1), sum(p$invested<0.5), 100*mean(p$invested<0.5), sum(p$invested<0.25)))
cat(sprintf("mean cash fraction = %.4f (연평균 현금비중)\n", mean(p$cashfrac)))
print(p[, .(n=.N, mean_inv=round(mean(invested),3), mean_ret_orig=round(mean(ret_orig),4)), by=regime])
p[, yr := substr(realized_ym,1,4)]
print(p[, .(mean_inv=round(mean(invested),3)), by=yr][order(yr)])

## ---- 기준선 재현 검증 (judge 확정값 대조) ----
x0 <- xts(p$ret_noL4, order.by=p$anchor_date)
sr_arith <- function(r) mean(r)/sd(r)*sqrt(12)
geo <- function(x) as.numeric(table.AnnualizedReturns(x, scale=12)[3,1])
cagr <- function(r){ n<-length(r); (prod(1+r))^(12/n)-1 }  # 진단용(계약값과 대조만)
mdd <- function(x) as.numeric(maxDrawdown(x))
cat("\n== [check] baseline vs judge ==\n")
cat(sprintf("SR_arith=%.4f (계약 1.7042) | SR_geo=%.4f (judge 1.898) | CAGR=%.4f (0.4522) | MDD=%.4f (0.2329)\n",
    sr_arith(p$ret_noL4), geo(x0), cagr(p$ret_noL4), mdd(x0)))

## ---- ② 유휴현금 캐리 (CD91, PIT: anchor_date 기준 last-known) ----
b <- as.data.table(read_parquet(file.path(ROOT,".cache/ecos_bond_rates.parquet")))
b[, Date := as.Date(Date)]
cd <- b[Series=="KR_CD91"][order(Date)]
call1 <- b[Series=="KR_Call1D"][order(Date)]
lastknown <- function(tbl, d) { v <- tbl[Date <= d, Value]; if(length(v)) tail(v,1) else NA_real_ }
p[, rf_cd    := sapply(anchor_date, function(d) lastknown(cd, d))]
p[, rf_call  := sapply(anchor_date, function(d) lastknown(call1, d))]
p[, rf_used  := ifelse(is.na(rf_cd), rf_call, rf_cd)]          # CD91 없으면(2005-08 이전) Call1D
p[, rf_m := rf_used/100/12]
cat(sprintf("\n== [2] cash carry == CD91 결측 개월(Call1D 대체): %d / rf_m mean=%.4f%% (연 %.2f%%)\n",
    sum(is.na(p$rf_cd)), 100*mean(p$rf_m), mean(p$rf_used)))
p[, ret_carry := ret_noL4 + cashfrac*rf_m]
xc <- xts(p$ret_carry, order.by=p$anchor_date)
## 가중 평균 캐리 기여 (연율)
carry_ann <- mean(p$cashfrac*p$rf_m)*12
cat(sprintf("carry 기여(산술, 연율) = %.4f%%p | mean(cashfrac)=%.3f x mean rf=%.2f%%\n", 100*carry_ann, mean(p$cashfrac), mean(p$rf_used)))
cat(sprintf("BASE : SR_arith %.4f | SR_geo %.4f | CAGR %.4f | MDD %.4f | Calmar %.4f\n",
    sr_arith(p$ret_noL4), geo(x0), cagr(p$ret_noL4), mdd(x0), cagr(p$ret_noL4)/mdd(x0)))
cat(sprintf("CARRY: SR_arith %.4f | SR_geo %.4f | CAGR %.4f | MDD %.4f | Calmar %.4f\n",
    sr_arith(p$ret_carry), geo(xc), cagr(p$ret_carry), mdd(xc), cagr(p$ret_carry)/mdd(xc)))
cat(sprintf("DELTA: dSR_arith %+.4f | dSR_geo %+.4f | dCAGR %+.4f | dMDD %+.4f\n",
    sr_arith(p$ret_carry)-sr_arith(p$ret_noL4), geo(xc)-geo(x0),
    cagr(p$ret_carry)-cagr(p$ret_noL4), mdd(xc)-mdd(x0)))
## excess basis (ER = ret - rf_m 전액): 양 basis 병기
er0 <- p$ret_noL4 - p$rf_m; erc <- p$ret_carry - p$rf_m
cat(sprintf("EXCESS-basis SR: base %.4f -> carry %.4f (d %+.4f)\n", sr_arith(er0), sr_arith(erc), sr_arith(erc)-sr_arith(er0)))
## 서브기간
sub <- function(r, d, from, to=NULL){ i <- d>=as.Date(from) & (if(is.null(to)) TRUE else d<=as.Date(to)); r[i] }
d <- p$anchor_date
for (nm in list(c("2004-02-01","2016-12-31","pre2017"), c("2017-01-01","2026-12-31","post2017"))) {
  r0 <- sub(p$ret_noL4,d,nm[1],nm[2]); rc <- sub(p$ret_carry,d,nm[1],nm[2])
  x0s <- xts(r0, order.by=d[d>=as.Date(nm[1])&d<=as.Date(nm[2])])
  cat(sprintf("[%s] n=%d BASE SR_a %.3f CAGR %.3f MDD %.3f | CARRY SR_a %.3f (d %+.3f) CAGR %.3f\n",
      nm[3], length(r0), sr_arith(r0), cagr(r0), mdd(x0s), sr_arith(rc), sr_arith(rc)-sr_arith(r0), cagr(rc)))
}
r0 <- tail(p$ret_noL4,60); rc <- tail(p$ret_carry,60)
cat(sprintf("[last60m] BASE SR_a %.3f CAGR %.3f | CARRY SR_a %.3f (d %+.3f) CAGR %.3f (d %+.4f)\n",
    sr_arith(r0), cagr(r0), sr_arith(rc), sr_arith(rc)-sr_arith(r0), cagr(rc), cagr(rc)-cagr(r0)))

## ---- ③ 총수익 vs active + overlay 구조 ----
cat("\n== [3] 총수익 vs overlay 분해 ==\n")
xn <- xts(p$ret_orig, order.by=p$anchor_date)   # naked (overlay 없음, 비용동일가정 밖 — ret_orig 자체 net)
cat(sprintf("NAKED(ret_orig): SR_a %.4f | SR_geo %.4f | CAGR %.4f | MDD %.4f\n",
    sr_arith(p$ret_orig), geo(xn), cagr(p$ret_orig), mdd(xn)))
cat(sprintf("overlay drag(산술 mean): naked %.4f -> noL4 %.4f (d %+.4f/m = %+.2f%%p/yr)\n",
    mean(p$ret_orig), mean(p$ret_noL4), mean(p$ret_noL4)-mean(p$ret_orig), 12*100*(mean(p$ret_noL4)-mean(p$ret_orig))))
cat(sprintf("overlay 회피/포기 분해: invested<1 구간에서 ret_orig<0 회피분 %.4f/m, ret_orig>0 포기분 %.4f/m\n",
    mean(pmax(-p$cashfrac*p$ret_orig,0)), mean(pmax(p$cashfrac*p$ret_orig,0))))
## R05 스위칭 비용 실측
cat(sprintf("R05 스위칭 비용(dR05*15bps) 합계 = %.4f (연평균 %.4f%%p)\n", sum(dR05*COST), 100*sum(dR05*COST)/ (269/12)))

## ---- MDD 구조 (noL4 top-5 drawdowns) ----
cat("\n== [MDD 구조] noL4 top-5 ==\n")
dd <- table.Drawdowns(x0, top=5)
print(dd)
ddc <- table.Drawdowns(xc, top=3)
cat("-- carry 적용 시 top-3 --\n"); print(ddc)

fwrite(p[, .(realized_ym, anchor_date, regime, ret_orig, beta_R05, m4, invested, cashfrac, rf_used, rf_m, ret_noL4, ret_carry)],
  "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad/a2_panel_carry.csv")
cat("\n[DONE]\n")
