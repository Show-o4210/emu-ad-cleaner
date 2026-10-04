"""Download a pinned minimal Android SDK locally, verifying official archive hashes."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(os.environ.get("MUMU_ANDROID_SDK_ROOT", r"F:\Tools\.agent\tools\android-sdk\35"))
CACHE = Path(os.environ.get("MUMU_SDK_CACHE", r"F:\Tools\.agent\cache\android-sdk"))
BASE = "https://dl.google.com/android/repository/"

def fetch(url, destination):
    with urllib.request.urlopen(url, timeout=60) as response, destination.open("wb") as out:
        while block := response.read(1024 * 1024):
            out.write(block)

def prepare(package):
    path = package.attrib["path"]
    for archive in package.findall("./archives/archive"):
        host = archive.findtext("host-os")
        if host not in (None, "windows"):
            continue
        complete = archive.find("complete")
        url = complete.findtext("url")
        checksum = complete.find("checksum")
        algorithm = checksum.attrib.get("type", "sha1")
        expected = checksum.text.strip()
        archive_path = CACHE / url
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        if not archive_path.exists():
            print("Downloading", path, url, flush=True)
            fetch(BASE + url, archive_path)
        with archive_path.open("rb") as inp:
            actual = hashlib.file_digest(inp, algorithm).hexdigest()
        if actual != expected:
            raise RuntimeError("Archive checksum mismatch: " + url)
        dest = ROOT / Path(*path.split(";"))
        dest.mkdir(parents=True, exist_ok=True)
        if not (dest / "source.properties").exists():
            with zipfile.ZipFile(archive_path) as z:
                for entry in z.infolist():
                    relative = Path(*entry.filename.split("/")[1:])
                    if not relative.parts:
                        continue
                    target = dest / relative
                    if not target.resolve().is_relative_to(dest.resolve()):
                        raise RuntimeError("Unsafe archive path")
                    if entry.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(z.read(entry))
        print("Ready", str(dest), flush=True)
        return {"package": path, "url": BASE + url, "checksum_algorithm": algorithm, "checksum": actual}
    raise RuntimeError("No compatible archive: " + path)

if __name__ == "__main__":
    ROOT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    metadata = CACHE / "repository2-3.xml"
    fetch(BASE + "repository2-3.xml", metadata)
    tree = ET.parse(metadata)
    wanted = {"build-tools;35.0.0", "platforms;android-35"}
    packages = [p for p in tree.getroot() if p.tag.endswith("remotePackage") and p.attrib.get("path") in wanted]
    if len(packages) != len(wanted):
        raise RuntimeError("Pinned SDK packages missing from official index")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        records = list(pool.map(prepare, packages))
    (ROOT / "download-provenance.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
