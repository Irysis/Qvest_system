## =============================================================================
## FQ-229 (C3) — 귀무분포의 기준점 실측: "게이트를 아예 안 거는 것"(Δ=0)은 그 귀무 안 어디인가?
##  c2 는 "무작위 재배정보다 낫다"(p 0.012~0.048)를 보였다. 그런데 귀무 중앙이 **음수**다.
##  ⇒ 임의로 월별 가중을 흔드는 행위 자체가 해롭다면, 높은 백분위는 "덜 해롭다"의 의미일 수 있다.
##  결정적 대조점 = **무게이트(Δ=0)** 의 백분위. 이 값이 높으면 백분위 논증은 증거력을 잃는다.
## metric_type: canonical_screen_diag.
## =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[c3] ", fmt, "\n"), ...)); flush.console() }
R <- readRDS(file.path(OUT, "c2_results.rds"))
CMP <- fread(file.path(OUT, "c1_paired_comparison.csv"))

TAB <- rbindlist(lapply(names(R), function(g) {
  nd <- as.data.table(R[[g]]$nd); ob <- R[[g]]$obs
  data.table(gate = g, n_null = nrow(nd),
             obs_d_pt = ob$d_pt, obs_ptrd = ob$ptrd, obs_d_ir = ob$d_ir,
             null_med_d_pt = median(nd$d_pt),
             pct_obs   = mean(nd$d_pt <= ob$d_pt),
             pct_zero  = mean(nd$d_pt <= 0),
             pct_obs_ir = mean(nd$d_ir <= ob$d_ir), pct_zero_ir = mean(nd$d_ir <= 0),
             frac_null_positive = mean(nd$d_pt > 0)) }))
for (i in seq_len(nrow(TAB))) with(TAB[i], say(
  "%s · 귀무 %d회 · 중앙 %+.4f · 귀무 중 양수 비율 %.3f\n     ΔPORT_t: 관측 %+.4f (백분위 %.1f%%) vs **무게이트 0** (백분위 %.1f%%) ⇒ 분산연결이 무게이트 대비 얻는 백분위 = %+.1f%%p\n     ΔIR    : 관측 %+.4f (백분위 %.1f%%) vs 0 (백분위 %.1f%%)",
  gate, n_null, null_med_d_pt, frac_null_positive,
  obs_d_pt, pct_obs*100, pct_zero*100, (pct_obs - pct_zero)*100,
  obs_d_ir, pct_obs_ir*100, pct_zero_ir*100))

say("================ 판정 ================")
say("★귀무 중앙이 음수이고 무게이트(0)가 이미 높은 백분위에 있으면,")
say("  '무작위보다 낫다'는 대부분 **'월별 가중을 임의로 흔들지 않았다'**로 설명된다.")
for (i in seq_len(nrow(TAB))) with(TAB[i], say(
  "  %s: 무게이트가 이미 상위 %.1f%% ⇒ 분산연결의 순증 백분위 %+.1f%%p · 무게이트 대비 paired t %+.3f",
  gate, pct_zero*100, (pct_obs - pct_zero)*100,
  CMP[arm == if (gate == "G1_n") "arm2_comp_G1" else "arm5_comp_G4", paired_t_nw3]))
say("★결론 축: 경제적으로 구속력 있는 비교는 **무게이트 대비 paired t** 이다(|t| max %.3f · 문턱 2.0).",
    max(abs(CMP$paired_t_nw3)))
fwrite(TAB, file.path(OUT, "c3_null_reference.csv"))
saveRDS(TAB, file.path(OUT, "c3_results.rds"))
say("저장 완료 -> %s", OUT)
