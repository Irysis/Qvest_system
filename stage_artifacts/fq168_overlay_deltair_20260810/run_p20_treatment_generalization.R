## P20 — 명제가 **처리-무관**인가: D03 밴드에서도 같은 부호 관계인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  명제: **선별 오버레이는 base 의 선호를 되돌린다** — base 가 자를 대상을 이미 많이 담을수록 Δ 나쁨.
##  reversal 처리에서 확인(P15 4점). ⇒ **다른 처리(FQ-170 의 D03 밴드)** 에서도 서는가.
##  ★D03 밴드의 '자를 대상' 은 없다(밴드는 **채우는** 연산). 대응 개념 = **base 가 밴드 구역(q3~4)을
##    이미 담는 비중** — 많이 담을수록 밴드가 새로 넣을 게 없고, base 순위를 되돌리는 효과만 남는다.
##    ⇒ 예측: **band_share 높을수록 Δ 나쁨**(reversal 의 q1 과 같은 방향).
##  ★1급 = **극단 대조**(상위3 vs 하위3의 Δ). 오늘 계열-간 상관은 5회 미달했고 4점 대조가 답을 냈다.
##  ★2급(참고) = 20 base 상관 — 해상도 아래일 것으로 예상되므로 **판정에 쓰지 않는다**.
##  ★강한 검정점: **CORE4_EW 는 P12a 에서 유일한 음수 Δ(-0.381)** ⇒ band_share 가 높아야 한다.
##  판정:
##   Q1_GENERALIZES      : 상위3 평균 Δ < 하위3 평균 Δ ∧ CORE4 가 상위군
##   Q2_PARTIAL          : 방향은 맞으나 CORE4 가 상위군이 아님
##   Q3_TREATMENT_SPECIFIC: 분리 없음 → reversal 특유, 계약에 처리별 열 필요
##  ★자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

## P12a 의 밴드 Δ (정체 정의 20 합성)
D12 <- fread(file.path(OUT, "../fq170_band_cost_20260809/p12a_strong.csv"))
cat(sprintf("[P12a] 합성 %d · Δ 범위 %.3f~%.3f\n", nrow(D12), min(D12$delta), max(D12$delta)))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
NET <- fread(file.path(OUT, "../fq170_band_cost_20260809/p11c_net.csv"))
CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
need <- unique(c(NET$base, CORE4)); ds <- sort(unique(B$Date)); acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=need), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]; if (!nrow(z)) next
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
FD <- rbindlist(acc, fill=TRUE)
U <- merge(B[, .(Date,Ticker,D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]; U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, FD, by=c("Date","Ticker"), all.x=TRUE)
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
U[, in_band := q %in% 3:4]
zs <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s==0) rep(0,length(x)) else (x-m)/s}
fam_of <- function(x){f<-sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f)}
NET[, fam := fam_of(base)]
comps <- list()
for (f in unique(NET$fam)) { mem <- intersect(NET[fam==f, base], names(U)); if (length(mem)) comps[[paste0("FAM_",f)]] <- mem }
h4 <- intersect(CORE4, names(U)); if (length(h4)==4L) comps[["CORE4_EW"]] <- h4
rows <- list()
for (nm in names(comps)) {
  U[, .tmp := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=comps[[nm]]]
  D <- U[is.finite(.tmp) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  D[, rk := frank(-.tmp, ties.method="first"), by=Date]
  H <- D[rk <= 25L]
  U[, .tmp := NULL]
  if (uniqueN(H$Date) < 100L) next
  S <- H[, .(share = mean(in_band)), by=Date]
  rows[[length(rows)+1L]] <- data.table(base=nm, n=nrow(S), band_share=round(mean(S$share),4))
}
R <- rbindlist(rows, fill=TRUE)
R <- merge(R, D12[, .(base, delta, t_nb)], by="base")
R <- R[order(-band_share)]
cat(sprintf("\n=== base 별 밴드 구역 보유 비중 vs 밴드 Δ (n=%d) ===\n", nrow(R)))
print(R[, .(base, band_share, delta, t_nb)])
hi <- head(R, 3); lo <- tail(R, 3)
cat(sprintf("\n★상위3(share 높음) Δ 평균 **%+.3f** : %s\n", mean(hi$delta), paste(hi$base, collapse=", ")))
cat(sprintf("★하위3(share 낮음) Δ 평균 **%+.3f** : %s\n", mean(lo$delta), paste(lo$base, collapse=", ")))
core_in_hi <- "CORE4_EW" %in% hi$base
core_rank <- which(R$base == "CORE4_EW")
cat(sprintf("CORE4_EW(유일 음수 Δ -0.381) 순위 = **%d / %d** (share %.4f) · 상위3 포함 %s\n",
            core_rank, nrow(R), R[base=="CORE4_EW", band_share], core_in_hi))
sep <- mean(hi$delta) < mean(lo$delta)
verdict <- if (sep && core_in_hi) "Q1_GENERALIZES" else if (sep) "Q2_PARTIAL" else "Q3_TREATMENT_SPECIFIC"
cat(sprintf("\n판정: %s\n", verdict))
rho <- suppressWarnings(cor(R$band_share, R$delta, method="spearman"))
cat(sprintf("[2급·판정 아님] spearman(share, Δ) = %+.3f (n=%d) — 계열-간 상관은 오늘 5회 미달\n", rho, nrow(R)))
if (verdict == "Q3_TREATMENT_SPECIFIC")
  cat("=> reversal 특유 — `overlay_precheck` 표에 **처리별 열**이 필요하다(스키마에 treatment 필드 있음)\n")
fwrite(R, file.path(OUT,"p20_band_share.csv"))
write_json(list(verdict=verdict, n=nrow(R), hi_mean=mean(hi$delta), lo_mean=mean(lo$delta),
                core4_rank=core_rank, core4_in_hi=core_in_hi, rho_secondary=rho, results=R),
           file.path(OUT,"p20_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
