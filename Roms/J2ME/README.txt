J2ME (Java ME) phone games run on the FreeJ2ME-Plus core, which is a wrapper
around a real Java runtime. Neither one ships with spruce - together they are
about 37MB to download - so both come from the Game Nursery.

To install:

  1. Open Game Nursery from the Apps menu. It needs WiFi.
  2. Pick J2ME, then FreeJ2ME.
  3. Let it download and install.

That puts the core and the Java runtime on the card, along with three free
games to start with: Bomber 2, jtris and Crossword Solver.

Until the runtime is installed, J2ME does not appear in the game list at all.
That is deliberate, not a fault.

Once it is installed, copy .jar or .kjx midlets into this folder.

These games were written for dozens of different phone screens. If a game is
cut off, squashed, or tiny, set Core Options > Phone Resolution to the size the
game expects - 176x208 and 240x320 cover most of them - and restart the game.
Core Options > Phone Key Layout does the same job for games that ignore the
controls: Nokia and Siemens layouts are the common ones.

64-bit devices only. The Miyoo Mini and the A30 do not have the memory to run a
JVM, so J2ME is not offered on them.
