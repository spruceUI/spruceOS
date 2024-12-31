#!/bin/sh


echo 3 > /proc/sys/kernel/printk

chmod a+x /usr/bin/notify

CUSTOMER1_DIR=/media/sdcard0/miyoo355/
CUSTOMER2_DIR=/media/sdcard1/miyoo355/
export CUSTOMER_DIR=${CUSTOMER1_DIR}
if [ -d ${CUSTOMER2_DIR} ]   ; then
  export CUSTOMER_DIR=${CUSTOMER2_DIR}
fi

EE1_DIR=/media/sdcard0/emulationstation
EE2_DIR=/media/sdcard1/emulationstation
export EE_DIR=${EE1_DIR}
if [ -d ${EE2_DIR} ]   ; then
  export EE_DIR=${EE2_DIR}
fi
echo CUSTOMER_DIR is $CUSTOMER_DIR, EE_DIR is $EE_DIR> /tmp/runee.log

killprocess(){
   pid=`ps | grep $1 | grep -v grep | cut -d' ' -f3`
   kill -9 $pid
}


runifnecessary(){
    cnt=0
    #a=`ps | grep $1 | grep -v grep`
    a=`pgrep $1`
    while [ "$a" == "" ] && [ $cnt -lt 8 ] ; do 
	   echo try to run $2 `cat /proc/uptime`
	   $2 $3 &
           sleep 0.5
	   cnt=`expr $cnt + 1`
           a=`pgrep $1`
    done
}

export LD_LIBRARY_PATH=/usr/miyoo/lib


#motor
echo 20 > /sys/class/gpio/export
echo -n out > /sys/class/gpio/gpio20/direction
echo -n 0 > /sys/class/gpio/gpio20/value
# sleep 0.05
# echo -n 1 > /sys/class/gpio/gpio20/value
# sleep 0.05
# echo -n 0 > /sys/class/gpio/gpio20/value

#wait for sdcard mounted
mounted=`cat /proc/mounts | grep sdcard`
cnt=0
/usr/bin/fbdisplay /usr/miyoo/bin/skin/icon-wait-tf-card.png &
while [ "$mounted" == "" ] && [ $cnt -lt 8 ] ; do
   echo "wait for sdcard $cnt $mounted"
   sleep 0.5
   cnt=`expr $cnt + 1`
   mounted=`cat /proc/mounts | grep SDCARD`
done

touch /tmp/fbdisplay_exit

echo "before wifi module " `cat /proc/uptime`
#insmod /system/lib/modules/RTL8189FU.ko
echo "after wifi module " `cat /proc/uptime`

#joypad
echo -1 > /sys/class/miyooio_chr_dev/joy_type
#keyboard
#echo 0 > /sys/class/miyooio_chr_dev/joy_type

sleep 0.1
hdmipugin=`cat /sys/class/drm/card0-HDMI-A-1/status`
if [ "$hdmipugin" == "connected" ] ; then
    /usr/bin/fbdisplay /usr/miyoo/bin/skin_1080p/app_loading_bg.png &
else
    /usr/bin/fbdisplay /usr/miyoo/bin/skin/app_loading_bg.png &
fi

mkdir -p /tmp/miyoo_inputd

val=`/usr/miyoo/bin/jsonval turboA`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_a
else
    unlink /tmp/miyoo_inputd/turbo_a
fi
val=`/usr/miyoo/bin/jsonval turboB`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_b
else
    unlink /tmp/miyoo_inputd/turbo_b
fi
val=`/usr/miyoo/bin/jsonval turboX`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_x
else
    unlink /tmp/miyoo_inputd/turbo_x
fi
val=`/usr/miyoo/bin/jsonval turboY`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_y
else
    unlink /tmp/miyoo_inputd/turbo_y
fi
val=`/usr/miyoo/bin/jsonval turboL`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_l
else
    unlink /tmp/miyoo_inputd/turbo_l
fi
val=`/usr/miyoo/bin/jsonval turboR`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_r
else
    unlink /tmp/miyoo_inputd/turbo_r
fi
val=`/usr/miyoo/bin/jsonval turboL2`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_l2
else
    unlink /tmp/miyoo_inputd/turbo_l2
