#!/usr/bin/env bash
VERSION="v0.6.4"
Github="https://github.com/mag37/dockcheck"
RawUrl="https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh"

set -uo pipefail
shopt -s nullglob
shopt -s failglob

# Variables for self updating
ScriptArgs=( "$@" )
ScriptPath="$(readlink -f "$0")"
ScriptWorkDir="$(dirname "$ScriptPath")"

# User customizable defaults
if [[ -s "${HOME}/.config/dockcheck.config" ]]; then
  source "${HOME}/.config/dockcheck.config"
elif [[ -s "${ScriptWorkDir}/dockcheck.config" ]]; then
  source "${ScriptWorkDir}/dockcheck.config"
fi

# Initialise variables
Timeout=${Timeout:=10}
MaxAsync=${MaxAsync:=1}
AutoMode=${AutoMode:=false}
DontUpdate=${DontUpdate:=false}
DRunUp=${DRunUp:=false}
Stopped=${Stopped:=""}
Exclude=${Exclude:-}
DaysOld=${DaysOld:-}
Excludes=()
GotUpdates=()
regbin=""
jqbin=""

while getopts "aynd:e:rs:t:x:" options; do
  case "${options}" in
    a|y) AutoMode=true ;;
    d)   DaysOld=${OPTARG} ;;
    e)   Exclude=${OPTARG} ;;
    n)   DontUpdate=true; AutoMode=true;;
    r)   DRunUp=true ;;
    s)   Stopped="-a" ;;
    t)   Timeout="${OPTARG}" ;;
    x)   MaxAsync=${OPTARG} ;;
    *)   exit 2 ;;
  esac
done
shift "$((OPTIND-1))"

# Set $1 to a variable for name filtering later
SearchName="${1:-}"

# Setting up options
if [[ "$DontUpdate" == true ]]; then AutoMode=true; fi
if [[ -n "$Exclude" ]]; then
  IFS=',' read -ra Excludes <<< "$Exclude"
  unset IFS
fi
if [[ -n "$DaysOld" ]]; then
  if ! [[ $DaysOld =~ ^[0-9]+$ ]]; then
    echo "{\"error\": \"Days -d argument given ($DaysOld) is not a number.\"}"
    exit 2
  fi
fi

datecheck() {
  ImageDate=$("$regbin" -v error image inspect "$RepoUrl" --format='{{.Created}}' | cut -d" " -f1)
  ImageEpoch=$(date -d "$ImageDate" +%s 2>/dev/null) || ImageEpoch=$(date -f "%Y-%m-%d" -j "$ImageDate" +%s)
  ImageAge=$(( ( $(date +%s) - ImageEpoch )/86400 ))
  if [[ "$ImageAge" -gt "$DaysOld" ]]; then
    return 0
  else
    return 1
  fi
}

# Static binary downloader for dependencies
binary_downloader() {
  BinaryName="$1"
  BinaryUrl="$2"
  case "$(uname -m)" in
    x86_64|amd64) architecture="amd64" ;;
    arm64|aarch64) architecture="arm64";;
    *) echo "{\"error\": \"Architecture not supported.\"}"; exit 1;;
  esac
  GetUrl="${BinaryUrl/TEMP/"$architecture"}"
  if command -v curl &>/dev/null; then curl -L "$GetUrl" > "$ScriptWorkDir/$BinaryName";
  elif command -v wget &>/dev/null; then wget "$GetUrl" -O "$ScriptWorkDir/$BinaryName";
  else echo "{\"error\": \"curl/wget not available - get $BinaryName manually.\"}"; exit 1;
  fi
  [[ -f "$ScriptWorkDir/$BinaryName" ]] && chmod +x "$ScriptWorkDir/$BinaryName"
}

# Dependency check + installer function
dependency_check() {
  AppName="$1"
  AppVar="$2"
  AppUrl="$3"
  if command -v "$AppName" &>/dev/null; then export "$AppVar"="$AppName";
  elif [[ -f "$ScriptWorkDir/$AppName" ]]; then export "$AppVar"="$ScriptWorkDir/$AppName";
  else
    binary_downloader "$AppName" "$AppUrl"
    [[ -f "$ScriptWorkDir/$AppName" ]] && export "$AppVar"="$ScriptWorkDir/$1" || { echo "{\"error\": \"Failed to download $AppName.\"}"; exit 1; }
  fi
  # Final check if binary is correct
  [[ "$1" == "jq" ]] && VerFlag="--version"
  [[ "$1" == "regctl" ]] && VerFlag="version"
  ${!AppVar} "$VerFlag" &> /dev/null || { echo "{\"error\": \"$AppName is not working.\"}"; exit 1; }
}

