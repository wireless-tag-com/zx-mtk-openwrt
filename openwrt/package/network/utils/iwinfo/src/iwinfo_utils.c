/*
 * iwinfo - Wireless Information Library - Shared utility routines
 *
 *   Copyright (C) 2010 Jo-Philipp Wich <xm@subsignal.org>
 *
 * The iwinfo library is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 *
 * The iwinfo library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with the iwinfo library. If not, see http://www.gnu.org/licenses/.
 *
 * The signal handling code is derived from the official madwifi tools,
 * wlanconfig.c in particular. The encryption property handling was
 * inspired by the hostapd madwifi driver.
 */

#include "iwinfo/utils.h"


static int ioctl_socket = -1;
struct uci_context *uci_ctx = NULL;
struct uci_package *uci_pkg = NULL;

static int iwinfo_ioctl_socket(void)
{
	/* Prepare socket */
	if (ioctl_socket == -1)
	{
		ioctl_socket = socket(AF_INET, SOCK_DGRAM, 0);
		fcntl(ioctl_socket, F_SETFD, fcntl(ioctl_socket, F_GETFD) | FD_CLOEXEC);
	}

	return ioctl_socket;
}

int iwinfo_ioctl(int cmd, void *ifr)
{
	int s = iwinfo_ioctl_socket();
	return ioctl(s, cmd, ifr);
}

int iwinfo_dbm2mw(int in)
{
	double res = 1.0;
	int ip = in / 10;
	int fp = in % 10;
	int k;

	for(k = 0; k < ip; k++) res *= 10;
	for(k = 0; k < fp; k++) res *= LOG10_MAGIC;

	return (int)res;
}

int iwinfo_mw2dbm(int in)
{
	double fin = (double) in;
	int res = 0;

	while(fin > 10.0)
	{
		res += 10;
		fin /= 10.0;
	}

	while(fin > 1.000001)
	{
		res += 1;
		fin /= LOG10_MAGIC;
	}

	return (int)res;
}

int iwinfo_ifup(const char *ifname)
{
	struct ifreq ifr;

	strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);

	if (iwinfo_ioctl(SIOCGIFFLAGS, &ifr))
		return 0;

	ifr.ifr_flags |= (IFF_UP | IFF_RUNNING);

	return !iwinfo_ioctl(SIOCSIFFLAGS, &ifr);
}

int iwinfo_ifdown(const char *ifname)
{
	struct ifreq ifr;

	strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);

	if (iwinfo_ioctl(SIOCGIFFLAGS, &ifr))
		return 0;

	ifr.ifr_flags &= ~(IFF_UP | IFF_RUNNING);

	return !iwinfo_ioctl(SIOCSIFFLAGS, &ifr);
}

int iwinfo_ifmac(const char *ifname)
{
	struct ifreq ifr;

	strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);

	if (iwinfo_ioctl(SIOCGIFHWADDR, &ifr))
		return 0;

	ifr.ifr_hwaddr.sa_data[0] |= 0x02;
	ifr.ifr_hwaddr.sa_data[1]++;
	ifr.ifr_hwaddr.sa_data[2]++;

	return !iwinfo_ioctl(SIOCSIFHWADDR, &ifr);
}

void iwinfo_close(void)
{
	if (ioctl_socket > -1)
		close(ioctl_socket);

	ioctl_socket = -1;
}

struct iwinfo_hardware_entry * iwinfo_hardware(struct iwinfo_hardware_id *id)
{
	FILE *db;
	char buf[256] = { 0 };
	static struct iwinfo_hardware_entry e;
	struct iwinfo_hardware_entry *rv = NULL;

	if (!(db = fopen(IWINFO_HARDWARE_FILE, "r")))
		return NULL;

	while (fgets(buf, sizeof(buf) - 1, db) != NULL)
	{
		memset(&e, 0, sizeof(e));

		if (sscanf(buf, "%hx %hx %hx %hx %hd %hd \"%63[^\"]\" \"%63[^\"]\"",
			       &e.vendor_id, &e.device_id,
			       &e.subsystem_vendor_id, &e.subsystem_device_id,
			       &e.txpower_offset, &e.frequency_offset,
			       e.vendor_name, e.device_name) < 8)
			continue;

		if ((e.vendor_id != 0xffff) && (e.vendor_id != id->vendor_id))
			continue;

		if ((e.device_id != 0xffff) && (e.device_id != id->device_id))
			continue;

		if ((e.subsystem_vendor_id != 0xffff) &&
			(e.subsystem_vendor_id != id->subsystem_vendor_id))
			continue;

		if ((e.subsystem_device_id != 0xffff) &&
			(e.subsystem_device_id != id->subsystem_device_id))
			continue;

		rv = &e;
		break;
	}

