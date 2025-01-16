#!/usr/bin/env lua

--[[
 * A lua library for mtk's wifi driver.
 *
 * Copyright (C) 2019 MediaTek Inc. All Rights Reserved.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License version 2.1
 * as published by the Free Software Foundation
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
]]


require("datconf")
--local ioctl_help = require "ioctl_helper"
local mtkdat = {}
local nixio = require("nixio")
local shuci = require("shuci")

local uciCfgfile = "/etc/config/wireless"
local lastCfgfile = "/tmp/mtk/wifi/wireless.last"

local PHY_11BG_MIXED = 0
local PHY_11B = 1
local PHY_11A = 2
local PHY_11ABG_MIXED = 3
local PHY_11G = 4
local PHY_11ABGN_MIXED = 5
local PHY_11N_2_4G = 6
local PHY_11GN_MIXED = 7
local PHY_11AN_MIXED = 8
local PHY_11BGN_MIXED = 9
local PHY_11AGN_MIXED = 10
local PHY_11N_5G = 11
local PHY_11VHT_N_ABG_MIXED = 12
local PHY_11VHT_N_AG_MIXED = 13
local PHY_11VHT_N_A_MIXED = 14
local PHY_11VHT_N_MIXED = 15
local PHY_11AX_24G = 16
local PHY_11AX_5G = 17
local PHY_11AX_6G = 18
local PHY_11AX_24G_6G = 19
local PHY_11AX_5G_6G = 20
local PHY_11AX_24G_5G_6G = 21
local PHY_11BE_24G = 22
local PHY_11BE_5G = 23
local PHY_11BE_6G = 24
local PHY_11BE_24G_6G = 25
local PHY_11BE_5G_6G = 26
local PHY_11BE_24G_5G_6G = 27

local HT_BW_20 = 0
local HT_BW_40 = 1

local VHT_BW_2040 = 0
local VHT_BW_80 = 1
local VHT_BW_160 = 2
local VHT_BW_8080 = 3
local VHT_BW_320 = 4

local EHT_BW_20 = 0
local EHT_BW_2040 = 1
local EHT_BW_80 = 2
local EHT_BW_160 = 3
local EHT_BW_320 = 4

local l1dat_parser = {
    L1_DAT_PATH = "/etc/wireless/l1profile.dat",
    IF_RINDEX = "ifname_ridx",
    DEV_RINDEX = "devname_ridx",
    MAX_NUM_APCLI = 1,
    MAX_NUM_WDS = 4,
    MAX_NUM_MESH = 1,
    MAX_NUM_EXTIF = 16,
    MAX_NUM_DBDC_BAND = 2,
}

local l1cfg_options = {
            ext_ifname="",
            apcli_ifname="apcli",
            wds_ifname="wds",
            mesh_ifname="mesh"
      }


--util functions
local function __cfg2list(str)
    -- delimeter == ";"
    local i = 1
    local list = {}
    if str == nil then return list end
    for k in string.gmatch(str, "([^;]+)") do
        list[i] = k
        i = i + 1
    end
    return list
end

function mtkdat.split(s, delimiter)
    if s == nil then s = "" end
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

function mtkdat.exist(path)
    if path == nil then return false end
    local fp = io.open(path, "rb")
    if fp then fp:close() end
    return fp ~= nil
end

function mtkdat.trim(s)
  if s then return (s:gsub("^%s*(.-)%s*$", "%1")) end
end

function mtkdat.uci_load(filename)
    return shuci.decode(filename)
end

local function uci_apply_wireless_mlo_vif(uci_cfg, uci_mld, ap_id_table, sta_id_table)
    if uci_mld.disabled == '1' then
        return
    end

    if uci_mld.mode == nil or
       ( string.lower(uci_mld.mode) ~= "sta" and
         string.lower(uci_mld.mode) ~= "ap" ) then
        return
    end

    local mode = string.lower(uci_mld.mode)

    if uci_mld.iface == nil then
        return
    end

    local ifaces = mtkdat.split(uci_mld.iface, " ")
    if ifaces == nil or #ifaces == 0 then
        return
    end

    local sta_main_idx = 1
    local idx
    local vifname
    local group

    if mode == "sta" then
        if uci_mld.main_iface ~= nil then
            for idx, vifname in pairs(ifaces) do
                if vifname == uci_mld.main_iface then
                    sta_main_idx = idx
                end
            end
        end
    end
    if uci_mld.mldgroup == nil then
        if mode == "ap" then
            uci_mld.mldgroup = table.remove(ap_id_table)
        elseif mode == "sta" then
            uci_mld.mldgroup = table.remove(sta_id_table)
        end
    end
    if uci_mld.mldgroup == nil then
        return
    end
    group = uci_mld.mldgroup

    for idx, vifname in pairs(ifaces) do
        local uci_vif = mtkdat.get_uci_vif_by_vif_name(uci_cfg, vifname)
        local uci_dev = mtkdat.get_uci_dev_by_dev_name(uci_cfg, uci_vif.device)

        if uci_vif ~= nil and
           uci_vif.mode == mode and
           string.find(uci_mld._device_list, uci_vif.device) == nil and
           string.find(uci_dev.htmode, "EHT") ~= nil then

            if mode == "ap" then
                uci_vif.mldgroup = group
            end

            if uci_mld.ssid then
                uci_vif.ssid = uci_mld.ssid
            end

            if mode == "sta" then
                if idx ~= sta_main_idx then
                    uci_vif.network = nil
                    uci_vif.ssid = nil
                end
            end

            if uci_mld.encryption then
                uci_vif.encryption = uci_mld.encryption
                if uci_mld.key then
                    uci_vif.key = uci_mld.key
                end
                if uci_mld.ieee80211w then
                    uci_vif.ieee80211w = uci_mld.ieee80211w
                end
                if uci_mld.pmf_sha256 then
                    uci_vif.pmf_sha256 = uci_mld.pmf_sha256
                end
                if uci_mld.sae_password then
                    uci_vif.sae_password = uci_mld.sae_password
                end
            end
            uci_mld._device_list = uci_mld._device_list.." "..uci_vif.device
        end
    end
end

local function uci_apply_wireless_mlo(uci_cfg)
    local ap_multi_link_mld_group_id_table = {}
    local sta_multi_link_mld_group_id_table = {}
    local i

    for i = 16, 1, -1 do
        table.insert(ap_multi_link_mld_group_id_table, tostring(i))
        table.insert(sta_multi_link_mld_group_id_table, tostring(i))
    end
    if uci_cfg["wifi-mld"] ~= nil then
        for _, uci_mld in pairs(uci_cfg["wifi-mld"]) do
            if uci_mld ~= nil then
                uci_mld._device_list = ""
                uci_apply_wireless_mlo_vif(uci_cfg, uci_mld,
                    ap_multi_link_mld_group_id_table,
                    sta_multi_link_mld_group_id_table)
            end
        end
    end
    for _, uci_vif in pairs(uci_cfg["wifi-iface"]) do
        if uci_vif.mode == "ap" and
           uci_vif.mldgroup == nil and
           ( uci_vif.disabled == "0" or uci_vif.disabled == nil ) then
            uci_vif.mldgroup = "0"
        end
    end
end

function mtkdat.uci_load_wireless()
    local uci_cfg

    uci_cfg = mtkdat.uci_load(uciCfgfile)
    uci_apply_wireless_mlo(uci_cfg)

    return uci_cfg
end

function mtkdat.get_uci_dev_by_dev_name(uci, devname)
    for _, dev in pairs(uci["wifi-device"]) do
        if dev[".name"] == devname then
            return dev
        end
    end
    return nil
end

function mtkdat.get_uci_vif_by_vif_name(uci, vifname)
    for _, vif in pairs(uci["wifi-iface"]) do
        if vif[".name"] == vifname then
            return vif
        end
    end
    return nil
end

function mtkdat.get_uci_vifs_by_dev_name(uci, devname)
    local vifs = {}

    for vifname, vif in pairs(uci["wifi-iface"]) do
        if vif.device == devname then
            if tonumber(vif.vifidx) then
                vifs[tonumber(vif.vifidx)] = vif
            end
        end
    end

    for vifname, vif in pairs(uci["wifi-iface"]) do
        if vif.device == devname then
            if tonumber(vif.vifidx) == nil  then
                vifs[#vifs+1] = vif
            end
        end
    end

    return vifs
end


function mtkdat.get_uci_mld_by_vif_name(uci, vifname)
    if uci["wifi-mld"] == nil then
        return nil
    end

    for _, uci_mld in pairs(uci["wifi-mld"]) do
        local ifaces = mtkdat.split(uci_mld.iface, " ")
        for i = 1, #ifaces do
            if ifaces[i] == vifname then
                return uci_mld
            end
        end
    end

    return nil
end

function mtkdat.check_if_sta_mld_all_members_up(uci, uci_mld)
    if uci_mld == nil then
        return 0
    end

    local main_iface = uci_mld.main_iface

    local ifaces = mtkdat.split(uci_mld.iface, " ")

    if ifaces == nil or #ifaces == 0 then
        return 0
    end

    if main_iface == nil then
        main_iface = ifaces[1]
    end

    for i = 1, #ifaces do
        if ifaces[i] ~= main_iface then
            local uci_vif = mtkdat.get_uci_vif_by_vif_name(uci, ifaces[i])
            if uci_vif and (uci_vif.disabled == nil or uci_vif.disabled == "0") then
                local result = mtkdat.read_pipe("ifconfig "..ifaces[i])
                if string.find(result, "UP") == nil then
                    return 0
                end
            end
        end
    end
    return 1
end

function mtkdat.get_uci_sta_mld_main_iface(uci, uci_mld)
    if uci_mld == nil then
        return nil
    end

    if uci_mld.main_iface then
        return mtkdat.get_uci_vif_by_vif_name(uci, uci_mld.main_iface)
    end

    if uci_mld.iface == nil then
        return nil
    end

    local ifaces = mtkdat.split(uci_mld.iface, " ")

    if ifaces == nil or #ifaces == 0 then
        return nil
    end

    return mtkdat.get_uci_vif_by_vif_name(uci, ifaces[1])
end

local function token_set(str, n, v)
    -- n start from 1
    -- delimeter == ";"
    if not str then str = "" end
    if not v then v = "" end
    local tmp = __cfg2list(str)
    if type(v) ~= type("") and type(v) ~= type(0) then
        return
    end
    if #tmp < tonumber(n) then
        for i=#tmp, tonumber(n) do
            if not tmp[i] then
                tmp[i] = v -- pad holes with v !
            end
        end
    else
        tmp[n] = v
    end
    return table.concat(tmp, ";"):gsub("^;*(.-);*$", "%1"):gsub(";+",";")
end


local function token_get(str, n, v)
    -- n starts from 1
    -- v is the backup in case token n is nil
    if not str then return v end
    local tmp = __cfg2list(str)
    return tmp[tonumber(n)] or v
end

local function __lines(str)
    local t = {}
    local function helper(line) table.insert(t, line) return "" end
    helper((str:gsub("(.-)\r?\n", helper)))
    return t
end

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function mtkdat.spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys, order)
    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

local function mode2band(mode)
    local i = tonumber(mode)
    if i == PHY_11BG_MIXED or
       i == PHY_11B or
       i == PHY_11G or
       i == PHY_11N_2_4G or
       i == PHY_11GN_MIXED or
       i == PHY_11BGN_MIXED or
       i == PHY_11AX_24G or
       i == PHY_11BE_24G then
        return "2.4G"
    elseif i == PHY_11A or
           i == PHY_11ABG_MIXED or
           i == PHY_11ABGN_MIXED or
           i == PHY_11AN_MIXED or
           i == PHY_11AGN_MIXED or
           i == PHY_11N_5G or
           i == PHY_11VHT_N_ABG_MIXED or
           i == PHY_11VHT_N_AG_MIXED or
           i == PHY_11VHT_N_A_MIXED or
           i == PHY_11VHT_N_MIXED or
           i == PHY_11AX_5G or
           i == PHY_11BE_5G then
	return "5G"
    elseif i == PHY_11AX_6G or
           i == PHY_11AX_24G_6G or
           i == PHY_11AX_5G_6G or
           i == PHY_11AX_24G_5G_6G or
           i == PHY_11BE_6G or
           i == PHY_11BE_24G_6G or
           i == PHY_11BE_5G_6G or
           i == PHY_11BE_24G_5G_6G then
        return "6G"
    end
end

function mtkdat.read_pipe(pipe)
    local retry_count = 10
    local fp, txt, err
    repeat  -- fp:read() may return error, "Interrupted system call", and can be recovered by doing it again
        fp = io.popen(pipe)
        txt, err = fp:read("*a")
        fp:close()
        retry_count = retry_count - 1
    until err == nil or retry_count == 0
    return txt
end

local function table_clone(org)
    local copy = {}
    for k, v in pairs(org) do
        copy[k] = v
    end
    return copy
end

local function set_dat_cfg(datfile, cfg, val)
    datobj = datconf.openfile(datfile)
    if datobj then
        datobj:set(cfg, val)
        datobj:commit()
        datobj:close()
    end
end

local function get_dat_cfg(datfile, cfg)
    local val
    datobj = datconf.openfile(datfile)
    if datobj then
        val = datobj:get(cfg)
        datobj:close()
    end

    return val
end

