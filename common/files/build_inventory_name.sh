#!/usr/bin/env bash

normalize_environment_name() {
  local environment_name="$1"
  local environment_transform='s/dev/development_dev/;s/test/test_test/;s/training/test_training/;s/stage/preproduction_stage/;s/-preprod$/_preproduction_preprod/;s/-prod/_production_prod/;s/-/_/g'

  echo "$environment_name" | sed "$environment_transform"
}

build_inventory_name() {
  local environment_name="$1"
  local suffix="${2:-}"
  local prefix="${3:-environment_name_}"

  printf '%s%s%s\n' "$prefix" "$(normalize_environment_name "$environment_name")" "$suffix"
}