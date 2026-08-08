# run_fq122_telegram.R — FQ-122 결과 브리핑 + WT 상태 갱신
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(ggplot2); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001"; MBX <- "qepm/mailbox/worktask/WT-D20260808_001"
p2 <- readRDS(file.path(OUT, "fq122_part2.rds"))

# ── 차트 1: 팩터 x 가중규칙 한계기여 (부호 갈림 시각화) ──────────────────────
RECON <- p2$RECON[q == 0.20, .(cell = weighting, factor, d = d_ann_pct, t = paired_t)]
PROD  <- p2$PROD[!grepl("lag1", arm), .(cell = sub("_D03_EWMA|_Q01_EB", "", arm),
  factor = ifelse(grepl("D03", arm), "D03_EWMA", "Q01_EB"), d = d_ann_pct, t = paired_t)]
G <- rbind(RECON, PROD)
G[, cell := factor(cell, levels = c("W1_recon_ew25","W2_recon_tilt25","W3_prod_tilt20","W4_prod_ew20"))]
dir.create(file.path(OUT, "charts"), showWarnings = FALSE)
p <- ggplot(G, aes(x = cell, y = d, fill = factor)) +
  geom_col(position = position_dodge(0.75), width = 0.68) +
  geom_hline(yintercept = 0, linewidth = 0.6) +
  geom_text(aes(label = sprintf("%+.2f\n(t %+.2f)", d, t)),
            position = position_dodge(0.75), vjust = ifelse(G$d >= 0, -0.15, 1.1), size = 3.1) +
  scale_fill_manual(values = c(D03_EWMA = "#C0504D", Q01_EB = "#4F81BD")) +
  labs(title = "FQ-122 하위분위 제외필터 — 단일 대비 한계기여 (연 %, 순비용)",
       subtitle = "q=0.20 고정 · paired NW lag-3 · W3 = production 실코드(패리티 통과) · 전 셀 |t|<2",
       x = NULL, y = "연환산 한계기여 (%)", fill = "제외 팩터") +
  expand_limits(y = c(-6, 4)) +
  theme_minimal(base_size = 11) + theme(legend.position = "top")
ggsave(file.path(OUT, "charts/fq122_marginal.png"), p, width = 8.6, height = 5.0, dpi = 150)

# ── 차트 2: 신호 구조 (자기 분위별 forward active) ──────────────────────────
F1 <- data.table(
  factor = rep(c("D03_EWMA","Q01_EB"), each = 5),
  q = rep(paste0("Q", 1:5), 2),
  act = c(0.82, NA, 2.89, NA, -4.01, -2.83, NA, 2.39, NA, 1.81))
F1 <- F1[is.finite(act)]
p2c <- ggplot(F1, aes(x = q, y = act, group = factor, color = factor)) +
  geom_line(linewidth = 1.1) + geom_point(size = 3) +
  geom_hline(yintercept = 0, linetype = 2) +
  scale_color_manual(values = c(D03_EWMA = "#C0504D", Q01_EB = "#4F81BD")) +
  labs(title = "신호 구조 — 자기 분위별 초과수익 (연 %)",
       subtitle = "Q1=최저 z(고변동·불안정) · Q5=최고 z. D03 는 좌측 아닌 우측(Q5)이 유의 열위 = 베타 끌림",
       x = "자기 분위", y = "연 초과수익 (%)", color = NULL) +
  theme_minimal(base_size = 11) + theme(legend.position = "top")
ggsave(file.path(OUT, "charts/fq122_shape.png"), p2c, width = 8.6, height = 4.6, dpi = 150)

