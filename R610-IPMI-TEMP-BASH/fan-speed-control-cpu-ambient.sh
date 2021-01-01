#!/bin/bash
# A fan control script designed to work as a TrueNAS init script

# Constants
STATIC_SPEED_LOW="0x0a"
STATIC_SPEED_HIGH="0x20"

DEFAULT_THRESHOLD_AMBIENT=32 # The ambient temperature at which we default back to the iDRAC
DEFAULT_THRESHOLD_CPU=80     # The ambient temperature at which we default back to the iDRAC
RESET_INTERVAL=60            # The time after which the average should be reset

BASE_TEMP=32              # No fans when below this temp
DESIRED_TEMP1=38          # Aim to keep the temperature below this
DESIRED_TEMP2=48          # Ramp up fans above this
DESIRED_TEMP3=58          # Really ramp up fans above this
DEMAND1=5                 # Pre-scaled demand at temp1 in %
DEMAND2=50                # Pre-scaled demand at temp2 in %
DEMAND3=200               # Pre-scaled demand at temp3 in %

IPMI_CONNECTION_STRING="" # This is optional. Only needed if running this remotely. Example: '-I lanplus -H <ip> -U <user> -P <password>'

#########################################################################################################################################

ambient_systemps=()
core_systemps=()

current_mode=""
last_demand=""

# To check if defined use
# [ -z "$arg" ]

# Calculate the average all parameters
# Returns float or ""
# Example:
# echo $(average 21 20) --> 20.5
average() {
    sum=0
    count=0

    for arg in "$@"; do
        if [ -n "$arg" ]; then
            sum=$(echo $sum + "$arg" | bc)
            count=$((count + 1))
        else
            echo ""
            return
        fi
    done

    echo "scale=1; $sum / $count" | bc
}

# Return the max of all parameters
# Returns float or ""
# Example:
# echo $(max 12 25 12.5 20) --> 25
max() {
    max=0

    for arg in "$@"; do
        if [ -n "$arg" ]; then
            if (($(echo "$arg > $max" | bc -l))); then
                max=$arg
            fi
        else
            echo ""
            return
        fi
    done

    echo "$max"
}

# Set the fans to the default mode (give ipmi module back control)
# Example:
# if set_fans_default; then <success>
# Returns 0 if success, 1 if failure
set_fans_default() {
    if [ -z "$current_mode" ] || [[ "$current_mode" != "default" ]]; then
        last_demand=""
        echo -e "--> Enable default fan control" >&2
        for i in {1..10}; do
            if eval "ipmitool $IPMI_CONNECTION_STRING raw 0x30 0x30 0x01 0x01"; then
                current_mode="default"
                return 0
            fi
            sleep 1
            echo -e "Retrying default control $i" >&2
        done
        echo -e "Retries of default control all failed" >&2
        return 1
    fi
    return 0
}

# Set the fans acording to the demand
# Example:
# if set_fans_auto; then <success>
# Returns 0 if success, 1 if failure
set_fans_auto() {
    weighted_temp=$(average "$last_average_cpu_temp")

    # If any of the temps in not defined or the total is 0 set back to default
    if [ -z "$weighted_temp" ] || (($(echo "$weighted_temp <= 0.0" | bc -l))); then
        set_fans_default
        echo -e "Error reading all temperatures! Fallback to default" >&2
        return
    fi
    echo -e "Weighted temp: $weighted_temp" >&2

    # If the mode is not set or not ""First time enable manual mode
    if [ -z "$current_mode" ] || [ "$current_mode" != "auto" ]; then
        echo $current_mode
        if eval "ipmitool $IPMI_CONNECTION_STRING raw 0x30 0x30 0x01 0x00"; then
            current_mode="auto"
            echo -e "--> Disabled default fan control" >&2
        else
            return 1
        fi
    fi

    demand=0
    if (($(echo "$weighted_temp >= $DESIRED_TEMP2" | bc -l))); then
        demand=$(echo "scale=2; $DEMAND2 + ($weighted_temp - $DESIRED_TEMP2) * ($DEMAND3 - $DEMAND2) / ($DESIRED_TEMP3 - $DESIRED_TEMP2)" | bc -l)
    elif (($(echo "$weighted_temp >= $DESIRED_TEMP1" | bc -l))); then
        demand=$(echo "scale=2; $DEMAND1 + ($weighted_temp - $DESIRED_TEMP1) * ($DEMAND2 - $DEMAND1) / ($DESIRED_TEMP2 - $DESIRED_TEMP1)" | bc -l)
    elif (($(echo "$weighted_temp < $DESIRED_TEMP1 && $weighted_temp > $BASE_TEMP" | bc -l))); then
        demand=$(echo "scale=2; ($weighted_temp - $BASE_TEMP) * $DEMAND1 / ($DESIRED_TEMP1 - $BASE_TEMP)" | bc -l)
    fi
    echo -e "Demand: $demand" >&2

    demand=$(echo "result = $((STATIC_SPEED_LOW)) + $demand / 100 * ($((STATIC_SPEED_HIGH)) - $((STATIC_SPEED_LOW))); scale=0; result/1" | bc -l)
    if ((demand > 255)); then
        demand=255
    fi

    if [ -z "$last_demand" ] || (($(echo "$demand < $last_demand || $demand > $last_demand" | bc -l))); then
        last_demand=$demand
        if eval "ipmitool $IPMI_CONNECTION_STRING raw 0x30 0x30 0x02 0xff $(printf "0x%x" $demand)"; then
            echo -e "--> Set new fan speeds to $(printf "0x%x" $demand)\n" >&2
        else
            return 1
        fi
    fi

    return 0
}