	fclose(db);
	return rv;
}

int iwinfo_hardware_id_from_mtd(struct iwinfo_hardware_id *id)
{
	FILE *mtd;
	uint16_t *bc;

	int fd, off;
	unsigned int len;
	char buf[128];

	if (!(mtd = fopen("/proc/mtd", "r")))
		return -1;

	while (fgets(buf, sizeof(buf), mtd) != NULL)
	{
		if (fscanf(mtd, "mtd%d: %x %*x %127s", &off, &len, buf) < 3 ||
		    (strcmp(buf, "\"boardconfig\"") && strcmp(buf, "\"EEPROM\"") &&
		     strcmp(buf, "\"factory\"")))
		{
			off = -1;
			continue;
		}

		break;
	}

	fclose(mtd);

	if (off < 0)
		return -1;

	snprintf(buf, sizeof(buf), "/dev/mtdblock%d", off);

	if ((fd = open(buf, O_RDONLY)) < 0)
		return -1;

	bc = mmap(NULL, len, PROT_READ, MAP_PRIVATE|MAP_LOCKED, fd, 0);

	if ((void *)bc != MAP_FAILED)
	{
		id->vendor_id = 0;
		id->device_id = 0;

		for (off = len / 2 - 0x800; off >= 0; off -= 0x800)
		{
			/* AR531X board data magic */
			if ((bc[off] == 0x3533) && (bc[off + 1] == 0x3131))
			{
				id->vendor_id = bc[off + 0x7d];
				id->device_id = bc[off + 0x7c];
				id->subsystem_vendor_id = bc[off + 0x84];
				id->subsystem_device_id = bc[off + 0x83];
				break;
			}

			/* AR5416 EEPROM magic */
			else if ((bc[off] == 0xA55A) || (bc[off] == 0x5AA5))
			{
				id->vendor_id = bc[off + 0x0D];
				id->device_id = bc[off + 0x0E];
				id->subsystem_vendor_id = bc[off + 0x13];
				id->subsystem_device_id = bc[off + 0x14];
				break;
			}

			/* Rt3xxx SoC */
			else if ((bc[off] == 0x3050) || (bc[off] == 0x5030) ||
			         (bc[off] == 0x3051) || (bc[off] == 0x5130) ||
			         (bc[off] == 0x3052) || (bc[off] == 0x5230) ||
			         (bc[off] == 0x3350) || (bc[off] == 0x5033) ||
			         (bc[off] == 0x3352) || (bc[off] == 0x5233) ||
			         (bc[off] == 0x3662) || (bc[off] == 0x6236) ||
			         (bc[off] == 0x3883) || (bc[off] == 0x8338) ||
			         (bc[off] == 0x5350) || (bc[off] == 0x5053))
			{
				/* vendor: RaLink */
				id->vendor_id = 0x1814;
				id->subsystem_vendor_id = 0x1814;

				/* device */
				if (((bc[off] & 0xf0) == 0x30) ||
				    ((bc[off] & 0xff) == 0x53))
					id->device_id = (bc[off] >> 8) | (bc[off] & 0x00ff) << 8;
				else
					id->device_id = bc[off];

				/* subsystem from EEPROM_NIC_CONF0_RF_TYPE */
				id->subsystem_device_id = (bc[off + 0x1a] & 0x0f00) >> 8;
			} else if ((bc[off] == 0x7620) || (bc[off] == 0x2076) ||
			           (bc[off] == 0x7628) || (bc[off] == 0x2876) ||
			           (bc[off] == 0x7688) || (bc[off] == 0x8876)) {
				/* vendor: MediaTek */
				id->vendor_id = 0x14c3;
				id->subsystem_vendor_id = 0x14c3;

				/* device */
				if ((bc[off] & 0xff) == 0x76)
					id->device_id = (bc[off] >> 8) | (bc[off] & 0x00ff) << 8;
				else
					id->device_id = bc[off];

				/* subsystem from EEPROM_NIC_CONF0_RF_TYPE */
				id->subsystem_device_id = (bc[off + 0x1a] & 0x0f00) >> 8;
			}
		}

		munmap(bc, len);
	}

	close(fd);

	return (id->vendor_id && id->device_id) ? 0 : -1;
}

