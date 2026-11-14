#!/bin/bash
# 应用内更新测试：版本比较、appcast 解析、关于窗口文案与限流（全部离屏夹具），
# 可选 --live 用真实 appcast 做一次线上探针。
#
# --live 的期望值全部从线上 appcast 现取：线上最新版来自 <sparkle:version>，
# 用来比较的旧版本默认是「线上版本往回一个 patch」，也可用 --installed 覆盖。
# 脚本里不写任何具体版本号，所以每次发版都不会让这个模式变红。
#
# 网络不可用（或显式 --offline）时 --live 打印 skipped 并以 0 退出：
# 探针失败不是产品缺陷，不该算红。
#
# 用法：
#   bash replica/scripts/test-app-updates.sh                      # 只跑离屏夹具
#   bash replica/scripts/test-app-updates.sh --live               # 夹具 + 线上 appcast
#   bash replica/scripts/test-app-updates.sh --live --installed 1.0.11
#   bash replica/scripts/test-app-updates.sh --live --offline     # 强制跳过线上探针
#   bash replica/scripts/test-app-updates.sh --live --live-feed http://127.0.0.1:9/appcast.xml
#   bash replica/scripts/test-app-updates.sh --render[=目录]      # 另外渲染关于窗口截图
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-app-updates.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

default_feed='https://github.com/aexachao/BlinkClip/releases/latest/download/appcast.xml'

usage() {
  cat <<'USAGE'
用法：test-app-updates.sh [--live [--offline] [--installed <版本>] [--live-feed <URL>]]
                          [--render[=<目录>]] [--preview]
  --live            用真实 appcast 跑线上探针；期望版本从 feed 现取
  --offline         强制跳过线上探针，打印 skipped 并返回 0
  --installed <版本> 比较用的安装版本；缺省为「线上版本往回一个 patch」
  --live-feed <URL> 覆盖 feed 地址（默认 SUFeedURL 指向的 appcast）
  --render[=<目录>] 额外渲染关于窗口截图（默认 $TMPDIR/blinkclip-about-renders）
  --preview         打印 PREVIEW_APP 供人工预览
USAGE
}

live=0
offline=0
preview=0
installed=''
render_dir=''
live_feed="$default_feed"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) live=1; shift ;;
    --offline) offline=1; live=1; shift ;;
    --installed|--live-feed)
      if [[ $# -lt 2 ]]; then
        printf '%s 需要一个参数值\n' "$1" >&2
        usage >&2
        exit 2
      fi
      if [[ "$1" == --installed ]]; then installed="$2"; live=1; else live_feed="$2"; fi
      shift 2 ;;
    --installed=*) installed="${1#*=}"; live=1; shift ;;
    --live-feed=*) live_feed="${1#*=}"; shift ;;
    --render) render_dir="${BLINKCLIP_ABOUT_RENDER_DIR:-${TMPDIR:-/tmp}/blinkclip-about-renders}"; shift ;;
    --render=*) render_dir="${1#*=}"; shift ;;
    --preview) preview=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '未知参数：%s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

note() { printf '%s\n' "$*" >&2; }

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n'; }

