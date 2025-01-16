#!/bin/ash

interface=$1    # phy0/phy1/ra0
cmd_type=$2     # set/show/e2p/mac
full_cmd=$3
interface_ori=${interface}
start_idx_7986="0"

work_mode="RUN" # RUN/PRINT/DEBUG
iwpriv_file="/tmp/iwpriv_wrapper"
interface_file="/tmp/interface"
phy_idx=$(echo ${interface} | tr -dc '0-9')

function do_cmd() {
    case ${work_mode} in
        "RUN")
            eval "$1"
            ;;
        "PRINT")
            echo "$1"
            ;;
        "DEBUG")
            echo "$1"
            eval "$1"
            ;;
    esac
}

function print_debug() {
    if [ "${work_mode}" = "DEBUG" ]; then
        echo "$1"
    fi
}

function write_dmesg() {
    echo "$1" > /dev/kmsg
}

function record_config() {
    local config=$1
    local tmp_file=$3

    # check is mt7986 or mt7915/7916, and write its config
    if [ ${config} != "STARTIDX" ]; then
        if [ $phy_idx -lt $start_idx_7986 ]; then
            config="${config}_PCIE"
        elif [ $phy_idx -ge $start_idx_7986 ]; then
            config="${config}_7986"
        fi
    fi

    if [ -f ${tmp_file} ]; then
        if grep -q ${config} ${tmp_file}; then
            sed -i "/${config}/c\\${config}=$2" ${tmp_file}
        else
            echo "${config}=$2" >> ${tmp_file}
        fi
    else
        echo "${config}=$2" >> ${tmp_file}
    fi
}

function get_config() {
    local config=$1
    local tmp_file=$2

    if [ ! -f ${tmp_file} ]; then
        echo ""
        return
    fi

    # check is mt7986 or mt7915/7916, and load its config
    if [ ${config} != "STARTIDX" ]; then
        if [ $phy_idx -lt $start_idx_7986 ]; then
            config="${config}_PCIE"
        elif [ $phy_idx -ge $start_idx_7986 ]; then
            config="${config}_7986"
        fi
    fi

    if grep -q ${config} ${tmp_file}; then
        echo "$(cat ${tmp_file} | grep ${config} | sed s/=/' '/g | cut -d " " -f 2)"
    else
        echo ""
    fi
}

function convert_interface {
    start_idx_7986=$(get_config "STARTIDX" ${interface_file})
    local eeprom_file=/sys/kernel/debug/ieee80211/phy0/mt76/eeprom
    if [ -z "${start_idx_7986}" ]; then
        if [ ! -z "$(head -c 2 ${eeprom_file} | hexdump | grep "7916")" ]; then
            start_idx_7986="2"
        elif [ ! -z "$(head -c 2 ${eeprom_file} | hexdump | grep "7915")" ]; then
            start_idx_7986="1"
        elif [ ! -z "$(head -c 2 ${eeprom_file} | hexdump | grep "7986")" ]; then
            start_idx_7986="0"
        else
            echo "Interface Conversion Failed!"
            echo "Please use iwpriv <phy0/phy1/..> set <...> or configure the sku of your board manually by the following commands"
            echo "For AX6000: echo STARTIDX=0 >> ${interface_file}"
            echo "For AX7800: echo STARTIDX=2 >> ${interface_file}"
            echo "For AX8400: echo STARTIDX=1 >> ${interface_file}"
            exit 0
        fi
        record_config "STARTIDX" ${start_idx_7986} ${interface_file}
    fi

    if [[ $1 == "raix"* ]]; then
        phy_idx=1
    elif [[ $1 == "rai"* ]]; then
        phy_idx=0
    elif [[ $1 == "rax"* ]]; then
        phy_idx=$((start_idx_7986+1))
    else
        phy_idx=$start_idx_7986
    fi

    # convert phy index according to band idx
    local band_idx=$(get_config "ATECTRLBANDIDX" ${iwpriv_file})
    if [ "${band_idx}" = "0" ]; then
        if [[ $1 == "raix"* ]]; then
            phy_idx=0
        elif [[ $1 == "rax"* ]]; then
            phy_idx=$start_idx_7986
        fi
    elif [ "${band_idx}" = "1" ]; then
        if [[ $1 == "rai"* ]]; then
            phy_idx=1
        elif [[ $1 == "ra"* ]]; then
            phy_idx=$((start_idx_7986+1))
        fi
    fi

    interface="phy${phy_idx}"
}

