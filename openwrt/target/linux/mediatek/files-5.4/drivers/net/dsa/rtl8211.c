#include <linux/etherdevice.h>
#include <linux/if_bridge.h>
#include <linux/iopoll.h>
#include <linux/mdio.h>
#include <linux/mfd/syscon.h>
#include <linux/module.h>
#include <linux/netdevice.h>
#include <linux/of_mdio.h>
#include <linux/of_net.h>
#include <linux/of_platform.h>
#include <linux/phylink.h>
#include <linux/regmap.h>
#include <linux/regulator/consumer.h>
#include <linux/reset.h>
#include <linux/gpio/consumer.h>
#include <net/dsa.h>
#include <linux/of_address.h>

#define BIT_0       0x0001
#define BIT_1       0x0002
#define BIT_2       0x0004
#define BIT_3       0x0008
#define BIT_4       0x0010
#define BIT_5       0x0020
#define BIT_6       0x0040
#define BIT_7       0x0080
#define BIT_8       0x0100
#define BIT_9       0x0200
#define BIT_10      0x0400
#define BIT_11      0x0800
#define BIT_12      0x1000
#define BIT_13      0x2000
#define BIT_14      0x4000
#define BIT_15      0x8000

#define MMD_PMAPMD     1
#define MMD_PCS        3
#define MMD_AN         7
#define MMD_VEND1      30   /* Vendor specific 2 */
#define MMD_VEND2      31   /* Vendor specific 2 */

/*mii_mgr_read/mii_mgr_write is the callback API for rtl8367 driver*/
unsigned int mii_mgr_read(struct mii_bus *bus, unsigned int phy_addr,unsigned int phy_register,unsigned int *read_data)
{
    mutex_lock_nested(&bus->mdio_lock, MDIO_MUTEX_NESTED);

    *read_data = bus->read(bus, phy_addr, phy_register);

    mutex_unlock(&bus->mdio_lock);

    return 0;
}

unsigned int mii_mgr_write(struct mii_bus *bus, unsigned int phy_addr,unsigned int phy_register,unsigned int write_data)
{
    mutex_lock_nested(&bus->mdio_lock, MDIO_MUTEX_NESTED);

    bus->write(bus, phy_addr, phy_register, write_data);

    mutex_unlock(&bus->mdio_lock);
    
    return 0;
}

static unsigned int rtl8221_phy_mmd_write(struct mii_bus *bus, unsigned int phy_id,
                     unsigned int mmd_num, unsigned int reg_id, unsigned int reg_val)
{
    if (mmd_num == 31) {
        uint16_t reg;
        uint16_t dat;
        reg = reg_id/16;
        dat = 16 + (reg_id % 16) / 2;
        mii_mgr_write(bus, phy_id, mmd_num, reg);
        mii_mgr_write(bus, phy_id, dat, reg_val);
    } else {
        uint16_t dat = 0x4000 | (mmd_num & 0x1F);
        mii_mgr_write(bus, phy_id, 13, mmd_num);
        mii_mgr_write(bus, phy_id, 14, reg_id);
        mii_mgr_write(bus, phy_id, 13, dat);
        mii_mgr_write(bus, phy_id, 14, reg_val);
    }

    return 0;
}

static unsigned int rtl8221_phy_mmd_read(struct mii_bus *bus, unsigned int phy_id, unsigned int mmd_num, unsigned int reg_id)
{
    unsigned int rdata = 0;
    if (mmd_num == 31) {
        uint16_t reg;
        uint16_t dat;

        reg = reg_id/16;
        dat = 16 + (reg_id % 16) / 2;
        mii_mgr_write(bus, phy_id, mmd_num, reg);
        mii_mgr_read(bus, phy_id, dat, &rdata);
    } else {
        uint16_t dat = 0x4000 | (mmd_num & 0x1F);
        mii_mgr_write(bus, phy_id, 13, mmd_num);
        mii_mgr_write(bus, phy_id, 14, reg_id);
        mii_mgr_write(bus, phy_id, 13, dat);
        mii_mgr_read(bus, phy_id, 14, &rdata);
    }

    return rdata;
}


