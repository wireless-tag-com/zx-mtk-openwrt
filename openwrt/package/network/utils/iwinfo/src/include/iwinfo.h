#ifndef __IWINFO_H_
#define __IWINFO_H_

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <glob.h>
#include <ctype.h>
#include <dirent.h>
#include <stdint.h>

#include <sys/ioctl.h>
#include <sys/mman.h>
#include <net/if.h>
#include <errno.h>


#define IWINFO_BUFSIZE	24 * 1024
#define IWINFO_ESSID_MAX_SIZE	32

#define IWINFO_80211_A       (1 << 0)
#define IWINFO_80211_B       (1 << 1)
#define IWINFO_80211_G       (1 << 2)
#define IWINFO_80211_N       (1 << 3)
#define IWINFO_80211_AC      (1 << 4)
#define IWINFO_80211_AD      (1 << 5)
#define IWINFO_80211_AX      (1 << 6)

#define IWINFO_BAND_24       (1 << 0)
#define IWINFO_BAND_5        (1 << 1)
#define IWINFO_BAND_6        (1 << 2)
#define IWINFO_BAND_60       (1 << 3)

#define IWINFO_CIPHER_NONE    (1 << 0)
#define IWINFO_CIPHER_WEP40   (1 << 1)
#define IWINFO_CIPHER_TKIP    (1 << 2)
#define IWINFO_CIPHER_WRAP    (1 << 3)
#define IWINFO_CIPHER_CCMP    (1 << 4)
#define IWINFO_CIPHER_WEP104  (1 << 5)
#define IWINFO_CIPHER_AESOCB  (1 << 6)
#define IWINFO_CIPHER_CKIP    (1 << 7)
#define IWINFO_CIPHER_GCMP    (1 << 8)
#define IWINFO_CIPHER_CCMP256 (1 << 9)
#define IWINFO_CIPHER_GCMP256 (1 << 10)
#define IWINFO_CIPHER_COUNT  11

#define IWINFO_KMGMT_NONE    (1 << 0)
#define IWINFO_KMGMT_8021x   (1 << 1)
#define IWINFO_KMGMT_PSK     (1 << 2)
#define IWINFO_KMGMT_SAE     (1 << 3)
#define IWINFO_KMGMT_OWE     (1 << 4)
#define IWINFO_KMGMT_COUNT   5

#define IWINFO_AUTH_OPEN     (1 << 0)
#define IWINFO_AUTH_SHARED   (1 << 1)
#define IWINFO_AUTH_COUNT    2

#define IWINFO_FREQ_NO_10MHZ		(1 << 0)
#define IWINFO_FREQ_NO_20MHZ		(1 << 1)
#define IWINFO_FREQ_NO_HT40PLUS		(1 << 2)
#define IWINFO_FREQ_NO_HT40MINUS	(1 << 3)
#define IWINFO_FREQ_NO_80MHZ		(1 << 4)
#define IWINFO_FREQ_NO_160MHZ		(1 << 5)
#define IWINFO_FREQ_NO_2160MHZ		(1 << 6)

extern const char *IWINFO_CIPHER_NAMES[IWINFO_CIPHER_COUNT];
extern const char *IWINFO_KMGMT_NAMES[IWINFO_KMGMT_COUNT];
extern const char *IWINFO_AUTH_NAMES[IWINFO_AUTH_COUNT];


enum iwinfo_opmode {
	IWINFO_OPMODE_UNKNOWN    = 0,
	IWINFO_OPMODE_MASTER     = 1,
	IWINFO_OPMODE_ADHOC      = 2,
	IWINFO_OPMODE_CLIENT     = 3,
	IWINFO_OPMODE_MONITOR    = 4,
	IWINFO_OPMODE_AP_VLAN    = 5,
	IWINFO_OPMODE_WDS        = 6,
	IWINFO_OPMODE_MESHPOINT  = 7,
	IWINFO_OPMODE_P2P_CLIENT = 8,
	IWINFO_OPMODE_P2P_GO     = 9,
};

extern const char *IWINFO_OPMODE_NAMES[];


