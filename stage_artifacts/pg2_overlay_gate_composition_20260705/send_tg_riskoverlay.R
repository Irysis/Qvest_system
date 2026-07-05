suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
sections <- list(
  list(type="summary", emoji="🛡️",
       body="리스크 오버레이로 스코프 복귀 후 실제 개선 발견. 다층 곱셈 오버레이가 현행 M4xR05 디리스킹을 전 위험지표에서 지배합니다."),
  list(type="kv", emoji="🔭", heading="렌즈 교정이 열쇠였다",
       kv=list("잘못된 렌즈"="오버레이를 알파 짝지은 t값으로 재단 (A5 기각 오류)",
               "올바른 렌즈"="위험 조건부 평가 (최대낙폭 칼마 꼬리위험 위기손실)",
               "이유"="오버레이 임무 = 작은 수익 대가로 하방 보호")),
  list(type="kv", emoji="📊", heading="다층 곱셈 오버레이 (도훈 지시)",
       kv=list("현행 2층 m4xR05"="최대낙폭 0.233 칼마 1.94 샤프 1.90",
               "3층 +점프모델 베어확률"="최대낙폭 0.185 칼마 2.49 샤프 2.10",
               "4층 +위기확률"="샤프 2.12 위기손실 최소",
               "개선폭"="최대낙폭 -21퍼센트 칼마 +28퍼센트 꼬리위험 감소 수익도 상승")),
  list(type="kv", emoji="🧩", heading="왜 작동하나",
       kv=list("핵심"="서로 다른 위험 계층을 곱셈 결합 (꼬리 점프 위기)",
               "직교성"="베어확률과 R05 상관 0.40 = 다른 위험 포착",
               "곱셈이 필수"="최댓값 결합은 실패 = 컴파운드 디리스킹이 핵심")),
  list(type="kv", emoji="🔬", heading="검증 통과",
       kv=list("위약검정 200회"="최대낙폭 칼마 샤프 전부 p 0.000",
               "부분기간"="전반 후반 양쪽 개선",
               "시점무결성"="점프모델 = 워크포워드 온라인 (미래참조 없음 확인)",
               "시차 안정"="기준선 시차와 동등 이상")),
  list(type="text", emoji="⚠️", heading="정직 캐비앗 + 다음",
       body=paste0("스크리닝급(재구성 기반)이며 정식 포지 재측정과 다중검정 게이트가 남았습니다. ",
                   "약 16개 구성 탐색이나 메커니즘은 사전 지정(도훈 지시)이고 여러 구성서 일관됩니다. ",
                   "운용 북 변경 없음. 다음 = 정식 포지 확정 + 라이브 노출 영향 + 도훈 확인 후 거버넌스. ",
                   "리스크 오버레이 파트로 돌아오니 실제 개선이 나왔습니다."))
)
res <- tryCatch(
  tg_agent_brief(agent="Q-Lead",
    title="리스크 오버레이 발견 - 다층 곱셈(점프모델 베어확률)이 M4xR05 디리스킹 지배",
    sections=sections, as_of="2026-07-05",
    lock_scope="qlead_riskoverlay_multilayer_bearprob_20260705"),
  error=function(e){ cat("[TG] 실패:", conditionMessage(e), "\n"); NULL })
cat("[TG] result:", if(is.null(res)) "NULL" else "sent", "\n")