static void Rtl8226b_serdes_autoNego_set(struct mii_bus *bus, int enable, unsigned int phy_id)
{
    uint16_t phydata = 0;

    rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x7588, 0x0002);

    if (enable)
        phydata = 0x70D0;
    else
        phydata = 0x71D0;

    rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x7589, phydata);
    rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x7587, 0x0003);
    mdelay(50);
}

static void Rtl8226b_serdes_option_set(struct mii_bus *bus, u8 functioninput, unsigned int phy_id)
{
    u16 phydata = 0;
    if ((functioninput >= 0) && (functioninput <= 3))
    {
        phydata = rtl8221_phy_mmd_read(bus, phy_id, MMD_VEND1, 0x75F3);

        phydata &= ~(1 << 0) ;
        rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x75F3, phydata);
        phydata = rtl8221_phy_mmd_read(bus, phy_id, MMD_VEND1, 0x697A);

        phydata &= (~(1 << 0 | 1 << 1 | 1 << 2 |  1 << 3 | 1 << 4 | 1 << 5));
        phydata |= functioninput;

        rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x697A, phydata);

        if ((functioninput == 0) || (functioninput == 2))
        {
            rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x6A04, 0x0503);
            rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x6F10, 0xD455);
            rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x6F11, 0x8020);
        }
        else if ((functioninput == 1) || (functioninput == 3))
        {
            rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x6A04, 0x0503);
            rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x6F10, 0xD433);
            rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND1, 0x6F11, 0x8020);
        }


        // change link state
        phydata = rtl8221_phy_mmd_read(bus, phy_id, MMD_VEND2, 0xA400);
        phydata |= 1 << 14 ;
        rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND2, 0xA400, phydata);
        phydata = rtl8221_phy_mmd_read(bus, phy_id, MMD_VEND2, 0xA400);

        phydata &= ~(1<< 14) ;
        rtl8221_phy_mmd_write(bus, phy_id, MMD_VEND2, 0xA400, phydata);
    }
}

static void Rtl8226b_phy_reset(struct mii_bus *bus, unsigned int phy_id)
{
    uint16_t phydata0 = 0, phydata1 = 0;
    uint16_t waitcount = 0;

    phydata0 = rtl8221_phy_mmd_read(bus, phy_id, MMD_PMAPMD, 0x0);

    phydata1 |= (1 << 15);

    rtl8221_phy_mmd_write(bus, phy_id, MMD_PMAPMD, 0x0, phydata1);

    while(1)
    {
        phydata1 = rtl8221_phy_mmd_read(bus, phy_id, MMD_PMAPMD, 0x0);
        if (!(phydata1 & (1 << 15)))
            break;

        if (++waitcount == 500)
        {
            break;
        }
    }

    rtl8221_phy_mmd_write(bus, phy_id, MMD_PMAPMD, 0x0, phydata0);
}

static void Rtl8226b_set_ipg(struct mii_bus *bus, unsigned int phy_id)
{
    uint16_t phydata0 = 0;

    phydata0 = rtl8221_phy_mmd_read(bus, phy_id, 30, 0x75B5);

    phydata0 &= ~(0xF);
    phydata0 |= 0x8;

    rtl8221_phy_mmd_write(bus, phy_id, 30, 0x75B5, phydata0);
}

void Rtl8226b_PHYmodeEEE_set(struct mii_bus *bus, int hDevice,int on_off)
{
    u16 phydata = 0;
    if(on_off){
        
        phydata = rtl8221_phy_mmd_read(bus, hDevice, MMD_VEND2, 0xA432);

        phydata |= BIT_5;

        rtl8221_phy_mmd_write(bus, hDevice, MMD_VEND2, 0xA432, phydata);
    }
    else{
        phydata = rtl8221_phy_mmd_read(bus, hDevice, MMD_VEND2, 0xA432);
        phydata &= (~BIT_5);

        rtl8221_phy_mmd_write(bus, hDevice, MMD_VEND2, 0xA432, phydata);
    }
    
      phydata = rtl8221_phy_mmd_read(bus, hDevice, MMD_VEND2, 0xA400);

      phydata |= BIT_9;

      rtl8221_phy_mmd_write(bus, hDevice, MMD_VEND2, 0xA400, phydata);
}

static int gsw_phy_link = 0;

