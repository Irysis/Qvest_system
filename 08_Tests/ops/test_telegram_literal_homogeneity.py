#!/usr/bin/env python3
"""test_telegram_literal_homogeneity.py — 텔레그램 발신 R 파일에 '섞인 리터럴' 0건 (v10.4 2026-09-24)

왜: R 이 C 로케일로 뜬 채(Qvest_MorningReboot.bat 의 LC_ALL=C.UTF-8 — Windows R 은 C.UTF-8 을 못 세워 C 로 폴백)
  telegram_notify.R 을 source 하면, 한 문자열 리터럴 안에 \\u/\\U 이스케이프와 **원시 비ASCII** 가 섞인 곳은
  파싱 단계에서 원시 바이트가 Latin-1 로 재해석돼 이중 인코딩된다. 모듈 안의 로케일 가드(.tg_ensure_utf8_ctype)는
  파일 전체가 파싱된 **뒤에** 돌아 제 파일을 못 지킨다. 실측: 제목 "Q-Lead Â·"(c3 82 c2 b7) 9월 34건,
  "📖 ì©ì´ íì´"(=용어 풀이) 40건. 근본 수리는 .bat 환경(test_scheduler_bat_locale.sh)이고, 이 검사는 방어층 —
  C 로케일로 뜨는 호출자가 다시 생겨도 헤더가 깨지지 않게 리터럴을 **전부 이스케이프로 균질화**한 상태를 지킨다.

판정:
  S  정적: 대상 파일의 R 문자열 리터럴 중 (\\u|\\U 이스케이프) ∧ (원시 비ASCII) 동시 보유 = 0건
  P  스캐너 양성 대조: 합성 섞인 리터럴 1건 검출 · 오검출 대조 5종(원시만/이스케이프만/\\\\u 리터럴/주석/raw 문자열) 0건
  M1 스캐너 돌연변이(\\U 무시) → P 의 \\U 주입을 놓침(= \\U 처리가 판정을 지탱)
  R  런타임(결함 환경 LC_ALL=C.UTF-8 자식 Rscript · 발송 0 — dry_run + POST 스텁):
       tg_agent_brief 헤더 첫 줄에 c2 b7(·) 존재 ∧ c3 82 c2 b7(Â·) 부재
       tg_send(mute=TRUE) 요청 본문에만 disable_notification · 기본 호출 본문 = chat_id,text,parse_mode(불변)
  M2 런타임 돌연변이: 모듈 사본의 헤더 리터럴을 수리 전 형태(원시 ·)로 되돌리면 → Â· 재현(= R 프로브가 결함을 본다)
"""
import json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = os.path.join("02_Infrastructure", "hooks", "qvest_hook_router.py")
ROOT = None
for c in (os.path.join(HERE, "..", ".."), os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")):
    if c and os.path.isfile(os.path.join(c, MARK)):
        ROOT = os.path.abspath(c); break
T = "telegram_literal_homogeneity"
if not ROOT:
    print(json.dumps({"test": T, "pass": 0, "fail": 1, "total": 1, "preflight": "no_root"})); sys.exit(1)
TG = os.path.join(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R")
TARGETS = [TG,
           os.path.join(ROOT, "02_Infrastructure", "ops", "morning_steps", "freshness_audit.R"),
           os.path.join(ROOT, "02_Infrastructure", "data", "dr_fail_signature.R")]

PASS = FAIL = 0
def chk(label, cond, detail=""):
    global PASS, FAIL
    if cond: PASS += 1; print("  ok   " + label)
    else: FAIL += 1; print("  FAIL " + label + (" — " + detail if detail else ""))

# ── 스캐너 (R 렉서 최소판: 주석 · "..." · '...' · raw 문자열 r"(...)" · `이름`) ─────────────
ESC_RE = re.compile(r"(?<!\\)(?:\\\\)*\\[uU]")
def r_string_literals(src):
    i, n, line, out = 0, len(src), 1, []
    while i < n:
        c = src[i]
        if c == "\n": line += 1; i += 1; continue
        if c == "#":
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if c in "rR" and i + 1 < n and src[i + 1] in "\"'" and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] in "._")):
            q = src[i + 1]; k = i + 2; d = 0
            while k < n and src[k] == "-": d += 1; k += 1
            if k < n and src[k] in "([{":
                term = {"(": ")", "[": "]", "{": "}"}[src[k]] + "-" * d + q
                e = src.find(term, k + 1); e = n if e < 0 else e + len(term)
                line += src.count("\n", i, e); i = e; continue
        if c in "\"'":
            q = c; k = i + 1
            while k < n and src[k] != q: k += 2 if src[k] == "\\" else 1
            lit = src[i:k + 1]; out.append((line, lit)); line += lit.count("\n"); i = k + 1; continue
        if c == "`":
            k = src.find("`", i + 1); k = n - 1 if k < 0 else k
            line += src.count("\n", i, k + 1); i = k + 1; continue
        i += 1
    return out
