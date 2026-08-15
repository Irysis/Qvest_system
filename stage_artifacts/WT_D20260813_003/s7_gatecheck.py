# s7_gatecheck.py — alpha_package.json 을 (1) schema (2) ast_spec_gate 두 계층에 태운다.
# ★검사기 양방향: 정상 통과 확인 + 위반 주입 시 발화 확인.
import io, json, os, subprocess, sys, copy, tempfile

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
PKG = os.path.join(ROOT, "qepm/mailbox/worktask/WT-D20260813_003/alpha_package.json")
pkg = json.load(io.open(PKG, encoding="utf-8"))

# ── (1) schema ──────────────────────────────────────────────────────────────
try:
    import jsonschema
    sch = json.load(io.open(os.path.join(ROOT, "02_Infrastructure/worktask/schema.json"), encoding="utf-8"))
    sub = dict(sch); sub["$ref"] = "#/definitions/alpha_package"
    errs = sorted(jsonschema.Draft7Validator(sub).iter_errors(pkg), key=lambda e: e.path)
    print("[schema] errors =", len(errs))
    for e in errs[:8]:
        print("   -", list(e.path)[:4], "::", e.message[:220])
except ImportError:
    print("[schema] jsonschema 미설치 — skip")

# ── (2) ast_spec_gate.sh ────────────────────────────────────────────────────
GATE = os.path.join(ROOT, "02_Infrastructure/hooks/ast_spec_gate.sh")

def run_gate(payload_pkg, label):
    payload = {"tool_name": "Write",
               "tool_input": {"file_path": PKG, "content": json.dumps(payload_pkg, ensure_ascii=False)}}
    p = subprocess.run(["bash", GATE], input=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                       capture_output=True)
    out = p.stdout.decode("utf-8", "replace").strip()
    try:
        j = json.loads(out) if out else {}
    except Exception:
        j = {"_raw": out[:300]}
    dec = j.get("decision", "allow")
    print(f"[gate:{label}] decision={dec}  reason={str(j.get('reason',''))[:200]}")
    if p.stderr:
        print(f"[gate:{label}] stderr={p.stderr.decode('utf-8','replace')[:200]}")
    return dec

d_ok = run_gate(pkg, "as-written")

# 위반 주입 3종 — 게이트가 실제로 차단하는지 (통과만 보고 '안전' 이라 쓰지 않기 위해)
inj = copy.deepcopy(pkg); inj["hypothesis"]["mechanism"]["agent"] = ""
d1 = run_gate(inj, "inject:mechanism.agent 공백")
inj = copy.deepcopy(pkg); inj["hypothesis"]["falsification"] = []
d2 = run_gate(inj, "inject:falsification 빈배열")
inj = copy.deepcopy(pkg); inj["factors"][0]["ast"] = {"op": "FUTURE_MEAN", "args": [{"leaf": "A4_benchmark_kospi200"}, 3]}
d3 = run_gate(inj, "inject:O 밖 연산자 FUTURE_MEAN")
inj = copy.deepcopy(pkg); inj["hypothesis"]["regime_scope"]["weakens_or_reverses_in"] = []
d4 = run_gate(inj, "inject:weakens 빈배열")

print("\n[요약] as-written =", d_ok, "| 위반주입 발화 =",
      sum(1 for d in (d1, d2, d3, d4) if d == "block"), "/ 4")
