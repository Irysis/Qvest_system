suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

sections <- list(
  list(type="summary", emoji="🔍",
       body="M4×R05 초월 오버레이 13변형 실측: 게이트 형태·홀딩스 구성 모두 베이스라인을 못 이김. 오버레이 프론티어 소진."),
  list(type="kv", emoji="📏", heading="베이스라인 재현 통과",
       kv=list("대상"="현행 북 R05×m4 (269개월)",
               "샤프(기하)"="1.895 (권위 1.898)",
               "포트알파 t값"="6.17 (권위 6.21)",
               "정렬검증"="한 달 앞 정렬 확인, 미래참조 없음")),
  list(type="kv", emoji="📉", heading="게이트 형태 정밀화 기각",
       kv=list("방식"="하드빈을 연속매핑으로, 평균노출 동일",
               "결과"="다섯 변형 전부 열위 (쌍대 t −1.1~−3.6)",
               "함의"="하드빈 위기집중 방어가 우월, 연속점프모형 국내 비이전",
               "최선흔적"="시장 위기확률 신호: 낙폭 개선이나 알파 희생·지연취약")),
  list(type="kv", emoji="🔁", heading="국면조건부 구성 무효",
       kv=list("방식"="핵심-방어 슬리브 회전 및 가중 틸트",
               "결과"="여덟 변형 전부 쌍대 t 비유의(절댓값 1 미만)",
               "함의"="롱온리 시장베타 0.92 바닥, 이름회전으론 위기방어 불가")),
  list(type="text", emoji="📌", heading="판정과 다음 방향",
       body=paste0("게이트 형태와 국면조건부 구성 두 오버레이 프론티어 모두 실측 음성입니다. ",
                   "공짜 점심 없음(낙폭 개선은 항상 실현 알파 희생으로 상쇄). ",
                   "자기 적대검증 통과, 운용 북 변경 없음. ",
                   "오버레이 각도 소진 → 자원은 비수익 원천(DART 내부자 이력) 또는 잔차 직교 슬리브로 전환을 권고합니다. ",
                   "미검증 잔여는 종목별 진짜 시장베타 틸트(기대효익 낮음)."))
)

res <- tryCatch(
  tg_agent_brief(agent="Q-Lead",
    title="M4xR05 초월 오버레이 연구 - 형태·구성 둘 다 음성 (13변형)",
    sections=sections, as_of="2026-07-05",
    lock_scope="qlead_overlay_beyond_r05m4_20260705"),
  error=function(e){ cat("[TG] 발송 실패:", conditionMessage(e), "\n"); NULL })
cat("[TG] result:", if(is.null(res)) "NULL" else "sent", "\n")
