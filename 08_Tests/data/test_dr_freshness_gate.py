#!/usr/bin/env python3
"""test_dr_freshness_gate.py — daily_refresh [0c] 적재 신선도 판정: 측정 시점 = 적재 후 · 하류 산출물 판정 제외 (v10.4 2026-09-24)

왜: [0c] 가 두 가지 이유로 매일 거짓 exit 1 을 만들었고, 그 exit 1 을 task_health 가 다시 방송했다.
  ① 측정 시점 — [0b] 직후(적재 **전**)에 재서 [1pre] 벤치·[1] RAWDATA·[4/7] MSM·KTRI·국면이 안 들어온 상태를 쟀다.
     화요일 00:03 마다 benchmark lag 3>2 (09-15·09-22 실측 — 같은 실행의 [1pre] 가 곧바로 전진시켰다).
  ② 판정 범위 — p3_forecast(브리핑 [6a] 산출물, 리프레시가 고칠 수 없다)의 정체가 DR exit 1 로 둔갑(09-23·09-24).
  문턱(max_lag)은 바꾸지 않았다. 목록 원천 = freshness_audit.R 의 role=downstream → JSON downstream_items 하나.

판정:
  C1 순서: freshness_audit.R 호출이 모든 적재 스텝 라벨(echo "[N/7]" — [0c]·[7/7] 제외) 뒤 · [7/7] 앞
  CM 돌연변이(블록을 [0b] 직후로 되돌림) → C1 red
  A1~A5 판독기(배포된 heredoc 을 앵커로 추출해 실행): p3만 → OK+제외 · bench+p3 → STALE:bench · 키 부재 → p3 포함 STALE
        · 구판 스칼라 직렬화 "p3_forecast" 도 제외 · 판독 불가 → UNREADABLE
  AM 돌연변이(downstream 무시) → A1 red
  B1~B5 bash 분기(배포된 case 블록 실행): OK · STALE(이름 export) · 제외 줄 · 판독 불가 · 끝 CR 허용 · 빈 칸 보존(구분자 '|')
  F1 감사기가 p3_forecast 에 role=downstream 을 달고 JSON 에 downstream_items 를 쓴다(정적)
"""
import json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = os.path.join("02_Infrastructure", "hooks", "qvest_hook_router.py")
ROOT = None
for c in (os.path.join(HERE, "..", ".."), os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")):
    if c and os.path.isfile(os.path.join(c, MARK)):
        ROOT = os.path.abspath(c); break
T = "dr_freshness_gate"
if not ROOT:
    print(json.dumps({"test": T, "pass": 0, "fail": 1, "total": 1, "preflight": "no_root"})); sys.exit(1)
DR = os.path.join(ROOT, "02_Infrastructure", "data", "daily_refresh.sh")
FA = os.path.join(ROOT, "02_Infrastructure", "ops", "morning_steps", "freshness_audit.R")
PASS = FAIL = 0
def chk(label, cond, detail=""):
    global PASS, FAIL
    if cond: PASS += 1; print("  ok   " + label)
    else: FAIL += 1; print("  FAIL " + label + (" — " + str(detail) if detail else ""))

src = open(DR, "rb").read().decode("utf-8")

def order_ok(s):
    lines = s.split("\n")
    fa = [i for i, l in enumerate(lines) if "ops/morning_steps/freshness_audit.R" in l and not l.lstrip().startswith("#")]
    steps = [(i, m.group(1)) for i, l in enumerate(lines) for m in [re.match(r'^\s*echo "\[([0-9][0-9a-z.]*)(?:/7)?\]', l)] if m]
    load = [i for i, lab in steps if lab not in ("0c", "7") and not lab.startswith("0c")]
    s7 = [i for i, lab in steps if lab == "7"]
    if len(fa) != 1 or not load or len(s7) != 1: return False, "fa=%s load=%d s7=%s" % (fa, len(load), s7)
    return (fa[0] > max(load) and fa[0] < s7[0]), "fa=%d max_load=%d s7=%d" % (fa[0], max(load), s7[0])

print("== daily_refresh [0c] 적재 신선도 판정 ==")
ok, why = order_ok(src)
chk("C1 신선도 측정 = 모든 적재 스텝 뒤 · [7/7] 앞", ok, why)
# CM: [0c] 블록을 [0b] run_r 블록 직후(수리 전 자리)로 되돌린다
a = src.find('# ── [0c] 적재 검증 — "돌렸다"가 아니라'); e = src.find('\ncd "$INFRA"\n', a)
b0 = src.find('echo "[0b/7]'); b1 = src.find("\n'\n", b0)
if a > 0 and e > a and b0 > 0 and b1 > b0:
    blk = src[a:e + len('\ncd "$INFRA"\n')]
    mut = src[:a] + src[e + len('\ncd "$INFRA"\n'):]
    k = mut.find("\n'\n", mut.find('echo "[0b/7]')) + 3
    mut = mut[:k] + "\n" + blk + mut[k:]
    chk("CM 돌연변이(블록을 [0b] 직후로 되돌림) → C1 red", not order_ok(mut)[0])
else:
    chk("CM 돌연변이 전제(블록·[0b] 앵커)", False, (a, e, b0, b1))

# ── 판독기 heredoc 추출·실행 ─────────────────────────────────────────────────────
m = re.search(r"<<'PYEOF' 2>/dev/null\n(.*?)\nPYEOF\n", src[src.find('[0c/7]'):], re.S)
PYSRC = m.group(1) if m else ""
chk("A0 [0c] 판독기 heredoc 추출", "downstream_items" in PYSRC, "추출 실패 또는 downstream 판독 없음")
td = tempfile.mkdtemp()
def judge(obj, code=None, raw=None):
    f = os.path.join(td, "fa.json")
    with open(f, "w", encoding="utf-8") as h:
        h.write(raw if raw is not None else json.dumps(obj))
    p = os.path.join(td, "j.py"); open(p, "w", encoding="utf-8").write(code if code is not None else PYSRC)
    r = subprocess.run([sys.executable, p, f], capture_output=True, timeout=60)
    return r.stdout.decode("utf-8", "replace").strip()
P3 = "p3_forecast(STALE,lag=5d)"; BM = "benchmark(STALE,lag=3d)"
chk("A1 p3 만 STALE + downstream → OK · 제외 목록에 p3", judge({"stale_items": [P3], "downstream_items": ["p3_forecast"]}) == "OK|%s|" % P3,
    judge({"stale_items": [P3], "downstream_items": ["p3_forecast"]}))
chk("A2 bench+p3 → STALE:bench · 이름 export = benchmark",
    judge({"stale_items": [BM, P3], "downstream_items": ["p3_forecast"]}) == "STALE:%s|%s|benchmark" % (BM, P3))
chk("A3 downstream_items 키 부재(구판 JSON) → p3 포함 STALE(보수적)",
    judge({"stale_items": [P3]}) == "STALE:%s||p3_forecast" % P3, judge({"stale_items": [P3]}))
chk("A4 스칼라 직렬화(auto_unbox) \"p3_forecast\" 도 제외",
    judge({"stale_items": [P3], "downstream_items": "p3_forecast"}).startswith("OK|"))
chk("A5 JSON 판독 불가 → UNREADABLE", judge(None, raw="{ broken") == "UNREADABLE")
mut_py = re.sub(r"(?m)^ds = set\(.*$", "ds = set()", PYSRC)
chk("AM 돌연변이(downstream 무시) → A1 red",
    mut_py != PYSRC and judge({"stale_items": [P3], "downstream_items": ["p3_forecast"]}, code=mut_py).startswith("STALE:"))

# ── bash 분기(배포된 case 블록) ──────────────────────────────────────────────────
seg = src[src.find('[0c/7]'):]
b = seg.find('  _FA_ST="${_FA_ST%$\'\\r\'}"'); c = seg.find("  esac\n", b)
CASE = seg[b:c + len("  esac\n")] if b > 0 and c > b else ""
chk("B0 [0c] bash 분기 블록 추출", "IFS='|' read" in CASE, CASE[:80])
def branch(st):
    sh = os.path.join(td, "b.sh")
    with open(sh, "w", encoding="utf-8", newline="\n") as h:
        h.write("DR_FAILED=(); DR_STALE_NAMES=''\n_FA_ST=\"$1\"\n" + CASE +
                'echo "FAILED=${DR_FAILED[*]:-}"; echo "NAMES=${DR_STALE_NAMES:-}"\n')
    r = subprocess.run(["bash", sh, st], capture_output=True, timeout=60)
    out = r.stdout.decode("utf-8", "replace").replace("\r", "")
    kv = dict(l.split("=", 1) for l in out.split("\n") if l.startswith(("FAILED=", "NAMES=")))
    return kv, out
kv, out = branch("OK||")
chk("B1 OK → 실패 0", kv.get("FAILED") == "" and "FRESH" in out, out[-200:])
kv, out = branch("STALE:%s|%s|benchmark" % (BM, P3))
chk("B2 STALE → ingest_freshness · 이름 benchmark export · 제외 줄 출력",
    kv.get("FAILED") == "ingest_freshness" and kv.get("NAMES") == "benchmark" and "p3_forecast" in out and "판정 제외" in out, out[-300:])
kv, out = branch("OK|%s|" % P3)
chk("B3 p3 만 → 실패 0 + 제외 줄(보고는 남는다)", kv.get("FAILED") == "" and "판정 제외" in out, out[-300:])
kv, out = branch("UNREADABLE")
chk("B4 판독 불가 → ingest_freshness:unreadable(미측정을 정상으로 접지 않음)", kv.get("FAILED") == "ingest_freshness:unreadable", out[-200:])
kv, out = branch("STALE:%s||benchmark\r" % BM)
chk("B5 끝 CR(Windows python stdout) 허용 · 빈 제외 칸 보존", kv.get("FAILED") == "ingest_freshness" and kv.get("NAMES") == "benchmark", out[-200:])

fa = open(FA, "rb").read().decode("utf-8")
chk("F1 감사기: p3_forecast role=downstream · JSON downstream_items",
    re.search(r'audits\$p3_forecast\$role\s*<-\s*"downstream"', fa) is not None and "downstream_items = " in fa)
shutil.rmtree(td, ignore_errors=True)
print("  ── %d/%d pass" % (PASS, PASS + FAIL))
print(json.dumps({"test": T, "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(0 if FAIL == 0 else 1)
