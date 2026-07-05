suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
sections <- list(
  list(type="summary", emoji="💡",
       body="자가발전 사이클이 발견에 도달했습니다. post-2017 벽은 상당부분 벤치 아티팩트였고, 메가캡 앵커 구성이 배포성을 부활시킵니다."),
  list(type="kv", emoji="🔬", heading="4-사이클 자가발전 궤적",
       kv=list("사이클1 대형주 신호"="반증. 통찰: 크기는 안정하나 무알파, 알파는 감쇠",
               "사이클2 벤치 진단"="벽의 정체 = 대형주 지배 시총가중 지수 아티팩트",
               "사이클3 메가캡 앵커"="구성 레버 작동, 최근구간 유의성 6배 상승",
               "사이클4 적대검증"="통과 (가짜승자 아님)")),
  list(type="kv", emoji="📈", heading="발견: 메가캡 앵커 구성",
       kv=list("방식"="벤치 지배 상위2종을 20퍼센트 상한에 고정 + 나머지 알파",
               "포트알파 t값"="3.78 에서 4.76 (시총가중 대비)",
               "정보비율"="0.82 에서 0.99",
               "최근구간 t값"="0.41 에서 2.62 (2017년 이후)",
               "적대검증"="가짜알파 대비 엣지 +5.83, 위약검정 p 0.000, 시차 안정")),
  list(type="kv", emoji="🧭", heading="벽의 재해석",
       kv=list("핵심"="동일 알파가 동일가중 벤치 대비로는 최근에도 살아있음",
               "함의"="최근 알파 감쇠는 소멸이 아니라 대형주 집중레짐과 얽힘",
               "구조"="20퍼센트 상한 분산북이 삼성 하이닉스 지배 지수 못따라감")),
  list(type="text", emoji="⚠️", heading="정직 캐비앗 + 다음",
       body=paste0("이것은 스크리닝급 실측(정식 포지 계약 아님)이며 근사 재구성입니다. ",
                   "상위2종에 40퍼센트 집중 리스크가 있고 과적합 게이트는 조건부 구간(0.55)입니다. ",
                   "운용 북 변경 없음. 다음 = 정식 포지 재측정 + 북한계기여 + 집중리스크 판단은 도훈 확인 후. ",
                   "본 발견은 오늘 열두 건 벽확인을 뒤집는 첫 배포 레버입니다."))
)
res <- tryCatch(
  tg_agent_brief(agent="Q-Lead",
    title="자가발전 사이클 발견 - 메가캡 앵커 구성이 최근 배포성 부활",
    sections=sections, as_of="2026-07-05",
    lock_scope="qlead_megacap_anchor_discovery_20260705"),
  error=function(e){ cat("[TG] 실패:", conditionMessage(e), "\n"); NULL })
cat("[TG] result:", if(is.null(res)) "NULL" else "sent", "\n")
