setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")
CH <- "stage_artifacts/WT_D20260714_005/charts"
tg_agent_brief(
  agent = "Alpha",
  title = "R29 — Z6 가치축 미래참조-제거 재측정 ： 개선 소멸 （구성-한정 부정판정）",
  sections = list(
    list(type="summary", emoji="📌",
      body="미래참조 걷어내니 Z6 가치축 개선 t 3.81→1.02~1.72（문턱 2.0 미달）. 북 무변경 · dossier 승격 NO-GO."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c("R27은 '가치（싸게 사기）'축을 북에 섞으니 초과기여가 유의（t 3.81）하다고 판정했음.",
              "R28이 그 판정의 바탕 백테 패널이 '같은 달' 팩터데이터를 써서 top-25 성과가 ~2배 부풀려졌음을 발견（1개월 미래참조）.",
              "R29 = 부풀림 없는 '한 달 전（T-1）' 데이터로 북과 가치축을 다시 만들어 재측정.",
              "결과 ： 가치축 개선 t가 3.81 → 1.02~1.72로 내려앉아 합격선（2.0）을 못 넘음. 즉 R27의 개선은 상당분이 미래참조 착시였음.")),
    list(type="bullet", emoji="⚖️", heading="판정 （평문）",
      items=c("판정1： 저장 268m 패널 = 전기간 '같은 달' 팩터 = 1개월 미래참조. 운용 forward（T-1）는 clean.",
              "가치데이터 자체는 이미 clean（T-1과 상관 1.0） — 미래참조는 전적으로 base 패널.",
              "판정2： 구성-한정 부정판정 — clean 한계기여 t 1.02~1.72 < 2.0. R27 3.81=착시.",
              "단 '가치 죽음' 아님： clean에서도 t 3.06→3.85·EW t 6.39. 북 무변경, dossier 보류.")),
    list(type="kv", emoji="📊", heading="핵심 실측 （시가총액가중, 순비용 15bps）",
      kv=list(
        "배관 검증"="R27 정확 재현 paired t 3.738 （보고 3.807） → 측정 유효",
        "시점 교체（베이스만）"="미래참조 t 2.23／2.59 → clean t 1.02／1.33",
        "핵심 （clean）"="paired t 1.243 · IS 0.92 · HO 1.08 · ΔIR +0.153",
        "게이트（paired≥2.0 ∧ ΔIR≥0.05）"="전 clean 조건 미달 （t 1.02~1.72）",
        "가치데이터 시점"="가치 = 한달전（T-1）과 상관 1.0000 → 이미 clean")),
    list(type="kv", emoji="🔬", heading="실제 수치 （재산출 재료, 판정 아님）",
      kv=list(
        "clean 베이스 초과수익 t"="3.058／3.247 （저장/운용 가중）",
        "Z6 clean 변형 초과수익 t"="3.85／4.35 （가치 섞은 후）",
        "저장 미래참조 베이스（참고）"="5.24 （같은-달 부풀림, 2.08배）",
        "현직 북 고정값（참고만）"="6.130 — clean 재산출은 별도 심사（범위 밖）")),
    list(type="bullet", emoji="🧭", heading="기전 정합 （R27 검증은 왜 통과했나）",
      items=c("R27 placebo（p=0）·lag（2.98）은 '가치 신호 무결성'만 시험 → 결론 유지（가치=진짜·clean）.",
              "R27 미시험 = 베이스 패널 시점. 미래참조 베이스가 가치 한계이득 ~2배 증폭（ΔIR 0.153 vs 0.345）.",
              "즉 가치는 clean인데 그 한계기여가 부풀린 베이스 위에서 크게 측정됨 — 모순 없음.")),
    list(type="bullet", emoji="🚩", heading="주의 / 프론티어 （종결 아님）",
      items=c("cap-tier 국소화 벽 ： 가치 오버레이 EW기준 t 6.39 ≫ cap-w top-25 t 3.85 → 대형주 편중이 희석.",
              "→ FQ-045 신설 ： 가치를 cap-tier-조건부（중형·기타 슬리브）／EW-tilt로 재소비（cap-w 우회 프론티어）.",
              "FQ-044 후속 ： 저장 268m 패널 전량 clean（T-1） 재빌드 + 북 6.130 clean 재산출（judge 라운드）.")),
    list(type="bullet", emoji="➡️", heading="다음 （도훈 결정 / 자동 착수）",
      items=c("dossier 재발사 보류 — clean 기준 선별자격 미충족（FQ-042）.",
              "FQ-045 신설： 가치를 중형·기타 tier 조건부 또는 동일가중-틸트로 재소비.",
              "저장 268m 패널 clean 재빌드 + 북 6.130 clean 재산출 = 별도 심사（FQ-044）.",
              "L-AR-20260714_172027 · 사전등록 07744bdb · 북 무변경"))
  ),
  charts = c(file.path(CH,"r29_panel.png"))
)
cat("TG_SENT\n")
