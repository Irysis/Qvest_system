# run_06_align_reuse_test.R — 내 두 측정이 부호 반대로 나온 원인 규명
# run_01: 동결~live rank 상관 **+0.9999** (2026-01 포함)
# run_05: 동결~live rank 상관 **−1.0000** (2026-01)
# 유일한 구조적 차이 = `.load_registry()` 호출 패턴:
#   run_01 은 루프 밖에서 1회 로드해 재사용, run_05 도 1회 재사용 — 그러나 **호출 순서/누적 상태**가 다르다.
# 오늘 p11 에서 `align_factor_direction` 이 **입력 data.table 을 참조 변형**하는 것을 확인했으므로,
# registry 객체도 같은 방식으로 변형될 수 있다 → 재사용 시 정렬 방향이 달라진다는 가설.
# 검증: 같은 달을 ①매번 fresh registry ②한 registry 재사용(반복 호출) 로 각각 정렬해 대조.
suppressMessages({ library(data.table); library(arrow); library(dplyr) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/beta_z_source_20260808"
DD <- as.Date("2026-01-01")

get_raw <- function(dd) {
  f <- as.data.table(load_month_factors(dd, factor_names = "R05_Tail_Risk"))
  if ("Coverage" %in% names(f)) f <- f[Coverage == TRUE]
  f[is.finite(Z_Score)]
}
ali <- function(f, reg, dd) {
  fa <- as.data.table(align_factor_direction(copy(f)[, sig_date := dd], reg, sig_date = dd, min_ic_months = 12L))
  zc <- if ("Z_Score_Aligned" %in% names(fa)) "Z_Score_Aligned" else "Z_Score"
  fa[, .(Ticker, z = get(zc))]
}
f0 <- get_raw(DD)
## ★raw 스냅샷을 **align 호출 이전에** 떠둔다 — align_factor_direction 은 호출부의 copy() 로도
##   보호되지 않는 참조 변형을 하며(실측: 호출 후 입력에서 Z_Score 컬럼이 사라짐), 이 자체가 결함이다.
RAW <- data.table(Ticker = f0$Ticker, z_raw = f0$Z_Score)
cat(sprintf("[입력] %s | %d행 | raw z 평균 %+.4f (스냅샷 확보)\n", DD, nrow(f0), mean(RAW$z_raw)))

## ① 매번 fresh registry
a1 <- ali(f0, .load_registry(), DD)
a2 <- ali(f0, .load_registry(), DD)
## ② 한 registry 를 재사용해 연속 호출
regR <- .load_registry()
b1 <- ali(f0, regR, DD)
b2 <- ali(f0, regR, DD)
b3 <- ali(f0, regR, DD)
m <- Reduce(function(x,y) merge(x,y,by="Ticker"), list(
  setnames(copy(a1),"z","fresh1"), setnames(copy(a2),"z","fresh2"),
  setnames(copy(b1),"z","reuse1"), setnames(copy(b2),"z","reuse2"), setnames(copy(b3),"z","reuse3")))
cat(sprintf("\n[정렬 결과 재현성] n=%d\n", nrow(m)))
cat(sprintf("  fresh1 vs fresh2 : Spearman %+.4f | 동일값 %s\n",
            cor(m$fresh1,m$fresh2,method="spearman"), identical(m$fresh1,m$fresh2)))
cat(sprintf("  reuse1 vs reuse2 : Spearman %+.4f | 동일값 %s\n",
            cor(m$reuse1,m$reuse2,method="spearman"), identical(m$reuse1,m$reuse2)))
cat(sprintf("  reuse2 vs reuse3 : Spearman %+.4f | 동일값 %s\n",
            cor(m$reuse2,m$reuse3,method="spearman"), identical(m$reuse2,m$reuse3)))
cat(sprintf("  fresh1 vs reuse1 : Spearman %+.4f\n", cor(m$fresh1,m$reuse1,method="spearman")))
mr <- merge(RAW, m[, .(Ticker, fresh1, reuse1)], by="Ticker")
cat(sprintf("  raw    vs fresh1 : Spearman %+.4f  (−1 이면 정렬이 부호를 뒤집음)\n",
            cor(mr$z_raw, mr$fresh1, method="spearman")))
cat(sprintf("  raw    vs reuse1 : Spearman %+.4f\n", cor(mr$z_raw, mr$reuse1, method="spearman")))
cat(sprintf("  [입력 훼손] 호출 후 f0 컬럼: %s\n", paste(names(f0), collapse=", ")))
flag <- cor(m$fresh1,m$reuse1,method="spearman") < 0.99 || !identical(m$reuse1,m$reuse2)
cat(sprintf("\n[판정] %s\n", ifelse(flag,
  "★★align_factor_direction 이 호출 패턴에 따라 다른 결과 — 재현성 결함(내 두 측정의 부호 차이 원인)",
  "정렬은 재현적 — 부호 차이의 원인은 다른 곳(측정 코드 자체를 재검해야)")))
fwrite(m, file.path(OUT, "align_reuse_test.csv"))
