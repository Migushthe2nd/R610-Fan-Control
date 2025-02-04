#!/usr/bin/perl

use strict;
use warnings;
use List::MoreUtils qw( apply );
use File::Temp qw(tempfile);

my $static_speed_low=0x0a;
my $static_speed_high=0x20;   # this is the speed value at 100% demand
                              # ie what we consider the point we don't
                              # really want to get hotter but still
                              # tolerate
my $ipmi_inlet_sensorname="0Eh"; # there are multiple "Ambient Temp" sensors, so use its ID
my $ipmi_remote="-I lanplus -H <ip> -U <user> -P <password>";

my $default_threshold=32;  # the ambient temperature we use above
                           # which we default back to letting the drac
                           # control the fans
my $base_temp     = 32;    # no fans when below this temp
my $desired_temp1 = 42;    # aim to keep the temperature below this
my $desired_temp2 = 48;    # really ramp up fans above this
my $desired_temp3 = 58;    # really ramp up fans above this
my $demand1       = 5;     # prescaled demand at temp1
my $demand2       = 40;    # prescaled demand at temp2
my $demand3       = 200;   # prescaled demand at temp3

my @ambient_ipmitemps=();
my @coretemps=();
my @cputemps=();

my $current_mode;
my $lastfan;

# returns undef if there are no inputs, and ignores inputs that are
# undef
sub average {
  my (@v) = (@_);

  my $div = 0;
  my $tot = 0;
  foreach my $v (@v) {
    if (defined $v) {
      $tot += $v;
      $div++;
    }
  }
  my $avg=undef;
  if ($div > 0) {
    $avg = sprintf "%.2f", $tot/$div;
  }
  return $avg;
}

# returns undef if there are no inputs, and ignores inputs that are
# undef
sub max {
  my (@v) = (@_);
  my $max=undef;
  foreach my $v (@v) {
    if (defined $v) {
      if (!defined $max or $v > $max) {
        $max = $v;
      }
    }
  }
  return $max;
}

sub set_fans_default {
  if (!defined $current_mode or $current_mode ne "default") {
    $current_mode="default";
    $lastfan=undef;
    print "--> enable dynamic fan control\n";
    foreach my $attempt (1..10) {
      system("ipmitool $ipmi_remote raw 0x30 0x30 0x01 0x01") == 0 and return 1;
      sleep 1;
      print "  Retrying dynamic control $attempt\n";
    }
    print "Retries of dynamic control all failed\n";
    return 0;
  }
  return 1;
}

sub set_fans_servo {
  my ($ambient_temp, $_cputemps, $_coretemps) = (@_);
  my (@cputemps)  = @$_cputemps;
  my (@coretemps) = @$_coretemps;

  my $weighted_temp = average(average(@cputemps), average(@coretemps));

  if (!defined $weighted_temp or $weighted_temp == 0) {
    print "Error reading all temperatures! Fallback to idrac control\n";
    set_fans_default();
    return;
  }
  print "weighted_temp = $weighted_temp ; ambient_temp $ambient_temp\n";

  if (!defined $current_mode or $current_mode ne "set") {
    $current_mode="set";
    print "--> disable dynamic fan control\n";
    system("ipmitool $ipmi_remote raw 0x30 0x30 0x01 0x00") == 0 or return 0;
    # if this fails, want to return telling caller not to think weve
    # made a change
  }

  # FIXME: probably want to take into account ambient temperature - if
  # the difference between weighted_temp and ambient_temp is small
  # because ambient_temp is large, then less need to run the fans
  # because there's still low power demands
  my $demand = 0; # want demand to be a reading from 0-100% of
                  # $static_speed_low - $static_speed_high
  if ($weighted_temp > $base_temp and
      $weighted_temp < $desired_temp1) {
    # slope m = (y2-y1)/(x2-x1)
    # y - y1 = (x-x1)(y2-y1)/(x2-x1)
    # y1 = 0 ; x1 = base_temp ; y2 = demand1 ; x2 = desired_temp1
    # x = weighted_temp
    $demand = 0 + ($weighted_temp - $base_temp) * ($demand1 - 0)/($desired_temp1 - $base_temp);
  } elsif ($weighted_temp >= $desired_temp2) {
    # y1 = demand1 ; x1 = desired_temp1 ; y2 = demand2 ; x2 = desired_temp2
    $demand = $demand2 + ($weighted_temp - $desired_temp2) * ($demand3 - $demand2)/($desired_temp3 - $desired_temp2);
  } elsif ($weighted_temp >= $desired_temp1) {
    # y1 = demand1 ; x1 = desired_temp1 ; y2 = demand2 ; x2 = desired_temp2
    $demand = $demand1 + ($weighted_temp - $desired_temp1) * ($demand2 - $demand1)/($desired_temp2 - $desired_temp1);
  }
  printf "demand = %0.2f", $demand;
  $demand = int($static_speed_low + $demand/100*($static_speed_high-$static_speed_low));
  if ($demand>255) {
    $demand=255;
  }
  printf " -> %i\n", $demand;
  # ramp down the fans quickly upon lack of demand, don't ramp them up
  # to tiny spikes of 1 fan unit.  FIXME: But should implement long
  # term smoothing of +/- 1 fan unit
  if (!defined $lastfan or $demand < $lastfan or $demand > $lastfan + 1) {
    $lastfan = $demand;
    $demand = sprintf("0x%x", $demand);
#    print "demand = $demand\n";
    print "--> ipmitool (network address) raw 0x30 0x30 0x02 0xff $demand\n";
    system("ipmitool $ipmi_remote raw 0x30 0x30 0x02 0xff $demand") == 0 or return 0;
    # if this fails, want to return telling caller not to think weve
    # made a change
  }
  return 1;
}

