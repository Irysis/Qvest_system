suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

sections <- list(
  list(type="summary", emoji="🔍",
       body="M4×R05 초월 오버레이 13변형 실측: 게이트 형태·홀딩스 구성 모두 베이스라인을 못 이김. 오버레이 프론티어 소진."),
  list(type="kv", emoji="📏", heading="베이스라인 재현(PASS)",
       kv=list("대상"="no_faith = R05×m4 (269개월)",
               "SR_geo"="1.895 (권위 1.898)",
               "PORT_t"="6.17 (권위 6.21)",
               "정렬검증"="베타-scan offset+2=forward, 누출 없음")),
  list(type="kv", emoji="📉", heading="Track A 게이트 형태 = FALSIFIED",
       kv=list("방식"="하드빈→연속매핑, 평균노출 매칭",
               "결과"="5변형 전부 열위 (paired_t -1.1~-3.6)",
               "함의"="하드빈 위기집중컷 우월, Continuous-Jump KR 비이전",
               "최선흔적"="시장 crisis-prob: MDD 감소이나 alpha 희생+lag1 취약")),
  list(type="kv", emoji="🔁", heading="Track B/C 국면조건부 구성 = NULL",
       kv=list("방식"="Core-Defense sleeve 회전 + weight 틸트",
               "결과"="8변형 전부 |paired_t|<1 (비유의)",
               "함의"="long-only 베타 0.92 바닥 - 이름회전 위기방어 불가, 현금만 유효")),
  list(type="text", emoji="📌", heading="판정 + 다음",
       body=paste0("게이트 형태·구성 두 오버레이 프론티어 모두 measured-negative. 공짜점심 없음(MDD 감소는 항상 realized alpha 희생으로 상쇄). ",
                   "자기 적대검증(AX-008 2/3: Forge 실측+Self-Adv) 통과, book 무변경. ",
                   "오버레이 각도 소진 -> 자원은 비-return 원천(W3 DART insider 역사파싱) 또는 잔차-직교 sleeve로 전환 권고. ",
                   "미검증 잔여 = factor_db per-name 진짜 market-베타 틸트(저EV)."))
)

res <- tryCatch(
  tg_agent_brief(agent="Q-Lead",
    title="M4xR05 초월 오버레이 연구 - 게이트형태·구성 둘 다 negative (13변형)",
    sections=sections, as_of="2026-07-05",
    lock_scope="qlead_overlay_beyond_r05m4_20260705"),
  error=function(e){ cat("[TG] 발송 실패:", conditionMessage(e), "\n"); NULL })
cat("[TG] result:", if(is.null(res)) "NULL" else "sent", "\n")
