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
  { name = S("Gold Ingot"),            item = "default:gold_ingot", },
  { name = S("Gold Block"),            item = "default:goldblock", },
  { name = S("Diamond"),               item = "default:diamond", },
  { name = S("Mese"),                  item = "default:mese", },
  { name = S("Mese Crystal"),          item = "default:mese_crystal", },
  { name = S("Mese Crystal Fragment"), item = "default:mese_crystal_fragment", },
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

local function get_group_areas(group)
  if group == "" then
    return {}
  end

  return core.deserialize(storage:get_string("group_areas_" .. group)) or {}
end

local function save_group_areas(group, area_ids)
  if group == "" then
    return
  end

  if #area_ids == 0 then
    storage:set_string("group_areas_" .. group, "")
  else
    storage:set_string("group_areas_" .. group, core.serialize(area_ids))
  end
end

local function add_group_area(group, area_id)
  if group == "" then
    return
  end

  local area_ids = get_group_areas(group)

  for _, existing_id in ipairs(area_ids) do
    if existing_id == area_id then
      return
    end
  end

  area_ids[#area_ids + 1] = area_id
  save_group_areas(group, area_ids)
end

local function remove_group_area(group, area_id)
  if group == "" then
    return
  end

  local area_ids = get_group_areas(group)
  local remaining = {}

  for _, existing_id in ipairs(area_ids) do
    if existing_id ~= area_id then
      remaining[#remaining + 1] = existing_id
    end
  end

  save_group_areas(group, remaining)
end

local function get_area_group(area_id)
  if area_id <= 0 then
    return ""
  end

  return storage:get_string("area_group_" .. area_id)
end

local function set_area_group(area_id, group)
  if area_id <= 0 then
    return
  end

  storage:set_string("area_group_" .. area_id, group or "")
end

local function update_area_group(area_id, group)
  local old_group = get_area_group(area_id)

  if old_group ~= "" and old_group ~= group then
    remove_group_area(old_group, area_id)
  end

  set_area_group(area_id, group)

  if group ~= "" then
    add_group_area(group, area_id)
  end
end

local function player_owns_group(player_name, group)
  if group == "" then
    return false
  end

  for _, area_id in ipairs(get_group_areas(group)) do
    local area = areas.areas[area_id]

    if area and area.owner == player_name and get_area_group(area_id) == group then
      return true
    end
  end

  return false
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

  if #pending == 1 then
    core.chat_send_player(player_name, core.colorize("#FFFFFF", S("Real Estate: You have @1 pending payment. Use @2 to collect it.", #pending, core.colorize("#FFFF00", "/claim_payment") ) ) )
  else
    core.chat_send_player(player_name, core.colorize("#FFFFFF", S("Real Estate: You have @1 pending payments. Use @2 to collect it.", #pending, core.colorize("#FFFF00", "/claim_payment") ) ) )
  end
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
        core.chat_send_player(player_name, S("Real Estate: You received @1 @2.", payment.amount, get_currency_name(payment.item) ) )
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
    core.chat_send_player(player_name, S("Real Estate: Your inventory does not have enough room for your pending payments.") )
  elseif #remaining > 0 then
    core.chat_send_player(player_name, core.colorize("#FFFFFF", S("Real Estate: Some payments are still waiting because your inventory is full. Use the command @1 again when you have room.", core.colorize("#FFFF00", "/claim_payment") ) ) )
  else
    core.chat_send_player(player_name, S("Real Estate: All pending payments have been collected.") )
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
  meta:set_string("infotext", S("Land for sale by @1", owner) )

  local area_ids = areas:getAreasAtPos(pos)
  local selected_id
  local selected_size
  local selected_group

  for area_id, area in pairs(area_ids) do
    if area.owner == owner then
      local group = get_area_group(area_id)

      if group ~= "" then
        local size = (math.abs(area.pos1.x - area.pos2.x) + 1) *
          (math.abs(area.pos1.y - area.pos2.y) + 1) *
          (math.abs(area.pos1.z - area.pos2.z) + 1)

        if not selected_size or size < selected_size then
          selected_id = area_id
          selected_size = size
          selected_group = group
        end
      end
    end
  end

  if selected_id then
    meta:set_int("id", selected_id)
    meta:set_string("group", selected_group)
    meta:set_int("area_locked", 1)
  end
end

local function get_setup_formspec(pos, player)
  local meta = core.get_meta(pos)
  local id = meta:get_int("id")
  local price = meta:get_int("price")
  local currency = meta:get_string("currency")
  local group = meta:get_string("group")
  local group_locked = false

  if id > 0 then
    local area_group = get_area_group(id)

    if area_group ~= "" then
      group = area_group
      group_locked = true
    end
  end

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
    "label[2.5,0;" .. ESC(S("Real estate for sale")) .. "]" ..
    "label[0.2,1.5;" .. ESC(S("Currency:")) .. "]"

  for index, currency_data in ipairs(currencies) do
    local column = (index - 1) % 3
    local row = math.floor((index - 1) / 3)
    local x = 1.4 + (column * 2.0)
    local y = 1.3 + (row * 0.8)
    local checked = currency == currency_data.item and "true" or "false"

    formspec = formspec .. "checkbox[" .. x .. "," .. y .. ";currency_" .. index .. ";" .. ESC(currency_data.name) .. ";" .. checked .. "]"
  end

  formspec = formspec ..
    "field[0.5," .. fields_y .. ";2.5,1;name;" .. ESC(S("Area ID")) .. ";" .. ESC(id) .. "]" ..
    "field[3.2," .. fields_y .. ";2.5,1;price;" .. ESC(S("Price")) .. ";" .. ESC(price) .. "]"

  if group_locked then
    formspec = formspec ..
      "label[5.9," .. (fields_y - 0.6) .. ";" .. ESC(S("Group Name")) .. "]" ..
      "label[5.9," .. (fields_y - 0.1) .. ";" .. ESC(group) .. "]"
  else
    formspec = formspec ..
      "field[5.9," .. fields_y .. ";2.5,1;group;" .. ESC(S("Group Name")) .. ";" .. ESC(group) .. "]"
  end

  formspec = formspec ..
    "button_exit[0.2," .. buttons_y .. ";3,1;Quit;" .. ESC(S("Quit")) .. "]" ..
    "button[5.2," .. buttons_y .. ";3,1;sell;" .. ESC(S("Save")) .. "]" ..
    ""

  return formspec
end

local function get_sell_formspec(pos, player)
  local meta = core.get_meta(pos)
  local owner = meta:get_string("owner")
  local group = meta:get_string("group")
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
    core.chat_send_player(name, S("This sale point is unconfigured."))
    return
  end

  if get_currency_name(currency) == "Unknown" then
    core.chat_send_player(name, S("This sale point has an invalid currency."))
    return
  end

  if not areas.areas[id] then
    core.chat_send_player(name, S("The area no longer exists."))
    return
  end

  local area = areas.areas[id]
  local currency_name = get_currency_name(currency)

  local formspec =
    "size[8,6]" ..
    default.gui_bg ..
    default.gui_bg_img ..
    default.gui_slots ..
    "label[2.5,0;" .. ESC(S("Real estate for sale")) .. "]" ..
    "label[0.5,1.0;" .. ESC(S("Area ID:")) .. " " .. id .. "]" ..
    "label[0.5,1.5;" .. ESC(S("Area Name:")) .. " " .. ESC(area.name or "") .. "]" ..
    "label[0.5,2.0;" .. ESC(S("Area Price:")) .. " " .. price .. "]" ..
    "item_image[0.5,2.5;1,1;" .. currency .. "]" ..
    "label[1.7,2.85;" .. ESC(currency_name) .. "]" ..
    "label[0.5,3.5;" .. ESC(S("Surface Area:")) .. " " .. jc_realestate.area(id) .. " m²]" ..
    (group ~= "" and "label[0.5,4.0;" .. ESC(S("Group:")) .. " " .. ESC(group) .. "]" or "") ..
    "button_exit[0.2,5.5;3,1;Quit;" .. ESC(S("Quit")) .. "]" ..
    "button[4.7,5.5;3,1;buy;" .. ESC(S("Buy")) .. "]"

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
    meta:set_string("infotext", S("Locked Chest (owned by @1)", new_owner) )
    return
  end

  if starts_with(node.name, "doors:door_steel_") then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Steel Door\nOwned by @1", new_owner) )
    return
  end

  if node.name == "technic:iron_locked_chest"
    or node.name == "technic:copper_locked_chest"
    or node.name == "technic:silver_locked_chest"
    or node.name == "technic:gold_locked_chest"
    or node.name == "technic:mithril_locked_chest" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Locked Chest (owned by @1)", new_owner) )
    return
  end

  if node.name == "inbox:empty" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Mailbox of @1", new_owner) )
    return
  end

  if node.name == "itemframes:frame" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Item frame (owned by @1)", new_owner) )
    return
  end

  if node.name == "itemframes:pedestral" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Pedestral frame (owned by @1)", new_owner) )
    return
  end

  if node.name == "currency:safe" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Safe (owned by @1)", new_owner ) )
    return
  end

  if node.name == "currency:shop" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Exchange shop (owned by @1)", new_owner ) )
    return
  end

  if node.name == "bitchange:bank" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Bank (owned by @1)", new_owner ) )
    return
  end

  if node.name == "bitchange:moneychanger" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Moneychanger (owned by @1)", new_owner ) )
    return
  end

  if node.name == "bitchange:warehouse" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Warehouse (owned by @1)", new_owner) )
    return
  end

  if node.name == "bitchange:shop" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)

    if meta:get_string("title") ~= "" then
      meta:set_string("infotext", S("Exchange shop \"@1\" (@2)", meta:get_string("title"), new_owner ) )
    else
      meta:set_string("infotext", S("Exchange shop (@1)", new_owner) )
    end

    return
  end

  if node.name == "locked_sign:sign_wall_locked" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Wall Sign (@1)", new_owner) )
    return
  end

  if node.name == "basic_signs:sign_wall_locked" then
    meta:set_string("owner", new_owner)
    meta:set_string("doors_owner", new_owner)
    meta:set_string("infotext", S("Locked sign, owned by @1", new_owner) )
    return
  end

  if starts_with(node.name, "multidecor:") then
    local def = core.registered_nodes[node.name]

    if def and def.add_properties and def.add_properties.door and def.add_properties.door.has_lock then
      meta:set_string("owner", new_owner)
      meta:set_string("infotext", S("Owned by @1", new_owner) )
      return
    end
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

local function transfer_area(id, buyer, seller, pos, actor, group)
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

  update_area_group(id, group)

  core.set_node(pos, {name = "air"})

  core.chat_send_player(buyer, S("The area has been transferred to you.") )

  return true
end

local function pay_seller(seller, currency, price)
  store_pending_payment(seller, currency, price)

  local seller_player = core.get_player_by_name(seller)

  if seller_player then
    core.chat_send_player(seller, core.colorize("#FFFFFF", S("Real Estate: You have a payment of @1 @2 waiting. Use the command @3 to collect it.", price, get_currency_name(currency), core.colorize("#FFFF00", "/claim_payment") ) ) )
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
    local group = meta:get_string("group")

    if id <= 0 or price <= 0 then
      core.chat_send_player(name, S("This sale point is unconfigured.") )
      return
    end

    if not areas.areas[id] then
      core.chat_send_player(name, S("The area no longer exists."))
      return
    end

    if get_currency_name(currency) == "Unknown" then
      core.chat_send_player(name, S("This sale point has an invalid currency."))
      return
    end

    if owner == "" then
      core.chat_send_player(name, S("This sale point has no owner."))
      return
    end

    if owner == name then
      core.chat_send_player(name, S("You cannot buy your own area."))
      return
    end

    if group ~= "" and player_owns_group(name, group) then
      core.chat_send_player(name, S("You already own a property in the group \"@1\".", group ) )
      return
    end

    local available = count_items(player, currency)

    if available < price then
      core.chat_send_player(name, S("You need @1 @2 to purchase this area. You have @3.", price, get_currency_name(currency), available) )
      return
    end

    if not remove_items(player, currency, price) then
      core.chat_send_player(name, S("Unable to remove the payment from your inventory.") )
      return
    end

    if not transfer_area(id, name, owner, pos, player, group) then
      add_items(player, currency, price)
      core.chat_send_player(name, S("The area could not be transferred.") )
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
      local id = meta:get_int("id")

      if pressed.name then
        id = tonumber(pressed.name)

        if not id then
          core.chat_send_player(name, S("Invalid area number: \"@1\"", pressed.name ) )
          return
        end

        if not areas.areas[id] then
          core.chat_send_player(name, S("No such area with id @1", pressed.name ) )
          return
        end

        if areas.areas[id].owner ~= name then
          core.chat_send_player(name, S("You don't own area id @1", id ) )
          return
        end

        core.chat_send_player(name, S("Selling area @1 [@2]", (areas.areas[id].name or ""), id ) )
        meta:set_int("id", id)

        local group = get_area_group(id)

        if group ~= "" then
          meta:set_string("group", group)
        else
          meta:set_string("group", "")
        end
      end

      --------------------------------------------------------------
      -- Price.
      --------------------------------------------------------------
      if pressed.price then
        local price = tonumber(pressed.price)

        if not price or price < 1 or price ~= math.floor(price) then
          core.chat_send_player(name, S("Price must be a whole number greater than zero.") )
          return
        end

        meta:set_int("price", price)
      end

      --------------------------------------------------------------
      -- Group.
      --------------------------------------------------------------
      local area_group = get_area_group(id)

      if area_group ~= "" then
        meta:set_string("group", area_group)
      elseif pressed.group then
        meta:set_string("group", pressed.group:trim())
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

      meta:set_string("infotext", S("Land for sale by @1 - @2 @3", name, price, get_currency_name(currency) ) )

      core.close_formspec(name, "jc_realestate.setup")

      return
    end
  end
end)

core.register_chatcommand("realestate_clear_group", {
  params = "<groupname> <player>",
  description = S("Remove a player from a real estate group."),
  privs = {server = true},
  func = function(name, param)
    local group, player_name = param:match("^(%S+)%s+(.+)$")

    if not group or not player_name then
      return false, S("Usage: /realestate_clear_group <groupname> <player>")
    end

    player_name = player_name:trim()

    local area_ids = get_group_areas(group)

    for _, area_id in ipairs(area_ids) do
      local area = areas.areas[area_id]

      if area and area.owner == player_name then
        remove_group_area(group, area_id)
        return true, S("Removed @1 from group @2.", player_name, group)
      end
    end

    return false, S("Player @1 does not own an area in group @2.", player_name, group)
  end,
})

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
  description = S("For Sale Sign"),
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