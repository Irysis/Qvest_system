## p7 — 텔레그램 보고 (실측 수치 포함 → 원칙 9 차트 의무)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/ladder_sweep")
say  <- function(fmt, ...) { cat(sprintf(paste0("[tg] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- fread(file.path(OUT, "decompose.csv"))
setorder(R, t_capw)
short <- sub("_.*$", "", R$factor); short <- paste0(short, "_", substr(sub("^[^_]*_", "", R$factor), 1, 6))

## 차트 1 — basis 전환의 t 변화 (양수는 커지고 음수는 더 작아진다 = 배율기 지문)
c1 <- tg_chart_sweep(
  labels = short, values = round(R$t_ew - R$t_capw, 3), out_dir = OUT,
  title = "basis 전환 시 t 변화 — 부호를 따라간다 (배율기 지문)",
  value_label = "t(EW) - t(cap-w)", hline = 0, hline_label = "변화 없음",
  filename = "ch1_t_shift.png")

## 차트 2 — se 비율 (모든 재료에서 1 미만 = 분모 축소)
c2 <- tg_chart_sweep(
  labels = short, values = round(R$se_ratio, 3), out_dir = OUT,
  title = "active 변동성 비율 se(EW)/se(cap-w) — 전 재료 1 미만",
  value_label = "se 비율", hline = 1.0, hline_label = "동일 (1.0)",
  filename = "ch2_se_ratio.png")

## 차트 3 — 채널 크기 비교 (mean vs se)
c3 <- tg_chart_sweep(
  labels = c(paste0(short, " · mean"), paste0(short, " · se")),
  values = round(c(R$contrib_mean, R$contrib_se), 3), out_dir = OUT,
  title = "t 변화의 채널 분해 — mean 이동 vs se 축소",
  value_label = "t 기여", hline = 0, hline_label = "0",
  filename = "ch3_channels.png")
say("차트 3종 생성")

tg_agent_brief(
  agent = "Q-Lead",
  title = "성과 측정 자 바꾸기 검거 — 어제 판정 근거 정정 + 계약 수리",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "\uc624\ub298 \uc81c\uac00 \"\uae30\uc900\uc744 \ubc14\uafc0\uba74 \ud569\uaca9\uc120\uc744 \ub118\ub294\ub2e4\" \uace0 \ubcf4\uace0\ud55c \uac83\uc774 \ud2c0\ub838\uc2b5\ub2c8\ub2e4. \uc9c1\uc811 \uc7ac\uce21\uc815\ud574 \ubc14\ub85c\uc7a1\uace0 \uc7ac\ubc1c \ubc29\uc9c0 \uc7a5\uce58\uae4c\uc9c0 \ub2ec\uc558\uc2b5\ub2c8\ub2e4."),
    list(type = "bullet", emoji = "\U0001F4D6", heading = "\uc27d\uc740 \uc124\uba85",
         items = c(
           "\ubc30\uacbd: \uc131\uacfc\ub97c \ucc44\uc810\ud560 \ub54c \ube44\uad50 \uae30\uc900(\ubca4\uce58\ub9c8\ud06c)\uc744 \ub458 \uc4f0\uace0 \uc788\uc5c8\uc2b5\ub2c8\ub2e4",
           "\uc624\ud574: \ub458\uc9f8 \uae30\uc900\uc73c\ub85c \ubcf4\uba74 \uc810\uc218\uac00 \uc62c\ub77c\uac00 '\uc9c4\uc9dc \uc2e4\ub825\uc774 \ub4dc\ub7ec\ub09c \uac83' \uc73c\ub85c \uc77d\uc5c8\uc2b5\ub2c8\ub2e4",
           "\uc7ac\uce21\uc815: \uc810\uc218\uac00 \uc624\ub978 \uac8c \uc544\ub2c8\ub77c **\uc790 \ub208\uae08\uc774 \ubc14\ub00c\uc5c8\ub358 \uac83**\uc785\ub2c8\ub2e4 (1.37\ubc30 \ud655\ub300)",
           "\uc99d\uac70: \uc2e4\ub825\uc774 **\ub098\uc05c** \uc7ac\ub8cc 5\uac1c\ub97c \uac19\uc740 \uc790\ub85c \uc7ac\ub2c8 \ub354 \ub098\uc05c \uc810\uc218\uac00 \ub098\uc654\uc2b5\ub2c8\ub2e4",
           "\uc758\ubbf8: \uadf8 \uc804\ub7b5\uc740 \ud569\uaca9\uc120\uc744 \ub118\uc9c0 \ubabb\ud588\uace0, \uc2e4\uc81c \uc790\ubcf8\uc740 \ub4e4\uc5b4\uac00\uc9c0 \uc54a\uc2b5\ub2c8\ub2e4")),
    list(type = "kv", emoji = "\U0001F4CA", heading = "\ud575\uc2ec \uc218\uce58",
         kv = list(
           "\ubcc0\ub3d9\uc131\ube44" = "0.729 (\ubd84\ubaa8 \uc544\ub2cc \ubd84\ubaa8 \ucd95\uc18c)",
           "\ud655\ub300\ubc30\uc728" = "x1.371 (\ubd80\ud638 \ubb34\uad00)",
           "\ud56d\ub4f1\uac80\uc99d" = "2.363x1.406-0.268 = 2.946 = \uc2e4\uce21",
           "\uc815\uc815 \uadc0\uc18d" = "\ube44\uc6a9 23% / \uc2e0\ud638\ubd80\uc871 77%",
           "\uac80\uc0ac" = "22/22 (\uc704\ubc18 \uc8fc\uc785 \ud3ec\ud568)")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "\uc8fc\uc758",
         items = c(
           "\uc774 \ud568\uc815\uc740 \uc5b4\uc81c\ub3c4 \ud55c \ubc88 \uc7a1\ud614\uace0 \uae08\uc9c0 \uaddc\uce59\uae4c\uc9c0 \uc788\uc5c8\ub294\ub370 \uc624\ub298 \ub610 \ubc1f\uc558\uc2b5\ub2c8\ub2e4",
           "\uae30\ub85d\ubb38 4\uacf3\uc73c\ub85c \ubc88\uc9c4 \ub4a4 \ubc1c\uacac\ub3fc \uc804\ubd80 \ub418\ub3cc\ub838\uc2b5\ub2c8\ub2e4",
           "\uaddc\ubc94\uc73c\ub85c\ub294 \uc548 \ub9c9\ud600 \uc0b0\ucd9c \ucf54\ub4dc \uc790\uccb4\uc5d0 \uacbd\uace0\ub97c \ubc15\uc558\uc2b5\ub2c8\ub2e4",
           "\uc815\uc815\ud558\ub294 \uacfc\uc815\uc5d0\uc11c \uc81c\uac00 \ub610 2\ubc88 \uacfc\ud558\uac8c \ub2e8\uc815\ud574 \ub458 \ub2e4 \ucca0\ud68c\ud588\uc2b5\ub2c8\ub2e4")),
    list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "\ub2e4\uc74c",
         items = c(
           "\uacc4\uc57d \uacbd\uace0 \ud544\ub4dc\ub97c \uc778\uc6a9 \uc9c0\uc810\ub4e4\uc774 \uc2e4\uc81c\ub85c \uc77d\ub294\uc9c0 \ubc30\uc120 \uc2e4\uce21 (FQ-196)",
           "\ub300\ud615\uc8fc/\uc911\ud615\uc8fc \ubd84\ud574 \uc9c4\ub2e8\ub3c4 \uac19\uc740 \ubcd1\uc778\uc9c0 \ud655\uc778",
           "\uacc4\uc57d \uc2e0\ud638 \uc790\ubcf8 \ud310\uc815\uc740 \ubd88\ubcc0 \u2014 \uc624\ubc84\ub808\uc774 \ub77c\uc6b0\ud305 \uc720\uc9c0")),
    list(type = "text", emoji = "\U0001F4A1", heading = "\ubcf8\uc9c8",
         body = "\uac19\uc740 \uc624\ub3c5\uc774 \uc774\ud2c0 \uc5f0\uc18d \ub3c5\ub9bd \uc138\uc158\uc5d0\uc11c \ub098\uc654\uc2b5\ub2c8\ub2e4. \uaddc\ubc94\uacfc \uba54\ubaa8\ub9ac\ub85c\ub294 \ub9c9\ud788\uc9c0 \uc54a\uc558\uace0, \uc218\uce58\ub97c \ub0b4\ub193\ub294 \ucf54\ub4dc\uac00 \ubd84\ud574\ub97c \uac19\uc774 \ubc1c\ud589\ud558\ub3c4\ub85d \uace0\uce5c \ub4a4\uc5d0\uc57c \ub2eb\ud614\uc2b5\ub2c8\ub2e4.")
  ),
  charts = c(c1, c2, c3),
  footer = "\U0001F4DA \uc0b0\ucd9c: stage_artifacts/ladder_sweep/ \u00b7 \uacc4\uc57d canonical_screen_bt.R basis_channels \u00b7 \uac80\uc0ac test_basis_channels.R 22/22"
)
say("=== 발송 완료 ===")
