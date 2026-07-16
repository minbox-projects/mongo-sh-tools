#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mongo-sh-tools-test.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

make_test_app() {
  local app_dir="$TMP_DIR/app"
  mkdir -p "$app_dir" "$TMP_DIR/home/.mongo_sh_tools"
  cp "$ROOT_DIR/mongo_sh_tools" "$app_dir/mongo_sh_tools"
  chmod +x "$app_dir/mongo_sh_tools"

  cat > "$app_dir/mongosh" <<'EOF'
#!/bin/bash
script=""
while (( $# > 0 )); do
  case "$1" in
    --eval) script="$2"; shift 2 ;;
    --file) script=$(<"$2"); shift 2 ;;
    *) shift ;;
  esac
done

case "$script" in
  *getCollectionNames*) printf 'items\n' ;;
  *'const sample ='*) printf 'name|string\n' ;;
  *'__TOTAL__:'*) printf '{"name":"alpha"}\n__TOTAL__:1\n' ;;
  *deleteOne*'print(EJSON.stringify(result));'*) printf '{"acknowledged":true,"deletedCount":1}\n' ;;
  *createCollection*'print(EJSON.stringify(result));'*) printf '{"ok":1}\n' ;;
  *estimatedDocumentCount*) printf '1\n' ;;
  *countDocuments*) printf '1\n' ;;
  *'function getInsertedCount('*'__IMPORT_RESULT__:'*) printf '__IMPORT_RESULT__:{"total":1,"inserted":1,"failed":0,"errors":[]}\n' ;;
  *'__IMPORT_RESULT__:'*) printf '__IMPORT_RESULT__:{"total":1,"inserted":null,"failed":null,"errors":[]}\n' ;;
  *'__IMPORT_COUNT__:'*) printf '__IMPORT_COUNT__:1\n{"name":"alpha"}\n' ;;
  *listDatabases*) printf 'test|1\n' ;;
  *'cursor.forEach'*)
    printf '{"_id":{"$oid":"0123456789abcdef01234567"}}\n'
    printf '__PROGRESS__:1\n' >&2
    ;;
esac
EOF
  chmod +x "$app_dir/mongosh"

  cat > "$TMP_DIR/home/.mongo_sh_tools/config.json" <<'EOF'
{
  "host": "localhost",
  "port": 27017,
  "database": "test",
  "ssl": false,
  "defaultLimit": 20,
  "exportLimit": 10000
}
EOF

  printf '%s\n' "$app_dir/mongo_sh_tools"
}

test_user_can_edit_collection_selection_with_readline() {
  command -v script >/dev/null 2>&1 || fail "script is required for the terminal test"

  local app output
  app=$(make_test_app)
  set +o pipefail
  output=$({ sleep 1; printf '2\033[D1\033[C\177\n'; sleep 0.5; printf 'x\n'; sleep 0.5; printf '1\nx\n'; } |
    HOME="$TMP_DIR/home" script -q /dev/null bash "$app" 2>&1)
  set -o pipefail

  [[ "$output" == *"已选择: items"* ]] || fail "terminal editing did not select collection 1"
  [[ "$output" != *"无效输入，请重新选择"* ]] || fail "terminal editing was not enabled"
  [[ "$output" == *"再见"* ]] || fail "script did not return to the main menu"
}

test_user_can_run_a_query() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nq\n1\n\n\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *'"name":"alpha"'* ]] || fail "query result was not displayed"
  [[ "$output" == *"匹配总数: 1 | 本次显示: 20 条"* ]] || fail "query total was not displayed"
}

test_user_can_return_to_previous_query_step() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nq\n1\n5\nb\n3\n\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"本次显示: 3 条"* ]] || fail "returning to the query limit did not use the modified value"
  [[ "$output" != *"本次显示: 5 条"* ]] || fail "query used the value from before returning"
}

test_user_can_return_through_all_query_steps() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nq\n1\n5\nb\n3\nb\nb\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" != *"执行: db.items.find"* ]] || fail "returning from the first query step did not cancel the workflow"
  [[ "$output" == *"再见"* ]] || fail "query workflow did not return to the menu after repeated back"
}

test_user_can_return_in_projection_and_sort_queries() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nq\n2\n5\nb\n6\n\nb\n\n1\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)
  [[ "$output" == *"本次显示: 6 条"* ]] || fail "projection query did not retain the modified limit after returning"

  app=$(make_test_app)
  output=$(printf '1\nq\n5\n5\nb\n6\n\nb\n\n1\n1\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)
  [[ "$output" == *'sort({"name":1}).limit(6)'* ]] || fail "custom sort query did not return to and modify the sort step"
}

