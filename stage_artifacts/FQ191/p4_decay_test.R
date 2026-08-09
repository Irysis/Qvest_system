## FQ-191 P4 — ★내 oos 진단 정정 전 마지막 확인: 전/후반 차이가 유의한가
## 나는 close_round 에 "oos 미달은 표본 구조이지 신호 열화가 아니다" 라고 썼는데 P3 이 반대를 보였다.
## 그러나 n=13씩이다 — **차이가 유의하지 않으면 '감쇠 확정' 도 과장**이다. 양쪽 다 확인한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ191")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/required_effect_size.R")

M <- fread(file.path(OUT, "p1_rule.csv"))[, date := as.Date(date)]
M <- M[date < as.Date("2026-01-01")]
ON <- M[regime %in% TRUE][order(date)][, act := ret_rule_net - bm]
say("=== 입력 실측 === ON %d개월 · %s ~ %s", nrow(ON), min(ON$date), max(ON$date))

n <- nrow(ON); h <- floor(n/2)
a1 <- ON$act[1:h]; a2 <- ON$act[(h+1):n]
say("=== 1. 전/후반 차이 검정 ===")
say("  전반 n=%d 평균 %+.5f (연 %+.2f%%) sd %.4f", length(a1), mean(a1), mean(a1)*12*100, sd(a1))
say("  후반 n=%d 평균 %+.5f (연 %+.2f%%) sd %.4f", length(a2), mean(a2), mean(a2)*12*100, sd(a2))
d <- mean(a1) - mean(a2)
se <- sqrt(var(a1)/length(a1) + var(a2)/length(a2))
say("  ★차이 %+.5f/월 (연 %+.2f%%) · Welch se %.5f · **t %+.3f**", d, d*12*100, se, d/se)
tt <- t.test(a1, a2); say("  Welch t.test: t %+.3f · df %.1f · p %.4f · 95%%CI [%+.5f, %+.5f]",
                          tt$statistic, tt$parameter, tt$p.value, tt$conf.int[1], tt$conf.int[2])

say("=== 2. 검정력 — 이 표본이 감쇠를 검출할 수 있었나 ===")
r <- required_effect(n = n, t_threshold = 2.0, sd_monthly = sd(ON$act), design = "split")
say("  ON %d개월 split 설계 · sd %.4f → 필요 효과 월 %.5f = 연 **%.2f%%**",
    n, sd(ON$act), r$required_monthly, r$required_annual*100)
say("  관측 차이 연 %.2f%% vs 필요 %.2f%% → %s",
    d*12*100, r$required_annual*100,
    if (abs(d) >= r$required_monthly) "검출 가능 범위" else "★검정력 미달")

say("=== 3. 연도별 ON 초과 (분할 임의성 회피) ===")
ON[, yr := format(date, "%Y")]
print(ON[, .(n = .N, act_ann = round(mean(act)*12*100, 2)), by = yr][order(yr)])
cy <- ON[, .(m = mean(act)), by = yr]
say("  연도-평균 계열 추세 spearman(연도, 초과) = %+.3f (n=%d)",
    suppressWarnings(cor(seq_len(nrow(cy)), cy$m, method="spearman")), nrow(cy))

say("=== 4. ★판정 ===")
sig <- tt$p.value < 0.05
say("  전/후반 차이 유의(p<0.05): %s (p=%.4f)", sig, tt$p.value)
say("  ⇒ %s", if (sig) "★신호 감쇠 확정 — 내 close_round 진단('표본 구조') 정정 필요" else
  "★★**감쇠도 확정 못 함** — 점추정은 감쇠 방향이나 유의하지 않다. 내 원 진단('표본 구조')도, 정정안('감쇠 확정')도 **둘 다 과장**이다. 정직한 라벨 = 검정력 부족")
saveRDS(list(t = tt, d = d, req = r), file.path(OUT, "p4.rds"))
say("=== P4 완료 ===")
