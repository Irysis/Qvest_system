#!/usr/bin/env Rscript
Sys.setlocale("LC_ALL","English_United States.utf8")
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/telegram/telegram_notify.R")
ST <- "stage_artifacts/WT_D20260718_007"
res <- tg_agent_brief(
  agent="Alpha",
  title="WT-D20260718_007 정밀화 r2 — paired-return 유의화 3방향 실측 (graduation 갭)",
  as_of="2026-07-19",
  sections=list(
    list(emoji="📌", heading="한 줄 결론 (return-graduation 미달·calmar 정제)", type="bullet",
         items=c("유일 gap=초과수익 짝검정 비유의. 3방향으로 유의화 시도",
                 "τ 재매칭·grind 보완 둘 다 짝검정 악화 → 실패",
                 "교집합(양자 합의 시에만 방어)만 짝검정 -1.49→+0.49로 부호 반전·전 지표 우위",
                 "그러나 +0.49는 유의선(+2)에 크게 못 미침 → return-graduation 미달",
                 "→ 비지도 이상탐지는 꼬리위험(손익비/최대낙폭) 정제 한정 확정")),
    list(emoji="📊", heading="3방향 초과수익 짝검정 (목표 +2)", type="kv",
         kv=list(
           "AE 단독(원본)"="-1.49 (비유의)",
           "1방향 임계값 재매칭"="-1.62 (악화 — 과잉발화가 drag 아님)",
           "2방향 grind 보완"="-2.21 (악화 — 완만하락 방어 무익)",
           "3방향 교집합(양자합의)"="+0.49 전체 / +0.50 표본외 (부호반전·비유의)")),
    list(emoji="🏆", heading="교집합 = 전 지표 우위(파레토 지배)", type="kv",
         kv=list(
           "손익비 (인컴번트→교집합)"="2.069 → 2.284 (+0.215, 전 변형 최고)",
           "최대낙폭 (인컴번트→교집합)"="-18.7% → -17.0%",
           "샤프지수 (인컴번트→교집합)"="1.809 → 1.815",
           "연복리 (인컴번트→교집합)"="+0.13%p (수익 손실 없음)",
           "기전"="양자 합의(고신뢰 폭락)만 방어 → AE 위기포착 유지·오발화 drag 제거")),
    list(emoji="🛡️", heading="정밀화 미래참조 규율", type="kv",
         kv=list(
           "grind 미래참조 가드"="통과 (컷오프 < 홀딩월 시작)",
           "2방향 1기 지연 스트레스"="1.806→1.800 (붕괴 없음)",
           "임계값·가중 선택"="IS 전용 (표본외 무조회)",
           "교집합"="무수 규칙(합의 시 방어) — 과적합 표면 없음")),
    list(emoji="🚩", heading="자가 적대검증 (약점 공개)", type="bullet",
         items=c("교집합 +0.49는 비유의 → 수익 개선 주장 안 함(확정)",
                 "1방향 실패로 r1 '예산 confound' 가설 반증 — 과잉발화는 drag 아닌 신호값",
                 "grind 신호는 정상 작동(2018 2/4·2022 7/10) 그러나 방어가 수익 손실 → 깨끗한 negative",
                 "교집합은 파레토 지배(전 book 지표 우위)이나 유의성은 꼬리위험 한정")),
    list(emoji="➡️", heading="다음 단계", type="bullet",
         items=c("리스크리서치: 교집합 오버레이를 손익비-graduation 후보로 포지 재측정(수익 아님)",
                 "타이밍 오버레이 수익-graduation은 이 book서 상한 확정(r1+r2 전부 유의선 미달)",
                 "수익 상승은 선택(selection) 계층에서 — 타이밍 계층 아님"))
  ),
  charts=c(file.path(ST,"chart_refine_paired.png"), file.path(ST,"chart_refine_calmar.png")),
  footer="고정스냅샷=WT-D20260718_007_r1 · 측정=스크리닝(포지 아님) · r2판정=수익 graduation 미달·손익비 정제",
  force=TRUE
)
cat("[tg] ok=", isTRUE(res$ok), " bytes=", res$bytes %||% NA, " err=", res$error %||% "none", "\n", sep="")
