-- Real Estate mod for Luanti
-- Sell your areas!

-- Copyright (c) 2018 Gabriel Pérez-Cerezo <gabriel@gpcf.eu>
-- Copyright (c) 2026 erstazi <erstazi@gmail.com>

-- This program is free software: you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation, either version 3 of the
-- License, or (at your option) any later version.

-- This program is distributed in the hope that it will be useful, but
-- WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see
-- <http://www.gnu.org/licenses/>.

local S = core.get_translator(core.get_current_modname())
local SF = string.format
local ESC = core.formspec_escape
local storage = core.get_mod_storage()

jc_realestate = {}

jc_realestate.area = function(area_id)
  local area = areas.areas[area_id]

  if not area then
    return 0
  end

  local size = (math.abs(area.pos1.x - area.pos2.x) + 1) * (math.abs(area.pos1.z - area.pos2.z) + 1)

  return size
end

local playerpos = {}

local currencies = {
  { name = "Gold Ingot",            item = "default:gold_ingot", },
  { name = "Gold Block",            item = "default:goldblock", },
  { name = "Diamond",               item = "default:diamond", },
  { name = "Mese",                  item = "default:mese", },
  { name = "Mese Crystal",          item = "default:mese_crystal", },
  { name = "Mese Crystal Fragment", item = "default:mese_crystal_fragment", },
}

local function get_currency_name(item)
  for _, currency in ipairs(currencies) do
    if currency.item == item then
      return currency.name
    end
  end

  return "Unknown"
end

local function count_items(player, item_name)
  local count = 0
  local inventory = player:get_inventory()

  for i = 1, inventory:get_size("main") do
    local stack = inventory:get_stack("main", i)

    if stack:get_name() == item_name then
      count = count + stack:get_count()
    end
  end

  return count
end

local function remove_items(player, item_name, amount)
  local inventory = player:get_inventory()
  local remaining = amount

  for i = 1, inventory:get_size("main") do
    local stack = inventory:get_stack("main", i)

    if stack:get_name() == item_name then
      local remove = math.min(stack:get_count(), remaining)

      stack:set_count(stack:get_count() - remove)
      inventory:set_stack("main", i, stack)

      remaining = remaining - remove

      if remaining <= 0 then
        return true
      end
    end
  end

  return false
end

local function get_item_capacity(player, item_name)
  local inventory = player:get_inventory()
  local stack_max = ItemStack(item_name):get_stack_max()
  local capacity = 0

  for i = 1, inventory:get_size("main") do
    local stack = inventory:get_stack("main", i)

    if stack:is_empty() then
      capacity = capacity + stack_max
    elseif stack:get_name() == item_name then
      capacity = capacity + stack_max - stack:get_count()
    end
  end

  return capacity
end

local function add_items(player, item_name, amount)
  if get_item_capacity(player, item_name) < amount then
    return false
  end

  local inventory = player:get_inventory()
  local stack_max = ItemStack(item_name):get_stack_max()
  local remaining = amount

  while remaining > 0 do
    local count = math.min(remaining, stack_max)
    local stack = ItemStack(item_name)
    stack:set_count(count)

    local leftover = inventory:add_item("main", stack)

    if not leftover:is_empty() then
      return false
    end

    remaining = remaining - count
  end

  return true
end

local function get_pending_payments(player_name)
  local key = "pending_" .. player_name
  return core.deserialize(storage:get_string(key)) or {}
end

local function save_pending_payments(player_name, pending)
  local key = "pending_" .. player_name

  if #pending == 0 then
    storage:set_string(key, "")
  else
    storage:set_string(key, core.serialize(pending))
  end
end

local function store_pending_payment(player_name, item_name, amount)
  local pending = get_pending_payments(player_name)

  pending[#pending + 1] = {
    item = item_name,
    amount = amount,
  }

  save_pending_payments(player_name, pending)
end

