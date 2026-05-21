#!/usr/bin/env python3
from __future__ import annotations

"""Convert protobuf payloads between JSON and binary wire format."""

import argparse
import importlib
import json
import shutil
import subprocess
import sys
import re
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
 
from google.protobuf import json_format
from google.protobuf import symbol_database


SCRIPT_ROOT = Path(__file__).resolve().parent
DEFAULT_TMP_ROOT = SCRIPT_ROOT / "tmp"
LAST_TMP_DIR_FILE = SCRIPT_ROOT / ".convert_protobuf_json.last_tmp_dir"


def _pb2_path_for_import(import_path: str, tmp_dir: Path) -> Path:
  import_file = Path(import_path)
  return tmp_dir / import_file.with_name(import_file.stem + "_pb2.py")


def read_last_tmp_dir() -> Path | None:
  if not LAST_TMP_DIR_FILE.exists():
    return None
  saved = LAST_TMP_DIR_FILE.read_text().strip()
  if not saved:
    return None
  return Path(saved).resolve()


def write_last_tmp_dir(tmp_dir: Path) -> None:
  LAST_TMP_DIR_FILE.write_text(f"{tmp_dir}\n")


def clear_last_tmp_dir(tmp_dir: Path) -> None:
  saved = read_last_tmp_dir()
  if saved == tmp_dir and LAST_TMP_DIR_FILE.exists():
    LAST_TMP_DIR_FILE.unlink()


def resolve_tmp_dir(args: argparse.Namespace, *, prefer_saved: bool = False) -> Path:
  if args.tmp_dir:
    return args.tmp_dir.resolve()
  if prefer_saved:
    saved = read_last_tmp_dir()
    if saved is not None:
      return saved
  return DEFAULT_TMP_ROOT


def resolve_buf_lock(args: argparse.Namespace, root: Path) -> tuple[Path, bool]:
  if args.buf_lock:
    return args.buf_lock.resolve(), True
  return (root / "buf.lock").resolve(), False


def ensure_tmp_root(tmp_dir: Path) -> None:
  tmp_dir.mkdir(parents=True, exist_ok=True)


def existing_buf_export_paths(buf_lock_path: Path, tmp_dir: Path) -> list[Path]:
  include_paths: list[Path] = []
  buf_export_root = tmp_dir / "buf_exports"
  for owner, repository in parse_buf_lock(buf_lock_path):
    dest = buf_export_root / owner / repository
    if dest.exists():
      include_paths.append(dest)
  return include_paths
	
def resolve_proto_file(path: Path, root: Path) -> Path:
  """Resolve proto path relative to the configured root and ensure it exists."""
  candidate = path if path.is_absolute() else (root / path)
  candidate = candidate.resolve()
  if not candidate.exists():
    raise FileNotFoundError(f"Proto file not found: {candidate}")
  try:
    candidate.relative_to(root)
  except ValueError as exc:  # pragma: no cover - guardrail
    raise ValueError("Proto file must live under the configured root") from exc
  return candidate


def _relative_paths(proto_path: Path, root: Path) -> tuple[Path, Path]:
  relative_proto = proto_path.relative_to(root)
  pb2_relative = relative_proto.with_name(relative_proto.stem + "_pb2.py")
  return relative_proto, pb2_relative


IMPORT_RE = re.compile(r'^\s*import\s+"([^\"]+)"')


@dataclass(frozen=True)
class ProtoSpec:
  abs_path: Path
  import_path: str


def _parse_imports(proto_file: Path, include_paths: list[Path], root: Path) -> list[ProtoSpec]:
  imports: list[ProtoSpec] = []
  search_paths = [root, *include_paths]
  for line in proto_file.read_text().splitlines():
    match = IMPORT_RE.match(line)
    if not match:
      continue
    import_target = match.group(1)
    resolved: Path | None = None
    for base in search_paths:
      candidate = base / import_target
      if candidate.exists():
        resolved = candidate
        break
    if resolved is not None:
      imports.append(ProtoSpec(abs_path=resolved, import_path=import_target))
  return imports


def _collect_proto_closure(proto_file: Path, include_paths: list[Path], root: Path) -> list[ProtoSpec]:
  stack: list[ProtoSpec] = [
      ProtoSpec(
          abs_path=proto_file,
          import_path=str(proto_file.relative_to(root)),
      )
  ]
  seen: set[str] = set()
  ordered: list[ProtoSpec] = []
  while stack:
    current = stack.pop()
    if current.import_path in seen:
      continue
    seen.add(current.import_path)
    ordered.append(current)
    for dep in _parse_imports(current.abs_path, include_paths, root):
      stack.append(dep)
  return ordered


