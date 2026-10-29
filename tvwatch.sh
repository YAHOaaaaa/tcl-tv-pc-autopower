#!/system/bin/sh
# Runs on the TV (started by tv_on.ps1 over ADB).
# Puts the TV to sleep when the PC's HDMI input loses signal for DELAY seconds.
# Only acts when the signal was present before (state "ok") and that HDMI input is the current one,
# so turning the TV on by remote while the PC is off, or watching another input, is left alone.
#   usage: sh tvwatch.sh [HDMI_HARDWARE_ID=15] [DELAY_SECONDS=20]
HW=${1:-15}
DELAY=${2:-20}
DIR=/data/local/tmp
STATE=$DIR/tvwatch.state
echo $$ > $DIR/tvwatch.pid

# Initial state from the most recent signal event already in the log
last=$(logcat -d -s VCodecHdmi:D TvPassThroughSession:I | grep -E "SignalLock mHardwareDeviceId=$HW|signalChangeHandler\[1197\]" | tail -1)
case "$last" in
  *SignalLock*|*"0(Stable)"*) echo ok > $STATE ;;
  *) echo woke > $STATE ;;
esac

# Sleep watcher: when the TV goes to standby, forget the old "signal present" state
# (writing on the way down avoids racing the SignalLock event that follows a wake-up),
# and record which input was on screen so tv_on.ps1 only wakes the TV back onto the PC.
# The TV flips the current input id to the launcher's id as it falls asleep,
# so the sample from one poll earlier is the one written.
(
  prev=Awake
  in_cur=; in_prev=
  while true; do
    now=$(dumpsys power | grep -o 'mWakefulness=[A-Za-z]*' | cut -d= -f2)
    if [ "$now" = Awake ]; then
      in_prev=$in_cur
      in_cur=$(settings get secure tcl_sys_tv_input_current_device_id)
    elif [ "$prev" = Awake ]; then
      echo woke > $STATE
      echo "${in_prev:-$in_cur}" > $DIR/tvwatch.input
    fi
    prev=$now
    sleep 2
  done
) &

logcat -T 1 -s VCodecHdmi:D TvPassThroughSession:I | while read -r line; do
  case "$line" in
    *"SignalLock mHardwareDeviceId=$HW"*)
      echo ok > $STATE ;;
    *"signalChangeHandler[1197]"*"0(Stable)"*)
      # VCodecHdmi reports every HDMI port: only count it when the PC's port is the current input
      if [ "$(settings get secure tcl_sys_tv_input_current_device_id)" = "$HW" ]; then echo ok > $STATE; else echo other > $STATE; fi ;;
    *"signalChangeHandler[1197]"*"1(UnStable)"*)
      case "$(cat $STATE)" in ok|nosig*) echo unstable > $STATE ;; esac ;;
    *"signalChangeHandler[1197]"*"2(NoSignal)"*)
      prev=$(cat $STATE)
      if [ "$prev" = ok ] || [ "$prev" = unstable ]; then
        t=$(date +%s); echo "nosig $t" > $STATE
        (
          sleep $DELAY
          if [ "$(cat $STATE)" = "nosig $t" ] \
             && [ "$(settings get secure tcl_sys_tv_input_current_device_id)" = "$HW" ] \
             && dumpsys power | grep -q 'mWakefulness=Awake'; then
            echo "$(date) no PC signal for ${DELAY}s -> sleep" >> $DIR/tvwatch.log
            echo slept > $STATE
            input keyevent KEYCODE_SLEEP
          fi
        ) &
      fi ;;
  esac
done
