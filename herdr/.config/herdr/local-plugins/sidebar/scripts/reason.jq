# Why an agent waits, for its inbox row: the last text or tool call of its transcript's last
# turn, as one short line. Reads a Claude transcript's lines raw (jq -nR), since the line still
# being written doesn't parse and is passed over.
def last_line: split("\n") | map(select(test("[[:alnum:]]"))) | last // "";
def asked: if .name == "AskUserQuestion" then .input.questions[0].question // ""
  else "\(.name): \(.input.command // .input.file_path // .input.url // .input.description // "" | split("\n")[0])" end;
[inputs | fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text" or .type == "tool_use")]
| last // empty | (if .type == "text" then .text | last_line else asked end)
| gsub("[*`]"; "") | sub("^\\s*([-•]\\s+)?"; "") | gsub("\\s+"; " ") | .[0:80] | sub("\\s+$"; "")