local function get_file_lines(fileName)
    local fd = io.open(fileName, "r")
    if not fd then return end
    local content = fd:read("*all")
    fd:close()
    return __lines(content)
end

local function write_file_lines(fileName, lines)
    local fd = io.open(fileName, "w")
    if not fd then return end
    for _, line in pairs(lines) do
        fd:write(line..'\n')
    end
    fd:close()
end

local function file_is_diff(file1, file2)
    local l1 = get_file_lines(file1)
    local l2 = get_file_lines(file2)

    if (#l1 ~= #l2) then return true end

    for k, v in pairs(l1) do
        if (l1[k] ~= l2[k]) then
            return true
        end
    end

    return false
end

key = ""
local function print_table(table , level)
  level = level or 1
  local indent = ""
  for i = 1, level do
    indent = indent.."  "
  end

  if key ~= "" then
    --print(indent..key.." ".."=".." ".."{")
    print(key.." ".."=".." ".."{")
  else
    --print(indent .. "{")
    print("{")
  end

  key = ""
  for k,v in pairs(table) do
     if type(v) == "table" then
        key = k
        print_table(v, level + 1)
     else
        local content = string.format("%s%s = %s", indent .. "  ",tostring(k), tostring(v))
      print(content)
      end
  end
  print(indent .. "}")

end


local function add_default_value(l1cfg)
    for k, v in ipairs(l1cfg) do

        for opt, default in pairs(l1cfg_options) do
            if ( opt == "ext_ifname" ) then
                v[opt] = v[opt] or v["main_ifname"].."_"
            else
                v[opt] = v[opt] or default..k.."_"
            end
        end
    end

    return l1cfg
end

local function get_value_by_idx(devidx, mainidx, subidx, key)
    --print("Enter get_value_by_idx("..devidx..","..mainidx..", "..subidx..", "..key..")<br>")
    if not devidx or not mainidx or not key then return end

    local devs = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    if not devs then return end

    local dev_ridx = l1dat_parser.DEV_RINDEX
    local sidx = subidx or 1
    local devname1  = devidx.."."..mainidx
    local devname2  = devidx.."."..mainidx.."."..sidx

    --print("devnam1=", devname1, "devname2=", devname2, "<br>")
    return devs[dev_ridx][devname2] and devs[dev_ridx][devname2][key]
           or devs[dev_ridx][devname1] and devs[dev_ridx][devname1][key]
end

-- path to zone is 1 to 1 mapping
local function l1_path_to_zone(path)
    --print("Enter l1_path_to_zone("..path..")<br>")
    if not path then return end

    local devs = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    if not devs then return end

    for _, dev in pairs(devs[l1dat_parser.IF_RINDEX]) do
        if dev.profile_path == path then
            return dev.nvram_zone
        end
    end

    return
end

-- zone to path is 1 to n mapping
local function l1_zone_to_path(zone)
    if not zone then return end

    local devs = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    if not devs then return end

    local plist = {}
    for _, dev in pairs(devs[l1dat_parser.IF_RINDEX]) do
        if dev.nvram_zone == zone then
            if not next(plist) then
                table.insert(plist,dev.profile_path)
            else
                local plist_str = table.concat(plist)
                if not plist_str:match(dev.profile_path) then
                    table.insert(plist,dev.profile_path)
                end
            end
        end
    end

    return next(plist) and plist or nil
end

local function l1_ifname_to_datpath(ifname)
    if not ifname then return end

    local devs = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    if not devs then return end

    local ridx = l1dat_parser.IF_RINDEX
    return devs[ridx][ifname] and devs[ridx][ifname].profile_path
end

local function l1_ifname_to_zone(ifname)
    if not ifname then return end

    local devs = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    if not devs then return end

    local ridx = l1dat_parser.IF_RINDEX
    return devs[ridx][ifname] and devs[ridx][ifname].nvram_zone
end

local function l1_zone_to_ifname(zone)
    if not zone then return end

    local devs = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    if not devs then return end

    local zone_dev
    for _, dev in pairs(devs[l1dat_parser.DEV_RINDEX]) do
        if dev.nvram_zone == zone then
            zone_dev = dev
        end
    end

    if not zone_dev  then
        return nil
    else
        return zone_dev.main_ifname, zone_dev.ext_ifname, zone_dev.apcli_ifname, zone_dev.wds_ifname, zone_dev.mesh_ifname
    end
end

function load_band_profile(path)
    local MacAddress
    local E2pAccessMode
    local TestModeEn
    local band_profile_paths = {}
    local fd = io.open(path, "r")

    if fd == nil then
        return
    end

    for line in fd:lines() do
        line = mtkdat.trim(line)
        if string.byte(line) ~= string.byte("#") then
            local i = string.find(line, "=")
            if i then
                local k, v, k1
                k = mtkdat.trim( string.sub(line, 1, i-1) )
                v = mtkdat.trim( string.sub(line, i+1) )
                k1 = string.match(k, "BN(%d+)_profile_path")
                if k1 then
                    band_profile_paths[#band_profile_paths + 1] = v
                elseif k == "MacAddress" then
                    MacAddress = v
                elseif k == "E2pAccessMode" then
                    E2pAccessMode = v
                elseif k == "TestModeEn" then
                    TestModeEn = v
                end
            end
        end
    end
    fd:close()

    return band_profile_paths, MacAddress, E2pAccessMode, TestModeEn
end


-- input: L1 profile path.
-- output A table, devs, contains
--   1. devs[%d] = table of each INDEX# in the L1 profile
--   2. devs.ifname_ridx[ifname]
--         = table of each ifname and point to relevant contain in dev[$d]
--   3. devs.devname_ridx[devname] similar to devs.ifnameridx, but use devname.
--      devname = INDEX#_value.mainidx(.subidx)
-- Using *_ridx do not need to handle name=k1;k2 case of DBDC card.
function load_l1_profile(path)
    local devs = setmetatable({}, {__index=
                     function(tbl, key)
                           local util = require("luci.util")
                           --print("metatable function:", util.serialize_data(tbl), key)
                           --print("-----------------------------------------------")
                           if ( string.match(key, "^%d+")) then
                               tbl[key] = {}
                               return tbl[key]
                           end
                     end
                 })
    local chipset_num = {}
    local dir = io.popen("ls /etc/wireless/")
    if not dir then return end
    local fd = io.open(path, "r")
    if not fd then return end

    -- convert l1 profile into lua table
    local l1_profiles = {}
    for line in fd:lines() do
        line = mtkdat.trim(line)
        if string.byte(line) ~= string.byte("#") then
            local i = string.find(line, "=")
            if i then
                local k, v, k1, k2
                k = mtkdat.trim( string.sub(line, 1, i-1) )
                v = mtkdat.trim( string.sub(line, i+1) )
                k1, k2 = string.match(k, "INDEX(%d+)_(.+)")
                if k1 then
                    k1 = tonumber(k1) + 1
                    if k2 == "main_ifname" or
                       k2 == "ext_ifname" or
                       k2 == "wds_ifname" or
                       k2 == "apcli_ifname" or
                       k2 == "mesh_ifname" or
                       k2 == "nvram_zone" then
                        l1_profiles[#l1_profiles][k2] = mtkdat.split(v, ";")
                    else
                        l1_profiles[#l1_profiles][k2] = v
                    end
                else
                    k1 = string.match(k, "INDEX(%d+)")
                    if k1 then
                        local chip = {}
                        k1 = tonumber(k1) + 1
                        chip["INDEX"] = v
                        chipset_num[v] = (not chipset_num[v] and 1) or chipset_num[v] + 1
                        l1_profiles[#l1_profiles + 1] = chip
                        l1_profiles[#l1_profiles]["mainidx"] = chipset_num[v]
                    end
                end
            else
                nixio.syslog("warning", "skip line without '=' "..line)
            end
        else
            nixio.syslog("warning", "skip comment line "..line)
        end
    end
    fd:close()

    local per_band_profile = false
    for i = 1, table.getn(l1_profiles) do
        if l1_profiles[i].profile_path then
            band_profile_path, MacAddress, E2pAccessMode, TestModeEn = load_band_profile(l1_profiles[i]["profile_path"])
            if band_profile_path and table.getn(band_profile_path) > 0 then
                l1_profiles[i]["band_profile_path"] = band_profile_path
                l1_profiles[i]["MacAddress"] = MacAddress
                l1_profiles[i]["E2pAccessMode"] = E2pAccessMode
                l1_profiles[i]["TestModeEn"] = TestModeEn
                per_band_profile = true
            else
                band_profile_path = {}
                table.insert(band_profile_path, l1_profiles[i]["profile_path"])
                l1_profiles[i]["band_profile_path"] = band_profile_path
            end
        end
    end

    local devs = {}
    for i = 1, table.getn(l1_profiles) do
        local band_num = table.getn(l1_profiles[i]["band_profile_path"])
        for j = 1,  band_num do
            local dev = {}

            for option, value in pairs(l1_profiles[i]) do
                if option == "band_profile_path" then
                elseif option == "profile_path" then
                   dev["profile_path"] = l1_profiles[i]["band_profile_path"][j]
                elseif option == "main_ifname" or
                       option == "ext_ifname" or
                       option == "wds_ifname" or
                       option == "apcli_ifname" or
                       option == "mesh_ifname" or
                       option == "nvram_zone" then
                        if per_band_profile or #l1_profiles[i][option] < 2 then
                            dev[option] = l1_profiles[i][option][j]
                        else
                            --legacy DBDC, option is separated by semicolons, ex: ra0;rax0
                            local ii
                            for ii=1, #l1_profiles[i][option] do
                                dev[option]=token_set(dev[option], ii, l1_profiles[i][option][ii])
                            end
                        end
                else
                   dev[option] = value
                end

                if band_num > 1 then
                    dev["subidx"] = j
                end
            end
            devs[#devs + 1] = dev
        end
    end

    add_default_value(devs)
    --local util = require("luci.util")
    --local seen2 = {}
    -- print("Before setup ridx", util.serialize_data(devs, seen2))

    -- Force to setup reverse indice for quick search.
    -- Benifit:
    --   1. O(1) search with ifname, devname
    --   2. Seperate DBDC name=k1;k2 format in the L1 profile into each
    --      ifname, devname.
    local dbdc_if = {}
    local ridx = l1dat_parser.IF_RINDEX
    local dridx = l1dat_parser.DEV_RINDEX
    local band_num = l1dat_parser.MAX_NUM_DBDC_BAND
    local k, v, dev, i , j, last
    local devname
    devs[ridx] = {}
    devs[dridx] = {}
    for _, dev in ipairs(devs) do
        dbdc_if[band_num] = token_get(dev.main_ifname, band_num, nil)
        if dbdc_if[band_num] then
            for i = 1, band_num - 1 do
                dbdc_if[i] = token_get(dev.main_ifname, i, nil)
            end
            for i = 1, band_num do
                devs[ridx][dbdc_if[i]] = {}
                devs[ridx][dbdc_if[i]]["subidx"] = i

                for k, v in pairs(dev) do
                    if  k == "INDEX" or k == "EEPROM_offset" or k == "EEPROM_size"
                       or k == "mainidx" then
                        devs[ridx][dbdc_if[i]][k] = v
                    else
                        devs[ridx][dbdc_if[i]][k] = token_get(v, i, "")
                    end
                end
                devname = dev.INDEX.."."..dev.mainidx.."."..devs[ridx][dbdc_if[i]]["subidx"]
                devs[dridx][devname] = devs[ridx][dbdc_if[i]]
            end

            local apcli_if, wds_if, ext_if, mesh_if = {}, {}, {}, {}

            for i = 1, band_num do
                ext_if[i] = token_get(dev.ext_ifname, i, nil)
                apcli_if[i] = token_get(dev.apcli_ifname, i, nil)
                wds_if[i] = token_get(dev.wds_ifname, i, nil)
                mesh_if[i] = token_get(dev.mesh_ifname, i, nil)
            end

            for i = 1, l1dat_parser.MAX_NUM_EXTIF - 1 do -- ifname idx is from 0
                for j = 1, band_num do
                    devs[ridx][ext_if[j]..i] = devs[ridx][dbdc_if[j]]
                end
            end

            for i = 0, l1dat_parser.MAX_NUM_APCLI - 1 do
                for j = 1, band_num do
                    devs[ridx][apcli_if[j]..i] = devs[ridx][dbdc_if[j]]
                end
            end

            for i = 0, l1dat_parser.MAX_NUM_WDS - 1 do
                for j = 1, band_num do
                    devs[ridx][wds_if[j]..i] = devs[ridx][dbdc_if[j]]
                end
            end

            for i = 0, l1dat_parser.MAX_NUM_MESH - 1 do
                for j = 1, band_num do
                    if mesh_if[j] then
                        devs[ridx][mesh_if[j]..i] = devs[ridx][dbdc_if[j]]
                    end
                end
            end

        else
            devs[ridx][dev.main_ifname] = dev

            if dev.subidx then
                devname = dev.INDEX.."."..dev.mainidx.."."..dev.subidx
            else
                devname = dev.INDEX.."."..dev.mainidx
            end
            devs[dridx][devname] = dev

            for i = 1, l1dat_parser.MAX_NUM_EXTIF - 1 do  -- ifname idx is from 0
                devs[ridx][dev.ext_ifname..i] = dev
            end

            for i = 0, l1dat_parser.MAX_NUM_APCLI - 1 do  -- ifname idx is from 0
                devs[ridx][dev.apcli_ifname..i] = dev
            end

            for i = 0, l1dat_parser.MAX_NUM_WDS - 1 do  -- ifname idx is from 0
                devs[ridx][dev.wds_ifname..i] = dev
            end

            for i = 0, l1dat_parser.MAX_NUM_MESH - 1 do  -- ifname idx is from 0
                devs[ridx][dev.mesh_ifname..i] = dev
            end
        end
    end

    return devs
end



function mtkdat.create_link_for_nvram( )
    local devs = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    if not mtkdat.exist("/tmp/mtk/wifi") then
        os.execute("mkdir -p /tmp/mtk/wifi/")
    end

    for devname, dev in pairs(devs.devname_ridx) do
        local dev = devs.devname_ridx[devname]
        local profile = dev.profile_path
        os.execute("ln -sf "..profile.." /tmp/mtk/wifi/"..dev.nvram_zone)
    end
end


local function get_table_length(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end



function mtkdat.__get_l1dat()
    l1dat = load_l1_profile(l1dat_parser.L1_DAT_PATH)

    return l1dat, l1dat_parser
end

function mtkdat.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[mtkdat.deepcopy(orig_key)] = mtkdat.deepcopy(orig_value)
        end
        setmetatable(copy, mtkdat.deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


function mtkdat.detect_first_card()
    local profiles = mtkdat.search_dev_and_profile()
    for _, profile in mtkdat.spairs(profiles, function(a,b) return string.upper(a) < string.upper(b) end) do
        return profile
    end
end

function mtkdat.load_profile(path, raw)
    local cfgs = {}

    cfgobj = datconf.openfile(path)
    if cfgobj then
        cfgs = cfgobj:getall()
        cfgobj:close()
    elseif raw then
        cfgs = datconf.parse(raw)
    end

    return cfgs
end


local function save_easymesh_profile_to_nvram()
    if not pcall(require, "mtknvram") then
        return
    end
    local nvram = require("mtknvram")
    local merged_easymesh_dev1_path = "/tmp/mtk/wifi/merged_easymesh_dev1.dat"
    local l1dat = load_l1_profile(l1dat_parser.L1_DAT_PATH)
    local dev1_profile_paths
    local dev1_profile_path_table = l1_zone_to_path("dev1")
    if not next(dev1_profile_path_table) then
        return
    end
    dev1_profile_paths = table.concat(dev1_profile_path_table, " ")
    -- Uncomment below two statements when there is sufficient space in dev1 NVRAM zone to store EasyMesh Agent's BSS Cfgs Settings.
    -- mtkdat.__prepare_easymesh_bss_nvram_cfgs()
    -- os.execute("cat "..dev1_profile_paths.." "..mtkdat.__read_easymesh_profile_path().." "..mtkdat.__easymesh_bss_cfgs_nvram_path().." > "..merged_easymesh_dev1_path.." 2>/dev/null")
    -- Comment or remove below line once above requirement is met.
    os.execute("cat "..dev1_profile_paths.." "..mtkdat.__read_easymesh_profile_path().." > "..merged_easymesh_dev1_path.." 2>/dev/null")
    nvram.nvram_save_profile(merged_easymesh_dev1_path, "dev1")
end

function mtkdat.save_profile(cfgs, path)

    if not cfgs then
        nixio.syslog("err", "configuration was empty, nothing saved")
        return
    end

    -- Keep a backup of last profile settings
    -- if string.match(path, "([^/]+)\.dat") then
       -- os.execute("cp -f "..path.." "..mtkdat.__profile_previous_settings_path(path))
    -- end
    local datobj = datconf.openfile(path)
    datobj:merge(cfgs)
    datobj:close(true) -- means close and commit

    if pcall(require, "mtknvram") then
        local nvram = require("mtknvram")
        local l1dat = load_l1_profile(l1dat_parser.L1_DAT_PATH)
        local zone = l1_path_to_zone(path)

        if pcall(require, "map_helper") and zone == "dev1" then
            save_easymesh_profile_to_nvram()
        else
            if not l1dat then
                nixio.syslog("debug", "save_profile: no l1dat")
                nvram.nvram_save_profile(path)
            else
                if zone then
                    nixio.syslog("debug", "save_profile "..path.." "..zone)
                    nvram.nvram_save_profile(path, zone)
                else
                    nixio.syslog("debug", "save_profile "..path)
                    nvram.nvram_save_profile(path)
                end
            end
        end
    end
end



-- update path1 by path2
local function update_profile(path1, path2)
    local cfg1 = datconf.openfile(path1)
    local cfg2 = datconf.openfile(path2)

    cfg1:merge(cfg2:getall())
    cfg1:close(true)
    cfg2:close()
end


function mtkdat.__profile_previous_settings_path(profile)
    assert(type(profile) == "string")
    local bak = "/tmp/mtk/wifi/"..string.match(profile, "([^/]+)\.dat")..".last"
    if not mtkdat.exist("/tmp/mtk/wifi") then
        os.execute("mkdir -p /tmp/mtk/wifi")
    end
    return bak
end

function mtkdat.__profile_applied_settings_path(profile)
    assert(type(profile) == "string")
    local bak

    if not mtkdat.exist("/tmp/mtk/wifi") then
        os.execute("mkdir -p /tmp/mtk/wifi")
    end

    if string.match(profile, "([^/]+)\.dat") then
        bak = "/tmp/mtk/wifi/"..string.match(profile, "([^/]+)\.dat")..".applied"
    elseif string.match(profile, "([^/]+)\.txt") then
        bak = "/tmp/mtk/wifi/"..string.match(profile, "([^/]+)\.txt")..".applied"
    elseif string.match(profile, "([^/]+)$") then
        bak = "/tmp/mtk/wifi/"..string.match(profile, "([^/]+)$")..".applied"
    else
        bak = ""
    end

    return bak
end

-- if path2 is not given, use backup of path1.
function mtkdat.diff_profile(path1, path2)
    assert(path1)
    if not path2 then
        path2 = mtkdat.__profile_applied_settings_path(path1)
        if not mtkdat.exist(path2) then
            return {}
        end
    end
    assert(path2)

    local cfg1
    local cfg2
    local diff = {}
    if path1 == mtkdat.__easymesh_bss_cfgs_path() then
        cfg1 = get_file_lines(path1) or {}
        cfg2 = get_file_lines(path2) or {}
    else
        cfg1 = mtkdat.load_profile(path1) or {}
        cfg2 = mtkdat.load_profile(path2) or {}
    end

    for k,v in pairs(cfg1) do
        if cfg2[k] ~= cfg1[k] then
            diff[k] = {cfg1[k] or "", cfg2[k] or ""}
        end
    end

    for k,v in pairs(cfg2) do
        if cfg2[k] ~= cfg1[k] then
            diff[k] = {cfg1[k] or "", cfg2[k] or ""}
        end
    end

    return diff
end

local function diff_config(cfg1, cfg2)
    local diff = {}

    for k,v in pairs(cfg1) do
        if cfg2[k] ~= v and not (cfg2[k] == nil and v == '') then
            diff[k] = v
        end
    end

    return diff
end


local function search_dev_and_profile_orig()
    local nixio = require("nixio")
    local dir = io.popen("ls /etc/wireless/")
    if not dir then return end
    local result = {}
    -- case 1: mt76xx.dat (best)
    -- case 2: mt76xx.n.dat (multiple card of same dev)
    -- case 3: mt76xx.n.nG.dat (case 2 plus dbdc and multi-profile, bloody hell....)
    for line in dir:lines() do
        -- nixio.syslog("debug", "scan "..line)
        local tmp = io.popen("find /etc/wireless/"..line.." -type f -name \"*.dat\"")
        for datfile in tmp:lines() do
            -- nixio.syslog("debug", "test "..datfile)

            repeat do
            -- for case 1
            local devname = string.match(datfile, "("..line..").dat")
            if devname then
                result[devname] = datfile
                -- nixio.syslog("debug", "yes "..devname.."="..datfile)
                break
            end
            -- for case 2
            local devname = string.match(datfile, "("..line.."%.%d)%.dat")
            if devname then
                result[devname] = datfile
                break
            end
            -- for case 3
            local devname = string.match(datfile, "("..line.."%.%d%.%dG)%.dat")
            if devname then
                result[devname] = datfile
                -- nixio.syslog("debug", "yes "..devname.."="..datfile)
                break
            end
            end until true
        end
    end

    for k,v in pairs(result) do
        nixio.syslog("debug", "search_dev_and_profile_orig: "..k.."="..v)
    end

    return result
end

local function search_dev_and_profile_l1()
    local l1dat = load_l1_profile(l1dat_parser.L1_DAT_PATH)

    if not l1dat then return end

    local nixio = require("nixio")
    local result = {}
    local dbdc_2nd_if = ""

    for k, dev in ipairs(l1dat) do
        dbdc_2nd_if = token_get(dev.main_ifname, 2, nil)
        if dbdc_2nd_if then
            result[dev["INDEX"].."."..dev["mainidx"]..".1"] = token_get(dev.profile_path, 1, nil)
            result[dev["INDEX"].."."..dev["mainidx"]..".2"] = token_get(dev.profile_path, 2, nil)
        elseif dev["subidx"] then
            result[dev["INDEX"].."."..dev["mainidx"].."."..dev["subidx"]] = dev.profile_path
        else
            result[dev["INDEX"].."."..dev["mainidx"]] = dev.profile_path
        end
    end

    for k,v in pairs(result) do
        nixio.syslog("debug", "search_dev_and_profile_l1: "..k.."="..v)
    end

    return result
end

function mtkdat.search_dev_and_profile()
    return search_dev_and_profile_l1() or search_dev_and_profile_orig()
end

function mtkdat.__read_easymesh_profile_path()
    return "/etc/map/mapd_cfg"
end

function mtkdat.__write_easymesh_profile_path()
    return "/etc/map/mapd_user.cfg"
end

function mtkdat.__easymesh_mapd_profile_path()
    return "/etc/mapd_strng.conf"
end

function mtkdat.__easymesh_bss_cfgs_path()
    return "/etc/map/wts_bss_info_config"
end

function mtkdat.__easymesh_bss_cfgs_nvram_path()
    local p = "/tmp/mtk/wifi/wts_bss_info_config.nvram"
    if not mtkdat.exist("/tmp/mtk/wifi") then
        os.execute("mkdir -p /tmp/mtk/wifi")
    end
    return p
end

local function get_iface_prefix(ifname)
    assert(ifname ~= nil)
    local prefix
    local i  = string.find(ifname, "%d+")
    if i ~= nil then
        prefix = string.sub(ifname, 0, i-1)
        i = string.sub(ifname, i, -1)
        i = tonumber(i)
    end

    return prefix, i
end

local uci_dev_options = {
    "type", "vendor", "txpower", "channel", "channel_grp", "acs_alg", "acs_skiplist", "beacon_int",
    "txpreamble", "band", "bw", "ht_extcha", "ht_txstream", "ht_rxstream",
    "shortslot", "ht_distkip", "bgprotect", "txburst", "region", "country", "aregion",
    "vht_bw_sig", "pktaggregate", "ht_mcs", "e2p_accessmode", "map_mode", "dbdc_mode",
    "etxbfencond", "itxbfen", "mutxrx_enable", "bss_color", "colocated_bssid",
    "twt_support", "individual_twt_support", "he_ldpc", "txop", "dfs_enable",
    "sre_enable", "powerup_enbale", "powerup_cckofdm", "powerup_ht20", "powerup_ht40", "powerup_vht20",
    "powerup_vht40", "powerup_vht80", "powerup_vht160", "vow_airtime_fairness_en",
    "ht_badec", "ht_rdg", "ht_bawinsize", "whnat", "vow_bw_ctrl", "vow_ex_en", "htmode", "wireless_mode", "pure_11b",
    "mbssid", "doth", "dfs_zero_wait", "dfs_dedicated_zero_wait", "dfs_zero_wait_default", "rd_region",
    "psc_acs", "qos_enable", "dabs_vendor_key_bitmap", "dabs_group_key_bitmap",
}

local uci_iface_options = {
    "device", "network", "mode", "disabled", "ssid", "bssid", "vifidx", "hidden", "wmm", "dtim_period",
    "encryption", "key", "key1", "key2", "key3", "key4", "rekey_interval", "rekey_meth",
    "ieee8021x", "auth_server", "auth_port", "auth_secret", "ownip", "idle_timeout", "session_timeout",
    "preauth", "ieee80211w", "pmf_sha256", "wireless_mode", "mldgroup", "tx_rate", "no_forwarding",
    "rts_threshold", "frag_threshold", "apsd_capable", "vht_bw_signal", "vht_ldpc", "vht_stbc", "vht_sgi",
    "ht_ldpc", "ht_stbc","ht_protect", "ht_gi", "ht_opmode", "ht_amsdu", "ht_autoba",
    "igmpsn_enable", "mumimoul_enable", "mumimodl_enable", "muofdmaul_enable", "muofdmadl_enable",
    "vow_group_max_ratio", "vow_group_min_ratio", "vow_airtime_ctrl_en", "vow_group_max_rate", "vow_group_min_rate",
    "vow_rate_ctrl_en", "pmk_cache_period", "wds", "wdslist", "wds0key", "wds1key", "wds2key", "wds3key",
    "wdsencryptype", "wdsphymode", "wps_state", "wps_pin",  "owetrante", "mac_repeateren", "access_policy", "access_list",
    "htmode", "bw", "pure_11b"
}

local uci_mld_options = {
    "disabled", "mode", "iface", "main_iface", "mld_addr", "ssid", "encryption", "sae_password",
    "ieee80211w", "pmf_sha256", "key"
}

local function uci_encode_options(fp, uci_options, cfg_type, tbl)
    fp:write(string.format("config\t%s\t'%s'\n", cfg_type, tbl[".name"]))

    for _, i in pairs(uci_options) do
        if (tbl[i] ~= nil) then
            if type(tbl[i]) == "table" then
                for _, v in pairs(tbl[i]) do
                     fp:write(string.format("\tlist\t%s\t'%s'\n",i,v))
                end
            elseif tbl[i] ~= '' then
                fp:write(string.format("\toption\t%-10s\t'%s'\n", i, tostring(tbl[i])))
            end
        end
    end
    fp:write("\n")
end

local function uci_encode_dev_options(fp, dev)
    uci_encode_options(fp, uci_dev_options, "wifi-device", dev)
end

local function uci_encode_iface_options(fp, iface)
    uci_encode_options(fp, uci_iface_options, "wifi-iface", iface)
end

local function uci_encode_mld_options(fp, mldgroup)
    uci_encode_options(fp, uci_mld_options, "wifi-mld", mldgroup)
end

local function dat2uci_encryption(auth, encr)
    local encryption

    if auth == "OPEN" and encr == "NONE" then
        encryption = "none"
--[[
    elseif auth == "OPEN" and encr == "WEP" then
        encryption = "wep-open"
    elseif auth == "SHARED" and encr == "WEP" then
        encryption = "wep-shared"
    elseif auth == "WEPAUTO" and encr == "WEP" then
        encryption = "wep-auto"
]]
    elseif auth == "WPA" and encr == "TKIP" then
        encryption = "wpa+tkip"
    elseif auth == "WPA" and encr == "TKIPAES" then
        encryption = "wpa+tkip+ccmp"
    elseif auth == "WPA" and encr == "AES" then
        encryption = "wpa+ccmp"
    elseif auth == "WPA2" and encr == "TKIP" then
        encryption = "wpa2+tkip"
    elseif auth == "WPA2" and encr == "TKIPAES" then
        encryption = "wpa2+tkip+ccmp"
    elseif auth == "WPA2" and encr == "AES" then
        encryption = "wpa2+ccmp"
    elseif auth == "WPA3" and encr == "AES" then
        encryption = "wpa3"
    elseif auth == "WPA3-192" and encr == "GCMP256"  then
        encryption = "wpa3-192"
    elseif auth == "WPAPSK" and encr == "AES" then
        encryption = "psk+ccmp"
    elseif auth == "WPAPSK" and encr == "TKIP" then
        encryption = "psk+tkip"
    elseif auth == "WPAPSK" and encr == "TKIPAES" then
        encryption = "psk+tkip+ccmp"
    elseif auth == "WPA2PSK" and encr == "AES" then
        encryption = "psk2+ccmp"
    elseif auth == "WPA2PSK" and encr == "TKIP" then
        encryption = "psk2+tkip"
    elseif auth == "WPA2PSK" and encr == "TKIPAES" then
        encryption = "psk2+tkip+ccmp"
    elseif auth == "WPA3PSK" and encr == "AES" then
        encryption = "sae"
    elseif auth == "WPAPSKWPA2PSK" and encr == "TKIP" then
        encryption = "psk-mixed+tkip"
    elseif auth == "WPAPSKWPA2PSK" and encr == "TKIPAES" then
        encryption = "psk-mixed+tkip+ccmp"
    elseif auth == "WPAPSKWPA2PSK" and encr == "AES" then
        encryption = "psk-mixed+ccmp"
    elseif auth == "WPA2PSKWPA3PSK" and encr == "AES" then
        encryption = "sae-mixed"
    elseif auth == "WPA1WPA2" and encr == "TKIP" then
        encryption = "wpa-mixed+tkip"
    elseif auth == "WPA1WPA2" and encr == "AES" then
        encryption = "wpa-mixed+ccmp"
    elseif auth == "WPA1WPA2" and encr == "TKIPAES" then
        encryption = "wpa-mixed+tkip+ccmp"
    elseif auth == "WPA3WPA2" then
        encryption = "wpa3-mixed"
    elseif auth == "OWE" and encr == "AES" then
        encryption = "owe"
    else
        encryption = "none"
    end

    return encryption
end

local function uci2dat_encryption(encryption)
    local auth
    local encr

    if encryption == "none" then
        auth = "OPEN"
        encr = "NONE"
--[[
    elseif encryption == "wep-open" then
        auth = "OPEN"
        encr = "WEP"
    elseif encryption == "wep-shared" then
        auth = "SHARED"
        encr = "WEP"
    elseif encryption == "wep-auto" then
        auth = "WEPAUTO"
        encr = "WEP"
]]
    elseif encryption == "wpa+tkip" then
        auth = "WPA"
        encr = "TKIP"
    elseif encryption == "wpa+tkip+ccmp" then
        auth = "WPA"
        encr = "TKIPAES"
    elseif encryption == "wpa+ccmp" then
        auth = "WPA"
        encr = "AES"
    elseif encryption == "wpa2+tkip" then
        auth = "WPA2"
        encr = "TKIP"
    elseif encryption == "wpa2+tkip+ccmp" then
        auth = "WPA2"
        encr = "TKIPAES"
    elseif encryption == "wpa2+ccmp" then
        auth = "WPA2"
        encr = "AES"
    elseif encryption == "wpa3" then
        auth = "WPA3"
        encr = "AES"
    elseif encryption == "wpa3-192" then
        auth = "WPA3-192"
        encr = "GCMP256"
    elseif encryption == "psk+ccmp" then
        auth = "WPAPSK"
        encr = "AES"
    elseif encryption == "psk+tkip" then
        auth = "WPAPSK"
        encr = "TKIP"
    elseif encryption == "psk+tkip+ccmp" then
        auth = "WPAPSK"
        encr = "TKIPAES"
    elseif encryption == "psk2+ccmp" then
        auth = "WPA2PSK"
        encr = "AES"
    elseif encryption == "psk2+tkip" then
        auth = "WPA2PSK"
        encr = "TKIP"
    elseif encryption == "psk2+tkip+ccmp" then
        auth = "WPA2PSK"
        encr = "TKIPAES"
    elseif encryption == "sae" then
        auth = "WPA3PSK"
        encr = "AES"
    elseif encryption == "psk-mixed+tkip" then
        auth = "WPAPSKWPA2PSK"
        encr = "TKIP"
    elseif encryption == "psk-mixed+tkip+ccmp" then
        auth = "WPAPSKWPA2PSK"
        encr = "TKIPAES"
    elseif encryption == "psk-mixed+ccmp" then
        auth = "WPAPSKWPA2PSK"
        encr = "AES"
    elseif encryption == "sae-mixed" then
        auth = "WPA2PSKWPA3PSK"
        encr = "AES"
    elseif encryption == "wpa-mixed+tkip" then
        auth = "WPA1WPA2"
        encr = "TKIP"
    elseif encryption == "wpa-mixed+ccmp" then
        auth = "WPA1WPA2"
        encr = "AES"
    elseif encryption == "wpa-mixed+tkip+ccmp" then
        auth = "WPA1WPA2"
        encr = "TKIPAES"
    elseif encryption == "wpa3-mixed" then
        auth = "WPA3WPA2"
        encr = "AES"
    elseif encryption == "owe" then
        auth = "OWE"
        encr = "AES"
    else
        auth = "OPEN"
        encr = "NONE"
    end

    return auth, encr
end

local function uci2hostapd_encryption(encryption, hostapd_cfg)
    assert(hostapd_cfg ~= nil)

    if encryption == "none" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = ''
--[[
    elseif encryption == "wep-open" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '0'
    elseif encryption == "wep-shared" then
        hostapd_cfg.auth_algs = '2'
        hostapd_cfg.wpa = '0'
    elseif encryption == "wep-auto" then
        hostapd_cfg.auth_algs = '3'
        hostapd_cfg.wpa = '0'
]]
    elseif encryption == "wpa+tkip" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '1'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.wpa_pairwise = 'TKIP'
    elseif encryption == "wpa+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '1'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.wpa_pairwise = 'CCMP'
    elseif encryption == "wpa+tkip+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '1'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.wpa_pairwise = 'TKIP CCMP'
    elseif encryption == "wpa2+tkip" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.rsn_pairwise = 'TKIP'
    elseif encryption == "wpa2+tkip+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.rsn_pairwise = 'TKIP CCMP'
    elseif encryption == "wpa2+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    elseif encryption == "wpa3" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP-SUITE-B-192'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    elseif encryption == "wpa3-192" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP-SUITE-B-192'
        hostapd_cfg.rsn_pairwise = 'GCMP-256'
    elseif encryption == "psk+tkip" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '1'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.wpa_pairwise = 'TKIP'
    elseif encryption == "psk+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '1'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.wpa_pairwise = 'CCMP'
    elseif encryption == "psk+tkip+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '1'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.wpa_pairwise = 'TKIP CCMP'
    elseif encryption == "psk2+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    elseif encryption == "psk2+tkip" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.rsn_pairwise = 'TKIP'
    elseif encryption == "psk2+tkip+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.rsn_pairwise = 'TKIP CCMP'
    elseif encryption == "sae" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'SAE'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    elseif encryption == "psk-mixed+tkip" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '3'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.rsn_pairwise = 'TKIP'
    elseif encryption == "psk-mixed+tkip+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '3'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.rsn_pairwise = 'TKIP CCMP'
    elseif encryption == "psk-mixed+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '3'
        hostapd_cfg.wpa_key_mgmt = 'WPA-PSK'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    elseif encryption == "sae-mixed" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'SAE WPA-PSK'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    elseif encryption == "wpa-mixed+tkip" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '3'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.rsn_pairwise = 'TKIP'
    elseif encryption == "wpa-mixed+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '3'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    elseif encryption == "wpa-mixed+tkip+ccmp" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '3'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP'
        hostapd_cfg.rsn_pairwise = 'TKIP CCMP'
    elseif encryption == 'wpa3-mixed' then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'WPA-EAP WPA-EAP-SUITE-B-192'
        hostapd_cfg.rsn_pairwise = 'TKIP CCMP'
    elseif encryption == "owe" then
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = '2'
        hostapd_cfg.wpa_key_mgmt = 'OWE'
        hostapd_cfg.rsn_pairwise = 'CCMP'
    else
        hostapd_cfg.auth_algs = '1'
        hostapd_cfg.wpa = ''
    end
end

function mtkdat.auth2hostapd_encryption(auth, encr)

    local cfg = {}
    local encryption = dat2uci_encryption(auth, encr)
    uci2hostapd_encryption(encryption, cfg)

    return cfg
end


local function bw2htmode(bw, mode)
    local i = tonumber(mode)
    if i >= 0 and i <= 4 then
        if i == 1 then
            return "NOHT", "1"
        else
            return "NOHT", "0"
        end
    elseif i >= 5 and i <= 11 then
        return "HT"..bw, "0"
    elseif i >= 12 and i <= 15 then
        return "VHT"..bw, "0"
    elseif i >= 16 and i <= 21 then
        if bw == "80_80" then
            return nil, nil
        else
            return "HE"..bw, "0"
        end
    elseif i >= 22 and i <= 27 then
        if bw == "80_80" then
            return nil, nil
        else
            return "EHT"..bw, "0"
        end
    end
end

local function cfg2dev(cfg, devname, dev)
    assert(cfg ~= nil)
    assert(dev ~= nil)

    dev[".name"] = string.gsub(devname, "%.", "_")
    dev.type = "mtkwifi"
    dev.vendor = "mediatek"
    dev.txpower = cfg.TxPower
    if cfg.Channel == "0" then
        dev.channel = "auto"
        if cfg.AutoChannelSelect then
            dev.acs_alg = cfg.AutoChannelSelect
        end
        if cfg.AutoChannelSkipList then
            dev.acs_skiplist = cfg.AutoChannelSkipList
        end
    else
        dev.channel = cfg.Channel
    end
    dev.channel_grp = cfg.ChannelGrp
    dev.beacon_int = cfg.BeaconPeriod
    dev.txpreamble = cfg.TxPreamble

    local WirelessMode = cfg.WirelessMode:split(";")[1]
    if cfg.HT_BW == "1" then
        if cfg.VHT_BW == "0" or not cfg.VHT_BW then
            if cfg.HT_BSSCoexistence == '0' or not cfg.HT_BSSCoexistence then
--                dev.bw = "40"
                  dev.ht_coex = '1'
            else
--                dev.bw = "60"
            end
            dev.htmode, dev.pure_11b = bw2htmode("40", WirelessMode)
        elseif cfg.VHT_BW == "1" then
--            dev.bw = "80"
            dev.htmode, dev.pure_11b = bw2htmode("80", WirelessMode)
        elseif cfg.VHT_BW == "2" then
            if cfg.EHT_ApBw == '3' then
--                dev.bw = "160"
                dev.htmode, dev.pure_11b = bw2htmode("160", WirelessMode)
            elseif cfg.EHT_ApBw == '4' then
--                dev.bw = "320"
                dev.htmode, dev.pure_11b = bw2htmode("320", WirelessMode)
            end
        elseif cfg.VHT_BW == "3" then
--            dev.bw = "161"
            dev.htmode, dev.pure_11b = bw2htmode("80_80", WirelessMode)
            dev.vht_sec80_channel = cfg.VHT_Sec80_Channel
        end
    else
--        dev.bw = "20"
        dev.htmode, dev.pure_11b = bw2htmode("20", WirelessMode)
    end

    dev.vht_sec80_channel = cfg.VHT_Sec80_Channel
    dev.ht_extcha = cfg.HT_EXTCHA
    dev.ht_txstream = cfg.HT_TxStream
    dev.ht_rxstream = cfg.HT_RxStream
    dev.shortslot = cfg.ShortSlot
    dev.ht_distkip = cfg.HT_DisallowTKIP
    dev.bgprotect = cfg.BGProtection
    dev.txburst = cfg.TxBurst

    dev.band = mode2band(WirelessMode)

    if dev.band == "2.4G" then
        dev.region = cfg.CountryRegion
    else
        dev.aregion = cfg.CountryRegionABand
        dev.pure_11b = nil
    end

    dev.pktaggregate = cfg.PktAggregate
    dev.country = cfg.CountryCode
    dev.ht_mcs = cfg.HT_MCS
    dev.e2p_accessmode = cfg.E2pAccessMode
    dev.map_mode = cfg.MapMode
    dev.dbdc_mode = cfg.DBDC_MODE
    dev.etxbfencond = cfg.ETxBfEnCond
    dev.itxbfen = cfg.ITxBfEn
    dev.mutxrx_enable = cfg.MUTxRxEnable
    dev.bss_color = cfg.BSSColorValue
    dev.colocated_bssid = cfg.CoLocatedBSSID
    dev.twt_support = cfg.TWTSupport
    dev.individual_twt_support = cfg.IndividualTWTSupport
    dev.he_ldpc = cfg.HE_LDPC
    dev.txop = cfg.TxOP
--    dev.ieee80211h = cfg.IEEE80211H
    dev.dfs_enable = cfg.DfsEnable
    dev.sre_enable = cfg.SREnable
    dev.powerup_enbale = cfg.PowerUpenable
    dev.powerup_cckofdm = cfg.PowerUpCckOfdm
    dev.powerup_ht20 = cfg.PowerUpHT20
    dev.powerup_ht40 = cfg.PowerUpHT40
    dev.powerup_vht20 = cfg.PowerUpVHT20
    dev.powerup_vht40 = cfg.PowerUpVHT40
    dev.powerup_vht80 = cfg.PowerUpVHT80
    dev.powerup_vht160 = cfg.PowerUpVHT160

    dev.vow_airtime_fairness_en = cfg.VOW_Airtime_Fairness_En
    dev.ht_badec = cfg.HT_BADecline
    dev.ht_rdg = cfg.HT_RDG
    dev.ht_bawinsize = cfg.HT_BAWinSize
    dev.whnat = cfg.WHNAT
    dev.e2p_accessmode = cfg.E2pAccessMode
    dev.vow_bw_ctrl = cfg.VOW_BW_Ctrl
    dev.vow_ex_en = cfg.VOW_RX_En
    dev.doth = cfg.IEEE80211H

    dev.dfs_zero_wait = cfg.DfsZeroWait
    dev.dfs_dedicated_zero_wait = cfg.DfsDedicatedZeroWait
    dev.dfs_zero_wait_default = cfg.DfsZeroWaitDefault
    dev.rd_region = cfg.RDRegion
    dev.psc_acs = cfg.PSC_ACS
    dev.dabs_group_key_bitmap = cfg.DABSgroupkeybitmap
    dev.dabs_vendor_key_bitmap = cfg.DABSvendorkeybitmap
    dev.qos_enable = cfg.QoSEnable

    return dev
end

local function cfg2iface(cfg, devname, ifname, iface, i)
    assert(cfg ~= nil)
    assert(iface ~= nil)

    local encr_list = cfg.EncrypType:split()
    local auth_list = cfg.AuthMode:split()
    encr_list = encr_list[1]:split(";")
    auth_list = auth_list[1]:split(";")

    iface[".name"] = ifname
    iface.device = devname
    --print("ifname:"..iface[".name"])
    iface.network = "lan"
    iface.mode = "ap"
    iface.disabled = "0"
    iface.ssid = cfg["SSID"..tostring(i)]
    iface.network = "lan"
    iface.vifidx = i
    iface.hidden = token_get(cfg.HideSSID, i, mtkdat.split(cfg.HideSSID,";")[1])
    iface.wmm = token_get(cfg.WmmCapable, i, mtkdat.split(cfg.WmmCapable,";")[1])
    iface.dtim_period = token_get(cfg.DtimPeriod, i, mtkdat.split(cfg.DtimPeriod,";")[1])

    iface.encryption = dat2uci_encryption(auth_list[i], encr_list[i])
    iface.key = ""
--[[
    if encr_list[i] == "WEP" then
        iface.key = token_get(cfg.DefaultKeyID, i, mtkdat.split(cfg.DefaultKeyID,";")[1])
    elseif auth_list[i] == "WPA2PSK" or auth_list[i] == "WPA3PSK" or
]]
    if auth_list[i] == "WPA2PSK" or auth_list[i] == "WPA3PSK" or
        auth_list[i] == "WPAPSKWPA2PSK" or auth_list[i] == "WPA2PSKWPA3PSK" then
        iface.key = cfg["WPAPSK"..tostring(i)]
    end

    local j
    for j = 1, 4 do
        iface["key"..tostring(j)] = cfg["Key"..tostring(j).."Str"..tostring(i)] or ''
    end

    iface.rekey_interval = token_get(cfg.RekeyInterval, i, mtkdat.split(cfg.RekeyInterval,";")[1])
    iface.rekey_meth = token_get(cfg.RekeyMethod, i, mtkdat.split(cfg.RekeyMethod,";")[1])
    iface.pmk_cache_period = token_get(cfg.PMKCachePeriod, i, mtkdat.split(cfg.PMKCachePeriod ,";")[1])

    iface.ieee8021x = token_get(cfg.IEEE8021X, i, mtkdat.split(cfg.IEEE8021X,";")[1])
    iface.auth_server = token_get(cfg.RADIUS_Server, i)
    iface.auth_port = token_get(cfg.RADIUS_Port, i)
    iface.auth_secret = cfg["RADIUS_Key"..tostring(i)]
    iface.ownip =  cfg.own_ip_addr
    iface.idle_timeout = cfg.idle_timeout_interval
    iface.session_timeout = token_get(cfg.session_timeout_interval, i, mtkdat.split(cfg.session_timeout_interval,";")[1])
    iface.preauth = token_get(cfg.PreAuth, i, mtkdat.split(cfg.PreAuth,";")[1])

    local pmfmfpc = token_get(cfg.PMFMFPC, i, mtkdat.split(cfg.PMFMFPC,";")[1])
    local pmfmfpr = token_get(cfg.PMFMFPR, i, mtkdat.split(cfg.PMFMFPR,";")[1])

    if pmfmfpc == '1' and pmfmfpr == '1' then
        iface.ieee80211w = '2'
    elseif pmfmfpc == '1' then
        iface.ieee80211w = '1'
    else
        iface.ieee80211w = '0'
    end

    if iface.ieee80211w == '2' and
       ( iface.encryption == "psk2+ccmp" or
         iface.encryption == "wpa2+ccmp" or
         iface.encryption == "wpa3" ) then
        iface.pmf_sha256 = "1"
    else
        iface.pmf_sha256 = token_get(cfg.PMFSHA256, i, mtkdat.split(cfg.PMFSHA256,";")[1])
    end

--    iface.wireless_mode = token_get(cfg.WirelessMode, i, mtkdat.split(cfg.WirelessMode,";")[1])
    iface.tx_rate = token_get(cfg.TxRate, i, mtkdat.split(cfg.TxRate,";")[1])
    if iface.tx_rate == '' then iface.tx_rate = tostring(0) end
    iface.no_forwarding = token_get(cfg.NoForwarding , i, mtkdat.split(cfg.NoForwarding ,";")[1])
    iface.rts_threshold = token_get(cfg.RTSThreshold, i, mtkdat.split(cfg.RTSThreshold,";")[1])
    iface.frag_threshold = token_get(cfg.FragThreshold, i, mtkdat.split(cfg.FragThreshold,";")[1])
    iface.apsd_capable = token_get(cfg.APSDCapable, i, mtkdat.split(cfg.APSDCapable,";")[1])
    iface.vht_bw_signal = token_get(cfg.VHT_BW_SIGNAL, i, mtkdat.split(cfg.VHT_BW_SIGNAL,";")[1])
    iface.vht_ldpc = token_get(cfg.VHT_LDPC, i, mtkdat.split(cfg.VHT_LDPC,";")[1])
    iface.vht_stbc = token_get(cfg.VHT_STBC, i, mtkdat.split(cfg.VHT_STBC,";")[1])
    iface.vht_sgi = token_get(cfg.VHT_SGI, i, mtkdat.split(cfg.VHT_SGI,";")[1])
    iface.ht_ldpc = token_get(cfg.HT_LDPC, i, mtkdat.split(cfg.HT_LDPC,";")[1])
    iface.ht_stbc = token_get(cfg.HT_STBC, i, mtkdat.split(cfg.HT_STBC,";")[1])
    iface.ht_protect = token_get(cfg.HT_PROTECT, i, mtkdat.split(cfg.HT_PROTECT,";")[1])
    iface.ht_gi = token_get(cfg.HT_GI , i, mtkdat.split(cfg.HT_GI ,";")[1])
    iface.ht_opmode = token_get(cfg.HT_OpMode , i, mtkdat.split(cfg.HT_OpMode ,";")[1])
    iface.ht_amsdu = token_get(cfg.HT_AMSDU, i, mtkdat.split(cfg.HT_AMSDU,";")[1])
    iface.ht_autoba = token_get(cfg.HT_AutoBA , i, mtkdat.split(cfg.HT_AutoBA ,";")[1])
    iface.igmpsn_enable = token_get(cfg.IgmpSnEnable, i, mtkdat.split(cfg.IgmpSnEnable,";")[1])

    iface.mumimoul_enable = token_get(cfg.MuMimoUlEnable, i, mtkdat.split(cfg.MuMimoUlEnable,";")[1])
    iface.mumimodl_enable = token_get(cfg.MuMimoDlEnable, i, mtkdat.split(cfg.MuMimoDlEnable,";")[1])
    iface.muofdmaul_enable = token_get(cfg.MuOfdmaUlEnable, i, mtkdat.split(cfg.MuOfdmaUlEnable,";")[1])
    iface.muofdmadl_enable = token_get(cfg.MuOfdmaDlEnable, i, mtkdat.split(cfg.MuOfdmaDlEnable,";")[1])
    iface.vow_group_max_ratio = token_get(cfg.VOW_Group_Max_Ratio, i, mtkdat.split(cfg.VOW_Group_Max_Ratio,";")[1])
    iface.vow_group_min_ratio = token_get(cfg.VOW_Group_Min_Ratio, i, mtkdat.split(cfg.VOW_Group_Min_Ratio,";")[1])
    iface.vow_airtime_ctrl_en = token_get(cfg.VOW_Airtime_Ctrl_En, i, mtkdat.split(cfg.VOW_Airtime_Ctrl_En,";")[1])
    iface.vow_group_max_rate = token_get(cfg.VOW_Group_Max_Rate , i, mtkdat.split(cfg.VOW_Group_Max_Rate ,";")[1])
    iface.vow_group_min_rate = token_get(cfg.VOW_Group_Min_Rate, i, mtkdat.split(cfg.VOW_Group_Min_Rate,";")[1])
    iface.vow_rate_ctrl_en = token_get(cfg.VOW_Rate_Ctrl_En, i, mtkdat.split(cfg.VOW_Rate_Ctrl_En,";")[1])

    iface.wds = token_get(cfg.WdsEnable, i, mtkdat.split(cfg.WdsEnable,";")[1])
    iface.wdslist = cfg.WdsList
    iface.wds0key = cfg.Wds0Key
    iface.wds1key = cfg.Wds1Key
    iface.wds2key = cfg.Wds2Key
    iface.wds3key = cfg.Wds3Key
    iface.wdsencryptype = cfg.WdsEncrypType
    iface.wdsphymode = cfg.WdsPhyMode

    local wsc_confmode, wsc_confstatus
    wsc_confmode = token_get(cfg.WscConfMode, i, mtkdat.split(cfg.WscConfMode,";")[1])
    wsc_confmode = tonumber(wsc_confmode)
    wsc_confstatus = token_get(cfg.WscConfStatus, i, mtkdat.split(cfg.WscConfStatus,";")[1])
    wsc_confstatus = tonumber(wsc_confstatus)

    iface.wps_state = ''
    if wsc_confmode and wsc_confmode ~= 0 then
        if wsc_confstatus == 1 then
            iface.wps_state = '1'
        elseif wsc_confstatus == 2 then
            iface.wps_state = '2'
        end
    end

    iface.wps_pin = token_get(cfg.WscVendorPinCode, i, mtkdat.split(cfg.WscVendorPinCode,";")[1])

    iface.access_policy = cfg["AccessPolicy"..tostring(i-1)]
    iface.access_list = __cfg2list(cfg["AccessControlList"..tostring(i-1)])

    return iface
end

local function cfg2apcli(cfg, devname, ifname, iface)
    assert(cfg ~= nil)
    assert(iface ~= nil)

    iface[".name"] = ifname
    iface.device = devname
    iface.mode = "sta"
    if cfg.ApCliEnable == "1" then
        iface.disabled = "0"
    else
        iface.disabled = "1"
    end

    iface.ssid = cfg.ApCliSsid
    iface.bssid = cfg.ApCliBssid
    iface.network = "lan"

    iface.encryption = dat2uci_encryption(cfg.ApCliAuthMode, cfg.ApCliEncrypType)

    iface.key = ""
--[[
    if cfg.ApCliEncrypType == "WEP" then
        iface.key = cfg.ApCliDefaultKeyID
    elseif cfg.ApCliAuthMode == "WPA2PSK" or cfg.ApCliAuthMode == "WPA3PSK" or
]]
    if cfg.ApCliAuthMode == "WPA2PSK" or cfg.ApCliAuthMode == "WPA3PSK" or
        cfg.ApCliAuthMode == "WPAPSKWPA2PSK" or cfg.ApCliAuthMode == "WPA2PSKWPA3PSK" then
        iface.key = cfg.ApCliWPAPSK
    end

    if cfg.ApCliPMFMFPC == '1' and cfg.ApCliPMFMFPR == '1' then
        iface.ieee80211w = '2'
    elseif cfg.ApCliPMFMFPC == '1' then
        iface.ieee80211w = '1'
    else
        iface.ieee80211w = '0'
    end

    iface.pmf_sha256 = cfg.ApCliPMFSHA256
    iface.owetrante = cfg.ApCliOWETranIe
    iface.mac_repeateren = cfg.MACRepeaterEn

    local j
    for j = 1, 4 do
        iface["key"..tostring(j)] = cfg["ApCliKey"..tostring(j).."Str"] or ''
    end

    iface.wps_pin = ''

    return iface
end

local function htmode2bw(band, htmode, pure_11b)
    local bw
    local wireless_mode

    if string.upper(htmode) == 'NOHT' then
        if string.upper(band) == "2.4G" or
           string.upper(band) == "2G" then
            if pure_11b == '1' then
                return tostring(PHY_11B), "20"
            else
                return tostring(PHY_11BG_MIXED), "20"
            end
        elseif string.upper(band) == "5G" then
            return tostring(PHY_11A), "20"
        end
    elseif string.upper(htmode) == 'HT20' then
        if string.upper(band) == "2.4G" or
           string.upper(band) == "2G" then
            return tostring(PHY_11BGN_MIXED), "20"
        elseif string.upper(band) == "5G" then
            return tostring(PHY_11AN_MIXED), "20"
        end
    elseif string.upper(htmode) == 'HT40' then
        if string.upper(band) == "2.4G" or
           string.upper(band) == "2G" then
            return tostring(PHY_11BGN_MIXED), "40"
        elseif string.upper(band) == "5G" then
            return tostring(PHY_11AN_MIXED), "40"
        end
    elseif string.upper(htmode) == 'VHT20' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11VHT_N_A_MIXED), "20"
        end
    elseif string.upper(htmode) == 'VHT40' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11VHT_N_A_MIXED), "40"
        end
    elseif string.upper(htmode) == 'VHT80' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11VHT_N_A_MIXED), "80"
        end
    elseif string.upper(htmode) == 'VHT80_80' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11VHT_N_A_MIXED), "161"
        end
    elseif string.upper(htmode) == 'VHT160' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11VHT_N_A_MIXED), "160"
        end
    elseif string.upper(htmode) == 'HE20' then
        if string.upper(band) == "2.4G" or
           string.upper(band) == "2G" then
            return tostring(PHY_11AX_24G), "20"
        elseif string.upper(band) == "5G" then
            return tostring(PHY_11AX_5G), "20"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11AX_6G), "20"
        end
    elseif string.upper(htmode) == 'HE40' then
        if string.upper(band) == "2.4G" or
           string.upper(band) == "2G" then
            return tostring(PHY_11AX_24G), "40"
        elseif string.upper(band) == "5G" then
            return tostring(PHY_11AX_5G), "40"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11AX_6G), "40"
        end
    elseif string.upper(htmode) == 'HE80' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11AX_5G), "80"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11AX_6G), "80"
        end
    elseif string.upper(htmode) == 'HE160' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11AX_5G), "160"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11AX_6G), "160"
        end
    elseif string.upper(htmode) == 'HE320' then
        if string.upper(band) == "6G" then
            return tostring(PHY_11AX_6G), "320"
        end
    elseif string.upper(htmode) == 'EHT20' then
        if string.upper(band) == "2.4G" or
           string.upper(band) == "2G" then
            return tostring(PHY_11BE_24G), "20"
        elseif string.upper(band) == "5G" then
            return tostring(PHY_11BE_5G), "20"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11BE_6G), "20"
        end
    elseif string.upper(htmode) == 'EHT40' then
        if string.upper(band) == "2.4G" or
           string.upper(band) == "2G" then
            return tostring(PHY_11BE_24G), "40"
        elseif string.upper(band) == "5G" then
            return tostring(PHY_11BE_5G), "40"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11BE_6G), "40"
        end
    elseif string.upper(htmode) == 'EHT80' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11BE_5G), "80"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11BE_6G), "80"
        end
    elseif string.upper(htmode) == 'EHT160' then
        if string.upper(band) == "5G" then
            return tostring(PHY_11BE_5G), "160"
        elseif string.upper(band) == "6G" then
            return tostring(PHY_11BE_6G), "160"
        end
    elseif string.upper(htmode) == 'EHT320' then
        if string.upper(band) == "6G" then
            return tostring(PHY_11BE_6G), "320"
        end
    end
