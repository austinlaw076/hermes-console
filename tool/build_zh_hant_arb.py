#!/usr/bin/env python3
"""Build lib/l10n/app_zh_Hant.arb via openai-codex gpt-5.6-luna (HK written 繁中)."""
from __future__ import annotations

import base64
import json
import re
import sys
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
EN_PATH = ROOT / "lib/l10n/app_en.arb"
ES_PATH = ROOT / "lib/l10n/app_es.arb"
OUT_PATH = ROOT / "lib/l10n/app_zh_Hant.arb"
PROGRESS = ROOT / "lib/l10n/.zh_hant_progress.json"
AUTH = Path("/home/austin/.hermes/auth.json")
CODEX_URL = "https://chatgpt.com/backend-api/codex/responses"
MODEL = "gpt-5.6-luna"
PLACEHOLDER_RE = re.compile(r"\{[^{}]+\}")

SYSTEM = """你是專業的香港 mobile app UI 本地化譯者。
把英文 UI 字串譯成「香港書面繁體中文」（不是粵語口語、不是台灣硬腔、不是简体）。

規則：
1. 只輸出譯文，不要引號、不要解釋、不要編號以外的多餘字。
2. 完整保留 ICU：{name}、{count, plural, ...}、select 等大括號與英文 keyword（other/one/few…）原樣。
3. 專有名詞保持英文：Hermes, Gateway, Dashboard, Tailscale, Obtainium, Play, SFTP, SSH, API, SSE, Cron, Kanban, MCP, Ollama, Whisper, Piper, QR, JSON, HTTP, HTTPS, Bearer, Termux。
4. 港式書面用詞：軟件、網絡、伺服器、裝置、設定、儲存、連線、訊息、檔案、資料、使用者/你、登入、配對、實例(Instance)、對話(Conversation)、批准(Approval)、技能(Skill)、執行(Run)、橋接(Bridge)。
5. 簡潔專業；避免「您」。
"""


def load_token() -> str:
    auth = json.loads(AUTH.read_text(encoding="utf-8"))
    return auth["providers"]["openai-codex"]["tokens"]["access_token"]


