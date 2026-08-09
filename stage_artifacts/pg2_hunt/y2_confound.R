## y2 — 순환 아님 확정 + **교락** 검정
## ★내 순환 우려 철회: FQ138/p1_measure.R:53 이 정의를 명시한다 —
##   `mega_spread = mean(ret_1m[top10]) - median(ret_1m)` = **상위10 시총 평균수익 − 전체 중앙값**.
##   순수 시장 수익률이고 계약 데이터가 아니다. ⇒ 순환 아님.
## ★그러나 FQ-138 사전등록이 기록한 것: cor(mega_spread, 벤치핸디캡 d) = **+0.896**.
##   ON 월 = 메가캡이 지는 달 = 소형편향 top-25 EW 의 순풍. **PG2 도 top-25 EW 다.**
##   ⇒ ON 월에 PG2 자신의 active 가 특이하면 상관의 분모가 달라져 rho 가 내려갈 수 있다 = 교락.
## 검정: ON/OFF 월에서 ①PG2 active 의 평균·sd ②계약 슬리브 active 의 평균·sd
##       ③rho 를 분자(cov)/분모(sd곱)로 분해해 어느 쪽이 rho 를 내렸는지 귀속
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[y2] ", fmt, "\n"), ...)); flush.console() }

Y <- readRDS(file.path(OUT, "y1.rds"))
Xp <- as.data.table(Y$Xp)   # 파킹 창 73개월 · on 컬럼 포함
on <- Xp[on %in% TRUE]; off <- Xp[on %in% FALSE]
say("=== 입력 === 파킹창 %d개월 · ON %d · OFF %d", nrow(Xp), nrow(on), nrow(off))

say("=== 1. ON/OFF 월의 두 계열 성질 ===")
say("  %-22s %10s %10s %10s", "계열", "평균", "sd", "n")
say("  %-22s %+10.5f %10.5f %10d", "PG2 active (ON)",  mean(on$inc_act),  sd(on$inc_act),  nrow(on))
say("  %-22s %+10.5f %10.5f %10d", "PG2 active (OFF)", mean(off$inc_act), sd(off$inc_act), nrow(off))
say("  %-22s %+10.5f %10.5f %10d", "계약 active (ON)",  mean(on$a_s),  sd(on$a_s),  nrow(on))
say("  %-22s %+10.5f %10.5f %10d", "계약 active (OFF)", mean(off$a_s), sd(off$a_s), nrow(off))
say("  ★PG2 active 가 ON 월에 %s (평균 %+.5f vs %+.5f · 비율 %.2f)",
    if (mean(on$inc_act) > mean(off$inc_act)) "**더 높다** (순풍 확인)" else "낮다",
    mean(on$inc_act), mean(off$inc_act),
    if (mean(off$inc_act) != 0) mean(on$inc_act)/mean(off$inc_act) else NA_real_)

say("=== 2. ★rho 분해 — 분자(cov) vs 분모(sd곱) ===")
dec <- function(Z, lab) {
  cv <- cov(Z$a_s, Z$inc_act); s1 <- sd(Z$a_s); s2 <- sd(Z$inc_act)
  say("  %-6s rho %+.3f = cov %+.6f / (sd_s %.5f x sd_i %.5f = %.6f)",
      lab, cv/(s1*s2), cv, s1, s2, s1*s2)
  c(rho = cv/(s1*s2), cov = cv, s1 = s1, s2 = s2)
}
dO <- dec(Xp, "전체"); dN <- dec(on, "ON"); dF <- dec(off, "OFF")
say("  ★ON vs 전체: cov 비율 %.3f · 분모 비율 %.3f → rho 이동 %+.3f",
    dN["cov"]/dO["cov"], (dN["s1"]*dN["s2"])/(dO["s1"]*dO["s2"]), dN["rho"]-dO["rho"])
say("  ⇒ %s", if (abs(dN["cov"]/dO["cov"]) < abs((dN["s1"]*dN["s2"])/(dO["s1"]*dO["s2"])))
  "★**분자(공분산)가 더 많이 줄었다** — 두 계열이 ON 월에 실제로 덜 함께 움직인다(교락 아님)" else
  "★**분모(변동성)가 더 많이 늘었다** — rho 하락이 변동성 확대의 산물일 수 있다(교락 의심)")

say("=== 3. ★교락 직접 검정: PG2 순풍을 통제하면 rho 가 유지되는가 ===")
## PG2 active 를 ON 더미로 회귀해 순풍 성분 제거 후 잔차로 rho 재산출
Xp[, on_i := as.integer(on)]
r1 <- lm(inc_act ~ on_i, data = Xp); r2 <- lm(a_s ~ on_i, data = Xp)
Xp[, i_res := residuals(r1)][, s_res := residuals(r2)]
say("  ON 더미 회귀: PG2 계수 %+.5f (p %.4f) · 계약 계수 %+.5f (p %.4f)",
    coef(r1)[2], summary(r1)$coefficients[2,4], coef(r2)[2], summary(r2)$coefficients[2,4])
onr <- Xp[on %in% TRUE]
say("  잔차 기준 ON월 rho = **%+.3f** (원 %+.3f · 이동 %+.3f)",
    cor(onr$s_res, onr$i_res), dN["rho"], cor(onr$s_res, onr$i_res) - dN["rho"])
say("  ⇒ %s", if (abs(cor(onr$s_res, onr$i_res) - dN["rho"]) < 0.05)
  "★순풍(수준 차)을 빼도 rho 가 유지 — **교락 아님**" else
  "★순풍 제거 시 rho 가 이동 — 수준 차가 rho 에 개입했다")

say("=== 4. ★★종합 판정 ===")
say("  ①순환: **아님** — mega_spread 는 시장 수익률(top10 평균 − 중앙값)이지 계약 데이터가 아니다.")
say("     내 x9/x8 의 '순환 의심' 서술은 **철회**한다. 정의를 확인하기 전에 의심을 기록한 것이 성급했다.")
say("  ②교락: 위 §2·§3 결과로 판정.")
say("  ③독립 라벨 미재현(x9: 0.338/0.657, 백분위 70%%/72%%)은 여전히 남는다 —")
say("     그러나 그것은 '다른 라벨이 이 일을 못 한다' 는 뜻이지 '계약 결과가 가짜' 라는 뜻이 아니다.")
say("     mega_spread 는 **메가캡-소형 상대성과 축**이고 PG2·계약 둘 다 소형편향이므로")
say("     그 축에서 구조가 갈리는 것이 기전적으로 자연스럽다.")
saveRDS(list(dO=dO, dN=dN, dF=dF), file.path(OUT,"y2.rds"))
say("=== y2 완료 ===")
