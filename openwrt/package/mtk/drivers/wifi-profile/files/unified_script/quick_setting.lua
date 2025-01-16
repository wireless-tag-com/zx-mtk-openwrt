local mtkdat = require("mtkdat")

function debug_info_write(devname,content)
    local filename = "/tmp/mtk/wifi/"..devname.."_quick_setting_cmd.sh"
    local ff = io.open(filename, "a")
    ff:write(content)
    ff:write("\n")
    ff:close()
end

function token(str, n, default)
    local i = 1
    local list = {}
    for k in string.gmatch(str, "([^;]+)") do
        list[i] = k
        i = i + 1
    end
    return list[tonumber(n)] or default
end

function GetFileSize( filename )
    local fp = io.open( filename )
    if fp == nil then
    return nil
    end
    local filesize = fp:seek( "end" )
    fp:close()
    return filesize
end

function vifs_cfg_parm(parm)
--[[
    local vifs_cfg_parms = {"AuthMode", "EncrypType", "Key", "WPAPSK", "Access", "^WPS", "^wps", "^Wsc", "PIN", "^WEP", ";", "_"}
]]
    local vifs_cfg_parms = {"AuthMode", "EncrypType", "Key", "WPAPSK", "Access", "^WPS", "^wps", "^Wsc", "PIN", ";", "_"}
    for _, pat in ipairs(vifs_cfg_parms) do
        if string.find(parm, pat) then
            return false
        end
    end
    return true
end

function get_hostapd_obj(auth, encr)
    local mytable = mtkdat.auth2hostapd_encryption(auth, encr)

    if mytable.rsn_pairwise == "TKIP CCMP" then
        mytable.rsn_pairwise = "TKIP,CCMP"
    end

    if mytable.wpa_pairwise == "TKIP CCMP" then
        mytable.wpa_pairwise = "TKIP,CCMP"
    end

    return mytable
end

local function get_ieee80211w(pmfmfpc, pmfmfpr)
    local ieee80211w
    if pmfmfpc == '1' and pmfmfpr == '1' then
        ieee80211w = '2'
    elseif pmfmfpc == '1' and pmfmfpr == '0' then
        ieee80211w = '1'
    else
        ieee80211w = '0'
    end
    return ieee80211w
end

