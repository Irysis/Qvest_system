# =============================================================================
# send_telegram.R — WT-D20260803_005 (FQ-131) 알파 브리핑
#   SOT: .claude/skills/qvest-telegram/SKILL.md — tg_agent_brief() 단일 진입점
#   계약: text body 30~220자 / bullet 항목 <=80자·>=2개 / kv 값 <=60자·>=2개
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/send_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
source("02_Infrastructure/telegram/telegram_notify.R")

P1R <- readRDS(file.path(OUT, "persistence_results.rds"))
P2R <- readRDS(file.path(OUT, "persistence_results2.rds"))
DBR <- readRDS(file.path(OUT, "dualbasis_results.rds"))
GSp <- P2R$gate_sim$primary
tb  <- P2R$bin_ci[grid == "primary" & bin == "[2,inf)"]
nm  <- mean(P1R$nulls$primary[is.finite(P1R$nulls$primary)])

CH <- file.path(OUT, "charts")
charts <- c(file.path(CH, "wt005_era_dualbasis.png"),
            file.path(CH, "wt005_persistence_bins.png"),
            file.path(CH, "wt005_gate_sim.png"))
charts <- charts[file.exists(charts)]

sections <- list(
  list(type = "summary", emoji = "\U0001F4CC",
       body = "팩터 285개 x 5년 창 4개 실측 — 자격 판정에 유통기한이 없다"),
  list(type = "text", emoji = "\U0001F9D1\u200D\U0001F3EB", heading = "쉬운 설명",
       body = paste0("\"이 팩터 좋다\"는 판정이 얼마나 오래 가는지 쟀습니다. ",
         "판정이 유지되는 길이가 창을 5년/3년/2년 무엇으로 잡든 항상 창 2.2~2.4개였습니다. ",
         "달력 수명이 있으면 개월수가 같아야 하는데 136/86/53개월로 창 길이를 따라갔습니다.")),
  list(type = "text", emoji = "\U0001F50E", heading = "그래서 무슨 뜻인가",
       body = paste0("판정이 시간이 지나 낡는 게 아니라, 애초에 그만큼 흐릿했다는 뜻입니다. ",
         "그리고 판정이 유지되는지 아닌지는 그 팩터가 아니라 그 시기의 시장 국면이 정합니다.")),
  list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (창 60개월, 사전등록)",
       kv = list(
         "판정 유지 확률" = sprintf("%.3f (전이군집 구간 %.3f~%.3f, 0.5 미배제)",
              P1R$pp$primary[["p"]], DBR$time_boot[grid=="primary", lo], DBR$time_boot[grid=="primary", hi]),
         "잡음만 있는 세계의 값" = sprintf("%.3f — 관측값이 이 분포 안(60.2 백분위)", nm),
         "가장 강한 판정 유지율" = sprintf("%.3f (%.3f~%.3f) 동전던지기", tb$p, tb$lo, tb$hi),
         "국면 유지 시 vs 전환 시" = "0.959 vs 0.304",
         "문턱 2.0 선발 결과" = sprintf("다음 창 t 평균 %+.3f, 양수 %.0f%%",
              GSp[tau==2, mean_t_next], 100*GSp[tau==2, share_pos_next]),
         "판정=국면 라벨 일치율" = sprintf("시총가중 %.3f / 동일가중 %.3f",
              mean(DBR$era_share$agree_cap), mean(DBR$era_share$agree_ew)))),
  list(type = "bullet", emoji = "\U0001F52C", heading = "지배 기전",
       items = c(
         "시총가중 벤치 기준 창별 양수 팩터 비율 0.75 / 0.91 / 0.22 / 0.02",
         "최근 5년엔 285개 중 6개만 벤치를 이겼다 — 초대형주 편중 국면",
         "동일가중 벤치로 바꾸면 0.37 / 0.50 / 0.42 / 0.48 로 진폭 소멸",
         "그런데 지속성은 벤치를 바꿔도 그대로 (0.607 대 0.578)",
         "판정 수준은 벤치 구성이, 지속성은 추정 잡음이 지배한다",
         "정렬 방향이 원인인가 검증 → 차이 +0.012 로 기각")),
  list(type = "bullet", emoji = "\U0001F9ED", heading = "조건별 안정성 (방향만)",
       items = c(
         "성장 0.667 · 수급흐름 0.667 · 퀄리티 0.659 · 모멘텀 0.655",
         "방어 0.465 · 유동성 0.487 — 동전던지기 이하",
         "방어형은 위기 캘린더 종속 (상관 0.842) 이라 별도 취급",
         "보유 시총 클수록 불안정: 대형 0.514 < 중형 0.604 < 소형 0.614",
         "회전율 실측은 높음 0.613 > 낮음 0.558 — 등록 라벨과 반대")),
  list(type = "bullet", emoji = "\U0001F6A9", heading = "정직 고지",
       items = c(
         "사전등록 위반 주입 판정식 미발화 — 집계 통계가 둔감했다",
         "다만 기울기 0.277→0.557, 최강 구간 0.500→0.791 로 누출 지문은 뚜렷",
         "팩터 285개는 독립 아님 — 주성분 90%가 39개, 제1주성분 분산 56%",
         "자가 적대검증이 내 산출물 결함 2건 검출, 둘 다 판정 불변 확인",
         "게이트가 미래참조 1건 차단 → 원인 규명·정량화·정정 후 통과")),
  list(type = "bullet", emoji = "\U0001F449", heading = "다음",
       items = c(
         "국면 공통성분을 미리 추정 가능한가 — 되면 문제가 국면 타이밍으로 이동",
         "국면 제거 후 상대 순위가 자본으로 전이되는가 (순위상관 0.20 생존)",
         "중형주 대역으로 유니버스를 좁히면 판정 안정성이 오르는가",
         "부활 조건은 비수익 원천 팩터 0.70 돌파 또는 전이 표본 6개 확보"))
)

res <- tg_agent_brief(agent = "Alpha",
  title = "WT-D20260803_005 알파 완료 — 자격 판정에 유통기한이 없다",
  sections = sections, charts = charts,
  footer = "판정 근거 = canonical screening 실측(시총가중 벤치). 자본 후보 아님, 비중·공분산 미산출.")
cat("[wt005] telegram 발송 결과:\n"); str(res, max.level = 2)
