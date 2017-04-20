--[[
This code is heavily based on the cmd module from the Python standard library.
The differences are as follows:
* It is in Lua.
* Readline support has been temporarily removed.
* The character match was replaced with a regular expression.
* Instead of function names, commands and help topics are stored in tables.
* No inheritance. Each interpreter is simply a table, with no special behavior.
* There are probably a bunch of off-by-one errors.
]]

local trim = require'trim'

local defaults = {
    prompt = '(Cmd) ',
    identmatch = '^[%a%d_]*',
    ruler = '=',
    lastcmd = '',
    doc_leader = '',
    doc_header = 'Documented commands (type help <topic>):',
    misc_header = 'Miscellaneous help topics:',
    undoc_header = 'Undocumented commands:',
    nohelp = '*** No help on %s',

    completekey = 'tab',
    stdin = io.stdin,
    stdout = io.stdout,

    cmdloop = function (self, intro)
        self:preloop()
        -- Interested in getting readline support in, but not totally sure what thay would look like.
        -- Like, could I have a dedicated readline instance attached to the cmd table?
        local status, err = pcall(
            function ()
                self.intro = self.intro or intro
                if self.intro then
                    self.stdout:write(tostring(self.intro), '\n')
                end
                do
                    local stop = nil
                    while not stop do
                        local line
                        if self.cmdqueue[1] then
                            line = table.remove(self.cmdqueue, 1)
                        else
                            self.stdout:write(self.prompt)
                            self.stdout:flush()
                            line = self.stdin:read("*line") or 'EOF'
                        end
                        line = self:precmd(line)
                        stop = self:onecmd(line)
                        stop = self:postcmd(stop, line)
                    end
                end
                self:postloop()
            end)
        assert(status, err)
    end,

    precmd = function (self, line)
        return line
    end,
    postcmd = function (self, stop, line)
        return stop
    end,
    preloop = function (self) end,
    postloop = function (self) end,

    parseline = function (self, line)
        line = trim(line)
        if #line == 0 then
            return nil, nil, line
        elseif line:sub(1, 1) == '?' then
            line = 'help ' .. line:sub(2)
        elseif line:sub(1, 1) == '!' then
            if self.action.shell then
                line = 'shell ' .. line:sub(2)
            else
                return nil, nil, line
            end
        end
        local _, id_end = line:find(self.identmatch)
        return line:sub(1, id_end), trim(line:sub(id_end + 1)), line
    end,
    onecmd = function (self, line)
        local cmd, arg
        cmd, arg, line = self:parseline(line)
        if not line then
            return self:emptyline()
        end
        if not cmd then
            return self:default(line)
        end
        self.lastcmd = line
        if line == 'EOF' then
            self.lastcmd = ''
        end
        if cmd == '' then
            return self:default(line)
        else
            local func = self.action[cmd]
            if func then
                return func(self, arg)
            else
                return self:default(line)
            end
        end
    end,
    emptyline = function (self)
        if self.lastcmd ~= '' then
            return self:onecmd(self.lastcmd)
        end
    end,
    default = function (self, line)
        self.stdout:write('*** Unknown syntax: ', line, '\n')
    end,
    print_topics = function (self, header, cmds, maxcol)
        if cmds[1] then
            self.stdout:write(header, '\n')
            if self.ruler and self.ruler ~= '' then
                self.stdout:write(self.ruler:rep(#header), '\n')
            end
            self:columnize(cmds, maxcol - 1) -- Not sure I should do the subtraction
            self.stdout:write'\n'
        end
    end,
    columnize = function (self, list, displaywidth)
        displaywidth = displaywidth or 80
        if #list == 0 then
            self.stdout:write'<empty>\n'
            return
        end
        local nonstrings = {}
        for i, v in ipairs(list) do
            if type(v) ~= 'string' then
                table.insert(nonstrings, i)
            end
        end
        if #nonstrings ~= 0 then
            error('list[i] not a string for i in ' .. table.concat(nonstrings, ', '))
        end
        if #list == 1 then
            self.stdout:write(list[1], '\n')
            return
        end
        local colwidths
        local ncols
        local nrows
        for _nrows in ipairs(list) do
            nrows = _nrows
            ncols = (#list + nrows - 1) // nrows
            colwidths = {}
            local totwidth = -2
            for col = 1, ncols do
                local colwidth = 0
                for row = 1, nrows do
                    local i = row + nrows * col
                    if i > #list then
                        break
                    end
                    local x = list[i]
                    colwidth = math.max(colwidth, #x)
                end
                table.insert(colwidths, colwidth)
                totwidth = totwidth + colwidth + 2
                if totwidth > displaywidth then
                    break
                end
            end
            if totwidth <= displaywidth then
                goto fits
            end
        end
        nrows = #list
        ncols = 1
        colwidths = {0}
        ::fits::
        for row = 1, nrows do
            local texts = {}
            for col = 1, ncols do
                local x = list[row + nrows * col]
                if x then
                    table.insert(texts, x)
                end
            end
            for col = 1, #texts do
                texts[col] = ('%%-%ds'):format(colwidths[col]):format(texts[col])
            end
            self.stdout:write(table.concat(texts, "  "), '\n')
        end
    end,
}

local default_actions = {
    help = function (self, arg)
        if arg and arg ~= '' then
            local func = self.help[arg]
            if func then
                func(self)
            else
                self.stdout:write(self.nohelp:format(arg), '\n')
            end
        else
            local cmds_doc, cmds_undoc, help_temp, help = {}, {}, {}, {}
            for k in pairs(self.help) do
                help_temp[k] = true
            end
            for k in pairs(self.action) do
                if help_temp[k] then
                    table.insert(cmds_doc, k)
                else
                    table.insert(cmds_undoc, k)
                end
                help_temp[k] = nil
            end
            for k in pairs(help_temp) do
                table.insert(help, k)
            end
            table.sort(cmds_doc)
            table.sort(help)
            table.sort(cmds_undoc)

            self.stdout:write(self.doc_leader, '\n')
            self:print_topics(self.doc_header, cmds_doc, 80)
            self:print_topics(self.misc_header, help, 80)
            self:print_topics(self.undoc_header, cmds_undoc, 80)
        end
    end,
}

return function (cmd)
    for k, v in pairs(defaults) do
        cmd[k] = cmd[k] or v
    end
    cmd.cmdqueue = {}
    cmd.action = cmd.action or {}
    for k, v in pairs(default_actions) do
        cmd.action[k] = cmd.action[k] or v
    end
    cmd.help = cmd.help or {}
    return cmd
end
