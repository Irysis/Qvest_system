## p6 — ★★자가 검거 2: 내가 08-08 을 "기전이 반대" 라고 정정한 것이 **과한 주장**이었다.
## 08-08 카드는 `d`(=capw-EW 벤치 수익차)의 **부호가 창 길이 의존**임을 조회표로 이미 확립했다:
##   48m +0.1613 / 120m +0.0708 / 167m +0.0238 / 220m +0.0014 / 240m -0.0063 / 269m -0.0148
## 내 창은 282개월(2003-01~2026-06)이고 측정 d = -0.0048/yr → **같은 부호·같은 자릿수 = 독립 재현**이다.
## 그들의 "더 쉬운 벤치" 는 **그들 창(167m, d>0)에서 옳다**. 내가 창 차이를 기전 차이로 읽었다.
## ⇒ 내가 새로 잰 것은 **se 채널 하나뿐**이다. 그 진술만 남기고 08-08 반박은 철회한다.
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p6] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

## 틀린 문장 → 정정 문장 (원문 그대로 치환)
BAD1 <- "\u2014 EW \uc720\ub2c8\ubc84\uc2a4 \ubca4\uce58 \uc218\uc775\uc774 cap-w \ubca4\uce58\ubcf4\ub2e4 **\ub192\uc544** mean \uae30\uc900 \ub354 **\uc5b4\ub824\uc6b4** \ubca4\uce58\ub2e4. "
GOOD1 <- paste0("\u2014 \ub2e8 \uc774 \ubd80\ud638\ub294 **\ucc3d \uae38\uc774 \uc758\uc874**\uc774\ub2e4(08-08 \uc870\ud68c\ud45c: 48m +0.161 / 167m +0.024 / 220m +0.001 / 269m -0.015). ",
  "\ub0b4 282\uac1c\uc6d4 \ucc3d\uc758 d = -0.0048/yr \ub294 \uadf8 \uc870\ud68c\ud45c\uc758 **\ub3c5\ub9bd \uc7ac\ud604**\uc774\uc9c0 \ubc18\ubc15\uc774 \uc544\ub2c8\ub2e4. ")
BAD2 <- "\ub2e4\ub9cc 08-08 \uc758 \uae30\uc804 \uc11c\uc220('\ub354 \uc26c\uc6b4 \ubca4\uce58\ub85c \ucc44\uc810')\ub3c4 **\ubc29\ud5a5\uc774 \ubc18\ub300**\uc600\uc74c\uc774 \uc774\ubc88 \uc2e4\uce21\uc73c\ub85c \ub4dc\ub7ec\ub0ac\ub2e4(EW \ub294 mean \uae30\uc900 \ub354 \uc5b4\ub835\ub2e4). \uae08\uc9c0 \uaddc\ubc94\uc740 \uc606\uc558\uace0 \uadfc\uac70\ub9cc \ud2c0\ub838\ub358 \uc154."
GOOD2 <- paste0("\u2605\ub0b4 1\ucc28 \uc815\uc815\ub3c4 \uacfc\ud588\ub2e4 \u2014 \"08-08 \uae30\uc804\uc774 \ubc18\ub300\" \ub85c \uc37c\uc73c\ub098 \uadf8\ub4e4\uc740 d \uc758 \ucc3d-\uc758\uc874\uc131\uc744 \uc774\ubbf8 \uc870\ud68c\ud45c\ub85c \ud655\ub9bd\ud574\ub454 \uc0c1\ud0dc\uc600\uace0, ",
  "\ub0b4 \uce21\uc815\uc740 \uadf8 \ud45c\uc758 \uc7ac\ud604\uc774\ub2e4. **\uc0c8\ub85c \uc7b0 \uac83\uc740 se \ucc44\ub110 \ud558\ub098\ubfd0**\uc774\ub2e4(08-08 \uc740 mean \ucc44\ub110\ub9cc \uce21\uc815).")

fix <- function(s) {
  if (is.na(s) || !is.character(s)) return(s)
  s <- gsub(BAD1, GOOD1, s, fixed = TRUE); gsub(BAD2, GOOD2, s, fixed = TRUE)
}
walk <- function(x) {
  if (is.character(x)) return(vapply(x, fix, "", USE.NAMES = FALSE))
  if (is.list(x)) return(lapply(x, walk))
  x
}