function change_band_idx {
    local new_idx=$1
    local new_phy_idx=$phy_idx

    local old_idx=$(get_config "ATECTRLBANDIDX" ${iwpriv_file})


    if [[ ${interface_ori} == "ra"* ]]; then
        if [ -z "${old_idx}" ] || [ "${old_idx}" != "${new_idx}" ]; then
            if [ "${new_idx}" = "0" ]; then
                # raix0 & rai0 becomes rai0
                if [[ $interface_ori == "rai"* ]]; then
                    new_phy_idx=0
                # rax0 & ra0 becomes ra0
                elif [[ $interface_ori == "ra"* ]]; then
                    new_phy_idx=$start_idx_7986
                fi
            elif [ "${new_idx}" = "1" ]; then
                # raix0 & rai0 becomes raix0
                if [[ $interface_ori == "rai"* ]]; then
                    new_phy_idx=1
                # rax0 & ra0 becomes rax0
                elif [[ $interface_ori == "ra"* ]]; then
                    new_phy_idx=$((start_idx_7986+1))
                fi
            fi
        fi

        if [ ${new_phy_idx} != ${phy_idx} ]; then
            do_ate_work "ATESTOP"
            phy_idx=$new_phy_idx
            interface="phy${phy_idx}"
            do_ate_work "ATESTART"
        fi
    fi
    record_config "ATECTRLBANDIDX" ${new_idx} ${iwpriv_file}
}

function simple_convert() {
    if [ "$1" = "ATETXCNT" ]; then
        echo "tx_count"
    elif [ "$1" = "ATETXLEN" ]; then
        echo "tx_length"
    elif [ "$1" = "ATETXMCS" ]; then
        echo "tx_rate_idx"
    elif [ "$1" = "ATEVHTNSS" ]; then
        echo "tx_rate_nss"
    elif [ "$1" = "ATETXLDPC" ]; then
        echo "tx_rate_ldpc"
    elif [ "$1" = "ATETXSTBC" ]; then
        echo "tx_rate_stbc"
    elif [ "$1" = "ATEPKTTXTIME" ]; then
        echo "tx_time"
    elif [ "$1" = "ATEIPG" ]; then
        echo "tx_ipg"
    elif [ "$1" = "ATEDUTYCYCLE" ]; then
        echo "tx_duty_cycle"
    elif [ "$1" = "ATETXFREQOFFSET" ]; then
        echo "freq_offset"
    else
        echo "undefined"
    fi
}

function convert_tx_mode() {
    if [ "$1" = "0" ]; then
        echo "cck"
    elif [ "$1" = "1" ]; then
        echo "ofdm"
    elif [ "$1" = "2" ]; then
        echo "ht"
    elif [ "$1" = "4" ]; then
        echo "vht"
    elif [ "$1" = "8" ]; then
        echo "he_su"
    elif [ "$1" = "9" ]; then
        echo "he_er"
    elif [ "$1" = "10" ]; then
        echo "he_tb"
    elif [ "$1" = "11" ]; then
        echo "he_mu"
    else
        echo "undefined"
    fi
}

function convert_gi {
    local tx_mode=$1
    local val=$2
    local sgi="0"
    local he_ltf="0"

    case ${tx_mode} in
        "ht"|"vht")
            sgi=${val}
            ;;
        "he_su"|"he_er")
            case ${val} in
                "0")
                    ;;
                "1")
                    he_ltf="1"
                    ;;
                "2")
                    sgi="1"
                    he_ltf="1"
                    ;;
                "3")
                    sgi="2"
                    he_ltf="2"
                    ;;
                "4")
                    he_ltf="2"
                    ;;
                *)
                    echo "unknown gi"
            esac
            ;;
        "he_mu")
            case ${val} in
                "0")
                    he_ltf="2"
                    ;;
                "1")
                    he_ltf="1"
                    ;;
                "2")
                    sgi="1"
                    he_ltf="1"
                    ;;
                "3")
                    sgi="2"
                    he_ltf="2"
                    ;;
                *)
                    echo "unknown gi"
            esac
            ;;
        "he_tb")
            case ${val} in
                "0")
                    sgi="1"
                    ;;
                "1")
                    sgi="1"
                    he_ltf="1"
                    ;;
                "2")
                    sgi="2"
                    he_ltf="2"
                    ;;
                *)
                    echo "unknown gi"
            esac
            ;;
        *)
            print_debug "legacy mode no need gi"
    esac

    do_cmd "mt76-test ${interface} set tx_rate_sgi=${sgi} tx_ltf=${he_ltf}"
}