source("02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260808_001 ALPHA_DONE — FQ-122 전이-음성 팩터의 슬롯 없는 소비",
  sections = list(
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명", items = c(
      "시도: 순위 예측력은 있는데 상위 25종목에 넣으면 손해였던 팩터 2종을, 자리를 주지 않고 쓰는 두 방법으로 시험했습니다",
      "방법: 하위 20%를 빼는 필터 · 경계에서 순위를 가르는 용도 — 295개월 모의 운용(백테스팅)",
      "결과: 경계 용도는 착수 전 조건에서 걸려 측정하지 않았고, 필터는 D03 회수 실패 · Q01 방향은 좋으나 미확립",
      "의미: 실제 자본 배정 근거가 아니라 재료를 회수할 수 있는지 판정하는 라운드입니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 실측", kv = list(
      "타이브레이커" = "측정 전 기각 — 경계 구간 기울기 D03 -3.28%/yr · Q01 -3.26%/yr",
      "D03 제외필터" = "4개 가중 규칙 전부 음수. 24회 무작위 제외와 구별 불가(p=0.833)",
      "Q01 제외필터" = "포트폴리오 t값 2.050 -> 2.381 · 회전율 789 -> 768%/yr",
      "Q01 한계기여" = "재구성 +1.36%/yr(t 0.92) · 실배포 경로 +2.10%/yr(t 1.31)",
      "가중 규칙 갈림" = "실배포 동일가중에서 -1.54%/yr 부호 반전 -> 사전등록 요건 미충족",
      "검정력" = "전 셀 검정력 부족 (필요 연효과 3.02~4.47%, 표본 295개월)",
      "측정 무결성" = "실배포 재현 최대 편차 5.13e-16 (패리티 통과)")),
    list(type = "bullet", emoji = "🚩", heading = "기전이 팩터별로 갈렸습니다", items = c(
      "D03: 정보가 왼쪽 꼬리에 있다는 전제 기각(t -0.63). 유의한 이탈은 오른쪽 초저변동 꼬리(-6.90%/yr)",
      "D03 오른쪽 꼬리 베타 0.709 vs 유니버스 0.889 = 베타 끌림이 정체",
      "Q01: 왼쪽 꼬리 열위 유의(t -2.25) + 최상위 평탄(t -0.21) = 예측했던 손실회피 형태",
      "주체 정합 — 개인 순매수가 고변동·불안정 종목에 집중(동시기 관측)",
      "2017년 이후 동일가중 기준에서는 Q01 개선 소멸(1.507 -> 1.505)")),
    list(type = "bullet", emoji = "➡️", heading = "다음 라운드 (프론티어 등재 완료)", items = c(
      "FQ-122a — Q01 개선의 시기 편중을 연속 상호작용으로 규명 (구간 분할 금지)",
      "FQ-122b — 가중 규칙 부호 반전의 완결 귀속 (모든 제외필터 라운드 공통 판정 프레임)",
      "FQ-122c — 월당 관측수가 큰 형태로 검정력 회수 (구간 내 조건부 회귀)",
      "FQ-122d — D03 는 베타 예산 축으로 risk-research 이관"))),
  charts = c(file.path(OUT, "charts/fq122_marginal.png"), file.path(OUT, "charts/fq122_shape.png")))

# ── WT 상태 갱신 ────────────────────────────────────────────────────────────
st <- list(task_id = "WT-D20260808_001", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), blocker = NULL)
write_json(st, file.path(MBX, "status.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
gl <- fromJSON(file.path(MBX, "governance_log.json"), simplifyVector = FALSE)
ev1 <- list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), agent = "alpha-research",
  action = "ALPHA_PACKAGE_EMITTED",
  summary = paste0("FQ-122 (b) 제외필터 실측 완료. (a) 타이브레이커는 승계 F4 킬스위치로 측정 전 기각. ",
    "D03 소비 불가(플라시보 구별 불가 p=0.833) / Q01 미확립·생존(가중규칙 부호 갈림 + 검정력 부족). ",
    "PARITY GATE A PASS 5.13e-16. next_probe 4건 큐 등재."))
ev2 <- list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), agent = "alpha-research",
  action = "PROCEDURE_DEVIATION_DECLARED",
  summary = paste0("Q-Lead 지시의 wt_create() 신규 발급을 하지 않고 기존 WT-D20260808_001 을 승계했다. ",
    "사유: 착수 시점 FQ-122 owner/in_flight 가 이미 본 WT 였고 alpha_hypothesis.json(verdict=designed) 실재 — ",
    "신규 발급 시 동일 FQ in-flight 중복 실행. challenge_note.md C-9 기록, 사후 승인 요청."))
gl$events <- c(gl$events, list(ev1), list(ev2))
write_json(gl, file.path(MBX, "governance_log.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("[tg] 상태·거버넌스 갱신 완료\n")