## 1. validation.json
p <- "stage_artifacts/FQ191/validation.json"
V <- fromJSON(p, simplifyVector = FALSE)
n1 <- sum(grepl(BAD1, unlist(V), fixed = TRUE)) + sum(grepl(BAD2, unlist(V), fixed = TRUE))
V <- walk(V)
V$correction_ladder_20260809$self_correction_2 <- paste0(
  "\u2605\u2605\uc774 \ube14\ub85d\uc758 1\ucc28 \ubcf8\ubb38\uc740 08-08 \ub97c '\uae30\uc804\uc774 \ubc18\ub300' \ub77c\uace0 \uc815\uc815\ud588\ub294\ub370 \uadf8\uac83\uc774 \ub610 \uacfc\ud588\ub2e4. ",
  "08-08 \uce74\ub4dc\ub294 d \uc758 \ubd80\ud638\uac00 \ucc3d \uae38\uc774\uc5d0 \ub530\ub77c \ubc14\ub010\ub2e4\ub294 \uac83\uc744 \uc870\ud68c\ud45c\ub85c \uc774\ubbf8 \ud655\ub9bd\ud588\uace0(269m -0.0148), ",
  "\ub0b4 282\uac1c\uc6d4 \uce21\uc815 -0.0048 \uc740 \uadf8 \ud45c\uc640 \uc815\ud569\ud55c\ub2e4. \ub0b4\uac00 **\ucc3d \ucc28\uc774\ub97c \uae30\uc804 \ucc28\uc774\ub85c \uc77d\uc5c8\ub2e4**. ",
  "\uc774\ubc88 \ub77c\uc6b4\ub4dc\uc758 \uc21c\uc218 \uae30\uc5ec = **se \ucc44\ub110(x1.371 \ubc30\uc728) + \uacc4\uc57d \ud544\ub4dc\ud654** \ub458\uc774\ub2e4.")
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), p)
say("1. validation.json — 치환 %d건 + 2차 자가정정 기입", n1)

## 2. 원장
Q <- read_frontier_queue(); n0 <- length(Q$entries)
hit <- 0L
for (k in seq_along(Q$entries)) {
  b <- paste(unlist(Q$entries[[k]]), collapse = "")
  if (grepl(BAD1, b, fixed = TRUE) || grepl(BAD2, b, fixed = TRUE)) {
    Q$entries[[k]] <- walk(Q$entries[[k]]); hit <- hit + 1L
  }
}
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("2. 원장 — %d개 항목 치환 · 항목수 %d → %d (불변 %s)", hit, n0, length(Q2$entries), length(Q2$entries)==n0)
say("   잔여 오문장: %d건",
    sum(vapply(Q2$entries, function(e) {
      b <- paste(unlist(e), collapse=""); grepl(BAD1,b,fixed=TRUE)||grepl(BAD2,b,fixed=TRUE) }, TRUE)))

## 3. 병목 지도 v56 본문
mp <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(mp, "raw", file.size(mp)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
M_BAD <- "EW \uc720\ub2c8\ubc84\uc2a4 \ubca4\uce58 \uc218\uc775\uc774 cap-w \ubcf4\ub2e4 **\ub192\uc544 mean \uae30\uc900 \ub354 \uc5b4\ub824\uc6b4 \ubca4\uce58**\ub2e4. "
M_GOOD <- paste0("\ub2e8 \uc774 \ubd80\ud638\ub294 **\ucc3d \uae38\uc774 \uc758\uc874**\uc774\uba70(08-08 \uc870\ud68c\ud45c 167m +0.024 / 269m -0.015), ",
  "\ub0b4 282m \uce21\uc815 -0.0048 \uc740 \uadf8 \ud45c\uc758 **\ub3c5\ub9bd \uc7ac\ud604**\uc774\ub2e4. ")
M_BAD2 <- "\ub2e4\ub9cc 08-08 \uc758 \uae30\uc804('\ub354 \uc26c\uc6b4 \ubca4\uce58')\ub3c4 \ubc29\ud5a5\uc774 \ubc18\ub300\uc600\ub2e4(\uaddc\ubc94\uc740 \uc606\uace0 \uadfc\uac70\uac00 \ud2c0\ub9bc). "
M_GOOD2 <- paste0("\u2605\ub610 \ub0b4 1\ucc28 \uc815\uc815\uc774 \uacfc\ud588\ub2e4 \u2014 \"08-08 \uae30\uc804\uc774 \ubc18\ub300\" \ub294 \ud2c0\ub9ac\uba70, \uadf8\ub4e4\uc740 \ucc3d-\uc758\uc874\uc131\uc744 \uc774\ubbf8 \ud655\ub9bd\ud588\ub2e4. ",
  "\uc774\ubc88 \ub77c\uc6b4\ub4dc\uc758 \uc21c\uc218 \uae30\uc5ec = **se \ucc44\ub110 + \uacc4\uc57d \ud544\ub4dc\ud654**. ")
t2 <- sub(M_BAD, M_GOOD, txt, fixed = TRUE); t2 <- sub(M_BAD2, M_GOOD2, t2, fixed = TRUE)
ch <- (t2 != txt)
if (ch) {
  ob <- charToRaw(enc2utf8(t2)); writeBin(ob, mp)
  r2 <- readBin(mp, "raw", file.size(mp))
  say("3. 지도 정정: %d → %d바이트 · CR %d(원 %d) · 오문장 잔여 %s",
      length(raw), length(ob), sum(r2==as.raw(13)), sum(raw==as.raw(13)),
      grepl(M_BAD, rawToChar(r2), fixed=TRUE) || grepl(M_BAD2, rawToChar(r2), fixed=TRUE))
} else say("3. ★지도 문장 불일치 — 수동 확인 필요")
say("=== p6 완료 ===")
