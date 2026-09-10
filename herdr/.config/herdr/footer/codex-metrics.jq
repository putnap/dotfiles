# Matches Codex 0.153.4 TokenUsage::percent_of_context_window_remaining.
def context_used:
  .info.model_context_window as $window | .info.last_token_usage.total_tokens as $used |
  if ($window | type) != "number" or ($used | type) != "number" then null
  elif $window <= 12000 then 100
  else 100 - ((([($window - 12000 - ([$used - 12000, 0] | max)), 0] | max) / ($window - 12000) * 100) | round | [., 0] | max | [.,100] | min) end;
def quota($minutes):
  [.rate_limits.primary, .rate_limits.secondary] | map(select(.window_minutes == $minutes)) | .[0].used_percent;
{model, effort, cwd, measured_at, approval, sandbox, context:context_used, five_hour:quota(300), weekly:quota(10080)}