end

local function dev2cfg(dev, cfg)
    assert(dev ~= nil)
    assert(cfg ~= nil)

    cfg.TxPower = dev.txpower
    cfg.Channel = dev.channel
    if string.lower(dev.channel) == "auto" or
       dev.channel == nil or
       dev.channel == "0" then
        cfg.Channel = 0
        if dev.acs_alg then
            cfg.AutoChannelSelect = dev.acs_alg
	else
            cfg.AutoChannelSelect = 3
        end
    elseif tonumber(dev.channel) > 0 then
        cfg.Channel = dev.channel
	cfg.AutoChannelSelect = 0
    end
    cfg.AutoChannelSkipList = dev.acs_skiplist or ""
    cfg.ChannelGrp = dev.channel_grp
    cfg.BeaconPeriod = dev.beacon_int
    cfg.TxPreamble = dev.txpreamble
    cfg.HT_EXTCHA = dev.ht_extcha
    cfg.HT_TxStream = dev.ht_txstream
    cfg.HT_RxStream = dev.ht_rxstream
    cfg.ShortSlot = dev.shortslot
    cfg.HT_DisallowTKIP = dev.ht_distkip
    cfg.BGProtection = dev.bgprotect
    cfg.TxBurst = dev.txburst
    if dev.ht_coex ~= nil then
        if dev.ht_coex == '1' then
            cfg.HT_BSSCoexistence = '0'
        elseif dev.ht_coex == '0' then
            cfg.HT_BSSCoexistence = '1'
        end
    end

    if dev.band == "2.4G" then
        cfg.CountryRegion = dev.region
    else
        cfg.CountryRegionABand = dev.aregion
    end

    cfg.PktAggregate = dev.pktaggregate
    cfg.CountryCode = dev.country
    cfg.HT_MCS = dev.ht_mcs
    cfg.E2pAccessMode = dev.e2p_accessmode
    cfg.MapMode = dev.map_mode
    cfg.DBDC_MODE = dev.dbdc_mode
    cfg.ETxBfEnCond = dev.etxbfencond
    cfg.ITxBfEn = dev.itxbfen
    cfg.MUTxRxEnable = dev.mutxrx_enable
    cfg.BSSColorValue = dev.bss_color
    cfg.CoLocatedBSSID = dev.colocated_bssid
    cfg.TWTSupport = dev.twt_support
    cfg.IndividualTWTSupport = dev.individual_twt_support
    cfg.HE_LDPC = dev.he_ldpc
    cfg.TxOP = dev.txop