# 版本逐段数值解析：只接受 v?1.2.3(.4)，输出四个数值分量（缺省补 0）。
# 这里全程按数值处理，禁止字符串比较（"1.0.9" > "1.0.10" 就是字符串比较的坑）。
version_components() {
  local value="$1"
  [[ "$value" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?$ ]] || return 1
  local major minor patch build=0
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[2]}))
  patch=$((10#${BASH_REMATCH[3]}))
  [[ -n "${BASH_REMATCH[5]:-}" ]] && build=$((10#${BASH_REMATCH[5]}))
  printf '%s %s %s %s\n' "$major" "$minor" "$patch" "$build"
}

# 数值比较，输出 -1 / 0 / 1；参数非法时返回 2。
version_compare() {
  local left_out right_out
  left_out=$(version_components "$1") || return 2
  right_out=$(version_components "$2") || return 2
  local -a left right
  read -r -a left <<< "$left_out"
  read -r -a right <<< "$right_out"
  local index
  for index in 0 1 2 3; do
    if (( left[index] > right[index] )); then printf '1\n'; return 0; fi
    if (( left[index] < right[index] )); then printf '%s\n' '-1'; return 0; fi
  done
  printf '0\n'
}

# 线上版本往回一个 patch（最后一个数值分量 -1）。没有更小的 patch 时不猜，
# 交给 --installed 指定。
previous_version() {
  local components
  components=$(version_components "$1") || return 1
  local -a parts
  read -r -a parts <<< "$components"
  if (( parts[3] > 0 )); then
    printf '%s.%s.%s.%s\n' "${parts[0]}" "${parts[1]}" "${parts[2]}" "$(( parts[3] - 1 ))"
    return 0
  fi
  if (( parts[2] > 0 )); then
    printf '%s.%s.%s\n' "${parts[0]}" "${parts[1]}" "$(( parts[2] - 1 ))"
    return 0
  fi
  return 1
}

# feed 里所有正式版 <sparkle:version>（预发布条目不参与比较）。
appcast_versions() {
  local file="$1"
  grep -o '<sparkle:version>[^<]*</sparkle:version>' "$file" 2>/dev/null \
    | sed -e 's|<sparkle:version>||' -e 's|</sparkle:version>||' \
    | while read -r version; do
        [[ -z "$version" ]] && continue
        version_components "$version" >/dev/null 2>&1 || continue
        printf '%s\n' "$version"
      done
}

# 取数值最大的版本（不是字典序最大）。
appcast_newest_version() {
  local newest='' candidate
  while read -r candidate; do
    [[ -z "$candidate" ]] && continue
    if [[ -z "$newest" ]] || [[ "$(version_compare "$candidate" "$newest")" == 1 ]]; then
      newest="$candidate"
    fi
  done
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

# 取 feed 的 sparkle:version，拿不到就返回非零；成功时把版本写到 stdout。
fetch_feed_version() {
  local url="$1" file="$2" attempt code note_text=''
  for attempt in 1 2; do
    if code=$(curl --silent --show-error --location --max-time 20 \
                   --write-out '%{http_code}' --output "$file" "$url" 2>"$test_root/curl.log"); then
      if [[ "$code" == 200 ]]; then
        return 0
      fi
      note_text="HTTP $code"
    else
      note_text="curl 失败：$(tr '\n' ' ' < "$test_root/curl.log")"
    fi
    if (( attempt == 1 )); then sleep 2; fi
  done
  printf '%s\n' "$note_text" > "$test_root/fetch-failure"
  return 1
}

# 自检：比较必须逐段按数值（字符串比较会把 1.0.9 排到 1.0.10 之后）。
assert_numeric_version_compare() {
  local left right want got
  while read -r left right want; do
    [[ -z "$left" ]] && continue
    got=$(version_compare "$left" "$right")
    if [[ "$got" != "$want" ]]; then
      printf 'FAIL: 版本比较 %s vs %s 得到 %s，期望 %s\n' "$left" "$right" "$got" "$want" >&2
      exit 1
    fi
  done <<'PAIRS'
1.0.9 1.0.10 -1
1.0.10 1.0.11 -1
1.0.11 1.0.11 0
1.0.11.0 1.0.11 0
1.0.12 1.0.11 1
1.2.3 1.10.0 -1
PAIRS
}
assert_numeric_version_compare

if [[ -n "$installed" ]]; then
  if ! version_components "$installed" >/dev/null 2>&1; then
    printf '非法 --installed 版本：%s\n' "$installed" >&2
    exit 2
  fi
fi

source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core
compile_native_test_harness app-updates \
  "$replica_root/Sources/BlinkClip/UI/ReplicaBrand.swift" \
  "$replica_root/Sources/BlinkClip/UI/BlinkClipAboutWindowController.swift" \
  "$replica_root/Tests/Native/AppUpdateHarness.swift"
test_app="$(dirname "$(dirname "$(dirname "$test_harness")")")"
plutil -insert BlinkClipSourceVersion -string '1.0.5-dev.2' "$test_app/Contents/Info.plist" >/dev/null
plutil -insert CFBundleShortVersionString -string '1.0.5' "$test_app/Contents/Info.plist" >/dev/null
if (( preview )); then
  printf 'PREVIEW_APP=%s\n' "$test_app"
fi

harness_args=()
live_status=''
live_version=''
live_installed=''
appcast_file="$test_root/appcast.xml"

if (( live )); then
  if (( offline )); then
    live_status="skipped: --offline 要求跳过线上探针（feed 与 --installed 都未使用）"
  elif ! fetch_feed_version "$live_feed" "$appcast_file"; then
    live_status="skipped: 读不到线上 appcast（$live_feed）：$(cat "$test_root/fetch-failure" 2>/dev/null || printf '未知原因')"
  elif ! live_version="$(appcast_versions "$appcast_file" | appcast_newest_version)"; then
    printf 'FAIL: %s 有应答，但没有任何可解析的 <sparkle:version>\n' "$live_feed" >&2
    printf '{"passed":false,"live_appcast":"failed","reason":"the appcast answered without a stable sparkle:version"}\n'
    exit 1
  else
    short_version="$(grep -o '<sparkle:shortVersionString>[^<]*' "$appcast_file" 2>/dev/null \
      | head -1 | sed -e 's|.*>||' || true)"
    note "线上 appcast 最新版：$live_version${short_version:+（shortVersionString: $short_version）}"
    live_installed="$installed"
    if [[ -z "$live_installed" ]]; then
      if live_installed="$(previous_version "$live_version")"; then
        note "未指定 --installed：用线上版本往回一个 patch 的 $live_installed 做「可更新」断言"
      else
        live_installed=''
        note "线上版本 $live_version 没有可减的 patch 分量：本次只断言「已是最新」，需要覆盖旧版本请传 --installed <版本>"
      fi
    fi
  fi
fi

if [[ -n "$render_dir" ]]; then
  mkdir -p "$render_dir"
  harness_args+=(--render "$render_dir")
fi
if [[ -n "$live_version" ]]; then
  harness_args+=(--live --live-version "$live_version" --live-feed "$live_feed")
  if [[ -n "$live_installed" ]]; then
    harness_args+=(--live-installed "$live_installed")
  fi
fi
if (( preview )); then
  harness_args+=(--preview)
fi

harness_code=0
# bash 3.2 在 set -u 下对空数组展开报 unbound variable，这里显式判空。
if [[ ${#harness_args[@]} -gt 0 ]]; then
  "$test_harness" "${harness_args[@]}" || harness_code=$?
else
  "$test_harness" || harness_code=$?
fi

if [[ -n "$live_status" ]]; then
  printf '%s\n' "$live_status"
  printf '{"live_appcast":"skipped","reason":"%s"}\n' "$(json_escape "${live_status#skipped: }")"
fi
if [[ -n "$render_dir" ]]; then
  printf '关于窗口截图：%s\n' "$render_dir"
fi
exit "$harness_code"
