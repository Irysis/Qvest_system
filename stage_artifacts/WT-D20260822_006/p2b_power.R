## WT-D20260822_006 P2b — 검정력 관문 재산출 (MEAN-BLIND)
suppressPackageStartupMessages({library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
OUT <- "stage_artifacts/WT-D20260822_006"
P <- readRDS(file.path(OUT,"p2_arms.rds")); act <- P$act; c0 <- act$C0$act
MATERIAL <- P$MATERIAL
cat(sprintf("MATERIAL = %.4f %%p/yr · C0 NW3 SE %.6f\n", MATERIAL, P$SE_C0))
PW <- rbindlist(lapply(setdiff(names(act),"C0"), function(a) {
  d <- act[[a]]$act - c0; n <- length(d)
  sd_m <- sd(d); nwi <- nw_inflation_measured(d, lag=3L)
  ro <- required_effect(n=n, t_threshold=2.0, sd_monthly=sd_m, nw_inflation=nwi)
  rb <- required_effect(n=n, t_threshold=2.0)
  se_arm <- sd_m*nwi/sqrt(n)
  data.table(arm=a, n=n,
    sd_monthly_own=round(sd_m,6), sd_ratio_vs_contract=round(sd_m/SPREAD_SD_MONTHLY_25EW,4),
    nw_inflation_measured=round(nwi,4),
    mde_own_annual_pct=round(ro$required_annual*100,4),
    mde_band_annual_pct=round(rb$required_annual*100,4),
    implied_t_own=round(ro$required_monthly/se_arm,4),
    implied_t_band=round(rb$required_monthly/se_arm,4),
    material_over_mde_own=round(MATERIAL/(ro$required_annual*100),4))
}))
print(PW)
cat("\n★자기-diff sd 로 만든 바의 퇴화 점검: implied_t_own 이 2.000 이면 t 검정의 단위 번역.\n")
cat("  → 판정 문턱으로는 implied_t_band 를 쓰고, MDE(own) 은 효과크기 단위(연 %p)로만 해석.\n")
## 상태축 지속성 (mandate 4: 대상 지속성을 먼저 재고 NW 보정 판정)
U <- P$U
for (nm in names(U)) { x <- U[[nm]]
  cat(sprintf("  u_%-6s AR1 = %+.4f\n", nm, cor(x[-1], x[-length(x)]))) }
d1 <- act$T2_AGREE$act - c0
cat(sprintf("\npaired diff (T2_AGREE-C0) AR1 = %+.4f  → NW lag-3 보정 %s\n",
  cor(d1[-1], d1[-length(d1)]), if (abs(cor(d1[-1], d1[-length(d1)]))>0.1) "해당" else "해당없음(그래도 병기)"))
saveRDS(list(PW=PW, MATERIAL=MATERIAL), file.path(OUT,"p2b_power.rds"))
cat("\n[saved] p2b_power.rds\n")
