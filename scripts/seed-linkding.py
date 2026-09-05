#!/usr/bin/env python3
"""Seed a throwaway linkding with the fixtures RealServerTests expect.

Usage:
  DINGMARK_TEST_SERVER=http://127.0.0.1:9090 DINGMARK_TEST_TOKEN=<api token> \
    python3 scripts/seed-linkding.py

Creates 130 bookmarks (120 active, 10 archived, 14 tags) on an empty
instance: a few hand-written edge cases (empty title, very long title,
Markdown notes, URL with query and fragment, shared, archived) and 122
generated "Site NNN" entries so the list paginates. Idempotent: does
nothing when the instance already holds bookmarks.
"""
import json
import os
import random
import sys
import urllib.request

server = os.environ.get("DINGMARK_TEST_SERVER", "http://127.0.0.1:9090").rstrip("/")
token = os.environ.get("DINGMARK_TEST_TOKEN")
if not token:
    sys.exit("DINGMARK_TEST_TOKEN missing")


def call(method, path, body=None):
    request = urllib.request.Request(
        server + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Token " + token, "Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


if call("GET", "/api/bookmarks/?limit=1")["count"] > 0:
    print("instance already seeded")
    sys.exit(0)

random.seed(7)
tags = ["selfhosting", "docker", "swift", "swiftui", "design", "réseau", "lecture", "recettes",
        "musique", "inbox", "ios", "sécurité", "k8s", "python"]
specials = [
    dict(url="https://example.com/no-title", title="", description="", tag_names=["inbox"], unread=True),
    dict(url="https://example.com/long-title",
         title="Un titre extrêmement long qui doit passer sur plusieurs lignes sans jamais être tronqué dans la cellule de la liste, même en corps de texte agrandi",
         description="Description longue " * 8, tag_names=["lecture", "design"], unread=True),
    dict(url="https://example.com/notes", title="Avec des notes Markdown", description="",
         notes="# Points clés\n- **Gras** et *italique*\n- Un lien vers [linkding](https://linkding.link)\n\nParagraphe avec `code` inline.\n\n1. Liste numérotée\n2. Deuxième",
         tag_names=["swift"], unread=False),
    dict(url="https://example.com/search?q=a+b&lang=fr#frag", title="URL avec query, plus et fragment", description="",
         tag_names=[], unread=True, shared=True),
    dict(url="https://www.example.org/www-prefix", title="Domaine avec www", description="", tag_names=["réseau"], unread=False),
    dict(url="https://archived.example/one", title="Archivé un", description="", tag_names=["selfhosting", "docker"],
         is_archived=True, unread=False),
    dict(url="https://archived.example/two", title="Archivé deux (tag unique)", description="", tag_names=["k8s"],
         is_archived=True, unread=True),
    dict(url="https://shared.example/", title="Partagé sur l’instance", description="Visible publiquement",
         tag_names=["python"], shared=True),
]
for special in specials:
    call("POST", "/api/bookmarks/", special)
for i in range(1, 123):
    call("POST", "/api/bookmarks/", dict(
        url=f"https://site{i}.example/page/{i}", title=f"Site {i:03d}",
        description=f"Description du site numéro {i}" if i % 3 else "",
        tag_names=random.sample(tags, k=random.choice([0, 1, 1, 2, 3])),
        unread=(i % 4 == 0), shared=(i % 10 == 0), is_archived=(i % 15 == 0)))

active = call("GET", "/api/bookmarks/?limit=1")["count"]
archived = call("GET", "/api/bookmarks/archived/?limit=1")["count"]
print(f"seeded: {active} active, {archived} archived")
