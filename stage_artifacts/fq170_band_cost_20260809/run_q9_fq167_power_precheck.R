## Q9 — FQ-167 착수 전 검정력 확인 (국면-조건부 설계)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  FQ-167 = "섹터-중립 역전 × 변동성 조건부 — **저변동 국면 한정** 적용".
##  ★08-08 카드: **국면-조건부·분할 = 구조적 저검정력**, 유효표본이 n·p(1−p) 로 급감(80→18.2),
##    필요 연효과 27.71%. 규약 = **사전등록 전에** `required_effect_size.R`, 비현실적이면 **착수 전 폐기**.
##  ⇒ 착수하기 전에 "저변동 3분위(≈1/3 개월)에서 검출 가능한 최소 효과" 를 낸다.
##  ★이 라운드는 **선정 보조**다 — FQ-167 을 대신 수행하지 않는다(owner 미배정이나 다음 세션 몫).
##  판정:
##   P1_FEASIBLE   : 필요 연효과가 KR long-only 에서 현실적(<= 8%/yr 수준)
##   P2_MARGINAL   : 8~15%
##   P3_INFEASIBLE : > 15% → **착수 전 폐기 권고**(08-08 규약)
##  ★read-only.
suppressPackageStartupMessages({ library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))

N_TOTAL <- 266L                 # 오늘 아크에서 반복 확인된 유효 창
FRAC    <- 1/3                  # 저변동 3분위
cat(sprintf("[설계] 전체 %d개월 · 저변동 3분위 적용 ⇒ 발화 개월 ≈ %d\n",
            N_TOTAL, round(N_TOTAL*FRAC)))

## ★초판이 반환 필드명을 **추측**해 전부 NA 를 냈다(`required_effect_annual_pct` 등 — 실제는
##   `required_monthly`/`required_annual`, 그리고 **분수**라 %는 x100).
##   그리고 계약에 **`design="split"` + `regime_frac`** 이 이미 있다 — 08-08 의 국면-분할 교훈이
##   계약에 인코딩돼 있는데 나는 n 을 손으로 줄여 근사하려 했다. **계약의 경로를 쓴다.**
res <- list()
specs <- list(list(nm = "전기간(대조)", design = "full",  frac = NA_real_),
              list(nm = "저변동 3분위", design = "split", frac = FRAC))
for (s in specs) {
  r <- try(if (s$design == "full") required_effect(n = N_TOTAL, t_threshold = 2.0, design = "full")
           else required_effect(n = N_TOTAL, t_threshold = 2.0, design = "split", regime_frac = s$frac),
           silent = TRUE)
  if (inherits(r, "try-error")) { cat(sprintf("  %s: 계산 실패 — %s\n", s$nm, conditionMessage(attr(r,"condition")))); next }
  mon <- r$required_monthly; ann <- r$required_annual * 100
  cat(sprintf("  %-14s design=%-5s · 필요 월효과 %.5f · **필요 연효과 %.2f%%** · NW인자 %.3f(%s)\n",
              s$nm, s$design, mon, ann, r$nw_inflation, r$nw_inflation_source))
  res[[s$nm]] <- list(design = s$design, monthly = mon, annual_pct = ann,
                      nw = r$nw_inflation, nw_src = r$nw_inflation_source)
}
ann_lo <- res[["저변동 3분위"]]$annual_pct
cat(sprintf("\n★저변동 한정 설계의 필요 연효과 = **%.2f%%/yr**\n", ann_lo))
cat(sprintf("  (참고) 전기간 대조 = %.2f%%/yr · 분할 비용 배수 %.2fx\n",
            res[["전기간(대조)"]]$annual_pct, ann_lo / res[["전기간(대조)"]]$annual_pct))
cat(sprintf("  FQ-167 의 근거 신호 IC = 0.0271(포지티브 57.4%%) — 이 IC 로 연 %.1f%% 를 낼 수 있는가가 관건\n", ann_lo))
verdict <- if (!is.finite(ann_lo)) "UNKNOWN" else if (ann_lo <= 8) "P1_FEASIBLE" else
           if (ann_lo <= 15) "P2_MARGINAL" else "P3_INFEASIBLE"
cat(sprintf("\n판정: %s\n", verdict))
if (verdict == "P3_INFEASIBLE")
  cat("=> **착수 전 폐기 권고**(08-08 규약) 또는 설계 변경: 국면 분할 대신 전기간 + 국면을 공변량으로.\n")
if (verdict == "P2_MARGINAL")
  cat("=> 착수 가능하나 **사전등록에 이 수치를 명시**하고, 미달 시 '효과 부재' 가 아니라 '검정력 미달' 로 라벨.\n")
cat("⚠이 수치는 top-25 EW 스프레드 sd 기준이다 — FQ-167 의 실제 구성(섹터-중립)에서 sd 가 다르면 재산출 필요\n")
write_json(list(verdict = verdict, n_total = N_TOTAL, frac = FRAC,
                required_annual_pct_lowvol = ann_lo,
                required_annual_pct_full = res[["전기간(대조)"]]$annual_pct,
                detail = res),
           file.path(OUT, "q9_fq167_power.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
