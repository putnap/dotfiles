on run argv
    set marker to item 1 of argv
    tell application "Ghostty"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with term in terminals of t
                    if name of term is marker then
                        select tab t
                        focus term
                        activate window w
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "missing"
end run