--    cfg.IEEE80211H = dev.ieee80211h
    cfg.DfsEnable = dev.dfs_enable
    cfg.SREnable = dev.sre_enable
    cfg.PowerUpenable = dev.powerup_enbale
    cfg.PowerUpCckOfdm = dev.powerup_cckofdm
    cfg.PowerUpHT20 = dev.powerup_ht20
    cfg.PowerUpHT40 = dev.powerup_ht40
    cfg.PowerUpVHT20 = dev.powerup_vht20
    cfg.PowerUpVHT40 = dev.powerup_vht40
    cfg.PowerUpVHT80 = dev.powerup_vht80
    cfg.PowerUpVHT160 = dev.powerup_vht160

    cfg.VOW_Airtime_Fairness_En = dev.vow_airtime_fairness_en
    cfg.HT_BADecline = dev.ht_badec
    cfg.HT_RDG = dev.ht_rdg
    cfg.HT_BAWinSize = dev.ht_bawinsize
    cfg.WHNAT = dev.whnat
    cfg.E2pAccessMode = dev.e2p_accessmode
    cfg.VOW_BW_Ctrl = dev.vow_bw_ctrl
    cfg.VOW_RX_En = dev.vow_ex_en
    cfg.IEEE80211H = dev.doth

    local wireless_mode, bw

    if dev.band ~= nil and dev.htmode ~= nil then
        wireless_mode, bw = htmode2bw(dev.band, dev.htmode, dev.pure_11b)
    end

    if dev.wireless_mode == nil then
        dev.wireless_mode = wireless_mode
    end

    if dev.bw == nil then
        dev.bw = bw
    end

    if dev.mbssid == "11v" then
        cfg.Dot11vMbssid = "1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1"
        cfg.Dot11vMbssidExt = ""
    elseif dev.mbssid == "11vExt" then
        dev._11vmbssid_tx_group=-1
        cfg.Dot11vMbssid = ""
        cfg.Dot11vMbssidExt = ""
    elseif dev.mbssid == "legacy" or dev.mbssid == nil then
        cfg.Dot11vMbssid = "0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0"
        cfg.Dot11vMbssidExt = ""
    end

    cfg.DfsZeroWait = dev.dfs_zero_wait
    cfg.DfsDedicatedZeroWait = dev.dfs_dedicated_zero_wait
    cfg.DfsZeroWaitDefault = dev.dfs_zero_wait_default
    if dev.rd_region then
        cfg.RDRegion = dev.rd_region
    else
        if dev.country == "US" or
           dev.country == "TW" then
            cfg.RDRegion = "FCC"
        elseif dev.country == "JP" then
            cfg.RDRegion = "JAP"
        elseif dev.country == "FR" or
            dev.country == "IE" or
            dev.country == "HK" or
            dev.country == "AU" or
            dev.country == "NONE" or
            dev.country == nil then
            cfg.RDRegion = "CE"
        end
    end
    cfg.PSC_ACS = dev.psc_acs
    cfg.DABSgroupkeybitmap = dev.dabs_group_key_bitmap;
    cfg.DABSvendorkeybitmap = dev.dabs_vendor_key_bitmap;
    cfg.QoSEnable = dev.qos_enable

    local wireless_mode, bw, ht_bw, vht_bw, eht_apbw
    wireless_mode, bw = htmode2bw(dev.band, dev.htmode, dev.pure_11b)

    if bw == "20" then
        ht_bw = tostring(HT_BW_20)
        vht_bw = tostring(VHT_BW_2040)
        eht_apbw = tostring(EHT_BW_20)
    else
        ht_bw = tostring(HT_BW_40)
        if bw == "40" then
            vht_bw = tostring(VHT_BW_2040)
            eht_apbw = tostring(EHT_BW_2040)
