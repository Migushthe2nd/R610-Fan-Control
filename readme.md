# INFO

This is a fork from spacelama's fan control script that was improved for the IPMI controller in the Dell PowerEdge R610. Feel free to modify and improve. I also ported it to bash to use with TrueNAS as an init script. It's not the best fan controller, but it'll do.

Current changes:

- sensor name
- high fan speed value

---

Here is a table with the HEX values and the average fan speeds for the R610 (this is a shitty test but hey, it's _something_):

| HEX | Decimal | FANS A (RPM, avg) | FANS B (RPM, avg) |
|-----|---------|-------------------|-------------------|
| 0 | 0 | 0 | 0 |
| 9 | 9 | 0 | 0 |
| a | 10 | 1200 | 840 |
| 10 | 16 | 2760 | 1920 |
| 17 | 23 | 4080 | 2880 |
| 20 | 32 | 5760 | 4080 |
| 27 | 39 | 7080 | 4920 |
| 30 | 48 | 8880 | 6120 |
| 37 | 55 | 10200 | 7080 |
| 40 | 64 | 10920 | 7680 |
| 47 | 71 | 12840 | 8880 |

![Fan Speeds RPM Graph](ipmi_rpm.png)

---

# Howto: Manually setting the fan speed of the Dell R610

1. Enable IPMI in iDrac
2. Install ipmitool on linux, win or mac os
3. Run the following command to issue IPMI commands:
   `ipmitool -I lanplus -H <iDracip> -U root -P <rootpw> <command>`

**Enable manual/static fan speed:**  
`raw 0x30 0x30 0x01 0x00`

**Set fan speed:**  
_A: 2760 RPM; B: 1920 RPM_: `raw 0x30 0x30 0x02 0xff 0x10`  
_Note: The RPM may differ from model to model_

**Disable / Return to automatic fan control:**  
`raw 0x30 0x30 0x01 0x01`

**Other: List all output from IPMI**  
`sdr elist all`

**Example of a command:**  
`ipmitool -I lanplus -H 192.168.0.120 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x10`

**Example of a command in the TrueNAS shell:**  
`ipmitool raw 0x30 0x30 0x02 0xff 0x10`

---

**Disclaimer**  
TLDR; I take _NO_ responsibility if you mess up anything.

---

These files are provided "as is", and I take no responsibility if they break something on your end.