def mixed(src, esc_re=ESC_RE):
    return [(ln, lit) for ln, lit in r_string_literals(src) if esc_re.search(lit) and any(ord(ch) > 127 for ch in lit)]

print("== 텔레그램 발신 R 파일 — 섞인 리터럴 0건 ==")
for f in TARGETS:
    rel = os.path.relpath(f, ROOT).replace("\\", "/")
    if not os.path.isfile(f):
        chk("S %s 존재" % rel, False, "파일 없음"); continue
    h = mixed(open(f, "rb").read().decode("utf-8"))
    chk("S %s 섞인 리터럴 0건" % rel, not h, "; ".join("L%d %s" % (ln, lit[:60]) for ln, lit in h[:5]))

SYN = ('a <- "\\U0001F4C5 \u00b7 x"\n'          # 섞임 — 검출 대상
       'b <- "\u00b7 \ud55c\uae00 only"\n'          # 원시만
       'c <- "\\u00b7 \\U0001F4C5"\n'               # 이스케이프만
       'd <- "\\\\u00b7 \u00b7"\n'                  # \\u = 리터럴 역슬래시 + u (이스케이프 아님)
       '# e <- "\\U0001F4C5 \u00b7" (주석)\n'
       'f <- r"(\\U0001F4C5 \u00b7)"\n')             # raw 문자열 — 이스케이프 해석 없음
h = mixed(SYN)
chk("P 스캐너 양성 대조: 합성 주입 1건만 검출(오검출 대조 5종 0)", [ln for ln, _ in h] == [1], str(h))
h2 = mixed(SYN, re.compile(r"(?<!\\)(?:\\\\)*\\u"))
chk("M1 스캐너 돌연변이(\\U 무시) → 주입을 놓침", h2 == [], str(h2))

