# Reduce only structured session metadata. Messages and tool output are discarded.
reduce inputs as $line ($previous[0];
  ($line | fromjson? // null) as $row |
  if $row.type == "turn_context" then
    .model = $row.payload.model | .effort = $row.payload.effort | .cwd = $row.payload.cwd |
    .approval = $row.payload.approval_policy | .sandbox = $row.payload.sandbox_policy.type
  elif $row.type == "event_msg" and $row.payload.type == "thread_settings_applied" then
    $row.payload.thread_settings as $settings |
    .model = $settings.model | .effort = $settings.reasoning_effort | .cwd = $settings.cwd |
    .approval = $settings.approval_policy |
    # A built-in profile names the sandbox; a custom one leaves the last turn's value standing.
    (if $settings.active_permission_profile.id == ":danger-full-access" then .sandbox = "danger-full-access"
     elif $settings.active_permission_profile.id == ":workspace" then .sandbox = "workspace-write"
     else . end)
  elif $row.type == "event_msg" and $row.payload.type == "token_count" then
    if $row.payload.info != null then .info = $row.payload.info else . end |
    if $row.payload.rate_limits != null and (($row.payload.rate_limits.limit_id // "codex") == "codex")
    then .rate_limits = $row.payload.rate_limits else . end |
    .measured_at = $row.timestamp
  else . end)