function __set_wifi_apcli_security(cfgs, diff, device, devname)
    -- to keep it simple, we always reconf the security if anything related is changed.
    -- do optimization only if there's significant performance defect.
    --if not diff[ApCliEnable][2] == "1" and cfgs[ApCliEnable] ~= "1" then return end
    local vifs = {} -- changed vifs

    -- figure out which vif is changed
    -- since multi-bssid is possible, both AuthMode and EncrypType can be a group
    local auth_old = cfgs.ApCliAuthMode:split() or {}
    local encr_old = cfgs.ApCliEncrypType and cfgs.ApCliEncrypType:split() or {}
    -- local keyid_old = cfgs.ApCliDefaultKeyID:split() or {}
    local auth_old_i = (auth_old[1] or ''):split(";")
    local encr_old_i = (encr_old[1] or ''):split(";")
    -- local keyid_old_i = (keyid_old[1] or ''):split(";")
    local auth_new = diff.ApCliAuthMode and diff.ApCliAuthMode[2]:split() or auth_old
    local auth_new_i = (auth_new[1] or ''):split(";")
    local encr_new = diff.ApCliEncrypType and diff.ApCliEncrypType[2]:split() or encr_old
    local encr_new_i = (encr_new[1] or ''):split(";")
    -- local keyid_new = diff.ApCliDefaultKeyID and diff.ApCliDefaultKeyID[2]:split() or keyid_old
    -- local keyid_new_i = (keyid_new[1] or ''):split(";")


    --print("encry ="..encr_new[1],auth_new[1], keyid_new[1],keyid_new_i[1])
    --print("encry_old ="..encr_old[1],auth_old[1], keyid_old[1])
    local num = math.max(#encr_old_i, #encr_new_i)
    for i = 1, num do
        local changed = false
        if next(auth_new) and auth_old_i[i] ~= auth_new_i[i] then
            changed = true
        elseif next(encr_new) and encr_old_i[i] ~= encr_new_i[i] then
            changed = true
        -- elseif next(keyid_new) and keyid_old_i[i] ~= keyid_new_i[i] then
        --    changed = true
        elseif diff["ApCliWPAPSK"] then
            changed = true
        elseif diff["ApCliSsid"] then
            changed = true
        elseif diff["ApCliPMFMFPC"] then
            changed = true
        elseif diff["ApCliPMFMFPR"] then
            changed = true
        elseif diff["ApCliPMFMFPR"] then
            changed = true
        elseif diff["ApCliPMFSHA256"] then
            changed = true
        else
            -- just support apcli0/apclii0/apclix0
            for j = 1, 4 do
                if diff["ApCliKey"..tostring(j).."Str"] then
                    changed = true
                    break
                end
            end
        end

        if changed then
            local vif = {}
            vif.idx = i
            vif.vifname = device.apcli_ifname..tostring(i-1)
            vif.AuthMode = auth_new_i and auth_new_i[i] or auth_old_i[i]
            vif.EncrypType = encr_new_i and encr_new_i[i] or encr_old_i[i]
            --vif.KeyID = keyid_new_i and keyid_new_i[i] or keyid_old_i[i]
            --vif.DefaultKeyID_idx = "wep_key"..tostring(vif.KeyID)
            --vif.DefaultKey = diff["ApCliKey"..tostring(vif.KeyID).."Str"]
            --            and diff["ApCliKey"..tostring(vif.KeyID).."Str"][2] or cfgs["ApCliKey"..tostring(vif.KeyID).."Str"]
            --vif.WEPType = "WEP"..tostring(vif.KeyID).."Type"
            --vif.WEPTypeVal = diff["WEP"..tostring(vif.KeyID).."Type"..tostring(i)] and
                        --diff["WEP"..tostring(vif.KeyID).."Type"..tostring(i)][2] or cfgs["WEP"..tostring(vif.KeyID).."Type"..tostring(i)]
            vif.WPAPSK = diff["ApCliWPAPSK"] and diff["ApCliWPAPSK"][2] or cfgs["ApCliWPAPSK"]
            vif.SSID = diff["ApCliSsid"] and diff["ApCliSsid"][2] or cfgs["ApCliSsid"]
            vif.pmfmfpc = diff["ApCliPMFMFPC"] and diff["ApCliPMFMFPC"][2] or cfgs["ApCliPMFMFPC"]
            vif.pmfmfpr = diff["ApCliPMFMFPR"] and diff["ApCliPMFMFPR"][2] or cfgs["ApCliPMFMFPR"]
            vif.pmfsha256 = diff["ApCliPMFSHA256"] and diff["ApCliPMFSHA256"][2] or cfgs["ApCliPMFSHA256"]
            table.insert(vifs, vif)
        end
    end

    -- iwpriv here
    for i, vif in ipairs(vifs) do

        commands = string.format([[
                wpa_cli -i %s remove_network all;
                wpa_cli -i %s add_network;
                wpa_cli -i %s set_network 0 ssid '"%s"';
                wpa_cli -i %s set_network 0 scan_ssid 1;
                mwctl %s set ApCliPMFSHA256 %s;]],
                vif.vifname, vif.vifname, vif.vifname, vif.SSID, vif.vifname,
                vif.vifname, vif.pmfsha256 or 0)
        local ieee80211w = get_ieee80211w(vif.pmfmfpc, vif.pmfmfpr)
        if vif.AuthMode == "OPEN" then
            --if vif.EncrypType == "WEP" then
            --commands = commands .."\n".. string.format([[
            --    wpa_cli -i %s set_network 0 key_mgmt WEP;
            --    wpa_cli -i %s set_network 0 %s '"%s"';
            --    wpa_cli -i %s set_network 0 wep_tx_keyidx %s;]],
            --vif.vifname, vif.vifname,  vif.DefaultKeyID_idx,
            --vif.DefaultKey, vif.vifname, vif.KeyID)
            --else
                commands = commands .."\n".. string.format([[
                wpa_cli -i %s set_network 0 key_mgmt NONE;]],
                vif.vifname)
            --end
        elseif    vif.AuthMode == "OWE" then
            commands = commands .."\n".. string.format([[
                wpa_cli -i %s set_network 0 key_mgmt OWE;
                wpa_cli -i %s set_network 0 proto RSN;
                wpa_cli -i %s set_network 0 ieee80211w 2;]],
            vif.vifname, vif.vifname, vif.vifname)
        --elseif vif.AuthMode == "SHARED" then
        --    commands = commands .."\n".. string.format([[
        --        wpa_cli -i %s set_network 0 key_mgmt NONE;
        --        wpa_cli -i %s set_network 0 %s '"%s"';
        --        wpa_cli -i %s set_network 0 wep_tx_keyidx %s;
        --        wpa_cli -i %s set_network 0 auth_alg SHARED;]],
        --    vif.vifname, vif.vifname, vif.DefaultKeyID_idx,
        --    vif.DefaultKey, vif.vifname, vif.KeyID, vif.vifname)
        elseif vif.AuthMode == "WPA2PSK" then
            if ieee80211w == "1" and vif.EncrypType == "AES" and vif.pmfsha256 == "1" then
                commands = commands .."\n".. string.format([[
                    wpa_cli -i %s set_network 0 proto RSN;
                    wpa_cli -i %s set_network 0 key_mgmt WPA-PSK WPA-PSK-SHA256;
                    wpa_cli -i %s set_network 0 psk '"%s"';
                    wpa_cli -i %s set_network 0 pairwise %s;
                    wpa_cli -i %s set network 0 group %s;
                    wpa_cli -i %s set_network 0 ieee80211w 1;]],
                vif.vifname, vif.vifname, vif.vifname, vif.WPAPSK, vif.vifname,
                get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname, get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname)
            elseif ieee80211w == "2" and vif.EncrypType == "AES" and vif.pmfsha256 == "1" then
                commands = commands .."\n".. string.format([[
                    wpa_cli -i %s set_network 0 proto RSN;
                    wpa_cli -i %s set_network 0 key_mgmt WPA-PSK-SHA256;
                    wpa_cli -i %s set_network 0 psk '"%s"';
                    wpa_cli -i %s set_network 0 pairwise %s;
                    wpa_cli -i %s set network 0 group %s;
                    wpa_cli -i %s set_network 0 ieee80211w 2;]],
                vif.vifname, vif.vifname, vif.vifname, vif.WPAPSK, vif.vifname,
                get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname, get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname)
            else
                commands = commands .."\n".. string.format([[
                    wpa_cli -i %s set_network 0 proto RSN;
                    wpa_cli -i %s set_network 0 key_mgmt WPA-PSK;
                    wpa_cli -i %s set_network 0 psk '"%s"';
                    wpa_cli -i %s set_network 0 pairwise %s;
                    wpa_cli -i %s set network 0 group %s;
                    wpa_cli -i %s set_network 0 ieee80211w %s;]],
                vif.vifname, vif.vifname, vif.vifname, vif.WPAPSK, vif.vifname,
                get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname, get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname, ieee80211w)
            end
         elseif vif.AuthMode == "WPA3PSK" then
            commands = commands .."\n".. string.format([[
                wpa_cli -i %s set sae_pwe 2;
                wpa_cli -i %s set_network 0 proto RSN;
                wpa_cli -i %s set_network 0 sae_password '"%s"';
                wpa_cli -i %s set_network 0 key_mgmt SAE;
                wpa_cli -i %s set_network 0 ieee80211w 2;]],
            vif.vifname, vif.vifname, vif.vifname, vif.WPAPSK, vif.vifname, vif.vifname)
        elseif vif.AuthMode == "WPAPSK" then
            commands = string.format([[
                wpa_cli -i %s set_network 0 proto WPA;
                wpa_cli -i %s set_network 0 key_mgmt WPA-PSK;
                wpa_cli -i %s set_network 0 psk '"%s"';
                wpa_cli -i %s set_network 0 pairwise %s;
                wpa_cli -i %s set network 0 group %s;]],
            vif.vifname, vif.vifname, vif.vifname, vif.WPAPSK, vif.vifname,
            get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
            vif.vifname, get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise)
        else
            error(string.format("invalid AuthMode \"%s\"", vif.AuthMode))
        end

        -- must append extra SSID command to make changes take effect
        commands = commands .."\n".. string.format([[
                wpa_cli -i %s enable_network 0;
                wpa_cli -i %s select_network 0;]], vif.vifname, vif.vifname)
        debug_info_write(devname, commands)
    end
end

function __set_wifi_security(cfgs, diff, device, devname)
    -- to keep it simple, we always reconf the security if anything related is changed.
    -- do optimization only if there's significant performance defect.

    local vifs = {} -- changed vifs

    -- figure out which vif is changed
    -- since multi-bssid is possible, both AuthMode and EncrypType can be a group
    local auth_old = cfgs.AuthMode:split()
    local encr_old = cfgs.EncrypType:split()
    local IEEE8021X_old = cfgs.IEEE8021X:split()
    -- local keyid_old = cfgs.DefaultKeyID:split()
    local pmfmfpc_old = cfgs.PMFMFPC:split()
    local pmfmfpr_old = cfgs.PMFMFPR:split()
    local pmfsha256_old = cfgs.PMFSHA256:split()
    local auth_new = {}
    local auth_new1 = {}
    local encr_new = {}
    local encr_new1 = {}
    local IEEE8021X_new ={}
    local IEEE8021X_new1 ={}
    -- local keyid_new = {}
    -- local keyid_new1 = {}
    local pmfmfpc_new = {}
    local pmfmfpc_new1 = {}
    local pmfmfpr_new = {}
    local pmfmfpr_new1 = {}
    local pmfsha256_new = {}
    local pmfsha256_new1 = {}

    if diff.EncrypType then
        encr_new = diff.EncrypType[2]:split()
        encr_new1 = encr_new[1]:split(";")
    end
    if diff.AuthMode then
        auth_new = diff.AuthMode[2]:split()
        auth_new1 = auth_new[1]:split(";")
    end
    if diff.IEEE8021X then
        IEEE8021X_new = diff.IEEE8021X[2]:split()
        IEEE8021X_new1 = IEEE8021X_new[1]:split(";")
    end
    -- if diff.DefaultKeyID then
    --    keyid_new = diff.DefaultKeyID[2]:split()
    --    keyid_new1 = keyid_new[1]:split(";")
    -- end
    if diff.PMFMFPC then
        pmfmfpc_new = diff.PMFMFPC[2]:split()
        pmfmfpc_new1 = pmfmfpc_new[1]:split(";")
    end
    if diff.PMFMFPR then
        pmfmfpr_new = diff.PMFMFPR[2]:split()
        pmfmfpr_new1 = pmfmfpr_new[1]:split(";")
    end
    if diff.PMFSHA256 then
        pmfsha256_new = diff.PMFSHA256[2]:split()
        pmfsha256_new1 = pmfsha256_new[1]:split(";")
    end

    -- For WPA/WPA2
    local RadiusS_old = cfgs.RADIUS_Server:split() or {}
    local RadiusP_old = cfgs.RADIUS_Port:split() or {}
    local RadiusS_old_i = (RadiusS_old[1] or ''):split(";")
    local RadiusP_old_i = (RadiusP_old[1] or ''):split(";")
    local RadiusS_new = diff.RADIUS_Server and diff.RADIUS_Server[2]:split() or RadiusS_old
    local RadiusP_new = diff.RADIUS_Port and diff.RADIUS_Port[2]:split() or RadiusP_old
    local RadiusS_new_i = (RadiusS_new[1] or ''):split(";") --split by ";"
    local RadiusP_new_i = (RadiusP_new[1] or ''):split(";")

    local auth_old1 = auth_old[1]:split(";") --auth_old1[1]=OPEN,auth_old1[2]=WPA2PSK
    local encr_old1 = encr_old[1]:split(";")
    local IEEE8021X_old1 =IEEE8021X_old[1]:split(";")
    -- local keyid_old1 =keyid_old[1]:split(";")
    local pmfmfpc_old1 =pmfmfpc_old[1]:split(";")
    local pmfmfpr_old1 =pmfmfpr_old[1]:split(";")
    local pmfsha256_old1 =pmfsha256_old[1]:split(";")

    for i = 1, #encr_old1 do
        local changed = false
        if next(auth_new) and auth_old1[i] ~= auth_new1[i] then
            changed = true
        elseif next(encr_new) and encr_old1[i] ~= encr_new1[i] then
            changed = true
        elseif next(IEEE8021X_new) and IEEE8021X_old1[i] ~= IEEE8021X_new1[i] then
            changed = true
        -- elseif next(keyid_new) and keyid_old1[i] ~= keyid_new1[i] then
        --    changed = true
        elseif next(pmfmfpc_new) and pmfmfpc_old1[i] ~= pmfmfpc_new1[i] then
            changed = true
        elseif next(pmfmfpr_new) and pmfmfpr_old1[i] ~= pmfmfpr_new1[i] then
            changed = true
        elseif next(pmfsha256_new) and pmfsha256_old1[i] ~= pmfsha256_new1[i] then
            changed = true
        elseif diff["WPAPSK"..tostring(i)] then
            changed = true
        elseif next(RadiusS_new) and RadiusS_old_i[i] ~= RadiusS_new_i[i] then
            changed = true
        elseif next(RadiusP_new) and RadiusP_old_i[i] ~= RadiusP_new_i[i] then
            changed = true
        elseif diff["RADIUS_Key"..tostring(i)] then
            changed = true
        else
            for j = 1, 4 do
                if diff["Key"..tostring(j).."Str"..tostring(i)] then
                    changed = true
                    break
                end
            end
        end

        if changed then
            local vif = {}
            vif.idx = i
            vif.vifname = device.ext_ifname..tostring(i-1)
            vif.AuthMode = auth_new1 and auth_new1[i] or auth_old1[i]
            vif.EncrypType = encr_new1 and encr_new1[i] or encr_old1[i]
            -- vif.KeyID = keyid_new1 and keyid_new1[i] or keyid_old1[i]
            vif.PMFMFPC = pmfmfpc_new1 and pmfmfpc_new1[i] or pmfmfpc_old1[i]
            vif.PMFMFPR = pmfmfpr_new1 and pmfmfpr_new1[i] or pmfmfpr_old1[i]
            vif.PMFSHA256 = pmfsha256_new1 and pmfsha256_new1[i] or pmfsha256_old1[i]
            -- vif.DefaultKeyID_idx = "wep_key"..tostring(vif.KeyID)
            -- vif.DefaultKey = diff["Key"..tostring(vif.KeyID).."Str"..tostring(i)] and
            --            diff["Key"..tostring(vif.KeyID).."Str"..tostring(i)][2] or cfgs["Key"..tostring(vif.KeyID).."Str"..tostring(i)]
            --vif.WEPType = "WEP"..tostring(vif.KeyID).."Type"
            --vif.WEPTypeVal = diff["WEP"..tostring(vif.KeyID).."Type"..tostring(i)] and
            --            diff["WEP"..tostring(vif.KeyID).."Type"..tostring(i)][2] or cfgs["WEP"..tostring(vif.KeyID).."Type"..tostring(i)]
            vif.WPAPSK = diff["WPAPSK"..tostring(i)] and diff["WPAPSK"..tostring(i)][2] or cfgs["WPAPSK"..tostring(i)]
            vif.SSID = diff["SSID"..tostring(i)] and diff["SSID"..tostring(i)][2] or cfgs["SSID"..tostring(i)]
            vif.IEEE8021X = IEEE8021X_new1 and IEEE8021X_new1[i] or IEEE8021X_old1[i]
            vif.RADIUS_Server = RadiusS_new_i and RadiusS_new_i[i] or RadiusS_old_i[i]
            vif.RADIUS_Port = RadiusP_new_i and RadiusP_new_i[i] or RadiusP_old_i[i]
            vif.RADIUS_Key = diff["RADIUS_Key"..tostring(i)] and diff["RADIUS_Key"..tostring(i)][2] or cfgs["RADIUS_Key"..tostring(i)]
            table.insert(vifs, vif)
        end
    end

    -- iwpriv here
    for i, vif in ipairs(vifs) do
        local ieee80211w = get_ieee80211w(vif.PMFMFPC, vif.PMFMFPR)
        if vif.AuthMode == "OPEN" then
            --if vif.EncrypType == "WEP" then
            --    commands = string.format([[
            --    hostapd_cli -i %s set eap_server 1;
            --    hostapd_cli -i %s set auth_algs 1;
            --    hostapd_cli -i %s set wpa 0;
            --    hostapd_cli -i %s set %s "%s";
            --    hostapd_cli -i %s wep_default_key %s;]],
            --vif.vifname, vif.vifname, vif.vifname,
            --vif.vifname, vif.DefaultKeyID_idx, vif.DefaultKey,
            --vif.vifname, vif.KeyID)
            --elseif vif.EncrypType == "NONE" and vif.IEEE8021X == "1" then
            if vif.EncrypType == "NONE" and vif.IEEE8021X == "1" then
                commands = string.format([[
                hostapd_cli -i %s set eap_server 1;
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set auth_server_addr %s;
                hostapd_cli -i %s set auth_server_port %s;
                hostapd_cli -i %s set auth_server_shared_secret %s;]],
            vif.vifname, vif.vifname, vif.vifname, vif.RADIUS_Server,
            vif.vifname, vif.RADIUS_Port, vif.vifname, vif.RADIUS_Key)
            else
                commands = string.format([[
                hostapd_cli -i %s set eap_server 1;
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set wpa 0;]],
            vif.vifname, vif.vifname, vif.vifname)
            end
        --elseif vif.AuthMode == "WEPAUTO" and vif.EncrypType == "WEP" then
        --        commands = string.format([[
        --        hostapd_cli -i %s set eap_server 1;
        --        hostapd_cli -i %s set auth_algs 3;
        --        hostapd_cli -i %s set wpa 0;
        --        hostapd_cli -i %s set %s "%s";
        --        hostapd_cli -i %s wep_default_key %s;]],
        --    vif.vifname, vif.vifname, vif.vifname,
        --    vif.vifname, vif.DefaultKeyID_idx, vif.DefaultKey,
        --    vif.vifname, vif.KeyID,vif.vifname)
        elseif vif.AuthMode == "OWE" then
            commands = string.format([[
                hostapd_cli -i %s set eap_server 1;
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set wpa 2;
                hostapd_cli -i %s set ieee80211w 2;
                hostapd_cli -i %s set wpa_key_mgmt OWE;
                hostapd_cli -i %s set rsn_pairwise CCMP;]],
            vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname)
        -- elseif vif.AuthMode == "SHARED" then
        --    commands = string.format([[
        --        hostapd_cli -i %s set eap_server 1;
        --        hostapd_cli -i %s set auth_algs 2;
        --        hostapd_cli -i %s set wpa 0;
        --        hostapd_cli -i %s set %s "%s";
        --        hostapd_cli -i %s wep_default_key %s;]],
        --    vif.vifname, vif.vifname, vif.vifname,
        --    vif.vifname, vif.DefaultKeyID_idx, vif.DefaultKey,
        --    vif.vifname, vif.KeyID, vif.vifname)
        elseif vif.AuthMode == "WPA2PSK" then
            if ieee80211w == "1" and vif.EncrypType == "AES" and vif.PMFSHA256 == "1" then
                commands = string.format([[
                    hostapd_cli -i %s set eap_server 1;
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w 1;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-PSK,WPA-PSK-SHA256;
                    hostapd_cli -i %s set rsn_pairwise %s;
                    hostapd_cli -i %s set wpa_passphrase %s;]],
                vif.vifname,
                vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname,
                get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise, vif.vifname, vif.WPAPSK)
            elseif ieee80211w == "2" and vif.EncrypType == "AES" then
                commands = string.format([[
                    hostapd_cli -i %s set eap_server 1;
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w 2;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-PSK-SHA256;
                    hostapd_cli -i %s set rsn_pairwise %s;
                    hostapd_cli -i %s set wpa_passphrase %s;]],
                vif.vifname, vif.vifname,
                vif.vifname, vif.vifname, vif.vifname, vif.vifname,
                get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise, vif.vifname, vif.WPAPSK)
            else
                commands = string.format([[
                    hostapd_cli -i %s set eap_server 1;
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w %s;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-PSK;
                    hostapd_cli -i %s set rsn_pairwise %s;
                    hostapd_cli -i %s set wpa_passphrase %s;]],
                vif.vifname, vif.vifname, vif.vifname, vif.vifname, ieee80211w, vif.vifname, vif.vifname,
                get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise, vif.vifname, vif.WPAPSK)
            end
         elseif vif.AuthMode == "WPA3PSK" then
            commands = string.format([[
                hostapd_cli -i %s set eap_server 1;
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set wpa 2;
                hostapd_cli -i %s set ieee80211w 2;
                hostapd_cli -i %s set wpa_key_mgmt SAE;
                hostapd_cli -i %s set rsn_pairwise CCMP;
                hostapd_cli -i %s set sae_password %s;
                hostapd_cli -i %s set wpa_passphrase %s;]],
            vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname,
            vif.WPAPSK, vif.vifname, vif.WPAPSK)
        elseif vif.AuthMode == "WPAPSKWPA2PSK" then
            commands = string.format([[
                hostapd_cli -i %s set eap_server 1;
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set wpa 3;
                hostapd_cli -i %s set wpa_key_mgmt WPA-PSK;
                hostapd_cli -i %s set rsn_pairwise %s;
                hostapd_cli -i %s set wpa_pairwise %s;
                hostapd_cli -i %s set sae_password %s;
                hostapd_cli -i %s set wpa_passphrase %s;]],
                vif.vifname, vif.vifname, vif.vifname, vif.vifname,
                vif.vifname, get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname, get_hostapd_obj("WPA2PSK", vif.EncrypType).rsn_pairwise,
                vif.vifname, vif.WPAPSK,
                vif.vifname, vif.WPAPSK)
        elseif vif.AuthMode == "WPA2PSKWPA3PSK" then
            commands = string.format([[
                hostapd_cli -i %s set eap_server 1;
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set wpa 2;
                hostapd_cli -i %s set ieee80211w 1;
                hostapd_cli -i %s set wpa_key_mgmt SAE,WPA-PSK;
                hostapd_cli -i %s set rsn_pairwise CCMP;
                hostapd_cli -i %s set sae_password %s;
                hostapd_cli -i %s set wpa_passphrase %s;
                mwctl %s set ap_security rekeymethod=time;]],
                vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname,
                vif.vifname, vif.WPAPSK,
                vif.vifname, vif.WPAPSK,
                vif.vifname)
        elseif vif.AuthMode == "WPA2" then
            if ieee80211w == "1" and vif.EncrypType == "AES" and vif.PMFSHA256 == "1" then
                commands = string.format([[
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w %s;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-EAP,WPA-EAP-SHA256;
                    hostapd_cli -i %s set rsn_pairwise %s;
                    hostapd_cli -i %s set eap_server 0;
                    hostapd_cli -i %s set auth_server_addr %s;
                    hostapd_cli -i %s set auth_server_port %s;
                    hostapd_cli -i %s set auth_server_shared_secret %s;]],
                    vif.vifname, vif.vifname,
                    vif.vifname, get_ieee80211w(vif.PMFMFPC, vif.PMFMFPR),
                    vif.vifname,
                    vif.vifname, get_hostapd_obj("WPA2", vif.EncrypType).rsn_pairwise,
                    vif.vifname,
                    vif.vifname, vif.RADIUS_Server,
                    vif.vifname, vif.RADIUS_Port,
                    vif.vifname, vif.RADIUS_Key)
            elseif ieee80211w == "2" and vif.EncrypType == "AES" then
                commands = string.format([[
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w %s;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-EAP-SHA256;
                    hostapd_cli -i %s set rsn_pairwise %s;
                    hostapd_cli -i %s set eap_server 0;
                    hostapd_cli -i %s set auth_server_addr %s;
                    hostapd_cli -i %s set auth_server_port %s;
                    hostapd_cli -i %s set auth_server_shared_secret %s;]],
                    vif.vifname, vif.vifname,
                    vif.vifname, get_ieee80211w(vif.PMFMFPC, vif.PMFMFPR),
                    vif.vifname,
                    vif.vifname, get_hostapd_obj("WPA2", vif.EncrypType).rsn_pairwise,
                    vif.vifname,
                    vif.vifname, vif.RADIUS_Server,
                    vif.vifname, vif.RADIUS_Port,
                    vif.vifname, vif.RADIUS_Key)
            else
                commands = string.format([[
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w %s;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-EAP;
                    hostapd_cli -i %s set rsn_pairwise %s;
                    hostapd_cli -i %s set eap_server 0;
                    hostapd_cli -i %s set auth_server_addr %s;
                    hostapd_cli -i %s set auth_server_port %s;
                    hostapd_cli -i %s set auth_server_shared_secret %s;]],
                    vif.vifname, vif.vifname,
                    vif.vifname, get_ieee80211w(vif.PMFMFPC, vif.PMFMFPR),
                    vif.vifname,
                    vif.vifname, get_hostapd_obj("WPA2", vif.EncrypType).rsn_pairwise,
                    vif.vifname,
                    vif.vifname, vif.RADIUS_Server,
                    vif.vifname, vif.RADIUS_Port,
                    vif.vifname, vif.RADIUS_Key)
            end
        elseif vif.AuthMode == "WPA3" then
            if ieee80211w == "1" and vif.PMFSHA256 == "1" then
                commands = string.format([[
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w 2;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-EAP,WPA-EAP-SHA256;
                    hostapd_cli -i %s set rsn_pairwise CCMP;
                    hostapd_cli -i %s set eap_server 0;
                    hostapd_cli -i %s set auth_server_addr %s;
                    hostapd_cli -i %s set auth_server_port %s;
                    hostapd_cli -i %s set auth_server_shared_secret %s;]],
                    vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname,
                    vif.vifname, vif.RADIUS_Server,
                    vif.vifname, vif.RADIUS_Port,
                    vif.vifname, vif.RADIUS_Key)
            elseif ieee80211w == "2" and vif.PMFSHA256 == "1" then
                commands = string.format([[
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w 2;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-EAP-SHA256;
                    hostapd_cli -i %s set rsn_pairwise CCMP;
                    hostapd_cli -i %s set eap_server 0;
                    hostapd_cli -i %s set auth_server_addr %s;
                    hostapd_cli -i %s set auth_server_port %s;
                    hostapd_cli -i %s set auth_server_shared_secret %s;]],
                    vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname,
                    vif.vifname, vif.RADIUS_Server,
                    vif.vifname, vif.RADIUS_Port,
                    vif.vifname, vif.RADIUS_Key)
            else
                commands = string.format([[
                    hostapd_cli -i %s set auth_algs 1;
                    hostapd_cli -i %s set wpa 2;
                    hostapd_cli -i %s set ieee80211w 2;
                    hostapd_cli -i %s set wpa_key_mgmt WPA-EAP;
                    hostapd_cli -i %s set rsn_pairwise CCMP;
                    hostapd_cli -i %s set eap_server 0;
                    hostapd_cli -i %s set auth_server_addr %s;
                    hostapd_cli -i %s set auth_server_port %s;
                    hostapd_cli -i %s set auth_server_shared_secret %s;]],
                    vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname,
                    vif.vifname, vif.RADIUS_Server,
                    vif.vifname, vif.RADIUS_Port,
                    vif.vifname, vif.RADIUS_Key)
            end
        elseif vif.AuthMode == "WPA1WPA2" then
            commands = string.format([[
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set wpa 3;
                hostapd_cli -i %s set ieee80211w %s;
                hostapd_cli -i %s set wpa_key_mgmt WPA-EAP;
                hostapd_cli -i %s set wpa_pairwise %s;
                hostapd_cli -i %s set rsn_pairwise %s;
                hostapd_cli -i %s set eap_server 0;
                hostapd_cli -i %s set auth_server_addr %s;
                hostapd_cli -i %s set auth_server_port %s;
                hostapd_cli -i %s set auth_server_shared_secret %s;]],
                vif.vifname, vif.vifname,
                vif.vifname, get_ieee80211w(vif.PMFMFPC, vif.PMFMFPR),
                vif.vifname,
                vif.vifname, get_hostapd_obj("WPA1WPA2", vif.EncrypType).rsn_pairwise,
                vif.vifname, get_hostapd_obj("WPA1WPA2", vif.EncrypType).rsn_pairwise,
                vif.vifname,
                vif.vifname, vif.RADIUS_Server,
                vif.vifname, vif.RADIUS_Port,
                vif.vifname, vif.RADIUS_Key)
        elseif vif.AuthMode == "WPA3-192" then
            commands = string.format([[
                hostapd_cli -i %s set auth_algs 1;
                hostapd_cli -i %s set wpa 2;
                hostapd_cli -i %s set ieee80211w 2;
                hostapd_cli -i %s set wpa_key_mgmt WPA-EAP-SUITE-B-192;
                hostapd_cli -i %s set rsn_pairwise GCMP-256;
                hostapd_cli -i %s set group_cipher GCMP-256;
                hostapd_cli -i %s set group_mgmt_cipher BIP-GMAC-256;
                hostapd_cli -i %s set eap_server 0;
                hostapd_cli -i %s set auth_server_addr %s;
                hostapd_cli -i %s set auth_server_port %s;
                hostapd_cli -i %s set auth_server_shared_secret %s;]],
                vif.vifname, vif.vifname, vif.vifname, vif.vifname, vif.vifname,vif.vifname,
                vif.vifname, vif.vifname,
                vif.vifname, vif.RADIUS_Server,
                vif.vifname, vif.RADIUS_Port,
                vif.vifname, vif.RADIUS_Key)
        else
            error(string.format("invalid AuthMode \"%s\"", vif.AuthMode))
        end

        -- must append extra SSID command to make changes take effect
            commands = commands .."\n".. string.format([[
                hostapd_cli -i %s set ssid '%s';
                hostapd_cli -i %s reload;]],
                vif.vifname, vif.SSID, vif.vifname)
        debug_info_write(devname, commands)
    end
end

--dev cfg, key is dat parm, value is for iwpriv cmd.
function match_dev_parm(key)
    local dat_iw_table = {
            CountryCode = "country code",                --mwctl ra0 set country code=1
            BGProtection = "BGProtection",               --mwctl ra0 set BGProtection=1
            ShortSlot = "ShortSlot",                     --mwctl ra0 set ShortSlot=1
            PktAggregate = "PktAggregate",               --mwctl ra0 set PktAggregate=1
            HT_DisallowTKIP = "HtDisallowTKIP",          --mwctl ra0 set HtDisallowTKIP=1
            HT_MCS = "HtMcs",                            --mwctl ra0 set HtMcs=1
            HT_MpduDensity = "HtMpduDensity",            --mwctl ra0 set HtMpduDensity=1
            HT_RDG = "HtRdg",                            --mwctl ra0 set HtRdg=1
            VOW_Airtime_Fairness_En = "vow atf_en",      --mwctl ra0 set vow atf_en=0

            HT_RxStream = "HtRxStream",                  --mwctl ra0 set HtRxStream=1
            TWTSupport = "twtsupport",
            IndividualTWTSupport = "twtsupport",
            BSSColorValue = "color_dbg",
            VOW_Airtime_Fairness_En = "vow atf_en",       --mwctl ra0 set vow atf_en=<0/1>
            VOW_BW_Ctrl = "vow_bw_enable"                 --mwctl ra0 set vow bw_en=<0/1>
    }

    return dat_iw_table[key]
end

function match_dev_parm_no_ssid(key)
    local dat_iw_table = {
        HT_BADecline = "ba_decline",                 --mwctl ra0 set ba_decline 0
        TxBurst =  "txburst",                        --mwctl ra0 set txburst 0
        HT_BAWinSize = "ba_wsize",                   --mwctl ra0 set ba_wsize 1
        BeaconPeriod = "beacon_int",                 --mwctl ra0 set beacon_int 1
        HT_TxStream = "ht_tx_stream",                --mwctl ra0 set ht_tx_stream 1
    }

    return dat_iw_table[key]
end

function match_vif_parm(key)
    local dat_iw_table = {
        APSDCapable = "UAPSDCapable",                --mwctl ra0 set UAPSDCapable=1          mwctl ra0 set SSID
        HT_GI = "HtGi",                              --mwctl ra0 set HtGi=1                  mwctl ra0 set SSID
        HT_STBC = "HtStbc",                          --mwctl ra0 set HtStbc=1                mwctl ra0 set SSID
        PMKCachePeriod = "PMKCachePeriod",           --mwctl ra0 set PMKCachePeriod          mwctl ra0 set SSID
        PreAuth = "PreAuth",                         --mwctl ra0 set PreAuth                 mwctl ra0 set SSID
        VHT_STBC = "VhtStbc",                        --mwctl ra0 set VhtStbc=1               mwctl ra0 set SSID
        VHT_BW_SIGNAL = "VhtBwSignal",               --mwctl ra0 set VhtBwSignal=1           mwctl ra0 set SSID
     }

    return dat_iw_table[key]
end

function match_vif_parm_need_reload(key)
    local dat_iw_table = {
         MuMimoDlEnable = "mu_dl_en",                --mwctl ra0 set muru_dl_en 0/1     mwctl ra0 set SSID
         MuMimoUlEnable = "mu_ul_en",
         MuOfdmaDlEnable = "muru_dl_en",
         MuOfdmaUlEnable = "muru_ul_en"
    }
    return dat_iw_table[key]
end

function match_vif_parm_no_ssid(key)
    local dat_iw_table = {
        HideSSID = "hide_ssid",                      --mwctl ra0 set hide_ssid 1/0
        HT_PROTECT = "ht_protect",                   --mwctl ra0 set ht_protect
        HT_OpMode = "ht_op_mode",                    --mwctl ra0 set ht_op_mode 1(green field)/0(mix mode)
        HT_AMSDU = "ht_amsdu",                       --mwctl ra0 set ht_amsdu 1
        HT_AutoBA = "ba_auto",                       --mwctl ra0 set ba_auto 1
        PMFSHA256 = "pmf_sha256",                    --mwctl ra0 set pmf_sha256 0
        PMFMFPC = "PMFMFPC",                         --mwctl ra0 set PMFMFPC 0
        PMFMFPR = "PMFMFPR",                         --mwctl ra0 set PMFMFPR 0
        DtimPeriod = "dtim_int",                     --mwctl ra0 set dtim_int 1
    }
    return dat_iw_table[key]
end

function match_vif_parm_need_group(key)
    local dat_iw_table = {
        VOW_Rate_Ctrl_En = "vow bw_ctl_en",
        VOW_Group_Min_Rate = "vow max_rate",
        VOW_Group_Max_Rate = "vow min_rate",
        VOW_Airtime_Ctrl_En = "vow atc_en",
        VOW_Group_Min_Ratio = "vow max_ratio",
        VOW_Group_Max_Ratio = "vow min_ratio",
    }
    return dat_iw_table[key]
end

function __bw(ht_bw, vht_bw, eht_apbw)
    local bw = ""
    if ht_bw == "0" or not ht_bw then
        bw = "20"
    elseif ht_bw == "1" and vht_bw == "0" or not vht_bw then
        bw = "40"
    elseif ht_bw == "1" and vht_bw == "1" then
        bw = "80"
    elseif ht_bw == "1" and vht_bw == "2" then
        if eht_apbw == '3' then
            bw = "160"
        elseif eht_apbw == '4' then
            bw = "320"
        end
    elseif ht_bw == "1" and vht_bw == "3" then
        bw = "8080MHz"
    end
    return bw
end

function iface_type(iface)
    local dir = io.popen("iw "..iface.." info")
    local num
    if not dir then return "" end
    for line in dir:lines() do
        if string.find(line, 'wiphy') then
            num = string.match(line, "%d")
        end
    end
    return "phy"..num
end

function __any_wsc_enabled(wsc_conf_mode, conf_state)
    local wps_state
    if wsc_conf_mode == "" or wsc_conf_mode == "0" then
        wps_state =  "0"
    elseif wsc_conf_mode == "7" then
        if conf_state == "1" then
            wps_state = "1"
        elseif conf_state == "2" then
            wps_state = "2"
        end
    end
    return wps_state
end

function __set_wifi_misc(cfgs, diff, device,devname)
    local vifname = device.main_ifname
    local vifext = device.ext_ifname
    local vifapcli = device.apcli_ifname
    local vifidx = cfgs.AuthMode:split(";")
    local commands_vifs_mwctl_ssid = false
    local commands_vifs_hostapd_ssid = false
    local commands_ssid = {}
    local commands_ssid_host = {}
    local commands_access_1 = {}
    local commands_access_2 = {} -- for black list
    local commands_ht = false -- for BW, to prevent exexute cmd twice
    local commands_wps = false

    for k,v in pairs(diff) do
        local current_iface = ""
        local hostapd_reload = false
        local commands, commands_1, commands_2, commandns
        local commands_vifs, val
        if k:find("^SSID") then
            local _,_,i = string.find(k, "^SSID([%d]+)")
                commands = string.format([[
                hostapd_cli -i %s set ssid '%s';]], vifext..tostring(tonumber(i)-1), tostring(v[2]))
                hostapd_reload = true
                current_iface = vifext..tostring(tonumber(i)-1)
        ----------------------------------------------------------------------------------------------------
                    -----------------------------device config ----------------------------
        elseif k == "CountryRegion" or k == "CountryRegionABand"  then
            commands = string.format([[
                mwctl phy %s set country region=%s;]], iface_type(vifname), tostring(v[2]))
            if cfgs["Channel"] == "0" then
                commands = commands .."\n".. string.format([[
                mwctl %s acs trigger=3;]], vifname)
            end
        elseif k == "Channel" or k == "channel" then
            if v[2] == "0" then
                commands = string.format([[
                mwctl %s acs trigger=3;]], vifname)
            else
                commands = string.format([[
                mwctl phy %s set channel num=%s;]], iface_type(vifname), tostring(v[2]))
            end
        elseif k == "HT_BSSCoexistence" then
            commands = string.format([[
                mwctl phy %s set channel ht_coex=%s;]], iface_type(vifname), tostring(v[2]))
        elseif k == "AutoChannelSelect" then
            -- do nothing
        elseif k == "PowerUpCckOfdm" or k == "powerupcckOfdm" then
            val = "0:"..v[2]
            commands = string.format([[
                mwctl %s set TxPowerBoostCtrl=%s;]], vifname, tostring(val))
        elseif k == "PowerUpHT20" or k == "powerupht20" then
            val = "1:"..v[2]
            commands = string.format([[
                mwctl %s set TxPowerBoostCtrl=%s;]], vifname, tostring(val))
        elseif k == "PowerUpHT40" or k == "powerupht40" then
            val = "2:"..v[2]
            commands = string.format([[
                mwctl %s set TxPowerBoostCtrl=%s;]], vifname, tostring(val))
        elseif k == "PowerUpVHT20" or k == "powerupvht20" then
            val = "3:"..v[2]
            commands = string.format([[
                mwctl %s set TxPowerBoostCtrl=%s;]], vifname, tostring(val))
        elseif k == "PowerUpVHT40" or k == "powerupvht40" then
            local val = "4:"..v[2]
            commands = string.format([[
                mwctl %s set TxPowerBoostCtrl=%s;]], vifname, tostring(val))
        elseif k == "PowerUpVHT80" or k == "powerupvht80" then
            val = "5:"..v[2]
            commands = string.format([[
                mwctl %s set TxPowerBoostCtrl=%s;]], vifname, tostring(val))
        elseif k == "PowerUpVHT160" or k == "powerupvht160" then
            val = "6:"..v[2]
            commands = string.format([[
                mwctl %s set TxPowerBoostCtrl=%s;]], vifname, tostring(val))
        elseif k == "TxPower" then
            commands = string.format([[
                mwctl %s set pwr TxPower=%s;]], vifname, tostring(v[2]))
        elseif k == "IEEE80211H" then
            commands = string.format([[
                mwctl phy %s set ieee80211h %s;]], iface_type(vifname), tostring(v[2]))
        elseif k == "HT_EXTCHA" then
            commands = string.format([[
                mwctl phy %s set channel ext_chan=%s;]], iface_type(vifname), tostring(v[2])==1 and "above" or "below")
        elseif k == "CountryCode" then
            commands = string.format([[
                mwctl phy %s set country code=%s;]], iface_type(vifname), tostring(v[2]))
        elseif not commands_ht and (k == "HT_BSSCoexistence" or k == "HT_BW" or k == "VHT_BW" or k == "EHT_ApBw") then
            commands_1 = string.format([[
                mwctl phy %s set channel bw=%s;]], iface_type(vifname), __bw(diff["HT_BW"] and tostring(diff["HT_BW"][2]) or cfgs["HT_BW"],
                diff["VHT_BW"] and tostring(diff["VHT_BW"][2]) or cfgs["VHT_BW"],
                diff["EHT_ApBw"] and tostring(diff["EHT_ApBw"][2]) or cfgs["EHT_ApBw"]))
            debug_info_write(devname, commands_1)
            commands_ht = true
        -- Find k in dat_iw_table and return the iwkey for iwpriv.
        elseif  match_dev_parm(k) then
            commands = string.format([[
                mwctl %s set %s=%s;]], vifname, tostring(match_dev_parm(k)), tostring(v[2]))
        -- Don't need to add "="
        elseif match_dev_parm_no_ssid(k) then
            commands = string.format([[
                mwctl %s set %s %s;]], vifname, tostring(match_dev_parm_no_ssid(k)), tostring(v[2]))

        ----------------------------------------------------------------------------------------------------
                    -----------------------------interface config ----------------------------
        elseif k == "IgmpSnEnable" then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
            commands_vifs = string.format([[
                mwctl %s set multicast_snooping enable=%s;]], vifext..tostring(tonumber(i)-1), token(diff[k][2], i))
                debug_info_write(devname, commands_vifs)
              end
            end
        elseif k == "NoForwarding" then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
            commands_vifs = string.format([[
                hostapd_cli -i %s set ap_isolate %s;]], vifext..tostring(tonumber(i)-1), token(diff[k][2], i))
                commands_ssid_host[i] = string.format([[
                hostapd_cli -i %s reload;]], vifext..tostring(tonumber(i)-1))
                debug_info_write(devname, commands_vifs)
                commands_vifs_hostapd_ssid = true
              end
            end
        elseif k == "WmmCapable" then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
            commands_vifs = string.format([[
                hostapd_cli -i %s set wmm_enabled %s;]], vifext..tostring(tonumber(i)-1), token(diff[k][2], i))
              debug_info_write(devname, commands_vifs)
              end
            end
        elseif k == "FragThreshold" then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
            commands_vifs = string.format([[
                iw phy %s set frag %s;]], iface_type(vifext..tostring(tonumber(i)-1)), token(diff[k][2], i))
              debug_info_write(devname, commands_vifs)
              end
            end
        elseif k == "WirelessMode" then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
                  commands_vifs = string.format([[
                      mwctl %s set %s %s;]], vifext..tostring(tonumber(i)-1), "phymode", token(diff[k][2], i))
                  commands_ssid_host[i] = string.format([[
                      hostapd_cli -i %s disable;hostapd_cli -i %s enable;]], vifext..tostring(tonumber(i)-1), vifext..tostring(tonumber(i)-1))
                  debug_info_write(devname, commands_vifs)
                  commands_vifs_hostapd_ssid = true
              end
            end
        elseif not commands_wps and (k == "WscConfMode" or k == "WscConfStatus") then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
            commands_vifs = string.format([[
                hostapd_cli -i %s set wps_state %s;]], vifext..tostring(tonumber(i)-1),
                __any_wsc_enabled(diff["WscConfMode"] and tostring(token(diff["WscConfMode"][2], i)) or token(cfgs["WscConfMode"], i),
                            diff["WscConfStatus"] and tostring(token(diff["WscConfStatus"][2], i)) or token(cfgs["WscConfStatus"], i)))
                commands_ssid_host[i] = string.format([[
                hostapd_cli -i %s disable;hostapd_cli -i %s enable;]], vifext..tostring(tonumber(i)-1), vifext..tostring(tonumber(i)-1))
                debug_info_write(devname, commands_vifs)
                commands_vifs_hostapd_ssid = true
              end
              commands_wps = true
            end
        elseif k == "RTSThreshold" then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
            commands_vifs = string.format([[
                iw phy %s set rts %s;]], iface_type(vifext..tostring(tonumber(i)-1)), token(diff[k][2], i))
                debug_info_write(devname, commands_vifs)
              end
            end
        -- Common case, set vif parameter and it's ssid
        elseif match_vif_parm(k) then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
                commands_vifs = string.format([[
                mwctl %s set %s=%s;]], vifext..tostring(tonumber(i)-1), tostring(match_vif_parm(k)), token(diff[k][2], i))
                commands_ssid[i] = string.format([[
                mwctl %s set SSID='%s';]], vifext..tostring(tonumber(i)-1), diff["SSID"..tostring(i)] and
                        tostring(diff["SSID"..tostring(i)][2]) or cfgs["SSID"..tostring(i)])
                debug_info_write(devname, commands_vifs)
                commands_vifs_mwctl_ssid = true
              end
            end
        elseif match_vif_parm_need_group(k) then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
                commands_vifs = string.format([[
                mwctl ra0 set %s=%s-%s;]], tostring(match_vif_parm_need_group(k)),  tostring(tonumber(i)-1), token(diff[k][2], i))
                debug_info_write(devname, commands_vifs)
              end
            end
        -- Don't need to set SSID, it will take effect immediately after iwpriv
        elseif match_vif_parm_no_ssid(k) then
            for i=1, #vifidx  do
              if token(cfgs[k], i) ~= token(diff[k][2], i) then
                commands_vifs = string.format([[
                mwctl %s set %s %s;]], vifext..tostring(tonumber(i)-1), tostring(match_vif_parm_no_ssid(k)), token(diff[k][2], i))
                debug_info_write(devname, commands_vifs)
              end
            end

        -- Special case : need to set multiple parameters at the same time when one parameter changed
        elseif k == "RekeyInterval" or k == "rekeyinterval" then
            for i=1, #vifidx  do
              if token(cfgs.RekeyInterval, i) ~= token(diff.RekeyInterval[2], i) then
                local commands_time = string.format([[
                mwctl %s set ap_security rekeymethod="time";]], vifext..tostring(tonumber(i)-1))
                debug_info_write(devname, commands_time)
              end
            end
        -- Special case : need to set multiple parameters at the same time when one parameter changed
        elseif k:find("AccessPolicy") then
            local index = string.match(k, '%d')
            if commands_access_2[index] then break end
            commands_vifs = string.format([[
                    mwctl %s acl policy=%s;]], vifext..tostring(index), tostring(v[2]))
            debug_info_write(devname, commands_vifs)
            if v[2] == '0' then break end
            -- Delete all entry first
            local commands_del_list = string.format([[
                    mwctl %s acl clear_all;]], vifext..tostring(index))
            debug_info_write(devname, commands_del_list)
            local list_old = cfgs["AccessControlList"..tostring(index)] or {}
            local list_old_i = (list_old or ''):split(";")
            if diff["AccessControlList"..tostring(index)] then
                local list_new = diff["AccessControlList"..tostring(index)] and diff["AccessControlList"..tostring(index)][2] or {}
                local list_new_i = (list_new or ''):split(";")
                for i=1, #list_new_i do
                    local commands_aclist = string.format([[
                    mwctl %s acl add=%s;]], vifext..tostring(index), list_new_i[i])
                    debug_info_write(devname, commands_aclist)
                end
            elseif cfgs["AccessControlList"..tostring(index)] and cfgs["AccessControlList"..tostring(index)] ~= "" then
                for i=1, #list_old_i do
                    local commands_aclist = string.format([[
                    mwctl %s acl add=%s;]], vifext..tostring(index), list_old_i[i])
                    debug_info_write(devname, commands_aclist)
                end
            end
            commands_access_1[index] = true
        elseif k:find("AccessControlList") then
            local index = string.match(k, '%d')
            if commands_access_1[index] then break end
            -- Clear all entry first
            local commands_del_list = string.format([[
                    mwctl %s acl clear_all;]], vifext..tostring(index))
            debug_info_write(devname, commands_del_list)
            -- Then add entries
            local commands_ac = string.format([[
                    mwctl %s acl policy=%s;]], vifext..tostring(index),  diff["AccessPolicy"..tostring(index)]
                and tostring(diff["AccessPolicy"..tostring(index)][2]) or cfgs["AccessPolicy"..tostring(index)])
            debug_info_write(devname, commands_ac)
            local list_new = diff["AccessControlList"..tostring(index)] and diff["AccessControlList"..tostring(index)][2] or {}
            local list_new_i = (list_new or ''):split(";")
            if diff["AccessControlList"..tostring(index)] and #list_new_i > 0 then
                for i=1, #list_new_i do
                    local commands_aclist = string.format([[
                    mwctl %s acl add=%s;]], vifext..tostring(index), list_new_i[i])
                    debug_info_write(devname, commands_aclist)
                end
            end
            commands_access_2[index] = true
        end

        if commands then
            debug_info_write(devname, commands)
        end

        if hostapd_reload then
            debug_info_write(devname, string.format([[
                hostapd_cli -i %s reload;]], current_iface))
        end
    end

    if commands_vifs_mwctl_ssid then
        for i=1, #vifidx  do
            if commands_ssid[i] then
                debug_info_write(devname, commands_ssid[i])
            end
        end
    end

    if commands_vifs_hostapd_ssid then
        for i=1, #vifidx  do
            if commands_ssid_host[i] then
                debug_info_write(devname, commands_ssid_host[i])
            end
        end
    end

end

function __set_he_mu(cfgs, diff, device,devname)
    local vifname
    local ssid
    local changed = false
    local vifext = device.ext_ifname

    local vifidx = cfgs.AuthMode:split(";")

    local commands = ""
    for k,v in pairs(diff) do
        if match_vif_parm_need_reload(k) then
            for i=1, #vifidx do
                if token(cfgs[k], i) ~= token(diff[k][2], i) then
                    vifname = vifext..tostring(tonumber(i)-1)
                    changed = true
                    ssid =  diff["SSID"..tostring(i)] and tostring(diff["SSID"..tostring(i)][2]) or cfgs["SSID"..tostring(i)]
                    commands = commands .."\n".. string.format([[
            mwctl %s set %s %s;]], vifext..tostring(tonumber(i)-1), tostring(match_vif_parm_need_reload(k)), token(diff[k][2], i))
                end
            end
        end
    end

    if changed then
        commands = commands .."\n".. string.format([[
                mwctl %s set SSID='%s';]], vifname, ssid)
        debug_info_write(devname, commands)
    end
end

function quick_settings(devname,path)
    local devs, l1parser = mtkdat.__get_l1dat()
    local path_last, cfgs, diff, device
    assert(l1parser, "failed to parse l1profile!")

    -- If there is't /tmp/mtk/wifi/devname.last, wifi down/wifi up is necessary.
    -- Case 1: The first time wifi setup;
    -- Case 2: When reload wifi by pressing UI button.
    if not mtkdat.exist("/tmp/mtk/wifi/"..string.match(path, "([^/]+)\.dat")..".last") then
        need_downup = true
    end
    -- Copy /tmp/mtk/wifi/devname.applied to /tmp/mtk/wifi/devname.last for diff
    --if not mtkdat.exist("/tmp/mtk/wifi/"..string.match(path, "([^/]+)\.dat")..".applied") then
        --os.execute("cp -f "..path.." "..mtkdat.__profile_previous_settings_path(path))
    --else
        --os.execute("cp -f "..mtkdat.__profile_applied_settings_path(path)..
            --" "..mtkdat.__profile_previous_settings_path(path))
    --end

    -- there are no /tmp/mtk/wifi/devname.last
    if need_downup then return true end

    path_last = mtkdat.__profile_previous_settings_path(path)
    diff =  mtkdat.diff_profile(path_last, path)
    cfgs = mtkdat.load_profile(path_last)
    if not next(diff) then return true end -- diff == nil

    -- It maybe better to save this parms in a new file.
    need_downup_parms = {"HT_LDPC", "VHT_SGI", "VHT_LDPC", "idle_timeout_interval",
                          "E2pAccessMode", "MUTxRxEnable","DLSCapable","VHT_Sec80_Channel",
                          "Wds", "PowerUpenable", "session_timeout_interval", "MapMode",
                          "ChannelGrp","TxOP","MldGroup", "HideSSID","TxPreamble"}
    for k, v in pairs(diff) do
        nixio.syslog("debug", "quick_settings diff : "..k.."="..v[2])
        for _, pat in ipairs(need_downup_parms) do
            if string.find(k, pat) then
                need_downup = true;
                nixio.syslog("debug", "quick_settings: need_downup "..k.."="..v[2])
                break
            end
        end
        if need_downup then break end
    end

    -- WirelessMode or BW is set per BSS for old or new cfg, need down/up forcibly
    if diff.WirelessMode and
       ((diff.WirelessMode[1] and #diff.WirelessMode[1]:split(";") > 1) or
        (diff.WirelessMode[2] and #diff.WirelessMode[2]:split(";") > 1)) then
            need_downup = true
    end
    if diff.HT_BW and
       ((diff.HT_BW[1] and #diff.HT_BW[1]:split(";") > 1) or
        (diff.HT_BW[2] and #diff.HT_BW[2]:split(";") > 1)) then
            need_downup = true
    end
    if diff.VHT_BW and
       ((diff.VHT_BW[1] and #diff.VHT_BW[1]:split(";") > 1) or
        (diff.VHT_BW[2] and #diff.VHT_BW[2]:split(";") > 1)) then
            need_downup = true
    end
    if diff.EHT_ApBw and
       ((diff.EHT_ApBw[1] and #diff.EHT_ApBw[1]:split(";") > 1) or
        (diff.EHT_ApBw[2] and #diff.EHT_ApBw[2]:split(";") > 1)) then
            need_downup = true
    end

    -- if wps state is 1 or 2 for certain BSS, need down up forcibly
    if string.find(cfgs["WscConfMode"], "7") ~= nil then
        need_downup = true
    end

    if need_downup then return true end

    -- Quick Setting
    os.execute("rm -rf /tmp/mtk/wifi/"..devname.."_quick_setting_cmd.sh")
    device = devs.devname_ridx[devname]

    -- need to set Authmode and Encry before MFPC&MFPR
    if cfgs["ApCliEnable"] and cfgs["ApCliEnable"] == "1" or
        diff["ApCliEnable"] and diff["ApCliEnable"][2] =="1" then
        __set_wifi_apcli_security(cfgs, diff, device, devname)
    end

    __set_wifi_misc(cfgs, diff, device, devname)

    __set_he_mu(cfgs, diff, device, devname)

    -- security is complicated enough to get a special API
    __set_wifi_security(cfgs, diff, device, devname)

    --execute all iwpriv cmd
    os.execute("sh /tmp/mtk/wifi/"..devname.."_quick_setting_cmd.sh")

    -- save the quick seting log, we assume it can hold up to 10000 at most.
    if mtkdat.exist("/tmp/mtk/wifi/"..devname.."_quick_setting_cmd.sh") then
        if mtkdat.exist("/tmp/mtk/wifi/quick_setting_cmds.log") then
            filesize = GetFileSize("/tmp/mtk/wifi/quick_setting_cmds.log")
            if filesize > 10000 then
                os.execute("mv -f /tmp/mtk/wifi/quick_setting_cmds.log /tmp/mtk/wifi/quick_setting_cmds_bak.log")
            end
        end
        os.execute("echo ............................................... >> /tmp/mtk/wifi/quick_setting_cmds.log")
        os.execute("cat /tmp/mtk/wifi/"..devname.."_quick_setting_cmd.sh >> /tmp/mtk/wifi/quick_setting_cmds.log")
    end
    return false
end