# Print reset, set fans back to default and remove traps
cleanup() {
    echo -e "Resetting fans back to default" >&2
    set_fans_default

    trap - SIGINT
    trap - SIGTERM
    trap - SIGHUP
    trap - EXIT
    kill $$
}

# On exit make sure to set fans to the default
trap cleanup SIGINT
trap cleanup SIGTERM
trap cleanup SIGHUP
trap cleanup EXIT

average_ambient_temps=()
last_average_ambient_temp=""
last_average_cpu_temp=""
average_ambient_temp=$last_average_ambient_temp
while true; do
    ########## Get ambient temperatures
    # TODO: this 'if' here, idk
    if [ -z "$last_average_ambient_temp" ]; then
        alt=20
        if [ -n "$last_average_ambient_temp" ]; then
            alt=$last_average_ambient_temp
        fi
        readarray -t tmp_ambient_systemps < <(timeout -k 1 20 ipmitool sdr type temperature | grep "Ambient Temp" | grep 'degrees' || echo " | $alt degrees C") # Use last temperature if it failed to read
    fi
    # Apply regex to ambient temps
    ambient_systemps=()
    for line in "${tmp_ambient_systemps[@]}"; do
        regexp="\|[[:space:]]([^ ]*)[[:space:]]degrees[[:space:]]C.*"
        [[ $line =~ $regexp ]]
        ambient_systemps+=("${BASH_REMATCH[1]}")
    done
    last_average_ambient_temp=$(average "${ambient_systemps[@]}")
    average_ambient_temps+=("$last_average_ambient_temp")
    average_ambient_temp=$(average "${average_ambient_temps[@]}")

    ########## Get cpu temperatures
    readarray -t tmp_core_systemps < <(timeout -k 1 20 sysctl -a | grep 'cpu.[[:digit:]]\+.temperature' || echo " | $last_average_cpu_temp degrees C")
    # Apply regex to cpu temps
    core_systemps=()
    for line in "${tmp_core_systemps[@]}"; do
        regexp=":[[:space:]]([^ ]*).*C.*"
        [[ $line =~ $regexp ]]
        core_systemps+=("${BASH_REMATCH[1]}")
    done
    last_average_cpu_temp=$(average "${core_systemps[@]}")

    ########## Print all temps
    echo -e "                            Now       1m"
    echo -e "Average ambient temp:       $last_average_ambient_temp      $average_ambient_temp"
    echo -e "Average CPU temp:           $last_average_cpu_temp      "

    ########## Set fans
    if (($(echo "$average_ambient_temp > $DEFAULT_THRESHOLD_AMBIENT" | bc -l))); then
        echo -e "Fallback to default because $average_ambient_temp (average ambient) > $DEFAULT_THRESHOLD_AMBIENT (threshold)"
        # Skip the resets if the set failed
        if ! set_fans_default; then
            continue
        fi
    elif (($(echo "$last_average_cpu_temp > $DEFAULT_THRESHOLD_CPU" | bc -l))); then
        echo -e "Fallback to default because $last_average_cpu_temp (last cpu) > $DEFAULT_THRESHOLD_CPU (threshold)"
        # Skip the resets if the set failed
        if ! set_fans_default; then
            continue
        fi
    else
        # Skip the resets if the set failed
        if ! set_fans_auto; then
            continue
        fi
    fi

    ########## Reset cache. Only keep the 20 latest measured ambient temperatures
    if (($(echo "${#average_ambient_temps[@]} > 20" | bc -l))); then
        average_ambient_temps=("${average_ambient_temps[@]:1}")
    fi

    sleep 3
done