def parse_buf_lock(buf_lock_path: Path) -> list[tuple[str, str]]:
  """Return (owner, repository) tuples declared in buf.lock."""
  if not buf_lock_path.exists():
    return []
  deps: list[tuple[str, str]] = []
  current: dict[str, str] | None = None
  in_deps = False
  for raw_line in buf_lock_path.read_text().splitlines():
    line = raw_line.rstrip()
    if not line.strip() or line.lstrip().startswith("#"):
      continue
    if not in_deps:
      if line.startswith("deps:"):
        in_deps = True
      continue
    if line and not line.startswith(" "):
      break
    stripped = line.strip()
    if stripped.startswith("- "):
      if current and current.get("remote") == "buf.build" and current.get("owner") and current.get("repository"):
        deps.append((current["owner"], current["repository"]))
      current = {}
      stripped = stripped[2:].strip()
      if stripped and ":" in stripped:
        key, value = stripped.split(":", 1)
        current[key.strip()] = value.strip()
      continue
    if current is None:
      continue
    if ":" in stripped:
      key, value = stripped.split(":", 1)
      current[key.strip()] = value.strip()
  if current and current.get("remote") == "buf.build" and current.get("owner") and current.get("repository"):
    deps.append((current["owner"], current["repository"]))
  seen: set[tuple[str, str]] = set()
  unique_deps: list[tuple[str, str]] = []
  for dep in deps:
    if dep in seen:
      continue
    seen.add(dep)
    unique_deps.append(dep)
  return unique_deps


def export_buf_modules(
    root: Path,
    buf_lock_path: Path,
    tmp_dir: Path,
    force: bool = False,
) -> list[Path]:
  """Export buf.lock dependencies and return include paths."""
  include_paths = existing_buf_export_paths(buf_lock_path, tmp_dir)
  deps = parse_buf_lock(buf_lock_path)
  buf_export_root = tmp_dir / "buf_exports"
  if not deps:
    return include_paths
  for owner, repository in deps:
    dest = buf_export_root / owner / repository
    if dest.exists():
      if force:
        shutil.rmtree(dest)
      else:
        continue
    ensure_tmp_root(tmp_dir)
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Exporting buf module {owner}/{repository} ...")
    subprocess.run(
        [
            "buf",
            "export",
            f"buf.build/{owner}/{repository}",
            "--output",
            str(dest),
        ],
        cwd=root,
        check=True,
    )
    if dest not in include_paths:
      include_paths.append(dest)
  return include_paths


def cleanup_generated_artifacts(tmp_dir: Path) -> None:
  if tmp_dir.exists():
    shutil.rmtree(tmp_dir)
    clear_last_tmp_dir(tmp_dir)
    print(f"Removed generated workspace {tmp_dir}")
    return
  print("Cleanup complete. No generated workspace found.")


def ensure_generated_module(
    proto_path: Path,
    root: Path,
    tmp_dir: Path,
    force_regen: bool = False,
    extra_proto_paths: list[Path] | None = None,
) -> Path:
  """Generate *_pb2.py for the given proto if needed and return its relative path."""
  relative_proto, pb2_relative = _relative_paths(proto_path, root)
  include_paths = extra_proto_paths or []
  closure = _collect_proto_closure(proto_path, include_paths, root)
  if not force_regen:
    missing = [
        _pb2_path_for_import(spec.import_path, tmp_dir)
        for spec in closure
        if not _pb2_path_for_import(spec.import_path, tmp_dir).exists()
    ]
    if not missing:
      return pb2_relative
  print(f"Generating Python bindings for {relative_proto} via protoc ...")
  generated_file = _pb2_path_for_import(str(relative_proto), tmp_dir)
  ensure_tmp_root(tmp_dir)
  generated_file.parent.mkdir(parents=True, exist_ok=True)
  proto_cmd = ["protoc", f"--proto_path={root}"]
  for extra_path in include_paths:
    proto_cmd.append(f"--proto_path={extra_path}")
  proto_cmd.append(f"--python_out={tmp_dir}")
  for spec in closure:
    proto_cmd.append(spec.import_path)
  subprocess.run(proto_cmd, cwd=root, check=True)
  return pb2_relative


