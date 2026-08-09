## p8 — [정정본] '쉬운 설명' 검사기가 내 섹션을 못 본 진짜 이유
##
## ★1차 결론("검사기가 조용히 죽음")은 **틀렸다**. 검사기는 정상이고 **내가 오타를 냈다**.
##   내 caller 는 heading 을 \u 이스케이프로 썼는데 `\uc27d` = "쉽" 이다(정본 "쉬" = `\uc26c`).
##   바이트로 확정: 내 것 ec 89 bd / 정본 ec 89 ac. 즉 텔레그램에 "쉽은 설명" 으로 나갔고
##   검사기는 그것을 **정확히 거부**했다. 경고가 옳았다.
## ★1차 진단 스크립트 자체도 결함이었다 — 4번 검사에서 비교 **양변에 같은 오타 문자열**을 넣고
##   TRUE 를 받아 "검사기 정상 아님" 쪽으로 몰았다(동어반복을 검사로 착각).
## ⇒ 규약: R 스크립트의 한글은 \u 이스케이프 말고 **Write 도구로 문자 그대로** 쓴다.
##   이스케이프 경로는 한 코드포인트만 틀려도 **그럴듯한 다른 글자**가 나오고 오류 신호가 없다.
##   (= 오늘 세 번째 "그럴듯한 오답" 계통. 길이도 맞고 한글이라 눈으로 안 걸린다.)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p8] ", fmt, "\n"), ...)); flush.console() }

wrong <- "\uc27d\uc740 \uc124\uba85"     # 내가 실제로 보낸 것
right <- "\uc26c\uc6b4 \uc124\uba85"     # 정본
hexof <- function(s) paste(sprintf("%02x", as.integer(charToRaw(s))), collapse = " ")

say("1. 내가 보낸 heading : [%s] · %s", wrong, hexof(wrong))
say("2. 정본 heading      : [%s] · %s", right, hexof(right))
say("3. 첫 글자 비교: 내 것 U+%04X vs 정본 U+%04X",
    utf8ToInt(substr(wrong,1,1)), utf8ToInt(substr(right,1,1)))

## 검사기 리터럴을 소스에서 직접 추출해 **양방향** 검사 (동어반복 회피)
L <- readLines("02_Infrastructure/telegram/telegram_notify.R", warn = FALSE, encoding = "UTF-8")
i <- grep("has_plain_section", L)[1]
m <- regmatches(L[i+1L], regexpr('grepl\\("[^"]+"', L[i+1L], perl = TRUE))
lit <- sub('"$', "", sub('^grepl\\("', "", m))
say("4. 검사기 리터럴: [%s] · %s", lit, hexof(lit))

say("5. ★양방향 검사 (여기가 1차에서 빠졌던 부분)")
say("   [\uc591\uc131] \uc815\ubcf8 heading \uc744 \uc8fc\uba74 \uac80\ucd9c\ub418\ub294\uac00 : %s", grepl(lit, right, fixed = TRUE))
say("   [\uc74c\uc131] \uc624\ud0c0 heading \uc744 \uc8fc\uba74 \uac70\ubd80\ud558\ub294\uac00 : %s", !grepl(lit, wrong, fixed = TRUE))
say("   [\uc74c\uc131] \ubb34\uad00 heading \uc744 \uc8fc\uba74 \uac70\ubd80\ud558\ub294\uac00 : %s",
    !grepl(lit, "\ud575\uc2ec \uc218\uce58", fixed = TRUE))

ok <- grepl(lit, right, fixed=TRUE) && !grepl(lit, wrong, fixed=TRUE)
say("=== \u2605\ud310\uc815 ===")
say("   %s", if (ok)
  "\u2605\uac80\uc0ac\uae30 \uc815\uc0c1(\uc591\uc131 \ud1b5\uacfc \u00b7 \uc74c\uc131 \uac70\ubd80). \uacbd\uace0\ub294 \uc633\uc558\uace0 \uacb0\ud568\uc740 \ub0b4 caller \uc758 \ud55c\uae00 \uc624\ud0c0\ub2e4."
  else "\u2605\u2605\uac80\uc0ac\uae30 \uacb0\ud568 \ud655\uc778 \u2014 \uc218\ub9ac \ud544\uc694")
say("   \uc870\uce58: \ud154\ub808\uadf8\ub7a8 \uc7ac\ubc1c\uc1a1\uc740 \ud558\uc9c0 \uc54a\ub294\ub2e4(\ubcf8\ubb38 4\uc904\uc740 \uc815\uc0c1 \uc804\ub2ec\ub428 \u00b7 \ucc44\ub110 \uc911\ubcf5 \ube44\uc6a9 > \uc81c\ubaa9 \uc624\ud0c0 \uc774\ub4dd).")
say("   \uc7ac\ubc1c \ubc29\uc9c0: \uc774\ud6c4 caller \ud55c\uae00\uc740 Write \ub3c4\uad6c\ub85c \ubb38\uc790 \uadf8\ub300\ub85c \uc791\uc131.")
