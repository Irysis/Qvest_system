suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
sections <- list(
  list(type="summary", emoji="🔧",
       body="정직 교정: 앞서 보고한 메가캡 앵커 발견은 실제 오버레이 배포북 측정에서 마일스톤이 아님으로 확인됐습니다."),
  list(type="kv", emoji="📉", heading="사이클5 배포북 측정 (실제 오버레이 적용)",
       kv=list("총수익 샤프"="1.142 에서 1.044 로 하락",
               "북한계기여 짝지은 t값"="-1.52 (음수)",
               "정보비율 변화"="+0.089 (거버넌스 게이트는 통과)",
               "과적합 게이트"="0.535 (조건부 구간, 미달)")),
  list(type="kv", emoji="🧠", heading="교정 결론",
       kv=list("앵커의 정체"="추가 수익이 아니라 추적오차 축소(벤치 허깅)",
               "이유"="저수익 메가캡 40퍼센트가 알파를 희석",
               "판정"="배포성 개선 기법이지 샤프 2.5 레버 아님")),
  list(type="kv", emoji="💎", heading="살아남은 진짜 부수발견",
       kv=list("확립"="최근 알파 감쇠는 상당부분 시총가중 벤치 아티팩트",
               "증거"="동일 알파가 동일가중 벤치 대비로는 최근 t값 2.04로 생존",
               "함의"="앞으로 알파 기각 전 동일가중 대비 검증 필요")),
  list(type="text", emoji="🔄", heading="계속",
       body="마일스톤까지 자가발전 지속. 다음 = 미탐색 비차단 데이터원(수급 플로우 피처)으로 사이클 계속. 운용 북 변경 없음.")
)
res <- tryCatch(
  tg_agent_brief(agent="Q-Lead",
    title="정직 교정 - 메가캡 앵커는 마일스톤 아님(추적오차 축소), 벤치 진단은 확립",
    sections=sections, as_of="2026-07-05",
    lock_scope="qlead_megacap_anchor_correction_20260705"),
  error=function(e){ cat("[TG] 실패:", conditionMessage(e), "\n"); NULL })
cat("[TG] result:", if(is.null(res)) "NULL" else "sent", "\n")
