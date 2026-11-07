#!/bin/sh

case "$1" in
on)
	pp 0x0300B034 0xc0
	;;
off)
	pp 0x0300B034 0xc4
	;;
esac