#!/usr/bin/env python3
"""MCP-first paper discovery probe for Qvest paper recharge.

This helper is intentionally conservative. It tries to use the local MCP
stdio server declared in .mcp.json for arXiv discovery, writes a machine-readable
status report, and exits cleanly when the MCP runtime is not available. The
daily recharge script can then fall back to curated institutional URLs without
silently pretending that MCP ran.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any


def _load_json(path: Path, default: Any) -> Any:
    try:
        with path.open("r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default


# 결과측 category 필터 (2026-06-18 Q): arxiv-mcp-server 의 categories 인자가 느슨해
# 비-퀀트 논문(math.AP/hep-ex/astro-ph/cs.CV/q-bio 등)이 후보로 leak 됨. 반환된 raw
# categories 로 퀀트/계량경제/통계-ML 인접만 통과시킨다.
_FINANCE_PREFIXES = ("q-fin", "econ", "stat.")
_FINANCE_EXACT = {"cs.lg", "cs.ai", "cs.ce", "math.oc"}


def _is_finance_relevant(categories: Any) -> bool:
    if not categories:
        return False
    if isinstance(categories, str):
        categories = [categories]
    for c in categories:
        cl = str(c).strip().lower()
        if cl.startswith(_FINANCE_PREFIXES) or cl in _FINANCE_EXACT:
            return True
    return False


# 결과측 scope 배제 (2026-06-18 Q): finance-relevant 라도 KR long-only 월간 *주식* 범위밖이
# 명백한 것(crypto·보험계리·채권/신용전용·파생가격·마이크로구조/HFT·에너지/원자재·양자)은 수집 제외.
# downstream LLM router의 정밀 필터에 대한 coarse 선제 트림 — 보수적 다중어 시그널만(오탐 회피).
_OUT_OF_SCOPE_SIGNALS = (
    "cryptocurrenc", "crypto-asset", "bitcoin", "blockchain",
    "actuarial", "reinsurance", "catastrophe bond", "cat bond",
    "mortality", "annuit", "claims reserv", "insurance contract", "insurance pricing",
    "credit default swap", "corporate bond", "sovereign bond", "treasury bond",
    "municipal bond", "bond market making", "default probability path",
    "option pricing", "derivative pricing", "exotic option", "swaption",
    "variance swap", "volatility surface",
    "market making", "market microstructure", "limit order book",
    "high-frequency trad", "high frequency trad", "tick data", "order flow imbalance",
    "epps effect", "electricity market", "power market", "energy market",
    "commodity futures", "quantum comput",
)


def _is_out_of_scope(title: Any, abstract: Any) -> bool:
    txt = f"{title} {abstract}".lower()
    return any(sig in txt for sig in _OUT_OF_SCOPE_SIGNALS)


class McpClient:
    def __init__(self, cmd: list[str], timeout_sec: int = 60) -> None:
        self.cmd = cmd
        self.timeout_sec = timeout_sec
        self.proc: subprocess.Popen[str] | None = None
        self._id = 0
        self._lock = threading.Lock()

    def start(self) -> None:
        self.proc = subprocess.Popen(
            self.cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

    def close(self) -> None:
        if self.proc is None:
            return
        try:
            self.proc.kill()
        except Exception:
            pass

    def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        if self.proc is None or self.proc.stdin is None or self.proc.stdout is None:
            raise RuntimeError("MCP process not started")
        with self._lock:
            self._id += 1
            req_id = self._id
        payload = {"jsonrpc": "2.0", "id": req_id, "method": method}
        if params is not None:
            payload["params"] = params
        self.proc.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()

        deadline = time.time() + self.timeout_sec
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                if self.proc.poll() is not None:
                    err = ""
                    if self.proc.stderr is not None:
                        err = self.proc.stderr.read()[:1200]
                    raise RuntimeError(f"MCP process exited early: {err}")
                time.sleep(0.1)
                continue
            line = line.strip()
            if not line.startswith("{"):
                continue
            msg = json.loads(line)
            if msg.get("id") == req_id:
                return msg
        raise TimeoutError(f"MCP request timed out: {method}")

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        if self.proc is None or self.proc.stdin is None:
            return
        payload = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        self.proc.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()


def _normalize_arxiv_results(raw: Any, query: str, errors: list | None = None) -> list[dict[str, Any]]:
    if isinstance(raw, dict):
        # MCP tool responses wrap payloads in content blocks: {"type":"text","text":"<json>"}.
        # arxiv-mcp-server returns the paper list as a JSON string inside such a block, so
        # unwrap + re-parse before looking for the papers array (else 0 usable candidates).
        if raw.get("type") == "text" and isinstance(raw.get("text"), str):
            try:
                return _normalize_arxiv_results(json.loads(raw["text"]), query, errors)
            except (json.JSONDecodeError, ValueError) as exc:
                # text 블록이 JSON이 아니면 대개 상류 서버의 에러 텍스트 — 무음 폐기 대신
                # errors에 보존해 인입 0 붕괴가 '정상 완료'로 위장되지 않게 한다.
                if errors is not None:
                    errors.append({
                        "query": query,
                        "kind": "text_block_parse_error",
                        "error": f"{type(exc).__name__}: {exc}",
                        "text_head": raw["text"][:400],
                    })
                return []
        for key in ("papers", "results", "items", "content"):
            if key in raw:
                return _normalize_arxiv_results(raw[key], query, errors)
        return []
    if isinstance(raw, list):
        rows = []
        for item in raw:
            if isinstance(item, dict):
                # A content block can also arrive as a list element (result.content[]).
                if item.get("type") == "text" and isinstance(item.get("text"), str):
                    rows.extend(_normalize_arxiv_results(item, query, errors))
                    continue
                title = item.get("title") or item.get("name") or ""
                arxiv_id = item.get("arxiv_id") or item.get("id") or item.get("paper_id") or ""
                pdf_url = item.get("pdf_url") or item.get("pdf") or ""
                abs_url = item.get("url") or item.get("abs_url") or ""
                cats = item.get("categories") or item.get("category") or []
                if isinstance(cats, str):
                    cats = [cats]
                published = item.get("published") or item.get("published_date") or item.get("date") or ""
                abstract = item.get("abstract") or item.get("summary") or ""
                rows.append(
                    {
                        "query": query,
                        "title": title,
                        "arxiv_id": arxiv_id,
                        "pdf_url": pdf_url,
                        "abs_url": abs_url,
                        "categories": cats,
                        "published": published,
                        "abstract": abstract,
                        "raw": item,
                    }
                )
        return rows
    return []


# 인입붕괴 baseline lookback (유효 리포트 건수): 직전 1건만 보면 붕괴 리포트(prefilter=0)가
# 남은 다음 실행부터 prev=0 → 경보 불성립 — 지속 outage가 '정상 완료'로 계속 위장된다.
# 최근 N건 중 가장 최근의 prefilter>0 리포트를 baseline으로 잡아 전이·지속 붕괴를 모두 잡되,
# N을 유한으로 묶어 pool 장기 포화(정당한 0 연속 N건+) 시 영구 경보 오탐은 차단한다.
_PREFILTER_LOOKBACK = 7


def _prev_prefilter(out_path: Path) -> tuple[int | None, str | None]:
    """최근 유효 리포트 _PREFILTER_LOOKBACK건(오늘분 제외, 최신순 — 파일명 YYYYMMDD =
    사전순 = 시간순) 중 가장 최근의 candidates_prefilter>0 을 baseline으로 반환.
    lookback 내 양수가 없으면 최신 유효 1건의 값(0 포함)을 반환 — 판정부의 prev_n>0
    조건이 자연 불성립해 경보가 꺼진다. prefilter 키 없는 리포트(runtime_unavailable 등
    비-탐색 실행)는 lookback 소모 없이 건너뜀."""
    try:
        sibs = sorted(p for p in out_path.parent.glob("mcp_discovery_*.json")
                      if p.name != out_path.name)
    except OSError:
        return None, None
    latest: tuple[int, str] | None = None
    seen_valid = 0
    for p in reversed(sibs):
        if seen_valid >= _PREFILTER_LOOKBACK:
            break
        prev = _load_json(p, None)
        if not (isinstance(prev, dict) and "candidates_prefilter" in prev):
            continue
        try:
            n = int(prev["candidates_prefilter"])
        except (TypeError, ValueError):
            continue
        seen_valid += 1
        if latest is None:
            latest = (n, p.name)
        if n > 0:
            return n, p.name
    return latest if latest is not None else (None, None)


def _call_search_tool(client: McpClient, tool_name: str, query: str, categories: list[str], max_results: int,
                      date_from: str | None = None, sort_by: str = "date") -> tuple[bool, Any]:
    # sort_by="date" + date_from(recency window) 으로 신규 논문 유입 (pool 포화 완화, 2026-06-18 Q).
    # 서버가 일부 인자를 거부하면 단계적으로 떨어뜨림(마지막은 결과측 _is_finance_relevant 가 정화).
    base = {"query": query, "max_results": max_results, "categories": categories, "sort_by": sort_by}
    if date_from:
        base["date_from"] = date_from
    attempts = [
        base,
        {**base, "search_query": query},
        {"query": query, "max_results": max_results, "categories": categories, "sort_by": sort_by},
        {"query": query, "max_results": max_results, "categories": categories},
        {"query": query, "limit": max_results, "categories": categories},
        {"query": query, "max_results": max_results},
    ]
    last = None
    for args in attempts:
        resp = client.request("tools/call", {"name": tool_name, "arguments": args})
        last = resp
        if "error" not in resp:
            return True, resp.get("result")
    return False, last


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=os.getcwd())
    parser.add_argument("--out", required=True)
    parser.add_argument("--max-results-per-query", type=int, default=5)
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    mcp_config = _load_json(root / ".mcp.json", {})
    quant_sources = _load_json(root / "02_Infrastructure/docs/quant_sources.json", {})
    arxiv_cfg = ((quant_sources.get("arxiv_queries") or {}))
    queries = list((arxiv_cfg.get("queries") or [])[:9])
    categories = list(arxiv_cfg.get("categories") or ["q-fin.PM", "q-fin.ST", "q-fin.RM", "q-fin.GN"])

    # config 의 recency_days / max_results_per_query 배선 (기존엔 무시되던 필드, 2026-06-18 Q).
    try:
        recency_days = int(arxiv_cfg.get("recency_days") or 0)
    except (TypeError, ValueError):
        recency_days = 0
    try:
        cfg_max = int(arxiv_cfg.get("max_results_per_query") or 0)
    except (TypeError, ValueError):
        cfg_max = 0
    max_results = cfg_max if cfg_max > 0 else args.max_results_per_query
    date_from = None
    if recency_days > 0:
        from datetime import date, timedelta
        date_from = (date.today() - timedelta(days=recency_days)).isoformat()

    report: dict[str, Any] = {
        "schema_version": "paper_recharge_mcp_v1",
        "project_root": str(root),
        "mcp_config_present": bool(mcp_config.get("mcpServers")),
        "queries": queries,
        "categories": categories,
        "recency_days": recency_days,
        "date_from": date_from,
        "max_results_per_query": max_results,
        "sort_by": "date",
        "status": "not_run",
        "candidates": [],
        "errors": [],
    }

    server = ((mcp_config.get("mcpServers") or {}).get("arxiv") or {})
    cmd_name = server.get("command")
    cmd_args = server.get("args") or []
    if not cmd_name:
        report["status"] = "mcp_config_missing_arxiv"
        out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        return 0

    resolved = shutil.which(cmd_name)
    report["mcp_command"] = cmd_name
    report["mcp_command_resolved"] = resolved
    if not resolved:
        report["status"] = "mcp_runtime_unavailable"
        report["errors"].append(f"command not found: {cmd_name}")
        out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        return 0

    cmd = [resolved] + [str(a).replace("C:/Users/99922/OneDrive/Quant_Module_Moltbot", str(root)) for a in cmd_args]
    client = McpClient(cmd)
    try:
        client.start()
        init = client.request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "qvest-paper-recharge", "version": "1.0.0"},
            },
        )
        report["initialize"] = init.get("result", {})
        client.notify("notifications/initialized")
        tools = client.request("tools/list").get("result", {}).get("tools", [])
        tool_names = [t.get("name", "") for t in tools if isinstance(t, dict)]
        report["tools"] = tool_names
        search_tool = next((t for t in tool_names if t in ("search_papers", "search_arxiv", "search")), "")
        if not search_tool:
            report["status"] = "mcp_search_tool_missing"
            out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            return 0

        candidates: list[dict[str, Any]] = []
        for query in queries:
            ok, result = _call_search_tool(client, search_tool, query, categories, max_results,
                                           date_from=date_from, sort_by="date")
            if ok:
                candidates.extend(_normalize_arxiv_results(result, query, report["errors"]))
            else:
                report["errors"].append({"query": query, "response": result})
        seen = set()
        uniq = []
        for row in candidates:
            key = row.get("arxiv_id") or row.get("pdf_url") or row.get("title")
            if key in seen:
                continue
            seen.add(key)
            uniq.append(row)
        # 결과측 category 필터: 비-퀀트 제거 (서버 categories 인자 leak 정화).
        fin = [r for r in uniq if _is_finance_relevant(r.get("categories"))]
        # scope 배제: KR 주식 범위밖(crypto·보험·채권·파생가격·마이크로구조·에너지·양자) 제거 (2026-06-18 Q).
        kept = [r for r in fin if not _is_out_of_scope(r.get("title"), r.get("abstract"))]
        # 최신순 정렬: published 내림차순 → 신규 논문 우선 적재.
        kept.sort(key=lambda r: str(r.get("published") or ""), reverse=True)
        report["candidates_prefilter"] = len(uniq)
        report["candidates_dropped_non_finance"] = len(uniq) - len(fin)
        report["candidates_dropped_out_of_scope"] = len(fin) - len(kept)
        report["candidates"] = kept
        report["status"] = "mcp_ok" if kept else "mcp_ok_no_candidates"
        # 인입 붕괴 분리 라벨: 최근 lookback 내 prefilter>0 실행이 있는데 이번 run
        # prefilter=0 이면 '정상 완료(no_candidates)'가 아니라 상류 의심 상태로 기록
        # (전이일 + 지속 outage 공통 — fail-open 라벨링 해소. lookback 소진 시 자연 해제).
        prev_n, prev_name = _prev_prefilter(out_path)
        report["prev_prefilter"] = prev_n
        report["prev_report"] = prev_name
        if len(uniq) == 0 and prev_n is not None and prev_n > 0:
            report["status"] = "mcp_suspect_empty"
    except Exception as exc:
        report["status"] = "mcp_error"
        report["errors"].append(f"{type(exc).__name__}: {exc}")
    finally:
        client.close()

    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
