function test_format()
    minetest.after(1, function()
        minetest.chat_send_all(minetest.get_color_escape_sequence("#FF0000")..[[✗ Looks like there's an error ! (!) /!\
]]..minetest.get_color_escape_sequence("#00FF00")..[[✓ All is alright yay ! (i) (x)]])
    end)
end

function test_chatcommands()
    cmd_ext.register_chatcommand("cmdlib_test", {
        params = "<param1>",
        privs = {fast = true},
        description = "Test command for cmdlib.",
        func = function(sendername, params)
            return true, "You shouted "..(params.param1)
        end
    })
    cmd_ext.register_chatcommand("cmdlib_test say", {
        params = "<param1>",
        privs = {fast = true, noclip = false},
        description = "Test command for cmdlib.",
        func = function(sendername, params)
            return true, "You said "..(params.param1)
        end
    })
    -- TODO fix error when invoking without params (should say params required ?)
    cmd_ext.register_chatcommand("cmdlib_test bark", {
        params = "<param1>",
        privs = {fast = true},
        description = "Test command for cmdlib.",
        func = function(sendername, params)
            return true, "You barked "..(params.param1)
        end
    })
    cmd_ext.register_chatcommand("cmdlib_test bark loud", {
        params = "[param1]",
        privs = {fast = true},
        description = "Test command : cmdlib.",
        func = function(sendername, params)
            return true, "You BARKED "..(params.param1 or "IDK")
        end
    })
end

function test_trie()
    local t = trie.new()
    trie.insert(t, "help")
    trie.insert(t, "heap")
    trie.insert(t, "me")
    --trie.insert(t, "heap")
    print(trie.search(t, "hewp"))
    trie.remove(t, "heap")
    print(trie.search(t, "help"))
    print(trie.search(t, "heap"))
end

function test_info()
    minetest.after(1, function()
        print(dump(chatcommand_info))
    end)
end

test_chatcommands()
-- test_format()
-- test_trie()
-- test_info()

--minetest.register_node("cmdlib:item", {description = minetest.get_color_escape_sequence("#FF0000").."✗ Looks like there's an error !"})