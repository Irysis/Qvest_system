#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""test_continuity_w3_director_freeze.py — W3(지도 신선도 넛지)는 디렉터 동결 중 침묵한다 (2026-09-24 도훈 DIR-PHASE0)

왜: layer_bottleneck_map.md 는 rf_director.R 이 매일 재생성하던 기계 산출물이다. 디렉터를 동결하면 갱신 주체가 없어
  W3 는 해소 불가능한 경보가 된다. 훅(research_continuity_guard.sh) python 본문을 **그대로 추출**해 샌드박스에서 실행한다.
  W1 양성 대조: director.enabled=true · 표 본문 30h 정체 · L-code 1h 전 → 발화(샌드박스가 발화 조건을 실제로 충족)
  W2 enabled=false → '{}'
  W3 config 부재 → 종전 판정(발화) — 판독 실패를 동결로 접지 않는다
  W4 돌연변이(스킵 조건 제거) → W2 가 발화로 뒤집힌다
운영 파일 무접촉(샌드박스 = tempfile).
"""
import io, json, os, re, subprocess, sys, tempfile, time, shutil

ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") or r"C:\Users\99922\OneDrive\Quant_Module_Moltbot"
HOOK = os.path.join(ROOT, "02_Infrastructure", "hooks", "research_continuity_guard.sh")
PY = sys.executable
P = F = 0


def ok(m):
    global P; P += 1; print("  OK  ", m)


def ng(m, why=""):
    global F; F += 1; print("  FAIL", m, ("— " + why) if why else "")


src = io.open(HOOK, encoding="utf-8").read().split("\n")
i0 = next(i for i, l in enumerate(src) if "<<'PY'" in l)
i1 = max(i for i, l in enumerate(src) if l == "PY")
BODY = "\n".join(src[i0 + 1:i1])
SKIP = "if isinstance(_dc, dict) and _dc.get('enabled') is False:"
if BODY.count(SKIP) != 1:
    ng("스킵 조건 줄이 정확히 1개여야 한다", str(BODY.count(SKIP)))


def sandbox(cfg):
    S = tempfile.mkdtemp(prefix="w3_freeze_")
    for d in ("06_Registry", ".cache", os.path.join("stage_artifacts", "l_code", "rnd")):
        os.makedirs(os.path.join(S, d), exist_ok=True)
    mp = os.path.join(S, "06_Registry", "layer_bottleneck_map.md")
    io.open(mp, "w", encoding="utf-8").write("# map\n\n| 계층 | 판정 |\n|---|---|\n| ① 알파 | 구속 |\n| ② 위험 | 여유 |\n")
    if cfg is not None:
        io.open(os.path.join(S, "06_Registry", "reinforce_auto_config.json"), "w", encoding="utf-8").write(json.dumps(cfg))
    # 표 본문 해시는 훅 자신의 정의부로 계산한다(복제 금지)
    ns = {"__name__": "hb"}
    exec(compile(BODY.split("msgs = []")[0].replace("root = sys.argv[1]", "root = ''"), "hb", "exec"), ns)
    rows = ns["mf_table_rows"](mp)
    now = time.time()
    json.dump({"schema": ns["MF_SCHEMA"], "table_sha": ns["mf_table_sha"](rows), "n_rows": len(rows),
               "observed_at": now - 30 * 3600}, io.open(os.path.join(S, ".cache", "layer_bottleneck_map_content.json"), "w", encoding="utf-8"))
    lc = os.path.join(S, "stage_artifacts", "l_code", "rnd", "l_code_t.json")
    ts = now - 3600
    json.dump({"l_code": "L-TEST-W3", "created_at": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ts))}, io.open(lc, "w", encoding="utf-8"))
    os.utime(lc, (ts, ts))
    return S


def run(body, S):
    f = os.path.join(S, "hook_body.py")
    io.open(f, "w", encoding="utf-8").write(body)
    r = subprocess.run([PY, f, S], capture_output=True, text=True, encoding="utf-8", env=dict(os.environ, PYTHONUTF8="1"))
    return (r.stdout or "").strip().splitlines()[-1] if (r.stdout or "").strip() else "ERR " + (r.stderr or "")[-200:]


fires = lambda o: "W3" in o
print("=== W3 × director.enabled ===")
S = sandbox({"director": {"enabled": True}}); o = run(BODY, S); shutil.rmtree(S, True)
(ok("W1 양성 대조 enabled=true → 발화") if fires(o) else ng("W1 양성 대조 — 샌드박스가 발화 조건을 못 만든다", o[:120]))
S = sandbox({"director": {"enabled": False}}); o = run(BODY, S); shutil.rmtree(S, True)
(ok("W2 enabled=false → 침묵 '{}'") if o == "{}" else ng("W2 동결인데 발화", o[:120]))
S = sandbox(None); o = run(BODY, S); shutil.rmtree(S, True)
(ok("W3 config 부재 → 종전 판정(발화)") if fires(o) else ng("W3 config 부재를 동결로 접었다", o[:120]))
S = sandbox({"director": {"enabled": False}}); o = run(BODY.replace(SKIP, "if False:"), S); shutil.rmtree(S, True)
(ok("W4 돌연변이(스킵 제거) → W2 가 발화로 뒤집힘") if fires(o) else ng("W4 돌연변이가 W2 를 뒤집지 못함(검사 무력)", o[:120]))
print("\n합계: 통과 %d · 실패 %d" % (P, F))
print(json.dumps({"test": "continuity_w3_director_freeze", "pass": P, "fail": F, "total": P + F, "skipped": 0}))
sys.exit(0 if F == 0 else 1)
