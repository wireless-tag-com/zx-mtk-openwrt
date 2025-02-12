#ZX
## support MT7981/MT7986

## How To Compile
#### ubuntu 18.04
+ prepare dpendency

  ````sh
  sudo apt-get install subversion build-essential \
      libncurses5-dev zlib1g-dev gawk git ccache \
      gettext libssl-dev xsltproc libxml-parser-perl \
      gengetopt
  ````
+ change root dir

  ````
  cd openwrt
  ````

+ get default config for specified board
  * WT7981P(3* GE, NOR +NAND)<br>
  	`make WT7981P_zx`

  * ZX7981PN(1 2.5G + 2 *GE, NOR +NAND)<br>
    `make ZX7981PN_zx`

  * ZX7981PG(3 *GE, NAND)<br>
    `make ZX7981PG_zx`

  * ZX7981PM(1 2.5G + 2 *GE + FAN, NAND)<br>
    `make ZX7981PM_zx`

  * ZX7981EM(5 *GE + 8GB EMMC + NVME SSD)<br>
    `make ZX7981EM_zx`

  * ZX7981EC(5 *GE + 8GB EMMC + NVME SSD)<br>
    `make ZX7981EC_zx`

  * ZX7986P(1 2.5G + 4 *GE + FAN + 128MB NAND)<br>
    `make ZX7986P_zx`

  * ZX7986E(1 2.5G + 4 *GE + FAN + 8GB EMMC)<br>
    `make ZX7986E_zx`

+ build<br>
  `make V=s -j4 || make V=s`

+ upgrade<br>
  1. binary in bin/targets/mediatek/mt7981/$board, name is *-sysupgrade.bin
  2. upgrade through web ui
  3. upgrade through ssh/telnet, use sysupgprade cmd



