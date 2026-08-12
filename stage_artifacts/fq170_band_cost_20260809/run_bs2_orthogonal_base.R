## BS2 — D03-직교 부차군으로 base 를 강화하면 결합이 가법으로 돌아오는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BQ1: 강화base x 밴드 상호작용 **-0.801**(대체재). 기전 가설 = 부차군에 저변동 성격이 섞여
##       D03(INVERTED 지배축)과 같은 종목을 향한다.
##  ⇒ 부차군 13종에서 **D03_EWMA 와 |rho|>=0.35 인 것을 제외**(사전 문턱)한 직교군으로 base 를 만든다.
##     2x2 재실행: (1)plain·무밴드 (2)직교강화·무밴드 (3)plain·밴드12 (4)직교강화·밴드12
##   BT1 가법 회복: |상호작용| <= 0.25 ∧ (4) > 2.137 → 직교화가 답. 문턱 접근 재개
##   BT2 여전 중복: 상호작용 <= -0.30 → 겹침은 저변동 성격 탓이 아니다(기전 가설 기각)
##   BT3 직교군 소멸: 제외 후 남는 팩터 < 3 → 부차군은 본래 D03 계열이었다(구조적 답)
##  ★양성 대조 (1)=1.292 · (3)=2.137 재현 필수. 커버리지 전 arm 명시.
##  BT4 자본 자격 주장은 PORT_t>=2.95 시에만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
SEC <- grep("^M0[12]", S[shape=="MONOTONE_TOP"]$Factor_Name, value=TRUE, invert=TRUE)
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
U <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
ds <- sort(unique(U$Date))

## ① 부차군 각 팩터의 D03 상관 census (6개월 샘플)
smp <- ds[seq(1, length(ds), by=6L)]
rr <- data.table(Factor_Name=SEC, s=0, n=0L)
for (i in seq_along(smp)) {
  dt <- smp[i]
  z <- try(load_month_factors(dt, factor_names=SEC), silent=TRUE); if (inherits(z,"try-error")) next
  W <- dcast(as.data.table(z)[!is.na(Z_Score_Aligned)], Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  m <- merge(W, U[Date==dt, .(Ticker, d03=D03_EWMA)], by="Ticker")
  for (f in intersect(SEC, names(m))) {
    v <- suppressWarnings(cor(m[[f]], m$d03, method="spearman", use="complete.obs"))
    if (is.finite(v)) rr[Factor_Name==f, `:=`(s=s+abs(v), n=n+1L)]
  }
}
rr[, rho := ifelse(n>0, s/n, NA_real_)]
print(rr[order(-rho), .(Factor_Name, rho=round(rho,3), n)])
ORTH <- rr[is.finite(rho) & rho < 0.35]$Factor_Name
cat(sprintf("\n[직교군] |rho(D03)| < 0.35 → %d종 / 부차군 %d종\n", length(ORTH), length(SEC)))
if (length(ORTH) < 3L) {
  cat("★BT3 — 직교군 3종 미만. 부차군은 본래 D03 계열이었다(구조적 답)\n")
  write_json(list(verdict="BT3_ORTH_EMPTY", n_orth=length(ORTH), rho=rr),
             file.path(OUT,"bs2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(status=0)
}

## ② 2x2
acc <- list()
for (i in seq_along(ds)) {
  dt <- ds[i]
  z <- try(load_month_factors(dt, factor_names=ORTH), silent=TRUE)
  zc <- if (inherits(z,"try-error")) NULL else
        as.data.table(z)[!is.na(Z_Score_Aligned), .(zc=mean(Z_Score_Aligned)), by=Ticker]
  m <- U[Date==dt, .(Ticker, m26=M26_Revenue_Mom, q)]
  m <- if (is.null(zc)) m[, zc:=0] else merge(m, zc, by="Ticker", all.x=TRUE)[is.na(zc), zc:=0]
  m[, base_plain := scale(m26)[,1]][, base_orth := (scale(m26)[,1]+scale(zc)[,1])/2]
  acc[[length(acc)+1L]] <- m[, .(Date=dt, Ticker, q, base_plain, base_orth)]
}
A <- rbindlist(acc)
mk <- function(bc, band) A[, {
  o <- order(-get(bc)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
  keep <- tk[seq_len(min(25L-band, .N))]
  pool <- tk[qq %in% 3:4 & !(tk %in% keep)]
  sel <- c(keep, head(pool, band))
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000-frank(-.SD[[bc]], ties.method="first"), -1e6))
}, by=Date, .SDcols=c("Ticker","q",bc)]
run <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  data.table(arm=lab, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), alpha_ann=round(r$alpha_annualized*100,3))
}
R <- rbindlist(list(run(mk("base_plain",0L),"1_plain"), run(mk("base_orth",0L),"2_orth"),
                    run(mk("base_plain",12L),"3_plain_band"), run(mk("base_orth",12L),"4_orth_band")))
print(R[])
g <- function(k) R[arm==k, PORT_t]
inter <- g("4_orth_band") - g("2_orth") - g("3_plain_band") + g("1_plain")
cat(sprintf("\n양성대조 (1) %.3f/1.292 · (3) %.3f/2.137\n상호작용 = %+.3f (BQ1 판: -0.801) · 최종 %.3f\n",
            g("1_plain"), g("3_plain_band"), inter, g("4_orth_band")))
ok <- abs(g("1_plain")-1.292)<=0.05 && abs(g("3_plain_band")-2.137)<=0.05
verdict <- { if (!ok) "BT0_POSITIVE_CONTROL_FAILED"
             else if (min(R$coverage)<0.95) "BT_INVALID_COVERAGE"
             else if (abs(inter)<=0.25 && g("4_orth_band")>2.137) "BT1_ADDITIVE_RECOVERED"
             else if (inter<=-0.30) "BT2_STILL_REDUNDANT" else "BT4_PARTIAL" }
cat(sprintf("판정: %s\n", verdict))
fwrite(R, file.path(OUT,"bs2_combine.csv"))
write_json(list(verdict=verdict, interaction=inter, n_orth=length(ORTH), orth=ORTH, results=R),
           file.path(OUT,"bs2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
