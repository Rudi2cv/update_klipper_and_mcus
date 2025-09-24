#!/bin/bash

rollback_repo=""
rollback_version=""
DO_ROLLBACK=false

#Define function to get previous install version
function get_rollback {
  count=0
  rollback_file="$1"
  if [[ -f "$rollback_file" ]]; then
    while IFS= read -r value || [[ -n "$value" ]]; do
      [ $count -eq 0 ] && rollback_version="$value"
      [ $count -eq 1 ] && rollback_repo="$value" && break
      count=$(($count + 1))
    done <"$rollback_file"
  fi
  return 0
}

function show_rollback {

  get_rollback $ukam_config/config/.previous_version

  echo "Local version $k_local_version"
  if [[ $rollback_version != "" &&
    $rollback_version != $k_local_version ]]; then
    if [[ $rollback_repo == "" ||
      $rollback_repo == "$k_repo $k_fullbranch" ]]; then
      echo "Known rollback version $rollback_version"
      DO_ROLLBACK=true
    else
      echo "Version $rollback_version belongs to another repo/branch"
      echo -e "${GREEN}$rollback_repo${DEFAULT}"
    fi
  fi
  if ! $DO_ROLLBACK; then
    echo "No rollback available"
  fi
}

function do_rollback() {
  QUIET=false
  TOUPDATE=false
  if [[ "$k_local_version" == *"dirty"* ]]; then
    echo -e "${RED}WARNING : Rollback a dirty repo will erase" \
      "untracked files.${DEFAULT}"
  fi
  $DO_ROLLBACK && ! rollback $rollback_version  &&  DO_ROLLBACK=false
  while ! $DO_ROLLBACK; do
    while [[ ! "$rollback_type" =~ ^[1-3]$ ]]; do
      echo -e "${MAGENTA}Select rollback type:${DEFAULT}"
      echo -e "${CYAN}  1)${DEFAULT} Rollback by number of commits"
      echo -e "${CYAN}  2)${DEFAULT} Rollback by version tag"
      echo -e "${CYAN}  3)${DEFAULT} Rollback by date"
      echo -e "${CYAN}  A)${DEFAULT} Abort rollback"
      read -p "${MAGENTA}Your choice ? ${DEFAULT}" rollback_type
      if [[ "${rollback_type^^}" == "A" ]]; then
        echo "Rollback aborted"
        return 0
      fi
    done

    case $rollback_type in
      1)
          nb_rollback=""
          while [[ ! "$nb_rollback" =~ ^[0-9]+$ ]]; do
            read -p "${MAGENTA}Number of commits to rollback, \
${DEFAULT}[B]${MAGENTA} Back ? ${DEFAULT}" nb_rollback
            if [[ "${nb_rollback^^}" == "B" ]]; then
              rollback_type=""
              break
            fi
          done
          [[ "${rollback_type}" == "" ]] && continue
          rollback_version=$(git -C ~/klipper describe HEAD~$nb_rollback \
            --tags --always --long)
        ;;
      2)
          commit_number=""
          while [[ ! "$commit_number" =~ ^[0-9]+$ ]]; do
            read -p "${MAGENTA}Version tag to rollback (${k_tag}-${GREEN}??? \
${MAGENTA}, only the last digits), ${DEFAULT}[B]${MAGENTA} Back ? ${DEFAULT}" commit_number
            if [[ "${commit_number^^}" == "B" ]]; then
              rollback_type=""
              break
            fi
          done
          [[ "${rollback_type}" == "" ]] && continue

          rollback_version=$(git -C ~/klipper rev-list $k_fullbranch $k_tag..HEAD | \
            xargs git -C ~/klipper describe --tags --always | \
            grep "$k_tag-$commit_number-" | head -n 1)
          if ! git -C ~/klipper rev-parse "$rollback_version" >/dev/null 2>&1; then
            echo -e "${RED}Version $k_tag-$commit_number not found${DEFAULT}"
            rollback_version=""
          fi
          
        ;;
      3)
          rollback_hash=""
          rollback_date=""
          while [[ ! "$rollback_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; do
            read -p "${MAGENTA}Rollback before date (YYYY-MM-DD), ${DEFAULT}[B] \
${MAGENTA} Back ? ${DEFAULT}" rollback_date
            if [[ "${rollback_date^^}" == "B" ]]; then
              rollback_type=""
              break
            fi
          done
          [[ "${rollback_type}" == "" ]] && continue

          rollback_hash=$(git -C ~/klipper rev-list -1 --before="$rollback_date" HEAD)
          if [[ "$rollback_hash" == "" ]]; then
            echo -e "${RED}No commit found before $rollback_date${DEFAULT}"
            return 0
          else
            rollback_version=$(git -C ~/klipper describe $rollback_hash --tags --always --long)
          fi
        ;;
    esac
    
    [[ $rollback_version != "" ]] && rollback $rollback_version && 
      DO_ROLLBACK=true
  done
  if $DO_ROLLBACK; then
    echo -e "\n     ${GREEN}Rollback done, you need to restart the\n     " \
      "klipper service to apply changes${DEFAULT}"
    TOUPDATE=true
  else
    echo "Rollback aborted"
    return 0
  fi
}

function rollback() {
  rb_version="$1"
  [[ "$rb_version" == "" ]] && 
    echo -e "${RED}No version specified for rollback${DEFAULT}" && return 1
  if git -C ~/klipper rev-parse "$rb_version" >/dev/null 2>&1; then
    nb_commits=$(git -C ~/klipper rev-list $rb_version..HEAD --count)
    date_commit=$(git -C ~/klipper show -s --format=%ci $rb_version)
    prefix="Rollback ${GREEN}$nb_commits${MAGENTA} commits to" && [[ $nb_commits -eq 0 ]] && prefix="Install"
    prompt "$prefix version ${GREEN}$rb_version${MAGENTA} ($date_commit) ?" || return 1
    git -C ~/klipper reset --hard $rb_version
    k_local_version=$rb_version
    return 0
  fi
  echo -e "${RED}Version $rb_version not found${DEFAULT}"
  return 1
}

function store_rollback_version() {
  echo -e "$k_local_version\n$k_repo $k_fullbranch" \
    >$ukam_config/config/.previous_version
}