--                HT_BSSCoexistence = '0'  -- TODO
        elseif bw == "60" then
            vht_bw = tostring(VHT_BW_2040)
--                HT_BSSCoexistence = '1'  -- TODO
        elseif bw == "80" then
            vht_bw = tostring(VHT_BW_80)
            eht_apbw = tostring(EHT_BW_80)
        elseif bw == "160" then
            vht_bw = tostring(VHT_BW_160)
            eht_apbw = tostring(EHT_BW_160)
        elseif bw == "161" then
            vht_bw = tostring(VHT_BW_8080)
        elseif bw == "320" then
            vht_bw = tostring(VHT_BW_160)
            eht_apbw = tostring(EHT_BW_320)
        end
    end

    cfg.HT_BW = ht_bw
    cfg.VHT_BW = vht_bw
    cfg.EHT_ApBw = eht_apbw
    cfg.WirelessMode = wireless_mode
    cfg.VHT_Sec80_Channel = dev.vht_sec80_channel

    return cfg
end

local function iface2cfg(dev, iface, i, cfg)
    assert(iface ~= nil)
    assert(cfg ~= nil)

    local encr, auth
    local htmode, wireless_mode, bw, ht_bw, vht_bw, eht_apbw, vht_sec80_channel

    cfg["SSID"..tostring(i)] = iface.ssid
    cfg.HideSSID = token_set(cfg.HideSSID, i, iface.hidden)
    cfg.WmmCapable = token_set(cfg.WmmCapable, i, iface.wmm)
    cfg.DtimPeriod = token_set(cfg.DtimPeriod, i, iface.dtim_period)

    local wireless_mode, bw, ht_bw, vht_bw, eht_apbw
    if iface.htmode ~= nil then
        wireless_mode, bw = htmode2bw(dev.band, iface.htmode, iface.pure_11b)

        if bw == "20" then
            ht_bw = tostring(HT_BW_20)
            vht_bw = tostring(VHT_BW_2040)
            eht_apbw = tostring(EHT_BW_20)
        else
            ht_bw = tostring(HT_BW_40)
            if bw == "40" then
                vht_bw = tostring(VHT_BW_2040)
                eht_apbw = tostring(EHT_BW_2040)
    --                HT_BSSCoexistence = '0'  -- TODO
            elseif bw == "60" then
                vht_bw = tostring(VHT_BW_2040)
    --                HT_BSSCoexistence = '1'  -- TODO
            elseif bw == "80" then
                vht_bw = tostring(VHT_BW_80)
                eht_apbw = tostring(EHT_BW_80)
            elseif bw == "160" then
                vht_bw = tostring(VHT_BW_160)
                eht_apbw = tostring(EHT_BW_160)
            elseif bw == "161" then
                vht_bw = tostring(VHT_BW_8080)
            elseif bw == "320" then
                vht_bw = tostring(VHT_BW_160)
                eht_apbw = tostring(EHT_BW_320)
            end
        end

        cfg.HT_BW = token_set(cfg.HT_BW, i, cfg.HT_BW:split(";")[1])
        cfg.HT_BW = token_set(cfg.HT_BW, i, ht_bw)
        cfg.VHT_BW = token_set(cfg.VHT_BW, i, cfg.VHT_BW:split(";")[1])
        cfg.VHT_BW = token_set(cfg.VHT_BW, i, vht_bw)
        cfg.EHT_ApBw = token_set(cfg.EHT_ApBw, i, cfg.EHT_ApBw:split(";")[1])
        cfg.EHT_ApBw = token_set(cfg.EHT_ApBw, i, eht_apbw)
        cfg.WirelessMode = token_set(cfg.WirelessMode, i, cfg.WirelessMode:split(";")[1])
        cfg.WirelessMode = token_set(cfg.WirelessMode, i, wireless_mode)
    end

    if iface.vht_sec80_channel ~= nil then
        cfg.VHT_Sec80_Channel = token_set(cfg.VHT_Sec80_Channel, i, cfg.VHT_Sec80_Channel:split(";")[1])
        cfg.VHT_Sec80_Channel = token_set(cfg.VHT_Sec80_Channel, i, iface.vht_sec80_channel)
    end

    auth, encr = uci2dat_encryption(iface.encryption)

    cfg.AuthMode = token_set(cfg.AuthMode, i, auth)
    cfg.EncrypType = token_set(cfg.EncrypType, i, encr)

