minetest.original_register_chatcommand = minetest.register_chatcommand
minetest.original_override_chatcommand = minetest.override_chatcommand

local minetest_register_chatcommand = function(name, def)
    register_chatcommand(name, {
        description = def.description,
        privs = def.privs,
        params = def.params,
        custom_syntax = true,
        func = def.func
    })
end

for name, def in pairs(minetest.registered_chatcommands) do
    minetest_register_chatcommand(name, def)
end

minetest.register_chatcommand = function(name, def)
    minetest_register_chatcommand(name, def)
    minetest.original_register_chatcommand(name, def)
end

minetest.override_chatcommand = function(name, def)
    minetest_register_chatcommand(name, def)
    minetest.original_override_chatcommand(name, def)
end