--[[
Taken from http://lua-users.org/wiki/StringTrim (#12)
]]

return function (s)
    local from = s:match"^%s*()"
    return from > #s and "" or s:match(".*%S", from)
end