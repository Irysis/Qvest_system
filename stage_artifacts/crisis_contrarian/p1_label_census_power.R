## 위기신호 역방향 가설 — P1: 라벨 census + **착수 전 검정력** (도훈 지시 2026-08-09)
## 가설(도훈): "시장은 선행한다 — 위기신호 발현 시점엔 이미 반영이 끝났으므로 비중을 **늘려야** 한다"
## 본 스크립트는 read-only 진단. 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/crisis_contrarian")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")

## ---- 1. 사용 가능한 국면 라벨 census -----------------------------------------
say("=== 1. 국면 라벨 산출물 census ===")
cands <- c(".cache/regime", "02_Infrastructure/regime", "06_Registry", ".cache")
for (d in cands) {
  if (!dir.exists(d)) { say("  %s 부재", d); next }
  f <- list.files(d, pattern = "regime|crisis|bear|msm|MSM|Crisis|Bear", full.names = TRUE, recursive = FALSE)
  if (length(f)) for (x in head(f, 14)) say("  %s  (%.0f KB)", x, file.size(x)/1024)
}

## ---- 2. 벤치 월수익 (계약 경로 재사용) ---------------------------------------
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
B <- as.data.table(P$bench)[!is.na(BM_Ret)][order(Date)]
say("=== 2. 벤치 실측 === %d개월 · %s ~ %s · 월평균 %+.4f (연 %+.2f%%) · sd %.4f",
    nrow(B), min(B$Date), max(B$Date), mean(B$BM_Ret), mean(B$BM_Ret)*12*100, sd(B$BM_Ret))

## ---- 3. ★착수 전 검정력 — 국면 ON 개월수별 필요 효과 -------------------------
say("=== 3. 착수 전 검정력 (도훈 아이디어를 '측정 가능한가' 부터) ===")
say("  판정량 = ON 월 벤치수익 평균 − OFF 월 평균 (또는 ON 월 초과)")
sd_m <- sd(B$BM_Ret)
say("  벤치 월 sd = %.4f (연 %.2f%%)", sd_m, sd_m*sqrt(12)*100)
say("  n_ON  필요월효과   필요연효과   해석")
for (n_on in c(10L, 20L, 25L, 40L, 60L, 100L)) {
  ## 두 집단 비교: 유효 n ≈ 조화평균 기반. ON 이 적을수록 급감.
  n_off <- nrow(B) - n_on
  se <- sd_m * sqrt(1/n_on + 1/n_off) * 1.25          # NW 팽창 근사
  req_m <- 2.0 * se
  say("  %4d  %10.4f   %9.2f%%   %s", n_on, req_m, req_m*12*100,
      if (req_m*12*100 > 40) "★비현실적 — 착수 전 폐기 대상" else
      if (req_m*12*100 > 20) "매우 큼 — 설계 재고" else "측정 가능 범위")
}
say("  ★기준선: FQ-117 이 보고한 라벨월 벤치 연율 **+90.1%%** (전체 평균 %+.2f%% 대비)", mean(B$BM_Ret)*12*100)
say("  ⇒ 보고된 효과 크기가 위 바를 넘는지가 착수 자격이다. 90%%p 급이면 n_ON 25 에서도 검출 가능.")

## ---- 4. 효과가 실재한다면 '언제' 켜지는가 — 진단 설계 선언 -------------------
say("=== 4. 판별해야 할 3가지 (사후해석 방지 — 측정 전 선언) ===")
say("  (a) 동시성: 라벨 ON 월의 **당월** 벤치수익 — 하락 중에 켜지는가 반등 중에 켜지는가")
say("  (b) 선행성: 라벨 ON 월의 **t+1..t+3** 벤치수익 — 켜진 다음에 더 오르는가")
say("  (c) 실행가능성: 라벨은 **월말**에 알 수 있는가(PIT). 당월 수익은 이미 지나간 것이라 **비중 조절에 못 쓴다**.")
say("  ★★핵심 함정: FQ-117 의 '+90.1%%' 가 (a)면 **거래 불가**다 — 그 달 수익은 이미 실현됐다.")
say("     도훈 가설이 자본으로 전이되려면 **(b) 가 양(+)** 이어야 한다. (a)만 양이면 지연 라벨의 재확인일 뿐이다.")

## ---- 5. 기존 overlay 와의 관계 (중복/충돌 확인) -------------------------------
say("=== 5. 현행 overlay 와의 관계 ===")
say("  현행 MDD 레버 = β_R05 단독(메모리: overlay MDD 개선의 83%%가 타이밍, m4 한계기여 −0.00%%pt)")
say("  ★BearProb/β_R05 와 CRISIS 라벨은 **다른 신호**다 — 역방향 제안이 현행 overlay 를 뒤집는 것은 아니다.")
say("  ⇒ 라운드는 '현행 overlay 교체' 가 아니라 '지연 라벨의 미사용 정보를 역방향으로 쓸 수 있나' 로 좁힌다.")

saveRDS(list(bench = B, sd_monthly = sd_m), file.path(OUT, "p1_bench.rds"))
say("=== P1 완료 ===")
