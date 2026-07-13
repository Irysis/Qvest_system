#==============================================================================
# WT-D20260713_001 R17 — Step 05: Telegram v7 판정 보고 (차트 첨부 의무, 원칙 9)
#==============================================================================
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_001")
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
charts <- readLines(file.path(OUT,"chart_paths.txt"))
# order: sweep bar first (판정 요약), then best-factor 3종
charts <- c(charts[grepl("sweep",charts)], charts[!grepl("sweep",charts)])

sections <- list(
  list(type="summary",
       body="보유 자산만으로 만든 신규 팩터 3종(텍스트 유사도·제출 지연·내부자 공시량) 모두 편입 문턱 미달, 생존자 0. 데이터 추가 없이 호출 0."),
  list(type="text", heading="🔎 쉬운 설명",
       body="이미 크롤해 둔 사업보고서 본문과 공시 기록에서 세 가지 새 신호를 만들어 실제 상위 25종목 포트폴리오로 검증했습니다. 문턱은 실현 초과수익의 통계적 강도(t값 2.95). 셋 중 제출 지연이 가장 나았지만 1.29로 한참 미달했고, 가짜신호 대조(순서 섞기)도 통과하지 못했습니다. 결론은 '틀림'이 아니라 '이 구성으로는 약함, 다음 시도 표시'입니다."),
  list(type="kv", heading="📊 3종 판정 (실현 초과수익 t값, 문턱 2.95)",
       kv=list(
         "F-A 텍스트 유사도"="1등 신호값 0.72 · 넓은시장 대비도 음수 · 가짜신호 대조 실패",
         "F-B 제출 지연(선두)"="1.29 · 크기효과 제거 후에도 1.10 유지 · 방향 일관하나 약함",
         "F-C 내부자 공시량 급변"="1.17 · 앞뒤 기간 불안정 · 회전율 과다 · 노이즈 확증",
         "생존자"="0종 (신규 팩터 온보딩 권고 없음)")),
  list(type="bullet", heading="🚩 자가 적대검증 요지",
       items=c(
         "텍스트 유사도는 크기효과 제거 후에도 신호가 없어 확증됨 — 방향을 뒤집으면 약한 양수(1.38)라 한국형 반전 가능성만 표시",
         "제출 지연은 순수 소형주 대리가 아님(크기 제거해도 대부분 생존) — 소형주 문제가 아니라 신호 강도 문제",
         "내부자 공시량은 가짜신호 대조 실패로 노이즈 확정 + 회전율 과다로 비용에 취약")),
  list(type="bullet", heading="➡️ 다음 시도 표시",
       items=c(
         "제출 지연을 선두 후보로 오버레이(국면·시장민감도) 결합 검토",
         "텍스트 유사도는 본문 전체(도입부 8천자 아닌 전문) 재추출 후 재검증 — 내부자 백필 종료 뒤 여유 할당량에서",
         "내부자 공시는 급변 대신 수준값 또는 방향서명 밀도로 재설계")))

res <- tg_agent_brief(
  agent="Alpha",
  title="WT-D20260713_001 R17 판정 — 보유 데이터 신규 팩터 3종 (생존자 0, config-scoped negative)",
  sections=sections, charts=charts,
  footer="원천: text_cache 4,490 · filings_inventory 8,229 · insider_activity 13,440. DART 호출 0(백필 보호). 상세: alpha_validation.json")
cat("[05] telegram sent:", isTRUE(res$ok %||% res), "\n")