def load_pb2_module(pb2_relative: Path, tmp_dir: Path, force_reload: bool) -> ModuleType:
  ensure_tmp_root(tmp_dir)
  if str(tmp_dir) not in sys.path:
    sys.path.insert(0, str(tmp_dir))
  module_name = ".".join(pb2_relative.with_suffix("").parts)
  if force_reload and module_name in sys.modules:
    return importlib.reload(sys.modules[module_name])
  return importlib.import_module(module_name)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
      formatter_class=argparse.RawDescriptionHelpFormatter,
      description=(
          "Convert protobuf payloads between JSON and binary wire format.\n"
          "Use -root to point at the base directory containing your protos.\n"
          "If -buf-lock is omitted, the script looks for buf.lock under -root.\n"
          "If -tmp-dir is omitted, generated artifacts go under tmp/ next to this script.\n"
          "Requires the protobuf runtime (python3 -m pip install --user protobuf)"
          " and the buf CLI (brew install buf) for vendoring dependencies."
      ),
      epilog=(
          "Examples:\n"
          "  Decode protobuf to JSON:\n"
          "    python3 tools/convert_protobuf_json.py -root . "
          "-proto-file anghamak/osn/tvguide/v1/service.proto "
          "-message anghamak.osn.tvguide.v1.GetChannelsResponse "
          "-input-bin /tmp/input.bin -output-json /tmp/output.json\n\n"
          "  Encode JSON to protobuf with a custom tmp dir:\n"
          "    python3 tools/convert_protobuf_json.py -root . -tmp-dir ./tools/tmp "
          "-proto-file anghamak/osn/tvguide/v1/service.proto "
          "-message anghamak.osn.tvguide.v1.GetChannelsResponse "
          "-input-json /tmp/input.json -output-bin /tmp/output.bin\n\n"
          "  Decode protobuf to JSON with an explicit buf.lock:\n"
          "    python3 tools/convert_protobuf_json.py -root . -buf-lock ./buf.lock "
          "-proto-file anghamak/osn/tvguide/v1/service.proto "
          "-message anghamak.osn.tvguide.v1.GetChannelsResponse "
          "-input-bin /tmp/input.bin -output-json /tmp/output.json\n\n"
          "  Clean generated artifacts:\n"
          "    python3 tools/convert_protobuf_json.py -root . -cleanup"
      ),
  )
  parser.add_argument(
      "-root",
      type=Path,
      required=True,
      help="Base directory used to resolve proto files and imports.",
  )
  parser.add_argument(
      "-tmp-dir",
      type=Path,
      help=(
          "Directory used for generated protobuf bindings and exported dependencies."
          " Defaults to tmp/ next to this script."
      ),
  )
  parser.add_argument(
      "-buf-lock",
      type=Path,
      help=(
          "Optional path to the buf.lock file used to export Buf dependencies."
          " Defaults to <root>/buf.lock."
      ),
  )
  parser.add_argument(
      "-proto-file",
      type=Path,
      help=(
          "Relative or absolute path to the .proto file defining the target message."
      ),
  )
  parser.add_argument(
      "-message",
      help=(
          "Fully qualified message name within the selected proto schema"
          " (e.g. 'anghamak.osn.auth.v1.LoginResponse')."
      ),
  )
  parser.add_argument(
      "-input-json",
      dest="input_json",
      type=Path,
      help="Path to the JSON file describing the protobuf message to encode.",
  )
  parser.add_argument(
      "-output-bin",
      dest="output_bin",
      type=Path,
      help="Path where the encoded binary protobuf should be written.",
  )
  parser.add_argument(
      "-input-bin",
      dest="input_bin",
      type=Path,
      help="Path to the binary protobuf payload to decode.",
  )
  parser.add_argument(
      "-output-json",
      dest="output_json",
      type=Path,
      help="Path where the decoded JSON payload should be written.",
  )
  parser.add_argument(
      "-allow-unknown-fields",
      action="store_true",
      help=(
          "Allow fields that are not known to the selected message schema."
          " Unknown fields will be ignored."
      ),
  )
  parser.add_argument(
      "-regen",
      action="store_true",
      help="Regenerate Python bindings even if they already exist.",
  )
  parser.add_argument(
      "-cleanup",
      action="store_true",
      help=(
          "Remove the resolved generated workspace and exit. Cleanup uses"
          " -tmp-dir when provided, otherwise the last remembered tmp dir,"
          " otherwise the default script-local tmp/ directory."
      ),
  )
  return parser.parse_args()