--[[
    if encr == "WEP" then
        cfg.DefaultKeyID = token_set(cfg.DefaultKeyID, i, iface.key)
    elseif auth == "WPA2PSK" or auth == "WPA3PSK" or
]]
    if auth == "WPA2PSK" or auth == "WPA3PSK" or
        auth == "WPAPSKWPA2PSK" or auth == "WPA2PSKWPA3PSK" then
        cfg["WPAPSK"..tostring(i)] = iface.key
    end

    local j
    for j = 1, 4 do
        local k = iface["key"..tostring(j)]
        if k then
            local len = #k
            if (len == 10 or len == 26 or len == 32) and k == string.match(k, '%x+') then
                cfg["Key"..tostring(j).."Type"] = token_set(cfg["Key"..tostring(j).."Type"], i, 0)
                cfg["Key"..tostring(j).."Str"..tostring(i)] = k
            elseif (len == 5 or len == 13 or len == 16) then
                cfg["Key"..tostring(j).."Type"] = token_set(cfg["Key"..tostring(j).."Type"], i, 1)
                cfg["Key"..tostring(j).."Str"..tostring(i)] = k
            end
        end
    end

    cfg.RekeyInterval = token_set(cfg.RekeyInterval, i, iface.rekey_interval)
    cfg.RekeyMethod = token_set(cfg.RekeyMethod, i, iface.rekey_meth)
    cfg.PMKCachePeriod = token_set(cfg.PMKCachePeriod, i, iface.pmk_cache_period )

    cfg.IEEE8021X = token_set(cfg.IEEE8021X, i, iface.ieee8021x)
    cfg.RADIUS_Server = token_set(cfg.RADIUS_Server, i, iface.auth_server)
    cfg.RADIUS_Port = token_set(cfg.RADIUS_Port, i, iface.auth_port)
    cfg["RADIUS_Key"..tostring(i)] = iface.auth_secret
    cfg.own_ip_addr = iface.ownip
    cfg.idle_timeout_interval = iface.idle_timeout
    cfg.session_timeout_interval = token_set(cfg.session_timeout_interval, i, iface.session_timeout)
    cfg.PreAuth = token_set(cfg.PreAuth, i, iface.preauth)

    if iface.ieee80211w == '2' then
        cfg.PMFMFPC = token_set(cfg.PMFMFPC, i, '1')
        cfg.PMFMFPR = token_set(cfg.PMFMFPR, i, '1')
    elseif iface.ieee80211w == '1' then
        cfg.PMFMFPC = token_set(cfg.PMFMFPC, i, '1')
        cfg.PMFMFPR = token_set(cfg.PMFMFPR, i, '0')
    elseif iface.ieee80211w == '0' then
        cfg.PMFMFPC = token_set(cfg.PMFMFPC, i, '0')
        cfg.PMFMFPR = token_set(cfg.PMFMFPR, i, '0')
    end

    if iface.ieee80211w == '2' and
       ( iface.encryption == "psk2+ccmp" or
         iface.encryption == "wpa2+ccmp" or
         iface.encryption == "wpa3" ) then
        cfg.PMFSHA256 = token_set(cfg.PMFSHA256, i, "1")
    else
        cfg.PMFSHA256 = token_set(cfg.PMFSHA256, i, iface.pmf_sha256)
    end