static void iwinfo_parse_rsn_cipher(uint8_t idx, uint16_t *ciphers)
{
	switch (idx)
	{
		case 0:
			*ciphers |= IWINFO_CIPHER_NONE;
			break;

		case 1:
			*ciphers |= IWINFO_CIPHER_WEP40;
			break;

		case 2:
			*ciphers |= IWINFO_CIPHER_TKIP;
			break;

		case 3:  /* WRAP */
			break;

		case 4:
			*ciphers |= IWINFO_CIPHER_CCMP;
			break;

		case 5:
			*ciphers |= IWINFO_CIPHER_WEP104;
			break;

		case 8:
			*ciphers |= IWINFO_CIPHER_GCMP;
			break;

		case 9:
			*ciphers |= IWINFO_CIPHER_GCMP256;
			break;

		case 10:
			*ciphers |= IWINFO_CIPHER_CCMP256;
			break;

		case 6:  /* AES-128-CMAC */
		case 7:  /* No group addressed */
		case 11: /* BIP-GMAC-128 */
		case 12: /* BIP-GMAC-256 */
		case 13: /* BIP-CMAC-256 */
			break;
	}
}

void iwinfo_parse_rsn(struct iwinfo_crypto_entry *c, uint8_t *data, uint8_t len,
					  uint16_t defcipher, uint8_t defauth)
{
	uint16_t i, count;
	uint8_t wpa_version = 0;

	static unsigned char ms_oui[3]        = { 0x00, 0x50, 0xf2 };
	static unsigned char ieee80211_oui[3] = { 0x00, 0x0f, 0xac };

	data += 2;
	len -= 2;

	if (!memcmp(data, ms_oui, 3))
		wpa_version |= 1;
	else if (!memcmp(data, ieee80211_oui, 3))
		wpa_version |= 2;

	if (len < 4)
	{
		c->group_ciphers |= defcipher;
		c->pair_ciphers  |= defcipher;
		c->auth_suites   |= defauth;
		return;
	}

	if (!memcmp(data, ms_oui, 3) || !memcmp(data, ieee80211_oui, 3))
		iwinfo_parse_rsn_cipher(data[3], &c->group_ciphers);

	data += 4;
	len -= 4;

	if (len < 2)
	{
		c->pair_ciphers |= defcipher;
		c->auth_suites  |= defauth;
		return;
	}

	count = data[0] | (data[1] << 8);
	if (2 + (count * 4) > len)
		return;

	for (i = 0; i < count; i++)
		if (!memcmp(data + 2 + (i * 4), ms_oui, 3) ||
		    !memcmp(data + 2 + (i * 4), ieee80211_oui, 3))
			iwinfo_parse_rsn_cipher(data[2 + (i * 4) + 3], &c->pair_ciphers);

	data += 2 + (count * 4);
	len -= 2 + (count * 4);

	if (len < 2)
	{
		c->auth_suites |= defauth;
		return;
	}

	count = data[0] | (data[1] << 8);
	if (2 + (count * 4) > len)
		return;

	for (i = 0; i < count; i++)
	{
		if (!memcmp(data + 2 + (i * 4), ms_oui, 3) ||
			!memcmp(data + 2 + (i * 4), ieee80211_oui, 3))
		{
			switch (data[2 + (i * 4) + 3])
			{
				case 1:  /* IEEE 802.1x */
					c->wpa_version |= wpa_version;
					c->auth_suites |= IWINFO_KMGMT_8021x;
					break;

				case 2:  /* PSK */
					c->wpa_version |= wpa_version;
					c->auth_suites |= IWINFO_KMGMT_PSK;
					break;

				case 3:  /* FT/IEEE 802.1X */
				case 4:  /* FT/PSK */
				case 5:  /* IEEE 802.1X/SHA-256 */
				case 6:  /* PSK/SHA-256 */
				case 7:  /* TPK Handshake */
					break;

				case 8:  /* SAE */
					c->wpa_version |= 4;
					c->auth_suites |= IWINFO_KMGMT_SAE;
					break;

				case 9:  /* FT/SAE */
				case 10: /* undefined */
					break;

				case 11: /* 802.1x Suite-B */
				case 12: /* 802.1x Suite-B-192 */
					c->wpa_version |= 4;
					c->auth_suites |= IWINFO_KMGMT_8021x;
					break;

				case 13: /* FT/802.1x SHA-384 */
				case 14: /* FILS SHA-256 */
				case 15: /* FILS SHA-384 */
				case 16: /* FT/FILS SHA-256 */
				case 17: /* FT/FILS SHA-384 */
					break;

				case 18: /* OWE */
					c->wpa_version |= 4;
					c->auth_suites |= IWINFO_KMGMT_OWE;
					break;
			}
		}
	}

	data += 2 + (count * 4);
	len -= 2 + (count * 4);
}

