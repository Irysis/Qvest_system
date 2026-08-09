## 적대검증 후속 3건을 FQ-122 에 서브라운드로 잠근다 (배분 전 등재 규약)
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries
i <- which(sapply(E, function(x) isTRUE(identical(x$id, "FQ-122"))))[1]
cat("[lock] FQ-122 인덱스:", i, "\n")
E[[i]]$verification_followup_20260809 <- list(
  owner = "Q-Lead session cee0bdd0 (2026-08-09) — 서브에이전트 배분",
  status = "in_flight",
  scope = paste(
    "적대검증 종합 우선순위 3·5·6 — 전부 WT-D20260808_001 산출물 위 재측정.",
    "①F3 β-drag t 를 lag>=59 (또는 Hansen-Hodrick) 로 재산출해 패키지·정본 **동시** 갱신 (기대 -5.07/-6.67).",
    "②D03 F2 를 윈저화(1%/99%)/순위 basis + 회전율 통제 포함으로 재측정 — 렌즈 반증(t -0.78/-0.55) 확정 또는 철회.",
    "③섹터-중립 β 로 F3 gap 재산출 — 렌즈4 단독 결과(D03 잔존 0.46 / **Q01 잔존 0.24**) 재현 여부.",
    "재현되면 Q01 gap 의 76% 가 종목 저β 가 아니라 섹터 구성 = 주장 A 크기의 존폐."),
  boundary = "FQ-165(M26 book-marginal)·FQ-173(인플레 나침반)과 파일·주제 무충돌. 발행 패널 유동성 수리(별건 결함 고지)는 이 라운드에 포함 — 같은 emit 경로를 손대므로 함께 처리."
)
q$entries <- E
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[lock] 잠금 완료\n")
