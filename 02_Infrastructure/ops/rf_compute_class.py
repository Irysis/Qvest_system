# -*- coding: utf-8 -*-
"""rf_compute_class.py — 충실구현 논문의 계산 등급(gpu | cpu) 판별 단일 정본 (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)

왜: 레인 다중 슬롯에서 torch/GPU 논문은 GPU 슬롯에만 들어간다(두 GPU 학습이 겹치면 VRAM 넘침 — 10-18 THGNN 공유 9.7GB 사고 계통).
  측정 단계가 GPU 를 쓰는지는 **구현 의존성**(엔진이 torch 를 부르는가)이 결정적이고, 구현 전에는 **큐 메타**(제목 · 후보 팩터 정의 · 사유의
  딥러닝 어휘)로 추정한다. 판별 순서(먼저 걸리는 것이 이긴다):
    ① 명시 — 요청 · 큐 항목의 compute_class("gpu"|"cpu") 또는 requires_gpu(true) (세션이 고칠 수 있는 손잡이)
    ② 구현 의존성 — 작업 디렉터리에 engine.R 이 있으면: engine.R 본문 + engine.R 이 이름으로 부르는 .py · .R(작업 디렉터리 · _work/)
       에서 주석 아닌 줄의 torch · tensorflow · jax · CUDA 사용 → gpu, 없으면 cpu(엔진이 GPU 를 안 쓰면 측정도 안 쓴다)
    ③ 큐 메타 키워드 — 딥러닝 어휘(기본 정규식 · 설정 replication_lane.gpu_keywords_regex 로 덮기) → gpu
    ④ 기본 cpu
  오판의 비용: gpu 를 cpu 로 → CPU 슬롯 작업자가 측정 직전(구현 의존성 재판정)에 GPU 슬롯으로 넘긴다(인계함) ·
             cpu 를 gpu 로 → GPU 슬롯에서 돈다(처리량만 손해). 그래서 구현 의존성 재판정이 마지막 방어선이다.
사용: classify(meta, wdir=None, cfg=None) → {"class", "basis", "detail"} · CLI 는 rf_replication_slots.py classify
"""
import io
import json
import os
import re

# 약어는 **글자** 경계로 본다 — \b 는 '_' 를 글자로 쳐서 'lstm_price_forecast'(큐 후보 팩터 이름 형식)를 놓쳤다(10-20 실측)
GPU_KEYWORDS_DEFAULT = (r"(?i)(deep[\s_-]?learning|neural[\s_-]?net(?:work)?s?|"
                        r"(?<![a-z])(?:lstm|gru|rnn|cnn|tcn|gnn|gcn|gat|vae|mlp|dqn|bert)(?![a-z])|"
                        r"long[\s_-]short[\s_-]term[\s_-]memory|transformer|convolutional|recurrent[\s_-]neural|autoencoder|"
                        r"graph[\s_-]neural|deep[\s_-]reinforcement|pytorch|tensorflow|"
                        r"딥러닝|신경망|트랜스포머|그래프\s?신경망|심층\s?강화|순환\s?신경)")
# 주석 아닌 줄의 GPU 프레임워크 사용 — R 엔진이 문자열로 품은 파이썬 코드(writeLines)도 줄 머리가 import 면 걸린다
ENGINE_DEP_RE = re.compile(r"(?m)^(?![ \t]*#).*?(\bimport[ \t]+torch\b|\bfrom[ \t]+torch\b|\bimport[ \t]+tensorflow\b|\bfrom[ \t]+tensorflow\b|"
                           r"\bimport[ \t]+jax\b|\bfrom[ \t]+jax\b|torch\.cuda|\.cuda\(|\blibrary\(\s*torch\s*\)|\btorch::)")
REF_RE = re.compile(r"([A-Za-z0-9_.\-]+\.(?:py|R))\b")
META_FIELDS = ("paper_title", "title", "factor_name", "factor_def", "reason")
SKIP_DIRS = ("_limit_partial", ".clean_paper", ".pre_agent_snapshot")


def _read(p, limit=2_000_000):
    try:
        with io.open(p, "rb") as f:
            return f.read(limit).decode("utf-8", "replace")
    except Exception:
        return ""


def _meta_text(meta):
    if not isinstance(meta, dict):
        return ""
    parts = []
    srcs = [meta, meta.get("paper") if isinstance(meta.get("paper"), dict) else {},
            meta.get("factor_candidate") if isinstance(meta.get("factor_candidate"), dict) else {}]
    for s in srcs:
        for k in META_FIELDS + ("name", "def"):
            v = s.get(k) if isinstance(s, dict) else None
            if isinstance(v, str):
                parts.append(v)
    return "\n".join(parts)