struct uci_section *iwinfo_uci_get_radio(const char *name, const char *type)
{
	struct uci_ptr ptr = {
		.package = "wireless",
		.section = name,
		.flags = (name && *name == '@') ? UCI_LOOKUP_EXTENDED : 0,
	};
	const char *opt;

	if (!uci_ctx) {
		uci_ctx = uci_alloc_context();
		if (!uci_ctx)
			return NULL;
	}

	if (uci_lookup_ptr(uci_ctx, &ptr, NULL, true))
		return NULL;

	if (!ptr.s || strcmp(ptr.s->type, "wifi-device") != 0)
		return NULL;

	opt = uci_lookup_option_string(uci_ctx, ptr.s, "type");
	if (!opt || strcmp(opt, type) != 0)
		return NULL;

	return ptr.s;
}

int iwinfo_uci_init(void)
{
	if (!uci_ctx) {
		uci_ctx = uci_alloc_context();
		if (!uci_ctx) {
			fprintf(stderr, "uci_alloc_context failed\n");
			return -1;
		}
	}
	if (!uci_pkg) {
		uci_load(uci_ctx, "wireless", &uci_pkg);
		if (!uci_pkg) {
			fprintf(stderr, "uci_load package failed\n");
			return -1;
		}
	}
	return 0;
}

#ifdef USE_NLWIFI
struct uci_section *iwinfo_uci_get_section(const char *name)
{
	struct uci_element *e;
	struct uci_section *s = NULL;
	const char *ifname;

	if (iwinfo_uci_init() < 0)
		return NULL;

	if (!name)
		return NULL;

	uci_foreach_element(&uci_pkg->sections, e) {
		s = uci_to_section(e);
		if ((strcmp(s->type, "wifi-device") != 0) && (strcmp(s->type, "wifi-iface") != 0))
			continue;

		ifname = uci_lookup_option_string(uci_ctx, s, "ifname");

		if ((s->e.name && (strcmp(s->e.name, name) == 0)) ||
			(ifname && (strcmp(ifname, name) == 0)))
			break;
	}

	return s;
}

const char *iwinfo_uci_get_device_config(const char *device, const char *option)
{
	struct uci_section *s;
	const char *val;

	s = iwinfo_uci_get_section(device);
	if (!s)
		return NULL;

	val = uci_lookup_option_string(uci_ctx, s, option);
	return val;
}

const char *iwinfo_uci_get_iface_config(const char *ifname, const char *option)
{
	struct uci_section *s;
	const char *val;

	s = iwinfo_uci_get_section(ifname);
	if (!s)
		return NULL;

	val = uci_lookup_option_string(uci_ctx, s, option);
	return val;
}

const char *iwinfo_uci_get_phy_config(const char *phyname, const char *option)
{
	struct uci_section *s;
	struct uci_element *e;
	const char *val;

	if (iwinfo_uci_init() < 0)
		return NULL;

	uci_foreach_element(&uci_pkg->sections, e) {
		s = uci_to_section(e);
		if (strcmp(s->type, "wifi-iface") != 0)
			continue;

		val = uci_lookup_option_string(uci_ctx, s, "ifname");
		if (!val)
			continue;

		val = nlwifi_ifname2phyname(val);
		if (!val || (strcmp(val, phyname) != 0))
			continue;

		val = uci_lookup_option_string(uci_ctx, s, "device");
		if (!val)
			continue;

		s = iwinfo_uci_get_section(val);
		if (!s)
			continue;

		val = uci_lookup_option_string(uci_ctx, s, option);
		return val;
	}

	return NULL;	
}