def determine_conversion_direction(args: argparse.Namespace) -> str:
  if args.cleanup:
    if args.input_json or args.output_bin or args.input_bin or args.output_json:
      raise SystemExit(
          "-cleanup cannot be combined with conversion input/output arguments."
      )
    return "cleanup"

  encode_requested = bool(args.input_json or args.output_bin)
  decode_requested = bool(args.input_bin or args.output_json)

  if encode_requested and decode_requested:
    raise SystemExit(
        "Choose one conversion direction: "
        "either -input-json/-output-bin or -input-bin/-output-json."
    )

  if encode_requested:
    missing = [
        name
        for name, value in {
            "-input-json": args.input_json,
            "-output-bin": args.output_bin,
        }.items()
        if not value
    ]
    if missing:
      joined = ", ".join(missing)
      raise SystemExit(f"Missing required arguments for JSON to protobuf: {joined}")
    return "encode"

  if decode_requested:
    missing = [
        name
        for name, value in {
            "-input-bin": args.input_bin,
            "-output-json": args.output_json,
        }.items()
        if not value
    ]
    if missing:
      joined = ", ".join(missing)
      raise SystemExit(f"Missing required arguments for protobuf to JSON: {joined}")
    return "decode"

  raise SystemExit(
      "Specify a conversion direction with either "
      "-input-json/-output-bin or -input-bin/-output-json."
  )


def encode_json_to_protobuf(args: argparse.Namespace, message_cls: type) -> None:
  print(f"Using proto {args.proto_file} and message {args.message} ...")
  print(f"Loading JSON from {args.input_json} ...")
  data = json.loads(args.input_json.read_text())
  print(f"Building {args.message} message ...")
  message = message_cls()
  json_format.ParseDict(data, message, ignore_unknown_fields=args.allow_unknown_fields)
  payload = message.SerializeToString()
  print(f"Writing binary protobuf to {args.output_bin} ...")
  args.output_bin.write_bytes(payload)
  print(f"Done. {len(payload)} bytes written.")


def decode_protobuf_to_json(args: argparse.Namespace, message_cls: type) -> None:
  print(f"Using proto {args.proto_file} and message {args.message} ...")
  print(f"Loading binary protobuf from {args.input_bin} ...")
  payload = args.input_bin.read_bytes()
  print(f"Parsing {args.message} message ...")
  message = message_cls()
  message.ParseFromString(payload)
  print(f"Writing JSON to {args.output_json} ...")
  args.output_json.write_text(
      json_format.MessageToJson(message, indent=2, preserving_proto_field_name=True)
  )
  print(f"Done. {len(payload)} bytes read.")


def main() -> None:
  args = parse_args()
  direction = determine_conversion_direction(args)
  missing = [
      name
      for name, value in {
          "-proto-file": args.proto_file if direction != "cleanup" else True,
          "-message": args.message if direction != "cleanup" else True,
      }.items()
      if not value
  ]
  if missing:
    joined = ", ".join(missing)
    raise SystemExit(f"Missing required arguments: {joined}")
  if direction == "cleanup":
    cleanup_generated_artifacts(resolve_tmp_dir(args, prefer_saved=True))
    return
  root = args.root.resolve()
  tmp_dir = resolve_tmp_dir(args)
  write_last_tmp_dir(tmp_dir)
  buf_lock_path, buf_lock_explicit = resolve_buf_lock(args, root)
  if buf_lock_explicit and not buf_lock_path.exists():
    raise SystemExit(f"Buf lock file not found: {buf_lock_path}")
  proto_path = resolve_proto_file(args.proto_file, root)
  buf_include_paths = export_buf_modules(
      root,
      buf_lock_path,
      tmp_dir,
      force=args.regen,
  )
  pb2_relative = ensure_generated_module(
      proto_path,
      root,
      tmp_dir,
      force_regen=args.regen,
      extra_proto_paths=buf_include_paths,
  )
  load_pb2_module(pb2_relative, tmp_dir, force_reload=args.regen)
  sym_db = symbol_database.Default()
  try:
    message_cls = sym_db.GetSymbol(args.message)
  except KeyError as exc:
    raise SystemExit(f"Unknown message type: {args.message}") from exc
  args.proto_file = proto_path
  if direction == "encode":
    encode_json_to_protobuf(args, message_cls)
    return
  decode_protobuf_to_json(args, message_cls)


if __name__ == "__main__":
  main()