fi
val=`/usr/miyoo/bin/jsonval turboR2`
if [ "$val" == "1" ] ; then
    touch /tmp/miyoo_inputd/turbo_r2
else
    unlink /tmp/miyoo_inputd/turbo_r2
fi

factory_test_mode=0
if [ -f /media/sdcard0/factory_test_mode ] || [ -f /media/sdcard0/pcba_test_mode ] ; then
    factory_test_mode=1
elif [ -f /media/sdcard1/factory_test_mode ] || [ -f /media/sdcard1/pcba_test_mode ] ; then
    factory_test_mode=1
fi

miyoo_fw_update=0
miyoo_fw_dir=/media/sdcard0
if [ -f /media/sdcard0/miyoo355_fw.img ] ; then
    miyoo_fw_update=1
    miyoo_fw_dir=/media/sdcard0
elif [ -f /media/sdcard1/miyoo355_fw.img ] ; then
    miyoo_fw_update=1
    miyoo_fw_dir=/media/sdcard1
fi

if [ ${miyoo_fw_update} -eq 1 ] ; then
echo "============== MIYOO FW update ==============="
export LD_LIBRARY_PATH=${CUSTOMER_DIR}/lib 
cd $miyoo_fw_dir
/usr/miyoo/apps/fw_update/miyoo_fw_update
fi

while [ 1 ]; do
  runee=`/usr/miyoo/bin/jsonval runee`
  if [ "$runee" == "1" ] && [ -f ${EE_DIR}/emulationstation ] && [ -f ${EE_DIR}/emulationstation.sh ] ; then
      cd ${EE_DIR}
      ./emulationstation.sh
      runee=`/usr/miyoo/bin/jsonval runee`
      echo runee $runee  >> /tmp/runee.log
  else      
      #exit 0
      #echo 600000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

      svrrunned=0

      SDRUNNED=0
      if [ -d ${CUSTOMER_DIR} ]   ; then
        export LD_LIBRARY_PATH=${CUSTOMER_DIR}/lib 
        
        echo run sdcard app LD_LIBRARY_PATH is ${LD_LIBRARY_PATH} `cat /proc/uptime`
        runifnecessary "keymon" ${CUSTOMER_DIR}/app/keymon 
        runifnecessary "miyoo_inputd" ${CUSTOMER_DIR}/app/miyoo_inputd   

        echo run sdcard app `cat /proc/uptime`
        cd ${CUSTOMER_DIR}/app/
        if [ ${factory_test_mode} -eq 1 ] ; then
            ${CUSTOMER_DIR}/app/factory_test
        else
            ${CUSTOMER_DIR}/app/MainUI
        fi

        if [ $? -eq 0 ] ; then
            SDRUNNED=1
        else
            SDRUNNED=0
        fi
      fi

      if [ ${SDRUNNED} -eq 0 ] ; then
        export LD_LIBRARY_PATH=/usr/miyoo/lib
        echo run app LD_LIBRARY_PATH is ${LD_LIBRARY_PATH} `cat /proc/uptime`   
        runifnecessary "keymon" /usr/miyoo/bin/keymon
        runifnecessary "miyoo_inputd" /usr/miyoo/bin/miyoo_inputd

        echo run internal app `cat /proc/uptime`
        cd /usr/miyoo/bin/
        if [ ${factory_test_mode} -eq 1 ] ; then
            /usr/miyoo/bin/factory_test
        else
            /usr/miyoo/bin/MainUI
        fi

      fi #[ ${SDRUNNED} -eq 0 ] 


      if [ -f /tmp/.cmdenc ] ; then                                                                                   
          /root/gameloader                                                                                             
      elif [ -f /tmp/cmd_to_run.sh ] ; then
         touch /tmp/miyoo_inputd/enable_turbo_input
         chmod a+x /tmp/cmd_to_run.sh
         /tmp/cmd_to_run.sh                                                                                           
         rm /tmp/cmd_to_run.sh
         rm /tmp/miyoo_inputd/enable_turbo_input
	     echo game finished
      fi

      #turn off motor in case app crash
  fi

done

