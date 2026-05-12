#==============================================================================
# 5 Path 비교 평가 — 1순위 선정 텔레그램 brief (v6.2 SOT 정합)
#==============================================================================

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Alpha",
  title = "한국 환경 정합 4번째 직교 알파 sleeve 5개 비교 — 1순위 거시 잔차 long-horizon 선정",
  sections = list(

    list(type = "summary", emoji = "📌",
         body = "한국 주식 long-only 4번째 직교 알파 sleeve 5개 path 자율 비교 — 거시 잔차 long-horizon 1순위 선정 (27/30)."),

    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "[목적] 한국 주식 long-only 환경 정합 4번째 직교 알파 sleeve 후보 발굴",
           "[중단 사유] WT_003 변동성 위험 프리미엄 진입 직전 도훈 명시 — 옵션 미거래 + 거래소 chain 미가입",
           "[선행 실패 3건] 변동성 1차 / 머신러닝 잔차 v4 미래참조 / v5 honest 실패",
           "[결론] 거시 잔차 long-horizon 점수 27/30 (0.900) — 1순위 권고"
         )),

    list(type = "kv", emoji = "📊", heading = "5 path 종합 점수",
         kv = list(
           "거시 잔차"   = "27/30 (1위)",
           "위기 방어"   = "26/30 (2위)",
           "다중 주파수" = "21/30 (3위)",
           "강화학습"    = "18/30 (4위)",
           "대체 정서"   = "14/30 (5위)"
         )),

    list(type = "bullet", emoji = "🏆", heading = "1순위 거시 잔차 근거",
         items = c(
           "한국 거시 (산업생산 / M2 / 환율) × KOSPI 잔차 → 종목 cross-section",
           "Cooper-Gulen-Schill 2008 RFS / Belo-Lin-Vitorino 2014 RFS 학술",
           "L-454 한국 내부 우선 / L-280 cross-section 직교 / L-281 Hybrid 진화",
           "ECOS + FRED + Factor DB 즉시 가용 (별도 인프라 부담 0)",
           "예상 회전율 150~300% — hurdle 600% 자연 회피",
           "Hybrid 3-source 직교성 cor 0.10~0.25 추정 (낮음)"
         )),

    list(type = "bullet", emoji = "🚩", heading = "잔존 위험 / 한계",
         items = c(
           "한국 거시 단일 factor M21~M29 정보계수 안정성 0.10~0.18 약함 — 잔차화 + cross-section 결합 boost 의무",
           "Mei-Wu 2014 거시 신호 노이즈 제거 + Harvey 2017 다중검정 t값 3.0 의무",
           "factor zoo overfitting 위험 — 직교성 검증 + DSR 디플레이티드 샤프 동시 의무",
           "한국 적용 학술 사례 일부만 (이상혁 외 2018 / Lee-Ohk 2014) — 사이클 재현 가능성 부분 검증"
         )),

    list(type = "bullet", emoji = "🔻", heading = "타 path 탈락 사유",
         items = c(
           "위기 방어 — STR_1715 + KR 10y bond ETF가 이미 defense 차지 (4번째 직교 의의 약함)",
           "다중 주파수 — STR_1715 자체 monthly + 일간 M4 overlay 사용 중 (직교성 모호)",
           "강화학습 — WT_002 v4 머신러닝 잔차 trauma 재발 위험 highest (in-sample 0.30 → OOS 0.05~0.15)",
           "대체 정서 — 한국 뉴스 NLP 인프라 미구축 + 외부 데이터 전송 mandate (Prohibition #12) 검토 의무"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 단계 (도훈 결정 input)",
         items = c(
           "정식 WT-D20260509_001 진입 — Path 1 거시 잔차 long-horizon (도훈 승인 의무)",
           "Step 0 가설 spec — ECOS / FRED 잔차화 + 종목 cross-section + 직교성 target rho < 0.25",
           "graduation 기준 inherit — Harvey-t > 3.0 / DSR > 0.5 / 정보계수 안정성 > 0.20"
         ))
  )
)

cat("[OK] Telegram brief sent.\n")