def codex_headers(token: str) -> dict[str, str]:
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "OpenAI-Beta": "responses=experimental",
        "User-Agent": "codex_cli_rs/0.0.0 (Hermes Agent)",
        "originator": "codex_cli_rs",
    }
    try:
        payload_b64 = token.split(".")[1] + "=" * (-len(token.split(".")[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload_b64))
        acct = claims.get("https://api.openai.com/auth", {}).get("chatgpt_account_id")
        if acct:
            headers["ChatGPT-Account-ID"] = acct
    except Exception:
        pass
    return headers


def protect(s: str) -> tuple[str, list[str]]:
    slots: list[str] = []

    def repl(m: re.Match[str]) -> str:
        slots.append(m.group(0))
        return f"⟦P{len(slots)-1}⟧"

    return PLACEHOLDER_RE.sub(repl, s), slots


def restore(s: str, slots: list[str]) -> str:
    out = s
    for i, ph in enumerate(slots):
        for form in (f"⟦P{i}⟧", f"[[P{i}]]", f"[P{i}]", f"P{i}"):
            # only replace token-like markers carefully
            if form.startswith("P") and form[1:].isdigit():
                continue
            out = out.replace(form, ph)
    return out


def stream_translate(client: httpx.Client, headers: dict, prompt: str) -> str:
    body = {
        "model": MODEL,
        "instructions": SYSTEM,
        "input": [
            {
                "role": "user",
                "content": [{"type": "input_text", "text": prompt}],
            }
        ],
        "store": False,
        "stream": True,
    }
    texts: list[str] = []
    with client.stream("POST", CODEX_URL, headers=headers, json=body, timeout=300.0) as r:
        if r.status_code == 401:
            raise RuntimeError("codex 401 unauthorized")
        if r.status_code >= 400:
            # read error body
            err = r.read().decode("utf-8", "replace")
            raise RuntimeError(f"codex {r.status_code}: {err[:300]}")
        for line in r.iter_lines():
            if not line or not line.startswith("data: "):
                continue
            data = line[6:]
            if data.strip() == "[DONE]":
                break
            try:
                ev = json.loads(data)
            except json.JSONDecodeError:
                continue
            if ev.get("type") == "response.output_text.delta":
                texts.append(ev.get("delta") or "")
    return "".join(texts).strip()


def translate_batch(client: httpx.Client, headers: dict, items: list[tuple[str, str]]) -> dict[str, str]:
    meta = []
    lines = []
    for i, (k, text) in enumerate(items):
        protected, slots = protect(text)
        meta.append((k, slots, text))
        lines.append(f"{i}|{protected}")
    prompt = (
        "將下列每一行譯成港式書面繁體中文。輸入格式「索引|原文」。"
        "輸出必須同樣「索引|譯文」，索引連續且行數一致，不要 markdown。\n\n"
        + "\n".join(lines)
    )
    content = stream_translate(client, headers, prompt)
    out: dict[str, str] = {}
    for line in content.splitlines():
        line = line.strip()
        if not line or "|" not in line:
            continue
        # strip accidental bullets
        if line[0] in "-*":
            line = line.lstrip("-* ")
        idx_s, tr = line.split("|", 1)
        idx_s = idx_s.strip()
        if not idx_s.isdigit():
            continue
        i = int(idx_s)
        if not (0 <= i < len(meta)):
            continue
        k, slots, original = meta[i]
        tr = restore(tr.strip().strip('"').strip("'"), slots)
        if set(PLACEHOLDER_RE.findall(original)) != set(PLACEHOLDER_RE.findall(tr)):
            tr = original
        out[k] = tr
    for k, slots, original in meta:
        out.setdefault(k, original)
    return out


def ensure_label_keys() -> dict:
    en = json.loads(EN_PATH.read_text(encoding="utf-8"))
    es = json.loads(ES_PATH.read_text(encoding="utf-8"))
    if "languageTraditionalChinese" not in en:
        en["languageTraditionalChinese"] = "Traditional Chinese"
        EN_PATH.write_text(json.dumps(en, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if "languageTraditionalChinese" not in es:
        es["languageTraditionalChinese"] = "Chino tradicional"
        ES_PATH.write_text(json.dumps(es, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return json.loads(EN_PATH.read_text(encoding="utf-8"))


def main() -> int:
    en = ensure_label_keys()
    token = load_token()
    headers = codex_headers(token)
    msg_keys = [k for k in en if not k.startswith("@") and k != "@@locale"]
    progress: dict[str, str] = {}
    if PROGRESS.is_file():
        progress = json.loads(PROGRESS.read_text(encoding="utf-8"))
    pending = [k for k in msg_keys if k not in progress]
    print(f"model={MODEL} total={len(msg_keys)} pending={len(pending)} done={len(progress)}", flush=True)

    batch_size = 25
    overrides = {
        "languageTraditionalChinese": "繁體中文",
        "languageEnglish": "English",
        "languageSpanish": "Español",
        "languageSystemDefault": "跟隨系統",
        "languageSettingTitle": "語言",
        "setLanguage": "語言",
        "setLanguageNote": "更改應用程式語言",
        "setLanguageSystem": "系統",
        "settingsTitle": "設定",
        "setTitle": "設定",
        "commonCancel": "取消",
        "commonOk": "知道了",
        "commonSave": "儲存",
    }
    # seed overrides immediately
    for k, v in overrides.items():
        if k in en:
            progress[k] = v

    with httpx.Client(http2=False) as client:
        # smoke
        try:
            smoke = stream_translate(client, headers, "Translate to HK written 繁中 only: Settings")
            print("smoke:", smoke, flush=True)
        except Exception as e:
            print("smoke failed", e, file=sys.stderr)
            return 1

        for start in range(0, len(pending), batch_size):
            batch_keys = pending[start : start + batch_size]
            items = [(k, en[k]) for k in batch_keys if isinstance(en.get(k), str) and k not in overrides]
            if not items:
                continue
            for attempt in range(6):
                try:
                    # refresh token occasionally
                    if attempt and attempt % 2 == 0:
                        headers = codex_headers(load_token())
                    part = translate_batch(client, headers, items)
                    progress.update(part)
                    PROGRESS.write_text(json.dumps(progress, ensure_ascii=False), encoding="utf-8")
                    print(
                        f"batch {start//batch_size+1}/{(len(pending)+batch_size-1)//batch_size} "
                        f"+{len(part)} progress={len(progress)}/{len(msg_keys)}",
                        flush=True,
                    )
                    break
                except Exception as e:
                    wait = min(60, 2 ** attempt)
                    print(f"retry {attempt} {e!r} sleep {wait}", flush=True)
                    time.sleep(wait)
            else:
                print("fatal batch", batch_keys[:5], file=sys.stderr)
                return 2
            time.sleep(0.35)

    out: dict = {"@@locale": "zh_Hant"}
    for k, v in en.items():
        if k == "@@locale":
            continue
        if k.startswith("@"):
            out[k] = v
            continue
        out[k] = progress.get(k, overrides.get(k, v))

    OUT_PATH.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    en_keys = {k for k in en if not k.startswith("@")}
    zh_keys = {k for k in out if not k.startswith("@")}
    missing = en_keys - zh_keys
    print("wrote", OUT_PATH, "keys", len(zh_keys), "missing", len(missing), flush=True)
    bad = 0
    for k in sorted(en_keys):
        if set(PLACEHOLDER_RE.findall(str(en[k]))) != set(PLACEHOLDER_RE.findall(str(out[k]))):
            bad += 1
            if bad <= 8:
                print("ph", k)
    print("placeholder_mismatches", bad, flush=True)
    # rough untranslated heuristic: identical to en and has spaces/letters
    same = 0
    for k in en_keys:
        if k in overrides:
            continue
        if out[k] == en[k] and re.search(r"[A-Za-z]{4,}", str(en[k])):
            same += 1
    print("still_englishish", same, flush=True)
    return 0 if not missing and bad == 0 else 3


if __name__ == "__main__":
    raise SystemExit(main())