test_user_can_return_in_pagination_setup() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nq\n3\n5\nb\n6\n\nq\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"第 1/1 页 (共 1 条，每页 6 条)"* ]] || fail "pagination did not use the modified page size after returning"
}

test_user_keeps_filters_when_returning_from_projection() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nq\n2\n\nname=alpha\ndone\nb\ndone\n\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *'执行: db.items.find({"name":"alpha"}, {})'* ]] || fail "returning from projection discarded the existing filter"
}

test_user_can_export_json_lines() {
  local app output exported_file
  app=$(make_test_app)
  output=$(printf '1\nd\n3\n\n\n\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)
  exported_file=$(find "$(dirname "$app")" -maxdepth 1 -name 'export_items_*.json' -type f | head -1)

  [[ "$output" == *"已导出:"* ]] || fail "export did not report completion"
  [[ "$output" == *"正在导出 JSON: 1 / 1"* ]] || fail "export progress was not displayed"
  [[ -n "$exported_file" ]] || fail "export file was not created"
  [[ "$(wc -l < "$exported_file")" -eq 1 ]] || fail "export file did not contain one JSON Lines document"
}

test_user_can_delete_a_document() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nd\n1\n\n1\ny\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"正在删除..."* ]] || fail "delete did not start"
  [[ "$output" == *'"deletedCount":1'* ]] || fail "delete result was not displayed"
}

test_user_can_cancel_a_delete() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nd\n1\n\n1\nn\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"已取消"* ]] || fail "delete cancellation was not displayed"
  [[ "$output" != *"正在删除..."* ]] || fail "cancelled delete was executed"
}

test_user_can_modify_delete_mode_after_returning() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nd\n1\n\n1\nb\n2\ny\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"即将执行: db.items.deleteMany({})"* ]] || fail "returning from delete confirmation did not restore mode selection"
}

test_user_can_create_a_collection() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nc\n5\ncreated\n\nb\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"创建成功，已自动切换到: created"* ]] || fail "collection creation success was not displayed"
  [[ "$output" != *"创建失败"* ]] || fail "successful collection creation was reported as failed"
}

test_collection_switch_returns_to_main_menu() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\nc\n1\n1\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"再见"* ]] || fail "collection switch did not return to the main menu"
}

test_database_switch_returns_to_main_menu() {
  local app output
  app=$(make_test_app)
  output=$(printf '1\ne\n1\n1\n1\nx\n' | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"再见"* ]] || fail "database switch did not return to the main menu"
}

test_user_can_import_json_lines() {
  local app output input_file
  app=$(make_test_app)
  input_file="$TMP_DIR/import.json"
  printf '{"name":"alpha"}\n' > "$input_file"
  output=$(printf '1\nd\n4\n%s\ny\nb\nx\n' "$input_file" | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *'导入结果: {"total":1,"inserted":1,"failed":0,"errors":[]}'* ]] || fail "import result was not displayed"
}

test_user_can_cancel_an_import() {
  local app output input_file
  app=$(make_test_app)
  input_file="$TMP_DIR/import.json"
  printf '{"name":"alpha"}\n' > "$input_file"
  output=$(printf '1\nd\n4\n%s\nn\nb\nx\n' "$input_file" | HOME="$TMP_DIR/home" bash "$app" 2>&1)

  [[ "$output" == *"已取消"* ]] || fail "import cancellation was not displayed"
  [[ "$output" != *"正在导入"* ]] || fail "cancelled import was executed"
}

test_user_can_edit_collection_selection_with_readline
test_user_can_run_a_query
test_user_can_return_to_previous_query_step
test_user_can_return_through_all_query_steps
test_user_can_return_in_projection_and_sort_queries
test_user_can_return_in_pagination_setup
test_user_keeps_filters_when_returning_from_projection
test_user_can_export_json_lines
test_user_can_delete_a_document
test_user_can_cancel_a_delete
test_user_can_modify_delete_mode_after_returning
test_user_can_create_a_collection
test_collection_switch_returns_to_main_menu
test_database_switch_returns_to_main_menu
test_user_can_import_json_lines
test_user_can_cancel_an_import
echo "PASS: mongo_sh_tools"
