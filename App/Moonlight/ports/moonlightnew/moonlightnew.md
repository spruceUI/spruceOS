## Notes

This port was made possible by: 
- The developers of [Moonlight Embedded](https://github.com/moonlight-stream/moonlight-embedded), huge thanks goes out for making moonlight work on embedded systems like our handhelds.
- The developers of [Love2D](https://github.com/love2d/love) for making this launcher possible.
- Kloptops and Cebion for testing alpha builds and giving great insights.
- JanTrueno for making this port possible, creating the launcher and putting in the effort into fixing this for muOS and Knulli as well. If you would like to support the work, you can buy me a coffee [here](https://ko-fi.com/jantrueno) :)

## Controls

| Button | Action |
|--|--| 
|A |Select|
|B|Back/Skip splash|
|D-pad|Navigate/Scroll|
|L1/R1|Exit Launcher|
|Start+Select|Exit Moonlight|


## Compile

```shell
**Libcurl 8.7.1:**
- sudo apt install build-essential libssl-dev libnghttp2-dev libz-dev
-  wget https://curl.se/download/curl-8.7.1.tar.xz
-  tar -xf curl-8.7.1.tar.xz
- cd curl-8.7.1
- ./configure --with-ssl
-  make
-  make install

**OpenSSL 3.3.1:**
- download OpenSSL-3.3.1 manually
- cd openssl-3.3.1
- chmod +x config Configure
- ./config
- make
- make install

**Moonlight:**
- sudo apt install libexpat1-dev libcurl4-openssl-dev libevdev-dev libssl-dev libopus-dev libasound2-dev libudev-dev libavahi-client-dev libcurl4-openssl-dev libevdev-dev libexpat1-dev libpulse-dev uuid-dev
- git clone https://github.com/moonlight-stream/moonlight-embedded.git
- cd moonlight-embedded
- git checkout 274d3db34da764344a7a402ee74e6080350ac0cd
- mkdir build
- cd build
- cmake .. (Disable X11)
- make -j8
```
