#!/usr/bin/env Rscript
# p8_reconcile.R — FQ-170 이중 아크 정합 기록 (ba4a1c30 vs 3ccb658c) + NP-5 재설계 처분
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-170"); stopifnot(length(i) == 1)

Q$entries[[i]]$dual_arc_reconciliation_20260809 <- paste0(
  "★이중 아크 정합 (규약: '두 판정이 다른 프레임에서 갈리는 것' 방지 — 늦은 발견, 버리지 않고 대조 라벨): ",
  "본 항목의 result/np1/np2_np4 = 세션 ba4a1c30 아크(본 원장 기록). 병렬로 세션 3ccb658c 이 ",
  "13라운드 아크를 수행(메모리 project-shape-is-routing-label-not-alpha-20260809, 원장 미기록). ",
  "**모순 없음 — 서로 다른 질문**: ba4a1c30 base = Q01 자기 top-25(재료-내부 차등: 'Q01 을 소비한다면 어디서' ",
  "→ 밴드 +5.62%p t 2.57 확립) / 3ccb658c base = M26 top-25(절대 경쟁력: '형태 활용이 강한 base 를 이기나' ",
  "→ 랭킹 축 3형태 전부 t<2 미달, 필터 축만 INVERTED(D03) +2.881 생존). ",
  "두 아크의 절대-수준 판정 일치: 밴드-Q01 절대 PORT_t 0.97 < M26 top-25 — ba4a1c30 의 '차등 규칙이지 ",
  "standalone 아님' 한정과 3ccb658c 의 '라우팅 라벨' 결론은 같은 메타 결론. ",
  "★교차 적용 교훈: (a) 3ccb658c 설계함정 #1 '밴드 내 상위 N = 밴드 top edge 측정'이 ba4a1c30 의 ",
  "NP-5 초안(D4~D6 내 상위 25)을 사전 무효화 — 혹 위치 D5 검정인데 top edge ≈ D6 을 재게 됨. ",
  "(b) #3 '필터형 대조군 = 동일강도 무작위'·#4 'draw 수 민감(2.18@20/1.70@50/2.05@100)' 는 ",
  "ba4a1c30 의 후속 셀 전부에 적용 의무. (c) ba4a1c30 의 배포 프레임 전이(cap-w +8.88%p)와 ",
  "위치-종속 실측(중립 D5 에 D8~D9 = 평평)은 3ccb658c 라우팅 표의 행 근거를 보강."
)
Q$entries[[i]]$next_action <- paste0(
  "[NP-5 재설계 — 초안 폐기] 3ccb658c 함정 #1 적용: '밴드 내 상위 25' 금지 → **밴드 전체 EW** 또는 ",
  "**밴드 내 무작위 25(다수 draw)** 로 재설계 + 동일강도 무작위 대조 + draw>=100. 유효분위 위치 필드로 ",
  "실효 밴드 위치 검증 의무. 첫 셀 = z_neutral D4~D6 전체 EW vs top-25. ",
  "[통합 후속] 두 아크의 라우팅 표 통합 — INVERTED 필터(3ccb658c 확립) x HUMP 밴드(ba4a1c30 확립) 를 ",
  "하나의 형태→소비면 표로. 전제 해소 필요: base 사후선택(production PG2 재현 P1)·INVERTED 표본 1건. ",
  "[잔존] FQ-171 census 완료 대기(신규 재료 일반화) · 소관: 이 항목의 추가 실측은 두 세션 간 중복 방지 위해 ",
  "본 next_action 을 먼저 갱신하고 착수할 것."
)
res <- write_frontier_queue(Q)
cat("[reconcile] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "두 세션이 같은 질문을 다른 각도로 풀었음을 확인 — 모순 없음, 교훈 교차 적용",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "형태 연구를 두 세션이 병렬 수행 — 다른 질문이라 모순 없고, 서로의 설계 결함을 잡아줬습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "발견: 다른 세션이 같은 주제로 13라운드를 병렬 진행한 것을 확인했습니다",
           "대조: 제 쪽은 '이 신호를 쓴다면 어디서', 그쪽은 '기존 강자를 이기나'였습니다",
           "정합: 두 답이 동시에 참 — 밴드는 자기 상단보다 낫지만 기존 강자엔 미달",
           "수확: 그쪽 설계 교훈이 제 다음 실험의 결함을 사전에 잡아냈습니다",
           "조치: 원장에 정합 기록을 남기고 다음 실험을 재설계했습니다")),
    list(type = "kv", emoji = "📊", heading = "정합 요지",
         kv = list(
           "제아크"   = "밴드 vs 자기 top-25 = +5.62%p (재료 내부 차등)",
           "병렬아크" = "랭킹 축 미달 · 역전형 필터만 +2.881 생존",
           "일치점"   = "형태는 자본 신호가 아니라 라우팅 라벨",
           "교차수확" = "'밴드 내 상위 N = 상단만 측정' 함정 사전 검거",
           "재설계"   = "밴드 전체 동일가중 + 무작위 대조 + draw 100")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "두 아크의 형태→소비면 라우팅 표 통합이 다음 단위입니다",
           "재설계된 위치-이동 검정은 원장에 등재해 뒀습니다",
           "판정: 자본 반영 없음 — 세션 간 정합 기록 완료"))
  ),
  footer = "📚 FQ-170 이중 아크 정합 · 3ccb658c x ba4a1c30",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