enum iwinfo_htmode {
	IWINFO_HTMODE_HT20       = (1 << 0),
	IWINFO_HTMODE_HT40       = (1 << 1),
	IWINFO_HTMODE_VHT20      = (1 << 2),
	IWINFO_HTMODE_VHT40      = (1 << 3),
	IWINFO_HTMODE_VHT80      = (1 << 4),
	IWINFO_HTMODE_VHT80_80   = (1 << 5),
	IWINFO_HTMODE_VHT160     = (1 << 6),
	IWINFO_HTMODE_NOHT       = (1 << 7),
	IWINFO_HTMODE_HE20       = (1 << 8),
	IWINFO_HTMODE_HE40       = (1 << 9),
	IWINFO_HTMODE_HE80       = (1 << 10),
	IWINFO_HTMODE_HE80_80    = (1 << 11),
	IWINFO_HTMODE_HE160      = (1 << 12),

	IWINFO_HTMODE_COUNT      = 13
};

extern const char *IWINFO_HTMODE_NAMES[IWINFO_HTMODE_COUNT];


struct iwinfo_rate_entry {
	uint32_t rate;
	int8_t mcs;
	uint8_t is_40mhz:1;
	uint8_t is_short_gi:1;
	uint8_t is_ht:1;
	uint8_t is_vht:1;
	uint8_t is_he:1;
	uint8_t he_gi;
	uint8_t he_dcm;
	uint8_t mhz;
	uint8_t nss;
};

struct iwinfo_assoclist_entry {
	uint8_t	mac[6];
	int8_t signal;
	int8_t signal_avg;
	int8_t noise;
	uint32_t inactive;
	uint32_t connected_time;
	uint32_t rx_packets;
	uint32_t tx_packets;
	uint64_t rx_drop_misc;
	struct iwinfo_rate_entry rx_rate;
	struct iwinfo_rate_entry tx_rate;
	uint32_t rx_bytes;
	uint32_t tx_bytes;
	uint32_t tx_retries;
	uint32_t tx_failed;
	uint64_t t_offset;
	uint8_t is_authorized:1;
	uint8_t is_authenticated:1;
	uint8_t is_preamble_short:1;
	uint8_t is_wme:1;
	uint8_t is_mfp:1;
	uint8_t is_tdls:1;
	uint32_t thr;
	uint16_t llid;
	uint16_t plid;
	char plink_state[16];
	char local_ps[16];
	char peer_ps[16];
	char nonpeer_ps[16];
};

struct iwinfo_survey_entry {
	uint64_t active_time;
	uint64_t busy_time;
	uint64_t busy_time_ext;
	uint64_t rxtime;
	uint64_t txtime;
	uint32_t mhz;
	uint8_t noise;
};

struct iwinfo_txpwrlist_entry {
	uint8_t  dbm;
	uint16_t mw;
};

struct iwinfo_freqlist_entry {
	uint8_t channel;
	uint32_t mhz;
	uint8_t restricted;
	uint32_t flags;
};

struct iwinfo_crypto_entry {
	uint8_t	enabled;
	uint8_t wpa_version;
	uint16_t group_ciphers;
	uint16_t pair_ciphers;
	uint8_t auth_suites;
	uint8_t auth_algs;
};

struct iwinfo_scanlist_ht_chan_entry {
	uint8_t primary_chan;
	uint8_t secondary_chan_off;
	uint8_t chan_width;
};

struct iwinfo_scanlist_vht_chan_entry {
	uint8_t chan_width;
	uint8_t center_chan_1;
	uint8_t center_chan_2;
};

static const char *ht_secondary_offset[4] = {
	"no secondary",
	"above",
	"[reserved!]",
	"below",
};


static uint16_t ht_chan_width[2] = {
	20, /* 20 MHz */
	2040, /* 40 MHz or higher (refer to vht if supported) */
};

static uint16_t vht_chan_width[] = {
	[0] = 40, /* 40 MHz or lower (refer to ht to a more precise width) */
	[1] = 80, /* 80 MHz */
	[3] = 8080, /* 80+80 MHz */
	[2] = 160, /* 160 MHz */
};

struct iwinfo_scanlist_entry {
	uint8_t mac[6];
	char ssid[IWINFO_ESSID_MAX_SIZE+1];
	enum iwinfo_opmode mode;
	uint8_t channel;
	uint8_t signal;
	uint8_t quality;
	uint8_t quality_max;
	struct iwinfo_crypto_entry crypto;
	struct iwinfo_scanlist_ht_chan_entry ht_chan_info;
	struct iwinfo_scanlist_vht_chan_entry vht_chan_info;
};

struct iwinfo_country_entry {
	uint16_t iso3166;
	char ccode[4];
};