local function notify_pending_payment(player)
  local player_name = player:get_player_name()
  local pending = get_pending_payments(player_name)

  if #pending == 0 then
    return
  end
  local singular = "Real Estate: You have @1 pending payment. Use @2 to collect it."
  local plural = "Real Estate: You have @1 pending payments. Use @2 to collect it."

  core.chat_send_player(player_name, core.colorize("#FFFFFF", SF("Real Estate: You have %s pending payment" .. (#pending == 1 and "" or "s") .. ". Use %s to collect it.", #pending, core.colorize("#FFFF00", "/claim_payment") ) ) )
end

local function claim_pending_payments(player)
  local player_name = player:get_player_name()
  local pending = get_pending_payments(player_name)

  if #pending == 0 then
    core.chat_send_player(player_name, S("Real Estate: You have no pending payments.") )

    return
  end

  local remaining = {}
  local claimed = 0

  for _, payment in ipairs(pending) do
    if get_item_capacity(player, payment.item) >= payment.amount then
      if add_items(player, payment.item, payment.amount) then
        core.chat_send_player(player_name, "Real Estate: You received " .. payment.amount .. " " .. get_currency_name(payment.item) .. "." )

        claimed = claimed + 1
      else
        remaining[#remaining + 1] = payment
      end
    else
      remaining[#remaining + 1] = payment
    end
  end

  save_pending_payments(player_name, remaining)

  if claimed == 0 then
    core.chat_send_player(player_name, "Real Estate: Your inventory does not have enough room for your pending payments.")
  elseif #remaining > 0 then
    core.chat_send_player(player_name, core.colorize("#FFFFFF", SF("Real Estate: Some payments are still waiting because your inventory is full. Use the command %s again when you have room.", core.colorize("#FFFF00", "/claim_payment") ) ) )
  else
    core.chat_send_player(player_name, "Real Estate: All pending payments have been collected.")
  end
end

core.register_chatcommand("claim_payment", {
  description = S("Collect pending real estate payments"),
  func = function(name)
    local player = core.get_player_by_name(name)

    if not player then
      return false, S("You must be online to claim your payments.")
    end

    claim_pending_payments(player)

    return true
  end,
})

core.register_on_joinplayer(function(player)
  core.after(1, function()
    if player and player:is_player() then
      notify_pending_payment(player)
    end
  end)
end)

local function after_place_node(pos, player)
  local meta = core.get_meta(pos)
  local owner = player:get_player_name()

  meta:set_string("owner", owner)
  meta:set_string("infotext", "Land for sale by " .. owner)
end

local function get_setup_formspec(pos, player)
  local meta = core.get_meta(pos)
  local id = meta:get_int("id")
  local price = meta:get_int("price")
  local currency = meta:get_string("currency")

  local currency_rows = math.ceil(#currencies / 3)
  local fields_y = 2.7 + (currency_rows * 0.8)
  local buttons_y = fields_y + 1.5
  local form_height = buttons_y + 1.2

  if id <= 0 then
    id = ""
  end

  if price <= 0 then
    price = ""
  end

  local formspec =
    "size[8.5," .. form_height .. "]" ..
    default.gui_bg ..
    default.gui_bg_img ..
    default.gui_slots ..
    "label[2.5,0;Real estate for sale]" ..
    "label[0.2,1.5;Currency:]"

  for index, currency_data in ipairs(currencies) do
    local column = (index - 1) % 3
    local row = math.floor((index - 1) / 3)
    local x = 1.4 + (column * 2.0)
    local y = 1.3 + (row * 0.8)
    local checked = currency == currency_data.item and "true" or "false"

    formspec = formspec .. "checkbox[" .. x .. "," .. y .. ";currency_" .. index .. ";" .. ESC(currency_data.name) .. ";" .. checked .. "]"
  end

  formspec = formspec ..
    "field[1.0," .. fields_y .. ";3,1;name;Area ID;" .. id .. "]" ..
    "field[4.5," .. fields_y .. ";3,1;price;Price;" .. price .. "]" ..
    "button_exit[0.2," .. buttons_y .. ";1,1;Quit;Quit]" ..
    "button[5.2," .. buttons_y .. ";3,1;sell;Save]" ..
    ""

  return formspec
end

local function get_sell_formspec(pos, player)
  local meta = core.get_meta(pos)
  local owner = meta:get_string("owner")
  local name = player:get_player_name()
  local id = meta:get_int("id")
  local price = meta:get_int("price")
  local currency = meta:get_string("currency")

  playerpos[name] = pos

  if name == owner then
    core.after(0.1, function()
      if core.get_player_by_name(name) then
        core.show_formspec(name, "jc_realestate.setup", get_setup_formspec(pos, player) )
      end
    end)

    return
  end

  if id <= 0 or price <= 0 or currency == "" then
    core.chat_send_player(name, "This sale point is unconfigured.")
    return
  end

  if get_currency_name(currency) == "Unknown" then
    core.chat_send_player(name, "This sale point has an invalid currency.")
    return
  end

  if not areas.areas[id] then
    core.chat_send_player(name, "The area no longer exists.")
    return
  end

  local area = areas.areas[id]
  local currency_name = get_currency_name(currency)

  local formspec =
    "size[8,6]" ..
    default.gui_bg ..
    default.gui_bg_img ..
    default.gui_slots ..
    "label[2.5,0;Real estate for sale]" ..
    "label[0.5,1.0;Area Number: " .. id .. "]" ..
    "label[0.5,1.5;Area Name: " .. ESC(area.name or "") .. "]" ..
    "label[0.5,2.0;Area Price: " .. price .. "]" ..
    "item_image[0.5,2.5;1,1;" .. currency .. "]" ..
    "label[1.7,2.85;" .. ESC(currency_name) .. "]" ..
    "label[0.5,3.5;Surface Area: " .. jc_realestate.area(id) .. " m²]" ..
    "button_exit[0.2,5;1,1;Quit;Quit]" ..
    "button[4.7,5;3,1;buy;Buy]"

  core.after(0.1, function()
    if core.get_player_by_name(name) then
      core.show_formspec(name, "jc_realestate.sell", formspec)
    end
  end)
end

local function starts_with(string, prefix)
  return string.sub(string, 1, string.len(prefix)) == prefix
end

local function transfer_node_owner(pos, original_owner, new_owner, actor)
  local meta = core.get_meta(pos)
  local node = core.get_node(pos)
  local node_owner = meta:get_string("owner")

  if node_owner == "" then
    node_owner = meta:get_string("doors_owner")
  end

  -- Do not take ownership of somebody else's protected node.
  if node_owner ~= "" and node_owner ~= original_owner and node_owner ~= new_owner then
    return
  end

  if node.name == "locks:shared_locked_chest" then
    locks:lock_set_owner(pos, new_owner, "Shared locked chest")
    return
  end

  if node.name == "locks:shared_locked_furnace" then
    locks:lock_set_owner(pos, new_owner, "Shared locked furnace")
    return
  end

  if node.name == "locks:shared_locked_sign_wall" then
    locks:lock_set_owner(pos, new_owner, "Shared locked sign")
    return
  end

  if starts_with(node.name, "locks:door") then
    locks:lock_set_owner(pos, new_owner, "Shared locked door")
    return
  end

  if node.name == "default:chest_locked" or node.name == "default:chest_locked_open" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Locked Chest (owned by " .. new_owner .. ")")
    return
  end

  if starts_with(node.name, "doors:door_steel_") then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Steel Door\nOwned by " .. new_owner)
    return
  end

  if node.name == "technic:iron_locked_chest"
    or node.name == "technic:copper_locked_chest"
    or node.name == "technic:silver_locked_chest"
    or node.name == "technic:gold_locked_chest"
    or node.name == "technic:mithril_locked_chest" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Locked Chest (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "inbox:empty" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", new_owner .. "'s Mailbox")
    return
  end

  if node.name == "itemframes:frame" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Item frame (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "itemframes:pedestral" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Pedestral frame (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "currency:safe" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Safe (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "currency:shop" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Exchange shop (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "bitchange:bank" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Bank (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "bitchange:moneychanger" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Moneychanger (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "bitchange:warehouse" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Warehouse (owned by " .. new_owner .. ")")
    return
  end

  if node.name == "bitchange:shop" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)

    if meta:get_string("title") ~= "" then
      meta:set_string("infotext", "Exchange shop \"" .. meta:get_string("title") .. "\" (" .. new_owner .. ")")
    else
      meta:set_string("infotext", "Exchange shop (" .. new_owner .. ")")
    end

    return
  end

  if node.name == "locked_sign:sign_wall_locked" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "\"\" (" .. new_owner .. ")")
    return
  end

  if node.name == "basic_signs:sign_wall_locked" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", "Locked sign, owned by " .. new_owner)
    return
  end

  if starts_with(node.name, "smartshop:shop") and smartshop then
    if smartshop.update_info then
      meta:set_string("owner", new_owner)
      meta:set_string("doors_owner", new_owner)

      if meta:get_int("type") == 0 and not (core.check_player_privs(new_owner, {creative = true}) or core.check_player_privs(new_owner, {give = true})) then
        meta:set_int("creative", 0)
        meta:set_int("type", 1)
      end

      smartshop.update_info(pos)

      return
    elseif smartshop.api and smartshop.api.get_object then
      local obj = smartshop.api.get_object(pos)

      if obj then
        obj:initialize_metadata(new_owner)
        obj:set_unlimited(false)
        obj:initialize_inventory()
        obj:update_appearance()
      end

      return
    end
  end
end

local function transfer_area_nodes(area, original_owner, new_owner, actor)
  local min_x = math.min(area.pos1.x, area.pos2.x)
  local max_x = math.max(area.pos1.x, area.pos2.x)
  local min_y = math.min(area.pos1.y, area.pos2.y)
  local max_y = math.max(area.pos1.y, area.pos2.y)
  local min_z = math.min(area.pos1.z, area.pos2.z)
  local max_z = math.max(area.pos1.z, area.pos2.z)

  for x = min_x, max_x do
    for y = min_y, max_y do
      for z = min_z, max_z do
        transfer_node_owner({x = x, y = y, z = z}, original_owner, new_owner, actor)
      end
    end
  end
end

local function transfer_area(id, buyer, seller, pos, actor)
  local area = areas.areas[id]

  if not area then
    return false
  end

  -- Make sure the seller still owns the area at the moment of purchase.
  if area.owner ~= seller then
    return false
  end

  transfer_area_nodes(area, seller, buyer, actor)

  area.owner = buyer
  areas:save()

  core.set_node(pos, {name = "air"})

  core.chat_send_player(buyer, "The area has been transferred to you." )

  return true
end

local function pay_seller(seller, currency, price)
  store_pending_payment(seller, currency, price)

  local seller_player = core.get_player_by_name(seller)

  if seller_player then
    core.chat_send_player(seller, core.colorize("#FFFFFF", SF("Real Estate: You have a payment of %s %s waiting. Use the command %s to collect it.", price, get_currency_name(currency), core.colorize("#FFFF00", "/claim_payment") ) ) )
  end

  return true
end

core.register_on_player_receive_fields(function(player, form, pressed)
  if form == "jc_realestate.sell" then
    if not pressed.buy then
      return
    end

    local name = player:get_player_name()
    local pos = playerpos[name]

    if not pos then
      return
    end

    local meta = core.get_meta(pos)
    local id = meta:get_int("id")
    local price = meta:get_int("price")
    local currency = meta:get_string("currency")
    local owner = meta:get_string("owner")

    if id <= 0 or price <= 0 then
      core.chat_send_player(name, "This sale point is unconfigured.")
      return
    end

    if not areas.areas[id] then
      core.chat_send_player(name, "The area no longer exists.")
      return
    end

    if get_currency_name(currency) == "Unknown" then
      core.chat_send_player(name, "This sale point has an invalid currency.")
      return
    end

    if owner == "" then
      core.chat_send_player(name, "This sale point has no owner.")
      return
    end

    if owner == name then
      core.chat_send_player(name, "You cannot buy your own area.")
      return
    end

    local available = count_items(player, currency)

    if available < price then
      core.chat_send_player(name, "You need " .. price .. " " .. get_currency_name(currency) .. " to purchase this area. You have " .. available .. "." )

      return
    end

    if not remove_items(player, currency, price) then
      core.chat_send_player(name, "Unable to remove the payment from your inventory." )

      return
    end

    if not transfer_area(id, name, owner, pos, player) then
      add_items(player, currency, price)

      core.chat_send_player(name, "The area could not be transferred." )

      return
    end

    pay_seller(owner, currency, price)
    core.close_formspec(name, "jc_realestate.sell")

    return
  end

  if form == "jc_realestate.setup" then
    local name = player:get_player_name()
    local pos = playerpos[name]

    if not pos then
      return
    end

    local meta = core.get_meta(pos)

    for index, currency_data in ipairs(currencies) do
      if pressed["currency_" .. index] == "true" then
        meta:set_string("currency", currency_data.item)

        core.after(0, function()
          local player = core.get_player_by_name(name)
          if player then
            core.show_formspec(name, "jc_realestate.setup", get_setup_formspec(pos, player) )
          end
        end)

        return
      end
    end

    --------------------------------------------------------------
    -- Save.
    --------------------------------------------------------------
    if pressed.sell then
      --------------------------------------------------------------
      -- Area number.
      --------------------------------------------------------------
      if pressed.name then
        local id = tonumber(pressed.name)

        if not id then
          core.chat_send_player(name, "Invalid area number: \"" .. pressed.name .. "\"" )

          return
        end

        if not areas.areas[id] then
          core.chat_send_player(name, "No such area with id " .. pressed.name )

          return
        end

        if areas.areas[id].owner ~= name then
          core.chat_send_player(name, "You don't own area " .. id )

          return
        end

        core.chat_send_player(name, "Selling area " .. (areas.areas[id].name or "") )

        meta:set_int("id", id)
      end

      --------------------------------------------------------------
      -- Price.
      --------------------------------------------------------------
      if pressed.price then
        local price = tonumber(pressed.price)

        if not price or price < 1 or price ~= math.floor(price) then
          core.chat_send_player(name, "Price must be a whole number greater than zero." )

          return
        end

        meta:set_int("price", price)
      end

      local currency = meta:get_string("currency")

      for index, currency_data in ipairs(currencies) do
        if pressed["currency_" .. index] == "true" then
          currency = currency_data.item
        end
      end

      if get_currency_name(currency) == "Unknown" then
        currency = currencies[1].item
        meta:set_string("currency", currency)
      end

      local id = meta:get_int("id")
      local price = meta:get_int("price")

      meta:set_string("infotext", "Land for sale by " .. name .. " - " .. price .. " " .. get_currency_name(currency) )

      core.close_formspec(name, "jc_realestate.setup")

      return
    end
  end
end)

core.register_node("jc_realestate:sign", {
  tiles = {
    "default_wood.png",
    "default_wood.png",
    "default_wood.png",
    "default_wood.png",
    "jc_realestate_sign_back.png",
    "jc_realestate_sign.png"
  },
  drawtype = "nodebox",
  paramtype = "light",
  description = "For Sale Sign",
  node_box = {
    type = "fixed",
    fixed = {
      {0.4375, -0.5, 0, 0.5, 0.4375, 0.0625},
      {-0.5, 0.375, 0, 0.5, 0.4375, 0.0625},
      {-0.465, -0.2, 0, 0.4, 0.3125, 0.0625},
      {-0.375, 0.3125, 0, -0.3125, 0.375, 0.0625},
      {0.25, 0.3125, 0, 0.3125, 0.4375, 0.0625},
    }
  },
  after_place_node = after_place_node,
  paramtype2 = "facedir",
  groups = {snappy = 3},
  on_rightclick = function(pos, node, player, itemstack, pointed_thing)
    get_sell_formspec(pos, player)
  end,
})

core.register_craft({
  output = "jc_realestate:sign",
  recipe = {
    {"default:stick", "default:stick", "default:stick"},
    {"default:stick", "", "default:sign_wall_wood"},
    {"default:stick", "", ""}
  }
})