static int gsw_link_thread(void *resv)
{
    struct mii_bus *bus = resv;
    for(;;) {      
         uint16_t phydata;
         bool blinkOk = false;

         phydata = rtl8221_phy_mmd_read(bus, 6, MMD_VEND2, 0xA434);
         blinkOk = (phydata & (1 << 2)) ? (true) : (false);
         if (gsw_phy_link != blinkOk) {
              if (blinkOk) {
		     printk("link up RTL8221\n");
              } else {
		      	printk("link down RTL8221\n");
              }
         }

         gsw_phy_link = blinkOk;

         msleep(1500);
         if(kthread_should_stop())
              break;
    }

    return 0;
}

static struct task_struct *gsw_link_task = NULL;

int g_rtl8211_status = 0;

void rtl8221_init(struct mii_bus *bus)
{
    u32 phy_id = 0;
    int phy_reg;
    u16 phydata = 0;

    mutex_lock_nested(&bus->mdio_lock, MDIO_MUTEX_NESTED);
    phy_reg = bus->read(bus, 6, 0x2);
    phy_id = phy_reg << 16;
    phy_reg = bus->read(bus, 6, 0x3);
    phy_id |= phy_reg;
    mutex_unlock(&bus->mdio_lock);

    printk("R6: 0x%x\n", phy_id);
    if (phy_id == 0x1cc849) {
        g_rtl8211_status = 1;
        printk("init RTL8221B ADDR6\n");
        phydata = rtl8221_phy_mmd_read(bus, 6, MMD_VEND2, 0xA430);
        phydata &= (~BIT_13);
        rtl8221_phy_mmd_write(bus, 6, MMD_VEND2, 0xA430, phydata);
        phydata = rtl8221_phy_mmd_read(bus, 6, MMD_VEND2, 0xA430);
        printk("0xA430: 0x%x\n", phydata);
        Rtl8226b_serdes_autoNego_set(bus, 0, 6);
        Rtl8226b_set_ipg(bus, 6);
        Rtl8226b_serdes_option_set(bus, 3, 6);
        Rtl8226b_PHYmodeEEE_set(bus, 6, 0);
        Rtl8226b_phy_reset(bus, 6);
        Rtl8226b_PHYmodeEEE_set(bus, 6, 0);
        rtl8221_phy_mmd_write(bus, 6, MMD_VEND2, 0xD032, 0x20); // led
        rtl8221_phy_mmd_write(bus, 6, MMD_VEND2, 0xD034, 0x7); // led
        if (gsw_link_task == NULL) {
            gsw_link_task = kthread_create(gsw_link_thread, bus, "rtl8211_link");
            if (!IS_ERR(gsw_link_task)) {
                wake_up_process(gsw_link_task);
            }
        }
    }

    mutex_lock_nested(&bus->mdio_lock, MDIO_MUTEX_NESTED);
    phy_reg = bus->read(bus, 5, 0x2);
    phy_id = phy_reg << 16;
    phy_reg = bus->read(bus, 5, 0x3);
    phy_id |= phy_reg;
    mutex_unlock(&bus->mdio_lock);

    printk("R5: 0x%x\n", phy_id);
    if (phy_id == 0x1cc849) {
        g_rtl8211_status = 1;
        printk("init RTL8221B ADDR5\n");
        phydata = rtl8221_phy_mmd_read(bus, 5, MMD_VEND2, 0xA430);
        phydata &= (~BIT_13);
        rtl8221_phy_mmd_write(bus, 5, MMD_VEND2, 0xA430, phydata);
        Rtl8226b_serdes_autoNego_set(bus, 0, 5);
        Rtl8226b_set_ipg(bus, 5);
        Rtl8226b_serdes_option_set(bus, 3, 5);
        Rtl8226b_PHYmodeEEE_set(bus, 5, 0);
        Rtl8226b_phy_reset(bus, 5);
        Rtl8226b_PHYmodeEEE_set(bus, 5, 0);
        rtl8221_phy_mmd_write(bus, 5, MMD_VEND2, 0xD032, 0x20); // led
        rtl8221_phy_mmd_write(bus, 5, MMD_VEND2, 0xD034, 0x7); // led
    }
}