function convert_channel {
    local ctrl_band_idx=$(get_config "ATECTRLBANDIDX" ${iwpriv_file})
    local ch=$(echo $1 | sed s/:/' '/g | cut -d " " -f 1)
    local bw=$(get_config "ATETXBW" ${iwpriv_file} | cut -d ":" -f 1)
    local bw_str="HT20"
    local base_chan=1
    local control_freq=0
    local base_freq=0

    if [ -z ${ctrl_band_idx} ]; then
        local band=$(echo $1 | sed s/:/' '/g | cut -d " " -f 2)
    else
        local band=$ctrl_band_idx
    fi

    if [[ $1 != *":"* ]] || [ "${band}" = "0" ]; then
        case ${bw} in
            "1")
                if [ "${ch}" -lt "3" ] || [ "${ch}" -gt "12" ]; then
                    local bw_str="HT20"
                else
                    local bw_str="HT40+"
                    ch=$(expr ${ch} - "2")
                fi
                ;;
        esac
        local base_freq=2412
    elif [ "${band}" = "1" ]; then
        case ${bw} in
            "5")
                bw_str="160MHz"
                if [ ${ch} -lt "68" ]; then
                    ch="36"
                elif [ ${ch} -lt "100" ]; then
                    ch="68"
                elif [ ${ch} -lt "132" ]; then
                    ch="100"
                elif [ ${ch} -lt "181" ]; then
                    ch="149"
                fi
                ;;
            "2")
                bw_str="80MHz"
                if [ ${ch} -lt "52" ]; then
                    ch="36"
                elif [ ${ch} -lt "68" ]; then
                    ch="52"
                elif [ ${ch} -lt "84" ]; then
                    ch="68"
                elif [ ${ch} -lt "100" ]; then
                    ch="84"
                elif [ ${ch} -lt "116" ]; then
                    ch="100"
                elif [ ${ch} -lt "132" ]; then
                    ch="116"
                elif [ ${ch} -lt "149" ]; then
                    ch="132"
                elif [ ${ch} -lt "165" ]; then
                    ch="149"
                elif [ ${ch} -lt "181" ]; then
                    ch="165"
                fi
                ;;
            "1")
                if [ ${ch} -lt "44" ]; then
                    ch=$([ "${ch}" -lt "40" ] && echo "36" || echo "40")
                    bw_str=$([ "${ch}" -le "38" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "52" ]; then
                    ch=$([ "${ch}" -lt "48" ] && echo "44" || echo "48")
                    bw_str=$([ "${ch}" -le "46" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "60" ]; then
                    ch=$([ "${ch}" -lt "56" ] && echo "52" || echo "56")
                    bw_str=$([ "${ch}" -le "54" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "68" ]; then
                    ch=$([ "${ch}" -lt "64" ] && echo "60" || echo "64")
                    bw_str=$([ "${ch}" -le "62" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "76" ]; then
                    ch=$([ "${ch}" -lt "72" ] && echo "68" || echo "72")
                    bw_str=$([ "${ch}" -le "70" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "84" ]; then
                    ch=$([ "${ch}" -lt "80" ] && echo "76" || echo "80")
                    bw_str=$([ "${ch}" -le "78" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "92" ]; then
                    ch=$([ "${ch}" -lt "88" ] && echo "84" || echo "88")
                    bw_str=$([ "${ch}" -le "86" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "100" ]; then
                    ch=$([ "${ch}" -lt "96" ] && echo "92" || echo "96")
                    bw_str=$([ "${ch}" -le "94" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "108" ]; then
                    ch=$([ "${ch}" -lt "104" ] && echo "100" || echo "104")
                    bw_str=$([ "${ch}" -le "102" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "116" ]; then
                    ch=$([ "${ch}" -lt "112" ] && echo "108" || echo "112")
                    bw_str=$([ "${ch}" -le "110" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "124" ]; then
                    ch=$([ "${ch}" -lt "120" ] && echo "116" || echo "120")
                    bw_str=$([ "${ch}" -le "118" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "132" ]; then
                    ch=$([ "${ch}" -lt "128" ] && echo "124" || echo "128")
                    bw_str=$([ "${ch}" -le "126" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "140" ]; then
                    ch=$([ "${ch}" -lt "136" ] && echo "132" || echo "136")
                    bw_str=$([ "${ch}" -le "134" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "149" ]; then
                    ch=$([ "${ch}" -lt "144" ] && echo "140" || echo "144")
                    bw_str=$([ "${ch}" -le "142" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "157" ]; then
                    ch=$([ "${ch}" -lt "153" ] && echo "149" || echo "153")
                    bw_str=$([ "${ch}" -le "151" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "165" ]; then
                    ch=$([ "${ch}" -lt "161" ] && echo "157" || echo "161")
                    bw_str=$([ "${ch}" -le "159" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "173" ]; then
                    ch=$([ "${ch}" -lt "169" ] && echo "165" || echo "169")
                    bw_str=$([ "${ch}" -le "167" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "181" ]; then
                    ch=$([ "${ch}" -lt "177" ] && echo "173" || echo "177")
                    bw_str=$([ "${ch}" -le "175" ] && echo "HT40+" || echo "HT40-")
                fi
                ;;
            "0")
                local bw_str="HT20"
                ;;
        esac
        local base_freq=5180
        local base_chan=36
    else
        case ${bw} in
            "5")
                bw_str="160MHz"
                if [ ${ch} -lt "33" ]; then
                    ch="1"
                elif [ ${ch} -lt "65" ]; then
                    ch="33"
                elif [ ${ch} -lt "97" ]; then
                    ch="65"
                elif [ ${ch} -lt "129" ]; then
                    ch="97"
                elif [ ${ch} -lt "161" ]; then
                    ch="129"
                elif [ ${ch} -lt "193" ]; then
                    ch="161"
                elif [ ${ch} -lt "225" ]; then
                    ch="193"
                fi
                ;;
            "2")
                bw_str="80MHz"
                if [ ${ch} -lt "17" ]; then
                    ch="1"
                elif [ ${ch} -lt "33" ]; then
                    ch="17"
                elif [ ${ch} -lt "49" ]; then
                    ch="33"
                elif [ ${ch} -lt "65" ]; then
                    ch="49"
                elif [ ${ch} -lt "81" ]; then
                    ch="65"
                elif [ ${ch} -lt "97" ]; then
                    ch="81"
                elif [ ${ch} -lt "113" ]; then
                    ch="97"
                elif [ ${ch} -lt "129" ]; then
                    ch="113"
                elif [ ${ch} -lt "145" ]; then
                    ch="129"
                elif [ ${ch} -lt "161" ]; then
                    ch="145"
                elif [ ${ch} -lt "177" ]; then
                    ch="161"
                elif [ ${ch} -lt "193" ]; then
                    ch="177"
                elif [ ${ch} -lt "209" ]; then
                    ch="193"
                elif [ ${ch} -lt "225" ]; then
                    ch="209"
                fi
                ;;
            "1")
                if [ ${ch} -lt "9" ]; then
                    ch=$([ "${ch}" -lt "5" ] && echo "1" || echo "5")
                    bw_str=$([ "${ch}" -le "3" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "17" ]; then
                    ch=$([ "${ch}" -lt "13" ] && echo "9" || echo "13")
                    bw_str=$([ "${ch}" -le "11" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "25" ]; then
                    ch=$([ "${ch}" -lt "21" ] && echo "17" || echo "21")
                    bw_str=$([ "${ch}" -le "19" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "33" ]; then
                    ch=$([ "${ch}" -lt "29" ] && echo "25" || echo "29")
                    bw_str=$([ "${ch}" -le "27" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "33" ]; then
                    ch=$([ "${ch}" -lt "29" ] && echo "25" || echo "29")
                    bw_str=$([ "${ch}" -le "27" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "41" ]; then
                    ch=$([ "${ch}" -lt "37" ] && echo "33" || echo "37")
                    bw_str=$([ "${ch}" -le "35" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "49" ]; then
                    ch=$([ "${ch}" -lt "45" ] && echo "41" || echo "45")
                    bw_str=$([ "${ch}" -le "43" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "57" ]; then
                    ch=$([ "${ch}" -lt "53" ] && echo "49" || echo "53")
                    bw_str=$([ "${ch}" -le "51" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "65" ]; then
                    ch=$([ "${ch}" -lt "61" ] && echo "57" || echo "61")
                    bw_str=$([ "${ch}" -le "59" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "73" ]; then
                    ch=$([ "${ch}" -lt "69" ] && echo "65" || echo "69")
                    bw_str=$([ "${ch}" -le "67" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "81" ]; then
                    ch=$([ "${ch}" -lt "77" ] && echo "73" || echo "77")
                    bw_str=$([ "${ch}" -le "75" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "89" ]; then
                    ch=$([ "${ch}" -lt "85" ] && echo "81" || echo "85")
                    bw_str=$([ "${ch}" -le "83" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "97" ]; then
                    ch=$([ "${ch}" -lt "93" ] && echo "89" || echo "93")
                    bw_str=$([ "${ch}" -le "91" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "105" ]; then
                    ch=$([ "${ch}" -lt "101" ] && echo "97" || echo "101")
                    bw_str=$([ "${ch}" -le "99" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "113" ]; then
                    ch=$([ "${ch}" -lt "109" ] && echo "105" || echo "109")
                    bw_str=$([ "${ch}" -le "107" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "121" ]; then
                    ch=$([ "${ch}" -lt "117" ] && echo "113" || echo "117")
                    bw_str=$([ "${ch}" -le "115" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "129" ]; then
                    ch=$([ "${ch}" -lt "125" ] && echo "121" || echo "125")
                    bw_str=$([ "${ch}" -le "123" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "137" ]; then
                    ch=$([ "${ch}" -lt "133" ] && echo "129" || echo "133")
                    bw_str=$([ "${ch}" -le "131" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "145" ]; then
                    ch=$([ "${ch}" -lt "141" ] && echo "137" || echo "141")
                    bw_str=$([ "${ch}" -le "139" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "153" ]; then
                    ch=$([ "${ch}" -lt "149" ] && echo "145" || echo "149")
                    bw_str=$([ "${ch}" -le "147" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "161" ]; then
                    ch=$([ "${ch}" -lt "157" ] && echo "153" || echo "157")
                    bw_str=$([ "${ch}" -le "155" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "169" ]; then
                    ch=$([ "${ch}" -lt "165" ] && echo "161" || echo "165")
                    bw_str=$([ "${ch}" -le "163" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "177" ]; then
                    ch=$([ "${ch}" -lt "173" ] && echo "169" || echo "173")
                    bw_str=$([ "${ch}" -le "171" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "185" ]; then
                    ch=$([ "${ch}" -lt "181" ] && echo "177" || echo "181")
                    bw_str=$([ "${ch}" -le "179" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "193" ]; then
                    ch=$([ "${ch}" -lt "189" ] && echo "185" || echo "189")
                    bw_str=$([ "${ch}" -le "187" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "201" ]; then
                    ch=$([ "${ch}" -lt "197" ] && echo "193" || echo "197")
                    bw_str=$([ "${ch}" -le "195" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "209" ]; then
                    ch=$([ "${ch}" -lt "205" ] && echo "201" || echo "205")
                    bw_str=$([ "${ch}" -le "203" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "217" ]; then
                    ch=$([ "${ch}" -lt "213" ] && echo "209" || echo "213")
                    bw_str=$([ "${ch}" -le "211" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "225" ]; then
                    ch=$([ "${ch}" -lt "221" ] && echo "217" || echo "221")
                    bw_str=$([ "${ch}" -le "219" ] && echo "HT40+" || echo "HT40-")
                elif [ ${ch} -lt "233" ]; then
                    ch=$([ "${ch}" -lt "229" ] && echo "225" || echo "229")
                    bw_str=$([ "${ch}" -le "227" ] && echo "HT40+" || echo "HT40-")
                fi
                ;;
            "0")
                local bw_str="HT20"
                ;;
        esac
        local base_freq=5955
    fi

    local control_freq=$(((ch - base_chan) * 5 + base_freq))
    do_cmd "iw dev mon${phy_idx} set freq ${control_freq} ${bw_str}"
}

function convert_rxstat {
    local res=$(do_cmd "mt76-test ${interface} dump stats")
    local mdrdy=$(echo "${res}" | grep "rx_packets" | cut -d "=" -f 2)
    local fcs_error=$(echo "${res}" | grep "rx_fcs_error" | cut -d "=" -f 2)
    local rcpi=$(echo "${res}" | grep "last_rcpi" | cut -d "=" -f 2 | sed 's/,/ /g')
    local ib_rssi=$(echo "${res}" | grep "last_ib_rssi" | cut -d "=" -f 2 | sed 's/,/ /g')
    local wb_rssi=$(echo "${res}" | grep "last_wb_rssi" | cut -d "=" -f 2 | sed 's/,/ /g')
    local rx_ok=$(expr ${mdrdy} - ${fcs_error})

    write_dmesg "rcpi: ${rcpi}"
    write_dmesg "fagc rssi ib: ${ib_rssi}"
    write_dmesg "fagc rssi wb: ${wb_rssi}"
    write_dmesg "all_mac_rx_mdrdy_cnt: ${mdrdy}"
    write_dmesg "all_mac_rx_fcs_err_cnt: ${fcs_error}"
    write_dmesg "all_mac_rx_ok_cnt : ${rx_ok}"
}

function set_mac_addr {
    record_config ${cmd} ${param} ${iwpriv_file}

    local addr1=$(get_config "ATEDA" ${iwpriv_file})
    local addr2=$(get_config "ATESA" ${iwpriv_file})
    local addr3=$(get_config "ATEBSSID" ${iwpriv_file})

    if [ -z "${addr1}" ]; then
        addr1="00:11:22:33:44:55"
    fi
    if [ -z "${addr2}" ]; then
        addr2="00:11:22:33:44:55"
    fi
    if [ -z "${addr3}" ]; then
        addr3="00:11:22:33:44:55"
    fi

    do_cmd "mt76-test phy${phy_idx} set mac_addrs=${addr1},${addr2},${addr3}"
}

function convert_ibf {
    local cmd=$1
    local param=$2
    local new_cmd=""
    local new_param=$(echo ${param} | sed s/":"/","/g)

    case ${cmd} in
        "ATETxBfInit")
            new_cmd="init"
            new_param=1
            do_cmd "mt76-test phy${phy_idx} set state=idle"
            ;;
        "ATEIBFPhaseComp")
            new_cmd="phase_comp"
            new_param="${new_param} aid=1"
            ;;
        "ATEEBfProfileConfig")
            new_cmd="ebf_prof_update"
            ;;
        "ATEIBfProfileConfig")
            new_cmd="ibf_prof_update"
            ;;
        "ATEIBfInstCal")
            new_cmd="phase_cal"
            ;;
        "ATEIBfGdCal")
            new_cmd="phase_cal"
            new_param="${new_param},00"
            ;;
        "TxBfTxApply")
            new_cmd="apply_tx"
            ;;
        "ATETxPacketWithBf")
            local bf_on=${new_param:0:2}
            local aid="01"
            local wlan_idx=${new_param:3:2}
            local update="00"
            local tx_len=${new_param:6}

            new_cmd="tx_prep"
            new_param="${bf_on},${aid},${wlan_idx},${update}"
            if [ "${tx_len}" = "00" ]; then
                new_param="${new_param} aid=1 tx_count=10000000 tx_length=1024"
            else
                new_param="${new_param} aid=1 tx_count=${tx_len} tx_length=1024"
            fi
            do_cmd "mt76-test phy${phy_idx} set state=idle"
            ;;
        "TxBfProfileData20MAllWrite")
            new_cmd="prof_update_all"
            ;;
        "ATEIBFPhaseE2pUpdate")
            new_cmd="e2p_update"
            ;;
        *)
    esac

    do_cmd "mt76-test phy${phy_idx} set txbf_act=${new_cmd} txbf_param=${new_param}"

    if [ "${cmd}" = "ATETxPacketWithBf" ]; then
        do_cmd "mt76-test phy${phy_idx} set state=tx_frames"
    fi
}

function convert_dfs {
    local cmd=$1
    local param=$2

    case ${cmd} in
        "DfsRxCtrl")
            local offchan_ch="$(echo $param | cut -d ':' -f1)"
            local offchan_bw="$(echo $param | cut -d ':' -f2)"

	    if [ "$offchan_bw" = "0" ]; then
            offchan_bw="20"
	    elif [ "$offchan_bw" = "1" ]; then
            offchan_bw="40"
	    elif [ "$offchan_bw" = "2" ]; then
            offchan_bw="80"
	    fi

	    do_cmd "mt76-test phy${phy_idx} set state=idle"
	    do_cmd "mt76-test phy${phy_idx} set offchan_ch=${offchan_ch} offchan_bw=${offchan_bw}"
            ;;
        "DfsRxHist")
            local ipi_th="$(echo $param | cut -d ':' -f 1)"
            local ipi_period="$(echo $param | cut -d ':' -f 2)"
	    local ipi_antenna="$(echo $param | cut -d ':' -f 3)"

	    if [ -z $ipi_antenna ]; then
	        do_cmd "mt76-test phy${phy_idx} set ipi_threshold=${ipi_th} ipi_period=${ipi_period}"
	    else
		do_cmd "mt76-test phy${phy_idx} set ipi_threshold=${ipi_th} ipi_period=${ipi_period} ipi_antenna_idx=${ipi_antenna}"
	    fi
            ;;
        *)
    esac
}

function do_ate_work() {
    local ate_cmd=$1

    case ${ate_cmd} in
        "ATESTART")
            local if_str=$(ifconfig | grep mon${phy_idx})

            if [ ! -z "${if_str}" -a "${if_str}" != " " ]; then
                echo "ATE already starts."
            else
                do_cmd "iw phy ${interface} interface add mon${phy_idx} type monitor"
                do_cmd "iw dev wlan${phy_idx} del"
                do_cmd "ifconfig mon${phy_idx} up"
                do_cmd "iw reg set VV"
            fi
            ;;
        "ATESTOP")
            local if_str=$(ifconfig | grep mon${phy_idx})

            if [ -z "${if_str}" -a "${if_str}" != " " ]; then
                echo "ATE does not start."
            else
                do_cmd "mt76-test ${interface} set state=off"
                do_cmd "iw dev mon${phy_idx} del"
                do_cmd "iw phy ${interface} interface add wlan${phy_idx} type managed"
                do_cmd "mt76-test ${interface} set aid=0"
            fi

            if [ ${phy_idx} -lt ${start_idx_7986} ]; then
                sed -i '/_PCIE=/d' ${iwpriv_file}
            elif [ ${phy_idx} -ge ${start_idx_7986} ]; then
                sed -i '/_7986=/d' ${iwpriv_file}
            fi
            ;;
        "TXCOMMIT")
            do_cmd "mt76-test ${interface} set aid=1"
            ;;
        "TXFRAME")
            do_cmd "mt76-test ${interface} set state=tx_frames"
            ;;
        "TXSTOP"|"RXSTOP")
            do_cmd "mt76-test ${interface} set state=idle"
            ;;
        "TXREVERT")
            do_cmd "mt76-test ${interface} set aid=0"
            ;;
        "RXFRAME")
            do_cmd "mt76-test ${interface} set state=rx_frames"
            ;;
        "TXCONT")
            do_cmd "mt76-test ${interface} set state=tx_cont"
            ;;
        "GROUPREK")
            do_cmd "mt76-test ${interface} set state=group_prek"
            do_cmd "atenl -i ${interface} -c \"eeprom precal sync group\""
            ;;
        "GROUPREKDump")
            do_cmd "mt76-test ${interface} set state=group_prek_dump"
            ;;
        "GROUPREKClean")
            do_cmd "mt76-test ${interface} set state=group_prek_clean"
            do_cmd "atenl -i ${interface} -c \"eeprom precal group clean\""
            ;;
        "DPD2G")
            do_cmd "mt76-test ${interface} set state=dpd_2g"
            do_cmd "atenl -i ${interface} -c \"eeprom precal sync dpd 2g\""
            ;;
        "DPD5G")
            do_cmd "mt76-test ${interface} set state=dpd_5g"
            do_cmd "atenl -i ${interface} -c \"eeprom precal sync dpd 5g\""
            ;;
        "DPD6G")
            do_cmd "mt76-test ${interface} set state=dpd_6g"
            do_cmd "atenl -i ${interface} -c \"eeprom precal sync dpd 6g\""
            ;;
        "DPDDump")
            do_cmd "mt76-test ${interface} set state=dpd_dump"
            ;;
        "DPDClean")
            do_cmd "mt76-test ${interface} set state=dpd_clean"
            do_cmd "atenl -i ${interface} -c \"eeprom precal dpd clean\""
            ;;
        *)
            print_debug "skip ${ate_cmd}"
            ;;
    esac
}

# main start here

if [[ ${interface} == "ra"* ]]; then
    convert_interface $interface
fi

tmp_work_mode=$(get_config "WORKMODE" ${iwpriv_file})

if [ ! -z ${tmp_work_mode} ]; then
    work_mode=${tmp_work_mode}
fi

cmd=$(echo ${full_cmd} | sed s/=/' '/g | cut -d " " -f 1)
param=$(echo ${full_cmd} | sed s/=/' '/g | cut -d " " -f 2)

if [ "${cmd_type}" = "set" ]; then
    skip=0
    case ${cmd} in
        "ATE")
            do_ate_work ${param}

            skip=1
            ;;
        "ATETXCNT"|"ATETXLEN"|"ATETXMCS"|"ATEVHTNSS"|"ATETXLDPC"|"ATETXSTBC"| \
        "ATEPKTTXTIME"|"ATEIPG"|"ATEDUTYCYCLE"|"ATETXFREQOFFSET")
            cmd_new=$(simple_convert ${cmd})
            if [ "${param_new}" = "undefined" ]; then
                echo "unknown cmd: ${cmd}"
                exit
            fi
            param_new=${param}
            ;;
        "ATETXANT"|"ATERXANT")
            cmd_new="tx_antenna"
            param_new=${param}
            ;;
        "ATETXGI")
            tx_mode=$(convert_tx_mode $(get_config "ATETXMODE" ${iwpriv_file}))
            convert_gi ${tx_mode} ${param}
            skip=1
            ;;
        "ATETXMODE")
            cmd_new="tx_rate_mode"
            param_new=$(convert_tx_mode ${param})
            if [ "${param_new}" = "undefined" ]; then
                echo "unknown tx mode"
                echo "0:cck, 1:ofdm, 2:ht, 4:vht, 8:he_su, 9:he_er, 10:he_tb, 11:he_mu"
                exit
            else
                record_config ${cmd} ${param} ${iwpriv_file}
            fi
            ;;
        "ATETXPOW0"|"ATETXPOW1"|"ATETXPOW2"|"ATETXPOW3")
            cmd_new="tx_power"
            param_new="${param},0,0,0"
            ;;
        "ATETXBW")
            record_config ${cmd} ${param} ${iwpriv_file}
            skip=1
            ;;
        "ATECHANNEL")
            convert_channel ${param}
            skip=1
            ;;
        "ATERXSTAT")
            convert_rxstat
            skip=1
            ;;
        "ATECTRLBANDIDX")
            change_band_idx ${param}
            skip=1
            ;;
        "ATEDA"|"ATESA"|"ATEBSSID")
            set_mac_addr ${cmd} ${param}
            skip=1
            ;;
        "DfsRxCtrl"|"DfsRxHist")
            convert_dfs ${cmd} ${param}
            skip=1
            ;;
        "ATETxBfInit"|"ATEIBFPhaseComp"|"ATEEBfProfileConfig"|"ATEIBfProfileConfig"| \
        "TxBfTxApply"|"ATETxPacketWithBf"|"TxBfProfileData20MAllWrite"|"ATEIBfInstCal"|\
        "ATEIBfGdCal"|"ATEIBFPhaseE2pUpdate")
            convert_ibf ${cmd} ${param}
            skip=1
            ;;
        "bufferMode")
            if [ "${param}" = "2" ]; then
                do_cmd "atenl -i ${interface} -c \"eeprom update buffermode\""
            fi
            skip=1
            ;;
        "ResetCounter"|"ATERXSTATRESET")
            skip=1
            ;;
        "WORKMODE")
            record_config "WORKMODE" ${param} ${iwpriv_file}
            echo "Entering ${param} mode in iwpriv"
            skip=1
            ;;
        *)
            print_debug "Unknown command to set: ${cmd}"
            skip=1
    esac

    if [ "${skip}" != "1" ]; then
        do_cmd "mt76-test ${interface} set ${cmd_new}=${param_new}"
    fi

