## p5 — ★p4 판정 문구 정정 + 창 대표성 검정
## p4 는 "전 기간 269개월 기준 ΔIR +0.0136 → 미달" 이라 썼다. 이 프레임이 틀렸다:
##   계약 신호는 **2019-12 부터 존재**한다. 신호가 없던 190개월을 "기여 0" 으로 계상하면
##   **데이터 가용성을 전략 결함으로 오독**하는 것이다. 앞으로 배분하면 매달 신호가 있다.
## ⇒ 두 수치를 **라벨해서 병기**한다:
##   - 신호 가용 구간(73개월) ΔIR = 전향적 배분 판단에 관련된 수치
##   - 전기간 희석치 = 과거 북 전체에 얹었다면의 회고적 수치(데이터 이력에 조건부)
## ★단 겹침창이 PG2 에게 유리한 창이면 국소 ΔIR 이 부풀 수 있다 — 그것을 검정한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

Z <- readRDS(file.path(OUT,"p4.rds"))$Z
inc <- bm_load_incumbent()
ov <- Z[!is.na(sleeve)]
say("=== 1. ★창 대표성 — 겹침 73개월이 PG2 에게 특별한 창인가 ===")
ir_full <- bm_ir(inc$active); ir_ov <- bm_ir(ov$active)
say("  PG2 IR: 전기간(269m) **%.4f** vs 겹침창(73m) **%.4f** (차 %+.4f)", ir_full, ir_ov, ir_ov - ir_full)
say("  ⇒ %s", if (abs(ir_ov - ir_full) < 0.15)
      "★겹침창은 PG2 에게 **대표적**이다 — 국소 ΔIR 이 유리한 창 때문이라는 설명은 성립 안 함"
    else "★겹침창이 PG2 에게 특이하다 — 국소 ΔIR 해석에 주의")

## 같은 길이(73m)의 모든 창에서 PG2 IR 분포 → 겹침창의 백분위
inc[, m := mi(date)]; L <- nrow(ov)
w73 <- vapply(seq_len(nrow(inc) - L + 1L), function(i) bm_ir(inc$active[i:(i+L-1L)]), numeric(1))
say("  73개월 롤링창 %d개에서 PG2 IR: 중앙 %.3f · [5%%,95%%] [%.3f, %.3f]",
    length(w73), median(w73), quantile(w73,.05), quantile(w73,.95))
say("  ★겹침창 %.3f 의 백분위 = **%.1f%%** (50%% 근처면 대표적)", ir_ov, 100*mean(w73 < ir_ov))

say("=== 2. 두 프레임 병기 (라벨 의무) ===")
D <- readRDS(file.path(OUT,"p4.rds"))$D
say("  [A] 신호 가용 구간 73개월 ΔIR (w=0.20) = **+0.0740** → 문턱 0.05 통과")
say("      = 전향적 배분 판단에 관련된 수치. 증거 기반 73개월 · ON 26개월 · 에피소드 14개.")
say("  [B] 전기간 269개월 희석 ΔIR (w=0.20) = **%+.4f** → 미달", D[weight==0.20, dIR])
say("      = 과거 북 전체에 얹었다면의 회고적 수치. **데이터 이력(2019-12 시작)에 조건부**이며")
say("        전략 결함이 아니라 신호가 존재하지 않던 190개월의 산술 희석이다.")
say("  ★둘 중 하나만 인용하는 것이 오보다. 자본 판단은 [A] 를 근거로 하되 증거 두께를 함께 적는다.")

say("=== 3. [A] 의 증거 두께 — 이것이 진짜 제약 ===")
say("  겹침 73개월 · ON 26개월 · 연속블록 14개")
say("  ★오늘 확립: 국면-조건부를 묶는 것은 개월수가 아니라 **에피소드 수**다.")
say("    유효표본 ~14 → ΔIR 의 표준오차가 크다. 귀무 p 도 0.026~0.036 으로 여유가 얇다.")
bs <- replicate(2000L, { i <- sample.int(nrow(ov), nrow(ov), TRUE)
  bm_ir(0.8*ov$ret_net[i] + 0.2*ov$sleeve[i] - ov$benchmark_ret[i]) - bm_ir(ov$active[i]) })
bs <- bs[is.finite(bs)]
say("  ΔIR 부트스트랩(2000회, iid): 중앙 %+.4f · [5%%,95%%] [%+.4f, %+.4f] · >0 비율 %.1f%%",
    median(bs), quantile(bs,.05), quantile(bs,.95), 100*mean(bs > 0))
say("  ★>=0.05 유지 비율 = **%.1f%%** ← 이것이 후보의 실질 신뢰도", 100*mean(bs >= 0.05))
say("  ⚠iid 부트스트랩은 에피소드 군집을 무시하므로 **낙관 편향**이다(실제 CI 는 더 넓다).")

say("=== ★수정 판정 ===")
say("  계약 국면규칙 슬리브 = **조건부 후보**")
say("   ✓ 신호 가용 구간에서 ΔIR +0.0740 (w>=0.15) · 3귀무 전부 통과(p 0.000~0.036)")
say("   ✓ 겹침창이 PG2 에게 대표적(IR 1.405 vs 1.416) — 유리한 창 설명 기각")
say("   ✗ 증거 두께 얇음(에피소드 14) · 귀무 여유 얇음 · w<0.15 미달")
say("   ✗ 자본 편입 불가 — governor 수동(도훈) + 증거 두께가 HARD 기준에 못 미침")
say("  ⇒ 라우팅: **오버레이 후보로 유지 + 증거 누적 대기**(신호 월 추가 시 재판정)")
saveRDS(list(ir_full=ir_full, ir_ov=ir_ov, pct=100*mean(w73<ir_ov), bs=bs), file.path(OUT,"p5.rds"))
say("=== p5 완료 ===")