dependency_check "regctl" "regbin" "https://github.com/regclient/regclient/releases/latest/download/regctl-linux-TEMP"
dependency_check "jq" "jqbin" "https://github.com/jqlang/jq/releases/latest/download/jq-linux-TEMP"

# Check docker compose binary
docker info &>/dev/null || { echo "{\"error\": \"No permissions to the docker socket.\"}"; exit 1; }
if docker compose version &>/dev/null; then DockerBin="docker compose" ;
elif docker-compose -v &>/dev/null; then DockerBin="docker-compose" ;
else
  echo "{\"error\": \"No docker compose binary available.\"}"
  exit 1
fi

# Testing and setting timeout binary
t_out=$(command -v timeout || echo "")
if [[ $t_out ]]; then
  t_out=$(realpath "$t_out" 2>/dev/null || readlink -f "$t_out")
  if [[ $t_out =~ "busybox" ]]; then
    t_out="timeout ${Timeout}"
  else t_out="timeout --foreground ${Timeout}"
  fi
else t_out=""
fi

check_image() {
  i="$1"
  local Excludes=($Excludes_string)
  for e in "${Excludes[@]}"; do
    if [[ "$i" == "$e" ]]; then
      return
    fi
  done

  # Skipping non-compose containers unless option is set
  ContLabels=$(docker inspect "$i" --format '{{json .Config.Labels}}')
  ContPath=$($jqbin -r '."com.docker.compose.project.working_dir"' <<< "$ContLabels")
  [[ "$ContPath" == "null" ]] && ContPath=""
  if [[ -z "$ContPath" ]] && [[ "$DRunUp" == false ]]; then
    return
  fi

  local GotUpdates
  ImageId=$(docker inspect "$i" --format='{{.Image}}')
  RepoUrl=$(docker inspect "$i" --format='{{.Config.Image}}')
  LocalHash=$(docker image inspect "$ImageId" --format '{{.RepoDigests}}')

  if RegHash=$($t_out "$regbin" -v error image digest --list "$RepoUrl" 2>&1); then
    if [[ "$LocalHash" != *"$RegHash"* ]]; then
      if [[ -n "${DaysOld:-}" ]] && ! datecheck; then
        return
      else
        printf "%s\n" "GotUpdates $i"
      fi
    fi
  fi
}

# Make required functions and variables available to subprocesses
export -f check_image datecheck
export Excludes_string="${Excludes[*]:-}"
export t_out regbin RepoUrl DaysOld DRunUp jqbin

# Check for POSIX xargs with -P option, fallback without async
if (echo "test" | xargs -P 2 >/dev/null 2>&1) && [[ "$MaxAsync" != 0 ]]; then
  XargsAsync="-P $MaxAsync"
else
  XargsAsync=""
fi

# Asynchronously check the image-hash of every running container VS the registry
GotUpdates=()
while read -r line; do
  Got=${line%% *}  # Extracts the first word (GotUpdates)
  item=${line#* }
  case "$Got" in
    GotUpdates) GotUpdates+=("$item") ;;
    *) ;;
  esac
done < <( \
  docker ps $Stopped --filter "name=$SearchName" --format '{{.Names}}' | \
  xargs $XargsAsync -I {} bash -c 'check_image "{}"' \
)

# Sort arrays alphabetically
IFS=$'\n'
GotUpdates=($(sort <<<"${GotUpdates[*]:-}"))
unset IFS

# Output only containers with updates as JSON
if [[ -n "${GotUpdates[*]:-}" ]]; then
  json_output="{\"containers_with_updates\": ["
  first=true
  for update in "${GotUpdates[@]}"; do
    if [[ "$first" == true ]]; then
      json_output="$json_output\"$update\""
      first=false
    else
      json_output="$json_output, \"$update\""
    fi
  done
  json_output="$json_output]}"
  echo "$json_output"
else
  echo "{\"containers_with_updates\": []}"
fi

exit 0