elif [ "${cmd_type}" = "show" ]; then
    do_cmd "mt76-test ${interface} dump"
    do_cmd "mt76-test ${interface} dump stats"

elif [ "${cmd_type}" = "e2p" ]; then
    offset=$(printf "0x%s" ${cmd})
    val=$(printf "0x%s" ${param})

    # eeprom offset write
    if [[ ${full_cmd} == *"="* ]]; then
        tmp=$((${val} & 0xff))
        tmp=$(printf "0x%x" ${tmp})
        do_cmd "atenl -i ${interface} -c \"eeprom set ${offset}=${tmp}\""

        offset=$((${offset}))
        offset=$(expr ${offset} + "1")
        offset=$(printf "0x%x" ${offset})
        tmp=$(((${val} >> 8) & 0xff))
        tmp=$(printf "0x%x" ${tmp})
        do_cmd "atenl -i ${interface} -c \"eeprom set ${offset}=${tmp}\""
    else
        v1=$(do_cmd "atenl -i ${interface} -c \"eeprom read ${param}\"")
        v1=$(echo "${v1}" | grep "val =" | cut -d '(' -f 2 | grep -o -E '[0-9]+')

        tmp=$(printf "0x%s" ${param})
        tmp=$((${tmp}))
        param2=$(expr ${tmp} + "1")
        param2=$(printf "%x" ${param2})
        v2=$(do_cmd "atenl -i ${interface} -c \"eeprom read ${param2}\"")
        v2=$(echo "${v2}" | grep "val =" | cut -d '(' -f 2 | grep -o -E '[0-9]+')

        param=$(printf "0x%s" ${param})
        param=$(printf "%04x" ${param})
        param=$(echo $param | tr 'a-z' 'A-Z')
        printf "%s       e2p:\n" ${interface_ori}
        printf "[0x%s]:0x%02x%02x\n" ${param} ${v2} ${v1}
    fi

elif [ "${cmd_type}" = "mac" ]; then
    regidx=/sys/kernel/debug/ieee80211/phy${phy_idx}/mt76/regidx
    regval=/sys/kernel/debug/ieee80211/phy${phy_idx}/mt76/regval
    offset=$(printf "0x%s" ${cmd})
    val=$(printf "0x%s" ${param})

    echo ${offset} > ${regidx}
    # reg write
    if [[ ${full_cmd} == *"="* ]]; then
        echo ${val} > ${regval}
    fi

    res=$(cat ${regval} | cut -d 'x' -f 2)
    printf "%s       mac:[%s]:%s\n" ${interface_ori} ${offset} ${res}

else
    echo "Unknown command"
fi
