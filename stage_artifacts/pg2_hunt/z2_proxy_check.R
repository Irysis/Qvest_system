## z2 — ★대리 축이 원 라벨을 재현하는가 (z1 설계 결함 확인)
## z1 은 희석 가설("Category 발화율을 조이면 rho 인하 폭이 커지나")을 검정하려 했으나
## Category 가 이산이라 조일 수 없어 **Regime_Score_smooth 문턱**을 대리 축으로 썼다.
## 그런데 rate72(발화율 71.7% 일치) 백분위 중앙 **75%** vs x6 의 Category **15%** — 모순.
## ⇒ 대리 축이 원 라벨을 재현하지 못한다는 뜻이면 z1 은 희석 가설을 **검정한 적이 없다**.
## ★확인: 두 라벨의 월 집합 일치율을 직접 잰다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[z2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1))
dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
mo <- U[!is.na(.dd)][order(.dd)][, .(cat = last(Category), rs = last(Regime_Score_smooth)), by = .(m = mi(.dd))]
mo[, m_apply := m + 1L]
mo <- mo[m_apply %in% inc$m]
say("=== 월별 %d개 ===", nrow(mo))

say("=== 1. Category 분포 ===")
print(sort(table(mo$cat), decreasing = TRUE))
dom <- names(sort(table(mo$cat), decreasing=TRUE))[1]
mo[, lab_cat := cat == dom]
say("  최빈 '%s' = ON · 발화율 %.1f%% (%d/%d)", dom, 100*mean(mo$lab_cat), sum(mo$lab_cat), nrow(mo))

say("=== 2. Regime_Score_smooth 문턱 라벨 (같은 발화율) ===")
p <- mean(mo$lab_cat)
th <- quantile(mo$rs, 1 - p, na.rm = TRUE)
mo[, lab_rs := rs >= th]
say("  문턱 %.3f · 발화율 %.1f%% (%d/%d)", th, 100*mean(mo$lab_rs), sum(mo$lab_rs), nrow(mo))

say("=== 3. ★두 라벨의 일치율 ===")
agree <- mean(mo$lab_cat == mo$lab_rs)
say("  월 단위 일치 **%.1f%%** (%d/%d)", 100*agree, sum(mo$lab_cat == mo$lab_rs), nrow(mo))
say("  교차표:"); print(table(Category = mo$lab_cat, RegimeScore = mo$lab_rs))
say("  ON 집합 교집합 %d / 합집합 %d = Jaccard **%.3f**",
    sum(mo$lab_cat & mo$lab_rs), sum(mo$lab_cat | mo$lab_rs),
    sum(mo$lab_cat & mo$lab_rs)/sum(mo$lab_cat | mo$lab_rs))
say("  phi 상관 %.3f", suppressWarnings(cor(as.integer(mo$lab_cat), as.integer(mo$lab_rs))))
say("  ★무작위 두 라벨의 기대 일치율(같은 발화율 %.1f%%) = %.1f%%", 100*p, 100*(p^2 + (1-p)^2))

say("=== ★판정 ===")
exp_ag <- p^2 + (1-p)^2
if (agree < exp_ag + 0.10) {
  say("  ★★대리 축이 원 라벨을 **재현하지 못한다**(일치 %.1f%% vs 무작위 기대 %.1f%%).",
      100*agree, 100*exp_ag)
  say("     ⇒ z1 은 희석 가설을 **검정한 적이 없다**. 검정한 것은 '다른 라벨' 이다.")
  say("     ⇒ **희석 가설은 여전히 미검**이며, Category 를 조일 축이 없으므로")
  say("        이 자산으로는 검정 불가다(Category 생산 코드에서 원시 연속 축을 찾아야 함).")
} else {
  say("  대리 축이 원 라벨을 상당히 재현(일치 %.1f%%) — z1 결과를 희석 가설 판정으로 쓸 수 있다.", 100*agree)
}
say("  ★설계 교훈: **대리 축을 쓸 때는 원 대상을 재현하는지 먼저 재라.**")
say("     발화율을 맞추는 것은 재현이 아니다 — 같은 비율로 **다른 달**을 고를 수 있다.")
say("     (오늘 반복: 존재 검사로 정체 검사 대체 · 한 이름 없다고 결론 · 대리 축 미검증)")
fwrite(mo[, .(m = m_apply, cat, lab_cat, rs, lab_rs)], file.path(OUT,"z2_labels.csv"))
say("=== z2 완료 ===")
