suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

sections <- list(
  list(type="summary", emoji="🔒",
       body="자가진행: 오버레이 마지막 잔여(진짜 시장베타 틸트) 실측 종결. 저베타 종목은 현금을 대체 못함(기계적 확정)."),
  list(type="kv", emoji="📐", heading="진짜 시장베타 틸트 = 음성",
       kv=list("계산"="RAWDATA 252일 롤링 베타, 종목별 PIT",
               "베타 회전"="쌍대 t -2.33 (유의 열위)",
               "저베타 방어"="쌍대 t -1.6~-1.2, 낙폭 오히려 악화")),
  list(type="kv", emoji="🧱", heading="핵심 기계적 발견",
       kv=list("북 베타 이동"="강한 틸트에도 0.899 → 0.889 (거의 불변)",
               "이유"="선정 25종 풀의 베타 분산이 작음",
               "위기 최악월"="저베타 -3.1% 대 현금 0%",
               "결론"="저베타 종목선택은 현금 대체 불가, 베타 바닥 실재")),
  list(type="text", emoji="📌", heading="종결",
       body=paste0("오버레이 세 프론티어(게이트 형태·국면 구성·진짜 베타) 16변형 전부 실측 음성. ",
                   "현금 오버레이(R05×m4)가 유일한 롱온리 베타 레버인 이유를 기계적으로 증명. ",
                   "no_faith 샤프 1.898이 천장, 운용 북 변경 없음. ",
                   "오버레이 각도 완전 종결 → 남은 레버는 비수익 원천 또는 잔차 직교 슬리브뿐."))
)
res <- tryCatch(
  tg_agent_brief(agent="Q-Lead",
    title="오버레이 최종 종결 - 진짜 베타 틸트도 음성 (16변형 완료)",
    sections=sections, as_of="2026-07-05",
    lock_scope="qlead_overlay_beyond_r05m4_trackD_20260705"),
  error=function(e){ cat("[TG] 발송 실패:", conditionMessage(e), "\n"); NULL })
cat("[TG] result:", if(is.null(res)) "NULL" else "sent", "\n")