--    cfg.WirelessMode = token_set(cfg.WirelessMode, i, iface.wireless_mode)
    cfg.MldGroup = token_set(cfg.MldGroup, i, iface.mldgroup)
    cfg.TxRate = token_set(cfg.TxRate, i, iface.tx_rate)
    cfg.NoForwarding = token_set(cfg.NoForwarding, i, iface.no_forwarding)
    cfg.VHT_BW_SIGNAL = token_set(cfg.VHT_BW_SIGNAL, i, iface.vht_bw_signal)
    cfg.VHT_SGI = token_set(cfg.VHT_SGI, i, iface.vht_sgi)
    cfg.RTSThreshold = token_set(cfg.RTSThreshold, i, iface.rts_threshold)
    cfg.FragThreshold = token_set(cfg.FragThreshold, i, iface.frag_threshold)
    cfg.APSDCapable = token_set(cfg.APSDCapable, i, iface.apsd_capable)
    cfg.VHT_LDPC = token_set(cfg.VHT_LDPC, i, iface.vht_ldpc)
    cfg.VHT_STBC = token_set(cfg.VHT_STBC, i, iface.vht_stbc)
    cfg.HT_LDPC = token_set(cfg.HT_LDPC, i, iface.ht_ldpc)
    cfg.HT_STBC = token_set(cfg.HT_STBC, i, iface.ht_stbc)
    cfg.HT_PROTECT = token_set(cfg.HT_PROTECT, i, iface.ht_protect)
    cfg.HT_GI = token_set(cfg.HT_GI, i, iface.ht_gi)
    cfg.HT_OpMode = token_set(cfg.HT_OpMode, i, iface.ht_opmode)
    cfg.HT_AMSDU = token_set(cfg.HT_AMSDU, i, iface.ht_amsdu)
    cfg.HT_AutoBA = token_set(cfg.HT_AutoBA, i, iface.ht_autoba)
    cfg.IgmpSnEnable = token_set(cfg.IgmpSnEnable, i, iface.igmpsn_enable)

    cfg.MuMimoUlEnable = token_set(cfg.MuMimoUlEnable, i, iface.mumimoul_enable)
    cfg.MuMimoDlEnable = token_set(cfg.MuMimoDlEnable, i, iface.mumimodl_enable)
    cfg.MuOfdmaUlEnable = token_set(cfg.MuOfdmaUlEnable, i, iface.muofdmaul_enable)
    cfg.MuOfdmaDlEnable = token_set(cfg.MuOfdmaDlEnable, i, iface.muofdmadl_enable)
    cfg.VOW_Group_Max_Ratio = token_set(cfg.VOW_Group_Max_Ratio, i, iface.vow_group_max_ratio)
    cfg.VOW_Group_Min_Ratio = token_set(cfg.VOW_Group_Min_Ratio, i, iface.vow_group_min_ratio)
    cfg.VOW_Airtime_Ctrl_En = token_set(cfg.VOW_Airtime_Ctrl_En, i, iface.vow_airtime_ctrl_en)
    cfg.VOW_Group_Max_Rate = token_set(cfg.VOW_Group_Max_Rate , i, iface.vow_group_max_rate)
    cfg.VOW_Group_Min_Rate = token_set(cfg.VOW_Group_Min_Rate, i, iface.vow_group_min_rate)
    cfg.VOW_Rate_Ctrl_En = token_set(cfg.VOW_Rate_Ctrl_En, i, iface.vow_rate_ctrl_en)

    cfg.WdsEnable = token_set(cfg.WdsEnable, i, iface.wds)
    cfg.WdsList = iface.wdslist
    cfg.Wds0Key = iface.wds0key
    cfg.Wds1Key = iface.wds1key
    cfg.Wds2Key = iface.wds2key
    cfg.Wds3Key = iface.wds3key
    cfg.WdsEncrypType = iface.wdsencryptype
    cfg.WdsPhyMode = iface.wdsphymode

    local wsc_confmode, wsc_confstatus

    if iface.wps_state == '1' then
        wsc_confmode = '7'
        wsc_confstatus = '1'
    elseif iface.wps_state == '2' then
        wsc_confmode = '7'
        wsc_confstatus = '2'
    else
        wsc_confmode = '0'
        wsc_confstatus = '1'
    end

    cfg.WscConfMode = token_set(cfg.WscConfMode, i, wsc_confmode)
    cfg.WscConfStatus = token_set(cfg.WscConfStatus, i, wsc_confstatus)
    cfg.WscVendorPinCode = token_set(cfg.WscVendorPinCode, i, iface.wps_pin)

    cfg["AccessPolicy"..tostring(i-1)] = iface.access_policy
    cfg["AccessControlList"..tostring(i-1)] = ""
    if iface.access_list ~= nil then
        for j, v in pairs(iface.access_list) do
            cfg["AccessControlList"..tostring(i-1)] = token_set(cfg["AccessControlList"..tostring(i-1)], j, v)
        end
    end

    if dev.mbssid == "11vExt" then
        if iface["11v_role"] == "tx" then
            dev._11vmbssid_tx_group = dev._11vmbssid_tx_group + 1
            cfg.Dot11vMbssidExt = token_set(cfg.Dot11vMbssidExt, i, "TX-"..tostring(dev._11vmbssid_tx_group))
        elseif iface["11v_role"] == "ntx" then
            cfg.Dot11vMbssidExt = token_set(cfg.Dot11vMbssidExt, i, "NT-"..tostring(dev._11vmbssid_tx_group))
        elseif iface["11v_role"] == "cohost" then
            cfg.Dot11vMbssidExt = token_set(cfg.Dot11vMbssidExt, i, "CH-"..tostring(dev._11vmbssid_tx_group))
        else
            cfg.Dot11vMbssidExt = token_set(cfg.Dot11vMbssidExt, i, "CH-"..tostring(dev._11vmbssid_tx_group))
        end
    end

    return cfg
end

local function apcli2cfg(dev, iface, cfg)
    if iface.disabled == nil or tonumber(iface.disabled) == 0 then
        cfg.ApCliEnable = "1"
    else
        cfg.ApCliEnable = "0"
    end

    cfg.ApCliSsid = iface.ssid or ""
    cfg.ApCliBssid = iface.bssid

    auth, encr = uci2dat_encryption(iface.encryption)
    cfg.ApCliAuthMode = auth
    cfg.ApCliEncrypType = encr

--[[
    if encr == "WEP" then
        cfg.ApCliDefaultKeyID = iface.key
    elseif auth == "WPA2PSK" or auth == "WPA3PSK" or
]]
    if auth == "WPA2PSK" or auth == "WPA3PSK" or
        auth == "WPAPSKWPA2PSK" or auth == "WPA2PSKWPA3PSK" then
        cfg.ApCliWPAPSK = iface.key
    end

    if iface.ieee80211w == '2' then
        cfg.ApCliPMFMFPC = '1'
        cfg.ApCliPMFMFPR = '1'
    elseif iface.ieee80211w == '1' then
        cfg.ApCliPMFMFPC = '1'
        cfg.ApCliPMFMFPR = '0'
    elseif iface.ieee80211w == '0' then
        cfg.ApCliPMFMFPC = '0'
        cfg.ApCliPMFMFPR = '0'
    end

    cfg.ApCliPMFSHA256 = iface.pmf_sha256
    cfg.ApCliOWETranIe = iface.owetrante
    cfg.MACRepeaterEn = iface.mac_repeateren

    local j
    for j = 1, 4 do
        local k = iface["key"..tostring(j)]
        if k then
            local len = #k
            if (len == 10 or len == 26 or len == 32) and k == string.match(k, '%x+') then
                cfg["ApCliKey"..tostring(j).."Type"] = '0'
                cfg["ApCliKey"..tostring(j).."Str"] = k
            elseif (len == 5 or len == 13 or len == 16) then
                cfg["ApCliKey"..tostring(j).."Type"] = '1'
                cfg["ApCliKey"..tostring(j).."Str"] = k
            end
        end
    end

    return cfg
