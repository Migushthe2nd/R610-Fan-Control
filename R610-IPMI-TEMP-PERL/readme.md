# Fan speed controller for dell R610 etc
_Author: spacelama_  

Dells don't like having third party cards installed, and ramp up the
fan speed to jetliner taking off. But you can override this.

This speed controller uses ipmi raw commands that seem to be similar
across a wide range of dell server generations (google searches for
`ipmitool raw 0x30 0x30 0x01 0x00` show it works for R710, R610, R730, T130,
and I run this on my R520

This script monitoring the ambient air temperature (you will likely
need to modify the $ipmi_inlet_sensorname variable to find the correct
sensor), the hdd temperatures, the core and socket temperatures
(weighted so one core shooting up if all the others are still cold -
let the heatsink do its job).

It uses setpoints and temperature ranges you can tune to your heart's
content. I use it to keep the fans low but increasing to a soft
volume up to 40 degrees, ramp it up quickly to 50degrees, then very
quickly towards full speed much beyond that. It also has an ambient
air temperature threshold of 32degrees where it gives up and delegates
control back to the firmware. Don't run your bedroom IT closet at 32
degrees yeah?

It's got a signal handler so it defaults to default behaviour when
killed by SIGINT/SIGTERM.

I run it on my proxmox hypervisor directly, hence not needing any ipmi
passwords. I will start and stop it through proxmox's systemd system
once I have it firmly debugged.

I wrote it the night before Australia's hottest December day on record
(hey we like our coal fondling prime-ministers). It seems to be
coping so far now that it has reached that predicted peak (I don't
believe it's only 26 in my un-air conditioned study).

All of this was inspired by [this Reddit post](https://www.reddit.com/r/homelab/comments/72qust/r510_noise/dnkofsv/) by /u/whitekidney