# ── 런타임 ─────────────────────────────────────────────────────────────────────────
RS = shutil.which("Rscript") or r"C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
PROBE = r'''
suppressWarnings(suppressMessages(source(Sys.getenv("TG_MOD"))))   # same form as live callers (no encoding arg)
r <- tg_agent_brief(agent = "Q-Lead", title = "probe", relaxed = TRUE, force = TRUE, dry_run = TRUE,
  sections = list(list(type = "summary", emoji = "\U0001F6A8", body = "header rendering probe only - never sent"),
                  list(type = "kv", emoji = "\U0001F4CB", heading = "kv", kv = list(a = "1", b = "2"))))
h <- strsplit(r$msg, "\n", fixed = TRUE)[[1]][1]
cat("HDR_HEX=", paste(as.character(charToRaw(h)), collapse = " "), "\n", sep = "")
cap <- new.env()
POST <- function(url, body, encode) { cap$names <- names(body); structure(list(), class = "response") }
http_error <- function(r) FALSE
status_code <- function(r) 200L
invisible(tg_send("\U0001F4C8 probe", mute = TRUE));  cat("BODY_MUTE=",  paste(cap$names, collapse = ","), "\n", sep = "")
invisible(tg_send("\U0001F4C8 probe"));               cat("BODY_PLAIN=", paste(cap$names, collapse = ","), "\n", sep = "")
'''
def run_probe(mod):
    td = tempfile.mkdtemp()
    try:
        pr = os.path.join(td, "probe.R"); open(pr, "w", encoding="ascii").write(PROBE)
        renv = os.path.join(td, "empty.Renviron"); open(renv, "w").close()
        env = {k: v for k, v in os.environ.items() if not (k.upper().startswith("LC_") or k.upper() in ("LANG", "LANGUAGE"))}
        env.update({"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",          # ★결함 환경 그대로(수리 전 MorningReboot.bat)
                    "R_ENVIRON_USER": renv, "TG_MOD": mod.replace("\\", "/"),
                    "QVEST_TG_DRY_RUN": "1", "QVEST_TG_SERIAL_LOCK": "0",
                    "CLAUDE_PROJECT_DIR": ROOT, "QM_ROOT": ROOT})
        p = subprocess.run([RS, "--no-save", "--no-restore", pr], capture_output=True, env=env, timeout=240, cwd=td)
        out = p.stdout.decode("utf-8", "replace").replace("\r", "")
        kv = dict(l.split("=", 1) for l in out.split("\n") if re.match(r"^(HDR_HEX|BODY_MUTE|BODY_PLAIN)=", l))
        return kv, out[-600:] + p.stderr.decode("utf-8", "replace")[-400:]
    finally:
        shutil.rmtree(td, ignore_errors=True)

if not os.path.isfile(RS):
    chk("R 런타임 프로브(전제: Rscript)", False, "Rscript 없음")
else:
    kv, tail = run_probe(TG)
    hx = kv.get("HDR_HEX", "")
    chk("R1 결함 환경(LC_ALL=C.UTF-8)에서도 헤더 · = c2 b7", " c2 b7 " in " %s " % hx, hx[:120] or tail)
    chk("R2 결함 환경에서 헤더에 Â·(c3 82 c2 b7) 없음", hx and "c3 82 c2 b7" not in hx, hx[:120])
    chk("R3 tg_send(mute=TRUE) 본문에 disable_notification", kv.get("BODY_MUTE", "").strip() == "chat_id,text,parse_mode,disable_notification", kv.get("BODY_MUTE", tail[-200:]))
    chk("R4 기본 tg_send 본문 불변(chat_id,text,parse_mode)", kv.get("BODY_PLAIN", "").strip() == "chat_id,text,parse_mode", kv.get("BODY_PLAIN", ""))
    # M2 — 모듈 사본의 헤더 리터럴을 수리 전 형태(원시 ·)로 되돌린다
    src = open(TG, "rb").read().decode("utf-8")
    old = '"%s <b>%s \\u00b7 %s</b>\\n\\U0001F4C5 %s"'
    td = tempfile.mkdtemp()
    try:
        mut = os.path.join(td, "telegram_notify_mut.R")
        open(mut, "wb").write(src.replace(old, '"%s <b>%s \u00b7 %s</b>\\n\\U0001F4C5 %s"', 1).encode("utf-8"))
        chk("M2 전제: 사본에 헤더 리터럴 되돌림 적용", src.count(old) == 1, "헤더 리터럴 형태가 바뀌었다 — 돌연변이 대상 갱신 필요")
        kvm, _ = run_probe(mut)
        chk("M2 런타임 돌연변이(원시 · 복원) → Â· 재현을 프로브가 잡는다", "c3 82 c2 b7" in kvm.get("HDR_HEX", ""), kvm.get("HDR_HEX", "")[:120])
    finally:
        shutil.rmtree(td, ignore_errors=True)

print("  ── %d/%d pass" % (PASS, PASS + FAIL))
print(json.dumps({"test": T, "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(0 if FAIL == 0 else 1)