my ($tempfh, $tempfilename) = tempfile("fan-speed-control.XXXXX", TMPDIR => 1);

$SIG{TERM} = $SIG{HUP} = $SIG{INT} = sub { my $signame = shift ; $SIG{$signame} = 'DEFAULT' ; print "Resetting fans back to default\n"; set_fans_default ; kill $signame, $$ };
END {
  my $exit = $?;
  unlink $tempfilename;
  print "Resetting fans back to default\n";
  set_fans_default;
  $? = $exit;
}

my $last_reset_ambient_ipmitemps=time;
my $ambient_temp=20;
while () {
  if (!@ambient_ipmitemps) {
    @ambient_ipmitemps=`timeout -k 1 20 ipmitool $ipmi_remote sdr type temperature | grep "$ipmi_inlet_sensorname" | grep [0-9] || echo " | $ambient_temp degrees C"` # ipmitool often fails - just keep using the previous result til it succeeds
  }
  @coretemps=`timeout -k 1 20 sensors | grep [0-9]`;
  @cputemps=grep {/^Package id/} @coretemps;
  @coretemps=grep {/^Core/} @coretemps;

  chomp @cputemps;
  chomp @coretemps;
  chomp @ambient_ipmitemps;

  @cputemps = apply { s/.*:  *([^ ]*).C.*/$1/ } @cputemps;
  @coretemps = apply { s/.*:  *([^ ]*).C.*/$1/ } @coretemps;
  @ambient_ipmitemps = apply { s/.*\| ([^ ]*) degrees C.*/$1/ } @ambient_ipmitemps;

  print "\n";

  print "cputemps=", join (" ; ", @cputemps), "\n";
  print "coretemps=", join (" ; ", @coretemps), "\n";
  print "ambient_ipmitemps=", join (" ; ", @ambient_ipmitemps), "\n";

  $ambient_temp = average(@ambient_ipmitemps);
  # FIXME: hysteresis
  if ($ambient_temp > $default_threshold) {
    print "fallback because of high ambient temperature $ambient_temp > $default_threshold\n";
    if (!set_fans_default()) {
      # return for next loop without resetting timers and delta change if that fails
      next;
    }
  } else {
    if (!set_fans_servo($ambient_temp, \@cputemps, \@coretemps)) {
      # return for next loop without resetting timers and delta change if that fails
      next;
    }
  }

  # every 60 seconds, invalidate the cache of the slowly changing
  # ambient temperatures to allow them to be refreshed
  if (time - $last_reset_ambient_ipmitemps > 60) {
    @ambient_ipmitemps=();
    $current_mode="reset"; # just in case the RAC has rebooted, it
                           # will go back into default control, so
                           # make sure we set it appropriately once
                           # per minute
    $last_reset_ambient_ipmitemps=time;
  }
  sleep 3;
}
