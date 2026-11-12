#!/usr/bin/env python3
"""Adds one release to a Sparkle appcast.xml, newest first.

Usage:
    add_appcast_item.py APPCAST --version 0.6.0 --build 42 --url URL \
        --signature-line 'sparkle:edSignature="…" length="…"' --min-os 14.6 \
        [--release-notes-url URL] [--date RFC822]
    add_appcast_item.py APPCAST --next-build
    add_appcast_item.py APPCAST --check --build 42 --version 0.6.0

`--signature-line` is exactly what Sparkle's `sign_update` prints for the
archive. Sparkle decides what's newer by comparing build numbers, so a build
has to be a whole number higher than every one already in the appcast;
`--next-build` prints the next free one and `--check` tests a build and
version without changing anything.
"""
import argparse
import email.utils
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
# 0.5.0, the last release before Sparkle, shipped as build 1.
FIRST_BUILD = 2


def q(name):
    return f"{{{SPARKLE}}}{name}"


def releases(appcast_text):
    """The (build, version) of every item in the appcast."""
    try:
        root = ET.fromstring(appcast_text)
    except ET.ParseError as error:
        raise ValueError(f"the appcast isn't valid XML: {error}")
    channel = root.find("channel")
    if channel is None:
        raise ValueError("the appcast has no <channel>")
    found = []
    for item in channel.findall("item"):
        build = (item.findtext(q("version")) or "").strip()
        if not build.isdigit():
            raise ValueError(f"the appcast lists a build that isn't a whole number: {build!r}")
        found.append((int(build), (item.findtext(q("shortVersionString")) or "").strip()))
    return found


def next_build(appcast_text):
    return max([build for build, _ in releases(appcast_text)], default=FIRST_BUILD - 1) + 1


def check_release(appcast_text, build, version):
    """Raises ValueError unless `build`/`version` can be added as the newest release."""
    if not str(build).isdigit():
        raise ValueError(f"the build must be a whole number, not {build!r}")
    for listed_build, listed_version in releases(appcast_text):
        if listed_version == version:
            raise ValueError(f"version {version} is already in the appcast")
        if int(build) <= listed_build:
            raise ValueError(
                f"build {int(build)} isn't higher than build {listed_build}, which is already in the appcast"
            )


def add_item(appcast_text, version, build, url, signature_line, min_os,
             release_notes_url=None, date=None):
    signature = re.search(r'sparkle:edSignature="([^"]+)"', signature_line)
    length = re.search(r'length="(\d+)"', signature_line)
    if not signature or not length:
        raise ValueError("signature line must contain sparkle:edSignature and length")
    check_release(appcast_text, build, version)
    # The item is written with the sparkle: prefix, so the document has to
    # declare it under that name.
    if f'xmlns:sparkle="{SPARKLE}"' not in appcast_text:
        raise ValueError("the appcast doesn't declare the sparkle: namespace")

    lines = [
        "<item>",
        f"    <title>Version {escape(version)}</title>",
        f"    <pubDate>{escape(date or email.utils.formatdate(usegmt=True))}</pubDate>",
        f"    <sparkle:version>{int(build)}</sparkle:version>",
        f"    <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>",
        f"    <sparkle:minimumSystemVersion>{escape(min_os)}</sparkle:minimumSystemVersion>",
    ]
    if release_notes_url:
        lines.append(f"    <sparkle:releaseNotesLink>{escape(release_notes_url)}</sparkle:releaseNotesLink>")
    lines += [
        f"    <enclosure url={quoteattr(url)} length={quoteattr(length.group(1))}"
        f' type="application/octet-stream" sparkle:edSignature={quoteattr(signature.group(1))}/>',
        "</item>",
    ]
    item = "".join(f"        {line}\n" for line in lines)

    # Spliced into the text rather than re-serialized, so comments and
    # anything else added to the appcast by hand survive. Newest first:
    # before the first existing <item>, else at the end of the channel.
    first_item = re.search(r"^[ \t]*<item[\s>]", appcast_text, re.MULTILINE)
    end_of_channel = re.search(r"^[ \t]*</channel>", appcast_text, re.MULTILINE)
    position = first_item or end_of_channel
    if not position:
        raise ValueError("can't find where to add the item: no <item> or </channel> at the start of a line")
    updated = appcast_text[:position.start()] + item + appcast_text[position.start():]
    if releases(updated)[0] != (int(build), version):
        raise ValueError("adding the item didn't leave it first in the appcast")
    return updated


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("appcast")
    parser.add_argument("--next-build", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--version")
    parser.add_argument("--build")
    parser.add_argument("--url")
    parser.add_argument("--signature-line")
    parser.add_argument("--min-os")
    parser.add_argument("--release-notes-url")
    parser.add_argument("--date")
    args = parser.parse_args()

    def require(*names):
        missing = [f"--{name.replace('_', '-')}" for name in names if getattr(args, name) is None]
        if missing:
            parser.error(f"missing {', '.join(missing)}")

    with open(args.appcast, encoding="utf-8") as handle:
        text = handle.read()
    try:
        if args.next_build:
            print(next_build(text))
            return
        if args.check:
            require("version", "build")
            check_release(text, args.build, args.version)
            return
        require("version", "build", "url", "signature_line", "min_os")
        updated = add_item(text, args.version, args.build, args.url, args.signature_line,
                           args.min_os, args.release_notes_url, args.date)
    except ValueError as error:
        sys.exit(f"error: {error}")
    with open(args.appcast, "w", encoding="utf-8") as handle:
        handle.write(updated)


if __name__ == "__main__":
    main()
