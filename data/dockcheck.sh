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
NoUpdates=()
GotErrors=()
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
  local GotUpdates NoUpdates GotErrors
  ImageId=$(docker inspect "$i" --format='{{.Image}}')
  RepoUrl=$(docker inspect "$i" --format='{{.Config.Image}}')
  LocalHash=$(docker image inspect "$ImageId" --format '{{.RepoDigests}}')
  if RegHash=$($t_out "$regbin" -v error image digest --list "$RepoUrl" 2>&1); then
    if [[ "$LocalHash" != *"$RegHash"* ]]; then
      if [[ -n "${DaysOld:-}" ]] && ! datecheck; then
        printf "%s\n" "NoUpdates $i"
      else
        printf "%s\n" "GotUpdates $i"
      fi
    else
      printf "%s\n" "NoUpdates $i"
    fi
  else
    printf "%s\n" "GotErrors $i"
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
NoUpdates=()
GotErrors=()
while read -r line; do
  Got=${line%% *}  # Extracts the first word (GotUpdates, NoUpdates, GotErrors)
  item=${line#* }
  case "$Got" in
    GotUpdates) GotUpdates+=("$item") ;;
    NoUpdates) NoUpdates+=("$item") ;;
    GotErrors) GotErrors+=("$item") ;;
    *) ;;
  esac
done < <( \
  docker ps $Stopped --filter "name=$SearchName" --format '{{.Names}}' | \
  xargs $XargsAsync -I {} bash -c 'check_image "{}"' \
)
# Sort arrays alphabetically
IFS=$'\n'
GotUpdates=($(sort <<<"${GotUpdates[*]:-}"))
NoUpdates=($(sort <<<"${NoUpdates[*]:-}"))
GotErrors=($(sort <<<"${GotErrors[*]:-}"))
unset IFS
# Output stacks with containers categorized as outdated, up-to-date, and errored in JSON
json_output="{\"stacks\": ["
declare -A stack_outdated
declare -A stack_uptodate
declare -A stack_errored
# Process containers with updates
for container in "${GotUpdates[@]}"; do
  stack=$($jqbin -r '."com.docker.compose.project"' <<< "$(docker inspect "$container" --format '{{json .Config.Labels}}')")
  [[ "$stack" == "null" ]] && stack="no_stack"
  # Check if key exists and append, otherwise initialize
  if [[ -n "${stack_outdated[$stack]+x}" ]]; then
    stack_outdated[$stack]="${stack_outdated[$stack]}, \"$container\""
  else
    stack_outdated[$stack]="\"$container\""
  fi
done
# Process containers with no updates
for container in "${NoUpdates[@]}"; do
  stack=$($jqbin -r '."com.docker.compose.project"' <<< "$(docker inspect "$container" --format '{{json .Config.Labels}}')")
  [[ "$stack" == "null" ]] && stack="no_stack"
  # Check if key exists and append, otherwise initialize
  if [[ -n "${stack_uptodate[$stack]+x}" ]]; then
    stack_uptodate[$stack]="${stack_uptodate[$stack]}, \"$container\""
  else
    stack_uptodate[$stack]="\"$container\""
  fi
done
# Process containers with errors
for container in "${GotErrors[@]}"; do
  stack=$($jqbin -r '."com.docker.compose.project"' <<< "$(docker inspect "$container" --format '{{json .Config.Labels}}')")
  [[ "$stack" == "null" ]] && stack="no_stack"
  # Check if key exists and append, otherwise initialize
  if [[ -n "${stack_errored[$stack]+x}" ]]; then
    stack_errored[$stack]="${stack_errored[$stack]}, \"$container\""
  else
    stack_errored[$stack]="\"$container\""
  fi
done
# Build JSON for stacks as an array of objects
first=true
declare -A processed
for stack in "${!stack_outdated[@]}" "${!stack_uptodate[@]}" "${!stack_errored[@]}"; do
  # Avoid duplicates by checking if already processed
  if [[ -z "${processed[$stack]+x}" ]]; then
    processed[$stack]=true
    if [[ "$first" == true ]]; then
      first=false
    else
      json_output="$json_output,"
    fi
    json_output="$json_output {"
    json_output="$json_output \"name\": \"$stack\","
    json_output="$json_output \"outdated\": [${stack_outdated[$stack]:-\"\"}],"
    json_output="$json_output \"up_to_date\": [${stack_uptodate[$stack]:-\"\"}],"
    json_output="$json_output \"errored\": [${stack_errored[$stack]:-\"\"}]"
    json_output="$json_output }"
  fi
done
json_output="$json_output ]}"
# If no stacks were found, output empty stacks array
if [[ "$first" == true ]]; then
  json_output="{\"stacks\": []}"
fi
echo "$json_output"
exit 0