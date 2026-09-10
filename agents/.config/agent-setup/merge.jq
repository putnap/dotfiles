def merge_owned($wanted; $previous; $protected):
  reduce (($previous // {}) | keys[]) as $key (. ;
    if ($wanted | has($key) | not) and has($key) and .[$key] == $previous[$key]
    then del(.[$key]) else . end) |
  reduce ($wanted | keys[]) as $key (. ;
    if ($protected | index($key)) != null then error("protected setting: " + $key)
    elif ($wanted[$key] | type) == "object" then
      .[$key] = ((.[$key] // {}) | merge_owned($wanted[$key]; $previous[$key]; $protected))
    else .[$key] = $wanted[$key] end);
def remove_peon:
  (if (.hooks | type) == "object" then
    .hooks |= with_entries(.value |= map(
      .hooks |= map(select(((.command // "") | contains("peon-ping")) | not)) |
      select(.hooks | length > 0)) | select(.value | length > 0)) else . end) |
  if ((.notify // "" | tostring) | contains("peon-ping")) then del(.notify) else . end;
($live[0] | merge_owned($wanted[0]; $previous[0][$name]; $protected) |
  if $name == "peon.toml" then . else remove_peon end) as $merged |
if any($protected[]; . as $key | $merged[$key] != $live[0][$key]) then error("protected field changed")
else $merged end
