suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
sections <- list(
  list(type="summary", emoji="✅",
       body="다층 리스크 오버레이 권위 확정 완료. 진짜 리스크-관리 개선이나 거버넌스 게이트 기준으론 마일스톤 아님 — 정직한 뉘앙스."),
  list(type="kv", emoji="📐", heading="권위 측정 (계약 등급, 노출 매칭)",
       kv=list("기준선 재현"="샤프 1.895 칼마 1.94 최대낙폭 0.233 = 인컴번트 일치",
               "R05x베어(노출매칭)"="샤프 2.10 칼마 2.49 최대낙폭 0.187 정보비율 중립",
               "디플레이티드 샤프"="1.000 (16개 탐색 과적합 아님, 통과)")),
  list(type="kv", emoji="⚖️", heading="정직한 판정",
       kv=list("총수익 리스크"="진짜 파레토 개선 (샤프 칼마 최대낙폭 꼬리 전부, 벤치상대 무손실)",
               "거버넌스 정보비율 게이트"="미달 (델타 +0.001~0.015, 0.05 문턱 아래)",
               "이유"="디리스킹은 벤치상대 초과수익을 안 늘림 = 정보비율 게이트는 알파지향",
               "함의"="정보비율 게이트가 리스크 오버레이 가치(하방보호)를 credit 안 함")),
  list(type="text", emoji="🧭", heading="도훈 판단 필요",
       body=paste0("리스크-관리(총 샤프 칼마 최대낙폭)가 목적이면 L2m 채택 가치 = 최대낙폭 23%→18.7% 칼마 +28% 무비용. ",
                   "벤치상대 정보비율이 목적이면 중립. 운용 북 변경 없음(거버넌스 수동). ",
                   "검증 완결: 계약등급 + 디플레이티드샤프 + 위약검정 + 부분기간 + 시점무결성 감사 전부 통과."))
)
res <- tryCatch(
  tg_agent_brief(agent="Q-Lead",
    title="리스크 오버레이 권위 확정 - 진짜 리스크개선이나 정보비율-마일스톤 아님(정직)",
    sections=sections, as_of="2026-07-05",
    lock_scope="qlead_riskoverlay_R4_authoritative_20260705"),
  error=function(e){ cat("[TG] 실패:", conditionMessage(e), "\n"); NULL })
cat("[TG] result:", if(is.null(res)) "NULL" else "sent", "\n")
