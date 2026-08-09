## x6 [재작성] — x5 이식 검정 판정
## ★x5 가 요약부에서 죽어 CSV 미기록. 측정 출력(24셀)은 전부 나왔으므로 그 값으로 재구성한다.
##   값 출처 = x5 실행 stdout (재측정 아님 · 전사만). 재현이 필요하면 x5 를 다시 돌린다.
suppressPackageStartupMessages(library(data.table))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[x6] ", fmt, "\n"), ...)); flush.console() }

R <- fread(text = "factor,grp,label,n_on,r_on,r_all,rnd_med,pct
V18_AM,근접,unified_Category,192,0.213,0.284,0.292,32
V18_AM,근접,jump_JM_State,77,0.459,0.284,0.226,92
V18_AM,근접,mega_spread,26,0.257,0.284,0.462,13
R17_Market_Leverage,근접,unified_Category,192,0.229,0.329,0.345,17
R17_Market_Leverage,근접,jump_JM_State,77,0.458,0.329,0.325,82
R17_Market_Leverage,근접,mega_spread,26,0.286,0.329,0.444,8
V19_Debt_to_Market,근접,unified_Category,192,0.229,0.329,0.344,22
V19_Debt_to_Market,근접,jump_JM_State,77,0.458,0.329,0.283,80
V19_Debt_to_Market,근접,mega_spread,26,0.286,0.329,0.412,13
L11_Kyle_Lambda,근접,unified_Category,192,0.208,0.343,0.360,8
L11_Kyle_Lambda,근접,jump_JM_State,77,0.523,0.343,0.312,90
L11_Kyle_Lambda,근접,mega_spread,26,0.296,0.343,0.375,25
Q30_Receivables_Turnover,무작위,unified_Category,192,0.414,0.484,0.506,12
Q30_Receivables_Turnover,무작위,jump_JM_State,77,0.600,0.484,0.464,93
Q30_Receivables_Turnover,무작위,mega_spread,26,0.562,0.484,0.471,80
IN04_Net_Equity_Issuance,무작위,unified_Category,192,0.324,0.393,0.402,13
IN04_Net_Equity_Issuance,무작위,jump_JM_State,77,0.498,0.393,0.382,78
IN04_Net_Equity_Issuance,무작위,mega_spread,26,0.654,0.393,0.470,93
MK01_CAPM_Beta,무작위,unified_Category,192,0.404,0.470,0.484,20
MK01_CAPM_Beta,무작위,jump_JM_State,77,0.648,0.470,0.427,93
MK01_CAPM_Beta,무작위,mega_spread,26,0.365,0.470,0.432,30
XF_LL02_NetDebt,무작위,unified_Category,192,0.173,0.263,0.276,7
XF_LL02_NetDebt,무작위,jump_JM_State,77,0.429,0.263,0.239,77
XF_LL02_NetDebt,무작위,mega_spread,26,0.148,0.263,0.443,5")
R[, beats := pct < 5]

say("=== 셀 %d개 (재료 %d x 라벨 %d) ===", nrow(R), uniqueN(R$factor), uniqueN(R$label))
say("★1급 통과(ON rho 가 무작위 5%% 아래): **%d/%d**", sum(R$beats), nrow(R))
say("  대조 기준 = 계약+mega_spread ON rho +0.186 · 백분위 **0%%**")
say("=== 라벨별 ===")
say("  %-18s %7s %11s %11s %11s", "label", "통과", "ON rho중앙", "백분위중앙", "백분위<50")
for (k in unique(R$label)) { s <- R[label == k]
  say("  %-18s %2d/%-4d %+11.3f %10.0f%% %8d/%d", k, sum(s$beats), nrow(s),
      median(s$r_on), median(s$pct), sum(s$pct < 50), nrow(s)) }

say("=== ★방향 일관성 (이항검정) ===")
u <- R[label=="unified_Category"]; j <- R[label=="jump_JM_State"]; g <- R[label=="mega_spread"]
bt <- function(x, n, alt) binom.test(x, n, 0.5, alternative = alt)$p.value
pu <- bt(sum(u$pct<50), nrow(u), "greater"); pj <- bt(sum(j$pct>50), nrow(j), "greater")
say("  unified_Category: 백분위<50 **%d/%d** · p **%.4f** → %s", sum(u$pct<50), nrow(u), pu,
    if (pu < 0.05) "★일관되게 rho 를 **낮춘다**" else "방향 미확립")
say("  jump_JM_State  : 백분위>50 **%d/%d** · p **%.4f** → %s", sum(j$pct>50), nrow(j), pj,
    if (pj < 0.05) "★일관되게 rho 를 **올린다**(역방향 정보)" else "방향 미확립")
say("  mega_spread    : 백분위<50 %d/%d · p %.4f", sum(g$pct<50), nrow(g), bt(sum(g$pct<50), nrow(g), "greater"))
say("  재료군별 통과: 근접 %d/%d · 무작위 %d/%d",
    sum(R[grp=="근접"]$beats), nrow(R[grp=="근접"]), sum(R[grp=="무작위"]$beats), nrow(R[grp=="무작위"]))

say("=== ★★판정 ===")
say("  1) **어떤 (라벨,재료) 쌍도 계약+mega_spread(백분위 0%%)를 재현하지 못한다.**")
say("     최저 %.0f%% (%s + %s) · 1급 통과 %d/%d · 다중검정 기대(24x5%%)=%.1f셀 대비 **유의 아님**",
    min(R$pct), R[which.min(pct), factor], R[which.min(pct), label], sum(R$beats), nrow(R), 0.05*nrow(R))
say("  2) ⇒ **계약+mega_spread 는 특이 쌍**이다. 기전은 확립됐으나 이 재료·라벨 집합으로는 **이식 안 됨**.")
say("  3) ★부수 발견 2건 (가설 — 확증 아님):")
say("     ⓐ unified_Category **8/8 전건 백분위<50** (p %.4f) — 약하지만 **일관되게 rho 를 낮춘다**.", pu)
say("        발화율 71.7%%·에피소드 29 로 계약(35.6%%/14)보다 완만 — 폭이 부족할 뿐 방향은 맞다.")
say("     ⓑ jump_JM_State **8/8 전건 백분위>50** (p %.4f) — **일관되게 rho 를 올린다**.", pj)
say("        ★역방향 정보: 이 라벨 ON 월은 북과 **더** 상관된 구간이므로,")
say("        **OFF 월에 보유**하는 반전 규칙이 직교성 레버일 수 있다(미측정 · next_probe).")
say("  4) ★정직: 8셀 이항검정이고 재료가 독립이 아니다(**V19≡R17 은 중복 쌍** — 오늘 확인).")
say("     유효 독립 재료는 8보다 적으므로 p 는 낙관 편향이다. 확증 아니라 **가설**로 등재한다.")
fwrite(R, "stage_artifacts/pg2_hunt/x5_transplant.csv")
say("=== x6 완료 → x5_transplant.csv 복원 ===")
