#!/usr/bin/env python3
"""Adds one release to a Sparkle appcast.xml, newest first.

Usage:
    add_appcast_item.py APPCAST --version 0.6.0 --build 42 --url URL \
        --signature-line 'sparkle:edSignature="…" length="…"' \
        [--min-os 14.6] [--release-notes-url URL] [--date RFC822]

`--signature-line` is exactly what Sparkle's `sign_update` prints for the
archive. Refuses to add a build that's already in the appcast, since Sparkle
decides what's newer by comparing build numbers.
"""
import argparse
import email.utils
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def q(name):
    return f"{{{SPARKLE}}}{name}"


def add_item(appcast_text, version, build, url, signature_line, min_os="14.6",
             release_notes_url=None, date=None):
    signature = re.search(r'sparkle:edSignature="([^"]+)"', signature_line)
    length = re.search(r'length="(\d+)"', signature_line)
    if not signature or not length:
        raise ValueError("signature line must contain sparkle:edSignature and length")

    root = ET.fromstring(appcast_text)
    channel = root.find("channel")
    for existing in channel.findall("item"):
        if existing.findtext(q("version")) == str(build):
            raise ValueError(f"build {build} is already in the appcast")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "pubDate").text = date or email.utils.formatdate(usegmt=True)
    ET.SubElement(item, q("version")).text = str(build)
    ET.SubElement(item, q("shortVersionString")).text = version
    ET.SubElement(item, q("minimumSystemVersion")).text = min_os
    if release_notes_url:
        ET.SubElement(item, "link").text = release_notes_url
    ET.SubElement(item, "enclosure", {
        "url": url,
        "length": length.group(1),
        "type": "application/octet-stream",
        q("edSignature"): signature.group(1),
    })

    # Newest first: before the first existing <item>, else at the end.
    children = list(channel)
    index = next((i for i, child in enumerate(children) if child.tag == "item"), len(children))
    channel.insert(index, item)
    ET.indent(root, space="    ")
    return '<?xml version="1.0" standalone="yes"?>\n' + ET.tostring(root, encoding="unicode") + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("appcast")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature-line", required=True)
    parser.add_argument("--min-os", default="14.6")
    parser.add_argument("--release-notes-url")
    parser.add_argument("--date")
    args = parser.parse_args()
    with open(args.appcast, encoding="utf-8") as handle:
        text = handle.read()
    try:
        updated = add_item(text, args.version, args.build, args.url, args.signature_line,
                           args.min_os, args.release_notes_url, args.date)
    except ValueError as error:
        sys.exit(f"error: {error}")
    with open(args.appcast, "w", encoding="utf-8") as handle:
        handle.write(updated)


if __name__ == "__main__":
    main()
