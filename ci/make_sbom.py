#!/usr/bin/env python3
"""Produce a single, declared-type SPDX 2.2 SBOM from Yocto's multi-document output.

Yocto kirkstone (poky 4.0.35) does not produce a single-file SBOM: it
produces one document per recipe, per package and per runtime, plus an
index.json, all inside <image>.spdx.tar.zst. The <image>.spdx.json file next
to the image is not self-contained: it covers one package and references
the rest via externalDocumentRefs. This script merges them into one file
with a declared SBOM type (build or deployed) and an optional --lean filter
that keeps only CONTAINS/DESCRIBES relationships.

NOTE: not yet validated against an SPDX validator or a composition-analysis
tool. Validate before using the output outside the company.

Usage
-----
  tar --zstd -xf core-image-...spdx.tar.zst -C /tmp/spdx
  ./make_sbom.py /tmp/spdx -o merged.spdx.json
  ./make_sbom.py /tmp/spdx -o merged.spdx.json --lean
"""
import argparse, json, pathlib, sys

CONTENT_RELS = {"CONTAINS", "CONTAINED_BY", "DESCRIBES", "DESCRIBED_BY"}

# Packages that only live on the build machine, not on the device: -native
# are Yocto's own build-time tools, -cross/-crosssdk are cross-toolchains.
HOST_SUFFIXES = ("-native", "-cross", "-crosssdk", "-cross-canadian")
HOST_INFIXES = ("-cross-", "-crosssdk-", "-nativesdk-")


def is_host_only(name: str) -> bool:
    """True if the package belongs to the build environment, not the image."""
    if not name:
        return False
    return name.endswith(HOST_SUFFIXES) or any(i in name for i in HOST_INFIXES) \
        or name.startswith("nativesdk-")


# SPDX 2.2 has no field to declare the SBOM type, so it's recorded in the
# document name and the creationInfo comment instead.
SBOM_TYPES = {
    "build": ("Build SBOM",
              "Generated during the build. Includes the build-time dependencies, so it lists "
              "host tools (-native, -cross) that are not present on the device."),
    "deployed": ("Deployed SBOM",
                 "Inventory of what is installed on the device. Host build tools (-native, "
                 "-cross) are excluded: they run on the build machine and are not shipped."),
}


def load_installed(path):
    """The exact list of packages installed in the image, from buildhistory.

    Lives at
      build/buildhistory/images/<machine>/<libc>/<image>/installed-package-names.txt
    and is published as a CI log artifact.
    """
    return {l.strip() for l in open(path) if l.strip()}


def merge(src: pathlib.Path, name: str, lean: bool, sbom_type: str, installed=None):
    index = json.load(open(src / "index.json"))["documents"]
    packages, rels, lic, dropped = [], [], {}, []
    seen, collisions, read = set(), 0, 0

    for entry in index:
        f = src / entry["filename"]
        if not f.exists():
            continue
        doc = json.load(open(f))
        read += 1

        for p in doc.get("packages", []):
            pid = p.get("SPDXID")
            if pid in seen:
                collisions += 1
                continue
            if sbom_type == "deployed":
                pname = p.get("name") or ""
                # With the buildhistory list, keep what's actually installed.
                # Without it, fall back to name matching (approximate).
                drop = pname not in installed if installed is not None else is_host_only(pname)
                if drop:
                    dropped.append(pname)
                    continue
            seen.add(pid)
            packages.append(p)

        for r in doc.get("relationships", []):
            if lean and r.get("relationshipType") not in CONTENT_RELS:
                continue
            # "DocumentRef-xxx:SPDXRef-yyy" -> "SPDXRef-yyy": Yocto's SPDXIDs
            # are already unique across documents.
            for k in ("spdxElementId", "relatedSpdxElement"):
                v = r.get(k, "")
                if isinstance(v, str) and v.startswith("DocumentRef-") and ":" in v:
                    r[k] = v.split(":", 1)[1]
            rels.append(r)

        for e in doc.get("hasExtractedLicensingInfos", []):
            prev = lic.get(e["licenseId"])
            # Keep the entry that actually has the license text.
            if prev is None or (not prev.get("extractedText") and e.get("extractedText")):
                lic[e["licenseId"]] = e

    empty = [k for k, v in lic.items() if not v.get("extractedText")]
    label, meaning = SBOM_TYPES[sbom_type]
    comment = (
        f"SBOM type: {label} (CISA taxonomy). {meaning} "
        f"Merged from {read} SPDX documents produced by Yocto create-spdx. "
        "PRELIMINARY, NOT VALIDATED: see tools/make_sbom.py."
    )
    if sbom_type == "deployed":
        comment += f" {len(dropped)} host-only packages were excluded."
    if lean:
        comment += (" Only content relationships are kept; the build-provenance "
                    "relationships (GENERATED_FROM, BUILD_DEPENDENCY_OF) are dropped.")
    return {
        "spdxVersion": "SPDX-2.2",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"{name} ({sbom_type})",
        "documentNamespace": f"http://spdx.org/spdxdoc/{name}-{sbom_type}",
        "creationInfo": {
            "created": "1970-01-01T00:00:00Z",
            "creators": ["Tool: sysele-merge-spdx-preliminary",
                         "Organization: System Electronics"],
            "comment": comment,
        },
        "packages": packages,
        "relationships": rels,
        "hasExtractedLicensingInfos": list(lic.values()),
    }, dict(read=read, packages=len(packages), rels=len(rels),
            lic=len(lic), collisions=collisions, empty=empty, dropped=dropped)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=pathlib.Path, help="folder with the extracted documents")
    ap.add_argument("-o", "--out", type=pathlib.Path, default=pathlib.Path("merged.spdx.json"))
    ap.add_argument("-n", "--name", default="merged")
    ap.add_argument("-t", "--type", choices=sorted(SBOM_TYPES), default="build",
                    help="build = everything Yocto generates; deployed = only what's "
                         "on the device, excluding host build tools")
    ap.add_argument("--installed", type=pathlib.Path,
                    help="buildhistory's installed-package-names.txt: makes the "
                         "deployed type keep exactly what's in the image")
    ap.add_argument("--lean", action="store_true",
                    help="keep only content relationships, not build provenance")
    a = ap.parse_args()

    if not (a.src / "index.json").exists():
        sys.exit(f"{a.src}/index.json not found: extract the .spdx.tar.zst first")

    installed = load_installed(a.installed) if a.installed else None
    if a.type == "deployed" and installed is None:
        print("  note: without --installed the filter is name-based (approximate)")
    doc, st = merge(a.src, a.name, a.lean, a.type, installed)
    a.out.write_text(json.dumps(doc, indent=2))

    print(f"  type                 {SBOM_TYPES[a.type][0]}")
    print(f"  documents read       {st['read']}")
    print(f"  packages             {st['packages']}")
    print(f"  relationships        {st['rels']}")
    print(f"  extracted licenses   {st['lic']}")
    print(f"  conflicting SPDXID   {st['collisions']}")
    print(f"  size                 {a.out.stat().st_size/1048576:.1f} MB")
    if st["dropped"]:
        print(f"  excluded (host-only) {len(st['dropped'])}")
    if st["empty"]:
        print(f"  WARNING: {len(st['empty'])} licenses with no text: {', '.join(st['empty'][:6])}")
        print("     a license with no text makes the SBOM incomplete exactly on")
        print("     proprietary components.")


if __name__ == "__main__":
    main()