end


local function find_mldgroup(mldgroups, mode, group)
    local i

    for i = 1, #mldgroups do
        if mldgroups[i].mldgroup == group and mldgroups[i].mode == mode then
            return mldgroups[i]
        end
    end

    return nil
end

local function create_mldgroup(mldgroups, group, name, mode)
    local num = #mldgroups

    num = num + 1
    mldgroups[num] = {}
    mldgroups[num][".name"] = name
    mldgroups[num].mldgroup = group
    mldgroups[num].mode = mode

    return mldgroups[num]
end

local function cfg2mldgroup(mldgroups, l1dat, cfg, ucicfg)
    local if_num = tonumber(cfg.BssidNum)
    local mldgroup
    local ifname
    local i
    local group
    local mld_addr

    for i = 1, if_num do
        if i == 1 then
            ifname = l1dat.main_ifname
        else
            ifname = l1dat.ext_ifname..tostring(i)
        end
        group = token_get(cfg.MldGroup, i, "0")
        if group ~= "0" then
            mldgroup = find_mldgroup(mldgroups, "ap", group)
            if mldgroup == nil then
                mldgroup = create_mldgroup(mldgroups, group, "apmld"..group, "ap")
                mldgroup.disabled = "0"
            end
            if mldgroup.iface ~= nil then
                mldgroup.iface = mldgroup.iface.." "..ifname
            else
                mldgroup.iface = ifname
                mldgroup.ssid = "AP_MTK_MLO_"..group
            end
            if mldgroup.mld_addr == nil then
                mld_addr = cfg["MldAddr"..group]
                if mld_addr ~= nil then
                    mldgroup.mld_addr = mld_addr
                end
            end
        end
    end

 --  if cfg.ApCliEnable == "1" then
        group = "1"
        if cfg.ApcliMloDisable == nil or token_get(cfg.ApcliMloDisable, 1, "1") == "0" then
            ifname = l1dat.apcli_ifname.."0"
            mldgroup = find_mldgroup(mldgroups, "sta", "1")
            if mldgroup == nil then
                mldgroup = create_mldgroup(mldgroups, group, "stamld"..group, "sta")
                mldgroup.disabled = "0"
            end
            if mldgroup.iface ~= nil then
                mldgroup.iface = mldgroup.iface.." "..ifname
            else
                mldgroup.iface = ifname
                local vif = mtkdat.get_uci_vif_by_vif_name(ucicfg, ifname)
                if vif then
                    mldgroup.ssid = vif.ssid
                    mldgroup.encryption = vif.encryption
                    mldgroup.key = vif.key
                    mldgroup.ieee80211w = vif.ieee80211w
                    mldgroup.pmf_sha256 = vif.pmf_sha256
                end
            end
            if mldgroup.mld_addr == nil then
                mld_addr = cfg["ApcliMldAddr"..group]
                if mld_addr ~= nil then
                    mldgroup.mld_addr = mld_addr
                end
            end
        end
--    end
end

function mtkdat.dat2uci()
    --local shuci = require("shuci")
    local profiles = mtkdat.search_dev_and_profile()
    local l1dat, l1 = mtkdat.__get_l1dat()
    local dev, ifname, iface, i, j
    local n = 1
    local m = 1
    local mldgroup

    if ( not profiles or not l1dat) then
        nixio.syslog("err", "search dev profile fail.")
        return
    end

    local fp = io.open(uciCfgfile, "w")
    if fp == nil then return end

    local dridx = l1.DEV_RINDEX

    local uci = {}
    uci["wifi-device"] = {}
    uci["wifi-iface"] = {}
    uci["wifi-mld"] = {}

    for devname, profile in mtkdat.spairs(profiles, function(a,b) return string.upper(a) < string.upper(b) end) do
        local cfg = mtkdat.load_profile(profile)
        if (cfg == nil) then
            fp:close()
            nixio.syslog("err", "load profile for "..devname.." fail.")
            return
        end
        --print("devname:"..devname.." profile:"..profile)

        uci["wifi-device"][n] = {}
        dev = uci["wifi-device"][n]
        cfg2dev(cfg, devname, dev)

        local main_ifname = l1dat[dridx][devname].ext_ifname
        local if_num = tonumber(cfg.BssidNum)

        i = 1
        while i <= if_num do
            uci["wifi-iface"][m] = {}
            iface = uci["wifi-iface"][m]
            ifname = main_ifname..(i-1)
            cfg2iface(cfg, dev[".name"], ifname, iface, i)

            m = m + 1
            i = i + 1
        end

        main_ifname = l1dat[dridx][devname].apcli_ifname
        uci["wifi-iface"][m] = {}
        iface = uci["wifi-iface"][m]
        ifname = main_ifname..(0)
        --print("apcli"..ifname)

        cfg2apcli(cfg, dev[".name"], ifname, iface)

        m = m + 1
        n = n + 1

        mldgroups = uci["wifi-mld"]
        cfg2mldgroup(mldgroups, l1dat[dridx][devname], cfg, uci)
    end
    --print_table(uci)

    for i = 1, n-1 do
        dev = uci["wifi-device"][i]
        uci_encode_dev_options(fp, dev)
        for j = 1, m-1 do
            iface = uci["wifi-iface"][j]
            if iface.device == dev[".name"] then
                uci_encode_iface_options(fp, iface)
            end
        end
    end

    for i = 1, #mldgroups do
        local ifaces = mtkdat.split(mldgroups[i].iface, " ")
        if #ifaces > 1 then
            uci_encode_mld_options(fp, mldgroups[i])
        end
    end
    --shuci.encode(uci, '/etc/config/wireless')
    fp:close()
    os.execute("cp "..uciCfgfile.." "..lastCfgfile)
end

local function mldgroup2cfg(ucicfg, cfgs, mldgroup)
    if mldgroup.disabled == '1' then
        return
    end

    if mldgroup.mode == nil or
       ( string.lower(mldgroup.mode) ~= "sta" and
         string.lower(mldgroup.mode) ~= "ap" ) then
        return
    end

    local mode = string.lower(mldgroup.mode)

    if mldgroup.iface == nil then
        return
    end

    local group = tonumber(mldgroup.mldgroup)

    local ifaces = mtkdat.split(mldgroup.iface, " ")
    if ifaces == nil or #ifaces == 0 then
        return
    end

    if mode == "ap" then
        for idx, vifname in pairs(ifaces) do
            vif = mtkdat.get_uci_vif_by_vif_name(ucicfg, vifname)
            if vif == nil or vif.mode ~= "ap" then
                ifaces[idx] = nil
            end
        end
    elseif mode == "sta" then
        for idx, vifname in pairs(ifaces) do
            vif = mtkdat.get_uci_vif_by_vif_name(ucicfg, vifname)
            if vif == nil or vif.mode ~= "sta" then
                ifaces[idx] = nil
            end
        end
    end


    local mld_addr = mldgroup.mld_addr

    if mode == "ap" then
        if mld_addr ~= nil then
            for devname, cfg in pairs(cfgs) do
                cfg["MldAddr"..tostring(group)] = mld_addr
            end
        end
        for idx, vifname in pairs(ifaces) do
            vif = mtkdat.get_uci_vif_by_vif_name(ucicfg, vifname)
            if vif ~= nil and vif.mode == "ap" and string.find(mldgroup._device_list, vif.device) == nil then
                vifidx = tonumber(vif.vifidx)
                local devname = string.gsub(vif.device, "%_", ".")
                cfg = cfgs[devname]
                cfg.MldGroup = token_set(cfg.MldGroup, vifidx, tostring(group))
		mldgroup._device_list = mldgroup._device_list.." "..vif.device
            end
        end
    elseif mode == "sta" then
        for idx, vifname in pairs(ifaces) do
            vif = mtkdat.get_uci_vif_by_vif_name(ucicfg, vifname)
            if vif ~= nil and vif.mode == "sta" and string.find(mldgroup._device_list, vif.device) == nil then
                local devname = string.gsub(vif.device, "%_", ".")
                cfg = cfgs[devname]
                cfg.ApcliMloDisable = token_set(cfg.ApcliMloDisable, 1, "0")
		mldgroup._device_list = mldgroup._device_list.." "..vif.device
            end
        end
    end
end

function mtkdat.uci2dat()
    if not mtkdat.exist(uciCfgfile) then return end

    local uci = mtkdat.uci_load_wireless()
    local profiles = mtkdat.search_dev_and_profile()
    local l1dat, l1 = mtkdat.__get_l1dat()
    local cfgs = {}
    local old_cfgs = {}
    local mldgroup

    if not profiles then
        nixio.syslog("err", "unable to get profiles")
        return
    end

    local dridx = l1.DEV_RINDEX

    for _, dev in pairs(uci["wifi-device"]) do
        if dev.type ~= "mtkwifi" then return end
        local devname = string.gsub(dev[".name"], "%_", ".")
        local cfg = mtkdat.load_profile(profiles[devname])
        local old_cfg = table_clone(cfg);
        local id

        for id = 1, 63 do
            cfg["MldAddr"..tostring(id)] = ""
        end
	cfg.ApcliMloDisable = token_set(cfg.ApcliMloDisable, 1, "1")
        cfg.MldGroup = "0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0"
        cfg.WscConfMode = "0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0"
        cfg.WscConfStatus = "0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0"
        cfg.WirelessMode = token_get(cfg.WirelessMode, 1, nil)
        cfg.HT_BW = token_get(cfg.HT_BW, 1, nil)
        cfg.VHT_BW = token_get(cfg.VHT_BW, 1, nil)
        cfg.EHT_ApBw = token_get(cfg.EHT_ApBw, 1, nil)
        cfgs[devname] = cfg
	old_cfgs[devname] = old_cfg
    end

    if uci["wifi-mld"] ~= nil then
        for _, mldgroup in pairs(uci["wifi-mld"]) do
            if mldgroup ~= nil then
                mldgroup._device_list = ""
                mldgroup2cfg(uci, cfgs, mldgroup)
            end
        end
    end

    for _, dev in pairs(uci["wifi-device"]) do
        if dev.type ~= "mtkwifi" then return end
        local devname = string.gsub(dev[".name"], "%_", ".")
        local cfg = cfgs[devname]
        local old_cfg = old_cfgs[devname]
        --print("dev:"..devname)
        dev2cfg(dev, cfg)

        local main_ifname = l1dat[dridx][devname].ext_ifname
        local iface
        local if_num = 0
        local vifs = mtkdat.get_uci_vifs_by_dev_name(uci, dev[".name"])

        for _, iface in pairs(vifs) do
            if iface.mode == 'ap' then
                local i = string.find(iface[".name"], "%d+")
                i = string.sub(iface[".name"], i, -1)
                i = tonumber(i) + 1
                iface2cfg(dev, iface, i, cfg)

                if_num = if_num + 1
            end
        end

        if not mtkdat.exist(cfgfile) or if_num > tonumber(cfg.BssidNum) then
            cfg.BssidNum = tostring(if_num)
        end

        for _, iface in pairs(vifs) do
            if iface.mode == 'sta' then
                apcli2cfg(dev, iface, cfg)
                break
            end
        end

        diff = diff_config(cfg, old_cfg)
        --print(devname.." diff config\n")
        --print_table(diff)
        for k, v in pairs(diff) do
            if v ~= nil then
                set_dat_cfg(profiles[devname], k, v)
            end
        end
    end

    --update last file
    os.execute("cp "..uciCfgfile.." "..lastCfgfile)

end


function mtkdat.get_iface_cfg(devname, ifname, cfg_name)
    local dev_name
    local profiles = mtkdat.search_dev_and_profile()
    local l1dat, l1 = mtkdat.__get_l1dat()
    local dridx = l1.DEV_RINDEX

    for dev_name, profile in mtkdat.spairs(profiles, function(a,b) return string.upper(a) < string.upper(b) end) do
        if dev_name == devname then
            local cfg = mtkdat.load_profile(profile)
            local i = 1
            local main_ifname = l1dat[dridx][devname].ext_ifname
            while i <= tonumber(cfg.BssidNum) do
                local if_name = main_ifname..(i-1)
                if if_name == ifname then
                    local v = cfg[cfg_name..tostring(i)]
                    if v ~= nil then return v end
                    return token_get(cfg[cfg_name], i, mtkdat.split(cfg[cfg_name],";")[1])
                end
                i = i + 1
            end
        end
    end

   return nil
end

function mtkdat.cfg_is_diff()
    if not mtkdat.exist(uciCfgfile) then return false end

    if not mtkdat.exist(lastCfgfile) then
        if not mtkdat.exist("/tmp/mtk/wifi") then
            os.execute("mkdir -p /tmp/mtk/wifi")
        end
        os.execute("cp "..uciCfgfile.." "..lastCfgfile)
        return false
    end

    if file_is_diff(uciCfgfile, lastCfgfile) then
        return true
    end

    return false
end

return mtkdat
