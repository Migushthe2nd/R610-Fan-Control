# Fan speed controller for Dell PowerEdge R610

_Author: Migush_

This is a port of spacelama's script from Perl to Bash. It works, but the demand feels quite unstable sometimes.

## rc.d boot script

1. `nano /usr/local/etc/rc.d/custom_fan_speeds`
2. Enter the following:

```sh 
#!/bin/sh

. /etc/rc.subr

name=custom_fan_speeds
rcvar=custom_fan_speeds_enable

start_cmd="${name}_start"
stop_cmd="${name}_stop"
stop_postcmd="${name}_cleanup"
status_cmd="${name}_status"

pidfile=/var/run/custom_fan_speeds.pid

load_rc_config $name
: ${custom_fan_speeds_enable:=no}
: ${custom_fan_speeds_msg="Nothing started."}

custom_fan_speeds_start()
{
   echo "Starting Dell Poweredge R610 Custom Fan Speeds"
   touch ${pidfile}
   /usr/sbin/daemon -cf -p ${pidfile} <path to script>
}

custom_fan_speeds_stop()
{
   echo "Stopping Dell Poweredge R610 Custom Fan Speeds"
   pkill $name
}

custom_fan_speeds_cleanup() {
   [ -f ${pidfile} ] && rm ${pidfile}
}

custom_fan_speeds_status() {
   if [ -e $pidfile ]; then
      echo script is running, pid=`cat $pidfile`
   else
      echo script is NOT running
      exit 1
   fi
}


run_rc_command "$1"
```

3. Replace `<path to script>` with the correct path.
4. Save
5. Make it executable `chmod +x /usr/local/etc/rc.d/custom_fan_speeds`
    1. Also make sure the script itself is executable.
6. Enable the service: `echo custom_fan_speeds_enable="YES" >> /etc/rc.conf`
7. Reboot or start the service manually: `service custom_fan_speeds start`

---

**Disclaimer**  
TLDR; I take _NO_ responsibility if you mess up anything.