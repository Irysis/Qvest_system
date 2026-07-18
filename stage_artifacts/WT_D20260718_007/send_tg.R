#!/usr/bin/env Rscript
Sys.setlocale("LC_ALL","English_United States.utf8")
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/telegram/telegram_notify.R")
ST <- "stage_artifacts/WT_D20260718_007"
res <- tg_agent_brief(
  agent="Alpha",
  title="WT-D20260718_007 ALPHA_DONE — 비지도 autoencoder regime detector (M4 BOCPD 대체 timing overlay)",
  as_of="2026-07-18",
  sections=list(
    list(emoji="📌", heading="한 줄 결론 (판정 조건부 양성)", type="bullet",
         items=c("비지도 오토인코더(재구성오류)가 WT-004 근본원인(미학습 폭락 미포착) 해결",
                 "2008 금융위기 9개월 전부 방어 발화 — 인컴번트 6/9·WT-004 지도학습판 0/9",
                 "위기 방어발화 상관 인컴번트의 2배 · 손익비 2.07→2.20 개선(2008 제외해도 유지)",
                 "단 월별 초과수익 검정 유의성 없음 → 꼬리위험 개선 실재·수익 개선은 비유의",
                 "→ 리스크리서치 진행 권고(앙상블 꼬리위험 보완)")),
    list(emoji="🔬", heading="Step 0 차별 (재탕 아님)", type="bullet",
         items=c("WT-004=지도학습(라벨·미학습 폭락 실패) vs 본건=비지도(이탈도·회피)",
                 "인컴번트=단변량 통계 변화점 vs 학습형 다변량 시퀀스 이상탐지",
                 "과거 #9506 오토인코더는 단독전략(낙폭 51.7%)이지 인컴번트 대체 overlay 아님")),
    list(emoji="📊", heading="book 오버레이 A/B 실측 (비중 고정·15bps)", type="kv",
         kv=list(
           "월별 방어발화율 (목표 0.126)"="인컴번트 0.126 / 시퀀스 0.172 / 포인트 0.199",
           "손익비 (인컴번트→시퀀스)"="2.069 → 2.196 (+0.127)",
           "최대낙폭 (인컴번트→시퀀스)"="-18.7% → -17.0%",
           "샤프지수 (인컴번트 vs 시퀀스)"="1.809 vs 1.809 (동률)",
           "월별 초과수익 짝검정 t값"="-1.49 (비유의·음수)",
           "위기 방어발화 상관 (인컴/시퀀스/포인트)"="0.062 / 0.124 / 0.148",
           "위기월 완충 (인컴번트/시퀀스)"="-2.84% / -2.75% (소폭 개선)")),
    list(emoji="🛡️", heading="미래참조 방지 3종 (동월 누출 재발방지)", type="kv",
         kv=list(
           "오버레이 미래참조 가드"="통과 0/221 위반",
           "엄격 미래참조 A/B 인플레"="샤프 +0.2% / 초과수익t -0.7% (정상)",
           "1기 지연 스트레스"="1.809→1.802 (붕괴 없음)",
           "프로덕션 일치"="정확 일치 (기준 1.8088)",
           "워크포워드"="표본외 발화율 상승=외삽=누출 반증")),
    list(emoji="🚩", heading="자가 적대검증 (약점 공개)", type="bullet",
         items=c("월별 수익 짝검정 비유의 → 수익 개선 주장 안 함. 개선은 꼬리위험(손익비/최대낙폭)에 국한",
                 "발화율이 목표 초과(0.172) → 단 표본외 샤프가 인컴번트보다 높아 과잉방어 아님(타이밍 품질)",
                 "포인트 변형은 손익비에서 인컴번트 미달(1.976) — 전 변형 승리 아님(정직 공개)",
                 "급성 미학습 폭락 전문(2008/코로나), 완만한 하락(2011/2018/2022) 미포착 → 인컴번트와 상보")),
    list(emoji="➡️", heading="다음 단계", type="bullet",
         items=c("리스크리서치 권고: 인컴번트(광범위)+오토인코더(급성 폭락) 앙상블 꼬리보완 평가",
                 "발화 임계값을 목표 0.126으로 정확 재매칭(과잉방어 요인 제거)",
                 "완만한 하락 커버용 낙폭지속기간 신호 추가"))
  ),
  charts=c(file.path(ST,"chart_calmar_sweep.png"), file.path(ST,"chart_crisis_firing.png")),
  footer="고정스냅샷=WT-D20260718_007_r1 · 측정=스크리닝(포지 확정 아님) · 판정=조건부 양성"
)
cat("[tg] ok=", isTRUE(res$ok), " bytes=", res$bytes %||% NA, " err=", res$error %||% "none", "\n", sep="")
