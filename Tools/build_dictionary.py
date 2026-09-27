#!/usr/bin/env python3
"""Build the small, offline English -> Chinese lookup database.

ECDICT is an MIT-licensed English/Chinese dictionary by Linwei. The upstream
CSV is deliberately not checked in; the derived database and license are.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import math
import re
import sqlite3
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_COMMIT = "bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b"
UPSTREAM_URL = (
    "https://raw.githubusercontent.com/skywind3000/ECDICT/"
    f"{UPSTREAM_COMMIT}/ecdict.csv"
)
UPSTREAM_SHA256 = "1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf"
DEFAULT_OUTPUT = ROOT / "Resources" / "lexicon.sqlite3"
KEY_PATTERN = re.compile(r"[a-z]+(?:[' -][a-z]+)*\Z")
HAN_PATTERN = re.compile(r"[\u3400-\u9fff]")
PURE_HAN_PATTERN = re.compile(r"[\u3400-\u9fff]{1,12}\Z")
PART_OF_SPEECH = re.compile(
    r"^(?:n|v|vt|vi|adj|ad|adv|a|prep|conj|pron|num|int|interj|art|pl|abbr|aux)\.\s*",
    re.IGNORECASE,
)
LABEL = re.compile(r"^\s*(?:\[[^]]+\]|【[^】]+】)\s*")


def normalize_key(word: str) -> str:
    return re.sub(r"\s+", " ", word.strip().lower().replace("-", " "))


def candidate_senses(translation: str) -> list[str]:
    """Only emit short text that is directly useful as an IME candidate."""
    found: list[str] = []
    for line in translation.splitlines():
        line = line.strip()
        if line.startswith("[网络]"):
            break
        line = LABEL.sub("", line)
        line = PART_OF_SPEECH.sub("", line)
        for fragment in re.split(r"[,，;；、]", line):
            fragment = LABEL.sub("", fragment.strip())
            fragment = PART_OF_SPEECH.sub("", fragment)
            fragment = re.split(r"[（(【\[]", fragment, maxsplit=1)[0].strip()
            if PURE_HAN_PATTERN.fullmatch(fragment) and fragment not in found:
                found.append(fragment)
                if len(found) == 5:
                    return found
    return found


def priority(row: dict[str, str], sense_index: int) -> int:
    ranks = [int(row[x]) for x in ("bnc", "frq") if row[x].isdigit() and int(row[x]) > 0]
    frequency = round(4000 / (1 + math.log10(min(ranks)))) if ranks else 0
    stars = int(row["collins"]) if row["collins"].isdigit() else 0
    return 1000 + frequency + stars * 100 + (300 if row["oxford"] == "1" else 0) - sense_index * 110


def source_bytes(source: Path | None) -> bytes:
    if source:
        data = source.read_bytes()
    else:
        print(f"Downloading ECDICT from {UPSTREAM_URL}")
        with urllib.request.urlopen(UPSTREAM_URL, timeout=120) as response:
            data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != UPSTREAM_SHA256:
        raise SystemExit(f"ECDICT SHA-256 mismatch: expected {UPSTREAM_SHA256}, got {digest}")
    return data


def build(source: Path | None, output: Path) -> None:
    data = source_bytes(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    db = sqlite3.connect(output)
    db.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA temp_store=MEMORY;
        CREATE TABLE entries (
          key TEXT NOT NULL,
          simplified TEXT NOT NULL,
          traditional TEXT,
          score INTEGER NOT NULL,
          source TEXT NOT NULL,
          PRIMARY KEY (key, simplified)
        ) WITHOUT ROWID;
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        """
    )
    insert = """
        INSERT INTO entries (key, simplified, traditional, score, source)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(key, simplified) DO UPDATE SET
          traditional = CASE WHEN excluded.score > score THEN excluded.traditional ELSE traditional END,
          source = CASE WHEN excluded.score > score THEN excluded.source ELSE source END,
          score = MAX(score, excluded.score)
    """
    count = 0
    with db:
        rows = csv.DictReader(io.StringIO(data.decode("utf-8-sig")))
        for row in rows:
            key = normalize_key(row["word"])
            translation = row["translation"].strip()
            if not KEY_PATTERN.fullmatch(key) or not HAN_PATTERN.search(translation):
                continue
            words = key.split()
            has_frequency = (
                row["oxford"] == "1"
                or row["collins"] not in ("", "0")
                or row["bnc"] not in ("", "0")
                or row["frq"] not in ("", "0")
            )
            direct_phrase = (
                2 <= len(words) <= 4
                and len(key) <= 40
                and PURE_HAN_PATTERN.fullmatch(translation) is not None
            )
            if not (has_frequency or direct_phrase):
                continue
            senses = candidate_senses(translation)
            for index, text in enumerate(senses):
                db.execute(insert, (key, text, None, priority(row, index), "ECDICT"))
                count += 1

        seed_order: dict[str, int] = {}
        for line in (ROOT / "Resources" / "core.tsv").read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) not in (2, 3):
                raise ValueError(f"Invalid core.tsv entry: {line}")
            english, simplified = columns[:2]
            traditional = columns[2] if len(columns) == 3 else None
            key = normalize_key(english)
            if not KEY_PATTERN.fullmatch(key) or not PURE_HAN_PATTERN.fullmatch(simplified):
                raise ValueError(f"Invalid core.tsv entry: {line}")
            seed_order[key] = seed_order.get(key, 0) + 1
            db.execute(insert, (key, simplified, traditional, 20000 - seed_order[key] * 100, "core"))

        db.executemany(
            "INSERT INTO metadata VALUES (?, ?)",
            [
                ("source", UPSTREAM_URL),
                ("sha256", UPSTREAM_SHA256),
                ("license", "MIT; copyright 2025 Linwei"),
                ("format", "1"),
            ],
        )
    db.execute("ANALYZE")
    db.execute("VACUUM")
    words = db.execute("SELECT COUNT(DISTINCT key) FROM entries").fetchone()[0]
    entries = db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    db.close()
    print(f"Built {output}: {words:,} English keys, {entries:,} Chinese candidates ({count:,} ECDICT senses)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Local copy of pinned ecdict.csv")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    options = parser.parse_args()
    build(options.source, options.output)
