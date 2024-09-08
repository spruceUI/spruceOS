#dd if=boot0_spinor.fex of=spi.bin
#dd if=u-boot-spinor.fex of=spi.bin bs=1K seek=24
#dd if=boot.fex of=spi.bin bs=1K seek=512

md5value=
md5wanted=
version=

rm /tmp/fwupdate_progress
rm /tmp/fwupdate_done

mkdir /mnt/SDCARD/.update
cd /mnt/SDCARD/.update
if [ -f /mnt/SDCARD/miyoo282_fw.img.keep ] ; then
    tar xvf /mnt/SDCARD/miyoo282_fw.img.keep
else
    tar xvf /mnt/SDCARD/miyoo282_fw.img
fi
if [ -f /mnt/SDCARD/.update/spi.bin ]
then
sysversion=`cat /usr/miyoo/version`
version=`cat version.txt`
md5wanted=`cat md5sum.txt`
echo "found version:"$version
echo "want md5:"[$md5wanted]
echo "sys version:"$sysversion
# if [ "$version" == "$sysversion" ] ; then
#     echo "same version"
#     cd /mnt/SDCARD/
#     rm .update -rf
#     rm miyoo282_fw.img -rf
#     echo 100 > "/tmp/fwupdate_progress"
#     echo 1 > "/tmp/fwupdate_done"
#     exit 0
# fi

md5value=`md5sum spi.bin`
#todo check bin
echo "found md5:"[$md5value]
if [[ "$md5value" == "$md5wanted" ]]
then
echo "check ok"
else
echo "MD5sum error"
cd /mnt/SDCARD/
rm .update -rf
rm miyoo282_fw.img -rf
echo 1 > "/tmp/fwupdate_error"
echo 1 > "/tmp/fwupdate_done"
exit 0
fi

else
echo "fw error"
cd /mnt/SDCARD/
rm .update -rf
rm miyoo282_fw.img -rf
echo 1 > "/tmp/fwupdate_error"
echo 1 > "/tmp/fwupdate_done"
exit 0
fi


echo "=============== do update =============="

echo 4 > "/tmp/fwupdate_progress"
flash_eraseall /dev/mtd0
echo 10 > "/tmp/fwupdate_progress"

flash_eraseall /dev/mtd1 > /tmp/erase_log.txt
flash_eraseall /dev/mtd2
echo 20 > "/tmp/fwupdate_progress"

flash_eraseall /dev/mtd3 > /tmp/erase_mtd3_log.txt
echo 50 > "/tmp/fwupdate_progress"

dd if=spi.bin of=/dev/mtd0 bs=1k
dd if=spi.bin of=/dev/mtd1 bs=1k skip=640
echo 70 > "/tmp/fwupdate_progress"

dd if=spi.bin of=/dev/mtd3 bs=1k skip=6144
echo 90 > "/tmp/fwupdate_progress"

cd /mnt/SDCARD/
rm .update -rf
rm miyoo282_fw.img -rf
echo 1 > "/tmp/fwupdate_done"

#poweroff
