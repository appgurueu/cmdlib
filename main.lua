modlib.mod.extend("cmdlib", "trie")
error_format = minetest.get_color_escape_sequence("#FF0000") .. "%s"
success_format = minetest.get_color_escape_sequence("#00FF00") .. "%s"
function scope_func(scope)
    return function()
        return false,
               "Not a chatcommand, but a category. For a list of subcommands do /help " ..
                   scope .. "."
    end
end

chatcommands = trie.new()
chatcommand_info = {}
format_error = function(str) return string.format(error_format, str) end
format_success = function(str) return string.format(success_format, str) end
function validate_privs(required, actual)
    local missing, to_lose = {}, {}
    for priv, expected in pairs(required) do
        if expected then
            if not actual[priv] then table.insert(missing, priv) end
        elseif actual[priv] then
            table.insert(to_lose, priv)
        end
    end
    return missing, to_lose
end
function validate_privs_ipairs(required, forbidden, actual)
    local missing, to_lose = {}, {}
    for _, priv in ipairs(required) do
        if not actual[priv] then table.insert(missing, priv) end
    end
    for _, priv in ipairs(forbidden) do
        if actual[priv] then table.insert(to_lose, priv) end
    end
    return missing, to_lose
end
function sufficient_privs(required, playername)
    local missing, to_lose = validate_privs(required, minetest.get_player_privs(playername))
    local str
    if not modlib.table.is_empty(missing) then
        str = string.format("Missing privilege%s: ",
                            ("s" and #missing > 1) or "") ..
                  table.concat(missing)
    end
    if not modlib.table.is_empty(to_lose) then
        str = (str or "") ..
                  string.format("%srivilege%s which need to be lost: ",
                                (str and ", p") or "P",
                                ("s" and #to_lose > 1) or "") ..
                  table.concat(to_lose)
    end
    return str
end
function build_param_parser(syntax)
    local params = modlib.text.split_without_limit(syntax, " ")
    local required_params, optional_params, list_param = {}, {}
    local i = 1
    while i <= #params and params[i]:sub(1, 1) == "<" and
        params[i]:sub(params[i]:len()) == ">" do
        table.insert(required_params, params[i]:sub(2, params[i]:len() - 1))
        i = i + 1
    end
    while i <= #params and params[i]:sub(1, 1) == "[" and
        params[i]:sub(params[i]:len()) == "]" do
        table.insert(optional_params, params[i]:sub(2, params[i]:len() - 1))
        i = i + 1
    end

    if i <= #params then
        -- check for list param
        if i == #params and params[i]:sub(1, 1) == "{" and
            params[i]:sub(params[i]:len()) == "}" then
            list_param = params[i]:sub(2, params[i]:len() - 1)
        else
            return -- Failure
        end
    end

    local limit = #required_params + #optional_params
    if list_param then limit = nil end
    local minimum = #required_params
    local paramlist = required_params
    modlib.table.append(paramlist, optional_params)
    return function(param)
        local params = modlib.text.split(param, " ", limit)
        for i, param in modlib.table.rpairs(params) do
            if param == "" then table.remove(params, i) end
        end
        if #params < minimum then
            return "Too few parameters given! At least " .. minimum .. " " ..
                       ((minimum == 1 and "is") or "are") ..
                       " required. The following parameters are missing: " ..
                       table.concat({unpack(required_params, #params + 1)})
        end
        local paramtable = {}
        for index, name in ipairs(paramlist) do
            paramtable[name] = params[index]
        end
        if list_param and #params > #paramlist then
            paramtable[list_param] = {unpack(params, #paramlist + 1)}
        end
        return nil, paramtable
    end
end
function build_func(def)
    if not def.param_parser then
        return function(invokername, params)
            if def.privs then
                local error = sufficient_privs(def.privs, invokername)
                if error then return false, error end
            end
            return def.fnc(invokername, params)
        end
    end
    return function(invokername, params)
        if def.privs then
            local error = sufficient_privs(def.privs, invokername)
            if error then return false, error end
        end
        local error, params = def.param_parser(params)
        if error then return false, error end
        return def.fnc(invokername, params)
    end
end
function register_chatcommand(name, def, override)
    local definition = {
        description = def.description ~= "" and def.description,
        privs = def.privs and next(def.privs) and def.privs,
        params = def.params ~= "" and def.params,
        custom_syntax = def.custom_syntax,
        implicit_call = def.implicit_call,
        fnc = def.func or error("/" .. name .. ": No function given")
    }
    if definition.params then definition.implicit_call = true end
    if not definition.custom_syntax then
        definition.param_parser = build_param_parser(definition.params or "")
    end
    definition.func = build_func(definition)
    local scopes = modlib.text.split_without_limit(name, " ")
    if #scopes == 1 then
        chatcommand_info[name] = modlib.table.tablecopy(definition)
        trie.insert(chatcommands, name, definition, override)
    else
        local supercommand, super_info = trie.get(chatcommands, scopes[1]),
                                         chatcommand_info[scopes[1]]
        if not supercommand then
            supercommand = {
                subcommands = trie.new(),
                func = scope_func(scopes[1])
            }
            trie.insert(chatcommands, scopes[1], supercommand)
            super_info = {subcommands = {}}
            chatcommand_info[scopes[1]] = super_info
        end
        local inherited_privs = modlib.table.tablecopy(supercommand.privs or {})
        for i = 2, #scopes - 1 do
            if not supercommand.subcommands then
                supercommand.subcommands = trie.new()
            end
            if not super_info.subcommands then
                super_info.subcommands = {}
            end
            local subcommand = {
                subcommands = trie.new(),
                func = scope_func(scopes[1])
            }
            local prevval = trie.insert(supercommand.subcommands, scopes[i],
                                        subcommand)
            modlib.table.add_all(inherited_privs,
                                 (prevval and prevval.privs) or {})
            supercommand = prevval or subcommand
            super_info.subcommands[scopes[i]] =
                super_info.subcommands[scopes[i]] or {subcommands = {}}
            super_info = super_info.subcommands[scopes[i]]
        end
        modlib.table.add_all(inherited_privs, def.privs or {})
        if not supercommand.subcommands then
            supercommand.subcommands = trie.new()
        end
        if not super_info.subcommands then super_info.subcommands = {} end
        definition.privs = next(inherited_privs) and inherited_privs
        super_info.subcommands[scopes[#scopes]] =
            modlib.table.tablecopy(definition)
        trie.insert(supercommand.subcommands, scopes[#scopes], definition,
                    override)
    end
end

local function name_comparator(info, name)
    return modlib.table.default_comparator(info.name, name)
end

local binary_search_name = modlib.table.binary_search_comparator(name_comparator)
function unregister_chatcommand(name)
    local function get(info, name)
        return info[(#chatcommand_info ~= 0 and binary_search(info, name)) or name]
    end
    local scopes = modlib.text.split_without_limit(name, " ")
    local super_info = chatcommand_info
    local super_trie = chatcommands
    local head_trie = chatcommands
    local head_info, head_name = chatcommand_info, scopes[1]
    for i = 2, #scopes do
        super_info = get(super_info, scopes[i-1]).subcommands
        super_trie = trie.get(super_trie, scopes[i-1]).subcommands
        local reset_head = next(super_info, next(super_info)) or super_info.implicit_call
        if reset_head then
            head_info, head_name = super_info, scopes[i]
            head_trie = super_trie
        end
    end
    trie.remove(head_trie, head_name)
    if #chatcommand_info ~= 0 then
        head_name = binary_search_name(head_info, head_name)
    end
    head_info[head_name] = nil
end

function wrap_text(text, max)
    max = max or 80
    local res = {text}
    while res[#res]:len() > max do
        for i = max, 1, -1 do
            if res[#res]:sub(i, i) == " " then
                table.insert(res, res[#res]:sub(i + 1))
                res[#res - 1] = res[#res - 1]:sub(1, i - 1)
                break
            end
        end
    end
    return res
end

function handle_chat_message(sendername, message)
    if message:sub(1, 1) == "/" then
        local last_space, next_space = 2, message:find(" ")
        local command_trie, command_name = chatcommands
        local cmd, suggestion
        repeat
            next_space = next_space or message:len() + 1
            command_name = message:sub(last_space, next_space - 1)
            if command_name == "" and cmd and not cmd.params then
                break
            end
            cmd, suggestion, _ = trie.search(command_trie, command_name)
            if not cmd then
                minetest.chat_send_player(sendername,
                                          string.format(error_format,
                                                        "No such chatcommand. " ..
                                                            ((suggestion and
                                                                'Did you mean "' ..
                                                                message:sub(1,
                                                                            last_space -
                                                                                1) ..
                                                                suggestion ..
                                                                '" ?') or "")))
                return true
            elseif cmd.subcommands and not cmd.implicit_call then
                command_trie = cmd.subcommands
                last_space, next_space = next_space + 1,
                                         message:find(" ", next_space + 1)
            else
                last_space = next_space + 1
                break
            end
        until next_space == message:len()
        local params = message:sub(last_space)
        local success, response = cmd.func(sendername, params)
        if response then
            if success == true then
                minetest.chat_send_player(sendername, string.format(
                                              success_format, response))
            elseif success == false then
                minetest.chat_send_player(sendername,
                                          string.format(error_format, response))
            else
                minetest.chat_send_player(sendername, response)
            end
        end
        return true
    end
end

table.insert(core.registered_on_chat_messages, 1, handle_chat_message)

function build_info(chatcommands)
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
        newdef.implicit_call = def.implicit_call
        newdef.description = def.description or ""
        newdef.descriptions = wrap_text(def.description or "", 60)
        newdef.privs = next(newprivs) and newprivs
        newdef.forbidden_privs = next(newforbiddenprivs) and newforbiddenprivs
        newdef.params = def.params or ""
        newdef.subcommands = def.subcommands
        table.insert(new_info, newdef)
        if newdef.subcommands then
            newdef.subcommands = build_info(newdef.subcommands)
        end
    end
    table.sort(new_info, function(d1, d2) return d1.name < d2.name end)
    return new_info
end

minetest.register_on_mods_loaded(function()
    modlib.mod.extend("cmdlib", "help")
    chatcommand_info = build_info(chatcommand_info)
end)
