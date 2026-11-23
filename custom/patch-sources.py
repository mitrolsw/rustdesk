import base64
import io
import json
import os
import resvg_py
import shutil
import subprocess
import sys
from pathlib import Path
from PIL import Image

def load_env_file(env_path: Path) -> None:
  # Load KEY=VALUE pairs from .env if present
  if not env_path.is_file():
    print(f"ERROR: file {env_path} not found", file=sys.stderr)
    sys.exit(1)

  print(f"Loading environment from {env_path}")
  for raw_line in env_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
      continue
    if "=" not in line:
      continue

    key, val = line.split("=", 1)
    key = key.strip()
    val = val.strip()

    # Strip matching surrounding single or double quotes
    if len(val) >= 2 and ((val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'"))):
      val = val[1:-1]

    if key:
      os.environ[key] = val

def savePng(img: Image, size: int, filename: str):
  destImg = img.resize((size, size), Image.Resampling.LANCZOS)
  destImg.save(filename, format="PNG")

def saveIco(img: Image, filename: str):
  destImg = img.resize((256, 256), Image.Resampling.LANCZOS)
  icon_sizes = [(16, 16), (32, 32), (48, 48), (256, 256)]
  destImg.save(filename, format="ICO", sizes=icon_sizes)

def run_cmd(args: list[str], capture: bool = False) -> subprocess.CompletedProcess[str]:
  # Execute external commands cleanly without shell escaping issues
  return subprocess.run(
    args,
    text=True,
    capture_output=capture,
    check=False,
  )

def apply_patch_idempotent(desc: str, patch_file: Path) -> None:
  # Apply a git diff idempotently while ignoring whitespace/CRLF differences
  if not patch_file.is_file():
    print(f"ERROR: patch file not found: {patch_file}", file=sys.stderr)
    sys.exit(1)

  check_apply = run_cmd(["git", "apply", "--ignore-whitespace", "--check", str(patch_file)], capture=True)
  if check_apply.returncode == 0:
    print(f"[{desc}] applying {patch_file}...")
    apply_res = run_cmd(["git", "apply", "--ignore-whitespace", str(patch_file)], capture=True)
    if apply_res.returncode != 0:
      print(f"ERROR: [{desc}] failed during git apply", file=sys.stderr)
      print(apply_res.stderr, file=sys.stderr)
      sys.exit(1)
    print(f"[{desc}] applied OK")
    return

  check_reverse = run_cmd(["git", "apply", "--ignore-whitespace", "--reverse", "--check", str(patch_file)], capture=True)
  if check_reverse.returncode == 0:
    print(f"[{desc}] already applied, skipping")
    return

  print(f"ERROR: [{desc}] failed to apply {patch_file} (conflict or upstream drift)", file=sys.stderr)
  debug_check = run_cmd(["git", "apply", "--ignore-whitespace", "--check", str(patch_file)], capture=True)
  if debug_check.stderr:
    print(debug_check.stderr, file=sys.stderr)

  common_rs = Path("src/common.rs")
  if common_rs.is_file():
    lines = common_rs.read_text(encoding="utf-8", errors="replace").splitlines()
    start = max(0, 2599)
    end = min(len(lines), 2630)
    for idx in range(start, end):
      print(f"{idx + 1}: {lines[idx]}", file=sys.stderr)

  sys.exit(1)

def replace_in_file(file_path: Path, old: str, new: str) -> None:
  # Perform a direct string replacement on a text file
  if not file_path.is_file():
    print(f"ERROR: file not found: {file_path}", file=sys.stderr)
    sys.exit(1)

  content = file_path.read_text(encoding="utf-8")
  updated = content.replace(old, new)
  file_path.write_text(updated, encoding="utf-8", newline="\n")

def set_icons() -> None:
  # Copy custom icons into target Flutter and resource directories
  print("Replacing icons...")

  # Load SVG vector graphics and render it to memory buffer
  shutil.copy(Path("custom/icon.svg"), Path("custom/tmp/icon.svg"))
  png_bytes = resvg_py.svg_to_bytes(svg_path="custom/tmp/icon.svg", width=512, height=512)
  img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")

  # save versions
  savePng(img, 32, "custom/tmp/32x32.png")
  savePng(img, 64, "custom/tmp/64x64.png")
  savePng(img, 128, "custom/tmp/128x128.png")
  savePng(img, 256, "custom/tmp/128x128@2x.png")
  savePng(img, 256, "custom/tmp/icon.png")
  saveIco(img, "custom/tmp/icon.ico")

  # set icons into sources
  shutil.copy(Path("custom/icon.svg")           , Path("custom/tmp/icon.svg"))
  shutil.copy(Path("custom/tmp/icon.svg")       , Path("flutter/assets/icon.svg"))
  shutil.copy(Path("custom/tmp/icon.svg")       , Path("res/scalable.svg"))
  shutil.copy(Path("custom/tmp/icon.svg")       , Path("res/logo.svg"))
  shutil.copy(Path("custom/tmp/32x32.png")      , Path("res/32x32.png"))
  shutil.copy(Path("custom/tmp/64x64.png")      , Path("res/64x64.png"))
  shutil.copy(Path("custom/tmp/128x128.png")    , Path("res/128x128.png"))
  shutil.copy(Path("custom/tmp/128x128@2x.png") , Path("res/128x128@2x.png"))
  shutil.copy(Path("custom/tmp/icon.ico")       , Path("flutter/windows/runner/resources/app_icon.ico"))
  shutil.copy(Path("custom/tmp/icon.ico")       , Path("res/icon.ico"))
  shutil.copy(Path("custom/tmp/icon.ico")       , Path("res/tray-icon.ico"))

def _env_flag(name: str) -> bool:
  # Safely read optional boolean flags without failing when unset
  return (os.getenv(name) or "").strip().upper() == "Y"

def _env_str(name: str) -> str:
  # Safely read optional string environment variables
  return (os.getenv(name) or "").strip()

def build_custom_config_file():
  # Initialize root structure with empty setting maps
  default_settings: dict[str, str] = {}
  override_settings: dict[str, str] = {}

  # populate default-settings entries
  if _env_flag("CUSTOM_ALLOW_NUMERIC_ONE_TIME_PASSWORD"):
    default_settings["allow-numeric-one-time-password"] = "Y"
  temp_pwd_len = _env_str("CUSTOM_TEMPORARY_PASSWORD_LENGTH")
  if temp_pwd_len:
    default_settings["temporary-password-length"] = temp_pwd_len
  if os.getenv("CUSTOM_SET_ADAPTIVE_VIEW_STYLE").strip().upper() == "Y":
    default_settings["view-style"] = "adaptive"

  # set server data
  override_settings["custom-rendezvous-server"] = _env_str("CUSTOM_RENDEZVOUS_SERVER")
  override_settings["api-server"] = _env_str("CUSTOM_API_SERVER")
  override_settings["relay-server"] = _env_str("CUSTOM_RELAY_SERVER")
  override_settings["key"] = _env_str("CUSTOM_PUB_KEY")

  # set network options
  if _env_flag("CUSTOM_ENABLE_PUNCH"):
    override_settings["enable-tcp-punch"] = "Y"
    override_settings["enable-udp-punch"] = "Y"
    override_settings["enable-ipv6-punch"] = "Y"
  if _env_flag("CUSTOM_ENABLE_WEBRTC"):
    override_settings["enable-webrtc"] = "Y"

  # write final JSON (in .txt file)
  config_data: dict[str, object] = {
    "app-name": os.getenv("CUSTOM_APP_NAME") or "MyApp",
    "default-settings": default_settings,
    "override-settings": override_settings,
  }

  output = Path("custom/tmp/custom.txt")
  json_text = json.dumps(config_data, indent=2, ensure_ascii=False) + "\n"
  output.write_text(json_text, encoding="utf-8", newline="\n")

  print("Custom config saved to ", output)
  # print(json_text)


def main() -> None:

  # load environment vars
  script_dir = Path(__file__).resolve().parent
  env_file = script_dir / ".env"
  load_env_file(env_file)

  # replace icons
  set_icons()

  # create custom configuration file
  print("Creating custom config file...")
  build_custom_config_file()

  # raw patches
  custom_app_url = os.environ.get("CUSTOM_APP_URL", "")
  if custom_app_url != "":
    index_tis = Path("src/ui/index.tis")
    replace_in_file(index_tis, "https://rustdesk.com", custom_app_url)
    replace_in_file(index_tis, f"{custom_app_url}/blog", "https://rustdesk.com/blog")

  # source patches
  apply_patch_idempotent(
    "Disable custom.txt file signature validation",
    Path("./custom/diffs/disable-config-file-signature-check.diff"),
  )

  print("Customizations applied successfully")

if __name__ == "__main__":
  main()