struct iwinfo_iso3166_label {
	uint16_t iso3166;
	char name[28];
};

struct iwinfo_hardware_id {
	uint16_t vendor_id;
	uint16_t device_id;
	uint16_t subsystem_vendor_id;
	uint16_t subsystem_device_id;
};

struct iwinfo_hardware_entry {
	char vendor_name[64];
	char device_name[64];
	uint16_t vendor_id;
	uint16_t device_id;
	uint16_t subsystem_vendor_id;
	uint16_t subsystem_device_id;
	int16_t txpower_offset;
	int16_t frequency_offset;
};

extern const struct iwinfo_iso3166_label IWINFO_ISO3166_NAMES[];

#define IWINFO_HARDWARE_FILE	"/usr/share/libiwinfo/devices.txt"


struct iwinfo_ops {
	const char *name;

	int (*probe)(const char *ifname);
	int (*mode)(const char *, int *);
	int (*channel)(const char *, int *);
	int (*center_chan1)(const char *, int *);
	int (*center_chan2)(const char *, int *);
	int (*frequency)(const char *, int *);
	int (*frequency_offset)(const char *, int *);
	int (*txpower)(const char *, int *);
	int (*txpower_offset)(const char *, int *);
	int (*bitrate)(const char *, int *);
	int (*signal)(const char *, int *);
	int (*noise)(const char *, int *);
	int (*quality)(const char *, int *);
	int (*quality_max)(const char *, int *);
	int (*mbssid_support)(const char *, int *);
	int (*hwmodelist)(const char *, int *);
	int (*htmodelist)(const char *, int *);
	int (*htmode)(const char *, int *);
	int (*ssid)(const char *, char *);
	int (*bssid)(const char *, char *);
	int (*country)(const char *, char *);
	int (*hardware_id)(const char *, char *);
	int (*hardware_name)(const char *, char *);
	int (*encryption)(const char *, char *);
	int (*phyname)(const char *, char *);
	int (*assoclist)(const char *, char *, int *);
	int (*txpwrlist)(const char *, char *, int *);
	int (*scanlist)(const char *, char *, int *);
	int (*freqlist)(const char *, char *, int *);
	int (*countrylist)(const char *, char *, int *);
	int (*survey)(const char *, char *, int *);
	int (*lookup_phy)(const char *, char *);
	int (*phy_path)(const char *phyname, const char **path);
	void (*close)(void);
};

const char * iwinfo_type(const char *ifname);
const struct iwinfo_ops * iwinfo_backend(const char *ifname);
const struct iwinfo_ops * iwinfo_backend_by_name(const char *name);
void iwinfo_finish(void);

extern const struct iwinfo_ops wext_ops;
extern const struct iwinfo_ops madwifi_ops;
extern const struct iwinfo_ops nl80211_ops;
extern const struct iwinfo_ops nlwifi_ops;
extern const struct iwinfo_ops wl_ops;

int nlwifi_set_channel(const char *device, u_int32_t channel);
int nlwifi_set_txpwr(const char *device, u_int32_t txpwr);
int nlwifi_set_htbw(const char *device, const char *htbw);
int nlwifi_set_hidden(const char *ifname, u_int32_t hidden);
int nlwifi_set_isolate(const char *ifname, u_int32_t isolate);
int nlwifi_set_maxstanum(const char *ifname, u_int32_t maxstanum);
int nlwifi_set_lowrssi(const char *ifname, u_int32_t lowrssi);
int nlwifi_set_macfilter(const char *ifname, const char *macfilter);
int nlwifi_add_aclmac(const char *ifname, const char *strmac);
int nlwifi_del_aclmac(const char *ifname, const char *strmac);
int nlwifi_deauth_mac(const char *ifname, const char *strmac);
int nlwifi_set_wsc(const char *ifname, const char *key);
int nlwifi_trigger_scan(const char *ifname);

int nlwifi_wifi_up(const char *device);
int nlwifi_wifi_down(const char *device);
int nlwifi_wifi_sync(const char *device);
int nlwifi_wifi_up_iface(const char *iface);
int nlwifi_wifi_down_iface(const char *iface);

const struct iwinfo_ops *mtk_nlwifi_ops();

int nlwifi_set_meshEnable(const char *ifname, int enable);
int nlwifi_set_meshEvent_Enable(const char *ifname, int enable);

const char *nlwifi_ifname2phyname(const char *ifname);

#include "iwinfo/utils.h"

#endif