int iwinfo_mac_str2eth(const char *buffer, u_int8_t *ether)
{
	int i, c;

	if ((NULL == buffer) || (NULL == ether)) {
		return -1;
	}

	for (i = 0; i < 6; i++) {	
		if ((*buffer =='-') || (*buffer ==':')) {
			buffer++;
		}

		if (*buffer >= '0' && *buffer <= '9') {
			c  = (unsigned char) (*buffer++ - '0'); 
		} else if (*buffer >= 'a' && *buffer <= 'f') {
			c  = (unsigned char) (*buffer++ - 'a') + 10;
		} else if (*buffer >= 'A' && *buffer <= 'F') {
			c  = (unsigned char) (*buffer++ - 'A') + 10; 
		} else {
			return -1;
		}

		c <<= 4;

		if (*buffer >= '0' && *buffer <= '9') {
			c |= (unsigned char) (*buffer++ - '0');
		} else if (*buffer >= 'a' && *buffer <= 'f') {
			c |= (unsigned char) (*buffer++ - 'a') + 10;
		} else {
			c |= (unsigned char) (*buffer++ - 'A') + 10;
		}

		ether[i] = (unsigned char) c;

	}

	return 0;
}
#endif

void iwinfo_uci_free(void)
{
	if (!uci_ctx)
		return;

	if (uci_pkg) {
		uci_unload(uci_ctx, uci_pkg);
		uci_pkg = NULL;
	}

	uci_free_context(uci_ctx);
	uci_ctx = NULL;
}


struct iwinfo_ubus_query_state {
	const char *ifname;
	const char *field;
	size_t len;
	char *buf;
};

static void iwinfo_ubus_query_cb(struct ubus_request *req, int type,
                                 struct blob_attr *msg)
{
	struct iwinfo_ubus_query_state *st = req->priv;

	struct blobmsg_policy pol1[2] = {
		{ "ifname",  BLOBMSG_TYPE_STRING },
		{ "config",  BLOBMSG_TYPE_TABLE }
	};

	struct blobmsg_policy pol2 = { st->field, BLOBMSG_TYPE_STRING };
	struct blob_attr *cur, *cur2, *cur3, *cfg[2], *res;
	int rem, rem2, rem3;

	blobmsg_for_each_attr(cur, msg, rem) {
		if (blobmsg_type(cur) != BLOBMSG_TYPE_TABLE)
			continue;

		blobmsg_for_each_attr(cur2, cur, rem2) {
			if (blobmsg_type(cur2) != BLOBMSG_TYPE_ARRAY)
				continue;

			if (strcmp(blobmsg_name(cur2), "interfaces"))
				continue;

			blobmsg_for_each_attr(cur3, cur2, rem3) {
				blobmsg_parse(pol1, sizeof(pol1) / sizeof(pol1[0]), cfg,
				              blobmsg_data(cur3), blobmsg_len(cur3));

				if (!cfg[0] || !cfg[1] ||
				    strcmp(blobmsg_get_string(cfg[0]), st->ifname))
					continue;

				blobmsg_parse(&pol2, 1, &res,
				              blobmsg_data(cfg[1]), blobmsg_len(cfg[1]));

				if (!res)
					continue;

				strncpy(st->buf, blobmsg_get_string(res), st->len);
				return;
			}
		}
	}
}

int iwinfo_ubus_query(const char *ifname, const char *field,
                      char *buf, size_t len)
{
	struct iwinfo_ubus_query_state st = {
		.ifname = ifname,
		.field = field,
		.buf = buf,
		.len = len
	};

	struct ubus_context *ctx = NULL;
	struct blob_buf b = { };
	int rv = -1;
	uint32_t id;

	blob_buf_init(&b, 0);

	ctx = ubus_connect(NULL);

	if (!ctx)
		goto out;

	if (ubus_lookup_id(ctx, "network.wireless", &id))
		goto out;

	if (ubus_invoke(ctx, id, "status", b.head, iwinfo_ubus_query_cb, &st, 250))
		goto out;

	rv = 0;

out:
	if (ctx)
		ubus_free(ctx);

	blob_buf_free(&b);

	return rv;
}