def _explicit(meta):
    if not isinstance(meta, dict):
        return None
    for s in (meta, meta.get("paper") if isinstance(meta.get("paper"), dict) else {}):
        v = (s or {}).get("compute_class")
        if v in ("gpu", "cpu"):
            return v
        if (s or {}).get("requires_gpu") is True:
            return "gpu"
    return None


def engine_dependency(wdir):
    """작업 디렉터리의 현재 엔진이 GPU 프레임워크를 쓰는가 — (True|False, 근거 파일) · 엔진 없음 = (None, '')."""
    if not wdir:
        return None, ""
    eng = os.path.join(wdir, "engine.R")
    if not os.path.isfile(eng):
        return None, ""
    txt = _read(eng)
    m = ENGINE_DEP_RE.search(txt)
    if m:
        return True, "engine.R:%s" % m.group(1).strip()
    refs = set(REF_RE.findall(txt))
    refs.discard("engine.R")
    for name in sorted(refs):
        for d in (wdir, os.path.join(wdir, "_work")):
            p = os.path.join(d, os.path.basename(name))
            if os.path.isfile(p) and not any(s in p for s in SKIP_DIRS):
                m = ENGINE_DEP_RE.search(_read(p))
                if m:
                    return True, "%s:%s" % (os.path.relpath(p, wdir).replace("\\", "/"), m.group(1).strip())
    return False, "engine.R(+%d 참조 파일) GPU 프레임워크 없음" % len(refs)


def classify(meta, wdir=None, cfg=None):
    ex = _explicit(meta)
    if ex:
        return {"class": ex, "basis": "explicit", "detail": "compute_class/requires_gpu"}
    dep, why = engine_dependency(wdir)
    if dep is not None:
        return {"class": "gpu" if dep else "cpu", "basis": "engine_dependency", "detail": why}
    rx = ((cfg or {}).get("replication_lane") or {}).get("gpu_keywords_regex") if isinstance(cfg, dict) else None
    try:
        pat = re.compile(rx) if isinstance(rx, str) and rx else re.compile(GPU_KEYWORDS_DEFAULT)
    except re.error:
        pat = re.compile(GPU_KEYWORDS_DEFAULT)
    m = pat.search(_meta_text(meta))
    if m:
        return {"class": "gpu", "basis": "queue_keywords", "detail": m.group(0)}
    return {"class": "cpu", "basis": "default", "detail": ""}


def lane_slug(key):
    """레인 셸의 SLUG 와 같은 규칙 — `printf %s KEY | tr -c 'A-Za-z0-9' '_' | cut -c1-24`(바이트 단위)."""
    b = (key or "").encode("utf-8")
    s = "".join(chr(x) if (48 <= x <= 57 or 65 <= x <= 90 or 97 <= x <= 122) else "_" for x in b)
    return s[:24]


def wdir_candidates(req, wdir_base):
    """요청이 가리킬 수 있는 작업 디렉터리 — 레인 셸의 규칙(normal = RP_AUTO_ · 청정 = RP_AUTO_CLEAN_ · 결합 = RP_AUTO_COMBO_)."""
    req = req or {}
    w = req.get("wdir")
    out = []
    if isinstance(w, str) and w:
        out.append(w if os.path.isabs(w) else os.path.join(os.path.dirname(os.path.dirname(wdir_base)), w))
    key = ((req.get("paper") or {}).get("paper_key")) or ""
    if key:
        sl = lane_slug(key)
        order = ["RP_AUTO_CLEAN_", "RP_AUTO_"] if req.get("lane_mode") == "clean" else ["RP_AUTO_", "RP_AUTO_CLEAN_"]
        if req.get("combo"):
            order = ["RP_AUTO_COMBO_"]
        out += [os.path.join(wdir_base, p + sl) for p in order]
    return out


def classify_request(req, wdir_base, cfg=None, wdir=None):
    """요청 1건 — 작업 디렉터리를 주면 그것만, 아니면 후보 중 engine.R 이 있는 첫 디렉터리로 구현 의존성을 본다."""
    cands = [wdir] if wdir else wdir_candidates(req, wdir_base)
    use = next((d for d in cands if d and os.path.isfile(os.path.join(d, "engine.R"))), None)
    return classify(req, use, cfg)


if __name__ == "__main__":       # 검사 · 수동 확인용: python rf_compute_class.py <요청.json> [작업 디렉터리]
    import sys
    r = json.load(io.open(sys.argv[1], encoding="utf-8")) if len(sys.argv) > 1 else {}
    print(json.dumps(classify(r, sys.argv[2] if len(sys.argv) > 2 else None), ensure_ascii=False))
