include("cmdlib", "trie.lua")

local override_minetest = false
local error_format = minetest.get_color_escape_sequence("#FF0000").."%s"
local success_format = minetest.get_color_escape_sequence("#00FF00").."%s"
local chatcommands = trie.new()
chatcommand_info = {}
cmd_ext = {
    error = function(str)
        return string.format(error_format, str)
    end,
    success = function(str)
        return string.format(success_format, str)
    end,
    validate_privs=function(required, actual)
        local missing, to_lose = {}, {}
        for priv, expected in pairs(required) do
            if expected then
                if not actual[priv] then table.insert(missing, priv) end
            elseif actual[priv] then
                table.insert(to_lose, priv)
            end
        end
        return missing, to_lose
    end,
    validate_privs_ipairs=function(required, forbidden, actual)
        local missing, to_lose = {}, {}
        for _, priv in ipairs(required) do
            if not actual[priv] then table.insert(missing, priv) end
        end
        for _, priv in ipairs(forbidden) do
            if actual[priv] then table.insert(to_lose, priv) end
        end
        return missing, to_lose
    end,
    -- returns
    sufficient_privs=function(required, playername)
        local missing, to_lose = cmd_ext.validate_privs(required, minetest.get_player_privs(playername))
        local str
        if not table_ext.is_empty(missing) then
            str = string.format("Missing privilege%s : ", ("s" and #missing > 1) or "")..table.concat(missing)
        end
        if not table_ext.is_empty(to_lose) then
            str = (str or "")..string.format("%srivilege%s which need to be lost : ", (str and ", p") or "P", ("s" and #to_lose > 1) or "")..table.concat(to_lose)
        end
        return str
    end,
    build_param_parser=function(syntax)
        local params = string_ext.split_without_limit(syntax, " ")
        local required_params, optional_params, list_param = {}, {}
        local i = 1
        while i <= #params and params[i]:sub(1, 1) == "<" and params[i]:sub(params[i]:len()) == ">" do
            table.insert(required_params, params[i]:sub(2, params[i]:len()-1))
            i = i + 1
        end
        while i <= #params and params[i]:sub(1, 1) == "[" and params[i]:sub(params[i]:len()) == "]" do
            table.insert(optional_params, params[i]:sub(2, params[i]:len()-1))
            i = i + 1
        end

        if i <= #params then
            -- check for list param
            if i == #params and params[i]:sub(1, 1) == "{" and params[i]:sub(params[i]:len()) == "}" then
                list_param = params[i]:sub(2, params[i]:len()-1)
            else
                return -- Failure
            end
        end

        local limit = #required_params + #optional_params + 1
        if list_param then limit = nil end
        local minimum = #required_params
        local paramlist = {}
        if next(required_params) then
            if next(optional_params) then
                paramlist = {unpack(required_params), unpack(optional_params)}
            end
            paramlist = required_params
        elseif next(optional_params) then
            paramlist = optional_params
        end
        return function (param)
            local params = string_ext.split(param, " ", limit)
            for i, param in table_ext.rpairs(params) do if param == "" then table.remove(params, i) end end
            if #params < minimum then
                return "Too few parameters given ! At least "..minimum.." are required. The following parameters are missing : "..table.concat({unpack(required_params, #params+1)})
            end
            local paramtable = {}
            for index, name in ipairs(paramlist) do
                paramtable[name] = params[index]
            end
            if list_param and #params > #paramlist then
                paramtable[list_param] = {unpack(params, #paramlist)}
            end
            return nil, paramtable
        end
    end,
    build_func=function(def)
        if not def.param_parser then
            return function(invokername, params)
                if def.privs then
                    local error = cmd_ext.sufficient_privs(def.privs, invokername); if error then return false, error end
                end
                return def.fnc(invokername, params)
            end
        end
        return function(invokername, params)
            if def.privs then
                local error = cmd_ext.sufficient_privs(def.privs, invokername); if error then return false, error end
            end
            local error, params = def.param_parser(params); if error then return false, error end
            return def.fnc(invokername, params)
        end
    end,
    register_chatcommand=function(name, def, override)
        local definition = {
            description = def.description ~= "" and def.description,
            privs = def.privs and next(def.privs) and def.privs,
            params = def.params ~= "" and def.params,
            custom_syntax = def.custom_syntax,
            implicit_call = def.implicit_call,
            fnc = def.func or error("/"..name.." : No function given")
        }
        if definition.params then
            definition.implicit_call = true
        end
        if not definition.custom_syntax then
            definition.param_parser = cmd_ext.build_param_parser(definition.params or "")
        end
        definition.func = cmd_ext.build_func(definition)
        local scopes=string_ext.split_without_limit(name, " ")
        if #scopes == 1 then
            chatcommand_info[name] = table_ext.tablecopy(definition)
            trie.insert(chatcommands, name, definition, override)
        else
            local supercommand, super_info = trie.get(chatcommands, scopes[1]), chatcommand_info[scopes[1]]
            if not supercommand then
                supercommand = {subcommands = {}, func = function() end}
                trie.insert(chatcommands, scopes[1], supercommand)
                super_info = {subcommands = {}}
                chatcommand_info[scopes[1]] = super_info
            end
            local inherited_privs = table_ext.tablecopy(supercommand.privs or {})
            for i = 2, #scopes-1 do
                if not supercommand.subcommands then
                    supercommand.subcommands = trie.new()
                end
                if not super_info.subcommands then
                    super_info.subcommands = {}
                end
                local subcommand = {subcommands = trie.new(), func = function() end}
                local prevval = trie.insert(supercommand.subcommands, scopes[i], subcommand)
                table_ext.add_all(inherited_privs, prevval.privs or {})
                supercommand = prevval or subcommand --trie.get(supercommand.subcommands, scopes[i])
                super_info[scopes[i]] = super_info.subcommands[scopes[i]] or {subcommands = {}}
                super_info = super_info.subcommands[scopes[i]]
            end
            table_ext.add_all(inherited_privs, def.privs or {})
            if not supercommand.subcommands then
                supercommand.subcommands = trie.new()
            end
            if not super_info.subcommands then
                super_info.subcommands = {}
            end
            definition.privs = next(inherited_privs) and inherited_privs
            super_info.subcommands[scopes[#scopes]] = table_ext.tablecopy(definition)
            trie.insert(supercommand.subcommands, scopes[#scopes], definition, override)
        end
    end,
    wrap_text = function(text, max)
        max = max or 80
        local res = {text}
        while res[#res]:len() > max do
            for i=max, 1, -1 do
                if res[#res]:sub(i, i) == " " then
                    table.insert(res,res[#res]:sub(i+1))
                    res[#res-1] = res[#res-1]:sub(1, i-1)
                    break
                end
            end
        end
        return res
    end
}

function cmd_ext.handle_chat_message(sendername, message)
    if message:sub(1, 1) == "/" then
        local last_space, next_space = 2, message:find(" ")
        local command_trie, command_name = chatcommands
        local cmd, suggestion
        repeat
            next_space = next_space or message:len()+1
            command_name = message:sub(last_space, next_space-1)
            if command_name == "" and cmd and not cmd.params then break end
            cmd, suggestion, _ = trie.search(command_trie, command_name)
            if not cmd then
                minetest.chat_send_player(sendername, string.format(error_format, "No such chatcommand. "..((suggestion and "Did you mean \""..message:sub(1, last_space-1)..suggestion.."\" ?") or "")))
                return true
            elseif cmd.subcommands and not cmd.implicit_call then
                command_trie = cmd.subcommands
                last_space, next_space = next_space + 1, message:find(" ", next_space+1)
            else
                last_space = next_space + 1
                break
            end
        until next_space == message:len()
        local params = message:sub(last_space)
        local success, response = cmd.func(sendername, params)
        if response then
            if success == true then
                minetest.chat_send_player(sendername, string.format(success_format, response))
            elseif success == false then
                minetest.chat_send_player(sendername, string.format(error_format, response))
            else
                minetest.chat_send_player(sendername, response)
            end
        end
        return true
    end
end

table.insert(core.registered_on_chat_messages, 1, cmd_ext.handle_chat_message)

dofile(get_resource("cmdlib", "override.lua"))
-- Tests - only uncomment if testing stuff
--[[
dofile("test.lua")
]]

minetest.register_on_mods_loaded(function()
    dofile(get_resource("cmdlib", "help.lua"))
    local function convert(chatcommands)
        local new_info = {}
        for name, def in pairs(chatcommands) do
            local newdef = {}
            newdef.name = name
            local newprivs, newforbiddenprivs = {}, {}
            for priv, val in pairs(def.privs or {}) do
                if val then
                    table.insert(newprivs, priv)
                else
                    table.insert(newforbiddenprivs, priv)
                end
            end
            newdef.description = def.description or ""
            newdef.descriptions = cmd_ext.wrap_text(def.description or "", 60)
            newdef.privs = next(newprivs) and newprivs
            newdef.forbidden_privs = next(newforbiddenprivs) and newforbiddenprivs
            newdef.params = def.params or ""
            newdef.subcommands = def.subcommands
            table.insert(new_info, newdef)
            if newdef.subcommands then
                newdef.subcommands = convert(newdef.subcommands)
            end
        end
        table.sort(new_info, function(d1, d2) return d1.name < d2.name end)
        return new_info
    end
    chatcommand_info = convert(chatcommand_info)
end)