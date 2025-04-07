#!/bin/sh

if [ -f "miyoo355_rootfs_32.img-partaa" ]; then
  cat miyoo355_rootfs_32.img-part* > miyoo355_rootfs_32.img
  rm miyoo355_rootfs_32.img-part*
fi


